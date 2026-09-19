#!/usr/bin/env node
'use strict';

// PreToolUse (Write/Edit/Read/Glob/Grep) hook. These tools require an ABSOLUTE path
// (Read/Write/Edit: `file_path`; Glob/Grep: `path`), but agent prompts (external-scout,
// task-manager) only ever specify the PROJECT-RELATIVE cache path
// (`.tmp/external-context/...`, `.tmp/tasks/...`). No prompt tells the agent HOW to
// absolutize that — so the model can conflate ".tmp" with the OS-wide "/tmp" and
// literally read/write/glob /tmp/external-context/... instead of
// <project>/.tmp/external-context/...
//
// That bug is quietly severe on BOTH sides: a wrong Write path means the cache is
// machine-global (every project's cache collides into the same files) and OS-cleared on
// reboot; a wrong Read/Glob/Grep path means the "check cache first" step either never
// finds the real (correctly-written) project cache — so it never hits, defeating the
// cache entirely — or worse, finds another project's stale leftovers still sitting in
// /tmp and treats them as this project's cache.
//
// Fix: rewrite ONLY the known project-owned cache subtrees when they land at the OS-tmp
// root, for every tool that can address them. Anything else under /tmp (e.g.
// merge-request-creator's scratch /tmp/mr-body.md) is intentionally OS-temp and passes
// through untouched — this hook does not touch it.
//
// Fails open on any error: a missing/broken hook must never block a legitimate call.

const fs = require('fs');
const path = require('path');

// Top-level segment right after /tmp/ that identifies a PROJECT cache subtree, not a
// generic OS scratch file. Extend this list if a new agent gets its own .tmp/<x>/ owner.
const OWNED_SUBTREES = ['external-context', 'tasks'];

// Which input field carries the path, per tool.
const PATH_FIELD = { Write: 'file_path', Edit: 'file_path', Read: 'file_path', Glob: 'path', Grep: 'path' };

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch { return ''; }
}

function rewrite(fp, projectDir) {
  const m = String(fp || '').match(/^\/tmp\/([^/]+)(\/.*)?$/);
  if (!m || !OWNED_SUBTREES.includes(m[1])) return null; // not our concern
  return path.join(projectDir, '.tmp', m[1] + (m[2] || ''));
}

function main() {
  const raw = readStdin();
  let input;
  try { input = JSON.parse(raw); } catch { process.exit(0); }

  const field = PATH_FIELD[input.tool_name];
  const ti = input.tool_input;
  if (!field || !ti || typeof ti[field] !== 'string') process.exit(0);

  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const fixed = rewrite(ti[field], projectDir);
  if (!fixed) process.exit(0); // pass through untouched

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      updatedInput: Object.assign({}, ti, { [field]: fixed }),
    },
  }));
}

main();
