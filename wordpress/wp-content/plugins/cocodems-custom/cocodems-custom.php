<?php
/**
 * Plugin Name:       CoCoDems Custom
 * Plugin URI:        https://github.com/cocodems/cocodems-crm
 * Description:       Custom functionality for the CoCoDems CRM platform.
 * Version:           0.1.0
 * Requires at least: 6.0
 * Requires PHP:      8.1
 * Author:            Columbia County Democrats
 * License:           GPL-2.0-or-later
 * Text Domain:       cocodems-custom
 *
 * @package CoCoDems
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'COCODEMS_CRM_VERSION', '0.1.0' );
define( 'COCODEMS_CRM_PLUGIN_FILE', __FILE__ );
define( 'COCODEMS_CRM_PLUGIN_DIR', plugin_dir_path( __FILE__ ) );

/**
 * Plugin bootstrap.
 */
function cocodems_custom_bootstrap(): void {
	// Custom hooks and integrations will be registered here.
}

add_action( 'plugins_loaded', 'cocodems_custom_bootstrap' );
