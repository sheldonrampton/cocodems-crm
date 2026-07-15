#!/usr/bin/env bash
# Refresh the local Docker database from a staging backup (S3 or local file).
#
# Run on your laptop with the local stack running:
#
#   bash scripts/sync-staging-to-local.sh
#   bash scripts/sync-staging-to-local.sh --from s3://bucket/cocodems/db/daily/cocodems-….sql.gz
#   bash scripts/sync-staging-to-local.sh --from backups/db/cocodems-….sql.gz
#
# Requires:
#   - Local Docker stack (docker-compose.local.yml)
#   - .env with CIVICRM_UF_BASEURL=http://localhost:8080 (no SITE_DOMAIN)
#   - BACKUP_S3_BUCKET in .env (unless --from is a local file)
#   - AWS CLI credentials that can read the backup bucket
#
# This replaces the local database. Uploads / installed extensions on staging
# are not copied — only the DB. Re-install third-party plugins/extensions
# locally as needed for experimentation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
FROM_PATH=""
FORCE=0
TMP_BACKUP=""

cleanup() {
	if [[ -n "${TMP_BACKUP}" && -f "${TMP_BACKUP}" ]]; then
		rm -f "${TMP_BACKUP}"
	fi
}
trap cleanup EXIT

usage() {
	cat <<'EOF'
Usage: sync-staging-to-local.sh [--from <path|s3://…>] [--yes]

  --from PATH   Restore from this dump (local .sql.gz or s3:// URI).
                Default: latest object under s3://BACKUP_S3_BUCKET/cocodems/db/daily/
  --yes, -y     Skip confirmation prompt
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--from)
			FROM_PATH="$2"
			shift 2
			;;
		--yes | -y)
			FORCE=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 1
			;;
	esac
done

if [[ ! -f "${ENV_FILE}" ]]; then
	echo "Missing ${ENV_FILE}" >&2
	echo "Copy .env.example to .env for local development first." >&2
	exit 1
fi

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true
}

if grep -q '^SITE_DOMAIN=' "${ENV_FILE}" 2>/dev/null; then
	echo "This script is for the local laptop only." >&2
	echo "${ENV_FILE} has SITE_DOMAIN set (staging-style). Use a local .env from .env.example." >&2
	exit 1
fi

BASE_URL="$(read_env CIVICRM_UF_BASEURL)"
BACKUP_S3_BUCKET="$(read_env BACKUP_S3_BUCKET)"
MYSQL_DATABASE="$(read_env MYSQL_DATABASE)"
MYSQL_DATABASE="${MYSQL_DATABASE:-cocodems}"

if [[ -z "${BASE_URL}" ]]; then
	echo "Set CIVICRM_UF_BASEURL in ${ENV_FILE} (e.g. http://localhost:8080)" >&2
	exit 1
fi

COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.local.yml"

if ! ${COMPOSE} exec -T mariadb true 2>/dev/null; then
	echo "Local MariaDB is not running. Start the stack:" >&2
	echo "  docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml up -d" >&2
	exit 1
fi

if [[ -z "${FROM_PATH}" ]]; then
	if [[ -z "${BACKUP_S3_BUCKET}" ]]; then
		echo "Set BACKUP_S3_BUCKET in ${ENV_FILE}, or pass --from <path|s3://…>." >&2
		exit 1
	fi
	if ! command -v aws >/dev/null 2>&1; then
		echo "aws CLI is required to download staging backups (or pass --from with a local file)." >&2
		exit 1
	fi

	echo "==> Finding latest daily backup in s3://${BACKUP_S3_BUCKET}/cocodems/db/daily/..."
	# aws s3 ls returns lines like: 2026-07-11 03:15:02   901234 filename.sql.gz
	LATEST_KEY="$(
		aws s3 ls "s3://${BACKUP_S3_BUCKET}/cocodems/db/daily/" \
			| awk '{print $4}' \
			| grep -E '\.sql\.gz$' \
			| sort \
			| tail -1
	)"
	if [[ -z "${LATEST_KEY}" ]]; then
		echo "No .sql.gz backups found under s3://${BACKUP_S3_BUCKET}/cocodems/db/daily/" >&2
		exit 1
	fi
	FROM_PATH="s3://${BACKUP_S3_BUCKET}/cocodems/db/daily/${LATEST_KEY}"
	echo "Using ${FROM_PATH}"
fi

if [[ ${FORCE} -ne 1 ]]; then
	echo "This will REPLACE the local \"${MYSQL_DATABASE}\" database with:"
	echo "  ${FROM_PATH}"
	echo "WordPress/CiviCRM URLs will be rewritten to ${BASE_URL}."
	read -r -p "Type SYNC to continue: " confirm
	if [[ "${confirm}" != "SYNC" ]]; then
		echo "Aborted."
		exit 1
	fi
fi

