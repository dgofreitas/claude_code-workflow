---
description: Set or check the active sub-project in a multi-project umbrella (anchors artifacts + state)
argument-hint: [<sub-project>|status|clear|list]
---

# /project — Set the Active Sub-Project

Deterministic override for the sub-project Master otherwise infers from the prompt (see
`CLAUDE.md` → Active Project). Use this in an **umbrella** install (one `.claude/` at the root,
several sub-project git repos like `teco` / `gerLic`) so every artifact path and git op anchors
to the right sub-project — and so per-project state (exec-mode, batch queue) never collides.

Single-project installs don't need this: with no active project, `$P = .` and everything works as before.

## Action

**Master-level action, not a subagent delegation** — run the bash directly.

Parse `$ARGUMENTS` (case-insensitive):

- empty or `status` → `cat .claude/.active-project 2>/dev/null || echo "(nenhum — projeto único, \$P=.)"`. Report the active sub-project. Do nothing else.
- `list` → `for d in */; do [ -d "$d/.git" ] && echo "${d%/}"; done`. List candidate sub-projects (dirs that are their own git repo).
- `clear` / `none` / `root` → `rm -f .claude/.active-project`. Confirm: "Projeto ativo: nenhum (projeto único, \$P=.)."
- `<name>` → validate it is a sub-project git repo: `[ -d "<name>/.git" ]`.
  - valid → `echo "<name>" > .claude/.active-project`. Confirm: "Projeto ativo: `<name>` — artefatos em `<name>/artifacts/`, estado em `.claude/.exec-mode.<name>`."
  - invalid → `[ -d "<name>" ] && echo "'<name>' não é um git repo próprio" || echo "'<name>' não existe"`; then run `list` and ask the user to pick one.

## Safety notes

- Switching the active project mid-session does not touch an in-flight `tech-lead` invocation — it changes anchoring only for turns after this command.
- The active project selects which **per-project state** files Master reads: `.claude/.exec-mode${name:+.<name>}` and `.claude/.batch-queue${name:+.<name>}.json`. Switching projects switches state; it does not clear the other project's queue.
- Story numbers repeat across sub-projects (STORY-032 in teco AND gerLic) — this pointer is what disambiguates them. When unset in an umbrella, Master asks before acting.

## Output

One line confirming the active (or unchanged) sub-project. No pipeline explanation.
