---
name: tavily
description: |
  Perform real-time web searches and extract deep content from specific URLs using the
  official Tavily remote MCP server in Claude Code.

  **When to use Tavily:**
  - Library/framework is NOT in the Context7 registry (~50+ supported libraries)
  - General troubleshooting, news, or current events
  - Architecture decisions requiring community consensus
  - Checking latest versions, changelogs, or breaking changes
  - Comparing multiple solutions or tools

  **When to use Context7 instead:**
  - Library IS in the Context7 registry (React, Next.js, Drizzle, Prisma, etc.)
  - Need structured, version-specific API documentation
  - Need code examples from official docs

  **Fallback chain:** Context7 (primary) -> Tavily MCP (secondary) -> WebFetch on specific URLs (tertiary)
---

# Tavily (Remote MCP)

## Overview

Tavily is a real-time web search and content extraction service. In Claude Code it is consumed
through the **official remote MCP server**, not a local script. Source of truth:
<https://docs.tavily.com/documentation/mcp>.

The remote server exposes the search/extract tools to Claude Code. Tool names are surfaced with the
MCP prefix `mcp__tavily-remote-mcp__<tool>` (e.g. `mcp__tavily-remote-mcp__tavily_search`).

## Installation (from scratch -- official procedure)

### Option A -- CLI (recommended)

```bash
# OAuth flow (no key in URL); Claude Code prompts for authentication on first use
claude mcp add tavily-remote-mcp --transport http https://mcp.tavily.com/mcp/
```

### Option B -- declare in `.claude/settings.json`

```json
{
  "mcpServers": {
    "tavily-remote-mcp": {
      "type": "http",
      "url": "https://mcp.tavily.com/mcp/"
    }
  }
}
```

### Option C -- API key in URL (no OAuth)

Append the key as a query parameter. NEVER commit a real key -- inject it from an env var:

```json
{
  "mcpServers": {
    "tavily-remote-mcp": {
      "type": "http",
      "url": "https://mcp.tavily.com/mcp/?tavilyApiKey=${TAVILY_API_KEY}"
    }
  }
}
```

> Get an API key at <https://app.tavily.com>. To disable the server, simply omit it from
> `mcpServers` (Claude Code has no `enabled: false` flag).

## MCP Tools

### `tavily-search`

Performs a web search and returns ranked results with optional AI answer.

**Key parameters:**

- `query` (required): Search query string
- `search_depth` (optional): `"basic"` or `"advanced"` -- use `"advanced"` for technical research (default `"basic"`)
- `max_results` (optional): number of results (default `5`, use `10` for deep research)
- `include_answer` (optional): include AI-generated summary (default `false`, use `true` when exploring unknown topics)

**Example:**

```text
tavily-search(query="best Node.js logging library 2026 comparison", max_results=10, search_depth="advanced", include_answer=true)
```

### `tavily-extract`

Extracts full content from one or more URLs.

**Key parameters:**

- `urls` (required): array of URLs to extract (max 20)
- `include_images` (optional): extract image descriptions (default `false`)

**When to use:** after `tavily-search` identifies promising URLs and you need deep reading
(changelog, blog post, doc page not covered by Context7).

## Workflow

1. **Check Context7 first**: if researching a library, try the `context7` skill before Tavily.
2. **Tavily search**: if Context7 has no match OR the topic is general web research, call
   `tavily-search` with `search_depth="advanced"` and `max_results=10`.
3. **Extract promising URLs**: if results look good, run `tavily-extract` on the top 3-5 URLs.
4. **Summarize and return**: return a brief summary + file locations (if persisted to `.tmp/external-context/`).

## Fallback Rules

- If the **Tavily MCP server is not configured/unavailable** (not added, OAuth declined, or network error):
  - Use `WebFetch` on specific known URLs
  - Do not fail the research task
- If **Tavily returns no results**: broaden the query or fall back to `WebFetch`.

## Parameter Heuristics

| Scenario | `search_depth` | `max_results` | `include_answer` |
|----------|----------------|---------------|------------------|
| Quick lookup | basic | 5 | false |
| Troubleshooting | advanced | 10 | true |
| Architecture comparison | advanced | 10 | true |
| API docs not in Context7 | advanced | 5 | false |

## Default Parameters (optional)

The remote server accepts a `DEFAULT_PARAMETERS` header to set defaults globally, e.g.
`{"include_images": false, "search_depth": "advanced", "max_results": 10}`. Configure this only at
the MCP client level if you want consistent behavior across calls.

## Important Notes

- Tavily is a **paid/limited API**. Use it efficiently. Prefer Context7 for supported libraries.
- **Never commit Tavily API keys.** Use OAuth (Option A/B) or an env var (`${TAVILY_API_KEY}`).
- If quota is exceeded, fall back immediately to `WebFetch`.
- Related agents: `.claude/agents/external-scout.md` (primary consumer), `.claude/agents/context-scout.md`.
