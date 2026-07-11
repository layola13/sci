# Phase B — Incremental Referee: Implementation Specification

Status: **design only, not implemented**. This document is the sound design to
implement in an environment where `src/verifier.zig` edits persist and test
output is trustworthy. It exists because Phase B could not be reliably landed or
verified in the session where this spec was written.

## Goal

Avoid re-running the full verifier on instruction streams that have already been
verified, without introducing use-after-free / double-free. The win is largest
under the daemon (process-persistent cache across requests from many agents).

## The soundness problem (why this is not a trivial cache)

`verifyWithOptions(allocator, instructions, options) VerifyError!VerifyResult`
returns `VerifyResult = union(enum){ ok: VerifyOk, trap: TrapReport }`.

`VerifyOk` holds caller-owned, heap-allocated data that the caller consumes and
then frees via `VerifyOk.deinit`:

```
VerifyOk = struct {
    annotated: []AnnotatedInstruction,   // owned
    function_sigs: []sig.FunctionSig,    // owned
    symbols: symbol.SymbolTable,         // owns its own allocator + StringHashMap
    const_decls: []const const_decl.ConstDecl = &.{},
    gas: gas.GasReport,
}
```

Caching a `VerifyOk` and returning it again would double-free (caller frees it;
cache still points at freed memory). So a result cache MUST return a **deep
copy** on every hit. The only external caller, `compileSource` (src/cli.zig,
call site near line 5028), consumes `ok.annotated` for codegen — so a cache hit
cannot skip producing `annotated`.

## Two sound options

### Option A — verdict-only cache + `sa check` command (lower risk)
- Add a verdict cache: `SHA256(instruction-stream + options) -> bool` (ok/not).
- Cache stores only a 32-byte digest, never owned pointers → no free hazard.
- A verdict cache does NOT help `compileSource` (it needs `annotated`). It only
  helps a **verify-only path**. That path does not exist yet; add an
  `sa check <file>` command that runs the verifier and reports ok/trap without
  codegen. `sa check` can then short-circuit on a cache hit soundly.
- Best first step: high value for agent loops ("is this code valid?") at low
  memory-safety risk.

### Option B — full result cache with deep copy (higher value, higher risk)
- Cache the produced `VerifyOk`; on hit return a **deep clone** so the caller
  can free it independently.
- Requires cloning every owned field. Leaf types below are value types, so their
  slices clone via `allocator.dupe`:
  - `AnnotatedInstruction = struct { base: inst.Instruction, delta: RegStateDelta, gas_step_cost: u32 }`
  - `RegStateDelta = struct { writes: []RegWrite, reads: []RegRead }`
  - `RegWrite = struct { reg: u16, state: RegState }` (value)
  - `RegRead  = struct { reg: u16, state: RegState }` (value)
  - So `annotated` clones as: dup the outer slice, then for each item dup
    `delta.writes` and `delta.reads`. (verified value-type leaves)
- STILL TO VERIFY before implementing (layouts NOT confirmed in this spec):
  - `sig.FunctionSig` — has an owned `name: []const u8` and `params` slice;
    confirm whether params are value types, then dup name bytes + params slice.
  - `symbol.SymbolTable` — owns an allocator + `StringHashMap` with owned keys.
    This is the hard part: cloning must re-init a table with the SAME allocator
    contract and dup all keys. Get its exact definition first.
  - `gas.GasReport`, `const_decls` — confirm value vs owned.

## Sound content hash (critical: hash ALL semantic fields)

A partial hash (e.g. opcode only) is UNSOUND — two semantically different
streams could collide and skip real verification. `inst.Instruction` has these
fields (confirmed from src/common/instruction.zig); the hash must fold in every
field that affects verification:

```
kind, source_line?, expanded_line?, package_identity, package_source_sha256,
op_kind, operands[4], raw_text, atomic_value_ty, atomic_ordering,
atomic_second_ordering, atomic_rmw_op, atomic_expected_text, atomic_new_text,
native_reg_names
```
- `kind`, `op_kind`, `operands`, atomic_* and the type indices definitely affect
  the verdict — hash them.
- `source_line`/`expanded_line` are location-only; excluding them lets identical
  code at different line numbers share a cache entry (an optimization) but
  confirm no verifier check depends on line numbers before excluding.
- Also fold in the `options` that change verdicts (package_grants, sax_context,
  check_exit_leaks, predecoded_*).

## Wiring without editing verifier.zig (matches this repo's constraints)

Because verifier.zig is large, prefer a NEW file `src/incr_verify.zig` exporting
the cache, and wire the call in `compileSource` (cli.zig) or in the new
`sa check` handler — not inside verifyWithOptions. `verifyWithOptions` is `pub`,
so a wrapper can live in a new file and be called by cli.zig.

## Test plan (unforgeable evidence)

- Unit-test all clone functions under `std.testing.allocator`: it detects leaks
  and double-frees at runtime. A passing clone round-trip test under the testing
  allocator is real memory-safety evidence.
- Round-trip: build a `VerifyOk`, clone it, deinit BOTH independently, assert no
  leak/no double-free.
- Hash: assert determinism (same input → same digest) and change-sensitivity
  (any semantic field change → different digest).
- E2E via daemon: two identical `sa check`/`sa build` requests → second is a
  cache hit; edit the source → cache miss (re-verifies).

## Acceptance

- `zig build` EXIT=0 from the committed tree.
- Clone unit tests pass under `std.testing.allocator`.
- Daemon: unchanged input re-verify is skipped; edited input is re-verified.
- No verifier verdict regressions on the existing test suite.
