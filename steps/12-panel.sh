#!/usr/bin/env bash
# Step 12 – the panel daemon (v0.1: authentication only), certificate, systemd, Fail2Ban, first admin.

step_12_panel() {
  if [[ ${OPT_NO_PANEL:-0} == 1 ]]; then info "--no-panel: skipping the daemon"; return 0; fi
  local bin="$INSTALLER_DIR/bin/phpanel-web-linux-$ARCH"
  if [[ ! -x $bin ]]; then
    error "binary $bin is missing (run daemon/build.sh first); the panel was not installed"
    return 0
  fi
  [[ $DRY_RUN == 1 ]] && { info "[dry-run] installing $bin to /opt/phpanel"; return 0; }

  # unprivileged user [F1]
  id phpanel >/dev/null 2>&1 || useradd --system --home-dir /opt/phpanel --shell /usr/sbin/nologin phpanel
  install -d -m 755 /opt/phpanel
  install -d -m 750 -o phpanel -g phpanel /opt/phpanel/data /opt/phpanel/logs
  install -d -m 750 -o root -g phpanel /opt/phpanel/ssl /opt/phpanel/ssl/panel
  install -d -m 750 -o root -g phpanel /etc/phpanel
  install -m 755 "$bin" /opt/phpanel/phpanel-web
  ln -sf /opt/phpanel/phpanel-web /usr/local/bin/phpanel-web

  # certificate: self-signed until the ACME step (lego, [21]); the daemon reloads it by itself when it changes
  local cert=/opt/phpanel/ssl/panel/fullchain.pem key=/opt/phpanel/ssl/panel/privkey.pem
  if [[ ! -s $cert ]]; then
    local cn=${PANEL_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)} san="DNS:localhost,IP:127.0.0.1"
    [[ -n ${PANEL_HOSTNAME:-} ]] && san="DNS:$PANEL_HOSTNAME,$san"
    [[ -n ${IP_PUBLIC:-} ]] && san="$san,IP:$IP_PUBLIC"
    [[ -n ${IP_LOCAL:-} && ${IP_LOCAL:-} != "${IP_PUBLIC:-}" ]] && san="$san,IP:$IP_LOCAL"
    if run openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 397 \
         -subj "/CN=$cn" -addext "subjectAltName=$san" -keyout "$key" -out "$cert"; then
      chown root:phpanel "$key" "$cert"; chmod 640 "$key"; chmod 644 "$cert"
      ok "self-signed certificate for the panel ($san)"
    else
      warn "could not generate the certificate; the daemon will use one generated in memory"
    fi
  fi

  install -m 644 "$INSTALLER_DIR/systemd/phpanel-web.service" /etc/systemd/system/phpanel-web.service

  # Fail2Ban for the panel login [18]
  if [[ -d /etc/fail2ban ]]; then
    cat >/etc/fail2ban/filter.d/phpanel.conf <<'EOF'
[Definition]
failregex = ^\S+ phpanel auth (failed|blocked) ip=<HOST> 
ignoreregex =
EOF
    cat >/etc/fail2ban/jail.d/phpanel.conf <<'EOF'
[phpanel]
enabled  = true
port     = 8443
filter   = phpanel
logpath  = /opt/phpanel/logs/auth.log
backend  = auto
maxretry = 5
findtime = 15m
bantime  = 10m
EOF
    touch /opt/phpanel/logs/auth.log; chown phpanel:phpanel /opt/phpanel/logs/auth.log; chmod 640 /opt/phpanel/logs/auth.log
    run systemctl restart fail2ban || warn "fail2ban did not restart after adding the phpanel jail"
  fi

  # first administrator
  local email=${OPT_ADMIN_EMAIL:-admin@${PANEL_HOSTNAME:-phpanel.local}} out pw
  if out=$(runuser -u phpanel -- /opt/phpanel/phpanel-web admin create --data /opt/phpanel/data --email "$email" 2>&1); then
    pw=$(awk '/^Password:/ {print $2}' <<<"$out")
    install -d -m 700 /root/.phpanel
    printf 'email=%s\npassword=%s\n' "$email" "$pw" >/root/.phpanel/admin-initial.txt
    chmod 600 /root/.phpanel/admin-initial.txt
    fact_set ADMIN_EMAIL "$email"
    ok "administrator created: $email (password in /root/.phpanel/admin-initial.txt)"
  else
    info "the administrator already exists or could not be created: $out"
  fi

  run systemctl daemon-reload
  run systemctl enable --now phpanel-web
  local i
  for i in 1 2 3 4 5; do
    sleep 1
    if curl -fsk --max-time 3 https://127.0.0.1:8443/health >/dev/null 2>&1; then ok "the panel responds on :8443"; return 0; fi
  done
  error "the panel does not respond on https://127.0.0.1:8443/health (journalctl -u phpanel-web)"
}
