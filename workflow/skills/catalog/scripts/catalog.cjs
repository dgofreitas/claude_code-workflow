#!/usr/bin/env node
// catalog.cjs — the deterministic half of the project catalog (artifacts/catalog/).
// Agents write the entries; this script decides which entries a diff touched, which
// went stale, whether two sub-projects disagree on a contract, and renders INDEX.md.
//
//   node catalog.cjs index     --project P            rewrite INDEX.md from the entries
//   node catalog.cjs affected  --project P [--base R] what the current branch's diff touched
//   node catalog.cjs check     --project P            stale entries, broken refs, contracts
//   node catalog.cjs lookup    --project P term...    entries matching the terms
//   node catalog.cjs inventory --project P            bootstrap aid: candidate units in the code
//
// .cjs on purpose: a project's package.json may say "type": "module", and the
// machines this runs on default to Node 18 — no ESM-only or newer APIs here.
//
// Exit codes: 0 ok · 1 usage/fatal · 2 check found problems · 3 no catalog in project

'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const CATALOG_DIR = path.join('artifacts', 'catalog');
const KINDS = { 'catalog-feature': 'features', 'catalog-contract': 'contracts' };

// Paths no entry needs to cover. Extendable per project with `ignore:` in overview.md.
const DEFAULT_IGNORE = [
  'artifacts/**', 'test/**', 'tests/**', '**/__tests__/**', '**/*.test.*', '**/*.spec.*',
  'coverage/**', 'node_modules/**', 'docs/**', '**/*.md', 'package-lock.json',
  'yarn.lock', 'pnpm-lock.yaml', '.gitignore', '.gitlab-ci.yml', '.github/**',
  '.claude/**', '.husky/**', '**/.eslintrc*', 'eslint.config.*', '.releaserc*',
];
const SOURCE_RE = new RegExp('\\.(' + [
  'c', 'h', 'cc', 'cpp', 'cxx', 'hpp', 'hh', 'js', 'cjs', 'mjs', 'jsx', 'ts', 'tsx', 'vue', 'svelte',
  'py', 'lua', 'go', 'rs', 'java', 'kt', 'kts', 'scala', 'groovy', 'cs', 'fs', 'rb', 'php', 'swift',
  'm', 'mm', 'dart', 'ex', 'exs', 'erl', 'pl', 'pm', 'r', 'jl', 'sh', 'bash', 'zsh', 'ps1', 'awk', 'sed',
  'sql', 'proto', 'graphql', 'gql', 'tf', 'njk', 'hbs', 'ejs', 'html', 'jinja', 'j2',
  'json5?', 'ya?ml', 'toml', 'ini', 'cfg', 'conf',
].join('|') + ')$');

// ---------------------------------------------------------------- frontmatter

// Minimal YAML subset: `k: v`, `k: [a, b]`, and block lists. Values lose their quotes
// and the `[[...]]` wrapper the artifact-frontmatter hook adds to `stories:`.
function clean(v) {
  return v.trim().replace(/^["']|["']$/g, '').replace(/^\[\[(.*)\]\]$/, '$1').trim();
}

function parseFrontmatter(text) {
  if (!text.startsWith('---')) return null;
  const end = text.indexOf('\n---', 3);
  if (end === -1) return null;
  const fm = {};
  let listKey = null;
  for (const line of text.slice(3, end).split('\n')) {
    const item = line.match(/^\s+-\s+(.*)$/);
    if (item && listKey) {
      fm[listKey].push(clean(item[1]));
      continue;
    }
    const m = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!m) continue;
    const [, key, raw] = m;
    const val = raw.trim();
    listKey = null;
    if (val === '') {
      fm[key] = [];
      listKey = key;
    } else if (val.startsWith('[') && val.endsWith(']') && !val.startsWith('[[')) {
      fm[key] = val.slice(1, -1).split(',').map(clean).filter(Boolean);
    } else {
      fm[key] = clean(val);
    }
  }
  return { fm, body: text.slice(end + 4) };
}

const asList = (v) => (Array.isArray(v) ? v : v ? [v] : []);

// ---------------------------------------------------------------- git + globs

function git(cwd, args, opts) {
  try {
    return execFileSync('git', ['-C', cwd].concat(args), {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024,
    }).trim();
  } catch (e) {
    if (opts && opts.allowFail) return null;
    throw new Error('git ' + args.join(' ') + ' failed in ' + cwd);
  }
}

function globToRe(g) {
  let re = '';
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === '*' && g[i + 1] === '*') {
      re += g[i + 2] === '/' ? '(?:.*/)?' : '.*';
      i += g[i + 2] === '/' ? 2 : 1;
    } else if (c === '*') re += '[^/]*';
    else if (c === '?') re += '[^/]';
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp('^' + re + '$');
}

