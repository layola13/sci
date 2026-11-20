# SA Kernel Improvement Evaluation Report (Performance / Security)

> This is the English counterpart of the Chinese document [kernel_improvement_evaluation_cn.md](./kernel_improvement_evaluation_cn.md).

> **Status (2026-11-05 document audit)**: A historical evaluation from 2026-06-15; appendix line counts are snapshots from that time (cli.zig is now 10,894 lines, src totals ~158K lines). The Cranelift backend and `--strict-tags` have still not landed to this day (no corresponding files/flags in src).

> **Assessment date**: 2026-06-15
> **Assessment scope**: only the SA compiler kernel (~36K lines of Zig under `sci/src/`). The plugin directory `/home/vscode/projects/sa_plugins/` is not assessed for now, as it is still under development.
> **Assessment baseline**: tasks.md P0.1–P0.5b completed; progress.md's latest issue6/7/8 micro-optimizations landed.

---

## 1. Honest positioning of the current kernel

**Already done — do not redo (to avoid wasted effort)**

| Landed | Source |
|---|---|
| Register scope localization (solves O(N²) memory explosion) | tasks.md P0.1 |
| Sparse incremental state annotation | tasks.md P0.2 |
| Declaration-level parallel emission (per-decl LLVM modules) | tasks.md P0.4 |
| In-memory direct LLVM-C, bypassing textual IR | tasks.md P0.5 / P0.5a |
| LLVM-C backend covers atomic / fallible / vtable / sys / wasm | tasks.md P0.5b series |
| WASM matrix 110-demo equivalence verification | tasks.md P0.5b-wasm-demo-matrix |
| `StaticStringMap` replaces string concatenation chains | progress.md issue8 Tier-1 |
| Verifier `sig_index_by_name` built once and reused | progress.md issue8 Tier-1 |
| Interpreter label/slot caches (eliminating per-run rebuilds) | progress.md issue8 Tier-1 |
| Binary search over memory blocks (replacing linear scans) | progress.md issue8 Tier-1 |
| `VerifierBufferPool` buffer reuse | progress.md issue8 |
| `DefDict.foldText` single-pass lazy output | progress.md issue8 |
| Expanded-import fragment cache (LRU) | progress.md issue6 IMP-1 |
| `appendFlattenFragment` + `cached_macro_defs` and other incremental foundations | progress.md issue6 |

**This means "the low-hanging fruit has all been picked"; the ROI of all improvements below drops sharply and they need careful selection.**

---

## 2. Performance: what can still be improved, ordered by ROI

### ⭐⭐⭐⭐⭐ 1. Function-level incremental compilation cache (largest single lever)

**Current state**: you are already working on the "expanded-import fragment cache" + `appendFlattenFragment` + `cached_macro_defs`; this is the foundation. But the end-to-end "change one function, recompile only one function" is **not yet wired up**.

**Approach**:
- key on `(function_source_sha256, def_dict_hash, sai_hash)`
- cache `FlattenResult.function_fragment` + `AnnotatedFunction` + the single-function `.o` object
- add a `function_artifact_hash` field to `sa.lock`
- incremental linking via `ld.lld --incremental` or hand-written `.a` repackaging

**Expected benefit**: a one-line change in a 10K-line project drops compilation from ~6s → ~200ms. **This is the key to pushing SA from "Zig speed" to an "interpreted experience".**

**Effort**: 2-3 weeks. The foundation is laid; what remains is engineering assembly + an equivalence test matrix.

**Risk**: cache-invalidation boundaries (macro dependencies, `#def` dependencies, `#loc` line offsets) are easy to get wrong; a "cache on/off equivalence PBT" must be a gate.

---

### ⭐⭐⭐⭐ 2. Multi-tier codegen (bypassing LLVM O3)

**Current state**: the FAQ § performance comparison itself admits "LLVM O3 is a seconds-to-tens-of-seconds bottleneck". The release path cannot avoid it, but the **dev path can completely bypass it**.

**Approach**:

| Command | Backend | Purpose |
|---|---|---|
| `sa run` | Interpreter (already exists) | <1ms startup |
| `sa build --dev` | **Cranelift** (new) | dev iteration, O0, within a second |
| `sa build-exe` | LLVM-C O1 (default) | CI / integration |
| `sa build-exe --release-fast` | LLVM-C O3 | release |

Cranelift codegens a function in ~1ms and can emit ELF/Mach-O/COFF/Wasm directly, with no external linker. Bytecode Alliance itself uses it for wasm runtime JIT.

