# shellcheck shell=bash
# Herdr: installed, plus the Claude Code integration when claude exists.
#
# Module contract (lib/tailscale.sh, lib/ssh.sh, lib/herdr.sh):
#   check_<x>    print ok/warn/fail lines; return 0 when ready, 1 when install_<x> should run.
#   install_<x>  make it ready; run every system change through hk_run (honours --dry-run).

HK_CLAUDE_INSTALL_LINE="curl -fsSL https://claude.ai/install.sh | bash"

# Prints the claude integration state from Herdr's own output: current | missing | outdated.
# Lines look like "claude: current (v11) (<path>)" or "claude: not installed (<path>)".
# Any other wording counts as outdated, and installing again refreshes it.
_hk_claude_integration_state() {
  local line
  if ! command -v herdr >/dev/null 2>&1; then
    echo missing
    return 0
  fi
  line=$(herdr integration status 2>/dev/null | grep '^claude:' || true)
  case $line in
    "claude: current"*) echo current ;;
    "claude: not installed"* | "") echo missing ;;
    *) echo outdated ;;
  esac
}

check_herdr() {
  local version state
  if ! version=$(herdr --version 2>/dev/null); then
    fail "herdr: not installed"
    return 1
  fi
  ok "herdr: ${version#herdr }"

  if ! command -v claude >/dev/null 2>&1; then
    warn "claude: not found, skipping the Herdr integration. Install it with: $HK_CLAUDE_INSTALL_LINE"
    return 0
  fi
  state=$(_hk_claude_integration_state)
  if [[ $state == current ]]; then
    ok "herdr: claude integration installed"
    return 0
  fi
  fail "herdr: claude integration $state"
  return 1
}

_hk_install_herdr_binary() {
  if [[ $HK_OS == macos ]] && command -v brew >/dev/null 2>&1; then
    hk_run brew install herdr
  else
    hk_run bash -c 'curl -fsSL https://herdr.dev/install.sh | sh'
  fi
  [[ ${HK_DRY_RUN:-0} == 1 ]] && return 0

  # The official script installs to ~/.local/bin, which a fresh shell may not have on PATH.
  if ! command -v herdr >/dev/null 2>&1 && [[ -x $HOME/.local/bin/herdr ]]; then
    export PATH="$HOME/.local/bin:$PATH"
    warn "herdr is in ~/.local/bin, which is not on your PATH. Add it to your shell profile."
  fi
  if ! command -v herdr >/dev/null 2>&1; then
    fail "herdr: installed, but not found on PATH"
    return 1
  fi
  ok "herdr: installed $(herdr --version | sed 's/^herdr //')"
}

install_herdr() {
  local state
  if ! command -v herdr >/dev/null 2>&1; then
    _hk_install_herdr_binary || return 1
  fi

  # check_herdr already warned about a missing claude; it is never installed automatically.
  if ! command -v claude >/dev/null 2>&1; then
    skip "herdr: claude not found, integration skipped"
    return 0
  fi
  state=$(_hk_claude_integration_state)
  if [[ $state == current ]]; then
    skip "herdr: claude integration already installed"
    return 0
  fi
  hk_run herdr integration install claude
  [[ ${HK_DRY_RUN:-0} == 1 ]] || ok "herdr: claude integration installed"
}
