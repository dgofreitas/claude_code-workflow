<!-- Context: stacks/mastra-ai | Priority: high | Version: 1.0 | Updated: 2026-05-02 -->
# Mastra AI

**Purpose**: Central orchestration layer for AI agents, workflows, and tools. Mastra wires together agents, tools, workflows, and observability with built-in persistence and logging.

**Reference root**: `src/mastra/`, `src/mastra/index.ts`, `src/mastra/shared.ts`

---

## Core

Central hub that composes agents, tools, workflows, and storage into a single instance.

```typescript
import { Mastra } from '@mastra/core/mastra';
import { agents, tools, workflows } from './components';

export const mastra = new Mastra({
  agents, tools, workflows,
  storage: new LibSQLStore({ url: 'file:./mastra.db' }),
});
```

- Centralized config in `src/mastra/index.ts`
- Persistence via `LibSQLStore` (SQLite)
- Built-in tracing + Pino logging
- Modular — components defined separately, composed centrally

---

## Agents & Tools

**Agents** = specialized LLM configs using Tools. **Tools** = standalone, reusable logic blocks with Zod-validated schemas.

```typescript
// Tool
const myTool = createTool({
  id: 'my-tool',
  inputSchema: z.object({ query: z.string() }),
  execute: async ({ inputData }) => ({ result: `Processed ${inputData.query}` }),
});

// Agent
const myAgent = new Agent({
  name: 'My Agent',
  instructions: 'Use my-tool to process queries.',
  model: { provider: 'OPEN_AI', name: 'gpt-4o' },
  tools: { myTool },
});
```

Tools can be executed independently of agents — highly reusable.

---

## Workflows

Directed graphs of steps. Sequential (`.then()`) or parallel (`.parallel()`). Support suspend/resume for human-in-the-loop.

```typescript
const workflow = createWorkflow({ id: 'my-workflow', inputSchema, outputSchema })
  .then(step1)
  .parallel([step2a, step2b])
  .then(mergeStep)
  .commit();

const { runId, start } = workflow.createRun();
const result = await start({ inputData: { ... } });
```

Each step has access to global `state` and `inputData` from the previous step.

### Step structure

Group steps by phase in dedicated `steps/` directories for complex workflows.

```typescript
// src/mastra/workflows/v3/steps/phase1.ts
export const myStep = createStep({
  id: 'my-step-id',
  inputSchema: z.object({ ... }),
  outputSchema: z.object({ ... }),
  stateSchema: workflowStateSchema,
  execute: async ({ inputData, state, mastra }) => {
    console.log('🚀 Starting myStep...');
    const result = await myTool.execute(inputData, { mastra });
    return result;
  },
});
```

- Shared schemas in `schemas.ts` co-located with steps
- Steps orchestrate; Tools do heavy lifting
- Console logs at start/end of each step for debugging

### Example: document ingestion (parallel branches)

```typescript
export const documentIngestionWorkflow = createWorkflow({
  id: 'document-ingestion',
  inputSchema: z.object({ filename: z.string(), fileBuffer: z.any() }),
  outputSchema: z.object({ documentId: z.string(), success: z.boolean() }),
})
  .then(uploadStep)
  .then(extractionStep)
  .parallel([classificationStep, summarizationStep])
  .then(mergeResultsStep)
  .commit();
```

Reference: `src/mastra/workflows/document-ingestion-with-classification-workflow.ts`

---

## Storage

Dual storage: local SQLite (via Drizzle) for business entities + `LibSQLStore` for Mastra execution data.

- **Business entities** in `src/db/schema.ts` — e.g., `cases`, `documents`, `assessments`, `outputs`
- **Mastra tables** — `mastra_traces`, `mastra_ai_spans`, `mastra_scorers`, `mastra_workflow_state`
- **V3 extensions** — `timeline_events`, `evidence_gaps`, `sub_claims`, `vulnerability_flags`
- **File blobs** — stored in `./tmp/` with paths referenced in DB
- **Cost tracking** — `prompt_execution_traces` captures per-AI-call cost and tokens

```typescript
storage: new LibSQLStore({
  url: process.env.MASTRA_DB_PATH || 'file:./mastra.db',
}),
```

---

## Evaluations

Scorers assess LLM output quality (0–1 score). Registered in Mastra instance, triggered during workflow execution. Results persisted in `mastra_scorers` for audit.

Common metrics: hallucination detection, fact validation, relevance scoring.

---

## Modular Building

As the project grows:

- **Component separation** — keep `agents`, `tools`, `workflows`, `scorers` in their own top-level directories under `src/mastra/`
- **Shared services** — instantiate DB/repos in `src/mastra/shared.ts` to avoid circular deps
- **Central registry** — all components registered in `src/mastra/index.ts` (single source of truth)
- **Feature grouping** — group related workflow steps into sub-dirs (e.g., `workflows/v3/steps/`)

```typescript
// src/mastra/shared.ts
export const services = createServices();

// src/mastra/index.ts
import { services } from './shared';
export const mastra = new Mastra({
  workflows: { myWorkflow },
  agents: { myAgent },
});
```

---

## File Map

| Component | Directory | Registered in |
|-----------|-----------|---------------|
| Mastra instance | `src/mastra/` | `src/mastra/index.ts` |
| Agents | `src/mastra/agents/` | `src/mastra/index.ts` |
| Tools | `src/mastra/tools/` | `src/mastra/index.ts` |
| Workflows | `src/mastra/workflows/` | `src/mastra/index.ts` |
| Scorers | `src/mastra/scorers/` | `src/mastra/index.ts` |
| Services | `src/services/` | `src/mastra/shared.ts` |

---

## Testing

Tool-level + workflow integration.

```bash
npm run test:calculator      # specific tool
npm run test:playbook        # tool suite
npm run test:workflow        # full E2E
npm run test:baseline        # vs. known baseline
npm run validity:workflow    # validity E2E
npm run traces               # inspect last run
```

Reference: `package.json` scripts, `scripts/`.

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `RateLimitError` | Too many concurrent requests | Rate-limit or increase quota |
| `NotFoundError` | Missing case/document ID in DB | Check DB state before workflow start |
| `MastraContextError` | `services` not passed to tool | Ensure `services` is in `ToolExecutionContext` |

Reference: `src/lib/errors.ts`

---

## Common Commands

| Command | Description |
|---------|-------------|
| `npm run dev` | Start Mastra in development |
| `npm run traces` | View recent execution traces |
| `npm run test:workflow` | Run the test workflow |
