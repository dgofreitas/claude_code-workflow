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

// --- Obsidian lineage links -------------------------------------------------
// Obsidian only draws a graph edge / backlink from a `[[wikilink]]` — a plain
// `epic: EPIC-005` is inert text. So we wrap ONLY the lineage fields, turning the
// artifact tree into a navigable graph (EPIC <- STORY <- reports) for free.
//
// Deliberately NOT wrapped: id, type, status, development, coverage, title,
// revision, layer, schema_version, created, updated, generated_by — those are what
// the Bases board (`story-board.base`) filters and groups on, and what agents/greps
// read. Wrapping them would change behaviour; wrapping these does not.
const LINK_FIELDS = new Set(['story', 'epic', 'parent', 'parent_epic', 'depends_on', 'blocks', 'supersedes']);

// Fields whose values are DOCUMENT names rather than entity ids — the product layer
// (`sources: [VISION, PERSONAS]`) and the summary hubs (`epics:`, `stories:`). These have no
// `PREFIX-` shape to test for, so any filename-safe token is linked. A value carrying a space,
// a slash or a colon is prose (`N/A`, `TBD — see below`) and is left alone.
const DOC_LINK_FIELDS = new Set(['sources', 'epics', 'stories']);
const DOC_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

// Only bare entity ids get linked. Prose values (`epic: Backfill Automático...`,
// `supersedes: X.md (2026-08-18, pre-rework)`) are left alone rather than minted
// into ghost nodes, and an already-wrapped `[[...]]` fails this test too — which is
// what makes the pass idempotent across the checkpoint's repeated writes.
const ENTITY_ID_RE = /^(?:STORY|EPIC|HOTFIX|SPIKE|BUG|TASK)-[A-Za-z0-9][A-Za-z0-9._-]*$/;

function isEntityId(v) {
  return ENTITY_ID_RE.test(v);
}

function isDocName(v) {
  return DOC_NAME_RE.test(v) && !v.startsWith('[[');
}

function wikilink(id) {
  return yamlStr('[[' + id + ']]');
}

// Rewrites lineage fields inside the leading `---` block. The body is never touched.
// Returns the input unchanged when there is nothing to link (caller uses that to no-op).
function linkifyFrontmatter(text, selfId) {
  if (!text.startsWith('---')) return text;
  const end = text.indexOf('\n---', 3);
  if (end === -1) return text;

  const head = text.slice(3, end);
  const rest = text.slice(end);

  const out = head.split('\n').map((line) => {
    const m = line.match(/^([A-Za-z0-9_]+):[ \t]*(.*)$/);
    if (!m) return line;
    const key = m[1];
    const val = m[2].trim();
    const isDoc = DOC_LINK_FIELDS.has(key);
    if ((!LINK_FIELDS.has(key) && !isDoc) || !val) return line;
    const ok = isDoc ? isDocName : isEntityId;

    // Inline YAML flow list: `depends_on: [STORY-005-22, STORY-005-24]`.
    // `[[X]]` also starts with '[' — the all-ids test below rejects it, so it is a no-op.
    if (val.startsWith('[') && val.endsWith(']')) {
      const items = val.slice(1, -1).split(',').map((x) => unquote(x.trim())).filter(Boolean);
      if (!items.length || !items.every(ok)) return line;
      return key + ': [' + items.map(wikilink).join(', ') + ']';
    }

    const bare = unquote(val);
    if (!ok(bare)) return line;
    // An epic carries `epic: <its own id>`; linking a file to itself is noise.
    if (selfId && bare === selfId) return line;
    return key + ': ' + wikilink(bare);
  });

  return '---' + out.join('\n') + rest;
}

function emit(ti, content) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      updatedInput: Object.assign({}, ti, { content: content }),
    },
  }));
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

  // Already has frontmatter → source artifact (epic/story/checkpoint) or hand-authored.
  // We never touch its fields (identity stays the author's), but we DO run the linkify
  // pass so its lineage shows up in the Obsidian graph. No-op when nothing is linkable.
  if (content.startsWith('---')) {
    const linked = linkifyFrontmatter(content, path.basename(filePath, '.md'));
    if (linked === content) { log('SKIP_HAS_FM', filePath); process.exit(0); }
    log('LINKIFY', filePath);
    emit(ti, linked);
    return;
  }

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
  // The sibling story may already be linkified (`epic: "[[EPIC-x]]"`). unquote() stripped the
  // quotes on read, and a bare `[[x]]` is a nested YAML flow sequence, not a string — so
  // re-quote anything that came back wrapped. linkifyFrontmatter cannot repair it later
  // because an already-wrapped value fails the id test.
  if (story.epic) lines.push('epic: ' + (story.epic.startsWith('[[') ? yamlStr(story.epic) : story.epic));
  lines.push('generated_by: ' + generatedBy);
  lines.push('schema_version: 1');
  lines.push('created: ' + new Date().toISOString().slice(0, 10));
  lines.push('---', '');

  const newContent = linkifyFrontmatter(lines.join('\n') + '\n' + content, base);

  log('INJECT', { filePath, type, id, revision, layer });
  emit(ti, newContent);
}

main();