**Expected benefit**: dev builds from seconds → milliseconds, letting SA's "compilation speed" story genuinely beat Rust in edge/serverless scenarios.

**Effort**: 4-6 weeks. Requires writing `src/emit_cranelift.zig`, but the IR is already three-address code, so the mapping is simpler than LLVM's.

**Risk**: one more backend = one more equivalence test suite = CI time grows linearly. Recommend default off, enabled only with `--dev`.

---

### ⭐⭐⭐ 3. Instruction array → SoA + string deduplication pool

**Current state**: `Instruction` is AoS (array of structs), with fields for op kind / operands / text / atomic meta / upstream_loc. Cache-line utilization is low.

**Approach**:
- split `instructions: []Instruction` into `kinds: []InstKind` (u8) + `operands: []u32x3` + `text_idx: []u32` + `loc_idx: []?u32`
- strings/text go through an interned pool, with operands storing `u32` indices
- verifier hot paths touch only `kinds[i]` and `operands[i]`, fitting 16-32 instructions per cache line

**Expected benefit**: verifier single-thread throughput 500K lines/sec → estimated 1.2-1.5M lines/sec. `AnnotatedInstruction` memory footprint drops 30-40%.

**Effort**: 2-3 weeks. Broad change surface (flattener / verifier / emitter all touched), but the transformation is mechanical.

**Risk**: coordination with the parallel verifier's memory view; diagnostics need on-demand reconstruction.

---

### ⭐⭐⭐ 4. Full function-level verifier parallelism + work stealing

**Current state**: `ParallelVerifyJob/Worker` already exists, but need to confirm: (a) is scheduling granularity function or file? (b) is there work stealing? (c) memory contention?

