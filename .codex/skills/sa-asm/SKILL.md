---
name: "sa-asm"
description: "Programming guide and reference for Symbolic Affine Assembly (SA-ASM), focusing on ownership, register management, and FFI safety."
when_to_use: "Activate this skill whenever you need to read, write, or debug SA-ASM (.saasm) code. It is essential for ensuring correct register accounting, ownership transfers, and compliance with the Referee's strict safety checks."
---

# SA Assembly (SA-ASM) Programming Guide

This guide details the syntax, keywords, and strict design patterns required to write valid Symbolic Affine (SA) assembly.

## 1. Core Philosophy: Flat, Explicit, and Safe
SA is a low-level, flat-control-flow affine language.
- **No Implicit Actions:** No GC, no implicit Drop, no block scoping (`{ }`).
- **Explicit Ownership:** Every register holds an affine capability (mask) that must be explicitly consumed, released, or returned.
- **Flat Blocks:** Control flow uses labels (`L_NAME:`), jumps (`jmp`), branches (`br`), and `return`.

## 2. Capability Operators
- `=` : **Bind / Alloc** - Register gains `Active` mask.
- `&` : **Borrow** - Pointer passed as borrow; source is locked.
- `^` : **Move** - Ownership transfers; source is consumed.
- `!` : **Release** - Frees owned memory or unlocks a borrow.
- `*` : **Raw Escape** - Strips safety mask. **FFI only.**

## 3. Function Signatures
- `@f(x: i32)` : By value.
- `@f(&x: ptr)` : Borrowed pointer.
- `@f(^x: ptr)` : Moved (consumed) pointer.
- `@f() -> ^ptr` : Returns ownership.
- `@f() -> i32!` : Fallible return (`{ u32 status, T value }`).
- `@ffi_wrapper` : Unsafe sandbox allowing `*`, `assume_safe`, `assume_borrow`.

## 4. Register Accounting (Crucial)
Every register (including temporaries) MUST be explicitly released (`!`) when no longer needed, before returning, or before a branch that doesn't use it. Failure results in `MemoryLeak` or `PhiStateConflict`.

## 5. Control Flow Patterns (Standard Templates)

### If / Else (Conditional Branching)
Must clean up the condition and unused parameters in BOTH paths.
```saasm
@max(a: i32, b: i32) -> i32:
L_ENTRY:
    is_a = sgt a, b
    br is_a -> L_A, L_B

L_A:
    !is_a        // Release condition
    !b           // Release unused param
    return a

L_B:
    !is_a
    !a           // Release unused param
    return b
```

### Loops (Using stack_alloc)
Standard pattern for a `for` or `while` loop.
```saasm
L_ENTRY:
    i_ptr = stack_alloc 8
    store i_ptr+0, 0 as u64
    jmp L_COND

L_COND:
    i = load i_ptr+0 as u64
    cond = ult i, 10
    br cond -> L_BODY, L_EXIT

L_BODY:
    // ... work ...
    next = add i, 1
    store i_ptr+0, next as u64
    !next        // Clean up loop-local
    !i           // Clean up loop-local
    !cond        // Clean up loop-local
    jmp L_COND

L_EXIT:
    !i           // Clean up before leaving
    !cond
    return
```

## 6. Structs & Memory Layout
Accessed via raw offsets defined by `#def`.
```saasm
#def Pt_SIZE = 8
#def Pt_x = +0
#def Pt_y = +4

@create_point(x: i32, y: i32) -> ^ptr:
L_ENTRY:
    pt = alloc Pt_SIZE
    store pt+Pt_x, x as i32
    store pt+Pt_y, y as i32
    !x
    !y
    return pt
```

## 7. Instruction Set / Reference
- **Memory**: `alloc`, `stack_alloc`, `load`, `store`, `take`, `ptr_add`.
- **Math**: `add`, `sub`, `mul`, `sdiv`, `udiv`, `fadd`, etc.
- **Logic**: `and`, `or`, `xor`, `shl`, `not`, etc.
- **Cmp**: `eq`, `ne`, `slt`, `sgt`, `fcmp_eq`, etc.
- **Atomics**: `atomic_load`, `atomic_store`, `cmpxchg`, `atomic_rmw_<OP>`, `fence`.
- **Cast**: `trunc`, `zext`, `sext`, `bitcast`, etc.

## 8. Types
`i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, `u64`, `f32`, `f64`, `ptr`, `v128`.

## 9. Preprocessor & Consts
- `#def NAME = VALUE`
- `@const NAME = utf8:"..."`
- `@const NAME = vtable { ... }`
- `@import "file.saasm-iface"`

## 11. Further Reading & Detailed Examples
For a deeper dive into specific error codes, troubleshooting, and advanced optimization patterns, refer to:
- `docs/faq.md`: Detailed solutions for common Referee traps and complex implementation patterns.
- `docs/errorcode.md`: Explanation of all compiler traps (e.g., `PhiStateConflict`, `UseAfterMove`).
