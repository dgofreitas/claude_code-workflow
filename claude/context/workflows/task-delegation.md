<!-- Context: workflows/task-delegation | Priority: high | Version: 1.1 | Updated: 2026-05-02 -->
<!-- Source of truth: /HOW_IT_WORKS.md (SDLC pipeline, gates, TechLead delegation rules).
     This file = operational protocol loaded by Master/TechLead at runtime.
     Session ID standard: {YYYY-MM-DD}-{slug} (canonical). Aligned with session-management.md. -->

# Task Delegation

**Purpose**: Complete guide to delegating work to subagents — from discovery through cleanup, with caching and specialist selection.

---

## Flow

```
DISCOVER → PROPOSE → APPROVE → INIT → PERSIST → DELEGATE → CLEANUP
```

1. **Discover** — ContextScout finds paths (read-only)
2. **Propose** — Show user summary (no writes yet)
3. **Approve** — User says yes; only now write anything
4. **Init** — Create `.tmp/sessions/{YYYY-MM-DD}-{slug}/context.md`
5. **Persist** — Write discovered paths into context.md
6. **Delegate** — Pass session path to specialist agent
7. **Cleanup** — Ask user, then delete session dir

**When to create a session**: only for approved, multi-file tasks (4+ files, >60 min) or when delegating to TaskManager. Simple 1–3 file tasks skip session creation.

---

## Session Context Template

Location: `.tmp/sessions/{YYYY-MM-DD}-{slug}/context.md`

```markdown
# Task Context: {Task Name}

Session ID: {YYYY-MM-DD}-{slug}
Created: {ISO timestamp}
Status: in_progress

## Current Request
{What user asked — verbatim or close paraphrase}

## Context Files (Standards)
- .claude/context/standards/code-quality.md
- .claude/context/standards/test-coverage.md

## Reference Files (Source)
- src/existing-module.ts
- package.json

## External Context Fetched
- .tmp/external-context/{package}/{topic}.md — {description}

## Components
- {Component} — {role}

## Constraints
{Versions, preferences, technical limits}

## Exit Criteria
- [ ] {specific completion condition}
```

### Semantic rules (never mix)

| Field | Contains | Example |
|-------|----------|---------|
| `context_files` | **Standards only** | `.claude/context/standards/code-quality.md` |
| `reference_files` | **Source material only** | `src/auth/service.ts` |
| `external_context` | **External docs only** | `.tmp/external-context/drizzle/schemas.md` |

---

## Choosing a Specialist

Route by domain, not by agent name familiarity.

| Task type | Specialist |
|-----------|------------|
| Node.js server code | `BackendDeveloper` |
| Python server code | `BackendDeveloperPython` |
| C systems code | `BackendDeveloperC` |
| React/Next.js UI | `FrontendDeveloperReact` |
| Vue/Nuxt UI | `FrontendDeveloperVue` |
| Angular UI | `FrontendDeveloperAngular` |
| Generic frontend | `FrontendDeveloper` |
| Bug fix (Node.js) | `BugFixerNodejs` |
| Bug fix (Python) | `BugFixerPython` |
| Bug fix (C) | `BugFixerC` |
| Tests (any stack) | `TestEngineer` / `PytestTester` |
| Code review | `CodeReviewer` (plus `CodeReviewerPython`/`CodeReviewerC`) |
| Codebase analysis | `CodeAnalyzer` (plus language variants) |
| Story planning | `ProductManager` → `Architect` → `TechLead` |
| MR/PR creation | `MergeRequestCreator` |
| QA validation | `QAAnalyst` |
| Documentation | `DocWriter` |

**Route by stack first, then by task.** If stack isn't clear, default to generic variant.

---

## Delegate Call

```javascript
task(
  subagent_type="TaskManager",
  description="{short action}",
  prompt="Load context from .tmp/sessions/{session-id}/context.md

  Task: {specific instructions}

  Expected output: {deliverables}"
)
```

Downstream agents read `context.md` — no re-discovery.

| Agent | Reads | Does |
|-------|-------|------|
| TaskManager | `context.md` | Extract files, create subtask JSONs |
| BackendDeveloper | subtask JSON | Load standards, reference source, implement |
| TestEngineer | session path | Write tests against same standards |
| CodeReviewer | session path | Review against applied standards |

---

## Context Caching

Cache discovered context inside the session to avoid re-reads across parallel or repeated subtasks.

**Cache when**: same task type repeats in session | same context files needed by multiple subtasks | parallel tasks share standards.

**Skip cache when**: single-task session (overhead not worth it) | external context (always fetch fresh).

### Cache layout

```
.tmp/sessions/{session-id}/
├── context.md
├── .cache/
│   ├── test-coverage.md         # copied from .claude/context/standards/
│   └── code-quality.md
└── .manifest.json
```

### Manifest

```json
{
  "session_id": "2026-05-02-parallel-tests",
  "created_at": "2026-05-02T14:30:22Z",
  "cache": {
    "test-coverage.md": {
      "source": ".claude/context/standards/test-coverage.md",
      "cached_at": "2026-05-02T14:30:25Z",
      "used_by": ["subtask_01", "subtask_02"],
      "status": "valid"
    }
  }
}
```

### Invalidation rules

Cache is **invalid** when: source file modified (timestamp mismatch) | session >24h old | source version changed | user requests refresh.

Pattern:

```
IF cache exists AND valid → use cached file (skip read)
ELSE → read from .claude/context/ → cache it
```

### Do / Don't

- ✅ Cache standards for repeated task types
- ✅ Validate cache before using
- ✅ Monitor hit rate
- ✅ Cleanup cache with session
- ❌ Cache external context (always fresh)
- ❌ Cache for single-task sessions
- ❌ Mix cached and fresh context in same task

---

## Related

- `.claude/context/workflows/tasks.md` — Task JSON schema, lifecycle, CLI
- `.claude/context/workflows/external-libraries.md` — ExternalScout workflow
- `.claude/context/meta/mvi.md` — MVI principle
