#!/usr/bin/env bash
# recover.sh — Crash recovery: reads checkpoint + DAG, outputs recovery plan
# Usage: ./recover.sh <workflow_id> <dag_file>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: $0 <workflow_id> <dag_file>" >&2
  exit 1
}

[[ $# -ge 2 ]] || usage
wf_id="$1" dag_file="$2"

[[ -f "$dag_file" ]] || { echo "Error: DAG file not found: $dag_file" >&2; exit 1; }

# Try to read latest checkpoint
checkpoint_file=""
resume_state="{}"
completed_tasks=""

if checkpoint_file=$("$SCRIPT_DIR/checkpoint.sh" latest "$wf_id" 2>/dev/null); then
  [[ -f "$checkpoint_file" ]] || checkpoint_file=""

  if [[ -n "$checkpoint_file" ]]; then
    "$SCRIPT_DIR/log.sh" info "recover" "Found checkpoint: $checkpoint_file" "$wf_id"

    # Extract completed tasks from checkpoint state
    completed_tasks=$(
      if command -v jq &>/dev/null; then
        jq -r '.state.completed_tasks // [] | join(",")' "$checkpoint_file"
      else
        echo ""
      fi
    )
  fi
fi

if [[ -z "$checkpoint_file" ]]; then
  "$SCRIPT_DIR/log.sh" info "recover" "No checkpoint found, starting fresh" "$wf_id"
fi

# Get full DAG order
dag_order=$("$SCRIPT_DIR/dag-execute.sh" order "$dag_file")

# Build recovery plan
if command -v jq &>/dev/null; then
  completed_json="[]"
  if [[ -n "$completed_tasks" ]]; then
    completed_json=$(echo "$completed_tasks" | jq -R 'split(",") | map(select(length > 0))')
  fi

  # Get all tasks in order
  all_tasks=$(echo "$dag_order" | jq -R 'split(",") | map(select(length > 0))')

  # Determine in-progress: first non-completed task
  in_progress=""
  resume_from=""
  pending_tasks=""

  IFS=',' read -ra tasks <<< "$dag_order"
  for t in "${tasks[@]}"; do
    [[ -z "$t" ]] && continue
    is_done=$(echo "$completed_json" | jq --arg t "$t" 'index($t) // empty' 2>/dev/null)
    if [[ -z "$is_done" ]]; then
      if [[ -z "$in_progress" ]]; then
        in_progress="$t"
        resume_from="$t"
      else
        pending_tasks="${pending_tasks:+$pending_tasks,}$t"
      fi
    fi
  done

  pending_json="[]"
  if [[ -n "$pending_tasks" ]]; then
    pending_json=$(echo "$pending_tasks" | jq -R 'split(",") | map(select(length > 0))')
  fi

  jq -n \
    --arg resume "$resume_from" \
    --argjson completed "$completed_json" \
    --argjson pending "$pending_json" \
    --arg in_progress "$in_progress" \
    '{resume_from: $resume, completed: $completed, pending: $pending, in_progress: $in_progress}'
else
  # Fallback without jq — just output raw data
  echo "resume_from: $resume_from"
  echo "completed: $completed_tasks"
  echo "pending: $pending_tasks"
fi

"$SCRIPT_DIR/log.sh" info "recover" "Recovery plan generated" "$wf_id"
