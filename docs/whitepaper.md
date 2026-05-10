# SA-ASM Whitepaper v1.0

SA-ASM is a symbolic affine intermediate language for machine-generated code and machine-checked ownership.

## Design Goals

- Keep syntax flat and token-dense.
- Make ownership transitions explicit.
- Make verification linear, deterministic, and structure-free.
- Lower valid programs to Zig and then to WASM64.

## Core Symbols

| Symbol | Meaning |
|---|---|
| `=` | bind / allocate |
| `&` | borrow |
| `^` | move / consume |
| `!` | release / drop |
| `$...$` | native escape block |

## ISA Summary

SA-ASM programs are line-oriented. Each line is one of: definition, macro, function signature, label, instruction, or native block.

## Capability Masks

| Mask | Name |
|---|---|
| `0x00` | Uninitialized |
| `0x01` | Active |
| `0x02` | Locked_Read |
| `0x04` | Locked_Mut |
| `0x08` | Consumed |
| `0x10` | BorrowView |

## Truth Table

The referee applies table-driven state updates. Illegal transitions emit structured traps rather than recovery heuristics.

## Macro and REP Rules

- `[MACRO] ... [END_MACRO]` registers a pure text template.
- `EXPAND` pastes the template at the call site.
- `[REP N] ... [END_REP]` duplicates the block `N` times and injects `%i`.
- Expansion depth is capped at 256.

## Native Escape Blocks

Text inside `$...$` is passed through verbatim to the Zig backend. The referee treats referenced registers conservatively.

## Rust -> SA-ASM -> Zig Examples

| Rust | SA-ASM | Zig |
|---|---|---|
| `let mut x = alloc(16);` | `x = alloc 16` | `const x = try allocator.alloc(u8, 16);` |
| `x = x + y;` | `z = add x, y` | `const z = x + y;` |
| `drop(x);` | `!x` | `allocator.free(x);` |
| `return x;` | `return x` | `return x;` |
| `ptr = &x;` | `r = &x` | `const r = x;` |

## Trap Codes

| Trap | When |
|---|---|
| `ForbiddenSyntax` | banned syntax found |
| `DuplicateDef` | repeated `#def` |
| `DuplicateLabel` | repeated label |
| `UnsupportedType` | illegal type annotation |
| `MacroRecursionLimit` | expansion depth too high |
| `RegisterRedefinition` | macro expansion collides |
| `UnknownRegister` | undeclared register used |
| `BorrowConflict` | invalid borrow access |
| `UseAfterMove` | consumed register reused |
| `DoubleMutableBorrow` | second mutable borrow |
| `ReadWriteConflict` | read borrow upgraded to mut borrow |
| `MemoryLeak` | live state at function exit |
| `CapabilityMismatch` | signature mismatch |
| `FallthroughForbidden` | non-terminating block end |
| `PhiStateConflict` | merged control-flow state diverges |
| `GasExceeded` | runtime gas exceeded |
| `ArenaOOM` | runtime allocation overflow |
| `SnapshotVersionMismatch` | incompatible snapshot |

## Status

This document is intended to be machine-readable and line-limited. It complements the grammar and implementation, not a substitute for them.
