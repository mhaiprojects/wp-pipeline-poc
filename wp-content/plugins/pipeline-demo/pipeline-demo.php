<?php
/**
 * Plugin Name: Pipeline Demo
 * Description: Visible marker plugin for the local DDEV dev/staging/production pipeline proof of concept.
 * Version: 0.2.0
 * Author: mhaiprojects
 * License: GPL-2.0-or-later
 */

if (!defined('ABSPATH')) {
    exit;
}

define('PIPELINE_DEMO_VERSION', '0.2.0');
define('PIPELINE_DEMO_RELEASE', 'v0.2.0');

/**
 * Print a single visible banner so curl and a browser can confirm which
 * release is running on this environment.
 */
function pipeline_demo_render_marker() {
    static $done = false;
    if ($done) {
        return;
    }
    $done = true;

    $version = defined('PIPELINE_DEMO_VERSION') ? PIPELINE_DEMO_VERSION : 'unknown';
    $release = defined('PIPELINE_DEMO_RELEASE') ? PIPELINE_DEMO_RELEASE : 'unknown';
    $home    = home_url();
    $label   = sprintf(
        'PIPELINE_DEMO %s (plugin %s) on %s — wave 2 banner',
        $release,
        $version,
        $home
    );

    printf(
        '<div id="pipeline-demo-marker" data-pipeline-release="%s" data-pipeline-version="%s" style="position:relative;z-index:99999;margin:0;padding:12px 16px;background:#7a1f1f;color:#fff;font:600 16px/1.4 sans-serif;text-align:center;">%s</div>',
        esc_attr($release),
        esc_attr($version),
        esc_html($label)
    );
}
add_action('wp_body_open', 'pipeline_demo_render_marker', 1);
add_action('wp_footer', 'pipeline_demo_render_marker', 1);

/**
 * Shortcode [pipeline_demo] for wp-cli / content checks.
 */
function pipeline_demo_shortcode() {
    $version = defined('PIPELINE_DEMO_VERSION') ? PIPELINE_DEMO_VERSION : 'unknown';
    $release = defined('PIPELINE_DEMO_RELEASE') ? PIPELINE_DEMO_RELEASE : 'unknown';
    return esc_html("PIPELINE_DEMO {$release} plugin={$version}");
}
add_shortcode('pipeline_demo', 'pipeline_demo_shortcode');
