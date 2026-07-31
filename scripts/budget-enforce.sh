#!/usr/bin/env bash
# budget-enforce.sh — Budget enforcement before agent dispatch
# Usage: ./budget-enforce.sh {check|enforce} <workflow_id> <agent_type> [estimated_tokens]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BD=".opencode/workflows"
usage() { echo "Usage: $0 {check|enforce} <workflow_id> <agent_type> [tokens]" >&2; exit 1; }
bf() { echo "${BD}/${1}/budget.json"; }
color() { (( $1 > 50 )) && echo GREEN || (( $1 > 25 )) && echo YELLOW || (( $1 > 10 )) && echo ORANGE || echo RED; }

enforce_common() {
  local wf="$1" agent="$2" f
  f=$(bf "$wf")
  [[ -f "$f" ]] || { echo "0 RED 0"; return; }
  local total alloc spent rem pct
  total=$(jq -r '.total_budget' "$f")
  alloc=$(jq -r --arg a "$agent" '.allocated[$a] // 0' "$f")
  spent=$(jq -r --arg a "$agent" '.spent[$a] // 0' "$f")
  if [[ "$alloc" == "0" ]]; then
    spent=$(jq '[.spent | to_entries[].value] | add // 0' "$f")
    rem=$(( total - spent ))
  else
    rem=$(( alloc - spent ))
  fi
  pct=$(( (spent * 100) / (alloc > 0 ? alloc : total) ))
  echo "$rem" "$(color $(( 100 - pct )))" "$pct"
}

cmd_check() {
  [[ $# -ge 3 ]] || usage
  local wf="$1" agent="$2" est="$3"
  [[ "$est" =~ ^[0-9]+$ ]] || { echo "Error: estimated_tokens must be numeric" >&2; exit 1; }
  read -r rem color pct <<< "$(enforce_common "$wf" "$agent")"
  local allowed=true reason=""
  (( rem < est )) && allowed=false && reason="Estimated $est exceeds remaining $rem"
  printf '{"allowed":%s,"reason":"%s","remaining":%s,"budget_pct":"%s"}\n' "$allowed" "$reason" "$rem" "$color"
}

cmd_enforce() {
  [[ $# -ge 2 ]] || usage
  local wf="$1" agent="$2"
  read -r rem color pct <<< "$(enforce_common "$wf" "$agent")"
  "$SCRIPT_DIR/log.sh" info "budget-enforce" "agent=$agent status=$color remaining=$rem" "$wf" || true
  if [[ "$color" == "RED" ]] || [[ "$color" == "ORANGE" ]]; then
    printf '{"allowed":false,"reason":"Budget critical (%s used)","remaining":%s,"budget_pct":"%s"}\n' "$pct" "$rem" "$color"
    exit 1
  elif [[ "$color" == "YELLOW" ]]; then
    printf '{"allowed":true,"reason":"Budget warning (%s used)","remaining":%s,"budget_pct":"%s"}\n' "$pct" "$rem" "$color"
  else
    printf '{"allowed":true,"reason":"Within budget","remaining":%s,"budget_pct":"%s"}\n' "$rem" "$color"
  fi
}

[[ $# -ge 2 ]] || usage; action="$1"; shift
case "$action" in check) cmd_check "$@";; enforce) cmd_enforce "$@";; *) usage;; esac
