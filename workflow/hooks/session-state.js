#!/usr/bin/env node
'use strict';

// SessionStart hook. Owns the per-session state dirs `.claude/.state/<session_id>/`, which
// hold what one conversation chose — active sub-project, exec-mode, batch queue — so two
// sessions on the same install never read each other's choice (see CLAUDE.md → Active Project).
//
// 1. Records the transcript path of this session in its dir.
// 2. Deletes the dirs whose transcript no longer exists. A dir lives exactly as long as its
//    session can be resumed: Claude Code drops transcripts after `cleanupPeriodDays`, and
//    from then on the session cannot come back. Age alone would delete the state of a
//    session resumed after weeks.
// 3. On resume, prints the stored state so it re-enters the context visibly — nothing comes
//    back in an automatic mode without the user seeing it.
//
// `/clear` starts a new session id on purpose: the user is asking for a fresh start, so
// nothing is carried over. Fails open: any error leaves the session untouched.

const fs = require('fs');
const path = require('path');

// A dir with no transcript recorded (written before this hook ran) is kept this long.
const UNRECORDED_TTL_MS = 30 * 24 * 3600 * 1000;
// A session that just started may not have written its transcript file yet.
const GRACE_MS = 24 * 3600 * 1000;

function read(file) {
  try { return fs.readFileSync(file, 'utf8').trim(); } catch { return ''; }
}

function sweep(stateRoot, ownId) {
  let entries = [];
  try { entries = fs.readdirSync(stateRoot, { withFileTypes: true }); } catch { return; }
  const now = Date.now();
  for (const e of entries) {
    if (!e.isDirectory() || e.name === ownId) continue;
    const dir = path.join(stateRoot, e.name);
    let age;
    try { age = now - fs.statSync(dir).mtimeMs; } catch { continue; }
    const transcript = read(path.join(dir, 'transcript'));
    const gone = transcript ? (age > GRACE_MS && !fs.existsSync(transcript)) : age > UNRECORDED_TTL_MS;
    if (gone) {
      try { fs.rmSync(dir, { recursive: true, force: true }); } catch { /* next session retries */ }
    }
  }
}

function resumeLine(dir) {
  const project = read(path.join(dir, 'active-project'));
  const mode = read(path.join(dir, 'exec-mode'));
  let queue = '';
  try {
    const q = JSON.parse(read(path.join(dir, 'batch-queue.json')));
    const left = Math.max(0, (q.queue || []).length - (q.current || 0));
    queue = `${left} na fila`;
  } catch { /* no queue */ }
  if (!project && !mode && !queue) return '';
  const parts = [`projeto: ${project || '(nenhum)'}`, `modo: ${mode || 'default'}`];
  if (queue) parts.push(queue);
  return `SESSÃO RETOMADA — estado desta sessão: ${parts.join(', ')}. ` +
    'Mostre esta linha ao usuário no primeiro turno' +
    (queue ? ' e, antes de continuar a fila, tire dela o que backlog-status.sh já mostra como DONE.' : '.');
}

function main() {
  let input;
  try { input = JSON.parse(fs.readFileSync(0, 'utf8')); } catch { return; }
  const sessionId = input.session_id;
  if (!sessionId || !/^[A-Za-z0-9-]+$/.test(sessionId)) return;

  const projectDir = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const stateRoot = path.join(projectDir, '.claude', '.state');
  const dir = path.join(stateRoot, sessionId);

  try {
    fs.mkdirSync(dir, { recursive: true });
    if (input.transcript_path) fs.writeFileSync(path.join(dir, 'transcript'), input.transcript_path + '\n');
  } catch { return; }

  sweep(stateRoot, sessionId);

  if (input.source === 'resume') {
    const line = resumeLine(dir);
    if (line) process.stdout.write(line + '\n');
  }
}

try { main(); } catch { /* fail open */ }
