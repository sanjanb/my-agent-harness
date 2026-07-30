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

Shared context is stored in `.opencode/shared-context.json`:

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

## Integration with Other Agents

### Coder Agent
- Load shared context before implementing
- Check existing patterns before creating new utilities
- Follow naming conventions from shared context

### Designer Agent
- Load design system from shared context
- Check existing components before creating new ones
- Follow style conventions

### Researcher Agent
- Load project structure to understand what exists
- Check existing patterns before recommending new ones
- Avoid duplicating existing solutions

### Orchestrator
- Load active agents to prevent conflicts
- Check recent changes to understand current state
- Use for task assignment decisions

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

❌ **NEVER:**
- Modify project code (only read)
- Override existing conventions (document, don't change)
- Delete shared context without confirmation
- Share context across different projects

## Output Format

```markdown
## Shared Context Loaded
- **Project:** [name]
- **Language:** [language]
- **Framework:** [framework]

## Conventions
- **Files:** [naming convention]
- **Functions:** [naming convention]
- **Components:** [naming convention]

## Active Agents
- [agent-task-id]: [task description]

## Recent Changes
- [change]: [description]

## Status
- [LOADED | CREATED | UPDATED]
```
