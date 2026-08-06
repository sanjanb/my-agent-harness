#!/usr/bin/env bash
# orchestrate.sh — End-to-end workflow orchestration
# Chains: init → validate → execute → checkpoint → merge → cleanup
# Usage: ./orchestrate.sh <dag_file> [budget_tokens]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_BASE=".opencode/workflows"
WORKTREE_BASE=".opencode/worktrees"
DRY_RUN=false
VERBOSE=false

usage() {
  cat >&2 <<EOF
Usage: $0 <dag_file> [budget_tokens]

Options:
  --dry-run    Validate only, don't execute agents
  --verbose    Print step details
  --resume     Resume from latest checkpoint

DAG format (JSON):
  {"nodes": [
    {"id": "task1", "depends_on": [], "agent": "explorer", "prompt": "..."},
    {"id": "task2", "depends_on": ["task1"], "agent": "fixer", "prompt": "..."}
  ]}
EOF
  exit 1
}

# Parse flags
DAG_FILE=""
BUDGET=""
RESUME=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --verbose)  VERBOSE=true; shift ;;
    --resume)   RESUME=true; shift ;;
    -*)         echo "Unknown flag: $1" >&2; exit 1 ;;
    *)
      [[ -z "$DAG_FILE" ]] && DAG_FILE="$1" || BUDGET="${BUDGET:-50000}"
      shift ;;
  esac
done

[[ -n "$DAG_FILE" ]] || usage
[[ -f "$DAG_FILE" ]] || { echo "Error: DAG file not found: $DAG_FILE" >&2; exit 1; }
BUDGET="${BUDGET:-50000}"

log() {
  local level="$1"; shift
  "$SCRIPT_DIR/log.sh" "$level" "orchestrate" "$*"
}

step_log() {
  $VERBOSE && echo "  → $*" || true
}

# ── Phase 1: Initialize ──────────────────────────────────────────
echo "═══ Phase 1: Initialize ═══"

if $RESUME; then
  # Find existing workflow
  latest_wf=$(ls -td "$WORKFLOW_BASE"/wf-* 2>/dev/null | head -1)
  if [[ -n "$latest_wf" ]]; then
    wf_id=$(basename "$latest_wf")
    echo "Resuming workflow: $wf_id"
    latest_cp=$("$SCRIPT_DIR/checkpoint.sh" latest "$wf_id" 2>/dev/null) || true
    if [[ -n "$latest_cp" ]]; then
      completed=$(jq -r '.state.completed // ""' "$latest_cp")
      step_num=$(jq -r '.step' "$latest_cp")
      echo "Resumed from step $step_num, completed: $completed"
    fi
  else
    echo "No workflow to resume, starting fresh"
    RESUME=false
  fi
fi

if ! $RESUME; then
  wf_id=$("$SCRIPT_DIR/workflow-init.sh" "orchestrate" "$BUDGET")
  "$SCRIPT_DIR/task-board.sh" init "$wf_id" >/dev/null
  "$SCRIPT_DIR/budget.sh" init "$wf_id" "$BUDGET" >/dev/null
  completed=""
  step_num=0
  echo "Created workflow: $wf_id (budget: $BUDGET tokens)"
fi

log info "Workflow $wf_id started, budget=$BUDGET"

# ── Phase 2: Validate DAG ───────────────────────────────────────
echo "═══ Phase 2: Validate DAG ═══"

"$SCRIPT_DIR/dag-execute.sh" validate "$DAG_FILE" || {
  log error "DAG validation failed"
  exit 1
}

total_nodes=$(jq '.nodes | length' "$DAG_FILE")
echo "DAG valid: $total_nodes nodes"

# ── Phase 3: Execute Loop ───────────────────────────────────────
echo "═══ Phase 3: Execute ═══"

execution_order=$("$SCRIPT_DIR/dag-execute.sh" order "$DAG_FILE")
echo "Execution order: $execution_order"

failures=0
max_failures=3

IFS=',' read -ra ALL_TASKS <<< "$execution_order"

