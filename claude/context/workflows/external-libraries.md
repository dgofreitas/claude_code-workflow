<!-- Context: workflows/external-libraries | Priority: high | Version: 3.1 | Updated: 2026-05-02 -->
<!-- Source of truth: /HOW_IT_WORKS.md §2 (ExternalScout mandatory).
     This file = operational protocol loaded by ExternalScout/agents at runtime. -->

# External Libraries

**Purpose**: Complete workflow for fetching, caching, integrating, and troubleshooting external library documentation via ExternalScout.

---

## Overview

External libraries = any npm/pip/gem/cargo package, third-party framework, ORM, auth lib, UI lib — anything NOT in your project's source code.

**Rule**: If it's not in `.claude/context/`, fetch docs via ExternalScout. Never rely on training data — it's outdated.

ExternalScout sources: **Context7 API** (primary, 50+ popular libraries) → **official docs via webfetch** (fallback for anything else).

Persisted to `.tmp/external-context/{package-name}/{topic}.md` with metadata header. Cache window: 7 days.

---

## Workflow

### 1. Delegate to ExternalScout

```javascript
task(
  subagent_type="ExternalScout",
  description="Fetch [Library] docs for [specific topic]",
  prompt="Fetch current documentation for [Library]: [specific question]

  Focus on:
  - [What you need - be specific]
  - [Related features/APIs]

  Context: [What you're building, framework, deployment target]"
)
```

**Good prompt**: Specific | Focused (3–5 items) | Contextual.
**Bad prompt**: Vague | Too broad | No tech-stack context.

### 2. Cache behavior

ExternalScout Stage 0 checks:

1. `.claude/context/INDEX.md` — if the library is already covered internally, return internal path (no external fetch)
2. `.tmp/external-context/{package}/` — if fresh (<7 days), return cached files
3. Otherwise → fetch Context7 → fallback to official docs

### 3. Persisted file format

```markdown
---
source: Context7 API
library: Drizzle ORM
package: drizzle-orm
topic: modular-schemas
fetched: 2026-01-28T14:30:22Z
official_docs: https://orm.drizzle.team/docs/goodies#multi-file-schemas
---

# Modular Schemas in Drizzle ORM
[Filtered documentation content]
```

Plus `.tmp/external-context/.manifest.json` tracking all fetched packages.

### 4. Combine with ContextScout

Use BOTH for most features:

```javascript
task(subagent_type="ContextScout", ...)   // project standards
task(subagent_type="ExternalScout", ...)  // library docs
// then implement using both
```

---

## FAQ

**When exactly should I use ExternalScout?**
Always when working with external packages. Triggers: user mentions a library, new `import`/`require`, new `package.json` dep, build error, first-time setup, version upgrade.

**What if I already know the library?**
Don't trust training data. Example: "I know Next.js, I'll use pages/" → reality: Next.js 15 uses app/ → broken code. Always fetch current docs.

**How do I know if something is external?**
In `package.json`/`requirements.txt`/`Gemfile` → external. Project utilities/internal modules → not external.

**What if ExternalScout doesn't have the library?**
Auto-fallback: Context7 → webfetch on official docs. Works for any library with public documentation.

**Do I need approval to use ExternalScout?**
No — read/fetch only. Approval required only for write/edit/bash operations downstream.

**ContextScout vs ExternalScout?**
ContextScout = internal project standards (fast, local). ExternalScout = external library APIs (slower, network). Use together.

---

## Scenarios

### Scenario 1 — New build with external packages (e.g., Next.js + Drizzle + Better Auth)

1. Check `scripts/install/` for install scripts
2. ExternalScout per package with tech-stack context ("Drizzle setup with PostgreSQL for Next.js commerce")
3. Verify version compatibility
4. Implement following current docs

### Scenario 2 — Package error during build

`Error: Cannot find module 'drizzle-orm/pg-core'`

1. ExternalScout: "Fetch Drizzle docs: PostgreSQL imports"
2. Verify current import patterns and package.json deps
3. Propose fix → request approval → apply

### Scenario 3 — First-time package setup

1. Check install scripts first
2. ExternalScout: install steps + peer deps + config + patterns
3. If install script exists → run it; else → manual per docs

### Scenario 4 — Version upgrade (e.g., Next.js 14 → 15)

1. ExternalScout: "Fetch Next.js 15 docs: Breaking changes and migration"
2. Identify affected code → plan migration → apply → test

### Error-handling patterns

| Error type | Process |
|------------|---------|
| Installation | ExternalScout: install docs → verify package name/version → check peer deps |
| Import/Module | ExternalScout: import patterns → check current API exports |
| API/Configuration | ExternalScout: API docs → check current signatures |
| Build errors | Identify package → ExternalScout: relevant docs + known issues |

---

## Cleanup

External context in `.tmp/external-context/` should be cleaned when:

- Task complete and session deleted
- Docs stale (>7 days)
- User explicitly requests cleanup
- Disk pressure

```bash
rm -rf .tmp/external-context/{package-name}/
# then update .tmp/external-context/.manifest.json
```

Files are **read-only for all agents** except ExternalScout itself.

---

## Quick Checklist

Before implementing with external libraries:

- [ ] ContextScout for project standards?
- [ ] Checked for install scripts?
- [ ] ExternalScout for EACH external library?
- [ ] Asked for installation + current API + integration patterns?
- [ ] Read returned docs before coding?

---

## Related

- `agent/subagents/core/externalscout.md` — ExternalScout agent
- `skills/context7/library-registry.md` — Supported libraries + IDs
- `context/workflows/task-delegation.md` — Delegation workflow
- `context/workflows/session-management.md` — Session lifecycle
