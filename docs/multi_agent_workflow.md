# SA Multi-Agent Concurrent Development Protocol (Draft)

> This is the English counterpart of the Chinese document [multi_agent_workflow_cn.md](./multi_agent_workflow_cn.md).

> **Document version**: v0.1 draft / 2026-06-15
> **Status**: specification only, no implementation code [2026-11-05 re-check: the draft has not been implemented — none of this document's five CLIs (contract/func/link/coordinate, etc.) nor `@reserved`/`@stub` have landed, and there are no corresponding entries in the top-level command table]
> **Target readers**: SA kernel developers, external plugin / business project users, multi-LLM agent coordinators
> **Related documents**:
> - [`design.md §3.1`](./design.md) source text protocols (`.sa` / `.sai` / `.sal`)
> - [`design.md §3.10`](./design.md) package management and `sa.lock`
> - [`faq.md`](./faq.md) "why is there no X" design philosophy
> - [`agent_first_toolchain.md`](./agent_first_toolchain.md) Agent-First CLI / `--json`
> - [`kernel_improvement_evaluation_cn.md`](./kernel_improvement_evaluation_cn.md) kernel improvement evaluation

---

## 1. Abstract

**Problem**: when multiple LLM agents concurrently write SA code, they still hit the traditional software-engineering dependency bottleneck of "A must finish before B can start", and cannot reach the expected fully parallel development speed.

**Diagnosis**: the physical upper bound on concurrency is the **number of topology layers in the interface dependency graph**, not the number of agents. Any concurrency scheme that does not eliminate interfaces will eventually get stuck on some A → B chain.

**Solution**: a three-phase protocol — **contract freeze → topology layering → function-level commit** — restructuring "unordered full concurrency" into "short serial contract + large parallel implementation + incremental commit". Leveraging SA's unique capabilities such as function-local Referee, physical separation of `.sai`/`.sal`, and SHA-256 pinning, the concurrency ceiling is raised to near the theoretical limit.

**This specification introduces no new keywords, does not change SA's five-symbol contract, and does not modify the Referee physical model**; it only defines:

1. The three-phase flow for multi-agent collaboration
2. The interface specification of five new CLI subcommands (`sa contract freeze` / `diff` / `lock` / function-level emit / coordinator scaffolding)
3. The syntax and semantics of two new declarations, `@reserved` / `@stub`
4. The contract-drift handling protocol
5. Function-level commit and conflict-resolution rules

The implementation effort is about 2.5 person-months, concentrated in the kernel CLI layer (without touching the Flattener / Referee core).

---

## 2. Problem diagnosis

### 2.1 Six classes of natural synchronization points

Even with Referee being function-local and emit being declaration-level parallel, **writing** still has the following non-eliminable dependencies:

| Synchronization point | Symptom | Scope of impact |
|---|---|---|
| **Call contract** | Before B writes `call @foo(^x)`, it must know whether A's first parameter of `@foo` is `^` / `&` / value | all callers depending on A |
| **Layout sharing** | Multiple agents all `load entity+Entity_pos as i64` — who decides the offset? | all code that reads/writes that struct |
| **`#def` namespace** | Two agents each define `#def NODE_SIZE = 16` but with different values | cross-file `#def` merge conflicts |
| **`@const` references** | A defines `@const VTABLE_FOO`, B references it in `call_indirect` | indirect calls / vtable dispatch |
| **`grants` permissions** | module-level permissions determine whether B can call A's exposed `@sys_*` | cross-module capability graph |
| **Test / label naming** | Two agents collide on the same `@test "name"` | test assembly / reporting |

**Conclusion**: the six classes of synchronization points together are the "interface". No concurrency protocol can eliminate interfaces; it can only **shrink, freeze, and version** them.

### 2.2 Concurrency-native levers SA already has

| Lever | Source | How to exploit it |
|---|---|---|
| Function-local Referee | tasks.md P0.1 | function = minimal synchronization unit, verification can be independent |
| `.sai` interface contract | design.md §3.1 | physically separate "signature" and "implementation" into different files |
| `.sal` layout contract | design.md §3.1 | physically separate "offset + macro facade" and "usage" into different files |
| SHA-256 pinning | design.md §3.10 / pkg | the same idea can be used to "pin contracts" |
| Declaration-level parallel emit | tasks.md P0.4 | multiple functions codegen simultaneously at a given moment |
| Function-level incremental cache (foundation) | progress.md issue6 IMP-1 | `appendFlattenFragment` is ready |
| Structured Trap JSON | agent_first_toolchain.md | on conflict, machine-readable and machine-fixable for the LLM |

### 2.3 "Fake synchronization killers" SA does not have

Compared with Rust / Scala / Haskell, SA has deliberately given up a batch of sources of cross-function dependency (detailed in the FAQ):

- ❌ Generic constraint solving (the "A implements trait B to compile" kind of 100s-scale latency)
- ❌ Cross-file type inference
- ❌ Lifetime inference
- ❌ Destructor-order dependencies induced by the Drop trait
- ❌ Implicit numeric promotion / impl coherence

**This means that as long as the interface is locked, function implementations really can be independently concurrent.** SA is one of the few languages that can actually deliver on this promise.

---

## 3. Three-phase concurrency protocol

### 3.1 Overview

```
┌─────────────────────────────────────────────────────────┐
│ Phase 0: Contract Freeze                                 │
│   single coordinator agent, serial                      │
│   input: business requirement description               │
│   output: full .sai + .sal + contract.lock (SHA-256)    │
│   duration: minutes (about 3-10 min for a 10K-line project)│
└──────────────────────────┬─────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────┐
│ Phase 1: Topology layering + intra-layer parallel impl   │
│   dependency graph L₀, L₁, ..., Lₖ                      │
│   N agents concurrent within a layer, N = functions in it│
│   each agent sees only .sai + .sal + contract.lock,      │
│     not others' implementations                          │
│   output: .sa body of each function                      │
│   duration: per-layer time = single-function impl time   │
│     (number of layers ≈ 5-10)                            │
└──────────────────────────┬─────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────┐
│ Phase 2: Function-level commit, incremental verify,      │
│          drift negotiation                               │
│   per function: single-function Referee verify (ms-level)│
│   pass → write to cache + sa.lock                        │
│   fail → Trap JSON feedback to agent, self-repair+resubmit│
│   contract drift → coordinator adjudication + affected    │
│     agents rebase                                        │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Phase 0: Contract freeze

**Input**: a business requirement described by a human or an upper-layer agent (a piece of natural language / a spec).

**The single "coordinator agent" is responsible for**:

1. **Decomposing the requirement** into N functions + M structs + K constants / vtables
2. **Writing out the `.sai` signature set**:
   - each function's `@name(params) -> ret:` header
   - ownership prefixes (`^` / `&` / value) must be explicit
   - `@extern` / `@ffi_wrapper` / `@export` must be explicitly marked
   - the `?` suffix (fallible) must be explicit
3. **Writing out the `.sal` layout set**:
   - each struct's `#def *_SIZE` / `#def *_field = +offset` (recommended to generate via the `sa layout` tool)
   - required `[MACRO]` facade declarations
   - vtable slot declarations (without function-body references)
4. **Writing out `contract.lock`**:
   - all `.sai` file paths + per-file SHA-256
   - all `.sal` file paths + per-file SHA-256
   - aggregate `contract_sha256` (a stable hash of all `.sai` + `.sal` byte streams)
   - the function dependency graph (DAG)
   - topology layering result (L₀..Lₖ)
   - capacity information: total function count / layer count / maximum layer width
5. **Validation**:
   - all `.sal` layouts referenced in `.sai` exist
   - all `@const` references have declarations
   - the dependency graph is acyclic (a cycle → the coordinator must re-split)

**Output location**: project root `contracts/<feature-name>/`, containing `*.sai` / `*.sal` / `contract.lock`.

**Boundaries of the coordinator agent**:
- ✅ may write function signatures
- ✅ may write layout constants
- ✅ may write vtable declarations
- ❌ **may not** write function bodies (not even stubs — stubs are written by the implementation agents of phase 1)
- ❌ **may not** implement macro bodies (macro facades are fine; macro bodies are implementation details)

**Irreversibility of contract freeze**:
- once `contract.lock` is generated, phase 1 begins
- if a contract change is found necessary during phase 1 → go through §6 "contract drift negotiation"; never silently modify `.sai`

### 3.3 Phase 1: Topology layering + intra-layer parallel implementation

**Dependency graph layering** (already output in phase 0):

- **L₀** = functions that call no other business functions (leaf functions; may call `sa_std` and `@extern`)
- **Lᵢ** = functions whose every call falls inside ⋃_{j<i} Lⱼ

**Intra-layer scheduling**:
- N functions per layer = N concurrent implementation agents
- each agent receives:
  - its own target function signature (one line in `.sai`)
  - the complete `.sai` set (to see dependency signatures)
  - the complete `.sal` set (to see layouts)
  - `contract.lock`'s `contract_sha256`
  - the function dependency graph (to avoid mistakenly calling undefined functions)

**Agent submission format** (recommended JSON):

```json
{
  "function_name": "parse_route",
  "function_body_sa": "@parse_route(...) -> ...:\nL_ENTRY:\n  ...\n",
  "contract_sha256": "<contract_sha256 output by phase 0>",
  "agent_id": "agent-impl-04",
  "claimed_layer": 2,
  "depends_on": ["@parse_path", "@trim_whitespace"],
  "macros_used": ["DROP_AND_RETURN", "ASSERT_EQ"],
  "consts_used": ["VTABLE_ROUTER"],
  "elapsed_ms": 4321
}
```

**Inter-layer barrier**:
- when a whole layer completes → the coordinator triggers an "intra-layer verification batch"
- all pass → proceed to the next layer
- any failure → that function's agent rebases and retries; other functions continue to the next layer (no blocking)

### 3.4 Phase 2: Function-level commit, incremental verification, drift negotiation

**Single-function verify**:
- input: the function's `.sa` body + `.sai` / `.sal` under the same `contract_sha256` + cached lower-layer functions that already passed
- call `sa func verify <func_name>.sa --contract contract.lock` (§4.3)
- output: Pass / Trap JSON

**Pass path**:
1. write to `cache/functions/<func_sha>.{sa,o,annotated.json}`
2. update the project `sa.lock`:
   ```toml
   [functions.parse_route]
   function_sha256 = "..."
   contract_sha256 = "..."
   object_sha256 = "..."
   committed_by = "agent-impl-04"
   ```
3. notify all upper-layer agents waiting on that function

**Failure path**:
1. return structured Trap JSON (already available from agent_first_toolchain.md)
2. on receipt, the agent **retries at most K times** (default K=3)
3. all K failures → escalate to the coordinator, possibly triggering contract-drift negotiation (§6)

**After all layers complete**:
- the coordinator triggers a "full link": `sa link --contract contract.lock --cache cache/`
- incrementally links all `.o`
- full Referee pass (already-verified functions are scanned again to ensure inter-function consistency — extremely fast, pure metadata check)
- final artifacts: executable / WASM / `.a`

---

## 4. Specification of five new CLI subcommands

> **Design principle**: the CLI does not change the Flattener / Referee / Emitter core; it only adds subcommands wrapping existing capabilities.

### 4.1 `sa contract freeze`

**Purpose**: freeze the output of phase 0.

**Usage**:

```
sa contract freeze <input-dir> [--out <out-dir>] [--json]
```

**Input**: a directory containing `.sai` and `.sal`.

**Output file**: `<out-dir>/contract.lock`, recommended in TOML format (readable + machine-parsable):

```toml
schema = "sa.contract/1"
contract_sha256 = "<aggregated hash>"
generated_at = "2026-06-15T10:30:00Z"
generator = "agent-coordinator-v1"

[[sai_files]]
path = "contracts/router/router.sai"
sha256 = "..."
functions = ["parse_route", "match_route", "build_router"]

[[sal_files]]
path = "contracts/router/router.sal"
sha256 = "..."
layouts = ["Route_SIZE", "Router_SIZE"]
consts = ["VTABLE_ROUTER"]
macros = ["ROUTE_INIT", "ROUTE_CLEANUP"]

[dependency_graph]
"parse_route" = []
"trim_whitespace" = []
"match_route" = ["parse_route", "trim_whitespace"]
"build_router" = ["match_route"]

[topology]
layers = [
  ["parse_route", "trim_whitespace"],
  ["match_route"],
  ["build_router"]
]
max_layer_width = 2
total_functions = 4
```

**`--json` mode**: the same information is output to stdout as JSON for direct consumption by the coordinator agent.

**Errors**:
- `ContractCycle`: the dependency graph has a cycle
- `MissingLayout`: `.sai` references an undeclared layout
- `MissingConst`: `.sai` references an undeclared `@const`
- `DuplicateSignature`: two `.sai` files declare a function with the same name

### 4.2 `sa contract diff`

**Purpose**: detect contract changes during phases 1/2 and trigger agent rebase.

**Usage**:

```
sa contract diff <old.lock> <new.lock> [--json]
```

**Output** (human-readable form):

```
Contract diff: contract_a → contract_b

CHANGES (1):
  ~ contract_sha256: aaa... → bbb...

FUNCTIONS:
  + added:    @parse_v2(s: ptr, len: u64) -> ptr
  - removed:  @parse_legacy
  ~ changed:  @foo  [BREAKING]
              param 0: ^x → &x

LAYOUTS:
  ~ Route_SIZE:  32 → 40  [BREAKING for L2+]
  + added field: Route_method @ +24
  ~ moved field: Route_path  +16 → +20  [BREAKING]

CONSTS:
  ~ VTABLE_ROUTER: 3 slots → 4 slots  [BREAKING for callers using slot 3]

GRANTS:
  + module router: added [net_tx]

AFFECTED FUNCTIONS (8):
  @match_route       (depends on @foo signature)
  @build_router      (depends on Route layout)
  @route_dispatch    (depends on VTABLE_ROUTER)
  ...
```

**`--json` mode**: structured output listing `breaking_changes[]` / `affected_functions[]` / `recommended_rebase_layers[]`.

### 4.3 `sa func verify` / `sa func emit`

**Purpose**: function-level commit entry points for phase 2.

**Usage**:

```
sa func verify <func.sa> --contract <contract.lock> [--json]
sa func emit   <func.sa> --contract <contract.lock> --out <func.o> [--cache <dir>]
```

**Responsibilities**:
- `verify`: run a single function through Flattener → Referee; no emit. Returns pass / Trap JSON.
- `emit`: run a single function through Flattener → Referee → LLVM-C → `.o`; on cache hit, copy directly.

**Cache-hit conditions** (all required):
1. `function_sha256` matches
2. `contract_sha256` matches
3. the `object_sha256` list of dependent functions all match
4. the compiler version matches

**Output**:

```json
{
  "function_name": "parse_route",
  "function_sha256": "...",
  "contract_sha256": "...",
  "object_sha256": "...",
  "instructions_emitted": 142,
  "gas_max_steps": "bounded(580)",
  "compile_tokens": 5230,
  "cache_hit": false,
  "elapsed_ms": 38
}
```

**Relationship to existing P0.4 / P0.5**:
- P0.4's per-declaration parallel emit is "parallelizing multiple functions within one process"
- this command is "multiple processes / multiple agents each emitting one function" — finer-grained but with slightly higher IPC cost

### 4.4 `sa link --contract`

**Purpose**: final linking at the end of phase 2.

**Usage**:

```
sa link --contract <contract.lock> --cache <dir> --out <output> \
        [--target exe|wasm|obj|wasm-wasi]
```

**Responsibilities**:
- collect `cache/functions/*.o`
- verify that the `function_sha256` corresponding to each `.o` matches the version recorded in `contract.lock`
- full-function metadata consistency check (call contracts / layout offsets / vtable references)
- call `zig cc` to link into the final artifact

**Errors**:
- `CacheStaleObject`: the contract corresponding to the cached `.o` has changed
- `MissingFunctionImpl`: declared in the contract but no implementation
- `ContractDriftAtLink`: a function's declared contract is inconsistent with the lock

### 4.5 `sa coordinate` (coordinator scaffolding)

**Purpose**: end-to-end orchestration of phases 0/1/2. Serves as a reference implementation; the community is encouraged to write smarter versions of its own.

**Usage**:

```
sa coordinate plan --req <requirement.md> --out <plan.json>
sa coordinate dispatch <plan.json> --workers <N>
sa coordinate reconcile --commits <dir>
sa coordinate status  [--json]
```

**`plan`**: call an LLM / agent to generate `.sai` / `.sal` drafts from the requirement (not frozen).

**`dispatch`**: distribute each layer's tasks to N worker agents (worker interface conventions in §5).

**`reconcile`**: aggregate all agents' function commits, trigger verify + link.

**`status`**: current progress (lists of completed / pending / blocked functions).

**Implementation**: recommended to first implement as Python / Bash scripts as a reference impl; not in the Zig kernel.

---

## 5. Two new source declarations

### 5.1 `@reserved`

**Syntax**:

```
@reserved <function_name>(<params>) -> <ret>
```

or:

```
@reserved <const_name> = <type>
```

**Semantics**: a placeholder declaration. Referee treats it as "known to exist" when checking callers and does not require an implementation to exist. Only at the linker stage is it checked that "a reserved must have a corresponding `@stub` or real implementation".

**Use case**:

```sa
// written by the phase 0 coordinator:
@reserved @parse_route(s: ptr, len: u64) -> ptr
@reserved @match_route(&router: ptr, path: ptr, path_len: u64) -> u64
```

The phase 1 implementation agent replaces `@reserved` with the real implementation.

### 5.2 `@stub`

**Syntax**:

```
@stub @<function_name>(<params>) -> <ret>:
    panic(SA_STUB_NOT_IMPLEMENTED)
```

**Semantics**: compilable, linkable, runnable (running immediately panics). Lets upper-layer functions still build and run tests when lower layers are unimplemented.

**Use case**:

```sa
// submitted by agent in phase 1, awaiting a lower-layer function:
@stub @match_route(&router: ptr, path: ptr, path_len: u64) -> u64:
L_ENTRY:
    panic(SA_STUB_NOT_IMPLEMENTED)
```

**Constraints**:
- `@stub` functions in the compiled artifact count toward `tainted_stub_count`
- `--release-fast` mode rejects projects containing `@stub` (forcing implementation)
- `sa.lock` records which functions are stubs, making it easy for CI to gate

### 5.3 Compatibility with existing syntax

- `@reserved` / `@stub` are new members of the existing `@` modifier family (alongside `@extern` / `@export` / `@ffi_wrapper` / `@test`)
- Flattener adds one new `LineKind`, without affecting the other 16 forms
- Referee adds one special case: "stub allowed at exit if SA_STUB_NOT_IMPLEMENTED panic"
- no new keywords introduced, five-symbol contract not broken

---

## 6. Contract drift negotiation protocol

### 6.1 When it triggers

During phases 1/2, it is discovered that the contract must change. Three sources:

1. **Implementation agent self-initiated**: while writing the implementation it finds the signature unreasonable (e.g. a parameter should be `&` rather than `^`)
2. **Referee feedback**: the implementation agent's submitted function is rejected, with the Trap pointing to a contract inconsistency
3. **External requirement change**: a human adds/modifies requirements

### 6.2 Drift flow

```
1. Drift requester (agent or human) submits a ContractDriftRequest
   ├── modified .sai / .sal
   ├── reason for the change
   └── estimated impact scope (list of affected functions)

2. Coordinator review
   ├── automatically run `sa contract diff`
   ├── list breaking changes
   ├── compute affected functions (reverse traversal of dependency graph)
   └── decision: approve / reject / approve with modifications

3. Approved → generate new contract.lock_v2
   ├── contract_sha256 updated
   ├── broadcast globally to all running agents
   └── all running agents receive the "contract drift" signal

4. Running agents handle it
   ├── check whether their own commit is in the affected_functions list
   ├── if listed → abort current implementation, rebase to the new contract
   └── not listed → continue, but submit with the new contract_sha256

5. Already-committed functions
   ├── cache entries automatically invalidated (contract_sha256 mismatch)
   ├── affected functions need re-implementation
   └── sa.lock records the drift history
```

### 6.3 Drift frequency ceiling

**Soft constraint**: more than 5 drifts in a single sprint → the coordinator algorithm has a bug and a "contract design review" should be triggered.

**Hard constraint**: every drift must have an explicit ContractDriftRequest record; "silently modifying `.sai`" is not allowed.

### 6.4 Minimizing drift cost

| Strategy | Effect |
|---|---|
| Have the coordinator think for 30 more seconds before freezing | reduces phase-1 drift |
| Include "ownership prefix expected by callers" in the requirement | reduces `^` ↔ `&` drift |
| Generate layouts with the `sa layout` tool instead of hand-writing | reduces offset drift |
| Agents implement L₀ (leaves) first, and only open L₁ after L₀ passes | narrows the blast radius of drift |

---

## 7. Function-level commit and conflict resolution

### 7.1 Commit granularity

**Rule**: one commit = one function + its exclusive `@const` / `@stub`.

**Not allowed**: a single commit spanning multiple functions (which would force serialization).

**The true need behind multi-function atomic commits**: usually means those two functions should be merged into one, or should be promoted to the `.sai` / `.sal` layer.

### 7.2 Conflict types

| Conflict | When discovered | Handling |
|---|---|---|
| Two agents implement the same function | at commit (first come, first served) | later one discards its implementation and works on another function |
| Two agents both use `#def NODE_SIZE` with different values | already forbidden in phase 0 — `#def` appears only in `.sal` | cannot happen |
| Two functions both declare `@const FOO` | phase 0 already allocated the `@const` namespace | cannot happen |
| Duplicate test name `@test "X"` | verify stage | later one adds suffix `X_2` |
| Function declares `grants [net_tx]`, caller doesn't have it | verify stage | Trap; caller rebases or coordinator supplements |
| `contract_sha256` has already changed when the agent commits | verify stage | drift triggered (§6) |

### 7.3 Commit log format

Every commit must be traceable:

```json
{
  "commit_id": "<random uuid>",
  "function_name": "parse_route",
  "function_sha256": "...",
  "contract_sha256": "...",
  "agent_id": "agent-impl-04",
  "agent_model": "claude-opus-4-7",
  "elapsed_ms": 4321,
  "retries": 0,
  "previous_traps": [],
  "committed_at": "2026-06-15T10:42:11Z"
}
```

Goes into the `[[commits]]` array of `sa.lock`.

---

## 8. Integration with existing SA features

### 8.1 Relationship to package management (`sa pkg`)

| Concept | sa.mod / sap.json | contract.lock |
|---|---|---|
| Scope | cross-project dependencies | single-project concurrent development protocol |
| Pinned object | third-party package source SHA | internal `.sai` / `.sal` SHA |
| Trust model | zero trust + grants whitelist | trusted within one project, but strong consistency required |
| Persistence | long-term, committed to Git | single sprint, discardable |

**Relationship**: complementary, not overlapping. `contract.lock` is a subset of `sa.lock` (specifically the `[contracts]` section).

### 8.2 Relationship to the Agent-First Toolchain

- `--json` output: all CLI commands in this protocol must support it
- `compile_tokens`: reported by each `sa func emit`, facilitating multi-round optimization by agents
- `sa explain`: the Trap feedback stage reuses existing capability
- `sa fix --plan`: during drift, can be used to suggest a rebase path

### 8.3 Relationship to function-level incremental caching

This protocol **strongly depends** on function-level incremental caching (see `kernel_improvement_evaluation_cn.md` §⭐⭐⭐⭐⭐ 1). The foundation is laid:

- `appendFlattenFragment` (delivered in progress.md)
- `cached_macro_defs` (delivered)
- `LayoutVersion` merge (delivered)
- `FunctionSig` deep clone + remapping (delivered)

**Still needed**:
- `(function_sha, contract_sha, deps_sha)` cache key
- single-function emit CLI (§4.3)
- incremental link driver

Effort estimates are in `kernel_improvement_evaluation_cn.md`.

### 8.4 Relationship to parallel emit

P0.4's declaration-level parallel emit parallelizes across functions **within a single process**. This protocol parallelizes across functions **across multiple processes / multiple agents**. The two complement each other:
- single process: use P0.4 for local sprints
- cross-process: this protocol suits large distributed sprints or multi-LLM collaboration

---

## 9. Boundaries / problems that cannot be solved

| Want to eliminate | Possible? | Why |
|---|---|---|
| All A → B dependencies | ❌ | interfaces are dependencies by nature |
| Phase-0 serialization | ❌ (but can be extremely short) | someone must define the interface first |
| Cross-layer concurrency | ❌ | topological order is a physical constraint |
| Agents not redoing work on contract drift | ❌ | but drift frequency can be minimized |
| Linear N→∞ scaling within a layer | ⚠️ partial | limited by Amdahl; 50-100 agents per layer is practically enough |
| Function granularity smaller than "one SA function" | ❌ | SA's minimal verification unit is the function |
| Automatic resolution of business-semantics conflicts | ❌ | that is the coordinator's intelligence level, not a protocol matter |

**What can truly be eliminated are "fake synchronization points"** — type inference, lifetime inference, trait coherence solving — which SA simply does not have.

---

## 10. Recommended landing order

### 10.1 Can be done first without touching the Zig kernel ("immediately runnable")

| Priority | Task | Effort |
|---|---|---|
| ⭐⭐⭐⭐⭐ | Document this protocol (this document is complete) | — |
| ⭐⭐⭐⭐ | Implement the `sa coordinate` script (Bash / Python) | 1-2 weeks |
| ⭐⭐⭐⭐ | Define and write a manual contract.lock template | 1 week |
| ⭐⭐⭐ | Write 3-5 example projects: coordinator output + 4-8 agent implementations | 1-2 weeks |

**After this wave**: the protocol can operate on existing SA as a "convention", without depending on kernel changes. Not optimal in performance, but the flow works end to end.

### 10.2 Requires new Zig kernel features ("industrially usable")

| Priority | Task | Effort | Where |
|---|---|---|---|
| ⭐⭐⭐⭐⭐ | function-level incremental compilation cache | 2-3 weeks | see `kernel_improvement_evaluation_cn.md` §⭐⭐⭐⭐⭐ 1 |
| ⭐⭐⭐⭐ | `sa contract freeze` / `diff` commands | 2 weeks | `src/cli.zig` + new `src/contract.zig` |
| ⭐⭐⭐⭐ | `sa func verify` / `emit` commands | 2 weeks | `src/cli.zig` + reuse existing flatten/verify |
| ⭐⭐⭐ | `sa link --contract` command | 1 week | reuse `driver/zigcc.zig` |
| ⭐⭐⭐ | `@reserved` / `@stub` syntax | 1 week | `src/flattener.zig` + `src/verifier.zig` |
| ⭐⭐ | `sa coordinate` CLI wrapper (Zig version) | 2 weeks | new `src/coordinate.zig` |

**Total**: about 2.5 months, in the CLI layer (without touching the Flattener / Referee core algorithms).

### 10.3 Long-term vision ("ecosystem level")

- third-party coordinator agent ecosystem (not just the one official SA implementation)
- `contract.lock` as a publishable-artifact schema standard (similar to protobuf's `.proto`)
- cross-project contract sharing ("a standard `.sai` for the router pattern")
- agent reputation / historical performance tracking (based on the commit log)
- automated drift suggestions (predicting from historical drift patterns)

---

## 11. One-sentence summary

> **The ceiling of SA multi-agent concurrent development is not the number of agents, but the number of topology layers in the interface dependency graph.**
>
> Through the four-part set of "short serial contract + large parallel implementation + function-level commit + drift negotiation", this protocol restructures unordered concurrency into controllable concurrency, enabling SA to reach near-theoretical-limit concurrency in multi-LLM collaboration scenarios while preserving all of Referee's safety guarantees.

---

## Appendix A: Glossary

| Term | Meaning |
|---|---|
| **Coordinator agent** | the single agent of phase 0, responsible for contract design |
| **Implementation agent** | the concurrent agents of phase 1, each responsible for one function |
| **Contract** | the complete `.sai` + `.sal` of a project |
| **contract_sha256** | the aggregate hash of the contract; all agents can see only one at a time |
| **Topology layer** | a set of functions in the dependency graph that do not depend on each other |
| **Drift** | a non-trivial change of the contract during phases 1/2 |
| **Rebase** | an agent re-implementing its function because of drift |
| **stub** | placeholder implementation that panics on running, allowing upper layers to build |
| **reserved** | placeholder declaration with no implementation, must be replaced before linking |

## Appendix B: Example workflow (HTTP router project)

**Human input** (requirement):

> "I want an HTTP path router supporting exact matching and wildcards (`/users/:id`). Given a URL path, return the matching handler index or -1."

**Phase 0 (coordinator agent, ~5 min)**:

Outputs `contracts/router/router.sai`:

```
@parse_route(s: ptr, len: u64) -> ptr
@trim_whitespace(&buf: ptr, len: u64) -> u64
@route_segments(&route: ptr) -> u64
@match_route(&router: ptr, path: ptr, path_len: u64) -> i64
@build_router(routes: ptr, count: u64) -> ptr
```

Outputs `contracts/router/router.sal`:

```
#def Route_SIZE = 32
#def Route_path_ptr = +0
#def Route_path_len = +8
#def Route_handler  = +16
#def Route_flags    = +24

#def Router_SIZE = 16
#def Router_routes = +0
#def Router_count  = +8

@const VTABLE_ROUTER = vtable { ... }
```

Outputs `contract.lock`: topology layering = `[[parse_route, trim_whitespace], [route_segments], [match_route, build_router]]`

**Phase 1 (5 concurrent agents, ~10 min)**:

- L₀: Agent A implements `parse_route`; Agent B implements `trim_whitespace`
- L₁: Agent C implements `route_segments`
- L₂: Agent D implements `match_route`; Agent E implements `build_router`

**Phase 2 (sequential commits, ~3 min)**:

Each function is verified + emitted. Total wall time ≈ max(layer time) × layer count = single-function time × 3 layers ≈ 15 min.

**Comparison with traditional single-agent sequential development**: estimated 5 functions × 10 min = 50 min.

**Speedup**: ~3× (limited by layer count, independent of function count). For a larger project (e.g. 50 functions / 5 layers), the speedup can reach ~10×.

---

## Appendix C: Open questions (to be discussed)

1. **Does the coordinator agent need a "sub-coordinator"?** Do large projects need per-module coordination?
2. **Can `@stub` functions be kept in production binaries?** The current spec forbids `@stub` in `--release-fast`; is that too strict?
3. **Should contract.lock be committed to Git?** Similar considerations to sa.lock — reproducibility vs. repository noise.
4. **Cross-sprint contract evolution** — does it need a `contract.lock` version chain (a v1 → v2 → v3 migration path)?
5. **Drift coordination** — can a voting mechanism be introduced? Auto-approve when multiple agents suggest drift in the same direction?
6. **Test name space** — should each agent get an automatic prefix, or should the coordinator pre-allocate?
7. **Agent performance data** — should it flow back into `sa.lock` for worker scheduling in later sprints?

Resolve the above before version v0.2.