for task_id in "${ALL_TASKS[@]}"; do
  # Skip already completed (resume mode)
  if [[ ",$completed," == *",$task_id,"* ]]; then
    step_log "SKIP: $task_id (already completed)"
    continue
  fi

  step_num=$((step_num + 1))
  echo ""
  echo "── Step $step_num: $task_id ──"

  # Get task info
  agent=$(jq -r --arg id "$task_id" '.nodes[] | select(.id == $id) | .agent' "$DAG_FILE")
  prompt=$(jq -r --arg id "$task_id" '.nodes[] | select(.id == $id) | .prompt' "$DAG_FILE")

  step_log "Agent: $agent"
  step_log "Prompt: ${prompt:0:80}..."

  # Check budget
  budget_status=$("$SCRIPT_DIR/budget.sh" check "$wf_id" 2>/dev/null) || true
  if echo "$budget_status" | jq -e '.pct_used > 90' 2>/dev/null; then
    echo "  ⚠ Budget exhausted (>${budget_status}%), halting"
    log warn "Budget exhausted, halting at step $step_num"
    break
  fi

  # Claim on task board
  "$SCRIPT_DIR/task-board.sh" claim "$wf_id" "$task_id" "orchestrate" >/dev/null
  step_log "Claimed on task board"

  # Create worktree for isolation
  wt_dir=""
  if git rev-parse --git-dir >/dev/null 2>&1; then
    wt_dir=$("$SCRIPT_DIR/worktree.sh" create "$wf_id" "wt-${task_id}" 2>/dev/null) || true
    if [[ -n "$wt_dir" ]]; then
      step_log "Worktree: $wt_dir"
    fi
  fi

  # Save checkpoint before dispatch
  "$SCRIPT_DIR/checkpoint.sh" save "$wf_id" "$step_num" \
    "{\"completed\":\"${completed}\",\"current\":\"${task_id}\"}" >/dev/null

  # Dispatch or dry-run
  if $DRY_RUN; then
    echo "  [DRY RUN] Would dispatch: agent=$agent task=$task_id"
    result="dry-run"
  else
    # Write prompt to temp file for agent launcher
    prompt_file=$(mktemp /tmp/prompt-XXXXXX.md)
    echo "$prompt" > "$prompt_file"

    # Launch agent
    if "$SCRIPT_DIR/agent-launcher.sh" "$wf_id" "$step_num" "$agent" "$prompt_file" "$wt_dir"; then
      result="success"
      echo "  ✓ Completed"
    else
      result="failed"
      failures=$((failures + 1))
      echo "  ✗ Failed (failure $failures/$max_failures)"
      log error "Agent $agent failed on task $task_id"

      if [[ $failures -ge $max_failures ]]; then
        echo "  ⚠ Too many failures, aborting"
        log critical "Max failures reached, aborting workflow"
        break
      fi
    fi

    rm -f "$prompt_file"
  fi

  # Complete on task board
  "$SCRIPT_DIR/task-board.sh" complete "$wf_id" "$task_id" "$result" >/dev/null

  # Record budget spend (estimated)
  "$SCRIPT_DIR/budget.sh" spend "$wf_id" "$agent" 1000 >/dev/null 2>&1 || true

  # Update completed list
  completed="${completed:+${completed},}${task_id}"

  # Checkpoint after completion
  "$SCRIPT_DIR/checkpoint.sh" save "$wf_id" "$step_num" \
    "{\"completed\":\"${completed}\",\"current\":\"${task_id}\",\"result\":\"${result}\"}" >/dev/null

  log info "Step $step_num: $task_id → $result"
done

# ── Phase 4: Merge ─────────────────────────────────────────────
echo ""
echo "═══ Phase 4: Merge ═══"

wt_base="${WORKTREE_BASE}/${wf_id}"
if [[ -d "$wt_base" ]]; then
  merge_errors=0
  for wt in "$wt_base"/*/; do
    [[ -d "$wt" ]] || continue
    wt_name=$(basename "$wt")
    if $DRY_RUN; then
      echo "  [DRY RUN] Would merge: $wt_name"
    else
      if "$SCRIPT_DIR/merge.sh" merge "$wt" "main" 2>&1; then
        echo "  ✓ Merged: $wt_name"
      else
        echo "  ✗ Merge conflict: $wt_name"
        merge_errors=$((merge_errors + 1))
      fi
    fi
  done

  if [[ $merge_errors -gt 0 ]]; then
    echo "  ⚠ $merge_errors merge conflict(s) — run: $SCRIPT_DIR/merge-conflict.sh detect $wf_id"
  fi
else
  echo "  No worktrees to merge"
fi

# ── Phase 5: Cleanup ───────────────────────────────────────────
echo "═══ Phase 5: Cleanup ═══"

if $DRY_RUN; then
  echo "  [DRY RUN] Would cleanup workflow $wf_id"
else
  "$SCRIPT_DIR/cleanup.sh" "$wf_id" 2>&1 || true
  echo "  Cleaned up: $wf_id"
fi

# ── Summary ─────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "Workflow: $wf_id"
echo "Steps: $step_num"
echo "Completed: $(echo "$completed" | tr ',' '\n' | grep -c . || echo 0)"
echo "Failures: $failures"
budget_used=$("$SCRIPT_DIR/budget.sh" report "$wf_id" 2>/dev/null | jq -r '[.spent | to_entries[].value] | add // 0' 2>/dev/null || echo 0)
echo "Budget: $budget_used tokens used"
echo "═══════════════════════════════════════"

log info "Workflow $wf_id complete: $step_num steps, $failures failures"
