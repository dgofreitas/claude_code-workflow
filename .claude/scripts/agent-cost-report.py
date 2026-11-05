#!/usr/bin/env python3
"""agent-cost-report.py — where the token budget actually goes, per subagent.

Reads Claude Code's own session logs (~/.claude/projects/**/agent-*.jsonl) and
attributes cost to each subagent. Read-only: never writes, never calls the API.

This is tooling for improving the workflow, NOT part of the workflow — it lives in this
repo's own .claude/, never in claude/ (the payload installed into other projects). It
reads the GLOBAL project log directory, so running it from here already covers every
project on the machine; installing a copy anywhere would measure the same data twice.

    python3 .claude/scripts/agent-cost-report.py                 # all history
    python3 .claude/scripts/agent-cost-report.py --hours 24      # last 24h
    python3 .claude/scripts/agent-cost-report.py --agent test-engineer --runs
    python3 .claude/scripts/agent-cost-report.py --agent test-engineer --files
    python3 .claude/scripts/agent-cost-report.py --agent architect --runs --match 'vislic|serverLic'

Two measurement traps this script exists to avoid:

  1. A single API request is logged as ~2 lines, one per content block, each
     carrying the SAME usage object. Counting lines double-counts requests, and
     summing output_tokens across them is wrong in the other direction: the
     first chunk's value is partial, so only the MAX per message.id is the real
     total. Thinking is ~79% of output and lives only in that delta.

  2. PRICES drifts. A model missing from it bills as Sonnet without a word, and
     until 2026-11-03 the table also had Opus 5 at 3x and Sonnet 5 at 1.5x the
     real price, plus a 2x long-context tier that no 4.6+ model has. Every
     model in the logs must be in PRICES — main() refuses to report otherwise.
     Source: https://platform.claude.com/docs/en/about-claude/pricing

The headline finding it was written for: cost grows with the SQUARE of session
length, because every request re-reads the whole accumulated context. The
predictor is how many files a delegation carries, not which domains it spans.
"""

import argparse
import glob
import json
import os
import re
import time
from collections import defaultdict

# (input, output, 5m cache write, 1h cache write, cache read) in $/Mtok.
# No long-context tier: 4.6+ models bill the whole 1M window at these rates.
PRICES = {
    'claude-opus-5-5': (4, 20, 5, 8, 0.20),
    'claude-opus-5': (5, 25, 6.25, 10, 0.50),
    'claude-opus-4-5': (5, 25, 6.25, 10, 0.50),
    'claude-sonnet-5-5': (2, 10, 2.50, 4, 0.10),
    'claude-sonnet-5': (2, 10, 2.50, 4, 0.20),
    'claude-sonnet-4-6': (3, 15, 3.75, 6, 0.30),
    'claude-haiku-4-5': (1, 5, 1.25, 2, 0.10),
    'claude-haiku-4-5-20251001': (1, 5, 1.25, 2, 0.10),
}
US_GEO = 1.1  # inference_geo "us" on 4.6+ models
LONG_CONTEXT = 200_000  # only reported (the >200k column), no longer priced
SOURCE_EXT = r'(?:js|jsx|ts|tsx|mjs|cjs|py|c|h|cpp|hpp|vue|go|rs|sh)'


def scan(path):
    """One log file -> (agent, delegation prompt, [(model, usage)] deduped)."""
    agent = deleg = None
    msgs = {}
    with open(path, encoding='utf-8', errors='ignore') as fh:
        for line in fh:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if agent is None:
                agent = entry.get('attributionAgent')
            msg = entry.get('message') or {}
            if deleg is None and msg.get('role') == 'user' and isinstance(msg.get('content'), str):
                deleg = msg['content']
            usage = msg.get('usage')
            if not (usage and msg.get('role') == 'assistant'):
                continue
            mid = msg.get('id')
            cw = usage.get('cache_creation_input_tokens', 0)
            cw1h = (usage.get('cache_creation') or {}).get('ephemeral_1h_input_tokens', 0)
            cur = (
                msg.get('model', '?'),
                usage.get('input_tokens', 0),
                cw - cw1h,
                cw1h,
                usage.get('cache_read_input_tokens', 0),
                usage.get('output_tokens', 0),
                usage.get('inference_geo') == 'us',
            )
            # Trap 1: keep the highest output_tokens seen for this message.
            if mid not in msgs or cur[5] > msgs[mid][5]:
                msgs[mid] = cur
    return agent, deleg or '', list(msgs.values())


