# SA Toolchain and Lua2SA (LuaJIT-like) Feasibility Assessment Report

> This is the English counterpart of the Chinese document [lua2sa_evaluation_cn.md](./lua2sa_evaluation_cn.md).

> **Status (2026-11-05 document audit)**: A historical assessment from 2026-06-14; the Lua project in question is not inside the sci repository, and the figures cited have no in-repo source. `bc2sa` is now a top-level command but is still a subset prototype (see the completeness evaluation and the current state of `llvm2sa.zig`), not a complete Lua pipeline.

> **Assessment date**: 2026-06-14
> **Assessment scope**:
> 1. Evaluation of the SA (Safe ASM) toolchain compiler (`/home/vscode/projects/sci`).
> 2. Evaluation of the current state of the Lua interpreter/compiler rewrite hand-written in SA (`/home/vscode/projects/lua/sa`).
> 3. Feasibility analysis of developing `lua2sa` (a LuaJIT-like compiler).
> **Constraints**: assessment only; do not modify or add project code.

---

## 1. Evaluation of the SA toolchain (`sci`) project

SA (Safe ASM) is a low-level safe assembly toolchain based on an explicit affine ownership model, a Referee static verifier, and emitting LLVM-C bytecode and WASM output.

### Core strengths
*   **Compile-time memory safety**: affine ownership and Referee verification catch lifetime errors (such as dangling pointers) at compile time. For example, in the Lua runtime string-clone path, the ownership constraint forced us to clone constants before freeing the `Proto`, avoiding a dangling-pointer design flaw.
*   **Low-level control and native integration**: ideally suited to writing extremely lightweight VM bytecode execution loops, and naturally combines with zero-copy async I/O engines such as `sa_net_uring`.
*   **Precise mathematical semantics**: supports generating precise division and modulo semantics for specific target machines, which is critical for porting Lua's idiomatic floating-point math logic across different CPUs.

### Core architectural bottlenecks (P0 limitations)
Although SA is well suited to writing low-level systems, the lack of high-level abstractions makes directly hand-writing a complex compiler front end in SA face enormous obstacles:
1.  **No structured `switch` / `match`**: multi-way branching relies entirely on chains of `eq` + `br`; as the number of instructions and token types grows, the branch structure expands linearly (for example, 57 VM opcodes require 57 manually maintained branch labels).
2.  **Expensive garbage collection and cleanup overhead**: every branch must manually consume live variables explicitly with `!reg` before exiting. The set of cleanup variables differs across exit paths and cannot be perfectly abstracted with macros, causing cleanup code to grow quadratically with the number of branches.
3.  **No stack allocation inside loops**: `stack_alloc` is not allowed inside a loop (it triggers a `PhiStateConflict`); all variables inside loop bodies must be hoisted outside the loop body in advance.
4.  **No support for AST/IR tree data structures**: SA does not support multi-level pointer trees, which forces hand-written dedicated parsing and code-generation functions for every combination of variable, expression, and operator, causing a "combinatorial explosion" in the number of parser functions.

---

## 2. Progress evaluation of the hand-written Lua rewrite in SA (`lua/sa`)

The current `/home/vscode/projects/lua/sa` branch attempts to reproduce Lua 5.5 entirely in hand-written SA code.

### Actual progress
*   **Covered subset**: implements a parser, a Pratt expression analyzer, a flat VM bytecode execution loop, and a simple runtime supporting `local`, `return`, `if`, and `while`. 458 test cases currently pass.
*   **The truth behind the passing tests**: native `sa build` does compile and pass `testes/all.lua` through `testes/goto.lua`, but this is achieved through **"lexical skipping"** and **stubs**.
    *   When unsupported complex syntax is encountered (such as function bodies, anonymous functions, table constructors, `generic for`), the compiler simply skips compilation by sliding over the text between matching token boundaries. This means the tests pass because the complex core code is silently filtered out at compile time and never actually executed at runtime.
