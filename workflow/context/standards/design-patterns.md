<!-- Context: standards/design-patterns | Priority: high | Version: 1.0 | Updated: 2026-07-02 -->

# Design Patterns — GoF Catalog

**Purpose**: Prescriptive catalog of the 23 Gang of Four patterns. Each entry answers **intent**, **when to use**, **when NOT to use** (overengineering trap), and **minimal shape**. Not tutorial material — reference for developer agents (apply) and review agents (flag missing/misapplied patterns).

**When to use**: `backend-developer*`, `frontend-developer*` before choosing a structural approach for non-trivial logic. `code-reviewer*` / `impl-reviewer-*` when flagging design issues by name instead of vague "refactor this".

---

## Golden Rules (read before applying anything)

1. **Rule of Three** — do not extract a pattern on the first occurrence, sometimes not even on the second. Repetition ≥3 times of the same problem shape is the earliest reasonable trigger.
2. **Pattern-first thinking is a smell.** Solve the concrete problem first; recognize the pattern after the fact. Never start from "this is a Visitor problem".
3. **Every pattern is a trade-off.** Flexibility costs indirection and cognitive load. If the flexibility is not currently exercised, you are paying the cost for nothing.
4. **Patterns are named vocabulary, not solutions.** Their main value in this workflow is that `code-reviewer` can say "extract a Strategy here" and `backend-developer` knows exactly what shape to produce — no ambiguity.

---

## Creational (5) — object construction

Patterns that separate *what* is constructed from *how*.

| Pattern | Intent | Use when | Do NOT use when | Minimal shape |
|---------|--------|----------|-----------------|---------------|
| **Singleton** | One instance for the whole process | The type genuinely represents a unique resource (process-wide config loaded once, DB connection pool) | You want "just one for now" — that is a global variable in disguise. Fights testability. Prefer dependency injection. | Private constructor + static `getInstance()`. In JS: module-level `const instance = new X()`. |
| **Factory Method** | Defer instantiation to a subclass | Base class knows *when* to create but not *what* type. Framework template-method flow. | You have only 1 or 2 concrete types and no polymorphism need — a switch or plain `new X()` is clearer. | Abstract method `create()` returning a base type; subclass overrides. |
| **Abstract Factory** | Create families of related objects without naming concrete classes | You have families of variants that MUST stay consistent (all "dark theme" widgets, all "postgres" adapters) — mixing families would be a bug. | You have one family. This is Factory Method with extra abstraction. |  Interface `WidgetFactory { button(); menu(); }`; per-family impl. |
| **Builder** | Assemble a complex object step by step | Object needs >3-4 params, especially with optional ones, or construction has ordering rules. Also: fluent APIs. | Object has ≤3 required params and no options. Regular constructor is clearer. | Chained setters returning `this`; terminal `build()`. |
| **Prototype** | Clone an existing object instead of constructing anew | Construction is expensive and you have a valid instance to copy from. Kernel/prototype-based JS. | Almost never in modern typed code — object spread / structured clone covers it. Mostly historical. | `clone(): This` method; deep vs shallow decision made explicit. |

---

## Structural (7) — object composition

Patterns that describe *how objects fit together*.

| Pattern | Intent | Use when | Do NOT use when | Minimal shape |
|---------|--------|----------|-----------------|---------------|
| **Adapter** | Make an incompatible interface fit an expected one | Wrapping an external library / legacy API to conform to your domain interface. | You control both sides — just change the interface. Adapter is for boundaries, not internal glue. | Class implementing `Target` interface, holding an `Adaptee` instance, translating calls. |
| **Bridge** | Separate abstraction from implementation so both vary independently | Two orthogonal axes of variation (e.g., renderer × shape, storage backend × cache policy) causing combinatorial subclass explosion. | Only one axis varies. Regular inheritance is fine. | Abstraction holds a reference to Implementor interface; each varies independently. |
| **Composite** | Treat individual and grouped objects uniformly | Tree structures where clients should not care leaf vs branch (file system, UI tree, org chart). | Flat collections. Composite is only worth it when the recursion actually matters to callers. | Common `Component` interface; `Leaf` implements it directly; `Composite` implements it and holds children. |
| **Decorator** | Add behavior to individual objects at runtime without subclassing | Layerable, opt-in behaviors (logging, caching, auth, retry, throttling) that combine in unpredictable orders. | Behavior is uniform across all instances. Use plain inheritance or middleware pipeline instead. | Wrapper implementing same interface as wrapped object, adding behavior around delegated calls. |
| **Facade** | Provide a simple interface over a complex subsystem | Public entry point to a subsystem you want to insulate callers from (checkout facade over cart + inventory + payment + shipping). | A single well-named function does the job. Facade with one method is overkill. | Class exposing a handful of high-level methods, delegating internally. |
| **Flyweight** | Share fine-grained objects to reduce memory | You have millions of tiny objects that share intrinsic state (glyphs in a text editor, tiles in a map). | You have thousands or fewer. Modern GC handles it. Pure optimization pattern. | Immutable shared state extracted into flyweight; per-instance extrinsic state passed as method arg. |
| **Proxy** | Substitute another object to control access | Virtual (lazy-load expensive resource), protection (auth check), remote (network call), caching, or logging proxies. | You do not need the interposition. A direct call is clearer. Do not confuse with Decorator — Decorator adds behavior, Proxy controls access. | Same interface as real subject; proxy holds ref (or creates lazily), intercepts before delegating. |

---

## Behavioral (11) — object interaction

Patterns that describe *how objects coordinate and distribute responsibility*.

