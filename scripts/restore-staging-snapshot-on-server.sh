#!/usr/bin/env bash
# Restore THIS staging instance from a named S3 safety snapshot.
#
# Run on the staging server:
#   bash scripts/restore-staging-snapshot-on-server.sh <name>
#   bash scripts/restore-staging-snapshot-on-server.sh <name> --yes
#
# Replaces the full database and overlays plugins/themes/CiviCRM files from
# s3://BACKUP_S3_BUCKET/cocodems/snapshots/<name>/.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
SNAPSHOT_NAME=""
FORCE=0
TMP_DIR=""

cleanup() {
	if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
		rm -rf "${TMP_DIR}"
	fi
}
trap cleanup EXIT

usage() {
	cat <<'EOF'
Usage: restore-staging-snapshot-on-server.sh <name> [--yes]

  Staging-only. Replaces MariaDB and overlays plugins/themes/CiviCRM files
  from s3://BACKUP_S3_BUCKET/cocodems/snapshots/<name>/.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--yes | -y)
			FORCE=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		-*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 1
			;;
		*)
			if [[ -n "${SNAPSHOT_NAME}" ]]; then
				echo "Unexpected argument: $1" >&2
				exit 1
			fi
			SNAPSHOT_NAME="$1"
			shift
			;;
	esac
done

if [[ -z "${SNAPSHOT_NAME}" ]]; then
	usage >&2
	exit 1
fi

