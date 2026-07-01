<!-- Context: README | Priority: critical | Version: 2.0 | Updated: 2026-05-02 -->
# Context System — README

Single-source knowledge base for agents and humans working in this project.

## Entry Point

→ **Always consult `INDEX.md`** — the flat semantic index of every leaf file.

The INDEX has every leaf context file tagged with semantic keywords and a one-line summary. Discovery is a single read.

## Structure — 5 buckets, flat

```
context/
├── INDEX.md                # ← Start here. Flat index of every leaf file.
├── README.md               # This file.
│
├── standards/              # HOW to write code (universal, tech-agnostic)
├── workflows/              # HOW to act (operational processes)
├── stacks/                 # TECH-specific (per language/framework)
├── meta/                   # ABOUT the context system itself
└── project/                # THIS specific project (business + technical)
```

Each bucket answers a distinct question. Depth never exceeds 2 levels.

## For Agents

```
1. read(".claude/context/INDEX.md")
2. Filter entries by tags matching user intent
3. Rank: critical → mandatory → remaining
4. Return up to 5 leaf files. Beyond that: "N more available on demand."
5. If external library mentioned and no match → recommend ExternalScout.
```

No subdirectory walks. No `navigation.md` files. The INDEX is the only map.

## For Humans

To add a new file → read `meta/creation.md`.
To maintain the system → read `meta/operations.md`.
To understand the design → read `meta/overview.md`.

## Principles

- **MVI** — each file ≤200 lines, scannable in <30s (`meta/mvi.md`)
- **Single source of truth** — each fact in exactly one file
- **Flat discovery** — 1 read to find anything
- **Intent-driven tags** — INDEX tags match task intent
- **Priority ranking** — `critical` / `mandatory` first
