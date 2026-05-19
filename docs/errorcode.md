# SA Error Code Guide

This document is the canonical reference for SA diagnostics.

Use it together with:
- [`design.md`](../.kiro/specs/sa-asm-language/design.md) §4.4, which pins the `TrapReport` schema and field semantics.
- [`tasks.md`](../.kiro/specs/sa-asm-language/tasks.md) §2.5a and §30.2-30.4, which track the diagnostics rollout and debug-mode scope.
- [`docs/faq.md`](./faq.md), which explains the user-facing reason for JSON-first diagnostics and stable trap names.
- [`docs/whitepaper.md`](./whitepaper.md), which keeps the reader-facing summary compact.

## 1. Rules

- Trap names are stable public identifiers.
- Trap enum ordinals are not public numeric codes.
- Do not infer meaning from enum order.
- Prefer structured diagnostics over bare strings.
- Follow Zig-style `ErrorMsg` / `ErrorBundle` thinking for notes and hints, but keep SA output JSON-first.

## 2. Diagnostic Layers

### 2.1 Public Trap Layer

`Trap` is the user-visible refusal surface. When the compiler can classify a semantic or syntax failure, it should emit JSON with a `trap` name from `src/common/trap.zig`.

| Trap | Stage | Status |
|---|---|---|
| `ForbiddenSyntax` | Flattener / Referee | emitted |
| `DuplicateDef` | Flattener | emitted |
| `DuplicateLabel` | Referee | emitted |
| `UnsupportedType` | Signature / Layout / Referee / CLI flatten wrapper | emitted |
| `ImportResolutionFailed` | Flattener / CLI flatten wrapper | emitted |
| `MacroRecursionLimit` | Flattener | emitted |
| `RegisterRedefinition` | Referee / CapabilityTable | emitted |
| `UnknownRegister` | Referee / CapabilityTable / metadata collection | emitted |
| `BorrowConflict` | Referee / CapabilityTable | emitted |
| `UseAfterMove` | Referee / CapabilityTable | emitted |
| `DoubleMutableBorrow` | Referee / CapabilityTable | emitted |
| `ReadWriteConflict` | Referee / CapabilityTable | emitted |
| `MemoryLeak` | Referee | emitted |
| `CapabilityMismatch` | Referee / Call checker | emitted |
| `FallthroughForbidden` | Referee | emitted |
| `PhiStateConflict` | Referee | emitted |
| `GasExceeded` | Referee / debug gas mode | roadmap-only |
| `ArenaOOM` | Flattener / Referee / CLI flatten wrapper | emitted |
| `SnapshotVersionMismatch` | snapshot / future persistence | roadmap-only |
| `IllegalUnsafeContext` | Referee | emitted |
| `FfiOwnershipViolation` | Referee | emitted |
| `UnsupportedSysIntrinsic` | Referee | emitted |
| `InteriorPtrEscape` | Referee | emitted |
| `ConstMutation` | Referee | emitted |
| `VTableSignatureMismatch` | Referee | roadmap-only |
| `StackEscape` | Referee | emitted |
| `EarlyReturnLeak` | Referee | emitted |
| `FallibleContractMismatch` | Referee | emitted |
| `InvalidAtomicOrdering` | Flattener / CLI mapping | emitted |
| `AtomicOrderingMismatch` | Referee | emitted |

Notes:
- `GasExceeded`, `SnapshotVersionMismatch`, and `VTableSignatureMismatch` are namespace-reserved, but not fully wired through the current pipeline.

### 2.2 Stage-Local Error Sets

These are internal Zig error sets. They are not public SA Trap codes by themselves.

