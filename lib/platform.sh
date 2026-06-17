#!/usr/bin/env bash

platform_is_termux_env() {
  [[ -n "${TERMUX_VERSION:-}" || "${PREFIX:-}" == *"/com.termux/files/usr"* ]]
}

platform_detect_default_id() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  if platform_is_termux_env; then
    case "${arch}" in
      aarch64|arm64) echo "termux-aarch64" ;;
      x86_64|amd64) echo "termux-x86_64" ;;
      *) return 1 ;;
    esac
    return 0
  fi

  case "${os}:${arch}" in
    MINGW64_NT*:x86_64|MSYS_NT*:x86_64|CYGWIN_NT*:x86_64) echo "windows-x86_64" ;;
    MINGW64_NT*:arm64|MSYS_NT*:arm64|CYGWIN_NT*:arm64) echo "windows-aarch64" ;;
    Darwin:arm64) echo "macos-aarch64" ;;
    Linux:x86_64|Linux:amd64) echo "linux-x86_64" ;;
    *) return 1 ;;
  esac
}

platform_display_name() {
  case "$1" in
    macos-aarch64) echo "macOS Apple Silicon" ;;
    linux-x86_64) echo "Linux x86_64" ;;
    windows-x86_64) echo "Windows x86_64" ;;
    windows-aarch64) echo "Windows ARM64" ;;
    termux-aarch64) echo "Termux Android aarch64" ;;
    termux-x86_64) echo "Termux Android x86_64" ;;
    *) echo "Unknown" ;;
  esac
}

platform_list_known() {
  printf '%-16s %s\n' "linux-x86_64" "$(platform_display_name linux-x86_64)"
  printf '%-16s %s\n' "macos-aarch64" "$(platform_display_name macos-aarch64)"
  printf '%-16s %s\n' "windows-x86_64" "$(platform_display_name windows-x86_64)"
  printf '%-16s %s\n' "windows-aarch64" "$(platform_display_name windows-aarch64)"
  printf '%-16s %s\n' "termux-aarch64" "$(platform_display_name termux-aarch64)"
  printf '%-16s %s\n' "termux-x86_64" "$(platform_display_name termux-x86_64)"
}

platform_bin_dir() {
  printf '%s\n' "${ROOT_DIR}/bin"
}

platform_config_dir() {
  printf '%s\n' "${ROOT_DIR}"
}

platform_download_asset_keyword() {
  case "$1" in
    macos-aarch64) echo "easytier-macos-aarch64" ;;
    linux-x86_64) echo "easytier-linux-x86_64" ;;
    windows-x86_64) echo "easytier-windows-x86_64" ;;
    windows-aarch64) echo "easytier-windows-aarch64" ;;
    *)
      return 1
      ;;
  esac
}
