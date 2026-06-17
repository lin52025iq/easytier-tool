#!/usr/bin/env bash

COMMAND=""
PROFILE=""
POSITIONAL_ARGS=()
ORIGINAL_ARGS=()
SELF_EXECUTABLE=""
FORCE_OVERWRITE="false"

ROLE_LABEL=""
CONFIG_ENV_FILE=""
EXECUTABLES_ENV_FILE=""
ACTIVE_EXECUTABLES_ENV_FILE=""
CONFIG_ENV_EXAMPLE_FILE=""
EXECUTABLES_ENV_EXAMPLE_FILE=""
AUTOSTART_ACTION=""
BIN_DIR=""
PLATFORM_ID=""
PLATFORM_NAME=""

CORE_BIN=""
CLI_BIN=""
WEB_BIN=""
WEB_EMBED_BIN=""

CONFIG_LOADED="false"
BINARY_CONFIG_LOADED="false"
BUILT_ARGS=()

NETWORK_NAME=""
NETWORK_SECRET=""
HOSTNAME=""
INSTANCE_NAME=""
PRIVATE_MODE="true"
USE_DHCP="false"
NODE_IPV4=""
NO_TUN="false"
RPC_PORTAL=""
MACHINE_ID=""
STATE_DIR=""
LOG_DIR=""
PID_FILE=""
CONSOLE_LOG_LEVEL="info"
FILE_LOG_LEVEL="info"
LISTENER_URLS=""
MAPPED_LISTENERS=""
PEER_URLS=""
PROXY_NETWORKS=""
TCP_WHITELIST=""
UDP_WHITELIST=""
EXTRA_ARGS=""
LOG_MAX_BYTES=$((10 * 1024 * 1024))

EASYTIER_CORE_FILENAME="easytier-core"
EASYTIER_CLI_FILENAME="easytier-cli"
EASYTIER_WEB_FILENAME="easytier-web"
EASYTIER_WEB_EMBED_FILENAME="easytier-web-embed"

bool_is_true() {
  [[ "${1:-false}" == "true" ]]
}

trim_text() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

split_csv() {
  local raw="${1:-}"
  local result=()
  local item

  IFS=',' read -r -a result <<<"$raw"
  for item in "${result[@]}"; do
    item="$(trim_text "$item")"
    [[ -n "$item" ]] && printf '%s\n' "$item"
  done
}

csv_to_space_joined() {
  local raw="${1:-}"
  local item
  local parts=()

  while IFS= read -r item; do
    parts+=("$item")
  done < <(split_csv "$raw")

  if (( ${#parts[@]} > 0 )); then
    printf '%s\n' "${parts[*]}"
  fi
}

profile_label() {
  case "$1" in
    create) echo "创建组网入口节点" ;;
    join) echo "加入现有组网" ;;
    *)
      echo "错误: 不支持的类型 $1，必须是 create 或 join。" >&2
      exit 1
      ;;
  esac
}

parse_common_options() {
  POSITIONAL_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)
        FORCE_OVERWRITE="true"
        shift
        ;;
      --*)
        echo "错误: 不支持的参数 $1" >&2
        echo "当前脚本只支持 --force，其余配置请直接修改项目根目录下的 .env 文件。" >&2
        exit 1
        ;;
      *)
        POSITIONAL_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

prepare_runtime_context() {
  PLATFORM_ID="$(platform_detect_default_id || true)"
  PLATFORM_NAME="$(platform_display_name "${PLATFORM_ID:-unknown}")"
  BIN_DIR="$(platform_bin_dir)"
  EXECUTABLES_ENV_FILE="${ROOT_DIR}/.env.executables"
  ACTIVE_EXECUTABLES_ENV_FILE="$EXECUTABLES_ENV_FILE"
  EXECUTABLES_ENV_EXAMPLE_FILE="${ROOT_DIR}/env-templates/.env.executables.example"
}

set_profile_context() {
  PROFILE="$1"
  ROLE_LABEL="$(profile_label "$PROFILE")"
  CONFIG_ENV_FILE="${ROOT_DIR}/.env.${PROFILE}"
  CONFIG_ENV_EXAMPLE_FILE="${ROOT_DIR}/env-templates/.env.${PROFILE}.example"
}

profile_config_file() {
  printf '%s/.env.%s\n' "$ROOT_DIR" "$1"
}

