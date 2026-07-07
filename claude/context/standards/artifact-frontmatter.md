<!-- Context: standards/artifact-frontmatter | Priority: high | Version: 1 | Updated: 2026-07-07 -->
# Artifact Frontmatter Standard

> Every SDLC artifact written under `artifacts/` MUST start with a YAML frontmatter
> block. Frontmatter is **identity + lineage — NOT mutable state**. It is written once
> by the generating agent and does not change afterwards. The **only** exception is the
> checkpoint file, which is the single mutable source of truth (see below).
>
> This is what powers the Obsidian **Bases** board (`story-board.base`) and any generated
> `INDEX.md`: a flat query over the frontmatter of every artifact.

## Golden rules

1. **Identity, not state.** Do NOT duplicate progress/status into story/report frontmatter.
   Progress lives in ONE place: the checkpoint. Everything else is an immutable snapshot.
2. **Write once.** The agent that creates the file writes the frontmatter and never rewrites it.
3. **Never invent fields.** Use only the fields below. Unknown keys break the board.
4. **`docs/` is off-limits** for SDLC artifacts — it is real project documentation (Swagger/ADR).
   All frontmatter'd artifacts live under `artifacts/`.

## Common fields (every artifact)

```yaml
---
id: STORY-042              # or EPIC-003 — the entity this file belongs to
type: story               # see "type" table below
title: Cadastro de licença # human title — "know the story at a glance"
development: licenciamento-v2  # grouping label; falls back to the Parent Epic id
epic: EPIC-003            # formal epic link when one exists (optional)
generated_by: product-manager  # the agent that wrote this file
schema_version: 1
created: 2026-07-07        # immutable
---
```

## `type` values (one per artifact kind)

| type | File | Written by |
|------|------|------------|
| `epic` | `EPIC-XXX.md` | product-owner |
| `story` | `STORY-XXX.md` | product-manager |
| `technical-analysis` | `STORY-XXX-technical-analysis.md` | architect |
| `code-analysis` | `STORY-XXX-code-analysis.md` | code-analyzer |
| `ux-spec` | `STORY-XXX-ux-spec.md` | ux-designer |
| `checkpoint` | `STORY-XXX-checkpoint.md` | tech-lead (skill) |
| `test-report` | `STORY-XXX-test-report.md` | test-engineer |
| `qa-report` | `STORY-XXX-qa-report[-rN].md` | qa-analyst |
| `code-review` | `STORY-XXX-code-review[-rN].md` | code-reviewer |
| `impl-report` | `STORY-XXX-impl-report.md` | backend/frontend developer, bug-fixer |

## Per-type extra fields

- **Reports** (`test-report`, `qa-report`, `code-review`, `impl-report`): add `story: STORY-XXX`.
- **Versioned reports** (`qa-report`, `code-review`): add `revision: r2` (each `-rN` is a new file).
- **checkpoint** — the ONLY mutable artifact. It additionally carries the live board fields,
  updated by tech-lead as the story crosses each gate:

  ```yaml
  ---
  id: STORY-042
  type: checkpoint
  story: STORY-042
  title: Cadastro de licença
  development: licenciamento-v2
  epic: EPIC-003
  status: in-qa        # board status — see lifecycle below
  coverage: 94         # % from test-engineer; omit until GATE 2
  schema_version: 1
  updated: 2026-07-07  # bumped on every checkpoint write
  ---
  ```

### checkpoint `status` lifecycle (board column)

| value | set when | by |
|-------|----------|----|
| `in-progress` | checkpoint created (implementation) | tech-lead |
| `in-qa` | GATE 2 passed (tests green), QA pending/running | tech-lead |
| `in-review` | GATE 3 passed (QA PASSED), review pending/running | tech-lead |
| `ready` | GATE 4 passed (review APPROVED), MR pending / DONE handoff | tech-lead |
| `merged` | MR created (the delivery milestone) | merge-request-creator |
| `blocked` | any gate BLOCKED / story blocked | tech-lead |

> `status`/`coverage`/`updated` are the ONLY frontmatter values that ever change, and only
> in the checkpoint. This keeps a single source of truth while giving the board live data.

## Who writes the frontmatter (source vs derived)

The contract lives in code, not in every agent prompt (same move the repo made for RTK).

- **Source artifacts** — frontmatter written by the generating agent, because `development` /
  `status` are human/orchestration decisions that must originate somewhere:
  - `epic` → product-owner
  - `story` → product-manager (owns the `development` grouping label)
  - `checkpoint` → tech-lead skill (owns mutable `status` / `coverage`)
  - plus merge-request-creator flips `status: merged` on the checkpoint.
- **Derived artifacts** — frontmatter auto-injected by the `artifact-frontmatter.js` PreToolUse
  hook on `Write`. The hook derives `type`/`id`/`revision`/`layer` from the filename and copies
  `title`/`development`/`epic` from the sibling `STORY-<id>.md`. These agents need NO frontmatter
  instruction: architect, code-analyzer, ux-designer, test-engineer(-python), qa-analyst,
  code-reviewer(-python), and the implementation/bug-fixer agents (impl-report).

## Migration (older artifacts)

Files without frontmatter are treated as `schema_version: 0`. Source-artifact agents prepend the
block on the next legitimate write; derived artifacts get it from the hook. Do NOT bulk-rewrite
historical artifacts — frontmatter is added only on the next write.
