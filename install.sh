#!/usr/bin/env bash
# PH-PANEL – bootstrapper. Checks the minimum requirements, obtains the installer and starts it.
#   From the repo (local): sudo bash install.sh [options]
#   From the internet:     curl -fsSL <URL>/install.sh | sudo bash -s -- [options]
set -Eeuo pipefail

# Default source: the public GitHub repository (no Releases yet, no signature yet - development only).
PHPANEL_REPO=${PHPANEL_REPO:-ph-panel/ph-panel}
PHPANEL_REF=${PHPANEL_REF:-main}
PHPANEL_ARCHIVE_URL=${PHPANEL_ARCHIVE_URL:-"https://github.com/$PHPANEL_REPO/archive/refs/heads/$PHPANEL_REF.tar.gz"}
# When a release is signed, set these two instead (see README).
PHPANEL_RELEASE_URL=${PHPANEL_RELEASE_URL:-""}
PHPANEL_MINISIGN_PUBKEY=${PHPANEL_MINISIGN_PUBKEY:-""}

die() { echo "Aborting: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root: sudo bash install.sh"
[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die "bash 4+ is required"
[[ -r /etc/os-release ]] && . /etc/os-release
case "${ID:-}" in ubuntu|debian) ;; *) die "only Ubuntu and Debian are supported (found: ${PRETTY_NAME:-unknown})" ;; esac
case "$(dpkg --print-architecture)" in amd64|arm64) ;; *) die "unsupported architecture: $(dpkg --print-architecture)" ;; esac

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo /tmp)

# 1) run from the installer directory (development / extracted archive)
if [[ -f $SELF_DIR/phpanel-install.sh ]]; then
  exec bash "$SELF_DIR/phpanel-install.sh" "$@"
fi

# 2) download the installer
command -v curl >/dev/null || { apt-get update -q && apt-get install -y -q curl ca-certificates; }
WORK=/opt/phpanel-installer
rm -rf "$WORK"; mkdir -p "$WORK"

if [[ -n $PHPANEL_RELEASE_URL && -n $PHPANEL_MINISIGN_PUBKEY ]]; then
  echo "Downloading the signed installer from $PHPANEL_RELEASE_URL ..."
  curl -fsSL -o "$WORK/phpanel-installer.tar.gz" "$PHPANEL_RELEASE_URL/phpanel-installer.tar.gz" \
    || die "could not download the installer"
  command -v minisign >/dev/null || apt-get install -y -q minisign >/dev/null
  curl -fsSL -o "$WORK/phpanel-installer.tar.gz.minisig" "$PHPANEL_RELEASE_URL/phpanel-installer.tar.gz.minisig" \
    || die "the installer signature is missing"
  minisign -Vm "$WORK/phpanel-installer.tar.gz" -P "$PHPANEL_MINISIGN_PUBKEY" >/dev/null \
    || die "the installer signature is NOT valid; aborting installation"
  echo "Signature verified."
  tar -xzf "$WORK/phpanel-installer.tar.gz" -C "$WORK"
else
  echo "Downloading the installer from $PHPANEL_ARCHIVE_URL ..."
  echo "Warning: unsigned development download (no signature verification yet)." >&2
  curl -fsSL -o "$WORK/phpanel-installer.tar.gz" "$PHPANEL_ARCHIVE_URL" || die "could not download the installer"
  tar -xzf "$WORK/phpanel-installer.tar.gz" -C "$WORK" --strip-components=1
fi
[[ -f $WORK/phpanel-install.sh ]] || die "the downloaded archive does not contain phpanel-install.sh"
exec bash "$WORK/phpanel-install.sh" "$@"
