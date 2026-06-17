#!/usr/bin/env bash

STYLE_RESET=""
STYLE_BOLD=""
STYLE_DIM=""
STYLE_CYAN=""
STYLE_BLUE=""
STYLE_MAGENTA=""
STYLE_GREEN=""
STYLE_YELLOW=""
STYLE_RED=""

init_output_style() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    STYLE_RESET=$'\033[0m'
    STYLE_BOLD=$'\033[1m'
    STYLE_DIM=$'\033[2m'
    STYLE_CYAN=$'\033[36m'
    STYLE_BLUE=$'\033[34m'
    STYLE_MAGENTA=$'\033[35m'
    STYLE_GREEN=$'\033[32m'
    STYLE_YELLOW=$'\033[33m'
    STYLE_RED=$'\033[31m'
  fi
}

print_divider() {
  printf '%s%s%s\n' "$STYLE_DIM" '------------------------------------------------------------' "$STYLE_RESET"
}

print_heading() {
  printf '\n%s%s============================================================%s\n' "$STYLE_BOLD" "$STYLE_CYAN" "$STYLE_RESET"
  printf '%s%s  %s%s\n' "$STYLE_BOLD" "$STYLE_CYAN" "$1" "$STYLE_RESET"
  printf '%s%s============================================================%s\n' "$STYLE_BOLD" "$STYLE_CYAN" "$STYLE_RESET"
}

print_subheading() {
  printf '\n%s%s[ %s ]%s\n' "$STYLE_BOLD" "$STYLE_BLUE" "$1" "$STYLE_RESET"
}

print_kv() {
  printf '  %s%-14s%s %s\n' "$STYLE_MAGENTA" "$1" "$STYLE_RESET" "$2"
}

print_info() {
  printf '%s[信息]%s %s\n' "$STYLE_CYAN" "$STYLE_RESET" "$1"
}

print_success() {
  printf '%s[成功]%s %s\n' "$STYLE_GREEN" "$STYLE_RESET" "$1"
}

print_warn() {
  printf '%s[提示]%s %s\n' "$STYLE_YELLOW" "$STYLE_RESET" "$1"
}

print_error() {
  printf '%s[错误]%s %s\n' "$STYLE_RED" "$STYLE_RESET" "$1" >&2
}

render_tsv_table() {
  local tsv="$1"

  [[ -n "$tsv" ]] || return 1

  printf '%s\n' "$tsv" | awk -F'\t' \
    -v border_color="$STYLE_DIM" \
    -v header_color="${STYLE_BLUE}${STYLE_BOLD}" \
    -v cell_color="$STYLE_BOLD" \
    -v reset="$STYLE_RESET" '
    {
      row_count = NR
      if (NF > col_count) {
        col_count = NF
      }

      for (i = 1; i <= NF; i++) {
        cells[NR, i] = $i
        cell_len = length($i)
        if (cell_len > widths[i]) {
          widths[i] = cell_len
        }
      }
    }

    function print_border(    i, j) {
      printf("%s+", border_color)
      for (i = 1; i <= col_count; i++) {
        for (j = 0; j < widths[i] + 2; j++) {
          printf("-")
        }
        printf("+")
      }
      printf("%s\n", reset)
    }

    function print_row(row_index, color,    i, value, padding, j) {
      printf("|")
      for (i = 1; i <= col_count; i++) {
        value = cells[row_index, i]
        padding = widths[i] - length(value)
        printf(" %s%s%s", color, value, reset)
        for (j = 0; j < padding; j++) {
          printf(" ")
        }
        printf(" |")
      }
      printf("\n")
    }

    END {
      if (row_count < 2) {
        exit 1
      }

      print_border()
      print_row(1, header_color)
      print_border()
      for (row = 2; row <= row_count; row++) {
        print_row(row, cell_color)
      }
      print_border()
    }
  '
}

render_node_info() {
  local raw="$1"
  local tsv=""

  tsv="$(printf '%s\n' "$raw" | awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }

    BEGIN {
      print "field\tvalue"
    }

    /^\|/ {
      line = $0
      sub(/^[[:space:]]*\|[[:space:]]*/, "", line)
      sub(/[[:space:]]*\|[[:space:]]*$/, "", line)
      count = split(line, cells, /\|/)
      if (count < 2) {
        next
      }

      key = trim(cells[1])
      value = trim(cells[2])
      if (key == "" || value == "" || key ~ /^-+$/ || value ~ /^-+$/) {
        next
      }

      printf("%s\t%s\n", key, value)
      found = 1
    }

    END {
      if (!found) {
        exit 1
      }
    }
  ')" || return 1

  render_tsv_table "$tsv"
}

