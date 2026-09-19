<!-- Context: project/intelligence-guide | Priority: high | Version: 1.0 | Updated: 2026-05-02 -->
# Project Intelligence Guide

**Purpose**: What project intelligence is, how to use it, and how to keep it alive.

---

## What & Why

**What**: Living documentation that bridges business domain and technical implementation.

**Why**: Projects fail when business intent is lost in code, decisions aren't documented with context, new members spend weeks understanding, and context lives only in people's heads. Project intelligence ensures **business and technical domains speak the same language**.

**Where**: `project/` bucket (this directory).

---

## Files in this Bucket

| Need | File | Covers |
|------|------|--------|
| Understand the "why" | `business-domain.md` | Problem, users, value proposition |
| Understand the "how" | `technical-domain.md` | Stack, architecture, key patterns |
| See the connection | `business-tech-bridge.md` | Business needs → technical solutions |
| Know the context | `decisions-log.md` | Decisions + rationale (ADR-style) |
| Current state | `living-notes.md` | Active issues, tech debt, open questions |
| This file | `intelligence-guide.md` | Meta-guide (how to use the bucket) |

---

## Onboarding Checklist

For new team members or agents joining the project:

- [ ] Read `business-domain.md` → understand the "why"
- [ ] Read `technical-domain.md` → understand the "how"
- [ ] Review `business-tech-bridge.md` → see the connection
- [ ] Check `decisions-log.md` → context on key choices
- [ ] Review `living-notes.md` → current state, active issues
- [ ] Explore codebase with this context loaded

This is the **first context to load** when joining a project — then standards and stack-specific context.

---

## When to Update Each File

| Trigger | File to update |
|---------|----------------|
| Business direction shifts, new market, new users | `business-domain.md` |
| New architectural decision | `decisions-log.md` (append, never rewrite past entries) |
| New issue, tech debt discovered, open question | `living-notes.md` |
| Feature launched, business need solved technically | `business-tech-bridge.md` |
| Stack change, new framework/library introduced | `technical-domain.md` |

---

## Adding a New Intelligence File

When a new kind of project-wide knowledge emerges:

1. **Check overlap** — does existing file already cover this? If yes → update instead.
2. **Naming** — kebab-case, singular, matches bucket vocabulary
3. **Frontmatter** — complete per `meta/frontmatter.md`
4. **MVI** — target ≤200 lines per `meta/mvi.md`
5. **Cross-reference** — update sibling files that reference this area
6. **Update INDEX.md** — add entry with tags + summary

Template skeleton:

```markdown
<!-- Context: project/{slug} | Priority: high | Version: 1.0 | Updated: YYYY-MM-DD -->
# {Title}

**Purpose**: {one line}

## Quick Reference
| Item | Value |
|------|-------|
| ... | ... |

## Content
{body}

## Related
- project/business-domain.md
```

---

## Updating an Existing File

1. **Locate** via INDEX.md
2. **Diff** before applying — keep a mental or commit-level record of what changed
3. **Bump version** in frontmatter (minor for substantive edits)
4. **Update `Updated:` date**
5. **Preserve history** — for `decisions-log.md` and `living-notes.md`, append rather than rewrite. History matters.

---

## Deprecation

When a file becomes obsolete:

1. **Don't delete immediately** — mark with `⚠️ DEPRECATED` in H1 for one release cycle
2. **Add deprecation note** at top explaining replacement
3. **Remove from INDEX.md** immediately (stop recommending it)
4. **Delete after one cycle** — if no one complained, it's safe to remove

Never keep DEPRECATED files in the INDEX — ContextScout would recommend them.

---

## Quality Standards

Every intelligence file must:

- ✅ Have a clear, one-line Purpose
- ✅ Be actionable (reader knows what to do after reading)
- ✅ Respect MVI (≤200 lines)
- ✅ Reference concrete artifacts (code paths, decisions, ADRs) when relevant
- ✅ Stay current — stale intelligence is worse than no intelligence

Reject:

- ❌ Vague generalities ("we value quality")
- ❌ Unsourced claims ("we decided" — by whom? when?)
- ❌ Duplication with `technical-domain.md` or `business-domain.md`

---

## Subfolders

Create subfolders **only** when a bucket has ≥6 related files with a clear sub-theme. Until then, keep flat.

Example candidates (only if justified):

- `project/integrations/` — per-third-party service notes
- `project/domains/` — per-bounded-context notes (if using DDD)

Avoid premature subdivision.

---

## Governance

- **Owner**: whoever last substantively edited `business-domain.md` for product, `technical-domain.md` for engineering
- **Review cadence**: quarterly light review — are the facts still true?
- **Trigger review**: any time an agent gives advice contradicting a file — means the file is stale

---

## Related

- `meta/overview.md` — context system overview
- `meta/mvi.md` — MVI rules
- `meta/creation.md` — how to create new context files
- `meta/frontmatter.md` — frontmatter schema
