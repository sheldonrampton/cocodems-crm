#!/usr/bin/env bash
# Sync CiviCRM base URL and resource paths with CIVICRM_UF_BASEURL in .env.
# Run after TLS setup, domain changes, or when CiviCRM menus/CSS fail to load.
#
#   bash scripts/fix-civicrm-urls.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
CIVI_SETTINGS="/var/www/html/wp-content/uploads/civicrm/civicrm.settings.php"
OVERRIDE_MARKER="# cocodems-crm URL overrides (scripts/fix-civicrm-urls.sh)"

if [[ ! -f "${ENV_FILE}" ]]; then
	echo "Missing ${ENV_FILE}" >&2
	exit 1
fi

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//'
}

BASE_URL="$(read_env CIVICRM_UF_BASEURL)"
if [[ -z "${BASE_URL}" ]]; then
	echo "Set CIVICRM_UF_BASEURL in ${ENV_FILE}" >&2
	exit 1
fi

# CiviCRM expects a trailing slash on the CMS base URL.
[[ "${BASE_URL}" != */ ]] && BASE_URL="${BASE_URL}/"

RESOURCE_URL="${BASE_URL}wp-content/plugins/civicrm/civicrm/"
FILES_URL="${BASE_URL}wp-content/uploads/civicrm/"
CUSTOM_CSS_URL="${FILES_URL}css/"

if [[ -f "${REPO_ROOT}/docker/docker-compose.staging.yml" ]]; then
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.staging.yml"
else
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.local.yml"
fi

if ! ${COMPOSE} exec -T php test -f "${CIVI_SETTINGS}" 2>/dev/null; then
	echo "CiviCRM settings not found at ${CIVI_SETTINGS}. Run deploy first." >&2
	exit 1
fi

echo "==> Updating CiviCRM base URL to ${BASE_URL}..."

${COMPOSE} exec -T php sed -i \
	-e "s|define( *'CIVICRM_UF_BASEURL'.*|define( 'CIVICRM_UF_BASEURL', '${BASE_URL}' );|" \
	-e "s|define(\"CIVICRM_UF_BASEURL\".*|define(\"CIVICRM_UF_BASEURL\", \"${BASE_URL}\");|" \
	"${CIVI_SETTINGS}"

if [[ "${BASE_URL}" == https://* ]]; then
	HTTP_URL="http://${BASE_URL#https://}"
	${COMPOSE} exec -T php sed -i "s|${HTTP_URL}|${BASE_URL}|g" "${CIVI_SETTINGS}" || true
	${COMPOSE} exec -T php sed -i "s|${HTTP_URL%/}|${BASE_URL%/}|g" "${CIVI_SETTINGS}" || true
fi

${COMPOSE} exec -T php php -r "
\$file = '${CIVI_SETTINGS}';
\$marker = '${OVERRIDE_MARKER}';
\$content = file_get_contents(\$file);
if (str_contains(\$content, \$marker)) {
	\$content = preg_replace('/\\n?' . preg_quote(\$marker, '/') . '[\\s\\S]*\\z/', '', rtrim(\$content));
}
\$block = \$marker . \"\\n\"
  . \"if (!isset(\\\$civicrm_setting['domain'])) {\\n\"
  . \"  \\\$civicrm_setting['domain'] = [];\\n\"
  . \"}\\n\"
  . \"\\\$civicrm_setting['domain']['userFrameworkResourceURL'] = '${RESOURCE_URL}';\\n\"
  . \"\\\$civicrm_setting['domain']['imageUploadURL'] = '${FILES_URL}';\\n\"
  . \"\\\$civicrm_setting['domain']['customCSSURL'] = '${CUSTOM_CSS_URL}';\\n\";
file_put_contents(\$file, rtrim(\$content) . \"\\n\\n\" . \$block . \"\\n\");
"

echo "==> Clearing CiviCRM template cache..."
${COMPOSE} exec -T php bash -c 'rm -rf /var/www/html/wp-content/uploads/civicrm/templates_c/* 2>/dev/null || true'

echo "==> Resetting CiviCRM config cache..."
${COMPOSE} exec -T -u www-data php cv sql "UPDATE civicrm_domain SET config_backend = NULL" 2>/dev/null || true

echo "==> Flushing CiviCRM caches..."
${COMPOSE} exec -T -u www-data php cv flush

echo "==> Rebuilding CiviCRM menus..."
${COMPOSE} exec -T -u www-data php cv ev 'CRM_Core_Invoke::rebuildMenuAndCaches();' 2>/dev/null || true

echo ""
echo "CiviCRM URLs updated."
echo "Reload CiviCRM in your browser (hard refresh). If menus are still missing, visit:"
echo "  ${BASE_URL%/}/wp-admin/admin.php?page=CiviCRM&q=civicrm/menu/rebuild&reset=1"
