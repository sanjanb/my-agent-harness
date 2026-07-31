#!/usr/bin/env bash
# task-board.sh — Atomic task board operations
# Usage: ./task-board.sh {init|claim|release|complete|status|stale} <args...>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

usage() { echo "Usage: $0 {init|claim|release|complete|status|stale} <args...>" >&2; exit 1; }
board_file() { echo ".opencode/workflows/$1/task-board.json"; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ensure_board() {
  local f; f=$(board_file "$1")
  if [[ ! -f "$f" ]]; then
    mkdir -p "$(dirname "$f")"
    echo "{\"tasks\":{},\"workflow_id\":\"$1\"}" > "$f"
  fi
}

jq_update() {
  local f="$1" expr="$2"; shift 2
  local tmp; tmp=$(mktemp)
  jq "$expr" "$@" "$f" > "$tmp" && mv "$tmp" "$f"
}

[[ $# -ge 1 ]] || usage
action="$1"; shift

case "$action" in
  init)
    [[ $# -ge 1 ]] || usage
    ensure_board "$1"
    "$SCRIPT_DIR/log.sh" info "task-board" "initialized board for $1" ""
    ;;
  claim)
    [[ $# -ge 3 ]] || usage
    ensure_board "$1"
    f=$(board_file "$1")
    now=$(now_iso)
    "$SCRIPT_DIR/flock.sh" "${f}.lock" bash -c "
      $HAS_JQ && jq --arg t '$2' --arg a '$3' --arg ts '$now' \
        '.tasks[\$t] = {\"status\":\"claimed\",\"agent\":\$a,\"claimed_at\":\$ts,\"claimed_by\":\$a}' \
        '$f' > '${f}.tmp' && mv '${f}.tmp' '$f'
    "
    "$SCRIPT_DIR/log.sh" info "task-board" "claimed task=$2 agent=$3" "$2"
    ;;
  release)
    [[ $# -ge 2 ]] || usage
    f=$(board_file "$1")
    [[ -f "$f" ]] || { echo "Error: Board not found for $1" >&2; exit 1; }
    $HAS_JQ && jq_update "$f" --arg t "$2" --arg r "${3:-}" --arg ts "$(now_iso)" \
      '.tasks[$t] = {"status":"pending","release_reason":$r,"released_at":$ts}'
    "$SCRIPT_DIR/log.sh" info "task-board" "released task=$2" "$2"
    ;;
  complete)
    [[ $# -ge 3 ]] || usage
    f=$(board_file "$1")
    [[ -f "$f" ]] || { echo "Error: Board not found for $1" >&2; exit 1; }
    $HAS_JQ && jq_update "$f" --arg t "$2" --arg s "$3" --arg ts "$(now_iso)" \
      '.tasks[$t] = {"status":"completed","result_summary":$s,"completed_at":$ts}'
    "$SCRIPT_DIR/log.sh" info "task-board" "completed task=$2" "$2"
    ;;
  status)
    [[ $# -ge 1 ]] || usage
    f=$(board_file "$1")
    [[ -f "$f" ]] || { echo "Error: Board not found for $1" >&2; exit 1; }
    if $HAS_JQ; then
      [[ -n "${2:-}" ]] && jq --arg t "$2" '.tasks[$t] // "not found"' "$f" || jq '.tasks' "$f"
    else
      cat "$f"
    fi
    ;;
  stale)
    [[ $# -ge 1 ]] || usage
    f=$(board_file "$1")
    [[ -f "$f" ]] || { echo "Error: Board not found for $1" >&2; exit 1; }
    if $HAS_JQ; then
      threshold=$(( $(date +%s) - ${2:-30} * 60 ))
      jq --argjson th "$threshold" \
        '[.tasks | to_entries[] | select(.value.status == "claimed" and (.value.claimed_at | fromdateiso8601) < $th)] | from_entries' "$f"
    fi
    ;;
  *) usage ;;
esac
