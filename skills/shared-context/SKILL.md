---
name: shared-context
description: Load project conventions into every agent session for consistent multi-agent output
---

# Shared Context

This skill ensures every agent session loads the same project conventions, coding standards, and architectural decisions. It solves the "agents guess independently" problem that causes inconsistent output across parallel agents.

## Why This Exists

When multiple agents work on the same project without shared context:
- Agent A uses camelCase, Agent B uses snake_case
- Agent A creates new utils, Agent B recreates existing ones
- Agent A follows one pattern, Agent B follows another
- Output diverges, rework increases, quality drops

Shared context eliminates this by loading project conventions into every session.

**Research basis:**
- First-Tree: "The gap is the shared context layer — agents guess conventions independently, output diverges"
- First-Tree: "SessionStart hook loads shared context into every agent"
- TruLayer: Uses "Design docs as message bus" for agent coordination

## Use When

- Starting any agent session (coder, designer, researcher, etc.)
- A deepwork session with multiple parallel agents
- Onboarding a new project or codebase
- After significant architecture changes

## What Gets Loaded

### Layer 1: Project Structure
- Directory layout and file organization
- Entry points and main modules
- Key configuration files

### Layer 2: Coding Standards
- From `code-philosophy` (5 Laws of Elegant Defense)
- From `frontend-philosophy` (5 Pillars of Intentional UI)
- Language-specific conventions (TypeScript, Python, etc.)
- Naming conventions (files, functions, variables)

### Layer 3: Existing Patterns
- Utility functions already available
- Common components and their locations
- API patterns and conventions
- Error handling patterns

### Layer 4: Architecture Decisions
- From ADRs (Architecture Decision Records)
- Chosen libraries and frameworks
- Design patterns in use
- Database schemas and models

### Layer 5: Agent-Specific Context
- What other agents are working on
- Current task dependencies
- Recent changes and decisions

## Storage Format

Shared context uses two files:

### 1. Static Context: `.opencode/shared-context.json`

Orchestrator-managed, read-only for agents. Contains project structure, naming conventions, and active agent state.

```json
{
  "lastUpdated": "2026-07-30T10:00:00Z",
  "project": {
    "name": "my-project",
    "root": "/path/to/project",
    "language": "typescript",
    "framework": "next"
  },
  "conventions": {
    "naming": {
      "files": "kebab-case",
      "functions": "camelCase",
      "components": "PascalCase",
      "constants": "UPPER_SNAKE_CASE"
    },
    "structure": {
      "src": "source code",
      "tests": "test files",
      "docs": "documentation"
    }
  },
  "patterns": {
    "utils": ["src/utils/format.ts", "src/utils/validate.ts"],
    "components": ["src/components/ui/"],
    "api": ["src/api/"]
  },
  "decisions": {
    "stateManagement": "zustand",
    "styling": "tailwind",
    "testing": "vitest"
  },
  "agents": {
    "active": ["coder-task-1", "designer-task-2"],
    "recentChanges": ["auth-module", "api-routes"]
  }
}
```

### 2. Learned Conventions: `.opencode/conventions.jsonl`

Agent-writable, append-only. Each line is a standalone JSON object. Agents discover patterns and write them back for future sessions.

**Format per line:**
```json
{"date":"2026-07-30","agent":"fixer","convention":"Use Set-Content not Out-File for .ps1","tags":["powershell","file-ops"]}
```

**Fields:**
| Field        | Type     | Required | Description                        |
| ------------ | -------- | -------- | ---------------------------------- |
| `date`         | string   | yes      | ISO date (YYYY-MM-DD)              |
| `agent`        | string   | yes      | Agent type that learned this       |
| `convention`   | string   | yes      | The convention text                |
| `tags`         | string[] | no       | Category tags for filtering        |
| `source`       | string   | no       | Where it was learned (file/line)   |
| `supersedes`   | string   | no       | Convention this replaces (by text) |

**Why JSONL over JSON or markdown:**
- Append-only: `echo '...' >> conventions.jsonl` (atomic, no lock needed)
- Clean git diffs: each entry is a separate line
- Dedup: `grep -c "pattern" conventions.jsonl` (no full-file parse)
- Crash-safe: partial write = last line incomplete, rest intact
- Filterable: `grep '"powershell"' conventions.jsonl` for category search

## Loading Process

Before any agent session starts:

1. **Check for shared context file**
   ```bash
   cat .opencode/shared-context.json
   ```

2. **If exists, load into session context**
   - Read conventions and patterns
   - Note active agents and recent changes
   - Use this to avoid conflicts

3. **If missing, create from project analysis**
   - Scan project structure
   - Detect naming conventions
   - Identify existing patterns
   - Write shared context file

4. **Update after significant changes**
   - New architecture decisions
   - New patterns established
   - Agent completions
   - Major refactors

## Memory Read: Loading Learned Conventions

Every agent session must load learned conventions before starting work:

1. **Check if conventions file exists**
   ```bash
   test -f .opencode/conventions.jsonl && echo "exists" || echo "missing"
   ```

2. **If exists, read all conventions**
   ```bash
   cat .opencode/conventions.jsonl
   ```
   - Parse each line as JSON
   - Note conventions relevant to your task
   - Reference during implementation

3. **Filter by relevance**
   - Conventions tagged with your task type → highest priority
   - Conventions from your agent type → follow them
   - Conventions from other agents → be aware, don't override
   - Conflicting conventions → follow the most recent (by date)

4. **Conflict resolution**
   - Convention vs code-philosophy → code-philosophy wins
   - Convention vs existing code → convention wins (code may be tech debt)
   - Two conventions conflict → human decides, or flag for AutoDream

## Memory Write: Recording Learned Conventions

