<!-- Context: workflows/component-planning | Priority: high | Version: 2.0 | Updated: 2026-05-02 -->
<!-- Source of truth: /HOW_IT_WORKS.md (Architect role + technical-analysis output).
     This file = two-level planning technique used by Architect within SDLC. -->

# Component-Based Planning

**Purpose**: Two-level technique to avoid monolithic upfront planning. Used by `Architect` when a story is too large for a single technical-analysis pass.

**Used by**: `Architect` (primary) | `TechLead` (when refining execution mid-story).

---

## Philosophy

> **"Plan the system, build the component."**

Don't write a detailed plan for the whole system upfront. Create a high-level roadmap, then zoom in to plan one component in detail before executing it.

---

## Two-level structure

### Level 1 — Master plan (roadmap)

**File:** `docs/stories/STORY-XXX/master-plan.md` (within SDLC) or `.tmp/sessions/{id}/master-plan.md` (non-SDLC).

**Content:**

- System architecture diagram (ASCII or mermaid)
- Component list (e.g., Auth, Database, API, UI)
- Dependency order (what must be built first?)
- Global standards/decisions (versions, conventions)

### Level 2 — Component plan (active spec)

**File:** `docs/stories/STORY-XXX/component-{name}.md` or `.tmp/sessions/{id}/component-{name}.md`.

**Content:**

- **Interface definition** — types, function signatures, API contracts
- **Test strategy** — specific cases to test
- **Task list** — atomic steps (per `feature-breakdown.md`)
- **Verification** — binary done checks

---

## Workflow

### Phase 1: System design (master plan)

1. Analyze full feature request.
2. Decompose into functional components (e.g., "User Service", "Email Worker", "Frontend Form").
3. Draft `master-plan.md`.
4. Get user approval on architecture and order (this is part of **Gate #2** in SDLC).

### Phase 2: Component execution loop

Repeat per component:

1. Select next unblocked component from master plan.
2. Draft `component-{name}.md`:
   - Define exact interface/types first
   - List atomic tasks (≤2h each, per `feature-breakdown.md`)
3. Get approval on the detailed component plan (internal to Gate #2 — Architect to user; or TechLead during execution refinement).
4. Execute via `TechLead` delegation.
5. Update `master-plan.md` to mark component complete.

---

## When to use

- **Complex features** — >3 files, multiple layers (DB + API + UI)
- **Unknowns** — later parts depend on earlier decisions
- **Large scope** — >2h estimated effort
- **Cross-cutting** — shared contracts between components

For simpler features: use `feature-breakdown.md` directly without two-level structure.

---

## Example master plan

```markdown
# Master Plan: E-Commerce Checkout

## Architecture
[Cart] → [Order Service] → [Payment Gateway]
                       → [Inventory Service]

## Component Order
1. [ ] **Inventory Service** — check stock
2. [ ] **Order Service** — create order record
3. [ ] **Payment Integration** — Stripe
4. [ ] **Checkout UI** — React components

## Global Decisions
- Node 20 + TypeScript strict
- Postgres + Drizzle ORM
- Stripe SDK v17
- Coverage ≥90%
```

## Example component plan

```markdown
# Component: Inventory Service

## Interface
```typescript
interface InventoryManager {
  checkStock(sku: string): Promise<boolean>;
  reserve(sku: string, quantity: number): Promise<void>;
}
```

## Tasks

- [ ] Define `InventoryManager` interface in `src/types.ts`
- [ ] Create mock for tests
- [ ] Implement `checkStock` with DB query
- [ ] Add unit tests for race conditions

## Verification

- [ ] Type check passes
- [ ] All tests green, coverage ≥90%
- [ ] Concurrent reserve doesn't oversell

```

---

## Integration with SDLC

| SDLC stage | Component-planning artifact |
|------------|----------------------------|
| Architect (after Gate #1) | Produces `master-plan.md` + initial `component-*.md` for first component |
| TechLead (during execution) | Generates next `component-{name}.md` as components unlock |
| TaskManager | Converts each `component-{name}.md` → `subtask_NN.json` |

---

## Related

- `context/workflows/feature-breakdown.md` — Atomic task decomposition
- `context/workflows/tasks.md` — JSON schema for subtasks
- `context/workflows/task-delegation.md` — How TechLead delegates each component
