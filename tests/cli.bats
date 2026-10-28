#!/usr/bin/env bats

setup() {
  HK="$BATS_TEST_DIRNAME/../herdr-kit"
}

@test "--help lists both commands" {
  run "$HK" --help
  [ "$status" -eq 0 ]
  [[ $output == *"setup "* ]]
  [[ $output == *"doctor "* ]]
  [[ $output == *"Not affiliated with Herdr or Tailscale"* ]]
}

@test "no command prints usage" {
  run "$HK"
  [ "$status" -eq 0 ]
  [[ $output == Usage:* ]]
}

@test "unknown command exits 2" {
  run "$HK" frobnicate
  [ "$status" -eq 2 ]
  [[ $output == *"unknown command: frobnicate"* ]]
}

@test "unknown flag exits 2" {
  run "$HK" doctor --nope
  [ "$status" -eq 2 ]
  [[ $output == *"unknown argument: --nope"* ]]
}

@test "setup --dry-run walks every module in order, then runs doctor" {
  run "$HK" setup --dry-run
  # Doctor reads the real machine, so its exit code (0 or 1) is not pinned here.
  [ "$status" -le 1 ]
  [ "${lines[0]}" = "! tailscale: not implemented yet" ]
  [ "${lines[1]}" = "! ssh: not implemented yet" ]
  [ "${lines[2]}" = "! herdr: not implemented yet" ]
  [[ ${lines[3]} == *"OS: "* ]]
}

@test "flags work before the command" {
  run "$HK" --dry-run --yes doctor
  [ "$status" -le 1 ]
  [[ ${lines[0]} == *"OS: "* ]]
}

@test "doctor --json prints one JSON object" {
  run "$HK" doctor --json
  [ "$status" -le 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ $output == '{"ok":'* ]]
}
