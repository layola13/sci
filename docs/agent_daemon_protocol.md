# `sa daemon` Protocol Specification (Phase A Executable Design)

> This is the English counterpart of the Chinese document [agent_daemon_protocol_cn.md](./agent_daemon_protocol_cn.md).

> **Implementation note (2026-07-11)**: The Unix socket daemon, the full argv (including `sa`/binary path normalization), `agent_id`/`generation` cancellation, `per-agent-limit`, `ping`/`shutdown`/`cancel`, response `metrics.wall_ms`, and verdict/affected counts have been implemented. Clients connect via `SA_DAEMON_SOCKET` (optionally `SA_AGENT_ID`/`SA_AGENT_GENERATION`).
>

> This document is the implementation specification for Phase A of [`agent_native_compiler_gap_and_plan_cn.md`](agent_native_compiler_gap_and_plan_cn.md). Target KPI: **reduce the cold-start cost of N agents from O(N) to O(1), with cache hits across requests**. Verified on 2026-07-11; the interface follows the current `src/cli.zig` / `src/flattener.zig` implementations.

---

## 0. Why the daemon is the highest-leverage change

Currently every `sa build/check/test` is a **cold-start process**:

- Three in-process static caches are all discarded when the process exits:
  - `src/cli.zig`: `source_tree_hash_cache` (source tree hash, verified by mtime+size)
  - `src/flattener.zig`: `import_source_cache` (imported source text)
  - `src/flattener.zig`: `expanded_import_cache` (expanded imports)
- N agents each cold-start, with zero cache reuse → repeated parse / expand / layout / verify.

These three caches are **already `mutex + tick-LRU` structures** (see `import_source_cache_mutex` / `import_source_cache_tick`), which makes them naturally suited to being moved into a long-lived process and shared across requests. The daemon does not need to rewrite the caches — it only needs to **extend their lifetime** and add request routing.

---

## 1. Process model

```
Agent A ─┐
Agent B ─┤   Unix domain socket        ┌─ Shared cache (in-process, survives across requests)
Agent C ─┼──►  $XDG_RUNTIME_DIR/  ────► │   source_tree_hash_cache
Agent D ─┘     sa-daemon-<projhash>.sock│   import_source_cache
              (JSON line protocol)     │   expanded_import_cache
                                        │   (added in Phase B) per-fn SAB / Referee summary
                                        └─ Scheduler (added in Phase D)
```

- **One daemon is bound to one project root** (the socket name contains a hash of the project root), to avoid cross-project cache contamination and to keep agent groups of different projects isolated from one another.
- **Thin client**: add a `--daemon` flag to existing CLI subcommands; if a connection can be established, go through the daemon; if it cannot (or `--no-daemon` is set), fall back to the current in-process execution — guaranteeing zero breakage and gradual rollout.
- **Transport**: Unix domain socket (local, low latency, inherently permission-isolated). No TCP is introduced, avoiding exposing a network surface (consistent with the minimal-exposure principle of `content_safety`).

---

## 2. Wire protocol (JSON line protocol)

Each request / response is a single line of UTF-8 JSON terminated by `\n` (NDJSON). It reuses the existing `--json` diagnostic model (the `{"status","diagnostics"}` output by `trap.writeJson`), so the parsing logic on the agent side is exactly the same as it is now.

### 2.1 Request

```json
{
  "id": "req-7f3a",
  "agent_id": "agent-03",
  "generation": 12,
  "op": "build" | "check" | "test" | "explain" | "cancel" | "ping" | "shutdown",
  "file": "src/main.sa",
  "args": ["--json", "--jobs", "4"],
  "cwd": "/abs/project/root"
}
```

- `agent_id` + `generation`: used for stale-task cancellation in Phase D (when a new generation from the same agent arrives, in-flight tasks of the old generation are cancelled). In Phase A these can simply be passed through without scheduling.
- `op: cancel`: the request body carries the `agent_id` to cancel (takes effect in Phase D; Phase A may return an `unsupported` placeholder).
- `op: ping` / `shutdown`: health check and graceful exit.

### 2.2 Response

Reuse the existing diagnostic model, adding daemon metadata:

```json
{
  "id": "req-7f3a",
  "status": "ok" | "error",
  "exit_code": 0,
  "metrics": {
    "compile_tokens": 12050,
    "instruction_count": 842,
    "wall_ms": 41,
    "cache": { "source_tree": "hit", "import": "hit", "expanded": "miss" }
  },
  "diagnostics": [ /* diagnostic array exactly matching the existing --json output */ ],
  "stdout": "…",
  "stderr": "…"
}
```

- `metrics.cache.*`: hit rates are the daemon's core observability metric, directly proving "reuse across agents".
- `stdout`/`stderr`: inside the daemon, execution output is captured into strings and returned; the client passes them through unchanged, guaranteeing that `--daemon` and non-daemon modes produce equivalent output for the agent.

---

## 3. Server execution path (reuse existing dispatch)

After receiving a request, the daemon **does not rewrite the compilation logic**; it directly reuses the existing entry point with injectable writers:

```
src/cli.zig:9520  executeWithWritersAndOptions(allocator, argv, stdout, stderr, options)
```

