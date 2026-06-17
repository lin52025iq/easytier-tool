#!/usr/bin/env bash

autostart_manager() {
  if os_is_termux; then
    echo "termux-boot"
    return 0
  fi

  if os_is_windows; then
    echo "windows-startup"
    return 0
  fi

  case "$(uname -s)" in
    Darwin) echo "launchd" ;;
    Linux) echo "systemd" ;;
    *)
      echo "unsupported"
      ;;
  esac
}

autostart_service_basename() {
  printf 'io.easytierctl.%s' "$1"
}

autostart_service_name() {
  case "$(autostart_manager)" in
    launchd) printf '%s.plist\n' "$(autostart_service_basename "$1")" ;;
    systemd) printf 'easytier-%s.service\n' "$1" ;;
    termux-boot) printf 'easytier-%s.sh\n' "$1" ;;
    windows-startup) printf 'easytier-%s.cmd\n' "$1" ;;
    *) return 1 ;;
  esac
}

autostart_service_path() {
  local name
  name="$(autostart_service_name "$1")" || return 1

  case "$(autostart_manager)" in
    launchd) printf '/Library/LaunchDaemons/%s\n' "$name" ;;
    systemd) printf '/etc/systemd/system/%s\n' "$name" ;;
    termux-boot) printf '%s/.termux/boot/%s\n' "$HOME" "$name" ;;
    windows-startup) printf '%s/%s\n' "$(os_windows_startup_dir)" "$name" ;;
    *) return 1 ;;
  esac
}

autostart_label() {
  printf '%s\n' "$(autostart_service_basename "$1")"
}

autostart_wrapper_stdout_log() {
  printf '%s/autostart.%s.stdout.log\n' "$LOG_DIR" "$1"
}

autostart_wrapper_stderr_log() {
  printf '%s/autostart.%s.stderr.log\n' "$LOG_DIR" "$1"
}

require_system_root() {
  if [[ "$(autostart_manager)" == "termux-boot" || "$(autostart_manager)" == "windows-startup" ]]; then
    return 0
  fi

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if os_has_sudo; then
      print_info "需要 root 权限写入系统开机自启配置，正在使用 sudo 重新运行..."
      exec sudo -E "$SELF_EXECUTABLE" "${ORIGINAL_ARGS[@]}"
    fi
    print_error "当前环境未检测到 sudo，无法写入系统级开机自启配置。"
    exit 1
  fi
}

autostart_service_exists() {
  local service_path
  service_path="$(autostart_service_path "$1" 2>/dev/null)" || return 1
  [[ -f "$service_path" ]]
}

