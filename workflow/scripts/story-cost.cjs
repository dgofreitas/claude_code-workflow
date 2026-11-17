#!/usr/bin/env node
'use strict';

// story-cost.cjs — what one story cost, per phase, per agent and per run, read from
// Claude Code's own session logs. Writes <id>-cost-report.md next to the story and,
// with --commit, commits that one file. Run by the tech-lead skill right before the MR.
//
//   node .claude/scripts/story-cost.cjs <STORY-ID> --tree "$P" [--commit]
//   node .claude/scripts/story-cost.cjs <STORY-ID> --print     # stdout only, writes nothing
//
// Never blocks delivery: every failure prints `story-cost: aviso: …` and exits 0.
//
// Measurement traps (same as the repo's agent-cost-report.py):
//   1. One API request is logged as ~2 lines with the SAME usage object, and the first
//      line's output_tokens is partial. Keep the MAX per message.id, never sum lines.
//   2. PRICES drifts. A model missing from it is reported in tokens with no $, never at
//      a guessed price. Source: https://platform.claude.com/docs/en/about-claude/pricing
//
// A run belongs to the story whose id is the FIRST id in its delegation prompt: in-story
// delegations open with their own story and may cite others later. Planning runs that
// cover many stories (product-manager) therefore land on one of them — read the
// Planejamento line with that in mind. In an umbrella the same id exists in several
// sub-projects, so the delegation must also name this session's sub-project path.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

// (input, output, 5m cache write, 1h cache write, cache read) in $/Mtok.
// Same table as the repo's .claude/scripts/agent-cost-report.py — change both together.
const PRICES = {
  'claude-opus-5-5': [4, 20, 5, 8, 0.20],
  'claude-opus-5': [5, 25, 6.25, 10, 0.50],
  'claude-opus-4-5': [5, 25, 6.25, 10, 0.50],
  'claude-sonnet-5-5': [2, 10, 2.50, 4, 0.10],
  'claude-sonnet-5': [2, 10, 2.50, 4, 0.20],
  'claude-sonnet-4-6': [3, 15, 3.75, 6, 0.30],
  'claude-haiku-4-5': [1, 5, 1.25, 2, 0.10],
  'claude-haiku-4-5-20251001': [1, 5, 1.25, 2, 0.10],
};
const US_GEO = 1.1;

const PHASES = [
  [/^(architect|code-analyzer|ux-designer|product-manager|product-owner|system-architect)$/, 'Planejamento'],
  [/^(context-scout|external-scout|Explore)$/, 'Contexto'],
  [/^(backend-developer|frontend-developer|shell-developer|devops-specialist|build-agent)/, 'Implementação'],
  [/^test-engineer/, 'Testes'],
  [/^qa-analyst/, 'QA'],
  [/^(code-reviewer|comment-sanitizer)/, 'Review'],
  [/^bug-fixer/, 'Correção'],
  [/^catalog-/, 'Catálogo'],
  [/^merge-request-creator$/, 'MR'],
];
const MAIN = 'sessão principal';

function warn(msg) {
  console.log('story-cost: aviso: ' + msg);
}

function phaseOf(agent) {
  if (agent === MAIN) return 'Orquestração';
  for (const [re, name] of PHASES) if (re.test(agent)) return name;
  return 'Outros';
}

function args(argv) {
  const out = { id: null, tree: '.', commit: false, print: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--tree') out.tree = argv[++i];
    else if (a === '--commit') out.commit = true;
    else if (a === '--print') out.print = true;
    else if (!out.id) out.id = a;
  }
  return out;
}

