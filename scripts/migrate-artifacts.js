#!/usr/bin/env node
'use strict';

// migrate-artifacts.js — one-time migration of an EXISTING project to the new artifact
// conventions introduced by the frontmatter/board/multi-project change.
//
// It does three things, in order:
//   1. Renames a mistyped `artifects/` folder -> `artifacts/` (and fixes internal
//      "artifects" string references inside .md files).
//   2. Backfills YAML frontmatter into existing STORY / EPIC / checkpoint / derived
//      artifacts that don't already have it (identity + lineage; title/development/epic
//      copied from the sibling story, exactly like the runtime hook).
//   3. Infers each checkpoint's `status` from its body (merged / ready / in-review /
//      in-qa / in-progress) so the Obsidian board lights up immediately.
//
// DRY RUN by default — prints a plan and touches nothing. Pass --apply to write.
// Run on a CLEAN git tree so the whole migration is a single revertible diff.
//
// Usage:
//   node scripts/migrate-artifacts.js --dest <project-root> [--apply] [--development <label>] [--force]
//
//   --dest <path>          project root to migrate (the dir that contains artifacts/ or artifects/)
//   --apply                actually write changes (default: dry run)
//   --development <label>  force this development label on ALL stories/epics (else derive
//                          from each story's Parent Epic id; blank if none)
//   --force                proceed even if the git tree is dirty / not a git repo

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

// ---- args ----------------------------------------------------------------
function parseArgs(argv) {
  const a = { apply: false, force: false, dest: null, development: null };
  for (let i = 2; i < argv.length; i++) {
    const t = argv[i];
    if (t === '--apply') a.apply = true;
    else if (t === '--force') a.force = true;
    else if (t === '--dest') a.dest = argv[++i];
    else if (t === '--development') a.development = argv[++i];
    else if (t === '-h' || t === '--help') a.help = true;
    else { console.error('Unknown arg: ' + t); a.help = true; }
  }
  return a;
}

// ---- helpers -------------------------------------------------------------
const TODAY = new Date().toISOString().slice(0, 10);

const SUFFIX_RULES = [
  { re: /-technical-analysis$/, type: 'technical-analysis', kind: 'derived' },
  { re: /-code-analysis$/, type: 'code-analysis', kind: 'derived' },
  { re: /-ux-spec$/, type: 'ux-spec', kind: 'derived' },
  { re: /-test-report$/, type: 'test-report', kind: 'derived' },
  { re: /-qa-report(?:-r(\d+))?$/, type: 'qa-report', kind: 'derived', rev: true },
  { re: /-code-review(?:-r(\d+))?$/, type: 'code-review', kind: 'derived', rev: true },
  { re: /-impl-report-(backend|frontend|shared|fix)$/, type: 'impl-report', kind: 'derived', layer: true },
  { re: /-checkpoint$/, type: 'checkpoint', kind: 'checkpoint' },
];

const GENERATED_BY = {
  'technical-analysis': 'architect', 'code-analysis': 'code-analyzer', 'ux-spec': 'ux-designer',
  'test-report': 'test-engineer', 'qa-report': 'qa-analyst', 'code-review': 'code-reviewer',
};
const IMPL_GENERATED_BY = { backend: 'backend-developer', frontend: 'frontend-developer', shared: 'shell-developer', fix: 'bug-fixer' };

function yamlStr(s) { return '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"'; }
function hasFrontmatter(text) { return text.startsWith('---'); }

function classify(name) {
  for (const r of SUFFIX_RULES) {
    const m = name.match(r.re);
    if (m) return { kind: r.kind, type: r.type, id: name.replace(r.re, ''), revision: r.rev ? 'r' + (m[1] || '1') : null, layer: r.layer ? m[1] : null };
  }
  if (/^epic-/i.test(name)) return { kind: 'epic', type: 'epic', id: name };
  if (/^story-/i.test(name)) return { kind: 'story', type: 'story', id: name };
  return null; // product singletons, summaries, loose docs, "copy" dups → left untouched
}

