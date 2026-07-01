<?php
/**
 * CoCoDems theme functions.
 *
 * @package CoCoDems
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

add_action(
	'after_setup_theme',
	static function (): void {
		add_theme_support( 'title-tag' );
	}
);
