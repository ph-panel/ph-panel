#!/usr/bin/env bash
# PH-PANEL - bootstrapper. Checks the minimum requirements, obtains the installer from the signed release
# channel of https://ph-panel.com, verifies it and starts it.
#   Public command (download, verify, run):
#     curl -fsSLO https://ph-panel.com/install.sh -O https://ph-panel.com/install.sh.minisig \
#       && minisign -Vm install.sh -P RWTdQ3rZTJw2cM8M2JeDTYHgcq/w0O7lbUXKbKHg/cNgavBfGoM25NZu && sudo bash install.sh [options]
#   From a local checkout or an extracted archive (phpanel-install.sh next to this file): sudo bash install.sh [options]
#
# What this script does before anything on the system is changed:
#   1. fetch latest.json and latest.json.minisig, verify them with the pinned public key below
#      (minisign is installed from the distribution package if it is missing) and check that the trusted
#      comment binds the manifest (file=latest.json version=X);
#   2. read the installer archive name, size and SHA-256 from the verified manifest, download the archive and its
#      .minisig, verify size, SHA-256, signature and trusted comment (file=NAME version=X);
#   3. refuse a manifest older than an installed panel (downgrade/replay) and an archive whose VERSION differs
#      from the manifest;
#   4. unpack into a root-owned 0700 temporary directory with strict tar checks, then run phpanel-install.sh.
# Any failure aborts there. There is no unsigned fallback.
#
# Developer overrides (environment variables; deliberately not documented anywhere else):
#   PHPANEL_SITE=<base URL>          read the release channel from another host (tests); http:// is accepted
#                                    only through this variable, and a warning is printed. The signing key stays pinned.
#   PHPANEL_ALLOW_UNSIGNED_DEV=1     with PHPANEL_ARCHIVE_URL=<url of a .tar.gz>: download and run an UNSIGNED archive
#                                    (development only, prints a loud warning, no verification of any kind).
set -Eeuo pipefail

PHPANEL_PUBKEY='RWTdQ3rZTJw2cM8M2JeDTYHgcq/w0O7lbUXKbKHg/cNgavBfGoM25NZu'
PHPANEL_KEY_ID='70369C4CD97A43DD'
DEFAULT_SITE='https://ph-panel.com'

die() { echo "Aborting: $*" >&2; exit 1; }
say() { echo "[ph-panel] $*"; }

[[ $EUID -eq 0 ]] || die "run as root: sudo bash install.sh"
[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die "bash 4+ is required"
[[ -r /etc/os-release ]] && . /etc/os-release
case "${ID:-}" in ubuntu|debian) ;; *) die "only Ubuntu and Debian are supported (found: ${PRETTY_NAME:-unknown})" ;; esac
case "$(dpkg --print-architecture)" in amd64|arm64) ;; *) die "unsupported architecture: $(dpkg --print-architecture)" ;; esac

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo /nonexistent)

# 1) run from the installer directory (development checkout / extracted archive)
if [[ -f $SELF_DIR/phpanel-install.sh ]]; then
  exec bash "$SELF_DIR/phpanel-install.sh" "$@"
fi

# ---------- helpers ----------
TMP=''
# shellcheck disable=SC2329
cleanup() { if [[ -n $TMP && -d $TMP ]]; then rm -rf "$TMP"; fi; return 0; }
trap cleanup EXIT
trap 'exit 130' INT TERM

apt_install() {   # apt_install PACKAGE... - the only change made to the system before verification
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q >/dev/null 2>&1 || die "apt-get update failed; cannot install: $*"
  apt-get install -y -q "$@" >/dev/null 2>&1 || die "could not install the package(s): $*"
}

