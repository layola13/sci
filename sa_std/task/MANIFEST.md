# task/ — module boundary manifest (SA std modularization Phase 1, 2026-11-22)

Domain D. Owner of threads, goroutines/tasks, channels, selection, and the
async executors built on them. `sa_std/thread/` is merged into this
directory (`thread/prelude.*` merged into `task/prelude.*`); the old
`thread/` directory remains only as four compat shims
(`join_handle.sa/.sal`, `prelude.sa/.sal`) — it holds no definitions.

## Layout

```
task/
├── prelude.sa / prelude.sal   # domain aggregation (see below)
├── task.sa / task.sal         # facade shim → ../core/task.sa (Task + executor-poll macros)
├── future.sa / future.sal     # facade shim → ../core/future.sa (Poll / Future macros)
├── thread.sal                 # JoinHandle layout + THREAD_DEFAULT_ID (moved from top level)
├── async.sla                  # multi-threaded async task executor (mpsc pipes + OS threads)
├── timer.sla                  # delay futures + cancellable one-shot Timer handles
├── m_async.sa / .sal / .sla   # m-async cancellation / task-group compat facade
├── plugin_async.sa / .sal / .sla  # plugin async adapter → PollResult<u64>
├── libsa_async.sa             # async state-machine helper macros (ASYNC_CTX_DEF …)
├── spawn/
│   ├── thread.sa / thread.sai     # OS-thread spawn/join/yield (pthread_* externs)
│   └── thread_local.sa / .sai     # thread_local! slot registry facade
├── join/
│   ├── join_handle.sa / .sal      # JoinHandle facade over thread.sa (canonical copy)
│   └── supervisor.sla             # one-for-one supervision over supervised goroutines
├── channel/
│   └── executor.sla               # single-owner executor goroutine skeleton over Chan
└── select/                        # RESERVED, empty in Phase 1 (see below)
```

## Public modules by subdir

| Subdir | Contents | Responsibility |
|---|---|---|
| `spawn/` | `thread.*`, `thread_local.*` | Spawning: OS threads (`THREAD_SPAWN`, `THREAD_JOIN_STATUS`, builder facade) and per-thread storage (`THREAD_LOCAL_SLOT`, `THREAD_LOCAL_U32/U64_GET/SET`). The goroutine spawn externs (`sa_task_spawn`, …) are declared in `sa_std/task.sai` (see deferral below), not here. |
| `join/` | `join_handle.*`, `supervisor.sla` | Joining / lifecycle: `JoinHandle` layout + facade, and `supervise()` (join + `sa_task_trap_info` + restart budget + notify channel). |
| `channel/` | `executor.sla` | Channel-pattern executor: one owner goroutine, FIFO inbox `Chan`, request/reply blocks, drain-on-stop. The runtime channel surface itself (`sa_chan_*`) is declared in `sa_std/task.sai`. |
| `select/` | *(empty)* | Reserved. The select surface is currently only the `sa_chan_select` extern declaration in `sa_std/task.sai`, which has **zero in-tree callers**. A standalone select module awaits the `.sai` split (see deferral below). |
| *(root)* | `task.*`, `future.*`, `async.sla`, `timer.sla`, `m_async.*`, `plugin_async.*`, `libsa_async.sa` | Cross-cutting entries: the `core/` facades, the two executors, timers, and the compat/adapter layers. |

## Allowed dependency direction

```
task  →  core, sync, time
task  ↛  net, db, http, os, io
```

Measured edges (Phase 1):

- `async.sla` → `sync/mpsc`, `sync/mutex`, `core/result`, `core/arc`,
  `core/waker`, `core/box`, `future`, `time.sla`, `pin`, `ptr`, `spawn/thread`
- `timer.sla` → `time.sla`, `future`, `core/arc`
- `executor.sla` → `sa_std/task.sai`, `core/box`
- `supervisor.sla` → `sa_std/task.sai`, `time.sai`, `ptr`
- `plugin_async.sa` → `core/future.sa`
- `m_async.sa` → only its own `.sal`; `libsa_async.sa` → nothing
- `spawn/thread.sa` → `thread.sai`, `time.sa`

Documented exception: `task/plugin_async.sla` (the SLA import surface)
also re-exports the HTTP plugin adapters (`plugin_http_async.sa`,
`plugin_http_server.sla`). That is the pre-existing aggregation purpose of
that file, not a dependency of the task macro layer — the `.sa`/`.sal` side
of `plugin_async` depends only on `core/future`.

## What did NOT move in Phase 1 (deferred, with reasons)

1. **`sa_std/task.sai` stays at the top level.** It declares the whole
   runtime extern surface in one file: `sa_task_*` (spawn/join/sleep/
   monitor/trap), `sa_chan_*` (make/destroy/close/send/recv/select),
   `sa_sync_*` (mutex/rwlock/waitgroup/once), and the wasm coop trio.
   It cannot move yet because:
   - no `.sai` file anywhere in the tree contains `@import`, so a `.sai`
     forwarding shim is an **unverified mechanism** (Phase 1 runs no
     builds/tests, so it cannot be proven);
   - `tests/task_spawn_vtable_entry_unit.sa` imports `sa_std/task.sai`
     directly and `tests/` must not be touched in Phase 1;
   - Zig-side comments lock the surface by path ("the whole
     `sa_std/task.sai` surface (36 names)", `src/emit_c.zig:172`).
   Splitting it into `spawn.sai` / `join.sai` / `channel.sai` /
   `select.sai` (which would also populate `select/` and move the
   `sa_sync_*` externs to `sync/`) is Phase 2+ work, coordinated with
   the Zig C1 test.
2. **`sa_std/core/task.sa` / `core/future.sa` / `core/waker.sa` /
   `core/arc.sa` stay in `core/`** (another domain's files). `task/`
   only holds the thin facades `task/task.sa` and `task/future.sa`
   that forward to them — the same shim pattern that already existed
   at the top level before Phase 1.
3. **`sa_std/executor_test.sla` stays at the top level.** It is a test
   file living inside the std tree; Phase 1 updates its imports only.

## Compatibility

Old top-level paths remain as thin shims forwarding to the new locations:
`task.sa/.sal`, `future.sa/.sal`, `thread.sa/.sal`, `join_handle.sa/.sal`,
`thread_local.sa`, `async.sla`, `executor.sla`, `supervisor.sla`,
`timer.sla`, `m_async.sa/.sal/.sla`, `plugin_async.sa/.sal/.sla`,
`libsa_async.sa`. Every in-repo non-test importer was switched to the
canonical path; `tests/` and external code keep working through the shims.

No shims exist for `thread.sai` / `thread_local.sai` (no in-repo importers
outside the moved files; a `.sai` shim is unverified — see above).
`sa_std/thread/` remains as a shim-only directory: `join_handle.sa/.sal`
and `prelude.sa/.sal` forward to `task/`; it holds no definitions.

## Prelude

`task/prelude.sa` aggregates the domain's `.sa` files
(`task`, `future`, `spawn/thread`, `spawn/thread_local`,
`join/join_handle`, `m_async`, `plugin_async`, `libsa_async`);
`task/prelude.sal` aggregates the layout side (`task.sal`,
`future.sal`, `thread.sal`, `join/join_handle.sal`,
`spawn/thread.sai`, `../task.sai`). The top-level `prelude.sa` /
`prelude.sal` now import only `task/prelude.sa` / `task/prelude.sal`
for this domain. `@import` is transitive in SA (see `sync/MANIFEST.md`
for the proof), so the prelude is the re-export mechanism — there is no
separate re-export syntax.
