# Orchestration Phase 5: Advanced Improvements Plan

> **Status:** PLANNING — Do not implement until approved by Sanjan.

## Overview

Extends the existing 4-phase orchestration system with 8 advanced capabilities based on 2026 industry research. These address memory, cost, resilience, debugging, and execution quality.

## Prerequisites

All 4 prior phases committed:
- Phase 1 (`96bb43f`): Worktree isolation, shared context, task board
- Phase 2 (`4254b67`): Model tier routing, quality gates
- Phase 3 (`6d997ff`): Babysit-merge, sprint contracts
- Phase 4 (`75df019`): Observability, system circuit breaker

## Improvement Roadmap

### Phase 5A: Memory & Identity (Week 1)

#### 5A-1: Agent-Writable Conventions
- **File:** `skills/shared-context/SKILL.md` (update)
- **What:** Allow agents to write back learned conventions, patterns, and decisions to a shared conventions file
- **Details:**
  - Add "Memory Write" section to shared-context skill
  - Agents append learned patterns to `CONVENTIONS.md` during work
  - Format: `[YYYY-MM-DD] <agent-type>: <convention>`
  - Dedup logic: don't repeat existing entries
- **Source:** CLAUDE.md/AGENTS.md pattern from Zylos Research

#### 5A-2: AutoDream Memory Consolidation
- **File:** `skills/auto-dream/SKILL.md` (new)
- **What:** Background sub-agent that consolidates session memory into long-term conventions between sessions
- **Details:**
  - Runs after workflow completes (or on-demand)
  - Reviews session outputs, extracts patterns
  - Updates CONVENTIONS.md with consolidated learnings
  - Removes stale/redundant entries
- **Source:** AutoDream (Feb 2026) — REM sleep analogy for agent memory

### Phase 5B: Cost & Resilience (Week 2)

#### 5B-1: Cost-Aware Circuit Breaker
- **File:** `agents/orchestration/error-coordinator.md` (update)
- **What:** Extend circuit breaker to track token usage and cost, not just failure count
- **Details:**
  - Add cost thresholds to circuit breaker triggers
  - Track cumulative token usage per workflow
  - Auto-halt if cost exceeds budget (default: $10/workflow)
  - Add `COST_BUDGET` environment variable support
  - Report cost in observability metrics
- **Source:** NiteAgent 2026 — $47K infinite loop horror story

#### 5B-2: Semantic Caching Layer
- **File:** `agents/orchestration/build.md` (update)
- **What:** Cache semantically similar prior requests to avoid redundant model calls
- **Details:**
  - Before dispatching to model, check cache for similar task+context pairs
  - Cache key: task description + relevant code context (hashed)
  - Cache hit → return cached result, skip model call
  - Cache miss → dispatch normally, store result
  - TTL: 24 hours default
  - Storage: local SQLite or JSON file
- **Savings:** 50-90% on cached hits
- **Source:** Zylos Cost Optimization 2026

#### 5B-3: Token Budget Guardrails
- **File:** `agents/orchestration/build.md` (update)
- **What:** Hard per-request and per-workflow token limits with graceful degradation
- **Details:**
  - `TOKEN_LIMIT_PER_TASK` (default: 50k)
  - `TOKEN_LIMIT_PER_WORKFLOW` (default: 500k)
  - When approaching limit: switch to cheaper model or reduce context
  - When exceeded: halt gracefully, report partial results
- **Source:** SkillGen 2026

### Phase 5C: Debugging & Tracing (Week 3)

#### 5C-1: Correlation IDs
- **File:** `agents/orchestration/observability.md` (update)
- **What:** Every agent task, tool call, and message carries a unique trace ID
- **Details:**
  - Generate UUID at workflow start
  - Pass through all agent invocations
  - Include in all log outputs
  - Enable session replay from any point
  - Format: `wf-{uuid8}-step-{n}-agent-{type}`
- **Source:** Atlan 2026, Data-Gate 2026 — "non-negotiable first step"

#### 5C-2: Session Replay
- **File:** `agents/orchestration/observability.md` (update)
- **What:** Record agent state at each step for deterministic replay debugging
- **Details:**
  - Snapshot state before each agent invocation
  - Record: inputs, outputs, model used, tokens consumed
  - Replay command: "replay workflow {id} from step {n}"
  - Diff mode: compare successful vs failed runs
- **Source:** Data-Gate 2026 — 8-step debugging checklist

### Phase 5D: Execution Quality (Week 4)

#### 5D-1: Plan-and-Execute DAG
- **File:** `agents/orchestration/build.md` (update)
- **What:** Orchestrator produces explicit DAG of subtasks with dependency edges
- **Details:**
  - Before dispatch, generate DAG as JSON
  - Nodes: task id, type, dependencies, estimated cost
  - Edges: dependency relationships
  - Execute in topological order, parallelize independent nodes
  - Checkpoint after each node
