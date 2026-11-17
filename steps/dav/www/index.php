<?php
// PH-PANEL [62]: the only entry of the calendar and contact server.
declare(strict_types=1);
error_reporting(E_ALL & ~E_DEPRECATED & ~E_STRICT);
require __DIR__ . '/../autoload.php';
require __DIR__ . '/../lib/Dav.php';
if (getenv('PHPANEL_DAV_HEALTH') === '1') { // the idle pool that only answers the health check
    header('Content-Type: text/plain');
    echo 'ok sabre ' . \Sabre\DAV\Version::VERSION . ' php ' . PHP_VERSION . "\n";
    exit;
}
$account = (string) getenv('PHPANEL_DAV_ACCOUNT');
$db = (string) getenv('PHPANEL_DAV_DB');
if ($account === '' || $db === '') {
    http_response_code(404);
    exit;
}
try {
    \PhDav\App::serve($account, $db);
} catch (\Throwable $e) {
    error_log('dav: ' . get_class($e) . ' ' . $e->getMessage());
    if (!headers_sent()) {
        http_response_code(500);
    }
}
