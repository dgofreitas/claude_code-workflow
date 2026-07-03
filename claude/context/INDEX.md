<!-- Context: INDEX | Priority: critical | Version: 2.0 | Updated: 2026-05-02 -->
# Context Index

> **Flat semantic index — single navigation entry point.**
> Format: `path | tags: ... | summary: one-line description`
>
> Read this file first. Then read only the leaf files matching the task.
> 5 buckets, flat: no subdirectory navigation files.

---

## 🧭 Bucket Guide

| Bucket | Answers | When to read |
|--------|---------|--------------|
| `standards/` | How do I write code well? | Writing/reviewing code |
| `workflows/` | What's the process for X? | Delegating tasks, running reviews, external libs |
| `stacks/` | How does this tech work? | Tech-specific implementation |
| `meta/` | How does the context system work? | Maintaining context files |
| `project/` | What's specific to this project? | Onboarding, decisions, current state |

---

## standards/ — How to write code

- `standards/essential-patterns.md` | tags: patterns, core, fundamentals, critical | summary: Cross-cutting patterns every agent should know.
- `standards/code-quality.md` | tags: quality, code, review, critical | summary: Universal code quality rules for writing/reviewing code.
- `standards/clean-code.md` | tags: clean-code, principles, naming, functions, comments, quality, code, review, maintainability | summary: Local quality rules — names, functions, nesting, comments; Boy Scout Rule.
- `standards/design-patterns.md` | tags: patterns, gof, creational, structural, behavioral, catalog, quality, code, review, maintainability, design | summary: Prescriptive GoF pattern catalog — intent, when to use, when NOT to (overengineering traps), minimal shape.
- `standards/code-smells-refactoring.md` | tags: smells, refactoring, fowler, legacy, review, quality, code, code-quality, maintainability, code-review | summary: Fowler smell catalog mapped to refactoring moves; safety principle (green tests, small steps); review reporting convention.
- `standards/api-design.md` | tags: api, design, rest, principles | summary: API design principles and patterns.
- `standards/test-coverage.md` | tags: tests, coverage, critical | summary: Testing standards across stacks.
- `standards/security.md` | tags: security, patterns, auth | summary: Security best practices and review checklist.
- `standards/documentation.md` | tags: docs, writing | summary: Documentation standards.
- `standards/code-analysis.md` | tags: analysis, code, debugging | summary: Code analysis approaches for debugging and review.
- `standards/dockerfile-patterns.md` | tags: docker, dockerfile, multi-stage, non-root, healthcheck, dumb-init | summary: Production-grade Dockerfile patterns — multi-stage builds, non-root user, signal handling, build-args.

## workflows/ — Processes to follow

- `workflows/code-review.md` | tags: review, code, workflow | summary: Code review process.
- `workflows/component-planning.md` | tags: planning, component | summary: Component-level planning workflow.
- `workflows/feature-breakdown.md` | tags: features, breakdown, planning | summary: Breaking complex features into 4+ files.
- `workflows/session-management.md` | tags: session, init, cleanup | summary: Session lifecycle and cleanup.
- `workflows/task-delegation.md` | tags: delegation, agents, specialists, caching, task-tool | summary: Full delegation flow — discovery, session, specialist routing, caching.
- `workflows/tasks.md` | tags: tasks, schema, lifecycle, cli, json, critical | summary: Task JSON schema, lifecycle, decomposition, CLI reference.
- `workflows/external-libraries.md` | tags: external, docs, fetch, cache, libraries, context7 | summary: ExternalScout workflow — fetching, caching, scenarios, FAQ.

## stacks/ — Technology-specific

- `stacks/system-architecture.md` | tags: greenfield, scaffold, stack-decision, architecture | summary: Stack selection framework and decision criteria for SystemArchitect.
- `stacks/nodejs.md` | tags: nodejs, backend, structure, mandatory | summary: Mandatory project structure for new Node.js services.
- `stacks/nodejs-domain-structure.md` | tags: nodejs, backend, domain, dispatchers, mongoose, shared, advanced | summary: Advanced domain-driven backend — dispatchers, Mongoose plugins, cross-domain coordination.
- `stacks/python.md` | tags: python, backend, structure, mandatory, fastapi, django | summary: Mandatory project structure for new Python backend services (FastAPI/Flask layered vs Django app-based).
- `stacks/react.md` | tags: react, patterns, nextjs, frontend | summary: React/Next.js patterns and best practices.
- `stacks/react-domain-structure.md` | tags: react, frontend, context, hooks, pwa, offline, vite | summary: Context-per-domain + useXxx hooks + PWA offline-first patterns.
- `stacks/frontend.md` | tags: frontend, delegation, when-to-use | summary: When to delegate UI tasks to FrontendDeveloper.
- `stacks/ui-styling.md` | tags: styling, ui, tailwind, flowbite, css, standards | summary: UI styling standards — Tailwind + Flowbite + responsive.
- `stacks/design-systems.md` | tags: design-systems, themes, oklch, css, templates | summary: Reference theme templates (Neo-Brutalism, Modern Dark Mode) and design tokens.
- `stacks/fullstack-containerized.md` | tags: docker, compose, nginx, mongo, redis, blueprint, architecture | summary: Fullstack blueprint — nginx + Node + React + Mongo + Redis with network isolation.
- `stacks/mastra-ai.md` | tags: mastra, ai, agents, workflows, tools, storage | summary: Mastra AI complete reference — core, agents, workflows, storage, testing.

## meta/ — About the context system

- `meta/overview.md` | tags: context, system, overview, critical | summary: How the context system works, the 5 buckets, how agents use it.
- `meta/mvi.md` | tags: mvi, standards, limits | summary: Minimum Viable Information standard (≤200 lines, <30s scan).
- `meta/structure.md` | tags: structure, standards, paths | summary: File and directory structure rules.
- `meta/frontmatter.md` | tags: frontmatter, metadata | summary: Frontmatter schema for context files.
- `meta/creation.md` | tags: creation, templates, new-context, workflow | summary: How to create new context files — templates, naming, MVI, frontmatter.
- `meta/operations.md` | tags: operations, harvest, extract, organize, update, migrate, error | summary: Maintenance operations — harvest, extract, organize, update, migrate, error.

## project/ — This specific project

- `project/intelligence-guide.md` | tags: intelligence, onboarding, governance | summary: How to use and maintain the project-intelligence bucket.
- `project/business-domain.md` | tags: business, domain, problem, users | summary: Business domain knowledge — problem, users, value.
- `project/technical-domain.md` | tags: technical, domain, stack, architecture | summary: Technical domain knowledge — stack, architecture, patterns.
- `project/business-tech-bridge.md` | tags: business, tech, bridge, mapping | summary: How business goals map to technical decisions.
- `project/decisions-log.md` | tags: decisions, log, adr, rationale | summary: Log of architectural and product decisions with rationale.
- `project/living-notes.md` | tags: notes, living, debt, issues | summary: Living notes — active issues, tech debt, open questions.

---

## 🧠 How agents use this index

1. **Read** `INDEX.md` (this file) — 1 read.
2. **Filter** entries by tags matching user intent.
3. **Rank** by priority tags: `critical` → `mandatory` → remaining.
4. **Return** up to 5 leaf files. If more match, report "N more available on demand".
5. **If a library/framework is mentioned and no entry matches** → recommend ExternalScout.

Do **not** navigate subdirectories. Do **not** open files not in this index. The index is the map.
