# OpenCode Orchestration: Analysis & Improvement Plan

> **Date:** 2026-07-30
> **Goal:** Transform OpenCode into the best multi-agent coding orchestration system

---

## Research Sources

| # | Source | Title | Date | URL |
|---|--------|-------|------|-----|
| 1 | amux.io | AI Agent Orchestration in 2026 | 2026-05-25 | https://amux.io/blog/ai-agent-orchestration |
| 2 | Anthropic | Harness design for long-running apps | 2025 | https://www.anthropic.com/research |
| 3 | TruLayer | Orchestration patterns for agentic dev | 2026-04-30 | https://trulayer.io/blog/orchestration-patterns |
| 4 | Augment Code | Multi-Agent AI System | 2026-03-20 | https://www.augmentcode.com/blog |
| 5 | GitHub Copilot | Multi-Agent System | 2026-05-30 | https://github.blog/ai-and-ml |
| 6 | First-Tree | Orchestrating Coding Agents | 2026 | https://first-tree.dev |
| 7 | skdhir/ai-agent-orchestra | Role-based agent isolation | 2026-02-22 | https://github.com/skdhir/ai-agent-orchestra |
| 8 | Anthropic | 2026 Agentic Coding Trends Report | 2026 | https://www.anthropic.com/research |

---

## Key Quotes from Research

> "Orchestration = Parallelism + Isolation + Communication + Coordination + Observability" — amux.io [1]

> "The constraint is orchestration — the system that turns capability into shippable output" — TruLayer [3]

> "Running 2-4 AI coding agents in parallel can accelerate investigation and implementation" — Augment Code [4]

> "The gap is the shared context layer — agents guess conventions independently, output diverges" — First-Tree [6]

> "The human is the bottleneck, not the agents. 3 parallel agents is practical max for one human reviewer" — skdhir [7]

> "Context resets (clearing context window + structured handoff) solve context anxiety" — Anthropic [2]

---

## Current System Analysis

### Architecture Layers

| Layer | Files | Lines | Status |
|-------|-------|-------|--------|
| Orchestration | build.md, context-manager.md, error-coordinator.md | 289 | Functional but incomplete |
| Development | coder.md | 215 | Strong (philosophy-driven) |
| Planning | plan.md | 103 | Basic delegation |
| Skills | deepwork, code-philosophy, frontend-philosophy, ETHOS | ~360+ | Excellent |
| Agents | @explorer, @librarian, @oracle, @designer, @fixer, @observer | ~6 | Good coverage |

### Strengths

1. **Philosophy-driven development** — code-philosophy (5 Laws of Elegant Defense) + frontend-philosophy (5 Pillars of Intentional UI) ensure consistent quality [from code-philosophy/SKILL.md, frontend-philosophy/SKILL.md]
2. **Context management** — compression patterns, boundary-aware compression, intent preservation [from context-manager.md]
3. **Error recovery** — retry, circuit breaker, fallback, checkpoint+resume [from error-coordinator.md]
4. **Deep work workflow** — Oracle review gates, designer handoff guardrails, scheduler discipline [from deepwork/SKILL.md]
5. **ETHOS** — Boil the Ocean, Search Before Building, User Sovereignty [from ETHOS.md]
6. **Rich agent ecosystem** — 6 specialist agents covering different domains

---

## Gap Analysis

### Gap 1: No Git Worktree Isolation (HIGH)

**Current:** All agents work on the same filesystem/branch. Parallel agents can conflict, create merge conflicts, break each other's work.

**Research Evidence:**
- amux.io: "L2 Isolation (git worktrees)" is one of five infrastructure layers [1]
- TruLayer: Pattern #2 is "Worktree isolation" — each agent works in isolated branch [3]
- Augment Code: Pattern #2 is "worktree isolation" for parallel agents [4]

**Impact:** Parallel execution is unsafe. Current system can only safely run 1 agent at a time.

**Solution:** New agent `orchestration/worktree-manager.md` that creates isolated git worktrees per agent task.

---

### Gap 2: No Shared Context Layer (HIGH)

**Current:** Each agent starts fresh with no knowledge of project conventions, existing patterns, or other agents' decisions. Agents guess conventions independently.

**Research Evidence:**
- First-Tree: "The gap is the shared context layer — agents guess conventions independently, output diverges" [6]
- First-Tree: "SessionStart hook loads shared context into every agent" [6]
- TruLayer: Uses "Design docs as message bus" for agent coordination [3]

**Impact:** Inconsistent output across agents. Rework when agents make conflicting decisions.

**Solution:** New skill `skills/shared-context/SKILL.md` that loads project conventions into every agent session.

---

### Gap 3: No Task Board with Atomic Claiming (HIGH)

**Current:** No formal task ownership mechanism. Tasks are dispatched but ownership is implicit.

**Research Evidence:**
- amux.io: "L3 Coordination (task board with atomic claiming)" [1]
- skdhir: Uses "Tracker as task queue" for coordination [7]
- TruLayer: "Trust-but-verify blocked claims" pattern [3]

**Impact:** Duplicate work possible. No crash recovery. Unclear task status.

**Solution:** New agent `orchestration/task-board.md` with atomic claiming and status transitions.

---

### Gap 4: No Model Tier Routing (MEDIUM)

**Current:** All agents use the same model regardless of task complexity.

