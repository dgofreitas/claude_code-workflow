---
name: playwright-debug
description: |
  Interactive GUI debugging playbook using the Playwright MCP server. Drives a
  real browser to reproduce, inspect, screenshot, and root-cause visual / DOM /
  interaction / hydration / network / console bugs in web frontends.

  **When to use Playwright MCP (debug):**
  - Bug is visual or interaction-driven (blank screen, broken layout, element not appearing, click does nothing, hydration mismatch, wrong render after state change)
  - Need to reproduce a reported UI bug against a running app URL
  - Need evidence (screenshot + console errors + network calls) for a Bug Fix Report
  - Need to verify a fix visually against the same reproduction path

  **When NOT to use this skill:**
  - Pure logic / backend bug with no UI surface → use bug-fixer-nodejs / bug-fixer-python / bug-fixer-c
  - Authoring/running E2E test suites → use the `test-execution` skill (`rtk playwright test` is for CI suites, NOT interactive debug)
  - Reading huge log files → see Anti-Patterns below

  **Tool source:** Microsoft `@playwright/mcp` (local server, registered in `.claude/settings.json` → `mcpServers.playwright`). Surfaced to agents as `browser_*` tools.
---

# Playwright MCP Debug Playbook

> **Purpose**: Give any agent a deterministic recipe for diagnosing GUI bugs with the Playwright MCP `browser_*` tools — reproduce, inspect, collect evidence, form a root-cause hypothesis, then hand off to a fix agent. This skill is the *capability*; agents (e.g. gui-debugger) consume it.

---

## 🛑 What NOT to Do (Anti-Patterns)

1. **NEVER use `rtk playwright test` for debug.** That wrapper is for CI test-suite output filtering (90%+ token savings on PASS logs). Interactive debug needs the MCP `browser_*` tools, not the test runner.
2. **NEVER read `~/.local/share/rtk/tee/*.log`** or any raw rtk tee file — the `read` tool hangs forever on these and freezes the pipeline (same rule as `test-execution`).
3. **NEVER navigate without `--isolated` semantics in a dirty profile.** The MCP server config uses `--isolated` for a clean profile per session; do not assume cookies/localStorage from a previous run persist. Set them explicitly via `browser_evaluate` / `browser_type` if reproduction depends on state.
4. **NEVER screenshot-blind.** A screenshot alone rarely shows the root cause. Always pair `browser_take_screenshot` with `browser_snapshot` (a11y/DOM tree) and `browser_console_messages` + `browser_network_requests`.
5. **NEVER skip reproduction.** RCA before fix is non-negotiable: reproduce the bug in the live browser first, then hypothesize. Do not patch from a stack trace alone when a UI surface is involved.
6. **NEVER run the dev server yourself.** Assume the app is already running at a known URL (passed in the delegation prompt). If no URL is given, ASK for it. Starting servers is the developer's job, not the debugger's.
7. **NEVER pipe MCP tool output** — these are structured tool results, not shell streams.

---

## ✅ Debug Workflow (deterministic)

### 1. Orient (cheap reads first)
- Confirm the **target URL** from the delegation prompt. If missing → ASK.
- Confirm the **reproduction steps** (or the symptom: blank screen, broken layout, click no-op, console error, 4xx/5xx, hydration warning).
- Note the **framework** (React/Next, Vue/Nuxt, Angular, plain) — affects where to look for the root cause (component state, hydration, lifecycle, CSS).

### 2. Reproduce
```
browser_navigate(url=<TARGET_URL>)
```
If reproduction needs interaction (login, click to open modal, fill form):
```
browser_click(element="button:has-text('Login')")   # or use the ref from snapshot
browser_type(element=<ref>, text="...")
```
Verify the symptom is present: `browser_take_screenshot` + `browser_snapshot`.

### 3. Collect Evidence (always these four together)
| Tool | What it gives you |
|------|-------------------|
| `browser_take_screenshot` | Visual state — what the user sees |
| `browser_snapshot` | Accessibility/DOM tree — element refs, hierarchy, missing nodes |
| `browser_console_messages` | JS errors, warnings, hydration mismatches, React/Vue dev warnings |
| `browser_network_requests` | 4xx/5xx, failed XHR/fetch, missing assets, CORS, slow calls |

Save evidence artifacts to `.claude/.debug/<STORY-XXX>/`:
- `01-repro-screenshot.png` (overwrite by re-saving with the MCP screenshot bytes)
- `01-console.txt`, `01-network.txt` (paste the relevant lines, not the whole dump)

### 4. Isolate & Hypothesize
- **Isolate**: binary-search the interaction chain. Disable one thing at a time (comment a component, remove a CSS rule, stub a fetch) to narrow the cause.
- **Hypothesize**: form ≤3 ranked hypotheses with evidence from step 3.
  - Example: console shows `Hydration failed` + element renders server-side but not client-side → hypothesis: SSR/CSR markup mismatch.
  - Example: network shows `404 /api/users` + UI shows empty list → hypothesis: API path drift, not a UI bug.

