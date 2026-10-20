#!/usr/bin/env bash
# Step 01 – pre-installation checks. Does not modify the system (apart from facts.env).

step_01_preflight() {
  [[ $EUID -eq 0 ]] || die "run the installer as root (sudo)"
  have systemctl || die "systemd is required"

  # --- operating system ---
  [[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
  . /etc/os-release
  local os="$ID" ver="$VERSION_ID" codename="${VERSION_CODENAME:-}"
  case "$os:$ver" in
    ubuntu:24.04|ubuntu:26.04|debian:12|debian:13)
      ok "supported system: $PRETTY_NAME" ;;
    ubuntu:22.04)
      warn "Ubuntu 22.04: the PHP Sury repo may no longer cover it; only the available PHP versions will be installed" ;;
    *)
      die "unsupported system: ${PRETTY_NAME:-$os $ver}. Supported: Ubuntu 24.04/26.04, Debian 12/13" ;;
  esac
  [[ -n $codename ]] || die "cannot determine the release name (VERSION_CODENAME)"
  fact_set OS_ID "$os"; fact_set OS_VERSION "$ver"; fact_set OS_CODENAME "$codename"

  # --- architecture ---
  local arch; arch=$(dpkg --print-architecture)
  case "$arch" in
    amd64|arm64) ok "architecture: $arch" ;;
    *) die "unsupported architecture: $arch (supported: amd64, arm64)" ;;
  esac
  fact_set ARCH "$arch"

  # --- the administrator's server account name (only matters before the first administrator exists) ---
  if [[ -n ${OPT_ADMIN_USERNAME:-} && ! -s /opt/phpanel/data/panel.db ]]; then
    local checker="$INSTALLER_DIR/bin/phpanel-web-linux-$arch" verdict
    if [[ -x $checker ]]; then
      verdict=$("$checker" username check "$OPT_ADMIN_USERNAME" 2>&1) || die "--admin-username: ${verdict#error: }"
    elif [[ ! $OPT_ADMIN_USERNAME =~ ^[a-z][a-z0-9]{2,31}$ ]]; then
      die "--admin-username: use 3 to 32 lowercase letters or digits, starting with a letter"
    fi
    ok "administrator username: $OPT_ADMIN_USERNAME"
  fi

  # --- the server must be clean: no web, mail, DNS or database stack installed yet ---
  # (skipped when this installer already ran here, or with PHPANEL_ALLOW_DIRTY=1)
  if [[ ! -f $PHPANEL_STATE_FILE && ${PHPANEL_ALLOW_DIRTY:-0} != 1 ]]; then
    local p found=()
    for p in apache2 nginx postfix exim4 dovecot-core bind9 mysql-server mariadb-server; do
      dpkg -s "$p" >/dev/null 2>&1 && found+=("$p")
    done
    [[ ${#found[@]} -eq 0 ]] || die "this server is not clean (already installed: ${found[*]}). PH-PANEL needs a fresh server; set PHPANEL_ALLOW_DIRTY=1 to override at your own risk."
  fi

  # --- resources ---
  local mem_mb disk_gb cpus
  mem_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
  cpus=$(nproc)
  disk_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
  info "resources: ${cpus} vCPU, ${mem_mb} MB RAM, ${disk_gb} GB free on /"
  (( mem_mb < 900 )) && warn "under 1 GB RAM: the installation may be slow or may fail"
  (( disk_gb < 6 )) && die "insufficient free space on / (${disk_gb} GB; at least ~6 GB needed for packages)"
  (( disk_gb < 10 )) && warn "under 10 GB free on /: little space will be left for websites"
  fact_set MEM_MB "$mem_mb"; fact_set CPUS "$cpus"; fact_set DISK_FREE_GB "$disk_gb"

  # --- network ---
  if curl -fsS --max-time 10 -o /dev/null https://deb.debian.org/ || curl -fsS --max-time 10 -o /dev/null http://archive.ubuntu.com/; then
    ok "internet access"
  else
    die "no internet access (required for the repos)"
  fi

  local lan_ip pub_ip
  lan_ip=$(primary_ipv4)
  pub_ip=${OPT_PUBLIC_IP:-$(public_ip || true)}
  [[ -n $lan_ip ]] || warn "no IPv4 address found on the interfaces"
  [[ -n $pub_ip ]] || warn "could not determine the public IP; use --public-ip"
  fact_set IP_LOCAL "${lan_ip:-}"; fact_set IP_PUBLIC "${pub_ip:-}"
  if [[ -n $lan_ip ]] && is_private_ip "$lan_ip"; then
    fact_set NAT_MODE 1
    info "NAT mode: internal IP $lan_ip, public IP ${pub_ip:-unknown} [54]"
  else
    fact_set NAT_MODE 0
    info "public IP on the interface: ${lan_ip:-?}"
  fi

  # --- hostname ---
  if [[ -n ${OPT_HOSTNAME:-} ]]; then
    [[ $OPT_HOSTNAME =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$ ]] || die "invalid --hostname: $OPT_HOSTNAME"
    # public DNS first (dig), because /etc/hosts may map the hostname to 127.0.0.1; getent only when dig is not installed yet
    local resolved
    if have dig; then resolved=$(dig +short +time=3 +tries=1 A "$OPT_HOSTNAME" @1.1.1.1 2>/dev/null | grep -E '^[0-9.]+$' | head -1) || true; fi
    [[ -n ${resolved:-} ]] || resolved=$(getent ahostsv4 "$OPT_HOSTNAME" 2>/dev/null | awk 'NR==1 {print $1}') || true
    if [[ -n $resolved && $resolved == "${pub_ip:-x}" ]]; then
      ok "hostname $OPT_HOSTNAME resolves to the public IP"
    else
      warn "hostname $OPT_HOSTNAME resolves to '${resolved:-nothing}', not to ${pub_ip:-the public IP}; the panel will use a self-signed certificate"
    fi
    fact_set PANEL_HOSTNAME "$OPT_HOSTNAME"
  else
    fact_set PANEL_HOSTNAME ""
    info "no --hostname: the panel will run on the IP, with a self-signed certificate"
  fi

  # --- outbound port 25 [46] ---
  local mx open=0
  for mx in gmail-smtp-in.l.google.com outlook-com.olc.protection.outlook.com; do
    if timeout 8 bash -c "exec 3<>/dev/tcp/$mx/25" 2>/dev/null; then open=1; break; fi
  done
  if (( open )); then
    ok "outbound port 25 is open"; fact_set PORT25_OUT open
  else
    warn "outbound port 25 appears to be blocked by the provider: the server will not be able to send mail directly (see SMTP relay [46])"
    fact_set PORT25_OUT blocked
  fi

  # --- preinstalled iptables rules (e.g. Oracle Cloud) [46] ---
  if [[ -f /etc/iptables/rules.v4 ]] && grep -q 'REJECT' /etc/iptables/rules.v4 2>/dev/null; then
    warn "preinstalled iptables rules exist (/etc/iptables/rules.v4) that may block ports; they will be replaced when nftables is configured"
  fi
}
