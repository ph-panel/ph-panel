# PH-PANEL

Web hosting control panel for Linux servers: domains, DNS, mail, databases, FTP and PHP in one place.

> **Alpha software, for testing only.**
> PH-PANEL is an early alpha release. It is intended only for testing and evaluation on throwaway
> servers, and for nothing else. Do not use it in production, with real customers, or with data you
> cannot afford to lose. The installer changes the whole system (packages, firewall, DNS, mail, web
> and database services) and expects a clean server.
>
> It is provided "as is", without any warranty or support. The authors accept no responsibility or
> liability for data loss, downtime, security incidents or any other damage resulting from its use.
> Features, configuration and behaviour can change or break between versions without notice.

## Status

Several features a hosting control panel needs are still missing. **Rough estimate: about 70% of the planned
feature set is done** (estimated on 2026-10-31). Check this page again later for progress.

| Area | Done | Notes |
| --- | --- | --- |
| Installer and base stack | ~78% | Web, PHP, database, mail, DNS, FTP, firewall and webmail packages are installed and configured. Joining a server to a cluster (`--join`) and a DNS-only server role are supported. Tested on Ubuntu 26.04 (amd64) only. |
| Panel core | ~80% | Sign-in by username with password recovery, admin, reseller and user roles, packages (including default unlimited ones), impersonation, two-factor authentication, profile, server and service control with uptime and logs, hostname and timezone settings, Let's Encrypt for the panel, unique account names, a REST API with per-user API keys (36 calls, OpenAPI document, rate limits), notifications by e-mail, SMS gateway, Telegram, Slack and signed webhook with rules, quiet hours and history, alerts for load, memory, disk, quotas, services, certificates, address reputation and bans, and a security page. |
| Hosting features | ~72% | Done: adding and removing domains and subdomains with PHP, web server, HTTPS, DNS zone and mail records set up automatically (about 2 seconds), PHP version and settings per domain, OPcache development and production mode, a full DNS zone editor (all common record types, BIND import and export, history with rollback, DNS health checks, DNSSEC, mail provider presets), optional Cloudflare sync per domain with an API token, wildcard certificates, databases and database users, phpMyAdmin with one-click login, HTTP to HTTPS redirect per domain, mail accounts with aliases, forwarders, catch-all, automatic replies, mailbox limits, mail modes, DKIM signing, a mail log, a scoped mail queue, one-click webmail sign-in (Roundcube by default, SnappyMail optional) with password change, FTP accounts (virtual users, FTP over TLS, per-account folders), a web file manager (works as the account owner, trash, archives, large uploads, code editor with history), and connection details for mail and FTP programs that warn when a name is hidden behind a proxy. Not started: cron, backups, WordPress tools, web statistics, import from other hosting, malware scanning. |
| Multi-server | ~65% | Done: DNS cluster with automatic zone sync between any number of servers, account migration with a compatibility check, maintenance state, verified transfer, TTL handling and failback, Fail2Ban bans and allowlist shared across the cluster, nameserver selection, adopting the zones of a removed server. Not done: fast migration mode, dedicated IP addresses. |
| Everything else | ~5% | Plugins and hooks, billing integration, command line tool for the remaining areas. |

Integrations with Cloudflare, SMS gateways, Telegram and certificate authorities have been tested against simulated
services only, not yet against real accounts.

Not yet tested: Debian, Ubuntu 24.04, arm64, real servers with very little memory in production-like use.

## Install

On a clean server (Ubuntu 26.04 / 24.04 or Debian 12 / 13, amd64 or arm64), as root:

```bash
curl -fsSL https://raw.githubusercontent.com/ph-panel/ph-panel/main/install.sh | bash
```

Optional flags go after `-s --`, for example a hostname with automatic certificate:

```bash
curl -fsSL https://raw.githubusercontent.com/ph-panel/ph-panel/main/install.sh | bash -s -- --hostname panel.example.com
```

| Flag | Meaning |
| --- | --- |
| `--hostname FQDN` | Panel hostname (needs a DNS record pointing at the server) |
| `--profile minimal\|small\|standard\|large` | Resource profile (default: chosen from RAM) |
| `--php all\|8.4,8.3,...` | PHP versions to install (default: by profile) |
| `--public-ip IP` | Public IP when the server sits behind NAT |
| `--admin-username NAME` | Username of the first administrator (default: random `adminNNNN`) |
| `--admin-email EMAIL` | Recovery email of the first administrator |
| `--dry-run` | Show what would be done, change nothing |

The panel listens on `https://SERVER-IP:8443`. The first administrator (a random username such as `admin3738`, with a generated
password) is printed at the end and saved in `/root/.phpanel/admin-initial.txt`. Sign in with the **username**; the email address is used only to
recover a forgotten password. The log is `/var/log/phpanel-install.log`.
Running the installer again is safe: finished steps are skipped (`--force --only 05,06` repeats some).

## What gets installed

Caddy and Apache (with ModSecurity and OWASP CRS), PHP 5.6 to 8.6 from packages.sury.org,
MariaDB, Postfix, Dovecot, Rspamd, Knot DNS with Unbound, Pure-FTPd, Redis, Fail2Ban with an
nftables firewall, Roundcube, SnappyMail and phpMyAdmin. Nothing is compiled on the server.

## License

Proprietary, free to use in the Community edition. See [LICENSE](LICENSE).
