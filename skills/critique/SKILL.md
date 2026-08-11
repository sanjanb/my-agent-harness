---
name: critique
description: Multi-model critique pipeline. Dispatches parallel critics across provider families, adjudicates disagreements, and produces a synthesized verdict. Use for high-stakes responses, low-confidence outputs, or when multi-perspective validation is needed.
---

# Critique Skill — Multi-Model Adjudication

## Overview

This skill orchestrates a panel of independent LLM critics that evaluate a response against a structured rubric. When critics disagree, an adjudicator resolves the conflict. This is how you separate a vibe coder from an AI engineer.

## When to Use

- **High-stakes output**: production code, security-sensitive changes, architecture decisions
- **Low-confidence single-model response**: when the generating model's confidence is below threshold
- **User-requested review**: explicit request for multi-perspective validation
- **Quality gate escalation**: when `quality-gate` or `reviewer` flags uncertainty

**When NOT to use:**

- Routine code edits or trivial changes
- Draft responses that haven't been through initial review
- When the single-model review already has ≥90% confidence and no critical findings
- Cost-sensitive paths where single review is sufficient

## Architecture

```
                    ┌──────────────────┐
                    │   Draft Response  │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │ Critic-A │  │ Critic-B │  │ Critic-C │
        │(nemotron)│  │(deepseek)│  │ (mimo)   │
        └────┬─────┘  └────┬─────┘  └────┬─────┘
             │              │              │
             ▼              ▼              ▼
        ┌─────────────────────────────────────┐
        │         Consensus Check             │
        │  Majority agree? → Output verdict   │
        │  Split/TIE?      → Adjudicate       │
        └──────────────┬──────────────────────┘
                       │ (on disagreement)
                       ▼
              ┌──────────────────┐
              │   Adjudicator    │
              │   (oracle)       │
              └────────┬─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │  Final Verdict   │
              └──────────────────┘
```

## The Pipeline

### Phase 1: Prepare the Critique

1. Receive the draft response and the original request
2. Determine the domain (code, architecture, planning, content, general)
3. Select the appropriate rubric dimensions (see Rubric Library below)
4. Compose the critic task prompt with: draft, original request, rubric, and domain

### Phase 2: Dispatch Critics (Parallel)

Dispatch three critics simultaneously using the `task` tool:

```
critic-a → nemotron-3-ultra-free  (OpenVIDIA family)
critic-b → deepseek-v4-flash-free (DeepSeek family)
critic-c → mimo-v2.5-free         (OpenCode family)
```

Each critic receives the same prompt but evaluates independently. Use `background: true` for all three — they run concurrently.

**Key**: Each critic MUST be dispatched to a different model provider. Three critics on the same model family are one critic at 3× cost.

### Phase 3: Collect and Compare

Wait for all three critic results. For each, extract:
- **Verdict**: APPROVE, REQUEST_CHANGES, or TIE
- **Confidence**: 0-100
- **Findings**: severity-classified list
- **Dimension scores**: 1-10 per dimension

### Phase 4: Determine Consensus

| Scenario                    | Action                                              |
| --------------------------- | --------------------------------------------------- |
| 2+ agree on REQUEST_CHANGES | Majority rules. Output combined findings.           |
| 2+ agree on APPROVE         | Majority rules. Output combined findings.           |
| 1-1-1 split (all different) | Adjudicate.                                        |
| 2 agree, 1 TIE             | Majority rules. TIE is noted but not blocking.     |
| All TIE                     | Adjudicate. The response is genuinely borderline.  |
| Confidence < 70 on majority | Adjudicate even if verdicts agree.                 |

### Phase 5: Adjudicate (On Disagreement Only)

When consensus fails, dispatch the adjudicator (oracle agent):

The adjudicator receives:
- The original request
- The draft response
- All three critic critiques (full structured output)
- The disagreement map (which critic said what)

