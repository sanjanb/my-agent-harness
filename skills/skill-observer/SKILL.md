---
name: skill-observer
description: >
  Monitors task execution for skill improvement opportunities. Use this skill
  during ANY multi-step task, agentic workflow, or substantive work session where
  the agent is using tools and producing deliverables. It captures patterns, user
  corrections, workflow insights, and methodology worth preserving as reusable
  skills. Also triggers during post-task feedback discussions and when the user
  explicitly mentions skill observations, improvements, the observation log,
  skill taxonomy, or asks the agent to watch for skill opportunities. Also known
  as "One Skill to Rule Them All" — trigger on this phrase too.
---

# Skill Observer

The meta-skill that builds and improves all your skills, including itself. Watches your work sessions, captures corrections and judgement calls, and turns them into skill improvements automatically.

Adapted from [rebelytics/one-skill-to-rule-them-all](https://github.com/rebelytics/one-skill-to-rule-them-all) for opencode's skill system and orchestration workflow.

## Core Mechanism

**Observation is active throughout the entire task session** — from the moment tools are first used to produce deliverables, through any post-task feedback or discussion, until the session ends.

### What to observe

1. **Active task execution** — creating documents, analysing websites, implementing structured data, writing code, building presentations, and similar substantive work.

2. **Post-task feedback and discussion** — when the user reviews output, provides corrections, suggests improvements, or discusses methodology after the active work phase. User feedback during these discussions is often the highest-signal input for skill improvement.

3. **Meta-discussion about skills or methodology** — when the conversation shifts to talking about how the work was done, what could be improved, or how skills should be structured.

### What NOT to do

**Mid-task work produces observations only; those observations get applied at the next review or by request.** The default is log, don't act.

Do not modify skill files during task execution unless the user explicitly asks. Do not create new skills mid-task unless the user explicitly asks.

---

## Observation Logging

**Path:** `[workspace folder]/skill-observations/log.md`

The workspace folder is your persistent workspace directory — the location where files survive between sessions. For opencode, this is typically `~/.config/opencode/` or the project root depending on context.

### Log File Structure

```markdown
# Skill Observation Log

Observations captured during task-oriented work.

**Status key:** OPEN = not yet actioned | ACTIONED (YYYY-MM-DD) = skill
updated/created | DECLINED (YYYY-MM-DD) = user decided not to pursue -
resolved statuses always carry their resolution date

---

## [Date]

### Observation 1: [Title]
**Status:** OPEN
[... full format ...]
```

### Per-Entry Format

Append to END only. `**Status:** OPEN` is the MANDATORY first field — entries without it are invisible to status-filtered passes.

```markdown
### Observation [N]: [Short descriptive title]

**Status:** OPEN
**Date:** [date]
**Session context:** [what task was being worked on]
**Skill:** [existing skill name, or "New skill candidate: [working name]"]
**Type:** [open-source | internal]
**Phase/Area:** [which part of the skill or workflow]

**Issue:** [What happened - specific enough to understand weeks later
without the original conversation.]

**Suggested improvement:** [Concrete change. For existing skills, name the
section or rule; for new skills, scope and key components.]

**Principle:** [The generalisable takeaway - the most important field.]
```

Optional: `**Reference file:**` line for session-local evidence saved to workspace first. For `type: open-source`, Principle must be fully generalised (no client names/domains).

### 3-Step Numbering Discipline (every append)

```bash
# 1. Pre-check - highest existing number, never trust session memory:
grep -oP '### Observation \K\d+' log.md | sort -n | tail -1

# 2. Pre-write collision assertion:
PROPOSED=$(( $(grep -oP '### Observation \K\d+' log.md | sort -n | tail -1) + 1 ))
grep -qE "^### Observation ${PROPOSED}:" log.md && { echo "COLLISION on #${PROPOSED}"; exit 1; }

# 3. Post-write verify: count occurrences of number; >1 = parallel collision
#    → renumber YOUR entry to max+1
```

### Log-Write Safety (shared-log concurrency rules)

- Backup first → re-read live log + diff vs snapshot immediately before any write-back
- Bounded entry-at-a-time mutation, NEVER DOTALL/greedy patterns across the multi-entry file
- Assert header count invariant against the LIVE pre-write file
- Verify own entries survived (grep each number written, exactly once)
- Status-only edit must use line-anchored multiline anchors only

### Enforcement Checkpoints

- Every 3rd TodoWrite completion (3rd, 6th, 9th...) MUST produce a log write — pending observations or an explicit `no observations` marker line
- Deliverable-event flush — `present_files`, deck/PDF render, staged skill hand-off, task/todo batch completion → flush before moving on

### Archival on Write (every log write)

Move resolved entries to `skill-observations/archive/log-[YYYY-MM-DD].md` (preserving log header in archive). Resolution decided by date read from file: `ACTIONED (YYYY-MM-DD)` / `DECLINED (YYYY-MM-DD)`; only entries whose recorded date is **before today** archive; same-day-resolved stay. Active log keeps: header, status key, all OPEN, same-day-resolved.

---

## Weekly Review Procedure

Trigger files:
- `skill-observations/last-review-date.txt` — value `never` (initial) or date review actually ran
- `skill-observations/scheduled-review-decline.txt` — user said no; suppresses offer 30 days
- `skill-observations/scheduler-registered.txt` — marker written ONLY after registration verified

### Steps 0–8

0. **Scheduled setup (fallback mode only)** — AFTER Step-1 no-observations short-circuit. Order: no OPEN obs + no principles → skip 0, just timestamp. Checks: decline file <30d? skip. Scheduler registered? skip. Offer → register → VERIFY registration succeeded before writing scheduler-registered.txt.

1. **Load** — archive prev-session resolved; read log. Build work queue from headers, NOT status grep. No OPEN obs + no principles → report, update timestamp, stop.

2. **Inventory skills** — from available skills in `~/.config/opencode/skills/`. Only user-owned custom skills updatable.

3. **Cross-check observations** — EVERY OPEN obs vs EVERY skill. Interactive: present all, await approval. Autonomous: apply approval policy.

4. **Cross-check principles** — flag every skill not complying with each active cross-cutting principle.

5. **Apply** — produce updated SKILL.md per skill: integrate into sections where they belong (NEVER append an observations list at bottom); preserve structure/voice/attribution.

6. **Mark ACTIONED** — status: `ACTIONED (YYYY-MM-DD) - Applied to [skill-name] (weekly review)`. Date is load-bearing for archival. Do NOT archive same-session.

7. **Timestamp** — write today's date to last-review-date.txt.

8. **Deliver & summarise** — stage, then present block; wait for acknowledgement.

### Approval Policy

- **Interactive:** always present grouped by skill (number, title, 1-sentence summary); flag judgment calls "needs your input"; wait for blanket/selective approval.
- **Scheduled autonomous:** apply non-escalated by default (safety = staging). Escalate w/o applying when: (1) NEW skill proposed; (2) removes/substantially restructures content; (3) self-flagged uncertainty; (4) two observations conflict.

### Delivery

Stage FULL skill dir to `[workspace folder]/skill-updates/[date]/[skill-name]/` (SKILL.md + references/, scripts/, assets/) — never SKILL.md alone. **Keep-two rule:** only 2 most recent date dirs under `skill-updates/`; delete older.

---

## Principle Propagation

**Path:** `[workspace folder]/skill-observations/cross-cutting-principles.md`

### Entry Condition

Observation's Principle applies to skills generally → log with `Skill: All skills`, surface it; user approves → add to file. That file is a **mandatory checklist during any skill creation or regeneration**.

### File Format

```markdown
# Cross-Cutting Principles

Principles that apply to all skills. Read as a mandatory checklist during
any skill creation or regeneration.

---

## Active Principles

### 1. [Principle title]
**Added:** [date]
**Applies to:** [all skills | all open-source skills | all skills with rules]
**Requirement:** [what it requires]
**Propagation:** [immediate | opportunistic]
**Status:** [active]
```

### Propagation Timing

- `immediate` → update all skills now (e.g. confidentiality rules)
- `opportunistic` → apply at each skill's next update

---

## Skill Improvement Workflow

### Act Only in 3 Contexts

1. Comprehensive review (weekly review)
2. Explicit user request ("update X skill", "act on observation #N")
3. In-session correction when a skill is producing wrong output

Otherwise: **log-and-defer** (default).

### Small vs Substantial

- **Small additive changes** (new rule, clarification, factual fix) → apply directly
- **Substantial** (restructuring, new capabilities, changed methodology) → understand full impact first

### Editing Rules (always start from live file)

1. Live file authoritative: `~/.config/opencode/skills/{skill}/SKILL.md`
2. Base edits on fresh read of live file — never workspace copy/draft/memory
3. Before overwriting staged copy: diff vs live; differ → rebase on live
4. Stage to `[workspace folder]/skill-updates/[date]/[skill-name]/` — FULL dir
5. Process rigour: complex/uncertain → careful analysis; internal with established requirements → write directly, flag substantial changes

### Status Transitions

- Applied in review: `ACTIONED (YYYY-MM-DD) - Applied to [skill-name] (weekly review)`
- Declined: `DECLINED (YYYY-MM-DD) - [reason]`
- `ACTIONED`/`DECLINED` without date → archival breaks

---

## Integration with opencode Orchestration

This skill works alongside opencode's workflow manager and specialist agents:

- **Observation logging** happens passively during normal task execution
- **Weekly review** can be triggered manually or via scheduled task
- **Specialist agents** (@fixer, @oracle, etc.) can contribute observations
- **Skill creation** uses opencode's skill system (`.opencode/skills/` or `~/.config/opencode/skills/`)

The skill does NOT:
- Override or conflict with the workflow manager's scheduling
- Require a separate skill-creator agent
- Use Claude-specific filesystem conventions

---

## Quick Reference

| Concept | Location |
|---------|----------|
| Observation log | `skill-observations/log.md` |
| Archive | `skill-observations/archive/log-[YYYY-MM-DD].md` |
| Cross-cutting principles | `skill-observations/cross-cutting-principles.md` |
| Last review date | `skill-observations/last-review-date.txt` |
| Skill updates staging | `skill-updates/[date]/[skill-name]/` |
| Skills directory | `~/.config/opencode/skills/` |
