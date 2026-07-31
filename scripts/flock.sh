#!/usr/bin/env bash
# flock.sh — Atomic file lock via PID-based lockfile
# Usage: ./flock.sh <lockfile> <command> [args...]
set -euo pipefail

STALE_THRESHOLD=1800  # 30 minutes in seconds

usage() {
  echo "Usage: $0 <lockfile> <command> [args...]" >&2
  exit 1
}

# Early exit: need at least lockfile + command
[[ $# -ge 2 ]] || usage

lockfile="$1"; shift
command="$1"; shift

# Create lockfile parent dir if needed
mkdir -p "$(dirname "$lockfile")" 2>/dev/null || true

cleanup() {
  rm -f "$lockfile"
}
trap cleanup EXIT

# Check existing lock
if [[ -f "$lockfile" ]]; then
  locked_pid=$(head -1 "$lockfile" 2>/dev/null || echo "")
  if [[ -n "$locked_pid" ]]; then
    # Check if process still alive (works on MSYS2/Git Bash)
    if kill -0 "$locked_pid" 2>/dev/null; then
      # Check staleness
      lock_time=$(sed -n '2p' "$lockfile" 2>/dev/null || echo "0")
      now=$(date +%s)
      age=$(( now - lock_time ))
      if [[ $age -lt $STALE_THRESHOLD ]]; then
        echo "Error: Lock held by PID $locked_pid (${age}s old, threshold ${STALE_THRESHOLD}s)" >&2
        exit 1
      fi
      echo "Warning: Breaking stale lock from PID $locked_pid (${age}s old)" >&2
    fi
  fi
fi

# Acquire lock
printf '%s\n%s\n' "$$" "$(date +%s)" > "$lockfile"

# Run command, propagate exit code
"$command" "$@"
exit_code=$?
exit $exit_code
