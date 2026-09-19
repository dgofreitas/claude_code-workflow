#!/usr/bin/env node
'use strict';

// SessionEnd hook. Deletes this session's rtk-anti-loop state directory — a fresh
// session always starts unblocked, regardless of what happened in a previous one.

const fs = require('fs');
const { log, sessionDir, readStdin } = require('./rtk-guard-lib');

function main() {
  log('CLEANUP_START', { pid: process.pid });

  const raw = readStdin();
  let input;
  try {
    input = JSON.parse(raw);
  } catch (e) {
    log('CLEANUP_PARSE_FAIL', String(e && e.message));
    return;
  }
  if (!input.session_id) return;

  try {
    fs.rmSync(sessionDir(input.session_id), { recursive: true, force: true });
    log('CLEANUP_DONE', { sessionId: input.session_id, reason: input.reason });
  } catch (e) {
    log('CLEANUP_FAIL', String(e && e.message));
  }
}

main();
