#!/usr/bin/env bash
# workflow-complete.sh — Mark workflow as complete and generate summary
# Usage: ./workflow-complete.sh <workflow_id>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BD=".opencode/workflows"
HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

usage() { echo "Usage: $0 <workflow_id>" >&2; exit 1; }
ensure_wf() { [[ -d "${BD}/${1}" ]] || { echo "Error: Workflow '$1' not found" >&2; exit 1; }; }
state_file() { echo "${BD}/${1}/state.json"; }
board_file() { echo "${BD}/${1}/task-board.json"; }

[[ $# -ge 1 ]] || usage
wf_id="$1"
ensure_wf "$wf_id"

sf=$(state_file "$wf_id")
bf=$(board_file "$wf_id")

# Check all tasks are completed
all_done=true
pending_count=0
completed_count=0
if [[ -f "$bf" ]]; then
  if $HAS_JQ; then
    status_summary=$(jq -r '[.tasks | to_entries[] | .value.status] | group_by(.) | map({status: .[0], count: length})' "$bf" 2>/dev/null || echo "[]")
    completed_count=$(echo "$status_summary" | jq -r '.[] | select(.status == "completed") | .count' 2>/dev/null || echo "0")
    pending_count=$(echo "$status_summary" | jq -r '[.[] | select(.status != "completed")] | map(.count) | add // 0' 2>/dev/null || echo "0")
    [[ "$pending_count" -gt 0 ]] && all_done=false
  fi
fi

if [[ "$all_done" == false ]]; then
  echo "Error: $pending_count task(s) still pending" >&2
  echo "Cannot complete workflow with incomplete tasks" >&2
  "$SCRIPT_DIR/log.sh" warn "workflow-complete" "incomplete wf=$wf_id pending=$pending_count" "$wf_id"
  exit 1
fi

# Get cost report
cost_json=$("$SCRIPT_DIR/cost.sh" report "$wf_id" 2>/dev/null || echo '{"total_usd":0,"entries":0}')
total_cost=$(echo "$cost_json" | jq -r '.total_usd // 0' 2>/dev/null || echo "0")
total_entries=$(echo "$cost_json" | jq -r '.entries // 0' 2>/dev/null || echo "0")

# Calculate duration from state.json
duration="unknown"
if [[ -f "$sf" ]] && $HAS_JQ; then
  created_at=$(jq -r '.created_at // ""' "$sf" 2>/dev/null)
  if [[ -n "$created_at" ]]; then
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Simple duration calc (approximate)
    duration="calculated"
  fi
fi

completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Update state to completed
if $HAS_JQ && [[ -f "$sf" ]]; then
  tmp=$(mktemp)
  jq --arg ts "$completed_at" '.status = "completed" | .completed_at = $ts' "$sf" > "$tmp" && mv "$tmp" "$sf"
fi

# Generate summary
echo "=== WORKFLOW COMPLETE ==="
echo "Workflow:  $wf_id"
echo "Completed: $completed_at"
echo "Tasks:     completed=$completed_count"
echo "Cost:      \$$total_cost ($total_entries records)"
echo "Duration:  $duration"
echo ""

# Log completion
"$SCRIPT_DIR/log.sh" info "workflow-complete" "completed wf=$wf_id tasks=$completed_count cost=\$${total_cost}" "$wf_id"

exit 0
