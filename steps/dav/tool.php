<?php
// PH-PANEL [62]: management of calendars and contacts, run by phpanel-root as the hosting account.
// Input: first line is JSON {"op":..., "db":..., ...}; the rest of stdin is the file for an import. Output: one JSON line.
declare(strict_types=1);
error_reporting(E_ALL & ~E_DEPRECATED & ~E_STRICT);
ini_set('display_errors', '0');
require __DIR__ . '/autoload.php';
require __DIR__ . '/lib/Dav.php';

use PhDav\Store;
use Sabre\CalDAV;
use Sabre\VObject;

function out(array $v): never
{
    echo json_encode($v, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE), "\n";
    exit($v['ok'] ?? false ? 0 : 1);
}

function fail(string $m): never
{
    out(['ok' => false, 'error' => $m]);
}

function slug(string $name): string
{
    $s = strtolower(trim((string) preg_replace('/[^A-Za-z0-9]+/', '-', $name), '-'));
    return $s === '' ? 'collection' : substr($s, 0, 40);
}

function principal(string $u): string
{
    if (!preg_match(PhDav\USER_RE, $u)) {
        fail('invalid mailbox');
    }
    return 'principals/' . $u;
}

$in = fgets(STDIN);
$a = is_string($in) ? json_decode($in, true) : null;
if (!is_array($a) || !isset($a['op'], $a['db']) || !is_string($a['db']) || $a['db'] === '' || $a['db'][0] !== '/') {
    fail('bad request');
}
$op = (string) $a['op'];
$dbPath = $a['db'];
$payload = '';
if ($op === 'import') {
    $payload = stream_get_contents(STDIN, 26 * 1024 * 1024 + 1);
    if (strlen((string) $payload) > 26 * 1024 * 1024) {
        fail('The file is too large (the limit is 25 MB).');
    }
}

