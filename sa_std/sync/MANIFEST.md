# sync/ — module boundary manifest (SA std modularization Phase 1, 2026-11-22)

Domain D. Owner of in-process synchronization primitives: atomics, locks,
condition variables, barriers, one-time initialization, and the bounded /
list-backed MPSC channels. Pure SA macro + layout (`.sa` + `.sal`) layer;
no runtime code of its own — the primitives are built from atomic
intrinsics, spin/backoff sleeps, and `alloc`/`load`/`store`.

## Public modules

| Module | Files | Responsibility |
|---|---|---|
| `atomic/` | `atomic/atomic.sa`, `atomic/atomic.sal` | `AtomicBool/U8/I8/U16/I16/U32/I32/U64/I64/Usize/Isize/Ptr`, `AtomicOrdering` (`RELAXED/RELEASE/ACQUIRE/ACQ_REL/SEQ_CST`), `ATOMIC_*` load/store/swap/CAS/fetch-op macros. Largest file in the domain (1500 lines). |
| `mutex/` | `mutex/mutex.sa`, `mutex/mutex.sal` | `Mutex` / `MutexGuard` spin-lock macros incl. try-lock, timeout lock, `_I32` payload form. |
| `rwlock/` | `rwlock/rwlock.sa`, `rwlock/rwlock.sal` | `RwLock` / `RwLockI32` multi-reader single-writer macros + read/write guards. |
| `once/` | `once/once.sa`, `once/once.sal` | `Once` / `OnceState` / `OnceLock` / `LazyLock` one-time init. |
| `barrier` | `barrier.sa`, `barrier.sal` | `Barrier` / `BarrierWaitResult`, single-generation spin barrier. Stays at `sync/` root (no subdir proposed in Phase 1). |
| `condvar` | `condvar.sa`, `condvar.sal` | `Condvar` over `Mutex` (notify one/all, wait, timeout wait). Depends on `mutex/`. |
| `mpsc` | `mpsc.sa`, `mpsc.sal` | Bounded MPSC channel macros (`Mpsc`, `Sender`/`Receiver`, `SendError`/`TryRecvError`/`RecvTimeoutError` …). This is sync's own channel; it is NOT the goroutine `Chan` (that lives in `task`, declared in `sa_std/task.sai`). |
| `mpsc_list` | `mpsc_list.sa`, `mpsc_list.sal` | Unbounded mutex + linked-list MPSC variant. **Not aggregated by `prelude.sa` / `prelude.sal`** (pre-existing state; only `rust_core.sa` and tests import it — see report). |
| `poison` | `poison.sa`, `poison.sal` | `PoisonError` / `TryLockError` layouts. No in-tree users outside tests. Aggregated by `prelude.sa` but **not by `prelude.sal`** (pre-existing asymmetry — see report). |
| `prelude` | `prelude.sa`, `prelude.sal` | Aggregation: importing `sync/prelude.sa` (or `.sal`) exposes every module above except `mpsc_list` (and `poison.sal` on the layout side). This is the established re-export mechanism in SA: `@import` is transitive (proven by `tests/unit_framework/std_prelude_import_surface.sa`, which imports only `sa_std/prelude.sa` and uses macros from transitively imported files). |

## Allowed dependency direction

```
sync  →  core, time, num, collections
sync  ↛  net, db, http, os, io, ffi, task
```

Measured edges (Phase 1, from the `@import` graph — not the proposal's
shorthand "sync depends on core"):

- `mpsc.sa` → `../core/mem.sa`, `../num.sa`, `../time.sai`
- `mpsc_list.sa` → `mutex.sa`, `../collections/linked_list.sa`, `../time.sai`
- `condvar.sa` → `mutex.sa` + `mutex.sal`, `../time.sa`, `../time.sai`
- `mutex.sa` → `../time.sa`, `../time.sai`
- `barrier.sa`, `once.sa`, `rwlock.sa` → `../time.sai`
- `atomic.sa`, `poison.sa` → only their own `.sal`

## Known reverse edge (pre-existing, NOT fixed in Phase 1)

`core` depends on `sync` today, so the layering is not acyclic:

- `sa_std/core/sa_core.sa` imports `../sync/rwlock.sa` + `../sync/rwlock.sal`
- `sa_std/rust_core.sa` imports `sync/rwlock`, `sync/mutex`, `sync/barrier`,
  `sync/condvar`, `sync/mpsc_list`

Resolving that edge (move the `RwLock` use out of core, or invert the
dependency) is a later-phase decision. Phase 1 only records it and keeps
the edge working through the new paths.

## Compatibility

Old paths (`sync/atomic.sa`, `sync/mutex.sa`, `sync/rwlock.sa`,
`sync/once.sa`, plus their `.sal`) remain as thin shims that forward to the
new locations. Every in-repo non-test importer was switched to the canonical
path; `tests/` and external code keep working through the shims. Removing a
shim is a breaking change and must be announced as such.

## Layout convention (for readers, not a rule change)

`_SIZE` covers the primitive header only; a trailing payload field sits at
`+SIZE` (e.g. `Mutex_SIZE = 8`, `Mutex_data = +8`; `Mpsc_SIZE = 32`,
`Mpsc_data = +32`). Allocating sites that carry a payload allocate
`SIZE + payload` (`MUTEX_NEW_I32` allocates 16; `MPSC_NEW` allocates
`Mpsc_data + cap * Mpsc_SLOT_SIZE`). This is deliberate, not a bug.
