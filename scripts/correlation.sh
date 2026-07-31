#!/usr/bin/env bash
# correlation.sh — Workflow correlation ID generator
# Usage: ./correlation.sh {generate|parent} <args...>
set -euo pipefail

gen_uuid8() {
  # 8-char hex UUID from /dev/urandom or $RANDOM fallback
  if [[ -r /dev/urandom ]]; then
    head -c 8 /dev/urandom | xxd -p | head -c 8
  else
    printf '%04x%04x' $(( RANDOM * RANDOM )) $(( RANDOM * RANDOM )) | head -c 8
  fi
}

usage() {
  cat >&2 <<EOF
Usage:
  $0 generate <workflow_id> <step_num> <agent_type>
  $0 parent   <workflow_id>
EOF
  exit 1
}

[[ $# -ge 1 ]] || usage
action="$1"; shift

case "$action" in
  generate)
    [[ $# -ge 3 ]] || usage
    wf_id="$1" step="$2" agent="$3"
    # Validate step is numeric
    [[ "$step" =~ ^[0-9]+$ ]] || { echo "Error: step_num must be numeric" >&2; exit 1; }
    uuid=$(gen_uuid8)
    printf 'wf-%s-step-%s-agent-%s\n' "$uuid" "$step" "$agent"
    ;;
  parent)
    [[ $# -ge 1 ]] || usage
    wf_id="$1"
    uuid=$(gen_uuid8)
    printf 'wf-%s-step-0-parent\n' "$uuid"
    ;;
  *) usage ;;
esac
