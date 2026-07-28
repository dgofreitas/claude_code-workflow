#!/usr/bin/env node
'use strict';

// PreToolUse (Write/Edit) hook. Write/Edit require an ABSOLUTE file_path, but agent
// prompts (external-scout, task-manager) only ever specify the PROJECT-RELATIVE cache
// path (`.tmp/external-context/...`, `.tmp/tasks/...`). No prompt tells the agent HOW
// to absolutize that — so the model can conflate ".tmp" with the OS-wide "/tmp" and
// literally write to /tmp/external-context/... instead of <project>/.tmp/external-context/...
//
// That bug is quietly severe: /tmp is machine-global (every project's cache collides
// into the same files) and OS-cleared on reboot (the cache silently evaporates).
//
// Fix: rewrite ONLY the known project-owned cache subtrees when they land at the OS-tmp
// root. Anything else under /tmp (e.g. merge-request-creator's scratch /tmp/mr-body.md)
// is intentionally OS-temp and passes through untouched — this hook does not touch it.
//
// Fails open on any error: a missing/broken hook must never block a legitimate Write.

const fs = require('fs');
const path = require('path');

// Top-level segment right after /tmp/ that identifies a PROJECT cache subtree, not a
// generic OS scratch file. Extend this list if a new agent gets its own .tmp/<x>/ owner.
const OWNED_SUBTREES = ['external-context', 'tasks'];

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch { return ''; }
}

function main() {
  const raw = readStdin();
  let input;
  try { input = JSON.parse(raw); } catch { process.exit(0); }

  const ti = input.tool_input;
  if ((input.tool_name !== 'Write' && input.tool_name !== 'Edit') || !ti || typeof ti.file_path !== 'string') {
    process.exit(0);
  }

  const fp = ti.file_path;
  const m = fp.match(/^\/tmp\/([^/]+)(\/.*)?$/);
  if (!m || !OWNED_SUBTREES.includes(m[1])) process.exit(0); // not our concern — pass through

  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const fixed = path.join(projectDir, '.tmp', m[1] + (m[2] || ''));

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      updatedInput: Object.assign({}, ti, { file_path: fixed }),
    },
  }));
}

main();