function titleFromHeading(text) {
  const m = text.match(/^#{1,6}\s+(?:STORY|EPIC)-[\w.-]+\s*[:\-]?\s*(.+?)\s*$/im);
  return m ? m[1].trim() : '';
}
function epicFromStory(text) {
  const m = text.match(/Parent\s*Epic[^\n]*?\b(EPIC-[\w.-]+)/i);
  return m ? m[1] : '';
}
function inferStatus(body) {
  const b = body.toLowerCase();
  if (/\[x\]\s*merge request[^\n]*https?:\/\//.test(b) || /merge request[^\n]*https?:\/\//.test(b)) return 'merged';
  if (/\[x\]\s*code review/.test(b) || /verdict:\s*approved/.test(b)) return 'ready';
  if (/\[x\]\s*qa\b/.test(b) || /qa[^\n]*status:\s*passed/.test(b)) return 'in-review';
  if (/\[x\]\s*tests?\b/.test(b)) return 'in-qa';
  return 'in-progress';
}
function inferCoverage(body) {
  const m = body.match(/(?:coverage|cobertura)[^\n%]*?(\d{2,3})\s*%/i);
  return m ? Number(m[1]) : null;
}

function buildFrontmatter(info, storyMeta, fileText) {
  const meta = storyMeta[info.id] || {};
  const L = ['---', 'id: ' + info.id, 'type: ' + info.type];
  if (info.kind === 'derived' || info.kind === 'checkpoint') L.push('story: ' + info.id);
  if (info.revision) L.push('revision: ' + info.revision);
  if (info.layer) L.push('layer: ' + info.layer);

  let title = meta.title, development = meta.development, epic = meta.epic;
  if (info.kind === 'story') { title = meta.title; development = meta.development; epic = meta.epic; }
  if (info.kind === 'epic') { title = titleFromHeading(fileText); development = ARGS.development || info.id; epic = info.id; }

  if (title) L.push('title: ' + yamlStr(title));
  if (development) L.push('development: ' + development);
  if (epic) L.push('epic: ' + epic);

  if (info.kind === 'checkpoint') {
    L.push('status: ' + inferStatus(fileText));
    const cov = inferCoverage(fileText);
    if (cov != null) L.push('coverage: ' + cov);
    L.push('generated_by: tech-lead', 'schema_version: 1', 'updated: ' + TODAY);
  } else {
    const gb = info.kind === 'epic' ? 'product-owner'
      : info.kind === 'story' ? 'product-manager'
      : info.type === 'impl-report' ? (IMPL_GENERATED_BY[info.layer] || 'developer')
      : (GENERATED_BY[info.type] || 'unknown');
    L.push('generated_by: ' + gb, 'schema_version: 1', 'created: ' + TODAY);
  }
  L.push('---', '');
  return L.join('\n');
}

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.isFile() && e.name.endsWith('.md')) out.push(p);
  }
  return out;
}