- **Source:** LangGraph Command primitive, OrgAgent paper (74% token reduction)

#### 5D-2: Evaluator-Optimizer Loop
- **File:** `agents/orchestration/quality-gate.md` (update)
- **What:** After quality-gate passes, run evaluator that scores output and feeds improvements back
- **Details:**
  - Quality gate → pass/fail (existing)
  - Evaluator → score 1-10 + improvement suggestions
  - If score < 8: feed suggestions back to specialist, re-run
  - Max 3 optimization iterations
  - Track improvement trajectory
- **Source:** Anthropic evaluator-optimizer pattern

#### 5D-3: Durable Execution Checkpoints
- **File:** `agents/orchestration/error-coordinator.md` (update)
- **What:** Every workflow step checkpointed for crash recovery
- **Details:**
  - After each successful step: serialize state to disk
  - On crash: detect last good checkpoint, resume from there
  - Checkpoint format: JSON with step number, agent state, task board state
  - Auto-cleanup: keep last 5 checkpoints per workflow
- **Source:** Temporal durable execution, LangGraph checkpointer

## Implementation Order

```
Week 1: 5A-1 → 5A-2 (memory compounds over time, start early)
Week 2: 5B-1 → 5B-2 → 5B-3 (cost controls before scaling)
Week 3: 5C-1 → 5C-2 (debugging needs correlation IDs first)
Week 4: 5D-1 → 5D-2 → 5D-3 (execution quality after foundation)
```

## Files Modified/Created

| Phase | Action | File |
|-------|--------|------|
| 5A-1 | Update | `skills/shared-context/SKILL.md` |
| 5A-2 | Create | `skills/auto-dream/SKILL.md` |
| 5B-1 | Update | `agents/orchestration/error-coordinator.md` |
| 5B-2 | Update | `agents/orchestration/build.md` |
| 5B-3 | Update | `agents/orchestration/build.md` |
| 5C-1 | Update | `agents/orchestration/observability.md` |
| 5C-2 | Update | `agents/orchestration/observability.md` |
| 5D-1 | Update | `agents/orchestration/build.md` |
| 5D-2 | Update | `agents/orchestration/quality-gate.md` |
| 5D-3 | Update | `agents/orchestration/error-coordinator.md` |

**Total:** 1 new file, 6 files updated, ~400 lines added

## Use Cases

### 5A-1: Agent-Writable Conventions
**Scenario:** @fixer encounters that this project uses `Set-Content` instead of `Out-File` for PowerShell scripts. It writes `[2026-07-30] fixer: Use Set-Content not Out-File for .ps1 files` to CONVENTIONS.md. Next session, @fixer reads this and avoids the mistake without re-discovering it.

**Scenario:** @designer learns the project's color palette is Tailwind `slate-*` not `gray-*`. Writes it down. Every future agent session starts with this knowledge.

**Scenario:** @oracle identifies a recurring anti-pattern (e.g., "never use `any` in TypeScript"). Writes it as a convention. Quality-gate references it during checks.

### 5A-2: AutoDream Memory Consolidation
**Scenario:** After a 3-hour multi-phase workflow, AutoDream runs overnight. It notices 5 agents all wrote similar conventions about file naming. It merges them into one canonical entry: "Files: kebab-case for components, camelCase for utils."

**Scenario:** AutoDream detects a stale convention from 3 months ago that contradicts a newer one. Removes the old entry, keeps the new.

**Scenario:** AutoDream identifies that certain conventions are never referenced by any agent. Flags them for removal to keep CONVENTIONS.md lean.

### 5B-1: Cost-Aware Circuit Breaker
**Scenario:** A workflow spawns 10 agents. By agent 6, cumulative cost hits $8. Circuit breaker trips at $10 threshold. Remaining 4 agents get cheaper models or are deferred. Total bill: $9.50 instead of projected $15.

**Scenario:** An agent enters an infinite loop, consuming 200k tokens. Cost tracker detects $47 in 10 minutes, auto-halts. Without this: $47K bill (NiteAgent horror story).

**Scenario:** Budget is set to $5/workflow via `COST_BUDGET=5`. Every dispatch checks remaining budget before choosing model tier.

### 5B-2: Semantic Caching Layer
**Scenario:** @fixer is asked to "add error handling to the auth module." Cache check finds a semantically similar task from last week (85% similarity). Returns cached result. Model call skipped. Cost: $0 instead of $0.30.

**Scenario:** @librarian researches "React 19 server components." Cache has near-identical query from 2 days ago. Returns cached docs. Saves 15 seconds of web search + model processing.

