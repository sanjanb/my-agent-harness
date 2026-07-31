#!/usr/bin/env bash
# merge-conflict.sh — Detect, report, and resolve merge conflicts
# Usage: ./merge-conflict.sh {detect|report|abort} [args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKTREE_BASE=".opencode/worktrees"
LOG="$SCRIPT_DIR/log.sh"

usage() { echo "Usage: $0 {detect|report|abort} [args...]" >&2; exit 1; }

cmd_detect() {
  local wt="$1"
  [[ -d "$wt" ]] || { echo "Error: Not found: $wt" >&2; exit 1; }
  local conflicts; conflicts=$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null) || true
  [[ -z "$conflicts" ]] && { echo "No conflicts"; exit 0; }
  echo "$conflicts"; exit 1
}

cmd_report() {
  local wf="$1" wt_base="${WORKTREE_BASE}/${1}"
  [[ -d "$wt_base" ]] || { echo "No worktrees for: $wf" >&2; exit 0; }

  local total=0
  for d in "$wt_base"/*/; do
    [[ -d "$d" ]] || continue; d="${d%/}"
    local conflicts; conflicts=$(git -C "$d" diff --name-only --diff-filter=U 2>/dev/null) || true
    [[ -z "$conflicts" ]] && continue
    local count; count=$(echo "$conflicts" | wc -l)
    total=$((total+count))
    echo "=== $(basename "$d") ($count conflict(s)) ==="
    echo "$conflicts"
  done
  [[ $total -eq 0 ]] && echo "No conflicts across workflow worktrees" || { echo "Total: $total conflict(s)"; exit 1; }
}

cmd_abort() {
  git merge --abort 2>&1 || { echo "Error: No merge in progress" >&2; exit 1; }
  "$LOG" warn "merge-conflict" "Merge aborted"; echo "Merge aborted"
}

[[ $# -ge 1 ]] || usage
action="$1"; shift
case "$action" in
  detect) [[ $# -ge 1 ]] || usage; cmd_detect "$1" ;;
  report) [[ $# -ge 1 ]] || usage; cmd_report "$1" ;;
  abort)  cmd_abort ;;
  *) usage ;;
esac
