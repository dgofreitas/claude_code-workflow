#!/usr/bin/env node
'use strict';

// PostToolUse + PostToolUseFailure (Bash) hook. Pure bookkeeping — never talks to
// the agent, never rewrites anything. Only updates the persisted per-command state
// that rtk-guard.js (PreToolUse) reads on the next attempt.
//
// Claude Code routes a Bash call to a DIFFERENT event depending on outcome:
//   - exit 0            -> PostToolUse      (full tool_response.stdout/stderr available)
//   - exit != 0          -> PostToolUseFailure (only a generic `error` string, no output)
// Both are wired to this same script; it branches on hook_event_name.

const {
  log,
  stateFilePath,
  readState,
  writeState,
  signatureOfSuccessOutput,
  signatureOfFailure,
  readStdin,
  BLOCK_THRESHOLD,
} = require('./rtk-guard-lib');

function main() {
  log('TRACK_START', { pid: process.pid });

  const raw = readStdin();
  let input;
  try {
    input = JSON.parse(raw);
  } catch (e) {
    log('TRACK_PARSE_FAIL', String(e && e.message));
    return;
  }

  if (input.tool_name !== 'Bash' || !input.tool_input || typeof input.tool_input.command !== 'string') {
    return;
  }

  let signature;
  if (input.hook_event_name === 'PostToolUseFailure') {
    signature = signatureOfFailure(input.error);
  } else if (input.hook_event_name === 'PostToolUse') {
    const resp = input.tool_response || {};
    signature = signatureOfSuccessOutput(resp.stdout, resp.stderr);
  } else {
    return;
  }

  const command = input.tool_input.command;
  const sf = stateFilePath(input.session_id, command);
  const state = readState(sf);

  if (signature === 'ok') {
    state.consecutiveFailures = 0;
    state.lastSignature = null;
  } else if (signature === state.lastSignature) {
    state.consecutiveFailures = (state.consecutiveFailures || 0) + 1;
  } else {
    state.consecutiveFailures = 1;
    state.lastSignature = signature;
  }

  if (state.consecutiveFailures >= BLOCK_THRESHOLD) {
    state.blocked = true;
  }

  writeState(sf, state);
  log('TRACK_WROTE', { sessionId: input.session_id, command, signature, state });
}

main();
