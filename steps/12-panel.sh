#!/usr/bin/env bash
# Step 12 – the panel daemons (phpanel-web, phpanel-root), certificate, systemd, Fail2Ban, first admin.

step_12_panel() {
  if [[ ${OPT_NO_PANEL:-0} == 1 ]]; then info "--no-panel: skipping the daemon"; return 0; fi
  local bin="$INSTALLER_DIR/bin/phpanel-web-linux-$ARCH" rootbin="$INSTALLER_DIR/bin/phpanel-root-linux-$ARCH"
  if [[ ! -x $bin || ! -x $rootbin ]]; then
    error "panel binaries are missing in $INSTALLER_DIR/bin (run daemon/build.sh first); the panel was not installed"
    return 0
  fi
  [[ $DRY_RUN == 1 ]] && { info "[dry-run] installing $bin to /opt/phpanel"; return 0; }

  # unprivileged user [F1]
  id phpanel >/dev/null 2>&1 || useradd --system --home-dir /opt/phpanel --shell /usr/sbin/nologin phpanel
  getent group phpanel-pma >/dev/null || groupadd --system phpanel-pma   # owns the phpMyAdmin sign-on socket
  install -d -m 755 /opt/phpanel
  install -d -m 750 -o phpanel -g phpanel /opt/phpanel/data /opt/phpanel/logs
  # where an account move keeps its archive [49]; the panel streams it to the other server, so its unit may write here
  install -d -m 700 -o phpanel -g phpanel /var/lib/phpanel/migrations
  install -d -m 750 -o root -g phpanel /opt/phpanel/ssl /opt/phpanel/ssl/panel
  install -d -m 750 -o root -g phpanel /etc/phpanel
  # what this server is for: the panel reads it to hide hosting on a name server [48]
  printf '%s\n' "${SERVER_ROLE:-full}" >/etc/phpanel/role; chown root:phpanel /etc/phpanel/role; chmod 640 /etc/phpanel/role
  install -d -m 755 /opt/phpanel/lang /opt/phpanel/themes
  # master key for 2FA secrets and trusted-device cookies [18]; created once, never replaced
  if [[ ! -s /etc/phpanel/secret.key ]]; then
    ( umask 077; head -c 32 /dev/urandom >/etc/phpanel/secret.key )
  fi
  chown phpanel:phpanel /etc/phpanel/secret.key; chmod 600 /etc/phpanel/secret.key
  install -m 755 "$bin" /opt/phpanel/phpanel-web
  install -m 750 -o root -g root "$rootbin" /opt/phpanel/phpanel-root
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
  install -m 644 "$INSTALLER_DIR/systemd/phpanel-root.service" /etc/systemd/system/phpanel-root.service

  # Fail2Ban for the panel login [18]
  if [[ -d /etc/fail2ban ]]; then
    cat >/etc/fail2ban/filter.d/phpanel.conf <<'EOF'
[Definition]
# Fail2Ban strips the timestamp before matching, so the line starts at "phpanel auth ..."
failregex = ^\s*phpanel auth (?:failed|blocked) ip=<HOST>(?:\s|$)
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

  # first administrator: signs in with the username (also the Linux account name); the email is only for recovering the password; the name defaults to admin plus four random digits (for example admin3738)
  local email=${OPT_ADMIN_EMAIL:-admin@${PANEL_HOSTNAME:-phpanel.local}} out pw uname
  local create=(admin create --data /opt/phpanel/data --email "$email")
  [[ -n ${OPT_ADMIN_USERNAME:-} ]] && create+=(--username "$OPT_ADMIN_USERNAME")
  if out=$(runuser -u phpanel -- /opt/phpanel/phpanel-web "${create[@]}" 2>&1); then
    pw=$(awk '/^Password:/ {print $2}' <<<"$out")
    uname=$(sed -n 's/.*Username: \([a-z0-9]*\) .*/\1/p' <<<"$out" | head -1)
    install -d -m 700 /root/.phpanel
    printf 'email=%s\nusername=%s\npassword=%s\n' "$email" "$uname" "$pw" >/root/.phpanel/admin-initial.txt
    chmod 600 /root/.phpanel/admin-initial.txt
    fact_set ADMIN_EMAIL "$email"
    ok "administrator created: username $uname, recovery email $email (details in /root/.phpanel/admin-initial.txt)"
  elif [[ $out == *"--username"* ]]; then
    error "the administrator was not created: ${out#error: }"
  elif [[ $out == *"UNIQUE"* ]]; then
    info "the administrator $email already exists; left unchanged"
  else
    info "the administrator could not be created: $out"
  fi

  # base address of the links in password-recovery mails; taken from here, never from a request header
  local pub=${PANEL_HOSTNAME:-${IP_PUBLIC:-${IP_LOCAL:-127.0.0.1}}}
  install -d -m 755 /etc/phpanel
  printf 'PHPANEL_PUBLIC_URL=https://%s:8443\n' "$pub" >/etc/phpanel/web.env
  chmod 644 /etc/phpanel/web.env

  run systemctl daemon-reload
  # restart (not just enable --now) so a re-run picks up new binaries; the helper starts first [F1]
  run systemctl enable phpanel-root phpanel-web
  run systemctl restart phpanel-root || error "phpanel-root did not start (journalctl -u phpanel-root)"
  run systemctl restart phpanel-web
  local i
  for i in 1 2 3 4 5; do
    sleep 1
    if curl -fsk --max-time 3 https://127.0.0.1:8443/health >/dev/null 2>&1; then ok "the panel responds on :8443"; return 0; fi
  done
  error "the panel does not respond on https://127.0.0.1:8443/health (journalctl -u phpanel-web)"
}
