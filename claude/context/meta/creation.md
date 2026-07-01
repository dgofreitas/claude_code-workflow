<!-- Context: meta/creation | Priority: high | Version: 1.0 | Updated: 2026-05-02 -->
# Creating Context Files

**Purpose**: Standards and workflow for adding new context files.

---

## Workflow

```
1. Determine bucket  → standards | workflows | stacks | meta | project
2. Pick template     → concept | guide | lookup | standard | workflow
3. Apply MVI         → target ≤200 lines, scannable in <30s
4. Validate size     → wc -l and re-compress if needed
5. Add cross-refs    → relative paths, never absolute
6. Update INDEX.md   → new entry with tags + summary
7. Commit            → single focused commit per new file
```

---

## File Naming

- **kebab-case**: `code-review.md`, `task-delegation.md`
- **Singular nouns for concepts**: `storage.md` not `storages.md`
- **No redundant prefixes**: `nodejs.md` (inside `stacks/`), NOT `stacks-nodejs.md`
- **Self-descriptive**: from filename alone, reader should know what's inside
- **No date/version in name**: version lives in frontmatter

---

## Frontmatter (Required)

```markdown
<!-- Context: {bucket}/{slug} | Priority: critical|high|medium|low | Version: 1.0 | Updated: YYYY-MM-DD -->
# {Title}

**Purpose**: {one-line description ending with period}
```

- **Context path**: matches the file location without `.md` extension
- **Priority**: `critical` (loaded for almost all tasks) | `high` (most tasks) | `medium` (specialized) | `low` (optional)
- **Version**: `Major.Minor` — bump Major on breaking restructure, Minor on substantive additions
- **Updated**: ISO date of last substantive edit

---

## MVI Rules (Minimal Viable Information)

Target: **≤200 lines**, scannable in **<30 seconds**.

Compression techniques:

1. **Extract core concept** — one paragraph stating the essence
2. **Bulletize key points** — lists over prose
3. **Minimize examples** — 1 canonical example, not 5 variations
4. **Replace repetition with references** — link to other context, don't inline
5. **Convert prose to tables** — for structured data

Bloat to remove:

- "Last updated" dates inside body (lives in frontmatter)
- Lengthy introductions repeating the Purpose line
- Restating related-file content instead of linking
- Code blocks longer than 20 lines (link to the real file instead)
- "Overview" sections that duplicate the first paragraph

The **30-second rule**: if a competent reader can't extract the file's core in 30s, compress it.

---

## Size Targets per Template

| Template | Target | Max | Use for |
|----------|--------|-----|---------|
| Concept | 80–120L | 150L | Single idea with 1 example |
| Guide | 120–180L | 200L | Step-by-step procedure |
| Lookup | 60–150L | 200L | Tables/reference — skim-only |
| Standard | 120–200L | 200L | Rules and conventions |
| Workflow | 150–200L | 200L | Multi-stage processes |

Reference material (theme templates, schemas) may exceed 200L if it's pure lookup data — document the reason in frontmatter comment.

---

## Templates

### Concept template

```markdown
<!-- Context: ... -->
# Concept: {Name}

**Purpose**: {one-line}

## Core Idea
{one paragraph, ≤4 sentences}

## Key Points
- {point 1}
- {point 2}
- {point 3}

## Quick Example
```{lang}
{minimal example}
```

## Related

- {cross-ref}

```

### Guide template

```markdown
<!-- Context: ... -->
# Guide: {Task}

**Purpose**: {what the reader will accomplish}

## Prerequisites
- {requirement}

## Steps

### 1. {Step name}
{instruction}

### 2. {Step name}
{instruction}

## Verification Checklist
- [ ] {condition}

## Related
- {cross-ref}
```

### Lookup template

```markdown
<!-- Context: ... -->
# Lookup: {Subject}

**Purpose**: Quick reference for {what}.

## {Category 1}

| Column | Column |
|--------|--------|
| data | data |

## {Category 2}

| Column | Column |
|--------|--------|
| data | data |
```

---

## Cross-Reference Rules

- Use **relative paths**: `../standards/code-quality.md`, not `/home/...`
- In runtime agent prompts: use `.claude/context/...` (runtime path)
- In context files referencing siblings: use `./` or `../`
- Link only to files that truly add information — no "see also" bloat
- Each file should have a **Related** section with 2–5 links max

---

## Validation Before Commit

- [ ] Line count ≤ target for template (or justified)
- [ ] Frontmatter complete (Context, Priority, Version, Updated)
- [ ] H1 title present and unique across the codebase
- [ ] No DEPRECATED markers
- [ ] All relative paths resolve
- [ ] INDEX.md entry added with ≥2 tags + 1-line summary
- [ ] No duplication of content that lives in another file

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| File >200L with prose | Apply compression techniques; split only if distinct topics |
| Duplicate H1 with another file | Rename or merge |
| Missing INDEX entry | Add before committing |
| Absolute paths in cross-refs | Switch to relative |
| Hard-coded dates in body | Move to frontmatter |
| Related section > 5 links | Trim to most useful 3–5 |

---

## Related

- `meta/overview.md` — Context system overview
- `meta/mvi.md` — MVI principle details
- `meta/structure.md` — File and directory rules
- `meta/frontmatter.md` — Frontmatter schema reference
- `meta/operations.md` — Extract/Harvest/Update workflows that create files
