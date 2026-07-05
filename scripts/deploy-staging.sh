#!/usr/bin/env bash
# Deploy (or update) CoCoDems CRM on the staging EC2 instance.
# Run on the server as the ubuntu user from the repo root, or via:
#
#   cd /opt/cocodems-crm && bash scripts/deploy-staging.sh
#
# First-time setup:
#   1. sudo bash scripts/bootstrap-staging-server.sh
#   2. Clone this repo to /opt/cocodems-crm
#   3. cp .env.staging.example .env && nano .env
#   4. bash scripts/deploy-staging.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

COMPOSE="docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.staging.yml"
ENV_FILE="${REPO_ROOT}/.env"
NGINX_TEMPLATE="${REPO_ROOT}/docker/nginx/host-staging.conf.template"
NGINX_SITE="/etc/nginx/sites-available/cocodems-staging"

if [[ ! -f "${ENV_FILE}" ]]; then
	echo "Missing ${ENV_FILE}" >&2
	echo "Copy .env.staging.example to .env and set passwords + SITE_DOMAIN." >&2
	exit 1
fi

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//'
}

SITE_DOMAIN="$(read_env SITE_DOMAIN)"
CIVICRM_UF_BASEURL="$(read_env CIVICRM_UF_BASEURL)"

if [[ -z "${SITE_DOMAIN}" || -z "${CIVICRM_UF_BASEURL}" ]]; then
	echo "Set SITE_DOMAIN and CIVICRM_UF_BASEURL in ${ENV_FILE}" >&2
	exit 1
fi

echo "==> Building and starting Docker containers..."
${COMPOSE} up -d --build

echo "==> Waiting for WordPress install (may take several minutes on first boot)..."
for i in $(seq 1 60); do
	if ${COMPOSE} exec -T php test -f /var/www/private/wp-config.php 2>/dev/null; then
		echo "WordPress config found."
		break
	fi
	echo "Still installing... (${i}/60)"
	sleep 10
done

echo "==> Installing host Nginx reverse proxy for ${SITE_DOMAIN}..."
export SITE_DOMAIN
envsubst '${SITE_DOMAIN}' < "${NGINX_TEMPLATE}" | sudo tee "${NGINX_SITE}" > /dev/null
sudo ln -sf "${NGINX_SITE}" /etc/nginx/sites-enabled/cocodems-staging
sudo nginx -t
sudo systemctl reload nginx

echo ""
echo "Deploy complete."
echo "  Site URL: ${CIVICRM_UF_BASEURL}"
echo "  Login:    ${CIVICRM_UF_BASEURL}/wp-login.php"
echo ""
echo "Next steps:"
echo "  1. Verify HTTP: curl -I http://${SITE_DOMAIN}/"
echo "  2. Enable HTTPS:  sudo bash scripts/setup-staging-tls.sh"
echo "  3. Password gate:  sudo bash scripts/setup-staging-auth.sh"
