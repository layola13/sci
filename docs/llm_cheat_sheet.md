# SA-ASM (Linear Ownership Assembly) LLM Cheat Sheet

**System Context**: SA (Symbolic Affine) is a line-oriented, affine ownership assembly language. It is memory-safe without GC.

## 1. Core 5-Symbol Ownership Contract
- `=` **(Bind)**: `r = alloc N` → `r` becomes `Active`.
- `&` **(Borrow)**: `b = &r` → `r` becomes `Locked` (Read/Mut), `b` becomes `BorrowView`.
- `^` **(Move)**: `call @consume(^r)` → `r` becomes `Consumed` (UseAfterMove if accessed).
- `!` **(Release)**: `!b` unlocks parent; `!r` physically frees heap allocation.
- `*` **(Escape)**: `raw = *safe` → allowed ONLY in `@ffi_wrapper` functions.

## 2. Function Signatures & ABI
- **By-value**: `@f(x: i32)` (Primitives only).
- **Borrow**: `@f(r: &ptr)` (Must be type `ptr`).
- **Move**: `@f(^d: ptr)` (Must be type `ptr`).
- **Return Fallible**: `@f() -> i32!` (ABI maps to `{u32 status, T value}`).
- **Extern/Export**: `@extern f(*p: ptr)` (C-ABI compatibility).

## 3. Basic Syntax & Operations
- **No nested blocks**: Control flow is strictly flat (`jmp`, `br`, `br_null`, `return`). Every block MUST end with a jump/branch/return.
- **Offsets / Structs**: Emulated via preprocessor.
  `#def Vec_len = +0`, `load ptr+Vec_len as u32`.
- **Error Propagation (`?`)**:
  `res = call @func()`; `val = ? res`. Flattens to `br_ok + L_early_return`.
- **Airlock (FFI)**: Unsafe pointer conversions (`assume_safe`, `assume_borrow`, `*`) are strictly forbidden outside of `@ffi_wrapper`.
- **System Calls**: `@sys_print`, `@sys_exit`, `@sys_read_file`, etc., are native intrinsics.

## 4. Crucial LLM Generation Rules (Referee Checks)
1. **MemoryLeak Trap**: All `Active` and `BorrowView` registers MUST be explicitly released (`!`) before a `return`. The compiler will NOT insert drops for you.
2. **Phi Consistency**: If jumping to a label `L_NAME:` from multiple branches, the ownership mask of every register must be identical across all incoming edges.
3. **DoubleMutableBorrow Trap**: You cannot borrow exclusively twice.
4. **UseAfterMove Trap**: Do not touch a register after it has been moved (`^`).
5. **EarlyReturnLeak**: If you use `?` and an error occurs, the early return path MUST NOT leak memory. If you have live allocations when calling a `!` function, `?` will trap. You must manually handle errors or free memory before `?`.

## 5. ISA Quick Reference
- **Mem**: `alloc`, `stack_alloc`, `load`, `store`, `take`.
- **Math**: `add`, `sub`, `mul`, `sdiv`, `udiv`, `neg`...
- **Cmp**: `eq`, `ne`, `slt`, `sle`, `sgt`, `sge`, `ult`, `ule`, `ugt`, `uge`...
- **Cast**: `trunc`, `zext`, `sext`, `bitcast`...
- **Atomic**: `atomic_load`, `atomic_store`, `cmpxchg`, `fence`.
- **Types**: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, `u64`, `f32`, `f64`, `ptr`, `v128`.

*(When generating `.sa` code, strictly adhere to flat control flow, rigorous explicit cleanup, and the exact keyword set).*
