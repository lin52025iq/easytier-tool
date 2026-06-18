#!/usr/bin/env bash

EASYTIER_GITHUB_REPO="EasyTier/EasyTier"
EASYTIER_RELEASES_API_BASE="https://api.github.com/repos/${EASYTIER_GITHUB_REPO}/releases"
DOWNLOAD_REQUESTED_VERSION=""
DOWNLOAD_RELEASE_TAG=""
DOWNLOAD_ASSET_NAME=""
DOWNLOAD_ASSET_URL=""
DOWNLOAD_ASSET_KEYWORD=""
DOWNLOAD_WORK_DIR=""
DOWNLOAD_ACTION_LABEL="下载"

github_auth_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf '%s\n' "${GITHUB_TOKEN}"
    return 0
  fi

  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s\n' "${GH_TOKEN}"
    return 0
  fi

  if command -v gh >/dev/null 2>&1; then
    gh auth token 2>/dev/null | awk 'NF { print; exit }'
    return 0
  fi

  return 1
}

print_github_rate_limit_help() {
  print_warn "当前请求命中了 GitHub API 匿名访问限流。"
  print_info "建议优先使用下面任一方式后重试:"
  printf '  1. export GITHUB_TOKEN=你的_token\n'
  printf '  2. export GH_TOKEN=你的_token\n'
  printf '  3. 先执行 gh auth login，然后再执行 easytierctl download/upgrade\n'
}

download_normalize_version() {
  local raw="${1:-latest}"
  if [[ -z "$raw" || "$raw" == "latest" ]]; then
    printf 'latest\n'
  elif [[ "$raw" == v* ]]; then
    printf '%s\n' "$raw"
  else
    printf 'v%s\n' "$raw"
  fi
}

download_release_api_url() {
  local version="$1"
  if [[ "$version" == "latest" ]]; then
    printf '%s/latest\n' "$EASYTIER_RELEASES_API_BASE"
  else
    printf '%s/tags/%s\n' "$EASYTIER_RELEASES_API_BASE" "$version"
  fi
}

download_require_http_client() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  print_error "当前环境缺少 curl 或 wget，无法下载 EasyTier 发布包。"
  exit 1
}

download_http_get() {
  local url="$1"
  local output_file="$2"
  local mode="${3:-quiet}"
  local auth_token=""

  auth_token="$(github_auth_token 2>/dev/null || true)"

  if command -v curl >/dev/null 2>&1; then
    if [[ "$mode" == "progress" ]]; then
      if [[ -n "$auth_token" ]]; then
        curl -fL --progress-bar \
          -H "Accept: application/vnd.github+json" \
          -H "Authorization: Bearer ${auth_token}" \
          "$url" -o "$output_file"
      else
        curl -fL --progress-bar \
          -H "Accept: application/vnd.github+json" \
          "$url" -o "$output_file"
      fi
    else
      if [[ -n "$auth_token" ]]; then
        curl -fsSL \
          -H "Accept: application/vnd.github+json" \
          -H "Authorization: Bearer ${auth_token}" \
          "$url" -o "$output_file"
      else
        curl -fsSL -H "Accept: application/vnd.github+json" "$url" -o "$output_file"
      fi
    fi
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    if [[ "$mode" == "progress" ]]; then
      if [[ -n "$auth_token" ]]; then
        wget --show-progress --progress=bar:force:noscroll \
          --header="Accept: application/vnd.github+json" \
          --header="Authorization: Bearer ${auth_token}" \
          -O "$output_file" "$url"
      else
        wget --show-progress --progress=bar:force:noscroll \
          --header="Accept: application/vnd.github+json" \
          -O "$output_file" "$url"
      fi
    else
      if [[ -n "$auth_token" ]]; then
        wget -q \
          --header="Accept: application/vnd.github+json" \
          --header="Authorization: Bearer ${auth_token}" \
          -O "$output_file" "$url"
      else
        wget -q --header="Accept: application/vnd.github+json" -O "$output_file" "$url"
      fi
    fi
    return 0
  fi

  return 1
}

