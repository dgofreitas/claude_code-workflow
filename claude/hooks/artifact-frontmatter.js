#!/usr/bin/env node
'use strict';

// PreToolUse (Write) hook. Auto-injects YAML frontmatter into DERIVED SDLC artifacts
// written under an `artifacts/` tree that don't already carry it. Identity + lineage
// (id/type/title/development/epic) are derived from the filename + the sibling
// STORY-<id>.md frontmatter (the single human-authored source of truth). Mutable board
// state (status/coverage) is NEVER touched here — that lives in the checkpoint, written
// by the tech-lead skill.
//
// SOURCE artifacts (epic, story, checkpoint) are written WITH frontmatter by their own
// agent and pass through untouched (the "already has frontmatter" guard). This keeps the
// frontmatter contract in ONE place (code) instead of duplicated across ~17 agent prompts
// — same move the repo made for the RTK anti-loop rules (prompt → code-enforced hook).
//
// Fails open on any error: a missing/broken hook must never block a legitimate Write.

const fs = require('fs');
const os = require('os');
const path = require('path');

const LOG_FILE = path.join(os.tmpdir(), 'artifact-frontmatter.log');

function log(tag, data) {
  try {
    fs.appendFileSync(LOG_FILE, '[' + new Date().toISOString() + '] [' + tag + '] ' +
      (typeof data === 'string' ? data : JSON.stringify(data)) + '\n');
  } catch {
    // best-effort only
  }
}

// Derived-artifact filename suffixes → type. Longest/most-specific patterns first so
// `-qa-report-r2` matches before a hypothetical bare `-qa-report` variant.
const SUFFIX_RULES = [
  { re: /-technical-analysis$/, type: 'technical-analysis' },
  { re: /-code-analysis$/, type: 'code-analysis' },
  { re: /-ux-spec$/, type: 'ux-spec' },
  { re: /-test-report$/, type: 'test-report' },
  { re: /-qa-report(?:-r(\d+))?$/, type: 'qa-report', rev: true },
  { re: /-code-review(?:-r(\d+))?$/, type: 'code-review', rev: true },
  { re: /-impl-report-(backend|frontend|shared|fix)$/, type: 'impl-report', layer: true },
];

const GENERATED_BY = {
  'technical-analysis': 'architect',
  'code-analysis': 'code-analyzer',
  'ux-spec': 'ux-designer',
  'test-report': 'test-engineer',
  'qa-report': 'qa-analyst',
  'code-review': 'code-reviewer',
};

const IMPL_GENERATED_BY = {
  backend: 'backend-developer',
  frontend: 'frontend-developer',
  shared: 'shell-developer',
  fix: 'bug-fixer',
};

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function unquote(v) {
  const s = String(v).trim();
  if (s.length >= 2 && ((s[0] === '"' && s[s.length - 1] === '"') || (s[0] === "'" && s[s.length - 1] === "'"))) {
    return s.slice(1, -1);
  }
  return s;
}

// Minimal top-level scalar parse of a leading `---` YAML block. Enough to lift
// title/development/epic from the sibling story — we never need nested structures here.
function parseFrontmatter(text) {
  if (!text.startsWith('---')) return {};
  const end = text.indexOf('\n---', 3);
  if (end === -1) return {};
  const out = {};
  for (const line of text.slice(3, end).split('\n')) {
    const m = line.match(/^([A-Za-z0-9_]+):\s*(.*)$/);
    if (m) out[m[1]] = unquote(m[2]);
  }
  return out;
}

function yamlStr(s) {
  return '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}

function main() {
  const raw = readStdin();
  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    process.exit(0); // can't parse our own input — fail open
  }

  const ti = input.tool_input;
  if (input.tool_name !== 'Write' || !ti || typeof ti.file_path !== 'string' || typeof ti.content !== 'string') {
    process.exit(0);
  }

  const filePath = ti.file_path;
  const content = ti.content;

  // Only markdown files inside an `artifacts/` tree.
  if (!/(^|\/)artifacts\//.test(filePath) || !filePath.endsWith('.md')) process.exit(0);

  // Already has frontmatter → source artifact (epic/story/checkpoint) or hand-authored. Leave it.
  if (content.startsWith('---')) { log('SKIP_HAS_FM', filePath); process.exit(0); }

  const base = path.basename(filePath, '.md');

  let type = null, revision = null, layer = null, id = base;
  for (const rule of SUFFIX_RULES) {
    const m = base.match(rule.re);
    if (m) {
      type = rule.type;
      id = base.replace(rule.re, '');
      if (rule.rev) revision = 'r' + (m[1] || '1');
      if (rule.layer) layer = m[1];
      break;
    }
  }
  // No known derived suffix → this is a bare STORY-XXX.md / EPIC-XXX.md (source, agent-written) or unknown. Skip.
  if (!type) { log('SKIP_NOT_DERIVED', base); process.exit(0); }

  // Lift title/development/epic from the sibling story (the single source of truth).
  let story = {};
  try {
    const sib = path.join(path.dirname(filePath), id + '.md');
    if (fs.existsSync(sib)) story = parseFrontmatter(fs.readFileSync(sib, 'utf8'));
  } catch {
    // sibling unreadable — emit what we can derive from the filename alone
  }

  const generatedBy = type === 'impl-report'
    ? (IMPL_GENERATED_BY[layer] || 'developer')
    : (GENERATED_BY[type] || 'unknown');

  const lines = ['---', 'id: ' + id, 'type: ' + type, 'story: ' + id];
  if (revision) lines.push('revision: ' + revision);
  if (layer) lines.push('layer: ' + layer);
  if (story.title) lines.push('title: ' + yamlStr(story.title));
  if (story.development) lines.push('development: ' + story.development);
  if (story.epic) lines.push('epic: ' + story.epic);
  lines.push('generated_by: ' + generatedBy);
  lines.push('schema_version: 1');
  lines.push('created: ' + new Date().toISOString().slice(0, 10));
  lines.push('---', '');

  const newContent = lines.join('\n') + '\n' + content;

  log('INJECT', { filePath, type, id, revision, layer });
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      updatedInput: Object.assign({}, ti, { content: newContent }),
    },
  }));
}

main();
