#!/usr/bin/env bash
# replay.sh — Session replay for debugging agent steps
# Usage: ./replay.sh {record|show|diff|prune} <args...>
set -euo pipefail

HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

usage() {
  echo "Usage: $0 {record|show|diff|prune} <args...>" >&2
  echo "  record <wf> <step> <agent> <input> <output>" >&2
  echo "  show   <wf> [step]" >&2
  echo "  diff   <wf> <step_a> <step_b>" >&2
  echo "  prune  <wf> [keep_count]" >&2
  exit 1
}

rdir() { echo ".opencode/workflows/$1/replay"; }
sfile() { echo "$(rdir "$1")/step-$2.json"; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

escape_json() {
  local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; echo "$s"
}

[[ $# -ge 1 ]] || usage
action="$1"; shift

case "$action" in
  record)
    [[ $# -ge 5 ]] || usage
    wf="$1" step="$2" agent="$3" input="$4" output="$5"
    [[ "$step" =~ ^[0-9]+$ ]] || { echo "Error: step_num must be numeric" >&2; exit 1; }
    mkdir -p "$(rdir "$wf")" 2>/dev/null || true
    printf '{"step":%s,"agent":"%s","timestamp":"%s","input":"%s","output":"%s","duration_ms":0,"tokens_used":0}\n' \
      "$step" "$agent" "$(now_iso)" "$(escape_json "$input")" "$(escape_json "$output")" > "$(sfile "$wf" "$step")"
    echo "Recorded step $step for $wf"
    ;;
  show)
    [[ $# -ge 1 ]] || usage
    wf="$1" step="${2:-}"
    dir=$(rdir "$wf")
    [[ -d "$dir" ]] || { echo "Error: No replays for $wf" >&2; exit 1; }
    if [[ -n "$step" ]]; then
      f=$(sfile "$wf" "$step"); [[ -f "$f" ]] || { echo "Error: Step $step not found" >&2; exit 1; }
      cat "$f"
    elif $HAS_JQ; then
      echo "["; first=true
      for f in "$dir"/step-*.json; do [[ -f "$f" ]] || continue; $first || echo ","; first=false; cat "$f"; done
      echo "]"
    else
      cat "$dir"/step-*.json 2>/dev/null || echo "No steps found"
    fi
    ;;
  diff)
    [[ $# -ge 3 ]] || usage
    fa=$(sfile "$1" "$2") fb=$(sfile "$1" "$3")
    [[ -f "$fa" ]] || { echo "Error: Step $2 not found" >&2; exit 1; }
    [[ -f "$fb" ]] || { echo "Error: Step $3 not found" >&2; exit 1; }
    if $HAS_JQ; then
      echo "--- Step $2 vs Step $3 ---"
      echo "[$2] input:  $(jq -r '.input' "$fa")"; echo "[$2] output: $(jq -r '.output' "$fa")"
      echo "[$3] input:  $(jq -r '.input' "$fb")"; echo "[$3] output: $(jq -r '.output' "$fb")"
    else
      echo "=== Step $2 ===" && cat "$fa"; echo "=== Step $3 ===" && cat "$fb"
    fi
    ;;
  prune)
    [[ $# -ge 1 ]] || usage
    wf="$1" keep="${2:-10}"; dir=$(rdir "$wf")
    [[ -d "$dir" ]] || { echo "No replays for $wf"; exit 0; }
    count=$(find "$dir" -name 'step-*.json' 2>/dev/null | wc -l)
    (( count <= keep )) && { echo "Nothing to prune ($count files)"; exit 0; }
    removed=0
    for f in $(ls -t "$dir"/step-*.json 2>/dev/null | tail -n +"$((keep + 1))"); do rm -f "$f" && removed=$((removed+1)); done
    echo "Pruned $removed replay(s), kept $keep"
    ;;
  *) usage ;;
esac
