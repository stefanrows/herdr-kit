# shellcheck shell=bash
# SSH: OpenSSH server reachable over the tailnet. Tailscale SSH must stay off.
#
# Module contract (lib/tailscale.sh, lib/ssh.sh, lib/herdr.sh):
#   check_<x>    print ok/warn/fail lines; return 0 when ready, 1 when install_<x> should run.
#   install_<x>  make it ready; run every system change through hk_run (honours --dry-run).
#
# Tests override HK_WSL_CONF.

# What check_ssh found missing: any of systemd, blocked, sshd, tailscale.
_HK_SSH_NEED=""
_HK_SSH_CHECKED=0

# _hk_priv <cmd...>: hk_run, through sudo unless already root.
_hk_priv() {
  if [[ $(id -u) -eq 0 ]]; then
    hk_run "$@"
  else
    hk_run sudo "$@"
  fi
}

# The sshd unit name: sshd on Arch, ssh on Debian/Ubuntu.
_hk_ssh_unit() {
  if [[ $HK_OS == arch ]]; then printf 'sshd\n'; else printf 'ssh\n'; fi
}

_hk_port22_listening() {
  [[ -n $(ss -ltnH 'sport = :22' 2>/dev/null) ]]
}

_hk_ssh_unit_active() {
  local unit
  unit=$(_hk_ssh_unit)
  systemctl is-active --quiet "$unit" && return 0
  # Ubuntu 22.10+ may leave ssh.service stopped while ssh.socket listens.
  [[ $HK_OS == debian ]] && systemctl is-active --quiet "$unit.socket"
}

# WSL2 distros boot without systemd until /etc/wsl.conf asks for it.
check_systemd() {
  case $(systemctl is-system-running 2>/dev/null) in
    running | degraded)
      ok "systemd is running"
      return 0
      ;;
  esac
  fail "systemd is not running (WSL2 needs it for sshd)"
  return 1
}

# Sets [boot] systemd=true in /etc/wsl.conf, keeping every other section.
fix_systemd() {
  local conf=${HK_WSL_CONF:-/etc/wsl.conf} tmp
  tmp=$(mktemp)
  if [[ -r $conf ]]; then
    awk '
      /^\[/ { if (inboot && !done) { print "systemd=true"; done = 1 } inboot = ($0 == "[boot]"); if (inboot) seen = 1 }
      inboot && /^[ \t]*systemd[ \t]*=/ { if (!done) print "systemd=true"; done = 1; next }
      { print }
      END {
        if (inboot && !done) print "systemd=true"
        else if (!seen) { if (NR) print ""; print "[boot]"; print "systemd=true" }
      }
    ' "$conf" >"$tmp"
  else
    printf '[boot]\nsystemd=true\n' >"$tmp"
  fi
  _hk_priv install -m 644 "$tmp" "$conf"
  rm -f "$tmp"
  warn "Run 'wsl --shutdown' from Windows, reopen this distro, then run herdr-kit setup again"
}

check_tailscale_ssh_off() {
  if ! command -v tailscale >/dev/null 2>&1; then
    skip "Tailscale SSH: tailscale not installed"
    return 0
  fi
  if tailscale debug prefs 2>/dev/null | grep -Eq '"RunSSH":[[:space:]]*false'; then
    ok "Tailscale SSH is off (Herdr uses plain OpenSSH)"
    return 0
  fi
  fail "Tailscale SSH is on or unreadable: it would answer port 22 instead of OpenSSH"
  return 1
}

fix_tailscale_ssh_off() {
  if [[ $HK_OS == macos ]]; then
    warn "Turn it off yourself: tailscale set --ssh=false"
    return 1
  fi
  _hk_priv tailscale set --ssh=false
}

_hk_ssh_need() {
  _HK_SSH_NEED="$_HK_SSH_NEED $1"
}

check_ssh() {
  _HK_SSH_NEED=""
  _HK_SSH_CHECKED=1

  if [[ $HK_OS == macos ]]; then
    # The Mac is the hub; never change its system settings.
    if nc -z localhost 22 >/dev/null 2>&1; then
      ok "Remote Login is on (OpenSSH reachable)"
    else
      skip "Remote Login is off (the Mac is the hub, so this is fine; System Settings > General > Sharing to turn it on)"
    fi
  else
    if [[ $HK_WSL == 1 ]] && ! check_systemd; then
      _hk_ssh_need systemd
      return 1
    fi
    if _hk_ssh_unit_active; then
      if _hk_port22_listening; then
        ok "OpenSSH server is running on port 22"
        skip "Use key auth: add your public key to ~/.ssh/authorized_keys"
      else
        fail "OpenSSH service is active but nothing listens on port 22"
        _hk_ssh_need sshd
      fi
    elif [[ $HK_WSL == 1 ]] && _hk_port22_listening; then
      fail "Port 22 is taken by a process outside this distro (all WSL2 distros share one network stack); stop it there first"
      _hk_ssh_need blocked
    else
      fail "OpenSSH server is not running"
      _hk_ssh_need sshd
    fi
  fi

  check_tailscale_ssh_off || _hk_ssh_need tailscale
  [[ -z $_HK_SSH_NEED ]]
}

install_ssh() {
  [[ $_HK_SSH_CHECKED == 1 ]] || check_ssh >/dev/null || true
  local unit rc=0
  case " $_HK_SSH_NEED " in
    *" systemd "*)
      fix_systemd
      # Without a restart nothing below can work; dry run keeps going.
      [[ ${HK_DRY_RUN:-0} == 1 ]]
      return
      ;;
    *" blocked "*) return 1 ;;
  esac
  case " $_HK_SSH_NEED " in
    *" sshd "*)
      unit=$(_hk_ssh_unit)
      if [[ $HK_OS == arch ]]; then
        _hk_priv pacman -S --needed openssh
      else
        _hk_priv apt-get install -y openssh-server
      fi
      _hk_priv systemctl enable --now "$unit"
      ;;
  esac
  case " $_HK_SSH_NEED " in
    *" tailscale "*) fix_tailscale_ssh_off || rc=1 ;;
  esac
  return "$rc"
}
