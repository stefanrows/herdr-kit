# shellcheck shell=bash
# Output and prompts. Colour only when stdout is a TTY and NO_COLOR is unset.

# Return code for module stubs that have no implementation yet.
HK_E_NOT_IMPLEMENTED=3

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  _HK_GREEN=$'\033[32m'
  _HK_GREY=$'\033[90m'
  _HK_YELLOW=$'\033[33m'
  _HK_RED=$'\033[31m'
  _HK_RESET=$'\033[0m'
else
  _HK_GREEN="" _HK_GREY="" _HK_YELLOW="" _HK_RED="" _HK_RESET=""
fi

_hk_say() {
  printf '%s%s%s %s\n' "$1" "$2" "$_HK_RESET" "$3"
}

ok() { _hk_say "$_HK_GREEN" "✓" "$*"; }
skip() { _hk_say "$_HK_GREY" "–" "$*"; }
warn() { _hk_say "$_HK_YELLOW" "!" "$*"; }
fail() { _hk_say "$_HK_RED" "✗" "$*"; }

# hk_json_str <string>: prints the string as a quoted JSON string.
hk_json_str() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

# Stub helper: not_implemented <name>
not_implemented() {
  warn "$1: not implemented yet"
  return "$HK_E_NOT_IMPLEMENTED"
}

# Runs a command that changes the system, or only prints it under --dry-run.
hk_run() {
  if [[ ${HK_DRY_RUN:-0} == 1 ]]; then
    skip "dry run: $*"
    return 0
  fi
  "$@"
}

# hk_confirm <question>: yes under --yes; no when there is no terminal to ask.
hk_confirm() {
  [[ ${HK_YES:-0} == 1 ]] && return 0
  [[ -t 0 ]] || return 1
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply == [yY]* ]]
}
