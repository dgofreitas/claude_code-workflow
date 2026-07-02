<!-- Context: standards/clean-code | Priority: high | Version: 2.0 | Updated: 2026-07-02 -->

# Clean Code — Local Quality Rules

**Purpose**: The layer *below* patterns and architecture — rules for names, functions, nesting, comments, and error handling at the line/function scope. Not architecture, not patterns — those live in `standards/design-patterns.md` and `standards/code-smells-refactoring.md`.

**When to use**: Every developer agent, every review agent, every pass over the code. This is the floor.

---

## Core Rules (non-negotiable)

- **Boy Scout Rule** — leave every file you touched a little cleaner than you found it. A small rename, a magic number promoted to a constant, one extra guard clause. Not a refactoring session — one small improvement per touch.
- **SRP at function level** — a function does one thing when you can name it without using "and" or a conjunction. `validateAndSave` is two things. Split.
- **Comments are code smells** — see `standards/code-smells-refactoring.md` §Dispensables → Comments. If you feel the need to explain *what* the next block does, extract a method with that name instead. Comments explain *why* (a workaround, a constraint, a surprising invariant), never *what*.
- **Names carry the type of thing they name** — collections plural (`users`, not `userList`), booleans read as predicates (`isActive`, `hasPermission`, `canRetry`), functions read as verbs (`calculateTotal`, not `total`).

## Core Principles

### 1. Meaningful Names

**Use intention-revealing names**:

- Variable names should reveal intent
- Function names should describe what they do
- Class names should describe what they represent

**Examples**:

```javascript
// Bad
const d = new Date();
const x = getUserData();

// Good
const currentDate = new Date();
const activeUserProfile = getUserData();
```

### 2. Functions Should Do One Thing

**Single Responsibility**:

- Each function should have one clear purpose
- Functions should be small (ideally < 20 lines)
- Extract complex logic into separate functions

**Example**:

```javascript
// Bad
function processUser(user) {
  validateUser(user);
  saveToDatabase(user);
  sendEmail(user);
  logActivity(user);
}

// Good
function processUser(user) {
  const validatedUser = validateUser(user);
  const savedUser = saveUserToDatabase(validatedUser);
  notifyUser(savedUser);
  return savedUser;
}
```

### 3. Avoid Deep Nesting

**Keep nesting shallow**:

- Use early returns
- Extract nested logic into functions
- Prefer guard clauses

**Example**:

```javascript
// Bad
function processOrder(order) {
  if (order) {
    if (order.items.length > 0) {
      if (order.total > 0) {
        // process order
      }
    }
  }
}

// Good
function processOrder(order) {
  if (!order) return;
  if (order.items.length === 0) return;
  if (order.total <= 0) return;
  
  // process order
}
```

### 4. DRY (Don't Repeat Yourself)

**Eliminate duplication**:

- Extract common logic into reusable functions
- Use composition over inheritance
- Create utility functions for repeated patterns

### 5. Error Handling

**Handle errors explicitly**:

- Use try-catch for expected errors
- Provide meaningful error messages
- Don't ignore errors silently

**Example**:

```javascript
// Bad
function fetchData() {
  try {
    return api.getData();
  } catch (e) {
    return null;
  }
}

// Good
async function fetchData() {
  try {
    return await api.getData();
  } catch (error) {
    logger.error('Failed to fetch data', { error });
    throw new DataFetchError('Unable to retrieve data', { cause: error });
  }
}
```

## Best Practices

1. **Write self-documenting code** - Code should explain itself through clear naming and structure
2. **Keep functions pure when possible** - Avoid side effects, return new values instead of mutating
3. **Use consistent formatting** - Follow language-specific style guides (Prettier, ESLint, etc.)
4. **Write tests first** - TDD helps design better APIs and catch issues early
5. **Refactor regularly** - Improve code structure as you learn more about the domain
6. **Comment why, not what** - Code shows what, comments explain why
7. **Use type systems** - TypeScript, type hints, or static analysis tools
8. **Favor composition** - Build complex behavior from simple, reusable pieces

## Anti-Patterns

- ❌ **Magic numbers** - Use named constants instead of hardcoded values
- ❌ **God objects** - Classes that do too much or know too much
- ❌ **Premature optimization** - Optimize for readability first, performance second
- ❌ **Clever code** - Simple and clear beats clever and complex
- ❌ **Long parameter lists** - Use objects or configuration patterns instead
- ❌ **Boolean flags** - Often indicate a function doing multiple things
- ❌ **Mutable global state** - Leads to unpredictable behavior and bugs

## Language-Specific Guidelines

### JavaScript/TypeScript

- Use `const` by default, `let` when needed, never `var`
- Prefer arrow functions for callbacks
- Use async/await over raw promises
- Destructure objects and arrays for clarity

### Python

- Follow PEP 8 style guide
- Use list comprehensions for simple transformations
- Prefer context managers (`with` statements)
- Use type hints for function signatures

### Go

- Follow effective Go guidelines
- Use defer for cleanup
- Handle errors explicitly
- Keep interfaces small

### Rust

- Embrace ownership and borrowing
- Use pattern matching
- Prefer iterators over loops
- Handle errors with Result types

## Related Context

- `standards/design-patterns.md` — the layer *above*: structural solutions when local cleanliness isn't enough
- `standards/code-smells-refactoring.md` — how to spot when clean-code rules were violated in legacy code, and the named refactoring to fix it
- `standards/code-quality.md` — review checklist that references these rules