*   **Key blocker**: execution times out when the tests reach `testes/heavy.lua`. This is because the counting logic for lexical skipping is too fragile; when it encounters nested control blocks it ends the skip early, causing complex syntax to be mistakenly sent to the compiler and leading to a VM infinite loop or a `PhiStateConflict` compile failure.

---

## 3. Feasibility evaluation of developing `lua2sa` (a LuaJIT-like compiler)

"Developing a LuaJIT-like `lua2sa`" has sharply different feasibility under different compilation modes:

### Route 1: Runtime JIT compiler (dynamically compiling Lua to SA)
Compile hot bytecode traces into SA code at runtime and execute them, as LuaJIT does.
*   **Feasibility**: ❌ **Completely infeasible**.
*   **Reason**: SA is a static, offline AOT toolchain (relying on the complex Flattener, Referee, and LLVM-C compile/link pipeline). SA has no lightweight runtime JIT compiler that can dynamically link and execute in memory. Generating SA assembly at runtime and then invoking LLVM linking has a time cost (on the order of seconds) that is completely unacceptable in a JIT scenario.

### Route 2: Direct source-translation AOT compiler (Lua source $\rightarrow$ SA assembly code)
Parse the Lua source, translate it directly into corresponding `.sa` assembly source, then compile offline.
*   **Feasibility**: ⚠️ **Extremely difficult, and it would lose SA's safety properties**.
*   **Reasons**:
    1.  **Dynamic typing obstacle**: Lua is dynamically typed while SA is statically verified. When compiling `x = a + b`, since the static types of `a` and `b` are unknown, the generated SA assembly can only box everything as `TValue` pointers and call runtime fallback functions. This makes the generated assembly merely shuffle pointers around, completely losing native CPU execution speed.
    2.  **Memory ownership disconnect**: Lua relies on GC while SA relies on affine single ownership. If the generated SA code were to implement arbitrary sharing and cyclic references, all pointers would have to be marked `Untracked` ("fare-dodger" mode) and a GC runtime written in SA. But that would completely neutralize SA's safety verifier, Referee, turning it into unsafe C.

### Route 3: Bytecode AOT static builder (Lua bytecode $\rightarrow$ SA build code)
This is the path explored by the historical Python script `tools/lua2sa.py`. It first compiles Lua source to bytecode, then emits a piece of SA code whose job is to statically build the `Proto` structures, finally handing them to the hand-written SA-VM for interpreted execution.
*   **Feasibility**: ✅ **Fully feasible (a prototype already exists)**.
*   **Limitations**: this does not bypass the VM interpreter; it merely changes "reading a bytecode file" into "static hard-coded construction". It has no native speedup of JIT and generates a large amount of template boilerplate code.

### Route 4: C-Lua VM $\rightarrow$ LLVM bitcode $\rightarrow$ `bc2sa` translator (best route)
This is currently the most feasible and highest-return approach. Compile the mature official C version of the Lua VM in its entirety to LLVM bytecode, use the optimizer `reg2mem` to eliminate PHI nodes, then translate it via a dedicated `bc2sa` converter into SA assembly in `Untracked` safety mode.
*   **Feasibility**: ⭐ **Highly feasible and most recommended**.
*   **Advantages**: 100% perfect support for the complete Lua 5.4/5.5 language features, avoiding the pain of writing a GC and closure capture in SA, while retaining SA's system-call airlock security isolation.

---

## 4. Architect's recommended route

1.  **Stop hand-writing the SA version of the Lua compiler**: continuing to expand the hand-written `parser.sa` has already hit an engineering bottleneck due to "function combinatorial explosion" and "manual register cleanup".
2.  **Develop a general-purpose `bc2sa` pipeline**: implement a `bc2sa` converter in the `sci` compiler (~1200–1850 lines of Zig code).
3.  **Assimilate official C-Lua into the SA ecosystem**: convert the official Lua C source into SA code via `bc2sa` and deploy it on SA's fast `sa_net_uring` runtime. This achieves 100% Lua parity and SA system-level isolation in the fastest time and with the lowest risk.
