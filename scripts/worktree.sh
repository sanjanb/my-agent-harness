#!/usr/bin/env bash
# worktree.sh — Git worktree management for agent isolation
# Usage: ./worktree.sh {create|validate|handoff|cleanup|list} [args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKTREE_BASE=".opencode/worktrees"
LOG="$SCRIPT_DIR/log.sh"

usage() { echo "Usage: $0 {create|validate|handoff|cleanup|list} [args...]" >&2; exit 1; }

cmd_create() {
  local wf="$1" branch="$2" wt_dir="${WORKTREE_BASE}/${1}/${2}"
  [[ -d "$wt_dir" ]] && { echo "Error: Worktree exists: $wt_dir" >&2; exit 1; }
  mkdir -p "$(dirname "$wt_dir")"
  git worktree add "$wt_dir" -b "$branch" 2>&1 || { echo "Error: Failed to create worktree" >&2; exit 1; }
  "$LOG" info "worktree" "Created $wt_dir (branch: $branch)"
  echo "$wt_dir"
}

cmd_validate() {
  local wt="$1"
  [[ -d "$wt" ]] || { echo "Error: Not found: $wt" >&2; exit 1; }
  git -C "$wt" rev-parse --git-dir >/dev/null 2>&1 || { echo "Error: Not a git worktree: $wt" >&2; exit 1; }
  local dirty; dirty=$(git -C "$wt" status --porcelain 2>/dev/null)
  [[ -z "$dirty" ]] || { echo "Error: Uncommitted changes in $wt" >&2; echo "$dirty" >&2; exit 1; }
  echo "OK: $wt"
}

cmd_handoff() { cmd_validate "$1"; cd "$1" && pwd; }

cmd_cleanup() {
  local wf="$1" wt_base="${WORKTREE_BASE}/${1}"
  [[ -d "$wt_base" ]] || { echo "No worktrees for: $wf" >&2; exit 0; }
  local removed=0
  for d in "$wt_base"/*/; do
    [[ -d "$d" ]] || continue; d="${d%/}"
    git worktree remove --force "$d" 2>/dev/null && removed=$((removed+1)) || echo "Warning: Could not remove $d" >&2
  done
  rmdir "$wt_base" 2>/dev/null || true
  "$LOG" info "worktree" "Cleaned $removed worktree(s) for $wf"
  echo "Removed $removed worktree(s)"
}

cmd_list() {
  [[ -d "$WORKTREE_BASE" ]] || { echo "No active worktrees"; exit 0; }
  git worktree list 2>/dev/null | grep -F "$WORKTREE_BASE" || echo "No opencode worktrees"
}

[[ $# -ge 1 ]] || usage
action="$1"; shift
case "$action" in
  create)   [[ $# -ge 2 ]] || usage; cmd_create "$1" "$2" ;;
  validate) [[ $# -ge 1 ]] || usage; cmd_validate "$1" ;;
  handoff)  [[ $# -ge 1 ]] || usage; cmd_handoff "$1" ;;
  cleanup)  [[ $# -ge 1 ]] || usage; cmd_cleanup "$1" ;;
  list)     cmd_list ;;
  *) usage ;;
esac