if ! [[ "${SNAPSHOT_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$ ]]; then
	echo "Invalid snapshot name '${SNAPSHOT_NAME}'." >&2
	exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
	echo "Missing ${ENV_FILE}" >&2
	exit 1
fi

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true
}

if ! grep -q '^SITE_DOMAIN=' "${ENV_FILE}" 2>/dev/null; then
	echo "This script must run on staging (SITE_DOMAIN required in .env)." >&2
	exit 1
fi

COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.staging.yml"
MYSQL_DATABASE="$(read_env MYSQL_DATABASE)"
MYSQL_DATABASE="${MYSQL_DATABASE:-cocodems}"
MYSQL_ROOT_PASSWORD="$(read_env MYSQL_ROOT_PASSWORD)"
BACKUP_S3_BUCKET="$(read_env BACKUP_S3_BUCKET)"
BASE_URL="$(read_env CIVICRM_UF_BASEURL)"

if [[ -z "${MYSQL_ROOT_PASSWORD}" || -z "${BACKUP_S3_BUCKET}" || -z "${BASE_URL}" ]]; then
	echo "Set MYSQL_ROOT_PASSWORD, BACKUP_S3_BUCKET, and CIVICRM_UF_BASEURL in ${ENV_FILE}" >&2
	exit 1
fi
if ! command -v aws >/dev/null 2>&1; then
	echo "aws CLI is required on staging." >&2
	exit 1
fi
if ! ${COMPOSE} exec -T mariadb true 2>/dev/null; then
	echo "MariaDB is not running." >&2
	exit 1
fi

S3_PREFIX="cocodems/snapshots/${SNAPSHOT_NAME}"
PACKAGE_URI="s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/"

if ! aws s3 ls "${PACKAGE_URI}manifest.json" >/dev/null 2>&1; then
	echo "Snapshot not found: ${PACKAGE_URI}manifest.json" >&2
	exit 1
fi

if [[ ${FORCE} -ne 1 ]]; then
	echo "This will REPLACE the staging database and overlay files from:"
	echo "  ${PACKAGE_URI}"
	echo "Type RESTORE_STAGING to continue:"
	if [[ -t 0 ]]; then
		printf '> ' >/dev/tty
		IFS= read -r confirm </dev/tty || confirm=""
	else
		IFS= read -r confirm || confirm=""
	fi
	confirm="$(printf '%s' "${confirm}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
	if [[ "${confirm}" != "RESTORE_STAGING" ]]; then
		echo "Aborted." >&2
		exit 1
	fi
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cocodems-snap-restore.XXXXXX")"
echo "==> Downloading snapshot ${SNAPSHOT_NAME}..."
aws s3 cp "${PACKAGE_URI}manifest.json" "${TMP_DIR}/manifest.json"
aws s3 cp "${PACKAGE_URI}database.sql.gz" "${TMP_DIR}/database.sql.gz"
aws s3 cp "${PACKAGE_URI}files.tar.gz" "${TMP_DIR}/files.tar.gz"

echo "==> Restoring full database (WordPress + CiviCRM)..."
if ! gunzip -c "${TMP_DIR}/database.sql.gz" \
	| ${COMPOSE} exec -T -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" mariadb \
		sh -ec 'mysql -u root -p"$MYSQL_ROOT_PASSWORD"'; then
	echo "Database restore failed." >&2
	exit 1
fi

echo "==> Extracting plugins, themes, and CiviCRM files..."
${COMPOSE} cp "${TMP_DIR}/files.tar.gz" php:/tmp/cocodems-snapshot-files.tar.gz
${COMPOSE} exec -T php bash -c '
set -euo pipefail
TMP=$(mktemp -d)
tar -xzf /tmp/cocodems-snapshot-files.tar.gz -C "$TMP"
if [ -d "$TMP/plugins" ]; then
  mkdir -p /var/www/html/wp-content/plugins
  find /var/www/html/wp-content/plugins -mindepth 1 -maxdepth 1 ! -name civicrm -exec rm -rf {} +
  find "$TMP/plugins" -mindepth 1 -maxdepth 1 -exec cp -a {} /var/www/html/wp-content/plugins/ \;
fi
if [ -d "$TMP/themes" ]; then
  mkdir -p /var/www/html/wp-content/themes
  find /var/www/html/wp-content/themes -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  find "$TMP/themes" -mindepth 1 -maxdepth 1 -exec cp -a {} /var/www/html/wp-content/themes/ \;
fi
if [ -d "$TMP/uploads/civicrm" ]; then
  mkdir -p /var/www/html/wp-content/uploads/civicrm
  for sub in ext custom persist; do
    if [ -d "$TMP/uploads/civicrm/$sub" ]; then
      rm -rf "/var/www/html/wp-content/uploads/civicrm/$sub"
      cp -a "$TMP/uploads/civicrm/$sub" /var/www/html/wp-content/uploads/civicrm/
    fi
  done
fi
chown -R www-data:www-data /var/www/html/wp-content/plugins /var/www/html/wp-content/themes /var/www/html/wp-content/uploads/civicrm
chmod -R u+rwX,g+rX,o+rX /var/www/html/wp-content/plugins /var/www/html/wp-content/themes
chmod 755 /var/www/html/wp-content
rm -rf "$TMP" /tmp/cocodems-snapshot-files.tar.gz
'

echo "==> Aligning WordPress/CiviCRM URLs for this staging host..."
bash "${REPO_ROOT}/scripts/fix-civicrm-urls.sh"
STAGING_BASE="${BASE_URL%/}"
${COMPOSE} exec -T php wp option update home "${STAGING_BASE}" --allow-root --path=/var/www/html
${COMPOSE} exec -T php wp option update siteurl "${STAGING_BASE}" --allow-root --path=/var/www/html
${COMPOSE} exec -T php wp cache flush --allow-root --path=/var/www/html 2>/dev/null || true
${COMPOSE} exec -T -u www-data -e XDG_STATE_HOME=/var/www/private/.cv-state php cv flush 2>/dev/null || true

CONTACTS="$(${COMPOSE} exec -T -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" \
	-e "MYSQL_DATABASE=${MYSQL_DATABASE}" mariadb sh -ec '
	mysql -u root -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM \`'"${MYSQL_DATABASE}"'\`.civicrm_contact WHERE is_deleted=0;"
' 2>/dev/null | tr -d '\r' || echo "?")"

echo ""
echo "Staging restored from snapshot: ${SNAPSHOT_NAME}"
echo "  Site:             ${STAGING_BASE}"
echo "  CiviCRM contacts: ${CONTACTS} live"
echo "Verify: ${STAGING_BASE}/wp-login.php"
