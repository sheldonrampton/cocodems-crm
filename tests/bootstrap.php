<?php
/**
 * Minimal WordPress stubs for plugin unit tests.
 *
 * @package CoCoDems
 */

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', sys_get_temp_dir() . '/' );
}

/**
 * @param string          $hook Hook name.
 * @param callable|string $callback Callback.
 * @param int             $priority Priority.
 * @param int             $accepted_args Accepted argument count.
 */
function add_action( $hook, $callback, $priority = 10, $accepted_args = 1 ) { // phpcs:ignore Generic.CodeAnalysis.UnusedFunctionParameter
}

/**
 * @param string $file Plugin file path.
 * @return string
 */
function plugin_dir_path( $file ) {
	return trailingslashit( dirname( $file ) );
}

/**
 * @param string $string Path.
 * @return string
 */
function trailingslashit( $string ) {
	return rtrim( $string, '/\\' ) . '/';
}
