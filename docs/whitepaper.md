# SA Whitepaper v0.1

SA (Symbolic Affine) is a fully independent, line-oriented affine ownership language designed for the LLM era. It produces native executables, WebAssembly modules, and linkable object files — without depending on any host language runtime.

## Identity

- **Not an IR**: SA is a standalone language with its own CLI, interpreter, and system primitives.
- **Not a host-dependent plugin**: `sa run hello.sa` executes directly. No Go, Rust, Zig, or Python runtime required.
- **Full-platform**: Native (x86_64 / ARM64 / Windows / Linux / macOS) + WASM (wasm32-wasi / wasm64) + embeddable `.o` for any C-ABI project.

## What ships today (v0.1 baseline)

| Command | Pipeline | Output |
|---|---|---|
| `sa run <file>` | Flattener → Referee → Interpreter | stdout + exit code |
| `sa build-exe <file>` | Flattener → Referee → LLVM IR → `zig cc` | standalone `.exe` |
| `sa build-wasm <file>` | Flattener → Referee → LLVM IR → `zig cc -target wasm32-wasi` | `.wasm` module |
| `sa build-obj <file>` | Flattener → Referee → LLVM IR → `zig cc -c` | `.o` (C-ABI linkable) |

No Zig source generation. No AST construction. No hidden round-trips.

## Checked-in `sa_std` Archive

SA-facing std modules (`io`, `fs`, `net`, `fmt`, `process`) are assembled with `@import` on the SA side and `@extern` declarations in their `.sai` files. C/C++ host examples still use `#include`, but only in host code.

The repository checks in `artifacts/sa_std/libsa_std.a`. Rebuild it with `zig build sa-std-static -Doptimize=Debug`. The implementation source is `src/runtime/sa_std.zig`; the public C header is `src/runtime/sa_std.h`.

## Core Symbols (5 ownership operators + 1 escape)

| Symbol | Semantics | State Effect |
|---|---|---|
| `=` | allocate / bind | target → Active |
| `&` | borrow (read or write determined by Referee dynamically) | source → Locked_Read/Locked_Mut, borrow → Active(BorrowView) |
| `^` | move / consume | source → Consumed |
| `!` | release (borrow → unlock source; ownership → physical free) | target → Consumed |
| `*` | raw pointer escape (only inside `@ffi_wrapper`) | produces Untracked register |
| `$...$` | native code escape block | conservatively consumes referenced registers |

**No `&mut` in syntax.** Shared vs exclusive is decided by Referee's `Locked_Read` / `Locked_Mut` bitmask at verification time.

## Instruction Set (ISA)

### Memory
- `reg = alloc N` — heap allocation
- `reg = stack_alloc N` — stack allocation (lifetime bound to function, no `^` escape)
- `dst = load src+offset [as T]` — read at byte offset
- `store dst+offset, val [as T]` — write at byte offset
- `dst = take src+offset` — extract interior pointer ownership
- `dst = ptr_add base, offset` — reserved for InteriorPtr derivation in the roadmap

### Arithmetic & Logic
- Integer: `add / sub / mul / sdiv / udiv / srem / urem / neg`
- Bitwise: `and / or / xor / shl / lshr / ashr / not`
- Integer comparison: `eq / ne / slt / sle / sgt / sge / ult / ule / ugt / uge`
- Float: `fadd / fsub / fmul / fdiv / fneg`
- Float comparison: `fcmp_eq / fcmp_ne / fcmp_lt / fcmp_le / fcmp_gt / fcmp_ge`
- Type conversion: `trunc / zext / sext / fptosi / sitofp / uitofp / fptrunc / fpext / bitcast`
- SIMD (minimal): `add.v128 / sub.v128 / mul.v128 / shuffle.v128 / extract_lane / insert_lane`

### Atomics
- `dst = atomic_load src+offset [ordering]`
- `atomic_store dst+offset, val [ordering]`
- `dst, ok = cmpxchg target+offset, expected, new [success_ord] [failure_ord]`
- `dst = atomic_rmw_<OP> target+offset, val [ordering]` — OP ∈ {add, sub, and, or, xor, xchg, smin, smax, umin, umax}
- `fence [ordering]`
- Ordering: `relaxed / acquire / release / acq_rel / seq_cst`

