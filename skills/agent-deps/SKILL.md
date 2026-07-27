# Agent Dependency Resolver

Resolves agent dependency chains before delegation. Use this when you need to determine the correct execution order for agents that depend on each other.

## When to Use

- Before delegating to an agent that has dependencies
- When planning multi-agent workflows
- To verify all prerequisites are met before starting work

## Usage

```bash
# Show execution plan for a specific agent
node skills/agent-deps/resolve.mjs coder

# Show full dependency graph
node skills/agent-deps/resolve.mjs --graph

# List all agents with their dependencies
node skills/agent-deps/resolve.mjs --all

# JSON output for programmatic use
node skills/agent-deps/resolve.mjs --all --json
```

## How It Works

1. Reads all agent definitions from `agents/**/*.md`
2. Parses `dependencies` from YAML frontmatter
3. Builds a dependency graph (topological sort)
4. Outputs the execution plan with required vs optional deps

## Dependency Format

Agents declare dependencies in their frontmatter:

```yaml
---
description: Technical implementation specialist
mode: subagent
dependencies:
  - agent: explore
    purpose: "Map codebase before implementing"
    optional: false
  - agent: researcher
    purpose: "Research library APIs"
    optional: true
---
```

- **required** (`optional: false`): Must run before the dependent agent
- **optional** (`optional: true`): Can run before, but not mandatory

## Orchestrator Integration

When the orchestrator delegates to an agent:

1. Check the agent's dependencies via `resolve.mjs <agent>`
2. Run required dependencies first (in order)
3. Pass their output as context to the target agent
4. Optionally run optional dependencies if time/budget allows

## Example

```
$ node resolve.js coder

Execution plan for: coder
==================================================
● 1. explore [research] — Map relevant code paths before implementing
   Codebase exploration agent for understanding project structure and patterns
○ 2. researcher [research] — Research library APIs and patterns
   External knowledge architect — gathers implementation-ready research

Required: explore
Optional: researcher
```

This means: before delegating to `coder`, first run `explore` to map the codebase. Optionally run `researcher` if the task involves external APIs.