**Research Evidence:**
- Augment Code: "BYOA routing: strong reasoning models for high-stakes decisions, faster models for routine iteration" [4]
- GitHub Copilot: "Model tier mapping: expensive models for reasoning, cheaper for execution" [5]

**Impact:** Wasted tokens on routine tasks. Suboptimal quality on complex decisions.

**Solution:** Add model routing criteria to planning/plan.md.

---

### Gap 5: No Automated Quality Gates (MEDIUM)

**Current:** Verification is manual. No automated checks before task completion.

**Research Evidence:**
- Augment Code: "automated quality gates" as pattern #5 [4]
- GitHub Copilot: "DELEGATION HARD-STOP rule prevents context bypass" [5]

**Impact:** Issues slip through. Manual verification is slow and inconsistent.

**Solution:** New agent `orchestration/quality-gate.md`.

---

### Gap 6: No Sequential Merge Strategy (MEDIUM)

**Current:** No defined merge order for parallel work.

**Research Evidence:**
- Augment Code: "Sequential merges: integrate one branch at a time, rebase remaining branches" [4]

**Impact:** Merge conflicts from parallel work. Integration is chaotic.

**Solution:** Add merge ordering to orchestration/build.md.

---

### Gap 7: No Babysit-Merge Pattern (MEDIUM)

**Current:** No CI monitoring agents.

**Research Evidence:**
- TruLayer: "Babysit-merge: separate agent watches CI and merges when green, doesn't fix CI failures" [3]

**Impact:** Manual CI monitoring. Slower merge cycle.

**Solution:** New agent `orchestration/babysit-merge.md`.

---

### Gap 8: No Explicit Definition of Done (MEDIUM)

**Current:** Vague completion criteria per agent type.

**Research Evidence:**
- TruLayer: "Agent definition: name, model, scope, tools, hard rules, working directories, definition of done" [3]
- skdhir: Clear task completion criteria in tracker [7]

**Impact:** Ambiguous completion. Unclear handoffs.

**Solution:** Add "Definition of Done" section to all agent definitions.

---

### Gap 9: No Sprint Contracts (LOW)

**Current:** No upfront "done" negotiation between planner and implementer.

**Research Evidence:**
- Anthropic: "Sprint contracts: generator and evaluator negotiate 'done' before coding" [2]

**Impact:** Scope creep. Misaligned expectations.

**Solution:** Add sprint contract template to deepwork SKILL.md.

---

### Gap 10: No File-Based Agent Communication (LOW)

**Current:** Agents return results to orchestrator, not to each other.

**Research Evidence:**
- Anthropic: "Communication via files: agents write/read files, not conversation" [2]

**Impact:** Agents can't share intermediate results directly.

**Solution:** Add file-based communication patterns to agent definitions.

---

### Gap 11: No Observability Layer (LOW)

**Current:** No metrics, tracing, or logging across agents.

**Research Evidence:**
- amux.io: "L5 Observability" is one of five infrastructure layers [1]

**Impact:** No visibility into system performance. Hard to debug.

**Solution:** New agent `orchestration/observability.md`.

---

### Gap 12: No System-Level Circuit Breaker (LOW)

**Current:** Error-coordinator handles per-agent failures, not system-wide.

**Research Evidence:**
- amux.io: System-level resilience patterns [1]

**Impact:** Cascade failures not detected.

**Solution:** Add system health monitoring to error-coordinator.

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2) — Isolation + Shared Context

| Task | File | Impact | Effort |
|------|------|--------|--------|
| Git worktree isolation | `agents/orchestration/worktree-manager.md` | HIGH | MEDIUM |
| Shared context layer | `skills/shared-context/SKILL.md` | HIGH | LOW |
| Task board with atomic claiming | `agents/orchestration/task-board.md` | HIGH | MEDIUM |

### Phase 2: Intelligence (Week 3-4) — Model Routing + Quality Gates

| Task | File | Impact | Effort |
|------|------|--------|--------|
| Model tier routing | Update `planning/plan.md` | MEDIUM | LOW |
| Automated quality gates | `agents/orchestration/quality-gate.md` | MEDIUM | MEDIUM |
| Sequential merge strategy | Update `orchestration/build.md` | MEDIUM | LOW |

### Phase 3: Automation (Week 5-6) — Babysit-Merge + Definition of Done

| Task | File | Impact | Effort |
|------|------|--------|--------|
| Babysit-merge agent | `agents/orchestration/babysit-merge.md` | MEDIUM | MEDIUM |
| Definition of done | All agent definitions | MEDIUM | LOW |
| Sprint contracts | Update `deepwork/SKILL.md` | LOW | LOW |

### Phase 4: Observability (Week 7-8) — Metrics + System Resilience

| Task | File | Impact | Effort |
|------|------|--------|--------|
| Observability layer | `agents/orchestration/observability.md` | LOW | HIGH |
| System-level circuit breaker | Update `error-coordinator.md` | LOW | MEDIUM |

---

## Expected Outcomes

| Metric | Current | After Improvement |
|--------|---------|-------------------|
| Parallel agents | 1-2 (conflicting) | 3-5 (isolated) |
| Agent consistency | Low (guessing) | High (shared context) |
| Quality verification | Manual | Automated gates |
| Cost efficiency | Same model for all | 30-50% reduction via routing |
| Merge conflicts | Frequent | Eliminated via sequential merge |
| CI monitoring | Manual | Autonomous babysit-merge |
| Visibility | None | Full metrics + tracing |
| System resilience | Per-agent only | System-level circuit breaker |
