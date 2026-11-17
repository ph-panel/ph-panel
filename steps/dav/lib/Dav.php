<?php
// PH-PANEL [62]: calendars and contacts. One SQLite file per hosting account holds the data of all its mailboxes; the pool runs as
// the account, so the file is owned by it and counts in its disk quota.
declare(strict_types=1);

namespace PhDav;

use PDO;
use Sabre\CalDAV;
use Sabre\CardDAV;
use Sabre\DAV;
use Sabre\DAVACL;

const USER_RE = '/^[a-z0-9]([a-z0-9._+-]{0,62}[a-z0-9])?@[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?\.[a-z]{2,63}$/';

final class Store
{
    public static function open(string $path, bool $create = true): PDO
    {
        $dir = dirname($path);
        if (!is_dir($dir)) {
            throw new \RuntimeException('data folder missing');
        }
        $new = !is_file($path);
        if ($new && !$create) {
            throw new \RuntimeException('no data yet');
        }
        $pdo = new PDO('sqlite:' . $path, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]);
        $pdo->exec('PRAGMA busy_timeout=8000');
        $pdo->exec('PRAGMA journal_mode=WAL');
        $pdo->exec('PRAGMA synchronous=NORMAL');
        $pdo->exec('PRAGMA foreign_keys=ON');
        $pdo->exec('PRAGMA trusted_schema=OFF');
        $has = $pdo->query("SELECT 1 FROM sqlite_master WHERE type='table' AND name='calendars'")->fetchColumn();
        if (!$has) {
            $pdo->exec('BEGIN IMMEDIATE');
            $has = $pdo->query("SELECT 1 FROM sqlite_master WHERE type='table' AND name='calendars'")->fetchColumn();
            if (!$has) {
                $pdo->exec((string) file_get_contents(__DIR__ . '/../schema.sql'));
            }
            $pdo->exec('COMMIT');
        }
        @chmod($path, 0600);
        return $pdo;
    }

    /** Makes the principal of a mailbox with a first calendar and address book; safe to repeat. */
    public static function provision(PDO $pdo, string $user): void
    {
        if (!preg_match(USER_RE, $user)) {
            throw new \InvalidArgumentException('bad user');
        }
        $uri = 'principals/' . $user;
        $st = $pdo->prepare('INSERT OR IGNORE INTO principals (uri,email,displayname) VALUES (?,?,?)');
        $st->execute([$uri, $user, $user]);
        $cal = new CalDAV\Backend\PDO($pdo);
        $books = new Book($pdo);
        $has = $pdo->prepare('SELECT COUNT(*) FROM calendarinstances WHERE principaluri=? AND access=1');
        $has->execute([$uri]);
        if ((int) $has->fetchColumn() === 0 && !self::everHad($pdo, 'c:' . $user)) {
            $cal->createCalendar($uri, 'default', ['{DAV:}displayname' => 'Personal',
                '{urn:ietf:params:xml:ns:caldav}supported-calendar-component-set' => new CalDAV\Xml\Property\SupportedCalendarComponentSet(['VEVENT', 'VTODO'])]);
            self::mark($pdo, 'c:' . $user);
        }
        $hb = $pdo->prepare('SELECT COUNT(*) FROM addressbooks WHERE principaluri=?');
        $hb->execute([$uri]);
        if ((int) $hb->fetchColumn() === 0 && !self::everHad($pdo, 'b:' . $user)) {
            $books->createAddressBook($uri, 'default', ['{DAV:}displayname' => 'Contacts']);
            self::mark($pdo, 'b:' . $user);
        }
    }

    // a person who deleted the starter collection does not get it back at every sign-in
    private static function everHad(PDO $pdo, string $k): bool
    {
        $s = $pdo->prepare('SELECT 1 FROM ph_meta WHERE k=?');
        $s->execute([$k]);
        return (bool) $s->fetchColumn();
    }

    private static function mark(PDO $pdo, string $k): void
    {
        $pdo->prepare('INSERT OR IGNORE INTO ph_meta (k,v) VALUES (?,?)')->execute([$k, '1']);
    }
}

/** Address book backend with sharing between the mailboxes of the account. */
class Book extends CardDAV\Backend\PDO
{
    private PDO $db;

    public function __construct(PDO $pdo)
    {
        parent::__construct($pdo);
        $this->db = $pdo;
    }

    public function getAddressBooksForUser($principalUri)
    {
        $out = parent::getAddressBooksForUser($principalUri);
        $st = $this->db->prepare('SELECT a.id,a.uri,a.displayname,a.description,a.synctoken,a.principaluri AS owner,s.access FROM addressbook_shares s JOIN addressbooks a ON a.id=s.addressbookid WHERE s.principaluri=?');
        $st->execute([$principalUri]);
        foreach ($st->fetchAll() as $r) {
            $out[] = [
                'id' => $r['id'],
                'uri' => 'shared-' . $r['id'],
                'principaluri' => $principalUri,
                '{DAV:}displayname' => ($r['displayname'] ?? $r['uri']) . ' (' . preg_replace('#^principals/#', '', (string) $r['owner']) . ')',
                '{' . CardDAV\Plugin::NS_CARDDAV . '}addressbook-description' => $r['description'],
                '{http://calendarserver.org/ns/}getctag' => $r['synctoken'],
                '{http://sabredav.org/ns}sync-token' => $r['synctoken'] ?: '0',
                '{http://sabredav.org/ns}owner-principal' => $r['owner'],
                '{http://sabredav.org/ns}read-only' => (int) $r['access'] < 3,
                'phdav-shared' => true,
            ];
        }
        return $out;
    }

