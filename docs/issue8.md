# SA Compiler — Core/Kernel Performance Deep Dive (issue8)

Continuation of issue7. This pass focuses exclusively on the compiler kernel: `src/flattener.zig`, `src/verifier.zig`, `src/interp.zig`, `src/lowerer.zig`, `src/common/`, `src/referee/`, `src/flattener/`. The audit reads the actual source — every finding includes file:line. Ordered by expected wall-clock impact on `sa run` and `sa build-exe` of realistic SA programs.

The kernel is fundamentally well-shaped (flat arrays, no AST, no graph theory — matches the whitepaper R20 principles). The wins are mostly in five areas:

1. **Hot-loop linear scans that should be hash lookups.**
2. **Repeated work** the flattener already did being redone in the verifier and again in the interpreter.
3. **Per-function allocation churn** in the verifier (11 parallel arrays + 3 hashmaps × function count).
4. **Wide AOS data layouts** that thrash cache during single-attribute passes.
5. **String dispatch cascades** that should be perfect-hash or length-bucketed.

## Implementation status (2026-06-10)

Completed core/kernel performance slices in this batch:
- P1/P3/P6: interpreter per-function slot maps, cached label maps, and sorted memory-block lookup.
- P2/P5/P7/P16/P20: verifier signature-name index, opcode `StaticStringMap`, verifier buffer pool, single-pass `DefDict.foldText`, and flattener owned-source preallocation.
- P27 follow-up: LLVM-C emitter call/vtable/reachability lookup now uses one shared function-signature alias index instead of repeated linear scans.

Still intentionally deferred: broad SOA/MultiArrayList rewrites for `Instruction` / `RegValue`, full verifier single-pass consumed-reg redesign, and verify/emitter pipeline overlap. These are larger semantic/performance refactors that should be benchmark-gated rather than mixed into this safety/performance patch.

---

## TIER 1 — Hot-loop linear scans

### P1. `FunctionSig.slotOf` is O(N) and called per-register in the interpreter
`src/common/signature.zig:71-76`
```zig
pub fn slotOf(self: FunctionSig, global_id: u32) ?u32 {
    for (self.reg_ids, 0..) |reg_id, idx| {
        if (reg_id == global_id) return @intCast(idx);
    }
    return null;
}
```
Callers in the interpreter inner loop:
- `src/interp.zig:1226` — every `resolveTextOperand`
- `src/interp.zig:1647` — every param bind on call entry
- `src/interp.zig:1966, 1989, 2004, 2018` — every indirect / direct / try-call return-binding

For a function with R registers executing I instructions, this is **O(R·I) per call** purely for slot lookup. A 50-register function running a 200-instruction loop spends 10000 lookups doing linear scans.

The verifier already solved this for itself with `FunctionRegScope.slot_by_id: AutoHashMap(u32, u32)` (`src/verifier.zig:214`) but the interpreter uses the bare `FunctionSig` slot table directly. **Use the same hashmap approach** — `FunctionSig` should carry a built-in `slot_by_id` populated once at sig collection time.

Expected gain: 5–20× speedup on register-dense functions in `sa run`.

### P2. Function-signature lookup at every call site in the verifier is O(M·N)
`src/verifier.zig:2873-2878`
```zig
const sig_match: ?sig.FunctionSig = blk: {
    for (metadata.sigs.items) |one| {
        if (std.mem.eql(u8, one.name, parsed.callee)) break :blk one;
    }
    break :blk null;
};
```
Also at `src/verifier.zig:2936-2941` for "is this arg a function symbol" inside the same call processing. Each `std.mem.eql` walks character-by-character; with N functions and M call sites in the program, the verifier does N·M name comparisons.

A `StringHashMap(usize)` (index into `metadata.sigs.items`) built at metadata-collection time turns this into O(M) total.

Expected gain: depends on N. For the 10001-function `demos/compare/big_bench.sa`, verification probably spends most of its time here.

### P3. `Interpreter.execFunction` rebuilds the label hashmap on every call
`src/interp.zig:1202-1215, 1632-1633`
```zig
fn buildLabelMap(self, body) !std.AutoHashMap(u32, usize) {
    var labels = std.AutoHashMap(u32, usize).init(self.allocator);
    for (body, 0..) |item, idx| {
        if (item.base.kind == .label) try labels.put(id, idx);
    }
    return labels;
}
// in execFunction:
var labels = try self.buildLabelMap(body);
defer labels.deinit();
```
This map is identical across calls to the same function — it's a property of the function body, not of the call. With recursive workloads (a `fib(35)` invocation, e.g.) the map is allocated, populated, and freed millions of times.

