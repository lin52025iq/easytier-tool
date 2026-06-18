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
    Linux:aarch64|Linux:arm64) echo "linux-aarch64" ;;
    Linux:x86_64|Linux:amd64) echo "linux-x86_64" ;;
    *) return 1 ;;
  esac
}

platform_display_name() {
  case "$1" in
    macos-aarch64) echo "macOS Apple Silicon" ;;
    linux-aarch64) echo "Linux ARM64" ;;
    linux-x86_64) echo "Linux x86_64" ;;
    windows-x86_64) echo "Windows x86_64" ;;
    windows-aarch64) echo "Windows ARM64" ;;
    termux-aarch64) echo "Termux Android aarch64" ;;
    termux-x86_64) echo "Termux Android x86_64" ;;
    *) echo "Unknown" ;;
  esac
}

platform_list_known() {
  printf '%-16s %s\n' "linux-aarch64" "$(platform_display_name linux-aarch64)"
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

platform_normalize_arch() {
  case "${1:-}" in
    aarch64|arm64) echo "aarch64" ;;
    x86_64|amd64) echo "x86_64" ;;
    armv7l|armv7|armhf) echo "armv7" ;;
    i386|i686) echo "i686" ;;
    *) return 1 ;;
  esac
}

platform_detect_os_family() {
  if platform_is_termux_env; then
    echo "termux"
    return 0
  fi

  case "$(uname -s 2>/dev/null || true)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) return 1 ;;
  esac
}

platform_download_asset_keywords() {
  local platform_id="${1:-}"
  local os_family=""
  local arch=""

  case "$platform_id" in
    macos-aarch64)
      printf '%s\n' "easytier-macos-aarch64" "macos-aarch64" "darwin-aarch64"
      return 0
      ;;
    linux-aarch64)
      printf '%s\n' "easytier-linux-aarch64" "linux-aarch64" "linux-arm64"
      return 0
      ;;
    linux-x86_64)
      printf '%s\n' "easytier-linux-x86_64" "linux-x86_64" "linux-amd64"
      return 0
      ;;
    windows-x86_64)
      printf '%s\n' "easytier-windows-x86_64" "windows-x86_64" "windows-amd64"
      return 0
      ;;
    windows-aarch64)
      printf '%s\n' "easytier-windows-aarch64" "windows-aarch64" "windows-arm64"
      return 0
      ;;
    termux-aarch64)
      printf '%s\n' \
        "easytier-android-aarch64" \
        "android-aarch64" \
        "android-arm64" \
        "easytier-linux-aarch64" \
        "linux-aarch64" \
        "linux-arm64"
      return 0
      ;;
    termux-x86_64)
      printf '%s\n' \
        "easytier-android-x86_64" \
        "android-x86_64" \
        "android-amd64" \
        "easytier-linux-x86_64" \
        "linux-x86_64" \
        "linux-amd64"
      return 0
      ;;
  esac

  os_family="$(platform_detect_os_family 2>/dev/null || true)"
  arch="$(platform_normalize_arch "$(uname -m 2>/dev/null || true)" 2>/dev/null || true)"

  if [[ -z "$os_family" || -z "$arch" ]]; then
    return 1
  fi

  case "$os_family:$arch" in
    termux:aarch64)
      printf '%s\n' "easytier-android-aarch64" "android-aarch64" "android-arm64" "easytier-linux-aarch64" "linux-aarch64"
      ;;
    termux:x86_64)
      printf '%s\n' "easytier-android-x86_64" "android-x86_64" "easytier-linux-x86_64" "linux-x86_64"
      ;;
    linux:aarch64)
      printf '%s\n' "easytier-linux-aarch64" "linux-aarch64" "linux-arm64"
      ;;
    linux:x86_64)
      printf '%s\n' "easytier-linux-x86_64" "linux-x86_64" "linux-amd64"
      ;;
    macos:aarch64)
      printf '%s\n' "easytier-macos-aarch64" "macos-aarch64" "darwin-aarch64"
      ;;
    windows:aarch64)
      printf '%s\n' "easytier-windows-aarch64" "windows-aarch64" "windows-arm64"
      ;;
    windows:x86_64)
      printf '%s\n' "easytier-windows-x86_64" "windows-x86_64" "windows-amd64"
      ;;
    *)
      return 1
      ;;
  esac
}

platform_download_asset_keyword() {
  platform_download_asset_keywords "$1" | head -1
}
