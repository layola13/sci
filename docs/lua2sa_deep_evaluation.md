# Why Direct Lua-to-SA Compilation Is Infeasible: A Low-Level Technical Depth Assessment

> This is the English counterpart of the Chinese document [lua2sa_deep_evaluation_cn.md](./lua2sa_deep_evaluation_cn.md).

> **Status (2026-11-05 document audit)**: A historical argument document from 2026-06-14 with no implementation-status claims; the inflation factors etc. are estimates with no measured source. The direction of the conclusion (go with an SLA front end) is consistent with the actual route later taken.

> **Assessment date**: 2026-06-14
> **Assessment topic**: Low-level conflicts between Lua runtime semantics and the SA (Safe ASM) static verification model
> **Goal**: From five dimensions — type system, memory management, closure scope, instruction inflation, and dynamic execution — deeply analyze why we cannot develop a compiler that directly AOT-compiles Lua source into Tracked-level native SA code.

---

## 1. Type disconnect: dynamic boxing vs. static Referee verification

Lua is a **dynamically typed language**: variables themselves carry no type constraints, only runtime values have types. SA, by contrast, is a **statically verified assembly language**: every register must have a definite static type at compile time (such as `i64`, `ptr`, etc.) so that Referee can perform linear safety checks.

### The dynamic dispatch problem
In Lua, even the simplest addition `x = a + b` is highly polymorphic. At runtime the operands may be integers, floating-point numbers, strings requiring implicit conversion, or tables with an `__add` metamethod bound.

If we compiled it directly into SA assembly:
1. SA cannot directly emit a CPU instruction like `t = add a, b`, because the concrete types of `a` and `b` are simply unknown at compile time.
2. The compiler must represent every Lua variable in SA as a huge boxed union — a `LuaTValue` structure pointer.
3. The corresponding direct SA code generation has to become extremely tedious type-dispatch logic:
    ```sa
    // Simulate dynamic type checks and multi-dispatch in SA
    a_tag = load a+0 as u64
    b_tag = load b+0 as u64
    is_int_a = eq a_tag, LUA_TINTEGER
    is_int_b = eq b_tag, LUA_TINTEGER
    both_int = and is_int_a, is_int_b
    br both_int -> L_FAST_ADD, L_SLOW_DISPATCH
    
    L_FAST_ADD:
        a_val = load a+8 as u64
        b_val = load b+8 as u64
        res_val = add a_val, b_val
        store x+0, LUA_TINTEGER as u64
        store x+8, res_val as u64
        jmp L_DONE
        
    L_SLOW_DISPATCH:
        // Call a hand-written C-style runtime helper to look up the metatable, handle floats or string conversion
        call @lua_runtime_add_fallback(&a, &b, &x)
        jmp L_DONE
    ```
4. **Conclusion**: direct translation does not produce "native SA instructions"; it turns simple Lua logic into countless pointer loads/stores and slow runtime interface calls. This amounts to "hand-writing an interpreter in assembly" and kills performance outright.

---

## 2. Memory disconnect: garbage collection (GC) vs. affine ownership

This is the most fundamental physical limitation.
*   **Lua** memory lifetimes are governed by a **garbage collector (GC)**. Objects (tables, closures, strings) can hold arbitrary shared references among themselves and can even form cyclic references (for example `t.self = t`).
*   **SA** enforces strict **affine ownership**. Any allocated resource can have only one owner at any given time. Once assigned to a new variable or passed into a function, its ownership is immediately consumed (`^` / `Consumed`). Unless one falls back entirely to the unsafe FFI `Untracked` pointer mode, SA does not allow any form of cycles or multi-way sharing.

