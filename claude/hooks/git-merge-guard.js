#!/usr/bin/env node
'use strict';

// PreToolUse (Bash) hook. Code-enforced guards on the git "publish" boundary — the
// class of bug a prompt-only rule can silently skip under a long delegation chain
// (see: STORY-005-32 incident, gh pr merge landed a stale remote state because
// commits made after merge-request-creator's push were never re-pushed).
//
// Guard 1 — `gh pr create|merge` / `glab mr create|merge`: DENY if the branch being
// published has uncommitted changes in its working tree or commits not yet on its
// upstream. Denial reason is self-healing — agent can push and retry, no human
// needed. Applies to `create` too, not just `merge`: an MR opened against unpushed
// local state is already wrong the moment it's created.
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
// Only the REPO matters here, not which of its working trees: branch refs and the
// worktree list are shared across every tree, so any of them answers both.
function resolveRepoDir() {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  try {
    const activeProject = fs.readFileSync(path.join(projectDir, '.claude', '.active-project'), 'utf8').trim();
    if (activeProject) return path.join(projectDir, activeProject);
  } catch {
    // no umbrella / no active project file — single-project install
  }
  return projectDir;
}

// stderr is discarded: a hook writing to stderr pollutes the transcript, and every
// call site already treats a throw as the error signal.
function git(args, cwd) {
  return execFileSync('git', args, {
    cwd, encoding: 'utf8', timeout: 10000, stdio: ['ignore', 'pipe', 'ignore'],
  }).trim();
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

const PUBLISH_RE = /\b(?:gh\s+pr|glab\s+mr)\s+(create|merge)\b/;
const PUSH_RE = /\bgit\s+push\b/;

// gh and glab spellings of "branch I am publishing FROM" and "branch I am merging INTO".
// The target must be excluded explicitly: every real command names one (`--base main`),
// so matching tokens against the ref list alone would always find two branches.
const SOURCE_FLAGS = { '--head': 1, '-H': 1, '--source-branch': 1 };
const TARGET_FLAGS = { '--base': 1, '-B': 1, '--target-branch': 1 };

// Crude whitespace tokenization — not a full shell parser.
function tokenize(command) {
  return command.split(/\s+/).map((t) => t.replace(/^['"]|['"]$/g, ''));
}

function flagValue(tokens, flags) {
  for (let i = 0; i < tokens.length; i++) {
    const eq = tokens[i].indexOf('=');
    const name = eq > -1 ? tokens[i].slice(0, eq) : tokens[i];
    if (!flags[name]) continue;
    return eq > -1 ? tokens[i].slice(eq + 1) : tokens[i + 1];
  }
  return undefined;
}

// The branch being published. An explicit source flag wins outright; otherwise fall back
// to gh/glab's positional `merge <branch>`, recognised by matching a token against refs
// that actually exist. Returns null when nothing matches or several do — the caller must
// then refuse, since guarding the wrong branch is indistinguishable from not guarding.
function detectBranch(tokens, branches) {
  const explicit = flagValue(tokens, SOURCE_FLAGS);
  if (explicit) return branches.has(explicit) ? explicit : null;

  const target = flagValue(tokens, TARGET_FLAGS);
  const hits = new Set(tokens.filter((t) => t !== target && branches.has(t)));
  return hits.size === 1 ? [...hits][0] : null;
}

// The working tree holding `branch`, or null when it is checked out nowhere (then there
// is no tree that could be dirty, and only the unpushed check applies). Records are
// blank-line separated; a prunable entry points at a directory that no longer exists.
function treeForBranch(branch, repoDir) {
  let out;
  try { out = git(['worktree', 'list', '--porcelain'], repoDir); } catch { return null; }

  let tree = null, ref = null, prunable = false;
  for (const line of (out + '\n\n').split('\n')) {
    if (line.startsWith('worktree ')) { tree = line.slice(9); ref = null; prunable = false; }
    else if (line.startsWith('branch ')) ref = line.slice(7);
    else if (line.startsWith('prunable')) prunable = true;
    else if (line === '' && tree) {
      if (!prunable && ref === 'refs/heads/' + branch) return tree;
      tree = null;
    }
  }
  return null;
}

function guardPublish(command, action, repoDir) {
  // A repo we cannot read refs from is an infra failure, not a violation — fail open,
  // exactly like the outer catch. Without this the branch simply looks undetectable and
  // every publish gets denied for the wrong reason.
  let branches;
  try {
    branches = new Set(
      git(['for-each-ref', '--format=%(refname:short)', 'refs/heads/'], repoDir).split('\n').filter(Boolean)
    );
  } catch {
    return;
  }

  const tokens = tokenize(command);
  const explicit = flagValue(tokens, SOURCE_FLAGS);
  if (explicit && !branches.has(explicit)) {
    deny(
      `Branch "${explicit}" não existe localmente neste repositório. Publicar a partir dela criaria uma MR ` +
      `fantasma: a API aceita o nome e devolve uma MR válida apontando para um ref que nunca existiu. ` +
      `Confira o nome da branch (e se ela é deste sub-projeto).`
    );
    return;
  }

  const branch = detectBranch(tokens, branches);
  if (!branch) {
    deny(
      'Comando de publicação precisa nomear a branch: `gh pr create --head <branch>`, `gh pr merge <branch>`, ' +
      '`glab mr create --source-branch <branch>` ou `glab mr merge <branch>`. Sem isso não dá para saber qual ' +
      'árvore de trabalho checar — e uma story pode estar numa worktree, não no checkout do sub-projeto. ' +
      'Repita o comando nomeando a branch.'
    );
    return;
  }

  const tree = treeForBranch(branch, repoDir);
  const dirty = tree ? git(['status', '--porcelain'], tree) : '';
  let unpushed = '0';
  try {
    unpushed = git(['rev-list', `${branch}@{upstream}..${branch}`, '--count'], repoDir);
  } catch {
    unpushed = '1'; // no upstream configured — can't prove it's pushed, treat as unpushed
  }

  if (dirty || unpushed !== '0') {
    deny(
      `Branch "${branch}"${tree ? ` (árvore ${tree})` : ' (checkout em nenhuma árvore)'}: ` +
      `${dirty ? 'working tree suja' : 'working tree limpa'}, unpushed commits: ${unpushed}. ` +
      `Publicar estado local não sincronizado com o remoto ${action === 'create' ? 'abre uma MR incompleta' : 'mergea a versão ERRADA'}. ` +
      `Dê "git push" (e commit primeiro, se estiver sujo) e tente de novo.`
    );
  }
}

// Deliberately avoids a naive substring match on "main"/"master", which would
// false-positive on branch names like "fix-main-bug" or "feat/main-page-redesign".
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
  const repoDir = resolveRepoDir();

  const publishMatch = command.match(PUBLISH_RE);
  if (publishMatch) {
    try {
      guardPublish(command, publishMatch[1], repoDir);
    } catch {
      process.exit(0); // git/fs failure — fail open, never block on infra error
    }
    process.exit(0);
  }

  if (PUSH_RE.test(command)) {
    try {
      if (pushTargetsMainOrMaster(command, repoDir)) {
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
