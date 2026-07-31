#!/usr/bin/env bash
# health.sh — System health check for orchestration components
# Usage: ./health.sh <workflow_id> | ./health.sh full
set -euo pipefail

HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true
BD=".opencode/workflows"
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

check_file() {
  local path="$1" name="$2"
  [[ -f "$path" ]] || { echo "{\"check\":\"$name\",\"status\":\"missing\"}"; return; }
  if $HAS_JQ && [[ "$path" == *.json ]]; then
    jq . "$path" >/dev/null 2>&1 && echo "{\"check\":\"$name\",\"status\":\"ok\"}" \
      || echo "{\"check\":\"$name\",\"status\":\"warn\",\"detail\":\"invalid JSON\"}"
  else
    echo "{\"check\":\"$name\",\"status\":\"ok\"}"
  fi
}

check_disk() {
  local dir="$BD/$1"
  [[ -d "$dir" ]] || { echo "{\"check\":\"disk_usage\",\"status\":\"missing\"}"; return; }
  local size; size=$(du -sk "$dir" 2>/dev/null | cut -f1)
  echo "{\"check\":\"disk_usage\",\"status\":\"ok\",\"detail\":\"${size:-0}KB\"}"
}

check_stale() {
  local wt_base=".opencode/worktrees/$1"
  [[ -d "$wt_base" ]] || { echo "{\"check\":\"stale_worktrees\",\"status\":\"ok\",\"detail\":\"none\"}"; return; }
  local stale=0 threshold=$(( $(date +%s) - 30 * 60 ))
  for d in "$wt_base"/*/; do
    [[ -d "$d" ]] || continue
    local mt; mt=$(stat -c %Y "$d" 2>/dev/null || stat -f %m "$d" 2>/dev/null || echo 0)
    (( mt > 0 && mt < threshold )) && stale=$((stale + 1))
  done
  (( stale > 0 )) && echo "{\"check\":\"stale_worktrees\",\"status\":\"warn\",\"detail\":\"$stale stale\"}" \
    || echo "{\"check\":\"stale_worktrees\",\"status\":\"ok\",\"detail\":\"none\"}"
}

check_workflow() {
  local wf="$1" dir="$BD/$wf"
  [[ -d "$dir" ]] || { echo "{\"workflow_id\":\"$wf\",\"state\":\"unhealthy\",\"checks\":[{\"check\":\"directory\",\"status\":\"missing\"}],\"timestamp\":\"$(now_iso)\"}"; return; }

  local s=() state="healthy"
  s+=("$(check_file "$dir/state.json" "state")")
  s+=("$(check_file "$dir/task-board.json" "task_board")")
  s+=("$(check_file "$dir/budget.json" "budget")")
  s+=("$(check_disk "$wf")")
  s+=("$(check_stale "$wf")")

  for c in "${s[@]}"; do
    echo "$c" | grep -q '"status":"missing"' && { state="unhealthy"; break; }
    echo "$c" | grep -q '"status":"warn"' && [[ "$state" != "unhealthy" ]] && state="degraded"
  done

  if $HAS_JQ; then
    echo "{\"workflow_id\":\"$wf\",\"state\":\"$state\",\"checks\":[$(printf '%s\n' "${s[@]}" | paste -sd,)],\"timestamp\":\"$(now_iso)\"}"
  else
    echo "Workflow: $wf | State: $state"; printf '%s\n' "${s[@]}"
  fi
}

[[ $# -ge 1 ]] || { echo "Usage: $0 <workflow_id> | $0 full" >&2; exit 1; }

if [[ "$1" == "full" ]]; then
  [[ -d "$BD" ]] || { echo "No workflows found"; exit 0; }
  ok=true
  for d in "$BD"/*/; do [[ -d "$d" ]] || continue; r=$(check_workflow "$(basename "$d")"); echo "$r"; echo "$r" | grep -q '"state":"healthy"' || ok=false; done
  $ok && exit 0 || exit 1
else
  r=$(check_workflow "$1"); echo "$r"; echo "$r" | grep -q '"state":"healthy"' && exit 0 || exit 1
fi
