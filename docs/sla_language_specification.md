# Sla: Safe Linear Language Specification & Design Report

> **Design Date**: June 14, 2026
> **Version**: v0.1-draft
> **Target Platform**: SA (Safe ASM) v0.1
> **Goal**: Define a simple, statically-typed scripting language with AST support that compiles directly to fully tracked, safe SA, natively resolving SA's ownership/branching limitations.

---

## 1. Core Language Identity & Philosophy

**Sla** (pronounced /slɑː/) is a high-level scripting language designed from the ground up to compile to **SA (Safe ASM)**. It bridges the gap between SA's low-level affine constraints and developer productivity by implementing:
1.  **An AST-Driven Compiler**: Avoids the low-level combinatorial parsing explosion of SA by employing a structured AST frontend.
2.  **Statically Tracked Affine Type System**: Inherits SA's ownership principles (Move/Borrow) but abstracts away manual register release (`!reg`) and Phi conflict resolution at compile-time.
3.  **Syntactic Abstractions**: Natively supports `if/else`, pattern-matching `switch/match`, and monomorphized generics.

---

## 2. Syntax Design & AST Mappings

Sla uses an expression-oriented, Rust-like syntax.

### A. Primitive Types
Sla primitive types map 1:1 to SA types:
*   `int` $\rightarrow$ `i64` / `u64`
*   `float` $\rightarrow$ `f64`
*   `bool` $\rightarrow$ `u8` (where `0` is false, `1` is true)
*   `T` (e.g. struct type) $\rightarrow$ `ptr` (tracked owned heap/stack pointer of layout `T` under SA Referee)
*   `&T` (borrow type) $\rightarrow$ `ptr` (borrowed pointer under SA Referee)

### B. AST Struct Layout
The compiler parses Sla source into a structured AST:
```
AST Node Types:
├── Program(decls: List[Decl])
├── Decl
│   ├── StructDecl(name: String, generics: List[String], fields: List[Field])
│   └── FuncDecl(name: String, generics: List[String], params: List[Param], ret_ty: Type, body: Block)
├── Stmt
│   ├── Let(name: String, value: Expr)
│   ├── Assign(target: Expr, value: Expr)
│   └── ExprStmt(expr: Expr)
└── Expr
    ├── Literal(val: Any)
    ├── Var(name: String)
    ├── If(cond: Expr, then_branch: Block, else_branch: Block)
    ├── Switch(val: Expr, cases: List[Case])
    ├── Binary(op: Op, left: Expr, right: Expr)
    ├── Call(func: String, generics: List[Type], args: List[Expr])
    └── Borrow(expr: Expr)
```

---

## 3. High-Level Feature Lowering to SA

### 1. `if/else` Statements & Automatic Phi/Cleanup Resolution

In low-level SA, every conditional branch must manually release every live register before jumping to a merge block, which is extremely error-prone and triggers `PhiStateConflict` or `MemoryLeak` traps.

**In Sla**: The compiler tracks the live variable set at every block. When compiling an `if/else` statement, Sla automatically calculates the differences in active registers at the merge point and **automatically injects** the required `!reg` instructions.

#### Sla Source
```sla
let x = alloc_struct();
if cond {
    use_and_consume(x); // x is moved/consumed here
} else {
    // x is not consumed here
}
// Merge point
```

#### Compiled SA Output (Auto-Generated)
```sa
    // x is Active (capability mask: Active)
    br cond -> L_THEN, L_ELSE
    
L_THEN:
    call @use_and_consume(x) // x becomes Consumed
    jmp L_MERGE
    
L_ELSE:
    // x remains Active. To resolve Phi conflict at L_MERGE, 
    // the Sla compiler automatically injects the release:
    !x // x becomes Consumed
    jmp L_MERGE
    
L_MERGE:
    // Sla Referee checks pass: x is Consumed on both incoming edges!
```

---

### 2. Pattern Matching `switch` Statements

SA does not support `switch` or `match`. Sla abstracts this into a pattern-matching `switch` statement and compiles it to flat branch ladders, while automating the cleanup of unmatched values.

#### Sla Source
```sla
switch val {
    1 => return 100,
    2 => return 200,
    default => return 0
}
```

