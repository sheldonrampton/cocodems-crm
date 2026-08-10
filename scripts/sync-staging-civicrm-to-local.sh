#!/usr/bin/env bash
# Replace local CiviCRM database tables from a staging backup while keeping
# WordPress tables and volume files (plugins, theme, uploads) unchanged.
#
# Run on your laptop with the local stack running:
#
#   bash scripts/sync-staging-civicrm-to-local.sh
#   bash scripts/sync-staging-civicrm-to-local.sh --from s3://bucket/cocodems/db/daily/cocodems-….sql.gz
#   bash scripts/sync-staging-civicrm-to-local.sh --from backups/db/cocodems-….sql.gz --yes
#
# Requires:
#   - Local Docker stack (docker-compose.local.yml)
#   - .env with CIVICRM_UF_BASEURL=http://localhost:PORT (no SITE_DOMAIN)
#   - BACKUP_S3_BUCKET in .env (unless --from is a local file)
#   - AWS CLI credentials that can read the backup bucket
#
# What is replaced:
#   Tables named civicrm_*, log_civicrm_*, and snap_civicrm_* (contacts,
#   contributions, events, custom groups/fields, CiviCRM settings, etc.)
#
# What is kept:
#   All wp_* tables (posts, options, users, plugins metadata, etc.)
#   Files on disk (plugins, theme, CiviCRM extensions under uploads, …)
#
# After import: CMS↔contact links in civicrm_uf_match are cleared (WordPress
# users stay; CiviCRM re-links on next login), URLs are rewritten for local
# via fix-civicrm-urls.sh, and CiviCRM caches are flushed.
#
# Compatible with macOS Bash 3.2 (no mapfile / associative arrays).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
FROM_PATH=""
FORCE=0
TMP_BACKUP=""
TEMP_DB=""
COMPOSE=""
MYSQL_ROOT_PASSWORD=""
MYSQL_DATABASE=""

cleanup() {
	if [[ -n "${TEMP_DB}" && -n "${COMPOSE}" && -n "${MYSQL_ROOT_PASSWORD}" ]]; then
		${COMPOSE} exec -T -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" mariadb \
			sh -ec 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`'"${TEMP_DB}"'\`;"' \
			2>/dev/null || true
	fi
	if [[ -n "${TMP_BACKUP}" && -f "${TMP_BACKUP}" ]]; then
		rm -f "${TMP_BACKUP}"
	fi
}
trap cleanup EXIT

