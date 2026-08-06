# Skill Authoring Reference

Reference for skill creation and editing. This is a reference file loaded on demand by the skill-observer SKILL.md.

## Skill File Format

Every skill lives in its own folder named after the skill:

```
~/.config/opencode/skills/my-skill/SKILL.md
```

### Frontmatter

```markdown
---
name: my-skill
description: One sentence covering what this skill does AND when to trigger it.
---

# My Skill

(skill body in markdown: instructions, examples, references)
```

- `name` is required, lowercase hyphen-separated, up to 64 chars, and matches the folder name.
- `description` is effectively required: skills without one are filtered out and never surfaced to the model. Cover both _what_ the skill does and _when_ to use it. Write in third person ("Use when...", not "I help with..."). Front-load concrete trigger keywords and filenames; gate with "Use ONLY when..." if the skill should stay quiet on adjacent topics.
- Optional: `license`, `compatibility`, `metadata` (string-string map).

## Editing Rules

### Always Start From the Live File

1. Live file authoritative: `~/.config/opencode/skills/{skill}/SKILL.md`
2. Base edits on fresh read of live file — never workspace copy/draft/memory
3. Before overwriting staged copy: diff vs live; differ → rebase on live
4. Stage to `[workspace folder]/skill-updates/[date]/[skill-name]/` — FULL dir

### Small Changes

If the improvement is clearly additive, low-risk, and doesn't require testing to verify it works, it can be applied directly to the skill:

- Adding a new rule or anti-pattern to an existing list
- Clarifying existing wording that proved ambiguous
- Adding a note or edge case to an existing section
- Fixing a factual error

### Substantial Changes

If the change could affect the skill's behaviour in ways that need verification:

- Restructuring phases or workflows
- Adding new capabilities or sections
- Changing core methodology or decision frameworks
- Any change where "does this actually work better?" is a genuine question

Match the rigour of the skill creation process to the complexity and audience.

## Relocation/Restructure Verification (2-tier)

1. `diff` old vs new base, enumerate added/moved lines
2. exact-match each non-empty line via `grep -F`
3. misses → substance-check via distinctive mid-line substring
4. word-count sanity per file

Plus: inventory original's enforcement mechanisms (checkpoints/assertions/invariants/mandatory-write rules) as an explicit checklist; sweep restructures for net-new behaviour.

## Pre-Flight Principle

Every skill with explicit rules needs a verification step re-reading rules against output before delivery. Embedded commands are pre-flight items — execute once against real data before saving.

## New-Skill Flow

Start with observation(s) as brief. Type early:

- **Open-source** — strip/generalise, no client names
- **Internal** — specifics freely, personal preferences
- **Uncertain** → default open-source

## Status Transitions

- Applied in review: `ACTIONED (YYYY-MM-DD) - Applied to [skill-name] (weekly review)`
- Declined: `DECLINED (YYYY-MM-DD) - [reason]`
- `ACTIONED`/`DECLINED` without date → archival breaks (date gates the cross-session grace period)
