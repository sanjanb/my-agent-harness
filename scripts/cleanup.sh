#!/usr/bin/env bash
# cleanup.sh — Post-merge cleanup of worktrees, branches, and state
# Usage: ./cleanup.sh <workflow_id> [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKTREE_BASE=".opencode/worktrees"
WORKFLOW_BASE=".opencode/workflows"
LOG="$SCRIPT_DIR/log.sh"

usage() { echo "Usage: $0 <workflow_id> [--force]" >&2; exit 1; }
[[ $# -ge 1 ]] || usage

wf="$1"; force=false; [[ "${2:-}" == "--force" ]] && force=true
wt_base="${WORKTREE_BASE}/${wf}"; wf_dir="${WORKFLOW_BASE}/${wf}"
[[ -d "$wt_base" ]] || { echo "No worktrees for: $wf"; exit 0; }

errors=0
for d in "$wt_base"/*/; do
  [[ -d "$d" ]] || continue; d="${d%/}"

  # Check merge status unless forced
  if ! $force; then
    local_branch=$(git -C "$d" branch --show-current 2>/dev/null) || true
    if [[ -n "$local_branch" ]] && ! git merge-base --is-ancestor "$local_branch" "main" 2>/dev/null; then
      echo "SKIP: $(basename "$d") (not merged)" >&2
      "$LOG" warn "cleanup" "Skipped unmerged: $d"
      errors=$((errors+1)); continue
    fi
  fi

  # Remove worktree, then branch
  if git worktree remove "$d" 2>/dev/null; then
    "$LOG" info "cleanup" "Removed worktree: $d"
  elif git worktree remove --force "$d" 2>/dev/null; then
    "$LOG" info "cleanup" "Force-removed worktree: $d"
  else
    echo "ERROR: Could not remove $d" >&2; errors=$((errors+1)); continue
  fi
  [[ -n "${local_branch:-}" ]] && git branch -D "$local_branch" 2>/dev/null || true
done

rmdir "$wt_base" 2>/dev/null || true

# Remove state/checkpoints, keep logs
if [[ -d "$wf_dir" ]]; then
  rm -rf "${wf_dir}/checkpoints" 2>/dev/null || true
  rm -f  "${wf_dir}/state.json" "${wf_dir}/state.json.bak" 2>/dev/null || true
  rmdir "$wf_dir" 2>/dev/null || true
  "$LOG" info "cleanup" "Removed state for $wf"
fi

[[ $errors -gt 0 ]] && { echo "Cleanup: $errors error(s)" >&2; exit 1; }
echo "Cleanup complete for $wf"
