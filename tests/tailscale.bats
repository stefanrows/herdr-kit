#!/usr/bin/env bats

# Stubs live in $STUBS (first on PATH). Every stub appends its argv to $CALLS.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/ui.sh"
  source "$BATS_TEST_DIRNAME/../lib/tailscale.sh"
  export NO_COLOR=1
  export HK_DRY_RUN=0 HK_YES=1 HK_TS_WAIT=0
  export HK_TAILSCALE_APP="$BATS_TEST_TMPDIR/no-app"
  export HK_SYSTEMD_DIR="$BATS_TEST_TMPDIR/systemd"
  mkdir -p "$HK_SYSTEMD_DIR"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$STUBS"
  : >"$CALLS"
  PATH="$STUBS:$PATH"
  export CALLS STUBS
  stub sudo 'exec "$@"'
  stub systemctl ''
  stub brew ''
  stub pacman ''
  HK_OS=debian HK_WSL=0
}

# stub <name> <body>: a command that logs its argv, then runs <body>.
stub() {
  printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\n%s\n' "$1" "$2" >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# stub_tailscale <backend-state>: `status --json` answers with a realistic Self + Peer.
stub_tailscale() {
  cat >"$BATS_TEST_TMPDIR/status.json" <<EOF
{
  "Version": "1.80.0",
  "BackendState": "$1",
  "TailscaleIPs": ["100.64.0.1"],
  "Self": {
    "HostName": "Omarchy",
    "DNSName": "omarchy.tail1234.ts.net.",
    "UserID": 42
  },
  "Peer": {
    "nodekey:abc": { "HostName": "other", "DNSName": "other.tail1234.ts.net." }
  }
}
EOF
  stub tailscale 'if [ "$1" = status ]; then cat "$BATS_TEST_TMPDIR/status.json"; fi'
}

# Hide real tailscale/brew/etc. that sit outside the stubs dir.
no_tailscale() {
  stub_tailscale Running
  rm "$STUBS/tailscale"
  # Keep PATH to stubs + system dirs that hold no tailscale.
  PATH="$STUBS:/usr/bin:/bin"
}

@test "check: installed and up prints the MagicDNS short name only" {
  stub_tailscale Running
  run check_tailscale
  [ "$status" -eq 0 ]
  [ "$output" = "✓ tailscale: up as omarchy" ]
  [[ $output != *100.64* ]]
  [[ $output != *tail1234* ]]
}

@test "check: installed but logged out" {
  stub_tailscale NeedsLogin
  run check_tailscale
  [ "$status" -eq 1 ]
  [[ $output == *"not logged in"* ]]
}

@test "check: installed but daemon not running" {
  stub tailscale 'exit 1'
  run check_tailscale
  [ "$status" -eq 1 ]
  [[ $output == *"daemon not running"* ]]
}

@test "check: missing" {
  no_tailscale
  run check_tailscale
  [ "$status" -eq 1 ]
  [[ $output == *"not installed"* ]]
}

@test "check: finds the macOS app CLI when tailscale is not on PATH" {
  no_tailscale
  stub_tailscale Running
  mv "$STUBS/tailscale" "$HK_TAILSCALE_APP"
  run check_tailscale
  [ "$status" -eq 0 ]
  [[ $output == *"up as omarchy"* ]]
}

@test "name falls back to HostName without MagicDNS" {
  stub_tailscale Running
  sed -i.bak 's/"DNSName": "omarchy.tail1234.ts.net."/"DNSName": ""/' "$BATS_TEST_TMPDIR/status.json"
  run hk_tailscale_name
  [ "$output" = omarchy ]
}

@test "install: logged out runs sudo tailscale up, never --ssh" {
  stub_tailscale NeedsLogin
  run install_tailscale
  grep -q '^tailscale up$' "$CALLS"
  ! grep -q -- '--ssh' "$CALLS"
  ! grep -q 'install' "$CALLS"
}

@test "install: already up changes nothing" {
  stub_tailscale Running
  run install_tailscale
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ] || ! grep -Eq 'tailscale up|systemctl|brew|pacman' "$CALLS"
}

@test "install: logged out without --yes and no terminal prints the command" {
  stub_tailscale NeedsLogin
  HK_YES=0 run install_tailscale </dev/null
  [ "$status" -eq 1 ]
  [[ $output == *"run: "*"tailscale up"* ]]
  ! grep -q '^tailscale up' "$CALLS"
}

@test "install: missing on macOS uses brew" {
  no_tailscale
  HK_OS=macos run install_tailscale
  grep -q '^brew install tailscale$' "$CALLS"
  grep -q '^brew services start tailscale$' "$CALLS"
}

@test "install: missing on Arch uses pacman and enables tailscaled" {
  no_tailscale
  HK_OS=arch run install_tailscale
  grep -q '^pacman -S --needed --noconfirm tailscale$' "$CALLS"
  grep -q '^systemctl enable --now tailscaled$' "$CALLS"
}

@test "install: --dry-run on Debian prints the official installer and changes nothing" {
  no_tailscale
  HK_OS=debian HK_DRY_RUN=1 run install_tailscale
  [ "$status" -eq 0 ]
  [[ $output == *"https://tailscale.com/install.sh"* ]]
  [[ $output == *"tailscale up"* ]]
  [[ $output != *"--ssh"* ]]
  [ ! -s "$CALLS" ]
}

@test "install: WSL2 without systemd warns with the fix and stops" {
  no_tailscale
  rmdir "$HK_SYSTEMD_DIR"
  HK_OS=debian HK_WSL=1 run install_tailscale
  [ "$status" -eq 1 ]
  [[ $output == *"systemd=true"* ]]
  [[ $output == *"wsl --shutdown"* ]]
  [ ! -s "$CALLS" ]
}

@test "install: macOS app installed but daemon down asks to open the app" {
  no_tailscale
  export HK_TAILSCALE_APP="$BATS_TEST_TMPDIR/Tailscale.app/Contents/MacOS/Tailscale"
  mkdir -p "$(dirname "$HK_TAILSCALE_APP")"
  printf '#!/bin/sh\nexit 1\n' >"$HK_TAILSCALE_APP"
  chmod +x "$HK_TAILSCALE_APP"
  HK_OS=macos run install_tailscale
  [ "$status" -eq 1 ]
  [[ $output == *"open the Tailscale app"* ]]
  ! grep -q '^brew' "$CALLS"
}