### Collapse of the variable-tracking chain
If we translated the creation of a Lua table directly into SA-tracked safe ownership code:
```lua
local t = {}
t.self = t  -- cyclic reference
return t
```
Under Tracked SA mode this simply cannot pass static verification:
1. If `t` is an ownership-protected SA pointer, executing `t.self = t` triggers a Move violation. Writing the field consumes `t` itself, making it impossible to reference `t` again later in the outer scope.
2. Even without cyclic references, because references can be shared arbitrarily at runtime (for example by being stored in a global table), SA cannot determine at static compile time exactly when a given table should be freed (`!`).
3. **The only compromise**: the generated SA must abandon Referee verification, mark all pointers as `Untracked` (unsafe mode), and implement a garbage-collector runtime on the SA side. But that directly eliminates the physical value of SA's static ownership verification.

---

## 3. Scope disconnect: Lua upvalues vs. SA stack physical isolation

Lua supports closures: an inner function can read and modify the local variables of its outer function (i.e., upvalues). When a closure outlives its outer function, the captured variable automatically "escapes" from the stack into heap memory (becoming a Closed Upvalue).

```lua
function create_counter()
    local count = 0
    return function()
        count = count + 1
        return count
    end
end
```

### SA's stack isolation and aliasing conflicts
1. SA enforces strict stack isolation. A child function has no way to read or write the local variable registers of a parent function across the call-stack boundary.
2. Under SA's affine model, two functions cannot mutably share the same heap pointer without violating the Referee aliasing rule (only one active mutable reference at a time).
3. To compile closures, a direct translator must fully simulate Lua's complex `UpVal` structure:
    *   All **local variables that might be captured by a closure** must abandon stack-register allocation from the moment of declaration and instead allocate a shared box on the heap (an `UpVal` structure).
    *   Every read/write of `count` must compile into double indirection (first load the upvalue pointer, then load the actual value).
4. This heap simulation is inefficient and leaves the generated SA code riddled with addressing details, making it extremely hard for the LLVM backend to perform register optimization on it.

---

## 4. Instruction inflation: compensation for the lack of Switch/Match and manual cleanup

In low-level SA assembly, since there is no `switch` construct and every branch must explicitly destroy all no-longer-used live variables before exiting (`!reg`), directly translating Lua control flow causes the generated assembly file to grow explosively.

For example, take the following single line of Lua:
```lua
obj.width = width + 10
```
When translated directly, the corresponding SA instructions that must be generated include:
*   Check whether `obj` is a table (conditional branch).
*   Check whether `width` is a number (conditional branch).
*   Resolve the metatable branch.
*   At the branch exit of every jump path, manually release the ownership of all temporary registers (`!obj`, `!width`, etc.).

This single line of Lua produces **50 to 100 lines of SA code**. An ordinary 1,000-line Lua script translates into **over 50,000 lines of massive SA assembly**:
*   This greatly increases the memory footprint of the `sci` compiler's Flattener and Referee analysis stages, and can even cause compilation timeouts.
*   Because every exit path copies a large number of `!reg` cleanup instructions, the compiled native binary size balloons sharply.

---

## 5. Dynamic execution barrier (dynamic load)

One of Lua's core features is the ability to dynamically load and execute string code:
```lua
local f = load("return " .. arg[1])
print(f())
```
If `lua2sa` wanted to support `load`:
1. The compiled native binary would have to embed a complete Lua-to-SA compiler front end.
2. In addition, the binary would have to carry the entire `sci` compiler itself (written in Zig and depending on LLVM).
3. This is physically infeasible. Therefore, direct translation to SA inevitably faces the complete loss of the dynamic-loading feature, unless one falls back to the current VM interpreted-execution mode.

---

## Summary

Directly translating Lua into safe Tracked SA suffers from a fundamental **impedance mismatch**. It tries to force a dynamic, strongly GC-dependent scripting language into a low-level, statically verified, single-ownership-based affine assembly language.

If we must use SA, we **should not compile general Lua source**. The correct strategic route is:
*   **Route A**: use `bc2sa` to assimilate the official C-Lua interpreter in its entirety and compile it into unsafe `Untracked` mode, with SA only performing outermost FFI airlock syscall interception.
*   **Route B**: directly create a new, safe linear-AST language that perfectly matches SA's physical characteristics (such as **Sla**), converging all types, lifetimes, and deallocation actions at compile time.