function projectsRoot() {
  return path.join(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude'), 'projects');
}

function logDir(sid) {
  const root = projectsRoot();
  if (sid) {
    for (const d of safeReaddir(root)) {
      if (fs.existsSync(path.join(root, d, sid + '.jsonl'))) return path.join(root, d);
    }
  }
  return path.join(root, process.cwd().replace(/[^A-Za-z0-9]/g, '-'));
}

function safeReaddir(d) {
  try {
    return fs.readdirSync(d);
  } catch {
    return [];
  }
}

function walk(dir, out) {
  for (const name of safeReaddir(dir)) {
    const p = path.join(dir, name);
    let st;
    try {
      st = fs.statSync(p);
    } catch {
      continue;
    }
    if (st.isDirectory()) walk(p, out);
    else if (/^agent-.*\.jsonl$/.test(name)) out.push(p);
  }
  return out;
}

// One log file -> { agent, deleg, session, requests[] } with requests deduped per message.id.
function scan(file, windows) {
  const res = { agent: null, deleg: null, session: null, requests: [] };
  const msgs = new Map();
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    return res;
  }
  for (const line of text.split('\n')) {
    if (!line) continue;
    let e;
    try {
      e = JSON.parse(line);
    } catch {
      continue;
    }
    if (!res.agent && e.attributionAgent) res.agent = e.attributionAgent;
    if (!res.session && e.sessionId) res.session = e.sessionId;
    const m = e.message || {};
    if (res.deleg === null && m.role === 'user' && typeof m.content === 'string') res.deleg = m.content;
    const u = m.usage;
    if (!u || m.role !== 'assistant') continue;
    const ts = Date.parse(e.timestamp || '') || 0;
    if (windows && !windows.some(([lo, hi]) => ts >= lo && ts <= hi)) continue;
    const cw = u.cache_creation_input_tokens || 0;
    const cw1h = (u.cache_creation || {}).ephemeral_1h_input_tokens || 0;
    const cur = {
      model: m.model || '?', ts,
      inp: u.input_tokens || 0, cw5: cw - cw1h, cw1h,
      cr: u.cache_read_input_tokens || 0, out: u.output_tokens || 0,
      us: u.inference_geo === 'us',
    };
    const prev = msgs.get(m.id);
    if (!prev || cur.out > prev.out) msgs.set(m.id, cur);
  }
  if (!res.agent) {
    try {
      res.agent = JSON.parse(fs.readFileSync(file.replace(/\.jsonl$/, '.meta.json'), 'utf8')).agentType || null;
    } catch {
      // older layouts have no meta file
    }
  }
  res.requests = [...msgs.values()]
    .filter((r) => r.inp + r.cw5 + r.cw1h + r.cr + r.out > 0)
    .sort((a, b) => a.ts - b.ts);
  return res;
}