    public function unshare(string $principalUri, $bookId): void
    {
        $this->db->prepare('DELETE FROM addressbook_shares WHERE addressbookid=? AND principaluri=?')->execute([$bookId, $principalUri]);
    }

    public function deleteAddressBook($addressBookId)
    {
        $this->db->prepare('DELETE FROM addressbook_shares WHERE addressbookid=?')->execute([$addressBookId]);
        parent::deleteAddressBook($addressBookId);
    }
}

class SharedAddressBook extends CardDAV\AddressBook
{
    private function ro(): bool
    {
        return !empty($this->addressBookInfo['{http://sabredav.org/ns}read-only']);
    }

    private function shared(): bool
    {
        return !empty($this->addressBookInfo['phdav-shared']);
    }

    public function getACL()
    {
        $p = $this->addressBookInfo['principaluri'];
        if ($this->ro()) {
            return [['privilege' => '{DAV:}read', 'principal' => $p, 'protected' => true]];
        }
        return [['privilege' => '{DAV:}all', 'principal' => $p, 'protected' => true]];
    }

    public function getChildACL()
    {
        return $this->getACL();
    }

    public function delete()
    {
        if ($this->shared()) {
            $this->carddavBackend->unshare($this->addressBookInfo['principaluri'], $this->addressBookInfo['id']);
            return;
        }
        parent::delete();
    }
}

class BookHome extends CardDAV\AddressBookHome
{
    public function getChildren()
    {
        $objs = [];
        foreach ($this->carddavBackend->getAddressBooksForUser($this->principalUri) as $b) {
            $objs[] = new SharedAddressBook($this->carddavBackend, $b);
        }
        return $objs;
    }
}

class BookRoot extends CardDAV\AddressBookRoot
{
    public function getChildForPrincipal(array $principal)
    {
        return new BookHome($this->carddavBackend, $principal['uri']);
    }
}

/** Principals: a mailbox sees only itself. */
class Principals extends DAVACL\PrincipalBackend\PDO
{
    private string $me;

    public function __construct(PDO $pdo, string $me)
    {
        parent::__construct($pdo);
        $this->me = 'principals/' . $me;
    }

    public function getPrincipalsByPrefix($prefixPath)
    {
        return array_values(array_filter(parent::getPrincipalsByPrefix($prefixPath), fn($p) => $p['uri'] === $this->me));
    }

    public function searchPrincipals($prefixPath, array $searchProperties, $test = 'allof')
    {
        return [];
    }

    public function findByUri($uri, $principalPrefix)
    {
        return null;
    }
}

/** The sign-in was done by the panel (Caddy asks it for every request); this only reads who it was. */
class Auth implements DAV\Auth\Backend\BackendInterface
{
    public function __construct(private string $account, private PDO $pdo)
    {
    }

    public function check(\Sabre\HTTP\RequestInterface $request, \Sabre\HTTP\ResponseInterface $response)
    {
        $user = (string) ($_SERVER['HTTP_X_PHPANEL_DAV_USER'] ?? '');
        $acct = (string) ($_SERVER['HTTP_X_PHPANEL_DAV_ACCOUNT'] ?? '');
        if ($acct === '' || !hash_equals($this->account, $acct) || !preg_match(USER_RE, $user)) {
            return [false, 'not signed in'];
        }
        Store::provision($this->pdo, $user);
        return [true, 'principals/' . $user];
    }

    public function challenge(\Sabre\HTTP\RequestInterface $request, \Sabre\HTTP\ResponseInterface $response)
    {
    }
}

final class App
{
    public static function serve(string $account, string $dbPath): void
    {
        $maint = dirname($dbPath) . '/maintenance';
        if (is_file($maint) && time() - (int) filemtime($maint) < 90) {
            http_response_code(503);
            header('Retry-After: 30');
            echo "Calendars and contacts are being restored. Try again in a minute.\n";
            return;
        }
        if ((int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > 26 * 1024 * 1024) {
            http_response_code(413);
            return;
        }
        $user = (string) ($_SERVER['HTTP_X_PHPANEL_DAV_USER'] ?? '');
        if (!preg_match(USER_RE, $user)) {
            http_response_code(403);
            return;
        }
        $pdo = Store::open($dbPath);
        $principals = new Principals($pdo, $user);
        $cal = new CalDAV\Backend\PDO($pdo);
        $book = new Book($pdo);
        $tree = [
            new CalDAV\Principal\Collection($principals),
            new CalDAV\CalendarRoot($principals, $cal),
            new BookRoot($principals, $book),
        ];
        $server = new DAV\Server($tree);
        $server->setBaseUri('/dav/');
        $server->addPlugin(new DAV\Auth\Plugin(new Auth($account, $pdo)));
        $acl = new DAVACL\Plugin();
        $acl->hideNodesFromListings = true;
        $acl->allowUnauthenticatedAccess = false;
        $server->addPlugin($acl);
        $server->addPlugin(new CalDAV\Plugin());
        $server->addPlugin(new CardDAV\Plugin());
        $server->addPlugin(new DAV\Sync\Plugin());
        $server->addPlugin(new DAV\PropertyStorage\Plugin(new DAV\PropertyStorage\Backend\PDO($pdo)));
        $server->addPlugin(new CalDAV\ICSExportPlugin());
        $server->exec();
    }
}