function ignorer(extra) {
  const res = DEFAULT_IGNORE.concat(asList(extra)).map(globToRe);
  return (p) => res.some((r) => r.test(p));
}

// The branch a story forked from: of the usual long-lived remote branches, the one whose
// merge-base is fewest commits behind HEAD. MR targets differ per repo (main, alpha...),
// so nothing here assumes one.
function forkBase(project) {
  const cands = ['origin/HEAD', 'origin/main', 'origin/master', 'origin/trunk', 'origin/develop', 'origin/dev',
    'origin/next', 'origin/alpha', 'origin/beta', 'origin/stable', 'origin/release'];
  let best = null;
  for (const ref of cands) {
    if (git(project, ['rev-parse', '--verify', '-q', ref], { allowFail: true }) === null) continue;
    const mb = git(project, ['merge-base', 'HEAD', ref], { allowFail: true });
    if (!mb) continue;
    const ahead = Number(git(project, ['rev-list', '--count', mb + '..HEAD']));
    if (!best || ahead < best.ahead) best = { ref, mb, ahead };
  }
  return best;
}

// ---------------------------------------------------------------- catalog load

function loadCatalog(project) {
  const root = path.join(project, CATALOG_DIR);
  if (!fs.existsSync(root)) return null;
  const entries = [];
  const problems = [];
  for (const sub of Object.values(KINDS)) {
    const dir = path.join(root, sub);
    if (!fs.existsSync(dir)) continue;
    for (const name of fs.readdirSync(dir).filter((n) => n.endsWith('.md')).sort()) {
      const rel = sub + '/' + name;
      const parsed = parseFrontmatter(fs.readFileSync(path.join(dir, name), 'utf8'));
      if (!parsed) {
        problems.push(['ERROR', rel, 'no frontmatter']);
        continue;
      }
      entries.push(Object.assign({ rel, body: parsed.body }, parsed.fm));
    }
  }
  let overview = null;
  const ov = path.join(root, 'overview.md');
  if (fs.existsSync(ov)) overview = (parseFrontmatter(fs.readFileSync(ov, 'utf8')) || { fm: {} }).fm;
  return { root, entries, problems, overview };
}

function validate(cat) {
  const problems = cat.problems.slice();
  const seen = {};
  const providedBy = {};
  for (const e of cat.entries) {
    for (const k of ['id', 'type', 'title', 'summary', 'verified-at']) {
      if (!e[k] || (Array.isArray(e[k]) && !e[k].length)) problems.push(['ERROR', e.rel, 'missing `' + k + ':`']);
    }
    if (e.type && !KINDS[e.type]) problems.push(['ERROR', e.rel, 'unknown type `' + e.type + '`']);
    if (e.type && KINDS[e.type] && !e.rel.startsWith(KINDS[e.type] + '/')) {
      problems.push(['ERROR', e.rel, '`' + e.type + '` belongs in ' + KINDS[e.type] + '/']);
    }
    if (e.type === 'catalog-contract') {
      if (!['provider', 'consumer'].includes(e.role)) problems.push(['ERROR', e.rel, '`role:` must be provider or consumer']);
      if (!e.kind) problems.push(['ERROR', e.rel, 'missing `kind:`']);
    }
    if (!asList(e.files).length) problems.push(['ERROR', e.rel, 'no `files:` — an entry that points nowhere cannot go stale, so it cannot be trusted']);
    // One capability, one feature. Parallel init batches cannot see each other's writes, and
    // two of them describing the same thing is the one race nothing else here catches: both
    // claim to provide the same contract.
    if (e.type === 'catalog-feature') {
      for (const id of asList(e.provides)) {
        if (providedBy[id]) problems.push(['ERROR', e.rel, 'provides `' + id + '`, as does ' + providedBy[id] + ' — one capability described twice? merge them, or keep `provides:` on the feature that implements it']);
        else providedBy[id] = e.rel;
      }
    }
    // Several consumers of one id are legitimate (a bot and a tester both call POST /host,
    // each reading different fields); two providers, or two features, are one entry split.
    if (e.role === 'consumer') continue;
    const key = e.id + '|' + (e.role || '');
    if (e.id && seen[key]) problems.push(['ERROR', e.rel, 'duplicate id with ' + seen[key]]);
    if (e.id) seen[key] = e.rel;
  }
  return problems;
}

