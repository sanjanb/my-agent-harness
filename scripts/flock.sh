#!/usr/bin/env bash
# flock.sh — Atomic directory-based lock (mkdir is atomic on POSIX/NTFS)
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
  rm -rf "$lockfile"
}
trap cleanup EXIT

# Try to acquire lock atomically via mkdir
if ! mkdir "$lockfile" 2>/dev/null; then
  # Lock exists — check staleness
  lock_time_file="$lockfile/.timestamp"
  if [[ -f "$lock_time_file" ]]; then
    lock_time=$(cat "$lock_time_file" 2>/dev/null || echo "0")
    now=$(date +%s)
    age=$(( now - lock_time ))
    if [[ $age -ge $STALE_THRESHOLD ]]; then
      echo "Warning: Breaking stale lock (${age}s old, threshold ${STALE_THRESHOLD}s)" >&2
      rm -rf "$lockfile"
      mkdir "$lockfile"
    else
      echo "Error: Lock held (${age}s old, threshold ${STALE_THRESHOLD}s)" >&2
      exit 1
    fi
  else
    echo "Error: Lock directory exists" >&2
    exit 1
  fi
fi
echo "$(date +%s)" > "$lockfile/.timestamp"

# Run command, propagate exit code
"$command" "$@"
exit_code=$?
exit $exit_code
