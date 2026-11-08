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
pure-ftpd pure-ftpd/virtualchroot boolean false
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

# WP-CLI [39] [60]: the distro package when it is recent enough, else the official phar of a pinned version, checked against the SHA-512 that
# is written here (not against a file that comes from the same place as the phar). Nothing is compiled.
WPCLI_VERSION=2.12.0
WPCLI_SHA512=be928f6b8ca1e8dfb9d2f4b75a13aa4aee0896f8a9a0a1c45cd5d2c98605e6172e6d014dda2e27f88c98befc16c040cbb2bd1bfa121510ea5cdf5f6a30fe8832
WPCLI_FILE=/usr/local/lib/phpanel/wp-cli.phar

install_wpcli() {
  dns_only && return 0
  if [[ -f $WPCLI_FILE ]] && { [[ -L $WPCLI_FILE ]] || echo "$WPCLI_SHA512  $WPCLI_FILE" | sha512sum -c --status 2>/dev/null; }; then
    ok "WP-CLI already installed"; return 0
  fi
  [[ $DRY_RUN == 1 ]] && { info "[dry-run] installing WP-CLI"; return 0; }
  install -d -m 755 /usr/local/lib/phpanel
  local cand
  cand=$(apt-cache policy wp-cli 2>/dev/null | awk '/Candidate:/ {print $2}') || true
  if [[ -n $cand && $cand != "(none)" ]] && dpkg --compare-versions "$cand" ge 2.10; then
    if apt_install_group "wordpress" wp-cli; then
      local phar
      phar=$(dpkg -L wp-cli 2>/dev/null | grep -E '\.phar$' | head -1)
      if [[ -n $phar && -f $phar ]]; then ln -sf "$phar" "$WPCLI_FILE"; ok "WP-CLI from the distro package ($cand)"; return 0; fi
    fi
  fi
  local tmp
  tmp=$(mktemp -d)
  if curl -fsSL --max-time 180 -o "$tmp/wp-cli.phar" "https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar" \
     && echo "$WPCLI_SHA512  $tmp/wp-cli.phar" | sha512sum -c --status; then
    install -m 755 -o root -g root "$tmp/wp-cli.phar" "$WPCLI_FILE"
    ok "WP-CLI ${WPCLI_VERSION} installed (SHA-512 verified)"
  else
    error "downloading or verifying WP-CLI ${WPCLI_VERSION} failed: the WordPress tools will not work until it is installed"
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
  if dns_only; then
    apt_install_group "web" caddy   # only the panel's own address and the ACME answer
  else
    apt_install_group "web" caddy apache2 libapache2-mod-security2 modsecurity-crs
  fi
  apt_install_group "dns" knot knot-dnssecutils knot-dnsutils unbound unbound-anchor dns-root-data
  if ! dns_only; then
    apt_install_group "mail" postfix postfix-sqlite dovecot-core dovecot-imapd dovecot-pop3d \
      dovecot-lmtpd dovecot-sieve dovecot-managesieved rspamd redis-server postsrsd
    apt_install_group "databases" mariadb-server mariadb-client
    apt_install_group "ftp" pure-ftpd
    apt_install_group "statistics" goaccess
    apt_install_group "backup" restic openssh-client   # scheduled backups [07] [71]
    apt_install_group "ssh" openssh-server sudo        # SSH access of the hosting accounts [66]
  fi

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
  done < <(dns_only || php_versions_wanted)   # on a name server the list stays empty: nothing to read, nothing to write to a closed pipe
  fact_set PHP_INSTALLED "${installed_php[*]}"
  if dns_only; then info "dns-only: no PHP"
  elif [[ ${#installed_php[@]} -gt 0 ]]; then ok "PHP installed: ${installed_php[*]}"; else error "no PHP version installed"; fi

  install_lego
  install_wpcli

  # spot checks from the specification
  if dns_only; then :
  elif have pure-certd || [[ -x /usr/sbin/pure-certd ]]; then
    ok "pure-certd available: per-domain SNI for FTP [17]"; fact_set FTP_SNI 1
  else
    warn "pure-certd missing: FTP will use the hostname certificate [17]"; fact_set FTP_SNI 0
  fi
  services_unblock
}