function measure(requests, unknown) {
  let tokens = 0, out = 0, cost = 0, priced = true, peak = 0;
  const models = new Map();
  for (const r of requests) {
    const ctx = r.inp + r.cw5 + r.cw1h + r.cr;
    tokens += ctx + r.out;
    out += r.out;
    peak = Math.max(peak, ctx);
    models.set(r.model, (models.get(r.model) || 0) + 1);
    const p = PRICES[r.model];
    if (!p) {
      unknown.add(r.model);
      priced = false;
      continue;
    }
    const c = (r.inp * p[0] + r.cw5 * p[2] + r.cw1h * p[3] + r.cr * p[4] + r.out * p[1]) / 1e6;
    cost += c * (r.us ? US_GEO : 1);
  }
  const model = [...models.entries()].sort((a, b) => b[1] - a[1])
    .map(([m]) => m.replace(/^claude-/, '')).join('+');
  const first = requests[0];
  return {
    reqs: requests.length, tokens, out, cost, priced, peak, model,
    baseline: first ? first.inp + first.cw5 + first.cw1h + first.cr : 0,
    start: first ? first.ts : 0,
    end: requests.length ? requests[requests.length - 1].ts : 0,
  };
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function subProjectFilter(sid, tree) {
  if (!sid) return null;
  let ap = '';
  try {
    ap = fs.readFileSync(path.join('.claude', '.state', sid, 'active-project'), 'utf8').trim();
  } catch {
    return null;
  }
  if (!ap || ap === '.') return null;
  // Delegations name the tree as `api/...`, `Repo api.` or a worktree `.../api-STORY-022`.
  const names = [ap, path.basename(path.resolve(tree))].map(escapeRe);
  return new RegExp(`(^|[\\s"'\`(:=/])(${names.join('|')})([/\\s.,;:-]|$)`, 'm');
}

function fmtTok(n) {
  if (n >= 1e6) return (n / 1e6).toFixed(2) + 'M';
  if (n >= 1e3) return (n / 1e3).toFixed(0) + 'k';
  return String(n);
}

function fmtCost(m) {
  return m.priced ? '$' + m.cost.toFixed(2) : '$' + m.cost.toFixed(2) + '+?';
}

function pct(part, total) {
  return total ? (100 * part / total).toFixed(0) + '%' : '-';
}

function hhmm(ts) {
  const d = new Date(ts);
  return d.toISOString().slice(5, 16).replace('T', ' ');
}

// Cycle 1 is the first pass. An implementation or fix run that starts after QA or review
// already ran in the current cycle opens the next one: that is the rework loop.
function assignCycles(runs) {
  let cycle = 1, judged = false;
  for (const r of runs) {
    if (r.agent === MAIN) continue;
    const ph = phaseOf(r.agent);
    if ((ph === 'Implementação' || ph === 'Correção') && judged) {
      cycle++;
      judged = false;
    }
    if (ph === 'QA' || ph === 'Review') judged = true;
    r.cycle = cycle;
    r.rework = cycle > 1 || ph === 'Correção';
  }
  return cycle;
}

function sum(runs) {
  const s = { runs: runs.length, reqs: 0, tokens: 0, out: 0, cost: 0, priced: true };
  for (const r of runs) {
    s.reqs += r.reqs;
    s.tokens += r.tokens;
    s.out += r.out;
    s.cost += r.cost;
    s.priced = s.priced && r.priced;
  }
  return s;
}

function group(runs, key) {
  const g = new Map();
  for (const r of runs) {
    const k = key(r);
    if (!g.has(k)) g.set(k, []);
    g.get(k).push(r);
  }
  return [...g.entries()].map(([k, rs]) => [k, sum(rs), rs]).sort((a, b) => b[1].tokens - a[1].tokens);
}

function frontmatter(id, tree, created) {
  const fm = { development: null, epic: null, title: null };
  const story = path.join(tree, 'artifacts', 'stories', id + '.md');
  try {
    const head = fs.readFileSync(story, 'utf8').split(/^---$/m)[1] || '';
    for (const k of Object.keys(fm)) {
      const m = head.match(new RegExp(`^${k}:\\s*(.+)$`, 'm'));
      if (m) fm[k] = m[1].trim();
    }
  } catch {
    // hotfixes have no story file; identity still comes from the id
  }
  const lines = ['---', `id: ${id}`, 'type: cost-report', `title: Custo — ${fm.title || id}`];
  if (fm.development) lines.push(`development: ${fm.development}`);
  if (fm.epic) lines.push(`epic: ${fm.epic}`);
  lines.push('generated_by: story-cost', 'schema_version: 1', `created: ${created}`, '---');
  return lines.join('\n');
}

function report(id, runs, cycles, unknown) {
  const total = sum(runs);
  const rework = sum(runs.filter((r) => r.rework));
  const lines = [];
  lines.push(`# Custo — ${id}`, '');
  lines.push('> Gerado por `.claude/scripts/story-cost.cjs` a partir dos logs locais do Claude Code,',
    '> no momento do MR: não inclui a criação do MR nem o merge. Tokens = contexto lido',
    '> (input + cache) + output, por request. "+?" = há modelo sem preço na tabela.', '');
  lines.push('<!-- mr:begin -->', '## Resumo', '');
  lines.push('| Tokens | Custo | Execuções | Requests | Ciclos | Retrabalho |');
  lines.push('|---|---|---|---|---|---|');
  lines.push(`| ${fmtTok(total.tokens)} | ${fmtCost(total)} | ${total.runs} | ${total.reqs} | ${cycles} | `
    + `${fmtTok(rework.tokens)} (${pct(rework.tokens, total.tokens)}) |`);
  lines.push('', '### Por fase', '');
  lines.push('| Fase | Execuções | Requests | Tokens | % | Custo |', '|---|---|---|---|---|---|');
  for (const [ph, s] of group(runs, (r) => phaseOf(r.agent))) {
    lines.push(`| ${ph} | ${s.runs} | ${s.reqs} | ${fmtTok(s.tokens)} | ${pct(s.tokens, total.tokens)} | ${fmtCost(s)} |`);
  }
  lines.push('', '### Por agente e modelo', '');
  lines.push('| Agente | Modelo | Execuções | Requests | Tokens | % | Custo | Ciclos |', '|---|---|---|---|---|---|---|---|');
  for (const [, s, rs] of group(runs, (r) => r.agent + '\0' + r.model)) {
    const cyc = [...new Set(rs.map((r) => r.cycle).filter(Boolean))].join(',') || '-';
    lines.push(`| ${rs[0].agent} | ${rs[0].model} | ${s.runs} | ${s.reqs} | ${fmtTok(s.tokens)} | `
      + `${pct(s.tokens, total.tokens)} | ${fmtCost(s)} | ${cyc} |`);
  }
  lines.push('<!-- mr:end -->', '', '## Execuções', '');
  lines.push('Ctx inicial = contexto do 1º request (o que o agente recebeu ao ser chamado). '
    + 'Ctx pico = maior contexto da execução; a diferença é o que ele acumulou trabalhando.', '');
  lines.push('| # | Início (UTC) | Agente | Modelo | Ciclo | Requests | Ctx inicial | Ctx pico | Tokens | Custo |');
  lines.push('|---|---|---|---|---|---|---|---|---|---|');
  runs.forEach((r, i) => {
    const cyc = r.agent === MAIN ? '-' : (r.rework ? `${r.cycle} ↻` : String(r.cycle));
    lines.push(`| ${i + 1} | ${hhmm(r.start)} | ${r.agent} | ${r.model} | ${cyc} | ${r.reqs} | `
      + `${fmtTok(r.baseline)} | ${fmtTok(r.peak)} | ${fmtTok(r.tokens)} | ${fmtCost(r)} |`);
  });
  if (unknown.size) lines.push('', `Modelos sem preço na tabela: ${[...unknown].join(', ')}.`);
  return lines.join('\n') + '\n';
}

function git(tree, argv) {
  return execFileSync('git', ['-C', tree, ...argv], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function commit(tree, file, id) {
  const rel = path.relative(tree, file);
  let tracked = true;
  try {
    git(tree, ['ls-files', '--error-unmatch', '--', rel]);
  } catch {
    tracked = false;
  }
  try {
    git(tree, ['add', '--', rel]);
    if (!git(tree, ['diff', '--cached', '--name-only', '--', rel]).trim()) return 'sem mudança';
    git(tree, ['commit', '-m', `docs(cost): ${id}`, '--', rel]);
    return 'commitado';
  } catch (err) {
    // A file left dirty would fail the MR's clean-tree check: telemetry must not block delivery.
    try {
      git(tree, ['reset', '-q', '--', rel]);
      if (tracked) git(tree, ['checkout', '--', rel]);
      else fs.unlinkSync(file);
    } catch {
      // best effort
    }
    warn(`commit falhou, relatório descartado: ${String(err.stderr || err.message).trim().split('\n')[0]}`);
    return null;
  }
}

function main() {
  const a = args(process.argv.slice(2));
  if (!a.id) {
    console.log('uso: story-cost.cjs <STORY-ID> --tree "$P" [--commit] | --print');
    return;
  }
  const prefix = (a.id.match(/^[A-Z]+-\d+(?:-\d+)*/) || [])[0];
  if (!prefix) return warn(`id sem forma <PREFIXO>-<n>: ${a.id}`);
  const letters = prefix.split('-')[0];
  const idRe = new RegExp(`\\b${letters}-\\d+(?:-\\d+)*`);
  const sid = process.env.CLAUDE_CODE_SESSION_ID || '';
  const dir = logDir(sid);
  const sub = subProjectFilter(sid, a.tree);
  const unknown = new Set();

  const runs = [];
  for (const file of walk(dir, [])) {
    const s = scan(file);
    const first = (s.deleg || '').match(idRe);
    if (!first || first[0] !== prefix) continue;
    if (sub && !sub.test(s.deleg)) continue;
    if (!s.requests.length) continue;
    runs.push({ agent: s.agent || '?', session: s.session, ...measure(s.requests, unknown) });
  }
  if (!runs.length) return warn(`nenhuma execução de ${prefix} nos logs de ${dir}`);

  // The main session (Master + tech-lead skill) has no story id of its own: charge it the
  // stretches of each session where this story's runs follow one another. A pause longer
  // than GAP splits the stretch, so a session resumed next day is not billed for the night.
  const GAP = 30 * 60 * 1000;
  const bySession = group(runs.filter((r) => r.session), (r) => r.session);
  for (const [session, , rs] of bySession) {
    const wins = [];
    for (const r of [...rs].sort((x, y) => x.start - y.start)) {
      const last = wins[wins.length - 1];
      if (last && r.start - last[1] <= GAP) last[1] = Math.max(last[1], r.end);
      else wins.push([r.start, r.end]);
    }
    const s = scan(path.join(dir, session + '.jsonl'), wins);
    if (s.requests.length) runs.push({ agent: MAIN, session, ...measure(s.requests, unknown) });
  }
  runs.sort((x, y) => x.start - y.start);
  const cycles = assignCycles(runs);
  const body = report(a.id, runs, cycles, unknown);

  if (a.print) return void process.stdout.write(body);
  const file = path.join(a.tree, 'artifacts', 'stories', a.id + '-cost-report.md');
  let created = new Date().toISOString().slice(0, 10);
  try {
    created = (fs.readFileSync(file, 'utf8').match(/^created:\s*(\S+)/m) || [])[1] || created;
  } catch {
    // first report for this story
  }
  try {
    fs.writeFileSync(file, frontmatter(a.id, a.tree, created) + '\n\n' + body);
  } catch (err) {
    return warn(`não consegui escrever ${file}: ${err.message}`);
  }
  const total = sum(runs);
  const state = a.commit ? commit(a.tree, file, a.id) : 'escrito';
  if (state) console.log(`story-cost: ${file} (${state}) — ${fmtTok(total.tokens)} tokens, ${fmtCost(total)}`);
}

try {
  main();
} catch (err) {
  warn(err.message);
}
