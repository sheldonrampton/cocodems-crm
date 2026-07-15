#!/usr/bin/env bash
# Package staging WordPress plugins and CiviCRM file data for local rebuilds.
#
# Run on the staging server:
#   bash scripts/backup-staging-files.sh --upload
#
# Uploads to s3://BACKUP_S3_BUCKET/cocodems/files/ and updates
# cocodems/files/latest.tar.gz plus versions.json.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
UPLOAD=0

usage() {
	cat <<'EOF'
Usage: backup-staging-files.sh [--upload]

  --upload   Upload the archive to s3://BACKUP_S3_BUCKET/cocodems/files/
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--upload)
			UPLOAD=1
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
	exit 1
fi

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true
}

if [[ -f "${REPO_ROOT}/docker/docker-compose.staging.yml" ]] \
	&& grep -q '^SITE_DOMAIN=' "${ENV_FILE}" 2>/dev/null; then
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.staging.yml"
else
	echo "Run this on the staging server (SITE_DOMAIN must be set in .env)." >&2
	exit 1
fi

BACKUP_S3_BUCKET="$(read_env BACKUP_S3_BUCKET)"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cocodems-files.XXXXXX")"
ARCHIVE="${WORK_DIR}/staging-files-${TIMESTAMP}.tar.gz"
MANIFEST="${WORK_DIR}/versions.json"

cleanup() {
	rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

if ! ${COMPOSE} exec -T php true 2>/dev/null; then
	echo "PHP container is not running." >&2
	exit 1
fi

echo "==> Collecting versions from staging..."
WP_VERSION="$(${COMPOSE} exec -T php wp core version --allow-root --path=/var/www/html 2>/dev/null | tr -d '\r')"
CIVI_VERSION="$(${COMPOSE} exec -T -u www-data -e XDG_STATE_HOME=/var/www/private/.cv-state php cv ev 'echo CRM_Utils_System::version();' 2>/dev/null | tr -d '\r')"

cat >"${MANIFEST}" <<EOF
{
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "wordpress": "${WP_VERSION}",
  "civicrm": "${CIVI_VERSION}"
}
EOF

echo "WordPress: ${WP_VERSION}"
echo "CiviCRM:   ${CIVI_VERSION}"

echo "==> Packaging plugins and CiviCRM files..."
${COMPOSE} cp "${MANIFEST}" php:/tmp/cocodems-versions.json
${COMPOSE} exec -T php bash -c '
set -euo pipefail
cd /var/www/html/wp-content
TMP=$(mktemp -d)
mkdir -p "$TMP/plugins" "$TMP/uploads/civicrm"
cp /tmp/cocodems-versions.json "$TMP/versions.json"
if [ -d plugins ]; then
  find plugins -mindepth 1 -maxdepth 1 ! -name civicrm ! -name cocodems-custom -exec cp -a {} "$TMP/plugins/" \;
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
tar -czf /tmp/cocodems-staging-files.tar.gz -C "$TMP" .
rm -rf "$TMP" /tmp/cocodems-versions.json
'

${COMPOSE} cp php:/tmp/cocodems-staging-files.tar.gz "${ARCHIVE}"
${COMPOSE} exec -T php rm -f /tmp/cocodems-staging-files.tar.gz

echo "Archive size: $(du -h "${ARCHIVE}" | awk '{print $1}')"

if [[ ${UPLOAD} -eq 1 ]]; then
	if [[ -z "${BACKUP_S3_BUCKET}" ]]; then
		echo "Set BACKUP_S3_BUCKET in ${ENV_FILE}" >&2
		exit 1
	fi
	if ! command -v aws >/dev/null 2>&1; then
		echo "aws CLI is required for --upload" >&2
		exit 1
	fi
	STAMPED_KEY="cocodems/files/staging-files-${TIMESTAMP}.tar.gz"
	LATEST_KEY="cocodems/files/latest.tar.gz"
	MANIFEST_KEY="cocodems/files/versions.json"
	echo "==> Uploading to s3://${BACKUP_S3_BUCKET}/${STAMPED_KEY}..."
	aws s3 cp "${ARCHIVE}" "s3://${BACKUP_S3_BUCKET}/${STAMPED_KEY}"
	aws s3 cp "${ARCHIVE}" "s3://${BACKUP_S3_BUCKET}/${LATEST_KEY}"
	aws s3 cp "${MANIFEST}" "s3://${BACKUP_S3_BUCKET}/${MANIFEST_KEY}"
	echo "Uploaded latest: s3://${BACKUP_S3_BUCKET}/${LATEST_KEY}"
fi

echo ""
echo "Files backup complete."
echo "WordPress=${WP_VERSION} CiviCRM=${CIVI_VERSION}"