if [[ "${FROM_PATH}" != s3://* && ! -f "${FROM_PATH}" ]]; then
	echo "Backup not found: ${FROM_PATH}" >&2
	exit 1
fi

bash "${REPO_ROOT}/scripts/restore-db.sh" "${FROM_PATH}" --yes

echo "==> Aligning WordPress/CiviCRM DB credentials with local .env..."
# wp-config.php and civicrm.settings.php live in Docker volumes and may still have
# passwords from the first install. MariaDB uses the current MYSQL_* from .env.
${COMPOSE} exec -T php php <<'PHP'
<?php
$user = getenv('WORDPRESS_DB_USER') ?: getenv('CIVICRM_DB_USER');
$pass = getenv('WORDPRESS_DB_PASSWORD') ?: getenv('CIVICRM_DB_PASSWORD');
$host = getenv('WORDPRESS_DB_HOST') ?: 'mariadb';
$port = getenv('WORDPRESS_DB_PORT') ?: '3306';
$name = getenv('WORDPRESS_DB_NAME') ?: getenv('CIVICRM_DB_NAME');
if (!$user || $pass === false || $pass === null || $pass === '' || !$name) {
	fwrite(STDERR, "Missing WORDPRESS_DB_* / CIVICRM_DB_* environment in php container.\n");
	exit(1);
}

$wp = '/var/www/private/wp-config.php';
$civi = '/var/www/html/wp-content/uploads/civicrm/civicrm.settings.php';

$wpSrc = file_get_contents($wp);
$wpSrc = preg_replace(
	"/define\(\s*'DB_NAME'\s*,\s*'[^']*'\s*\)/",
	"define( 'DB_NAME', '" . addcslashes($name, "\\'") . "' )",
	$wpSrc,
	1
);
$wpSrc = preg_replace(
	"/define\(\s*'DB_USER'\s*,\s*'[^']*'\s*\)/",
	"define( 'DB_USER', '" . addcslashes($user, "\\'") . "' )",
	$wpSrc,
	1
);
$wpSrc = preg_replace(
	"/define\(\s*'DB_PASSWORD'\s*,\s*'[^']*'\s*\)/",
	"define( 'DB_PASSWORD', '" . addcslashes($pass, "\\'") . "' )",
	$wpSrc,
	1
);
$wpSrc = preg_replace(
	"/define\(\s*'DB_HOST'\s*,\s*'[^']*'\s*\)/",
	"define( 'DB_HOST', '" . addcslashes($host, "\\'") . "' )",
	$wpSrc,
	1
);
file_put_contents($wp, $wpSrc);

$dsn = sprintf(
	'mysql://%s:%s@%s:%s/%s?new_link=true',
	rawurlencode($user),
	rawurlencode($pass),
	$host,
	$port,
	rawurlencode($name)
);
if (is_file($civi)) {
	$civiSrc = file_get_contents($civi);
	$civiSrc = preg_replace(
		"/define\(\s*'CIVICRM_UF_DSN'\s*,\s*'[^']*'\s*\)/",
		"define('CIVICRM_UF_DSN', '" . addcslashes($dsn, "\\'") . "')",
		$civiSrc
	);
	$civiSrc = preg_replace(
		"/define\(\s*'CIVICRM_DSN'\s*,\s*'[^']*'\s*\)/",
		"define('CIVICRM_DSN', '" . addcslashes($dsn, "\\'") . "')",
		$civiSrc
	);
	file_put_contents($civi, $civiSrc);
}

$mysqli = new mysqli($host, $user, $pass, $name, (int) $port);
if ($mysqli->connect_error) {
	fwrite(STDERR, 'DB credentials updated in config files, but connect failed: ' . $mysqli->connect_error . "\n");
	exit(1);
}
echo "Local DB credentials applied and verified.\n";
PHP

echo "==> Pointing WordPress at ${BASE_URL}..."
${COMPOSE} exec -T php wp option update home "${BASE_URL}" --allow-root --path=/var/www/html
${COMPOSE} exec -T php wp option update siteurl "${BASE_URL}" --allow-root --path=/var/www/html

ADMIN_USER="$(read_env CIVICRM_ADMIN_USER)"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="$(read_env CIVICRM_ADMIN_PASS)"
if [[ -n "${ADMIN_PASS}" ]]; then
	echo "==> Resetting WordPress user ${ADMIN_USER} password from local .env..."
	${COMPOSE} exec -T php wp user update "${ADMIN_USER}" --user_pass="${ADMIN_PASS}" --allow-root --path=/var/www/html
fi

echo "==> Rewriting CiviCRM URLs for local..."
bash "${REPO_ROOT}/scripts/fix-civicrm-urls.sh"

echo ""
echo "Staging → local sync complete."
echo "  Site:  ${BASE_URL}"
echo "  Login: ${BASE_URL%/}/wp-login.php"
echo "  User:  ${ADMIN_USER} (password from CIVICRM_ADMIN_PASS in .env)"
echo ""
echo "Database only — staging uploads/plugins/extensions in volumes were not copied."
echo "Install CiviCRM extensions and WordPress plugins locally for experimentation."
