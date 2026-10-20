#!/usr/bin/env bash
# PH-PANEL installer – common functions. Sourced from phpanel-install.sh.

PHPANEL_STATE_DIR=/var/lib/phpanel
PHPANEL_STATE_FILE=$PHPANEL_STATE_DIR/install-state
PHPANEL_FACTS_FILE=$PHPANEL_STATE_DIR/facts.env
PHPANEL_REPORT_FILE=$PHPANEL_STATE_DIR/install-report.txt
PHPANEL_LOG_FILE=/var/log/phpanel-install.log
POLICY_RC=/usr/sbin/policy-rc.d

DRY_RUN=${DRY_RUN:-0}
CURRENT_STEP=${CURRENT_STEP:-init}

if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_RED=$'\e[31m'; C_YEL=$'\e[33m'; C_GRN=$'\e[32m'; C_DIM=$'\e[2m'
else
  C_RESET=; C_BOLD=; C_RED=; C_YEL=; C_GRN=; C_DIM=
fi

_ts() { date '+%Y-%m-%d %H:%M:%S'; }
_logfile() { printf '%s [%s] %s\n' "$(_ts)" "$CURRENT_STEP" "$*" >>"$PHPANEL_LOG_FILE" 2>/dev/null || true; }

info()  { printf '%s\n' "  $*"; _logfile "INFO $*"; }
ok()    { printf '%s\n' "  ${C_GRN}✓${C_RESET} $*"; _logfile "OK $*"; }
warn()  { printf '%s\n' "  ${C_YEL}!${C_RESET} $*" >&2; _logfile "WARN $*"; report "WARN" "$*"; }
error() { printf '%s\n' "  ${C_RED}✗${C_RESET} $*" >&2; _logfile "ERROR $*"; report "ERROR" "$*"; }
die()   { printf '%s\n' "${C_RED}${C_BOLD}Aborting:${C_RESET} $*" >&2; _logfile "FATAL $*"; exit 1; }
step_title() { printf '\n%s\n' "${C_BOLD}[$1] $2${C_RESET}"; _logfile "=== $1 $2"; }

# report LEVEL MESSAGE – collects problems for the final summary
report() { printf '%s\t%s\t%s\n' "$1" "$CURRENT_STEP" "$2" >>"$PHPANEL_REPORT_FILE" 2>/dev/null || true; }

# run CMD... – executes (or only prints, with --dry-run); full output goes to the log
run() {
  if [[ $DRY_RUN == 1 ]]; then
    printf '%s\n' "  ${C_DIM}[dry-run] $*${C_RESET}"
    return 0
  fi
  _logfile "RUN $*"
  "$@" >>"$PHPANEL_LOG_FILE" 2>&1
}

# Step state: a completed step is not run again (idempotent installer).
step_done()  { grep -qx "$1" "$PHPANEL_STATE_FILE" 2>/dev/null; }
mark_done()  { [[ $DRY_RUN == 1 ]] || echo "$1" >>"$PHPANEL_STATE_FILE"; }

fact_set() {
  # fact_set KEY VALUE – saved for the following steps and for the daemon
  local k=$1 v=$2
  [[ $DRY_RUN == 1 ]] && { eval "$k=\$v"; return; }
  touch "$PHPANEL_FACTS_FILE"
  sed -i "/^${k}=/d" "$PHPANEL_FACTS_FILE"
  printf '%s=%q\n' "$k" "$v" >>"$PHPANEL_FACTS_FILE"
  eval "$k=\$v"
}
facts_load() {
  if [[ -f $PHPANEL_FACTS_FILE ]]; then . "$PHPANEL_FACTS_FILE"; fi
  # a profile name from an older release is not recognised: derive it again from the RAM size
  case ${PROFILE:-} in
    minimal|small|standard|large|'') ;;
    *) [[ -n ${MEM_MB:-} ]] && fact_set PROFILE "$(profile_from_mem "$MEM_MB")" ;;
  esac
}

# ---------- apt ----------

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Dpkg::Use-Pty=0)

apt_wait_lock() {
  local i
  for i in $(seq 1 60); do
    if ! fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1; then return 0; fi
    [[ $i == 1 ]] && info "waiting for apt to be released (another process is running)..."
    sleep 5
  done
  die "apt has been locked by another process for over 5 minutes"
}

apt_update() {
  apt_wait_lock
  run apt-get update -q
}

# pkg_available PACKAGE – is it available in the configured repos?
pkg_available() {
  local cand
  cand=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}') || true
  [[ -n $cand && $cand != "(none)" ]]
}