try {
    if ($op === 'selftest') {
        out(['ok' => true, 'sabre' => \Sabre\DAV\Version::VERSION, 'php' => PHP_VERSION, 'sqlite' => in_array('sqlite', PDO::getAvailableDrivers(), true)]);
    }
    if ($op === 'stats') {
        $s = 0;
        foreach (['', '-wal', '-shm'] as $x) {
            $s += is_file($dbPath . $x) ? (int) filesize($dbPath . $x) : 0;
        }
        out(['ok' => true, 'bytes' => $s, 'exists' => is_file($dbPath)]);
    }
    if ($op === 'backup') { // a consistent copy for the backup, written inside the data folder; the helper reads it from there
        if (!is_file($dbPath)) {
            out(['ok' => true, 'skipped' => true]);
        }
        $to = dirname($dbPath) . '/tmp/backup.sqlite';
        @unlink($to);
        $pdo = Store::open($dbPath, false);
        $pdo->exec('VACUUM INTO ' . $pdo->quote($to));
        @chmod($to, 0600);
        out(['ok' => true, 'file' => $to]);
    }
    if ($op === 'restore') { // the saved copy arrives on standard input after the first line
        $from = dirname($dbPath) . '/tmp/restore-in.sqlite';
        $o = fopen($from, 'wb');
        if (!$o || stream_copy_to_stream(STDIN, $o) === false) {
            fail('The saved copy could not be read.');
        }
        fclose($o);
        $chk = new PDO('sqlite:' . $from);
        if ($chk->query('PRAGMA integrity_check')->fetchColumn() !== 'ok' || !$chk->query("SELECT 1 FROM sqlite_master WHERE name='calendarobjects'")->fetchColumn()) {
            unset($chk);
            @unlink($from);
            fail('The saved copy is not a calendar and contact file.');
        }
        unset($chk);
        $flag = dirname($dbPath) . '/maintenance';
        touch($flag);
        sleep(2);
        $tmp = $dbPath . '.restore';
        if (!copy($from, $tmp)) {
            @unlink($from);
            @unlink($flag);
            fail('The copy could not be written (is the disk full?).');
        }
        @chmod($tmp, 0600);
        @unlink($dbPath . '-wal');
        @unlink($dbPath . '-shm');
        rename($tmp, $dbPath);
        @unlink($from);
        @unlink($flag);
        out(['ok' => true]);
    }

    $pdo = Store::open($dbPath, $op === 'provision');
    switch ($op) {
        case 'provision':
            foreach ((array) ($a['users'] ?? []) as $u) {
                Store::provision($pdo, (string) $u);
            }
            out(['ok' => true]);

        case 'list':
            $me = principal((string) $a['user']);
            $cal = new CalDAV\Backend\PDO($pdo);
            $books = new PhDav\Book($pdo);
            $cs = [];
            foreach ($cal->getCalendarsForUser($me) as $c) {
                $id = $c['id'];
                $n = $pdo->prepare('SELECT COUNT(*) FROM calendarobjects WHERE calendarid=?');
                $n->execute([$id[0]]);
                $o = $pdo->prepare('SELECT principaluri FROM calendarinstances WHERE calendarid=? AND access=1 LIMIT 1');
                $o->execute([$id[0]]);
                $own = (string) ($o->fetchColumn() ?: $me);
                $row = ['uri' => $c['uri'], 'name' => (string) ($c['{DAV:}displayname'] ?? $c['uri']), 'items' => (int) $n->fetchColumn(),
                    'owner' => preg_replace('#^principals/#', '', $own), 'mine' => $own === $me, 'access' => ((int) ($c['share-access'] ?? 1)) === 3 ? 'write' : (((int) ($c['share-access'] ?? 1)) === 2 ? 'read' : 'owner'), 'shared_with' => []];
                if ($row['mine']) {
                    $s = $pdo->prepare('SELECT principaluri,access FROM calendarinstances WHERE calendarid=? AND access IN (2,3)');
                    $s->execute([$id[0]]);
                    foreach ($s->fetchAll() as $r) {
                        $row['shared_with'][] = ['user' => preg_replace('#^principals/#', '', $r['principaluri']), 'access' => (int) $r['access'] === 3 ? 'write' : 'read'];
                    }
                }
                $cs[] = $row;
            }
            $bs = [];
            foreach ($books->getAddressBooksForUser($me) as $b) {
                $n = $pdo->prepare('SELECT COUNT(*) FROM cards WHERE addressbookid=?');
                $n->execute([$b['id']]);
                $own = (string) ($b['{http://sabredav.org/ns}owner-principal'] ?? $me);
                $row = ['uri' => $b['uri'], 'name' => (string) ($b['{DAV:}displayname'] ?? $b['uri']), 'items' => (int) $n->fetchColumn(),
                    'owner' => preg_replace('#^principals/#', '', $own), 'mine' => $own === $me,
                    'access' => $own === $me ? 'owner' : (!empty($b['{http://sabredav.org/ns}read-only']) ? 'read' : 'write'), 'shared_with' => []];
                if ($row['mine']) {
                    $s = $pdo->prepare('SELECT principaluri,access FROM addressbook_shares WHERE addressbookid=?');
                    $s->execute([$b['id']]);
                    foreach ($s->fetchAll() as $r) {
                        $row['shared_with'][] = ['user' => preg_replace('#^principals/#', '', $r['principaluri']), 'access' => (int) $r['access'] === 3 ? 'write' : 'read'];
                    }
                }
                $bs[] = $row;
            }
            out(['ok' => true, 'calendars' => $cs, 'books' => $bs]);

        case 'create':
            $me = principal((string) $a['user']);
            $name = trim((string) ($a['name'] ?? ''));
            if ($name === '' || mb_strlen($name) > 80) {
                fail('Give the name 1 to 80 characters.');
            }
            Store::provision($pdo, (string) $a['user']);
            $kind = (string) ($a['kind'] ?? '');
            $uri = slug($name);
            $q = $pdo->prepare($kind === 'book' ? 'SELECT COUNT(*) FROM addressbooks WHERE principaluri=?' : 'SELECT COUNT(*) FROM calendarinstances WHERE principaluri=? AND access=1');
            $q->execute([$me]);
            if ((int) $q->fetchColumn() >= 50) {
                fail('A mailbox can have up to 50 of these.');
            }
            for ($i = 0; $i < 20; $i++) {
                $u = $i === 0 ? $uri : $uri . '-' . ($i + 1);
                $ex = $pdo->prepare($kind === 'book' ? 'SELECT 1 FROM addressbooks WHERE principaluri=? AND uri=?' : 'SELECT 1 FROM calendarinstances WHERE principaluri=? AND uri=?');
                $ex->execute([$me, $u]);
                if (!$ex->fetchColumn()) {
                    break;
                }
            }
            if ($kind === 'book') {
                (new PhDav\Book($pdo))->createAddressBook($me, $u, ['{DAV:}displayname' => $name]);
            } elseif ($kind === 'calendar') {
                (new CalDAV\Backend\PDO($pdo))->createCalendar($me, $u, ['{DAV:}displayname' => $name,
                    '{urn:ietf:params:xml:ns:caldav}supported-calendar-component-set' => new CalDAV\Xml\Property\SupportedCalendarComponentSet(['VEVENT', 'VTODO'])]);
            } else {
                fail('bad kind');
            }
            out(['ok' => true, 'uri' => $u]);

        case 'rename':
        case 'delete':
        case 'share':
        case 'unshare':
        case 'import':
        case 'export':
            $me = principal((string) $a['user']);
            $kind = (string) ($a['kind'] ?? '');
            $uri = (string) ($a['uri'] ?? '');
            if (!in_array($kind, ['calendar', 'book'], true) || !preg_match('/^[A-Za-z0-9._-]{1,80}$/', $uri)) {
                fail('bad collection');
            }
            $col = null;
            if ($kind === 'calendar') {
                $s = $pdo->prepare('SELECT id,calendarid,access FROM calendarinstances WHERE principaluri=? AND uri=?');
                $s->execute([$me, $uri]);
                $r = $s->fetch();
                if ($r) {
                    $col = ['id' => (int) $r['calendarid'], 'inst' => (int) $r['id'], 'access' => (int) $r['access']];
                }
            } else {
                $own = $pdo->prepare('SELECT id FROM addressbooks WHERE principaluri=? AND uri=?');
                $own->execute([$me, $uri]);
                if ($r = $own->fetch()) {
                    $col = ['id' => (int) $r['id'], 'access' => 1];
                } elseif (preg_match('/^shared-(\d+)$/', $uri, $m)) {
                    $sh = $pdo->prepare('SELECT access FROM addressbook_shares WHERE addressbookid=? AND principaluri=?');
                    $sh->execute([(int) $m[1], $me]);
                    if ($r = $sh->fetch()) {
                        $col = ['id' => (int) $m[1], 'access' => (int) $r['access']];
                    }
                }
            }
            if ($col === null) {
                fail('That calendar or address book was not found.');
            }
            $owner = $col['access'] === 1;
            $writable = $owner || $col['access'] === 3;
            switch ($op) {
                case 'rename':
                    if (!$owner) {
                        fail('Only the owner can rename it.');
                    }
                    $name = trim((string) ($a['name'] ?? ''));
                    if ($name === '' || mb_strlen($name) > 80) {
                        fail('Give the name 1 to 80 characters.');
                    }
                    if ($kind === 'calendar') {
                        $pdo->prepare('UPDATE calendarinstances SET displayname=? WHERE id=?')->execute([$name, $col['inst']]);
                    } else {
                        $pdo->prepare('UPDATE addressbooks SET displayname=? WHERE id=?')->execute([$name, $col['id']]);
                    }
                    out(['ok' => true]);
                case 'delete':
                    if ($owner) {
                        if ($kind === 'calendar') {
                            (new CalDAV\Backend\PDO($pdo))->deleteCalendar([$col['id'], $col['inst']]);
                        } else {
                            (new PhDav\Book($pdo))->deleteAddressBook($col['id']);
                        }
                    } elseif ($kind === 'calendar') {
                        $pdo->prepare('DELETE FROM calendarinstances WHERE id=?')->execute([$col['inst']]);
                    } else {
                        (new PhDav\Book($pdo))->unshare($me, $col['id']);
                    }
                    out(['ok' => true]);
                case 'share':
                case 'unshare':
                    if (!$owner) {
                        fail('Only the owner can share it.');
                    }
                    $with = principal((string) ($a['with'] ?? ''));
                    if ($with === $me) {
                        fail('It already belongs to that mailbox.');
                    }
                    $acc = ($a['access'] ?? 'read') === 'write' ? 3 : 2;
                    if ($op === 'unshare') {
                        if ($kind === 'calendar') {
                            $pdo->prepare('DELETE FROM calendarinstances WHERE calendarid=? AND principaluri=? AND access IN (2,3)')->execute([$col['id'], $with]);
                        } else {
                            (new PhDav\Book($pdo))->unshare($with, $col['id']);
                        }
                        out(['ok' => true]);
                    }
                    Store::provision($pdo, (string) $a['with']);
                    if ($kind === 'calendar') {
                        $ex = $pdo->prepare('SELECT id FROM calendarinstances WHERE calendarid=? AND principaluri=?');
                        $ex->execute([$col['id'], $with]);
                        if ($e = $ex->fetch()) {
                            $pdo->prepare('UPDATE calendarinstances SET access=? WHERE id=?')->execute([$acc, $e['id']]);
                        } else {
                            $src = $pdo->prepare('SELECT displayname,description,calendarorder,calendarcolor,timezone,transparent FROM calendarinstances WHERE id=?');
                            $src->execute([$col['inst']]);
                            $c = $src->fetch();
                            $pdo->prepare('INSERT INTO calendarinstances (calendarid,principaluri,access,displayname,uri,description,calendarorder,calendarcolor,timezone,transparent,share_href,share_displayname,share_invitestatus) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,2)')
                                ->execute([$col['id'], $with, $acc, $c['displayname'], 'shared-' . $col['id'], $c['description'], $c['calendarorder'], $c['calendarcolor'], $c['timezone'], $c['transparent'], 'mailto:' . substr($with, 11), substr($with, 11)]);
                        }
                    } else {
                        $pdo->prepare('INSERT INTO addressbook_shares (addressbookid,principaluri,access) VALUES (?,?,?) ON CONFLICT(addressbookid,principaluri) DO UPDATE SET access=excluded.access')->execute([$col['id'], $with, $acc]);
                    }
                    out(['ok' => true]);
                case 'export':
                    if ($kind === 'calendar') {
                        $s = $pdo->prepare('SELECT calendardata FROM calendarobjects WHERE calendarid=? ORDER BY id');
                        $s->execute([$col['id']]);
                        $cal = new VObject\Component\VCalendar();
                        $tz = [];
                        foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $d) {
                            try {
                                $v = VObject\Reader::read(is_resource($d) ? stream_get_contents($d) : (string) $d);
                            } catch (\Throwable) {
                                continue;
                            }
                            foreach ($v->getComponents() as $c) {
                                if ($c->name === 'VTIMEZONE') {
                                    $id = (string) ($c->TZID ?? '');
                                    if (isset($tz[$id])) {
                                        continue;
                                    }
                                    $tz[$id] = true;
                                }
                                $cal->add(clone $c);
                            }
                        }
                        $text = $cal->serialize();
                    } else {
                        $s = $pdo->prepare('SELECT carddata FROM cards WHERE addressbookid=? ORDER BY id');
                        $s->execute([$col['id']]);
                        $text = '';
                        foreach ($s->fetchAll(PDO::FETCH_COLUMN) as $d) {
                            $d = is_resource($d) ? stream_get_contents($d) : (string) $d;
                            $text .= rtrim($d) . "\r\n";
                        }
                    }
                    out(['ok' => true, 'data' => base64_encode($text)]);
                case 'import':
                    if (!$writable) {
                        fail('You can only read this one, not add to it.');
                    }
                    $done = ['added' => 0, 'updated' => 0, 'skipped' => 0];
                    $backend = $kind === 'calendar' ? new CalDAV\Backend\PDO($pdo) : new PhDav\Book($pdo);
                    $objs = [];
                    $input = (string) $payload;
                    if (str_starts_with($input, "\xEF\xBB\xBF")) {
                        $input = substr($input, 3);
                    }
                    try {
                        $sp = $kind === 'calendar' ? new VObject\Splitter\ICalendar($input) : new VObject\Splitter\VCard($input);
                        while ($v = $sp->getNext()) {
                            $objs[] = $v;
                        }
                    } catch (\Throwable $e) {
                        fail('That file does not look like ' . ($kind === 'calendar' ? 'a calendar (.ics)' : 'contacts (.vcf)') . '.');
                    }
                    if (count($objs) > 20000) {
                        fail('The file has more than 20,000 entries; split it first.');
                    }
                    foreach ($objs as $v) {
                        try {
                            $v->validate(VObject\Node::REPAIR);
                            if ($kind === 'calendar') {
                                $uid = (string) ($v->getBaseComponent()->UID ?? '');
                            } else {
                                $uid = (string) ($v->UID ?? '');
                                if ($uid === '') {
                                    $uid = VObject\UUIDUtil::getUUID();
                                    $v->UID = $uid;
                                }
                            }
                            if ($uid === '') {
                                $done['skipped']++;
                                continue;
                            }
                            $name = preg_replace('/[^A-Za-z0-9._@-]+/', '-', $uid) . ($kind === 'calendar' ? '.ics' : '.vcf');
                            $name = substr($name, -120);
                            $data = $v->serialize();
                            if ($kind === 'calendar') {
                                $ex = $backend->getCalendarObject([$col['id'], $col['inst']], $name);
                                if ($ex) {
                                    $backend->updateCalendarObject([$col['id'], $col['inst']], $name, $data);
                                    $done['updated']++;
                                } else {
                                    $backend->createCalendarObject([$col['id'], $col['inst']], $name, $data);
                                    $done['added']++;
                                }
                            } else {
                                $ex = $backend->getCard($col['id'], $name);
                                if ($ex) {
                                    $backend->updateCard($col['id'], $name, $data);
                                    $done['updated']++;
                                } else {
                                    $backend->createCard($col['id'], $name, $data);
                                    $done['added']++;
                                }
                            }
                        } catch (\Throwable $e) {
                            $done['skipped']++;
                        }
                    }
                    out(['ok' => true] + $done);
            }
            break;

        case 'drop':
            $me = principal((string) $a['user']);
            $cal = new CalDAV\Backend\PDO($pdo);
            $books = new PhDav\Book($pdo);
            $pdo->exec('BEGIN');
            foreach ($cal->getCalendarsForUser($me) as $c) {
                if (($c['share-access'] ?? 1) <= 1) {
                    $cal->deleteCalendar($c['id']);
                }
            }
            $pdo->prepare('DELETE FROM calendarinstances WHERE principaluri=?')->execute([$me]);
            foreach ($books->getAddressBooksForUser($me) as $b) {
                if (empty($b['phdav-shared'])) {
                    $books->deleteAddressBook($b['id']);
                }
            }
            $pdo->prepare('DELETE FROM addressbook_shares WHERE principaluri=?')->execute([$me]);
            $pdo->prepare('DELETE FROM principals WHERE uri=?')->execute([$me]);
            $pdo->prepare("DELETE FROM propertystorage WHERE path LIKE ? ESCAPE '\\'")->execute(['%' . addcslashes($a['user'], '%_\\') . '%']);
            $pdo->prepare('DELETE FROM ph_meta WHERE k IN (?,?)')->execute(['c:' . $a['user'], 'b:' . $a['user']]);
            $pdo->exec('COMMIT');
            out(['ok' => true]);
    }
    fail('unknown operation');
} catch (\Throwable $e) {
    fail('The operation failed: ' . $e->getMessage());
}
