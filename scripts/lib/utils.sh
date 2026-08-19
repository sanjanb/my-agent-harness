#!/usr/bin/env bash
# Shared utility functions for runtime scripts.
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/lib/utils.sh"

# Escape a string for safe JSON embedding.
escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

# Return current UTC time in ISO 8601 format.
now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}