**Scenario:** Two parallel agents request similar code analysis. First hits cache miss, stores result. Second hits cache. 50% cost reduction on parallel work.

### 5B-3: Token Budget Guardrails
**Scenario:** A task is allocated 50k tokens. At 40k, the agent is flagged: "switch to cheaper model or truncate context." Agent switches to Haiku, completes task. Cost: $0.15 instead of $0.45.

**Scenario:** Workflow hits 500k token limit. Graceful halt: all partial results saved, task board updated with "blocked - budget exhausted." Human reviews and decides next step.

**Scenario:** @explorer is asked to search an enormous codebase. Token limit prevents runaway costs. Returns top-20 results instead of exhaustive scan.

### 5C-1: Correlation IDs
**Scenario:** Workflow fails at step 7 of 12. Correlation ID `wf-a1b2c3d4-step-7-agent-fixer` lets you grep all logs for that exact agent invocation. See: input was correct, model hallucinated, output was wrong. Root cause identified in 30 seconds instead of 30 minutes.

**Scenario:** Two parallel agents produce conflicting file edits. Correlation IDs show which agent wrote what, when. Merge conflict resolved by tracing each agent's timeline.

**Scenario:** Observability dashboard filters by correlation ID. Shows: step 1-6 succeeded, step 7 failed, steps 8-12 never ran. Clear blast radius.

### 5C-2: Session Replay
**Scenario:** Agent failed at step 5. Replay from step 3 with same inputs. Step 3-4 reproduce, step 5 fails differently. Confirms: bug is in the task, not the model.

**Scenario:** Compare two runs of same workflow. Run A succeeded, Run B failed. Diff shows: Run A used model X, Run B used model Y. Model Y lacks capability for this task type.

**Scenario:** New team member asks "how did this workflow work?" Replay shows step-by-step: what each agent did, what tools were called, what decisions were made. Onboarding in 10 minutes.

### 5D-1: Plan-and-Execute DAG
**Scenario:** Build orchestrator receives "add user authentication with JWT." DAG generated:
```
1. Research JWT patterns (no deps) → @librarian
2. Design auth schema (depends: 1) → @designer
3. Implement auth endpoints (depends: 2) → @fixer
4. Add auth middleware (depends: 3) → @fixer
5. Write tests (depends: 3,4) → @fixer
6. Quality gate (depends: 5) → quality-gate
```
Steps 1 runs alone. Steps 2 waits for 1. Steps 3-4 are sequential. Step 5 waits for 3+4. Optimal parallelism without conflicts.

**Scenario:** DAG shows step 3 depends on step 2. Step 2 fails. DAG halts dependent steps 3,4,5,6. No wasted work on doomed tasks.

**Scenario:** DAG visualization: `build --show-dag` outputs the execution graph for debugging orchestration itself.

### 5D-2: Evaluator-Optimizer Loop
**Scenario:** @fixer implements a REST API endpoint. Quality-gate passes (compiles, tests pass, philosophy compliant). Evaluator scores: 7/10 — "missing input validation on query params." Feedback sent back to @fixer. Re-implements with validation. Evaluator scores: 9/10. Done.

**Scenario:** @designer creates a landing page. Quality-gate passes. Evaluator: 6/10 — "CTA button too small on mobile." Feedback → @designer adjusts. Rescored: 8/10. Three iterations total.

**Scenario:** Evaluator scores plateau at 7/10 after 2 iterations. System stops optimizing. Reports: "diminishing returns, manual review recommended."

### 5D-3: Durable Execution Checkpoints
**Scenario:** Workflow crashes at step 8 of 12. Checkpoint saved after step 7. On restart: detect checkpoint, resume from step 8. No re-execution of steps 1-7. Saves 30 minutes of redundant work.

**Scenario:** Agent runs out of context window at step 5. Checkpoint preserved step 1-4 state. Fresh context loaded, step 5 resumes with full prior state.

**Scenario:** Human approves step 3 (manual review gate). Checkpoint records approval. If workflow restarts, step 3 is skipped (already approved).

## Expected Impact

| Metric | Before | After |
|--------|--------|-------|
| Cost per workflow | Baseline | -50-70% (semantic caching + model cascade) |
| Debugging time | Manual grep | Session replay + correlation IDs |
| Crash recovery | Restart from scratch | Resume from last checkpoint |
| Memory | Per-session | Cross-session learning |
| Execution efficiency | Sequential/parallel | DAG-optimized parallelism |
| Quality ceiling | Pass/fail | Iterative refinement loop |

## Commit Strategy

One commit per week:
- `feat: add agent memory system and auto-dream consolidation`
- `feat: add cost-aware circuit breaker and semantic caching`
- `feat: add correlation IDs and session replay debugging`
- `feat: add plan-and-execute DAG and evaluator-optimizer loop`