| Namespace | Codes |
|---|---|
| `src/flattener.zig` | `ForbiddenSyntax`, `DuplicateDef`, `MacroRecursionLimit`, `InvalidAtomicOrdering`, `InvalidSyntax`, `InvalidMacroInvocation`, `InvalidMacroDefinitionContext`, `UnbalancedMacro`, `UnbalancedRep`, `ImportCycle` |
| `src/common/signature.zig` | `InvalidFunctionSig`, `UnsupportedType` |
| `src/common/const_decl.zig` | `InvalidConstDecl`, `InvalidLiteral`, `InvalidUtf8`, `DuplicateSlot`, `EmptySlotName`, `EmptyFunctionName` |
| `src/common/atomic.zig` | `InvalidAtomicSyntax`, `InvalidAtomicOrdering`, `UnsupportedType` |
| `src/layout.zig` | `InvalidTarget`, `InvalidFieldList`, `InvalidFieldName`, `DuplicateField`, `UnsupportedType` |
| `src/referee/call.zig` | `InvalidCallSyntax`, `UnknownFunction`, `CapabilityMismatch`, `OutOfMemory` |
| `src/referee/table.zig` | `UnknownRegister`, `BorrowConflict`, `UseAfterMove`, `DoubleMutableBorrow`, `ReadWriteConflict`, `RegisterRedefinition`, `MemoryLeak`, `IllegalUnsafeContext`, `FfiOwnershipViolation` |
| `src/interp.zig` | `OutOfMemory`, `InvalidOperand`, `InvalidAddress`, `InvalidInstruction`, `InvalidFunction`, `UnknownFunction`, `MissingIndirectCallProvenance`, `UnsupportedInstruction`, `UnsupportedSysIntrinsic`, `UserExit` |
| `src/driver/zigcc.zig` | `ChildProcessFailed`, `InvalidTarget`, `MissingTarget` |
| `src/emit_llvm.zig` | `EmitError` variants: `OutOfMemory`, `InvalidOperand`, `UnsupportedInstruction`, `UnsupportedType`, `UnknownFunction`, `MissingIndirectCallProvenance` |
| `src/lowerer.zig` | `InvalidOperand`, `UnsupportedInstruction`, `OutOfMemory` |

### 2.3 Runtime ABI Exit Codes

These are not Trap codes. They are ABI-compatible integers returned by `sa_std` runtime calls.

| Code | Meaning |
|---|---|
| `0` | `SA_STD_OK` |
| `1` | `SA_STD_ERR_INVALID_ARGUMENT` |
| `2` | `SA_STD_ERR_INVALID_HANDLE` |
| `3` | `SA_STD_ERR_NOT_FOUND` |
| `4` | `SA_STD_ERR_ACCESS` |
| `5` | `SA_STD_ERR_NO_MEMORY` |
| `6` | `SA_STD_ERR_IO` |
| `7` | `SA_STD_ERR_NET` |
| `8` | `SA_STD_ERR_UNSUPPORTED` |
| `9` | `SA_STD_ERR_TRUNCATED` |
| `127` | `SA_STD_ERR_UNKNOWN` |

## 3. JSON Diagnostics

Current `TrapReport` fields:

| Field | Meaning |
|---|---|
| `trap` | Public trap name |
| `line` | Expanded line number, 1-based when an instruction exists; CLI-side flattening fallbacks currently report the first offending line in expanded text |
| `source_line` | Source line number, 1-based |
| `register` | Primary register name |
| `registers` | Related register list |
| `expected_mask` | Expected capability mask |
| `actual_mask` | Actual capability mask |
| `expected_mask_name` | Human-readable expected mask name |
| `actual_mask_name` | Human-readable actual mask name |
| `upstream_loc` | Upstream source mapping `{file,line,col}` or `null` |
| `function` | Current function declaration text, not just the bare name |
| `is_ffi_wrapper` | Whether the current function is an airlock wrapper; `null` when no function context exists |
| `message` | Primary human-readable message |
| `hint` | Optional fix suggestion |

Notes:
- `register_buf` and `function_buf` are internal fallback buffers.
- `upstream_file_buf`, `upstream_line`, and `upstream_col` are internal fallback carriers.
- A future `trap_code` field may be added later, but it must be explicit and not derived from enum ordinals.
- A future `source_text` or `original_text` field can be added for LLM repair workflows.

### Example

