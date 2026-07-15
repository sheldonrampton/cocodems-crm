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

CIVICRM_ROOT_PATH="/var/www/html/wp-content/plugins/civicrm/civicrm/"
CIVICRM_FILES_PATH="/var/www/html/wp-content/uploads/civicrm/"

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

if [[ -f "${REPO_ROOT}/docker/docker-compose.staging.yml" ]] \
	&& grep -q '^SITE_DOMAIN=' "${ENV_FILE}" 2>/dev/null; then
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.staging.yml"
else
	COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.local.yml"
fi

if ! ${COMPOSE} exec -T php test -f "${CIVI_SETTINGS}" 2>/dev/null; then
	echo "CiviCRM settings not found at ${CIVI_SETTINGS}. Run deploy first." >&2
	exit 1
fi

echo "==> Ensuring CiviCRM upload directories are writable..."
${COMPOSE} exec -T php bash -c "
mkdir -p '${CIVICRM_FILES_PATH}'{persist/contribute/dyn,ext,templates_c,upload,css,ConfigAndLog,custom,custom_templates,custom_php}
chown -R www-data:www-data '${CIVICRM_FILES_PATH}'
chmod -R 775 '${CIVICRM_FILES_PATH}'
"

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
  . \"global \\\$civicrm_paths;\\n\"
  . \"\\\$civicrm_paths['civicrm.root'] = [\\n\"
  . \"  'path' => '${CIVICRM_ROOT_PATH}',\\n\"
  . \"  'url' => '${RESOURCE_URL}',\\n\"
  . \"];\\n\"
  . \"\\\$civicrm_paths['civicrm.files'] = [\\n\"
  . \"  'path' => '${CIVICRM_FILES_PATH}',\\n\"
  . \"  'url' => '${FILES_URL}',\\n\"
  . \"];\\n\"
  . \"if (!isset(\\\$civicrm_setting['domain'])) {\\n\"
  . \"  \\\$civicrm_setting['domain'] = [];\\n\"
  . \"}\\n\"
  . \"\\\$civicrm_setting['domain']['uploadDir'] = '[civicrm.files]/upload/';\\n\"
  . \"\\\$civicrm_setting['domain']['imageUploadDir'] = '[civicrm.files]/persist/contribute/';\\n\"
  . \"\\\$civicrm_setting['domain']['customFileUploadDir'] = '[civicrm.files]/custom/';\\n\"
  . \"\\\$civicrm_setting['domain']['customTemplateDir'] = '[civicrm.files]/custom_templates/';\\n\"
  . \"\\\$civicrm_setting['domain']['customPHPPathDir'] = '[civicrm.files]/custom_php/';\\n\"
  . \"\\\$civicrm_setting['domain']['extensionsDir'] = '[civicrm.files]/ext/';\\n\"
  . \"\\\$civicrm_setting['domain']['userFrameworkResourceURL'] = '[civicrm.root]/';\\n\"
  . \"\\\$civicrm_setting['domain']['imageUploadURL'] = '[civicrm.files]/persist/contribute/';\\n\"
  . \"\\\$civicrm_setting['domain']['extensionsURL'] = '[civicrm.files]/ext/';\\n\"
  . \"unset(\\\$civicrm_setting['domain']['customCSSURL']);\\n\";
file_put_contents(\$file, rtrim(\$content) . \"\\n\\n\" . \$block . \"\\n\");
"

echo "==> Clearing CiviCRM template cache..."
${COMPOSE} exec -T php bash -c 'rm -rf /var/www/html/wp-content/uploads/civicrm/templates_c/* 2>/dev/null || true'

echo "==> Resetting CiviCRM config cache..."
${COMPOSE} exec -T -u www-data php cv sql -e "UPDATE civicrm_domain SET config_backend = NULL" 2>/dev/null || true

echo "==> Flushing CiviCRM caches..."
${COMPOSE} exec -T -u www-data php cv flush

echo "==> Rebuilding CiviCRM menus..."
${COMPOSE} exec -T -u www-data php cv ev 'CRM_Core_Invoke::rebuildMenuAndCaches();' 2>/dev/null || true

echo ""
echo "CiviCRM URLs updated."
echo "Run: bash scripts/diagnose-civicrm-urls.sh"
echo "Then hard-refresh CiviCRM in your browser."
echo "If menus are still missing, visit:"
echo "  ${BASE_URL%/}/wp-admin/admin.php?page=CiviCRM&q=civicrm/menu/rebuild&reset=1"
