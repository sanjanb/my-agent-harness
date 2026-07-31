# Runtime Roadmap: From Design Spec to Working System

> **Goal:** Make the orchestration system 10/10 — not just described, but executed.
> **Date:** 2026-07-31

---

## The Gap

Current system: **22 capabilities described in markdown.** Agents read instructions and hope the LLM follows them correctly.

Target system: **22 capabilities enforced by scripts.** Agents call scripts that do the mechanical work. LLMs handle decisions, scripts handle execution.

---

## Architecture

```
opencode agents (markdown)
    ↓ call via bash tool
scripts/ (shell/node)
    ↓ enforce
.opencode/ (state files)
```

**Principle:** LLMs decide, scripts execute, state files persist.

---

## What Needs to Be Built

### Category 1: Core Runtime (Must-Have)

| # | Component | What It Does | Files | Effort |
|---|-----------|--------------|-------|--------|
| 1.1 | **DAG Executor** | Reads DAG JSON, resolves deps, dispatches agents in topological order | `scripts/dag-execute.sh` | HIGH |
| 1.2 | **Atomic File Lock** | Prevents concurrent writes to shared state files | `scripts/flock.sh` | LOW |
| 1.3 | **JSON State Manager** | Read/write/query JSON state files safely | `scripts/state.sh` | MEDIUM |
| 1.4 | **Circuit Breaker** | Enforces Closed/Open/Half-Open state machine | `scripts/circuit-breaker.sh` | MEDIUM |
| 1.5 | **Token Budget Tracker** | Tracks token usage per workflow, halts when exceeded | `scripts/budget.sh` | MEDIUM |

### Category 2: Execution Infrastructure (Must-Have)

| # | Component | What It Does | Files | Effort |
|---|-----------|--------------|-------|--------|
| 2.1 | **Worktree Manager Script** | Creates, validates, merges, cleans up git worktrees | `scripts/worktree.sh` | MEDIUM |
| 2.2 | **Task Board Script** | Atomic claim/release/status on task-board.json | `scripts/task-board.sh` | MEDIUM |
| 2.3 | **Sequential Merge Script** | Merges branches one at a time, verifies each | `scripts/merge.sh` | LOW |
| 2.4 | **Checkpoint Writer** | Saves/resumes workflow state from .opencode/checkpoints/ | `scripts/checkpoint.sh` | MEDIUM |
| 2.5 | **Agent Dispatcher** | Dispatches agent via task tool with correlation ID injection | `scripts/dispatch.sh` | MEDIUM |

### Category 3: Cost & Caching (High-Value)

| # | Component | What It Does | Files | Effort |
|---|-----------|--------------|-------|--------|
| 3.1 | **Semantic Cache** | SHA-256 hash lookup on .opencode/cache.jsonl | `scripts/cache.sh` | MEDIUM |
| 3.2 | **Cost Tracker** | Appends cost events to logs.jsonl, queries totals | `scripts/cost.sh` | LOW |
| 3.3 | **Budget Enforcer** | Checks remaining budget before each dispatch, halts if exceeded | `scripts/budget-enforce.sh` | LOW |
| 3.4 | **Cost Report** | Generates cost summary per workflow/agent/step | `scripts/cost-report.sh` | LOW |

### Category 4: Observability (High-Value)

| # | Component | What It Does | Files | Effort |
|---|-----------|--------------|-------|--------|
| 4.1 | **Correlation ID Generator** | Generates wf-{uuid8} format IDs, injects into dispatches | `scripts/correlation.sh` | LOW |
| 4.2 | **Structured Logger** | Appends JSONL events to .opencode/logs.jsonl | `scripts/log.sh` | LOW |
| 4.3 | **Session Replay Writer** | Captures step state to .opencode/replay/ | `scripts/replay.sh` | MEDIUM |
| 4.4 | **Trace Reporter** | Queries logs.jsonl, generates workflow trace tables | `scripts/trace.sh` | MEDIUM |
| 4.5 | **Health Dashboard** | Aggregates metrics, surfaces bottlenecks | `scripts/health.sh` | MEDIUM |

### Category 5: Quality & Memory (Medium-Value)

| # | Component | What It Does | Files | Effort |
|---|-----------|--------------|-------|--------|
| 5.1 | **Quality Gate Runner** | Runs 7 checks (compile, philosophy, tests, style, security, scope, minimalism) | `scripts/quality-gate.sh` | HIGH |
| 5.2 | **Evaluator Scorer** | Scores 5 dimensions, calculates weighted total | `scripts/evaluate.sh` | MEDIUM |
| 5.3 | **Convention Writer** | Appends to conventions.jsonl with dedup check | `scripts/convention.sh` | LOW |
| 5.4 | **AutoDream Runner** | Deduplicates, merges, flags stale conventions | `scripts/auto-dream.sh` | MEDIUM |
| 5.5 | **Shared Context Loader** | Reads shared-context.json + conventions.jsonl, outputs summary | `scripts/load-context.sh` | LOW |

