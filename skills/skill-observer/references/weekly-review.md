# Weekly Skill Review Procedure

Detailed procedure for the weekly skill review. This is a reference file loaded on demand by the skill-observer SKILL.md.

## Trigger Files

- `skill-observations/last-review-date.txt` — value `never` (initial, written at setup) or date review actually ran. Missing file → recreate with `never`, never invent a date.
- `skill-observations/scheduled-review-decline.txt` — user said no; suppresses offer 30 days.
- `skill-observations/scheduler-registered.txt` — marker written ONLY after registration verified.
- `skill-observations/scheduled-task-draft.md` — draft prompt for the scheduled task.
- Scheduled task name: `weekly-skill-review`.

## Fallback Fires When

No scheduled review registered/succeeded in 7+ days AND last-review-date is `never`/>7 days old. Interactive = one-line offer only, never gates user's task. Scheduled = runs unprompted.

## Reachability Regimes (scheduled work)

1. **Shared filesystem** → scheduled mode works.
2. **Local-only fs + cloud scheduler** → physically broken, do NOT register; recommend calendar reminder + manual trigger, or sync log to reachable storage (git repo).
3. **Local-only fs + local scheduler** (cron/Task Scheduler) → works, user must keep agent runnable.

## Steps 0–8

### Step 0: Scheduled setup (fallback mode only)

AFTER the Step-1 no-observations short-circuit. Order: no OPEN obs + no principles → skip 0, just timestamp.

Checks:
- Decline file <30d? skip.
- Scheduler registered? skip.
- Regime 2? skip.

Offer → register (create-shortcut/set_scheduled_task; terminal: cron) named `weekly-skill-review` → VERIFY registration succeeded before writing scheduler-registered.txt. Unverified registration → no marker, tell user.

### Step 1: Load

Archive prev-session resolved; read log. Build work queue from headers, NOT status grep:

a. Enumerate all `### Observation N:` headers (authoritative list)
b. Classify each by `**Status:**` within body; missing/blank/non-ACTIONED/non-DECLINED = OPEN
c. Queue = headers minus ACTIONED/DECLINED

Reconciliation guard: assert count(headers) == count(status-classified); delta = statusless entries → triage as OPEN.

Read cross-cutting principles. No OPEN obs + no principles → report, update timestamp, stop.

### Step 2: Inventory skills

From `~/.config/opencode/skills/`. Only user-owned custom skills updatable. Read-only system skills: route obs to complementary `{system-skill}-extras` user skill holding the delta; create if needed.

### Step 3: Cross-check observations

EVERY OPEN obs vs EVERY skill (principles generalise), not just the named skill. Build skill → [observations].

Interactive: present all, await approval. Autonomous: apply approval policy.

### Step 4: Cross-check principles

Flag every skill not complying with each active cross-cutting principle.

### Step 5: Apply

Produce updated SKILL.md per skill: integrate into sections where they belong (NEVER append an observations list at bottom); preserve structure/voice/attribution. Follow skill-authoring editing rules.

### Step 6: Mark ACTIONED

Status: `ACTIONED (YYYY-MM-DD) - Applied to [skill-name] (weekly review)`. Date is load-bearing for archival. Do NOT archive same-session.

### Step 7: Timestamp

Write today's date to last-review-date.txt.

### Step 8: Deliver & summarise

Stage, then present block (see format below); wait for acknowledgement.

## Approval Policy

- **Interactive:** always present grouped by skill (number, title, 1-sentence summary); flag judgment calls "needs your input"; wait for blanket/selective approval.
- **Scheduled autonomous:** apply non-escalated by default (safety = staging). **Escalate w/o applying** when: (1) NEW skill proposed; (2) removes/substantially restructures content; (3) self-flagged uncertainty; (4) two observations conflict. Scheduled run still applies every non-escalated item.

## Summary Format (Step 8)

```
## Weekly Skill Review Complete - [date]

Updated skills ([N] observations, [N] principles applied):

**[skill-name]** - [1-sentence change summary]; observations #[N], #[N]

### Observations Actioned
[numbers and titles]

### Skipped (needs manual review)
[items with reasons]
```

## Delivery

Stage FULL skill dir to `[workspace folder]/skill-updates/[date]/[skill-name]/` (SKILL.md + references/, scripts/, assets/) — never SKILL.md alone.

**Pre-delivery gate (last step):**
1. grep staged SKILL.md for `references/`, `scripts/`, `assets/` paths → fail if any referenced file missing
2. multi-file skills fail if presented as bare file links instead of `.skill`

Sweep `__pycache__/`, `*.pyc`, `.DS_Store`, `.~lock.*` before zipping; read archive listing back. `chmod -R u+w` seeded copies (read-only mode travels with the copy). Never edit live skill files.

**Keep-two rule:** only 2 most recent date dirs under `skill-updates/`; delete older.

## Constraints

- Don't modify entries beyond status field
- Don't create new skills in review (note candidates for skill-creator)
- Unsure → skip and say so
- Internal obs get same rigour
