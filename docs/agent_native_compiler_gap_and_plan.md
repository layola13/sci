# Agent-Native Compiler Backend: Capability Assessment and Development Plan

> This is the English counterpart of the Chinese document [agent_native_compiler_gap_and_plan_cn.md](./agent_native_compiler_gap_and_plan_cn.md).

> **Status (2026-11-05 document audit)**: An assessment and plan from 2026-07-11; the "implementation update" at the top of the document overturns multiple rows of the matrix in the body — the daemon is now a top-level command (cli.zig:743) and daemon_client/daemon_cancel are in the repo, so rows such as "daemon 0%" in the matrix must not be cited in isolation. Percentages are the author's self-assessment with no quantitative source.

> Strategic positioning (user's strategic judgment): in the era of large models, code-generation capability is being commoditized; what is truly scarce is **the throughput of compile / verify / run feedback**. SA/SAB's core competitiveness should be **"when AI multi-agent systems generate code concurrently, can the compiler and verifier withstand high-frequency feedback?"**
>
> In one sentence: **AI can write code, but the toolchain determines how many times AI can trial-and-error.**

This document gives the current true support level based on **code-level verification** of `sci/src` (not documentation claims) and breaks the gaps down into an executable development plan. Verification date: 2026-07-11. Verification method: directly reading the implementations of `src/cli.zig` / `src/flattener.zig` / `src/referee.zig` / `src/sab.zig` / `src/emit_llvm_llvmc.zig`, together with the `Command` enum and actual run behavior; no unverified percentage is trusted.

---


> **Implementation update (2026-07-11, three pillars landed)**: `sa check` + verdict cache, full daemon argv/client, generation cancel / per-agent quota, `--affected` call-graph selection, and the 10-agent bench (`tools/agent_bench.sh`) have been merged into mainline. The 0%/5% entries in the historical matrix below are superseded by the code after this section; Phase F (contract CLI / multi-language SAB / distribution) has not been done.
>
## 0. Conclusion at a glance (capability matrix)

Verifying item by item against the agent-native features listed in the strategic description:

| # | Feature | Strategic requirement | Current true status (code-verified) | Completion |
|---|---------|-----------------------|--------------------------------------|------------|
| 1 | Structured JSON diagnostics | machine-readable, stable error codes | ✅ `--json` global flag genuinely implemented; stable codes such as `SA-FLAT-001/SA-REF-010/011` exist in `cli.zig` | **~85%** |
| 2 | `explain`/`fix`/`skills` subcommands | agent self-learning / repair planning | ✅ all three commands genuinely exist in the `Command` enum, with `--json` | **~80%** |
| 3 | `graph`/`size`/`layout --json` | blast radius / size analysis | ✅ commands exist; `graph` dependency/call graph, `size` function-level size | **~70%** |
| 4 | Compile-time token / gas metering | `compile_tokens`/`instruction_count` | ⚠️ design complete in docs, metrics fields partially present in code, not fully wired | **~40%** |
| 5 | File-level incremental cache | avoid full rebuild after changes | ✅ enabled by default (`--no-incremental` disables); `build-obj-incremental` reuses per-function `.o`, keyed by mtime+size+sha256 | **~70%** |
| 6 | **Function-level incremental SAB delta** | recompile only changed functions | ❌ none. Cache is at file/artifact granularity, not function-body-granularity delta | **~15%** |
| 7 | **Incremental Referee (summary hash reuse)** | don't re-verify unchanged functions | ❌ no function-body-hash / effect-summary / capability-hash reuse mechanism | **~5%** |
| 8 | **Selective test execution** | run only affected tests | ❌ no test dependency graph / affected-test selection; `--jobs` only parallelizes already-selected tests | **~10%** |
| 9 | **Daemon / server resident mode** | agents connect to a resident service, no process restart | ❌ no `daemon`/`watch`/`serve` compile entry (`serve` appears only in plugin context, not as a compile daemon)〔corrected 2026-11-05: overturned by the implementation update at the top of this document — `daemon` is now a top-level command in the cli.zig `Command` enum, and daemon_client/daemon_cancel are in the repo〕 | **0%** (outdated, see correction) |
| 10 | **Cancellable jobs** | cancel stale tasks | ❌ no job scheduler / cancellation | **0%** |
| 11 | **Speculative / branch-aware compilation** | multiple candidates sharing a base cache | ❌ no branch delta mechanism | **0%** |
| 12 | Resource isolation / scheduler | per-agent quota, priority queue | ❌ none; `--jobs N` is merely in-process parallelism | **~5%** |
| 13 | Fast layered failure | Syntax<5ms … Referee<50ms layered rejection | ⚠️ staged errors exist with early rejection, but no explicit latency budget / layered SLA | **~50%** |
| 14 | Multi-language unified SAB (TS/RS/SLA→SAB) | unified incremental build graph | ⚠️ SLA→SAB mature; RS→SAB not seen; unified build graph not built | **~30%** |
| 15 | SAB distributed/module-level compilation | module-level parallelism + cache | ⚠️ design in `sab_distributed_compilation.md` complete; 21 `module`-related occurrences in code, but module-level SAB cache pipeline not landed | **~25%** |

**Verification takeaways:**
- Three high-quality design documents already exist: `agent_first_toolchain.md`, `multi_agent_workflow_cn.md`, `sab_distributed_compilation.md`. **Design runs far ahead of implementation.**
- The `sa contract freeze` / `sa func verify` / `sa func emit` / `sa coordinate` / `sa link --contract` claimed in `multi_agent_workflow_cn.md` **all do not exist in the `Command` enum** (zero matches each). These are pure design, not yet implemented.
- `@reserved` / `@stub` source declarations are not recognized by the parser/flattener.

**Overall judgment:**
- **Single agent interaction layer (JSON/explain/fix/skills/graph/size): truly ~75%, the current biggest highlight.**
- **Concurrency / incremental / feedback-throughput layer (daemon / function-level incremental / incremental Referee / selective tests / cancellable / speculative compilation): truly ~10%. This is exactly the core of the strategic positioning, yet it is the biggest gap today.**

That is: **"the agent can understand the compiler" is essentially achieved; "the compiler can withstand N agents doing high-frequency concurrent trial-and-error" is almost starting from zero.**

---

## 1. Current state in detail (code evidence)

### 1.1 Already available (verifiable)

- **Global `--json`**: `cli.zig:hasJsonFlag` + `--json` help entries in each subcommand. Diagnostics are machine-parsable.
- **Stable error codes**: `cli.zig:1472+` has a mapping table with `SA-FLAT-001` (ForbiddenSyntax), `SA-FLAT-050` (ImportResolutionFailed), `SA-REF-010` (RegisterRedefinition), `SA-REF-011` (UnknownRegister), etc.
- **Agent subcommands**: the `Command` enum contains `explain`, `fix`, `skills`, `graph`, `size`, `layout`.
- **File-level incremental cache**: enabled by default. `BuildCacheKind.build_obj_incremental` reuses per-function `.o`; `SourceTreeHashCacheEntry` determines invalidation by (mtime, size) + sha256.
- **Parallel emit**: `emit_llvm_llvmc.zig` uses `std.Thread.spawn` to launch `emitWorker`, enabling codegen-unit parallelism when `--jobs>1` and the number of functions is ≥100.
- **Import source cache**: `flattener.zig` has `import_source_cache` / `expanded_import_cache` (with mutex, tick, hit counts), reusing import-expansion results across compilations.

### 1.2 Key gaps (strategically core, yet missing)

1. **No daemon**. Every agent invocation is a cold-start process. 20 agents = 20 process cold starts + caches cannot be fully reused across processes (existing caches are mostly in-process statics + on-disk artifacts).
2. **Incremental granularity is the file, not the function**. Changing one function still triggers reprocessing of the compilation unit containing that file; there is no path that "only parses/lowers/emits/verifies this one function + affected call edges".
3. **Referee has no incrementality**. No function-body-hash / type-layout-hash / capability-hash / effect-summary. Every verification is full, and with N agents concurrently the cost scales linearly.
4. **No test selectivity**. No test dependency graph; changing `can_access()` drags in `parser` tests. `--jobs` merely runs already-selected tests in parallel; it does not shrink the test set.
5. **No job scheduling / cancellation / quotas**. Stale tasks (agent has generated v2 but is still waiting on v1) cannot be cancelled; there are no per-agent memory/concurrency quotas, and multiple agents can easily blow up the machine (the local 3.5 GB / no-swap machine has repeatedly OOM'd — direct evidence of this risk).

---

## 2. Development plan (phased, ordered by "feedback throughput" benefit)

Design principle: **first eliminate the two biggest amplifiers — cold start and full verification — then do function-level incrementality and scheduling.**

### Phase A — resident daemon + inter-process cache reuse (highest leverage)

**Target KPI: reduce the cold-start cost of N agents from O(N) to O(1), with cache hits across requests.**

- `sa daemon` (new `Command`): resident service maintaining in-process AST/import/SAB/Referee caches.
- Simple local protocol (Unix socket + JSON line protocol, reusing the existing `--json` diagnostic model).
- Request types: `build` / `check` / `test` / `explain` / `cancel`.
- CLI thin client: `sa build --daemon` prefers connecting to the daemon, falling back to in-process on failure.
- Migrate existing static caches (`import_source_cache`, `source_tree_hash_cache`) into caches shared for the daemon's lifetime, naturally reused by multiple agents.

**Acceptance**: in a 10-agent benchmark (see §3), daemon mode reduces P50 feedback latency by ≥5× relative to cold-start mode.

**Landing document**: expand `agent_first_toolchain.md` with a "§5 Daemon mode" section. The complete executable protocol specification for Phase A (process model / wire protocol / execution path reusing `executeWithWritersAndOptions` / cache migration / acceptance criteria) is in `agent_daemon_protocol_cn.md`.

### Phase B — function-level content hash + incremental Referee

**Target KPI: zero re-verification for unchanged functions; verification cost of changing one function drops from O(module) to O(1 + call edges).**

- In `sab.zig`, compute a stable content hash for each function body (instruction stream + constants + type layout). The existing `writeOptionalHash`/`readOptionalHash` infrastructure can be extended to per-function.
- `referee.zig` outputs and caches a per-function summary:
  ```json
  {"function":"can_access","hash":"...","effects":[],"borrows":"ok",
   "capabilities":[],"verified":true}
  ```
- Before verification, check the summary cache: hash hit → skip; miss → verify and write back.
- Affected set: only re-verify functions whose body hash changed + their direct call edges (layout/capability dependencies).

**Acceptance**: after changing a single function, the Referee phase time of `sa check` is decoupled from project size (approximately constant).

**Landing document**: refine §3.2/§3.3 of `sab_distributed_compilation.md` (cache and cross-module verification protocol) to function level, and add an "incremental Referee summary format" subsection.

### Phase C — selective test execution

**Target KPI: changing `can_access()` runs only policy tests, not parser tests.**

- Build a test → function coverage dependency graph (can reuse Phase B's call graph).
- `sa test --affected`: run only tests with a dependency edge to changed functions.
- Maintain a test-result cache in the daemon (invalidated by hashes of the functions covered).

**Acceptance**: the number of tests triggered by a single-function change is bounded by the test closure that references that function, not the full suite.

### Phase D — job scheduler / cancellation / quotas (multi-agent resilience)

**Target KPI: the machine is not overwhelmed when N agents run concurrently; stale tasks are cancelled.**

- Daemon built-in scheduler: `max_parallel_{parse,lower,referee,emit}`, `max_memory_mb`, `per_agent_quota`, `priority_queue`, `dedupe_same_job`, `cancel_stale_jobs`.
- Cancellable compilation: requests carry `agent_id` + `generation`; when a new generation from the same agent arrives, in-flight tasks of the old generation are cancelled.
- Backpressure: over-quota requests are queued rather than OOM (directly addressing the measured OOM risk of 3.5 GB / no swap on this machine).

**Acceptance**: under a 50-agent stress test, peak memory is bounded, no OOM, and stale-task cancellation rate is observable.

### Phase E — layered-failure SLA + completion of token metering

- Set an explicit latency budget for each rejection stage and output measured time in `--json`: Syntax<5ms / Resolve<10ms / Layout<20ms / Capability<20ms / Referee<50ms.
- Complete full wiring of `compile_tokens` / `instruction_count` (a Phase 4 feature, currently ~40%).

### Phase F (long term) — multi-language unified SAB build graph + distribution

- RS→SAB front end (`sa_plugin_rs`) plugged into a unified SAB incremental build graph.
- Land module-level parallelism + cross-module SAB cache from `sab_distributed_compilation.md`.
- Land `contract freeze/diff` / `func verify/emit` / `link --contract` from `multi_agent_workflow_cn.md` into the `Command` enum (currently all pure design).

---

## 3. Recommended MVP: not hello world, but a concurrency benchmark

Per the strategic description, the MVP should directly prove "resistance to concurrency" rather than "can compile":

```text
Simulate 10 agents each changing a rule_NN.sla / rule_NN.rs
Compare:
  A) cold-start full: 10 × cold-start process × full check/test    → queuing/maxed out
  B) daemon + function-level incremental + affected-test           → shared cache + re-verify only changed functions
Metrics: concurrent jobs/sec, P50/P99 feedback latency, peak memory, cache hit rate,
         cancelled stale jobs
```

**Public metrics table** (the daemon should be able to emit these via `--json`):
`cold_compile_ms` / `incremental_compile_ms` / `sab_emit_ms` / `referee_verify_ms` /
`wasm_emit_ms` / `test_feedback_ms` / `concurrent_jobs_per_sec` /
`peak_memory_mb_under_N_agents` / `cache_hit_rate` / `cancelled_stale_jobs`.

Among these, **`concurrent_jobs_per_sec`** is the new number-one metric of the agent era.

---

## 4. Integrity note

- The "completion %" figures in this document come from code verification, not from `tasks.md`'s self-claims. The three existing design documents are of high quality, but **design ≠ implementation**: many claimed CLI commands do not exist in the `Command` enum.
- The single-interaction layer (§1.1) is a real and solid engineering achievement and can serve as a ready protocol base for the daemon.
- The strategically core concurrency/incrementality/throughput layer (§1.2) is essentially blank — this is both the biggest gap and the biggest opportunity:
  **it determines whether SA has differentiated competitiveness in the AI-agent era.**

---

## Appendix: relationship to existing documents

- `agent_first_toolchain.md` — single-interaction-layer design (mostly implemented). Phase A of this plan adds the daemon to it.
- `multi_agent_workflow_cn.md` — multi-agent protocol + contract freezing (pure design). Phase F of this plan lands its CLI.
- `sab_distributed_compilation.md` — module-level SAB cache/parallelism (pure design). Phases B/F of this plan refine it to function level and land it.
- This document's positioning: **pin down the implementation status of the three designs + re-prioritize by throughput benefit + give a stress-testable MVP.**
