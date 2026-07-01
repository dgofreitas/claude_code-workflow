# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This repo is **not a runnable app**. It is the source of truth for a multi-agent SDLC workflow that installs into `<project>/.claude/` via a self-contained shell installer. The deliverable is `claude-workflow-installer.sh` (a base64-encoded tarball).

There is **no automated test suite**. Testing means installing into a real project and exercising the workflow: `claude` → invoke Master (the main session, driven by the installed `CLAUDE.md`).

> This repo was split out of `opencode-workflow` (which also hosts a legacy OpenCode-based version of this same workflow). This repo contains only the Claude Code deliverable — no OpenCode source, no dual-provider tooling.

## Build & install commands

```bash
# Build the self-contained installer (outputs claude-workflow-installer.sh)
bash build-claude-installer.sh

# Install into a target project
bash install-claude.sh --dest <target-project>

# Verify installed files (run inside target project)
bash install-claude.sh --help   # shows all options

# Build with custom output path
bash build-claude-installer.sh --output /path/to/output.sh
```

After install, add `rtk` to PATH:

```bash
export PATH="$PWD/.claude/bin:$PATH"
```

## Architecture

`claude/` is the entire deliverable — everything that gets bundled by `build-claude-installer.sh` and installed into `<project>/.claude/`:

```
claude/
├── CLAUDE.md          # Master orchestrator instructions (injected every session)
├── RTK.md             # Token-optimizer reference (rtk prefix for bash commands)
├── settings.json      # Claude Code harness config (models, hooks, MCP servers)
├── agents/            # Agent .md files (kebab-case, one per specialist)
├── commands/sdlc/      # Slash commands (.md)
├── skills/            # Skills (SKILL.md entrypoints), incl. tech-lead (orchestration skill)
├── context/            # 5-bucket context system (INDEX.md + files)
├── hooks/              # Caveman mode + RTK session hooks (Node.js)
└── bin/                # rtk binary (token-saving bash proxy)
```

### SDLC pipeline (the happy path)

```
Master (main session, router)
  → product-manager → [GATE-PM] → stories
  → system-architect → [GATE-SA] → stack (greenfield only)
  → architect → [GATE-AR] → technical plan
  → tech-lead skill (per-story orchestration)
      → backend/frontend devs (parallel)
      → test-engineer → [GATE: coverage ≥90%]
      → qa-analyst → [GATE: QA PASSED]
      → code-reviewer → [GATE: REVIEW APPROVED]
      → merge-request-creator → [GATE-MR: PR created]
  → [GATE-NEXT] → next story or summary
```

Five named human approval gates: `GATE-PM`, `GATE-SA`, `GATE-AR`, `GATE-MR`, `GATE-NEXT`. Execution mode (default / auto-gate / batch-auto) is persisted to `.claude/.exec-mode` — set it deterministically with `/mode` (see `claude/commands/sdlc/mode.md`) or let Master infer it from trigger phrases.

`tech-lead` is a **Skill**, not a subagent — it runs in the main session context (which always has the `Agent`/`Task` tool), and orchestrates the specialist subagents inside a single story. Master never calls story-internal agents (test-engineer, qa-analyst, code-reviewer, merge-request-creator, bug-fixer) directly; it always goes through the `tech-lead` skill. See `claude/CLAUDE.md` for the full routing/gate logic.

> **Nested subagent delegation** (a subagent's `Agent` tool calling another subagent, e.g. `backend-developer` calling `context-scout`) requires **Claude Code ≥ v2.1.172**. Below that version those calls silently no-op. Also note: the `Agent(name1, name2)` scoped-allowlist syntax in a subagent's own `tools:` frontmatter is only enforced when that agent runs as the main thread (`claude --agent`) — inside a subagent definition, any parenthesized list is ignored and the subagent gets unrestricted nested-spawn ability.

### Context system (`claude/context/`)

Five buckets: `standards/`, `workflows/`, `stacks/`, `meta/`, `project/`. The only navigation point is `context/INDEX.md` — a flat semantic index with tags. `context-scout` reads INDEX.md, filters by tags, and returns ≤5 files. Each file targets ≤200 lines (MVI — Minimal Viable Information principle).

### RTK token optimizer

`bin/rtk` is a bash proxy that rewrites git/test/build output for 60–99% token savings. **Always use `npm run <script>` — short forms (`npm test`, `npm start`) break the rewrite.** Do not add `| tail` or `| head` pipes to RTK-supported commands; RTK filters output itself.

## Critical rules

### max_tokens

Never cap `max_tokens` on code-generation agents (backend-developer, frontend-developer*, test-engineer, shell-developer) — mid-file truncation produces broken code. Safe to cap only on orchestrators/reporters (Master, qa-analyst, code-reviewer).

### Model tiering

Pick Opus/Sonnet/Haiku 4.x per role deliberately when adding agents to `claude/agents/` — don't default everything to the same tier. Cheap/fast models for high-volume lookups (context-scout, external-scout), stronger models for implementation and review.

### Agent permission model

Claude Code subagents don't support OpenCode-style granular per-agent task allowlists (`permission.task: {"*": deny, "X": allow}`). The closest lever is `tools:`/`disallowedTools:` in a subagent's frontmatter, plus a global `permissions.deny: ["Agent(name)"]` in `settings.json` (session-wide, not scoped to one calling agent). Don't rely on `Agent(a, b)` inside a subagent's own `tools:` for enforcement — it's cosmetic there (see note above).

## Key files

| File | Purpose |
|------|---------|
| `claude/CLAUDE.md` | Master orchestrator instructions (the installed workflow entry point) |
| `claude/RTK.md` | RTK token-optimizer command reference |
| `claude/settings.json` | Claude Code harness: models, MCP servers, hooks |
| `claude/skills/tech-lead/SKILL.md` | In-story orchestration (Impl → Test → QA → Review → MR) |
| `claude/commands/sdlc/mode.md` | `/mode` — deterministic execution-mode switch |
| `build-claude-installer.sh` | Builds the self-contained `claude-workflow-installer.sh` |
| `install-claude.sh` | Installs the workflow into a target project's `.claude/` |
