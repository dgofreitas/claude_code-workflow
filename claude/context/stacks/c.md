<!-- Context: development/backend/c/project-structure | Priority: high | Version: 1.0 | Updated: 2026-08-12 -->

# C — Project Structure Standard

**Purpose**: Defines the mandatory project structure for C services and libraries.
CMake is the assumed default build system — it is a **choice**, not a fact: Meson owns the
freedesktop/GNOME stack (systemd, GStreamer, Mesa, QEMU) and Autotools has a large legacy
tail. Detect the build system before assuming. Do not mix build systems in one project.

---

## Stack Detection Cheatsheet

| File Present | Stack Indicator |
|------|----------------|
| `CMakeLists.txt` | CMake → default assumption |
| `meson.build` | Meson → `meson setup build && meson test -C build` |
| `configure.ac` / `Makefile.am` | Autotools (legacy) → `./configure && make && make check` |
| `Makefile` only | Plain Make — small/embedded project |
| `compile_commands.json` | Compilation DB present → static analysis is wired |
| `test/` or `tests/` + `unity.c` | Unity test framework |
| `#include <cmocka.h>` in tests | cmocka (mocks statics/syscalls via linker wrap) |
| `#include <criterion/criterion.h>` | Criterion (host-only Linux, forks per test) |
| `.clang-tidy` / `.clang-format` | LLVM tooling configured |

---

## Layout: Library + Executable + Tests

```
project-root/
├── CMakeLists.txt          # top-level: project(), include(CTest), add_subdirectory
├── include/                # PUBLIC headers only — the API surface
│   └── myproj/
│       └── calc.h          # self-contained, include-guarded
├── src/                    # implementation + private headers
│   ├── calc.c
│   ├── internal.h          # NEVER installed, not in include/
│   └── main.c              # entrypoint (thin — logic lives in the lib)
├── tests/
│   ├── CMakeLists.txt
│   ├── test_calc.c
│   └── unity/              # vendored (unity.c, unity.h, unity_internals.h)
├── .clang-tidy
└── compile_commands.json   # generated, gitignored
```

**Rule**: business logic goes in a **library target**, never directly in the executable —
otherwise tests cannot link against it. `main.c` only parses args and calls into the lib.

---

## Minimal Modern CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.20)
project(myproj C)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)              # -std=c11, NOT -std=gnu11
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)    # for clang-tidy/cppcheck

add_library(mylib src/calc.c)
target_include_directories(mylib PUBLIC include)
target_compile_options(mylib PRIVATE -Wall -Wextra -Wpedantic)

include(CTest)                           # implies enable_testing(); MUST be top-level
if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
```

```cmake
# tests/CMakeLists.txt
add_executable(test_calc test_calc.c unity/unity.c)
target_link_libraries(test_calc PRIVATE mylib)
add_test(NAME test_calc COMMAND test_calc)
set_tests_properties(test_calc PROPERTIES TIMEOUT 30)
```

`enable_testing()` / `include(CTest)` must be in the **top-level** file, after `project()`.
In a subdirectory only → "No test configuration file found!".

---

## Key Patterns

### Error handling — pick ONE convention per project

```c
/* Convention A: 0 on success, -1 + errno on failure */
int calc_load(const char *path, calc_t *out);

/* Convention B: negative errno directly (kernel style) */
int calc_load(const char *path, calc_t *out);   /* returns -ENOENT, -EINVAL */
```

Mixing conventions within a module is a defect. Check **every** `malloc`/`fopen`/syscall return.

### Memory ownership — document it in the header

```c
/* Returns a newly allocated buffer; caller must free(). NULL on failure. */
char *calc_render(const calc_t *c);
```

`realloc(p, n)` returning NULL **leaks the old `p`** if you assigned into `p` — use a temp:
```c
char *tmp = realloc(buf, n);
if (!tmp) { free(buf); return -1; }
buf = tmp;
```

### Single cleanup path

```c
int process(void) {
    int rc = -1;
    FILE *f = NULL;
    char *buf = NULL;
    f = fopen("in.txt", "r");
    if (!f) goto cleanup;
    buf = malloc(1024);
    if (!buf) goto cleanup;
    rc = 0;
cleanup:
    free(buf);
    if (f) fclose(f);
    return rc;
}
```

### Header hygiene

- Include guard (`#ifndef MYPROJ_CALC_H`) or `#pragma once`
- Headers must compile standalone — include what they use, nothing more
- Never `static` definitions in a header; forward-declare structs instead of including
- Private headers live in `src/`, never `include/`

### Bounded string handling

`strncpy` does **NOT** NUL-terminate on truncation — substituting it for `strcpy` is not a
fix. Prefer `snprintf` and **check the return** (it returns the length it *would* have
written, so `ret >= size` means truncation):

```c
int n = snprintf(dst, sizeof dst, "%s/%s", dir, name);
if (n < 0 || (size_t)n >= sizeof dst) return -1;   /* truncated */
```

---

## Naming Conventions

| Element | Pattern | Example |
|---------|---------|---------|
| File | snake_case | `calc_engine.c` |
| Public function | `module_verb` | `calc_load()`, `calc_free()` |
| Static function | snake_case | `parse_line()` |
| Type | `_t` suffix | `calc_t`, `parser_state_t` |
| Macro / constant | UPPER_SNAKE | `CALC_MAX_DEPTH` |
| Include guard | `PROJECT_FILE_H` | `MYPROJ_CALC_H` |
| Struct member | snake_case | `item_count` |

---

## When Creating a New Project

1. `CMakeLists.txt` with `CMAKE_C_STANDARD 11`, `C_EXTENSIONS OFF`, `EXPORT_COMPILE_COMMANDS ON`
2. Split `include/` (public API) from `src/` (implementation + private headers)
3. Business logic in a **library target**; `main.c` stays thin
4. Vendor Unity into `tests/unity/` (3 files, no dependency) — use cmocka instead if you
   must mock static functions or syscalls
5. `include(CTest)` at top level; one `add_test()` per test executable
6. Baseline warnings: `-Wall -Wextra -Wpedantic`; add the C-specific ones `-Wall` misses:
   `-Wconversion -Wsign-conversion -Wshadow -Wstrict-prototypes -Wmissing-prototypes
   -Wcast-align -Wnull-dereference -Wvla -Wformat=2`
7. **Separate build directories per purpose** — they use conflicting flags:
   `build-debug/`, `build-coverage/` (`-O0 --coverage`), `build-asan/`, `build-tsan/`
8. Target ≥90% line coverage via `gcovr --fail-under-line 90`

---

## Related Context

- [Code Quality](../standards/code-quality.md)
- [Clean Code](../standards/clean-code.md)
- [Test Coverage](../standards/test-coverage.md)