- Assemble the request's `args` into `argv`, capture `stdout`/`stderr` with in-memory buffer writers, and after execution put the buffer contents back into the response's `stdout`/`stderr` fields.
- The returned `!u8` is the `exit_code`.
- **Key change**: change the static cache variables in `src/cli.zig` and `src/flattener.zig` from "process statics" to "held by the daemon session" — the minimal approach is to keep them static but **not clear them at the end of a request** (they are not cleared now either; they disappear only when the process exits). Since the daemon is long-lived, they naturally survive across requests. The only thing to add is making the LRU limit configurable at runtime (there are already `*_max_entries` test hooks; promote them to a formal env var / request parameter).

### 3.1 Concurrency model (minimal Phase A version)

- The daemon main thread accepts connections; each connection gets a worker thread (or a thread pool).
- The caches are already protected by `mutex` → concurrent access from multiple workers is safe, no further changes needed.
- Phase A **does not do scheduling / cancellation / quotas** (that is Phase D); first prove the benefit of "cache reuse across requests + no cold start". However, the request structure reserves `agent_id`/`generation` to avoid breaking the protocol in Phase D.

---

## 4. Client changes (thin client)

> **Implementation status (re-verified 2026-11-05)**: The `--daemon` flag form described in this section was not implemented as written — cli.zig has no `--daemon` flag. The current integration is environment-variable driven: `src/daemon_client.zig` reads `SA_DAEMON_SOCKET` (:18) to decide whether to use the daemon, only `--no-daemon` acts as an opt-out switch (:23), and `SA_AGENT_ID` identifies the agent (:48). The actual usage of `sa daemon` is `sa daemon [--socket path] [--max-workers N] [--per-agent-limit N]`, with no `--idle-timeout` option. The text below is preserved as originally designed; when citing it, defer to this note.

- Add `Command.daemon` (`sa daemon [--socket <path>] [--idle-timeout <s>]`): start / run the resident service in the foreground.
- Add `--daemon` / `--no-daemon` to existing subcommands:
  - `--daemon`: attempt to connect (optionally auto-spawn if the socket does not exist), then use the wire protocol.
  - Default (no flag): keep the current behavior (in-process), **zero breakage**.
- On connection failure, fall back to in-process execution and emit a downgrade hint on `stderr` (readable by the agent).

---

## 5. Lifecycle and security

- **Socket permissions** `0600`, owner-only connections (local multi-tenant isolation).
- **Idle timeout**: automatically exit after N seconds of inactivity, avoiding zombie daemons consuming memory (directly addressing the measured constraint of 3.5 GB / no swap on this machine).
- **Version check**: the request carries the client compiler version; if it does not match the daemon version, respond with `status:error, code: SA-DAEMON-001 version mismatch`, and the client falls back to a cold start. (The cache key already includes `cacheCompilerVersion()`, so daemon version drift will not corrupt the cache.)
- **Crash isolation**: a panic in a single request should not bring down the daemon — the worker thread catches it and returns a `status:error` diagnostic; if necessary, that request falls back to an in-process retry on the client.

---

## 6. Acceptance criteria (aligned with the Phase A KPI)

1. **Correctness equivalence**: `--daemon` and cold-start mode produce **byte-for-byte identical** diagnostics + exit_code for the same input (A/B testing with the existing fixture corpus).
2. **Observable cache reuse**: a second agent's request for the same project has `metrics.cache.import = "hit"`.
3. **Throughput**: in a 10-agent benchmark (see the gap document §3), daemon-mode P50 feedback latency is **reduced by ≥5×** relative to cold start.
4. **Stability**: a single-request panic does not bring down the daemon; idle timeout reclaims correctly.
5. **Zero breakage**: without `--daemon`, behavior is exactly the same as now.

---

## 7. Additional stable error codes (write into the `trap.zig` dictionary)

> 2026-11-05 note: the SA-DAEMON-001…005 codes below have zero hits in a grep of the entire `src/` tree and have not been implemented.

| Code | Meaning |
|------|---------|
| `SA-DAEMON-001` | Client/daemon version mismatch; client should fall back to a cold start |
| `SA-DAEMON-002` | Socket connection failure (daemon not started / permissions) |
| `SA-DAEMON-003` | Malformed request (JSON parse failure / missing fields) |
| `SA-DAEMON-004` | Request cancelled (Phase D: preempted by a new generation) |
| `SA-DAEMON-005` | Quota exceeded, request queued and timed out (Phase D) |

---

## 8. Implementation order (Phase A internal breakdown)

1. **A1**: `Command.daemon` + Unix socket accept + NDJSON encode/decode + `op: ping/shutdown`. (a skeleton daemon can be run)
2. **A2**: route `op: build/check` to `executeWithWritersAndOptions`, capture stdout/stderr in buffers, return exit_code + diagnostics.
3. **A3**: confirm that the static cache lifetime survives across requests + report `metrics.cache.*` hit rates.
4. **A4**: client `--daemon` flag + connection/fallback logic.
5. **A5**: idle timeout, socket permissions, version check, panic isolation.
6. **A6**: 10-agent benchmark script + P50 latency comparison report.

Each step can be independently verified with `zig build` + A/B testing on the existing corpus; there is no need to wait for all of Phase A to finish.

---

## Appendix: relationship to existing documents

- This document = the expansion of Phase A of `agent_native_compiler_gap_and_plan_cn.md`.
- `agent_first_toolchain.md`: a "§5 Daemon mode" section should be added pointing back to this document.
- Phase B (function-level content hash + incremental Referee) per-function SAB / Referee summary caches will hang off the same daemon cache layer in the future (a place is reserved for them in this document §1).
- Phase D (scheduling / cancellation / quotas) reuses the `agent_id` / `generation` fields in this document's request, without breaking the protocol.
