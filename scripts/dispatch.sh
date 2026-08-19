#!/usr/bin/env bash
# dispatch.sh — Agent dispatch with correlation ID injection
# Usage: ./dispatch.sh <workflow_id> <step_num> <agent_type> <prompt_file> [task_id]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat >&2 <<EOF
Usage: $0 <workflow_id> <step_num> <agent_type> <prompt_file> [task_id]
EOF
  exit 1
}

[[ $# -ge 4 ]] || usage

wf_id="$1" step="$2" agent="$3" prompt_file="$4" task_id="${5:-}"

# Validate step is numeric
[[ "$step" =~ ^[0-9]+$ ]] || { echo "Error: step_num must be numeric" >&2; exit 1; }

# Validate prompt file exists
[[ -f "$prompt_file" ]] || { echo "Error: Prompt file not found: $prompt_file" >&2; exit 1; }

# Generate correlation ID
corr_id=$("$SCRIPT_DIR/correlation.sh" generate "$wf_id" "$step" "$agent")

# Log dispatch event
"$SCRIPT_DIR/log.sh" info "dispatch" "Dispatching agent=$agent step=$step" "$corr_id"

# Agent type mapping
get_subagent_type() {
  case "$1" in
    explorer|explore)        echo "explore" ;;
    fixer|coder)             echo "fixer" ;;
    designer)                echo "designer" ;;
    oracle|reviewer)         echo "oracle" ;;
    librarian|researcher)    echo "librarian" ;;
    test-engineer|test)      echo "development/test-engineer" ;;
    devops)                  echo "development/devops-specialist" ;;
    scribe|content)          echo "content/scribe" ;;
    typescript|ts)           echo "development/typescript-pro" ;;
    refactor)                echo "development/refactoring-specialist" ;;
    mcp)                     echo "development/mcp-developer" ;;
    orchestrator|build)      echo "orchestration/build" ;;
    *)                       echo "general" ;;
  esac
}

subagent_type=$(get_subagent_type "$agent")
prompt=$(cat "$prompt_file")

# Invoke agent via opencode run
echo "$prompt" | opencode run \
  --agent "$subagent_type" \
  --auto \
  --format json \
  2>&1

exit_code=$?

# Build traceability JSON
dispatched_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
status="completed"
[[ $exit_code -ne 0 ]] && status="failed"

if [[ -n "$task_id" ]]; then
  printf '{"correlation_id":"%s","agent":"%s","subagent_type":"%s","prompt_file":"%s","task_id":"%s","dispatched_at":"%s","status":"%s"}\n' \
    "$corr_id" "$agent" "$subagent_type" "$prompt_file" "$task_id" "$dispatched_at" "$status"
else
  printf '{"correlation_id":"%s","agent":"%s","subagent_type":"%s","prompt_file":"%s","dispatched_at":"%s","status":"%s"}\n' \
    "$corr_id" "$agent" "$subagent_type" "$prompt_file" "$dispatched_at" "$status"
fi

exit $exit_code
