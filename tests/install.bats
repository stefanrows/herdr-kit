#!/usr/bin/env bats

# Always pipe the installer: that is the public one-liner, and it leaves
# BASH_SOURCE unbound. Tests never source install.sh.

setup() {
  unset HK_REF HK_REPO HK_PREFIX HK_SHARE_DIR HK_BIN_DIR HK_TARBALL_URL
  INSTALL_SH="$BATS_TEST_DIRNAME/../install.sh"
  HOME="$BATS_TEST_TMPDIR/home"
  PREFIX="$BATS_TEST_TMPDIR/prefix"
  mkdir -p "$HOME"
  export HOME
  ORIG_PATH=$PATH
}

teardown() {
  PATH=$ORIG_PATH
}

# Mini upstream git repo tagged v0.1.0, with herdr-kit + lib/ so fetch accepts it.
make_upstream() {
  local repo=$BATS_TEST_TMPDIR/upstream
  mkdir -p "$repo/lib"
  printf '#!/usr/bin/env bash\nprintf "stub %s\\n" "$*"\n' >"$repo/herdr-kit"
  chmod +x "$repo/herdr-kit"
  printf '# lib\n' >"$repo/lib/ui.sh"
  git -C "$repo" init -q
  git -C "$repo" config user.email kit@example.invalid
  git -C "$repo" config user.name kit
  git -C "$repo" add .
  git -C "$repo" commit -qm v0.1.0
  git -C "$repo" tag v0.1.0
  printf '%s\n' "$repo"
}

tag_other_ref() {
  local repo=$1
  printf '#!/usr/bin/env bash\nprintf "other-ref\\n"\n' >"$repo/herdr-kit"
  chmod +x "$repo/herdr-kit"
  git -C "$repo" add herdr-kit
  git -C "$repo" commit -qm other
  git -C "$repo" tag other-ref
}

# cat | bash is the curl | bash path; env vars go on the receiving bash.
run_install() {
  cat "$INSTALL_SH" | env HOME="$HOME" "$@" bash
}

installed_ok() {
  PATH=$ORIG_PATH
  [[ -x $PREFIX/bin/herdr-kit ]]
  [[ -d $PREFIX/share/herdr-kit/lib ]]
  [[ $(readlink "$PREFIX/bin/herdr-kit") = "$PREFIX/share/herdr-kit/herdr-kit" ]]
}

@test "install.sh never reads BASH_SOURCE" {
  ! grep -qE '\$\{?BASH_SOURCE' "$INSTALL_SH"
}

@test "install.sh uses set -euo pipefail" {
  grep -q '^set -euo pipefail$' "$INSTALL_SH"
}

@test "piped into bash installs the default tag v0.1.0" {
  local repo
  repo=$(make_upstream)
  tag_other_ref "$repo"
  run run_install HK_REPO="$repo" HK_PREFIX="$PREFIX"
  [ "$status" -eq 0 ]
  installed_ok
  grep -q 'stub' "$PREFIX/share/herdr-kit/herdr-kit"
  ! grep -q other-ref "$PREFIX/share/herdr-kit/herdr-kit"
  [[ $output == *"Next: herdr-kit setup"* ]]
  [[ $output == *"Installing herdr-kit (v0.1.0)"* ]]
}

@test "HK_REF selects a different tag" {
  local repo
  repo=$(make_upstream)
  tag_other_ref "$repo"
  run run_install HK_REPO="$repo" HK_PREFIX="$PREFIX" HK_REF=other-ref
  [ "$status" -eq 0 ]
  grep -q other-ref "$PREFIX/share/herdr-kit/herdr-kit"
  [[ $output == *"Installing herdr-kit (other-ref)"* ]]
}

@test "re-run is idempotent and refreshes the tree" {
  local repo
  repo=$(make_upstream)
  run_install HK_REPO="$repo" HK_PREFIX="$PREFIX"
  tag_other_ref "$repo"
  run run_install HK_REPO="$repo" HK_PREFIX="$PREFIX" HK_REF=other-ref
  [ "$status" -eq 0 ]
  installed_ok
  grep -q other-ref "$PREFIX/share/herdr-kit/herdr-kit"
  [[ $output == *"Next: herdr-kit setup"* ]]
}

@test "re-run replaces a regular file at the bin path with a symlink" {
  local repo
  repo=$(make_upstream)
  mkdir -p "$PREFIX/bin"
  printf 'old\n' >"$PREFIX/bin/herdr-kit"
  run run_install HK_REPO="$repo" HK_PREFIX="$PREFIX"
  [ "$status" -eq 0 ]
  installed_ok
}