### 5. Verify
Confirm the top hypothesis with a **targeted** action:
- Click the suspect element and re-snapshot to confirm it changes (or doesn't).
- `browser_evaluate(expression="document.querySelector('...')")` to inspect computed style / DOM presence.
- Reproduce the exact bug once more after the suspected cause is temporarily removed — if the symptom vanishes, hypothesis confirmed.

### 6. Hand off to fix
Document: reproduction steps, evidence file paths, confirmed root cause, file:line if known. Then the fix agent (or you, if you are gui-debugger) applies a minimal fix and re-runs the reproduction path to confirm resolution.

---

## Heuristics — Which Tool by Symptom

| Symptom | First tool | Then |
|---------|------------|------|
| Blank screen / nothing renders | `browser_console_messages` | `browser_snapshot` (is root node present?) |
| Element not appearing | `browser_snapshot` | `browser_take_screenshot` + check CSS `display`/`visibility` via `browser_evaluate` |
| Layout broken / misaligned | `browser_take_screenshot` | `browser_snapshot` + `browser_evaluate` for computed styles / box model |
| Click does nothing | `browser_snapshot` (find ref) → `browser_click` | `browser_console_messages` for handler errors |
| Wrong data shown | `browser_network_requests` | Check the response payload, not the UI |
| Hydration mismatch | `browser_console_messages` | Compare `browser_snapshot` before/after hydration |
| 4xx / 5xx on action | `browser_network_requests` | Verify endpoint + payload vs backend contract |
| Flicker / race (intermittent) | `browser_wait_for(text=...)` then snapshot | Repeat 3-5x; intermittent = timing/async issue |
| Console error on load | `browser_console_messages` | Map error → source file via stack |

---

## Fallback Chain

1. **Playwright MCP unavailable** (server crash, `npx @playwright/mcp` missing, not registered in `.claude/settings.json`):
   - Fall back to CLI: `npx playwright open <URL>` (interactive inspector) — needs the project to have `@playwright/test` installed; use `browser_evaluate`-equivalent via DevTools console.
   - If `@playwright/test` is not installed → ASK the developer to start the app and reproduce manually, or delegate to external-scout for setup.
2. **MCP returns no snapshot / timeout on a heavy SPA**: wait, retry once with `browser_wait_for`. If still empty → the page is genuinely broken (root cause found: render never completes).
3. **App not running**: ASK for the URL or for the dev server to be started. Never start servers yourself.

> Do **not** fail the whole bug-fix task if the MCP is unavailable — capture whatever evidence you can (curl the URL, read the component source) and hand off with an explicit `[BLOCKED: playwright-mcp unavailable]` note so tech-lead can re-route or unblock.

---

## 🧭 Navigation Memory via Codegen (the "site map")

The Playwright MCP server is launched with `--codegen typescript --output-dir .claude/playwright-flows`. Every action the agent takes is recorded as Playwright TypeScript code into that project-local folder. This turns the folder into a **navigation map**: the first time the agent reaches a feature (login, dashboard, create-chart, deploy), it pays the trial-and-error cost; subsequent runs replay the recorded path instead of re-exploring.

### Load (before exploring)
When asked to reach a feature, BEFORE doing trial-and-error:
1. `ls .claude/playwright-flows/` — look for a matching `<flow>.spec.ts` (e.g. `login.spec.ts`, `create-chart.spec.ts`).
2. If a candidate exists, **read it** and execute the recorded Playwright steps (`browser_navigate` / `browser_click` / `browser_type` with the stable selectors from the file). Use the recorded locators — they survived trial-and-error once already.
3. Verify each step against the live `browser_snapshot` (URL changed, expected element present, expected text visible).
4. If every checkpoint passes → feature reached, zero exploration. Done.
5. If a checkpoint fails (UI changed, selector drifted) → fall back to exploration for the failing step only, then **overwrite** the `.spec.ts` with the corrected path (see Save).

If NO matching file → explore normally (workflow above), then Save.

### Save (after a successful first run or after correcting drift)
Once a flow completes with the expected outcome:
1. Confirm the codegen output landed in `.claude/playwright-flows/`.
2. **Rename** the auto-generated file (timestamped) to a stable `<flow>.spec.ts` slug so it is findable next time. Pick the slug from the feature, not the date.
3. The recorded file may contain noise from failed attempts during trial-and-error — that is acceptable. The next run validates each step against the live snapshot; anything that no longer matches is simply dropped on the fly. Optionally, on a clean re-run with no drift, ask the agent to rewrite the file with only the verified path (no manual format required — it stays Playwright TS).

### Naming convention
- One file per flow: `login.spec.ts`, `deploy-staging.spec.ts`, `create-chart.spec.ts`, `insert-action.spec.ts`.
- Slug = feature verb-noun, kebab-case, no timestamps in the filename.
- Auth flows: prefer pairing with `browser_storage_state` saved to `.claude/playwright-flows/.session/<flow>.json` (gitignored) so login is skipped entirely on replays — codegen records the steps, storage state skips them.

### Hard rules
- **Never** store ephemeral refs (`ref=e12`) — codegen already emits stable `getByRole` / `getByLabel` / `getByTestId` locators; keep those.
- **Never** commit `.claude/playwright-flows/.session/` (contains cookies). Add to `.gitignore`.
- If the MCP is unavailable, codegen does not run — fall back to manual exploration and write nothing.
- The map is **per-project**: `.claude/playwright-flows/` lives in the target project, not in this workflow repo.

---

## Golden Rules

1. **Reproduce before you fix** — no fix from a trace alone when a UI surface exists.
2. **Four tools together** — screenshot + snapshot + console + network. Never just one.
3. **Save evidence** to `.claude/.debug/<STORY>/` — feeds the Bug Fix Report.
4. **Isolate by removal**, not by adding more code. Confirm hypothesis before patching.
5. **No `rtk` here** — this skill uses MCP tools, not the RTK test wrapper.
6. **Never read rtk/tee logs** — same hard rule as `test-execution`.
