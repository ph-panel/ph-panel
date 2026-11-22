#!/usr/bin/env bash
# Step 06 – web stack: Caddy [02], Apache + ModSecurity [02][58], PHP-FPM [03][58]. Configuration only; starting happens in step 08.

# The landing page of the bare server address. Everything is inline (one style block, one SVG), so the page makes no other request; the style
# block is allowed by its hash in the Content-Security-Policy of 00-acme.caddy.
LANDING_CSS=':root{color-scheme:light dark;--bg:#f7f3f3;--card:#fff;--ink:#1a1214;--muted:#5f5156;--line:#e3d6d7;--red:#cc1424;--red-h:#a8101e;--glow:rgba(204,20,36,.12);--lk:#b3101f}
@media(prefers-color-scheme:dark){:root{--bg:#0b0a0c;--card:#151216;--ink:#f6f2f3;--muted:#b2a8ae;--line:#2c252e;--red:#c8182a;--red-h:#d82033;--glow:rgba(242,73,90,.16);--lk:#ff7a86}}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;min-height:100vh;display:flex;flex-direction:column;font:400 1rem/1.6 system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;color:var(--ink);background:radial-gradient(60rem 28rem at 50% -8rem,var(--glow),transparent 70%),var(--bg)}
main{flex:1;display:grid;place-items:center;padding:2.5rem 1rem 1.5rem}
.card{width:100%;max-width:38rem;background:var(--card);border:1px solid var(--line);border-radius:18px;padding:2.4rem 2rem 1.8rem;box-shadow:0 18px 50px -24px rgba(120,20,30,.35);text-align:center}
.brand{display:inline-flex;align-items:center;gap:.6rem;font-weight:800;font-size:1.15rem;letter-spacing:.01em;text-decoration:none;color:var(--ink)}
.brand b{font-weight:800}.brand span{color:var(--lk)}.brand svg{width:2.4rem;height:2.4rem}
h1{font-size:clamp(1.55rem,5vw,2.15rem);line-height:1.2;margin:1.4rem 0 .8rem;letter-spacing:-.015em}
p{margin:.35rem 0;color:var(--muted)}
.btns{display:flex;flex-wrap:wrap;gap:.6rem;justify-content:center;margin:1.7rem 0 .4rem}
.btn{display:inline-flex;align-items:center;min-height:2.75rem;padding:0 1.15rem;border-radius:10px;border:1px solid var(--line);color:var(--ink);text-decoration:none;font-weight:600;background:transparent;white-space:nowrap}
.btn:hover{border-color:var(--lk);color:var(--lk)}
.btn.p{background:var(--red);border-color:var(--red);color:#fff}.btn.p:hover{background:var(--red-h);border-color:var(--red-h);color:#fff}
a:focus-visible{outline:3px solid var(--red);outline-offset:3px}
.admin{margin-top:1.6rem;padding-top:1.2rem;border-top:1px solid var(--line);font-size:.95rem}
.admin a{color:var(--lk);font-weight:600}.admin a:hover{text-decoration-thickness:2px}
footer{padding:1rem;text-align:center;font-size:.85rem;color:var(--muted)}
@media(max-width:30rem){.card{padding:1.8rem 1.1rem 1.4rem}.btn{flex:1 1 40%;justify-content:center;padding:0 .7rem}}'
LANDING_HTML='<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><meta name="color-scheme" content="light dark">
<title>Powered by PH-PANEL</title>
<style>@CSS@</style></head>
<body><main><section class="card">
<a class="brand" href="https://ph-panel.com/" rel="noopener noreferrer"><svg viewBox="0 0 32 32" role="img" aria-label="PH-PANEL logo"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f0384a"/><stop offset="1" stop-color="#a30017"/></linearGradient></defs><rect width="32" height="32" rx="8" fill="url(#g)"/><path fill="#fff" fill-rule="evenodd" d="M8.5 7h8.3a5.6 5.6 0 0 1 0 11.2H12.6V25H8.5zM12.6 10.8v3.6h4.1a1.8 1.8 0 0 0 0-3.6z"/><circle cx="22.8" cy="22.4" r="2.1" fill="#fff"/></svg><b>PH<span>-</span>PANEL</b></a>
<h1>This server is powered by PH-PANEL</h1>
<p>PH-PANEL is a hosting control panel that runs web sites, e-mail, DNS and backups on your own server.</p>
<p>Simple, fast, and made for people who run their own hosting.</p>
<div class="btns"><a class="btn p" href="https://ph-panel.com/" rel="noopener noreferrer">ph-panel.com</a><a class="btn" href="https://ph-panel.com/docs" rel="noopener noreferrer">Docs</a><a class="btn" href="https://ph-panel.com/install" rel="noopener noreferrer">Install</a><a class="btn" href="https://ph-panel.com/donate" rel="noopener noreferrer">Support the project</a></div>
<p class="admin">Are you the administrator? <a href="@PANEL@">Sign in to your panel</a></p>
</section></main>
<footer>Made in the E.U.</footer></body></html>
'

landing_css_hash() { printf '%s' "$LANDING_CSS" | openssl dgst -sha256 -binary | openssl base64 -A; }

setup_landing() {
  local panel html
  if [[ -n ${PANEL_HOSTNAME:-} ]]; then panel="https://$PANEL_HOSTNAME:8443/"
  # shellcheck disable=SC2016
  else panel='https://{{$h := placeholder "http.request.host"}}{{if contains ":" $h}}[{{$h | html}}]{{else}}{{$h | html}}{{end}}:8443/'; fi
  html=${LANDING_HTML//@CSS@/$LANDING_CSS}; html=${html//@PANEL@/$panel}
  [[ $DRY_RUN == 1 ]] && { info "[dry-run] writing the landing page"; return 0; }
  install -d -m 755 /opt/phpanel/landing
  printf '%s\n' "$html" | write_file /opt/phpanel/landing/index.html 644
}

setup_caddy() {
  install -d -m 755 /opt/phpanel /var/lib/phpanel/acme
  # the Caddy fragments list every account's domains: root and the caddy user only
  if getent group caddy >/dev/null 2>&1; then install -d -m 750 -o root -g caddy /opt/phpanel/caddy; else install -d -m 755 /opt/phpanel/caddy; fi
  # site logs live in the account directories (group www-data); Caddy needs that group
  id caddy >/dev/null 2>&1 && usermod -aG www-data caddy || true
  # Caddy's admin API can reconfigure the whole web server, so it listens on a unix socket that only the caddy user (and root) can open,
  # never on a TCP port that every hosting account on the machine could reach. `caddy reload` finds the socket in the Caddyfile.
  local admin_was=""
  [[ -f /etc/caddy/Caddyfile ]] && admin_was=$(grep -m1 -E '^[[:space:]]*admin[[:space:]]' /etc/caddy/Caddyfile 2>/dev/null || true)
  write_file /etc/caddy/Caddyfile <<'CONF'
# Generated by PH-PANEL. Per-site fragments live in /opt/phpanel/caddy/ [02].
{
	admin unix//run/caddy/admin.sock|0600
	servers {
		metrics
	}
}
import /opt/phpanel/caddy/*.caddy
CONF
  # /run/caddy belongs to the caddy user and is closed to everybody else
  write_file /etc/systemd/system/caddy.service.d/phpanel-admin.conf <<'CONF'
# Generated by PH-PANEL: the admin socket of Caddy lives here, owned by caddy, closed to other users
[Service]
RuntimeDirectory=caddy
RuntimeDirectoryMode=0700
CONF
  # the loopback listener of the local web apps was a convenience for diagnostics that bypassed the panel's access rules: gone
  rm -f /opt/phpanel/caddy/20-webapps-local.caddy
  [[ $DRY_RUN == 1 ]] || systemctl daemon-reload >/dev/null 2>&1 || true
  # the page that visitors of the bare server address (or an unknown host name) see: static, self-contained, answers 404 so nothing indexes it as a site
  setup_landing
  # ACME webroot for the panel hostname [21]; anything else on :80 gets the landing page with status 404
  local css_hash; css_hash=$(landing_css_hash)
  write_file /opt/phpanel/caddy/00-acme.caddy <<CONF
:80 {
	handle /.well-known/acme-challenge/* {
		root * /var/lib/phpanel/acme
		file_server
	}
	handle {
		error "PH-PANEL" 404
	}
	handle_errors {
		root * /opt/phpanel/landing
		header Content-Type "text/html; charset=utf-8"
		header Content-Security-Policy "default-src 'none'; style-src 'sha256-$css_hash'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
		header X-Content-Type-Options nosniff
		header Referrer-Policy no-referrer
		header Cache-Control "no-store"
		header -Server
		rewrite * /index.html
		templates
		file_server
	}
}
CONF
  if [[ $DRY_RUN != 1 ]] && have caddy; then
    runuser -u caddy -- caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >>"$PHPANEL_LOG_FILE" 2>&1 \
      && ok "Caddyfile valid" || error "caddy validate failed (see $PHPANEL_LOG_FILE)"
    # a running Caddy keeps the old configuration until it is asked: an existing server gets the request metrics [70] only after a reload
    if systemctl is-active --quiet caddy 2>/dev/null; then
      if runuser -u caddy -- caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
        if [[ $admin_was == *2019* || ! -S /run/caddy/admin.sock ]]; then
          # the running Caddy still has its admin API on the TCP port: a reload cannot reach the new socket, so it starts again (a moment without web)
          run systemctl restart caddy && ok "Caddy restarted with its admin API on a private socket" || warn "Caddy did not restart; check it"
        else
          run systemctl reload caddy || true
        fi
      fi
    fi
  fi
}

setup_apache() {
  [[ -d /etc/apache2 ]] || { info "apache2 not installed, skipping"; return 0; }
  [[ $DRY_RUN == 1 ]] && { info "[dry-run] configuring Apache"; return 0; }
  # on 127.0.0.1 only, behind Caddy; 8079 = local mod_status for the Services page [53]
  printf 'Listen 127.0.0.1:8080\nListen 127.0.0.1:8079\n' >/etc/apache2/ports.conf
  sed -i 's/<VirtualHost \*:80>/<VirtualHost 127.0.0.1:8080>/; s/^\(\s*CustomLog\)/#\1/' /etc/apache2/sites-available/000-default.conf 2>/dev/null || true
  write_file /etc/apache2/sites-available/phpanel-status.conf <<'CONF'
<VirtualHost 127.0.0.1:8079>
    <Location "/server-status">
        SetHandler server-status
        Require local
    </Location>
</VirtualHost>
CONF
  local sl tpw mrw
  sl=$(pick 2 4 8 16); mrw=$(pick 50 100 200 400); tpw=25
  write_file /etc/apache2/conf-available/phpanel.conf <<CONF
# Generated by PH-PANEL [58]
ServerTokens Prod
ServerSignature Off
ExtendedStatus On
KeepAlive On
MaxKeepAliveRequests 1000
KeepAliveTimeout 60
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 127.0.0.1
<IfModule mpm_event_module>
    ServerLimit $sl
    StartServers 1
    ThreadsPerChild $tpw
    MinSpareThreads 25
    MaxSpareThreads 75
    MaxRequestWorkers $mrw
    MaxConnectionsPerChild 10000
</IfModule>
CONF
  # hosted domains: one file per domain in /opt/phpanel/apache, included here; unknown names get a plain 404
  install -d -m 750 /opt/phpanel/apache /opt/phpanel/php-pools
  write_file /opt/phpanel/apache/00-default.conf <<'CONF'
# PH-PANEL: unknown host names get a plain 404
<VirtualHost 127.0.0.1:8080>
    ServerName default.invalid
    RedirectMatch 404 ^
</VirtualHost>
CONF
  write_file /etc/apache2/conf-available/phpanel-sites.conf <<'CONF'
# PH-PANEL sites
IncludeOptional /opt/phpanel/apache/*.conf
CONF
  run a2enconf phpanel-sites || true
  # the packaged unit makes /home read-only, but site error logs are written there
  write_file /etc/systemd/system/apache2.service.d/phpanel.conf <<'CONF'
[Service]
ProtectHome=no
CONF
  run systemctl daemon-reload || true
  run a2dissite default-ssl || true
  run a2disconf other-vhosts-access-log || true
  run a2dismod -f mpm_prefork mpm_worker autoindex negotiation || true
  run a2enmod mpm_event proxy proxy_fcgi setenvif remoteip headers rewrite status security2 || true
  run a2enconf phpanel || true
  run a2ensite phpanel-status || true

  # ModSecurity: Detect on the minimal profile, Block on the rest; JSON audit [02][51]
  local ms=/etc/modsecurity/modsecurity.conf
  if [[ ! -f $ms && -f $ms-recommended ]]; then cp "$ms-recommended" "$ms"; fi
  if [[ -f $ms ]]; then
    sed -i "s/^SecRuleEngine .*/SecRuleEngine $(pick DetectionOnly On On On)/" "$ms"
    # the audit log is one JSON object per line for the panel's log analysis [51]; the packaged file has no SecAuditLogFormat line at all, so it
    # is set (or added), and only the parts the analysis needs are logged (headers, response headers and the rule messages, no bodies)
    if grep -q '^SecAuditLogFormat' "$ms"; then sed -i 's/^SecAuditLogFormat .*/SecAuditLogFormat JSON/' "$ms"; else printf '\n# PH-PANEL [51]\nSecAuditLogFormat JSON\n' >>"$ms"; fi
    sed -i 's/^SecAuditLogParts .*/SecAuditLogParts ABFHZ/' "$ms"
  else
    warn "ModSecurity: $ms is missing (libapache2-mod-security2 package)"
  fi
  # applications use PUT, PATCH and DELETE (Laravel and Symfony APIs); the rule set allows only GET, HEAD, POST and OPTIONS by default. This file is read
  # before the rule set, so the check for the method is switched off for these three and everything else stays as it is [59]
  write_file /etc/modsecurity/phpanel-methods.conf <<'CONF'
# PH-PANEL: PUT, PATCH and DELETE are normal for web applications
SecRule REQUEST_METHOD "@rx ^(PUT|PATCH|DELETE)$" "id:1009100,phase:1,pass,nolog,ctl:ruleRemoveById=911100"
CONF
  local incl; incl=$(apachectl -t -D DUMP_INCLUDES 2>/dev/null || true)
  if grep -qi 'crs\|owasp' <<<"$incl"; then ok "OWASP CRS loaded in Apache"
  else warn "OWASP CRS does not appear in the Apache configuration (modsecurity-crs); check that the rules are included"; fi
  run apachectl configtest && ok "apache2 configtest OK" || error "apachectl configtest failed"
}

setup_php() {
  local v pm f
  pm=$(pick ondemand ondemand dynamic dynamic)
  for v in ${PHP_INSTALLED:-}; do
    [[ -d /etc/php/$v/fpm ]] || continue
    write_file "/etc/php/$v/fpm/conf.d/99-phpanel.ini" <<CONF
; Generated by PH-PANEL [58]
expose_php=Off
mail.add_x_header=On
; mail() goes through the program of the panel: the sender must be the account's own, the hourly limit applies [28] [47]
sendmail_path=/usr/local/lib/phpanel/phpanel-sendmail -t -i
opcache.enable=1
opcache.memory_consumption=$(pick 64 128 192 256)
opcache.interned_strings_buffer=$(pick 8 16 16 32)
opcache.max_accelerated_files=$(pick 10000 20000 30000 50000)
opcache.validate_timestamps=1
opcache.revalidate_freq=2
CONF
    # per-domain pools live in /opt/phpanel/php-pools/<version>
    if [[ $DRY_RUN != 1 && -f /etc/php/$v/fpm/php-fpm.conf ]]; then
      install -d -m 755 "/opt/phpanel/php-pools/$v"  # (inside the closed php-pools folder)
      grep -qxF "include=/opt/phpanel/php-pools/$v/*.conf" "/etc/php/$v/fpm/php-fpm.conf" \
        || echo "include=/opt/phpanel/php-pools/$v/*.conf" >>"/etc/php/$v/fpm/php-fpm.conf"
    fi
    f=/etc/php/$v/fpm/pool.d/www.conf
    if [[ $DRY_RUN != 1 && -f $f ]]; then
      sed -i "s/^pm = .*/pm = $pm/" "$f"
      if [[ $pm == ondemand ]]; then
        grep -q '^pm.process_idle_timeout' "$f" \
          && sed -i 's/^pm.process_idle_timeout.*/pm.process_idle_timeout = 10s/' "$f" \
          || sed -i 's/^;pm.process_idle_timeout.*/pm.process_idle_timeout = 10s/' "$f"
      fi
    fi
  done
  ok "PHP-FPM: pm=$pm, OPcache per profile $PROFILE"
}

# The generated web configuration lists every account's domains, folders and PHP settings: not for hosting accounts to read. Caddy reads its
# fragments as the caddy user; Apache and PHP-FPM read theirs as root.
harden_web_config() {
  [[ $DRY_RUN == 1 ]] && return 0
  if [[ -d /opt/phpanel/caddy ]]; then chown root:caddy /opt/phpanel/caddy 2>/dev/null || true; chmod 750 /opt/phpanel/caddy; fi
  install -d -m 750 /opt/phpanel/domains   # the per-domain records; the panel creates the files (0640)
  local d; for d in /opt/phpanel/apache /opt/phpanel/php-pools /opt/phpanel/domains /var/log/phpanel-fpm; do [[ -d $d ]] && chmod 750 "$d"; done
  return 0
}

step_06_web() {
  setup_caddy
  if dns_only; then info "dns-only: no Apache or PHP"; harden_web_config; return 0; fi
  setup_apache
  setup_php
  harden_web_config
}
