---
description: Apply the Comment Budget to existing files — triage by density, then delete narration and keep invariants, without touching a single code line
argument-hint: [file | folder | .ext | all] [--apply] [--limit N]
---

# /sanitize-comments — Comment Cleanup

Brings **existing** code into line with `standards/documentation.md` §Comment Budget. The `code-reviewer` gate stops *new* bloat; this command clears the backlog.

Report-first by design: it never writes on the first pass.

## Arguments

Parse `$ARGUMENTS`:

| Form | Scope |
|------|-------|
| `src/teco.js` | that one file |
| `src/` or `compose/` | every source file under it, recursively |
| `.yml` / `*.yml` / `yml` | every file with that extension in the repo |
| `all` / empty | the whole repo |
| `--apply` | perform the edits (default is report-only) |
| `--limit N` | only the N densest files (default 15 — keeps one run reviewable) |

Always exclude: `.git/`, `node_modules/`, `vendor/`, `dist/`, `build/`, `coverage/`, `.nyc_output/`, and anything matched by `.gitignore`.

## Step 1 — Clean Tree Gate (MANDATORY)

```bash
git status --porcelain
```

**Not empty → STOP.** Print: "Working tree sujo. Commit ou stash antes — `git diff` é a revisão desta operação e `git checkout` é o desfazer." No exceptions: without a clean baseline the user cannot review or revert what an agent rewrote across many files.

## Step 2 — Triage (mechanical, no edits)

Run this in the main context — it is cheap and its numbers drive everything after:

```bash
git ls-files -- $SCOPE | grep -Ev '(^|/)(node_modules|vendor|dist|build|coverage|\.nyc_output)/' | while read -r f; do
  case "$f" in *.js|*.ts|*.jsx|*.tsx|*.py|*.sh|*.bash|*.c|*.h|*.go|*.rb|*.java|*.yml|*.yaml) ;; *) continue ;; esac
  tot=$(grep -c '' "$f"); blank=$(grep -c '^[[:space:]]*$' "$f")
  cmt=$(grep -cE '^[[:space:]]*(#|//|\*|/\*)' "$f")
  code=$((tot-blank-cmt)); [ "$code" -le 0 ] && continue
  awk -v c="$cmt" -v k="$code" -v f="$f" 'BEGIN{printf "%.1f\t%d\t%d\t%s\n", 100*c/(c+k), c, k, f}'
done | sort -rn | head -${LIMIT:-15}
```

Then report, **before touching anything**: total files in scope, aggregate comment/code ratio, and the ranked table (density %, comment lines, code lines, path).

Also surface the three mechanically-certain findings — they need no judgment:

- **Stale references**: paths cited in comments that no longer exist (`grep` the comments for path-like tokens, test each with `ls`)
- **Duplicate blocks**: identical comment text in 2+ places. Ignore decorative separators (nothing but punctuation after the marker) and directives — those are *meant* to repeat:

  ```bash
  git grep -hE '^[[:space:]]*(#|//)' -- $SCOPE | sed 's/^[[:space:]]*//' \
    | grep -vE '^(#|//)[[:space:]]*[-=_*#/─━═┄·.[:space:]]*$' \
    | grep -vEi 'shellcheck|eslint|noqa|type:|pylint|nosec|nolint' \
    | awk 'length($0)>40' | sort | uniq -c | sort -rn | awk '$1>1'
  ```

  Repeated section headers (`# ── main ──`) are expected — ignore them; what matters is repeated *prose*.

- **Oversized blocks**: runs of 5+ consecutive comment lines (`awk '/^[[:space:]]*(#|\/\/|\*)/{n++;next}{if(n>=5)print FILENAME": "n;n=0}'`)

## Step 3 — Branch on `--apply`

**Without `--apply`**: stop here. Print the triage plus "Rode de novo com `--apply` para executar."

**With `--apply`**: single pass — print how many files will be rewritten, then go straight to Step 4. **Do NOT ask the user to confirm** and do NOT require a prior report-only run: the triage above already ran in this same turn, and re-running the command just to see it would spend the agent budget twice. The clean-tree gate (Step 1) plus `--limit` are the safety net; `git checkout .` is the undo.

## Step 4 — Delegate

Delegate to **comment-sanitizer**, in batches of at most 5 files per call so each agent holds full file context:

```
Task(subagent_type="comment-sanitizer", description="Sanitize comments in <batch>", prompt="Apply standards/documentation.md §Comment Budget to these files: <paths>. Full-line comment blocks only — never a trailing comment, never a code line. Verify each file with the Never Touch Code diff check and revert any file that fails. Return the per-file table of removals with original text.")
```

Batches are independent — issue them in parallel. One failing batch never blocks the others.

## Step 5 — Verify (MANDATORY, main context)

Never trust the agents' self-report. Re-verify the whole diff yourself:

```bash
git diff -U0 | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*(#|//|\*|/\*|$)'
```

**Any output = a code line changed.** Print the offending lines and tell the user to inspect before committing — do not attempt to repair it yourself.

Then, if the project has them, run the cheap guards: `npm run lint`, `npm run test`, `bash -n` on changed shell files, `python -m py_compile` on changed Python.

## Step 6 — Report

Save the consolidated report to `artifacts/comment-sanitization-<scope>-<date>.md`, merging every batch. **This report is the only record of deleted text** — it is what makes the deletion reversible, so it is never skipped.

Close with: files touched, comment lines before → after, any `FAILED` file, and `git diff --stat`.

## Safety notes

- Report-only by default; `--apply` is always an explicit second run.
- Requires a clean tree, so `git checkout .` reverts the entire operation.
- The agent never touches directives, shebangs, licence headers, or public API docs — deleting an `eslint-disable` or `# shellcheck disable=` would change behavior.
- Borderline comments are shortened, never deleted: a lost invariant costs more than a verbose comment.
- This command never fixes unrelated problems it notices — it reports them.
