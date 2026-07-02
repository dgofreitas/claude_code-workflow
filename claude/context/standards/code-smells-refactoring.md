<!-- Context: standards/code-smells-refactoring | Priority: high | Version: 1.0 | Updated: 2026-07-02 -->

# Code Smells & Refactoring Catalog

**Purpose**: Named vocabulary for what is wrong (smells) and the safe move to fix it (refactorings). Not tutorial material — reference for `code-reviewer*` / `impl-reviewer-*` to flag findings precisely, and for `bug-fixer-*` / `backend-developer*` to know which technique to apply.

**When to use**: `code-reviewer*` writing findings ("Long Method → Extract Method" instead of "this function is too long"). Any developer agent before applying a non-trivial change to legacy code.

---

## The Safety Principle — read first

A refactoring is a **behavior-preserving code change**. Two rules are non-negotiable:

1. **Green tests before, green tests after.** If tests are not green before you start, you are not refactoring — you are debugging while also moving code, and you will not know which broke what. Fix or add tests first.
2. **Small steps, commit often.** One named refactoring at a time. Compile/run tests after each step. A refactoring session should look like 10 small commits, not one huge "refactor" commit.

Refactoring and behavior change never share a commit. If you find a bug mid-refactor, note it, finish the refactor, commit, then fix the bug in a separate commit.

---

## The 24 Smells (Fowler taxonomy)

Grouped by what they signal. Each has a **detection** (how you notice it) and a **refactoring** (the named move to fix it).

### Bloaters — things that grew too large

| Smell | Detection | Refactoring |
|-------|-----------|-------------|
| **Long Method** | Function >20 lines; you scroll to read it; hard to name what it does in one sentence | Extract Method — pull cohesive blocks into new named functions |
| **Large Class** | Class with >7 fields or >200 lines; touches unrelated concerns | Extract Class (split responsibilities) or Extract Subclass |
| **Primitive Obsession** | Strings/numbers used to represent domain concepts (email as string, money as number, phone as string) | Replace Primitive with Object — introduce `Email`, `Money`, `PhoneNumber` value objects |
| **Long Parameter List** | ≥4 params, especially with booleans or optional trailing args | Introduce Parameter Object (bundle related), or Preserve Whole Object (pass the aggregate) |
| **Data Clumps** | Same 3+ variables travel together across many method signatures (`firstName, lastName, email` everywhere) | Extract Class — they wanted to be an object |

### Object-Orientation Abusers — misuse of OO features

| Smell | Detection | Refactoring |
|-------|-----------|-------------|
| **Switch Statements** | `switch` on a type code, especially duplicated across the codebase | Replace Conditional with Polymorphism — subclasses per case, method per behavior |
| **Temporary Field** | Instance field only set/used under specific conditions; empty most of the time | Extract Class for the algorithm that uses it — the field belongs to that class |
| **Refused Bequest** | Subclass inherits methods it does not want / overrides them all to throw | Push Down Method to only the subclasses that want it, or replace inheritance with composition |
| **Alternative Classes with Different Interfaces** | Two classes do the same job with different method names | Rename Method; if still divergent, Extract Superclass |

### Change Preventers — code that resists change

| Smell | Detection | Refactoring |
|-------|-----------|-------------|
| **Divergent Change** | One class changes for multiple unrelated reasons (touched for auth changes AND for pricing changes) | Extract Class — split by axis of change |
| **Shotgun Surgery** | A single conceptual change forces edits in many classes (adding a field forces touching 15 files) | Move Method / Move Field — consolidate what changes together into one place |
| **Parallel Inheritance Hierarchies** | Every new subclass in hierarchy A forces a new subclass in hierarchy B | Move Method/Field — collapse one hierarchy into the other |

### Dispensables — things that should not exist

| Smell | Detection | Refactoring |
|-------|-----------|-------------|
| **Duplicate Code** | Same logic in ≥3 places (Rule of Three) — small variations OK, structural repetition not | Extract Method (same class), Pull Up Method (siblings), or Extract Class |
| **Dead Code** | Function/variable/branch reachable but never actually called with meaningful input | Delete it. Git remembers. Do not comment out — that is graveyard code. |
| **Speculative Generality** | Abstract classes, hooks, or params introduced "for future needs" that never came | Inline Class / Collapse Hierarchy — YAGNI in reverse |
| **Data Class** | Class with only fields + getters/setters and no behavior | Move Method — behavior that operates on this data belongs on this class |
| **Lazy Class** | Class that does almost nothing; its purpose was never fulfilled | Inline Class — merge it back into its only caller |
| **Comments** | Comment explains *what* the next block does, or apologizes for its complexity | The comment is a code smell. Extract Method with a name that says what the block does — the name replaces the comment. Keep comments only for *why*. |

