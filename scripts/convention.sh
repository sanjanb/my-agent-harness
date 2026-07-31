#!/usr/bin/env bash
# convention.sh — Read/write agent-writable conventions from .opencode/conventions.jsonl
# Usage: ./convention.sh {add|get|list|search|consolidate} <args...>
set -euo pipefail

HAS_JQ=false; command -v jq &>/dev/null && HAS_JQ=true
CONV_FILE=".opencode/conventions.jsonl"

usage() {
  cat >&2 <<EOF
Usage:
  $0 add <key> <value> [source]
  $0 get <key>
  $0 list
  $0 search <term>
  $0 consolidate
EOF
  exit 1
}

escape_json() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; echo "$s"; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
ensure_file() { mkdir -p "$(dirname "$CONV_FILE")" 2>/dev/null || true; [[ -f "$CONV_FILE" ]] || touch "$CONV_FILE"; }
write_entry() { printf '{"key":"%s","value":"%s","source":"%s","timestamp":"%s","uses":1}\n' "$(escape_json "$1")" "$(escape_json "$2")" "$3" "$(now_iso)" >> "$CONV_FILE"; }

[[ $# -ge 1 ]] || usage
action="$1"; shift

case "$action" in
  add)
    [[ $# -ge 2 ]] || usage
    key="$1"; value="$2"; source="${3:-agent}"
    ensure_file
    if $HAS_JQ && [[ -s "$CONV_FILE" ]]; then
      updated=false; tmpf=$(mktemp)
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ek=$(echo "$line" | jq -r '.key // ""' 2>/dev/null)
        if [[ "$ek" == "$key" ]]; then
          uses=$(echo "$line" | jq -r '.uses // 0' 2>/dev/null)
          echo "$line" | jq --arg v "$value" --argjson u "$((uses+1))" '.value=$v|.uses=$u|.timestamp='"$(now_iso)"'' >> "$tmpf"
          updated=true
        else echo "$line" >> "$tmpf"; fi
      done < "$CONV_FILE"
      if $updated; then mv "$tmpf" "$CONV_FILE"; else rm -f "$tmpf"; write_entry "$key" "$value" "$source"; fi
    else write_entry "$key" "$value" "$source"; fi
    echo "Added: $key"
    ;;
  get)
    [[ $# -ge 1 ]] || usage
    ensure_file
    if $HAS_JQ; then grep "\"key\":\"$1\"" "$CONV_FILE" 2>/dev/null | tail -1 | jq -r '.value // empty' 2>/dev/null
    else grep "\"key\":\"$1\"" "$CONV_FILE" 2>/dev/null | tail -1 | sed 's/.*"value":"\([^"]*\)".*/\1/'; fi
    ;;
  list)
    ensure_file
    if $HAS_JQ; then echo "["; first=true
      while IFS= read -r line; do [[ -n "$line" ]] && { $first || echo ","; first=false; echo "$line"; }; done < "$CONV_FILE"; echo "]"
    else cat "$CONV_FILE"; fi
    ;;
  search)
    [[ $# -ge 1 ]] || usage
    ensure_file
    if $HAS_JQ; then echo "["; first=true
      while IFS= read -r line; do [[ -n "$line" ]] && echo "$line" | grep -qi "$1" 2>/dev/null && { $first || echo ","; first=false; echo "$line"; }; done < "$CONV_FILE"; echo "]"
    else grep -i "$1" "$CONV_FILE" 2>/dev/null || echo "[]"; fi
    ;;
  consolidate)
    ensure_file; $HAS_JQ || { echo "Error: consolidate requires jq" >&2; exit 1; }
    [[ -s "$CONV_FILE" ]] || { echo "Nothing to consolidate"; exit 0; }
    tmpf=$(mktemp)
    jq -s 'group_by(.key)|map(sort_by(.timestamp)|last|.uses=(map(.uses//0)|add))' "$CONV_FILE" > "$tmpf" 2>/dev/null
    : > "$CONV_FILE"; jq -c '.' "$tmpf" 2>/dev/null >> "$CONV_FILE" || true; rm -f "$tmpf"
    echo "Consolidated"
    ;;
  *) usage ;;
esac
