---
name: ship
description: |
  Ship pipeline: test → build → review → deploy → notify.
  Uses agents: test-engineer, devops-specialist, reviewer.
  Configurable via .opencode/ship.jsonc.
  Use when asked to "ship", "deploy", "push to main", "create a PR", or "get it deployed".
---

## Preamble (run first)

```bash
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
OPENCODE_ROOT="$HOME/.config/opencode"
[ -n "$_ROOT" ] && [ -d "$_ROOT/.opencode" ] && OPENCODE_ROOT="$_ROOT/.opencode"
OPENCODE_BIN="$OPENCODE_ROOT/bin"
_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
echo "BRANCH: $_BRANCH"
_SESSION_ID="$$-$(date +%s)"
echo "SESSION_ID: $_SESSION_ID"
mkdir -p ~/.opencode/sessions
touch ~/.opencode/sessions/"$PPID"
```

## Load Ship Config

```bash
SHIP_CONFIG="$_ROOT/.opencode/ship.jsonc"
if [ ! -f "$SHIP_CONFIG" ]; then
  SHIP_CONFIG="$OPENCODE_ROOT/ship.jsonc"
fi
if [ -f "$SHIP_CONFIG" ]; then
  echo "SHIP_CONFIG: $SHIP_CONFIG"
  cat "$SHIP_CONFIG" | jq -r '.stages // [] | join(",")' 2>/dev/null || echo "stages: test,build,review,deploy,notify"
else
  echo "SHIP_CONFIG: not found, using defaults"
  echo "stages: test,build,review,deploy,notify"
fi
```

## Ship Pipeline

You are running the `/ship` workflow. This is a **mostly automated** pipeline. Run each enabled stage in order. Stop only for:
- On the base branch (abort)
- Stage failure with `failOnFailure: true`
- Explicit user decision points (version bump, deploy target)

### Stage Execution

For each stage in `stages` array from config:

#### 1. TEST STAGE
```bash
# Delegates to test-engineer agent
opencode run test-engineer -- "Run full test suite with coverage. Fail on any test failure. Output summary with pass/fail counts and coverage percentage."
```
- Uses `test` config: agent, command, args, failOnFailure, timeout
- On failure: stop pipeline, report test results

#### 2. BUILD STAGE
```bash
# Delegates to devops-specialist agent
opencode run devops-specialist -- "Run typecheck, lint, and build. Verify all pass. Output build artifacts and any warnings."
```
- Uses `build` config: agent, commands[], docker, failOnFailure, timeout
- Runs each command in sequence
- On failure: stop pipeline, report build errors

#### 3. REVIEW STAGE
```bash
# Delegates to reviewer agent
opencode run reviewer -- "Perform full 4-layer code review (Correctness, Security, Performance, Style) on the diff vs base branch. Output findings with confidence scores. Fail on security/correctness issues per config."
```
- Uses `review` config: agent, mode, failOn[], timeout
- On blocking findings: stop pipeline, present review for user decision

#### 4. DEPLOY STAGE
```bash
# Delegates to devops-specialist agent
opencode run devops-specialist -- "Deploy to {target} environment on {platform}. Verify deployment health. Output deployment URL and status."
```
- Uses `deploy` config: agent, target, platform, environments, failOnFailure, timeout
- Target from config or args: `/ship --target production`
- On failure: offer revert, stop pipeline

#### 5. NOTIFY STAGE
```bash
# Uses notify plugin
opencode notify --title "Ship {status}" --message "{branch} → {target} ({duration}s)" --sound {success:complete,failure:error}
```
- Uses `notify` config: on[], channels[], message template
- Always runs (success or failure)

## Arguments

- `/ship` — run full pipeline with config defaults
- `/ship --stage test` — run only test stage
- `/ship --stage test,build` — run specific stages
- `/ship --target production` — deploy to production
- `/ship --dry-run` — show what would run without executing
- `/ship --skip-review` — skip review stage (use with caution)

## Config Schema (.opencode/ship.jsonc)

```jsonc
{
  "stages": ["test", "build", "review", "deploy", "notify"],
  "test": {
    "agent": "test-engineer",
    "command": "test",
    "args": ["--coverage"],
    "failOnFailure": true,
    "timeout": 300000
  },
  "build": {
    "agent": "devops-specialist",
    "commands": ["typecheck", "lint", "build"],
    "docker": false,
    "failOnFailure": true,
    "timeout": 300000
  },
  "review": {
    "agent": "reviewer",
    "mode": "full",
    "failOn": ["security", "correctness"],
    "timeout": 180000
  },
  "deploy": {
    "agent": "devops-specialist",
    "target": "preview",
    "platform": "vercel",
    "environments": {
      "preview": { "url": "auto", "alias": true },
      "production": { "url": "manual", "alias": false }
    },
    "failOnFailure": true,
    "timeout": 300000
  },
  "notify": {
    "on": ["success", "failure"],
    "channels": ["desktop", "terminal"],
    "message": "{status}: {branch} → {target} ({duration}s)"
  }
}
```

## Completion

Output summary:
```
✅ Ship complete: {branch} → {target}
   Test: {pass}/{total} ({coverage}%)
   Build: {status}
   Review: {findings} blocking, {warnings} warnings
   Deploy: {url}
   Duration: {total}s
```

On failure:
```
❌ Ship failed at {stage}: {error}
   {details}
   Run `/ship --stage {stage}` to retry from failure point
```