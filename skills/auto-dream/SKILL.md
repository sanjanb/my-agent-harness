---
name: auto-dream
description: Background memory consolidation — digests session learnings into long-term conventions
---

# AutoDream

Background sub-agent that consolidates agent session memory into persistent conventions. Runs between sessions to deduplicate, merge, and clean learned conventions — like REM sleep for agent memory.

## Why This Exists

Agents learn project-specific patterns during work. Without consolidation:
- Duplicate conventions accumulate (5 entries saying the same thing)
- Stale conventions persist (contradict newer decisions)
- Convention file grows unbounded
- Agents read redundant entries, wasting context

AutoDream prevents this by periodically consolidating conventions into canonical, deduplicated entries.

**Research basis:**
- AutoDream (Feb 2026) — REM sleep analogy for agent memory consolidation
- Zylos Research — "Observer agent produces structured timestamped notes"
- LangMem SDK — "Automatic semantic deduplication"

## When to Run

| Trigger | Action |
|---------|--------|
| Workflow completes | Automatic consolidation |
| conventions.jsonl > 80 entries | Trigger consolidation |
| Manual `/auto-dream` command | On-demand run |
| After major refactors | Consolidate related entries |

## Process

### Step 1: Read Existing Conventions

```bash
cat .opencode/conventions.jsonl
```

Parse each line as JSON. Build index:
- Entry count
- Entries by tag
- Entries by agent
- Entries by date

### Step 2: Review Session Logs

Scan recent workflow outputs for patterns not yet in conventions:
- Agent discoveries (new utilities, naming patterns)
- Human corrections (Sanjan prefers X over Y)
- Anti-patterns identified (never use Z)

### Step 3: Dedup

Check for duplicate/similar conventions:

```bash
# Find entries about same topic
grep -i "kebab-case" .opencode/conventions.jsonl
```

**Dedup rules:**
| Situation | Action |
|-----------|--------|
| Exact text match | Remove older, keep newer |
| Same topic, different wording | Merge into single canonical entry |
| Contradicting conventions | Keep newer, mark older as superseded |
| Same topic, different agents | Merge, note both agent sources |

### Step 4: Stale Detection

Flag entries that are:
- Older than 90 days
- Never referenced by any agent session

Add `_stale: true` and `_staleReason` fields:

```json
{"date":"2026-04-01","agent":"fixer","convention":"Use Out-File","tags":["powershell"],"_stale":true,"_staleReason":"Contradicted by newer: Use Set-Content"}
```

**Stale entry lifecycle:**
- 0-90 days: Active
- 90-120 days: Flagged stale, excluded from reads
- 120+ days: Auto-removed

### Step 5: Consolidate Related Entries

Merge entries about the same topic into single canonical entries:

**Before (5 entries about naming):**
```jsonl
{"date":"2026-07-01","agent":"fixer","convention":"Use kebab-case for component files","tags":["naming"]}
{"date":"2026-07-05","agent":"designer","convention":"Components are PascalCase files","tags":["naming"]}
{"date":"2026-07-10","agent":"fixer","convention":"Component filenames use kebab-case","tags":["naming"]}
{"date":"2026-07-15","agent":"designer","convention":"Use PascalCase for component file names","tags":["naming"]}
{"date":"2026-07-20","agent":"fixer","convention":"kebab-case for .tsx files in src/components","tags":["naming","react"]}
```

**After (1 canonical entry):**
```jsonl
{"date":"2026-07-30","agent":"auto-dream","convention":"Component files: kebab-case for filenames, PascalCase for export names. Example: my-button.tsx exports MyButton.","tags":["naming","components"],"supersedes":"Use kebab-case for component files, Components are PascalCase files, Component filenames use kebab-case, Use PascalCase for component file names, kebab-case for .tsx files in src/components"}
```

### Step 6: Write Consolidated Conventions

```bash
# Backup original
cp .opencode/conventions.jsonl .opencode/conventions.jsonl.bak

# Write consolidated version
# (replaces file, not append)
```

### Step 7: Generate Report

```markdown
## AutoDream Consolidation Report

**Date:** 2026-07-30
**Entries before:** 85
**Entries after:** 42

### Actions Taken
- **Merged:** 15 duplicate entries → 3 canonical entries
- **Superseded:** 8 outdated entries → 4 updated entries
- **Flagged stale:** 5 entries (> 90 days, never referenced)
- **Removed:** 2 entries (> 120 days, already stale)

### Canonical Entries Created
1. [naming] Component files: kebab-case filenames, PascalCase exports
2. [powershell] Use Set-Content not Out-File for .ps1 files
3. [typescript] Never use `any` — use `unknown` + type guard

### Stale Entries (excluded from reads)
- [2026-04-01] Use Out-File for PowerShell (contradicted by Set-Content)
- [2026-03-15] Use var instead of let (contradicted by code-philosophy)

### Health
- Convention file size: 42 entries (healthy)
- Next consolidation recommended: 2026-08-30
```

## Integration with Shared Context

When agents read conventions:
- Stale entries (`_stale: true`) are excluded
- Superseded entries are excluded
- Only active, canonical entries are loaded

When agents write conventions:
- AutoDream runs after workflow completes
- New entries are consolidated with existing

## Authority

**CAN:**
- Read conventions.jsonl
- Read session logs and workflow outputs
- Write consolidated conventions.jsonl
- Flag stale entries (add `_stale` field)
- Remove entries > 120 days old
- Backup before consolidation

**NEVER:**
- Modify project code
- Remove entries < 90 days old
- Change convention meaning (only consolidate wording)
- Override human-written conventions
- Run during active workflows (only between sessions)
- Consolidate entries from different projects

## Output Format

```markdown
## AutoDream Report
- **Before:** [count] entries
- **After:** [count] entries
- **Merged:** [count] duplicates → [count] canonical
- **Superseded:** [count] outdated → [count] updated
- **Stale flagged:** [count] entries
- **Removed:** [count] entries

## Canonical Entries
1. [tag] [convention text]
2. [tag] [convention text]

## Health
- [status message]
```

## Runtime Scripts

AutoDream uses these scripts:

- `scripts/auto-dream.sh` — Memory consolidation between sessions
- `scripts/convention.sh` — Reads/writes conventions
- `scripts/replay.sh` — Reads replay files for consolidation
- `scripts/log.sh` — Logs consolidation events
- `scripts/state.sh` — Reads workflow state
