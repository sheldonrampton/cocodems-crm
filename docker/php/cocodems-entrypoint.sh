#!/usr/bin/env bash
set -euo pipefail

source_wordpress() {
	if [ ! -f /var/www/html/index.php ]; then
		echo "Copying WordPress files into /var/www/html..."
		cp -a /usr/src/wordpress/. /var/www/html/
		chown -R www-data:www-data /var/www/html
	fi
}

wait_for_database() {
	local host="${WORDPRESS_DB_HOST:-mariadb}"
	local port="${WORDPRESS_DB_PORT:-3306}"
	local user="${WORDPRESS_DB_USER:-wordpress}"
	local password="${WORDPRESS_DB_PASSWORD:-wordpress}"
	local max_attempts=60
	local attempt=1

	echo "Waiting for MariaDB at ${host}:${port}..."
	while [ "${attempt}" -le "${max_attempts}" ]; do
		if mysqladmin ping -h "${host}" -P "${port}" -u "${user}" -p"${password}" --skip-ssl --silent 2>/dev/null; then
			echo "MariaDB is ready."
			return 0
		fi
		echo "MariaDB not ready yet (attempt ${attempt}/${max_attempts})..."
		sleep 2
		attempt=$((attempt + 1))
	done

	echo "Timed out waiting for MariaDB." >&2
	exit 1
}

maybe_install_site() {
	if [ -f "${WORDPRESS_CONFIG_FILE:-/var/www/private/wp-config.php}" ]; then
		return 0
	fi

	echo "Running first-time WordPress + CiviCRM installation..."
	gosu www-data install-site.sh
}

ensure_cv_state_dir() {
	mkdir -p /var/www/private/.cv-state
	chown -R www-data:www-data /var/www/private/.cv-state
}

source_wordpress
ensure_cv_state_dir
wait_for_database
maybe_install_site

exec /usr/local/bin/docker-entrypoint.sh "$@"
