#!/usr/bin/env bash
# Install (or remove) the daily database backup cron job on staging.
#
#   sudo bash scripts/setup-staging-backup-cron.sh
#   sudo bash scripts/setup-staging-backup-cron.sh --hour 4 --minute 30
#   sudo bash scripts/setup-staging-backup-cron.sh --uninstall
#
# Requires:
#   - BACKUP_S3_BUCKET in .env
#   - awscli on the host (bootstrap-staging-server.sh or apt install awscli)
#   - Docker stack running (deploy-staging.sh)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
CRON_FILE="/etc/cron.d/cocodems-db-backup"
LOG_FILE="/var/log/cocodems-backup.log"
CRON_USER="ubuntu"
CRON_HOUR="3"
CRON_MINUTE="15"
UNINSTALL=0

usage() {
	cat <<EOF
Usage: setup-staging-backup-cron.sh [options]

  --hour HOUR       UTC hour to run (default: 3)
  --minute MINUTE   UTC minute to run (default: 15)
  --uninstall       Remove the cron job
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--hour)
			CRON_HOUR="$2"
			shift 2
			;;
		--minute)
			CRON_MINUTE="$2"
			shift 2
			;;
		--uninstall)
			UNINSTALL=1
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

if [[ "${EUID}" -ne 0 ]]; then
	echo "Run as root: sudo bash $0" >&2
	exit 1
fi

if [[ ${UNINSTALL} -eq 1 ]]; then
	if [[ -f "${CRON_FILE}" ]]; then
		rm -f "${CRON_FILE}"
		echo "Removed ${CRON_FILE}"
	else
		echo "No cron job installed (${CRON_FILE} not found)."
	fi
	exit 0
fi

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true
}

if [[ ! -f "${ENV_FILE}" ]]; then
	echo "Missing ${ENV_FILE}" >&2
	exit 1
fi

BACKUP_S3_BUCKET="$(read_env BACKUP_S3_BUCKET)"
if [[ -z "${BACKUP_S3_BUCKET}" ]]; then
	echo "Set BACKUP_S3_BUCKET in ${ENV_FILE} before enabling scheduled backups." >&2
	exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
	echo "AWS CLI not found. Install with: apt-get install -y awscli" >&2
	exit 1
fi

if ! command -v sg >/dev/null 2>&1; then
	echo "sg command not found (install util-linux)." >&2
	exit 1
fi

if ! id "${CRON_USER}" >/dev/null 2>&1; then
	echo "User ${CRON_USER} not found." >&2
	exit 1
fi

if ! getent group docker >/dev/null 2>&1; then
	echo "docker group not found." >&2
	exit 1
fi

if ! id -nG "${CRON_USER}" | grep -qw docker; then
	echo "User ${CRON_USER} is not in the docker group. Re-run bootstrap-staging-server.sh or: usermod -aG docker ${CRON_USER}" >&2
	exit 1
fi

touch "${LOG_FILE}"
chown "${CRON_USER}:${CRON_USER}" "${LOG_FILE}"
chmod 640 "${LOG_FILE}"

cat >"${CRON_FILE}" <<EOF
# CoCoDems CRM — daily MariaDB backup to S3 (installed by setup-staging-backup-cron.sh)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
${CRON_MINUTE} ${CRON_HOUR} * * * ${CRON_USER} ${REPO_ROOT}/scripts/cron-backup-db.sh
EOF

chmod 644 "${CRON_FILE}"

echo "Installed daily backup cron:"
echo "  Schedule: ${CRON_MINUTE} ${CRON_HOUR} * * * (UTC)"
echo "  User:     ${CRON_USER}"
echo "  Log:      ${LOG_FILE}"
echo "  S3:       s3://${BACKUP_S3_BUCKET}/cocodems/db/"
echo ""
echo "Test now: sudo -u ${CRON_USER} bash ${REPO_ROOT}/scripts/cron-backup-db.sh"
echo "Tail log: tail -f ${LOG_FILE}"
