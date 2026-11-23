# core — module boundary manifest (SA stdlib Phase 1, 2026-11-22)

`sa_std/core/` is the minimal core of the SA standard library: the types,
memory primitives, and control-flow machinery every other domain builds on.
It must be the bottom of the dependency graph.

## 1. Dependency rule

- **core may only depend on core.** Every `@import` whose resolved target
  leaves `core/` is a boundary violation and must be listed in §5 until it
  is removed.
- **core must never depend on `io`, `net`, `db`, `http`, or `task`.**
  (Verified: zero such edges — see §5. Note `core/future/task.sa` is a
  *file inside* core, not a dependency on a task domain; its extraction is
  an open decision, §6.)
- Other domains (`alloc`, `collections`, `sync`, `text`, `io`, …) may depend
  on core; core never depends on them.

## 2. Subdomains

| Subdomain | Files | Responsibility |
|---|---|---|
| `core/types/` | `any`, `array`, `ascii`, `borrow`, `char`, `cmp`, `convert`, `cow`, `default`, `ops`, `pin`, `trait_object` (+`.sal`) | Core traits and primitive types: comparison, conversion, borrowing, operators, `char`, fixed arrays, `Pin`, trait objects |
| `core/memory/` | `mem`, `mem.sal`, `raw`, `box`, `cleanup`, `manually_drop`, `prelude`, `rel_link`, `slice_pool`, `slot_pool` | Raw memory ops (`sa_mem_copy/set`, `BOX_*`), size/align macros, `ManuallyDrop`, cleanup guards, arena/pool primitives |
| `core/ptr/` | `ptr`, `ptr.sal` | Raw pointer operations |
| `core/slice/` | `slice`, `slice.sal`, `sort` | Slices and slice algorithms (sorting) |
| `core/option/` | `option`, `option.sal` | `Option<T>` |
| `core/result/` | `result`, `result.sal` | `Result<T, E>` |
| `core/num/` | `num`, `num.sai`, `num.sal`, `math`, `math.sai`, `num_u32`, `bit`, `nonzero`, `prelude` | Integers/floats, `NonZero`, float math externs, bit ops, `u32` derived ops |
| `core/marker/` | `marker`, `marker.sal`, `phantom_data`, `prelude` | Marker types (`PhantomData`, ZST helpers) |
| `core/error/` | `error`, `error.sal` | Core error types |
| `core/hash/` | `hasher`, `hash.sal`, `probe` | `DefaultHasher`/`RandomState` public API (`hasher`); map probe/mix helpers (`probe`, see §5 D1) |
| `core/cell/` | `cell`, `refcell`, `rc`, `arc`, `weak` (+`.sal`) | Interior mutability and smart pointers (`Cell`, `RefCell`, `Rc`, `Arc`, `Weak`) |
| `core/iter/` | `iter`, `iter.sal`, `loop` | Iterators and loop macros |
| `core/control/` | `control`, `control.sal`, `rust_patterns.sal` | Control-flow macros (`if`/`for`/`switch`/`try`), Rust-style pattern macros |
| `core/panic/` | `panic`, `panic.sal` | Panic machinery |
| `core/future/` | `future`, `task`, `waker` (+`.sal`) | Async primitives hosted in core (see §6: extraction candidate) |
| `core/derive/` | `derive`, `dispatch` (+`.sal`) | Derive/dispatch macro machinery |
| `core/runtime/` | `globals.sai`, `modstate.sai`, `identity.sai` | `@extern` contracts for runtime built-ins (global cells, module state, identity maps) |
| `core/` (root) | `prelude`, `sa_core`, `rust_core` | `prelude` — the core aggregate facade; `sa_core` — assertion macros for smoke tests (see §5 D5); `rust_core` — Rust-core compatibility aggregate (see §5 D6) |

## 3. File roles

- `.sa` — macros and `@export` functions (the implementation).
- `.sal` — `#def` layout constants (struct sizes/offsets, numeric constants).
  Exception: `core/control/control.sal` holds `[MACRO]` definitions, not
  layout constants — a pre-existing extension/content mismatch, kept as-is.
- `.sai` — `@extern` declarations (FFI contracts for Zig runtime built-ins).

## 4. Layering inside core (bottom → top)

