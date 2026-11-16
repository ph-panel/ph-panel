# PH-PANEL

Web hosting control panel for Linux servers: domains, DNS, mail, databases, FTP and PHP in one place.

## Alpha notice

> **Alpha software, for testing.**
> PH-PANEL is alpha software, meant for testing and evaluation on test servers. It is provided "as is"; features and behaviour can change between versions.
> The installer changes the whole system (packages, firewall, DNS, mail, web and database services) and expects a clean server.

## Status

**Rough estimate: about 60% of the planned features are done** (estimated on 2026-11-15). More is added with every release.

| Area | Done | What you can do today |
| --- | --- | --- |
| Base | ~67% | Install a full hosting server in one command (web, PHP 5.6 to 8.6, databases, mail, DNS, FTP, firewall), on Ubuntu 24.04 / 26.04 and Debian 12 / 13. Sign in with two-factor protection and password recovery; administrators, resellers and users with packages. |
| Operations and security | ~52% | Alerts by e-mail, SMS, Telegram, Slack and webhook; a daily health check of the server; disk and inode limits for accounts; automatic security updates; Fail2Ban bans; SSH keys for accounts. |
| Domains, mail and access | ~85% | Add a domain and get the website, HTTPS, DNS and mail set up in seconds; full DNS editor with DNSSEC and optional Cloudflare sync; certificates of your own or wildcard; mailboxes with aliases, forwarding, automatic replies and one-click webmail (Roundcube or SnappyMail); FTP accounts; databases with phpMyAdmin; redirects and custom error pages. |
| Users' features | ~48% | File manager with editor, cron jobs, WordPress install and safe updates, backups to your own destinations (your folder, S3, SFTP, FTP) with restore of a file, a database or a mailbox, the whole server as one file with an optional password, and import from another hosting panel. |
| Cluster | ~100% | Several servers working together: shared DNS, moving accounts between servers, shared Fail2Ban bans. |
| Ecosystem | ~20% | REST API with API keys and a signed install channel. |

**Coming next:** traffic and CPU/RAM limits per account, web terminal, CalDAV/CardDAV, per-mailbox spam settings, malware scan, graphs per service, web log analysis, languages and themes, plug-ins, and updating the panel itself from the panel.

**Software and services.** Admin, Software and services lists every optional part of the server (PHP versions, Redis, phpMyAdmin, the webmail clients, mail, FTP, Fail2Ban) and installs, removes, starts and stops each one. Nothing that is in use is removed.

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
| `--no-telemetry` | do not send usage statistics to the PH-PANEL team (on by default) |
| `--share-email` | also send the administrator's email to the PH-PANEL team for security and update notices (default: no) |
| `--only STEPS` | run only the given steps (e.g. 03,04) |
| `--force` | also re-run steps that already completed |
| `--dry-run` | show what would be done, without making changes |
| `-h, --help` | this message |

The panel listens on `https://SERVER-IP:8443`. The first administrator, a random username such as `admin3738` with a generated password, is printed at the end of the installation and saved in `~root/.phpanel/admin-initial.txt`.

Sign in with the **username**. The e-mail address is used to recover a forgotten password.

Running the installer again is safe: finished steps are skipped. `--force --only 05,06` repeats some of them. The log is `/var/log/phpanel-install.log`.

## What gets installed

Caddy and Apache (with ModSecurity and OWASP CRS), PHP 5.6 to 8.6 from packages.sury.org, MariaDB, Postfix, Dovecot, Rspamd, Knot DNS with Unbound, Pure-FTPd, Redis, Fail2Ban with an nftables firewall, Roundcube, SnappyMail and phpMyAdmin.

## Privacy

Every 6 hours your server sends the PH-PANEL team a short report: a random server id, system and PH-PANEL version, load, memory, disk and uptime. It never includes domains, accounts, files, mail or customer data, and your e-mail address is sent only if you choose it.
Turn it off with `--no-telemetry` at install, or later in Admin, Server, Usage statistics.
More in the [privacy page](https://ph-panel.com/privacy).

## Support development

PH-PANEL is free to use. If it helps you, you can [support its development](https://ph-panel.com/donate).

## License

Proprietary, free to use in the Community edition. See [LICENSE](LICENSE).
