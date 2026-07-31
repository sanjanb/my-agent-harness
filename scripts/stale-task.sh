#!/usr/bin/env bash
# stale-task.sh — Detect and handle stale tasks on the task board
# Usage: ./stale-task.sh {detect|release|report} <args...>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BD=".opencode/workflows"
DEFAULT_MAX_AGE=30

usage() { echo "Usage: $0 {detect|release|report} <args...>" >&2; exit 1; }
board_file() { echo "${BD}/${1}/task-board.json"; }
ensure_board() { [[ -f "$(board_file "$1")" ]] || { echo "Error: Board not found for $1" >&2; exit 1; }; }

now_epoch() { date +%s; }
iso_to_epoch() {
  local ts="$1"
  date --version &>/dev/null 2>&1 && date -d "$ts" +%s 2>/dev/null || \
    date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0
}

cmd_detect() {
  [[ $# -ge 1 ]] || usage
  local wf="$1" max_age="${2:-$DEFAULT_MAX_AGE}"
  ensure_board "$wf"
  local f; f=$(board_file "$wf")
  local now; now=$(now_epoch)
  local threshold=$(( now - max_age * 60 ))

  local stale_found=false
  while IFS= read -r entry; do
    local task_id claimed_at
    task_id=$(echo "$entry" | jq -r '.id')
    claimed_at=$(echo "$entry" | jq -r '.claimed_at')
    [[ -z "$claimed_at" || "$claimed_at" == "null" ]] && continue
    local claim_epoch; claim_epoch=$(iso_to_epoch "$claimed_at")
    [[ "$claim_epoch" -eq 0 ]] && continue
    if [[ "$claim_epoch" -lt "$threshold" ]]; then
      local age_min=$(( (now - claim_epoch) / 60 ))
      printf '{"task_id":"%s","claimed_at":"%s","age_minutes":%d,"stale":true}\n' \
        "$task_id" "$claimed_at" "$age_min"
      stale_found=true
    fi
  done < <(command jq -c '[.tasks | to_entries[] | select(.value.status == "claimed")] | [.[] | {id: .key, claimed_at: .value.claimed_at}] | .[]' "$f" 2>/dev/null || true)
  [[ "$stale_found" == false ]] && echo '{"stale":[],"count":0}'
  "$SCRIPT_DIR/log.sh" info "stale-task" "detect wf=$wf max_age=${max_age}m" "$wf"
}

cmd_release() {
  [[ $# -ge 2 ]] || usage
  local wf="$1" task_id="$2"
  ensure_board "$wf"
  "$SCRIPT_DIR/task-board.sh" release "$wf" "$task_id" "stale detection"
  "$SCRIPT_DIR/log.sh" info "stale-task" "released stale task=$task_id" "$wf"
  echo "Released task $task_id (stale)"
}

cmd_report() {
  [[ $# -ge 1 ]] || usage
  local wf="$1"
  ensure_board "$wf"
  local f; f=$(board_file "$wf")
  local now; now=$(now_epoch)

  printf "%-20s %-12s %-10s %-8s %s\n" "TASK_ID" "STATUS" "AGE(MIN)" "STALE?" "AGENT"
  printf "%-20s %-12s %-10s %-8s %s\n" "------" "------" "--------" "------" "-----"

  while IFS= read -r entry; do
    local task_id status agent claimed_at
    task_id=$(echo "$entry" | jq -r '.key')
    status=$(echo "$entry" | jq -r '.value.status // "unknown"')
    agent=$(echo "$entry" | jq -r '.value.agent // "-"')
    claimed_at=$(echo "$entry" | jq -r '.value.claimed_at // ""')

    local age_str="-" stale_str="no"
    if [[ -n "$claimed_at" && "$claimed_at" != "null" ]]; then
      local claim_epoch; claim_epoch=$(iso_to_epoch "$claimed_at")
      if [[ "$claim_epoch" -gt 0 ]]; then
        local age_min=$(( (now - claim_epoch) / 60 ))
        age_str="$age_min"
        [[ "$age_min" -gt "$DEFAULT_MAX_AGE" && "$status" == "claimed" ]] && stale_str="YES"
      fi
    fi
    printf "%-20s %-12s %-10s %-8s %s\n" "$task_id" "$status" "$age_str" "$stale_str" "$agent"
  done < <(command jq -c '.tasks | to_entries[]' "$f" 2>/dev/null || true)

  "$SCRIPT_DIR/log.sh" info "stale-task" "report wf=$wf" "$wf"
}

[[ $# -ge 1 ]] || usage
action="$1"; shift
case "$action" in
  detect)  cmd_detect "$@" ;;
  release) cmd_release "$@" ;;
  report)  cmd_report "$@" ;;
  *) usage ;;
esac
