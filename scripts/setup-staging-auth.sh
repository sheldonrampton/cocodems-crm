#!/usr/bin/env bash
# Add HTTP basic auth in front of the staging site (committee demo protection).
# Run on the EC2 instance:
#
#   sudo bash scripts/setup-staging-auth.sh
#
# Or set STAGING_HTTP_USER and STAGING_HTTP_PASS in .env before running.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
NGINX_SITE="/etc/nginx/sites-available/cocodems-staging"
HTPASSWD_FILE="/etc/nginx/cocodems-staging.htpasswd"

if [[ "${EUID}" -ne 0 ]]; then
	echo "Run as root: sudo bash $0" >&2
	exit 1
fi

read_env() {
	local key="$1"
	if [[ -f "${ENV_FILE}" ]]; then
		grep -E "^${key}=" "${ENV_FILE}" | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true
	fi
}

STAGING_HTTP_USER="$(read_env STAGING_HTTP_USER)"
STAGING_HTTP_PASS="$(read_env STAGING_HTTP_PASS)"
STAGING_HTTP_USER="${STAGING_HTTP_USER:-staging}"

if [[ -z "${STAGING_HTTP_PASS}" ]]; then
	read -r -s -p "Password for user '${STAGING_HTTP_USER}': " STAGING_HTTP_PASS
	echo
fi

echo "==> Creating htpasswd file..."
htpasswd -bc "${HTPASSWD_FILE}" "${STAGING_HTTP_USER}" "${STAGING_HTTP_PASS}"
chmod 640 "${HTPASSWD_FILE}"
chown root:www-data "${HTPASSWD_FILE}"

echo "==> Enabling basic auth in Nginx..."
sed -i 's|^[[:space:]]*# auth_basic |    auth_basic |' "${NGINX_SITE}"
sed -i 's|^[[:space:]]*# auth_basic_user_file |    auth_basic_user_file |' "${NGINX_SITE}"

nginx -t
systemctl reload nginx

echo "Basic auth enabled. Users need: ${STAGING_HTTP_USER} / (password you set)"