// ---------------------------------------------------------------- index

function renderIndex(cat) {
  const line = (e) => '- `' + e.rel + '` | tags: ' + asList(e.tags).join(', ') + ' | summary: ' + e.summary;
  const feats = cat.entries.filter((e) => e.type === 'catalog-feature');
  const prov = cat.entries.filter((e) => e.type === 'catalog-contract' && e.role === 'provider');
  const cons = cat.entries.filter((e) => e.type === 'catalog-contract' && e.role === 'consumer');
  const out = [
    '<!-- GENERATED by .claude/skills/catalog/scripts/catalog.cjs index — never edit by hand -->',
    '',
    '# Catalog INDEX',
    '',
    '> What exists in THIS project and where. Describes the code; never prescribes —',
    '> for how new code must be written, `.claude/context/` wins. Format: `.claude/skills/catalog/SKILL.md`.',
    '',
    '- `overview.md` | tags: overview, modules, stack | summary: What the project is, its modules and how it talks to its neighbours.',
    '',
    '## Features (' + feats.length + ')',
    '',
  ].concat(feats.map(line), [
    '',
    '## Contracts provided (' + prov.length + ')',
    '',
  ], prov.map(line), [
    '',
    '## Contracts consumed (' + cons.length + ')',
    '',
  ], cons.map(line), ['']);
  return out.join('\n');
}

function cmdIndex(project, cat) {
  const problems = validate(cat).filter((p) => p[0] === 'ERROR');
  if (problems.length) {
    report(problems);
    console.error('INDEX not written: fix the errors above first.');
    return 2;
  }
  fs.writeFileSync(path.join(cat.root, 'INDEX.md'), renderIndex(cat));
  console.log('INDEX.md written: ' + cat.entries.length + ' entries');
  return 0;
}

// ---------------------------------------------------------------- affected

// Files changed since each sha, computed once per distinct sha: a bootstrap stamps every
// entry with the same one, so this is one `git diff` instead of one per entry — what makes
// it cheap enough for `lookup` and the session-start summary.
const changedSince = {};
function staleFiles(project, e) {
  const files = asList(e.files);
  const sha = e['verified-at'];
  if (!sha || !files.length) return null;
  const key = path.resolve(project) + '@' + sha;
  if (!(key in changedSince)) {
    if (git(project, ['cat-file', '-e', sha + '^{commit}'], { allowFail: true }) === null) changedSince[key] = null;
    else {
      const out = git(project, ['diff', '--name-only', '--no-renames', sha, 'HEAD'], { allowFail: true });
      changedSince[key] = new Set(out ? out.split('\n').filter(Boolean) : []);
    }
  }
  const changed = changedSince[key];
  if (changed === null) return ['(verified-at ' + sha + ' not in this repo — re-verify)'];
  return files.filter((f) => changed.has(f));
}

