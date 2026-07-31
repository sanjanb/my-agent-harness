#!/usr/bin/env bash
# dashboard.sh — Human-readable orchestration dashboard
# Usage: ./dashboard.sh <workflow_id> | ./dashboard.sh global
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BD=".opencode/workflows"

# Colors
R='\033[0;31m' Y='\033[0;33m' G='\033[0;32m' C='\033[0;36m' B='\033[1m' D='\033[0m'

state_color() {
  case "$1" in
    healthy|completed|ok) echo "$G" ;;
    degraded|pending|warn) echo "$Y" ;;
    unhealthy|failed|error|missing) echo "$R" ;;
    *) echo "$D" ;;
  esac
}

render_workflow() {
  local wf="$1" dir="$BD/$wf"
  printf "${B}━━━ Workflow: %s ━━━${D}\n" "$wf"

  # State
  if [[ -f "$dir/state.json" ]]; then
    local state; state=$(cat "$dir/state.json" 2>/dev/null || echo "{}")
    if command -v jq &>/dev/null; then
      printf "  State:    %s\n" "$(echo "$state" | jq -r '.status // .state // "unknown"')"
    else
      printf "  State:    (raw) %s\n" "$state"
    fi
  else
    printf "  State:    ${R}missing${D}\n"
  fi

  # Task board
  if [[ -f "$dir/task-board.json" ]] && command -v jq &>/dev/null; then
    local tb="$dir/task-board.json"
    local pending claimed completed failed
    pending=$(jq '[.tasks | to_entries[] | select(.value.status == "pending")] | length' "$tb" 2>/dev/null || echo 0)
    claimed=$(jq '[.tasks | to_entries[] | select(.value.status == "claimed")] | length' "$tb" 2>/dev/null || echo 0)
    completed=$(jq '[.tasks | to_entries[] | select(.value.status == "completed")] | length' "$tb" 2>/dev/null || echo 0)
    failed=$(jq '[.tasks | to_entries[] | select(.value.status == "failed")] | length' "$tb" 2>/dev/null || echo 0)
    printf "  Tasks:    ${G}%s done${D} / ${Y}%s claimed${D} / %s pending / ${R}%s failed${D}\n" \
      "$completed" "$claimed" "$pending" "$failed"
  else
    printf "  Tasks:    ${R}no task board${D}\n"
  fi

  # Budget
  if [[ -f "$dir/budget.json" ]] && command -v jq &>/dev/null; then
    local bgt="$dir/budget.json"
    local total spent pct
    total=$(jq -r '.total_budget // 0' "$bgt" 2>/dev/null)
    spent=$(jq '[.spent | to_entries[].value] | add // 0' "$bgt" 2>/dev/null)
    (( total > 0 )) && pct=$(( (spent * 100) / total )) || pct=0
    local clr; clr=$(state_color "$(( 100 - pct > 25 ? 100 : 50 ))")
    printf "  Budget:   %s/%s tokens (%s%% used) %s\n" "$spent" "$total" "$pct" ""
  else
    printf "  Budget:   ${R}no budget${D}\n"
  fi

  # Recent logs
  local logf=".opencode/logs.jsonl"
  if [[ -f "$logf" ]] && command -v jq &>/dev/null; then
    printf "  ${C}Recent logs:${D}\n"
    jq -r 'select(.corr != null) | "    \(.ts) [\(.level)] \(.component): \(.msg)"' "$logf" 2>/dev/null | tail -5
  fi

  # Worktrees
  local wtb=".opencode/worktrees/$wf"
  if [[ -d "$wtb" ]]; then
    printf "  Worktrees: %s active\n" "$(find "$wtb" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
  fi

  # Correlation trace summary
  local tf="$dir/trace.jsonl"
  if [[ -f "$tf" ]] && command -v jq &>/dev/null; then
    local ops; ops=$(wc -l < "$tf" 2>/dev/null || echo 0)
    local fail; fail=$(jq -s '[.[] | select(.status == "failed" or .status == "error")] | length' "$tf" 2>/dev/null || echo 0)
    printf "  Traces:   %s operations, ${R}%s failed${D}\n" "$ops" "$fail"
  fi

  echo ""
}

[[ $# -ge 1 ]] || { echo "Usage: $0 <workflow_id> | $0 global" >&2; exit 1; }

if [[ "$1" == "global" ]]; then
  printf "${B}╔══════════════════════════════════╗${D}\n"
  printf "${B}║     ORCHESTRATION DASHBOARD      ║${D}\n"
  printf "${B}╚══════════════════════════════════╝${D}\n\n"
  [[ -d "$BD" ]] || { echo "No workflows found."; exit 0; }
  for d in "$BD"/*/; do [[ -d "$d" ]] || continue; render_workflow "$(basename "$d")"; done
else
  [[ -d "$BD/$1" ]] || { echo "Workflow '$1' not found" >&2; exit 1; }
  render_workflow "$1"
fi
