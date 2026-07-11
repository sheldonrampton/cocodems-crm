#!/usr/bin/env bash
# Restore MariaDB from a gzip SQL dump created by backup-db.sh.
#
#   bash scripts/restore-db.sh backups/db/cocodems-20260708-120000.sql.gz
#   bash scripts/restore-db.sh backups/db/cocodems-20260708-120000.sql.gz --yes
#   bash scripts/restore-db.sh s3://my-bucket/cocodems/db/cocodems-20260708-120000.sql.gz --yes
#
# WARNING: replaces the current database contents.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
BACKUP_PATH=""
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
Usage: restore-db.sh <backup.sql.gz|s3://bucket/key.sql.gz> [--yes]

  --yes, -y   Skip the interactive confirmation prompt
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
			if [[ -n "${BACKUP_PATH}" ]]; then
				echo "Unexpected argument: $1" >&2
				usage >&2
				exit 1
			fi
			BACKUP_PATH="$1"
			shift
			;;
	esac
done

if [[ -z "${BACKUP_PATH}" ]]; then
	usage >&2
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

if [[ -f "${REPO_ROOT}/docker/docker-compose.staging.yml" ]] \
	&& grep -q '^SITE_DOMAIN=' "${ENV_FILE}" 2>/dev/null; then
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.staging.yml"
else
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.local.yml"
fi

MYSQL_DATABASE="$(read_env MYSQL_DATABASE)"
MYSQL_ROOT_PASSWORD="$(read_env MYSQL_ROOT_PASSWORD)"

if [[ -z "${MYSQL_DATABASE}" || -z "${MYSQL_ROOT_PASSWORD}" ]]; then
	echo "Set MYSQL_DATABASE and MYSQL_ROOT_PASSWORD in ${ENV_FILE}" >&2
	exit 1
fi

if ! ${COMPOSE} exec -T mariadb true 2>/dev/null; then
	echo "MariaDB container is not running. Start the stack first." >&2
	exit 1
fi

RESTORE_FILE="${BACKUP_PATH}"

if [[ "${BACKUP_PATH}" == s3://* ]]; then
	if ! command -v aws >/dev/null 2>&1; then
		echo "aws CLI is required for s3:// backups" >&2
		exit 1
	fi
	TMP_BACKUP="$(mktemp "${TMPDIR:-/tmp}/cocodems-restore.XXXXXX.sql.gz")"
	echo "==> Downloading ${BACKUP_PATH}..."
	aws s3 cp "${BACKUP_PATH}" "${TMP_BACKUP}"
	RESTORE_FILE="${TMP_BACKUP}"
elif [[ ! -f "${RESTORE_FILE}" ]]; then
	echo "Backup file not found: ${RESTORE_FILE}" >&2
	exit 1
fi

if [[ ${FORCE} -ne 1 ]]; then
	echo "This will REPLACE database \"${MYSQL_DATABASE}\" with:"
	echo "  ${BACKUP_PATH}"
	read -r -p "Type RESTORE to continue: " confirm
	if [[ "${confirm}" != "RESTORE" ]]; then
		echo "Aborted."
		exit 1
	fi
fi

echo "==> Restoring ${BACKUP_PATH}..."
gunzip -c "${RESTORE_FILE}" | ${COMPOSE} exec -T mariadb sh -ec 'mysql -u root -p"$MYSQL_ROOT_PASSWORD"'

echo "==> Flushing CiviCRM caches (if available)..."
${COMPOSE} exec -T -u www-data -e XDG_STATE_HOME=/var/www/private/.cv-state php cv flush 2>/dev/null || true

echo ""
echo "Restore complete."
