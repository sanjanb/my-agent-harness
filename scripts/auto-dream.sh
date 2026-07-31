#!/usr/bin/env bash
# auto-dream.sh — Memory consolidation between sessions (AutoDream pattern)
# Usage: ./auto-dream.sh <workflow_id> [--dry-run]
set -euo pipefail

HAS_JQ=false; command -v jq &>/dev/null && HAS_JQ=true
usage() { echo "Usage: $0 <workflow_id> [--dry-run]" >&2; exit 1; }
[[ $# -ge 1 ]] || usage
wf="$1"; dry_run=false; [[ "${2:-}" == "--dry-run" ]] && dry_run=true

wf_dir=".opencode/workflows/$wf"
[[ -d "$wf_dir" ]] || { echo "Error: Workflow '$wf' not found in .opencode/workflows/" >&2; exit 1; }

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
escape_json() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; echo "$s"; }

# Collect learnings from multiple sources
patterns=(); anti_patterns=(); preferences=(); decisions=()

# 1. Read logs
log_file="$wf_dir/logs.jsonl"
if [[ -f "$log_file" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    level=$(echo "$line" | jq -r '.level // ""' 2>/dev/null)
    msg=$(echo "$line" | jq -r '.msg // ""' 2>/dev/null)
    [[ -z "$msg" ]] && continue
    if [[ "$level" == "ERROR" || "$level" == "CRITICAL" ]]; then
      anti_patterns+=("$msg")
    elif [[ "$level" == "INFO" ]]; then
      patterns+=("$msg")
    fi
  done < "$log_file"
fi

# 2. Read replay files
replay_dir="$wf_dir/replay"
if [[ -d "$replay_dir" ]]; then
  for f in "$replay_dir"/step-*.json; do
    [[ -f "$f" ]] || continue
    output=$(jq -r '.output // ""' "$f" 2>/dev/null)
    [[ -n "$output" ]] && patterns+=("$output")
  done
fi

# 3. Read conventions
conv_file=".opencode/conventions.jsonl"
if [[ -f "$conv_file" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    val=$(echo "$line" | jq -r '.value // ""' 2>/dev/null)
    src=$(echo "$line" | jq -r '.source // ""' 2>/dev/null)
    [[ -n "$val" ]] && { [[ "$src" == "user" ]] && preferences+=("$val") || decisions+=("$val"); }
  done < "$conv_file"
fi

# 4. Read state for decisions
state_file="$wf_dir/state.json"
if [[ -f "$state_file" ]]; then
  status=$(jq -r '.status // ""' "$state_file" 2>/dev/null)
  [[ -n "$status" ]] && decisions+=("Workflow status: $status")
fi

# Build JSON arrays from collected data
build_json_array() {
  local arr=("$@")
  local result="["
  local first=true
  for item in "${arr[@]}"; do
    [[ -z "$item" ]] && continue
    $first || result+=","
    first=false
    result+="\"$(escape_json "$item")\""
  done
  result+="]"
  echo "$result"
}

patterns_json=$(build_json_array "${patterns[@]}")
anti_json=$(build_json_array "${anti_patterns[@]}")
prefs_json=$(build_json_array "${preferences[@]}")
decisions_json=$(build_json_array "${decisions[@]}")

output="{\"patterns\":$patterns_json,\"anti_patterns\":$anti_json,\"preferences\":$prefs_json,\"decisions\":$decisions_json,\"last_consolidated\":\"$(now_iso)\"}"

if $dry_run; then
  echo "=== DRY RUN: Memory for workflow $wf ==="
  $HAS_JQ && echo "$output" | jq . || echo "$output"
  exit 0
fi

# Write memory file
memory_file="$wf_dir/memory.json"
$HAS_JQ && echo "$output" | jq . > "$memory_file" || echo "$output" > "$memory_file"
echo "Consolidated memory written to $memory_file"
