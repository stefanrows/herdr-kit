#!/usr/bin/env bash
# herdr-kit installer. Safe to pipe: curl -fsSL .../install.sh | bash
# Fetches the full tree (piped bash has no BASH_SOURCE and cannot find lib/).
set -euo pipefail

HK_REPO=${HK_REPO:-https://github.com/stefanrows/herdr-kit.git}
HK_REF=${HK_REF:-v0.1.0}
HK_PREFIX=${HK_PREFIX:-$HOME/.local}
HK_SHARE_DIR=${HK_SHARE_DIR:-$HK_PREFIX/share/herdr-kit}
HK_BIN_DIR=${HK_BIN_DIR:-$HK_PREFIX/bin}

_hk_abs() {
  case $1 in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

# GitHub archive URL for a tag, branch, or SHA. HK_TARBALL_URL overrides (tests).
_hk_tarball_url() {
  if [[ -n ${HK_TARBALL_URL:-} ]]; then
    printf '%s\n' "$HK_TARBALL_URL"
    return 0
  fi
  local repo=${HK_REPO%.git}
  case $repo in
    https://github.com/* | https://www.github.com/*)
      printf '%s/archive/%s.tar.gz\n' "$repo" "$HK_REF"
      ;;
    *)
      return 1
      ;;
  esac
}

# Prints the directory that contains herdr-kit and lib/, whether the archive
# unpacked flat or as GitHub's <repo>-<ref>/ wrapper.
_hk_tree_root() {
  local dir=$1 d
  if [[ -f $dir/herdr-kit && -d $dir/lib ]]; then
    printf '%s\n' "$dir"
    return 0
  fi
  for d in "$dir"/*/; do
    if [[ -f ${d}herdr-kit && -d ${d}lib ]]; then
      printf '%s\n' "${d%/}"
      return 0
    fi
  done
  return 1
}

_hk_fetch_tarball() {
  local dest=$1 url=$2 tmp root
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/herdr-kit.tgz.XXXXXX")
  curl -fsSL "$url" | tar -xz -C "$tmp"
  root=$(_hk_tree_root "$tmp") || {
    printf 'herdr-kit: archive did not contain herdr-kit and lib/\n' >&2
    rm -rf "$tmp"
    return 1
  }
  rm -rf "$dest"
  mv "$root" "$dest"
  [[ $root == "$tmp" ]] || rm -rf "$tmp"
}

_hk_fetch() {
  local dest=$1 staging=$2 src=$2/src
  local fetched=0 used_git=0 url

  mkdir -p "$staging"
  if command -v git >/dev/null 2>&1; then
    used_git=1
    if GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$HK_REF" --quiet "$HK_REPO" "$src"; then
      fetched=1
    fi
  fi

  if [[ $fetched -eq 0 ]]; then
    if url=$(_hk_tarball_url); then
      if [[ $used_git -eq 1 ]]; then
        printf 'herdr-kit: git clone failed; trying tarball\n' >&2
      fi
      command -v curl >/dev/null 2>&1 || {
        printf 'herdr-kit: need curl to fetch %s\n' "$url" >&2
        return 1
      }
      _hk_fetch_tarball "$src" "$url"
      fetched=1
    else
      if [[ $used_git -eq 1 ]]; then
        printf 'herdr-kit: git clone of %s (ref %s) failed\n' "$HK_REPO" "$HK_REF" >&2
      else
        printf 'herdr-kit: need git or curl to install\n' >&2
      fi
      return 1
    fi
  fi

  if [[ ! -f $src/herdr-kit || ! -d $src/lib ]]; then
    printf 'herdr-kit: fetched tree is missing herdr-kit or lib/\n' >&2
    return 1
  fi

  mkdir -p "${dest%/*}"
  rm -rf "$dest"
  mv "$src" "$dest"
  chmod +x "$dest/herdr-kit"
}

_hk_bin_on_path() {
  case ":$PATH:" in
    *":$HK_BIN_DIR:"*) return 0 ;;
    *) return 1 ;;
  esac
}

hk_install() {
  local staging
  HK_PREFIX=$(_hk_abs "$HK_PREFIX")
  HK_SHARE_DIR=$(_hk_abs "$HK_SHARE_DIR")
  HK_BIN_DIR=$(_hk_abs "$HK_BIN_DIR")

  staging=$(mktemp -d "${TMPDIR:-/tmp}/herdr-kit.XXXXXX")
  # shellcheck disable=SC2064
  trap 'rm -rf "'"$staging"'"' EXIT

  printf 'Installing herdr-kit (%s)\n' "$HK_REF"
  _hk_fetch "$HK_SHARE_DIR" "$staging"
  mkdir -p "$HK_BIN_DIR"
  ln -sfn "$HK_SHARE_DIR/herdr-kit" "$HK_BIN_DIR/herdr-kit"

  printf 'Installed to %s\n' "$HK_SHARE_DIR"
  printf 'Linked %s\n' "$HK_BIN_DIR/herdr-kit"
  if ! _hk_bin_on_path; then
    printf 'herdr-kit is in %s, which is not on your PATH. Add it to your shell profile.\n' "$HK_BIN_DIR"
  fi
  printf '\nNext: herdr-kit setup\n'
}

hk_install
