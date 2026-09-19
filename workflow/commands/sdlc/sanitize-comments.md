---
description: Apply the Comment Budget to existing files — triage by density, then delete narration and keep invariants, without touching a single code line
argument-hint: [file | folder | dir/*.ext | .ext | all] [--apply] [--exclude PAT] [--limit N] [--level safe|default|strict] [--report]
---

# /sanitize-comments — Comment Cleanup

Brings **existing** code into line with `standards/documentation.md` §Comment Budget. The `code-reviewer` gate stops *new* bloat; this command clears the backlog.

Report-first by design: it never writes on the first pass.

## Arguments

Pass `$ARGUMENTS` through to the scan script **verbatim** — it owns the parsing. The forms it accepts:

| Form | Scope |
|------|-------|
| `src/teco.js` | that one file |
| `src/` or `compose/` | every source file under it, recursively |
| `src/*.py` | **non-recursive** — only that extension directly in that directory |
| `.yml` / `*.yml` / `yml` | every file with that extension in the repo |
| `all` / empty | the whole repo |
| `--apply` | perform the edits (default is report-only) |
| `--exclude PAT` | skip a file, folder (`migrations/`) or extension (`.sql`). Repeatable, or comma-separated. **Adds to** the fixed list, never replaces it |
| `--limit N` | only the N densest files (default 15 — keeps one run reviewable) |
| `--level safe\|default\|strict` | how aggressive to be — overrides the per-file default below |
| `--report` | also save the sanitization report to `artifacts/`. Off by default |
| `--root DIR` | scan this repo instead of the auto-resolved one |

`--apply` and `--report` are consumed by **this command**; everything else goes to the script untouched.

Always excluded: `.git/`, `node_modules/`, `vendor/`, `dist/`, `build/`, `coverage/`, `.nyc_output/`, and anything untracked by git (which covers `.gitignore`).

## Level

Two kinds of file need opposite treatment, so the level defaults per file and `--level` overrides:

| File class | Extensions | Default level |
|------------|-----------|---------------|
| **code** | `.js .jsx .ts .tsx .py .sh .bash .c .h .go .rb .java` | `default` |
| **operator config** | `.conf .env* .ini .toml .json5 .properties`, `Dockerfile`, `*.template`, `*.yml`/`*.yaml` | `safe` |

In an operator-facing config the comments **are** the deliverable — a `%config(noreplace)` template is read by whoever fills it in. The budget's line and ratio limits do not transfer there; only "no story residue" does. Applying `default` to one of those would demand deleting the documentation that makes the file usable.

Level semantics are defined once, in `comment-sanitizer.md` §Priority 2. Pass the resolved level to the agent — never restate the table here.

> The extension→level mapping above is **implemented** in `scripts/sanitize-scan.sh` (`levelFor`), which is what actually decides. The table here is documentation of that function; change both together or they drift.

## Step 1 — Scan (one call, read-only)

```bash
.claude/scripts/sanitize-scan.sh <args-minus-apply-and-report>
```

The script owns everything mechanical: the clean-tree gate, repo-root resolution, scope parsing, exclusions, level classification, density ranking, the `--limit` cut, and the three auxiliary scans. It never writes to a project file.

**Branch on the exit code — never on whether stdout looks empty.** An empty stdout from a failing git call is indistinguishable from "nothing to do", and reading it as the latter is what once let `--apply` run with no safety net:

| Exit | Meaning | Action |
|------|---------|--------|
| `0` | scan complete | continue to Step 2 |
| `1` | bad arguments | show stderr, stop |
| `2` | **working tree dirty** | show stderr, stop. `git diff` is the review of this operation and `git checkout` is the undo — both need a clean baseline |
| `3` | root is not a git repo | show stderr, stop. In an umbrella install, re-run with `--root <sub-project>` |
| `4` | scope matched nothing | show stderr, stop |

If the script is missing or not executable, **stop and say so** — do not fall back to inline bash. A silent fallback reintroduces exactly the ambiguity the script exists to remove.

## Step 2 — Report the scan

Relay the script's output to the user before touching anything: `FILES_CONSIDERED`, the aggregate ratio, the ranked table, and — explicitly — `EXCLUDED_TOTAL` and `LIMIT_DROPPED`.

> Never let exclusion or truncation stay silent. A run that skipped 40 files reads as "covered everything" unless the count is on screen.

> Density ranks the queue; it does not judge. A `safe` file at 70% is normal — read the level column before reacting to the percentage.

The script also emits three mechanically-certain findings, which need no judgment from you: `STALE_REFS` (paths cited in comments that no longer exist), `DUPLICATE_BLOCKS` (identical comment prose in 2+ places — decorative separators and directives are already filtered out, since those are *meant* to repeat), and `OVERSIZED_BLOCKS` (runs of 5+ consecutive comment lines). Each section is capped, and prints how many entries were omitted.

## Step 3 — Branch on `--apply`

**Without `--apply`**: stop here. Print the triage plus "Rode de novo com `--apply` para executar."

**With `--apply`**: single pass — print how many files will be rewritten, then go straight to Step 4. **Do NOT ask the user to confirm** and do NOT require a prior report-only run: the triage above already ran in this same turn, and re-running the command just to see it would spend the agent budget twice. The clean-tree gate (Step 1) plus `--limit` are the safety net; `git checkout .` is the undo.

## Step 4 — Delegate

Batch **only** the paths in the scan's `RANKED` block, and pass them as the script printed them (relative to `ROOT`). Anything the scan excluded or the `--limit` dropped stays out — re-adding a file here would walk it straight back in through the back door, past the exclusion the user asked for.

Delegate to **comment-sanitizer**, in batches of at most 5 files per call so each agent holds full file context. **Batch by level** — one call never mixes `safe` and `default` files, since the level is a per-call instruction:

```
Task(subagent_type="comment-sanitizer", description="Sanitize comments in <batch>", prompt="LEVEL: <safe|default|strict>. Apply standards/documentation.md §Comment Budget to these files: <paths>. Full-line comment blocks only — never a trailing comment, never a code line. Verify each file with the Never Touch Code diff check and revert any file that fails. Return the per-file table of removals with original text. Do NOT write a report file.")
```

Drop the last sentence when the user passed `--report`.

Batches are independent — issue them in parallel. One failing batch never blocks the others.

## Step 5 — Verify (MANDATORY, main context)

Never trust the agents' self-report. Re-verify the whole diff yourself, anchored to the `ROOT` the scan printed — a bare `git diff` inspects whatever repo the session happens to sit in, which in an umbrella install is not the one that was rewritten:

```bash
git -C <ROOT> diff -U0 | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*(#|//|\*|/\*|$)'
```

**Any output = a code line changed.** Print the offending lines and tell the user to inspect before committing — do not attempt to repair it yourself.

Then, if the project has them, run the cheap guards: `npm run lint`, `npm run test`, `bash -n` on changed shell files, `python -m py_compile` on changed Python.

## Step 6 — Close out

Always print to the user: files touched, comment lines before → after, any `FAILED` file, and `git -C <ROOT> diff --stat`.

**Only with `--report`**, also save the consolidated report to `artifacts/comment-sanitization-<scope>-<date>.md`, merging every batch.

> The report is not the rescue path — git is. Step 1 refuses to run on a dirty tree precisely so that `git diff` shows every removal and `git checkout .` undoes all of them. The file is worth asking for when the run will be committed before anyone reviews it; otherwise it duplicates the diff.

## Safety notes

- Report-only by default; writing requires an explicit `--apply`.
- The scan refuses to run on a dirty tree (exit `2`), so `git checkout .` reverts the entire operation.
- Scope, exclusion and ranking are decided by the script, not inferred — the same arguments always select the same files.
- Operator-facing config defaults to `safe` — never let a density number push a `.conf` into `default`.
- The agent never touches directives, shebangs, licence headers, or public API docs — deleting an `eslint-disable` or `# shellcheck disable=` would change behavior.
- Borderline comments are shortened, never deleted: a lost invariant costs more than a verbose comment.
- This command never fixes unrelated problems it notices — it reports them.
