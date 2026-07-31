#!/usr/bin/env bash
# state.sh — JSON state manager (jq-native, fallback to basic ops)
# Usage: ./state.sh {read|write|query|init} <args...>
set -euo pipefail

HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

usage() {
  cat >&2 <<EOF
Usage:
  $0 read   <file> [key.path]
  $0 write  <file> <key.path> <value>
  $0 query  <file> <jq-expression>
  $0 init   <file> <json>
EOF
  exit 1
}

[[ $# -ge 2 ]] || usage
action="$1"; shift

cmd_read() {
  local file="$1" key="${2:-}"
  [[ -f "$file" ]] || { echo "Error: File not found: $file" >&2; return 1; }

  if [[ -z "$key" ]]; then
    cat "$file"
  elif $HAS_JQ; then
    jq -r --arg k "$key" 'getpath($k | split("."))' "$file"
  else
    # Fallback: just cat the file (no dot-path parsing without jq)
    echo "Warning: jq not found, printing full file" >&2
    cat "$file"
  fi
}

cmd_write() {
  local file="$1" key="$2" value="$3"
  mkdir -p "$(dirname "$file")" 2>/dev/null || true

  # Backup existing
  [[ -f "$file" ]] && cp "$file" "${file}.bak"

  if $HAS_JQ; then
    local tmp
    tmp=$(mktemp)
    if [[ -f "$file" ]]; then
      jq --arg k "$key" --arg v "$value" 'setpath($k | split("."); $v)' "$file" > "$tmp"
    else
      echo '{}' | jq --arg k "$key" --arg v "$value" 'setpath($k | split("."); $v)' > "$tmp"
    fi
    mv "$tmp" "$file"
  else
    # Minimal fallback: write raw value
    echo "$value" > "$file"
  fi
}

cmd_query() {
  local file="$1" expr="$2"
  [[ -f "$file" ]] || { echo "Error: File not found: $file" >&2; return 1; }
  if $HAS_JQ; then
    jq "$expr" "$file"
  else
    echo "Error: jq required for query" >&2; return 1
  fi
}

cmd_init() {
  local file="$1" json="$2"
  # Validate JSON
  if $HAS_JQ; then
    echo "$json" | jq . >/dev/null 2>&1 || { echo "Error: Invalid JSON" >&2; return 1; }
  fi
  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  [[ -f "$file" ]] && cp "$file" "${file}.bak"
  echo "$json" > "$file"
}

case "$action" in
  read)  [[ $# -ge 1 ]] || usage; cmd_read "$@" ;;
  write) [[ $# -ge 3 ]] || usage; cmd_write "$@" ;;
  query) [[ $# -ge 2 ]] || usage; cmd_query "$@" ;;
  init)  [[ $# -ge 2 ]] || usage; cmd_init "$@" ;;
  *) usage ;;
esac
