---
name: test-execution
description: Strategy and best practices for agents to run tests and check coverage without failing or timing out. Covers Vitest, Jest, Node Native, Mocha, and npm test.
---

# Test Execution & Coverage Strategy

> **Purpose**: Prevent agents from making common mistakes (wrong commands, reading huge files, piping errors) when running tests, checking coverage, and executing static analysis (ESLint/TypeScript) across ANY Node.js project.

---

## 🛑 What NOT to Do (Anti-Patterns)

1. **NEVER read raw `.log` files** (e.g., `~/.local/share/rtk/tee/...`). These files are huge and will cause you to time out or exceed token limits.
2. **NEVER blindly read `coverage-summary.json`**. It might not exist or might not be generated depending on the test configuration. Always verify file existence first.
3. **NEVER run the entire test suite** if you only need to check one failing test or if the suite produces too much output.
4. **NEVER run tests without verifying your directory**. In monorepos (e.g., frontend/backend), running `npm test` in the root will fail if tests are inside sub-folders.

---

## ✅ Proper Strategy for Test Execution

### 1. Verify Working Directory First
Before running any test command, ensure you are in the correct directory containing the target `package.json` and test configuration.
- **Good**: `cd backend && npm run test`
- **Good**: `cd frontend && npx vitest run src/App.test.tsx`
- **Bad**: Trying to run `npm test` from the root directory without checking if `package.json` exists there.

### 2. Running Tests Safely (Any Framework)
Always use standard test execution commands WITHOUT pipes. If using `npm test`, you can pass arguments to the underlying runner using `--`.
- **Good**: `npm run test`
- **Good**: `npm test -- src/my-file.test.ts`
- **Good**: `npx jest src/my-file.test.ts`

### 3. Checking Coverage (The Smart Way)
Instead of looking for JSON or HTML files that might not exist or are too large, force the test runner to output a short text summary directly to the console.

**How to get Text-Summary Coverage by Framework:**

*   **Generic `npm test` (passes args down):**
    ```bash
    # Try passing generic coverage flags if you don't know the runner
    npm test -- --coverage
    ```

*   **Vitest:**
    ```bash
    npx vitest run --coverage.enabled=true --coverage.reporter=text-summary
    ```

*   **Jest:**
    ```bash
    npx jest --coverage --coverageReporters="text-summary"
    ```

*   **Node.js Native Test Runner (`node --test`):**
    ```bash
    node --experimental-test-coverage --test
    ```

*   **Mocha (requires c8 or nyc):**
    ```bash
    npx c8 --reporter=text-summary mocha
    # or
    npx nyc --reporter=text-summary mocha
    ```

*This will print a concise table in the console with % coverage, without needing to read external files.*

**If you MUST read coverage files:**
1. First verify the directory exists using the `list_dir` or `glob` tool. Do not blindly read paths like `coverage/coverage-summary.json`.
2. Check `package.json` or `vitest.config.ts`/`jest.config.js` to see where coverage is actually output.

### 4. Handling Test Failures & Large Outputs
If a test suite fails with a massive output that gets truncated:
1. **Do NOT** try to read the full truncated log file.
2. Identify the specific file that failed from the summary output.
3. Run ONLY that file to get a focused error trace:
   ```bash
   npm test -- path/to/failing-file.test.ts
   # or
   npx jest path/to/failing-file.test.ts
   ```
4. If still too large, stop on the first failure (Bail):
   - **Vitest/Jest:** `npm test -- path/to/failing.test.ts --bail 1`
   - **Mocha:** `npx mocha path/to/failing.test.ts --bail`

### 5. Linting and Static Analysis (ESLint & TSC)
Running `eslint` or `tsc` on a dirty codebase can produce massive outputs that crash the terminal proxy or consume all tokens.

*   **TypeScript (tsc):**
    Never pipe `tsc` to `grep`. If `tsc --noEmit` fails with too many errors, you must fix the most critical errors first or focus on the files you modified.
*   **ESLint:**
    If `eslint .` produces too much output:
    1. **Target Specific Files:** Run ESLint only on the files you are currently working on.
       ```bash
       npx eslint path/to/your-file.ts
       ```
    2. **Quiet Mode:** Only show errors, ignore warnings to reduce output size.
       ```bash
       npx eslint . --quiet
       ```
    3. **Auto-fix:** Attempt to automatically fix issues before reading the output.
       ```bash
       npx eslint . --fix
       ```

---

## Summary of Golden Rules

1. **NO PIPES** on test or lint commands.
2. **VERIFY CWD**: Always `cd` into the correct project folder (frontend/backend) first.
3. **TEXT REPORTERS** for coverage (e.g., `--coverageReporters="text-summary"`).
4. **ISOLATE** failing tests or lint errors by running only their specific files.
5. **NEVER READ** raw `rtk` log files.
