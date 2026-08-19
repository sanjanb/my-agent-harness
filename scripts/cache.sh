#!/usr/bin/env bash
# cache.sh — JSONL-based semantic cache for task results
# Usage: ./cache.sh {check|save|query|stats|find-similar} <args...>
set -euo pipefail
CACHE_FILE=".opencode/cache.jsonl"
usage() { echo "Usage: $0 {check|save|query|stats|find-similar} <args...>" >&2; exit 1; }
ensure_cache() { mkdir -p "$(dirname "$CACHE_FILE")" 2>/dev/null || true; [[ -f "$CACHE_FILE" ]] || touch "$CACHE_FILE"; }

cmd_check() {
  [[ $# -ge 1 ]] || usage; ensure_cache
  local query="$1"
  # Try exact hash match first
  local match; match=$(grep "\"task_hash\":\"${query}\"" "$CACHE_FILE" 2>/dev/null | head -1)
  [[ -n "$match" ]] && { echo "$match"; exit 0; }
  # If a prompt was provided as second arg, try similarity on prompt
  if [[ $# -ge 2 ]]; then
    cmd_find_similar "$2"
  fi
  exit 1
}

cmd_find_similar() {
  [[ $# -ge 1 ]] || usage; ensure_cache
  local match; match=$(grep -i "\"task_prompt\":\".*${1}.*\"" "$CACHE_FILE" 2>/dev/null | head -1)
  [[ -n "$match" ]] && { echo "$match"; exit 0; } || exit 1
}

cmd_save() {
  [[ $# -ge 2 ]] || usage
  local hash="$1" result_file="$2" agent="${3:-unknown}" model="${4:-unknown}" cost="${5:-0}" prompt="${6:-}"
  [[ -f "$result_file" ]] || { echo "Error: Result file not found: $result_file" >&2; exit 1; }
  ensure_cache
  local result ts; result=$(cat "$result_file"); ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  result="${result//\\/\\\\}"; result="${result//$'\n'/\\n}"; result="${result//$'\t'/\\t}"
  printf '{"task_hash":"%s","task_prompt":"%s","result":"%s","agent":"%s","timestamp":"%s","model":"%s","cost":%s}\n' \
    "$hash" "$prompt" "$result" "$agent" "$ts" "$model" "$cost" >> "$CACHE_FILE"
  echo "Cached result for $hash"
}

cmd_query() {
  [[ $# -ge 1 ]] || usage; ensure_cache
  local matches; matches=$(grep -i "$1" "$CACHE_FILE" 2>/dev/null || true)
  [[ -n "$matches" ]] && { echo "$matches"; exit 0; } || { echo "No matches for '$1'" >&2; exit 1; }
}

cmd_stats() {
  ensure_cache
  local total oldest newest
  total=$(wc -l < "$CACHE_FILE" 2>/dev/null | tr -d ' ')
  if (( total > 0 )); then
    oldest=$(head -1 "$CACHE_FILE" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
    newest=$(tail -1 "$CACHE_FILE" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
  fi
  printf '{"total_entries":%s,"oldest":"%s","newest":"%s","cache_file":"%s"}\n' "$total" "$oldest" "$newest" "$CACHE_FILE"
}

[[ $# -ge 1 ]] || usage; action="$1"; shift
case "$action" in check) cmd_check "$@";; save) cmd_save "$@";; query) cmd_query "$@";; stats) cmd_stats "$@";; find-similar) cmd_find_similar "$@";; *) usage;; esac