When you discover a project-specific pattern, write it back for future sessions.

### When to Write

| Situation | Example |
|-----------|---------|
| Discovered non-obvious pattern | "This project uses `Set-Content` not `Out-File` for PowerShell" |
| Fixed bug caused by wrong assumption | "Auth module expects snake_case, not camelCase" |
| Received human correction | "Sanjan prefers tailwind over CSS modules" |
| Found existing utility you didn't know about | "Use `src/utils/format.ts` for date formatting" |
| Identified anti-pattern to avoid | "Never use `any` in TypeScript — use `unknown` + type guard" |

### When NOT to Write

| Skip | Reason |
|------|--------|
| Generic programming knowledge | "Use const over let" — already in code-philosophy |
| Language defaults | "Python uses snake_case" — not project-specific |
| One-off特殊情况 | "This specific file has 3000 lines" — not a convention |
| Temporary workarounds | "Had to hack around X" — not a pattern to repeat |

### Dedup Process

Before writing, check if convention already exists:

```bash
# Search for similar convention
grep -i "Set-Content" .opencode/conventions.jsonl

# If returns results → check if exact match
# If exact match → skip (don't duplicate)
# If similar but outdated → append new entry with supersedes field
# If no match → append new entry
```

**Dedup rules:**
1. Exact text match → skip
2. Same topic, updated info → append new, add `supersedes` field pointing to old
3. Same topic, different perspective → both valid, append both
4. Different topic → always append

### Write Format

Append exactly one JSON line to `.opencode/conventions.jsonl`:

```bash
echo '{"date":"2026-07-30","agent":"fixer","convention":"Use Set-Content not Out-File for .ps1","tags":["powershell","file-ops"],"source":"src/scripts/deploy.ps1:42"}' >> .opencode/conventions.jsonl
```

**Required fields:** `date`, `agent`, `convention`
**Optional fields:** `tags` (array), `source` (file:line), `supersedes` (convention text being replaced)

### Tag Taxonomy

Use consistent tags for filtering:

| Category | Tags |
|----------|------|
| Language | `typescript`, `python`, `powershell`, `bash` |
| Framework | `react`, `next`, `tailwind`, `prisma` |
| Pattern | `naming`, `structure`, `error-handling`, `testing` |
| Workflow | `git`, `ci-cd`, `deployment`, `review` |
| Anti-pattern | `avoid`, `deprecated`, `security-risk` |

### Size Management

- **Soft limit:** 100 entries
- **At 80+ entries:** AutoDream consolidation runs automatically
- **Stale entries:** > 90 days + never referenced → flagged for removal
- **Dedup on write:** prevents bloat from duplicate conventions

### Coder Agent (@fixer)
- **Read:** Load shared context + conventions before implementing
- **Write:** After discovering project-specific pattern, after fixing bug caused by wrong assumption
- **Example:** Fixer learns "this project uses Zod for validation, not Yup" → writes to conventions

### Designer Agent (@designer)
- **Read:** Load design system from shared context + conventions before UI work
- **Write:** After design decision, after discovering component pattern
- **Example:** Designer learns "project uses `slate-*` not `gray-*`" → writes to conventions

### Researcher Agent (@librarian)
- **Read:** Load project structure + conventions before research
- **Write:** After library-specific finding, after discovering existing solution
- **Example:** Librarian finds "project already has `src/utils/format.ts`" → writes to conventions

### Reviewer Agent (@oracle)
- **Read:** Load conventions before review to check compliance
- **Write:** After identifying anti-pattern, after architecture decision
- **Example:** Oracle identifies "never use `any` in TypeScript" → writes to conventions

### Explorer Agent (@explorer)
- **Read:** Load conventions to understand what to search for
- **Write:** After finding existing pattern that wasn't documented
- **Example:** Explorer finds "auth module uses JWT, not sessions" → writes to conventions

### Build Orchestrator
- **Read:** Load all conventions before dispatching agents
- **Write:** After workflow completes, consolidate learnings
- **Example:** Orchestrator notes "parallel agents conflicted on file naming" → writes to conventions

## Update Triggers

Update shared context when:
- New architecture decision is made
- New pattern is established
- Agent completes a task
- Major refactor happens
- New dependency is added
- Convention changes

## Authority

✅ **You CAN and SHOULD:**
- Read project structure and conventions
- Create shared context file if missing
- Update shared context after changes
- Report shared context status
- Write learned conventions to `.opencode/conventions.jsonl` (see Memory Write below)

❌ **NEVER:**
- Modify project code (only read)
- Override existing conventions (document, don't change)
- Delete shared context without confirmation
- Share context across different projects
- Write generic programming knowledge (only project-specific patterns)
- Modify existing convention entries (append new, or supersede via `supersedes` field)

## Output Format

```markdown
## Shared Context Loaded
- **Project:** [name]
- **Language:** [language]
- **Framework:** [framework]

## Conventions (Static)
- **Files:** [naming convention]
- **Functions:** [naming convention]
- **Components:** [naming convention]

## Learned Conventions (JSONL)
- **Total entries:** [count]
- **Recent additions:**
  - [date] [agent]: [convention]
  - [date] [agent]: [convention]

## Active Agents
- [agent-task-id]: [task description]

## Recent Changes
- [change]: [description]

## Status
- [LOADED | CREATED | UPDATED]
- **Conventions:** [READ | WRITTEN | SKIP (dedup)]
```

## Runtime Scripts

Shared context uses these scripts for mechanical operations:

- `scripts/convention.sh` — CRUD for conventions.jsonl
- `scripts/load-context.sh` — Loads all context for agent sessions
- `scripts/auto-dream.sh` — Memory consolidation
- `scripts/state.sh` — Reads workflow state
- `scripts/log.sh` — Logs context operations
