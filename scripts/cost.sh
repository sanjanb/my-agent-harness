#!/usr/bin/env bash
# cost.sh — Per-agent and per-workflow cost tracking
# Usage: ./cost.sh {record|report|rate} <args...>
set -euo pipefail
CD=".opencode/workflows"
declare -A IR=( ["opus-4"]=15 ["sonnet-4"]=3 ["haiku"]=0.50 )
declare -A OR=( ["opus-4"]=75 ["sonnet-4"]=15 ["haiku"]=2.50 )
usage() { echo "Usage: $0 {record|report|rate} <args...>" >&2; exit 1; }
cf() { echo "${CD}/${1}/costs.jsonl"; }
ensure_wf() { [[ -d "${CD}/${1}" ]] || { echo "Error: Workflow '$1' not found" >&2; exit 1; }; }

cmd_record() {
  [[ $# -ge 5 ]] || usage
  local wf="$1" agent="$2" model="$3" in_tok="$4" out_tok="$5"
  [[ "$in_tok" =~ ^[0-9]+$ ]] && [[ "$out_tok" =~ ^[0-9]+$ ]] || { echo "Error: tokens must be numeric" >&2; exit 1; }
  ensure_wf "$wf"
  local in_r="${IR[$model]:-0}" out_r="${OR[$model]:-0}"
  local cost; cost=$(awk "BEGIN { printf \"%.6f\", ($in_tok * $in_r + $out_tok * $out_r) / 1000000 }")
  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p "$(dirname "$(cf "$wf")")" 2>/dev/null || true
  printf '{"agent":"%s","model":"%s","input_tokens":%s,"output_tokens":%s,"cost_usd":%s,"timestamp":"%s"}\n' \
    "$agent" "$model" "$in_tok" "$out_tok" "$cost" "$ts" >> "$(cf "$wf")"
  echo "$cost"
}

cmd_report() {
  [[ $# -ge 1 ]] || usage; ensure_wf "$1"
  local f; f=$(cf "$1")
  [[ -f "$f" ]] || { echo '{"total_usd":0,"by_agent":{},"by_model":{},"entries":0}'; return; }
  awk -F'"' '{
    for(i=1;i<=NF;i++){
      if($i=="agent") agent=$(i+2)
      if($i=="model") model=$(i+2)
      if($i=="cost_usd") cost=$(i+2)+0
    }
    total+=cost; by_agent[agent]+=cost; by_model[model]+=cost; n++
  }END{
    printf "{\"total_usd\":%.6f,\"entries\":%d,\"by_agent\":{",total,n
    first=1; for(a in by_agent){if(!first)printf",";printf"\"%s\":%.6f",a,by_agent[a];first=0}
    printf"},\"by_model\":{"
    first=1; for(m in by_model){if(!first)printf",";printf"\"%s\":%.6f",m,by_model[m];first=0}
    printf"}}\n"
  }' "$f"
}

cmd_rate() {
  [[ $# -ge 1 ]] || usage; local model="$1"
  [[ -v "IR[$model]" ]] || { echo "Error: Unknown model '$model'. Known: ${!IR[*]}" >&2; exit 1; }
  printf '{"model":"%s","input_per_million":%s,"output_per_million":%s}\n' "$model" "${IR[$model]}" "${OR[$model]}"
}

[[ $# -ge 1 ]] || usage; action="$1"; shift
case "$action" in record) cmd_record "$@";; report) cmd_report "$@";; rate) cmd_rate "$@";; *) usage;; esac
