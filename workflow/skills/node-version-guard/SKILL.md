---
name: node-version-guard
description: >
  Ensures the correct Node.js version is active via nvm BEFORE running any
  npm/node command (install, test, run, build, exec, ci). Prevents the
  recurring bug of testing or installing with the wrong Node version, which
  produces misleading failures (peer dep errors, EBADENGINE warnings, runtime
  crashes, lockfile drift). Trigger: any time the agent is about to run
  `npm`, `npx`, `node`, `yarn`, `pnpm`, `vitest`, `jest`, `tsc`, or any script
  from `package.json` against a project that declares a Node version
  requirement. Also auto-triggers when the user says "run tests", "install
  deps", "build the project", "use nvm", "wrong node version", "EBADENGINE",
  "ERESOLVE", or mentions node version mismatch.
---

# Node Version Guard

Run this preflight BEFORE any `npm` / `npx` / `node` / `yarn` / `pnpm` / `vitest`
/ `jest` / `tsc` command in a project. Wrong Node version is a silent killer:
install succeeds with warnings, tests fail with cryptic errors, lockfile drifts.

## Preflight Checklist (do all 4, in order)

### 1. Detect the required Node version

Look in this order; first match wins.

| Source | Where | Format |
|--------|-------|--------|
| `.nvmrc` | project root | bare version: `20.20.2` or `lts/iron` |
| `.node-version` | project root | bare version: `20.20.2` |
| `package.json` → `engines.node` | project root or subdir | semver range: `>=20.0.0` |
| `Dockerfile` → `FROM node:XX-...` | any service Dockerfile | major version: `20` |

If **none** of the above exist, the project has no version requirement — run
the command with whatever Node is active, but mention this to the user.

If multiple sources conflict (e.g., `.nvmrc` says 20 but `engines.node` says
`>=22`), prefer `.nvmrc` (it is the explicit, project-pinned version) and flag
the discrepancy to the user.

### 2. Check the active Node version

```sh
node --version
```

If it matches the requirement (semver satisfies), **stop here** — proceed with
the command. No need to switch.

### 3. If mismatched, switch via nvm

nvm must be sourced before use. Use the literal path (no shell substitution —
the terminal tool blocks `$VAR` expansion):

```sh
. /home/<user>/.nvm/nvm.sh && nvm use <version>
```

Find the user's home by reading the project root path you already have. Do
NOT use `$HOME` or `~` in the command — resolve it to the literal path first.

If `nvm use <version>` fails with "N/A: version not installed", list what is
installed and pick the closest compatible one:

```sh
. /home/<user>/.nvm/nvm.sh && nvm ls | grep -v default
```

Pick the **lowest installed version that satisfies the requirement** (e.g.,
requirement `>=20.0.0`, installed `v18.20.8 v20.20.2 v22.22.2` → use `20.20.2`,
not `22.22.2`, for parity with the project's intent).

If **no installed version satisfies the requirement**, do NOT proceed with the
npm command. Tell the user:

> Project requires Node `<requirement>`, but only `<installed>` are installed
> via nvm. Install with: `nvm install <lowest-satisfying>` (e.g.,
> `nvm install 20`). Aborting to avoid running with the wrong version.

### 4. Verify the switch actually took effect

After `nvm use`, re-check:

```sh
node --version && npm --version
```

Only then proceed with the original npm/node command.

## Critical Rules

- **Every** npm/yarn/pnpm command in a session must be preceded by this
  preflight — even if you already ran it earlier in the same session. A
  subshell spawned by the terminal tool does NOT inherit nvm state from a
  previous invocation. Each `terminal` call starts a fresh shell, so you must
  re-source nvm and re-`nvm use` in the SAME command line as the npm command:

  ```sh
  . /home/<user>/.nvm/nvm.sh && nvm use 20.20.2 && npm install
  ```

  Never split `nvm use` and `npm install` across two `terminal` calls — the
  second call will not have nvm active.

- **Never** use `nvm alias default` — that changes the user's global default.
  Use `nvm use`, which is per-shell.

- **Never** use `sudo npm` — that bypasses nvm and uses the system Node.

- If the user explicitly says "use the system node" or "ignore version", obey
  them and skip the preflight. Note the risk once and proceed.

## Lockfile Regeneration

If you change `package.json` (add/remove/upgrade a dependency), the lockfile
must be regenerated with the **correct** Node version active:

```sh
. /home/<user>/.nvm/nvm.sh && nvm use <version> && rm -f package-lock.json && npm install
```

Regenerating with the wrong Node version produces a lockfile that fails to
install on the right version (or vice versa) — this is the original sin that
this skill exists to prevent.

## When to Skip

- One-off `node -e "..."` inspecting a JSON file → not a project command.
- Running a script that has nothing to do with the project's `package.json`
  (e.g., `node scripts/parse-logs.js` in a dir without `engines`).
- The user is reading files or running `git` — not Node commands.

## Reporting

After the preflight, briefly state to the user which Node version was
activated and why (e.g., "Switched to Node 20.20.2 — project's `engines.node`
requires >=20.0.0, was on 18.20.8"). This makes the guard visible so the user
knows it ran and can catch false positives.

## Failure Modes This Prevents

| Symptom | Root cause | What this skill does |
|---------|-----------|----------------------|
| `npm error ERESOLVE peerOptional` on `npm install` | Lockfile built on Node 18, project requires 20, peer deps resolve differently | Re-source nvm + correct version before install |
| `npm warn EBADENGINE` | Wrong Node version active | Switch before running |
| Tests pass locally, fail in CI | Local Node ≠ CI Node | Pin via `.nvmrc` + this preflight |
| `npm ci` fails "lockfile out of sync" | Lockfile regenerated on wrong Node | Always regenerate with correct version |
| Build succeeds but runtime crashes | Optional peer installed on wrong Node | Install on the right Node |
| `nvm use` "works" but next command fails | Each `terminal` call is a fresh shell without nvm sourced | Always chain in one command line |

## Related

- Project-level pinning: prefer a committed `.nvmrc` in every Node project so
  this skill has an unambiguous source of truth. If the project lacks one,
  recommend the user add it: `node --version > .nvmrc`.