download_parse_release_json() {
  local json_file="$1"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

print("TAG\t" + data.get("tag_name", ""))
for asset in data.get("assets", []):
    print("ASSET\t%s\t%s" % (asset.get("name", ""), asset.get("browser_download_url", "")))
PY
    return 0
  fi

  if command -v python >/dev/null 2>&1; then
    python - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r") as f:
    data = json.load(f)

print("TAG\t" + data.get("tag_name", ""))
for asset in data.get("assets", []):
    print("ASSET\t%s\t%s" % (asset.get("name", ""), asset.get("browser_download_url", "")))
PY
    return 0
  fi

  awk '
    /"tag_name"[[:space:]]*:/ && !tag_printed {
      line = $0
      sub(/^.*"tag_name"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      print "TAG\t" line
      tag_printed = 1
    }

    /"name"[[:space:]]*:/ {
      line = $0
      sub(/^.*"name"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      current_name = line
    }

    /"browser_download_url"[[:space:]]*:/ {
      line = $0
      sub(/^.*"browser_download_url"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      if (current_name != "") {
        print "ASSET\t" current_name "\t" line
        current_name = ""
      }
    }
  ' "$json_file"
}

download_prepare_workspace() {
  DOWNLOAD_WORK_DIR="${ROOT_DIR}/.downloads"
  mkdir -p "$DOWNLOAD_WORK_DIR" "$BIN_DIR"
}

download_resolve_release_metadata() {
  local version="$1"
  local api_url=""
  local json_file=""
  local parsed_file=""
  local best_score="-1"
  local score=""
  local line_type=""
  local asset_name=""
  local asset_url=""
  local keyword=""
  local keyword_rank=0
  local matched_keyword=""
  local keywords_file=""

  keywords_file="$(mktemp "${TMPDIR:-/tmp}/easytier-keywords.XXXXXX.txt")"
  if ! platform_download_asset_keywords "$PLATFORM_ID" >"$keywords_file" 2>/dev/null || [[ ! -s "$keywords_file" ]]; then
    rm -f "$keywords_file" 2>/dev/null || true
    print_error "无法为当前平台生成 EasyTier 发布包匹配关键字。"
    print_kv "平台" "${PLATFORM_NAME} (${PLATFORM_ID:-unknown})"
    print_warn "脚本已经尝试通过 uname / Termux 环境变量推断平台，但仍无法得到可下载资源匹配规则。"
    exit 1
  fi
  DOWNLOAD_ASSET_KEYWORD="$(awk 'NF { print; exit }' "$keywords_file")"

  api_url="$(download_release_api_url "$version")"
  json_file="$(mktemp "${TMPDIR:-/tmp}/easytier-release.XXXXXX.json")"
  parsed_file="$(mktemp "${TMPDIR:-/tmp}/easytier-release.XXXXXX.tsv")"

  if ! download_http_get "$api_url" "$json_file" "quiet"; then
    rm -f "$json_file" "$parsed_file" "$keywords_file" 2>/dev/null || true
    print_error "无法获取 EasyTier 发布信息: $api_url"
    print_github_rate_limit_help
    exit 1
  fi

  if ! download_parse_release_json "$json_file" >"$parsed_file"; then
    rm -f "$json_file" "$parsed_file" "$keywords_file" 2>/dev/null || true
    print_error "无法解析 EasyTier 发布信息。"
    exit 1
  fi

  while IFS=$'\t' read -r line_type asset_name asset_url; do
    case "$line_type" in
      TAG)
        DOWNLOAD_RELEASE_TAG="$asset_name"
        ;;
      ASSET)
        case "$asset_name" in
          *.zip|*.tar.gz|*.tgz) ;;
          *) continue ;;
        esac

        matched_keyword=""
        keyword_rank=0
        while IFS= read -r keyword; do
          [[ -n "$keyword" ]] || continue
          keyword_rank=$((keyword_rank + 1))
          if [[ "$asset_name" == *"$keyword"* ]]; then
            matched_keyword="$keyword"
            break
          fi
        done <"$keywords_file"

        [[ -n "$matched_keyword" ]] || continue

        score=$((200 - keyword_rank))
        [[ "$asset_name" == *"$DOWNLOAD_RELEASE_TAG"* ]] && score=$((score + 20))
        if os_is_windows; then
          [[ "$asset_name" == *.zip ]] && score=$((score + 10))
        else
          [[ "$asset_name" == *.zip ]] && score=$((score + 5))
          [[ "$asset_name" == *.tar.gz || "$asset_name" == *.tgz ]] && score=$((score + 8))
        fi

        if (( score > best_score )); then
          best_score="$score"
          DOWNLOAD_ASSET_NAME="$asset_name"
          DOWNLOAD_ASSET_URL="$asset_url"
          DOWNLOAD_ASSET_KEYWORD="$matched_keyword"
        fi
        ;;
    esac
  done <"$parsed_file"

  rm -f "$json_file" "$parsed_file" "$keywords_file" 2>/dev/null || true

  if [[ -z "$DOWNLOAD_RELEASE_TAG" ]]; then
    print_error "未能从 GitHub release 中解析出版本号。"
    exit 1
  fi

  if [[ -z "$DOWNLOAD_ASSET_NAME" || -z "$DOWNLOAD_ASSET_URL" ]]; then
    print_error "未找到适用于当前平台的 EasyTier 发布包。"
    print_kv "平台" "${PLATFORM_NAME} (${PLATFORM_ID:-unknown})"
    print_kv "首选关键字" "${DOWNLOAD_ASSET_KEYWORD}"
    print_kv "版本" "${DOWNLOAD_RELEASE_TAG}"
    print_warn "可以执行 ./easytierctl platform current 查看平台识别结果，或手动下载后放入 bin/。"
    exit 1
  fi
}