```json
{
  "trap": "UnknownRegister",
  "line": 13,
  "source_line": 24,
  "register": "after",
  "registers": [],
  "expected_mask": null,
  "actual_mask": null,
  "expected_mask_name": null,
  "actual_mask_name": null,
  "upstream_loc": null,
  "function": "@main() -> i32:",
  "is_ffi_wrapper": false,
  "message": "register is not declared in the current scope",
  "hint": null
}
```

## 4. Public Trap Catalog

| Code | Namespace | Stage | Current trigger | Message / hint shape | Status |
|---|---|---|---|---|---|
| `ForbiddenSyntax` | Trap | Flattener / Referee | `{}` / `if` / `else` / `while` / `for` / `a.b.c` / invalid borrow or call syntax | primary message, optional hint | emitted |
| `DuplicateDef` | Trap | Flattener | repeated `#def` name | primary message, no hint today | emitted |
| `DuplicateLabel` | Trap | Referee | same `L_NAME:` twice in one function | primary message, optional hint | emitted |
| `UnsupportedType` | Trap | Signature / Layout / Referee / CLI flatten wrapper | unsupported primitive type annotation | primary message, no hint today | emitted |
| `ImportResolutionFailed` | Trap | Flattener / CLI flatten wrapper | unresolved import path / ambiguous package version / rejected precompiled artifact | primary message, contextual hint | emitted |
| `MacroRecursionLimit` | Trap | Flattener | macro expansion depth > 256 | primary message, no hint today | emitted |
| `RegisterRedefinition` | Trap | Referee | macro expansion or instruction rebinds an already live register | primary message, `register` | emitted |
| `UnknownRegister` | Trap | Referee | use of a never-declared register | primary message, `register` | emitted |
| `BorrowConflict` | Trap | Referee | read/write/move on a locked-mut source | primary message, `register`, mask fields | emitted |
| `UseAfterMove` | Trap | Referee | access on a consumed register | primary message, `register`, mask fields | emitted |
| `DoubleMutableBorrow` | Trap | Referee | second exclusive borrow on same source | primary message, `register`, mask fields | emitted |
| `ReadWriteConflict` | Trap | Referee | shared borrow upgraded to mutable borrow or write-through shared borrow | primary message, `register`, mask fields | emitted |
| `MemoryLeak` | Trap | Referee | active or locked registers remain at function exit | primary message, mask fields | emitted |
| `CapabilityMismatch` | Trap | Referee / call checker | call-site prefix does not match callee contract | primary message, `register`, mask fields | emitted |
| `FallthroughForbidden` | Trap | Referee | basic block ends without terminator | primary message + hint | emitted |
| `PhiStateConflict` | Trap | Referee | incoming control-flow states disagree | primary message | emitted |
| `GasExceeded` | Trap | Referee / debug gas mode | gas budget exhausted | reserved for future debug mode | roadmap-only |
| `ArenaOOM` | Trap | Flattener / Referee / CLI flatten wrapper | internal allocation or bookkeeping failed | primary message | emitted |
| `SnapshotVersionMismatch` | Trap | Snapshot / future persistence | snapshot version mismatch | not wired in current pipeline | roadmap-only |
| `IllegalUnsafeContext` | Trap | Referee | raw pointer / assume_* outside `@ffi_wrapper` | primary message | emitted |
| `FfiOwnershipViolation` | Trap | Referee | `^` / `!` on `FfiBorrow` view | primary message, `register`, mask fields | emitted |
| `UnsupportedSysIntrinsic` | Trap | Referee | unsupported `@sys_*` intrinsic | primary message | emitted |
| `InteriorPtrEscape` | Trap | Referee | `InteriorPtr` crosses FFI boundary | primary message, `register`, mask fields | emitted |
| `ConstMutation` | Trap | Referee | `@const` value is moved, released, or exclusively borrowed | primary message, `register`, mask fields | emitted |
| `VTableSignatureMismatch` | Trap | Referee | indirect-call tuple mismatches vtable slot signature | planned, not yet emitted | roadmap-only |
| `StackEscape` | Trap | Referee | stack allocation is moved, returned, or passed across native escape boundary | primary message, `register`, mask fields, sometimes hint | emitted |
| `EarlyReturnLeak` | Trap | Referee | `?` early return path leaves live registers | primary message, `register`, mask fields | emitted |
| `FallibleContractMismatch` | Trap | Referee | `?` on a non-fallible value or wrong fallible return path | primary message, `register`, mask fields | emitted |
| `InvalidAtomicOrdering` | Trap | Flattener | `cmpxchg` failure ordering stronger than success ordering | primary message | emitted |
| `AtomicOrderingMismatch` | Trap | Referee | same-address RMW ordering combination not allowed | primary message | emitted |

