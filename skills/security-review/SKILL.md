---
name: security-review
description: Code review with confidence scoring, git blame context, auto-skip, and policy file support. Use when reviewing PRs, diffs, or code changes for security issues. Triggers on "review", "security review", "code review", "pr review", "check for issues".
---

# Security Review

Automated code review with confidence-based filtering to reduce false positives.

## Workflow

### Step 1: Auto-Skip Check

Before running review, check if this PR should be skipped:

```bash
# Get PR state
gh pr view $PR_NUMBER --json state,isDraft,author,title,additions,deletions

# Skip conditions:
# - state == "CLOSED" or state == "MERGED"
# - isDraft == true
# - author.login contains "bot" or "dependabot" or "renovate"
# - additions + deletions < 10 (trivial)
# - Already has review comments from this session
```

If any skip condition matches, report and stop.

### Step 2: Load Policy Files

Check for org-specific rules in order (first match wins):

1. `~/.claude/security-guidance.md` — user-wide rules
2. `<project>/.claude/security-guidance.md` — project rules
3. `<project>/.claude/security-guidance.local.md` — local overrides

Combined size budget: 8KB. If exceeded, truncate from tail (project-local dropped first).

### Step 3: Get Diff and Git Blame

```bash
# Get the diff for review
gh pr diff $PR_NUMBER

# Get blame for changed lines to identify introduced vs pre-existing
git blame -L $START,$END $FILE --porcelain
```

For each issue found, check git blame to determine:
- **Introduced**: Author matches PR author, commit is recent
- **Pre-existing**: Already in codebase before this PR

Only flag **introduced** issues unless reviewing full file context.

### Step 4: Run Review

Scan for these categories:

| Category             | Patterns to check                                    |
| -------------------- | ---------------------------------------------------- |
| Command injection    | `os.system()`, `subprocess.shell=True`, `exec()`     |
| XSS                  | `innerHTML`, `dangerouslySetInnerHTML`, `eval()`     |
| Secrets              | Hardcoded API keys, tokens, passwords                |
| Deserialization      | `pickle.load()`, `yaml.load()` without SafeLoader    |
| Path traversal       | User input in file paths without validation          |
| SQL injection        | String concatenation in queries                      |
| SSRF                 | User-controlled URLs in requests                     |
| Authentication       | Missing auth checks, weak validation                 |
| Error handling       | Silent failures, leaked exceptions                   |

Apply any rules from loaded policy files.

### Step 5: Confidence Scoring

Score each issue 0-100 independently:

| Score | Meaning                              |
| ----- | ------------------------------------ |
| 0-25  | Low confidence, likely false positive |
| 26-50 | Moderate, might be real but minor     |
| 51-75 | High confidence, real issue           |
| 76-100| Very high, definitely real            |

**Scoring criteria:**
- Evidence strength (direct vs inferred)
- Verification status (confirmed vs potential)
- Specificity (exact line vs general area)
- Reproducibility (always happens vs edge case)

### Step 6: Filter and Output

```bash
# Default threshold: 80
# Configurable via env var: SECURITY_REVIEW_THRESHOLD=80

# Only report issues with confidence >= threshold
```

Output format:

```
## Security Review

Found X issues (filtered from Y total, threshold: Z):

1. [HIGH] Issue title (confidence: 85)
   
   File: path/to/file.ts
   Line: 42-45
   Status: **Introduced in this PR**
   
   Description of the issue and why it's dangerous.

2. [MEDIUM] Another issue (confidence: 82)
   ...
```

## Environment Variables

| Variable                   | Default | Description                           |
| -------------------------- | ------- | ------------------------------------- |
| `SECURITY_REVIEW_DISABLE`  | `0`     | Set to `1` to disable entire review      |
| `ENABLE_CONFIDENCE_SCORING`| `1`     | Set to `0` to show all issues unfiltered |
| `ENABLE_GIT_BLAME`         | `1`     | Set to `0` to skip blame analysis        |
| `ENABLE_AUTO_SKIP`         | `1`     | Set to `0` to disable auto-skip logic    |
| `SECURITY_REVIEW_THRESHOLD`| `80`    | Minimum confidence score to report       |

## Examples

### Basic review
```
/security-review
```

### Review specific PR
```
/security-review --pr 123
```

### Review without git blame (faster)
```
ENABLE_GIT_BLAME=0 /security-review
```

### Show all issues regardless of confidence
```
ENABLE_CONFIDENCE_SCORING=0 /security-review
```

## Policy File Format

Policy files use markdown with rules as bullet points:

```markdown
# Acme Security Rules

- All database queries must use parameterized statements
- API keys must never appear in logs
- User input must be validated against allowlist
- Error responses must not leak stack traces
```

Rules are appended to the review prompt in order: user → project → project-local.
