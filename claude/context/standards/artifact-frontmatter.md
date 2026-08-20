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

## Artifact naming (the `XXX` in `STORY-XXX`)

`STORY-XXX` / `EPIC-XXX` in the agent instructions means the **whole id**, never just a
number. The id is the filename, and the filename is the Obsidian graph label:
`STORY-005-30` labels a dot, `STORY-005-30-chunking-strategy` labels a story.

```
artifacts/epics/EPIC-<development-slug>.md     EPIC-market-data-backfill
artifacts/stories/STORY-<seq>-<slug>.md        STORY-005-30-chunking-strategy
  derived artifacts append their suffix to the FULL id:
     STORY-005-30-chunking-strategy-qa-report-r2.md
```

- **`<seq>`** — existing numbering, unchanged and FIRST, so the explorer keeps sorting by
  epic/date. Epic-scoped stories keep the `NNN-NN` shape (`005-30`).
- **`<slug>`** — 2–4 kebab-case words naming the implementation; the branch is exactly
  `feat/<story-id>`.
- **Fix outside a story** — `HOTFIX-<slug>` (production break) or `BUGFIX-<slug>` (defect found
  in development). No `<seq>`: a fix is not backlog-ordered. It carries a checkpoint like any
  story, and its derived artifacts append the usual suffixes.
- **Epic id** = `EPIC-` + the epic's `development` slug. No opaque `EPIC-005`.

> **Reserved suffixes.** A slug must NEVER end with a derived-artifact suffix (see the `type`
> table) or with `-rN`: `STORY-005-41-code-review.md` reads as a *code-review of*
> `STORY-005-41`. Rephrase it (`-code-review-flow`).

> **Summaries link in the body.** `EPICS-SUMMARY-<dev>` / `BACKLOG-SUMMARY-<dev>` are the
> map-of-content hubs — reference rows as `[[EPIC-x]]` / `[[STORY-x]]`, never as a markdown
> path link. `[X](/docs/stories/X.md)` is absolute-from-vault-root, dies on any folder rename,
> and resolves to nothing.

Existing numeric-only ids stay valid — this applies to artifacts created from now on, and
the two conventions coexist without a problem.

## Common fields (every artifact)

```yaml
---
id: STORY-042-license-registration   # or EPIC-licenciamento — the entity this file is about
type: story               # see "type" table below
title: Cadastro de licença # human title — "know the story at a glance"
development: licenciamento-v2  # grouping label; falls back to the Parent Epic id
epic: EPIC-licenciamento  # formal epic link when one exists (optional)
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
| `hotfix` / `bugfix` | `HOTFIX-<slug>.md` / `BUGFIX-<slug>.md` | tech-lead (skill) |
| `technical-analysis` | `STORY-XXX-technical-analysis.md` | architect |
| `code-analysis` | `STORY-XXX-code-analysis.md` | code-analyzer |
| `ux-spec` | `STORY-XXX-ux-spec.md` | ux-designer |
| `checkpoint` | `STORY-XXX-checkpoint.md` | tech-lead (skill) |
| `test-report` | `STORY-XXX-test-report.md` | test-engineer |
| `qa-report` | `STORY-XXX-qa-report[-rN].md` | qa-analyst |
| `code-review` | `STORY-XXX-code-review[-rN].md` | code-reviewer |
| `impl-report` | `STORY-XXX-impl-report.md` | backend/frontend developer, bug-fixer |

**Product layer** (`artifacts/product/`, `artifacts/epics/`) — `id` is the filename itself.
Same rule as stories/epics: **doc type first, development slug second**, so every VISION sorts
next to every other VISION. A single-development project may drop the slug (`VISION.md`).

```
artifacts/product/   VISION-<dev>.md    PERSONAS-<dev>.md   OKRS-<dev>.md
                     ROADMAP-<dev>.md   NFRS-<dev>.md       GLOSSARY-<dev>.md
                     PM-HANDOFF-<dev>.md