# semver_cmp A B -> prints -1, 0 or 1. Core a.b.c numerically; no prerelease is newer than any prerelease;
# prerelease identifiers compare as in semver; the identifier "dev" (a development build) sorts below everything.
semver_cmp() {
  local a=$1 b=$2 ca cb pa='' pb='' i x y n
  local -a A B PA PB
  ca=${a%%-*}; cb=${b%%-*}
  [[ $a == *-* ]] && pa=${a#*-}
  [[ $b == *-* ]] && pb=${b#*-}
  IFS=. read -ra A <<<"$ca"; IFS=. read -ra B <<<"$cb"
  for i in 0 1 2; do
    x=$((10#${A[$i]})); y=$((10#${B[$i]}))
    if (( x < y )); then echo -1; return; fi
    if (( x > y )); then echo 1; return; fi
  done
  if [[ -z $pa && -z $pb ]]; then echo 0; return; fi
  if [[ -z $pa ]]; then echo 1; return; fi
  if [[ -z $pb ]]; then echo -1; return; fi
  IFS=. read -ra PA <<<"$pa"; IFS=. read -ra PB <<<"$pb"
  n=${#PA[@]}; if (( ${#PB[@]} > n )); then n=${#PB[@]}; fi
  for ((i = 0; i < n; i++)); do
    x=${PA[$i]:-}; y=${PB[$i]:-}
    if [[ -z $x ]]; then echo -1; return; fi
    if [[ -z $y ]]; then echo 1; return; fi
    [[ $x == "$y" ]] && continue
    if [[ $x == dev ]]; then echo -1; return; fi
    if [[ $y == dev ]]; then echo 1; return; fi
    if [[ $x =~ ^[0-9]+$ && $y =~ ^[0-9]+$ ]]; then
      if (( 10#$x < 10#$y )); then echo -1; else echo 1; fi; return
    fi
    if [[ $x =~ ^[0-9]+$ ]]; then echo -1; return; fi
    if [[ $y =~ ^[0-9]+$ ]]; then echo 1; return; fi
    if [[ $x < $y ]]; then echo -1; else echo 1; fi; return
  done
  echo 0
}

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$'

# safe_extract ARCHIVE DEST - strict checks first, then extraction without ownership, links or device files
safe_extract() {
  local archive=$1 dest=$2 names types name t n1 n2
  names=$(tar --quoting-style=escape -tzf "$archive" 2>/dev/null) || die "the archive is not a readable .tar.gz"
  types=$(tar --quoting-style=escape -tvzf "$archive" 2>/dev/null | cut -c1) || die "the archive is not a readable .tar.gz"
  n1=$(wc -l <<<"$names"); n2=$(wc -l <<<"$types")
  [[ -n $names && $n1 -eq $n2 ]] || die "the archive listing is inconsistent"
  while IFS= read -r name; do
    [[ $name =~ ^phpanel(/[A-Za-z0-9._+@=,-]+)*/?$ ]] || die "the archive contains an unexpected path: $name"
    [[ /$name/ != */../* ]] || die "the archive contains a '..' path: $name"
  done <<<"$names"
  while IFS= read -r t; do
    [[ $t == - || $t == d ]] || die "the archive contains a link, device or special file (type '$t')"
  done <<<"$types"
  tar -xzf "$archive" -C "$dest" --strip-components=1 --no-same-owner --no-same-permissions --no-overwrite-dir \
    || die "could not unpack the archive"
  chmod -R go-w "$dest"
}

# ---------- unsigned development path (loud) ----------
if [[ ${PHPANEL_ALLOW_UNSIGNED_DEV:-} == 1 ]]; then
  [[ -n ${PHPANEL_ARCHIVE_URL:-} ]] || die "PHPANEL_ALLOW_UNSIGNED_DEV=1 needs PHPANEL_ARCHIVE_URL"
  {
    echo "################################################################"
    echo "# WARNING: UNSIGNED DEVELOPMENT INSTALL - NO SIGNATURE, NO HASH  #"
    echo "# CHECK IS DONE. NEVER USE THIS ON A REAL SERVER.                #"
    echo "################################################################"
  } >&2
  command -v curl >/dev/null || apt_install curl ca-certificates
  TMP=$(mktemp -d /var/tmp/phpanel-install.XXXXXX); chmod 700 "$TMP"
  curl -fsSL -o "$TMP/archive.tar.gz" "$PHPANEL_ARCHIVE_URL" || die "could not download $PHPANEL_ARCHIVE_URL"
  mkdir "$TMP/x"; safe_extract "$TMP/archive.tar.gz" "$TMP/x"
  [[ -f $TMP/x/phpanel-install.sh ]] || die "the archive does not contain phpanel-install.sh"
  rc=0; bash "$TMP/x/phpanel-install.sh" "$@" || rc=$?
  exit "$rc"
fi

# ---------- the signed channel ----------
SITE=${PHPANEL_SITE:-$DEFAULT_SITE}
CURL_PROTO=(--proto '=https' --tlsv1.2)
if [[ $SITE != "$DEFAULT_SITE" ]]; then
  [[ $SITE =~ ^https?://[A-Za-z0-9.:-]+(/[A-Za-z0-9._~-]+)*$ ]] || die "PHPANEL_SITE is not a valid base URL (no trailing slash)"
  echo "WARNING: using the release channel $SITE instead of $DEFAULT_SITE (developer override). The signing key is still the pinned one." >&2
  [[ $SITE == http://* ]] && CURL_PROTO=(--proto '=http,https')
fi

command -v curl >/dev/null || apt_install curl ca-certificates
for t in tar gzip sha256sum awk; do command -v "$t" >/dev/null || die "required tool missing: $t"; done
if ! command -v minisign >/dev/null; then
  say "minisign is not installed; installing it from the distribution package"
  apt_install minisign
  command -v minisign >/dev/null || die "minisign could not be installed; install it manually (apt install minisign) and run again"
fi

TMP=$(mktemp -d /var/tmp/phpanel-install.XXXXXX) || die "cannot create a temporary directory"
chmod 700 "$TMP"
[[ $(stat -c '%u:%a' "$TMP") == 0:700 ]] || die "the temporary directory is not root-owned 0700"
mkdir "$TMP/dl" "$TMP/x"

fetch() {   # fetch URL OUTFILE MAXBYTES
  curl -fsS "${CURL_PROTO[@]}" --connect-timeout 15 --max-time 600 --max-filesize "$3" --retry 2 -o "$2" "$1" \
    || die "download failed (network error, missing file, or larger than the manifest allows): $1"
}

# verify_sig FILE SIGFILE NAME VERSION - signature with the pinned key and the trusted comment binding
verify_sig() {
  local file=$1 sig=$2 name=$3 version=$4 out tc w ok_f=0 ok_v=0
  out=$(minisign -V -m "$file" -x "$sig" -P "$PHPANEL_PUBKEY" 2>&1) \
    || die "the signature of $name is NOT valid for the PH-PANEL release key ($PHPANEL_KEY_ID); aborting"
  tc=$(sed -n 's/^Trusted comment: //p' <<<"$out")
  [[ -n $tc ]] || die "the signature of $name has no trusted comment; aborting"
  for w in $tc; do
    [[ $w == "file=$name" ]] && ok_f=1
    [[ $w == "version=$version" ]] && ok_v=1
  done
  [[ $ok_f == 1 ]] || die "the signature does not name this file (expected file=$name in the trusted comment); aborting"
  [[ $ok_v == 1 ]] || die "the signature is for another version (expected version=$version in the trusted comment); aborting"
  return 0
}

say "Fetching the release manifest from $SITE"
fetch "$SITE/latest.json" "$TMP/dl/latest.json" 1048576
fetch "$SITE/latest.json.minisig" "$TMP/dl/latest.json.minisig" 4096

# the signature is verified over the bytes before anything is read from the manifest
minisign -V -m "$TMP/dl/latest.json" -x "$TMP/dl/latest.json.minisig" -P "$PHPANEL_PUBKEY" >/dev/null 2>&1 \
  || die "the manifest signature is NOT valid for the PH-PANEL release key ($PHPANEL_KEY_ID); aborting"

# The manifest is generated in a fixed pretty-printed layout; the signature above makes its content trusted.
PARSED=$(awk '
  /^    "[a-z_]+": / { k=$1; gsub(/[":]/,"",k); v=$0; sub(/^    "[a-z_]+": /,"",v); sub(/,$/,"",v); gsub(/^"|"$/,"",v); print "T\t" k "\t" v; next }
  /^        \{$/ { n=""; kd=""; pl=""; sz=""; sh=""; next }
  /^            "(name|kind|platform|size|sha256)": / { k=$1; gsub(/[":]/,"",k); v=$0; sub(/^            "[a-z0-9]+": /,"",v); sub(/,$/,"",v); gsub(/^"|"$/,"",v);
      if (k=="name") n=v; else if (k=="kind") kd=v; else if (k=="platform") pl=v; else if (k=="size") sz=v; else sh=v; next }
  /^        \},?$/ { print "F\t" n "\t" kd "\t" pl "\t" sz "\t" sh }
' "$TMP/dl/latest.json") || die "cannot read the manifest"

m_get() { awk -F'\t' -v k="$1" '$1=="T" && $2==k {print $3}' <<<"$PARSED"; }
[[ $(m_get schema) == 2 ]] || die "unsupported manifest schema"
[[ $(m_get product) == PH-PANEL ]] || die "the manifest is not a PH-PANEL manifest"
[[ $(m_get key_id) == "$PHPANEL_KEY_ID" ]] || die "the manifest names another signing key"
[[ $(m_get version | wc -l) -eq 1 ]] || die "the manifest has no single version"
M_VERSION=$(m_get version)
[[ $M_VERSION =~ $VERSION_RE ]] || die "the manifest version is not valid: $M_VERSION"

# the trusted comment of the manifest signature must bind it: file=latest.json version=X
verify_sig "$TMP/dl/latest.json" "$TMP/dl/latest.json.minisig" latest.json "$M_VERSION"
say "Manifest verified: release $M_VERSION"

# downgrade / replay protection against an installed panel
if [[ -x /opt/phpanel/phpanel-web ]]; then
  INSTALLED=$(/opt/phpanel/phpanel-web version 2>/dev/null | head -n1 || true)
  [[ $INSTALLED =~ $VERSION_RE ]] || die "a panel is installed but its version cannot be read ('$INSTALLED'); refusing to continue"
  [[ $(semver_cmp "$M_VERSION" "$INSTALLED") -ge 0 ]] \
    || die "the release manifest ($M_VERSION) is older than the installed panel ($INSTALLED): downgrade refused"
fi

# the installer archive of this release
ARCH_NAME="phpanel-installer-$M_VERSION.tar.gz"
ARCH_LINE=$(awk -F'\t' -v n="$ARCH_NAME" '$1=="F" && $2==n && $3=="archive" && $4=="any" {print}' <<<"$PARSED")
[[ -n $ARCH_LINE && $(wc -l <<<"$ARCH_LINE") -eq 1 ]] || die "the manifest lists no installer archive named $ARCH_NAME"
IFS=$'\t' read -r _ _ _ _ A_SIZE A_SHA <<<"$ARCH_LINE"
[[ $A_SIZE =~ ^[0-9]+$ && $A_SIZE -gt 0 && $A_SIZE -le 67108864 ]] || die "the manifest gives an invalid archive size"
[[ $A_SHA =~ ^[0-9a-f]{64}$ ]] || die "the manifest gives an invalid archive SHA-256"

say "Downloading $ARCH_NAME ($A_SIZE bytes)"
fetch "$SITE/downloads/$M_VERSION/$ARCH_NAME" "$TMP/dl/$ARCH_NAME" "$A_SIZE"
fetch "$SITE/downloads/$M_VERSION/$ARCH_NAME.minisig" "$TMP/dl/$ARCH_NAME.minisig" 4096
[[ $(stat -c %s "$TMP/dl/$ARCH_NAME") -eq $A_SIZE ]] || die "the archive size differs from the manifest (truncated or altered download)"
[[ $(sha256sum "$TMP/dl/$ARCH_NAME" | cut -d' ' -f1) == "$A_SHA" ]] || die "the archive SHA-256 differs from the manifest; aborting"
verify_sig "$TMP/dl/$ARCH_NAME" "$TMP/dl/$ARCH_NAME.minisig" "$ARCH_NAME" "$M_VERSION"
say "Archive verified (size, SHA-256, signature, trusted comment)"

safe_extract "$TMP/dl/$ARCH_NAME" "$TMP/x"
[[ -f $TMP/x/phpanel-install.sh && -f $TMP/x/VERSION ]] || die "the archive does not contain phpanel-install.sh and VERSION"
[[ $(tr -d '\n' <"$TMP/x/VERSION") == "$M_VERSION" ]] || die "the archive VERSION differs from the manifest version; aborting"

say "Starting the installer $M_VERSION"
rc=0
bash "$TMP/x/phpanel-install.sh" "$@" || rc=$?
exit "$rc"
