---
description: Create a structured user story from a feature request, bug report, or spike
argument-hint: <description of what needs to be done>
---

# /story — Create User Story

Delegate to the **product-manager** subagent to transform a feature request, bug report, or spike into a structured, actionable user story.

## Action

Invoke the `product-manager` subagent via the Task tool:

> Analyze and create structured user stories for: **$ARGUMENTS**. If the input contains MULTIPLE epics or features, create ONE separate story per epic/feature.

## product-manager will

- Analyze input scope (single feature vs. multiple epics/features)
- If multi-epic input: decompose into separate stories (STORY-001, STORY-002, etc.)
- Write each story with title, description, acceptance criteria (GIVEN-WHEN-THEN)
- Define Definition of Done per story
- Map cross-story dependencies
- Output each story to `artifacts/stories/STORY-XXX.md`
- Output backlog summary to `artifacts/stories/BACKLOG-SUMMARY.md` (if multiple stories)

## Output

One or more markdown story files at `artifacts/stories/STORY-XXX.md`, each containing:

- Story type and title
- User story (As a / I want / So that)
- Acceptance criteria (GIVEN-WHEN-THEN format, 3-8 per story)
- Technical notes and constraints
- Dependencies (within and across stories)
- Definition of Done

When multiple stories are created, a `artifacts/stories/BACKLOG-SUMMARY.md` is also generated with the full story list (IDs, priorities, estimates), dependency graph, and suggested implementation order.