download_require_archive_tools() {
  local archive_name="$1"

  case "$archive_name" in
    *.zip)
      if ! command -v unzip >/dev/null 2>&1; then
        print_error "当前环境缺少 unzip，无法解压 ${archive_name}。"
        exit 1
      fi
      ;;
    *.tar.gz|*.tgz)
      if ! command -v tar >/dev/null 2>&1; then
        print_error "当前环境缺少 tar，无法解压 ${archive_name}。"
        exit 1
      fi
      ;;
    *)
      print_error "不支持的发布包格式: ${archive_name}"
      exit 1
      ;;
  esac
}

download_extract_archive() {
  local archive_file="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"

  case "$archive_file" in
    *.zip)
      unzip -oq "$archive_file" -d "$target_dir"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$archive_file" -C "$target_dir"
      ;;
    *)
      print_error "不支持的发布包格式: ${archive_file}"
      exit 1
      ;;
  esac
}

download_find_binary() {
  local extract_dir="$1"
  local base_name="$2"

  find "$extract_dir" -type f \( -name "$base_name" -o -name "${base_name}.exe" \) | head -1
}

write_executables_config_file() {
  local core_name="$1"
  local cli_name="$2"
  local web_name="$3"
  local web_embed_name="$4"

  cat >"$EXECUTABLES_ENV_FILE" <<EOF
# EasyTier 可执行文件名映射
#
# 该文件由 easytierctl download / upgrade 自动生成或更新。
# 二进制目录固定为项目根目录下的 bin/，这里只维护具体文件名。

EASYTIER_CORE_FILENAME=${core_name}
EASYTIER_CLI_FILENAME=${cli_name}
EASYTIER_WEB_FILENAME=${web_name}
EASYTIER_WEB_EMBED_FILENAME=${web_embed_name}
EOF
}

download_install_binary() {
  local source_file="$1"
  local target_name="$2"
  local temp_target="${BIN_DIR}/.${target_name}.tmp.$$"
  local final_target="${BIN_DIR}/${target_name}"

  cp "$source_file" "$temp_target"
  chmod 755 "$temp_target" 2>/dev/null || true
  mv -f "$temp_target" "$final_target"
}

download_any_profile_running() {
  profile_pid_running create || profile_pid_running join
}

download_warn_running_processes() {
  if ! download_any_profile_running; then
    return 0
  fi

  if os_is_windows; then
    print_error "检测到 EasyTier 正在运行，Windows 下升级前请先执行 stop。"
    exit 1
  fi

  print_warn "检测到 EasyTier 正在运行。"
  print_warn "新的二进制会写入 bin/，但已运行进程仍会继续使用旧版本，重启后才会生效。"
}

