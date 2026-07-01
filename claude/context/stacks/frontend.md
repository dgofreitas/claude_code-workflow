<!-- Context: development/frontend/when-to-delegate | Priority: high | Version: 3.0 | Updated: 2026-03-29 -->
# When to Delegate to FrontendDeveloper

**Core Rule**: Delegate design-intensive work. Handle simple edits directly.

---

## Decision Matrix

### Delegate to FrontendDeveloper

| Scenario | Why | Example |
|----------|-----|---------|
| **New UI from scratch** | Needs staged workflow (layout → theme → animation → implement) | "Create a landing page" |
| **Design system work** | Requires standards + ExternalScout for UI libs | "Implement Tailwind + Shadcn" |
| **Complex responsive** | Mobile-first across breakpoints | "Dashboard with sidebar + grid" |
| **Animations** | Performance optimization, micro-interactions | "Add smooth transitions" |
| **Theme creation** | OKLCH colors, CSS custom properties | "Create dark mode theme" |
| **Component lib integration** | ExternalScout for docs (Flowbite, Radix) | "Integrate Flowbite" |
| **Accessibility-focused UI** | WCAG compliance, ARIA | "Accessible form with validation" |

### Handle Directly (Don't Delegate)

| Scenario | Why | Example |
|----------|-----|---------|
| **Simple HTML/CSS edits** | Single file, straightforward | "Change button text" |
| **Bug fixes** | Fixing existing code | "Fix broken footer link" |
| **Content updates** | Text/image changes | "Update hero copy" |
| **Single component update** | One existing component | "Add prop to Button" |
| **Quick prototypes** | Throwaway code | "HTML mockup to test idea" |

---

## Delegation Checklist

- [ ] Task is UI/design focused (not backend/logic)?
- [ ] Requires design expertise (layout, theme, animations)?
- [ ] Benefits from staged workflow?
- [ ] User has approved the approach?

---

## How to Delegate

1. **Discover context** (optional): Use ContextScout for design standards
2. **Propose approach**: Present plan with task, approach, context needed
3. **Get approval**: Wait for explicit user approval
4. **Delegate with context**:

```javascript
task(
  subagent_type="FrontendDeveloper",
  description="{task summary}",
  prompt="Load context from .tmp/context/{session-id}/bundle.md before starting.
          
          Task: {requirements}
          
          Requirements:
          - Tailwind CSS + Flowbite (or specified framework)
          - Mobile-first responsive
          - Animations <400ms
          - Save to design_iterations/{name}.html
          
          Follow staged workflow (layout → theme → animation → implement).
          Request approval between each stage."
)
```

---

## FrontendDeveloper Capabilities

| Does Well | Does NOT Do |
|-----------|-------------|
| Complete UI designs from scratch | Backend logic / API integration |
| Design systems (Tailwind, Shadcn, Flowbite) | Database queries |
| Responsive layouts (mobile-first) | Testing / validation |
| Animations + micro-interactions | Code review / refactoring |
| OKLCH themes + CSS custom properties | Simple HTML/CSS edits (overkill) |
| Staged workflow with versioning | Content-only updates |

---

## Context Files Loaded via ContextScout

- **Design system**: project-specific theme templates, color systems
- **Styling standards**: `ui-styling-standards.md` — Tailwind, Flowbite, responsive
- **Animation patterns**: project-specific animation syntax
- **React patterns**: `development/frontend/react/react-patterns.md` (if React project)
- **Delegation**: `core/workflows/task-delegation-basics.md`

---

## Related

- **FrontendDeveloper Agent** → `.claude/agents/frontend-developer.md`
- **UI Styling Standards** → `ui-styling-standards.md`
- **Delegation Workflow** → `../../core/workflows/task-delegation-basics.md`
