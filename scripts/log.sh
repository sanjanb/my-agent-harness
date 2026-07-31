#!/usr/bin/env bash
# log.sh — Structured JSONL logger
# Usage: ./log.sh <level> <component> <message> [correlation_id]
# Always exits 0 — logging must never fail.
set -uo pipefail

VALID_LEVELS="debug info warn error critical"

usage() {
  echo "Usage: $0 <level> <component> <message> [correlation_id]" >&2
  echo "Levels: $VALID_LEVELS" >&2
  exit 1
}

[[ $# -ge 3 ]] || usage
level="$1" component="$2" message="$3" corr="${4:-}"

# Validate level
level_upper=$(echo "$level" | tr '[:lower:]' '[:upper:]')
case "$VALID_LEVELS" in
  *"$level"*) ;;
  *) echo "Warning: Unknown level '$level', using as-is" >&2; level_upper=$(echo "$level" | tr '[:lower:]' '[:upper:]') ;;
esac

# Determine log file path
log_dir=".opencode"
log_file="${log_dir}/logs.jsonl"
mkdir -p "$log_dir" 2>/dev/null || true

# Build JSON line — handle special chars in message
ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# Escape JSON string: backslash, double-quote, newlines, tabs
escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

msg_escaped=$(escape_json "$message")
corr_escaped=$(escape_json "$corr")

if [[ -n "$corr" ]]; then
  printf '{"ts":"%s","level":"%s","component":"%s","msg":"%s","corr":"%s"}\n' \
    "$ts" "$level_upper" "$component" "$msg_escaped" "$corr_escaped" >> "$log_file"
else
  printf '{"ts":"%s","level":"%s","component":"%s","msg":"%s"}\n' \
    "$ts" "$level_upper" "$component" "$msg_escaped" >> "$log_file"
fi

exit 0