## 5. Current Emission Rules

### 5.1 Flattener

Flattener errors are mapped to traps in `src/cli.zig`.

Current mapping:
- `ForbiddenSyntax` -> `ForbiddenSyntax`
- `DuplicateDef` -> `DuplicateDef`
- `MacroRecursionLimit` -> `MacroRecursionLimit`
- `InvalidAtomicOrdering` -> `InvalidAtomicOrdering`
- `UnsupportedType` -> `UnsupportedType`
- `OutOfMemory` -> `ArenaOOM`
- `ImportCycle` -> `ForbiddenSyntax` with an import-cycle message
- `InvalidMacroInvocation` / `InvalidMacroDefinitionContext` / `UnbalancedMacro` / `UnbalancedRep` / `InvalidSyntax` -> `ForbiddenSyntax`
- Other flattening failures currently fall back to `ForbiddenSyntax` with `message = @errorName(err)` and a generic hint

### 5.2 Referee

Referee already emits structured `TrapReport` JSON for semantic failures.

Observed current messages:
- `UnknownRegister`: `register is not declared in the current scope`
- `UseAfterMove`: `moved value is no longer usable`
- `BorrowConflict`: `borrow rules reject this access`
- `IllegalUnsafeContext`: `raw pointer and assume_* instructions are only legal inside @ffi_wrapper`
- `RegisterRedefinition`: `register is already live`
- `StackEscape`: `stack allocation cannot cross a native escape boundary`
- `MemoryLeak`: `live registers remain at function exit`
- `FallthroughForbidden`: `function body ended without a terminator`
- `EarlyReturnLeak`: `early return would leak live registers`
- `FallibleContractMismatch`: `? can only be applied to fallible return values` or `fallible values must be propagated with ? or returned from a fallible function`
- `AtomicOrderingMismatch`: `same-address RMW ordering combination is not allowed`
- `UnsupportedSysIntrinsic`: `target runtime does not support this @sys_* intrinsic`

### 5.3 Interpreter and Driver

These stages mostly emit plain Zig errors, not SA Trap JSON.

- Interpreter uses `RunError` and currently prints `error: <name>` on unexpected runtime failures.
- Driver uses `CompileError` and forwards child stderr.
- CLI parameter errors remain plain errors unless wrapped elsewhere.

## 6. Expansion Notes

If a future change adds richer diagnostics, it should add fields in this order:
1. `trap_code`
2. `source_text`
3. `original_text`
4. source excerpt / caret span
5. optional note chain

The addition must not break existing `trap`-first consumers.

## 7. Cross References

- [`src/common/trap.zig`](../src/common/trap.zig) is the source of truth for public trap names and `TrapReport` serialization.
- [`src/cli.zig`](../src/cli.zig) currently performs flattening-to-trap fallback mapping.
- [`src/referee/verifier.zig`](../src/referee/verifier.zig) is the main semantic trap emitter.
- [`.kiro/specs/sa-asm-language/design.md`](../.kiro/specs/sa-asm-language/design.md) §4.4 defines the schema contract that this guide indexes.
- [`.kiro/specs/sa-asm-language/tasks.md`](../.kiro/specs/sa-asm-language/tasks.md) §2.5a and §30.2-30.4 track rollout, debug-gas, and debug-san work.
- [`docs/faq.md`](./faq.md) explains the rationale in user-facing terms.
- [`.kiro/specs/sa-asm-language/requirements.md`](../.kiro/specs/sa-asm-language/requirements.md) carries the originating requirements.
- [`docs/whitepaper.md`](./whitepaper.md) carries the compact reader summary.
