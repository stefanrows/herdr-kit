#!/usr/bin/env bats
# Stubs live in $BATS_TEST_TMPDIR/bin and log every call to $CALLS.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/ui.sh"
  source "$BATS_TEST_DIRNAME/../lib/os.sh"
  source "$BATS_TEST_DIRNAME/../lib/ssh.sh"
  export NO_COLOR=1
  export HK_OS_RELEASE="$BATS_TEST_TMPDIR/os-release"
  export HK_WSL_CONF="$BATS_TEST_TMPDIR/wsl.conf"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  : >"$CALLS"
  mkdir "$BATS_TEST_TMPDIR/bin"
  # PATH holds only the stubs plus the few real tools the module needs, so the
  # host's own tailscale/ss/systemctl never leak in.
  mkdir "$BATS_TEST_TMPDIR/tools"
  local t
  for t in awk grep install mktemp rm cat tr bash env sed dirname chmod; do
    ln -s "$(command -v "$t")" "$BATS_TEST_TMPDIR/tools/$t"
  done
  PATH="$BATS_TEST_TMPDIR/bin:$BATS_TEST_TMPDIR/tools"
  stub sudo 'exec "$@"'
  stub id 'echo 1000'
}

# stub <name> <body>: a command that logs its arguments, then runs <body>.
stub() {
  printf '#!/usr/bin/env bash\necho "%s $*" >>"$CALLS"\n%s\n' "$1" "$2" >"$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

os_debian() {
  printf 'ID=ubuntu\nID_LIKE=debian\n' >"$HK_OS_RELEASE"
  HK_UNAME_S=Linux HK_UNAME_R=${1:-6.8.0-generic} hk_detect_os
}

os_arch() {
  printf 'ID=arch\n' >"$HK_OS_RELEASE"
  HK_UNAME_S=Linux HK_UNAME_R=6.17.1-arch1-1 hk_detect_os
}

os_wsl() { os_debian 6.6.87.2-microsoft-standard-WSL2; }

os_mac() { HK_UNAME_S=Darwin HK_UNAME_R=25.0.0 hk_detect_os; }

# Healthy Linux box: systemd up, ssh active and listening, no tailscale.
healthy() {
  stub systemctl '[[ $1 == is-system-running ]] && echo running; exit 0'
  stub ss 'echo "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*"'
}

@test "Debian: sshd active and listening passes" {
  os_debian
  healthy
  run check_ssh
  [ "$status" -eq 0 ]
  [[ $output == *"OpenSSH server is running"* ]]
}

@test "Debian: sshd not running fails, install uses apt and enables ssh" {
  os_debian
  stub systemctl 'case $1 in enable) exit 0 ;; is-system-running) echo running ;; *) exit 3 ;; esac'
  stub ss 'true'
  stub apt-get 'true'
  check_ssh >/dev/null && return 1
  install_ssh >/dev/null
  grep -q 'apt-get install -y openssh-server' "$CALLS"
  grep -q 'systemctl enable --now ssh$' "$CALLS"
}

@test "Arch: install uses pacman and enables sshd" {
  os_arch
  stub systemctl 'case $1 in enable) exit 0 ;; is-system-running) echo running ;; *) exit 3 ;; esac'
  stub ss 'true'
  stub pacman 'true'
  check_ssh >/dev/null && return 1
  install_ssh >/dev/null
  grep -q 'pacman -S --needed openssh' "$CALLS"
  grep -q 'systemctl enable --now sshd$' "$CALLS"
}

@test "install under --dry-run changes nothing" {
  os_debian
  stub systemctl 'case $1 in enable) exit 0 ;; is-system-running) echo running ;; *) exit 3 ;; esac'
  stub ss 'true'
  stub apt-get 'true'
  HK_DRY_RUN=1
  check_ssh >/dev/null || true
  run install_ssh
  [ "$status" -eq 0 ]
  [[ $output == *"dry run: sudo apt-get install -y openssh-server"* ]]
  ! grep -q '^apt-get' "$CALLS"
  ! grep -q 'enable' "$CALLS"
}

@test "Ubuntu socket activation counts as active" {
  os_debian
  stub systemctl '[[ $1 == is-active && $3 == ssh.socket ]] && exit 0; [[ $1 == is-system-running ]] && echo running; exit 3'
  stub ss 'echo "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*"'
  run check_ssh
  [ "$status" -eq 0 ]
}

@test "WSL without systemd: fix_systemd offered, sshd install not attempted" {
  os_wsl
  stub systemctl 'echo offline; exit 1'
  stub ss 'true'
  stub apt-get 'true'
  run check_ssh
  [ "$status" -eq 1 ]
  [[ $output == *"systemd is not running"* ]]
  check_ssh >/dev/null || true
  run install_ssh
  [ "$status" -eq 1 ]
  [[ $output == *"wsl --shutdown"* ]]
  grep -q '^\[boot\]' "$HK_WSL_CONF"
  grep -q '^systemd=true' "$HK_WSL_CONF"
  ! grep -q 'apt-get' "$CALLS"
}

@test "WSL without systemd under --dry-run: no file written, no install" {
  os_wsl
  stub systemctl 'echo offline; exit 1'
  stub apt-get 'true'
  HK_DRY_RUN=1
  check_ssh >/dev/null || true
  run install_ssh
  [ "$status" -eq 0 ]
  [[ $output == *"dry run: sudo install"* ]]
  [ ! -e "$HK_WSL_CONF" ]
  ! grep -q 'apt-get' "$CALLS"
}

@test "fix_systemd keeps existing sections and adds to [boot]" {
  os_wsl
  printf '[user]\ndefault=stefan\n\n[boot]\ncommand=echo hi\n\n[interop]\nenabled=true\n' >"$HK_WSL_CONF"
  fix_systemd >/dev/null
  run cat "$HK_WSL_CONF"
  [[ $output == *"default=stefan"* ]]
  [[ $output == *"[interop]"* ]]
  [[ $output == *"command=echo hi"* ]]
  [ "$(grep -c '^systemd=true' "$HK_WSL_CONF")" -eq 1 ]
  [ "$(grep -c '^\[boot\]' "$HK_WSL_CONF")" -eq 1 ]
}

@test "fix_systemd flips systemd=false" {
  os_wsl
  printf '[boot]\nsystemd=false\n' >"$HK_WSL_CONF"
  fix_systemd >/dev/null
  run cat "$HK_WSL_CONF"
  [ "$(grep -c systemd "$HK_WSL_CONF")" -eq 1 ]
  [[ $output == *"systemd=true"* ]]
}

@test "WSL: port 22 owned outside this distro fails with a hint, no install" {
  os_wsl
  stub systemctl '[[ $1 == is-system-running ]] && echo running; exit 3'
  stub ss 'echo "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*"'
  stub apt-get 'true'
  run check_ssh
  [ "$status" -eq 1 ]
  [[ $output == *"outside this distro"* ]]
  check_ssh >/dev/null || true
  run install_ssh
  [ "$status" -eq 1 ]
  ! grep -q 'apt-get' "$CALLS"
}

@test "macOS: Remote Login off is a skip, not a failure" {
  os_mac
  stub nc 'exit 1'
  run check_ssh
  [ "$status" -eq 0 ]
  [[ $output == *"Remote Login is off"* ]]
}

@test "macOS: Remote Login on passes" {
  os_mac
  stub nc 'exit 0'
  run check_ssh
  [ "$status" -eq 0 ]
  [[ $output == *"Remote Login is on"* ]]
}

@test "Tailscale SSH on: check fails, Linux fix runs tailscale set --ssh=false" {
  os_debian
  healthy
  stub tailscale '[[ $1 == debug ]] && printf "{\n  \"RunSSH\": true\n}\n"; exit 0'
  run check_tailscale_ssh_off
  [ "$status" -eq 1 ]
  check_ssh >/dev/null || true
  install_ssh >/dev/null
  grep -q 'tailscale set --ssh=false' "$CALLS"
}

@test "Tailscale SSH on: dry run only prints the fix" {
  os_debian
  healthy
  stub tailscale '[[ $1 == debug ]] && printf "{\n  \"RunSSH\": true\n}\n"; exit 0'
  HK_DRY_RUN=1
  check_ssh >/dev/null || true
  run install_ssh
  [ "$status" -eq 0 ]
  [[ $output == *"dry run: sudo tailscale set --ssh=false"* ]]
  ! grep -q 'tailscale set' "$CALLS"
}

@test "Tailscale SSH off passes" {
  os_debian
  stub tailscale '[[ $1 == debug ]] && printf "{\n  \"RunSSH\": false\n}\n"; exit 0'
  run check_tailscale_ssh_off
  [ "$status" -eq 0 ]
  [[ $output == *"Tailscale SSH is off"* ]]
}

@test "Tailscale prefs unreadable counts as not off" {
  os_debian
  stub tailscale 'exit 1'
  run check_tailscale_ssh_off
  [ "$status" -eq 1 ]
}

@test "No tailscale: skip" {
  os_debian
  run check_tailscale_ssh_off
  [ "$status" -eq 0 ]
  [[ $output == *"tailscale not installed"* ]]
}

@test "macOS: Tailscale SSH on prints the command as a hint, changes nothing" {
  os_mac
  stub nc 'exit 0'
  stub tailscale '[[ $1 == debug ]] && printf "{\n  \"RunSSH\": true\n}\n"; exit 0'
  check_ssh >/dev/null || true
  run install_ssh
  [ "$status" -eq 1 ]
  [[ $output == *"tailscale set --ssh=false"* ]]
  ! grep -q 'tailscale set' "$CALLS"
}
