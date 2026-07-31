#!/usr/bin/env bash
# load-context.sh — Load all context for an agent session
# Usage: ./load-context.sh <agent_type> [workflow_id]
set -euo pipefail

HAS_JQ=false; command -v jq &>/dev/null && HAS_JQ=true
usage() { echo "Usage: $0 <agent_type> [workflow_id]" >&2; exit 1; }
[[ $# -ge 1 ]] || usage
agent_type="$1"; workflow_id="${2:-}"

escape_json() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; echo "$s"; }

echo "=== Context for agent: $agent_type ==="
echo ""

# 1. Shared conventions
echo "## Shared Conventions"
conv_file=".opencode/conventions.jsonl"
if [[ -f "$conv_file" ]]; then
  if $HAS_JQ; then
    jq -r '.key + " = " + .value' "$conv_file" 2>/dev/null | head -20
  else
    cat "$conv_file" | head -20
  fi
else
  echo "(none)"
fi
echo ""

# 2. Project conventions
echo "## Project Conventions"
proj_conv=".opencode/project-conventions.jsonl"
if [[ -f "$proj_conv" ]]; then
  if $HAS_JQ; then
    jq -r '.key + " = " + .value' "$proj_conv" 2>/dev/null | head -20
  else
    cat "$proj_conv" | head -20
  fi
else
  echo "(none)"
fi
echo ""

# 3. Memory from auto-dream (if workflow_id provided)
if [[ -n "$workflow_id" ]]; then
  echo "## Memory (workflow: $workflow_id)"
  mem_file=".opencode/workflows/$workflow_id/memory.json"
  if [[ -f "$mem_file" ]]; then
    $HAS_JQ && jq -r '
      "Patterns: " + (.patterns | length | tostring),
      "Anti-patterns: " + (.anti_patterns | length | tostring),
      "Preferences: " + (.preferences | length | tostring),
      "Decisions: " + (.decisions | length | tostring),
      "Last consolidated: " + .last_consolidated
    ' "$mem_file" 2>/dev/null || cat "$mem_file"
  else
    echo "(no memory yet)"
  fi
  echo ""

  # 4. Budget status
  echo "## Budget Status"
  state_file=".opencode/workflows/$workflow_id/state.json"
  if [[ -f "$state_file" ]]; then
    if $HAS_JQ; then
      budget=$(jq -r '.budget_tokens // 0' "$state_file" 2>/dev/null)
      spent=$(jq -r '.spent_tokens // 0' "$state_file" 2>/dev/null)
      echo "Budget: $budget tokens | Spent: $spent tokens | Remaining: $((budget - spent))"
    else
      echo "(jq not available for budget)"
    fi
  else
    echo "(no workflow state)"
  fi
  echo ""

  # 5. Recent logs (last 10)
  echo "## Recent Logs"
  log_file=".opencode/workflows/$workflow_id/logs.jsonl"
  if [[ -f "$log_file" ]]; then
    if $HAS_JQ; then
      tail -10 "$log_file" | jq -r '[.level, .component, .msg] | join(" | ")' 2>/dev/null || tail -10 "$log_file"
    else
      tail -10 "$log_file"
    fi
  else
    echo "(no logs)"
  fi
  echo ""
fi
