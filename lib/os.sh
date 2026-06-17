#!/usr/bin/env bash

os_is_termux() {
  [[ -n "${TERMUX_VERSION:-}" || "${PREFIX:-}" == *"/com.termux/files/usr"* ]]
}

os_is_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

os_has_sudo() {
  command -v sudo >/dev/null 2>&1
}

os_windows_path_to_posix() {
  local path="$1"
  local drive=""
  local rest=""

  path="${path//\\//}"
  case "$path" in
    [A-Za-z]:/*)
      drive="${path%%:*}"
      rest="${path#?:}"
      drive="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
      printf '/%s%s\n' "$drive" "$rest"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

os_to_native_path() {
  local path="$1"
  if os_is_windows && command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path"
  else
    printf '%s\n' "$path"
  fi
}

os_windows_startup_dir() {
  local raw=""

  if [[ -n "${APPDATA:-}" ]]; then
    raw="${APPDATA}"
  elif command -v powershell >/dev/null 2>&1; then
    raw="$(powershell -NoProfile -Command '[Environment]::GetFolderPath("Startup")' 2>/dev/null | tr -d '\r' | head -1)"
    if [[ -n "$raw" ]]; then
      printf '%s\n' "$(os_windows_path_to_posix "$raw")"
      return 0
    fi
  fi

  if [[ -n "$raw" ]]; then
    printf '%s/Microsoft/Windows/Start Menu/Programs/Startup\n' "$(os_windows_path_to_posix "$raw")"
  fi
}

os_windows_bash_executable() {
  local bash_path=""

  bash_path="$(command -v bash 2>/dev/null || true)"
  [[ -n "$bash_path" ]] || return 1
  os_to_native_path "$bash_path"
}

os_default_hostname() {
  if os_is_termux && command -v getprop >/dev/null 2>&1; then
    local termux_hostname=""
    termux_hostname="$({
      getprop net.hostname 2>/dev/null
      getprop ro.product.device 2>/dev/null
      getprop ro.product.model 2>/dev/null
    } | awk 'NF { print; exit }')"
    if [[ -n "$termux_hostname" ]]; then
      printf '%s\n' "$termux_hostname"
      return 0
    fi
  fi

  if os_is_windows; then
    hostname 2>/dev/null || printf 'windows-host\n'
    return 0
  fi

  case "$(uname -s)" in
    Darwin)
      if command -v scutil >/dev/null 2>&1; then
        scutil --get LocalHostName 2>/dev/null || hostname -s
      else
        hostname -s 2>/dev/null || hostname
      fi
      ;;
    *)
      hostname -s 2>/dev/null || hostname
      ;;
  esac
}

os_detect_machine_id() {
  case "$(uname -s)" in
    Darwin)
      if command -v ioreg >/dev/null 2>&1; then
        ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/ { print tolower($4); exit }'
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      if command -v powershell >/dev/null 2>&1; then
        powershell -NoProfile -Command '(Get-CimInstance Win32_ComputerSystemProduct).UUID.ToLower()' 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }'
      fi
      ;;
    Linux)
      if os_is_termux && command -v getprop >/dev/null 2>&1; then
        {
          getprop ro.serialno 2>/dev/null
          getprop ro.boot.serialno 2>/dev/null
          getprop persist.sys.device_name 2>/dev/null
          getprop ro.product.device 2>/dev/null
        } | awk 'NF { print tolower($0); exit }'
        return 0
      fi
      if [[ -r /etc/machine-id ]]; then
        tr -d '[:space:]' </etc/machine-id
      fi
      ;;
  esac
}

os_tcp_probe() {
  local host="$1"
  local port="$2"

  if ! command -v nc >/dev/null 2>&1; then
    return 2
  fi

  case "$(uname -s)" in
    Darwin) nc -z -G 5 "$host" "$port" >/dev/null 2>&1 ;;
    *) nc -z -w 5 "$host" "$port" >/dev/null 2>&1 ;;
  esac
}
