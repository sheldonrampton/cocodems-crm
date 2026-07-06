#!/usr/bin/env bash
# Upgrade CiviCRM on an existing install after rebuilding the PHP image.
#
# Rebuild first (pulls new CIVICRM_VERSION from docker/php/Dockerfile):
#   sudo -u ubuntu bash scripts/deploy-staging.sh
#
# Then run this script:
#   sudo -u ubuntu bash scripts/upgrade-civicrm.sh
#
# Local dev:
#   docker compose --project-directory . -f docker/docker-compose.yml \
#     -f docker/docker-compose.local.yml up -d --build
#   bash scripts/upgrade-civicrm.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f "${REPO_ROOT}/docker/docker-compose.staging.yml" ]]; then
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.staging.yml"
else
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.local.yml"
fi

# cv stores upgrade state under XDG_STATE_HOME (www-data cannot write /var/www/.cv).
CV_STATE_DIR="/var/www/private/.cv-state"
CV_EXEC=(exec -T -u www-data -e "XDG_STATE_HOME=${CV_STATE_DIR}")

CIVI_SRC="/usr/src/wordpress/wp-content/plugins/civicrm"
CIVI_DST="/var/www/html/wp-content/plugins/civicrm"

if ! ${COMPOSE} exec -T php test -d "${CIVI_SRC}" 2>/dev/null; then
	echo "CiviCRM not found in image at ${CIVI_SRC}. Rebuild the PHP container first." >&2
	exit 1
fi

echo "==> Ensuring cv state directory is writable..."
${COMPOSE} exec -T php bash -c "mkdir -p '${CV_STATE_DIR}' && chown -R www-data:www-data '${CV_STATE_DIR}'"

echo "==> Replacing CiviCRM plugin files from image..."
${COMPOSE} exec -T php bash -c "
	rm -rf '${CIVI_DST}'
	cp -a '${CIVI_SRC}' '${CIVI_DST}'
	chown -R www-data:www-data '${CIVI_DST}'
"

echo "==> Running CiviCRM database upgrade..."
${COMPOSE} "${CV_EXEC[@]}" php cv upgrade:db

echo "==> Flushing CiviCRM caches..."
${COMPOSE} "${CV_EXEC[@]}" php cv flush

echo ""
echo "CiviCRM upgrade complete."
${COMPOSE} "${CV_EXEC[@]}" php cv ev 'echo "Version: " . CRM_Utils_System::version() . PHP_EOL;'
