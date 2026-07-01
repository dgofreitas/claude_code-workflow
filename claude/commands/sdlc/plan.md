---
description: Generate a technical architecture plan and execution strategy for a user story
argument-hint: <story-file-or-description>
---

# /plan — Architecture Planning

Delegate to the **architect** subagent to analyze a user story and produce a technical execution plan with agent delegation strategy.

## Action

Invoke the `architect` subagent via the Task tool:

> Analyze and create a technical plan for: **$ARGUMENTS**

## architect will

- Read the story file (if path provided) or parse the description
- Detect project stack (language, framework, build system)
- Invoke code-analyzer for codebase pattern analysis
- Design the architecture and component plan
- Create execution batches with agent assignments
- Output technical analysis to `docs/stories/STORY-XXX-technical-analysis.md`

## Output

A technical analysis file containing: stack detection results, architecture decisions, component breakdown, execution batches (parallel/sequential ordering), agent assignments per batch (language-specific routing), and risk assessment.

## Prerequisites

- A story file should exist (run `/story` or `/epic` first)
- For greenfield projects: `docs/architecture/TECH-STACK.md` must exist (run `/scaffold` first)