// ---- main ----------------------------------------------------------------
let ARGS;
function main() {
  ARGS = parseArgs(process.argv);
  if (ARGS.help || !ARGS.dest) {
    console.log('Usage: node scripts/migrate-artifacts.js --dest <project-root> [--apply] [--development <label>] [--force]');
    process.exit(ARGS.help ? 0 : 1);
  }
  const root = path.resolve(ARGS.dest);
  if (!fs.existsSync(root)) { console.error('dest not found: ' + root); process.exit(1); }
  const write = ARGS.apply;
  console.log(`\n# migrate-artifacts — ${write ? 'APPLY' : 'DRY RUN'}  (dest: ${root})\n`);

  // git safety
  let isRepo = false, dirty = false;
  try { const s = execFileSync('git', ['-C', root, 'status', '--porcelain'], { encoding: 'utf8' }); isRepo = true; dirty = s.trim().length > 0; } catch { isRepo = false; }
  if (write) {
    if (!isRepo && !ARGS.force) { console.error('✗ not a git repo — revert would be hard. Re-run with --force to override.'); process.exit(1); }
    if (dirty && !ARGS.force) { console.error('✗ git tree is dirty — commit/stash first (so the migration is a clean revertible diff), or --force.'); process.exit(1); }
  } else if (isRepo && dirty) {
    console.log('  ⚠ note: git tree is dirty; --apply would refuse without --force.\n');
  }

  // Phase 1 — folder rename artifects/ -> artifacts/
  const typo = path.join(root, 'artifects');
  const good = path.join(root, 'artifacts');
  if (fs.existsSync(typo)) {
    if (!fs.existsSync(good)) {
      console.log(`RENAME  artifects/  ->  artifacts/`);
      if (write) fs.renameSync(typo, good);
    } else {
      // merge non-colliding files
      const moved = [], collide = [];
      for (const f of walk(typo, [])) {
        const rel = path.relative(typo, f);
        const dst = path.join(good, rel);
        if (fs.existsSync(dst)) collide.push(rel);
        else { moved.push(rel); if (write) { fs.mkdirSync(path.dirname(dst), { recursive: true }); fs.renameSync(f, dst); } }
      }
      console.log(`MERGE   artifects/ -> artifacts/  (${moved.length} moved, ${collide.length} collisions kept in artifects/)`);
      if (collide.length) collide.slice(0, 10).forEach(c => console.log(`          collision: ${c}`));
    }
  }

  // Scan wherever the files physically are right now (artifects/ in dry run; artifacts/ after apply).
  const scanDirs = [good, typo].filter(d => fs.existsSync(d));
  if (scanDirs.length === 0) { console.log('No artifacts/ or artifects/ folder found — nothing to do.'); return; }

  // Phase 2+3 — text fix + frontmatter backfill
  const files = scanDirs.reduce((acc, d) => acc.concat(walk(d, [])), []);
  const storyMeta = {};
  for (const f of files) {
    const c = classify(path.basename(f, '.md'));
    if (c && c.kind === 'story') {
      const txt = fs.readFileSync(f, 'utf8');
      const epic = epicFromStory(txt);
      storyMeta[c.id] = { title: titleFromHeading(txt), epic, development: ARGS.development || epic || '' };
    }
  }

  const stats = { textfix: 0, story: 0, epic: 0, checkpoint: 0, derived: 0, hadFm: 0, skip: 0, partial: 0 };
  const samples = [];
  for (const f of files) {
    const orig = fs.readFileSync(f, 'utf8');
    let text = orig;
    if (text.includes('artifects')) { text = text.split('artifects').join('artifacts'); stats.textfix++; }

    const info = classify(path.basename(f, '.md'));
    if (!info) { if (text !== orig && write) fs.writeFileSync(f, text); stats.skip++; continue; }
    if (hasFrontmatter(text)) { if (text !== orig && write) fs.writeFileSync(f, text); stats.hadFm++; continue; }

    const fm = buildFrontmatter(info, storyMeta, text);
    const partial = (info.kind === 'derived' || info.kind === 'checkpoint') && !storyMeta[info.id];
    if (partial) stats.partial++;
    stats[info.kind]++;
    if (samples.length < 4) samples.push({ file: path.relative(root, f), fm });
    if (write) fs.writeFileSync(f, fm + '\n' + text);
  }

  // report
  console.log('\n## Frontmatter backfill');
  console.log(`  stories:      ${stats.story}`);
  console.log(`  epics:        ${stats.epic}`);
  console.log(`  checkpoints:  ${stats.checkpoint}  (status inferred from body)`);
  console.log(`  derived:      ${stats.derived}`);
  console.log(`  already had:  ${stats.hadFm}  (skipped)`);
  console.log(`  non-SDLC:     ${stats.skip}  (product docs / summaries / dups — untouched)`);
  console.log(`  internal 'artifects' refs fixed in: ${stats.textfix} file(s)`);
  if (stats.partial) console.log(`  ⚠ ${stats.partial} derived/checkpoint had NO sibling story → partial frontmatter (no title/development/epic)`);
  if (samples.length) {
    console.log('\n## Sample frontmatter that ' + (write ? 'was' : 'would be') + ' injected:');
    for (const s of samples) console.log(`\n--- ${s.file} ---\n${s.fm.trim()}`);
  }

  console.log('\n' + (write ? '✓ applied.' : '(dry run — nothing written. Re-run with --apply to write.)'));
  if (write && isRepo) {
    console.log('\nReview:  git -C ' + root + ' status   /   git -C ' + root + ' diff');
    console.log('Revert:  git -C ' + root + ' restore -- .   &&   git -C ' + root + ' clean -fd artifacts');
  }
}

main();