function cmdAffected(project, cat, baseArg) {
  const base = baseArg ? { ref: baseArg, mb: git(project, ['merge-base', 'HEAD', baseArg]) } : forkBase(project);
  if (!base) {
    console.error('cannot find the fork base — pass --base <ref>');
    return 1;
  }
  const ns = git(project, ['diff', '--name-status', '-M', base.mb, 'HEAD']);
  const changes = ns ? ns.split('\n').map((l) => l.split('\t')) : [];
  const ignored = ignorer(cat.overview && cat.overview.ignore);
  const changed = new Set();
  const gone = new Set();
  for (const c of changes) {
    const st = c[0][0];
    if (st === 'R') {
      gone.add(c[1]);
      changed.add(c[2]);
    } else if (st === 'D') gone.add(c[1]);
    else changed.add(c[1]);
  }

  const touched = [];
  const covered = new Set();
  for (const e of cat.entries) {
    const files = asList(e.files);
    files.forEach((f) => covered.add(f));
    const hit = files.filter((f) => changed.has(f) || gone.has(f));
    if (hit.length) touched.push({ e, hit, gone: hit.filter((f) => gone.has(f)), allGone: files.every((f) => gone.has(f)) });
  }
  const uncovered = Array.from(changed).filter((f) => !covered.has(f) && !ignored(f) && SOURCE_RE.test(f));

  // Drift from outside the workflow: entries this diff did not touch whose files moved
  // anyway since they were verified. Capped — the story MR is not a catalog rewrite.
  const touchedSet = new Set(touched.map((t) => t.e.rel));
  const drift = [];
  for (const e of cat.entries) {
    if (touchedSet.has(e.rel)) continue;
    const s = staleFiles(project, e);
    if (s && s.length) drift.push({ e, s });
  }

  const work = touched.length || uncovered.length || drift.length;
  console.log('CATALOG: ' + (work ? 'update' : 'no-op'));
  // The size tech-lead splits on: one keeper call per ~12 entries, like init batches.
  const units = touched.length + Math.min(drift.length, 5) + Math.ceil(uncovered.length / 4);
  console.log('work units: ' + units + ' (touched ' + touched.length + ', stale ' + Math.min(drift.length, 5) +
    ', uncovered files ' + uncovered.length + ')' + (units > 12 ? ' — split into parallel batches of ≤ 12' : ''));
  console.log('base: ' + base.ref + ' @ ' + base.mb.slice(0, 10) + ' | head: ' + git(project, ['rev-parse', '--short=10', 'HEAD']));
  console.log('changed files: ' + changes.length);
  if (touched.length) {
    console.log('\n## Entries touched by this diff (' + touched.length + ')');
    for (const t of touched) {
      console.log('- ' + t.e.rel + ' ← ' + t.hit.join(', ') +
        (t.allGone ? '  [ALL FILES GONE — capability removed? delete the entry; moved? repoint it]'
          : t.gone.length ? '  [GONE: ' + t.gone.join(', ') + ']' : ''));
    }
  }
  if (uncovered.length) {
    console.log('\n## Changed source files no entry covers (' + uncovered.length + ')');
    uncovered.forEach((f) => console.log('- ' + f));
  }
  if (drift.length) {
    console.log('\n## Stale from outside this diff (' + drift.length + ', refresh at most 5)');
    drift.slice(0, 5).forEach((d) => console.log('- ' + d.e.rel + ' ← ' + d.s.join(', ')));
  }
  return 0;
}

// ---------------------------------------------------------------- check

// Sibling sub-projects of an umbrella: every <parent>/<dir>/artifacts/catalog/ except ours.
// A worktree under .worktrees/ sees the same siblings as its sub-project checkout. A sibling
// whose catalog is still on an unmerged branch lives in a worktree instead — name it with
// --siblings.
function siblingCatalogs(project, explicit) {
  if (explicit) {
    return explicit.split(',').filter(Boolean).map((dir) => ({ name: path.basename(dir), cat: loadCatalog(dir) })).filter((s) => s.cat);
  }
  const abs = path.resolve(project);
  const top = git(abs, ['rev-parse', '--show-toplevel'], { allowFail: true }) || abs;
  const common = git(abs, ['rev-parse', '--path-format=absolute', '--git-common-dir'], { allowFail: true });
  const home = common ? path.dirname(common) : top;
  const parent = path.dirname(home);
  // During a bootstrap every sub-project's catalog sits on a branch of the same name, often in
  // a worktree rather than in the sub-project checkout. A sibling worktree on this project's
  // branch wins over the sibling checkout, so a coordinated bootstrap cross-checks itself.
  const branch = git(abs, ['branch', '--show-current'], { allowFail: true });
  const out = [];
  for (const d of fs.readdirSync(parent)) {
    const dir = path.join(parent, d);
    if (dir === home || dir === top) continue;
    if (git(dir, ['rev-parse', '--git-dir'], { allowFail: true }) === null) continue;
    let where = dir;
    if (branch) {
      const wl = git(dir, ['worktree', 'list', '--porcelain'], { allowFail: true }) || '';
      for (const block of wl.split('\n\n')) {
        const wt = (block.match(/^worktree (.+)$/m) || [])[1];
        const br = (block.match(/^branch refs\/heads\/(.+)$/m) || [])[1];
        if (wt && br === branch && fs.existsSync(path.join(wt, CATALOG_DIR))) where = wt;
      }
    }
    if (!fs.existsSync(path.join(where, CATALOG_DIR))) continue;
    const cat = loadCatalog(where);
    if (cat) out.push({ name: where === dir ? d : d + ' (' + path.basename(where) + ')', cat });
  }
  return out;
}

