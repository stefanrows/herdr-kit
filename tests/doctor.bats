#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../lib/ui.sh"
  source "$BATS_TEST_DIRNAME/../lib/doctor.sh"
  HK_OS=macos
  HK_WSL=0
  ORIG_PATH=$PATH
}

# fake_bin narrows PATH; bats' own cleanup needs the real one back.
teardown() {
  PATH=$ORIG_PATH
}

# Replaces every probe with a stub that is green by default; change one with: stub <id> <rc> <detail>.
green() {
  local id
  for id in $HK_DOCTOR_CHECKS; do
    eval "doctor_probe_$id() { _stub_probe $id; }"
  done
  stub os 0 macos
  stub tailscale 0 up
  stub magicdns 0 mbp
  stub sshd 0 "listening on port 22"
  stub tailscale_ssh 0 off
  stub herdr 0 0.9.5
  stub claude 0 "current (v11)"
}

stub() {
  printf -v "STUB_RC_$1" '%s' "$2"
  printf -v "STUB_DETAIL_$1" '%s' "$3"
}

_stub_probe() {
  local rc=STUB_RC_$1 detail=STUB_DETAIL_$1
  printf '%s\n' "${!detail}"
  return "${!rc}"
}

# usage_error lives in the dispatcher; tests use the real binary for argument errors.
@test "all green: one line per check, then the machine add line" {
  green
  run run_doctor
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "✓ OS: macos" ]
  [ "${lines[1]}" = "✓ Tailscale: up" ]
  [ "${lines[2]}" = "✓ MagicDNS name: mbp" ]
  [ "${lines[3]}" = "✓ SSH server: listening on port 22" ]
  [ "${lines[4]}" = "✓ Tailscale SSH: off" ]
  [ "${lines[5]}" = "✓ Herdr: 0.9.5" ]
  [ "${lines[6]}" = "✓ Claude Code integration: current (v11)" ]
  [ "${lines[7]}" = "On your hub, run: herdr machine add mbp" ]
  [ "${#lines[@]}" -eq 8 ]
}

@test "Tailscale SSH on: no machine add line, points to setup, exit 1" {
  green
  stub tailscale_ssh 1 "on (must be off)"
  run run_doctor
  [ "$status" -eq 1 ]
  [[ $output == *"✗ Tailscale SSH: on (must be off)"* ]]
  [[ $output == *"Tailscale SSH is on; run: herdr-kit setup (turns it off)"* ]]
  [[ $output != *"machine add"* ]]
}

@test "Tailscale SSH unreadable: no machine add line, no setup hint" {
  green
  stub tailscale_ssh 1 unknown
  run run_doctor
  [ "$status" -eq 1 ]
  [[ $output != *"machine add"* ]]
  [[ $output != *"turns it off"* ]]
}

@test "Tailscale down: failed line, no machine add line, exit 1" {
  green
  stub tailscale 1 "not up (NeedsLogin)"
  stub magicdns 1 unknown
  run run_doctor
  [ "$status" -eq 1 ]
  [[ $output == *"✗ Tailscale: not up (NeedsLogin)"* ]]
  [[ $output != *"machine add"* ]]
}

@test "SSH server missing: no machine add line, exit 1" {
  green
  stub sshd 1 "no SSH server on port 22"
  run run_doctor
  [ "$status" -eq 1 ]
  [[ $output == *"✗ SSH server: no SSH server on port 22"* ]]
  [[ $output != *"machine add"* ]]
}

@test "Claude Code not installed: skipped, still green" {
  green
  stub claude 2 "Claude Code not installed"
  run run_doctor
  [ "$status" -eq 0 ]
  [[ $output == *"– Claude Code integration: Claude Code not installed"* ]]
  [[ $output == *"herdr machine add mbp"* ]]
}

@test "Claude integration outdated: exit 1, machine add line stays" {
  green
  stub claude 1 "outdated (v9)"
  run run_doctor
  [ "$status" -eq 1 ]
  [[ $output == *"✗ Claude Code integration: outdated (v9)"* ]]
  [[ $output == *"herdr machine add mbp"* ]]
}

@test "--json: same checks as one JSON line, nothing else" {
  green
  run run_doctor --json
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  expected='{"ok":true,"checks":['
  expected+='{"id":"os","label":"OS","status":"ok","detail":"macos"},'
  expected+='{"id":"tailscale","label":"Tailscale","status":"ok","detail":"up"},'
  expected+='{"id":"magicdns","label":"MagicDNS name","status":"ok","detail":"mbp"},'
  expected+='{"id":"sshd","label":"SSH server","status":"ok","detail":"listening on port 22"},'
  expected+='{"id":"tailscale_ssh","label":"Tailscale SSH","status":"ok","detail":"off"},'
  expected+='{"id":"herdr","label":"Herdr","status":"ok","detail":"0.9.5"},'
  expected+='{"id":"claude","label":"Claude Code integration","status":"ok","detail":"current (v11)"}'
  expected+='],"machine_add":"herdr machine add mbp"}'
  [ "$output" = "$expected" ]
}

@test "--json with Tailscale SSH on: not ok, machine_add is null" {
  green
  stub tailscale_ssh 1 "on (must be off)"
  stub claude 2 "Claude Code not installed"
  run run_doctor --json
  [ "$status" -eq 1 ]
  [[ $output == '{"ok":false,'* ]]
  [[ $output == *'"id":"tailscale_ssh","label":"Tailscale SSH","status":"fail","detail":"on (must be off)"'* ]]
  [[ $output == *'"id":"claude","label":"Claude Code integration","status":"skip"'* ]]
  [[ $output == *',"machine_add":null}' ]]
}

