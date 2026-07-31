#!/usr/bin/env bash
# budget.sh — Token budget management
# Usage: ./budget.sh {init|set-agent|check|spend|report} <args...>
set -euo pipefail
BD=".opencode/workflows"
usage() { echo "Usage: $0 {init|set-agent|check|spend|report} <args...>" >&2; exit 1; }
bf() { echo "${BD}/${1}/budget.json"; }
ensure_wf() { [[ -d "${BD}/${1}" ]] || { echo "Error: Workflow '$1' not found" >&2; exit 1; }; }
ensure_bf() { [[ -f "$(bf "$1")" ]] || { echo "Error: Budget not initialized for '$1'" >&2; exit 1; }; }
color() { (( $1 > 50 )) && echo GREEN || (( $1 > 25 )) && echo YELLOW || (( $1 > 10 )) && echo ORANGE || echo RED; }

cmd_init() {
  [[ $# -ge 2 ]] || usage
  local wf="$1" total="$2"
  [[ "$total" =~ ^[0-9]+$ ]] || { echo "Error: total_budget_tokens must be numeric" >&2; exit 1; }
  ensure_wf "$wf"
  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"total_budget":%s,"allocated":{},"spent":{},"created_at":"%s","updated_at":"%s"}\n' \
    "$total" "$ts" "$ts" > "$(bf "$wf")"
  echo "Budget initialized: $total tokens for $wf"
}

cmd_set_agent() {
  [[ $# -ge 3 ]] || usage
  local wf="$1" agent="$2" budget="$3"
  [[ "$budget" =~ ^[0-9]+$ ]] || { echo "Error: agent_budget must be numeric" >&2; exit 1; }
  ensure_bf "$wf"
  command -v jq &>/dev/null || { echo "Error: jq required" >&2; exit 1; }
  local f ts tmp; f=$(bf "$wf"); ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ"); tmp=$(mktemp)
  jq --arg a "$agent" --argjson b "$budget" --arg t "$ts" \
    '.allocated[$a] = $b | .updated_at = $t' "$f" > "$tmp" && mv "$tmp" "$f"
  echo "Agent '$agent' budget set to $budget tokens"
}

cmd_check() {
  [[ $# -ge 1 ]] || usage
  local wf="$1" agent="${2:-}"; ensure_bf "$wf"
  local f total; f=$(bf "$wf"); total=$(jq -r '.total_budget' "$f")
  if [[ -n "$agent" ]]; then
    local alloc spent; alloc=$(jq -r --arg a "$agent" '.allocated[$a] // 0' "$f")
    spent=$(jq -r --arg a "$agent" '.spent[$a] // 0' "$f")
    [[ "$alloc" == "0" ]] && { echo "No budget for agent '$agent'" >&2; exit 1; }
    local pct=$(( (spent * 100) / alloc ))
    printf '{"agent":"%s","allocated":%s,"spent":%s,"remaining":%s,"pct_used":%s,"status":"%s"}\n' \
      "$agent" "$alloc" "$spent" "$(( alloc - spent ))" "$pct" "$(color $(( 100 - pct )))"
  else
    local ts; ts=$(jq '[.spent | to_entries[].value] | add // 0' "$f")
    local pct=$(( (ts * 100) / total ))
    printf '{"total":%s,"spent":%s,"remaining":%s,"pct_used":%s,"status":"%s"}\n' \
      "$total" "$ts" "$(( total - ts ))" "$pct" "$(color $(( 100 - pct )))"
  fi
}

cmd_spend() {
  [[ $# -ge 3 ]] || usage
  local wf="$1" agent="$2" tokens="$3"
  [[ "$tokens" =~ ^[0-9]+$ ]] || { echo "Error: tokens_used must be numeric" >&2; exit 1; }
  ensure_bf "$wf"
  local f ts tmp; f=$(bf "$wf"); ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ"); tmp=$(mktemp)
  jq --arg a "$agent" --argjson t "$tokens" --arg ts "$ts" \
    '.spent[$a] = ((.spent[$a] // 0) + $t) | .updated_at = $ts' "$f" > "$tmp" && mv "$tmp" "$f"
  echo "Recorded $tokens tokens for agent '$agent'"
}

cmd_report() { [[ $# -ge 1 ]] || usage; ensure_bf "$1"; cat "$(bf "$1")"; }

[[ $# -ge 1 ]] || usage; action="$1"; shift
case "$action" in
  init) cmd_init "$@";; set-agent) cmd_set_agent "$@";; check) cmd_check "$@";;
  spend) cmd_spend "$@";; report) cmd_report "$@";; *) usage;;
esac