The adjudicator must:
1. Identify the specific points of disagreement
2. Evaluate each critic's reasoning
3. Make a final ruling on each disputed point
4. Produce a synthesized verdict with reasoning

### Phase 6: Synthesize Final Output

Combine the consensus (or adjudicated) verdict into a final output:

```
## Critique Verdict

**Consensus:** [APPROVE | REQUEST_CHANGES]
**Confidence:** [average of panel, or adjudicator's confidence]
**Critics:** [list models and their verdicts]
**Adjudicated:** [yes/no]

### Panel Summary
| Critic   | Verdict | Confidence | Key Finding |
| -------- | ------- | ---------- | ----------- |
| critic-a |         |            |             |
| critic-b |         |            |             |
| critic-c |         |            |             |

### Combined Findings
[Unified list of findings from all critics, deduplicated and severity-sorted]

### Adjudicator Notes
[Only if adjudicated — what the disagreement was and how it was resolved]

### Recommendation
[Concrete next steps based on the verdict]
```

## Rubric Library

### Code Review Rubric

| Dimension       | What to evaluate                                         |
| --------------- | -------------------------------------------------------- |
| Correctness     | Logic accuracy, edge cases, error handling               |
| Completeness    | All requirements addressed, no missing paths             |
| Actionability   | Code is runnable, clear, and doesn't need guessing       |
| Risks           | Security, performance, data integrity, breaking changes  |
| Philosophy      | 5 Laws compliance (Early Exit, Parse Don't Validate, Atomic Predictability, Fail Fast, Intentional Naming) |

### Architecture Rubric

| Dimension       | What to evaluate                                         |
| --------------- | -------------------------------------------------------- |
| Correctness     | Sound design decisions, correct trade-offs               |
| Completeness    | All components addressed, boundaries defined             |
| Actionability   | Can be implemented from this plan without ambiguity      |
| Risks           | Scalability, maintainability, coupling, failure modes     |
| Philosophy      | YAGNI compliance, simplicity, minimal abstraction        |

### Planning Rubric

| Dimension       | What to evaluate                                         |
| --------------- | -------------------------------------------------------- |
| Correctness     | Accurate scope, realistic estimates, correct dependencies|
| Completeness    | All steps covered, edge cases considered                 |
| Actionability   | Each step is a concrete, bounded task                    |
| Risks           | Blockers identified, fallback paths, scope creep risk    |
| Philosophy      | Minimal plan, no over-engineering, clear acceptance criteria |

### Content Rubric

| Dimension       | What to evaluate                                         |
| --------------- | -------------------------------------------------------- |
| Correctness     | Factual accuracy, no hallucinations                      |
| Completeness    | All points covered, no missing context                   |
| Actionability   | Reader can act on this immediately                       |
| Risks           | Misinterpretation, ambiguity, missing caveats            |
| Philosophy      | Clear, concise, no unnecessary complexity                |

## Cost Math

- 3 critics × ~⅓ orchestrator cost each = ~1× orchestrator cost for the panel
- Adjudicator fires on ~30-40% of cases (only on disagreement)
- Net: ~1.3-1.4× cost of a single review
- **Worth it when**: the cost of a wrong answer exceeds the 0.3-0.4× premium

## Integration Points

- **Quality Gate**: When `quality-gate` confidence < 70%, escalate to critique pipeline
- **Reviewer**: When `reviewer` finds conflicting signals, escalate to critique pipeline
- **Adjudicator**: Uses existing `oracle` agent (already routed to `big-pickle`)
- **Delegation**: All dispatch uses the existing `task` tool with `background: true`

## Disagreement Metrics

Track these over time to calibrate your panel:

- **Cohen's κ**: Inter-rater agreement (target 0.6-0.8)
  - < 0.6: Judge panel needs work (rubric unclear, models too correlated)
  - > 0.8: Production-ready panel
- **Agreement rate**: If > 95%, drop a critic (too correlated)
- **Adjudication rate**: If > 50%, rubric needs sharpening
