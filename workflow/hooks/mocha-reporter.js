'use strict';

// rtk ships parsers for jest/vitest/pytest/cargo/go, but none for mocha: `rtk hook
// claude` rewrites `npx mocha X` to `rtk npx mocha X`, which is plain passthrough.
// Measured on a real 875-test suite: 161,666 bytes raw vs 161,519 through rtk — 0.09%.
// mocha's own `min` reporter cuts the same suite to 53,005 bytes while keeping every
// failure intact (test name, assertion message, expected/actual diff, source line), and
// on a green suite collapses to a single `N passing` line.
//
// `rtk test <cmd>` also shrinks the output (to ~372 bytes) but it is a `tail -5`, not a
// parser: on failure it prints the tail of a stack trace with no test name and no
// assertion message. A blinded agent retries more, and retries are what actually cost —
// so this rewrites the reporter instead of routing through `rtk test`.

const fs = require('fs');
const path = require('path');

const MOCHARC_NAMES = [
  '.mocharc.js', '.mocharc.cjs', '.mocharc.mjs',
  '.mocharc.json', '.mocharc.jsonc',
  '.mocharc.yml', '.mocharc.yaml',
];

function invokesMocha(command) {
  return /(^|[\s;&|])(npx\s+)?mocha([\s;&|]|$)/.test(command);
}

function hasExplicitReporter(command) {
  return /(^|\s)(--reporter(\s|=)|-R(\s|$))/.test(command);
}

// `cd <dir> && npx mocha ...` is the shape agents actually emit; the config files that
// could already pin a reporter live in that dir, not in the hook's cwd.
function commandCwd(command, fallback) {
  const m = command.match(/^\s*cd\s+("([^"]+)"|'([^']+)'|([^\s;&|]+))/);
  const dir = m && (m[2] || m[3] || m[4]);
  return dir || fallback;
}

// In an umbrella install (one .claude/, several sub-project repos) a command without an
// explicit `cd` resolves to the umbrella root, where no .mocharc exists — which would
// read as "no reporter configured" and inject over the sub-project's own choice. mocha
// never runs without a package.json nearby, so its absence means we resolved the wrong
// directory and must not touch the command.
function looksLikeProjectRoot(dir) {
  try {
    return fs.existsSync(path.join(dir, 'package.json'));
  } catch {
    return false;
  }
}

function configuresReporter(dir, command) {
  const explicit = command.match(/--config(?:\s+|=)("([^"]+)"|'([^']+)'|([^\s;&|]+))/);
  const candidates = explicit
    ? [path.resolve(dir, explicit[2] || explicit[3] || explicit[4])]
    : MOCHARC_NAMES.map((n) => path.join(dir, n));

  for (const p of candidates) {
    try {
      if (/(^|\s|["'])reporter["']?\s*[:=]/.test(fs.readFileSync(p, 'utf8'))) return true;
    } catch {
      // unreadable or absent — nothing to honour
    }
  }
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
    if (pkg && pkg.mocha && pkg.mocha.reporter) return true;
  } catch {
    // no package.json, or no mocha block in it
  }
  return false;
}

// Returns the command unchanged whenever anything is uncertain: a wrong reporter breaks
// a test run, while a missed rewrite only forgoes the saving.
function withCompactReporter(command, cwd) {
  if (typeof command !== 'string' || !command) return command;
  if (!invokesMocha(command) || hasExplicitReporter(command)) return command;

  const dir = commandCwd(command, cwd || process.cwd());
  if (!looksLikeProjectRoot(dir)) return command;
  if (configuresReporter(dir, command)) return command;

  return command.replace(
    /((?:^|[\s;&|])(?:npx\s+)?mocha)(?=[\s;&|]|$)/,
    '$1 --reporter min'
  );
}

module.exports = { withCompactReporter, invokesMocha, hasExplicitReporter, commandCwd };
