#!/usr/bin/env bats

# Commands run against a PATH holding only symlinks to basic tools plus stubs,
# so a herdr or claude installed on the test machine never leaks in.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/ui.sh"
  source "$BATS_TEST_DIRNAME/../lib/herdr.sh"

  STUBS="$BATS_TEST_TMPDIR/bin"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$STUBS" "$HOME/.local/bin"
  : >"$STUB_LOG"

  local tool
  for tool in bash sh grep sed cat chmod mkdir; do
    ln -s "$(command -v "$tool")" "$STUBS/$tool"
  done
  ORIG_PATH=$PATH
  PATH="$STUBS"
  HK_OS=debian
  HK_DRY_RUN=0
}

teardown() {
  PATH=$ORIG_PATH
}

# stub <name> <body>: an executable in the stub dir that logs its call, then runs <body>.
stub() {
  printf '#!/bin/sh\necho "%s $*" >>"$STUB_LOG"\n%s\n' "$1" "$2" >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# stub_herdr <claude status line>: herdr 0.9.5 with a fixed integration status.
stub_herdr() {
  stub herdr "case \$1 in
  --version) echo 'herdr 0.9.5' ;;
  integration) [ \$2 = status ] && printf 'codex: not installed (/x)\n%s\n' '$1' ;;
esac"
}

@test "check: herdr missing" {
  run check_herdr
  [ "$status" -eq 1 ]
  [ "$output" = "✗ herdr: not installed" ]
}

@test "check: herdr present, claude missing warns with the install line" {
  stub_herdr "claude: not installed (/x)"
  run check_herdr
  [ "$status" -eq 0 ]
  [[ $output == *"✓ herdr: 0.9.5"* ]]
  [[ $output == *"curl -fsSL https://claude.ai/install.sh | bash"* ]]
}

@test "check: integration current" {
  stub_herdr "claude: current (v11) (/x)"
  stub claude ""
  run check_herdr
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "✓ herdr: claude integration installed" ]
}

@test "check: integration missing" {
  stub_herdr "claude: not installed (/x)"
  stub claude ""
  run check_herdr
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "✗ herdr: claude integration missing" ]
}

@test "check: any other integration state counts as outdated" {
  stub_herdr "claude: outdated (v9) (/x)"
  stub claude ""
  run check_herdr
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "✗ herdr: claude integration outdated" ]
}

@test "install: macOS with brew uses brew" {
  HK_OS=macos
  stub brew "printf '#!/bin/sh\necho \"herdr 0.9.5\"\n' >'$STUBS/herdr'; chmod +x '$STUBS/herdr'"
  run install_herdr
  [ "$status" -eq 0 ]
  grep -q '^brew install herdr$' "$STUB_LOG"
  [[ $output == *"✓ herdr: installed 0.9.5"* ]]
}

@test "install: Linux pipes the official script into sh" {
  stub curl "printf '#!/bin/sh\necho \"herdr 0.9.5\"\n' >'$HOME/.local/bin/herdr'; chmod +x '$HOME/.local/bin/herdr'"
  run install_herdr
  [ "$status" -eq 0 ]
  grep -q '^curl -fsSL https://herdr.dev/install.sh$' "$STUB_LOG"
  [[ $output == *"~/.local/bin, which is not on your PATH"* ]]
  [[ $output == *"✓ herdr: installed 0.9.5"* ]]
}

@test "install: macOS without brew falls back to the official script" {
  HK_OS=macos
  stub curl "true"
  run install_herdr
  [ "$status" -eq 1 ]
  grep -q '^curl -fsSL https://herdr.dev/install.sh$' "$STUB_LOG"
  [ "${lines[-1]}" = "✗ herdr: installed, but not found on PATH" ]
}

@test "install: adds the claude integration when claude exists" {
  stub_herdr "claude: not installed (/x)"
  stub claude ""
  run install_herdr
  [ "$status" -eq 0 ]
  grep -q '^herdr integration install claude$' "$STUB_LOG"
}

@test "install: skips an integration that is already current" {
  stub_herdr "claude: current (v11) (/x)"
  stub claude ""
  run install_herdr
  [ "$status" -eq 0 ]
  ! grep -q 'integration install' "$STUB_LOG"
  [[ $output == *"claude integration already installed"* ]]
}

@test "install: never installs claude itself" {
  stub_herdr "claude: not installed (/x)"
  run install_herdr
  [ "$status" -eq 0 ]
  ! grep -q 'integration install' "$STUB_LOG"
  ! grep -q 'claude.ai' "$STUB_LOG"
}

@test "dry run: changes nothing and prints what would run" {
  HK_DRY_RUN=1
  stub curl "echo should-not-run >&2; exit 1"
  run install_herdr
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
  [[ $output == *"– dry run: bash -c curl -fsSL https://herdr.dev/install.sh | sh"* ]]
}

@test "dry run: also previews the claude integration" {
  HK_DRY_RUN=1
  stub_herdr "claude: not installed (/x)"
  stub claude ""
  run install_herdr
  [ "$status" -eq 0 ]
  ! grep -q 'integration install' "$STUB_LOG"
  [ "$output" = "– dry run: herdr integration install claude" ]
}
