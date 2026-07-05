#!/usr/bin/env bash
# Enable HTTPS on staging using Certbot + host Nginx.
# Run on the EC2 instance after deploy-staging.sh and DNS are working.
#
#   sudo bash scripts/setup-staging-tls.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [[ "${EUID}" -ne 0 ]]; then
	echo "Run as root: sudo bash $0" >&2
	exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
	echo "Missing ${ENV_FILE}" >&2
	exit 1
fi

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//'
}

SITE_DOMAIN="$(read_env SITE_DOMAIN)"
CIVICRM_ADMIN_EMAIL="$(read_env CIVICRM_ADMIN_EMAIL)"

if [[ -z "${SITE_DOMAIN}" || -z "${CIVICRM_ADMIN_EMAIL}" ]]; then
	echo "Set SITE_DOMAIN and CIVICRM_ADMIN_EMAIL in ${ENV_FILE}" >&2
	exit 1
fi

echo "==> Requesting TLS certificate for ${SITE_DOMAIN}..."
certbot --nginx -d "${SITE_DOMAIN}" --non-interactive --agree-tos -m "${CIVICRM_ADMIN_EMAIL}" --redirect

HTTPS_URL="https://${SITE_DOMAIN}"

echo "==> Updating .env CIVICRM_UF_BASEURL to ${HTTPS_URL}..."
if grep -q '^CIVICRM_UF_BASEURL=' "${ENV_FILE}"; then
	sed -i "s|^CIVICRM_UF_BASEURL=.*|CIVICRM_UF_BASEURL=${HTTPS_URL}|" "${ENV_FILE}"
else
	echo "CIVICRM_UF_BASEURL=${HTTPS_URL}" >> "${ENV_FILE}"
fi

COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.staging.yml"

echo "==> Updating WordPress URLs..."
${COMPOSE} exec -T php wp option update home "${HTTPS_URL}" --path=/var/www/html --allow-root
${COMPOSE} exec -T php wp option update siteurl "${HTTPS_URL}" --path=/var/www/html --allow-root

WP_CONFIG="/var/www/private/wp-config.php"
if ${COMPOSE} exec -T php test -f "${WP_CONFIG}" 2>/dev/null; then
	${COMPOSE} exec -T php sed -i "s|define( 'WP_HOME'.*|define( 'WP_HOME', '${HTTPS_URL}' );|" "${WP_CONFIG}" || true
	${COMPOSE} exec -T php sed -i "s|define( 'WP_SITEURL'.*|define( 'WP_SITEURL', '${HTTPS_URL}' );|" "${WP_CONFIG}" || true
fi

echo ""
echo "HTTPS enabled: ${HTTPS_URL}"
