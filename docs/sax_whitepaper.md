# SAX Whitepaper v0.1

SAX (Symbolic Affine XML) is the frontend UI dialect of SA. It compiles `.sax` component files
directly to WebAssembly + HTML — no JavaScript runtime, no GC, no hidden allocations.

**Prerequisite**: Read `docs/whitepaper.md` first (SA base language). SAX reuses SA's entire
ISA, ownership model, and Referee verbatim. This paper only documents the delta.

---

## Identity

- **Not a JS framework**: SAX compiles to WASM. There is no JavaScript bundle.
- **Not a templating engine**: SAX is lowered to `.saasm` and verified by the same Referee.
- **Not a new language**: SAX is SA with one added layer — an XML structure wrapper.
- **Full ownership**: Every state variable is tracked by Capability Mask. Leaks are compile errors.

---

## What ships in SAX v0.1

| Command | Pipeline | Output |
|---|---|---|
| `saasm sax build <file.sax>` | SAX Parser → Flattener → Referee → WASM Emitter → Airlock Gen | `app.wasm + airlock.js + index.html` |
| `saasm sax check <file.sax>` | SAX Parser → Flattener → Referee (SAX rules) | Trap report or OK |
| `saasm sax new <name>` | scaffold | project directory |

---

## Core Concepts (4 additions on top of SA)

| SAX Concept | SA Equivalent | Purpose |
|---|---|---|
| `<Component name="X">` | `@export` function group | UI component boundary |
| `<state> v = 0 </state>` | `alloc` + `Active` mask | reactive private state |
| `{expr}` interpolation | `load` + Airlock `set_text` | bind state to DOM text/attr |
| `onclick={^handler}` | `BorrowView` + Airlock `bind_event` | attach event listener |

Everything else — `@handler:`, `L_LABEL:`, `br`, `jmp`, `!var`, `load`, `store`, `add`, etc. —
is **identical to standard SA**. No new instructions. No new operators.

---

## File Structure

Every `.sax` file contains one or more `<Component>` blocks:

```
<Component name="NAME">

  <state>                      ← optional; omit for stateless components
    var1 = INIT_EXPR
    var2 = alloc N
  </state>

  DOM_TREE                     ← XML markup with {expr} and event={^fn}

  @handlerName:                ← one or more event handlers
  L_ENTRY:
    SA_INSTRUCTIONS
    ret

  !var1 !var2                  ← release ALL state vars; missing → SaxStateLeak
</Component>
```

---

## Ownership Rules (SAX additions to R4)

SAX adds 5 new Referee rules on top of SA's existing 23 Traps:

| Trap | Trigger |
|---|---|
| `SaxStateLeak` | A `<state>` variable is still `Active` at component destroy exit |
| `SaxEventEscape` | `^handler` references a function outside the same `<Component>` |
| `SaxRenderOutsideHandler` | `call @render()` appears outside a `@handler` body |
| `SaxInvalidInterpolation` | `{expr}` contains `^` (Move) or `!` (Release) |
| `SaxStateWriteFromOutside` | Code outside the component writes to its state memory slot |

All other SA Traps remain active: `MemoryLeak`, `UseAfterMove`, `BorrowConflict`, etc.

---

## State Variables

```xml
<state>
  count  = 0             <!-- i64 (default integer) -->
  ratio  = 0.0           <!-- f64 (default float) -->
  flag   = 0 as i1       <!-- boolean -->
  buf    = alloc 256     <!-- heap buffer: 256 bytes, ptr type -->
  items  = alloc 24      <!-- dynamic array fat-pointer: data_ptr+len+cap (8+8+8) -->
</state>
```

Rules:
- One declaration per line.
- Types follow SA literal inference (same as `.saasm`).
- `alloc N` = heap allocation of N bytes. The Lowerer emits the `alloc` SA instruction.
- Every `<state>` var **must** appear in the `!release_stmt` at the end of the component.
  Missing release → `SaxStateLeak`. Extra release of nonexistent var → `UseAfterMove`.

---

## DOM Markup

### Static node

```xml
<div class="card">
  <h2>Hello</h2>
</div>
```

Lowered to Airlock calls: `sax_dom_create("div")`, `sax_dom_add_class(...)`,
`sax_dom_append_child(...)`, `sax_dom_set_text(...)`.

### Text interpolation

```xml
<h1>Count: {count}</h1>
<p class="{status_class}">Status</p>
```

`{expr}` inside text → `sax_dom_set_text(node, load state+offset)`.  
`{expr}` inside attribute → `sax_dom_set_attr(node, "class", load state+offset)`.

`expr` must be a **read-only** SA expression: `load`, arithmetic ops, no `^` or `!`.

### Event binding

