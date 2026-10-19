<p align="center"><img src="assets/logo.svg" width="72" alt="PH-PANEL logo"></p>

<h1 align="center">PH-PANEL</h1>

Web hosting control panel for Linux servers: domains, DNS, mail, databases, FTP and PHP in one place.
Early development: the installer and the base stack work, the panel itself is still small.

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
| `--profile minim\|mic\|standard\|mare` | Resource profile (default: chosen from RAM) |
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