function cmdCheck(project, cat, siblings) {
  const problems = validate(cat);
  for (const e of cat.entries) {
    for (const f of asList(e.files)) {
      if (!fs.existsSync(path.join(project, f))) problems.push(['ERROR', e.rel, 'file does not exist: ' + f]);
    }
    const s = staleFiles(project, e);
    if (s && s.length) problems.push(['STALE', e.rel, 'changed since ' + e['verified-at'] + ': ' + s.join(', ')]);
  }

  const idx = path.join(cat.root, 'INDEX.md');
  if (!fs.existsSync(idx) || fs.readFileSync(idx, 'utf8') !== renderIndex(cat)) {
    problems.push(['ERROR', 'INDEX.md', 'out of date — run `catalog.cjs index`']);
  }

  // Contracts: the same id on both sides is the join key. A consumer reading a field the
  // provider does not emit is the "producer and consumer disagree" class of defect.
  const mine = cat.entries.filter((e) => e.type === 'catalog-contract');
  const sibs = siblingCatalogs(project, siblings);
  const norm = (f) => f.replace(/\[\]/g, '').replace(/\s+/g, '');
  const providers = {};
  const owners = {};
  for (const src of [{ name: '(this project)', cat }].concat(sibs)) {
    for (const e of src.cat.entries) {
      if (e.type !== 'catalog-contract' || e.role !== 'provider') continue;
      providers[e.id] = { e, where: src.name };
      (owners[e.id] = owners[e.id] || []).push(src.name);
    }
  }
  // Two projects providing one id are two different things sharing a name (two `sessions`
  // collections in two databases), and a consumer would be joined to whichever came last.
  for (const e of mine.filter((x) => x.role === 'provider')) {
    if (owners[e.id] && owners[e.id].length > 1) {
      problems.push(['ERROR', e.rel, '`' + e.id + '` is also provided by ' + owners[e.id].filter((o) => o !== '(this project)').join(', ') +
        ' — qualify the name with what tells them apart (e.g. mongo.<database>.<collection>, http with the host/service prefix)']);
    }
  }
  for (const e of mine.filter((x) => x.role === 'consumer')) {
    const p = providers[e.id];
    if (!p) {
      problems.push(['INFO', e.rel, 'no provider catalogued for `' + e.id + '`' + (e.counterpart ? ' (counterpart: ' + e.counterpart + ')' : '')]);
      continue;
    }
    // The two sides rarely write fields at the same depth: `releaseUpdate` on one side covers
    // `releaseUpdate.termoAceite` on the other, and `items[].id` is `items.id`. Only a field with
    // no ancestor or descendant on the provider side is a disagreement.
    const emitted = asList(p.e.fields).map(norm);
    const covers = (f) => emitted.some((q) => q === f || f.startsWith(q + '.') || q.startsWith(f + '.'));
    const missing = asList(e.fields).filter((f) => !covers(norm(f)));
    if (missing.length && emitted.length) {
      problems.push(['MISMATCH', e.rel, 'reads ' + missing.join(', ') + ' — not in ' + p.where + ' ' + p.e.rel]);
    }
  }

  // The other direction: this project's providers against the siblings' consumers. Without
  // it a story that drops a field a sibling still reads passes its own check — the provider's
  // story is exactly where that break has to show up.
  for (const e of mine.filter((x) => x.role === 'provider')) {
    const emitted = asList(e.fields).map(norm);
    if (!emitted.length) continue;
    const covers = (f) => emitted.some((q) => q === f || f.startsWith(q + '.') || q.startsWith(f + '.'));
    for (const sib of sibs) {
      for (const c of sib.cat.entries) {
        if (c.type !== 'catalog-contract' || c.role !== 'consumer' || c.id !== e.id) continue;
        const missing = asList(c.fields).filter((f) => !covers(norm(f)));
        if (missing.length) problems.push(['MISMATCH', e.rel, sib.name + ' ' + c.rel + ' reads ' + missing.join(', ') + ' — not emitted here']);
      }
    }
  }

  const ignored = ignorer(cat.overview && cat.overview.ignore);
  const covered = new Set();
  cat.entries.forEach((e) => asList(e.files).forEach((f) => covered.add(f)));
  const src = git(project, ['ls-files']).split('\n').filter((f) => f && !ignored(f) && SOURCE_RE.test(f));
  const unc = src.filter((f) => !covered.has(f));
  const pct = src.length ? Math.round((100 * (src.length - unc.length)) / src.length) : 100;
  // A large rewrite done outside the workflow: refreshing entry by entry costs more and ends
  // worse than rebuilding — the old entries' boundaries no longer match the code.
  const hit = new Set(problems.filter((x) => x[0] === 'STALE' || (x[0] === 'ERROR' && /file does not exist/.test(x[2]))).map((x) => x[1]));
  const ratio = cat.entries.length ? hit.size / cat.entries.length : 0;
  if (hit.size) {
    problems.push(['INFO', '(remedy)', hit.size + ' of ' + cat.entries.length + ' entries (' + Math.round(ratio * 100) + '%) stale or pointing at removed files — ' +
      (ratio > 0.3 ? 'above 30%: rebuild with `/sdlc:catalog init` rather than refresh' : '`/sdlc:catalog refresh` them')]);
  }
  problems.push(['INFO', '(coverage)', pct + '% of ' + src.length + ' source files are in some entry' + (sibs.length ? ' | siblings with a catalog: ' + sibs.map((s) => s.name).join(', ') : '')]);

  report(problems);
  return problems.some((p) => p[0] !== 'INFO') ? 2 : 0;
}