### Control Flow
- `jmp L_NAME` — unconditional jump
- `br cond -> L_TRUE, L_FALSE` — conditional branch
- `br_null reg -> L_NULL, L_NOT_NULL` — null check branch
- `call @func(args)` / `call_indirect func_ptr(args)`
- `return [reg]`

## Control Flow and Phi

- SA keeps control flow flat: every block ends with `jmp`, `br`, `br_null`, or `return`.
- Phi consistency is a frontend responsibility. If two incoming edges disagree on a register's capability mask, the frontend must repair the flow before emitting the join label.
- `libsa_scope` is the optional helper for generating the explicit `!reg` cleanup text needed at scope exits and join points.

### Error Propagation
- `v = ? res` — early return if `res.status != 0` (Flattener expands to `br + return`)
- `panic(code)` — unrecoverable termination
- `panic_msg(code, *str_ptr, str_len)` — termination with message
- Function suffix `!` marks fallible return: `@f() -> i32!` → ABI `{u32 status, i32 value}`

### FFI Airlock (only inside `@ffi_wrapper`)
- `raw = *safe` — strip capability mask
- `safe = assume_safe raw` — grant Active mask to raw pointer
- `view = assume_borrow raw [, mut]` — grant FfiBorrow view (no physical free on `!`)

## Capability Mask (10-bit, stored as u16)

```
bit 0  (0x0001)  Active
bit 1  (0x0002)  Locked_Read
bit 2  (0x0004)  Locked_Mut
bit 3  (0x0008)  Consumed
bit 4  (0x0010)  BorrowView
bit 5  (0x0020)  FfiBorrow
bit 6  (0x0040)  Untracked
bit 7  (0x0080)  Fallible
bit 8  (0x0100)  Immutable
bit 9  (0x0200)  InteriorPtr
```

Referee validates ownership by linear scan + bitwise AND/OR. No graph theory. No backtracking.

## Function Signatures

| Rust form | SA signature | Rule |
|---|---|---|
| `fn f(x: i32)` | `@f(x: i32)` | by-value, native numeric only |
| `fn f(r: &T)` / `fn f(r: &mut T)` | `@f(r: &ptr)` | borrow, ty must be `ptr` |
| `fn f(d: T)` (move) | `@f(^d: ptr)` | move, ty must be `ptr` |
| `fn f() -> Box<T>` | `@f() -> ^ptr` | move out |
| `fn f() -> Result<T,E>` | `@f() -> i32!` | fallible ABI |
| `extern fn f(p: *T)` | `@extern f(*p: ptr)` | FFI raw pointer |

**No user-defined type names in signatures.** Layouts live in `#def` dictionaries only.

## Preprocessor

- `#def NAME = VALUE` — text substitution + constant folding (`+/-/*`)
- `#loc "file":line:col` — upstream source mapping (→ DWARF `!DILocation`)
- `[MACRO] NAME %p1, %p2 ... [END_MACRO]` — parameterized text template
- `[REP N] ... [END_REP]` — compile-time unrolling with `%i` cursor
- `EXPAND NAME arg1, arg2` — macro invocation
- `@const NAME = <literal>` — global read-only data (.rodata), no type annotation; roadmap feature

## Global Constants (`@const`)

```
@const HELLO_BYTES = utf8:"hello world"
@const ZEROS_256 = repeat:256 of 0x00
@const CIRCLE_VT = vtable { draw = @Circle_draw, drop = @Circle_drop }
```

No type annotation. Byte length inferred from literal. Roadmap feature: immutable mask cannot `^`, `!`, or exclusive-borrow.

## System Primitives (`@sys_*`)

| Primitive | Native mapping | WASM (WASI) mapping |
|---|---|---|
| `@sys_print(*msg, len)` | `write(1, ...)` | `fd_write` |
| `@sys_read_file(*path, plen, *out_len) -> *buf` | `open+read+close` | `path_open+fd_read` |
| `@sys_write_file(*path, plen, *data, dlen) -> i32` | `open+write+close` | `path_open+fd_write` |
| `@sys_exit(code)` | `_exit` | `proc_exit` |
| `@sys_argv(i) -> *str` / `@sys_argc() -> i32` | process args | `args_get` |

