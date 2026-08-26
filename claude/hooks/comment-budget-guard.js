#!/usr/bin/env node
'use strict';

// PreToolUse (Write/Edit) hook. Enforces the ONE mechanically-checkable half of the
// Comment Budget — "max 5 lines per comment block" — at the moment a file is written,
// instead of three gates later in code-reviewer.
//
// Why here and not only there: the limit is already in every producer agent's prompt
// (backend-developer.md and friends) and gets skipped anyway under a long delegation
// chain. Caught by the reviewer, a 6-line block costs a BLOCKED verdict plus the full
// mandatory rework cycle — re-test, re-QA, re-review — to delete one line. Caught here,
// it costs the authoring agent one retry with its context still loaded.
//
// Scope is deliberately narrow: only the countable rule, only code files. Whether a
// comment narrates history instead of an invariant is judgment, and stays with the
// reviewer. Operator-facing config (.conf/.env/.ini/...) is excluded outright — there
// the comments ARE the deliverable and the budget's line limits do not transfer.
//
// Fails open on any error: a broken hook must never block a legitimate Write.

const fs = require('fs');
const path = require('path');

const MAX_BLOCK_LINES = 5;

const CODE_EXT = /\.(js|jsx|mjs|cjs|ts|tsx|py|c|h|cc|cpp|hpp|go|rb|java|sh|bash)$/i;
const COMMENT_LINE = /^\s*(#|\/\/|\*|\/\*)/;

// Blocks that are long by contract, not by bloat. Deleting or truncating any of these
// changes behavior or strips required documentation, so length is not a defect here.
const EXEMPT = /SPDX|copyright|licen[sc]e|eslint-|@ts-|noqa|type:\s*ignore|pylint:|shellcheck|nosec|nolint|@param|@returns?|@type|@throws|@example|@deprecated/i;

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch { return ''; }
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

// Runs of consecutive full-line comments longer than the budget. Trailing comments are
// invisible here by design — they live on code lines, which this budget does not govern.
function offendingBlocks(text) {
  const lines = String(text).split('\n');
  const found = [];
  let start = -1;
  let block = [];

  const flush = () => {
    if (block.length > MAX_BLOCK_LINES && !EXEMPT.test(block.join('\n'))) {
      found.push({ line: start + 1, len: block.length, first: block[0].trim().slice(0, 60) });
    }
    start = -1;
    block = [];
  };

  lines.forEach((line, i) => {
    if (COMMENT_LINE.test(line)) {
      if (start === -1) start = i;
      block.push(line);
    } else {
      flush();
    }
  });
  flush();

  return found;
}

function main() {
  const raw = readStdin();
  let input;
  try { input = JSON.parse(raw); } catch { process.exit(0); }

  const ti = input.tool_input;
  if ((input.tool_name !== 'Write' && input.tool_name !== 'Edit') || !ti || typeof ti.file_path !== 'string') {
    process.exit(0);
  }
  if (!CODE_EXT.test(ti.file_path)) process.exit(0);

  // Write carries the whole file, so its line numbers are real; Edit carries only the
  // replacement, so a block split across two edits is invisible — the reviewer still
  // covers that case.
  const body = input.tool_name === 'Write' ? ti.content : ti.new_string;
  if (typeof body !== 'string') process.exit(0);

  const blocks = offendingBlocks(body);
  if (!blocks.length) process.exit(0);

  const where = input.tool_name === 'Write' ? (b) => `linha ${b.line}` : () => 'no trecho editado';
  const detail = blocks
    .map((b) => `${b.len} linhas ${where(b)} ("${b.first}…")`)
    .join('; ');

  deny(
    `Comment Budget: ${path.basename(ti.file_path)} tem bloco de comentário acima do limite de ${MAX_BLOCK_LINES} linhas — ${detail}. ` +
    `Bloco longo vai para artifacts/stories/*.md com um ponteiro de UMA linha no código. ` +
    `Se o bloco carrega um invariante ou uma armadilha, comprima para ≤${MAX_BLOCK_LINES} linhas e mantenha o essencial — o limite vale igual. ` +
    `Reescreva e tente de novo.`
  );
}

main();
