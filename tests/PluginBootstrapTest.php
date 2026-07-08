<?php
/**
 * Smoke tests for the cocodems-custom plugin bootstrap.
 *
 * @package CoCoDems
 */

declare(strict_types=1);

use PHPUnit\Framework\TestCase;

/**
 * Plugin bootstrap tests.
 */
final class PluginBootstrapTest extends TestCase {

	/**
	 * Ensure the plugin defines expected constants when loaded.
	 */
	public function test_plugin_defines_constants(): void {
		require_once dirname( __DIR__ ) . '/wordpress/wp-content/plugins/cocodems-custom/cocodems-custom.php';

		self::assertSame( '0.1.0', COCODEMS_CRM_VERSION );
		self::assertSame(
			dirname( __DIR__ ) . '/wordpress/wp-content/plugins/cocodems-custom/cocodems-custom.php',
			COCODEMS_CRM_PLUGIN_FILE
		);
		self::assertStringEndsWith( '/', COCODEMS_CRM_PLUGIN_DIR );
	}
}