usage() {
	cat <<'EOF'
Usage: sync-staging-civicrm-to-local.sh [--from <path|s3://…>] [--yes]

  Replace local CiviCRM tables from a staging SQL dump. WordPress tables
  and media/plugins on disk are not modified.

  --from PATH   Source dump (local .sql.gz or s3:// URI).
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
MYSQL_ROOT_PASSWORD="$(read_env MYSQL_ROOT_PASSWORD)"

if [[ -z "${BASE_URL}" ]]; then
	echo "Set CIVICRM_UF_BASEURL in ${ENV_FILE} (e.g. http://localhost:8080)" >&2
	exit 1
fi

if [[ -z "${MYSQL_ROOT_PASSWORD}" ]]; then
	echo "Set MYSQL_ROOT_PASSWORD in ${ENV_FILE}" >&2
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
	echo "This will REPLACE local CiviCRM tables in \"${MYSQL_DATABASE}\" from:"
	echo "  ${FROM_PATH}"
	echo "WordPress tables (content, users, options) stay as they are on local."
	echo "CiviCRM URLs will be rewritten for ${BASE_URL}."
	echo "Or re-run with --yes to skip this prompt."
	# Avoid read -p (macOS bash + paste can interleave badly). Strip CR/whitespace so
	# copy-pasted SYNC_CIVI still matches. Keep stdin on the terminal when possible.
	if [[ -t 0 ]]; then
		printf 'Type SYNC_CIVI to continue: ' >/dev/tty
		# shellcheck disable=SC2094
		IFS= read -r confirm </dev/tty || confirm=""
	else
		printf 'Type SYNC_CIVI to continue: '
		IFS= read -r confirm || confirm=""
	fi
	# Normalize: drop CR and surrounding whitespace (common when pasting)
	confirm="$(printf '%s' "${confirm}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
	if [[ "${confirm}" != "SYNC_CIVI" ]]; then
		echo "Aborted (expected SYNC_CIVI, got: ${confirm:-<empty>})." >&2
		echo "Tip: bash scripts/sync-staging-civicrm-to-local.sh --yes" >&2
		exit 1
	fi
fi

RESTORE_FILE="${FROM_PATH}"
if [[ "${FROM_PATH}" == s3://* ]]; then
	if ! command -v aws >/dev/null 2>&1; then
		echo "aws CLI is required for s3:// backups" >&2
		exit 1
	fi
	TMP_BACKUP="$(mktemp "${TMPDIR:-/tmp}/cocodems-civi-sync.XXXXXX.sql.gz")"
	echo "==> Downloading ${FROM_PATH}..."
	aws s3 cp "${FROM_PATH}" "${TMP_BACKUP}"
	RESTORE_FILE="${TMP_BACKUP}"
elif [[ ! -f "${RESTORE_FILE}" ]]; then
	echo "Backup not found: ${FROM_PATH}" >&2
	exit 1
fi

mysql_root() {
	${COMPOSE} exec -T -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" mariadb \
		sh -ec 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$@"' -- "$@"
}

list_civi_tables() {
	local schema="$1"
	mysql_root -N -e "
SELECT table_name
FROM information_schema.tables
WHERE table_schema = '${schema}'
  AND (
    table_name LIKE 'civicrm_%'
    OR table_name LIKE 'log_civicrm_%'
    OR table_name LIKE 'snap_civicrm_%'
  )
ORDER BY table_name;
"
}

table_in_list() {
	local needle="$1"
	local list="$2"
	local t
	for t in ${list}; do
		if [[ "${t}" == "${needle}" ]]; then
			return 0
		fi
	done
	return 1
}

WP_POSTS_BEFORE="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.wp_posts;")"
WP_OPTIONS_BEFORE="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.wp_options;")"
WP_USERS_BEFORE="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.wp_users;")"
WP_SITEURL_BEFORE="$(mysql_root -N -e "SELECT option_value FROM \`${MYSQL_DATABASE}\`.wp_options WHERE option_name='siteurl' LIMIT 1;")"

TEMP_DB="cocodems_civi_src_$(date +%s)"

echo "==> Loading staging dump into temporary database ${TEMP_DB}..."
mysql_root -e "DROP DATABASE IF EXISTS \`${TEMP_DB}\`; CREATE DATABASE \`${TEMP_DB}\`;"

# Dump uses --databases, so it contains CREATE DATABASE / USE for MYSQL_DATABASE.
# Rename only backtick-quoted identifiers (mysqldump style) to the temp DB.
if ! gunzip -c "${RESTORE_FILE}" \
	| sed "s/\`${MYSQL_DATABASE}\`/\`${TEMP_DB}\`/g" \
	| ${COMPOSE} exec -T -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" mariadb \
		sh -ec 'mysql -u root -p"$MYSQL_ROOT_PASSWORD"'; then
	echo "Failed to load dump into temporary database." >&2
	exit 1
fi

CIVI_TABLE_LIST="$(list_civi_tables "${TEMP_DB}" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
if [[ -z "${CIVI_TABLE_LIST}" ]]; then
	echo "No CiviCRM tables found in ${TEMP_DB} after import." >&2
	echo "The dump may use a different database name than MYSQL_DATABASE=${MYSQL_DATABASE}." >&2
	exit 1
fi

CIVI_TABLE_COUNT="$(printf '%s\n' ${CIVI_TABLE_LIST} | wc -l | tr -d ' ')"
echo "==> Found ${CIVI_TABLE_COUNT} CiviCRM table(s) in staging dump"

LOCAL_CIVI_LIST="$(list_civi_tables "${MYSQL_DATABASE}" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
DROP_SQL="SET FOREIGN_KEY_CHECKS=0;"
DROP_COUNT=0
if [[ -n "${LOCAL_CIVI_LIST}" ]]; then
	for t in ${LOCAL_CIVI_LIST}; do
		if ! table_in_list "${t}" "${CIVI_TABLE_LIST}"; then
			DROP_SQL="${DROP_SQL} DROP TABLE IF EXISTS \`${MYSQL_DATABASE}\`.\`${t}\`;"
			DROP_COUNT=$((DROP_COUNT + 1))
		fi
	done
fi
DROP_SQL="${DROP_SQL} SET FOREIGN_KEY_CHECKS=1;"
if [[ ${DROP_COUNT} -gt 0 ]]; then
	echo "==> Dropping ${DROP_COUNT} local-only CiviCRM table(s)..."
	mysql_root -e "${DROP_SQL}"
fi

echo "==> Copying CiviCRM tables into ${MYSQL_DATABASE}..."
if ! ${COMPOSE} exec -T \
	-e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" \
	-e "TEMP_DB=${TEMP_DB}" \
	-e "MYSQL_DATABASE=${MYSQL_DATABASE}" \
	-e "TABLE_LIST=${CIVI_TABLE_LIST}" \
	mariadb sh -ec '
		# TABLE_LIST is space-separated table names from the outer script.
		# shellcheck disable=SC2086
		mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" \
			--single-transaction \
			--routines=false \
			--triggers \
			"$TEMP_DB" $TABLE_LIST \
		| mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"
	'; then
	echo "Failed to copy CiviCRM tables into ${MYSQL_DATABASE}." >&2
	exit 1
fi

echo "==> Clearing civicrm_uf_match so local WordPress users re-link on login..."
if ! mysql_root -e "
SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE \`${MYSQL_DATABASE}\`.civicrm_uf_match;
SET FOREIGN_KEY_CHECKS=1;
"; then
	mysql_root -e "DELETE FROM \`${MYSQL_DATABASE}\`.civicrm_uf_match;"
fi

echo "==> Dropping temporary database ${TEMP_DB}..."
mysql_root -e "DROP DATABASE IF EXISTS \`${TEMP_DB}\`;"
TEMP_DB=""

echo "==> Rewriting CiviCRM URLs for local (${BASE_URL})..."
bash "${REPO_ROOT}/scripts/fix-civicrm-urls.sh"

WP_POSTS_AFTER="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.wp_posts;")"
WP_OPTIONS_AFTER="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.wp_options;")"
WP_USERS_AFTER="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.wp_users;")"
WP_SITEURL_AFTER="$(mysql_root -N -e "SELECT option_value FROM \`${MYSQL_DATABASE}\`.wp_options WHERE option_name='siteurl' LIMIT 1;")"
CIVI_CONTACTS="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.civicrm_contact;" 2>/dev/null || echo "?")"

if [[ "${WP_POSTS_BEFORE}" != "${WP_POSTS_AFTER}" \
	|| "${WP_OPTIONS_BEFORE}" != "${WP_OPTIONS_AFTER}" \
	|| "${WP_USERS_BEFORE}" != "${WP_USERS_AFTER}" \
	|| "${WP_SITEURL_BEFORE}" != "${WP_SITEURL_AFTER}" ]]; then
	echo "WARNING: WordPress table markers changed unexpectedly:" >&2
	echo "  posts:   ${WP_POSTS_BEFORE} -> ${WP_POSTS_AFTER}" >&2
	echo "  options: ${WP_OPTIONS_BEFORE} -> ${WP_OPTIONS_AFTER}" >&2
	echo "  users:   ${WP_USERS_BEFORE} -> ${WP_USERS_AFTER}" >&2
	echo "  siteurl: ${WP_SITEURL_BEFORE} -> ${WP_SITEURL_AFTER}" >&2
	exit 1
fi

echo ""
echo "Staging → local CiviCRM sync complete."
echo "  CiviCRM contacts: ${CIVI_CONTACTS}"
echo "  WordPress posts/options/users unchanged (${WP_POSTS_AFTER}/${WP_OPTIONS_AFTER}/${WP_USERS_AFTER})"
echo "  siteurl unchanged: ${WP_SITEURL_AFTER}"
echo "  CiviCRM base URL:  ${BASE_URL}"
echo ""
echo "WordPress content, plugins, theme, and users were not modified."
echo "Log in with your existing local WordPress account; CiviCRM will re-link contacts as needed."
echo "Files under wp-content (plugins, extensions, uploads) were not copied from staging."
