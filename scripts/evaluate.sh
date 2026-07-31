#!/usr/bin/env bash
# evaluate.sh — Evaluator-optimizer: scores implementation quality across dimensions
# Usage: ./evaluate.sh <workflow_id> <worktree_path> [--iteration N]
set -euo pipefail

HAS_JQ=false; command -v jq &>/dev/null && HAS_JQ=true
usage() { echo "Usage: $0 <workflow_id> <worktree_path> [--iteration N]" >&2; exit 1; }
[[ $# -ge 2 ]] || usage
wf="$1"; worktree="$2"; iteration=0
[[ "${3:-}" == "--iteration" && -n "${4:-}" ]] && iteration="$4"
[[ -d "$worktree" ]] || { echo "Error: '$worktree' not found" >&2; exit 1; }

# Score a dimension 0-10 via heuristic
score_dim() {
  local label="$1" pattern="$2" path="$3"
  local hits=0 total=0
  if [[ -d "$path" ]]; then
    total=$(find "$path" -type f \( -name '*.sh' -o -name '*.js' -o -name '*.ts' -o -name '*.py' \) 2>/dev/null | wc -l)
    hits=$(grep -rlE "$pattern" "$path" 2>/dev/null | wc -l)
  fi
  if (( total == 0 )); then echo 5; return; fi
  local pct=$(( hits * 100 / total ))
  # Invert: more hits of anti-pattern = lower score
  if [[ "$label" == "clarity" || "$label" == "minimalism" ]]; then
    (( pct > 50 )) && echo 3 && return
    (( pct > 20 )) && echo 6 && return
    echo 8
  else
    (( pct > 50 )) && echo 8 && return
    (( pct > 20 )) && echo 6 && return
    echo 3
  fi
}

# Correctness: error handling patterns
s_correctness=$(score_dim "correctness" '(exit [1-9]|die|panic|throw|catch|\berr\b)' "$worktree")
# Robustness: input validation
s_robustness=$(score_dim "robustness" '(\[\s*-z|\[\s*-n|check|validate|require|usage\(\))' "$worktree")
# Clarity: short names vs long names
s_clarity=$(score_dim "clarity" '(\btmp\b|\bx\b|\bi\b|\bj\b|\bval\b)' "$worktree")
# Philosophy: early exit, guard clauses
s_philosophy=$(score_dim "philosophy" '(return [0-9]|exit [0-9]|usage\(\)|die )' "$worktree")
# Minimalism: dead code markers
s_minimalism=$(score_dim "minimalism" '(TODO|FIXME|HACK|DEPRECATED|unused)' "$worktree")

# Weighted total (0-100)
total=$(echo "scale=1; ($s_correctness*30 + $s_robustness*25 + $s_clarity*20 + $s_philosophy*15 + $s_minimalism*10) / 100" | bc 2>/dev/null || echo 50)
# Clamp
total_int=${total%.*}; total_int=${total_int:-50}
(( total_int > 10 )) && total_int=10
(( total_int < 0 )) && total_int=0

# Recommendation
rec="REJECT"; (( $(echo "$total >= 8" | bc -l 2>/dev/null || echo 0) )) && rec="SHIP"
(( $(echo "$total >= 6 && $total < 8" | bc -l 2>/dev/null || echo 0) )) && rec="OPTIMIZE"

# Cap iterations
if (( iteration >= 3 )); then
  rec="ESCALATE"
  echo "{\"workflow\":\"$wf\",\"iteration\":$iteration,\"recommendation\":\"ESCALATE\",\"reason\":\"Max iterations reached\"}"
  exit 0
fi

escape_json() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; echo "$s"; }

result="{\"workflow\":\"$(escape_json "$wf")\",\"correctness\":$s_correctness,\"robustness\":$s_robustness,\"clarity\":$s_clarity,\"philosophy\":$s_philosophy,\"minimalism\":$s_minimalism,\"total\":$total,\"recommendation\":\"$rec\",\"iteration\":$iteration}"

$HAS_JQ && echo "$result" | jq . || echo "$result"