#### Compiled SA Output
```sa
    is_1 = eq val, 1
    br is_1 -> L_CASE_1, L_CHECK_2
    
L_CHECK_2:
    !is_1
    is_2 = eq val, 2
    br is_2 -> L_CASE_2, L_DEFAULT
    
L_CASE_1:
    !is_1
    !val // Sla auto-injects release of unused switch target
    return 100
    
L_CASE_2:
    !is_2
    !val // Sla auto-injects release of unused switch target
    return 200
    
L_DEFAULT:
    !is_2
    !val // Sla auto-injects release of unused switch target
    return 0
```

---

### 3. Monomorphized Generics

SA does not support generic functions or structures. Sla implements **compile-time monomorphization** (similar to C++ templates or Rust generics).

When a generic struct `Box<T>` or generic function `identity<T>(val: T)` is parsed:
1.  The compiler does not generate code for the generic templates directly.
2.  At every call site or instantiation point, Sla records the concrete type parameter (e.g., `Box<int>`, `identity<float>`).
3.  The compiler generates concrete, specialized struct layouts and functions:

#### Sla Generic Definition
```sla
struct Box<T> {
    val: T
}

fn identity<T>(x: T) -> T {
    return x
}
```

#### Generated SA Code (For `Box[int]` and `identity[int]`)
```sal
// layout_box_int.sal - Generated Layout
#struct Box_int_Layout {
    val: i64
}
```
```sa
// code_box_int.sa - Generated Code
@identity_int(x: i64) -> i64:
L_ENTRY:
    return x
```

If instantiated for `Box<Item>` (heap pointer), the compiler generates a specialized layout with pointer types and inserts Referee checks.

---

### 4. Method Chaining & UFCS (Universal Function Call Syntax)

In affine and linear type systems, updating a data structure (such as appending to a `Vec`) typically consumes (Moves) the old instance and returns a new one. To avoid deeply nested function call pyramids like `push(push(v, 1), 2)`, Sla supports method syntax and method chaining.

#### Design Philosophy
Sla does not introduce object-oriented dynamic dispatch at runtime. Instead, it relies on compile-time static lowering via **Universal Function Call Syntax (UFCS)**:
*   **Syntax Translation**: For any expression `x.method(y)`, the compiler inspects the static type of `x` (e.g. `Vec<T>`), resolves the corresponding method on the type, and rewrites the expression into a static function call: `method(x, y)`.
*   **Method Chaining**: If a method returns the receiver type (or any other type), calls can be chained directly: `v.push(1).push(2)` is lowered during AST flattening to `push(push(v, 1), 2)`.

#### Auto-Borrow and Auto-Move
To improve developer ergonomics, Sla's compiler automatically analyzes function signatures to insert ownership operators at call sites:
1.  **Auto-Borrow**: If the first argument of the target function expects a borrow `&T` but the receiver is a value type `v`, the compiler rewrites the receiver to `&v`. For example, `v.len()` is automatically converted to `len(&v)`.
2.  **Auto-Move**: If the first argument of the target function expects an owned value `T` (taking ownership), the compiler rewrites the receiver to `^v`. For example, `v.push(1)` is automatically converted to `push(^v, 1)`.

#### Sla Source
```sla
let v = vec_new();
let final_v = v.push(10).push(20);
```

#### Lowered Static Function Output
```sla
let v = vec_new();
let final_v = push(^(push(^v, 10)), 20);
```

---

### 5. Error Propagation & Postfix `?` Operator

