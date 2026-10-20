#!/usr/bin/env bash
# PH-PANEL – main installation script (phase 1: packages + base services + authentication daemon).
set -Eeuo pipefail

INSTALLER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PHPANEL_VERSION=$(cat "$INSTALLER_DIR/VERSION" 2>/dev/null || echo 0.1.0-dev)

usage() {
  cat <<EOF
PH-PANEL installer $PHPANEL_VERSION

Usage: sudo bash phpanel-install.sh [options]

  --hostname FQDN         the panel hostname (e.g. panel.example.com)
  --public-ip IP          the public IP, if auto-detection is wrong (servers on a LAN)
  --profile P             auto|minimal|small|standard|large (default: auto, based on RAM)
  --php LIST              auto|all|8.4,7.4,... (default: based on profile)
  --admin-email EMAIL     the first administrator's email
  --admin-username NAME   the administrator's server account name (default: admin plus four random digits, e.g. admin3738)
  --no-panel              install only the stack, without the panel daemon
  --only STEPS            run only the given steps (e.g. 03,04)
  --force                 also re-run steps that already completed
  --dry-run               show what would be done, without making changes
  -h, --help              this message
EOF
}

OPT_HOSTNAME='' OPT_PUBLIC_IP='' OPT_PROFILE=auto OPT_PHP=auto OPT_ADMIN_EMAIL='' OPT_ADMIN_USERNAME='' OPT_NO_PANEL=0 OPT_ONLY='' OPT_FORCE=0
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --hostname) OPT_HOSTNAME=${2,,}; shift 2 ;;
    --public-ip) OPT_PUBLIC_IP=$2; shift 2 ;;
    --profile) OPT_PROFILE=$2; shift 2 ;;
    --php) OPT_PHP=$2; shift 2 ;;
    --admin-email) OPT_ADMIN_EMAIL=$2; shift 2 ;;
    --admin-username) OPT_ADMIN_USERNAME=${2,,}; shift 2 ;;
    --no-panel) OPT_NO_PANEL=1; shift ;;
    --only) OPT_ONLY=$2; shift 2 ;;
    --force) OPT_FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done
export DRY_RUN

. "$INSTALLER_DIR/lib/common.sh"
for f in "$INSTALLER_DIR"/steps/[0-9][0-9]-*.sh; do . "$f"; done

[[ $EUID -eq 0 ]] || die "run as root: sudo bash $0"
install -d -m 755 "$PHPANEL_STATE_DIR"
touch "$PHPANEL_LOG_FILE"; chmod 600 "$PHPANEL_LOG_FILE"
: >"$PHPANEL_REPORT_FILE"

on_error() {
  local rc=$? line=$1
  services_unblock
  error "unexpected error in step '$CURRENT_STEP', line $line (code $rc). Details: $PHPANEL_LOG_FILE"
  exit "$rc"
}
trap 'on_error $LINENO' ERR
trap 'services_unblock' EXIT   # policy-rc.d never stays on the system

STEPS=(
  "01:preflight:Initial checks"
  "02:profile:Resource profile and swap"
  "03:repos:Vendor repositories"
  "04:packages:Package installation"
  "05:system:System configuration (local DNS, firewall, quotas)"
  "06:web:Web configuration (Caddy, Apache, PHP)"
  "07:data:Data and access configuration (MariaDB, Knot, FTP, Fail2Ban)"
  "08:mail:Mail configuration (Postfix, Dovecot, Rspamd)"
  "09:webapps:Webmail and phpMyAdmin"
  "10:maint:Maintenance (DB dump, health check, cron)"
  "11:services:Starting services"
  "12:panel:Panel daemon (authentication)"
  "13:letsencrypt:Let's Encrypt certificate for the panel"
)

printf '%s\n' "${C_BOLD}PH-PANEL installer $PHPANEL_VERSION${C_RESET}  (log: $PHPANEL_LOG_FILE)"
[[ $DRY_RUN == 1 ]] && printf '%s\n' "${C_YEL}Dry-run mode: nothing is modified.${C_RESET}"
_logfile "=== start $PHPANEL_VERSION args: hostname=$OPT_HOSTNAME profile=$OPT_PROFILE php=$OPT_PHP no_panel=$OPT_NO_PANEL dry=$DRY_RUN"

facts_load
for entry in "${STEPS[@]}"; do
  IFS=: read -r num name title <<<"$entry"
  if [[ -n $OPT_ONLY && ",$OPT_ONLY," != *",$num,"* ]]; then continue; fi
  CURRENT_STEP="$num-$name"
  step_title "$num" "$title"
  # step 01 always runs: it refreshes the facts the other steps depend on
  if [[ $num != 01 && $OPT_FORCE == 0 ]] && step_done "$CURRENT_STEP"; then
    info "already done, skipping (use --force to run again)"
    continue
  fi
  "step_${num}_${name}"
  mark_done "$CURRENT_STEP"
done
CURRENT_STEP=final

# ---------- summary ----------
printf '\n%s\n' "${C_BOLD}Summary${C_RESET}"
n_err=$(grep -c '^ERROR' "$PHPANEL_REPORT_FILE" || true)
n_warn=$(grep -c '^WARN' "$PHPANEL_REPORT_FILE" || true)
if [[ $n_err -eq 0 && $n_warn -eq 0 ]]; then
  ok "no errors or warnings"
