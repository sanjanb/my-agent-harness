#!/usr/bin/env bash
# agent-launcher.sh — Invoke agents with correlation tracking
# Usage: ./agent-launcher.sh <workflow_id> <step_num> <agent_type> <prompt_file> [worktree_dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: $0 <workflow_id> <step_num> <agent_type> <prompt_file> [worktree_dir]" >&2
  exit 1
}

[[ $# -ge 4 ]] || usage

wf_id="$1"
step="$2"
agent="$3"
prompt_file="$4"
worktree_dir="${5:-}"

# Validate
[[ "$step" =~ ^[0-9]+$ ]] || { echo "Error: step_num must be numeric" >&2; exit 1; }
[[ -f "$prompt_file" ]] || { echo "Error: Prompt file not found: $prompt_file" >&2; exit 1; }

# Generate correlation ID
corr_id=$("$SCRIPT_DIR/correlation.sh" generate "$wf_id" "$step" "$agent")

# Log dispatch
"$SCRIPT_DIR/log.sh" info "agent-launcher" "Launching agent=$agent step=$step corr=$corr_id" "$corr_id"

# Read prompt
prompt=$(cat "$prompt_file")

# Build agent-specific context
agent_context=""
if [[ -n "$worktree_dir" ]]; then
  agent_context="Working directory: $worktree_dir"
fi

# Agent type mapping (agent_type → subagent_type for task tool)
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

# Build the full prompt with context
full_prompt="$prompt"
if [[ -n "$agent_context" ]]; then
  full_prompt="${agent_context}

${prompt}"
fi

# Append correlation metadata
full_prompt="${full_prompt}

---
Correlation ID: $corr_id
Workflow: $wf_id
Step: $step
Agent: $agent"

# ── Dispatch Method Selection ───────────────────────────────────
# Method 1: Write to dispatch file for orchestrator to pick up
dispatch_file="${SCRIPT_DIR}/../.opencode/workflows/${wf_id}/dispatch-${step}.json"
mkdir -p "$(dirname "$dispatch_file")"

cat > "$dispatch_file" <<EOF
{
  "correlation_id": "$corr_id",
  "workflow_id": "$wf_id",
  "step": $step,
  "agent": "$agent",
  "subagent_type": "$subagent_type",
  "prompt_file": "$prompt_file",
  "worktree_dir": "$worktree_dir",
  "dispatched_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "pending"
}
EOF

echo "$dispatch_file"
