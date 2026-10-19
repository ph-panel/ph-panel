#!/usr/bin/env bash
# Step 11 – starting services; minimal configuration, just enough for the services to start without port conflicts,
# then start and report. The full configuration of each service comes in the project's later steps.

service_check() {
  local svc=$1
  systemctl list-unit-files "$svc.service" --no-legend 2>/dev/null | grep -q . || { info "$svc: not installed, skipping"; return 0; }
  run systemctl enable "$svc" || true
  run systemctl restart "$svc" || true
  sleep 1
  if systemctl is-active --quiet "$svc"; then
    ok "$svc started"
  else
    error "$svc fails to start"
    { echo "----- journalctl -u $svc -----"; journalctl -u "$svc" -n 25 --no-pager 2>&1; } >>"$PHPANEL_LOG_FILE"
  fi
}

resolver_activate() {
  # once Unbound responds: systemd-resolved stub off, /etc/resolv.conf -> 127.0.0.1 [05]
  if systemctl list-unit-files systemd-resolved.service --no-legend 2>/dev/null | grep -q .; then
    run systemctl restart systemd-resolved || true
  fi
  if ! systemctl is-active --quiet unbound; then warn "Unbound inactive: leaving /etc/resolv.conf unchanged"; return 0; fi
  if ! dig +short +time=3 +tries=1 @127.0.0.1 deb.debian.org | grep -q .; then
    warn "Unbound does not resolve: leaving /etc/resolv.conf unchanged"; return 0
  fi
  rm -f /etc/resolv.conf
  printf 'nameserver 127.0.0.1\noptions edns0\n' >/etc/resolv.conf
  if getent hosts deb.debian.org >/dev/null; then ok "/etc/resolv.conf -> Unbound 127.0.0.1"
  else
    printf 'nameserver 1.1.1.1\n' >/etc/resolv.conf
    warn "resolution through Unbound failed after the switch; temporarily set 1.1.1.1"
  fi
}

mariadb_start() {
  run systemctl enable mariadb || true
  run systemctl restart mariadb || true
  sleep 2
  if systemctl is-active --quiet mariadb; then ok "mariadb started (profile ${MYCNF_PROFILE:-?})"; return 0; fi
  warn "mariadb fails to start with profile ${MYCNF_PROFILE:-?}; reverting to the default configuration"
  { journalctl -u mariadb -n 25 --no-pager 2>&1; } >>"$PHPANEL_LOG_FILE"
  rm -f /etc/mysql/mariadb.conf.d/90-phpanel.cnf /etc/mysql/mariadb.conf.d/91-phpanel-hw.cnf
  run systemctl restart mariadb || true
  sleep 2
  if systemctl is-active --quiet mariadb; then warn "mariadb started only without the PH-PANEL profile"; else error "mariadb fails to start even without the profile"; fi
}

step_11_services() {
  [[ $DRY_RUN == 1 ]] && { info "[dry-run] starting services"; return 0; }
  run systemctl daemon-reload

  # firewall first, then the rest
  if [[ -f /etc/nftables.conf ]]; then service_check nftables; else warn "firewall not enabled (/etc/nftables.conf is missing)"; fi

  service_check chrony
  # chrony replaces systemd-timesyncd; clear the stale failed state it leaves behind
  run systemctl disable --now systemd-timesyncd || true
  run systemctl reset-failed systemd-timesyncd || true
  service_check unbound
  if have unbound-checkconf; then
    unbound-checkconf >>"$PHPANEL_LOG_FILE" 2>&1 && ok "unbound-checkconf OK" || error "unbound-checkconf failed"
  fi
  resolver_activate
  mariadb_start
  local svc
  for svc in redis-server apache2; do service_check "$svc"; done
  local v
  for v in ${PHP_INSTALLED:-}; do service_check "php${v}-fpm"; done

  service_check caddy   # after the php-fpm pools: the webmail/dbadmin groups take effect on restart
  if [[ ${KNOT_OK:-0} == 1 ]]; then
    service_check knot
  else
    run systemctl disable --now knot || true
    info "knot: stopped (the configuration is invalid or the IP is missing)"
  fi
  for svc in rspamd dovecot postsrsd postfix pure-ftpd fail2ban; do service_check "$svc"; done
}