else
  [[ $n_err -gt 0 ]] && { printf '%s\n' "  ${C_RED}Errors ($n_err):${C_RESET}"; awk -F'\t' '$1=="ERROR" {print "   - [" $2 "] " $3}' "$PHPANEL_REPORT_FILE"; }
  [[ $n_warn -gt 0 ]] && { printf '%s\n' "  ${C_YEL}Warnings ($n_warn):${C_RESET}"; awk -F'\t' '$1=="WARN" {print "   - [" $2 "] " $3}' "$PHPANEL_REPORT_FILE"; }
  info "full report: $PHPANEL_REPORT_FILE"
fi

facts_load

# access_summary – URLs, ports and the first login; also saved to /root/.phpanel/access.txt (0600)
access_summary() {
  local email='' username='' password='' urls=() u row port label state where=''
  [[ ${NAT_MODE:-0} == 1 ]] && where=' / router'
  install -d -m 700 /root/.phpanel
  if [[ -f /root/.phpanel/admin-initial.txt ]]; then
    email=$(sed -n 's/^email=//p' /root/.phpanel/admin-initial.txt)
    password=$(sed -n 's/^password=//p' /root/.phpanel/admin-initial.txt)
    username=$(sed -n 's/^username=//p' /root/.phpanel/admin-initial.txt)
    # installs made before usernames were generated have no username line: ask the panel
    if [[ -z $username && -x /opt/phpanel/phpanel-web ]]; then
      username=$(runuser -u phpanel -- /opt/phpanel/phpanel-web user list --data /opt/phpanel/data 2>/dev/null | awk -v e="$email" '$2==e {print $NF}')
    fi
  fi
  [[ -n ${PANEL_HOSTNAME:-} ]] && urls+=("https://$PANEL_HOSTNAME:8443|hostname")
  [[ -n ${IP_PUBLIC:-} ]] && urls+=("https://$IP_PUBLIC:8443|public IP")
  [[ -n ${IP_LOCAL:-} && ${IP_LOCAL:-} != "${IP_PUBLIC:-}" ]] && urls+=("https://$IP_LOCAL:8443|local network")
  [[ ${#urls[@]} -gt 0 ]] || urls+=("https://127.0.0.1:8443|this server only")

  printf '%s\n' "${C_BOLD}PH-PANEL is ready${C_RESET}"
  printf '\n%s\n' "${C_BOLD}Panel URLs${C_RESET}"
  for u in "${urls[@]}"; do printf '  %-40s (%s)\n' "${u%%|*}" "${u##*|}"; done
  printf '\n%s\n' "${C_BOLD}Login${C_RESET}"
  if [[ -n $email ]]; then
    printf '  user:      %s\n' "$email"
    [[ -z $username ]] || printf '  username:  %s   (the administrator'"'"'s server account name)\n' "$username"
    printf '  password:  %s\n' "$password"
    printf '  (saved in /root/.phpanel/admin-initial.txt; change the password after the first login)\n'
  else
    printf '  no administrator was created; create one with: phpanel-web admin create --data /opt/phpanel/data --email you@example.com\n'
  fi
  printf '\n%s\n' "${C_BOLD}Ports${C_RESET}  (open them in your provider firewall${where}; state is what this server listens on now)"
  for row in "22|SSH" "80|HTTP (Caddy, ACME)" "443|HTTPS (Caddy, sites)" "8443|PH-PANEL panel and API" \
             "25|SMTP" "465|SMTPS" "587|Mail submission" "993|IMAPS" "995|POP3S" "21|FTP (TLS)" "53|DNS (TCP and UDP)"; do
    port=${row%%|*}; label=${row#*|}
    if ss -ltnH "sport = :$port" 2>/dev/null | grep -q .; then state=listening
    elif [[ $port == 443 ]]; then state='starts with the first site'
    else state='not listening'; fi
    printf '  %-6s %-30s %s\n' "$port" "$label" "$state"
  done
  printf '  %-6s %-30s %s\n' "30000-31000" "FTP passive range" "(opened by the firewall)"
  [[ ${NAT_MODE:-0} == 1 ]] && printf '  Behind NAT: forward these ports from the router to %s.\n' "${IP_LOCAL:-this server}"
  if [[ -z ${PANEL_HOSTNAME:-} ]]; then
    printf '\n  No --hostname was given: the panel uses a self-signed certificate; the browser will show a warning.\n'
  else
    case ${LE_STATUS:-skipped} in
      issued) printf "\n  Certificate: Let's Encrypt (renewed automatically at 02:30).\n" ;;
      *) printf "\n  Certificate: self-signed for now (Let's Encrypt: %s). Check that %s points to this server and port 80 is open; the daily job retries. Log: /opt/phpanel/logs/le.log\n" "${LE_STATUS:-skipped}" "$PANEL_HOSTNAME" ;;
    esac
  fi
}

if [[ $DRY_RUN != 1 ]]; then
  printf '\n'
  access_summary | tee >(sed 's/\x1b\[[0-9;]*m//g' >/root/.phpanel/access.txt) 
  chmod 600 /root/.phpanel/access.txt 2>/dev/null || true
fi
[[ $n_err -eq 0 ]] || exit 3
