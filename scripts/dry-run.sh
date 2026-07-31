#!/usr/bin/env bash
# dry-run.sh — Simulate workflow execution without running agents
# Usage: ./dry-run.sh <dag_file> [workflow_id]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BD=".opencode/workflows"
HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

usage() { echo "Usage: $0 <dag_file> [workflow_id]" >&2; exit 1; }
require_jq() { $HAS_JQ || { echo "Error: jq required for dry-run" >&2; exit 1; }; }

[[ $# -ge 1 ]] || usage
dag_file="$1" wf_id="${2:-}"

# Validate DAG first
"$SCRIPT_DIR/dag-execute.sh" validate "$dag_file" || exit 1

# Get execution order
order=$("$SCRIPT_DIR/dag-execute.sh" order "$dag_file")
[[ -n "$order" ]] || { echo "Error: Empty execution order" >&2; exit 1; }

echo "=== DRY RUN ==="
echo "DAG: $dag_file"
[[ -n "$wf_id" ]] && echo "Workflow: $wf_id"
echo ""

# Token estimates (defaults — real values come from node config)
DEFAULT_INPUT_TOKENS=2000
DEFAULT_OUTPUT_TOKENS=500

total_tokens=0
total_cost=0
step_num=0

IFS=',' read -ra STEPS <<< "$order"
for step_id in "${STEPS[@]}"; do
  step_num=$((step_num + 1))

  # Extract node info from DAG
  node_json=$(command jq --arg id "$step_id" '.nodes[] | select(.id == $id)' "$dag_file" 2>/dev/null || echo "{}")
  agent=$(echo "$node_json" | jq -r '.agent // "unknown"')
  model=$(echo "$node_json" | jq -r '.model // "sonnet-4"')
  input_tok=$(echo "$node_json" | jq -r '.input_tokens // 0')
  output_tok=$(echo "$node_json" | jq -r '.output_tokens // 0')
  [[ "$input_tok" == "0" ]] && input_tok=$DEFAULT_INPUT_TOKENS
  [[ "$output_tok" == "0" ]] && output_tok=$DEFAULT_OUTPUT_TOKENS

  # Calculate step cost
  step_cost=$(awk "BEGIN { printf \"%.6f\", ($input_tok * 0.000003 + $output_tok * 0.000015) }" 2>/dev/null || echo "0")
  step_tokens=$((input_tok + output_tok))
  total_tokens=$((total_tokens + step_tokens))
  total_cost=$(awk "BEGIN { printf \"%.6f\", $total_cost + $step_cost }")

  # Check budget if workflow_id provided
  budget_ok="n/a"
  if [[ -n "$wf_id" ]]; then
    if "$SCRIPT_DIR/budget.sh" check "$wf_id" "$agent" &>/dev/null; then
      budget_ok="ok"
    else
      budget_ok="OVER"
    fi
  fi

  printf "  Step %d: %-15s  agent=%-12s  model=%-10s  tokens=%-8d  cost=\$%s  budget=%s\n" \
    "$step_num" "$step_id" "$agent" "$model" "$step_tokens" "$step_cost" "$budget_ok"
done

echo ""
echo "=== SUMMARY ==="
echo "Total steps: ${#STEPS[@]}"
echo "Total tokens: $total_tokens"
echo "Estimated cost: \$$total_cost"
[[ -n "$wf_id" ]] && echo "Budget check: completed"
echo ""
echo "Exit 0: plan is valid"
exit 0