```xml
<button onclick={^inc}>+1</button>
<input oninput={^handleInput} />
```

`^handler` = `BorrowView` mask on the handler function reference.  
Lowered to `sax_dom_bind_event(node, "click", handler_export_idx)`.

`handler` must be defined in the **same** `<Component>`. Cross-component → `SaxEventEscape`.

Supported events: `onclick` `oninput` `onchange` `onsubmit` `onkeydown` `onkeyup`
`onfocus` `onblur` `onmouseenter` `onmouseleave`.

---

## Event Handlers

```
@handlerName:
L_ENTRY:
    // pure SA-ASM: load/store/add/sub/call/br/jmp...
    // modify state, then call @render()
    ret
```

Rules:
- Function body is **identical to `.saasm`** — full SA ISA, flat control flow, no `{}`.
- Access state via `load state_ptr+OFFSET as TYPE`.
- Modify state via `store state_ptr+OFFSET, value as TYPE`.
- Call `call @render()` after state mutations to update the DOM.
- `call @render()` is only legal inside a `@handler` — elsewhere → `SaxRenderOutsideHandler`.
- Use `L_LABEL:` + `br`/`jmp` for all branches and loops. `if`/`while`/`for` → `ForbiddenSyntax`.

---

## Minimal Complete Example — Counter

```xml
<Component name="Counter">

  <state>
    count = 0
    last  = 0
  </state>

  <div class="counter">
    <h1>{count}</h1>
    <button onclick={^inc}>+1</button>
    <button onclick={^dec}>-1</button>
  </div>

  @inc:
  L_ENTRY:
    count = load state+Counter_count as i64
    count = add count, 1
    store state+Counter_count, count as i64
    last  = call @sax_get_time()
    store state+Counter_last, last as i64
    call @render()
    ret

  @dec:
  L_ENTRY:
    count = load state+Counter_count as i64
    count = sub count, 1
    store state+Counter_count, count as i64
    last  = call @sax_get_time()
    store state+Counter_last, last as i64
    call @render()
    ret

  !count !last
</Component>
```

Build:

```
saasm sax build counter.sax
# → dist/app.wasm  dist/airlock.js  dist/index.html
```

---

## Branching in Handlers (SA flat style)

```
@handleSubmit:
L_ENTRY:
    len = load state+TodoList_input_len as i64
    ok  = sgt len, 0
    br ok -> L_DO, L_SKIP
L_DO:
    call @sax_array_push(&items, &input_buf, len)
    store state+TodoList_input_len, 0 as i64
    call @render()
    jmp L_END
L_SKIP:
    jmp L_END
L_END:
    ret
```

No `if`. No `{`. Labels + `br`. This is identical to standard SA.

---

## Loops in Handlers

```
@renderList:
L_ENTRY:
    i   = 0
    end = load state+TodoList_items_len as i64
L_LOOP:
    cond = ult i, end
    br cond -> L_BODY, L_END
L_BODY:
    row = call @sax_array_get(&items, i)
    call @sax_dom_append_row(list_node, row)
    i = add i, 1
    jmp L_LOOP
L_END:
    ret
```

---

## Component Lifecycle (Phase 2)

Phase 1 has no explicit lifecycle hooks — the Lowerer auto-generates init and destroy functions.  
Phase 2 adds optional hooks:

```
@onMount:          <!-- called after component is inserted into DOM -->
L_ENTRY:
    id = call @sax_set_interval(^onTick, 1000)
    store timer_id, id as i64
    ret

@onUnmount:        <!-- called before component is removed from DOM -->
L_ENTRY:
    id = load timer_id as i64
    call @sax_clear_interval(id)
    ret
```

---

## Airlock API Quick Reference

Full documentation: `docs/sax_airlock.md`. Most-used Phase 1 APIs:

| API | JS Equivalent |
|---|---|
| `sax_dom_set_text(node, ptr, len)` | `node.textContent = str` |
| `sax_dom_set_attr(node, key_ptr, klen, val_ptr, vlen)` | `node.setAttribute(k, v)` |
| `sax_dom_add_class(node, cls_ptr, len)` | `node.classList.add(cls)` |
| `sax_dom_remove_class(node, cls_ptr, len)` | `node.classList.remove(cls)` |
| `sax_dom_get_value(node, buf, len)` | `input.value` |
| `sax_dom_set_value(node, ptr, len)` | `input.value = str` |
| `sax_dom_bind_event(node, evt_ptr, elen, fn_idx)` | `node.addEventListener(evt, fn)` |
| `sax_dom_query(sel_ptr, slen)` | `document.querySelector(sel)` |
| `sax_dom_create(tag_ptr, tlen)` | `document.createElement(tag)` |
| `sax_dom_append_child(parent, child)` | `parent.appendChild(child)` |
| `sax_dom_remove_self(node)` | `node.remove()` |
| `sax_get_time()` | `Date.now()` |
| `sax_itoa(val, buf, len)` | `val.toString()` |