profile_pid_file() {
  printf '%s/.state/%s/easytier.pid\n' "$ROOT_DIR" "$1"
}

profile_is_valid() {
  [[ "$1" == "create" || "$1" == "join" ]]
}

ensure_valid_profile() {
  if ! profile_is_valid "$1"; then
    echo "错误: 不支持的类型 $1，必须是 create 或 join。" >&2
    exit 1
  fi
}

profile_config_exists() {
  [[ -f "$(profile_config_file "$1")" ]]
}

profile_pid_running() {
  local pid_file
  local pid

  pid_file="$(profile_pid_file "$1")"
  [[ -f "$pid_file" ]] || return 1

  pid="$(tr -d '[:space:]' <"$pid_file" 2>/dev/null)"
  [[ -n "$pid" ]] || return 1
  ps -p "$pid" >/dev/null 2>&1
}

detect_unique_running_profile() {
  local matches=()
  local profile

  for profile in create join; do
    if profile_pid_running "$profile"; then
      matches+=("$profile")
    fi
  done

  if (( ${#matches[@]} == 1 )); then
    printf '%s\n' "${matches[0]}"
  elif (( ${#matches[@]} > 1 )); then
    echo "__AMBIGUOUS__"
  fi
}

detect_unique_config_profile() {
  local matches=()
  local profile

  for profile in create join; do
    if profile_config_exists "$profile"; then
      matches+=("$profile")
    fi
  done

  if (( ${#matches[@]} == 1 )); then
    printf '%s\n' "${matches[0]}"
  elif (( ${#matches[@]} > 1 )); then
    echo "__AMBIGUOUS__"
  fi
}

resolve_profile_for_command() {
  local command="$1"
  local explicit_profile="${2:-}"
  local running_profile=""
  local config_profile=""

  if [[ -n "$explicit_profile" ]]; then
    ensure_valid_profile "$explicit_profile"
    printf '%s\n' "$explicit_profile"
    return 0
  fi

  running_profile="$(detect_unique_running_profile || true)"
  if [[ "$running_profile" == "__AMBIGUOUS__" ]]; then
    echo "错误: 当前同时检测到 create 和 join 都在运行，请显式指定要操作的类型。" >&2
    exit 1
  fi

  case "$command" in
    stop|restart|status|diagnose|logs)
      if [[ -n "$running_profile" ]]; then
        printf '%s\n' "$running_profile"
        return 0
      fi
      ;;
  esac

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


load_defaults() {
  HOSTNAME="$(os_default_hostname)"
  INSTANCE_NAME="${PROFILE}-${PLATFORM_ID:-generic}"

  if [[ "$PROFILE" == "create" ]]; then
    USE_DHCP="false"
  else
    USE_DHCP="true"
  fi

  STATE_DIR="${ROOT_DIR}/.state/${PROFILE}"
  LOG_DIR="${ROOT_DIR}/logs/${PROFILE}"
  PID_FILE="${STATE_DIR}/easytier.pid"
}

load_env_file() {
  local env_file="$1"
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

load_binary_config() {
  if [[ "$BINARY_CONFIG_LOADED" == "true" ]]; then
    return 0
  fi

  if [[ -f "$EXECUTABLES_ENV_FILE" ]]; then
    ACTIVE_EXECUTABLES_ENV_FILE="$EXECUTABLES_ENV_FILE"
    load_env_file "$EXECUTABLES_ENV_FILE"
  fi

  CORE_BIN="${BIN_DIR}/${EASYTIER_CORE_FILENAME}"
  CLI_BIN="${BIN_DIR}/${EASYTIER_CLI_FILENAME}"
  WEB_BIN="${BIN_DIR}/${EASYTIER_WEB_FILENAME}"
  WEB_EMBED_BIN="${BIN_DIR}/${EASYTIER_WEB_EMBED_FILENAME}"
  BINARY_CONFIG_LOADED="true"
}

load_profile_config() {
  if [[ "$CONFIG_LOADED" == "true" ]]; then
    return 0
  fi

  load_binary_config
  load_defaults

  if [[ ! -f "$CONFIG_ENV_FILE" ]]; then
    echo "错误: 未找到配置文件 ${CONFIG_ENV_FILE}" >&2
    echo "请先执行: ./easytierctl init ${PROFILE}" >&2
    exit 1
  fi

  load_env_file "$CONFIG_ENV_FILE"
  CONFIG_LOADED="true"
}

ensure_binary() {
  local bin="$1"
  if os_is_windows; then
    if [[ ! -f "$bin" ]]; then
      echo "错误: 缺少可执行文件 $bin" >&2
      exit 1
    fi
    return 0
  fi

  if [[ ! -x "$bin" ]]; then
    echo "错误: 缺少可执行文件 $bin" >&2
    exit 1
  fi
}

ensure_dirs() {
  mkdir -p "$BIN_DIR" "$STATE_DIR" "$LOG_DIR"
  chmod 755 "$BIN_DIR" "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true
}

generate_machine_id() {
  local machine_id=""
  machine_id="$(os_detect_machine_id || true)"

  if [[ -z "$machine_id" ]] && command -v uuidgen >/dev/null 2>&1; then
    machine_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  fi

  if [[ -z "$machine_id" ]]; then
    machine_id="$(date +%s)-$$-$RANDOM"
  fi

  printf '%s\n' "$machine_id"
}

get_machine_id() {
  local machine_id_file="${STATE_DIR}/machine-id"

  if [[ -n "${MACHINE_ID:-}" ]]; then
    printf '%s\n' "$MACHINE_ID"
    return 0
  fi

  local system_machine_id
  system_machine_id="$(os_detect_machine_id || true)"
  if [[ -n "$system_machine_id" ]]; then
    printf '%s\n' "$system_machine_id"
    return 0
  fi

  ensure_dirs

  if [[ -s "$machine_id_file" ]]; then
    tr -d '[:space:]' <"$machine_id_file"
    printf '\n'
    return 0
  fi

  system_machine_id="$(generate_machine_id)"
  printf '%s\n' "$system_machine_id" >"$machine_id_file"
  chmod 644 "$machine_id_file" 2>/dev/null || true
  printf '%s\n' "$system_machine_id"
}

append_csv_args() {
  local flag="$1"
  local csv="$2"
  local item
  while IFS= read -r item; do
    BUILT_ARGS+=("$flag" "$item")
  done < <(split_csv "$csv")
}

append_extra_args() {
  local item key value
  while IFS= read -r item; do
    if [[ "$item" == *=* ]]; then
      key="${item%%=*}"
      value="${item#*=}"
      BUILT_ARGS+=("$(trim_text "$key")" "$(trim_text "$value")")
    else
      BUILT_ARGS+=("$item")
    fi
  done < <(split_csv "$EXTRA_ARGS")
}

validate_config() {
  [[ -n "$NETWORK_NAME" ]] || { echo "错误: NETWORK_NAME 不能为空" >&2; exit 1; }
  [[ -n "$NETWORK_SECRET" ]] || { echo "错误: NETWORK_SECRET 不能为空" >&2; exit 1; }
  [[ -n "$HOSTNAME" ]] || { echo "错误: HOSTNAME 不能为空" >&2; exit 1; }
  [[ -n "$INSTANCE_NAME" ]] || { echo "错误: INSTANCE_NAME 不能为空" >&2; exit 1; }

  if ! bool_is_true "$USE_DHCP" && ! bool_is_true "$NO_TUN" && [[ -z "${NODE_IPV4:-}" ]]; then
    echo "错误: 当 USE_DHCP=false 且 NO_TUN=false 时，必须设置 NODE_IPV4" >&2
    exit 1
  fi

  if [[ "$PROFILE" == "create" ]] && [[ -z "$LISTENER_URLS" ]]; then
    echo "错误: 创建组网时必须设置 LISTENER_URLS" >&2
    exit 1
  fi

  if [[ "$PROFILE" == "join" ]] && [[ -z "$PEER_URLS" ]]; then
    echo "错误: 加入组网时必须设置 PEER_URLS" >&2
    exit 1
  fi
}

needs_root() {
  if os_is_windows; then
    return 1
  fi
  ! bool_is_true "$NO_TUN"
}

require_root() {
  if needs_root && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if os_has_sudo; then
      echo "需要 root 权限创建 TUN 虚拟网卡，正在使用 sudo 重新运行..."
      exec sudo -E "$SELF_EXECUTABLE" "${ORIGINAL_ARGS[@]}"
    fi
    if os_is_termux; then
      print_error "Termux 当前未检测到 sudo，无法自动提权创建 TUN。"
      print_warn "如果你在 Termux 中运行，推荐将对应 .env 文件中的 NO_TUN=true。"
      print_warn "如果设备已 root，请切换到 root shell 后再执行。"
      exit 1
    fi
    print_error "当前环境未检测到 sudo，无法自动提权创建 TUN。"
    exit 1
  fi
}

find_pid() {
  pgrep -f "${CORE_BIN}.*${NETWORK_NAME}.*${INSTANCE_NAME}" 2>/dev/null | head -1
}

pid_owner() {
  local pid="$1"
  ps -o user= -p "$pid" 2>/dev/null | tr -d ' '
}

pid_is_root_owned() {
  local pid="$1"
  [[ "$(pid_owner "$pid")" == "root" ]]
}

remove_pid_file() {
  if [[ ! -e "$PID_FILE" ]]; then
    return 0
  fi

  if [[ "${EUID:-$(id -u)}" -eq 0 || -w "$PID_FILE" ]]; then
    rm -f "$PID_FILE"
  elif os_has_sudo; then
    sudo rm -f "$PID_FILE" 2>/dev/null || true
  else
    print_warn "PID 文件没有写权限，且当前环境未检测到 sudo，已跳过清理。"
  fi
}

is_running() {
  local pid
  pid="$(find_pid)"
  [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1
}

run_cli() {
  ensure_binary "$CLI_BIN"

  local pid
  pid="$(find_pid)"

  if [[ -n "$pid" ]] && pid_is_root_owned "$pid" && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if os_has_sudo; then
      sudo "$CLI_BIN" -n "$INSTANCE_NAME" "$@"
    else
      print_error "当前 EasyTier 进程属于 root，且当前环境未检测到 sudo，无法查询状态。"
      return 1
    fi
  else
    "$CLI_BIN" -n "$INSTANCE_NAME" "$@"
  fi
}

trim_log_file_if_needed() {
  local log_file="$1"
  local file_size=""
  local temp_file=""

  [[ -f "$log_file" ]] || return 0

  file_size="$(wc -c <"$log_file" 2>/dev/null | tr -d '[:space:]')"
  [[ -n "$file_size" ]] || return 0

  if [[ "$file_size" -le "$LOG_MAX_BYTES" ]]; then
    return 0
  fi

  temp_file="${log_file}.trim.$$"
  tail -c "$LOG_MAX_BYTES" "$log_file" >"$temp_file" 2>/dev/null || {
    rm -f "$temp_file" 2>/dev/null || true
    return 1
  }

  cat "$temp_file" >"$log_file" 2>/dev/null || true
  rm -f "$temp_file" 2>/dev/null || true
}

trim_log_dir_if_needed() {
  local log_file

  [[ -d "$LOG_DIR" ]] || return 0

  for log_file in "$LOG_DIR"/*; do
    [[ -f "$log_file" ]] || continue
    trim_log_file_if_needed "$log_file" || true
  done
}

start_log_maintenance() {
  local core_pid="$1"

  (
    while kill -0 "$core_pid" 2>/dev/null; do
      trim_log_dir_if_needed
      sleep 5
    done
    trim_log_dir_if_needed
  ) >/dev/null 2>&1 &
  disown "$!" 2>/dev/null || true
}

check_single_target() {
  local url="$1"
  local scheme="${url%%://*}"
  local remainder="${url#*://}"
  local host_port="${remainder%%/*}"
  local host="${host_port%:*}"
  local port="${host_port##*:}"

  if [[ "$host" == "$port" || -z "$host" || -z "$port" ]]; then
    printf '%s[跳过]%s 地址格式无法探测\n' "$STYLE_YELLOW" "$STYLE_RESET"
    return 0
  fi

  if [[ "$scheme" != "tcp" ]]; then
    printf '%s[仅展示]%s UDP 入口不做探测\n' "$STYLE_DIM" "$STYLE_RESET"
    return 0
  fi

  if os_tcp_probe "$host" "$port"; then
    printf '%s[可达]%s\n' "$STYLE_GREEN" "$STYLE_RESET"
  else
    local code=$?
    if [[ "$code" -eq 2 ]]; then
      printf '%s[跳过]%s 未安装 nc，无法探测\n' "$STYLE_YELLOW" "$STYLE_RESET"
    else
      printf '%s[不可达]%s\n' "$STYLE_RED" "$STYLE_RESET"
    fi
  fi
}

check_peer_targets() {
  local item
  if [[ -z "$PEER_URLS" ]]; then
    print_warn "未配置上游入口"
    return 0
  fi

  while IFS= read -r item; do
    printf '  - %-36s ' "$item"
    check_single_target "$item"
  done < <(split_csv "$PEER_URLS")
}

check_tun_ip() {
  if bool_is_true "$NO_TUN"; then
    return 0
  fi

  if [[ -z "${NODE_IPV4:-}" ]]; then
    return 1
  fi

  if command -v ifconfig >/dev/null 2>&1 && ifconfig 2>/dev/null | grep -qF "inet $NODE_IPV4"; then
    return 0
  fi

  if command -v ip >/dev/null 2>&1 && ip addr show 2>/dev/null | grep -qF "inet ${NODE_IPV4}/"; then
    return 0
  fi

  if os_is_windows && command -v ipconfig >/dev/null 2>&1 && ipconfig 2>/dev/null | grep -qF "$NODE_IPV4"; then
    return 0
  fi

  return 1
}

build_args() {
  BUILT_ARGS=(
    --network-name "$NETWORK_NAME"
    --network-secret "$NETWORK_SECRET"
    --machine-id "$(get_machine_id)"
    --hostname "$HOSTNAME"
    -m "$INSTANCE_NAME"
    --private-mode "$PRIVATE_MODE"
    --console-log-level "$CONSOLE_LOG_LEVEL"
    --file-log-level "$FILE_LOG_LEVEL"
    --file-log-dir "$LOG_DIR"
  )

  if [[ -n "$RPC_PORTAL" ]]; then
    BUILT_ARGS+=(-r "$RPC_PORTAL")
  fi

  if bool_is_true "$NO_TUN"; then
    BUILT_ARGS+=(--no-tun true)
  elif bool_is_true "$USE_DHCP"; then
    BUILT_ARGS+=(-d true)
  else
    BUILT_ARGS+=(-i "$NODE_IPV4")
  fi

  if [[ "$PROFILE" == "create" ]]; then
    append_csv_args -l "$LISTENER_URLS"
    append_csv_args -p "$PEER_URLS"
  else
    BUILT_ARGS+=(--no-listener)
    append_csv_args -p "$PEER_URLS"
  fi

  append_csv_args --mapped-listeners "$MAPPED_LISTENERS"

  if [[ -n "$PROXY_NETWORKS" ]]; then
    BUILT_ARGS+=(-n "$(csv_to_space_joined "$PROXY_NETWORKS")")
  fi

  append_csv_args --tcp-whitelist "$TCP_WHITELIST"
  append_csv_args --udp-whitelist "$UDP_WHITELIST"
  append_extra_args
}

verify_platform_binaries() {
  load_binary_config
  print_kv "二进制目录" "${BIN_DIR}"

  local missing="false"
  local file
  for file in "$CORE_BIN" "$CLI_BIN" "$WEB_BIN" "$WEB_EMBED_BIN"; do
    if { os_is_windows && [[ -f "$file" ]]; } || [[ -x "$file" ]]; then
      printf '  %s[OK]%s %s\n' "$STYLE_GREEN" "$STYLE_RESET" "$(basename "$file")"
    else
      printf '  %s[缺失]%s %s -> %s\n' "$STYLE_RED" "$STYLE_RESET" "$(basename "$file")" "$file"
      missing="true"
    fi
  done

  if [[ "$missing" == "true" ]]; then
    return 1
  fi
}

print_summary() {
  print_heading "执行摘要"
  print_kv "操作" "${ROLE_LABEL}"
  print_kv "平台" "${PLATFORM_NAME} (${PLATFORM_ID:-unknown})"
  print_kv "仓库目录" "${ROOT_DIR}"
  print_kv "二进制目录" "${BIN_DIR}"
  print_kv "可执行映射" "${ACTIVE_EXECUTABLES_ENV_FILE}"
  print_kv "配置文件" "${CONFIG_ENV_FILE}"
  print_kv "网络名称" "${NETWORK_NAME}"
  print_kv "节点名称" "${HOSTNAME}"
  print_kv "实例名称" "${INSTANCE_NAME}"
  print_kv "machine-id" "$(get_machine_id)"
  print_kv "状态目录" "${STATE_DIR}"
  print_kv "日志目录" "${LOG_DIR}"

  if bool_is_true "$NO_TUN"; then
    print_kv "TUN 模式" "已关闭"
  elif bool_is_true "$USE_DHCP"; then
    print_kv "虚拟 IP" "DHCP 自动分配"
  else
    print_kv "虚拟 IP" "${NODE_IPV4}"
  fi
}

cmd_platform_list() {
  print_heading "平台列表"
  print_info "脚本内置支持的平台如下:"
  platform_list_known
}

cmd_platform_current() {
  local detected_id
  detected_id="$(platform_detect_default_id || true)"
  print_heading "当前平台"
  print_kv "ID" "${PLATFORM_ID:-unknown}"
  print_kv "名称" "${PLATFORM_NAME}"
  if [[ -n "$detected_id" ]]; then
    print_kv "支持状态" "已内置识别"
  else
    print_kv "支持状态" "未内置识别"
  fi
}

cmd_platform_verify() {
  print_heading "二进制检查"
  if verify_platform_binaries; then
    print_success "二进制检查通过"
  else
    print_error "二进制不完整，请把 4 个 EasyTier 文件复制到 ${BIN_DIR}/"
    exit 1
  fi
}

cmd_init_config() {
  local target_file template_file
  case "$PROFILE" in
    executables)
      target_file="$EXECUTABLES_ENV_FILE"
      template_file="$EXECUTABLES_ENV_EXAMPLE_FILE"
      ;;
    create|join)
      target_file="$CONFIG_ENV_FILE"
      template_file="$CONFIG_ENV_EXAMPLE_FILE"
      ;;
    *)
      echo "错误: init 不支持的类型 ${PROFILE}" >&2
      exit 1
      ;;
  esac
  if [[ -f "$target_file" ]] && ! bool_is_true "$FORCE_OVERWRITE"; then
    echo "错误: 配置文件已存在 ${target_file}" >&2
    echo "如果需要覆盖，请追加 --force。" >&2
    exit 1
  fi

  cp "$template_file" "$target_file"
  print_success "已生成配置文件"
  print_kv "输出文件" "${target_file}"
}

cmd_start() {
  verify_platform_binaries >/dev/null
  ensure_binary "$CORE_BIN"

  if is_running; then
    print_warn "easytier 已在运行 (PID: $(find_pid))"
    cmd_status || true
    return 0
  fi

  require_root "$@"
  ensure_dirs
  print_summary

  if [[ "$PROFILE" == "join" ]]; then
    print_subheading "入口连通性检查"
    check_peer_targets
  fi

  build_args
  cd "$STATE_DIR"
  trim_log_dir_if_needed

  nohup "$CORE_BIN" "${BUILT_ARGS[@]}" >>"${LOG_DIR}/runtime.log" 2>&1 &
  local pid=$!
  disown "$pid" 2>/dev/null || true
  start_log_maintenance "$pid"

  echo
  print_info "等待 easytier 启动 ..."
  for _ in {1..15}; do
    sleep 1
    if is_running; then
      break
    fi
  done

  if ! is_running; then
    print_error "启动失败，最近日志如下:"
    tail -30 "${LOG_DIR}/runtime.log" 2>/dev/null || true
    remove_pid_file
    exit 1
  fi

  echo "$(find_pid)" >"$PID_FILE"
  print_success "easytier 已启动 (PID: $(find_pid))"
  print_kv "运行日志" "${LOG_DIR}/runtime.log"

  if ! bool_is_true "$NO_TUN"; then
    print_info "等待虚拟网卡就绪 ..."
    for i in {1..20}; do
      if check_tun_ip; then
        print_success "虚拟网卡已就绪"
        break
      fi
      if [[ "$i" -eq 20 ]]; then
        print_warn "未在预期时间内检测到虚拟 IP，可执行 diagnose 查看详情。"
      fi
      sleep 1
    done
  fi

  cmd_status || true
}

cmd_stop() {
  local pid
  pid="$(find_pid)"

  if [[ -z "$pid" ]]; then
    print_warn "easytier 未在运行"
    remove_pid_file
    return 0
  fi

  print_info "正在停止 easytier (PID: $pid) ..."

  if pid_is_root_owned "$pid" && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if os_has_sudo; then
      sudo kill "$pid" 2>/dev/null || true
    else
      print_error "当前 EasyTier 进程属于 root，且当前环境未检测到 sudo，无法停止。"
      return 1
    fi
  else
    kill "$pid" 2>/dev/null || true
  fi

  for _ in {1..10}; do
    if pid_is_root_owned "$pid" && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      if os_has_sudo; then
        sudo kill -0 "$pid" 2>/dev/null || break
      else
        break
      fi
    else
      kill -0 "$pid" 2>/dev/null || break
    fi
    sleep 0.5
  done

  if pid_is_root_owned "$pid" && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if os_has_sudo && sudo kill -0 "$pid" 2>/dev/null; then
      sudo kill -9 "$pid" 2>/dev/null || true
    fi
  elif kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi

  remove_pid_file
  print_success "已停止"
}

cmd_status() {
  if ! is_running; then
    print_warn "easytier 未在运行"
    return 1
  fi

  print_heading "运行状态"
  print_kv "类型" "${PROFILE}"
  print_kv "PID" "$(find_pid)"
  print_kv "实例" "${INSTANCE_NAME}"
  print_kv "日志" "${LOG_DIR}/runtime.log"
  print_divider

  print_subheading "节点信息"
  show_cli_node_info

  print_subheading "已连接节点"
  show_cli_peer_info

  print_subheading "路由"
  show_cli_route_info
}

cmd_logs() {
  local log_file="${LOG_DIR}/runtime.log"
  if [[ -f "$log_file" ]]; then
    print_heading "运行日志"
    print_kv "日志文件" "$log_file"
    tail -f "$log_file"
  else
    print_warn "暂无日志: $log_file"
  fi
}

cmd_diagnose() {
  print_heading "EasyTier 诊断"

  print_subheading "平台"
  print_kv "名称" "${PLATFORM_NAME} (${PLATFORM_ID:-unknown})"

  print_subheading "二进制检查"
  if verify_platform_binaries; then
    print_success "二进制检查通过"
  else
    print_warn "二进制不完整，请检查 bin/ 目录中的 4 个 EasyTier 文件。"
  fi

  print_subheading "配置文件"
  print_kv "可执行映射" "${ACTIVE_EXECUTABLES_ENV_FILE}"
  print_kv "运行配置" "${CONFIG_ENV_FILE}"

  print_subheading "进程"
  if is_running; then
    print_kv "状态" "运行中"
    print_kv "PID" "$(find_pid)"
  else
    print_kv "状态" "未运行"
  fi

  print_subheading "本地身份"
  print_kv "machine-id" "$(get_machine_id)"
  print_kv "状态目录" "${STATE_DIR}"

  if [[ "$PROFILE" == "join" ]]; then
    print_subheading "上游入口检查"
    check_peer_targets
  fi

  print_subheading "最近日志"
  tail -20 "${LOG_DIR}/runtime.log" 2>/dev/null || echo "  无日志"

  if is_running; then
    print_divider
    print_subheading "节点状态"
    print_info "节点信息"
    show_cli_node_info
    print_info "已连接节点"
    show_cli_peer_info
    print_info "路由"
    show_cli_route_info
  fi
}

cmd_foreground() {
  verify_platform_binaries >/dev/null
  ensure_binary "$CORE_BIN"
  require_root "$@"
  ensure_dirs
  print_summary
  print_info "前台模式已启动，按 Ctrl+C 退出。"
  build_args
  cd "$STATE_DIR"
  trim_log_dir_if_needed
  start_log_maintenance "$$"
  exec "$CORE_BIN" "${BUILT_ARGS[@]}"
}

cmd_check() {
  verify_platform_binaries >/dev/null
  ensure_binary "$CORE_BIN"
  ensure_dirs
  build_args
  print_heading "配置检查"
  print_info "正在检查配置 ..."
  "$CORE_BIN" "${BUILT_ARGS[@]}" --check-config
  print_success "配置检查通过"
}

show_usage() {
  cat <<EOF
用法:
  ./easytierctl help

平台与二进制:
  ./easytierctl platform list                查看脚本内置支持的平台标识
  ./easytierctl platform current             查看当前系统识别结果
  ./easytierctl platform verify              检查 bin/ 中所需可执行文件是否齐全

初始化配置:
  ./easytierctl init executables             生成可执行文件名映射配置
  ./easytierctl init create                  生成创建组网配置
  ./easytierctl init join                    生成加入组网配置

开机自启:
  ./easytierctl autostart install [类型]     安装开机自启
  ./easytierctl autostart uninstall [类型]   卸载开机自启
  ./easytierctl autostart status [类型]      查看开机自启状态

组网运行:
  ./easytierctl check [类型]                 检查组网配置，不实际启动
  ./easytierctl start [类型]                 启动组网节点
  ./easytierctl stop [类型]                  停止组网节点
  ./easytierctl restart [类型]               重启组网节点
  ./easytierctl status [类型]                查看组网节点状态
  ./easytierctl diagnose [类型]              输出组网节点诊断信息
  ./easytierctl logs [类型]                  查看组网节点日志
  ./easytierctl fg [类型]                    前台运行组网节点

参数:
  --force                                   覆盖已存在的配置文件（仅 init 使用）

类型说明:
  类型支持 create 或 join。
  大多数命令都可以省略类型，脚本会优先按当前运行实例或现有配置自动判断。

示例:
  ./easytierctl init executables
  ./easytierctl init create
  ./easytierctl autostart install join
  ./easytierctl start create
  ./easytierctl status
EOF
}

easytierctl_main() {
  init_output_style
  ORIGINAL_ARGS=("$@")
  SELF_EXECUTABLE="${ROOT_DIR}/easytierctl"
  COMMAND="${1:-help}"
  shift || true

  parse_common_options "$@"
  prepare_runtime_context

  case "$COMMAND" in
    help|-h|--help)
      show_usage
      ;;
    platform)
      local subcmd="${POSITIONAL_ARGS[0]:-list}"
      case "$subcmd" in
        list) cmd_platform_list ;;
        current) cmd_platform_current ;;
        verify) cmd_platform_verify ;;
        *)
          echo "错误: 未知 platform 子命令 ${subcmd}" >&2
          show_usage
          exit 1
          ;;
      esac
      ;;
    init)
      PROFILE="${POSITIONAL_ARGS[0]:-}"
      if [[ -z "$PROFILE" ]]; then
        echo "错误: init 需要指定 executables、create 或 join。" >&2
        exit 1
      fi
      if [[ "$PROFILE" == "create" || "$PROFILE" == "join" ]]; then
        set_profile_context "$PROFILE"
      fi
      cmd_init_config
      ;;
    autostart)
      AUTOSTART_ACTION="${POSITIONAL_ARGS[0]:-}"
      if [[ -z "$AUTOSTART_ACTION" ]]; then
        echo "错误: autostart 需要指定 install、uninstall 或 status。" >&2
        exit 1
      fi
      case "$AUTOSTART_ACTION" in
        install|uninstall|status) ;;
        *)
          echo "错误: 不支持的 autostart 动作 ${AUTOSTART_ACTION}。" >&2
          exit 1
          ;;
      esac
      PROFILE="$(resolve_profile_for_autostart "$AUTOSTART_ACTION" "${POSITIONAL_ARGS[1]:-}")"
      set_profile_context "$PROFILE"
      case "$AUTOSTART_ACTION" in
        install) cmd_autostart_install ;;
        uninstall) cmd_autostart_uninstall ;;
        status) cmd_autostart_status ;;
      esac
      ;;
    start|stop|restart|status|diagnose|logs|check|fg)
      PROFILE="$(resolve_profile_for_command "$COMMAND" "${POSITIONAL_ARGS[0]:-}")"
      set_profile_context "$PROFILE"
      load_profile_config
      validate_config
      case "$COMMAND" in
        start) cmd_start ;;
        stop) cmd_stop ;;
        restart) cmd_stop; cmd_start ;;
        status) cmd_status ;;
        diagnose) cmd_diagnose ;;
        logs) cmd_logs ;;
        check) cmd_check ;;
        fg) cmd_foreground ;;
      esac
      ;;
    *)
      echo "错误: 未知命令 ${COMMAND}" >&2
      show_usage
      exit 1
      ;;
  esac
}