render_peer_info() {
  local raw="$1"
  local tsv=""

  tsv="$(printf '%s\n' "$raw" | awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }

    function parse_line(line, arr,    i, count) {
      sub(/^[[:space:]]*\|[[:space:]]*/, "", line)
      sub(/[[:space:]]*\|[[:space:]]*$/, "", line)
      count = split(line, arr, /\|/)
      for (i = 1; i <= count; i++) {
        arr[i] = trim(arr[i])
      }
      return count
    }

    function safe(value) {
      return value == "" ? "-" : value
    }

    BEGIN {
      print "role\thostname\tipv4\ttunnel\tlat(ms)\tloss\trx\ttx\tNAT\tversion"
    }

    /^\|/ {
      if ($0 ~ /^[[:space:]\|\-]+$/) {
        next
      }

      line = $0
      count = parse_line(line, cells)

      if (!header_ready) {
        for (i = 1; i <= count; i++) {
          headers[i] = cells[i]
        }
        header_ready = 1
        next
      }

      delete values
      for (i = 1; i <= count; i++) {
        values[headers[i]] = cells[i]
      }

      role = values["cost"] == "Local" ? "self" : "peer"
      printf("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
        role,
        safe(values["hostname"]),
        safe(values["ipv4"]),
        safe(values["tunnel"]),
        safe(values["lat(ms)"]),
        safe(values["loss"]),
        safe(values["rx"]),
        safe(values["tx"]),
        safe(values["NAT"]),
        safe(values["version"]))
      found = 1
    }

    END {
      if (!found) {
        exit 1
      }
    }
  ')" || return 1

  render_tsv_table "$tsv"
}

render_route_info() {
  local raw="$1"
  local tsv=""

  tsv="$(printf '%s\n' "$raw" | awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }

    function parse_line(line, arr,    i, count) {
      sub(/^[[:space:]]*\|[[:space:]]*/, "", line)
      sub(/[[:space:]]*\|[[:space:]]*$/, "", line)
      count = split(line, arr, /\|/)
      for (i = 1; i <= count; i++) {
        arr[i] = trim(arr[i])
      }
      return count
    }

    function safe(value) {
      return value == "" ? "-" : value
    }

    BEGIN {
      print "hostname\tipv4\tnext-hop\thops\tlat(ms)\tnext(ms)"
    }

    /^\|/ {
      if ($0 ~ /^[[:space:]\|\-]+$/) {
        next
      }

      line = $0
      count = parse_line(line, cells)

      if (!header_ready) {
        for (i = 1; i <= count; i++) {
          headers[i] = cells[i]
        }
        header_ready = 1
        next
      }

      delete values
      for (i = 1; i <= count; i++) {
        values[headers[i]] = cells[i]
      }

      if (values["next_hop_hostname"] == "Local" || values["next_hop_hostname"] == "-") {
        next_hop = "Local"
      } else if (values["next_hop_ipv4"] == "-" || values["next_hop_ipv4"] == "") {
        next_hop = values["next_hop_hostname"]
      } else {
        next_hop = values["next_hop_hostname"] " (" values["next_hop_ipv4"] ")"
      }

      printf("%s\t%s\t%s\t%s\t%s\t%s\n",
        safe(values["hostname"]),
        safe(values["ipv4"]),
        safe(next_hop),
        safe(values["path_len"]),
        safe(values["path_latency"]),
        safe(values["next_hop_lat"]))
      found = 1
    }

    END {
      if (!found) {
        exit 1
      }
    }
  ')" || return 1

  render_tsv_table "$tsv"
}

show_cli_node_info() {
  local raw_output=""

  raw_output="$(run_cli node 2>/dev/null || true)"
  if [[ -z "$raw_output" ]]; then
    print_warn "RPC 暂不可用，请稍后再试"
    return 0
  fi

  render_node_info "$raw_output" || printf '%s\n' "$raw_output"
}

show_cli_peer_info() {
  local raw_output=""

  raw_output="$(run_cli peer 2>/dev/null || true)"
  if [[ -z "$raw_output" ]]; then
    print_warn "暂无已连接节点信息"
    return 0
  fi

  render_peer_info "$raw_output" || printf '%s\n' "$raw_output"
}

show_cli_route_info() {
  local raw_output=""

  raw_output="$(run_cli route 2>/dev/null || true)"
  if [[ -z "$raw_output" ]]; then
    print_warn "暂无路由信息"
    return 0
  fi

  render_route_info "$raw_output" || printf '%s\n' "$raw_output"
}
