#!/usr/bin/env bash
# checkpoint.sh — Workflow checkpoint save/resume/list
# Usage: ./checkpoint.sh {save|latest|list|resume} <args...>
set -euo pipefail

HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

usage() {
  cat >&2 <<EOF
Usage:
  $0 save   <workflow_id> <step_num> <state_json>
  $0 latest <workflow_id>
  $0 list   <workflow_id>
  $0 resume <workflow_id>
EOF
  exit 1
}

checkpoint_dir() {
  echo ".opencode/workflows/$1/checkpoints"
}

save_checkpoint() {
  local wf="$1" step="$2" state_json="$3"
  [[ "$step" =~ ^[0-9]+$ ]] || { echo "Error: step_num must be numeric" >&2; exit 1; }

  local dir; dir=$(checkpoint_dir "$wf")
  mkdir -p "$dir"

  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local file="${dir}/step-${step}.json"

  # Validate state_json is valid JSON if jq available
  if $HAS_JQ; then
    echo "$state_json" | jq empty 2>/dev/null || { echo "Error: Invalid state JSON" >&2; exit 1; }
    jq -n --argjson step "$step" --arg ts "$ts" --argjson state "$state_json" \
      '{step: $step, timestamp: $ts, state: $state}' > "$file"
  else
    printf '{"step":%s,"timestamp":"%s","state":%s}\n' "$step" "$ts" "$state_json" > "$file"
  fi

  echo "$file"
}

latest_checkpoint() {
  local wf="$1"
  local dir; dir=$(checkpoint_dir "$wf")
  [[ -d "$dir" ]] || { echo "Error: No checkpoints for workflow $wf" >&2; exit 1; }

  # Find highest step number
  local latest
  latest=$(ls "$dir"/step-*.json 2>/dev/null | sort -t'-' -k2 -n | tail -1)
  [[ -n "$latest" && -f "$latest" ]] || { echo "Error: No checkpoint files found" >&2; exit 1; }
  echo "$latest"
}

list_checkpoints() {
  local wf="$1"
  local dir; dir=$(checkpoint_dir "$wf")
  [[ -d "$dir" ]] || { echo "No checkpoints for workflow $wf"; exit 0; }

  for f in "$dir"/step-*.json; do
    [[ -f "$f" ]] || continue
    if $HAS_JQ; then
      local step_num ts
      step_num=$(jq -r '.step' "$f")
      ts=$(jq -r '.timestamp' "$f")
      printf 'step-%s  %s  %s\n' "$step_num" "$ts" "$f"
    else
      basename "$f"
    fi
  done
}

resume_checkpoint() {
  local wf="$1"
  local f; f=$(latest_checkpoint "$wf")

  if $HAS_JQ; then
    jq '.state' "$f"
  else
    cat "$f"
  fi
}

[[ $# -ge 1 ]] || usage
action="$1"; shift

case "$action" in
  save)   [[ $# -ge 3 ]] || usage; save_checkpoint "$1" "$2" "$3" ;;
  latest) [[ $# -ge 1 ]] || usage; latest_checkpoint "$1" ;;
  list)   [[ $# -ge 1 ]] || usage; list_checkpoints "$1" ;;
  resume) [[ $# -ge 1 ]] || usage; resume_checkpoint "$1" ;;
  *) usage ;;
esac
