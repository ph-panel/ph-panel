#!/usr/bin/env bash
# Step 03 – vendor repositories. Each repo is tested separately; one that has no packages
# for this release stays in the sources and is only reported (REPO_MISSING), so we can see where we lack a repo.

KEYRING_DIR=/etc/apt/keyrings

# repo_test LIST_FILE – runs apt update only for that file
repo_test() {
  local list=$1
  [[ $DRY_RUN == 1 ]] && return 0
  local out rc
  out=$(apt-get update -q -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts=- \
        -o APT::Get::List-Cleanup=0 2>&1); rc=$?
  printf '%s\n' "$out" >>"$PHPANEL_LOG_FILE"
  [[ $rc -eq 0 ]] && ! grep -qE '^(E:|Err:)|does not have a Release file' <<<"$out"
}

# repo_add NAME LIST_FILE DEB_LINE – writes the list, tests it, removes it if it does not work
repo_add() {
  local name=$1 list=$2 line=$3
  if [[ $DRY_RUN == 1 ]]; then info "[dry-run] repo $name: $line"; return 0; fi
  echo "$line" >"$list"
  if repo_test "$list"; then
    ok "repo $name for $OS_CODENAME"
  else
    error "repo $name: no packages for $OS_CODENAME or unreachable (leaving it in the sources)"
    REPO_MISSING="${REPO_MISSING:-} $name"
  fi
}

fetch_key() { # fetch_key URL DESTINATION [dearmor]
  local url=$1 dest=$2 mode=${3:-}
  if [[ $DRY_RUN == 1 ]]; then info "[dry-run] key $url -> $dest"; return 0; fi
  if [[ $mode == dearmor ]]; then
    curl -fsSL --max-time 30 "$url" | gpg --batch --yes --dearmor -o "$dest"
  else
    curl -fsSL --max-time 30 -o "$dest" "$url"
  fi
  chmod 644 "$dest"
}

step_03_repos() {
  apt_update
  apt_install_group "prerequisites" ca-certificates curl gnupg apt-transport-https lsb-release
  run install -d -m 755 "$KEYRING_DIR"

  # Caddy – official apt repo (same repo for all releases)
  if fetch_key https://dl.cloudsmith.io/public/caddy/stable/gpg.key "$KEYRING_DIR/caddy-stable.gpg" dearmor; then
    repo_add caddy /etc/apt/sources.list.d/caddy-stable.list \
      "deb [signed-by=$KEYRING_DIR/caddy-stable.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main"
  else error "could not download the Caddy repo key"; fi

  # Knot DNS – repo CZ.NIC (catalog zones + change of ownership)
  if fetch_key https://pkg.labs.nic.cz/gpg "$KEYRING_DIR/cznic-labs-pkg.gpg"; then
    repo_add knot-dns /etc/apt/sources.list.d/cznic-knot-dns.list \
      "deb [signed-by=$KEYRING_DIR/cznic-labs-pkg.gpg] https://pkg.labs.nic.cz/knot-dns $OS_CODENAME main"
  else error "could not download the Knot (CZ.NIC) repo key"; fi

  # Rspamd – official repo
  if fetch_key https://rspamd.com/apt-stable/gpg.key "$KEYRING_DIR/rspamd.gpg" dearmor; then
    repo_add rspamd /etc/apt/sources.list.d/rspamd.list \
      "deb [signed-by=$KEYRING_DIR/rspamd.gpg] https://rspamd.com/apt-stable/ $OS_CODENAME main"
  else error "could not download the Rspamd repo key"; fi

  # PHP – Ondřej Surý, always from packages.sury.org (Ubuntu and Debian); no PPA.
  if [[ $DRY_RUN == 1 ]]; then info "[dry-run] repo packages.sury.org"
  elif curl -fsSL --max-time 30 -o /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb \
       && dpkg -i /tmp/debsuryorg-archive-keyring.deb >>"$PHPANEL_LOG_FILE" 2>&1; then
    repo_add php-sury /etc/apt/sources.list.d/php-sury.list \
      "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $OS_CODENAME main"
  else error "could not install the packages.sury.org key"; REPO_MISSING="${REPO_MISSING:-} php-sury"; fi

  apt_update || error "final apt update reported errors (details in $PHPANEL_LOG_FILE)"
  fact_set REPO_MISSING "${REPO_MISSING:-}"
  if [[ -n ${REPO_MISSING:-} ]]; then warn "repos without support for $OS_CODENAME:${REPO_MISSING}"; fi
}
