# shellcheck shell=bash
# Tailscale: installed, logged in, MagicDNS name known.
#
# Module contract (lib/tailscale.sh, lib/ssh.sh, lib/herdr.sh):
#   check_<x>    print ok/warn/fail lines; return 0 when ready, 1 when install_<x> should run.
#   install_<x>  make it ready; run every system change through hk_run (honours --dry-run).
#
# Also exports:
#   hk_tailscale_name   print this machine's MagicDNS short name (nothing if unknown).
#
# Tailscale SSH stays off: `tailscale up` is never passed --ssh.
# Tests override HK_TAILSCALE_APP (macOS app CLI path), HK_SYSTEMD_DIR and HK_TS_WAIT.

# _hk_ts_bin: prints the tailscale CLI path; fails when none is installed.
_hk_ts_bin() {
  local app=${HK_TAILSCALE_APP:-/Applications/Tailscale.app/Contents/MacOS/Tailscale}
  if command -v tailscale >/dev/null 2>&1; then
    command -v tailscale
  elif [[ -x $app ]]; then
    printf '%s\n' "$app"
  else
    return 1
  fi
}

# _hk_ts_status <bin>: prints `tailscale status --json`; fails when the daemon is down.
_hk_ts_status() {
  local out
  out=$("$1" status --json 2>/dev/null) || return 1
  [[ -n $out ]] || return 1
  printf '%s\n' "$out"
}

# _hk_ts_json_field <field>: first string value of "<field>" on stdin (Self comes first).
_hk_ts_json_field() {
  { grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" || true; } |
    head -n 1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/'
}

# _hk_ts_state <bin>: BackendState (Running, NeedsLogin, Stopped, ...); empty if the daemon is down.
_hk_ts_state() {
  local json
  json=$(_hk_ts_status "$1") || return 0
  printf '%s\n' "$json" | _hk_ts_json_field BackendState
}

hk_tailscale_name() {
  local bin json name
  bin=$(_hk_ts_bin) || return 0
  json=$(_hk_ts_status "$bin") || return 0
  name=$(printf '%s\n' "$json" | _hk_ts_json_field DNSName)
  # DNSName is "<short>.<tailnet>.ts.net."; HostName covers a tailnet without MagicDNS.
  name=${name%%.*}
  [[ -n $name ]] || name=$(printf '%s\n' "$json" | _hk_ts_json_field HostName)
  printf '%s\n' "$name" | tr '[:upper:]' '[:lower:]'
}

check_tailscale() {
  local bin state name
  if ! bin=$(_hk_ts_bin); then
    fail "tailscale: not installed"
    return 1
  fi
  state=$(_hk_ts_state "$bin")
  case $state in
    Running)
      name=$(hk_tailscale_name)
      if [[ -n $name ]]; then
        ok "tailscale: up as $name"
      else
        ok "tailscale: up"
      fi
      ;;
    "")
      warn "tailscale: installed, daemon not running"
      return 1
      ;;
    *)
      warn "tailscale: installed, not logged in"
      return 1
      ;;
  esac
}

# _hk_ts_install_package: installs the CLI + daemon for this OS.
_hk_ts_install_package() {
  case $HK_OS in
    macos)
      command -v brew >/dev/null 2>&1 || {
        fail "tailscale: Homebrew is required (https://brew.sh)"
        return 1
      }
      hk_run brew install tailscale
      ;;
    arch)
      hk_run sudo pacman -S --needed --noconfirm tailscale
      ;;
    debian)
      # Official installer: https://tailscale.com/install.sh
      hk_run bash -c 'curl -fsSL https://tailscale.com/install.sh | sh'
      ;;
    *)
      fail "tailscale: unsupported OS"
      return 1
      ;;
  esac
}

# _hk_ts_start_daemon <bin>: starts tailscaled and waits for the CLI to answer.
_hk_ts_start_daemon() {
  local bin=$1 sudo=() i
  [[ $(id -u) -eq 0 ]] || sudo=(sudo)
  case $HK_OS in
    macos)
      if [[ $bin == */Tailscale.app/* ]]; then
        warn "tailscale: open the Tailscale app once so its daemon starts"
        return 1
      fi
      hk_run "${sudo[@]+"${sudo[@]}"}" brew services start tailscale
      ;;
    *)
      hk_run "${sudo[@]+"${sudo[@]}"}" systemctl enable --now tailscaled
      ;;
  esac || return 1
  [[ ${HK_DRY_RUN:-0} == 1 ]] && return 0
  for ((i = 0; i < ${HK_TS_WAIT:-10}; i++)); do
    _hk_ts_status "$bin" >/dev/null && return 0
    sleep 1
  done
  fail "tailscale: daemon did not come up"
  return 1
}

install_tailscale() {
  local bin sudo=() installed=1 daemon_up=1 state=""
  [[ $(id -u) -eq 0 ]] || sudo=(sudo)

  # WSL2 only runs tailscaled under systemd: say how to enable it, don't work around it.
  if [[ ${HK_WSL:-0} == 1 && ! -d ${HK_SYSTEMD_DIR:-/run/systemd/system} ]]; then
    warn "tailscale: systemd is not running in this WSL2 distro"
    warn "  add to /etc/wsl.conf:  [boot]  systemd=true"
    warn "  then run in Windows:   wsl --shutdown   and re-run herdr-kit setup"
    return 1
  fi

  bin=$(_hk_ts_bin) || installed=0
  if ((!installed)); then
    _hk_ts_install_package || return 1
    bin=$(_hk_ts_bin) || bin=tailscale # not found after a dry run
  fi

  # After a dry-run install nothing exists to ask, so assume the steps below are needed.
  if ((!installed)) && [[ ${HK_DRY_RUN:-0} == 1 ]]; then
    daemon_up=0
  else
    _hk_ts_status "$bin" >/dev/null || daemon_up=0
  fi
  if ((!daemon_up)); then
    _hk_ts_start_daemon "$bin" || return 1
  fi

  if [[ ${HK_DRY_RUN:-0} != 1 ]]; then
    state=$(_hk_ts_state "$bin")
  fi
  if [[ $state != Running ]]; then
    if [[ ${HK_DRY_RUN:-0} == 1 ]] || hk_confirm "Log in to Tailscale now? (opens a browser login)"; then
      # Interactive browser login. Never --ssh: remote access is plain OpenSSH over the tailnet.
      hk_run "${sudo[@]+"${sudo[@]}"}" "$bin" up || return 1
    else
      warn "tailscale: not logged in; run: ${sudo[*]+${sudo[*]} }tailscale up"
      return 1
    fi
  fi

  [[ ${HK_DRY_RUN:-0} == 1 ]] && return 0
  check_tailscale
}
