#!/usr/bin/env bash
# Print CiviCRM URL settings and sample asset paths (for debugging 404s).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${REPO_ROOT}/docker/docker-compose.staging.yml" ]]; then
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.staging.yml"
else
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.local.yml"
fi

echo "==> civicrm.settings.php overrides"
${COMPOSE} exec -T php grep -E "CIVICRM_UF_BASEURL|cocodems-crm URL|userFrameworkResourceURL|imageUploadURL|civicrm_paths\['civicrm\.(files|root)" /var/www/html/wp-content/uploads/civicrm/civicrm.settings.php 2>/dev/null || true

echo ""
echo "==> Active CiviCRM config (runtime)"
# shellcheck disable=SC2016
${COMPOSE} exec -T -u www-data php cv ev '
$c = CRM_Core_Config::singleton();
echo "userFrameworkResourceURL: {$c->userFrameworkResourceURL}\n";
echo "imageUploadURL: {$c->imageUploadURL}\n";
echo "customCSSURL: {$c->customCSSURL}\n";
echo "extensionsURL: " . ($c->extensionsURL ?? "(unset)") . "\n";
echo "uploadDir: {$c->uploadDir}\n";
echo "imageUploadDir: {$c->imageUploadDir}\n";
echo "customFileUploadDir: {$c->customFileUploadDir}\n";
echo "extensionsDir: " . ($c->extensionsDir ?? "(unset)") . "\n";
' 2>/dev/null || true

echo ""
echo "==> Sample persist assets on disk"
${COMPOSE} exec -T php bash -c 'ls -1 /var/www/html/wp-content/uploads/civicrm/persist/contribute/dyn/*.{js,css} 2>/dev/null | head -5' || true
