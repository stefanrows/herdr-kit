#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../lib/os.sh"
  export HK_OS_RELEASE="$BATS_TEST_TMPDIR/os-release"
}

@test "macOS" {
  HK_UNAME_S=Darwin HK_UNAME_R=25.0.0 hk_detect_os
  [ "$HK_OS" = macos ]
  [ "$HK_WSL" = 0 ]
}

@test "Arch Linux" {
  printf 'NAME="Arch Linux"\nID=arch\n' >"$HK_OS_RELEASE"
  HK_UNAME_S=Linux HK_UNAME_R=6.17.1-arch1-1 hk_detect_os
  [ "$HK_OS" = arch ]
  [ "$HK_WSL" = 0 ]
}

@test "Arch derivative via ID_LIKE" {
  printf 'ID=endeavouros\nID_LIKE=arch\n' >"$HK_OS_RELEASE"
  HK_UNAME_S=Linux HK_UNAME_R=6.17.1 hk_detect_os
  [ "$HK_OS" = arch ]
}

@test "Ubuntu inside WSL2" {
  printf 'ID=ubuntu\nID_LIKE=debian\n' >"$HK_OS_RELEASE"
  HK_UNAME_S=Linux HK_UNAME_R=6.6.87.2-microsoft-standard-WSL2 hk_detect_os
  [ "$HK_OS" = debian ]
  [ "$HK_WSL" = 1 ]
}

@test "Debian with quoted values and no trailing newline" {
  printf 'ID="debian"' >"$HK_OS_RELEASE"
  HK_UNAME_S=Linux HK_UNAME_R=6.1.0-26-amd64 hk_detect_os
  [ "$HK_OS" = debian ]
  [ "$HK_WSL" = 0 ]
}

@test "unknown Linux is unsupported" {
  printf 'ID=fedora\n' >"$HK_OS_RELEASE"
  HK_UNAME_S=Linux HK_UNAME_R=6.11.4 hk_detect_os
  [ "$HK_OS" = unsupported ]
}

@test "missing os-release is unsupported" {
  HK_OS_RELEASE=/nonexistent HK_UNAME_S=Linux HK_UNAME_R=6.11.4 hk_detect_os
  [ "$HK_OS" = unsupported ]
}
