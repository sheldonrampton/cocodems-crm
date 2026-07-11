#!/usr/bin/env bash
# Backup the MariaDB database (WordPress + CiviCRM).
#
#   bash scripts/backup-db.sh
#   bash scripts/backup-db.sh --upload
#   bash scripts/backup-db.sh --upload --keep-local
#
# Staging cron uploads to S3 and does not keep a local copy (uses /tmp only).
#
# S3 layout (when --upload):
#   cocodems/db/daily/   — every backup; lifecycle expires after 30 days
#   cocodems/db/monthly/ — additional copy on the 1st UTC; kept 365 days
#
# Set BACKUP_S3_BUCKET from `terraform output -raw backup_bucket_name`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
UPLOAD=0
KEEP_LOCAL=0

usage() {
	cat <<'EOF'
Usage: backup-db.sh [--upload] [--keep-local]

  --upload       Upload to S3 (requires BACKUP_S3_BUCKET in .env)
  --keep-local   With --upload, keep the .sql.gz on disk after upload
                 (default: remove local copy after a successful upload)
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--upload)
			UPLOAD=1
			shift
			;;
		--keep-local)
			KEEP_LOCAL=1
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

TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
BACKUP_DIR="${REPO_ROOT}/backups/db"
REMOVE_AFTER_UPLOAD=0

if [[ ${UPLOAD} -eq 1 && ${KEEP_LOCAL} -eq 0 ]]; then
	BACKUP_FILE="$(mktemp "${TMPDIR:-/tmp}/cocodems-backup.XXXXXX.sql.gz")"
	REMOVE_AFTER_UPLOAD=1
	echo "==> Dumping ${MYSQL_DATABASE} to temporary file..."
else
	mkdir -p "${BACKUP_DIR}" 2>/dev/null || true
	if [[ ! -d "${BACKUP_DIR}" ]] || [[ ! -w "${BACKUP_DIR}" ]]; then
		echo "Cannot write to ${BACKUP_DIR} (run as $(whoami))." >&2
		echo "On staging: sudo bash scripts/setup-staging-backup-cron.sh" >&2
		echo "Or: sudo chown -R ubuntu:ubuntu ${REPO_ROOT}/backups" >&2
		exit 1
	fi
	BACKUP_FILE="${BACKUP_DIR}/${MYSQL_DATABASE}-${TIMESTAMP}.sql.gz"
	echo "==> Dumping ${MYSQL_DATABASE} to ${BACKUP_FILE}..."
fi

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
		exit 1
	fi
	if ! command -v aws >/dev/null 2>&1; then
		echo "aws CLI is required for --upload" >&2
		exit 1
	fi

	DAILY_KEY="cocodems/db/daily/${MYSQL_DATABASE}-${TIMESTAMP}.sql.gz"
	echo "==> Uploading to s3://${BACKUP_S3_BUCKET}/${DAILY_KEY}..."
	aws s3 cp "${BACKUP_FILE}" "s3://${BACKUP_S3_BUCKET}/${DAILY_KEY}"
	echo "Uploaded: s3://${BACKUP_S3_BUCKET}/${DAILY_KEY}"

	if [[ "$(date -u +%d)" == "01" ]]; then
		MONTHLY_KEY="cocodems/db/monthly/${MYSQL_DATABASE}-$(date -u +%Y-%m)-01.sql.gz"
		echo "==> Uploading monthly snapshot to s3://${BACKUP_S3_BUCKET}/${MONTHLY_KEY}..."
		aws s3 cp "${BACKUP_FILE}" "s3://${BACKUP_S3_BUCKET}/${MONTHLY_KEY}"
		echo "Uploaded: s3://${BACKUP_S3_BUCKET}/${MONTHLY_KEY}"
	fi

	if [[ ${REMOVE_AFTER_UPLOAD} -eq 1 ]]; then
		rm -f "${BACKUP_FILE}"
		echo "Removed local copy after upload."
	fi
fi

echo ""
if [[ ${REMOVE_AFTER_UPLOAD} -eq 1 ]]; then
	echo "Backup complete (S3 only)."
else
	echo "Backup complete: ${BACKUP_FILE}"
fi
