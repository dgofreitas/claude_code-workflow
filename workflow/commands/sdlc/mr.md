---
description: Create a comprehensive merge request / pull request with full context and traceability
argument-hint: [base-branch]
---

# /mr — Create Merge Request

Delegate to the **merge-request-creator** subagent to generate a comprehensive, well-structured MR/PR. If no base branch is specified, defaults to `main`.

## Action

Invoke the `merge-request-creator` subagent via the Task tool:

> Create a comprehensive MR/PR for current branch against **$ARGUMENTS** (default: main). Aggregate all agent outputs, implementation reports, test results, and review findings.

## merge-request-creator will

- Analyze git log and diff against base branch
- Collect implementation reports from story docs
- Aggregate test results and coverage metrics
- Include code review findings and resolutions
- Create MR/PR via `gh pr create` or `glab mr create`

## Output

A merge request created on the remote with: summary of changes, linked story/issue references, implementation details, test coverage metrics, review findings summary, screenshots (if UI changes), and a reviewer checklist.
