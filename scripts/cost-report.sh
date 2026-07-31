#!/usr/bin/env bash
# cost-report.sh — Human-readable cost reports and budget status
# Usage: ./cost-report.sh <workflow_id> [--json] | summary [--json]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CD=".opencode/workflows"
usage() { echo "Usage: $0 <workflow_id> [--json] | summary [--json]" >&2; exit 1; }
is_summary() { [[ "$1" == "summary" ]]; }

workflow_report() {
  local wf="$1" json="$2" wf_dir="${CD}/${wf}"
  [[ -d "$wf_dir" ]] || { echo "Error: Workflow '$wf' not found" >&2; exit 1; }
  local bf="${wf_dir}/budget.json" cf="${wf_dir}/costs.jsonl"
  local total_budget=0 total_spent=0
  [[ -f "$bf" ]] && total_budget=$(jq -r '.total_budget // 0' "$bf") && \
    total_spent=$(jq '[.spent | to_entries[].value] | add // 0' "$bf" 2>/dev/null || echo 0)
  local costs='{"total_usd":0,"entries":0,"by_agent":{},"by_model":{}}'
  [[ -f "$cf" ]] && costs=$("$SCRIPT_DIR/cost.sh" report "$wf" 2>/dev/null || echo "$costs")
  local total_usd entries; total_usd=$(echo "$costs" | jq -r '.total_usd // 0'); entries=$(echo "$costs" | jq -r '.entries // 0')

  if [[ "$json" == "true" ]]; then
    jq -n --arg wf "$wf" --argjson b "$total_budget" --argjson s "$total_spent" --argjson c "$costs" \
      '{workflow:$wf,budget:{total_tokens:$b,spent_tokens:$s},costs:$c}'
  else
    echo "=== Cost Report: $wf ==="
    echo "Budget:    $total_budget tokens"
    echo "Spent:     $total_spent tokens"
    (( total_budget > 0 )) && echo "Util:      $(( (total_spent * 100) / total_budget ))%"
    echo "Cost:      \$$total_usd ($entries entries)"
    echo "Agents:"; echo "$costs" | jq -r '.by_agent | to_entries[] | "  \(.key): \(.value | . * 100 | round / 100)"'
    echo "Models:"; echo "$costs" | jq -r '.by_model | to_entries[] | "  \(.key): \(.value | . * 100 | round / 100)"'
  fi
}

summary_report() {
  local json="$1" total_budget=0 total_spent=0 total_usd=0 count=0
  for d in "${CD}"/wf-*; do
    [[ -d "$d" ]] || continue; local wf_id; wf_id=$(basename "$d")
    local bf="${d}/budget.json"
    if [[ -f "$bf" ]]; then
      total_budget=$(( total_budget + $(jq -r '.total_budget // 0' "$bf") ))
      total_spent=$(( total_spent + $(jq '[.spent | to_entries[].value] | add // 0' "$bf" 2>/dev/null || echo 0) ))
    fi
    local cf="${d}/costs.jsonl"
    if [[ -f "$cf" ]]; then
      local w_usd; w_usd=$("$SCRIPT_DIR/cost.sh" report "$wf_id" 2>/dev/null | jq -r '.total_usd // 0' || echo 0)
      total_usd=$(awk "BEGIN{printf\"%.6f\",$total_usd+$w_usd}")
    fi
    count=$(( count + 1 ))
  done
  if [[ "$json" == "true" ]]; then
    jq -n --argjson w "$count" --argjson b "$total_budget" --argjson s "$total_spent" --arg c "$total_usd" \
      '{total_workflows:$w,budget:{total_tokens:$b,spent_tokens:$s},total_cost_usd:($c|tonumber)}'
  else
    echo "=== Cost Summary ==="
    echo "Workflows: $count | Budget: $total_budget tokens | Spent: $total_spent tokens | Cost: \$$total_usd"
  fi
}

[[ $# -ge 1 ]] || usage; target="$1"; json="false"; [[ "${2:-}" == "--json" ]] && json="true"
if is_summary "$target"; then summary_report "$json"; else workflow_report "$target" "$json"; fi