install_easytier_release() {
  local requested_version="$1"
  local archive_file=""
  local extract_dir=""
  local core_src=""
  local cli_src=""
  local web_src=""
  local web_embed_src=""
  local core_name=""
  local cli_name=""
  local web_name=""
  local web_embed_name=""

  download_require_http_client
  download_prepare_workspace
  download_warn_running_processes
  download_resolve_release_metadata "$requested_version"
  download_require_archive_tools "$DOWNLOAD_ASSET_NAME"

  archive_file="${DOWNLOAD_WORK_DIR}/${DOWNLOAD_ASSET_NAME}"
  extract_dir="${DOWNLOAD_WORK_DIR}/extract-${DOWNLOAD_RELEASE_TAG}-$$"
  rm -rf "$extract_dir" 2>/dev/null || true

  print_heading "EasyTier ${DOWNLOAD_ACTION_LABEL}"
  print_kv "仓库" "${EASYTIER_GITHUB_REPO}"
  print_kv "平台" "${PLATFORM_NAME} (${PLATFORM_ID:-unknown})"
  print_kv "版本" "${DOWNLOAD_RELEASE_TAG}"
  print_kv "资源包" "${DOWNLOAD_ASSET_NAME}"
  print_kv "匹配关键字" "${DOWNLOAD_ASSET_KEYWORD}"

  print_info "正在${DOWNLOAD_ACTION_LABEL} EasyTier 发布包 ..."
  if ! download_http_get "$DOWNLOAD_ASSET_URL" "$archive_file" "progress"; then
    rm -rf "$extract_dir" 2>/dev/null || true
    print_error "下载失败: ${DOWNLOAD_ASSET_URL}"
    exit 1
  fi

  print_info "正在解压发布包 ..."
  download_extract_archive "$archive_file" "$extract_dir"

  core_src="$(download_find_binary "$extract_dir" "easytier-core")"
  cli_src="$(download_find_binary "$extract_dir" "easytier-cli")"
  web_src="$(download_find_binary "$extract_dir" "easytier-web")"
  web_embed_src="$(download_find_binary "$extract_dir" "easytier-web-embed")"

  if [[ -z "$core_src" || -z "$cli_src" || -z "$web_src" || -z "$web_embed_src" ]]; then
    rm -rf "$extract_dir" 2>/dev/null || true
    print_error "发布包中缺少预期的 EasyTier 可执行文件。"
    exit 1
  fi

  core_name="$(basename "$core_src")"
  cli_name="$(basename "$cli_src")"
  web_name="$(basename "$web_src")"
  web_embed_name="$(basename "$web_embed_src")"

  download_install_binary "$core_src" "$core_name"
  download_install_binary "$cli_src" "$cli_name"
  download_install_binary "$web_src" "$web_name"
  download_install_binary "$web_embed_src" "$web_embed_name"
  write_executables_config_file "$core_name" "$cli_name" "$web_name" "$web_embed_name"

  rm -rf "$extract_dir" 2>/dev/null || true

  BINARY_CONFIG_LOADED="false"
  load_binary_config

  print_success "EasyTier 已安装到 bin/ 目录"
  print_kv "core" "${CORE_BIN}"
  print_kv "cli" "${CLI_BIN}"
  print_kv "web" "${WEB_BIN}"
  print_kv "web-embed" "${WEB_EMBED_BIN}"
  print_kv "可执行映射" "${EXECUTABLES_ENV_FILE}"
}

cmd_download_release() {
  DOWNLOAD_ACTION_LABEL="下载"
  DOWNLOAD_REQUESTED_VERSION="$(download_normalize_version "${POSITIONAL_ARGS[0]:-latest}")"
  install_easytier_release "$DOWNLOAD_REQUESTED_VERSION"
}

cmd_upgrade_release() {
  DOWNLOAD_ACTION_LABEL="升级"
  DOWNLOAD_REQUESTED_VERSION="$(download_normalize_version "${POSITIONAL_ARGS[0]:-latest}")"
  install_easytier_release "$DOWNLOAD_REQUESTED_VERSION"
}