| Pattern | Intent | Use when | Do NOT use when | Minimal shape |
|---------|--------|----------|-----------------|---------------|
| **Chain of Responsibility** | Pass request along a chain until one handler accepts | Middleware pipelines (Express/Koa), event bubbling, validation stages where any link may terminate. | Order is fixed and known — plain sequential calls are clearer. | Handler with `next` reference; `handle()` either processes or delegates to `next`. |
| **Command** | Encapsulate a request as an object | Undo/redo, transactional queues, deferred execution, GUI actions bound to buttons/shortcuts. | You just want to call a function. `Command` for a single-shot direct call is bureaucracy. | Class with `execute()` (and optionally `undo()`); invoker holds and triggers. |
| **Interpreter** | Represent grammar as an object tree; evaluate by traversal | You are literally implementing a small language / DSL / query language. Rare. | Anything that is not a language. Regex or a parser generator covers 90% of "small language" needs faster. | AST node classes each with `interpret(context)`; typically paired with Visitor. |
| **Iterator** | Traverse a collection without exposing internals | Custom aggregate types where clients need sequential access. Language iterators (JS generators, Python `__iter__`, C# `IEnumerable`) cover most cases. | Native language iteration works. Reinventing iteration is a smell. | Return object with `next(): { value, done }` (JS) or equivalent per language. |
| **Mediator** | Centralize complex communication between components | Chat rooms, form-field cross-validation, dialog with many mutually-affecting widgets — replaces N×N direct links with N-to-1. | Only 2-3 components interact. Direct calls are clearer. Overuse turns mediator into a god object. | Central `Mediator` object; components call `mediator.notify(event)`; mediator dispatches. |
| **Memento** | Capture and restore an object's state without violating encapsulation | Undo, checkpoint/restore, time travel debugging, save games. | State can be serialized directly. Memento is for controlled internal-state snapshots that outsiders should not read. | `Memento` object created by originator, opaque to caretaker who stores it. |
| **Observer** | Publish-subscribe on state changes | UI reactive to model, event bus, domain-event fan-out. | You have exactly one listener. Direct call. Observers with 1 subscriber are always premature. | Subject maintains subscriber list; `notify()` walks them. RxJS/EventEmitter/domain events are all this. |
| **State** | Behavior varies with internal state; each state is an object | Complex FSM where transitions and per-state behavior are non-trivial (order lifecycle, connection lifecycle, editor modes). | 2 states with a boolean flag. If-else is clearer. | Context holds current `State` object; each `State` implements the same interface, may transition context to another. |
| **Strategy** | Interchangeable algorithms for the same problem | Multiple valid algorithms for the same task (compression, sorting, pricing rules, retry policies) selectable at runtime or config. | Only one algorithm exists. Strategy in advance of a second algorithm is speculation. | Interface `Strategy { execute(data) }`; context holds one, delegates. |
| **Template Method** | Skeleton of algorithm in base class, subclasses fill in steps | Framework flow where high-level sequence is fixed but individual steps vary per subclass (test setUp/tearDown, HTTP handler lifecycle). | You can achieve the same with strategy composition — usually cleaner because composition beats inheritance. Template Method locks you into inheritance. | Base class with `run()` calling `abstract step1()`, `abstract step2()`; subclasses implement steps. |
| **Visitor** | Add operations to an object structure without changing the classes | Object structure is stable but operations grow (compiler AST needing type-check, code-gen, pretty-print without touching AST nodes). | Object structure changes often — you will have to touch every visitor for every new node type. Then it's a maintenance nightmare. | Visitable object has `accept(visitor)`; visitor has `visitX(node)` per node type. |

---

## Selection Heuristics — when to reach for which

Use this table when the problem is clear but the pattern is not:

| The problem is… | Try first |
|-----------------|-----------|
| "I have N ways to do X and want to swap at runtime" | Strategy |
| "I want to add behavior around an existing thing" | Decorator (add behavior) or Proxy (control access) — decide by intent |
| "This class has grown a huge switch-on-type" | Replace with Strategy or State; possibly Visitor if type set is stable |
| "Two objects must stay consistent" | Observer |
| "Complex object with lots of optional config" | Builder |
| "Legacy/external interface does not fit" | Adapter |
| "Multi-step process where steps are pluggable" | Template Method (inheritance) or Strategy (composition — prefer this) |
| "Undo / redo / audit trail" | Command + Memento |
| "Middleware / handler pipeline" | Chain of Responsibility |

---

## Anti-Patterns — common misuses

- **Singleton as global state** — hides dependencies, breaks tests. If you cannot inject it, it is global state wearing a Singleton hat.
- **Factory-for-one-type** — a Factory that always returns the same concrete type is dead code. Delete it and call `new X()`.
- **God Facade** — Facade that grew until it has 40 methods and touches every subsystem. Split by subsystem or feature.
- **Observer chains** — deep observer chains (A → B → C → D) become impossible to debug. Prefer a single event bus with explicit topics.
- **Strategy of one** — a Strategy interface with one implementation is a class you needed. Add the interface when the second strategy appears.
- **Visitor over a moving target** — using Visitor on a class hierarchy that changes often produces churn across every visitor. Only worth it when node types are stable.
- **Decorator soup** — 6 decorators wrapping the same object across the codebase is unreadable. Consider a middleware pipeline (list of functions) or explicit config.

---

## Related Context

- `standards/code-smells-refactoring.md` — smells often signal a missing pattern; catalog of the refactoring moves to introduce one safely
- `standards/clean-code.md` — the layer *below* patterns (names, functions, nesting); patterns solve structural problems, clean code solves local problems
- `standards/code-quality.md` — review checklist that references patterns by name
