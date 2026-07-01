---
description: Define tech stack and scaffold project structure for greenfield projects (system-architect)
argument-hint: [description or context]
---

# /scaffold — Project Foundation Setup

Delegate to the **system-architect** subagent to analyze NFRs, propose the tech stack, and scaffold the initial project structure.

## When to Use

- Starting a new project from scratch (no `package.json`, no build files)
- Need to define: language, framework, database, infra topology
- After PO created epics/NFRs, before PM creates stories (or after)

## Action

Invoke the `system-architect` subagent via the Task tool:

> Analyze NFRs and propose tech stack for: **$ARGUMENTS**

## system-architect will

- Read `docs/product/NFRS.md` + `docs/product/VISION.md`
- Analyze technical requirements from NFRs
- Propose complete tech stack with rationale
- ⏸️ GATE #SA: await your approval
- After approval: create `docs/architecture/TECH-STACK.md`
- Scaffold initial project structure
- Document decisions in `context/project/`

## Output

- `docs/architecture/TECH-STACK.md`
- `context/project/technical-domain.md` (filled)
- `context/project/decisions-log.md` (stack decision recorded)
- Initial project scaffolding (directories, config files)

## Next Step

After scaffold, run `/story` or `/plan EPIC-XXX` to proceed with the backlog.
