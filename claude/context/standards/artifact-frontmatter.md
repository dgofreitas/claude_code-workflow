<!-- Context: standards/artifact-frontmatter | Priority: high | Version: 1 | Updated: 2026-07-07 -->
# Artifact Frontmatter Standard

> Every SDLC artifact written under `artifacts/` MUST start with a YAML frontmatter
> block. Frontmatter is **identity + lineage — NOT mutable state**. It is written once
> by the generating agent and does not change afterwards. The **only** exception is the
> checkpoint file, which is the single mutable source of truth (see below).
>
> This is what powers the Obsidian **Bases** board (`story-board.base`) and any generated
> `INDEX.md`: a flat query over the frontmatter of every artifact.

> Naming (`STORY-<seq>-<slug>`, `EPIC-<dev>`) and the wikilink lineage that feeds the Obsidian
> graph live in `standards/artifact-naming.md`.

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
not per-development, so it keeps a bare name. Other files under `artifacts/architecture/` are
`type: design` — the architect's API designs, data flows, folder structures and test strategies.
Both link up with `epic:` (the epic whose scope they were written for).

`type: note` is the escape hatch for a document that is genuinely not an SDLC artifact — an
ad-hoc analysis, a working note. It is not a default: reach for it only when no other type
fits, and expect it to have no lineage edge unless the note names a story or epic itself.

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

## Migration (older artifacts)

Files without frontmatter are treated as `schema_version: 0`. Source-artifact agents prepend the
block on the next legitimate write; derived artifacts get it from the hook. Do NOT bulk-rewrite
historical artifacts on your own initiative — frontmatter is added only on the next write.

The one exception is a **migration the user explicitly authorises**, to make an existing tree
navigable in one pass. It is a deliberate, reviewable act, not a background sweep: work on a
clean git tree, dry-run and show the diff first, and infer only what the files already state —
an epic id from the epic's own H1, a `story:` link from the report's filename, a checkpoint
`status` from whether its checklist still has `- [ ]` items (the same signal Pre-Merge
Verification reads). Never invent state that no file records; a note with no natural parent
stays an orphan, and a link to a story file that was never written stays unresolved. Both are
findings, not defects to paper over.