### Category 6: Safety & Recovery (Must-Have)

| # | Component | What It Does | Files | Effort |
|---|-----------|--------------|-------|--------|
| 6.1 | **Stale Task Detector** | Finds tasks claimed >30min ago, releases them | `scripts/stale-task.sh` | LOW |
| 6.2 | **Crash Recovery** | Reads latest checkpoint, resumes from next node | `scripts/recover.sh` | MEDIUM |
| 6.3 | **Merge Conflict Handler** | Detects conflicts, reports to orchestrator, does NOT auto-resolve | `scripts/merge-conflict.sh` | LOW |
| 6.4 | **Workflow Cleanup** | Removes worktrees, checkpoints, temp files after completion | `scripts/cleanup.sh` | LOW |
| 6.5 | **Dry Run Mode** | Runs entire workflow without executing — validates DAG, budgets, deps | `scripts/dry-run.sh` | MEDIUM |

### Category 7: Integration (Glue)

| # | Component | What It Does | Files | Effort |
|---|-----------|--------------|-------|--------|
| 7.1 | **Workflow Init** | Creates workflow ID, allocates budget, initializes state | `scripts/workflow-init.sh` | LOW |
| 7.2 | **Workflow Complete** | Finalizes state, generates report, cleans up | `scripts/workflow-complete.sh` | LOW |
| 7.3 | **Status Dashboard** | Shows all active workflows, their status, costs | `scripts/dashboard.sh` | MEDIUM |
| 7.4 | **Git Hooks** | Pre-commit: validate state files. Post-commit: update shared context | `scripts/hooks.sh` | LOW |

---

## Agent Definition Updates

These agent markdown files need updates to reference the scripts:

| Agent | Update Needed |
|-------|---------------|
| `build.md` | Add script calls for DAG execution, dispatch, caching, budget checks |
| `error-coordinator.md` | Add script calls for circuit breaker state, cost tracking, checkpoints |
| `quality-gate.md` | Add script calls for quality checks, evaluator scoring |
| `observability.md` | Add script calls for logging, tracing, health dashboard |
| `worktree-manager.md` | Add script calls for worktree lifecycle |
| `task-board.md` | Add script calls for atomic claiming, stale detection |
| `babysit-merge.md` | Add script calls for CI monitoring, sequential merge |
| `context-manager.md` | Add script calls for context loading, compression |

---

## Implementation Order

### Phase R1: Core Runtime (Build First)
Scripts that everything else depends on.

1. `scripts/flock.sh` — File locking (everything depends on this)
2. `scripts/state.sh` — JSON state read/write
3. `scripts/correlation.sh` — ID generation
4. `scripts/log.sh` — Structured logging
5. `scripts/workflow-init.sh` — Workflow initialization

### Phase R2: Execution Engine
The actual DAG executor and dispatch.

6. `scripts/dispatch.sh` — Agent dispatch with correlation injection
7. `scripts/task-board.sh` — Atomic claiming
8. `scripts/dag-execute.sh` — DAG topological execution
9. `scripts/checkpoint.sh` — State save/resume
10. `scripts/recover.sh` — Crash recovery

### Phase R3: Isolation & Merge
Git worktree and merge management.

11. `scripts/worktree.sh` — Worktree lifecycle
12. `scripts/merge.sh` — Sequential merge
13. `scripts/merge-conflict.sh` — Conflict detection
14. `scripts/cleanup.sh` — Post-workflow cleanup

### Phase R4: Cost & Cache
Token budgets and semantic caching.

15. `scripts/budget.sh` — Budget tracking
16. `scripts/budget-enforce.sh` — Budget enforcement
17. `scripts/cache.sh` — Semantic cache lookup/store
18. `scripts/cost.sh` — Cost event logging
19. `scripts/cost-report.sh` — Cost reporting

### Phase R5: Observability
Monitoring and debugging.

20. `scripts/replay.sh` — Session replay capture
21. `scripts/trace.sh` — Trace report generation
22. `scripts/health.sh` — Health dashboard
23. `scripts/dashboard.sh` — Status overview

### Phase R6: Quality & Memory
Quality gates and convention management.

24. `scripts/quality-gate.sh` — Quality check runner
25. `scripts/evaluate.sh` — Evaluator scorer
26. `scripts/convention.sh` — Convention write with dedup
27. `scripts/auto-dream.sh` — Memory consolidation
28. `scripts/load-context.sh` — Context loader

### Phase R7: Safety & Polish
Recovery, dry run, hooks.

29. `scripts/stale-task.sh` — Stale task detection
30. `scripts/dry-run.sh` — Workflow dry run
31. `scripts/workflow-complete.sh` — Workflow finalization
32. `scripts/hooks.sh` — Git hooks

### Phase R8: Agent Updates
Update all 8 agent markdown files to reference scripts.

