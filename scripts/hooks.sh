#!/usr/bin/env bash
# hooks.sh — Run user-defined lifecycle hooks at workflow points
# Usage: ./hooks.sh <hook_name> <workflow_id> [extra_args...]
# Hook names: pre-workflow, post-workflow, pre-step, post-step, on-error, on-recovery
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR=".opencode/hooks"

usage() {
  cat >&2 <<EOF
Usage: $0 <hook_name> <workflow_id> [extra_args...]

Hook names:
  pre-workflow   - Before workflow starts
  post-workflow  - After workflow completes
  pre-step       - Before a step runs (extra_args: step_num agent_type)
  post-step      - After a step runs (extra_args: step_num agent_type result)
  on-error       - When a step fails (extra_args: step_num agent_type error)
  on-recovery    - After error recovery (extra_args: step_num agent_type)

Hooks are advisory — exit 0 regardless of hook result.
EOF
  exit 1
}

VALID_HOOKS="pre-workflow post-workflow pre-step post-step on-error on-recovery"

[[ $# -ge 2 ]] || usage
hook_name="$1" wf_id="$2"; shift 2
extra_args=("$@")

# Validate hook name
case " $VALID_HOOKS " in
  *" $hook_name "*) ;;
  *) echo "Error: Unknown hook '$hook_name'" >&2; echo "Valid hooks: $VALID_HOOKS" >&2; exit 1 ;;
esac

# Find hook script
hook_script="${HOOKS_DIR}/${hook_name}.sh"

if [[ ! -f "$hook_script" ]]; then
  # No hook defined — silently succeed
  exit 0
fi

if [[ ! -x "$hook_script" ]]; then
  echo "Warning: Hook '$hook_script' not executable, skipping" >&2
  exit 0
fi

# Set environment for hooks
export WORKFLOW_ID="$wf_id"
export CORRELATION_ID="${CORRELATION_ID:-}"
export STEP_NUM="${STEP_NUM:-}"
export AGENT_TYPE="${AGENT_TYPE:-}"

"$SCRIPT_DIR/log.sh" info "hooks" "running $hook_name wf=$wf_id" "$wf_id"

# Run hook with extra args — advisory, always exit 0
if "$hook_script" "$wf_id" "${extra_args[@]}" 2>&1; then
  "$SCRIPT_DIR/log.sh" info "hooks" "hook $hook_name succeeded" "$wf_id"
else
  "$SCRIPT_DIR/log.sh" warn "hooks" "hook $hook_name failed (advisory, continuing)" "$wf_id"
fi

exit 0
