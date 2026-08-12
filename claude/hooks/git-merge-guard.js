#!/usr/bin/env node
'use strict';

// PreToolUse (Bash) hook. Code-enforced guards on the git "publish" boundary — the
// class of bug a prompt-only rule can silently skip under a long delegation chain
// (see: STORY-005-32 incident, gh pr merge landed a stale remote state because
// commits made after merge-request-creator's push were never re-pushed).
//
// Guard 1 — `gh pr create` / `gh pr merge`: DENY if the current branch has
// uncommitted changes or commits not yet on its upstream. Denial reason is
// self-healing — agent can push and retry, no human needed. Applies to `create`
// too, not just `merge`: an MR opened against unpushed local state is already
// wrong the moment it's created, catching it here is cheaper than at merge time.
//
// Guard 2 — `git push` targeting main/master directly (explicit or bare push while
// main/master is checked out): ASK (forces human confirmation) regardless of
// exec-mode — auto-gate/batch-auto would otherwise auto-approve Claude Code's own
// built-in permission prompt for this. Legitimate recovery pushes stay possible;
// they just can't happen unattended.
//
// Fails open only on infra errors (git/node/fs failure) — never as a way to bypass
// an actually-detected violation. Matches the RTK/tmp-cache-guard convention.

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch { return ''; }
}

// Same $P resolution Master's own step-0 preamble uses — without it, an umbrella
// install would check the wrong git repo (umbrella root instead of the sub-project).
function resolveProjectDir() {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  try {
    const activeProject = fs.readFileSync(path.join(projectDir, '.claude', '.active-project'), 'utf8').trim();
    if (activeProject) return path.join(projectDir, activeProject);
  } catch {
    // no umbrella / no active project file — single-project install
  }
  return projectDir;
}

function git(args, cwd) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', timeout: 10000 }).trim();
}

function deny(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  }));
}

function ask(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'ask',
      permissionDecisionReason: reason,
    },
  }));
}

const PUBLISH_RE = /\bgh\s+pr\s+(create|merge)\b/;
const PUSH_RE = /\bgit\s+push\b/;

// Crude whitespace tokenization (not a full shell parser) — deliberately avoids a
// naive substring/regex match on "main"/"master", which would false-positive on
// branch names like "fix-main-bug" or "feat/main-page-redesign".
function pushTargetsMainOrMaster(command, cwd) {
  const tokens = command.split(/\s+/).map((t) => t.replace(/^['"]|['"]$/g, ''));
  const pushIdx = tokens.findIndex((t, i) => t === 'push' && tokens[i - 1] === 'git');
  if (pushIdx === -1) return false;

  const rest = tokens.slice(pushIdx + 1).filter((t) => !t.startsWith('-'));
  if (rest.some((t) => t === 'main' || t === 'master' || t.endsWith(':main') || t.endsWith(':master'))) {
    return true;
  }

  // Bare `git push` or `git push origin` (no explicit branch) publishes whatever is
  // currently checked out — only a real risk if that happens to be main/master.
  if (rest.length <= 1) {
    try {
      const current = git(['branch', '--show-current'], cwd);
      return current === 'main' || current === 'master';
    } catch {
      return false;
    }
  }
  return false;
}

function main() {
  const raw = readStdin();
  let input;
  try { input = JSON.parse(raw); } catch { process.exit(0); }

  if (input.tool_name !== 'Bash' || !input.tool_input || typeof input.tool_input.command !== 'string') {
    process.exit(0);
  }

  const command = input.tool_input.command;
  const cwd = resolveProjectDir();

  const publishMatch = command.match(PUBLISH_RE);
  if (publishMatch) {
    try {
      const dirty = git(['status', '--porcelain'], cwd);
      let unpushedCount = '0';
      try {
        unpushedCount = git(['rev-list', '@{u}..HEAD', '--count'], cwd);
      } catch {
        unpushedCount = '1'; // no upstream configured — can't prove it's pushed, treat as unpushed
      }

      if (dirty || unpushedCount !== '0') {
        const branch = (() => { try { return git(['branch', '--show-current'], cwd); } catch { return '?'; } })();
        const action = publishMatch[1]; // "create" or "merge"
        deny(
          `Working tree em "${branch}" está ${dirty ? 'suja' : 'limpa'}, unpushed commits: ${unpushedCount}. ` +
          `"gh pr ${action}" sobre estado local não sincronizado com o remoto ${action === 'create' ? 'abre uma MR incompleta' : 'mergea a versão ERRADA'}. ` +
          `Dê "git push" (e commit primeiro, se estiver sujo) e tente de novo.`
        );
        return;
      }
    } catch {
      process.exit(0); // git/fs failure — fail open, never block on infra error
    }
    process.exit(0);
  }

  if (PUSH_RE.test(command)) {
    try {
      if (pushTargetsMainOrMaster(command, cwd)) {
        ask(
          'Push direto para a branch default (main/master) ignora revisão de PR. Confirme que isso é intencional ' +
          '(ex.: recovery de estado quebrado) — se for trabalho normal de story, prefira abrir/atualizar um PR.'
        );
        return;
      }
    } catch {
      process.exit(0); // fail open on infra error
    }
  }

  process.exit(0);
}

main();
