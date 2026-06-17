# SlaX: Sla-driven Safe UI Framework Design & Integration Plan

> **Design Date**: June 14, 2026
> **Version**: v0.1-draft
> **Module Path**: `/home/vscode/projects/sa_plugins/sa_plugin_sax`
> **Core Idea**: Introduce Sla's static typing, expression syntax, method chaining, and automatic lifetime cleanup to the SAX (Safe ASM XML) framework. This completely eliminates the pain of writing low-level SA assembly for frontend UI development, establishing a safe and highly productive **SlaX (Sla + SAX)** development experience.

---

## 1. Motivation & Pain Point Analysis

In the current **SAX** framework (see [sax_design.md](file:///home/vscode/projects/sci/docs/sax_design.md)), although developers can use XML declarations for the DOM tree, the underlying component state management and event handling logic (`@handler`) must still be written in **low-level SA assembly**. This introduces severe friction:
1. **Explicit Memory Leak Management**: Developers must manually list `!stateVar1 !stateVar2` at the end of every component. Forgetting a single variable triggers a `SaxStateLeak` trap.
2. **Verbose Manual Loading & Storing**: Accessing state requires writing explicit register load/store offsets (e.g., `count = load state+Counter_count as i64`), which is mentally taxing and error-prone.
3. **Flat Control Flow Constraints**: Conditional branching (`if/else`) and loops are forbidden inside event handlers. Developers must manually construct label jumps (`br` / `jmp`) and flat labels.
4. **No Advanced Method Chaining**: For common UI structures like `Vec` or `String`, developers cannot call `items.push(x)`. They must resort to nested FFI function calls.

**SlaX** resolves this by integrating the **Sla compiler frontend** directly into the SAX compilation pipeline, allowing developers to write component logic using modern Sla syntax.

---

## 2. Compilation Pipeline Evolution: SAX to SlaX

By introducing Sla, the SlaX compiler pipeline abstracts away low-level SA assembly generation:

```
                    .slax Source File (XML DOM + Sla Syntax)
                                     │
                                     ▼
                               [SlaX Parser]
                       ├── Parses XML into DOM structure
                       └── Extracts Sla state and function blocks
                                     │
                                     ▼
                           [Airlock Sla Codegen]
                       └── Translates XML DOM to high-level Sla
                           (auto-generates init() & render() in Sla)
                                     │
                                     ▼
                          [Sla Compiler Frontend]
                       ├── 1. Parsing & Type Checking
                       ├── 2. Monomorphization (Generics)
                       ├── 3. Hygienic Macro Expansion
                       ├── 4. Lifetime Analysis & Automatic `!` Injection
                       └── 5. Loop Stack Allocation Hoisting
                                     │
                                     ▼
                        Generated .sa & Layout (.sal)
                                     │
                                     ▼
                        [SA Referee Verifier] (verifier.zig)
                                     │
                                     ▼
                       [LLVM-C Backend] ➔ WebAssembly (.wasm)
```

**Key Advantages**:
*   **Simplified SAX Lowering**: The SAX Parser no longer manages registers, branch flattening, or variable cleanups. It simply outputs high-level Sla code and delegates low-level generation to the Sla Compiler.
*   **Zero-Leak Guarantees**: Using Sla's **implicit lifetime cleanup**, state variables and local event handler variables are automatically released at scope exit. Hand-written `!count` lists are obsolete.

---

## 3. SlaX Syntax Definition & File Format (`.slax`)

`.slax` is the source file format for the SlaX framework. Its structure is defined as follows:

```xml
<Component name="ComponentName">
  <state>
    // State declarations: Uses Sla variable definition syntax (let)
    let state_var1: Type = init_expr;
  </state>

  <!-- Declarative XML DOM Tree -->
  <div class="container">
    <h1>{state_var1}</h1>
    <button onclick={^handler}>Action</button>
  </div>

  // Event handlers and component logic: Written as standard Sla functions
  fn handler() {
      // Structured Sla code supporting if/else, loops, and method chaining
  }
</Component>
```

Key differences from `.sax`:
*   The `release_stmt` block at the bottom of components (e.g. `!stateVar1 ...`) is removed.
*   The `<state>` block declares variables using standard Sla `let` statements.
*   All `@handler:` blocks are replaced with standard Sla function definitions `fn handler_name() { ... }`, eliminating `L_ENTRY:` boilerplates and manual `ret` instructions.

---

## 4. Typical Integration Example: Counter

### SlaX Source (`Counter.slax`)
```xml
<Component name="Counter">
  <state>
    let count: int = 0;
    let last: int = 0;
  </state>

  <div class="counter">
    <h1>{count}</h1>
    <p>Last updated: {last} ms ago</p>
    <div class="buttons">
      <button onclick={^inc}>+1</button>
      <button onclick={^dec}>-1</button>
      <button onclick={^reset}>Reset</button>
    </div>
  </div>

  // Increment
  fn inc() {
      count = count + 1;
      last = sax_get_time();
      render(); // Triggers UI re-render
  }

  // Decrement
  fn dec() {
      count = count - 1;
      last = sax_get_time();
      render();
  }

  // Reset
  fn reset() {
      count = 0;
      last = sax_get_time();
      render();
  }
</Component>
```

### Lowered Sla Code Representation (Assembled in Compilation Memory)

The SlaX Parser compiles the DOM tree into Sla functions interacting with the Airlock and merges them with the user's Sla state and functions:

```sla
// 1. Auto-generated component state and DOM layouts
struct CounterState {
    count: int,
    last: int
}

struct CounterDom {
    node_display: ptr,
    node_btn_inc: ptr,
    node_btn_dec: ptr,
    node_btn_reset: ptr
}

// 2. Auto-generated initialization and mount function
fn sax_counter_init() {
    let state = CounterState { count: 0, last: 0 };
    
    // Query DOM nodes
    let dom = CounterDom {
        node_display: sax_dom_query("#display"),
        node_btn_inc: sax_dom_query(".btn-inc"),
        node_btn_dec: sax_dom_query(".btn-dec"),
        node_btn_reset: sax_dom_query(".btn-reset")
    };
    
    // Bind event handlers (borrowing the handler functions)
    sax_dom_bind_event(&dom.node_btn_inc, "click", &sax_counter_inc);
    sax_dom_bind_event(&dom.node_btn_dec, "click", &sax_counter_dec);
    sax_dom_bind_event(&dom.node_btn_reset, "click", &sax_counter_reset);
    
    // Execute initial render
    sax_counter_render(&state, &dom);
}

// 3. Auto-generated renderer function
fn sax_counter_render(state: &CounterState, dom: &CounterDom) {
    let buf = stack_alloc(32);
    let blen = sax_itoa(state.count, &buf);
    sax_dom_set_text(dom.node_display, &buf, blen);
}

// 4. Lowered user event handlers (accepting state and DOM contexts)
fn sax_counter_inc(state: &CounterState, dom: &CounterDom) {
    state.count = state.count + 1;
    state.last = sax_get_time();
    sax_counter_render(state, dom);
}

fn sax_counter_dec(state: &CounterState, dom: &CounterDom) {
    state.count = state.count - 1;
    state.last = sax_get_time();
    sax_counter_render(state, dom);
}

fn sax_counter_reset(state: &CounterState, dom: &CounterDom) {
    state.count = 0;
    state.last = sax_get_time();
    sax_counter_render(state, dom);
}
```
*The Sla Compiler then takes this combined Sla code and lowers it directly to statically verified SA assembly.*

---

## 5. Advanced Example: TodoList (With Generics & Method Chaining)

This example illustrates using `Vec` generic containers, method chaining, and automatic lifetime management in SlaX.

```xml
<Component name="TodoList">
  <state>
    let items: Vec<TodoItem> = Vec::new();
    let input_buf: String = String::new();
  </state>

  <div class="todo-app">
    <h1>Todo List</h1>
    <div class="input-row">
      <input 
        type="text" 
        id="todo-input" 
        placeholder="What needs to be done?" 
        value="{input_buf}" 
        oninput={^handleInput} />
      <button onclick={^addTodo}>Add</button>
    </div>
    <ul id="todo-list">
      <!-- Renders dynamically -->
    </ul>
  </div>

  // Handle typing input
  fn handleInput(val: String) {
      input_buf = ^val; // Transfer ownership to update input buffer
      render();
  }

  // Add a new todo item
  fn addTodo() {
      if input_buf.len() > 0 {
          let item = TodoItem {
              text: ^input_buf, // Transfer text ownership
              completed: false
          };
          
          // Method chaining and automatic Borrow/Move promotion
          items.push(^item); 
          
          // Reset input box
          input_buf = String::new();
          render();
      }
      // items and input_buf lifetimes are managed safely by the framework.
      // No manual releases are required, ensuring zero memory leaks.
  }
</Component>
```

---

## 6. SlaX-Specific Referee Verification Optimizations

By utilizing the Sla compiler frontend, several complex SAX Referee verification rules are bypassed:

1.  **`SaxStateLeak` (Obsoleted)**: Since Sla tracks variable lifespans and handles cleanups implicitly, the compiler automatically injects `!state` and `!dom` cleanups at the exits of `init` and `destroy` functions. Hand-written cleanups are no longer required.
2.  **`SaxRenderOutsideHandler` (Compile-time Checked)**: Because `render()` is a normal Sla function, the compiler's call-graph analyzer statically validates that it is only invoked within event handlers or lifecycle callbacks.
3.  **`ForbiddenSyntax` (Obsoleted)**: Since Sla supports `if/else` and loops natively, the parser no longer restricts control flow inside event handlers. The compiler automatically lowers them to flat SA jumps, unlocking full expressive power for developers.