## FFI Airlock

- `@ffi_wrapper` functions are the **only** place where `*` / `assume_safe` / `assume_borrow` are legal.
- Ordinary `@func` using these → `Trap: IllegalUnsafeContext`.
- FFI memory enters sandbox via `assume_borrow` only (no ownership transfer into sandbox).
- Handle/ID pattern for long-lived host objects.
- `@extern` declares C-ABI symbols; `@export` exposes C-ABI symbols without name mangling.

## Build Modes

- `sa build-exe` and `sa build-wasm` default to `--release`; all ownership checks are complete at compile time, so release artifacts carry no Referee runtime.
- `-g` enables DWARF and upstream source mapping.
- `--no-debug` strips debug metadata.
- `--debug-gas` inserts gas counters and may trap with `GasExceeded`.
- `--debug-san` inserts runtime alloc/free bookkeeping for UAF / Double-Free and is intentionally slower.

## Frontend Contract (R20)

- Frontends own scope exit: emit explicit `!reg` for every still-live register when a scope ends.
- Frontends own Phi consistency: every incoming edge to a label must agree on the capability mask, or the frontend must repair the flow before emission.
- Frontends own lowering: `match`, `async`, and hidden Drop insertion are upstream responsibilities, not SA semantics.
- `libsa_scope` is the optional helper for these repairs; SA itself does not infer lifetimes.

## Referee Trap Codes

Authoritative trap catalog: [`docs/errorcode.md`](/home/vscode/projects/sci/docs/errorcode.md).
This section is a compact summary for readers; it may lag the live namespace.

| Trap | Trigger |
|---|---|
| ForbiddenSyntax | `{}` / `if` / `while` / `for` / `a.b.c` in source |
| DuplicateDef | `#def` name repeated |
| DuplicateLabel | same `L_NAME:` twice in one function |
| UnsupportedType | type annotation not in {i8..u64, f32, f64, ptr, v128} |
| MacroRecursionLimit | expansion depth > 256 |
| RegisterRedefinition | macro expansion produces duplicate Active register |
| UnknownRegister | reference to never-assigned register |
| BorrowConflict | read/write/move on Locked_Mut register |
| UseAfterMove | access on Consumed register |
| DoubleMutableBorrow | second exclusive borrow on same source |
| ReadWriteConflict | upgrade Locked_Read to Locked_Mut |
| MemoryLeak | Active/Locked registers remain at function exit |
| CapabilityMismatch | call-site prefix doesn't match signature |
| FallthroughForbidden | basic block doesn't end with jmp/br/return |
| PhiStateConflict | label incoming edges have incompatible masks |
| IllegalUnsafeContext | `*`/`assume_*` outside `@ffi_wrapper` |
| FfiOwnershipViolation | `^`/`!` on FfiBorrow register |
| InteriorPtrEscape | InteriorPtr passed to `@extern` |
| StackEscape | `stack_alloc` product `^` moved or returned |
| ConstMutation | `^`/`!`/exclusive-borrow on `@const` register |
| EarlyReturnLeak | `?` early-return path has unreleased Active registers |
| InvalidParamType | `&`/`^` param ty is not `ptr` |
| InvalidAtomicOrdering | `cmpxchg` failure_ord stronger than success_ord |
| TagMismatch | call-site tag doesn't match signature tag (v0.5) |
| MissingTag | `--strict-tags` mode: `alloc` without `tag` (v0.5) |
| VTableSignatureMismatch | `call_indirect` args don't match vtable slot signature (v0.3) |

## Panic Code Dictionary (R18.6)

| Code | Meaning |
|---|---|
| 100 | DivByZero |
| 101 | OutOfBounds |
| 102 | Unreachable |
| 103 | AssertionFailed |
| 104 | IntegerOverflow |
| 105 | NullDeref |
| 106 | MissingVariant |
| 107 | AllocFailed |
| 108–127 | Reserved |
| 128–255 | User-defined |