Move the label map into `FunctionRange` (built once at `Interpreter.init`), or into `referee.VerifyOk` so it survives across the program's lifetime.

Expected gain: order-of-magnitude reduction in `sa run` allocator pressure for recursive programs.

### P4. `classifyLine` runs twice on every instruction text
`src/flattener.zig:3392` (during flatten) and `src/verifier.zig:205` (during verify).

`classifyLine` is a 130-line cascade of `startsWith` and `eql` checks (`src/flattener/line_classifier.zig:765-895`); it allocates nothing but is hot. Running it twice across the entire flattened program doubles parsing cost for zero new information.

Fix: have the flattener attach the existing `ClassifiedLine` to each `Instruction` (or to a parallel array indexed by `expanded_line`) and let the verifier consume it. `Instruction.raw_text` is already retained — the classified form costs only ~80 extra bytes per instruction. Or, store the classified array in the flatten result and pass it through.

Expected gain: ~50% reduction in the verifier's text-parsing time.

### P5. `parseOpKind` is a 60-deep `std.mem.eql` cascade
`src/common/instruction.zig:88`
```zig
return if (std.mem.eql(u8, text, "add")) .add
  else if (std.mem.eql(u8, text, "sub")) .sub
  else if (std.mem.eql(u8, text, "mul")) .mul
  ...60 more
```
Same shape in `parseOpCode` (line 151) with 24 entries. Each `mem.eql` checks length-then-byte-compare. Average cost is ~30 string comparisons per opcode. Called from `classifyLine` for every `op` instruction line.

Replace with: bucket by length (`text.len`), then within each bucket a small linear scan or perfect-hash. A 2-line table-driven version using `std.ComptimeStringMap` (now `std.StaticStringMap`) is both faster and far more maintainable.

Expected gain: roughly 4–8× for the opcode-parsing micro-benchmark; small but it's on every flatten and every classifyLine call.

