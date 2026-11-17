<?php
// PH-PANEL [62]: loader for the SabreDAV libraries that ship in vendor/ (BSD-3-Clause, see vendor/*/LICENSE and VENDORED.txt).
declare(strict_types=1);

$phdavBase = __DIR__;
spl_autoload_register(static function (string $class) use ($phdavBase): void {
    static $map = [
        'Sabre\\Event\\'   => 'vendor/event/lib/',
        'Sabre\\Xml\\'     => 'vendor/xml/lib/',
        'Sabre\\HTTP\\'    => 'vendor/http/lib/',
        'Sabre\\Uri\\'     => 'vendor/uri/lib/',
        'Sabre\\VObject\\' => 'vendor/vobject/lib/',
        'Psr\\Log\\'       => 'vendor/log/src/',
        'PhDav\\'          => 'lib/',
        'Sabre\\'          => 'vendor/dav-lib/',
    ];
    foreach ($map as $prefix => $dir) {
        if (strncmp($class, $prefix, strlen($prefix)) === 0) {
            $file = $phdavBase . '/' . $dir . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
            if (is_file($file)) {
                require $file;
            }
            return;
        }
    }
});

foreach ([
    'vendor/event/lib/coroutine.php', 'vendor/event/lib/Loop/functions.php', 'vendor/event/lib/Promise/functions.php',
    'vendor/xml/lib/Deserializer/functions.php', 'vendor/xml/lib/Serializer/functions.php',
    'vendor/http/lib/functions.php', 'vendor/uri/lib/functions.php',
] as $f) {
    require_once $phdavBase . '/' . $f;
}
