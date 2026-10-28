# shellcheck shell=bash
# OS detection. Exports HK_OS (macos | arch | debian | unsupported) and HK_WSL (1 | 0).
# Tests override HK_UNAME_S, HK_UNAME_R and HK_OS_RELEASE.

# _hk_os_release_field <field> <file>: prints the unquoted value, if any.
_hk_os_release_field() {
  local line
  [[ -r $2 ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      "$1="*)
        line=${line#*=}
        line=${line#[\"\']}
        line=${line%[\"\']}
        printf '%s\n' "$line"
        return 0
        ;;
    esac
  done <"$2"
}

hk_detect_os() {
  local uname_s uname_r os_release id id_like
  uname_s=${HK_UNAME_S:-$(uname -s)}
  uname_r=${HK_UNAME_R:-$(uname -r)}
  os_release=${HK_OS_RELEASE:-/etc/os-release}

  HK_OS=unsupported
  HK_WSL=0
  case $uname_s in
    Darwin) HK_OS=macos ;;
    Linux)
      id=$(_hk_os_release_field ID "$os_release")
      id_like=$(_hk_os_release_field ID_LIKE "$os_release")
      case " $id $id_like " in
        *" arch "*) HK_OS=arch ;;
        *" debian "* | *" ubuntu "*) HK_OS=debian ;;
      esac
      # WSL kernels carry "microsoft" in the release string, e.g. 5.15.x-microsoft-standard-WSL2.
      case $(printf '%s' "$uname_r" | tr '[:upper:]' '[:lower:]') in
        *microsoft*) HK_WSL=1 ;;
      esac
      ;;
  esac
  export HK_OS HK_WSL
}
