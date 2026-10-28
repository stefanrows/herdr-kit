#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../lib/ui.sh"
}

@test "printers use their symbols" {
  [ "$(ok ready)" = "✓ ready" ]
  [ "$(skip done)" = "– done" ]
  [ "$(warn careful)" = "! careful" ]
  [ "$(fail broken)" = "✗ broken" ]
}

@test "no colour when stdout is not a TTY" {
  run ok ready
  [[ $output != *$'\033'* ]]
}

@test "hk_run only prints under dry run" {
  HK_DRY_RUN=1 run hk_run touch "$BATS_TEST_TMPDIR/x"
  [ "$status" -eq 0 ]
  [ "$output" = "– dry run: touch $BATS_TEST_TMPDIR/x" ]
  [ ! -e "$BATS_TEST_TMPDIR/x" ]
}

@test "hk_run runs the command otherwise" {
  HK_DRY_RUN=0 hk_run touch "$BATS_TEST_TMPDIR/x"
  [ -e "$BATS_TEST_TMPDIR/x" ]
}

@test "hk_confirm: yes under --yes, no without a terminal" {
  HK_YES=1 hk_confirm "Go?"
  HK_YES=0 run hk_confirm "Go?" </dev/null
  [ "$status" -ne 0 ]
}

@test "not_implemented warns and returns its code" {
  run not_implemented tailscale
  [ "$status" -eq "$HK_E_NOT_IMPLEMENTED" ]
  [ "$output" = "! tailscale: not implemented yet" ]
}
