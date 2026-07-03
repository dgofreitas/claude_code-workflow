#!/usr/bin/env node
'use strict';

// PreToolUse (Bash) hook. Replaces the previous direct "rtk hook claude" wiring.
//
// Decides, silently (the agent never sees this decision), whether to let `rtk hook
// claude` rewrite the command or whether this exact command has already failed
// BLOCK_THRESHOLD times in a row this session — in which case rtk is skipped
// entirely and the command runs exactly as the agent typed it (rtk prefix stripped
// if present). rtk-guard-track.js (PostToolUse/PostToolUseFailure) is the only
// thing that ever sets `blocked: true`; this script only reads that state.

const { execFileSync } = require('child_process');
const path = require('path');
const {
  log,
  stateFilePath,
  readState,
  readStdin,
  stripRtkPrefix,
  gcStaleSessions,
} = require('./rtk-guard-lib');

function main() {
  log('PRE_START', { pid: process.pid });

  const raw = readStdin();
  let input;
  try {
    input = JSON.parse(raw);
  } catch (e) {
    log('PRE_PARSE_FAIL', String(e && e.message));
    process.exit(0); // can't parse our own input — fail open
  }

  if (input.tool_name !== 'Bash' || !input.tool_input || typeof input.tool_input.command !== 'string') {
    process.exit(0);
  }

  gcStaleSessions();

  const command = input.tool_input.command;
  const sf = stateFilePath(input.session_id, command);
  const state = readState(sf);

  if (state.blocked) {
    const { stripped } = stripRtkPrefix(command);
    log('PRE_BLOCKED', { sessionId: input.session_id, command, stripped });
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        updatedInput: Object.assign({}, input.tool_input, { command: stripped }),
      },
    }));
    return;
  }

  // Not blocked — delegate entirely to the real rtk rewrite logic, feeding it the
  // exact same stdin we received. Pass its output straight through unchanged.
  try {
    const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const rtkBin = path.join(projectDir, '.claude', 'bin', 'rtk');
    const out = execFileSync(rtkBin, ['hook', 'claude'], {
      input: raw,
      encoding: 'utf8',
      timeout: 10000,
    });
    log('PRE_REWRITE_OK', { sessionId: input.session_id, command });
    process.stdout.write(out);
  } catch (e) {
    log('PRE_REWRITE_FAIL', String(e && e.message));
    process.exit(0); // rtk missing/broken/timed out — fail open
  }
}

main();
