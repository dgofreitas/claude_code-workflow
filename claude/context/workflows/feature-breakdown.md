<!-- Context: workflows/feature-breakdown | Priority: high | Version: 3.0 | Updated: 2026-05-02 -->
<!-- Source of truth: /HOW_IT_WORKS.md (SDLC: Architect produces breakdown).
     This file = breakdown technique loaded by Architect/PM/TaskManager at runtime.
     Output integrates with workflows/tasks.md (JSON schema). -->

# Feature Breakdown

**Purpose**: Decompose a feature into atomic, dependency-aware subtasks ready for `tasks.md` JSON schema.

**Used by**: `Architect` (within technical-analysis) | `ProductManager` (story sizing) | `TaskManager` (subtask creation).

---

## When to break down

- 4+ files affected
- Estimated effort >60 min
- Cross-layer (DB + API + UI)
- Dependencies between components

If <4 files and <60 min: skip breakdown, deliver as single task.

---

## Process

```
SCOPE → PHASES → ATOMIC TASKS (1–2h) → DEPENDENCIES → ESTIMATES → JSON
```

### 1. Scope

What's the complete requirement? End goal? Constraints? Out-of-scope?

### 2. Phases

Logical groupings. What must happen first? What runs in parallel?

### 3. Atomic tasks (1–2h each)

Each task must be:

- Single clear outcome
- Independently testable
- Concrete deliverables (files/endpoints, not adjectives)
- Binary acceptance criteria

Bad: "Implement authentication" → Good: "Create password hashing utility in `src/auth/hash.ts`".

### 4. Dependencies

Map `depends_on` chains. Mark `parallel: true` when no shared files and no runtime coupling.

### 5. Estimates

Realistic, include test time, add buffer. Overestimate > underestimate.

---

## Output: integrate with tasks.md

The breakdown produces input for `task.json` + `subtask_NN.json` per `workflows/tasks.md`. Map fields:

| Breakdown concept | tasks.md field |
|-------------------|----------------|
| Phase + task title | `subtask.title` |
| Files to modify | `subtask.deliverables` |
| Dependencies | `subtask.depends_on` |
| Parallel flag | `subtask.parallel` |
| Verification | `subtask.acceptance_criteria` |
| Suggested specialist | `subtask.suggested_agent` |
| Total effort | `task.objective` (informal) |

---

## Markdown template (planning artifact)

Use during planning before generating JSON. Save to `docs/stories/STORY-XXX/breakdown.md` if SDLC, else `.tmp/sessions/{id}/breakdown.md`.

```markdown
# Breakdown: {Feature}

## Overview
{1–2 sentences}

## Prerequisites
- [ ] {Prereq 1}

## Phase 1: {Name}
**Goal:** {what this phase accomplishes}

- [ ] **Task 1.1:** {description}
  - **Files:** `path/to/file.ts`
  - **Estimate:** 1h
  - **Depends on:** none
  - **Parallel:** yes
  - **Verify:** {binary check}
  - **Agent:** BackendDeveloper

- [ ] **Task 1.2:** {description}
  - **Files:** `path/to/other.ts`
  - **Estimate:** 30m
  - **Depends on:** Task 1.1
  - **Parallel:** no
  - **Verify:** Tests pass
  - **Agent:** TestEngineer

## Phase 2: {Name}
**Goal:** {...}
- [ ] **Task 2.1:** ...

## Testing strategy
- Unit: {scope}
- Integration: {flows}
- E2E: {journeys}
- **Coverage target:** ≥90% (mandatory)

## Total
**Time:** {X}h | **Complexity:** Low/Med/High
```

---

## Decomposition checklist

- [ ] Each task ≤2h?
- [ ] Dependencies form valid DAG (no cycles)?
- [ ] Parallel tasks correctly flagged (no shared files)?
- [ ] Acceptance criteria binary (pass/fail, not subjective)?
- [ ] Deliverables concrete (paths, endpoints, not adjectives)?
- [ ] Coverage target ≥90% included?
- [ ] Each task mapped to a specialist agent?

---

## Common patterns

### Database-first

1. Schema → 2. Migrations → 3. Models → 4. Business logic → 5. API → 6. Tests

### API-first (contract-driven)

1. OpenAPI spec → 2. Mock server → 3. Frontend (against mock) || Backend (impl) → 4. Integration → 5. Tests

### Vertical slice

1. Pick smallest end-to-end path → 2. Build through all layers → 3. Add next slice
   (preferred for new features — delivers value early)

### Refactor

1. Add tests for existing behavior → 2. Refactor small slice → 3. Verify green → 4. Repeat

---

## Anti-patterns

- ❌ Mega-tasks ("Implement payment system" — break into 10–15 atomic tasks)
- ❌ Hidden dependencies (always declare via `depends_on`)
- ❌ Non-binary criteria ("Code is clean" → unprovable)
- ❌ Parallel tasks touching same file (race conditions)
- ❌ Skipping test estimates (always include)

---

## Related

- `context/workflows/tasks.md` — JSON schema, lifecycle, CLI
- `context/workflows/task-delegation.md` — How to delegate after breakdown
- `context/workflows/component-planning.md` — Two-level planning (system + component)