@test "a check with no probe fails instead of crashing" {
  green
  HK_DOCTOR_CHECKS="os nonsense"
  run run_doctor
  [ "$status" -eq 1 ]
  [[ $output == *"✗ nonsense: no such check"* ]]
}

@test "doctor rejects unknown arguments with exit 2" {
  run "$BATS_TEST_DIRNAME/../herdr-kit" doctor --nope
  [ "$status" -eq 2 ]
  [[ $output == *"doctor: unknown argument: --nope"* ]]
}

# --- real probes against stubbed commands --------------------------------------------------

# Puts fake tailscale/herdr/claude on a PATH that holds nothing else but sed and cat.
fake_bin() {
  FAKE_BIN=$BATS_TEST_TMPDIR/bin
  mkdir -p "$FAKE_BIN"
  ln -sf "$(command -v sed)" "$FAKE_BIN/sed"
  ln -sf "$(command -v cat)" "$FAKE_BIN/cat"
  PATH=$FAKE_BIN
}

# Probes run with PATH=$FAKE_BIN only, so fake_cmd needs absolute paths for its own tools.

fake_cmd() { # fake_cmd <name> <script body>
  printf '#!/bin/sh\n%s\n' "$2" >"$FAKE_BIN/$1"
  /bin/chmod +x "$FAKE_BIN/$1"
}

fake_tailscale() {
  fake_cmd tailscale 'case "$1 $2" in
  "status --json") cat <<JSON
{
  "BackendState": "'"$1"'",
  "Self": {
    "DNSName": "mbp.tail1234.ts.net.",
    "HostName": "My-Laptop"
  },
  "Peer": {
    "nodekey:aa": {
      "DNSName": "other.tail1234.ts.net."
    }
  }
}
JSON
  ;;
  "debug prefs") printf "{\n  \"RunSSH\": '"$2"'\n}\n" ;;
esac'
}

@test "probe tailscale: Running is up, anything else is not" {
  fake_bin
  fake_tailscale Running false
  run doctor_probe_tailscale
  [ "$status" -eq 0 ]
  [ "$output" = "up" ]

  fake_tailscale NeedsLogin false
  run doctor_probe_tailscale
  [ "$status" -eq 1 ]
  [ "$output" = "not up (NeedsLogin)" ]
}

@test "probe tailscale: missing binary" {
  fake_bin
  run doctor_probe_tailscale
  [ "$status" -eq 1 ]
  [ "$output" = "not installed" ]
}

@test "probe magicdns: short name of this node only, never the tailnet" {
  fake_bin
  fake_tailscale Running false
  run doctor_probe_magicdns
  [ "$status" -eq 0 ]
  [ "$output" = "mbp" ]
}

@test "probe tailscale_ssh: reads RunSSH from the prefs" {
  fake_bin
  fake_tailscale Running false
  run doctor_probe_tailscale_ssh
  [ "$status" -eq 0 ]
  [ "$output" = "off" ]

  fake_tailscale Running true
  run doctor_probe_tailscale_ssh
  [ "$status" -eq 1 ]
  [ "$output" = "on (must be off)" ]
}

@test "probe tailscale_ssh: unreadable prefs are not ok" {
  fake_bin
  fake_cmd tailscale 'exit 1'
  run doctor_probe_tailscale_ssh
  [ "$status" -eq 1 ]
  [ "$output" = "unknown" ]
}

@test "probe herdr: prints the bare version" {
  fake_bin
  fake_cmd herdr 'echo "herdr 0.9.5"'
  run doctor_probe_herdr
  [ "$status" -eq 0 ]
  [ "$output" = "0.9.5" ]
}

@test "probe herdr: missing binary" {
  fake_bin
  run doctor_probe_herdr
  [ "$status" -eq 1 ]
  [ "$output" = "not installed" ]
}

@test "probe claude: skipped without Claude Code" {
  fake_bin
  fake_cmd herdr 'exit 0'
  run doctor_probe_claude
  [ "$status" -eq 2 ]
}

@test "probe claude: state only, the hook path is dropped" {
  fake_bin
  fake_cmd claude 'exit 0'
  fake_cmd herdr 'cat <<EOF
pi: not installed (/home/me/.pi/agent/extensions/herdr-agent-state.ts)
claude: current (v11) (/home/me/.claude/hooks/herdr-agent-state.sh)
EOF'
  run doctor_probe_claude
  [ "$status" -eq 0 ]
  [ "$output" = "current (v11)" ]
}

@test "probe claude: not installed integration fails" {
  fake_bin
  fake_cmd claude 'exit 0'
  fake_cmd herdr 'echo "claude: not installed (/home/me/.claude/hooks/herdr-agent-state.sh)"'
  run doctor_probe_claude
  [ "$status" -eq 1 ]
  [ "$output" = "not installed" ]
}

@test "probe sshd: nothing listening fails" {
  HK_SSH_PORT=1 run doctor_probe_sshd
  [ "$status" -eq 1 ]
  [ "$output" = "no SSH server on port 1" ]
}

@test "probe sshd: an SSH banner on the port is ok, other services are not" {
  command -v python3 >/dev/null || skip "python3 needed for a throwaway listener"
  local portfile=$BATS_TEST_TMPDIR/port
  python3 -I -c '
import socket, sys
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(2)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
for banner in (b"SSH-2.0-OpenSSH_9.9\r\n", b"HTTP/1.1 400 Bad Request\r\n"):
    c, _ = s.accept()
    c.sendall(banner)
    c.close()
' "$portfile" &
  local pid=$!
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do [[ -s $portfile ]] && break; sleep 0.2; done

  HK_SSH_PORT=$(<"$portfile") run doctor_probe_sshd
  [ "$status" -eq 0 ]
  HK_SSH_PORT=$(<"$portfile") run doctor_probe_sshd
  [ "$status" -eq 1 ]
  wait "$pid"
}
