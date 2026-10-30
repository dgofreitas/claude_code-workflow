<!-- Context: workflows/tasks | Priority: critical | Version: 1.1 | Updated: 2026-05-02 -->
<!-- Source of truth: /HOW_IT_WORKS.md (TaskManager role).
     This file = JSON schema + lifecycle loaded by TaskManager at runtime. -->

# Task Management

**Purpose**: JSON-driven task system — schema, lifecycle, decomposition, and CLI reference.

Location: `.tmp/tasks/{feature-slug}/` at project root.

---

## Schema

Two file types: `task.json` (feature-level) + `subtask_NN.json` (atomic tasks).

### task.json

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | kebab-case identifier |
| `name` | string | Yes | Human-readable name (≤100) |
| `status` | enum | Yes | active / completed / blocked / archived |
| `objective` | string | Yes | One-line objective (≤200) |
| `context_files` | array | No | **Standards only** — code quality, patterns, security |
| `reference_files` | array | No | **Source only** — existing code, config, schemas |
| `exit_criteria` | array | No | Completion conditions |
| `subtask_count` | int | No | Total subtasks |
| `completed_count` | int | No | Done subtasks |
| `created_at` / `completed_at` | datetime | Yes/No | ISO 8601 |

### subtask_NN.json

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | `{feature}-{seq}` |
| `seq` | string | Yes | 2-digit (01, 02, ...) |
| `title` | string | Yes | Title (≤100) |
| `status` | enum | Yes | pending / in_progress / completed / blocked |
| `depends_on` | array | No | Sequence numbers of dependencies |
| `parallel` | bool | No | Can run alongside others |
| `context_files` | array | No | **Standards only** |
| `reference_files` | array | No | **Source only** |
| `suggested_agent` | string | No | e.g., `FrontendDeveloperReact` |
| `acceptance_criteria` | array | No | Binary pass/fail conditions |
| `deliverables` | array | No | Files to create/modify |
| `agent_id` / `started_at` / `completed_at` / `completion_summary` | various | No | Set during execution |

**Optional enhanced fields** (v2.0, backward compatible): `bounded_context`, `module`, `vertical_slice`, `contracts`, `related_adrs`, `rice_score`, `wsjf_score`.

---

## Status Transitions

```
pending → in_progress   (working agent, when deps satisfied)
in_progress → completed (TaskManager, after verification)
* → blocked             (either, when issue found)
blocked → pending       (when unblocked)
```

Status ownership: **TaskManager** sets `pending` (creation) and `completed` (after verification). **Working agent** sets `in_progress`. Either can set `blocked`.

---

## Lifecycle

```
1. Initiation    → TaskManager creates task.json + subtasks
2. Selection     → Find eligible (deps satisfied)
3. Execution     → Working agent implements
4. Verification  → TaskManager validates
5. Archiving     → Move to completed/ when done
```

### 1. Initiation

```
.tmp/tasks/{feature-slug}/
├── task.json
├── subtask_01.json
├── subtask_02.json
└── subtask_03.json
```

Validate: `task-cli.js validate {feature}`.

### 2. Selection & Execution

Working agent picks up task:

1. Read subtask JSON
2. Update `status: "in_progress"`, set `agent_id`, `started_at`
3. Load `context_files` (lazy)
4. Implement `deliverables`
5. Add `completion_summary` (≤200 chars)

Only start when all `depends_on` entries are `completed`.

### 3. Verification & Archiving

TaskManager checks each `acceptance_criteria`. If all pass → `task-cli.js complete {feature} {seq} "summary"`. When `completed_count == subtask_count` → move folder `.tmp/tasks/{slug}/` → `.tmp/tasks/completed/{slug}/`.

---

## Decomposition — Splitting Features into Tasks

### 1. Atomic boundaries

Each task must be:

- Completable in 1–2 hours
- Single clear outcome
- Independently testable
- No overlap with other tasks

Bad: "Implement authentication". Good: "Create password hashing utility".

### 2. Map dependencies

```
01 → no deps
02 → depends_on: ["01"]
03 → depends_on: ["01", "02"]
```

### 3. Identify parallel tasks

Mark `parallel: true` when the task doesn't modify shared files AND doesn't depend on runtime state of other tasks. Examples: independent unit tests, isolated utilities, docs for separate features.

### 4. Binary acceptance criteria

- ✅ "JWT tokens signed with RS256"
- ✅ "Tests pass"
- ❌ "Code is clean" (subjective)

### 5. Concrete deliverables

Files/endpoints, not adjectives: `src/auth/hash.ts`, `POST /api/login`, `tests/auth.test.ts`.

### Verification checklist

- [ ] Each task 1–2h?
- [ ] Dependencies form valid order (no cycles)?
- [ ] Parallel tasks correctly flagged?
- [ ] Criteria binary?
- [ ] Deliverables concrete?

---

## CLI Reference

Run: `node .claude/skills/task-management/scripts/task-cli.js <command> [args]`

| Command | Args | Purpose |
|---------|------|---------|
| `status` | `[feature]` | Progress summary |
| `next` | `[feature]` | Tasks ready (deps satisfied) |
| `parallel` | `[feature]` | Parallelizable tasks ready now |
| `deps` | `<feature> <seq>` | Dependency tree |
| `blocked` | `[feature]` | Blocked tasks + reasons |
| `complete` | `<feature> <seq> "summary"` | Mark done (≤200 chars) |
| `validate` | `[feature]` | JSON + deps + cycles check |

Exit codes: `0` success, `1` error.

```
# status
[my-feature] My Feature Name
  Status: active | Progress: 40% (2/5)
  Pending: 2 | In Progress: 1 | Completed: 2 | Blocked: 0

# next
=== Ready Tasks (deps satisfied) ===
[my-feature]
  02 - Create JWT service  [sequential]
  03 - Write unit tests    [parallel]

# validate
[my-feature]
  ✓ All checks passed
[broken-feature]
  ✗ ERROR: 03: depends on non-existent task 99
```

---

## Planning Agents Integration

For multi-stage story work, planning agents populate enhanced schema fields before task creation:

| Agent | Output path |
|-------|-------------|
| ArchitectureAnalyzer | `.tmp/architecture/contexts.json` |
| StoryMapper | `.tmp/story-maps/map.json` |
| PrioritizationEngine | `.tmp/backlog/prioritized.json` |
| ContractManager | `.tmp/contracts/{service}.json` |
| ADRManager | `docs/adr/` |

---

## Related

- `.claude/context/workflows/task-delegation.md` — Delegation flow + specialists + caching
- `.claude/agents/task-manager.md` — TaskManager agent
