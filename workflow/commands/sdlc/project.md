---
description: Set or check the active sub-project in a multi-project umbrella (anchors artifacts + state)
argument-hint: [<sub-project>|status|clear|list]
---

# /project — Set the Active Sub-Project

Deterministic override for the sub-project Master otherwise infers from the prompt (see
`CLAUDE.md` → Active Project). Use this in an **umbrella** install (one `.claude/` at the root,
several sub-project git repos like `teco` / `gerLic`) so every artifact path and git op anchors
to the right sub-project. The choice belongs to **this session** (`.claude/.state/<session>/active-project`), so a second session on the same install keeps its own.

Single-project installs don't need this: with no active project, `$P = .` and everything works as before.

## Action

**Master-level action, not a subagent delegation** — run the bash directly, after resolving this session's state dir:

```bash
S="${CLAUDE_CODE_SESSION_ID:+.claude/.state/$CLAUDE_CODE_SESSION_ID}"
```

`$S` empty (no session id) → the choice cannot persist: say so in one line and treat the name as valid for this turn only.

Parse `$ARGUMENTS` (case-insensitive):

- empty or `status` → `cat "$S/active-project" 2>/dev/null || echo "(nenhum — projeto único, \$P=.)"`. Report the active sub-project. Do nothing else.
- `list` → `for d in */; do [ -d "$d/.git" ] && echo "${d%/}"; done`. List candidate sub-projects (dirs that are their own git repo).
- `clear` / `none` / `root` → `rm -f "$S/active-project"`. Confirm: "Projeto ativo: nenhum (projeto único, \$P=.)."
- `<name>` → validate it is a sub-project git repo: `[ -d "<name>/.git" ]`.
  - valid → `mkdir -p "$S" && echo "<name>" > "$S/active-project"`. Confirm: "Projeto ativo nesta sessão: `<name>` — artefatos em `<name>/artifacts/`."
  - invalid → `[ -d "<name>" ] && echo "'<name>' não é um git repo próprio" || echo "'<name>' não existe"`; then run `list` and ask the user to pick one.

## Safety notes

- Switching the active project mid-session does not touch an in-flight `tech-lead` invocation — it changes anchoring only for turns after this command.
- Mode and batch queue are per session too, not per project: switching projects keeps them.
- Story numbers repeat across sub-projects (STORY-032 in teco AND gerLic) — this pointer disambiguates a request with no story id. With an id, Master finds the sub-project that has it. When neither settles it, Master asks before acting.

## Output

One line confirming the active (or unchanged) sub-project. No pipeline explanation.
