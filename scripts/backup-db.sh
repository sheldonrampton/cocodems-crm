#!/usr/bin/env bash
# Backup the MariaDB database (WordPress + CiviCRM).
#
#   bash scripts/backup-db.sh
#   bash scripts/backup-db.sh --upload    # also copy to S3 (BACKUP_S3_BUCKET in .env)
#
# Staging:
#   cd /opt/cocodems-crm && bash scripts/backup-db.sh --upload
#
# Backups are written to backups/db/ (gitignored). Set BACKUP_S3_BUCKET from
# `terraform output -raw backup_bucket_name` in infra/terraform/environments/staging.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
UPLOAD=0

usage() {
	cat <<'EOF'
Usage: backup-db.sh [--upload]

  --upload   Copy the dump to s3://BACKUP_S3_BUCKET/cocodems/db/ after writing locally
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
	echo "Copy .env.example (local) or .env.staging.example (server) to .env first." >&2
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
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.local.yml"
fi

MYSQL_DATABASE="$(read_env MYSQL_DATABASE)"
MYSQL_ROOT_PASSWORD="$(read_env MYSQL_ROOT_PASSWORD)"
BACKUP_S3_BUCKET="$(read_env BACKUP_S3_BUCKET)"

if [[ -z "${MYSQL_DATABASE}" || -z "${MYSQL_ROOT_PASSWORD}" ]]; then
	echo "Set MYSQL_DATABASE and MYSQL_ROOT_PASSWORD in ${ENV_FILE}" >&2
	exit 1
fi

if ! ${COMPOSE} exec -T mariadb true 2>/dev/null; then
	echo "MariaDB container is not running. Start the stack first." >&2
	exit 1
fi

BACKUP_DIR="${REPO_ROOT}/backups/db"
mkdir -p "${BACKUP_DIR}"

TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/${MYSQL_DATABASE}-${TIMESTAMP}.sql.gz"

echo "==> Dumping ${MYSQL_DATABASE} to ${BACKUP_FILE}..."
${COMPOSE} exec -T mariadb sh -ec '
	mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" \
		--single-transaction \
		--routines \
		--triggers \
		--databases "$MYSQL_DATABASE"
' | gzip -9 >"${BACKUP_FILE}"

echo "Backup size: $(du -h "${BACKUP_FILE}" | awk '{print $1}')"

if [[ ${UPLOAD} -eq 1 ]]; then
	if [[ -z "${BACKUP_S3_BUCKET}" ]]; then
		echo "Set BACKUP_S3_BUCKET in ${ENV_FILE} to upload backups." >&2
		echo "Staging: terraform output -raw backup_bucket_name (in environments/staging)" >&2
		exit 1
	fi
	if ! command -v aws >/dev/null 2>&1; then
		echo "aws CLI is required for --upload" >&2
		exit 1
	fi

	S3_KEY="cocodems/db/${MYSQL_DATABASE}-${TIMESTAMP}.sql.gz"
	echo "==> Uploading to s3://${BACKUP_S3_BUCKET}/${S3_KEY}..."
	aws s3 cp "${BACKUP_FILE}" "s3://${BACKUP_S3_BUCKET}/${S3_KEY}"
	echo "Uploaded: s3://${BACKUP_S3_BUCKET}/${S3_KEY}"
fi

echo ""
echo "Backup complete: ${BACKUP_FILE}"
