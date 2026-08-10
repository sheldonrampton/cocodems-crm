#!/usr/bin/env bash
# Apply a WordPress package produced by sync-local-wordpress-to-staging.sh.
#
# Run ON THE STAGING SERVER (or via SSM from that script):
#
#   bash scripts/apply-local-wordpress-on-staging.sh s3://BUCKET/cocodems/sync/local-wp/TIMESTAMP/
#
# Replaces WordPress tables (wp_*) and extracts plugins/themes from the package.
# Does not replace CiviCRM tables. Clears civicrm_uf_match and rewrites site URLs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
PACKAGE_URI="${1:-}"
TMP_DIR=""

cleanup() {
	if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
		rm -rf "${TMP_DIR}"
	fi
}
trap cleanup EXIT

usage() {
	cat <<'EOF'
Usage: apply-local-wordpress-on-staging.sh <s3://bucket/cocodems/sync/local-wp/TIMESTAMP/>

  Staging-only. Imports wp-tables.sql.gz and extracts wp-content.tar.gz from the
  package prefix. CiviCRM tables are left unchanged.
EOF
}

if [[ -z "${PACKAGE_URI}" || "${PACKAGE_URI}" == -h || "${PACKAGE_URI}" == --help ]]; then
	usage
	exit 0
fi

if [[ "${PACKAGE_URI}" != s3://* ]]; then
	echo "Package URI must be s3://..." >&2
	exit 1
fi
# Normalize trailing slash
PACKAGE_URI="${PACKAGE_URI%/}/"

if [[ ! -f "${ENV_FILE}" ]]; then
	echo "Missing ${ENV_FILE}" >&2
	exit 1
fi

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true
}

if ! grep -q '^SITE_DOMAIN=' "${ENV_FILE}" 2>/dev/null; then
	echo "This script must run on staging (SITE_DOMAIN required in .env)." >&2
	exit 1
fi

COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.staging.yml"
MYSQL_DATABASE="$(read_env MYSQL_DATABASE)"
MYSQL_DATABASE="${MYSQL_DATABASE:-cocodems}"
MYSQL_ROOT_PASSWORD="$(read_env MYSQL_ROOT_PASSWORD)"
BASE_URL="$(read_env CIVICRM_UF_BASEURL)"

if [[ -z "${MYSQL_ROOT_PASSWORD}" || -z "${BASE_URL}" ]]; then
	echo "Set MYSQL_ROOT_PASSWORD and CIVICRM_UF_BASEURL in ${ENV_FILE}" >&2
	exit 1
fi

# CiviCRM expects trailing slash on base URL for some paths
STAGING_BASE="${BASE_URL}"
[[ "${STAGING_BASE}" != */ ]] && STAGING_BASE="${STAGING_BASE}/"
STAGING_BASE_NOSLASH="${STAGING_BASE%/}"

if ! ${COMPOSE} exec -T mariadb true 2>/dev/null; then
	echo "MariaDB is not running on staging." >&2
	exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
	echo "aws CLI is required on staging." >&2
	exit 1
fi

mysql_root() {
	${COMPOSE} exec -T -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" mariadb \
		sh -ec 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$@"' -- "$@"
}

CIVI_LIVE_BEFORE="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.civicrm_contact WHERE is_deleted=0;" 2>/dev/null || echo "?")"
CIVI_TOTAL_BEFORE="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.civicrm_contact;" 2>/dev/null || echo "?")"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cocodems-wp-apply.XXXXXX")"
echo "==> Downloading package from ${PACKAGE_URI}..."
aws s3 cp "${PACKAGE_URI}manifest.json" "${TMP_DIR}/manifest.json"
aws s3 cp "${PACKAGE_URI}wp-tables.sql.gz" "${TMP_DIR}/wp-tables.sql.gz"
aws s3 cp "${PACKAGE_URI}wp-content.tar.gz" "${TMP_DIR}/wp-content.tar.gz"

LOCAL_BASE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("local_base_url",""))' "${TMP_DIR}/manifest.json")"
SKIP_DB_FLAG="$(python3 -c 'import json,sys; print(int(bool(json.load(open(sys.argv[1])).get("skip_db",0))))' "${TMP_DIR}/manifest.json")"
SKIP_FILES_FLAG="$(python3 -c 'import json,sys; print(int(bool(json.load(open(sys.argv[1])).get("skip_files",0))))' "${TMP_DIR}/manifest.json")"

LOCAL_BASE_NOSLASH="${LOCAL_BASE%/}"
LOCAL_BASE_SLASH="${LOCAL_BASE_NOSLASH}/"

if [[ "${SKIP_DB_FLAG}" -eq 0 ]]; then
	echo "==> Importing WordPress tables (CiviCRM tables untouched)..."
	if ! gunzip -c "${TMP_DIR}/wp-tables.sql.gz" \
		| ${COMPOSE} exec -T -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" \
			-e "MYSQL_DATABASE=${MYSQL_DATABASE}" mariadb \
			sh -ec 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'; then
		echo "Failed to import WordPress tables." >&2
		exit 1
	fi
else
	echo "==> Skipping WordPress table import (package skip_db=1)."
fi

CIVI_LIVE_AFTER="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.civicrm_contact WHERE is_deleted=0;")"
CIVI_TOTAL_AFTER="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.civicrm_contact;")"
if [[ "${CIVI_LIVE_BEFORE}" != "${CIVI_LIVE_AFTER}" || "${CIVI_TOTAL_BEFORE}" != "${CIVI_TOTAL_AFTER}" ]]; then
	echo "ERROR: CiviCRM contact counts changed after WordPress import (should be impossible):" >&2
	echo "  live:  ${CIVI_LIVE_BEFORE} -> ${CIVI_LIVE_AFTER}" >&2
	echo "  total: ${CIVI_TOTAL_BEFORE} -> ${CIVI_TOTAL_AFTER}" >&2
	exit 1
