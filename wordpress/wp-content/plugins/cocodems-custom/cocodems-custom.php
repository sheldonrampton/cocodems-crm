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
	add_action( 'admin_head', 'cocodems_civicrm_admin_ui_fixes', 100 );
}

/**
 * CSS fixes for CiviCRM screens embedded in wp-admin.
 *
 * Resolves WordPress Access Control checkboxes that appear but do not toggle,
 * usually due to admin theme/plugin CSS (appearance: none) or invisible overlays.
 */
function cocodems_civicrm_admin_ui_fixes(): void {
	// phpcs:ignore WordPress.Security.NonceVerification.Recommended -- Read-only admin screen routing.
	$page = isset( $_GET['page'] ) ? sanitize_text_field( wp_unslash( $_GET['page'] ) ) : '';
	if ( 'CiviCRM' !== $page ) {
		return;
	}

	echo '<style>
		#wpbody-content .crm-container input[type="checkbox"],
		#wpbody-content .crm-container input[type="radio"] {
			pointer-events: auto !important;
			position: relative;
			z-index: 2;
			opacity: 1 !important;
			appearance: auto !important;
			-webkit-appearance: checkbox !important;
		}
		#wpbody-content .blockUI.blockOverlay {
			display: none !important;
		}
	</style>';
}

add_action( 'plugins_loaded', 'cocodems_custom_bootstrap' );
