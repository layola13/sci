# Verified AOT Lua-to-SA Compiler (Tracked Route) Implementation Plan

> This is the English counterpart of the Chinese document [lua2sa_verified_aot_plan_cn.md](./lua2sa_verified_aot_plan_cn.md).

> **Status (2026-11-05 document audit)**: A planning draft from 2026-06-14; none of the four phases have been implemented in the sci repo (there is no lua2sa command/source). The actual route is the SLA front end and a `bc2sa` subset prototype. This document is archived only; do not cite it as the current state.

> **Design date**: 2026-06-14
> **Core goal**: design a compiler (`lua2sa`) that compiles a strongly typed subset of Lua syntax directly into **fully tracked SA assembly that satisfies Referee static safety verification**.
> **Core metrics**: zero runtime GC overhead, 100% static Referee pass rate, and automatic compile-time determination and injection of lifetime management (`!reg`).

---

## 1. Core idea: simulate dynamic semantics at compile time

To genuinely experience SA's core safety features (affine ownership, zero garbage-collection overhead, strict static lifetime checks), we must abandon the dynamic VM interpreted-execution model. Instead, we use **compile-time static analysis** to translate Lua language constructs directly into SA's native counterparts.

```
Lua source
   │
[Type inference engine] ───────→ (infer static types: i64, ptr, structs)
   │
[Lifetime & escape analysis] ──→ (compute scopes, auto-inject stack_alloc and !reg)
   │
[Monomorphization & codegen] ──→ Tracked safe SA code (.sa + .sal)
   │
[SA Referee verifier] ─────────→ statically verified native binary (zero GC, 100% safe)
```

---

## 2. Mapping table: statically translating Lua semantics to Tracked SA

| Lua dynamic semantics | Static Tracked SA translation strategy |
|---|---|
| **Dynamic variables** | **Static type inference and monomorphization**<br>All variables are inferred at compile time into native SA registers (such as `i64`, `f64`). When the same function is called with different argument types, multiple strongly typed SA function bodies are cloned at compile time. |
| **Garbage collection (GC)** | **Compile-time lifetime analysis (linear/affine types)**<br>The compiler analyzes each variable's lifetime in the AST and automatically injects `!reg` release or free calls right after its last use point, thereby completely eliminating the runtime GC engine. |
| **Dynamic key-value tables** | **Static struct layouts**<br>Tables with fixed fields (such as `{x=1, y=2}`) are lowered at compile time into static struct definitions in a `.sal` file. Field accesses compile directly into CPU offset loads (such as `load t+8`). |
| **Dynamic closures** | **Lexical-scope escape analysis**<br>If a closure's lifetime does not escape the current function (it is not returned, nor stored in a global table), it is allocated directly on the stack. Escaping closures are either forbidden or compiled into strongly owned reference-counted containers. |

---

## 3. Translation example: Lua source $\rightarrow$ fully Tracked static SA

The following shows how a standard Lua snippet is translated through this route into zero-GC-overhead SA code fully protected by static ownership verification.

### Lua source (`math_test.lua`)
```lua
local function multiply(t, factor)
    return t.val * factor
end

local item = { val = 42 }
local result = multiply(item, 2)
return result
```

### Compiled Tracked SA assembly

First, the compiler statically generates a layout file for the table structure:
```sal
// math_test.sal - auto-generated struct layout
#struct ItemLayout {
    val: i64
}
```

Then the compiler generates `.sa` code that fully complies with ownership tracking:
```sa
// math_test.sa - auto-generated Tracked assembly
@import "math_test.sal"

@multiply(t: ptr, factor: i64) -> i64:
L_ENTRY:
    // Field reads are safely guarded and bounds-checked by the math_test.sal layout
    val = load t+0 as i64
    res = mul val, factor
    !t // explicitly consume and reclaim t's ownership
    return res

@export main() -> i64:
L_ENTRY:
    // Allocate the struct space directly on the stack (no heap allocation, no GC pressure!)
    item = stack_alloc 8
    store item+0, 42 as i64
    
    // Call the strongly typed function, passing the statically tracked item pointer
    result = call @multiply(item, 2)
    
    // The compiler can statically ensure that item's ownership was consumed by multiply and properly cleaned up.
    // If item is accessed again afterwards, the SA compiler rejects it with an error.
    return result
```

### Why this approach perfectly demonstrates SA's value:
1.  **Zero runtime GC**: data is stack-allocated via `stack_alloc`, with lifetimes bound entirely to the stack frame.
2.  **Explicit ownership management**: the `item` pointer transfers ownership when passed as an argument and is precisely destroyed at the last exit. If the developer introduces a memory leak in the code, the SA compiler reports an error at compile time.
3.  **Extremely fast execution**: all native CPU instructions (`i64` add/subtract/multiply/divide), with no union dynamic unboxing and no slow metatable dispatch.

---

## 4. Concrete four-phase implementation plan

### Phase 1: Gradual type inference engine (weeks 1–3)
1.  Write a parser in Python or Rust supporting a Lua variant syntax with optional type annotations (gradual typing, e.g. `local x: integer = 1`).
2.  Implement the Hindley-Milner type inference algorithm to infer global types for unannotated variables and function parameters.
3.  For Lua scripts whose definite static types cannot be inferred at compile time (such as variables that change type dynamically, or heterogeneous mixed-type arrays), report an error and refuse to compile.

### Phase 2: Compile-time lifetime and escape analyzer (weeks 4–6)
1.  Build a control flow graph (CFG) for the input Lua code.
2.  Perform **live variable analysis** to precisely locate the statement where each table or string is last accessed.
3.  After the last access point, automatically inject `!ptr` or a memory-release interface call.
4.  Perform **escape analysis**: for tables that do not escape the current function scope, downgrade them from heap allocation to SA stack allocation (`stack_alloc`), squeezing out even more performance.

### Phase 3: Table-to-struct layout mapper (weeks 7–9)
1.  Analyze table initialization statements. For tables with fixed keys (such as `{x=1, y=2}`), transform them in the generated `.sal` layout file into corresponding C-style struct definitions.
2.  Convert all attribute accesses (such as `t.x`) into direct loads/stores based on static memory offsets.
3.  Restrict or outright reject dynamic key addressing (such as `t[var]`), unless `var` is a compile-time constant.

### Phase 4: Monomorphization and code-emission backend (weeks 10–12)
1.  Implement the monomorphization mechanism: if a generic function is called with arguments of different types, automatically clone two strongly typed functions in SA (such as `add_i64` and `add_f64`).
2.  Emit the final Tracked `.sa` safe assembly.
3.  Integrate with the `sci` compiler, using SA's Referee static verifier to safety-scan the generated code, proving it has mathematical-grade memory safety and no memory leaks.

---

## 5. Language limitations (the Lua subset this compiler accepts)

To make compile-time static safety verification feasible, `lua2sa` under this route must impose the following strong constraints on the Lua language:
1.  **Static typing constraint**: runtime variables may not dynamically change their type.
2.  **No mixed-type tables**: tables must behave like C structs or homogeneous single-type arrays.
3.  **No dynamic code execution**: `load` and `loadstring` are not supported.
4.  **No arbitrary cyclic references**: cyclic references are detected and rejected at compile time, unless an explicitly declared weak-reference container is used.