fi

if [[ "${SKIP_FILES_FLAG}" -eq 0 ]]; then
	echo "==> Extracting plugins and themes..."
	${COMPOSE} cp "${TMP_DIR}/wp-content.tar.gz" php:/tmp/cocodems-wp-content.tar.gz
	${COMPOSE} exec -T php bash -c '
set -euo pipefail
TMP=$(mktemp -d)
tar -xzf /tmp/cocodems-wp-content.tar.gz -C "$TMP"
# Archive root layout: plugins/ themes/ (never overwrites uploads/civicrm)
if [ -d "$TMP/plugins" ]; then
  mkdir -p /var/www/html/wp-content/plugins
  # Refresh non-CiviCRM plugins; keep civicrm tree on staging
  find /var/www/html/wp-content/plugins -mindepth 1 -maxdepth 1 ! -name civicrm -exec rm -rf {} +
  find "$TMP/plugins" -mindepth 1 -maxdepth 1 -exec cp -a {} /var/www/html/wp-content/plugins/ \;
fi
if [ -d "$TMP/themes" ]; then
  mkdir -p /var/www/html/wp-content/themes
  # Replace themes wholesale from local package
  find /var/www/html/wp-content/themes -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  find "$TMP/themes" -mindepth 1 -maxdepth 1 -exec cp -a {} /var/www/html/wp-content/themes/ \;
fi
chown -R www-data:www-data /var/www/html/wp-content/plugins /var/www/html/wp-content/themes
chmod -R u+rwX,g+rX,o+rX /var/www/html/wp-content/plugins /var/www/html/wp-content/themes
rm -rf "$TMP" /tmp/cocodems-wp-content.tar.gz
'
else
	echo "==> Skipping plugins/themes extract (package skip_files=1)."
fi

if [[ "${SKIP_DB_FLAG}" -eq 0 ]]; then
	echo "==> Pointing WordPress at ${STAGING_BASE_NOSLASH}..."
	${COMPOSE} exec -T php wp option update home "${STAGING_BASE_NOSLASH}" --allow-root --path=/var/www/html
	${COMPOSE} exec -T php wp option update siteurl "${STAGING_BASE_NOSLASH}" --allow-root --path=/var/www/html

	if [[ -n "${LOCAL_BASE_NOSLASH}" && "${LOCAL_BASE_NOSLASH}" != "${STAGING_BASE_NOSLASH}" ]]; then
		echo "==> search-replace ${LOCAL_BASE_NOSLASH} → ${STAGING_BASE_NOSLASH} (wp_* only)..."
		# shellcheck disable=SC2046
		${COMPOSE} exec -T php wp search-replace \
			"${LOCAL_BASE_NOSLASH}" "${STAGING_BASE_NOSLASH}" \
			$(${COMPOSE} exec -T php wp db tables --all-tables-with-prefix --format=csv --allow-root --path=/var/www/html | tr -d '\r') \
			--precise --recurse-objects --skip-columns=guid --allow-root --path=/var/www/html \
			|| true
		if [[ "${LOCAL_BASE_SLASH}" != "${LOCAL_BASE_NOSLASH}" ]]; then
			# shellcheck disable=SC2046
			${COMPOSE} exec -T php wp search-replace \
				"${LOCAL_BASE_SLASH}" "${STAGING_BASE}" \
				$(${COMPOSE} exec -T php wp db tables --all-tables-with-prefix --format=csv --allow-root --path=/var/www/html | tr -d '\r') \
				--precise --recurse-objects --skip-columns=guid --allow-root --path=/var/www/html \
				|| true
		fi
	fi

	echo "==> Clearing civicrm_uf_match so CMS users re-link to CiviCRM contacts..."
	if ! mysql_root -e "
SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE \`${MYSQL_DATABASE}\`.civicrm_uf_match;
SET FOREIGN_KEY_CHECKS=1;
"; then
		mysql_root -e "DELETE FROM \`${MYSQL_DATABASE}\`.civicrm_uf_match;"
	fi
fi

echo "==> Flushing WordPress and CiviCRM caches..."
${COMPOSE} exec -T php wp cache flush --allow-root --path=/var/www/html 2>/dev/null || true
${COMPOSE} exec -T -u www-data -e XDG_STATE_HOME=/var/www/private/.cv-state php cv flush 2>/dev/null || true
${COMPOSE} exec -T -u www-data -e XDG_STATE_HOME=/var/www/private/.cv-state php \
	cv ev 'CRM_Core_Invoke::rebuildMenuAndCaches();' 2>/dev/null || true

WP_POSTS="$(mysql_root -N -e "SELECT COUNT(*) FROM \`${MYSQL_DATABASE}\`.wp_posts;")"
echo ""
echo "Local → staging WordPress apply complete."
echo "  Staging URL:      ${STAGING_BASE_NOSLASH}"
echo "  wp_posts:         ${WP_POSTS}"
echo "  CiviCRM contacts: ${CIVI_LIVE_AFTER} live / ${CIVI_TOTAL_AFTER} total (unchanged)"
echo ""
echo "Verify: ${STAGING_BASE_NOSLASH}/wp-login.php"
echo "Log in with the WordPress users from the local dump; CiviCRM contacts stay as on staging."
