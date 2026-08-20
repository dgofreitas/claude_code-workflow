---
description: Fix a bug through the tech-lead skill, with regression tests, QA and review
argument-hint: <bug description or error message>
---

# /bugfix — Bug Diagnosis and Fix

Invoke the **tech-lead** skill to run the fix as a real story: it picks the language-specific
bug-fixer, then drives tests, QA and review through the same gates as any other work.

> Fix the following bug: **$ARGUMENTS**

## Why through tech-lead, not straight to the bug fixer

THE SCOPE RULE (see `CLAUDE.md`): Master never calls test-engineer, qa-analyst, code-reviewer,
merge-request-creator or **bug-fixer** directly. Routing around the skill would skip the
checkpoint and every gate — the fix would land untested, unreviewed, and leave no trace of why
the code changed.

## Naming

A fix that is not part of an existing story gets its own id, and tech-lead creates the
checkpoint under it:

```
artifacts/stories/HOTFIX-<slug>.md              # e.g. HOTFIX-xirr-missing-dep
artifacts/stories/HOTFIX-<slug>-checkpoint.md
```

Use `HOTFIX-` for a production break and `BUGFIX-` for a defect found in development; the slug
is 2–4 kebab-case words. Frontmatter carries `type: hotfix` (or `bugfix`) — see
`context/standards/artifact-frontmatter.md`. A fix that belongs to a story in flight keeps that
story's id instead; do not open a second one.

## What tech-lead runs

1. **bug-fixer** (by language) — reproduce, root-cause, minimal non-breaking fix, regression test
2. **test-engineer** — GATE 2, suite green
3. **qa-analyst** — GATE 3, QA PASSED
4. **code-reviewer** — GATE 4, APPROVED
5. **merge-request-creator** — GATE 5, PR opened

## Output

Root cause, the fix and why it is minimal, files touched, the regression test that failed before
and passes after, plus the QA and review verdicts — all recorded in the checkpoint.
