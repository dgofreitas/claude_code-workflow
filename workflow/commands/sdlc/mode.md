---
description: Set or check the SDLC execution mode (default / auto-gate / batch-auto) without relying on natural-language trigger phrases
argument-hint: [default|auto-gate|batch-auto|status]
---

# /mode — Set SDLC Execution Mode

Deterministic override for the mode Master otherwise infers from trigger phrases (see `CLAUDE.md` → Execution Modes). Use this when the switch matters enough that you don't want to rely on phrase matching — e.g. before starting a batch run, or to drop back to manual mid-session.

## Action

This is a **Master-level action, not a subagent delegation** — run the bash commands directly in this context, no `Task()` call.

First resolve this session's state files (see `CLAUDE.md` → Active Project — mode is stored **per session**, so a second session on the same install never inherits an automatic mode):

```bash
S="${CLAUDE_CODE_SESSION_ID:+.claude/.state/$CLAUDE_CODE_SESSION_ID}"; M="$S/exec-mode"; Q="$S/batch-queue.json"
```

`$S` empty (no session id) → nothing can persist: report "Modo: default — esta versão do Claude Code não expõe o id de sessão, então o modo não persiste entre turnos" and stop.

Then parse `$ARGUMENTS` (case-insensitive), operating on `$M` / `$Q`:

- empty or `status` → `cat "$M" 2>/dev/null || echo "default (no override file)"`. Report the current mode. Do nothing else.
- `default` / `manual` → `rm -f "$M"`. Confirm: "Modo: default (todos os gates pedem aprovação)."
- `auto-gate` / `auto` / `auto-gates` → `mkdir -p "$S" && echo "auto-gate" > "$M"`. Confirm: "Modo: auto-gate (GATE-PM/SA/AR/MR automáticos, GATE-NEXT ainda pergunta)."
- `batch-auto` / `batch` → `mkdir -p "$S" && echo "batch-auto" > "$M"`. Confirm: "Modo: batch-auto (todos os gates automáticos, roda até esgotar a fila)." The queue itself (`$Q`) is built by the normal Batch-Auto flow on the next delegation (story IDs from the prompt, or the PENDING/PLANNED rows of `backlog-status.sh`) — this command only sets the mode flag, it does not start execution.
- anything else → ask the user to pick one of: default / auto-gate / batch-auto.

## Safety notes

- Switching mode mid-story does not interrupt an in-flight `tech-lead` skill invocation — it only changes gate behavior for turns after this command runs.
- Switching to `default` mid-batch (`rm "$M"`) does **not** clear the batch queue (`$Q`). The queue file stays; a later `batch-auto` would resume it. To abandon the queue entirely, also run `rm -f "$Q"`.
- Mode and queue are **per session**, not per sub-project: switching the active project (`/project`) keeps this session's mode. Another session — and this one after `/clear` — starts in default.
- This never bypasses Pre-Merge Verification (CLAUDE.md §6.1) — that check is independent of mode and always runs before GATE-MR.

## Output

One line confirming the new or current mode. No pipeline explanation.