To provide an elegant error propagation mechanism without introducing any new keywords (strictly maintaining Sla's 12-keyword policy), Sla uses the postfix `?` operator.

#### Design Philosophy
*   **Syntax**: `?` is a postfix unary operator that can only be applied to expressions returning `Result<T, E>` (or any type structured with `is_err: bool`, `value: T`, `error: E` fields).
*   **AST Lowering**: `let x = expr?;` is automatically expanded by the compiler to a conditional check:
    1.  If the expression evaluates to an `Err`, the compiler extracts the error payload, runs all automatic scope cleanups (auto-injecting `!`) for active local variables, and returns `Err(error_payload)`.
    2.  If the expression evaluates to `Ok`, it unwraps and returns the inner `value` field using move semantics (`^`), continuing program execution.

#### Sla Source
```sla
fn process_data() -> Result<int, Error> {
    let data = fetch_from_db()?;
    return Ok(data + 1);
}
```

#### Lowered Sla Output
```sla
fn process_data() -> Result<int, Error> {
    let temp_res = fetch_from_db();
    if temp_res.is_err {
        let err = ^temp_res.error;
        !temp_res;
        
        // Auto-generated lifetime cleanups (releasing all active variables in scope)
        
        return Err(^err);
    }
    let data = ^temp_res.value;
    !temp_res;
    
    return Ok(data + 1);
}
```

---

## 4. Complete Sla Example & Compiled SA Mapping

Let's map a complete Sla program containing a generic struct, conditional branching, and pattern matching into statically verified SA.

### Sla Source (`example.sla`)
```sla
struct Option<T> {
    has_value: bool,
    value: T
}

fn process_option(opt: Option<int>) -> int {
    if opt.has_value {
        let val = opt.value;
        !opt; // Consume Option wrapper
        return val;
    } else {
        !opt; // Consume Option wrapper
        return -1;
    }
}

// Added: Numeric range loop example showing how loops are lowered in Sla
fn sum_range(limit: int) -> int {
    let sum = 0;
    for i in 1..limit {
        sum = sum + i;
    }
    return sum;
}
```

### Generated Layout (`example.sal`)
```sal
// Static layout mapping Option<int>
#struct Option_int_Layout {
    has_value: u8,   // offset +0
    value: i64       // offset +8 (aligned)
}
```

### Generated Tracked SA (`example.sa`)
```sa
@import "example.sal"

@process_option(opt: ptr) -> i64:
L_ENTRY:
    // Load fields directly using offsets defined in example.sal
    has_val = load opt+0 as u8
    is_true = eq has_val, 1
    br is_true -> L_THEN, L_ELSE
    
L_THEN:
    !is_true
    !has_val
    // Extract ownership of value field
    val = load opt+8 as i64
    !opt // Free the Option_int_Layout allocation
    return val
    
L_ELSE:
    !is_true
    !has_val
    !opt // Free the Option_int_Layout allocation on the other branch
    return -1

// Added: Lowered loop structure SA assembly from sum_range compilation
@sum_range(limit: i64) -> i64:
L_ENTRY:
    sum = 0
    // Allocate stack space for the loop counter
    i_slot = stack_alloc 8
    store i_slot+0, 1 as i64
    jmp L_LOOP_HEAD

L_LOOP_HEAD:
    i = load i_slot+0 as i64
    is_less = slt i, limit
    br is_less -> L_LOOP_BODY, L_LOOP_EXIT

L_LOOP_BODY:
    !is_less
    sum = add sum, i
    next_i = add i, 1
    store i_slot+0, next_i as i64
    !next_i
    !i
    jmp L_LOOP_HEAD

L_LOOP_EXIT:
    !is_less
    !i
    !i_slot
    !limit // Consume/release the unused limit parameter to balance ownership
    return sum
```

---

## 6. Retention and Evaluation of Ownership Symbols `&`, `^`, `!`

To allow developers to experience SA's core ownership verification model natively, Sla explicitly retains and integrates SA's core ownership symbols in its syntax, creating a hybrid "explicit contract, implicit lifetime cleanup" model.

### A. Move Operator: `^`
*   **Design Choice**: **Fully Retained**.
*   **Syntax**: `let y = ^x;` or `call_func(^x);`.
*   **SA Translation**: Lowers 1:1 to SA's `^`.
*   **Value**: Writing `^x` gives developers direct feedback on when ownership transfer (Move Semantics) occurs. The compiler marks the moved variable `x` as `Consumed` in its symbol table, and any subsequent read access to `x` triggers a compile-time `UseAfterMove` error.

### B. Borrow Operator: `&`
*   **Design Choice**: **Fully Retained**.
*   **Syntax**: `let ref_x = &x;`.
*   **SA Translation**: Lowers 1:1 to SA's `&`.
*   **Value**: Crucial for avoiding unnecessary copies and moves. Using `&x` creates a borrow view. Sla's Borrow Checker statically computes whether it is a `Locked_Read` or `Locked_Mut` borrow and automatically inserts `!ref_x` at the end of the block. The developer experiences SA's race-free, concurrency-safe alias checks without writing manual unlock calls.

### C. Release / Free Operator: `!`
*   **Design Choice**: **Retained for explicit release, supplemented with implicit compiler cleanup**.
*   **Syntax**: `!x;`.
*   **SA Translation**: Lowers 1:1 to SA's `!x`.
*   **Hybrid Design**:
    1.  **Explicit `!x`**: Allows developers to manually free resources mid-scope (e.g. freeing large arrays before a long loop). Once freed, the variable is marked as `Consumed` in the compiler.
    2.  **Implicit Cleanup**: If a variable `x` is still `Active` at the end of a block, the Sla compiler **automatically inserts `!x`** before exiting. This ensures the output SA conforms to Referee's strict memory-leak rules while sparing the developer from typing `!var` repeatedly at every return path.

---

## 7. Development Roadmap for Sla

If we proceed with Sla, the compiler engineering roadmap is simple and structured:

```
[Month 1: Frontend]
  ├── Write Sla Lexer & AST Parser in Rust/Zig (supports if, switch, generics syntax)
  └── Implement Scope and Symbol Table Builder

[Month 2: Type Inference & Monomorphization]
  ├── Implement Static Type Checker & Monomorphizer for generic functions & structures
  └── Generate monomorphized Struct Layouts (.sal)

[Month 3: Lifetime Tracker & Codegen]
  ├── Build control-flow analyzer to track register states
  ├── Auto-inject cleanup (!reg) and resolve branch joins (PhiStateConflict protection)
  └── Emit final Tracked .sa code

[Month 4: Validation]
  └── Run generated code against sci's Referee verifier & native executor
```

---

## 8. Comprehensive Design Example: Sla Source Code File

Below is a complete Sla source code example demonstrating structs, generics, hygienic macros, `if/else`, pattern-matching `switch`, explicit `^` moves, explicit `&` borrows, explicit `!` releases, and compile-time lifetime deduction.

```sla
// 1. Define a generic structure (Option)
struct Option<T> {
    has_value: bool,
    value: T
}

// 2. Define a hygienic macro
macro swap(a, b) {
    let temp = ^a;
    a = ^b;
    b = ^temp;
}

// 3. Define a generic function utilizing ownership transfer
// opt is passed by-value, meaning it is consumed by this function
fn unwrap_or<T>(opt: Option<T>, default_val: T) -> T {
    // Conditional if-else statement
    if opt.has_value {
        // Move the inner value out using '^'
        let val = ^opt.value;
        
        // Explicitly consume the opt wrapper container
        !opt; 
        
        // Explicitly release the unused default_val (avoids MemoryLeak)
        !default_val; 
        
        return val;
    } else {
        let val = ^default_val;
        
        // Explicitly release the empty Option wrapper
        !opt; 
        
        return val;
    }
}

// 4. Define a function processing math, borrowing, hygienic macros, loops, and switch matching
fn process_and_inspect(status: int, config_val: &int) -> int {
    // Borrow dereference operation
    let current_config = *config_val; // read value from borrow pointer
    let offset = 100;
    
    // Numeric loop example: sum 1 to 5 (loop local stack variables are automatically hoisted by the compiler)
    let sum = 0;
    for i in 1..5 {
        let temp = stack_alloc(8); // 8-byte stack allocation, automatically hoisted to avoid Phi conflicts
        store temp+0, i as int;
        sum = sum + (load temp+0 as int);
        !temp; // release local variable
    }
    
    // Call the hygienic macro (renames local variable temp inside the compiler to avoid capture)
    swap(current_config, offset);
    !offset; // release the unused variable
    
    // Pattern-matching switch statement
    switch status {
        200 => {
            // Returns calculation result. config_val is implicitly released (!) 
            // by the compiler at block exit.
            return current_config + sum;
        },
        500 => {
            !sum; // release unused loop variable
            return -1;
        },
        default => {
            !sum; // release unused loop variable
            return 0;
        }
    }
}
```

### Compiler Lowering to SA:
*   An instantiation of `Option<int>` generates a corresponding `Option_int_Layout.sal` with static byte offsets.
*   `unwrap_or<int>` monomorphizes to a safe SA function named `@unwrap_or_int`.
*   The `swap` macro is compiled to an SA `[MACRO]` block, and calls translate to `EXPAND` with alpha-converted variables.
*   The `for i in 1..5` loop lowers to conditional jump structures, and its loop body stack allocations are hoisted before the loop label.
*   The `switch` in `process_and_inspect` is lowered to conditional jump ladders. The compiler automatically generates the required `!current_config` and dereference releases before every block exit.

---

## 9. Minimal Keyword Policy

To keep Sla "as simple as possible," Sla rejects introducing any platform-specific or unconventional keywords (e.g. eliminating `Own` and `Ref`). Sla's keyword set is strictly limited to the following 12 basic C/Rust-style keywords:
*   **Structure & Function**: `struct`, `fn`
*   **Control Flow**: `if`, `else`, `switch`, `return`
*   **Loop Iteration**: `for`, `in`
*   **Variable & Constant**: `let`, `const`
*   **Compilation Modifier**: `inline`
*   **Macro Definition**: `macro`

Ownership state transitions are represented purely through the type syntax itself and the four core operators: `=` (binding), `&` (borrowing), `^` (moving), and `!` (releasing).

---

## 10. Macro Mapping Strategy

In SA, preprocessor macros (`[MACRO]`, `EXPAND`, `#def`) are heavily utilized. In Sla, we make the design choice to **discard unsafe text-level macros (`[MACRO]`)** in favor of compiler features, implementing a **hygienic macro system** in the compiler frontend and lowering it 1:1 to SA's native `[MACRO]`.

### Why Sla Doesn't Need SA-style Raw Text Macros

SA relies on raw text macros to compensate for the lack of generics and automatic scope lifetime cleanups. Sla's compiler handles these features natively via type monomorphization and scope lifetime analysis.

However, a hygienic macro system remains essential for low-level wrapping and code reuse. To ensure safety, Sla introduces **hygienic macros**, completely preventing variable capture and naming conflicts.

---

## 11. Sla Hygienic Macro Design and SA [MACRO] Mapping

To provide Rust-like **hygienic macros** in Sla while lowering them to SA's text-level `[MACRO]` preprocessor, Sla's compiler employs **compile-time name mangling (Alpha-conversion)**.

### The Challenge
*   **SA's `[MACRO]` is Unhygienic**: It performs simple text replacement. Declaring a temporary variable `temp` inside a macro can easily clash with or shadow a variable named `temp` in the caller's scope.
*   **Sla Must Ensure Hygiene**: Local variables declared inside Sla macros must not leak to the caller's scope, and caller variables must not be accidentally captured.

### Hygienic Macro Design in Sla

1.  **Syntax (`macro` Keyword)**:
    Sla defines hygienic macros using the `macro` keyword:
    ```sla
    macro swap(a, b) {
        let temp = ^a;
        a = ^b;
        b = ^temp;
    }
    ```
2.  **Compile-Time Alpha-Conversion**:
    When Sla's parser builds the macro AST, the semantic analyzer renames all local variable declarations inside the macro (e.g. `temp`) to globally unique mangled names (e.g. `swap_temp_unique_99`).
3.  **1:1 Lowering to SA's `[MACRO]`**:
    Sla's compiler outputs a standard SA `[MACRO]`, mapping macro parameters to `%a`, `%b`.

#### Generated SA Output Structure
```sa
    // Generated SA Macro definition with unique, mangled local variable names
    [MACRO] swap_hygiene %a, %b
        swap_temp_unique_99 = ^%a
        %a = ^%b
        %b = ^swap_temp_unique_99
        !swap_temp_unique_99
    [END_MACRO]
```
When `swap(x, y)` is invoked in Sla, the compiler emits the SA macro expansion:
```sa
    EXPAND swap_hygiene x, y
```

This ensures Sla developers get a clean, safe, Rust-like hygienic macro experience, while the compiler maps it 1:1 to SA's native `[MACRO]` under the hood.

---

## 12. Numeric `for` Loops & Automatic Hoisting

Sla supports simple, Rust-like numeric range loops: `for i in start..end { ... }`.

### The Challenge: `stack_alloc` inside Loops
In low-level SA, allocating stack variables (`stack_alloc`) inside a loop body triggers Referee conflicts (like `PhiStateConflict` or `StackEscape`) because the loop cycles back to the label head, making register scopes indeterminate for the verifier.

### Sla's Automatic Hoisting Solution

Sla's compiler resolves this compiler-level constraint in the AST lowering phase:
1.  **Hoisting**: The compiler automatically detects all `stack_alloc` declarations inside a `for` loop body.
2.  **Pre-allocation**: It programmatically hoists these stack allocation statements outside and before the loop label (e.g. `L_LOOP_HEAD`).
3.  **Variable Reuse**: Within the loop body, it reuses the pre-allocated stack slots, emitting `store`/`load` updates without allocating new space.
4.  **Automatic Release**: Once the loop exits, it generates the appropriate `!` instructions to release the stack variables.

#### Sla Source
```sla
for i in 1..5 {
    // The compiler automatically hoists this stack variable to avoid Phi conflicts
    let temp_buf = stack_alloc_bytes(); 
    do_something(&temp_buf, i);
}
```

#### Lowered SA Code (With Hoisting)
```sa
    // 1. Hoisted: Stack allocations placed before loop head
    temp_buf = stack_alloc 16
    i_slot = stack_alloc 8
    store i_slot+0, 1 as i64
    
L_LOOP_HEAD:
    i = load i_slot+0 as i64
    is_less = slt i, 5
    br is_less -> L_LOOP_BODY, L_LOOP_EXIT
    
L_LOOP_BODY:
    !is_less
    // Body uses pre-allocated temp_buf
    call @do_something(&temp_buf, i)
    
    // Increment counter
    next_i = add i, 1
    store i_slot+0, next_i as i64
    !next_i
    !i
    jmp L_LOOP_HEAD
    
L_LOOP_EXIT:
    !is_less
    !i
    // 2. Automatic cleanup: release stack allocations upon loop exit
    !i_slot
    !temp_buf
```
This automatic hoisting allows developers to write clean, scoped block logic inside loops without manually micro-managing assembly stack layouts.
```

---

## 13. Mappings to `sa_std` (Standard Library Mappings)

Sla adheres to the principle of "not reinventing the wheel." Since `sa_std` already contains highly optimized, hand-written implementations of structures like `Box`, `Rc`, `RefCell`, `Vec`, and `HashMap` in SA assembly, Sla provides a simple **`extern` binding mechanism** to map high-level generic interfaces directly to the existing `sa_std` implementations with zero runtime overhead.

### 1. External Layout Mapping (`extern struct`)
Sla supports mapping high-level generic structs to external layouts using `extern struct` declarations:
```sla
// Sla Standard Library Binding (rc.sla)
@import "sa_std/rc.sal" // Import raw layout definitions exported by sa_std

// Declare an external struct, indicating the physical layout is managed externally
extern struct Rc<T>;
```
At compile-time, when Sla monomorphizes `Rc<int>`, it avoids generating a new struct layout and instead references the pre-defined external `Rc_int_Layout`, ensuring ABI-level compatibility.

### 2. External API Mappings (`@extern fn`)
Sla uses the `@extern` modifier to declare external SA functions or macro interfaces:
```sla
// Declare external sa_std APIs
@extern fn sa_std_rc_new<T>(val: T) -> Rc<T>;
@extern fn sa_std_rc_clone<T>(rc: &Rc<T>) -> Rc<T>;
@extern fn sa_std_rc_drop<T>(rc: Rc<T>);
```
At the AST lowering phase, Sla translates high-level calls directly to external SA function `call` instructions:
```sla
// Sla Source
let my_rc = sa_std_rc_new(val);

// Lowered SA Output
my_rc = call @sa_std_rc_new(val)
```

### 3. Automatic Destructor Hooking
For non-primitive resource types (like `Rc<T>`), when they go out of scope, Sla's implicit lifetime cleanup can be configured to emit a call to the registered FFI destructor (e.g. `@sa_std_rc_drop`) instead of a simple `!reg` release (since dropping an `Rc` requires decrementing reference counts and conditional deallocation):
```sla
// Sla Source
{
    let my_rc = sa_std_rc_new(100);
    // business logic
} // end of scope

// Lowered SA Output (automatic FFI destructor invocation)
call @sa_std_rc_drop(my_rc)
```

### 4. Direct Reuse of Native `.sal` and `.sai` Files
To achieve true zero-copy integration and avoid duplicate human declarations, Sla's compiler frontend includes built-in parsers for SA's native `.sal` (layout specification) and `.sai` (interface contract) files:
*   **`.sal` Direct Parsing**: The Sla compiler reads `.sal` files directly from `sa_std` or third-party plugins. It automatically registers the defined struct offsets (e.g., `#struct` structures) inside Sla's type system, sparing developers from re-declaring them.
*   **`.sai` Direct Parsing**: Sla reads external API declarations (e.g., `@extern` function signatures) from `.sai` files using standard `@import` statements, automatically registering FFI function signatures as strongly-typed functions inside Sla.

This accomplishes two critical objectives:
1.  **Guaranteed ABI Consistency**: Sla compiles type layouts and FFI signatures using the exact same `.sal`/`.sai` files checked by the Referee verifier at validation time, completely eliminating risks of ABI drift or manual synchronization errors.
2.  **Instant Plugin Ecosystem Support**: Any existing SA plugin (e.g., `sa_plugin_db`, `sa_plugin_http_client`) providing standard `.sal`/`.sai` files is immediately usable inside Sla through a simple `@import` line, without requiring any middleman glue code.

Using this binding mechanism, the Sla compiler core remains completely agnostic to smart pointers or collection internals, delegating all complex logic to the rich `sa_std` ecosystem through minimal declarative mappings.

---

## 14. Strategic Positioning & Roadmap for Sla Compiler

Sla, as a high-level language designed for the SA static ecosystem, adopts a phased **"decoupled development, safe first"** evolution strategy.

### 1. Strategic Positioning: Plugin-First Approach
To achieve rapid iteration in the early stages while protecting the stability of the core SA compiler (`sci`), the Sla compiler is developed as an **external, standalone SA plugin (`sa_plugin_sla`)**:
*   **Physical Sandbox**: The Sla compiler frontend operates outside the `sci` main repo. Compiler panics or parser errors in the Sla frontend will never impact core `sa compile` or `sa referee` stability.
*   **Decoupled Output**: The Sla plugin behaves purely as a transpiler, reading `.sla` files and writing valid `.sa` assembly and `.sal` layout files. It then delegates the generated files to the core assembler and Referee verifier, ensuring a modular boundary.
*   **Dogfooding the Plugin System**: Developing as a native SA plugin allows us to thoroughly test and validate SA's plugin manifest and permissions model (`sap.json`).

### 2. Evolutionary Roadmap
The Sla compiler lifecycle is divided into two distinct phases:

#### Phase 1: Standalone Transpiler Plugin (sa_plugin_sla)
*   **Target Repository**: Hosted in a separate plugin workspace at `/home/vscode/projects/sa_plugins/sa_plugin_sla`.
*   **Workflow**: Users install it via `sa plugin install sa_plugin_sla`, compile Sla code via `sa sla build app.sla -o app.sa`, and then verify/assemble using the core toolchain.
*   **Milestones**: Stabilize Sla's syntax, complete type-checking and monomorphization logic, run loop hoisting algorithms, and verify output against Referee checks.

#### Phase 2: Core compiler Integration (First-Class Citizen)
*   **Target Repository**: Merge Sla's AST parser and lowering frontend into the core `sci` repository.
*   **Workflow**: The core `sa` CLI natively supports `.sla` file extensions, compiling them directly from Sla ➔ SA ➔ Referee ➔ WASM/EXE through a unified compilation pipeline.
*   **Milestones**: Promote Sla to the default, recommended high-level language for SA development, completely replacing raw, manual SA assembly for writing business logic and plugins.





