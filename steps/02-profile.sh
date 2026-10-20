#!/usr/bin/env bash
# Step 02 – resource profile [43], my.cnf profile [44], swap.

step_02_profile() {
  local mem=$MEM_MB profile mycnf
  if [[ -n ${OPT_PROFILE:-} && $OPT_PROFILE != auto ]]; then
    profile=$OPT_PROFILE
    info "forced profile: $profile"
  else profile=$(profile_from_mem "$mem")
  fi
  case $profile in minimal|small|standard|large) ;; *) die "invalid --profile: $profile (use minimal, small, standard or large)" ;; esac

  # my.cnf p01–p10 by actual RAM [44] (the files are written in the MariaDB configuration step)
  if   (( mem <= 1024 ));  then mycnf=p01
  elif (( mem <= 2048 ));  then mycnf=p02
  elif (( mem <= 3072 ));  then mycnf=p03
  elif (( mem <= 4096 ));  then mycnf=p04
  elif (( mem <= 6144 ));  then mycnf=p05
  elif (( mem <= 8192 ));  then mycnf=p06
  elif (( mem <= 12288 )); then mycnf=p07
  elif (( mem <= 16384 )); then mycnf=p08
  elif (( mem <= 32768 )); then mycnf=p09
  else mycnf=p10
  fi
  fact_set PROFILE "$profile"; fact_set MYCNF_PROFILE "$mycnf"
  ok "resource profile: $profile, MariaDB profile: $mycnf"

  # swap on the minimal and small profiles, if it does not already exist
  if [[ $profile == minimal || $profile == small ]]; then
    if swapon --show --noheadings | grep -q .; then
      info "swap already exists, keeping it"
    elif [[ -e /swapfile ]]; then
      warn "/swapfile exists but is not active; leaving it untouched"
    else
      info "creating a 1 GB /swapfile"
      run fallocate -l 1G /swapfile || run dd if=/dev/zero of=/swapfile bs=1M count=1024
      run chmod 600 /swapfile
      run mkswap /swapfile
      run swapon /swapfile
      if [[ $DRY_RUN != 1 ]] && ! grep -q '^/swapfile ' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >>/etc/fstab
      fi
      ok "1 GB swap active"
    fi
    if [[ $DRY_RUN != 1 ]]; then
      echo 'vm.swappiness=10' >/etc/sysctl.d/60-phpanel-swap.conf
      sysctl -q -p /etc/sysctl.d/60-phpanel-swap.conf || true
    fi
  fi
}