artifacts/epics/     EPICS-SUMMARY-<dev>.md
artifacts/stories/   BACKLOG-SUMMARY-<dev>.md
```

`artifacts/architecture/TECH-STACK.md` (`type: tech-stack`, system-architect) is project-wide,
not per-development, so it keeps a bare name — it links out via `sources`.

`type` is the lowercased doc name: `vision`, `personas`, `okrs`, `roadmap`, `nfrs`,
`glossary`, `handoff`, and `summary` for both summaries. Written by product-owner, except
`BACKLOG-SUMMARY` (product-manager).

Every file of one effort shares the same `development` value, and `<dev>` IS that value.
**The summaries are per-development too** — a project running `theme` and `market-data-backfill`
side by side needs one backlog each, not one file overwritten twice. And `sources:` must point
at the docs of its OWN development (`sources: [VISION-theme, PERSONAS-theme]`).

## Per-type extra fields

- **Reports** (`test-report`, `qa-report`, `code-review`, `impl-report`): add `story: STORY-XXX`
  (the full id, slug included).
- **Versioned reports** (`qa-report`, `code-review`): add `revision: r2` (each `-rN` is a new file).
- **checkpoint** — the ONLY mutable artifact. It additionally carries the live board fields,
  updated by tech-lead as the story crosses each gate:

  ```yaml
  ---
  id: STORY-042-license-registration
  type: checkpoint
  story: STORY-042-license-registration
  title: Cadastro de licença
  development: licenciamento-v2
  epic: EPIC-licenciamento
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

## Lineage links (Obsidian graph)

Obsidian only draws a graph edge / backlink from a `[[wikilink]]` — a plain `epic: EPIC-005`
is inert text. So the `artifact-frontmatter.js` hook wraps the **lineage fields** on every
`Write` under `artifacts/`, making the artifact tree navigable as a graph:

```yaml
story: "[[STORY-042]]"     # written by agents as `story: STORY-042` — the hook wraps it
epic: "[[EPIC-licenciamento]]"
parent: "[[EPIC-licenciamento]]"
depends_on: ["[[STORY-041-license-model]]"]
```

**Agents keep writing plain ids.** Do NOT hand-write the brackets — the hook is the single
place that owns this, exactly like the frontmatter injection itself.

| | fields |
|---|---|
| **wrapped (entity ids)** | `story`, `epic`, `parent`, `parent_epic`, `depends_on`, `blocks`, `supersedes` |
| **wrapped (doc names)** | `sources`, `epics`, `stories` — any filename-safe token, no `PREFIX-` needed |
| **never wrapped** | `id`, `type`, `title`, `development`, `status`, `coverage`, `revision`, `layer`, `schema_version`, `created`, `updated`, `generated_by` |

The never-wrapped set is what the Bases board filters/groups on and what agents grep — wrapping
it would change behaviour. Wrapping the lineage set does not: the board shows `epic` as a
display column only.

Three guards keep the pass safe:

1. **Id-shaped values only** (`STORY-*`, `EPIC-*`, `HOTFIX-*`, `SPIKE-*`, `BUG-*`, `TASK-*`).
   A prose value (`epic: Backfill Automático de Dados`) is left alone rather than minted into
   a ghost node — so an epic MUST be referenced by **id**, never by title.
2. **Idempotent** — an already-wrapped value fails the id test, so the checkpoint's repeated
   writes never double-wrap.
3. **No self-links** — an epic carrying `epic: <its own id>` is skipped.

The doc-name fields let the **product layer** join the graph — `PM-HANDOFF` is the hub closing
the loop from the PO's decisions down to the epic.

```yaml
# artifacts/product/PM-HANDOFF-market-data-backfill.md
type: handoff
development: market-data-backfill
epics: [EPIC-market-data-backfill]           # -> the epic it hands over
sources: [VISION, PERSONAS, OKRS, NFRS]      # -> the PO decisions it derives from
```

Anything with a space, slash or colon stays prose (`epics: N/A` is untouched).

> Consequence: `epic: EPIC-x` requires a file resolvable as `EPIC-x` — `EPIC-x.md`, or any
> file carrying `aliases: [EPIC-x]`. An epic filed under a prose name with no alias produces
> an unresolved node.

## Migration (older artifacts)

Files without frontmatter are treated as `schema_version: 0`. Source-artifact agents prepend the
block on the next legitimate write; derived artifacts get it from the hook. Do NOT bulk-rewrite
historical artifacts — frontmatter is added only on the next write.
