# PH-PANEL

Web hosting control panel for Linux servers: domains, DNS, mail, databases, FTP and PHP in one place.

## Alpha notice

> **Alpha software, for testing.**
> PH-PANEL is alpha software, meant for testing and evaluation on test servers. It is provided "as is"; features and behaviour can change between versions.
> The installer changes the whole system (packages, firewall, DNS, mail, web and database services) and expects a clean server.

## Status

**Rough estimate: about 60% of the project is done** (estimated on 2026-11-15). The estimate is measured against the 72 points of the specification; an earlier figure of about 80% (2026-11-08) counted started features, not the specification, and is replaced by this one.
Everything listed under "What works" is built and passes its automated tests. Backup is being reworked.

| Area | Done | What works |
| --- | --- | --- |
| Base | ~67% | Web, PHP, database, mail, DNS, FTP, firewall and webmail packages are installed and configured. Joining a server to a cluster (`--join`) and a DNS-only server role are supported. Tested on Ubuntu 26.04, Ubuntu 24.04, Debian 12 and Debian 13 (amd64): a fresh install finishes cleanly and passes the same test suites on each. Sign-in by username with password recovery, admin, reseller and user roles, packages (including default unlimited ones), impersonation, two-factor authentication, profile, server and service control with uptime and logs, hostname and timezone settings, Let's Encrypt for the panel, unique account names. |
| Operations and security | ~52% | Notifications by e-mail, SMS gateway, Telegram, Slack and signed webhook with rules, quiet hours and history; alerts for load, memory, disk, quotas, services, certificates, address reputation, bans, backups and WordPress updates; a security page; SSH keys for hosting accounts (add, generate, revoke, keys-only sign-in, keys of the server administrator with re-confirmation); scheduled backups with retention and restore of an account, a folder, a file, a database or a mailbox, on a local folder (anywhere inside /var/backups, /backup, /mnt, /srv or /media, including mounted disks and network shares), S3-compatible or SFTP destination (being reworked). |
| Domains, mail and access | ~85% | Adding and removing domains and subdomains with PHP, web server, HTTPS, DNS zone and mail records set up automatically (about 2 seconds); alias and parked names, redirects (301/302), password-protected folders and custom error pages per domain; PHP version and settings per domain, OPcache development and production mode; a full DNS zone editor (all common record types, BIND import and export, history with rollback, DNS health checks, DNSSEC, mail provider presets); optional Cloudflare sync per domain with an API token; wildcard certificates; certificates bought elsewhere (upload or request, validation, expiry alerts, automatic fallback to Let's Encrypt, served for the mail name too); mail accounts with aliases, forwarders, catch-all, automatic replies, mailbox limits, mail modes, DKIM signing, a mail log, a scoped mail queue, one-click webmail sign-in (Roundcube by default, SnappyMail optional) with password change; FTP accounts (virtual users, FTP over TLS, per-account folders); connection details for mail and FTP programs that warn when a name is hidden behind a proxy. |
| Users' features | ~48% | Databases and database users, phpMyAdmin with one-click login; a web file manager (works as the account owner, trash, archives, large uploads, code editor with history); cron jobs per account (jailed, with limits, logs and e-mailed output); WordPress one-click install and toolkit (central list, safe updates that roll back when the site breaks, scheduled updates, staging and push, hardening, maintenance and debug modes). |
| Cluster | ~100% | DNS cluster with automatic zone sync between any number of servers, account migration with a compatibility check, maintenance state, verified transfer, TTL handling and failback, Fail2Ban bans and allowlist shared across the cluster, nameserver selection, adopting the zones of a removed server, IP management (address list with rescan, dedicated addresses per domain, mail sent from a dedicated address, scheduled moves, main address change with automatic rollback of network changes). |
| Ecosystem | ~20% | A REST API with per-user API keys (OpenAPI document, rate limits) and a signed install channel. |

**Not built yet:** web terminal, CalDAV/CardDAV, per-mailbox antispam, malware scan, slow-query monitor, web log analysis, graphs per service, multilanguage files, themes, plug-ins, licence editions, panel self-update.

**Account import.** Import an account from a backup made by another hosting panel: files, databases with their original passwords, mailboxes, DNS zones, cron jobs, certificates and FTP accounts.

**Software and services.** Admin, Software and services lists every optional part of the server (PHP versions 5.6 to 8.6, Redis, WP-CLI, phpMyAdmin, the Roundcube and SnappyMail webmail clients, the mail stack, FTP, Fail2Ban and restic) with its state, version and size, and installs, removes, starts, stops and restarts each one as a tracked job. Nothing that is in use is removed: PH-PANEL lists what uses it, and the domains of a PHP version can be moved to another installed version first.

## Install

On a clean server (Ubuntu 26.04 / 24.04 or Debian 12 / 13, amd64), as root, install minisign and curl, download the installer, check its signature with the release key and run it, as one line:

```bash
apt-get update && apt-get install -y minisign curl && curl -fsSLO https://ph-panel.com/install.sh -O https://ph-panel.com/install.sh.minisig && minisign -Vm install.sh -P RWTdQ3rZTJw2cM8M2JeDTYHgcq/w0O7lbUXKbKHg/cNgavBfGoM25NZu && bash install.sh
```

Run it as root (on Ubuntu, `sudo -i` first). The first part installs minisign and curl, which check and download the installer.

Release key: id `70369C4CD97A43DD`, public key `RWTdQ3rZTJw2cM8M2JeDTYHgcq/w0O7lbUXKbKHg/cNgavBfGoM25NZu` (also published at https://ph-panel.com/minisign.pub).

Optional flags go after the script name, for example a hostname with automatic certificate:

```bash
apt-get update && apt-get install -y minisign curl && curl -fsSLO https://ph-panel.com/install.sh -O https://ph-panel.com/install.sh.minisig && minisign -Vm install.sh -P RWTdQ3rZTJw2cM8M2JeDTYHgcq/w0O7lbUXKbKHg/cNgavBfGoM25NZu && bash install.sh --hostname panel.example.com
```

| Flag | Meaning |
| --- | --- |
| `--hostname FQDN` | the panel hostname (e.g. panel.example.com) |
| `--public-ip IP` | the public IP, if auto-detection is wrong (servers on a LAN) |
| `--profile P` | auto\|minimal\|small\|standard\|large (default: auto, based on RAM) |
| `--php LIST` | auto\|all\|8.4,7.4,... (default: based on profile) |
| `--admin-email EMAIL` | the first administrator's recovery email (used only to reset the password) |
| `--admin-username NAME` | the administrator's sign-in name and server account name (default: admin plus four random digits, e.g. admin3738) |
| `--join IP` | after the installation, join the cluster of the server at IP (needs --token) |
| `--token TOKEN` | the join token made on that server (Admin, DNS, Cluster, or: phpanel-web cluster token) |
| `--join-port N` | the panel port of that server (default 8443) |
| `--role R` | full (default) or dns-only: a name server with the panel only, secondary for the zones of the cluster |
| `--no-panel` | install only the stack, without the panel daemon |
| `--only STEPS` | run only the given steps (e.g. 03,04) |
| `--force` | also re-run steps that already completed |
| `--dry-run` | show what would be done, without making changes |
| `-h, --help` | this message |

The panel listens on `https://SERVER-IP:8443`. The first administrator, a random username such as `admin3738` with a generated password, is printed at the end of the installation and saved in `~root/.phpanel/admin-initial.txt`.

Sign in with the **username**. The e-mail address is used to recover a forgotten password.

Running the installer again is safe: finished steps are skipped. `--force --only 05,06` repeats some of them. The log is `/var/log/phpanel-install.log`.

## What gets installed

Caddy and Apache (with ModSecurity and OWASP CRS), PHP 5.6 to 8.6 from packages.sury.org, MariaDB, Postfix, Dovecot, Rspamd, Knot DNS with Unbound, Pure-FTPd, Redis, Fail2Ban with an nftables firewall, Roundcube, SnappyMail and phpMyAdmin.

## License

Proprietary, free to use in the Community edition. See [LICENSE](LICENSE).
