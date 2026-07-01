<!-- Context: meta/overview | Priority: critical | Version: 1.0 | Updated: 2026-05-02 -->
# Context System Overview

**Purpose**: How this context system is structured, why, and how agents use it.

---

## The Problem It Solves

Without structure, agent prompts become either (a) too small (agents invent conventions) or (b) too large (agents drown in irrelevant text). This system solves it by providing **focused, on-demand knowledge** — agents pull exactly what they need, when they need it.

---

## How It Works

```
Agent receives task
   ↓
ContextScout reads INDEX.md  (1 read)
   ↓
Filters entries by intent tags
   ↓
Returns up to 5 ranked leaf files
   ↓
Agent loads only those files
```

- **Single entry point**: `INDEX.md` at the root of `context/`
- **Flat semantic index**: `path | tags | summary` — one line per leaf file
- **No subdirectory navigation**: no `navigation.md` files between root and leaves
- **Budget**: max 5 files returned per query (configurable; rest available on demand)

---

## Directory Layout (5 Buckets)

```
context/
├── INDEX.md                  # Single navigation map
├── README.md                 # Human-facing explanation
│
├── standards/                # HOW to write code (universal, tech-agnostic)
├── workflows/                # HOW to act (operational processes)
├── stacks/                   # TECH-specific (per language/framework)
├── meta/                     # ABOUT the context system itself
└── project/                  # THIS specific project
```

### Bucket semantics

| Bucket | Answers | Examples |
|--------|---------|----------|
| `standards/` | "How do I write code well?" | code-quality, clean-code, api-design, security, testing, docs |
| `workflows/` | "What's the process for X?" | code-review, task-delegation, feature-breakdown, external-libraries |
| `stacks/` | "How does this tech work?" | nodejs, react, mastra-ai, design-systems, frontend, ui-styling |
| `meta/` | "How does the context system work?" | overview (this file), mvi, structure, frontmatter, creation, operations |
| `project/` | "What's specific to this project?" | business-domain, technical-domain, decisions-log, living-notes |

**Predictability test**: "Where does X go?" — if more than one bucket is plausible, the taxonomy is wrong. Fix the bucket, not the file.

---

## Core Principles

### 1. MVI (Minimal Viable Information)

Each leaf file: target ≤200 lines, scannable in <30 seconds. Agents can read multiple files without context window pressure. See `meta/mvi.md`.

### 2. Flat Discovery

Agents do **1 read** (`INDEX.md`) to find everything. No tree-walk through subdirectories. Complexity grows with content, not with navigation.

### 3. Single Source of Truth

Each fact lives in exactly one file. References use relative paths. Duplication is a defect.

### 4. Intent-Driven Retrieval

Tags in `INDEX.md` match task intent (e.g., `tags: testing, react, vitest`). ContextScout filters semantically; no manual path-memorization by human or agent.

### 5. Priority Ranking

Tags like `critical`, `mandatory`, `high` signal which files must load vs. which are optional. ContextScout returns ranked results.

---

## Agent Interaction

Three agents read this system:

| Agent | Role |
|-------|------|
| **ContextScout** | Discovers files from INDEX.md, returns up to 5 ranked by priority. Read-only. |
| **ExternalScout** | Fetches external library docs. Checks INDEX.md first — if internal coverage exists, returns that instead. |
| **Any specialist** | Receives session `context.md` with pre-loaded file paths from ContextScout. Reads files directly. |

Agents never navigate subdirectories manually. The index is the only map.

---

## File Lifecycle

```
CREATE  → meta/creation.md  (templates, naming, frontmatter)
UPDATE  → meta/operations.md → Update operation
ORGANIZE → meta/operations.md → Organize operation
HARVEST → meta/operations.md → Harvest operation (pull knowledge from scattered sources)
EXTRACT → meta/operations.md → Extract operation (from URL/docs/code)
MIGRATE → meta/operations.md → Migrate operation (global → local, version moves)
ERROR   → meta/operations.md → Error operation (capture recurring errors)
```

When a new file is added or edited, **`INDEX.md` must be updated** — ideally via a script so it never goes stale.

---

## Success Criteria

A healthy context system:

- ✅ `INDEX.md` lists every leaf file with tags + summary
- ✅ No subdirectory `navigation.md` files
- ✅ ≤5 files loaded per typical query
- ✅ Most files ≤200 lines
- ✅ Zero DEPRECATED files in INDEX
- ✅ Zero duplicated H1 titles across files
- ✅ Each bucket answers a distinct, non-overlapping question

---

## Related

- `meta/mvi.md` — Minimal Viable Information rules
- `meta/structure.md` — File structure & directory rules
- `meta/frontmatter.md` — Frontmatter schema
- `meta/creation.md` — How to create new files
- `meta/operations.md` — Maintenance operations
- `.claude/agents/context-scout.md` — ContextScout agent
- `.claude/agents/external-scout.md` — ExternalScout agent
