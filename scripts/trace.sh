#!/usr/bin/env bash
# trace.sh — Correlation trace across agents
# Usage: ./trace.sh {start|add|show|timeline} <args...>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

usage() {
  cat >&2 <<EOF
Usage:
  $0 start    <workflow_id> <correlation_id>
  $0 add      <workflow_id> <correlation_id> <agent_type> <operation> <status>
  $0 show     <workflow_id> <correlation_id>
  $0 timeline <workflow_id>
EOF
  exit 1
}

trace_file() { echo ".opencode/workflows/$1/trace.jsonl"; }
now_iso()    { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

[[ $# -ge 1 ]] || usage
action="$1"; shift

case "$action" in
  start)
    [[ $# -ge 2 ]] || usage
    wf="$1" corr="$2"
    dir=".opencode/workflows/$wf"
    mkdir -p "$dir" 2>/dev/null || true

    printf '{"correlation_id":"%s","agent":"orchestrator","operation":"workflow_start","status":"started","timestamp":"%s","duration_ms":0}\n' \
      "$corr" "$(now_iso)" >> "$(trace_file "$wf")"
    echo "Trace started: $corr"
    ;;

  add)
    [[ $# -ge 5 ]] || usage
    wf="$1" corr="$2" agent="$3" op="$4" status="$5"
    [[ -f "$(trace_file "$wf")" ]] || { echo "Error: Trace file not found. Run 'start' first." >&2; exit 1; }

    op_esc=$(escape_json "$op")
    printf '{"correlation_id":"%s","agent":"%s","operation":"%s","status":"%s","timestamp":"%s","duration_ms":0}\n' \
      "$corr" "$agent" "$op_esc" "$status" "$(now_iso)" >> "$(trace_file "$wf")"
    echo "Trace added: $corr/$agent/$op"
    ;;

  show)
    [[ $# -ge 2 ]] || usage
    wf="$1" corr="$2"
    f=$(trace_file "$wf")
    [[ -f "$f" ]] || { echo "Error: No trace file for $wf" >&2; exit 1; }

    if $HAS_JQ; then
      jq --arg c "$corr" 'select(.correlation_id == $c)' "$f" | jq -s '.'
    else
      grep "\"correlation_id\":\"$corr\"" "$f" || echo "No entries for $corr"
    fi
    ;;

  timeline)
    [[ $# -ge 1 ]] || usage
    f=$(trace_file "$1")
    [[ -f "$f" ]] || { echo "Error: No trace file for $1" >&2; exit 1; }

    if $HAS_JQ; then
      jq -s 'sort_by(.timestamp) | .[] | "\(.timestamp) [\(.status)] \(.agent)/\(.operation) (\(.duration_ms)ms)"' "$f"
    else
      sort "$f" || cat "$f"
    fi
    ;;

  *) usage ;;
esac