### Couplers — things bound too tightly

| Smell | Detection | Refactoring |
|-------|-----------|-------------|
| **Feature Envy** | Method uses another object's data more than its own (many `other.getX()` / `other.getY()` calls) | Move Method — the method wants to live on the other class |
| **Inappropriate Intimacy** | Two classes reach deep into each other's internals | Move Method / Move Field, or Extract Class holding the shared concept, or Change Bidirectional Association to Unidirectional |
| **Message Chains** | `a.getB().getC().getD().doSomething()` — client walks the object graph | Hide Delegate — `a.doSomething()` handles the walk internally |
| **Middle Man** | Class whose methods almost all delegate to another class | Remove Middle Man — let clients call the delegate directly, or Inline Class |

### Other

| Smell | Detection | Refactoring |
|-------|-----------|-------------|
| **Incomplete Library Class** | You need one more method on a library class you can't modify | Introduce Foreign Method (helper in your code) or Introduce Local Extension (subclass/wrapper) |

---

## The Core Refactoring Moves

You do not need 60 named refactorings. These 12 handle the vast majority of the smells above. Learn these shapes; the rest are variants.

| Move | What it does | Applies to |
|------|--------------|-----------|
| **Extract Method** | Turn a code block into a named function | Long Method, Duplicate Code (same class), Comments |
| **Inline Method** | Replace a call with the method body | When the method name says less than the body |
| **Extract Class** | Split a class into two along a responsibility line | Large Class, Divergent Change, Data Clumps, Temporary Field |
| **Inline Class** | Merge a class into its only user | Lazy Class, Speculative Generality, Middle Man |
| **Move Method** / **Move Field** | Relocate a member to where it is really used | Feature Envy, Shotgun Surgery, Inappropriate Intimacy |
| **Rename** (variable/method/class) | Change a name to fit intent | Any time reading takes a second guess |
| **Replace Conditional with Polymorphism** | Turn `switch(type)` into subclass dispatch | Switch Statements |
| **Replace Primitive with Object** | Wrap a raw value in a domain type | Primitive Obsession |
| **Introduce Parameter Object** | Group related params into a single object | Long Parameter List, Data Clumps |
| **Pull Up Method** / **Push Down Method** | Move a method up or down an inheritance hierarchy | Duplicate Code (siblings), Refused Bequest |
| **Hide Delegate** / **Remove Middle Man** | Route through an intermediary, or stop routing | Message Chains, Middle Man |
| **Replace Magic Number with Named Constant** | Give a literal a name | Any raw literal with semantic meaning |

---

## Refactoring vs Rewriting — decision heuristic

Refactoring is safe **when tests exist and the design is not fundamentally wrong**. Rewrite when:

- No tests exist AND the code is critical → write tests first (that alone often reveals the design is fine and refactoring beats rewriting)
- The abstraction is wrong at the root (wrong domain model, wrong sync/async choice, wrong data structure) — no sequence of small moves fixes this
- You would touch >70% of the file in refactors — you are rewriting anyway, just less honestly

If you can fix it in ≤5 named refactoring moves, refactor. Beyond that, revisit the decision.

---

## Review Reporting — how `code-reviewer*` should cite this

Findings that reference this file must use **both the smell name and the refactoring**:

```
File:Line → **Feature Envy**: OrderService.calculateTotal() reads 6 fields from Cart, none from itself.
Fix: **Move Method** — calculateTotal() belongs on Cart.
```

Not: "this method should be somewhere else" or "envious code".

---

## Related Context

- `standards/design-patterns.md` — many refactorings terminate in "introduce a pattern" (Replace Conditional with Polymorphism → Strategy or State; Extract Class → Strategy; etc.)
- `standards/clean-code.md` — smell #17 (Comments) is enforced by the naming rules there; smells #1-4 (Bloaters) map to the function-size and nesting rules
- `standards/code-quality.md` — review checklist should reference smells by name
