#!/usr/bin/env bash
# dag-execute.sh — DAG validation, topological sort, ready-task detection
# Usage: ./dag-execute.sh {validate|order|next} <args...>
set -euo pipefail

HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true
require_jq() { $HAS_JQ || { echo "Error: jq required" >&2; exit 1; }; }
usage() { echo "Usage: $0 {validate|order|next} <args...>" >&2; exit 1; }

jq_remove_node() {
  jq --arg id "$1" '.nodes = [.nodes[] | select(.id != $id) | .depends_on = [.depends_on[]? | select(. != $id)]]' "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

validate_dag() {
  local f="$1"
  [[ -f "$f" ]] || { echo "Error: DAG file not found: $f" >&2; exit 1; }
  require_jq
  jq empty "$f" 2>/dev/null || { echo "Error: Invalid JSON" >&2; exit 1; }
  local n; n=$(jq '.nodes | length' "$f")
  [[ "$n" -gt 0 ]] || { echo "Error: DAG has no nodes" >&2; exit 1; }
  local ids; ids=$(jq -r '.nodes[].id' "$f" | sort)
  local errors=0
  while IFS= read -r nid; do
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      echo "$ids" | grep -qxF "$dep" || { echo "Error: '$nid' depends on unknown '$dep'" >&2; errors=$((errors+1)); }
    done <<< "$(jq -r --arg id "$nid" '.nodes[] | select(.id == $id) | .depends_on // [] | .[]' "$f")"
  done <<< "$ids"
  # Cycle detection via Kahn's algorithm
  local tmp; tmp=$(mktemp); cp "$f" "$tmp"; local removed=0
  while true; do
    local leaves; leaves=$(jq -r '[.nodes[] | select((.depends_on // []) | length == 0) | .id] | .[]' "$tmp" 2>/dev/null)
    [[ -z "$leaves" ]] && break
    while IFS= read -r leaf; do [[ -z "$leaf" ]] && continue; jq_remove_node "$leaf" "$tmp"; removed=$((removed+1)); done <<< "$leaves"
  done
  rm -f "$tmp"
  [[ $removed -ne $n ]] && { echo "Error: Cycle detected ($removed/$n removable)" >&2; exit 1; }
  [[ $errors -eq 0 ]] || exit 1
  echo "DAG valid: $n nodes"
}

topo_order() {
  local f="$1"
  [[ -f "$f" ]] || { echo "Error: DAG file not found: $f" >&2; exit 1; }
  require_jq
  local tmp; tmp=$(mktemp); cp "$f" "$tmp"; local order=""
  while true; do
    local leaves; leaves=$(jq -r '[.nodes[] | select((.depends_on // []) | length == 0) | .id] | .[]' "$tmp" 2>/dev/null)
    [[ -z "$leaves" ]] && break
    while IFS= read -r leaf; do
      [[ -z "$leaf" ]] && continue
      order="${order:+$order,}$leaf"
      jq_remove_node "$leaf" "$tmp"
    done <<< "$leaves"
  done
  rm -f "$tmp"
  echo "$order"
}

ready_tasks() {
  local f="$1" completed_csv="$2"
  [[ -f "$f" ]] || { echo "Error: DAG file not found: $f" >&2; exit 1; }
  require_jq
  local cjson="[]"
  [[ -n "$completed_csv" ]] && cjson=$(echo "$completed_csv" | jq -R 'split(",") | map(select(length > 0))')
  jq --argjson c "$cjson" -r \
    '[.nodes[] | select((.depends_on // []) | all(. as $d | $c | index($d) != null)) | .id] | join(",")' "$f"
}

[[ $# -ge 2 ]] || usage
action="$1"; shift
case "$action" in
  validate) [[ $# -ge 1 ]] || usage; validate_dag "$1" ;;
  order)    [[ $# -ge 1 ]] || usage; topo_order "$1" ;;
  next)     [[ $# -ge 2 ]] || usage; ready_tasks "$1" "$2" ;;
  *) usage ;;
esac
