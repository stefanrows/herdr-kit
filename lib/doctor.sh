# shellcheck shell=bash
# Doctor: checks only, changes nothing. Ends with the exact `herdr machine add` line.
#
#   run_doctor [--json]  print one line per check; return 0 when everything needed is green.
#
# Each check is a read-only probe, doctor_probe_<id>: it prints a short detail and returns
#   0 ok, 1 not ok, 2 not applicable (shown as skipped, never fails the run).
# The probes read the system directly, so doctor works whichever modules have landed.

HK_DOCTOR_CHECKS="os tailscale magicdns sshd tailscale_ssh herdr claude"

_hk_doctor_label() {
  case $1 in
    os) printf 'OS\n' ;;
    tailscale) printf 'Tailscale\n' ;;
    magicdns) printf 'MagicDNS name\n' ;;
    sshd) printf 'SSH server\n' ;;
    tailscale_ssh) printf 'Tailscale SSH\n' ;;
    herdr) printf 'Herdr\n' ;;
    claude) printf 'Claude Code integration\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Tailscale's JSON is pretty-printed, one key per line; the first DNSName is this node's.
_hk_ts_json_field() {
  tailscale status --json 2>/dev/null | sed -n "s/^ *\"$1\": *\"\\([^\"]*\\)\".*/\\1/p" | sed -n '1p'
}

doctor_probe_os() {
  if [[ ${HK_OS:-unsupported} == unsupported ]]; then
    printf 'unsupported\n'
    return 1
  fi
  if [[ ${HK_WSL:-0} == 1 ]]; then
    printf '%s (WSL)\n' "$HK_OS"
  else
    printf '%s\n' "$HK_OS"
  fi
}

doctor_probe_tailscale() {
  if ! command -v tailscale >/dev/null 2>&1; then
    printf 'not installed\n'
    return 1
  fi
  local state
  state=$(_hk_ts_json_field BackendState) || true
  case $state in
    Running) printf 'up\n' ;;
    "") printf 'not running\n'; return 1 ;;
    *) printf 'not up (%s)\n' "$state"; return 1 ;;
  esac
}

doctor_probe_magicdns() {
  if ! command -v tailscale >/dev/null 2>&1; then
    printf 'unknown\n'
    return 1
  fi
  local dns name
  dns=$(_hk_ts_json_field DNSName) || true
  name=${dns%%.*}
  if [[ -z $name ]]; then
    printf 'unknown\n'
    return 1
  fi
  printf '%s\n' "$name"
}

# OpenSSH, not Tailscale SSH: ask the local port for the SSH banner.
doctor_probe_sshd() {
  local port=${HK_SSH_PORT:-22} banner=""
  banner=$({ exec 3<>"/dev/tcp/127.0.0.1/$port" && IFS= read -r -t 3 line <&3 && printf '%s' "$line"; } 2>/dev/null) || true
  case $banner in
    SSH-*) printf 'listening on port %s\n' "$port" ;;
    *) printf 'no SSH server on port %s\n' "$port"; return 1 ;;
  esac
}

# An unreadable setting counts as not ok: never advise `machine add` while Tailscale SSH might be on.
doctor_probe_tailscale_ssh() {
  if ! command -v tailscale >/dev/null 2>&1; then
    printf 'unknown\n'
    return 1
  fi
  local prefs
  prefs=$(tailscale debug prefs 2>/dev/null) || true
  case $prefs in
    *'"RunSSH": true'*) printf 'on (must be off)\n'; return 1 ;;
    *'"RunSSH": false'*) printf 'off\n' ;;
    *) printf 'unknown\n'; return 1 ;;
  esac
}

doctor_probe_herdr() {
  if ! command -v herdr >/dev/null 2>&1; then
    printf 'not installed\n'
    return 1
  fi
  local out version
  out=$(herdr --version 2>/dev/null) || true
  out=${out%%$'\n'*}
  version=${out##* }
  if [[ -z $version ]]; then
    printf 'unknown version\n'
    return 1
  fi
  printf '%s\n' "$version"
}

doctor_probe_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    printf 'Claude Code not installed\n'
    return 2
  fi
  if ! command -v herdr >/dev/null 2>&1; then
    printf 'needs Herdr\n'
    return 1
  fi
  local line
  line=$(herdr integration status 2>/dev/null | sed -n 's/^claude: *//p' | sed -n '1p') || true
  # Herdr appends the hook file path; keep the state only.
  line=${line%% \(/*}
  case $line in
    current*) printf '%s\n' "$line" ;;
    "") printf 'unknown\n'; return 1 ;;
    *) printf '%s\n' "$line"; return 1 ;;
  esac
}

run_doctor() {
  local json=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --json) json=1 ;;
      *) usage_error "doctor: unknown argument: $1" ;;
    esac
    shift
  done

  local id label rc detail status item items=""
  local bad=0 needed_bad=0 ssh_on=0 name=""
  for id in $HK_DOCTOR_CHECKS; do
    rc=0
    if declare -F "doctor_probe_$id" >/dev/null; then
      detail=$("doctor_probe_$id") || rc=$?
    else
      detail="no such check"
      rc=1
    fi
    label=$(_hk_doctor_label "$id")

    case $rc in
      0) status=ok ;;
      2) status=skip ;;
      *) status=fail ;;
    esac
    [[ $status != fail ]] || bad=1
    case $id in
      tailscale | magicdns | sshd | tailscale_ssh) [[ $status == ok ]] || needed_bad=1 ;;
    esac
    [[ $id != magicdns || $status != ok ]] || name=$detail
    [[ $id != tailscale_ssh || $status != fail || $detail != on* ]] || ssh_on=1

    if [[ $json == 1 ]]; then
      item=$(printf '{"id":%s,"label":%s,"status":%s,"detail":%s}' \
        "$(hk_json_str "$id")" "$(hk_json_str "$label")" "$(hk_json_str "$status")" "$(hk_json_str "$detail")")
      items=${items:+$items,}$item
    else
      case $status in
        ok) ok "$label: $detail" ;;
        skip) skip "$label: $detail" ;;
        *) fail "$label: $detail" ;;
      esac
    fi
  done

  local add_line=""
  [[ $needed_bad == 1 || $ssh_on == 1 ]] || add_line="herdr machine add $name"

  if [[ $json == 1 ]]; then
    local add_json=null
    [[ -z $add_line ]] || add_json=$(hk_json_str "$add_line")
    printf '{"ok":%s,"checks":[%s],"machine_add":%s}\n' \
      "$([[ $bad == 0 ]] && printf true || printf false)" "$items" "$add_json"
  elif [[ $ssh_on == 1 ]]; then
    printf '\nTailscale SSH is on; run: herdr-kit setup (turns it off)\n'
  elif [[ -n $add_line ]]; then
    printf '\nOn your hub, run: %s\n' "$add_line"
  fi

  [[ $bad == 0 ]]
}
