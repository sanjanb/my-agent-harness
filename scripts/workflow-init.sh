#!/usr/bin/env bash
# workflow-init.sh — Initialize a workflow with ID, budget, and state
# Usage: ./workflow-init.sh <workflow_name> [budget_tokens]
set -euo pipefail

DEFAULT_BUDGET=50000

usage() {
  echo "Usage: $0 <workflow_name> [budget_tokens]" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
name="$1"
budget="${2:-$DEFAULT_BUDGET}"

# Validate budget is numeric
[[ "$budget" =~ ^[0-9]+$ ]] || { echo "Error: budget_tokens must be numeric" >&2; exit 1; }

# Generate workflow ID
if [[ -r /dev/urandom ]]; then
  uuid=$(head -c 8 /dev/urandom | xxd -p | head -c 8)
else
  uuid=$(printf '%04x%04x' $(( RANDOM * RANDOM )) $(( RANDOM * RANDOM )) | head -c 8)
fi
wf_id="wf-${uuid}"

# Create workflow directory
wf_dir=".opencode/workflows/${wf_id}"
mkdir -p "$wf_dir" || { echo "Error: Failed to create $wf_dir" >&2; exit 1; }

# Create state.json
created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "${wf_dir}/state.json" <<EOF
{
  "id": "${wf_id}",
  "name": "${name}",
  "status": "initialized",
  "budget_tokens": ${budget},
  "spent_tokens": 0,
  "created_at": "${created_at}",
  "steps": [],
  "checkpoints": []
}
EOF

# Create logs.jsonl
touch "${wf_dir}/logs.jsonl"

# Output workflow ID
echo "$wf_id"
