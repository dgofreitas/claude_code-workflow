<!-- Context: standards/artifact-naming | Priority: high | Version: 1 | Updated: 2026-08-20 -->
# Artifact Naming & Lineage Links

> How an SDLC artifact is NAMED and how it LINKS to the rest of the tree. The frontmatter
> contract itself (which fields, who writes them) lives in `standards/artifact-frontmatter.md`.

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
