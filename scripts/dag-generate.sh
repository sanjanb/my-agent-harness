#!/usr/bin/env bash
# dag-generate.sh — Convert task list to DAG JSON
# Usage: ./dag-generate.sh <tasks_file> [output_file]
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 <tasks_file> [output_file]

Task file format (one task per line):
  task_id:agent_type:prompt_description[:depends_on,depends_on]

Examples:
  explore:explorer:Find all API endpoints and their patterns
  implement:fixer:Create /api/users endpoint[:explore]
  test:test-engineer:Write tests for /api/users[:implement]
  review:oracle:Review implementation quality[:implement]

Output: DAG JSON to stdout or file
EOF
  exit 1
}

[[ $# -ge 1 ]] || usage

tasks_file="$1"
output_file="${2:-}"
[[ -f "$tasks_file" ]] || { echo "Error: Tasks file not found: $tasks_file" >&2; exit 1; }

# Parse tasks
nodes=()
errors=0

while IFS= read -r line; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" == \#* ]] && continue

  # Parse: id:agent:prompt[:deps]
  # deps format: [:dep1,dep2] or empty
  # Split on [ to separate prompt from deps
  if [[ "$line" == *"["* ]]; then
    before="${line%%[*}"        # everything before first [
    deps="${line#*[}"          # everything after first [
    deps="${deps%\]}"          # strip trailing ]
    deps="${deps#:}"           # strip leading :
    IFS=':' read -r id agent prompt <<< "$before"
  else
    IFS=':' read -r id agent prompt <<< "$line"
    deps=""
  fi

  # Validate
  [[ -n "$id" ]] || { echo "Error: Missing task ID in line: $line" >&2; errors=$((errors+1)); continue; }
  [[ -n "$agent" ]] || { echo "Error: Missing agent for task '$id'" >&2; errors=$((errors+1)); continue; }
  [[ -n "$prompt" ]] || { echo "Error: Missing prompt for task '$id'" >&2; errors=$((errors+1)); continue; }

  # Build depends_on array
  depends_on="[]"
  if [[ -n "$deps" ]]; then
    IFS=',' read -ra dep_list <<< "$deps"
    depends_on=$(printf '%s\n' "${dep_list[@]}" | jq -R . | jq -s .)
  fi

  # Build node JSON
  node=$(jq -n \
    --arg id "$id" \
    --arg agent "$agent" \
    --arg prompt "$prompt" \
    --argjson depends_on "$depends_on" \
    '{id: $id, agent: $agent, prompt: $prompt, depends_on: $depends_on}')

  nodes+=("$node")
done < "$tasks_file"

[[ $errors -eq 0 ]] || { echo "Error: $errors parse error(s)" >&2; exit 1; }
[[ ${#nodes[@]} -gt 0 ]] || { echo "Error: No tasks found" >&2; exit 1; }

# Build DAG JSON
dag=$(printf '%s\n' "${nodes[@]}" | jq -s '{nodes: .}')

# Output
if [[ -n "$output_file" ]]; then
  echo "$dag" > "$output_file"
  echo "DAG written to: $output_file (${#nodes[@]} nodes)"
else
  echo "$dag"
fi