**Approach**:
- work unit = function, not file
- `std.Thread.Pool` + lock-free MPMC queue + work stealing (refer to Zig's own `ThreadPool`)
- per-worker independent `VerifierBufferPool` to reduce cache-line ping-pong

**Expected benefit**: ~25-30× verifier throughput on a 32-core machine (Amdahl-limited). Verification of a 10K-function project drops from ~200ms → ~10ms.

**Effort**: 1-2 weeks (provided `Referee` itself is already function-local, which from P0.1 it is).

---

### ⭐⭐ 5. Further WASM emitter size reduction

**Current state**: 48KB for hello world is already leading, but can be smaller.

**Approach**:
- move dead-code elimination earlier to the IR layer (not relying on wasm-opt)
- deduplicate strings/constants inside the emitter
- compress custom sections (optional compression for DWARF-in-WASM)
- multi-function outlining: identify function templates with identical bit patterns and emit once

**Expected benefit**: hello ~48KB → ~20KB; medium applications shrink 30-50%.

**Effort**: 2-3 weeks.

---

### ⭐⭐ 6. JIT-ify the interpreter

**Current state**: `interp.zig` is 2,330 lines, a big switch dispatch.

**Approach**: use Cranelift to JIT-compile hot functions, triggered by a threshold; cold code continues to be interpreted.

**Expected benefit**: 5-20× speedup for `sa run` in compute-heavy scenarios; slightly higher startup latency.

**Effort**: 3-4 weeks. Has synergy with the Cranelift backend.

**Low priority**: `sa run` is mainly for dev / sandbox use, where fast startup matters more than steady-state throughput. Recommend doing this after Tier 2.

---

## 3. Security: what can still be improved, ordered by ROI

### ⭐⭐⭐⭐⭐ 1. Formal verification of Referee (Coq/Lean4)

**Current state**: the FAQ and design.md §6 Properties 1-32 already spell out the correctness properties; the R33 Coq proof is on the roadmap but **has not been started**.

**Approach**:
- translate `referee/table.zig` (only 293 lines) into a Coq inductive definition
- define "bitmask state transitions" as small-step semantics
- prove 4 core properties: Progress, Preservation, NoMemoryLeak, NoUseAfterMove
- extract a reference implementation from Coq and differential-test it against the Zig implementation

**Expected benefit**:
- this is the only hard moat that Rust **cannot replicate** for SA
- once done, it can be printed on all promotional material: "SA is the first high-level language whose Referee is mathematically proven sound"
- directly opens up aviation / medical markets

**Effort**: 3-6 months (requires someone who knows Coq). But with ≤2500 lines, Referee is the world's **most formalization-friendly borrow checker**, more practically feasible than Rust's.

**Risk**: cannot find someone to do it; discovering midway that the Property descriptions have gaps with the implementation (which is actually a big win).

---

### ⭐⭐⭐⭐ 2. `--strict-tags` type-confusion guardrail

**Current state**: design.md §1.5 / FAQ § high-reliability list this as **SA's largest current security gap** — "mistaking an f64 coordinate for an i32 flag bit, Referee does not block it". On the v0.5 roadmap.

**Approach**:
- `alloc N tag <Name>` syntax (already designed)
- verifier checks the legality of the `(tag, off, T)` triple on `load r+off as T`
- `#tag <Name> { field: T @ +N }` declared in `.sal`
- `--strict-tags` flag forces it on globally

**Expected benefit**: upgrades SA from "memory safe" to "memory safe + type-unconfused". Directly closes the only semantic gap with Rust's safe subset.

**Effort**: 3-4 weeks. Tag metadata must thread from `.sal` all the way to the verifier table; moderate change surface.

---

### ⭐⭐⭐⭐ 3. Cross-function / FFI-boundary contract consistency check

**Current state**: FAQ § "why no lifetime" itself admits this is SA's **safety lower-bound gap**: "cross-function borrow safety is guaranteed by the frontend; if the frontend degrades incorrectly, you get a segfault at runtime". `libsa_scope` is only a helper, it does no global verification.

**Approach**:
- add a link-time pass (not in Referee, but in the linker driver)
- scan all `.sai` contracts + all `@extern` call sites
- verify: ownership prefixes (`^`/`&`/value) are consistent between caller and implementation
- add a `--link-check` flag to `sa build-exe`
- add `contract_consistency_hash` to `sa.lock`

**Expected benefit**: closes SA's "known gap". That caveat can be deleted from the docs.

**Effort**: 2-3 weeks. Does not affect hot paths (one-time at link time).

---

### ⭐⭐⭐ 4. Differential fuzzing (interp ↔ llvm-bc ↔ wasm)

**Current state**: you already have the `wasm-matrix` 110-demo equivalence matrix (P0.5b-wasm-demo-matrix), but those are fixed demos, not fuzz-generated.

**Approach**:
- write an SA program generator (based on EBNF + type/ownership constraints)
- run via `zig build fuzz-diff`: interp output vs LLVM bc output vs wasm output, all three must be byte-equal
- any divergence = automatic minimization + entry into the regression library

**Expected benefit**: catches semantic drift in emit backends / interp; this kind of bug is almost impossible to catch with test cases alone.

**Effort**: 3-4 weeks. The generator is the core difficulty.

---

### ⭐⭐⭐ 5. Trap diagnostic precision audit

**Current state**: progress.md mentions that before `snapshotFirstMismatch` there was a diagnostic bug where "slot vs globalId misalignment caused the wrong register name in the error"; may not be an isolated case.

**Approach**:
- write a "deliberately triggering" minimal sample for each Trap kind
- verify that `TrapReport`'s `register / source_line / upstream_loc / hint` are all precise
- add to CI gate

**Expected benefit**: improves the 1-shot success rate of the LLM self-repair loop. Directly converts into the selling-point number "writing code in SA is easier than in Rust".

**Effort**: 1 week (mechanical work).

---

### ⭐⭐⭐ 6. Capability mask extension review

**Current state**: design.md §4.2 is 9 bits. The FAQ itself mentions no plan to extend (§4.9).

**But need to review**:
- does it cover timing channels (constant-time execution declarations)?
- does it distinguish `unsafe_raw_ptr_read` from `unsafe_raw_ptr_write`?
- does it mark `floating_nondeterminism` (IEEE floating-point non-associativity, etc.)?

**Recommendation**: do not extend, but the docs must explicitly state "these 9 bits do not cover side channels / floating point / timing channels", to avoid over-promising.

---

### ⭐⭐ 7. Gas metering boundary audit

**Current state**: Property 11 requires `max_instruction_steps` to be a provable upper bound. But what is the coverage of loop-bound inference?

**Approach**:
- list the bounded-loop patterns currently recognized (`for i in 0..N`, while + strictly decreasing induction variable)
- list the patterns that get marked `unbounded`
- add tests for boundary cases

**Expected benefit**: avoids "claiming bounded when actually unbounded". Critical for the Gas-limit promise in edge/serverless scenarios.

**Effort**: 1-2 weeks (audit + adding tests, no algorithm changes).

---

### ⭐⭐ 8. Determinism guarantee for parallel / incremental compilation

**Current state**: P0.4 already does parallel emission; future P1 is incrementality.

**Approach**:
- golden rule: "same input ⇒ byte-identical output", including wasm / .o / `.sa.bc`
- add CI: run the same demo 100 times and diff the outputs
- run parallel vs serial and diff the outputs

**Expected benefit**: `sa pkg`'s "machine-code SHA-256" only then becomes meaningful; otherwise all of sa.lock's promises collapse.

**Effort**: 1 week (if already being done; if there is no CI gate yet, it must be added immediately).

---

## 4. Not recommended (high cost, low value)

| Idea | Why not |
|---|---|
| Add a type system to SA | directly violates the "no type system" philosophy; `--strict-tags` already covers the core need |
| Full-function NLL borrow graph | Rust has already walked this path; complexity explodes; SA's O(1) advantage would disappear |
| Add `mut` / `&mut` syntax | same as above, violates the design |
| Rewrite Referee in SIMD | already O(1) bit operations; SIMD rewrite has small benefit and large complexity |
| Hand-write a linker to replace `zig cc` | `zig cc` is already the simplest solution; hand-writing = maintenance hell |
| Split cli.zig's 6,967 lines | a large file does not affect runtime performance; splitting is laborious and bug-prone |

---

## 5. Recommended "next-quarter set of three"

If only three things can be picked (by strategic value, not by effort):

| # | Task | Strategic value | Effort |
|---|---|---|---|
| 1 | **Function-level incremental compilation cache** | turns SA's "compilation speed" from a paper advantage into a demonstrable dev loop | 2-3 weeks |
| 2 | **`--strict-tags` landing** | closes the only semantic gap with Rust's safe subset | 3-4 weeks |
| 3 | **Start Referee Coq formalization** | the only non-replicable moat, the high point of the narrative | 3-6 months (long term, but start now) |

Plus one **must-do hygiene item**: **a CI gate for byte-determinism of parallel/incremental output** (1 week). This is the prerequisite for sa.lock's SHA anchoring to be trustworthy; without it all other security claims collapse.

The remaining six items (Cranelift dev tier / SoA / fully parallel verifier / WASM compression / fuzzing / cross-function contracts / Trap diagnostic audit / Gas boundaries / Capability docs) serve as backlog, prioritized by user feedback.

---

## 6. One-sentence conclusion

**The dividend period for major kernel changes is over; we have entered the "polishing phase".** What can still generate real strategic value is not making hot paths 20% faster, but:

1. **Formal verification** (to obtain an unreplicable moat)
2. **Function-level incremental compilation** (to make "fast" a perceptible experience)
3. **`--strict-tags`** (to close the last gap with Rust safe)

The remaining micro-optimizations and small fixes queue up by ROI; there is no need to worry "it's already too late if we don't do it now".

---

## Appendix: kernel file list referenced during the evaluation

| File | Lines | Role |
|---|---|---|
| `src/flattener.zig` | 7,231 | text scanning, macro expansion, `#loc`, `#def`, function signatures |
| `src/cli.zig` | 6,967 | CLI subcommands, build driver |
| `src/verifier.zig` | 5,885 | Referee core, bitmasks, Phi merge, atomic ordering |
| `src/plugins.zig` | 3,532 | plugin discovery and manifest parsing |
| `src/interp.zig` | 2,330 | `sa run` in-memory interpreter |
| `src/emit_llvm_llvmc.zig` | 1,696 | LLVM-C in-memory direct emitter |
| `src/flattener/line_classifier.zig` | 1,045 | single-line 16-form classifier |
| `src/llvm2sa.zig` | 917 | bitcode → SA reverse translation (conservative subset) |
| `src/common/signature.zig` | 796 | function signature table |
| `src/common/trap.zig` | 595 | TrapReport data structure |
| `src/common/const_decl.zig` | 582 | `#def` / `@const` |
| `src/lowerer.zig` | 518 | IR lowering helpers |
| `src/referee/call.zig` | 436 | call-site ownership contract |
| `src/common/atomic.zig` | 394 | atomic ordering lattice |
| `src/common/instruction.zig` | 378 | Instruction / InstKind |
| `src/libsa_scope.zig` | 365 | frontend degradation helper |
| `src/flattener/def_dict.zig` | 350 | `#def` dictionary expansion |
| `src/referee/table.zig` | 293 | **Referee state-transition table (formalization target)** |
| `src/common/capability.zig` | 100 | CapabilityMask |
| `src/common/gas.zig` | 29 | Gas counting |

Kernel total ~36,000 lines of Zig (excluding plugins, excluding the runtime `sa_std.zig` 8,179 lines, excluding `sa_net_uring.zig` 2,485 lines).
