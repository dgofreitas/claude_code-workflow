<!-- Context: workflows/sessions | Priority: medium | Version: 3.0 | Updated: 2026-05-02 -->
<!-- Source of truth: /HOW_IT_WORKS.md (3-gate SDLC) + workflows/task-delegation.md (canonical session model).
     This file = session lifecycle protocol. Aligned: ID format, structure, cleanup. -->

# Session Management

**Purpose**: Lifecycle of `.tmp/sessions/{id}/` — when to create, what to put inside, how to clean up.

---

## Quick Reference

- **When to create**: only for approved, multi-file tasks (4+ files, >60 min) or when delegating to TaskManager. Skip for 1–3 file tasks.
- **Session ID**: `{YYYY-MM-DD}-{slug}` (e.g., `2026-05-02-user-auth`). Slug = kebab-case, ≤30 chars.
- **Lazy init**: only on first delegation that needs persisted context.
- **Cleanup**: ask user, then delete entire session dir.
- **Safety**: NEVER touch files outside current session.

---

## Structure

```
.tmp/sessions/{YYYY-MM-DD}-{slug}/
├── context.md           # Single source of context for this session
├── .manifest.json       # Tracks files, cache, activity
└── .cache/              # Optional — cached standards (see task-delegation.md)
    ├── code-quality.md
    └── test-coverage.md
```

**Single `context.md` model** (replaces older `features/code/tasks/general/` subdirs). One context file = one cognitive entry point per session.

---

## context.md template

See `workflows/task-delegation.md` §Session Context Template. Canonical structure:

```markdown
# Task Context: {Task Name}

Session ID: {YYYY-MM-DD}-{slug}
Created: {ISO timestamp}
Status: in_progress

## Current Request
{verbatim or close paraphrase}

## Context Files (Standards)
- context/standards/code-quality.md

## Reference Files (Source)
- src/existing-module.ts

## External Context Fetched
- .tmp/external-context/{package}/{topic}.md

## Components / Constraints / Exit Criteria
{...}
```

---

## Manifest

`.tmp/sessions/{id}/.manifest.json`:

```json
{
  "session_id": "2026-05-02-user-auth",
  "created_at": "2026-05-02T14:30:22Z",
  "last_activity": "2026-05-02T14:35:10Z",
  "context_files": ["context.md"],
  "delegations": [
    { "agent": "TaskManager", "at": "2026-05-02T14:32:00Z" },
    { "agent": "BackendDeveloper", "at": "2026-05-02T14:33:10Z" }
  ],
  "cache": {
    "code-quality.md": {
      "source": "context/standards/code-quality.md",
      "cached_at": "2026-05-02T14:30:25Z",
      "status": "valid"
    }
  }
}
```

Update `last_activity` after each delegation or context write.

---

## Lifecycle

```
1. CREATE  → on first delegation needing persisted context
2. WRITE   → context.md + manifest.json
3. DELEGATE → pass session path to specialist (no re-discovery)
4. CACHE   → optional, for repeated standards across subtasks
5. CLEANUP → ask user → delete entire session dir
```

---

## Isolation rules

- ✅ Multiple sessions can coexist (different IDs)
- ✅ Each session reads/writes only its own dir
- ✅ Cleanup deletes only own session folder
- ❌ NEVER access files from another session
- ❌ NEVER delete `.tmp/sessions/` root or sibling sessions

---

## Cleanup

### Manual (preferred)

After task completion:

1. Ask: "Should I clean up `.tmp/sessions/{id}/`?"
2. Wait for confirmation.
3. `rm -rf .tmp/sessions/{id}/`.

### Stale auto-cleanup

Sessions with `last_activity` >24h old are safe to auto-remove. See `scripts/cleanup-stale-sessions.sh` if present.

### Safety

- NEVER delete outside current session.
- ONLY delete files tracked in own manifest.
- ALWAYS confirm before destructive ops.

---

## Error handling

| Error | Action |
|-------|--------|
| Subagent failure | Report → ask user retry/abort. No auto-retry. |
| context.md write fail | Fall back to inline context in delegation prompt; warn user. |
| Session creation fail | Continue without session; warn user; use inline context. |

---

## Best practices

1. **Lazy init** — only when needed.
2. **One context.md per session** — no proliferation of subdirs.
3. **Update activity** — touch `last_activity` on every op.
4. **Confirm cleanup** — never silent delete.
5. **Cache standards only** — never cache external library docs (always fresh).

---

## Related

- `context/workflows/task-delegation.md` — DISCOVER→DELEGATE flow, context.md template, cache rules
- `context/workflows/tasks.md` — Task JSON schema (lives in `.tmp/tasks/`, not in sessions)
- `context/workflows/external-libraries.md` — `.tmp/external-context/` (separate from sessions)
