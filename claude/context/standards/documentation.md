<!-- Context: standards/docs | Priority: critical | Version: 2.1 | Updated: 2026-08-20 -->

# Documentation Standards

## Quick Reference

**Golden Rule**: If users ask the same question twice, document it

**Document** (✅ DO):

- WHY decisions were made
- Complex algorithms/logic
- Public APIs, setup, common use cases

**Don't Document** (❌ DON'T):

- Obvious code (i++ doesn't need comment)
- What code does (should be self-explanatory)
- Task history, state, or investigation logs — those go to the commit or the artifact (see §Comment Budget)

**Principles**: Audience-focused, Show don't tell, Keep current, **Right channel**

---

## Principles

**Audience-focused**: Write for users (what/how), developers (why/when), contributors (setup/conventions)
**Show, don't tell**: Code examples, real use cases, expected output
**Keep current**: Update with code changes, remove outdated info, mark deprecations

## README Structure

```markdown
# Project Name
Brief description (1-2 sentences)

## Features
- Key feature 1
- Key feature 2

## Installation
```bash
npm install package-name
```

## Quick Start

```javascript
const result = doSomething();
```

## Usage

[Detailed examples]

## API Reference

[If applicable]

## Contributing

[Link to CONTRIBUTING.md]

## License

[License type]

```

## Function Documentation

```javascript
/**
 * Calculate total price including tax
 * 
 * @param {number} price - Base price
 * @param {number} taxRate - Tax rate (0-1)
 * @returns {number} Total with tax
 * 
 * @example
 * calculateTotal(100, 0.1) // 110
 */
function calculateTotal(price, taxRate) {
  return price * (1 + taxRate);
}
```

## What to Document

### ✅ DO

- **WHY** decisions were made
- Complex algorithms/logic
- Non-obvious behavior
- Public APIs
- Setup/installation
- Common use cases
- Known limitations
- Workarounds (with explanation)

### ❌ DON'T

- Obvious code (i++ doesn't need comment)
- What code does (should be self-explanatory)
- Redundant information
- Outdated/incorrect info

For *code comments* specifically — how much is too much, and which of task history, state, or design rationale belongs in the commit vs. an artifact — see §Comment Budget below.

## Comment Budget

"Why, not what" is necessary but **not sufficient**. Design rationale, investigation logs and task history are all *why* — writing all of them buries the one comment that matters and rots as the code moves.

A comment earns its place only when **a competent reader (human or agent) would get it wrong without it**. Everything else has a better home.

### Three channels — pick exactly one

| Content | Goes to |
|---------|---------|
| Non-local invariant — "change this and X breaks", X not visible in this file | **Code**, 1–2 lines + pointer |
| Trap — an obvious-looking alternative that is wrong | **Code**, 1 line |
| Why this fix was made, what was broken, which task introduced it | **Commit message** |
| Design rationale, rejected alternatives, investigation log | **Artifact** (`artifacts/stories/*.md`) |

If a comment cites an artifact, it is duplicating it. **Keep the pointer, delete the copy.**

### Hard limits

- **Max 5 lines per comment block.** Longer belongs in an artifact — leave a one-line pointer.
- **A fix must not add more comment lines than code lines.** If the explanation outweighs the change, it is a commit message.
- **Never write the same explanation twice** — not across files, not across functions. Second occurrence is one line pointing at the first.
- **Never record state or history**: "not done yet", "already configured", "added in T4", "fixed here", "was X before". State goes stale silently; nothing in CI catches it.
- **Never name a file or symbol without verifying it exists.** A comment pointing at a deleted file is worse than no comment — the reader trusts it over the code.

### Good — short, imperative, stands out

```javascript
// invariant: prefix grepped by ci job .rpm_test_conf_expectation — STORY-056 §3
const PROMPT_PREFIX = 'preencha em ';

// browser resolves this, not docker DNS — internal name breaks login
const authorizeUrl = publicKeycloakUrl;

// HACK: API returns null instead of [], normalize it
const items = response.items || [];
```

### Bad

```javascript
// Increment i
i++;

/**
 * Introduced in T4 of STORY-062. The spike showed the previous driver went
 * stale when the two functions landed, so REQUIRED_CONF stayed empty and
 * require_conf() never died... [15 more lines]
 */
```

The second one is not "too verbose" — it is **in the wrong channel**. It is a commit message pasted into the source.

## API Documentation

```markdown
### POST /api/users
Create a new user

**Request:**
```json
{ "name": "John", "email": "john@example.com" }
```

**Response:**

```json
{ "id": "123", "name": "John", "email": "john@example.com" }
```

**Errors:**

- 400 - Invalid input
- 409 - Email exists

```

## Best Practices

✅ Explain WHY, not just WHAT
✅ Include working examples
✅ Show expected output
✅ Cover error handling
✅ Use consistent terminology
✅ Keep structure predictable
✅ Update when code changes

**Golden Rule**: If users ask the same question twice, document it.
