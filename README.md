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

Many of the features a hosting control panel needs are still missing. **Rough estimate: about 28% of the planned
feature set is done** (estimated on 2026-10-20). Check this page again later for progress.

| Area | Done | Notes |
| --- | --- | --- |
| Installer and base stack | ~70% | Web, PHP, database, mail, DNS, FTP, firewall and webmail packages are installed and configured. Tested on Ubuntu 26.04 (amd64) only. |
| Panel core | ~55% | Login, admin, reseller and user roles, packages (including default unlimited ones), impersonation, two-factor authentication, profile, server and service control, hostname and timezone settings, Let's Encrypt for the panel, unique account names. |
| Hosting features | ~20% | Done: adding and removing domains and subdomains with PHP, web server, HTTPS, DNS zone and mail records set up automatically (about 2 seconds), PHP version per domain. Not started: mail accounts, databases, FTP accounts, file manager, cron, backups, WordPress tools, statistics. |
| Everything else | ~2% | REST API, command line tool, multi-server cluster, account migration, plugins, import from other hosting, billing integration, alerts. |

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
| `--dry-run` | Show what would be done, change nothing |

The panel listens on `https://SERVER-IP:8443`. The first administrator is printed at the end
and saved in `/root/.phpanel/admin-initial.txt`. The log is `/var/log/phpanel-install.log`.
Running the installer again is safe: finished steps are skipped (`--force --only 05,06` repeats some).

## What gets installed

Caddy and Apache (with ModSecurity and OWASP CRS), PHP 5.6 to 8.6 from packages.sury.org,
MariaDB, Postfix, Dovecot, Rspamd, Knot DNS with Unbound, Pure-FTPd, Redis, Fail2Ban with an
nftables firewall, Roundcube, SnappyMail and phpMyAdmin. Nothing is compiled on the server.

## License

Proprietary, free to use in the Community edition. See [LICENSE](LICENSE).
