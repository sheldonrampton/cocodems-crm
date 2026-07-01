#!/usr/bin/env bash
set -euo pipefail

: "${WORDPRESS_DB_HOST:?WORDPRESS_DB_HOST is required}"
: "${WORDPRESS_DB_NAME:?WORDPRESS_DB_NAME is required}"
: "${WORDPRESS_DB_USER:?WORDPRESS_DB_USER is required}"
: "${WORDPRESS_DB_PASSWORD:?WORDPRESS_DB_PASSWORD is required}"
: "${CIVICRM_UF_BASEURL:?CIVICRM_UF_BASEURL is required}"
: "${WORDPRESS_SITE_TITLE:?WORDPRESS_SITE_TITLE is required}"
: "${CIVICRM_ADMIN_USER:?CIVICRM_ADMIN_USER is required}"
: "${CIVICRM_ADMIN_PASS:?CIVICRM_ADMIN_PASS is required}"
: "${CIVICRM_ADMIN_EMAIL:?CIVICRM_ADMIN_EMAIL is required}"
: "${CIVICRM_DB_HOST:?CIVICRM_DB_HOST is required}"
: "${CIVICRM_DB_NAME:?CIVICRM_DB_NAME is required}"
: "${CIVICRM_DB_USER:?CIVICRM_DB_USER is required}"
: "${CIVICRM_DB_PASSWORD:?CIVICRM_DB_PASSWORD is required}"

mkdir -p "$(dirname "${WORDPRESS_CONFIG_FILE}")"

wp config create \
	--path=/var/www/html \
	--dbhost="${WORDPRESS_DB_HOST}:${WORDPRESS_DB_PORT:-3306}" \
	--dbname="${WORDPRESS_DB_NAME}" \
	--dbuser="${WORDPRESS_DB_USER}" \
	--dbpass="${WORDPRESS_DB_PASSWORD}" \
	--config-file="${WORDPRESS_CONFIG_FILE}"

sed -i "/\/\* That's all, stop editing! Happy publishing\. \*\//,\$d" "${WORDPRESS_CONFIG_FILE}"

cat >> "${WORDPRESS_CONFIG_FILE}" <<EOF

define( 'WP_HOME', '${CIVICRM_UF_BASEURL}' );
define( 'WP_SITEURL', '${CIVICRM_UF_BASEURL}' );
EOF

wp core install \
	--path=/var/www/html \
	--url="${CIVICRM_UF_BASEURL}" \
	--title="${WORDPRESS_SITE_TITLE}" \
	--admin_user="${CIVICRM_ADMIN_USER}" \
	--admin_password="${CIVICRM_ADMIN_PASS}" \
	--admin_email="${CIVICRM_ADMIN_EMAIL}" \
	--skip-email

wp option update timezone_string "America/Chicago" --path=/var/www/html
wp rewrite structure '/%postname%/' --path=/var/www/html --hard

wp plugin activate civicrm --path=/var/www/html

if wp plugin is-installed cocodems-custom --path=/var/www/html; then
	wp plugin activate cocodems-custom --path=/var/www/html
fi

cd /var/www/html

cv core:install \
	--db="mysql://${CIVICRM_DB_USER}:${CIVICRM_DB_PASSWORD}@${CIVICRM_DB_HOST}:${CIVICRM_DB_PORT:-3306}/${CIVICRM_DB_NAME}" \
	--url="${CIVICRM_UF_BASEURL}" \
	-m "extras.adminUser=${CIVICRM_ADMIN_USER}" \
	-m "extras.adminPass=${CIVICRM_ADMIN_PASS}"

echo "WordPress and CiviCRM installation complete."
