---
description: Run QA validation against acceptance criteria for a story
argument-hint: <story-file-path>
---

# /qa — Quality Assurance Validation

Delegate to the **qa-analyst** subagent to validate that an implementation meets all acceptance criteria from the story.

## Action

Invoke the `qa-analyst` subagent via the Task tool:

> Validate implementation against acceptance criteria for: **$ARGUMENTS**

## qa-analyst will

- Read the PM story and extract acceptance criteria
- Execute automated tests (if available)
- Validate each GIVEN-WHEN-THEN criterion
- Check Definition of Done checklist
- Produce a QA report with pass/fail per criterion

## Output

A QA validation report: pass/fail status per acceptance criterion, test execution results, Definition of Done checklist status, blocking issues (if any), and recommendation (APPROVE or REJECT with reasons).