## Version Roadmap

| Version | Focus |
|---|---|
| v0.1 | Closed loop: Flattener + Referee + LLVM IR + CLI (14 weeks) |
| v0.2 | Self-authored WASM emitter + `#mode compact` infix sugar |
| v0.3 | Performance: VTable signature check + `libsa_async` macros + `--debug-san` |
| v0.4 | Parallel dev: `.sai` + `.sal` + incremental compilation |
| v0.5 | Ecosystem: `sa.pkg` package manager + `#tag` layout tagging + `sa_std` |
| v0.6 | Certification: Referee formal proof (Coq/Lean4) + FPGA hardware Referee |
| v1.0+ | Self-hosting (SA compiler written in SA) |

## Design Principles

1. **Zero AST** — flat arrays + u32 indices. No trees, no graphs.
2. **Linear scan** — all stages are single-pass forward. No backtracking.
3. **O(1) bitmask** — ownership transitions are AND/OR on u16. No constraint solvers.
4. **Five-symbol contract** — `= & ^ ! *` cover all ownership semantics.
5. **Frontend responsibility** — Drop insertion, Phi consistency, monomorphization are upstream's job.
6. **Upstream traceable** — `#loc` → DWARF `!DILocation` → gdb/lldb breakpoints on original source.
7. **Explicit over implicit** — no GC, no hidden Drop, no exception unwinding, no async magic.
8. **Airlock isolation** — all unsafe pointer operations physically confined to `@ffi_wrapper` functions.
9. **Full independence** — SA runs standalone. Interop with Rust/Go/Zig/C++ is optional, via C-ABI.

## Interoperability

SA interoperates with any language through standard C-ABI:
- `@export` produces unmangled symbols callable from C/C++/Rust/Go/Zig.
- `@extern` declares external symbols provided by any C-ABI library.
- `sa build-obj` produces `.o` files linkable with `zig cc`, `gcc`, `clang`, or `cargo`.
- FFI memory safety enforced by airlock: external pointers enter via `assume_borrow` only.

## Testing Model

- `sa run test.sa` + exit code 0/non-zero for pass/fail.
- `ASSERT_EQ` / `ASSERT_TRUE` macros in `sa_core.sa`.
- Must-trap tests: verify Referee correctly rejects invalid code.
- `@export` + external test frameworks (Zig test / Rust #[test] / Google Test).
- Property-based testing: 32 properties × 100+ random iterations.

## Rust -> SA -> LLVM IR Examples

| Case | Rust | SA | LLVM IR sketch |
|---|---|---|---|
| Struct field access | `v.x + v.y` | `#def Vec3_x = +0`, `#def Vec3_y = +4`, `x = load v+Vec3_x as f32` | `getelementptr` + `load` |
| Option + `?` | `let x = read()?;` | `res = call @read(...); x = ? res` | `extractvalue` + `icmp` + `br` |
| dyn Trait + VTable | `obj.draw()` | `@const VT = vtable { draw = @draw }; call_indirect draw_fn(obj_data)` | `load ptr` + indirect call |
| async single poll | `fetch().await?;` | `ctx state labels + poll fn + pending path` | label dispatch + branches |
| Rc clone + drop | `a.clone(); drop(b)` | `atomic_rmw_add` / `atomic_rmw_sub` on `Rc_strong` | `atomicrmw add/sub` |

## Pilot Protocol

- Generate 30 zero-shot prompts: 10 base use cases × 3 variants each.
- Run the prompts against GPT-4o, Claude Opus, and DeepSeek-Coder.
- Record the first-pass Referee pass rate as the observed baseline; do not predeclare a KPI.
- If the baseline drops below 50%, revisit whether the project should add a text-level pseudo-nested frontend before MVP freeze, and carry that decision into the post-MVP roadmap.

## Status

This document reflects the current v0.1 implementation state. Flattener, Referee,
LLVM IR Emitter, Interpreter, CLI, and the layout generator are operational. Remaining
roadmap items are tracked in `tasks.md`.