1. **Leaf layer, no imports:** `core/slice/slice.sa`, `core/memory/raw.sa`
   (raw ops), `core/panic/panic.sa`, `core/control/control.sa`,
   `core/num/bit.sa`, `core/types/default.sa`, plus all `.sal`/`.sai`.
2. **Types layer:** `option` → `result`/`panic`/`slice`;
   `result` → `option`/`panic`; `types/*` → `slice`/`option`/`result`/`hash`.
3. **Smart pointers:** `cell/*` → `num` (`arc` → `num.sal` only).
4. **Iterators/control:** `iter` → `slice`; `loop` → `slice`/`iter`/`num`.
5. **Aggregates (top):** `core/prelude`, `core/sa_core`, `core/rust_core`
   import across subdomains; they are entry points, not libraries.

## 5. Known boundary exceptions (documented, NOT fixed in Phase 1)

These edges leave `core/` today. Each is a defect record for Phase 2;
none was repaired (Phase 1 rule: organise boundaries, do not fix).

| # | Edge | Why it exists |
|---|---|---|
| D1 | `core/hash/probe.sa` → `hashmap.sal`, `hashmap.sa` (collections) | Probe/mix macros are hashmap implementation detail hosted in core; they call `@sa_map_get`/`@sa_map_put` |
| D2 | `core/iter/iter.sa` → `vec_runtime_macros.sa` (top-level, alloc) | Iterator macros reuse Vec runtime macros |
| D3 | `core/types/array.sa` → `vec.sa` (alloc) | Array helpers use `Vec` |
| D4 | `core/memory/{rel_link,slice_pool,slot_pool}.sla` → `vec.sa` (alloc) | Pools are `Vec`-backed arenas |
| D5 | `core/sa_core.sa` → `sync/rwlock.sal`, `sync/rwlock.sa` | Test-assertion aggregate pulls in rwlock; `sa_core` is test support, not core library |
| D6 | `core/rust_core.sa` → `sync/*` (9 edges) + `collections/linked_list.*` (2) | Rust-core compatibility aggregate, imports widely by design |
| — | `core/memory/*.sla` → `ptr.sa` (3 edges) | Resolves through the top-level `ptr.sa` shim back into `core/ptr/` — core-internal in effect, not a real outbound edge |

Forbidden-direction check (2026-11-22, static): **0 edges** from any file
under `core/` to `io` / `net` / `db` / `http` / `task` paths.

## 6. Open boundary decisions (for the user / Phase 2)

1. **`core/future/` (future/task/waker):** the task domain lives inside
   core, but the brief states core must not depend on task. Extract
   `future` + `task` + `waker` to a dedicated `task/` (or `async/`)
   domain, or formally declare them part of core? `core/prelude.sa` and
   `core/sa_core.sa` import `task.sa` today.
2. **`ffi.sa` / `ffi.sal` (top level):** FFI module, depends on
   `string.sa` (alloc); overlaps the `ffi/` subdir (`cstring` facades).
   Decide with the ffi owner: `core/ffi/` vs `ffi/` vs top level.
3. **`string_format.sa`, `str.sla`:** depend on alloc/io; proposed home
   `text/` (or fmt domain).
4. **`mem/` / `num/` / `marker/` directories:** now shim-only (4 files
   each). Remove them once importers migrate to canonical paths.
5. **Shim retirement:** 99 compatibility shims were left at old paths
   (434 real source files outside `sa_std/` — 353 in `tests/`, 81 in
   `demos/` — import old paths). Retire shims only after those importers
   are migrated; do not break `tests/` in Phase 1.

## 7. Compatibility policy

- `@import` is textual inclusion; the flattener dedupes by resolved entry
  path (`src/flattener/expandimportsinto.zig`, `seen_paths`) and the
  source-tree walk dedupes by real path (`src/cli/source_tree.zig`).
  A shim file containing only `@import "<new path>"` is therefore a
  lossless forwarder — this is the established in-tree pattern
  (`ascii.sa`, `option.sa`, … were already shims before Phase 1).
- Root-anchored imports (`@import "sa_std/..."`, `src/pkg/resolver.zig`)
  keep working unchanged through shims.
- Old paths are stable API: do not delete a shim without migrating its
  importers first.