### P6. `Interpreter.Memory.blockIndexAt` linear-scans block table
`src/interp.zig:430-436` (already covered in issue7 §13, restating because it's the single biggest interpreter win).

Replace with `std.AutoHashMap(u64, usize)` keyed by `block.addr` (returned from `alloc`), or store blocks sorted and bsearch. Every `load`/`store`/`ptr_meta` query becomes O(1).

---

## TIER 2 — Allocation churn

### P7. The verifier allocates 11 parallel arrays per function
`src/verifier.zig:2379-2400`
```zig
state = zeroed(u16, allocator, reg_count) catch ...
flags = try zeroed(u8, allocator, reg_count);
origins = try allocator.alloc(?u32, reg_count);
@memset(origins, null);
locks = try allocator.alloc(u16, reg_count);
@memset(locks, 0);
consumed_in_function = try allocator.alloc(bool, reg_count);
@memset(consumed_in_function, false);
interior_parent = try allocator.alloc(?u32, reg_count);
@memset(interior_parent, null);
interior_first_child = try allocator.alloc(?u32, reg_count);
@memset(interior_first_child, null);
interior_next_sibling = try allocator.alloc(?u32, reg_count);
@memset(interior_next_sibling, null);
interior_root = try allocator.alloc(?u32, reg_count);
@memset(interior_root, null);
interior_offset = try zeroed(u64, allocator, reg_count);
interior_offset_known = try allocator.alloc(bool, reg_count);
@memset(interior_offset_known, false);
```
**11 separate `allocator.alloc` calls × number-of-functions.** For 10001 functions that's 110011 small allocations every compile. Each is a malloc roundtrip and a memset.

`src/referee/table.zig:CapabilityTable` already implements a tight 4-array version (`masks`, `origins`, `lock_refs`, `flags`) — but the verifier doesn't use it. Two wins:

1. **Pool the buffers** at the top of `verify()` (size = max reg_count across functions) and `@memset` on function entry. This drops alloc count from O(funcs × 11) to O(11), reuse memory across functions.
2. **Pack into a single SOA struct** (mirror `CapabilityTable`) so the cache fetches related fields together when the verifier walks an instruction.

Expected gain: 30–50% reduction in verifier wall-clock on large modules.

### P8. Per-function HashMap allocation: `atomic_history`, `labels`, `defined_labels`
`src/verifier.zig:2311-2321`
```zig
var atomic_history = std.AutoHashMap(u64, u8).init(allocator);
defer atomic_history.deinit();
var labels = std.AutoHashMap(u32, LabelSnapshot).init(allocator);
defer { ... labels.deinit(); }
var defined_labels = std.AutoHashMap(u32, void).init(allocator);
defer defined_labels.deinit();
```
These three hashmaps are created and destroyed per function. Lines 2436-2437 already correctly call `clearRetainingCapacity` on the first two — but the maps themselves are scoped to a single function call. Move them up to the calling `verify()` scope and `clearRetainingCapacity` per function. Drops O(funcs × 3) hashmap allocs to O(3).

### P9. `computeFunctionConsumedRegs` is a redundant forward pass
`src/verifier.zig:914-929, 2411`
```zig
fn computeFunctionConsumedRegs(...) void {
    @memset(consumed_in_function, false);
    var idx = function_start_idx + 1;
    while (idx < instructions.len) : (idx += 1) {
        const item = instructions[idx];
        if (isDecl(item.kind)) break;
        markInstructionConsumedRegs(item, symbols, scope, consumed_in_function);
    }
}
```
This walks every instruction in the function before the main verifier walk starts. The main loop at line 2343 then walks **the same instructions** again. Each instruction's operands are touched twice, two cache lines pulled in instead of one.

Fix: merge consumed-reg tracking into the main forward pass. The verifier already needs to track register state — adding a `consumed_in_function` write is free if you're already there.

### P10. Symbol-id `@intCast(u32 → usize)` everywhere
~80 sites across `verifier.zig`. Each `@intCast` is essentially free (just type discipline) but the pattern obscures profile reads. More importantly, in `ReleaseFast` they wrap silently and in `ReleaseSafe` they bounds-check on every access — neither path is great. Storing indices as `usize` directly (or as `u32` and adopting `@as(usize, x)` consistently) would shave a measurable few percent.

### P11. `emitParsedLine` allocates and re-parses synthetic lines
`src/flattener.zig:2581-2680` (`print!` macro expansion path) issues many sequences like:
```zig
const ptr_release_line = try std.fmt.allocPrint(allocator, "! {s}", .{first.ptr});
defer allocator.free(ptr_release_line);
try emitParsedLine(...);
```
Each `emitParsedLine` invocation calls `classifyLine` (P4) and `intern` against the symbol table, and may itself allocate operand text. A `print!("hello", x)` with 5 args triggers ~15-25 `allocPrint` + re-parse cycles.

Counted **220+ `allocPrint`/`dupe` sites in `flattener.zig`** total. For format-string-heavy SA code this dominates flatten time.

Fixes (in order of impact):
1. **Have synthetic-emit helpers skip the re-parse** — build the `Instruction` directly instead of formatting back to a text line that has to be parsed again.
2. **Use an arena allocator** for the per-expansion lifetime, so the dozens of tiny strings are bulk-freed instead of individually.
3. **Reuse a scratch buffer** (`std.ArrayList(u8)`) across emits in the same expansion.

---

## TIER 3 — Data layout

### P12. `RegValue` is ~96 bytes; three optional slices on every value
`src/interp.zig:37-50`
```zig
const RegValue = struct {
    ty: sig.PrimType,         // 1 byte
    bits: u64,                // 8 bytes
    fallible: bool = false,   // 1 byte each, 6 bools = 6 bytes
    status: u32 = 0,
    interior_ptr: bool, borrow_view: bool, ffi_borrow: bool,
    extern_handle: bool, from_try: bool,
    const_name: ?[]const u8,        // ~24 bytes (option of slice)
    vtable_slot_name: ?[]const u8,  // ~24 bytes
    call_target_name: ?[]const u8,  // ~24 bytes
};
```
With Zig's struct layout this lands around 96 bytes. `FrameRegs.values: []?RegValue` then adds 1 byte + padding per optional wrapper. A 50-register frame is ~5 KB — bigger than L1 is even worth.

The three optional slices are only set on registers that point at a vtable/const/indirect-call target — probably <5% of all registers in realistic programs.

Fix: move the three optionals into a side-table `std.AutoHashMap(u32, RegProvenance)` populated only when needed. Drops `RegValue` to ~24 bytes; frames fit in L1 even for 100-register functions.

### P13. `Instruction` struct is ~200+ bytes
`src/common/instruction.zig:219-236` — `kind` + 2×u32 + `?package_identity` + `?package_source_sha256: [32]u8` + `?upstream_loc` + `?op_kind` + `[4]Operand` + `raw_text` + 6 atomic optionals + `native_reg_names`.

The Operand union has the widest variant `text: []const u8` at 16 bytes + 1 byte tag, padded to 24 bytes. `[4]Operand` is ~96 bytes alone.

The verifier and interpreter only touch a subset on every instruction:
- Verifier main loop: `kind`, `operands` (every step), `source_line`, `raw_text` (only on trap), `upstream_loc` (only on trap).
- Interpreter: same, plus `op_kind`.

The atomic fields (`atomic_value_ty`, `atomic_ordering`, `atomic_second_ordering`, `atomic_rmw_op`, `atomic_expected_text`, `atomic_new_text`) apply to <5% of instructions but cost ~40 bytes on every instruction.

**Recommendation**: split into SOA. Keep `kinds: []InstKind` (1 byte/inst), `operands: [][4]Operand` (96 bytes/inst), and put everything else (`raw_text`, atomic metadata, `upstream_loc`, package identity) into separate "cold" arrays touched only on trap or atomic instructions. The verifier walks `kinds` (or `kinds`+`operands`) prefetch-friendly.

This is the single biggest cache-friendliness improvement available, and Zig's `MultiArrayList` makes it cheap to implement.

### P14. `LineKind` dispatch is a sequential prefix cascade
`src/flattener/line_classifier.zig:765-895` — `classifyLine` does 20+ `startsWith` / `eql` checks in order. Worst-case path (unknown instruction) does all of them. A length-bucketed dispatch (most directives have unique first-3-chars) or a 256-entry switch on `trimmed[0]` to narrow the search would halve the work.

---

## TIER 4 — Algorithmic redundancy

### P15. The flattener and verifier maintain parallel symbol tables
`src/flattener.zig` builds `SymbolTable` (StringHashMap-backed) during flattening. The verifier in `collectMetadata` (`verifier.zig:1590-...`) then walks signatures again and re-interns into the same `metadata.symbols` table. With proper plumbing, the flattener's symbol table can be handed to the verifier directly — one fewer pass + one fewer hashmap allocation.

### P16. `DefDict.foldText` double-scans the text
`src/flattener/def_dict.zig:60-103`
```zig
// Fast path: check if any key exists in the text.
var has_replacement = false;
... // first scan: identify-and-test each token
if (!has_replacement) {
    return try allocator.dupe(u8, text);
}
... // second scan: actually replace
```
For text that contains zero matches the early exit is a win. For text that contains any match, the entire scan is repeated. A single-pass scan with a `std.ArrayList` initialized lazily on first match achieves both goals without the double walk.

### P17. `mapInstKind` and `isExecKind` / `isDecl` are dense switches but used outside hot paths
`src/verifier.zig:384, 398` — these are fine. Not a perf bug, but worth noting that they are correctly switch-based (not `mem.eql` cascades) — should serve as a template for fixing P5.

### P18. `markCaretConsumedRegs` re-scans instruction text byte-by-byte
`src/verifier.zig:887-901`
```zig
fn markCaretConsumedRegs(text: []const u8, ...) void {
    while (search_start < text.len) {
        const caret_idx = std.mem.indexOfPos(u8, text, search_start, "^") orelse return;
        ...
    }
}
```
This is called from `computeFunctionConsumedRegs` (already on the chopping block per P9) and uses `raw_text` instead of the parsed operand list. The parsed operands are already in `item.operands` — use those.

### P19. `addPart` in classifier copies pointer+len for every part
`src/flattener/line_classifier.zig:68` — `parts: [6][]const u8` is fixed-size. Every classifyLine that emits parts writes into all 6 slots even if only 1-3 are used. Minor cost compared to the others; mentioned for completeness.

---

## TIER 5 — Quick wins

### P20. `appendOwnedSource` doesn't preallocate
`src/flattener.zig:3968` — quick check showed it doesn't `ensureTotalCapacity` before the bytewise append loop. For source files >100 KB this triggers multiple `ArrayList` reallocs.

### P21. The flattener allocates `__sa_hyg{d}` hygiene names per macro expansion
`src/flattener.zig:1174` — `try std.fmt.allocPrint(allocator, "{s}__sa_hyg{d}", ...)`. For macro-heavy files (which is the common case in SA — the project has hundreds of macros), this is many small allocs. A reusable scratch buffer per macro expansion frame would dedupe.

### P22. `print!` macro produces `__PRINT_LIT_{line}_{const_id}` const names
`src/flattener.zig:2596, 2604, 2632` — same allocation pattern. Same fix.

### P23. The flattener's `SourceLine` array is rebuilt for every chunk
`src/flattener.zig:3380-3398` — `splitSource` reallocates `lines` even though `countSourceLines` was just used to size it. The flow is fine; mentioning because preallocating `lines.ensureTotalCapacity` happens correctly (line 3381) — no bug, just confirming.

### P24. Verifier's `body` walks redo `localizeInstructionRegs`
`src/verifier.zig:2463` is called per instruction inside the main loop and translates global reg IDs to scope slots. The translation is deterministic per (sig, instruction) pair — could be cached as an annotation on `Instruction` set during flattening, since reg IDs aren't going to change.

### P25. `interp.Memory.alloc` returns the heap pointer as `u64` address
`src/interp.zig:399` — `@intFromPtr(data.ptr)`. Real heap pointers are fine for an interpreter, but it forces `blockIndexAt` to compare against ranges. If `Memory` instead handed out *opaque* handles (`u32` index into the blocks list with a generation counter), then `load`/`store` become direct array indexes and the entire P6 problem evaporates. Slight semantic shift but cleaner.

---

## Architectural recommendations

### A1. Adopt `MultiArrayList` for `Instruction`
Zig's `std.MultiArrayList(Instruction)` automatically splits a struct-of-tagged-fields into SOA. The verifier and interpreter walk `.items(.kind)`, `.items(.operands)`, etc. — each pass touches one or two cache lines instead of the whole 200-byte struct. Fixes P13 without a refactor of every call site.

### A2. Build a `FunctionContext` once at verify-end and reuse it
A struct carrying:
- `slot_by_id: AutoHashMap(u32, u32)` (fixes P1)
- `label_map: AutoHashMap(u32, usize)` (fixes P3)
- pre-resolved `callee_index_by_name: StringHashMap(usize)` (fixes P2)
- per-instruction pre-localized `[4]u32` slot operands (fixes P24)

attached to each `FunctionSig`. Pay the cost once during verify, harvest the win in both `sa run` and the lowerer.

### A3. Single allocator pool for verifier per-function buffers
Add a `VerifierBuffers` struct holding the 11 arrays at max-reg-count. The verifier's `verify` allocs it once, calls `@memset` on entry to each function. Fixes P7.

### A4. Bench harness
`bench_compiler.zig` exists at the repo root but isn't visibly wired into CI. Make it report:
- flatten time per source-line
- verify time per instruction
- interp steps/second

with stable input so regressions don't slip past. After each tier-1 fix, rerun the bench and confirm the win.

### A5. `MultiArrayList` for `RegValue` in interpreter frames
Same idea as A1 — the interpreter walks one or two fields of `RegValue` at a time, never all 12 at once. SOA fits.

---

## Expected payoff if all Tier-1 fixes land

These are rough estimates from the kind of programs the test suite contains:

| Tier-1 fix | Estimated `sa run` speedup | Estimated `sa build-exe` speedup |
|---|---|---|
| P1 (slotOf hashmap) | 3–10× on register-dense functions | minor (verifier not affected) |
| P2 (callee name index) | minor | 5–20× on large modules |
| P3 (cached label map) | 5–50× on recursive workloads | none |
| P4 (no double classify) | minor | ~1.3–1.5× total verify |
| P5 (opcode table) | minor | ~1.05–1.1× flatten |
| P6 (block-index hashmap) | 2–5× on alloc-heavy programs | none |

Stacking the gains, realistic compile-time and run-time improvements of 2–5× are achievable without changing language semantics. The kernel design (flat arrays, linear scan, u16 bitmask) is sound — the perf wins come from filling in the missing index structures.

---

## What I would build next

In priority order:

1. **Wire up `bench_compiler.zig` to CI** with a baseline measurement (1–2 hours).
2. **P1 + P2 + P3** as a single PR — three index-structure additions, no semantic change (1 day).
3. **P7** — pool the verifier buffers (half a day).
4. **P4** — pass `ClassifiedLine` from flattener to verifier (half a day, careful with the parallel verify path).
5. **P13 via MultiArrayList** — the big cache-friendliness win, but more invasive. Save for after benchmarks confirm the simpler fixes (2–3 days).

All five together should deliver a clear 3×+ improvement on the benchmark, and lay the data-structure foundations the project will want once it self-hosts (v1.0+ in the roadmap).