---

## File Structure After Build

```
~/.config/opencode/
├── agents/orchestration/
│   ├── build.md              (updated — references scripts)
│   ├── context-manager.md    (updated)
│   ├── error-coordinator.md  (updated)
│   ├── quality-gate.md       (updated)
│   ├── observability.md      (updated)
│   ├── worktree-manager.md   (updated)
│   ├── task-board.md         (updated)
│   └── babysit-merge.md      (updated)
├── scripts/
│   ├── flock.sh              # File locking
│   ├── state.sh              # JSON state manager
│   ├── correlation.sh        # ID generation
│   ├── log.sh                # Structured logging
│   ├── workflow-init.sh      # Workflow initialization
│   ├── dispatch.sh           # Agent dispatch
│   ├── task-board.sh         # Atomic claiming
│   ├── dag-execute.sh        # DAG executor
│   ├── checkpoint.sh         # Checkpoint write/read
│   ├── recover.sh            # Crash recovery
│   ├── worktree.sh           # Worktree lifecycle
│   ├── merge.sh              # Sequential merge
│   ├── merge-conflict.sh     # Conflict detection
│   ├── cleanup.sh            # Post-workflow cleanup
│   ├── budget.sh             # Budget tracking
│   ├── budget-enforce.sh     # Budget enforcement
│   ├── cache.sh              # Semantic cache
│   ├── cost.sh               # Cost logging
│   ├── cost-report.sh        # Cost reporting
│   ├── replay.sh             # Session replay
│   ├── trace.sh              # Trace reports
│   ├── health.sh             # Health dashboard
│   ├── dashboard.sh          # Status overview
│   ├── quality-gate.sh       # Quality checks
│   ├── evaluate.sh           # Evaluator scorer
│   ├── convention.sh         # Convention writer
│   ├── auto-dream.sh         # Memory consolidation
│   ├── load-context.sh       # Context loader
│   ├── stale-task.sh         # Stale task detection
│   ├── dry-run.sh            # Workflow dry run
│   ├── workflow-complete.sh  # Workflow finalization
│   └── hooks.sh              # Git hooks
├── skills/
│   ├── shared-context/SKILL.md   (updated)
│   └── auto-dream/SKILL.md       (updated)
├── RUNTIME-ROADMAP.md
└── ORCHESTRATION-ANALYSIS.md
```

---

## Total: 32 Scripts + 8 Agent Updates + 2 Skill Updates

| Phase | Scripts | Agent Updates | Effort |
|-------|---------|---------------|--------|
| R1: Core Runtime | 5 | — | MEDIUM |
| R2: Execution Engine | 5 | — | HIGH |
| R3: Isolation & Merge | 4 | — | MEDIUM |
| R4: Cost & Cache | 5 | — | MEDIUM |
| R5: Observability | 4 | — | MEDIUM |
| R6: Quality & Memory | 5 | — | MEDIUM |
| R7: Safety & Polish | 4 | — | LOW |
| R8: Agent Updates | — | 8 agents + 2 skills | HIGH |
| **Total** | **32** | **10** | **~40 scripts, ~15 file updates** |

---

## Success Criteria

After building, the system is 10/10 if:

- [ ] `dag-execute.sh` actually runs a DAG and dispatches agents in order
- [ ] `flock.sh` prevents concurrent writes to task-board.json
- [ ] `circuit-breaker.sh` enforces state transitions (not just described)
- [ ] `budget.sh` halts workflow when token budget exceeded
- [ ] `cache.sh` returns cached results for identical tasks
- [ ] `worktree.sh` creates/validates/merges/cleans worktrees
- [ ] `checkpoint.sh` saves and resumes workflow state
- [ ] `quality-gate.sh` runs 7 checks and produces pass/fail
- [ ] `trace.sh` generates workflow trace from logs.jsonl
- [ ] `dry-run.sh` validates a workflow without executing it
- [ ] All agents reference scripts instead of describing manual steps
- [ ] End-to-end: init → DAG → dispatch → checkpoint → merge → cleanup works

---

## What Stays as Agent Instructions (Not Scripts)

Some things are inherently LLM decisions, not scriptable:

- Task decomposition (which agents, what order)
- DAG generation (which tasks depend on which)
- Quality scoring (subjective assessment)
- Convention writing (pattern recognition)
- Architecture decisions
- Error diagnosis (root cause analysis)
- Conflict resolution strategy selection

**Principle:** If it's mechanical → script it. If it requires judgment → keep as agent instruction.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Scripts add complexity | Each script < 100 lines, single responsibility |
| Shell portability (Windows/Linux) | Use bash explicitly, test on both |
| LLMs may not call scripts correctly | Agent markdown includes exact bash commands to run |
| State file corruption | flock.sh prevents concurrent writes |
| Script failures mid-workflow | checkpoint.sh enables resume from last good state |
