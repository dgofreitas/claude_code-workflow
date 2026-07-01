---
description: Run a comprehensive code review on recent changes using language-specific reviewers
argument-hint: [files-or-scope]
---

# /review — Code Review

Delegate to the appropriate **code-reviewer** variant to perform a thorough, security-aware code review.

## Workflow

1. **Detect language** from project files (package.json, pyproject.toml, CMakeLists.txt).
2. **Route to the appropriate reviewer**:
   - Node.js/TypeScript → `code-reviewer`
   - Other languages → use the matching `code-reviewer-<lang>` agent only if present in `.claude/agents/` (e.g. `code-reviewer-python`, `code-reviewer-c`); otherwise default to `code-reviewer`
3. **Invoke the reviewer** via the Task tool:

   > Review the following changes: **$ARGUMENTS**. If no specific files given, review all uncommitted changes (git diff).

## The reviewer will

- Call context-scout for project standards
- Analyze changes for security, correctness, performance, maintainability
- Produce a severity-tagged report (critical/high/medium/low)
- Suggest specific fixes for each finding

## Output

A structured review report: security findings (always first), correctness issues, performance concerns, maintainability suggestions, and suggested fixes per finding.
