'use strict';

// Shared state/helpers for the rtk-guard.js / rtk-guard-track.js / rtk-guard-cleanup.js
// hook trio. State lives in a plain JSON file per (session_id, normalized-command-hash)
// under the OS tmpdir — hooks are spawned fresh per invocation (no in-memory option),
// so this is the only way to remember "this command already failed N times" across calls.

const fs = require('fs');
const path = require('path');
const os = require('os');

const STATE_ROOT = path.join(os.tmpdir(), 'rtk-anti-loop');
const LOG_FILE = path.join(os.tmpdir(), 'rtk-anti-loop.log');
const BLOCK_THRESHOLD = 2; // matches the "2-Strike Rule" already used across agent prompts
const STALE_SESSION_MS = 24 * 60 * 60 * 1000; // GC safety net if SessionEnd never fires (crash/kill)

// Writing this line first thing, before any other I/O, is deliberate: an empirically
// observed race made the very first synchronous read of stdin (fd 0) occasionally
// return empty when it was the process's first filesystem/pipe touch. A cheap
// synchronous write before that first read reliably avoided it in testing (10/10
// vs ~1/5 without it). Doubles as an audit trail, same idea as the original
// OpenCode plugin's /tmp/opencode-rtk-anti-loop.log.
function log(tag, data) {
  try {
    const line = '[' + new Date().toISOString() + '] [' + tag + '] ' +
      (typeof data === 'string' ? data : JSON.stringify(data)) + '\n';
    fs.appendFileSync(LOG_FILE, line);
  } catch {
    // best-effort logging only
  }
}

function normalizeCommand(cmd) {
  return String(cmd || '')
    .replace(/\s+/g, ' ')
    .replace(/^\s*rtk\s+/, '')
    .replace(/^\s*npx\s+/, '')
    .replace(/\/home\/[^/]+\//g, '/home/*/')
    .replace(/\/Users\/[^/]+\//g, '/Users/*/')
    .replace(/\|\s*(tail|head)\s+-?\d+/g, '')
    .trim();
}

function hashCommand(cmd) {
  let h = 5381;
  for (let i = 0; i < cmd.length; i++) h = ((h * 33) ^ cmd.charCodeAt(i)) >>> 0;
  return h.toString(36);
}

function sessionDir(sessionId) {
  return path.join(STATE_ROOT, String(sessionId || 'unknown'));
}

function stateFilePath(sessionId, cmd) {
  return path.join(sessionDir(sessionId), hashCommand(normalizeCommand(cmd)) + '.json');
}

function readState(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return { consecutiveFailures: 0, lastSignature: null, blocked: false };
  }
}

function writeState(filePath, state) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(state));
}

// PostToolUse (exit 0) case: RTK can "succeed" per Claude Code's own bookkeeping while
// still producing broken/unusable output. These are the markers RTK itself emits for that.
function signatureOfSuccessOutput(stdout, stderr) {
  const o = ((stdout || '') + '\n' + (stderr || '')).trim();
  if (o.includes('[RTK:PASSTHROUGH]')) return 'passthrough';
  if (o.includes('All parsing tiers failed')) return 'passthrough';
  if (o.includes('JSON parse failed')) return 'json-parse-failed';
  if (o.includes('Output truncated')) return 'truncated';
  if (o.includes('Environment key') && o.includes('is unknown')) return 'env-unknown';
  return 'ok';
}

// PostToolUseFailure (exit != 0) case: Claude Code only exposes a generic error string
// (e.g. "Exit code 1"), no stdout/stderr. The string itself is the finest signal available.
function signatureOfFailure(errorText) {
  const e = String(errorText || '').trim();
  return e ? 'failure:' + e : 'failure:unknown';
}

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch (e) {
    log('WARN', 'readStdin failed: ' + (e && e.code) + ' ' + (e && e.message));
    return '';
  }
}

// When blocked, if the agent copied the rewritten "rtk <tool> ..." form from conversation
// history, strip it back to a native invocation — otherwise the command still goes through
// the rtk binary and reproduces the same failure even though we "unblocked" the rewrite.
function stripRtkPrefix(command) {
  const trimmed = command.trimStart();
  if (!trimmed.startsWith('rtk ')) return { stripped: command, changed: false };

  const rest = trimmed.slice(4).trimStart();
  const toolName = (rest.split(/\s+/)[0] || '');
  const needsNpx = /^(vitest|jest|mocha|eslint|tsc|prettier|vite|webpack|rollup|esbuild|tsup|stylelint)/.test(toolName);

  if (needsNpx) {
    if (toolName === 'vitest' && !rest.startsWith('vitest run')) {
      return { stripped: 'npx vitest run ' + rest.slice('vitest'.length).trimStart(), changed: true };
    }
    return { stripped: 'npx ' + rest, changed: true };
  }
  return { stripped: rest, changed: true };
}

function gcStaleSessions() {
  try {
    if (!fs.existsSync(STATE_ROOT)) return;
    const now = Date.now();
    for (const entry of fs.readdirSync(STATE_ROOT)) {
      const dir = path.join(STATE_ROOT, entry);
      try {
        const st = fs.statSync(dir);
        if (now - st.mtimeMs > STALE_SESSION_MS) {
          fs.rmSync(dir, { recursive: true, force: true });
        }
      } catch {
        // best-effort GC — never let this break the actual hook
      }
    }
  } catch {
    // best-effort
  }
}

module.exports = {
  STATE_ROOT,
  LOG_FILE,
  BLOCK_THRESHOLD,
  log,
  normalizeCommand,
  hashCommand,
  sessionDir,
  stateFilePath,
  readState,
  writeState,
  signatureOfSuccessOutput,
  signatureOfFailure,
  readStdin,
  stripRtkPrefix,
  gcStaleSessions,
};