function report(problems) {
  const order = { ERROR: 0, MISMATCH: 1, STALE: 2, INFO: 3 };
  problems.sort((a, b) => order[a[0]] - order[b[0]]);
  for (const [lvl, where, msg] of problems) console.log(lvl.padEnd(8) + ' ' + where + ' — ' + msg);
  const n = problems.filter((p) => p[0] !== 'INFO').length;
  console.log('\n' + (n ? n + ' problem(s)' : 'ok'));
}

// ---------------------------------------------------------------- lookup

function cmdLookup(project, cat, terms) {
  if (!terms.length) {
    console.error('lookup needs at least one term');
    return 1;
  }
  const res = terms.map((t) => new RegExp(t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'));
  const scored = cat.entries.map((e) => {
    const hay = [e.id, e.title, e.summary].concat(asList(e.tags), asList(e.canonical), asList(e.files), asList(e.provides), asList(e.consumes)).join(' ');
    const head = res.filter((r) => r.test(hay)).length;
    const body = res.filter((r) => r.test(e.body)).length;
    return { e, score: head * 2 + body };
  }).filter((x) => x.score).sort((a, b) => b.score - a.score).slice(0, 8);
  if (!scored.length) {
    console.log('no catalog entry matches: ' + terms.join(' ') + ' — explore the code, and the entry gets written at the end of the story');
    return 0;
  }
  for (const { e, score } of scored) {
    console.log('- ' + path.join(CATALOG_DIR, e.rel) + '  (score ' + score + ')');
    console.log('  ' + e.summary);
    // The answer a planner is looking for: where a domain value is computed, so the story
    // uses it instead of computing it again.
    for (const c of asList(e.canonical)) console.log('  canonical: ' + c);
    console.log('  files: ' + asList(e.files).join(', '));
    // Flagged at the moment of use: a planner reading a stale entry is the harm, and the
    // story that would refresh it only runs after the plan exists.
    const s = staleFiles(project, e);
    if (s && s.length) console.log('  ⚠ STALE since ' + e['verified-at'] + ': ' + s.join(', ') + ' — confirm in code before relying on it');
  }
  return 0;
}

// ---------------------------------------------------------------- summary

// One line per catalogued project for the SessionStart hook, and nothing when all is well —
// a line every session that says "ok" is noise the user learns to skip. In an umbrella the
// session runs from a root that is not a repo: every sub-project with a catalog is covered.
function cmdSummary(root) {
  const projects = [];
  if (fs.existsSync(path.join(root, CATALOG_DIR))) projects.push(root);
  else {
    for (const d of fs.readdirSync(root)) {
      const dir = path.join(root, d);
      try {
        if (fs.statSync(dir).isDirectory() && fs.existsSync(path.join(dir, CATALOG_DIR))) projects.push(dir);
      } catch (e) {
        // unreadable entry — not a project
      }
    }
  }
  for (const p of projects) {
    if (git(p, ['rev-parse', '--git-dir'], { allowFail: true }) === null) continue;
    const cat = loadCatalog(p);
    if (!cat) continue;
    const stale = cat.entries.filter((e) => {
      const s = staleFiles(p, e);
      return s && s.length;
    }).length;
    if (stale) {
      console.log('Catálogo ' + path.basename(p) + ': ' + stale + ' de ' + cat.entries.length +
        ' entradas desatualizadas (código mudou fora do workflow) — "catálogo desatualizado" lista e oferece refresh.');
    }
  }
  return 0;
}

// ---------------------------------------------------------------- inventory

// Interface hints per language — a map for the bootstrap agent to split work by and to spot
// contracts, never a source of truth: everything it prints is confirmed by reading the code.
// Each pattern applies only to files of its own language, so Python's `d.get('x')` is never
// read as an Express route. A language with no row here still gets its files and line counts.
const UP = (m) => m[1].toUpperCase() + ' ' + m[2];
const ONE = (m) => m[1];
const LANGS = [
  [/\.(js|cjs|mjs|jsx|ts|tsx)$/, [
    ['route', /\b(?:router|app|r|server|fastify)\.(get|post|put|patch|delete|all)\(\s*['"`]([^'"`]+)/g, UP],
    ['mount', /\b(?:app|router)\.use\(\s*['"`]([^'"`]+)/g, ONE],
    ['route', /@(Get|Post|Put|Patch|Delete)\(\s*['"`]([^'"`]*)/g, UP],
    ['env', /process\.env\.([A-Z0-9_]+)/g, ONE],
    ['collection', /\.collection\(\s*['"`]([^'"`]+)/g, ONE],
    ['http-out', /\bmethod:\s*['"`](GET|POST|PUT|PATCH|DELETE)['"`],\s*path:\s*[`'"]([^`'"]+)/g, UP],
    ['http-out', /\b(?:fetch|axios\.(?:get|post|put|patch|delete))\(\s*[`'"]([^`'"]+)/g, ONE],
    ['event', /\.(?:publish|subscribe|emit)\(\s*['"`]([^'"`]+)/g, ONE],
  ]],
  [/\.py$/, [
    ['route', /@\w+\.(get|post|put|patch|delete|route)\(\s*[rf]?['"]([^'"]+)/g, UP],
    ['route', /\b(?:re_)?path\(\s*r?['"]([^'"]*)['"]\s*,/g, ONE],
    ['env', /os\.(?:environ(?:\.get)?\(?\[?|getenv\()\s*['"]([A-Z0-9_]+)/g, ONE],
    ['http-out', /\b(?:requests|httpx)\.(get|post|put|patch|delete)\(\s*f?['"]([^'"]+)/g, UP],
    ['table', /__tablename__\s*=\s*['"]([^'"]+)/g, ONE],
  ]],
  [/\.go$/, [
    ['route', /\.(GET|POST|PUT|PATCH|DELETE)\(\s*"([^"]+)/g, UP],
    ['route', /HandleFunc\(\s*"([^"]+)/g, ONE],
    ['env', /os\.Getenv\(\s*"([A-Z0-9_]+)/g, ONE],
  ]],
  [/\.(java|kt|kts|scala|groovy)$/, [
    ['route', /@(Get|Post|Put|Patch|Delete|Request)Mapping\(\s*(?:value\s*=\s*|path\s*=\s*)?"([^"]*)/g, UP],
    ['env', /System\.getenv\(\s*"([A-Z0-9_]+)/g, ONE],
  ]],
  [/\.(c|h|cc|cpp|cxx|hpp|hh)$/, [
    ['env', /\bgetenv\(\s*"([A-Z0-9_]+)/g, ONE],
    ['ipc', /\b(bind|connect|listen|mq_open|shm_open|mkfifo)\s*\(/g, ONE],
    ['entry', /^\s*int\s+(main)\s*\(/gm, ONE],
  ]],
  [/\.(h|hpp|hh)$/, [
    ['api', /^(?!\s*(?:static|#|\/\/|\*))[A-Za-z_][\w\s\*]*?\b([A-Za-z_]\w*)\s*\([^;{)]*\)\s*;/gm, ONE],
  ]],
  [/\.lua$/, [
    ['env', /os\.getenv\(\s*['"]([A-Z0-9_]+)/g, ONE],
    ['require', /\brequire\s*\(?\s*['"]([^'"]+)/g, ONE],
  ]],
  [/\.(sh|bash|zsh)$/, [
    ['http-out', /\b(?:curl|wget)\b[^\n]*?(https?:\/\/[^\s'"]+|\/[A-Za-z0-9_\-/.]+\b)/g, ONE],
  ]],
  [/\.sql$/, [
    ['table', /\bcreate\s+table\s+(?:if\s+not\s+exists\s+)?["`]?([\w.]+)/gi, ONE],
  ]],
  [/\.proto$/, [
    ['rpc', /\brpc\s+(\w+)\s*\(/g, ONE],
  ]],
];

function cmdInventory(project, cat) {
  const ignored = ignorer(cat && cat.overview && cat.overview.ignore);
  const files = git(project, ['ls-files']).split('\n').filter((f) => f && !ignored(f) && SOURCE_RE.test(f));
  const groups = {};
  for (const f of files) {
    const pats = [].concat.apply([], LANGS.filter(([re]) => re.test(f)).map(([, p]) => p));
    const dir = f.includes('/') ? path.dirname(f) : '(root)';
    const g = (groups[dir] = groups[dir] || { files: [], loc: 0, hits: {} });
    let text = '';
    try {
      text = fs.readFileSync(path.join(project, f), 'utf8');
    } catch (e) {
      continue;
    }
    const loc = text.split('\n').length;
    g.files.push(f + ' (' + loc + ')');
    g.loc += loc;
    for (const [kind, re, fmt] of pats) {
      re.lastIndex = 0;
      let m;
      while ((m = re.exec(text))) (g.hits[kind] = g.hits[kind] || new Set()).add(fmt(m));
    }
  }
  const covered = new Set();
  if (cat) cat.entries.forEach((e) => asList(e.files).forEach((x) => covered.add(x)));
  console.log('# Inventory — ' + path.resolve(project) + ' @ ' + git(project, ['rev-parse', '--short=10', 'HEAD']));
  console.log('# ' + files.length + ' source files; (N) = lines; * = already in a catalog entry\n');
  for (const dir of Object.keys(groups).sort()) {
    const g = groups[dir];
    console.log('## ' + dir + ' — ' + g.files.length + ' files, ' + g.loc + ' lines');
    for (const f of g.files) console.log('  ' + (covered.has(f.replace(/ \(\d+\)$/, '')) ? '* ' : '  ') + f);
    for (const kind of Object.keys(g.hits)) console.log('  ' + kind + ': ' + Array.from(g.hits[kind]).sort().join(' | '));
    console.log('');
  }
  return 0;
}

// ---------------------------------------------------------------- main

function main(argv) {
  const cmd = argv[0];
  let project = '.';
  let base = null;
  let siblings = null;
  const rest = [];
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === '--project') project = argv[++i];
    else if (argv[i] === '--base') base = argv[++i];
    else if (argv[i] === '--siblings') siblings = argv[++i];
    else rest.push(argv[i]);
  }
  if (!['index', 'affected', 'check', 'lookup', 'inventory', 'summary'].includes(cmd)) {
    console.error('usage: catalog.cjs <index|affected|check|lookup|inventory|summary> --project <dir> [--base <ref>] [--siblings <dir,...>] [terms...]');
    return 1;
  }
  // Runs from a SessionStart hook: never fails, never blocks the session.
  if (cmd === 'summary') {
    try {
      return cmdSummary(project);
    } catch (e) {
      return 0;
    }
  }
  if (git(project, ['rev-parse', '--git-dir'], { allowFail: true }) === null) {
    console.error(project + ' is not a git repository');
    return 1;
  }
  const cat = loadCatalog(project);
  if (cmd === 'inventory') return cmdInventory(project, cat);
  if (!cat) {
    console.error('no catalog at ' + path.join(project, CATALOG_DIR) + ' — bootstrap it with the catalog skill');
    return 3;
  }
  if (cmd === 'index') return cmdIndex(project, cat);
  if (cmd === 'affected') return cmdAffected(project, cat, base);
  if (cmd === 'check') return cmdCheck(project, cat, siblings);
  return cmdLookup(project, cat, rest);
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
}
