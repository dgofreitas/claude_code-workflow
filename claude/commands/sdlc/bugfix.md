---
description: Diagnose and fix a bug using language-specific bug fixer agents
argument-hint: <bug description or error message>
---

# /bugfix — Bug Diagnosis and Fix

Route to the appropriate **bug-fixer** subagent based on project language to diagnose and fix a bug with root-cause analysis.

## Workflow

1. **Detect language** from project files.
2. **Route to the appropriate bug fixer**:
   - Node.js/TypeScript → `bug-fixer-nodejs`
   - Other languages → use the matching `bug-fixer-<lang>` agent only if present in `.claude/agents/` (e.g. `bug-fixer-python`, `bug-fixer-c`); otherwise default to `bug-fixer-nodejs`
3. **Invoke the bug fixer** via the Task tool:

   > Diagnose and fix the following bug: **$ARGUMENTS**

## The bug fixer will

- Call context-scout for project context
- Reproduce the bug (if possible)
- Perform root-cause analysis
- Propose a minimal, non-breaking fix
- Write regression tests
- Validate the fix

## Output

A bug fix report: root cause analysis, fix description (minimal, non-breaking), files modified, regression tests added, and validation results.
