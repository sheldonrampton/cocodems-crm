#!/usr/bin/env bash
# Create a named safety snapshot of THIS staging instance (DB + files) to S3.
#
# Run on the staging server:
#   bash scripts/create-staging-snapshot-on-server.sh <name>
#
# Written to: s3://BACKUP_S3_BUCKET/cocodems/snapshots/<name>/
#   manifest.json  database.sql.gz  files.tar.gz

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
SNAPSHOT_NAME="${1:-}"
WORK_DIR=""

cleanup() {
	if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
		rm -rf "${WORK_DIR}"
	fi
}
trap cleanup EXIT

usage() {
	cat <<'EOF'
Usage: create-staging-snapshot-on-server.sh <name>

  Staging-only. Dumps MariaDB and packages plugins/themes/CiviCRM files to
  s3://BACKUP_S3_BUCKET/cocodems/snapshots/<name>/
EOF
}

if [[ -z "${SNAPSHOT_NAME}" || "${SNAPSHOT_NAME}" == -h || "${SNAPSHOT_NAME}" == --help ]]; then
	usage
	exit 0
fi

if ! [[ "${SNAPSHOT_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$ ]]; then
	echo "Invalid snapshot name '${SNAPSHOT_NAME}'." >&2
	echo "Use 1–63 chars: letters, digits, ., _, - (must start with alphanumeric)." >&2
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
SITE_DOMAIN="$(read_env SITE_DOMAIN)"

if [[ -z "${MYSQL_ROOT_PASSWORD}" ]]; then
	echo "Set MYSQL_ROOT_PASSWORD in ${ENV_FILE}" >&2
	exit 1
fi
if [[ -z "${BACKUP_S3_BUCKET}" ]]; then
	echo "Set BACKUP_S3_BUCKET in ${ENV_FILE}" >&2
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
if ! ${COMPOSE} exec -T php true 2>/dev/null; then
	echo "PHP is not running." >&2
	exit 1
fi

S3_PREFIX="cocodems/snapshots/${SNAPSHOT_NAME}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cocodems-snap.XXXXXX")"

echo "==> Snapshot name: ${SNAPSHOT_NAME}"
echo "==> Target: s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/"

echo "==> Dumping database ${MYSQL_DATABASE}..."
${COMPOSE} exec -T -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" \
	-e "MYSQL_DATABASE=${MYSQL_DATABASE}" mariadb sh -ec '
	mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" \
		--single-transaction \
		--routines \
		--triggers \
		--databases "$MYSQL_DATABASE"
' | gzip -9 >"${WORK_DIR}/database.sql.gz"
echo "    $(du -h "${WORK_DIR}/database.sql.gz" | awk '{print $1}')"

echo "==> Collecting versions..."
WP_VERSION="$(${COMPOSE} exec -T php wp core version --allow-root --path=/var/www/html 2>/dev/null | tr -d '\r' || echo unknown)"
CIVI_VERSION="$(${COMPOSE} exec -T -u www-data -e XDG_STATE_HOME=/var/www/private/.cv-state php cv ev 'echo CRM_Utils_System::version();' 2>/dev/null | tr -d '\r' || echo unknown)"
CIVI_LIVE="$(${COMPOSE} exec -T -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" \
	-e "MYSQL_DATABASE=${MYSQL_DATABASE}" mariadb sh -ec '
	mysql -u root -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM \`'"${MYSQL_DATABASE}"'\`.civicrm_contact WHERE is_deleted=0;"
' 2>/dev/null | tr -d '\r' || echo "?")"

cat >"${WORK_DIR}/manifest.json" <<EOF
{
  "name": "${SNAPSHOT_NAME}",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "site_domain": "${SITE_DOMAIN}",
  "base_url": "${BASE_URL}",
  "wordpress": "${WP_VERSION}",
  "civicrm": "${CIVI_VERSION}",
  "civicrm_contacts_live": "${CIVI_LIVE}",
  "database": "database.sql.gz",
  "files": "files.tar.gz"
}
EOF

echo "==> Packaging plugins, themes, and CiviCRM file data..."
${COMPOSE} exec -T php bash -c '
set -euo pipefail
TMP=$(mktemp -d)
chmod 755 "$TMP"
mkdir -p "$TMP/plugins" "$TMP/themes" "$TMP/uploads/civicrm"
cd /var/www/html/wp-content
if [ -d plugins ]; then
  find plugins -mindepth 1 -maxdepth 1 ! -name civicrm -exec cp -a {} "$TMP/plugins/" \;
fi
if [ -d themes ]; then
  find themes -mindepth 1 -maxdepth 1 -exec cp -a {} "$TMP/themes/" \;
fi
if [ -d uploads/civicrm/ext ]; then
  cp -a uploads/civicrm/ext "$TMP/uploads/civicrm/"
fi
if [ -d uploads/civicrm/custom ]; then
  cp -a uploads/civicrm/custom "$TMP/uploads/civicrm/"
fi
if [ -d uploads/civicrm/persist ]; then
  cp -a uploads/civicrm/persist "$TMP/uploads/civicrm/"
fi
# Keep note: CiviCRM core plugin lives in image/volume; not duplicated here.
tar -czf /tmp/cocodems-snapshot-files.tar.gz -C "$TMP" .
rm -rf "$TMP"
'
${COMPOSE} cp php:/tmp/cocodems-snapshot-files.tar.gz "${WORK_DIR}/files.tar.gz"
${COMPOSE} exec -T php rm -f /tmp/cocodems-snapshot-files.tar.gz
echo "    $(du -h "${WORK_DIR}/files.tar.gz" | awk '{print $1}')"

echo "==> Uploading to s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/..."
aws s3 cp "${WORK_DIR}/manifest.json" "s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/manifest.json"
aws s3 cp "${WORK_DIR}/database.sql.gz" "s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/database.sql.gz"
aws s3 cp "${WORK_DIR}/files.tar.gz" "s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/files.tar.gz"
echo "${SNAPSHOT_NAME}" | aws s3 cp - "s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/latest.txt"

echo ""
echo "Staging snapshot created: ${SNAPSHOT_NAME}"
echo "  s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/"
echo "  WordPress ${WP_VERSION}  CiviCRM ${CIVI_VERSION}  contacts(live)=${CIVI_LIVE}"
