<?php
/**
 * WordPress bootstrap config.
 *
 * Database credentials live in WORDPRESS_CONFIG_FILE (default: /var/www/private/wp-config.php).
 * This file must remain in the web root so WordPress can locate it.
 */
$configFile = getenv( 'WORDPRESS_CONFIG_FILE' );
if ( $configFile && file_exists( $configFile ) ) {
	include_once $configFile;
} else {
	die( 'WordPress config file not found!' );
}

/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