# apt_install_group NAME PACKAGE... – installs a group; on failure, retries package by package
# so we know exactly what failed. Packages missing from the repos are reported, they do not stop the installation.
apt_install_group() {
  local group=$1; shift
  local want=() missing=() p
  for p in "$@"; do
    if pkg_available "$p"; then want+=("$p"); else missing+=("$p"); fi
  done
  for p in "${missing[@]}"; do
    warn "[$group] package unavailable in the configured repos: $p"
  done
  [[ ${#want[@]} -eq 0 ]] && return 0
  apt_wait_lock
  if run apt-get install "${APT_OPTS[@]}" --no-install-recommends "${want[@]}"; then
    ok "[$group] ${#want[@]} packages installed"
    return 0
  fi
  warn "[$group] group installation failed; retrying package by package"
  local failed=0
  for p in "${want[@]}"; do
    apt_wait_lock
    if run apt-get install "${APT_OPTS[@]}" --no-install-recommends "$p"; then
      _logfile "OK $p"
    else
      error "[$group] error installing package: $p (details in $PHPANEL_LOG_FILE)"
      failed=$((failed + 1))
      run apt-get -f install "${APT_OPTS[@]}" || true
    fi
  done
  [[ $failed -eq 0 ]] && ok "[$group] installed after retry"
  return 0
}

# ---------- services: they do not start while packages are being installed ----------
# policy-rc.d with exit 101 stops the automatic start from postinst; ports are
# configured only after installation, so we avoid conflicts (e.g. :53, :80).
services_block()   { [[ $DRY_RUN == 1 ]] && return; printf '#!/bin/sh\nexit 101\n' >"$POLICY_RC"; chmod 755 "$POLICY_RC"; }
services_unblock() { rm -f "$POLICY_RC"; }

# ---------- utilities ----------

have() { command -v "$1" >/dev/null 2>&1; }

is_private_ip() {
  local ip=$1
  [[ $ip =~ ^10\. || $ip =~ ^192\.168\. || $ip =~ ^172\.(1[6-9]|2[0-9]|3[01])\. || $ip =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\. ]]
}

# public_ip – majority result from several external services
public_ip() {
  local s ip results=()
  for s in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    ip=$(curl -4 -fsS --max-time 6 "$s" 2>/dev/null | tr -d '[:space:]')
    [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && results+=("$ip")
  done
  [[ ${#results[@]} -eq 0 ]] && return 1
  printf '%s\n' "${results[@]}" | sort | uniq -c | sort -rn | awk 'NR==1 {print $2}'
}

primary_ipv4() { ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'; }

# ---------- generated files ----------

# write_file DEST [MODE] – writes stdin to DEST only if it changed (idempotent)
write_file() {
  local dest=$1 mode=${2:-644} tmp
  tmp=$(mktemp)
  cat >"$tmp"
  if [[ $DRY_RUN == 1 ]]; then
    info "[dry-run] writing $dest"; rm -f "$tmp"; return 0
  fi
  install -d "$(dirname "$dest")"
  if [[ -f $dest ]] && cmp -s "$tmp" "$dest"; then
    chmod "$mode" "$dest"
  else
    install -m "$mode" "$tmp" "$dest"
    _logfile "WRITE $dest"
  fi
  rm -f "$tmp"
}

# profile_from_mem MB – resource profile name for a RAM size [43]
profile_from_mem() {
  local mb=$1
  if (( mb < 1536 )); then echo minimal
  elif (( mb < 4096 )); then echo small
  elif (( mb < 8192 )); then echo standard
  else echo large
  fi
}

# pick MINIMAL SMALL STANDARD LARGE – the value matching the resource profile [43]
pick() {
  case ${PROFILE:-standard} in
    minimal) echo "$1" ;;
    small) echo "$2" ;;
    standard) echo "$3" ;;
    *) echo "$4" ;;
  esac
}

# ensure_selfsigned DIR CN [SAN] – temporary fullchain.pem + privkey.pem (replaced by cert-sync [14])
ensure_selfsigned() {
  local dir=$1 cn=$2 san=${3:-DNS:$2}
  [[ $DRY_RUN == 1 ]] && return 0
  [[ -s $dir/fullchain.pem && -s $dir/privkey.pem ]] && return 0
  install -d -m 755 "$dir"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 397 \
    -subj "/CN=$cn" -addext "subjectAltName=$san" -keyout "$dir/privkey.pem" -out "$dir/fullchain.pem" \
    >>"$PHPANEL_LOG_FILE" 2>&1 || { warn "could not generate the temporary certificate $dir"; return 1; }
  chmod 600 "$dir/privkey.pem"; chmod 644 "$dir/fullchain.pem"
}
