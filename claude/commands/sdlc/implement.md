---
description: Execute a planned story through the full SDLC pipeline (tech-lead coordination)
argument-hint: <story-file-path>
---

# /implement — Execute Story Implementation

Coordinate the full implementation of a story using the **tech-lead** skill, which manages specialized subagents across the pipeline.

## Action

Use the **tech-lead** skill to orchestrate the story:

> Execute full implementation for story: **$ARGUMENTS**

> **Note:** `tech-lead` is a Skill (runs in the main context, which has the Task tool). It is NOT a subagent — do not invoke it via `Task(subagent_type=...)`. The skill itself delegates to the specialist subagents.

## tech-lead will

- Read the PM story and technical analysis
- Detect project stack and route to language-specific agents
- Execute implementation batches:
  - Delegate to `backend-developer` variants for implementation
  - Delegate to `frontend-developer` variants for UI work
  - Delegate to `test-engineer` variants for test creation
  - Delegate to `code-reviewer` variants for quality review
- Enforce gates (Domain → Tests → QA → Review → MR) before advancing
- Ensure Definition of Done is met

## Prerequisites

- A story file should exist (run `/story` first)
- A technical analysis should exist (run `/plan` first)
- Both are recommended but not strictly required

## Output

- Implementation complete with tests passing
- Implementation reports from each agent
- Ready for QA validation
