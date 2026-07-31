#!/usr/bin/env bash
# quality-gate.sh — Quality checks on code changes → pass/fail JSON
# Usage: ./quality-gate.sh <workflow_id> <worktree_path> [--json]
set -euo pipefail

HAS_JQ=false; command -v jq &>/dev/null && HAS_JQ=true
usage() { echo "Usage: $0 <workflow_id> <worktree_path> [--json]" >&2; exit 1; }
[[ $# -ge 2 ]] || usage
wf="$1"; worktree="$2"; json_only=false; [[ "${3:-}" == "--json" ]] && json_only=true
[[ -d "$worktree" ]] || { echo "Error: '$worktree' not found" >&2; exit 1; }

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
escape_json() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; echo "$s"; }
cp() { echo '{"check":"'"$1"'","pass":'"$2"',"detail":"'"$(escape_json "$3")"'"}'; }

# Collect changed files
files=()
if [[ -d "$worktree/.git" ]]; then
  while IFS= read -r f; do files+=("$f"); done < <(cd "$worktree" && git diff --name-only HEAD 2>/dev/null || true)
else
  while IFS= read -r f; do files+=("$f"); done < <(find "$worktree" -type f \( -name '*.sh' -o -name '*.js' -o -name '*.ts' -o -name '*.py' \) 2>/dev/null || true)
fi

# 1. Compilation
c1_pass=true; c1_det="All syntax OK"
for f in "${files[@]}"; do
  [[ -f "$worktree/$f" && "$f" == *.sh ]] && ! bash -n "$worktree/$f" 2>/dev/null && { c1_pass=false; c1_det="Syntax error in $f"; break; }
done

# 2. Philosophy anti-patterns
c2_pass=true; c2_det="No anti-patterns"
for f in "${files[@]}"; do
  [[ -f "$worktree/$f" ]] && grep -qiE '(eval |while.*true\b)' "$worktree/$f" 2>/dev/null && { c2_pass=false; c2_det="Anti-pattern in $f"; break; }
done

# 3. Tests exist
c3_pass=false; c3_det="No test files"
for f in "${files[@]}"; do
  base="${f##*/}"
  [[ "$base" == test_* || "$base" == *_test.* || "$base" == *.test.* ]] && { c3_pass=true; c3_det="Test found: $f"; break; }
done

# 4. Style — file length
c4_pass=true; c4_det="Within limits"
for f in "${files[@]}"; do
  [[ -f "$worktree/$f" ]] && lines=$(wc -l < "$worktree/$f" 2>/dev/null || echo 0) && (( lines > 200 )) && { c4_pass=false; c4_det="$f: $lines lines (>200)"; break; }
done

# 5. Security
c5_pass=true; c5_det="No secrets"
for f in "${files[@]}"; do
  [[ -f "$worktree/$f" ]] && grep -qiE '(password|secret|api_key)\s*=\s*["'"'"'][^"'"'"']{8,}' "$worktree/$f" 2>/dev/null && { c5_pass=false; c5_det="Hardcoded secret in $f"; break; }
done

# 6. Scope — diff size
c6_pass=true; c6_det="Diff OK"
if [[ -d "$worktree/.git" ]]; then
  big=$(cd "$worktree" && git diff --numstat HEAD 2>/dev/null | awk '$1+$2>500{print $3; exit}')
  [[ -n "${big:-}" ]] && { c6_pass=false; c6_det="Diff >500 lines: $big"; }
fi

# 7. Minimalism — TODO/FIXME
c7_pass=true; c7_det="Clean"
for f in "${files[@]}"; do
  [[ -f "$worktree/$f" ]] && grep -qE '^\s*#.*(TODO|FIXME|HACK)' "$worktree/$f" 2>/dev/null && { c7_pass=false; c7_det="TODO/FIXME in $f"; break; }
done

# Score: ~15 per pass
score=0; for p in $c1_pass $c2_pass $c3_pass $c4_pass $c5_pass $c6_pass $c7_pass; do $p && score=$((score+15)); done
[[ $score -gt 100 ]] && score=100
rec="REJECT"; (( score >= 85 )) && rec="SHIP"; (( score >= 60 )) && (( score < 85 )) && rec="OPTIMIZE"

# Output
checks="$(cp compilation "$c1_pass" "$c1_det"),$(cp philosophy "$c2_pass" "$c2_det"),$(cp tests "$c3_pass" "$c3_det"),$(cp style "$c4_pass" "$c4_det"),$(cp security "$c5_pass" "$c5_det"),$(cp scope "$c6_pass" "$c6_det"),$(cp minimalism "$c7_pass" "$c7_det")"
result="{\"workflow\":\"$(escape_json "$wf")\",\"timestamp\":\"$(now_iso)\",\"score\":$score,\"recommendation\":\"$rec\",\"checks\":[$checks]}"
$HAS_JQ && echo "$result" | jq . || echo "$result"