detect_unique_installed_autostart_profile() {
  local matches=()
  local profile

  for profile in create join; do
    if autostart_service_exists "$profile"; then
      matches+=("$profile")
    fi
  done

  if (( ${#matches[@]} == 1 )); then
    printf '%s\n' "${matches[0]}"
  elif (( ${#matches[@]} > 1 )); then
    echo "__AMBIGUOUS__"
  fi
}

resolve_profile_for_autostart() {
  local action="$1"
  local explicit_profile="${2:-}"
  local installed_profile=""
  local config_profile=""

  if [[ -n "$explicit_profile" ]]; then
    ensure_valid_profile "$explicit_profile"
    printf '%s\n' "$explicit_profile"
    return 0
  fi

  if [[ "$action" == "status" || "$action" == "uninstall" ]]; then
    installed_profile="$(detect_unique_installed_autostart_profile || true)"
    if [[ "$installed_profile" == "__AMBIGUOUS__" ]]; then
      echo "错误: 当前同时检测到 create 和 join 的开机自启配置，请显式指定类型。" >&2
      exit 1
    fi
    if [[ -n "$installed_profile" ]]; then
      printf '%s\n' "$installed_profile"
      return 0
    fi
  fi

  config_profile="$(detect_unique_config_profile || true)"
  if [[ "$config_profile" == "__AMBIGUOUS__" ]]; then
    echo "错误: 同时检测到 .env.create 和 .env.join，请显式指定 create 或 join。" >&2
    exit 1
  fi
  if [[ -n "$config_profile" ]]; then
    printf '%s\n' "$config_profile"
    return 0
  fi

  echo "错误: 无法自动判断当前类型，请显式指定 create 或 join。" >&2
  exit 1
}

write_launchd_plist() {
  local profile="$1"
  local target_file="$2"
  local stdout_log
  local stderr_log

  stdout_log="$(autostart_wrapper_stdout_log "$profile")"
  stderr_log="$(autostart_wrapper_stderr_log "$profile")"

  cat >"$target_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(autostart_label "$profile")</string>
  <key>ProgramArguments</key>
  <array>
    <string>${ROOT_DIR}/easytierctl</string>
    <string>fg</string>
    <string>${profile}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${ROOT_DIR}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${stdout_log}</string>
  <key>StandardErrorPath</key>
  <string>${stderr_log}</string>
</dict>
</plist>
EOF
}

write_systemd_unit() {
  local profile="$1"
  local target_file="$2"

  cat >"$target_file" <<EOF
[Unit]
Description=EasyTier ${profile} via easytierctl
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${ROOT_DIR}
ExecStart=${ROOT_DIR}/easytierctl fg ${profile}
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF
}

write_termux_boot_script() {
  local profile="$1"
  local target_file="$2"
  local stdout_log
  local stderr_log

  stdout_log="$(autostart_wrapper_stdout_log "$profile")"
  stderr_log="$(autostart_wrapper_stderr_log "$profile")"

  cat >"$target_file" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
cd "${ROOT_DIR}" || exit 1
mkdir -p "${LOG_DIR}"
termux-wake-lock >/dev/null 2>&1 || true
exec "${ROOT_DIR}/easytierctl" start "${profile}" >>"${stdout_log}" 2>>"${stderr_log}"
EOF
}

write_windows_startup_cmd() {
  local profile="$1"
  local target_file="$2"
  local bash_exe
  local root_native
  local root_posix

  bash_exe="$(os_windows_bash_executable)"
  root_native="$(os_to_native_path "$ROOT_DIR")"
  root_posix="$ROOT_DIR"

  cat >"$target_file" <<EOF
@echo off
cd /d "${root_native}"
"${bash_exe}" -lc "cd '${root_posix}' && ./easytierctl start ${profile}"
EOF
}

cmd_autostart_install() {
  local service_path
  local manager
  local temp_file
  local service_name

  manager="$(autostart_manager)"
  if [[ "$manager" == "unsupported" ]]; then
    print_error "当前系统暂不支持自动安装开机自启。"
    exit 1
  fi

  verify_platform_binaries >/dev/null
  load_profile_config
  validate_config
  ensure_dirs
  require_system_root

  service_path="$(autostart_service_path "$PROFILE")"
  service_name="$(autostart_service_name "$PROFILE")"
  temp_file="$(mktemp "${TMPDIR:-/tmp}/easytier-autostart.XXXXXX")"

  case "$manager" in
    launchd)
      write_launchd_plist "$PROFILE" "$temp_file"
      install -m 644 "$temp_file" "$service_path"
      launchctl bootout system "$service_path" >/dev/null 2>&1 || true
      launchctl bootstrap system "$service_path"
      launchctl enable "system/$(autostart_label "$PROFILE")"
      print_success "已安装并加载 launchd 开机自启"
      ;;
    systemd)
      write_systemd_unit "$PROFILE" "$temp_file"
      install -m 644 "$temp_file" "$service_path"
      systemctl daemon-reload
      systemctl enable --now "$service_name"
      print_success "已安装并启用 systemd 开机自启"
      ;;
    termux-boot)
      mkdir -p "$(dirname "$service_path")"
      write_termux_boot_script "$PROFILE" "$temp_file"
      install -m 755 "$temp_file" "$service_path"
      print_success "已安装 Termux:Boot 开机自启脚本"
      print_warn "请确认已安装并启用 Termux:Boot 应用。"
      if ! bool_is_true "$NO_TUN"; then
        print_warn "Termux 开机自启通常更适合 NO_TUN=true 的场景。"
      fi
      ;;
    windows-startup)
      mkdir -p "$(dirname "$service_path")"
      write_windows_startup_cmd "$PROFILE" "$temp_file"
      install -m 644 "$temp_file" "$service_path"
      print_success "已安装 Windows Startup 开机自启脚本"
      ;;
  esac

  rm -f "$temp_file"
  print_kv "服务文件" "$service_path"
}

cmd_autostart_uninstall() {
  local service_path
  local manager
  local service_name

  manager="$(autostart_manager)"
  if [[ "$manager" == "unsupported" ]]; then
    print_error "当前系统暂不支持自动卸载开机自启。"
    exit 1
  fi

  require_system_root
  service_path="$(autostart_service_path "$PROFILE")"
  service_name="$(autostart_service_name "$PROFILE")"

  if [[ ! -f "$service_path" ]]; then
    print_warn "未找到开机自启配置: $service_path"
    return 0
  fi

  case "$manager" in
    launchd)
      launchctl bootout system "$service_path" >/dev/null 2>&1 || true
      rm -f "$service_path"
      print_success "已卸载 launchd 开机自启"
      ;;
    systemd)
      systemctl disable --now "$service_name" >/dev/null 2>&1 || true
      rm -f "$service_path"
      systemctl daemon-reload
      print_success "已卸载 systemd 开机自启"
      ;;
    termux-boot)
      rm -f "$service_path"
      print_success "已卸载 Termux:Boot 开机自启脚本"
      ;;
    windows-startup)
      rm -f "$service_path"
      print_success "已卸载 Windows Startup 开机自启脚本"
      ;;
  esac

  print_kv "服务文件" "$service_path"
}

cmd_autostart_status() {
  local service_path
  local manager
  local service_name
  local label

  manager="$(autostart_manager)"
  if [[ "$manager" == "unsupported" ]]; then
    print_error "当前系统暂不支持查看开机自启状态。"
    exit 1
  fi

  service_path="$(autostart_service_path "$PROFILE")"
  service_name="$(autostart_service_name "$PROFILE")"
  label="$(autostart_label "$PROFILE")"

  print_heading "开机自启状态"
  print_kv "类型" "$PROFILE"
  print_kv "管理器" "$manager"
  print_kv "服务文件" "$service_path"

  if [[ ! -f "$service_path" ]]; then
    print_warn "当前未安装开机自启配置"
    return 0
  fi

  case "$manager" in
    launchd)
      if launchctl print "system/${label}" >/dev/null 2>&1; then
        print_success "launchd 已加载"
      else
        print_warn "launchd 配置文件已存在，但当前未加载"
      fi
      ;;
    systemd)
      print_kv "enabled" "$(systemctl is-enabled "$service_name" 2>/dev/null || echo unknown)"
      print_kv "active" "$(systemctl is-active "$service_name" 2>/dev/null || echo unknown)"
      ;;
    termux-boot)
      print_success "Termux:Boot 脚本已安装"
      print_warn "请确认 Termux:Boot 应用已安装，并允许开机自动运行。"
      ;;
    windows-startup)
      print_success "Windows Startup 脚本已安装"
      ;;
  esac
}
