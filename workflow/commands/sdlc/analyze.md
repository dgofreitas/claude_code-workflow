---
description: Analyze codebase architecture, patterns, and technical debt using language-specific analyzers
argument-hint: [scope or specific area to analyze]
---

# /analyze — Codebase Analysis

Route to the appropriate **code-analyzer** subagent to perform pre-planning analysis of the codebase.

## Workflow

1. **Detect language** from project files.
2. **Route to the appropriate analyzer**:
   - Node.js/TypeScript → `code-analyzer`
   - Any other language → `code-analyzer` (generic; language-specific variants such as `code-analyzer-python` / `code-analyzer-c` are used only if present in `.claude/agents/`)
3. **Invoke the analyzer** via the Task tool:

   > Analyze the codebase: **$ARGUMENTS**. If no specific scope, perform a full architecture analysis.

## The analyzer will

- Call context-scout for project context
- Map architecture patterns and conventions
- Identify technical debt and risks
- Document component relationships
- Output analysis to `artifacts/stories/STORY-XXX-code-analysis.md` (if story context) or display directly

## Output

A codebase analysis report: architecture overview and patterns, key components and relationships, technical debt items, risk areas, and improvement recommendations.