def price(requests):
    """Dollar cost of one run."""
    total = 0.0
    peak = 0
    over = 0
    for model, inp, cw5, cw1h, cr, out, us in requests:
        p_in, p_out, p_w5, p_w1h, p_read = PRICES[model]
        ctx = inp + cw5 + cw1h + cr
        over += ctx > LONG_CONTEXT
        peak = max(peak, ctx)
        cost = (inp * p_in + cw5 * p_w5 + cw1h * p_w1h + cr * p_read + out * p_out) / 1e6
        total += cost * (US_GEO if us else 1)
    return total, peak, over


def collect(hours, match=None, project=None):
    """match: regex over the delegation prompt — the log path names only the session's
    project, so in an umbrella the sub-project shows up in the prompt, not the path."""
    cutoff = time.time() - hours * 3600 if hours else 0
    root = os.path.expanduser('~/.claude/projects')
    runs = []
    unknown = defaultdict(int)
    foreign = defaultdict(int)
    for path in glob.glob(root + '/**/agent-*.jsonl', recursive=True):
        if os.path.getmtime(path) < cutoff:
            continue
        agent, deleg, requests = scan(path)
        # The log path names the session's project dir (e.g. -home-...-moneyTrackr-V2).
        if project and not re.search(project, path):
            continue
        if match and not re.search(match, deleg):
            continue
        # Zero-token entries (e.g. `<synthetic>`) cost nothing whatever their model.
        requests = [r for r in requests if any(r[1:6])]
        # Runs on other providers (model-profiles/ollama.json) have no Anthropic price.
        other = {r[0] for r in requests if not r[0].startswith('claude-')}
        if other:
            for m in other:
                foreign[m] += 1
            continue
        for r in requests:
            if r[0] not in PRICES:
                unknown[r[0]] += 1
        if not requests or unknown:
            continue
        cost, peak, over = price(requests)
        files = len(set(re.findall(r'[\w./-]+\.' + SOURCE_EXT + r'\b', deleg)))
        runs.append({
            'agent': agent or '?', 'cost': cost, 'reqs': len(requests),
            'peak': peak, 'over': over, 'files': files,
            'baseline': sum(requests[0][1:5]), 'path': path,
        })
    if unknown:
        raise SystemExit('models missing from PRICES (requests): '
                         + ', '.join(f'{m} ({n})' for m, n in sorted(unknown.items())))
    if foreign:
        print('excluded, non-Anthropic model (runs): '
              + ', '.join(f'{m} ({n})' for m, n in sorted(foreign.items())) + '\n')
    return runs


def per_agent(runs):
    agg = defaultdict(lambda: {'runs': 0, 'reqs': 0, 'cost': 0.0, 'peak': 0, 'over': 0, 'worst': 0.0})
    for r in runs:
        a = agg[r['agent']]
        a['runs'] += 1
        a['reqs'] += r['reqs']
        a['cost'] += r['cost']
        a['over'] += r['over']
        a['peak'] = max(a['peak'], r['peak'])
        a['worst'] = max(a['worst'], r['cost'])
    total = sum(v['cost'] for v in agg.values()) or 1
    print(f"{'agent':26} {'runs':>5} {'reqs':>6} {'cost$':>9} {'%':>6} "
          f"{'avg$':>7} {'worst$':>8} {'peak ctx':>10} {'>200k':>6}")
    for name, v in sorted(agg.items(), key=lambda kv: -kv[1]['cost']):
        print(f"{name:26} {v['runs']:5d} {v['reqs']:6d} {v['cost']:9.2f} "
              f"{100 * v['cost'] / total:5.1f}% {v['cost'] / v['runs']:7.2f} "
              f"{v['worst']:8.2f} {v['peak']:10,} {v['over']:6d}")
    print(f"\n{'TOTAL':26} {len(runs):5d} {sum(r['reqs'] for r in runs):6d} {total:9.2f}")


