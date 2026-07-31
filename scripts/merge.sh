#!/usr/bin/env bash
# merge.sh — Sequential merge of worktree branches into target
# Usage: ./merge.sh {merge|status} <args...>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKTREE_BASE=".opencode/worktrees"
LOG="$SCRIPT_DIR/log.sh"

usage() { echo "Usage: $0 {merge|status} [args...]" >&2; exit 1; }

cmd_merge() {
  local wt="$1" target="${2:-main}"
  [[ -d "$wt" ]] || { echo "Error: Worktree not found: $wt" >&2; exit 1; }

  local branch; branch=$(git -C "$wt" branch --show-current 2>/dev/null) || {
    echo "Error: Could not determine branch" >&2; exit 1; }

  # Stash any uncommitted changes
  git -C "$wt" stash push -m "merge-stash-$(date +%s)" 2>/dev/null || true

  git checkout "$target" 2>&1 || { echo "Error: Failed to checkout $target" >&2; exit 1; }

  if git merge --no-ff "$branch" -m "Merge '$branch' into $target" 2>&1; then
    "$LOG" info "merge" "Merged '$branch' into '$target'" "$wt"
    echo "OK: Merged '$branch' into '$target'"
  else
    "$LOG" error "merge" "Conflict: '$branch' into '$target'" "$wt"
    echo "CONFLICT: $branch -> $target (run merge-conflict.sh detect $wt)" >&2
    exit 1
  fi
}

cmd_status() {
  local wf="$1" wt_base="${WORKTREE_BASE}/${1}" target="main"
  [[ -d "$wt_base" ]] || { echo "No worktrees for: $wf" >&2; exit 1; }

  for d in "$wt_base"/*/; do
    [[ -d "$d" ]] || continue; d="${d%/}"
    local branch; branch=$(git -C "$d" branch --show-current 2>/dev/null) || { echo "$(basename "$d"): UNKNOWN"; continue; }
    if git merge-base --is-ancestor "$branch" "$target" 2>/dev/null; then
      printf '%-20s  %-30s  MERGED\n' "$(basename "$d")" "$branch"
    else
      printf '%-20s  %-30s  PENDING\n' "$(basename "$d")" "$branch"
    fi
  done
}

[[ $# -ge 1 ]] || usage
action="$1"; shift
case "$action" in
  merge)  [[ $# -ge 1 ]] || usage; cmd_merge "$1" "${2:-}" ;;
  status) [[ $# -ge 1 ]] || usage; cmd_status "$1" ;;
  *) usage ;;
esac
