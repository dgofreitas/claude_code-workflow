<!-- Context: meta/operations | Priority: high | Version: 1.0 | Updated: 2026-05-02 -->
# Context System Operations

**Purpose**: Maintenance operations for the context system. Each has a trigger, stages, and an approval gate before destructive actions.

---

## Operations Summary

| Op | Trigger | Key output |
|----|---------|-----------|
| **Harvest** | Pull knowledge from scattered sources (sessions, notes, temp files) | New/updated context files + cleanup |
| **Extract** | Capture knowledge from a specific URL/doc/code artifact | New context file |
| **Organize** | Existing context files are in the wrong bucket or overlap | Re-bucketed/renamed files |
| **Update** | Existing file has outdated info | Edited file + changelog entry |
| **Migrate** | Move context between scopes (global→local, old path→new path) | Relocated files, conflicts resolved |
| **Error** | Capture a recurring error so future agents fix it faster | New entry in error catalog |

**Common rule**: every destructive step requires explicit user approval before execution.

---

## Harvest

**When**: scattered `.md` files in workspace (sessions, tmp notes, scratch docs) contain reusable knowledge.

Stages:

1. **Scan** — glob for markdown files in `.tmp/`, sessions, scratch dirs
2. **Analyze** — classify each: `extract` (reusable) | `skip` (temporary/noise)
3. **Approve** — show classification, wait for user confirmation
4. **Extract** — create/update context files following MVI + frontmatter
5. **Cleanup** — with approval, delete source scratch files
6. **Report** — list new files, updated files, deleted sources

**Extract** (valuable knowledge): patterns, decisions, error fixes, integration notes.
**Skip** (noise): TODOs, commit messages, temporary progress logs.

---

## Extract

**When**: a single source (URL, library doc, code snippet) contains knowledge worth preserving.

Stages:

1. **Read source** — fetch and parse the source material
2. **Analyze & categorize** — what bucket does it belong to? (standards/workflows/stacks/meta/project)
3. **Select category** (approval) — user confirms target bucket
4. **Preview** (approval) — show filename, frontmatter, content preview
5. **Create** — write the file, respect MVI
6. **Update INDEX** — add entry with tags + summary
7. **Report** — confirm creation and path

---

## Organize

**When**: files live in the wrong bucket, names overlap, or a bucket has >15 files (smell of missing subdivision).

Stages:

1. **Scan** — list all leaf files with their current bucket
2. **Categorize** — propose correct bucket per file
3. **Resolve conflicts** (approval) — duplicates, ambiguous buckets, rename needs
4. **Preview** (approval) — show full move plan (from → to) as a table
5. **Execute moves** — move files, update relative paths inside them
6. **Update INDEX** — regenerate or patch
7. **Validate** — INDEX paths all exist, no orphans
8. **Report** — summary of moves, renames, merges

---

## Update

**When**: a fact in an existing file is stale, wrong, or incomplete.

Stages:

1. **Locate** — use INDEX.md to find the file
2. **Diff** — show what will change
3. **Approve** — user confirms edit
4. **Edit** — apply change, preserve frontmatter except `Updated:` date
5. **Bump version** — minor/patch bump in frontmatter
6. **Log** — append entry to `meta/CHANGELOG.md` if significant

---

## Migrate

**When**: moving context between scopes — e.g., shared global → per-project local, or renaming top-level buckets.

Stages:

1. **Detect sources** — find candidate files in old location
2. **Check conflicts** — existing files at destination? Newer timestamps?
3. **Approve & copy** — with explicit conflict resolution (overwrite/skip/merge)
4. **Cleanup & confirm** — delete old location only after copies verified

Conflict rules:

- Destination newer → prefer destination, skip source
- Source newer → prefer source, overwrite destination
- Ambiguous → prompt user

---

## Error

**When**: an error/bug pattern recurs and agents should know about it.

Stages:

1. **Search existing** — is this error already cataloged? If yes → use Update, not Error
2. **Check duplication** (approval) — confirm this is genuinely new vs a variant
3. **Preview** (approval) — show entry format
4. **Add/update** entry with: error name, cause, fix, related files
5. **Update INDEX** — error catalogs get their own file; update its entry
6. **Report** — confirm addition

Error entry format:

```markdown
## Error: {Name}

**Cause**: {root cause}
**Symptoms**: {what agent sees}
**Fix**: {concrete steps}
**Reference**: {file/line or library}
**Related**: {links to concepts}
```

### Deduplication

- **Similar errors** (same root cause, different messages) → consolidate under one entry
- **Related errors** (different root, same domain) → cross-link, don't merge
- **Duplicate errors** → update existing, don't create new

---

## Approval Gates

Every operation requires explicit user approval before:

- Writing new files
- Moving/renaming files
- Deleting files
- Overwriting existing content

Read/scan/preview steps do NOT require approval.

---

## Success Criteria

An operation succeeded when:

- ✅ Target file(s) reflect the intended state
- ✅ `INDEX.md` is updated (new/moved entries)
- ✅ No broken relative paths remain
- ✅ MVI respected in created/edited files
- ✅ User approved each destructive step

---

## Related

- `meta/overview.md` — How the system works
- `meta/creation.md` — How to create new files (input to Extract/Harvest)
- `meta/mvi.md` — MVI rules applied during every operation
- `meta/frontmatter.md` — Frontmatter schema