@test "does not run herdr-kit setup itself" {
  local repo
  repo=$(make_upstream)
  printf '#!/usr/bin/env bash\nprintf "setup-ran\\n" >"$PREFIX/ran"\n' >"$repo/herdr-kit"
  chmod +x "$repo/herdr-kit"
  git -C "$repo" add herdr-kit
  git -C "$repo" commit -qm setup-probe
  git -C "$repo" tag -f v0.1.0
  run run_install HK_REPO="$repo" HK_PREFIX="$PREFIX"
  [ "$status" -eq 0 ]
  [ ! -e "$PREFIX/ran" ]
  [[ $output != *"setup-ran"* ]]
}

@test "warns when the bin dir is not on PATH" {
  local repo
  repo=$(make_upstream)
  run run_install HK_REPO="$repo" HK_PREFIX="$PREFIX"
  [ "$status" -eq 0 ]
  [[ $output == *"not on your PATH"* ]]
}

@test "no PATH warning when the bin dir is already on PATH" {
  local repo
  repo=$(make_upstream)
  mkdir -p "$PREFIX/bin"
  PATH="$PREFIX/bin:$PATH"
  run run_install HK_REPO="$repo" HK_PREFIX="$PREFIX" PATH="$PATH"
  [ "$status" -eq 0 ]
  [[ $output != *"not on your PATH"* ]]
}

@test "failed fetch leaves a previous install in place" {
  local repo
  repo=$(make_upstream)
  run_install HK_REPO="$repo" HK_PREFIX="$PREFIX"
  [ -x "$PREFIX/bin/herdr-kit" ]
  mkdir -p "$BATS_TEST_TMPDIR/empty/lib"
  git -C "$BATS_TEST_TMPDIR/empty" init -q
  git -C "$BATS_TEST_TMPDIR/empty" config user.email kit@example.invalid
  git -C "$BATS_TEST_TMPDIR/empty" config user.name kit
  printf '# lib\n' >"$BATS_TEST_TMPDIR/empty/lib/ui.sh"
  git -C "$BATS_TEST_TMPDIR/empty" add .
  git -C "$BATS_TEST_TMPDIR/empty" commit -qm incomplete
  git -C "$BATS_TEST_TMPDIR/empty" tag v0.1.0
  run run_install HK_REPO="$BATS_TEST_TMPDIR/empty" HK_PREFIX="$PREFIX"
  [ "$status" -ne 0 ]
  [[ $output == *"missing herdr-kit or lib/"* ]]
  grep -q stub "$PREFIX/share/herdr-kit/herdr-kit"
}

@test "tarball fallback when git is missing (GitHub-style wrapper dir)" {
  local repo wrap tarball tools t
  repo=$(make_upstream)
  wrap=$BATS_TEST_TMPDIR/wrap
  mkdir -p "$wrap/herdr-kit-v0.1.0"
  cp -R "$repo/herdr-kit" "$repo/lib" "$wrap/herdr-kit-v0.1.0/"
  tarball=$BATS_TEST_TMPDIR/kit.tar.gz
  tar -czf "$tarball" -C "$wrap" herdr-kit-v0.1.0

  tools=$BATS_TEST_TMPDIR/tools
  mkdir -p "$tools"
  for t in bash sh tar curl mkdir ln rm mv chmod cat mktemp gzip uname env; do
    ln -s "$(command -v "$t")" "$tools/$t"
  done
  PATH="$tools"

  run run_install HK_REPO="$repo" HK_PREFIX="$PREFIX" HK_TARBALL_URL="file://$tarball" PATH="$PATH"
  [ "$status" -eq 0 ]
  installed_ok
  grep -q stub "$PREFIX/share/herdr-kit/herdr-kit"
}

@test "installed symlink runs the real dispatcher" {
  local repo root
  root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  repo=$BATS_TEST_TMPDIR/real
  mkdir -p "$repo"
  # Working tree, not HEAD: the symlink-aware dispatcher may still be uncommitted.
  cp "$root/herdr-kit" "$repo/"
  cp -R "$root/lib" "$repo/"
  git -C "$repo" init -q
  git -C "$repo" config user.email kit@example.invalid
  git -C "$repo" config user.name kit
  git -C "$repo" add .
  git -C "$repo" commit -qm v0.1.0
  git -C "$repo" tag v0.1.0
  run run_install HK_REPO="$repo" HK_PREFIX="$PREFIX"
  [ "$status" -eq 0 ]
  installed_ok
  run "$PREFIX/bin/herdr-kit" --help
  [ "$status" -eq 0 ]
  [[ $output == *"setup "* ]]
  [[ $output == *"doctor "* ]]
}
