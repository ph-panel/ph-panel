#!/usr/bin/env bash
# Step 04 – installation of all packages. Services do NOT start here (policy-rc.d);
# ports and configuration are done in the following steps. Errors are collected, they do not stop the installation.

PHP_ALL_VERSIONS=(5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3 8.4 8.5 8.6)
PHP_EXTENSIONS=(fpm cli common mysql sqlite3 curl xml mbstring zip gd intl bcmath opcache readline imagick redis imap soap)

php_versions_wanted() {
  local spec=${OPT_PHP:-auto}
  case $spec in
    all) printf '%s\n' "${PHP_ALL_VERSIONS[@]}" ;;
    auto)
      case $PROFILE in
        minimal) echo 8.4 ;;
        small) printf '%s\n' 8.3 8.4 ;;
        *) printf '%s\n' "${PHP_ALL_VERSIONS[@]}" ;;
      esac ;;
    *) tr ',' '\n' <<<"$spec" ;;
  esac
}

preseed_debconf() {
  local mailname=${PANEL_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}
  [[ $DRY_RUN == 1 ]] && return 0
  debconf-set-selections <<EOF
postfix postfix/main_mailer_type select Internet Site
postfix postfix/mailname string $mailname
pure-ftpd pure-ftpd/virtualchroot boolean true
pure-ftpd pure-ftpd/standalone-or-inetd select standalone
EOF
  echo "$mailname" >/etc/mailname
}

install_lego() {
  if have lego; then ok "lego already installed ($(lego --version 2>/dev/null | head -1))"; return 0; fi
  [[ $DRY_RUN == 1 ]] && { info "[dry-run] downloading lego"; return 0; }
  local tag ver tmp asset sums
  # without the GitHub API (rate limit, 403): we follow the /releases/latest -> /tag/vX.Y.Z redirect
  tag=$(curl -fsSLI --max-time 20 -o /dev/null -w '%{url_effective}' https://github.com/go-acme/lego/releases/latest 2>/dev/null) || tag=
  tag=${tag##*/}
  [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { error "could not determine the latest lego version"; return 0; }
  ver=${tag#v}; tmp=$(mktemp -d)
  asset="lego_${tag}_linux_${ARCH}.tar.gz"
  sums="lego_${ver}_checksums.txt"
  if curl -fsSL --max-time 120 -o "$tmp/$asset" "https://github.com/go-acme/lego/releases/download/$tag/$asset" \
     && curl -fsSL --max-time 30 -o "$tmp/$sums" "https://github.com/go-acme/lego/releases/download/$tag/$sums" \
     && (cd "$tmp" && grep " $asset\$" "$sums" | sha256sum -c --status); then
    tar -xzf "$tmp/$asset" -C "$tmp" lego && install -m 755 "$tmp/lego" /usr/local/bin/lego
    ok "lego $tag installed (checksum verified)"
  else
    error "downloading or verifying lego $tag failed"
  fi
  rm -rf "$tmp"
}

step_04_packages() {
  services_block
  preseed_debconf

  apt_install_group "base" \
    curl wget jq unzip zip tar zstd bzip2 xz-utils git rsync acl quota cron logrotate \
    chrony sudo openssl sqlite3 bind9-dnsutils netcat-openbsd lsof psmisc bubblewrap minisign

  apt_install_group "security" nftables fail2ban python3-systemd unattended-upgrades
  apt_install_group "web" caddy apache2 libapache2-mod-security2 modsecurity-crs
  apt_install_group "dns" knot knot-dnsutils unbound unbound-anchor dns-root-data
  apt_install_group "mail" postfix postfix-sqlite dovecot-core dovecot-imapd dovecot-pop3d \
    dovecot-lmtpd dovecot-sieve dovecot-managesieved rspamd redis-server postsrsd
  apt_install_group "databases" mariadb-server mariadb-client
  apt_install_group "ftp" pure-ftpd
  apt_install_group "statistics" goaccess

  local v e pkgs installed_php=()
  while read -r v; do
    [[ -z $v ]] && continue
    if ! pkg_available "php${v}-fpm"; then
      warn "[php] PHP $v is not available in the repo for $OS_ID $OS_VERSION"
      continue
    fi
    pkgs=()
    for e in "${PHP_EXTENSIONS[@]}"; do
      # from PHP 8.5, OPcache is built into PHP and no longer has a separate package
      if [[ $e == opcache && $(printf '%s\n' "$v" 8.5 | sort -V | head -1) == 8.5 ]]; then continue; fi
      pkgs+=("php${v}-${e}")
    done
    apt_install_group "php $v" "${pkgs[@]}"
    dpkg -s "php${v}-fpm" >/dev/null 2>&1 && installed_php+=("$v")
  done < <(php_versions_wanted)
  fact_set PHP_INSTALLED "${installed_php[*]}"
  if [[ ${#installed_php[@]} -gt 0 ]]; then ok "PHP installed: ${installed_php[*]}"; else error "no PHP version installed"; fi

  install_lego

  # spot checks from the specification
  if have pure-certd || [[ -x /usr/sbin/pure-certd ]]; then
    ok "pure-certd available: per-domain SNI for FTP [17]"; fact_set FTP_SNI 1
  else
    warn "pure-certd missing: FTP will use the hostname certificate [17]"; fact_set FTP_SNI 0
  fi
  services_unblock
}