All APIs must be called inside `@ffi_wrapper`-tagged functions (the Lowerer auto-generates these).
Direct calls from regular `@handler` code go through the generated wrapper layer.

---

## DOM Tag Whitelist

Only these HTML5 tags are accepted. Others → `SaxUnknownTag`.

**Layout**: `div` `section` `article` `header` `footer` `main` `nav` `aside`  
**Text**: `h1` `h2` `h3` `h4` `h5` `h6` `p` `span` `label` `strong` `em`  
**Form**: `button` `input` `textarea` `select` `option` `form`  
**List**: `ul` `ol` `li`  
**Table**: `table` `thead` `tbody` `tr` `th` `td`  
**Media**: `img` `video` `canvas`  
**SAX reserved** (uppercase): `<Router>` `<Page>` `<Slot>`

---

## SAX-Specific Trap Reference

In addition to all 29 SA Traps (see `docs/errorcode.md`), SAX adds:

| Trap | Stage | Message |
|---|---|---|
| `SaxStateLeak` | Referee | `<state> variable 'X' not released at component end` |
| `SaxEventEscape` | Referee | `^handler 'X' is not defined in this <Component>` |
| `SaxRenderOutsideHandler` | Referee | `call @render() is only legal inside @handler` |
| `SaxInvalidInterpolation` | SAX Parser | `interpolation {expr} must not contain ^ or !` |
| `SaxStateWriteFromOutside` | Referee | `state slot of 'ComponentX' written from outside component` |
| `SaxUnknownTag` | SAX Parser | `tag <foo> is not in the SAX whitelist` |
| `SaxUnknownEvent` | SAX Parser | `event 'onhover' is not supported; did you mean 'onmouseenter'?` |

---

## Comparison: SAX vs React vs Vue

| | React | Vue SFC | **SAX** |
|---|---|---|---|
| Language | JS/TS | JS/TS | **SA (assembly-level)** |
| Output | JS bundle | JS bundle | **WASM** |
| State | `useState` / Hook | `ref` / `reactive` | **`<state>` explicit ownership** |
| Memory safety | GC | GC | **Referee compile-time** |
| GC pauses | yes | yes | **none** |
| Memory leaks | runtime, hard to find | runtime | **compile error: SaxStateLeak** |
| LLM generation | medium | medium | **high (flat, structured)** |
| Control flow | JSX expressions | `v-if` / `v-for` | **flat `L_LABEL:` + `br`** |

---

## What SAX intentionally does NOT provide

- No `v-if` / `v-for` / `v-model` directive syntax
- No JSX expression nesting (`{items.map(...)}`)
- No implicit reactive tracking (no Proxy, no dependency graph at runtime)
- No `async`/`await` in handlers (use CPS / state machine lowering, same as SA)
- No CSS-in-JS (use external `.css` + `class` attribute, or `<style>` block in Phase 2)
- No SSR / hydration (WASM-first, browser-only in Phase 1)
- No hidden Drop (every `<state>` var must be explicitly `!released`)
- No operator precedence in `{expr}` (break into multiple `load`/`op` SA instructions)

---

## LLM Generation Guide

When generating `.sax` files:

1. **Start with `<Component name="X">`** — always the outermost wrapper.
2. **Declare all state in `<state>`** before the DOM tree.
3. **Write flat SA-ASM in `@handler` bodies** — use `L_LABEL:` + `br`/`jmp`, never `if`/`while`.
4. **Call `call @render()` after every state mutation** — exactly once per handler, at the logical end.
5. **End with `!var1 !var2 ...`** — list every `<state>` variable, or Referee will reject.
6. **Use `{varName}` only for read-only interpolation** — no `^`/`!` inside braces.
7. **Bind events with `onclick={^handlerName}`** — `handlerName` must exist in the same component.

Checklist before emitting (reduces first-pass Referee failures):
- [ ] Every `<state>` var has a matching `!var` at the end
- [ ] No `{` `}` in SA code blocks (only in XML attributes/text)
- [ ] No `if` / `while` / `for` — use `br` + labels
- [ ] Every `@handler` ends with `ret`
- [ ] `call @render()` only inside `@handler`
- [ ] `^handler` names match a `@handler:` defined in this `<Component>`

---

## Version

SAX v0.1 — corresponds to SA v0.1 MVP baseline.  
Roadmap: Phase 2 adds lifecycle hooks + router + fine-grained reactivity.  
Phase 3 adds native desktop target + WebGPU rendering path.