def per_run(runs, agent):
    sel = sorted((r for r in runs if r['agent'] == agent), key=lambda r: -r['cost'])
    if not sel:
        print(f'no runs for {agent}')
        return
    costs = [r['cost'] for r in sel]
    total = sum(costs)
    print(f"{agent}: {len(sel)} runs, ${total:.2f}")
    print(f"  median ${costs[len(costs) // 2]:.2f} | mean ${total / len(costs):.2f} | max ${costs[0]:.2f}")
    # Requests, not dollars, compare runs across a model change: price moved, the work did not.
    reqs = sorted(r['reqs'] for r in sel)
    peaks = sorted(r['peak'] for r in sel)
    print(f"  median {reqs[len(reqs) // 2]} reqs/run | median peak ctx {peaks[len(peaks) // 2]:,}")
    for k in (5, 10, 20):
        if k < len(costs):
            print(f"  top {k:2d} runs = ${sum(costs[:k]):7.2f} ({100 * sum(costs[:k]) / total:4.1f}% of the agent)")
    print(f"\n  {'cost$':>8} {'reqs':>5} {'files':>6} {'baseline':>9} {'peak ctx':>10}")
    for r in sel[:12]:
        print(f"  {r['cost']:8.2f} {r['reqs']:5d} {r['files']:6d} {r['baseline']:9,} {r['peak']:10,}")


def per_files(runs, agent):
    """Files-per-delegation is the cost predictor; domains are not."""
    sel = [r for r in runs if r['agent'] == agent and r['files']]
    if not sel:
        print(f'no runs with parseable file lists for {agent}')
        return
    print(f"{agent}: {len(sel)} runs with a parseable file list\n")
    print(f"  {'files in delegation':22} {'runs':>5} {'avg $':>8} {'avg reqs':>9}")
    bands = [(0, 2, '0-2'), (3, 4, '3-4'), (5, 8, '5-8'), (9, 10 ** 6, '9+')]
    for lo, hi, label in bands:
        band = [r for r in sel if lo <= r['files'] <= hi]
        if not band:
            continue
        print(f"  {label + ' files':22} {len(band):5d} "
              f"{sum(r['cost'] for r in band) / len(band):8.2f} "
              f"{sum(r['reqs'] for r in band) / len(band):9.0f}")
    big = [r for r in sel if r['files'] >= 5]
    if big:
        tot = sum(r['cost'] for r in sel)
        print(f"\n  5+ files: {len(big)}/{len(sel)} of runs but "
              f"${sum(r['cost'] for r in big):.0f} of ${tot:.0f} = "
              f"{100 * sum(r['cost'] for r in big) / tot:.0f}% of the cost")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--hours', type=float, help='only logs touched in the last N hours')
    ap.add_argument('--agent', help='drill into one agent')
    ap.add_argument('--runs', action='store_true', help='with --agent: per-run distribution')
    ap.add_argument('--files', action='store_true', help='with --agent: cost by files per delegation')
    ap.add_argument('--match', help='only runs whose delegation prompt matches this regex')
    ap.add_argument('--project', help='only runs whose log path (the session\'s project dir) matches this regex')
    args = ap.parse_args()

    runs = collect(args.hours, args.match, args.project)
    if not runs:
        print('no subagent logs found under ~/.claude/projects')
        return
    if args.agent and args.files:
        per_files(runs, args.agent)
    elif args.agent:
        per_run(runs, args.agent)
    else:
        per_agent(runs)


if __name__ == '__main__':
    main()
