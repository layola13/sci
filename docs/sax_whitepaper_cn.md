# SAX 白皮书 v0.2

> 本文为英文原版 [sax_whitepaper.md](./sax_whitepaper.md) 的中文对照版。

SAX（safe asm XML，安全汇编 XML）是 SA 的前端 UI 方言。它将 `.sax` 组件文件直接编译为 WebAssembly + HTML——没有 JavaScript 运行时，没有 GC，没有隐藏的分配。

**前置阅读**：先阅读 `docs/whitepaper.md`（SA 基础语言）。SAX 原样复用 SA 的全部 ISA、所有权模型和 Referee。本文只记录差异部分。

---

## 身份定位

- **不是 JS 框架**：SAX 编译为 WASM。没有 JavaScript bundle。
- **不是模板引擎**：SAX 被降级为 `.sa`，并由同一个 Referee 验证。
- **不是新语言**：SAX 就是 SA，只是多了一层——XML 结构包装。
- **完整所有权**：每个状态变量都由 Capability Mask 跟踪。泄漏即编译错误。

---

## SAX v0.1 的交付内容

当前实现说明：SAX 编译器/运行时位于 `/home/vscode/projects/sa_plugins/sa_plugin_sax`，由 SA 插件宿主加载。浏览器 WASM 通过 LLVM-C bitcode 加上 Zig 的 `wasm32-freestanding -fno-entry --import-symbols` 路径产出，而不是早期手工编写 `src/emit_wasm` 的方案。

| 命令 | 管线 | 产物 |
|---|---|---|
| `sa sax build <file.sax>` | SAX Parser → Flattener → Referee → LLVM-C `.sa.bc` → browser WASM → Airlock Gen | `app.wasm + airlock.js + index.html + generated .sa` |
| `sa sax check <file.sax>` | SAX Parser → Flattener → Referee (SAX rules) | Trap 报告或 OK |
| `sa sax new <name>` | 脚手架 | 项目目录 |
| `sa sax dev <file.sax>` | 刷新/静态开发入口；文件监听与保留状态的热替换仍在路线图中 | 开发产物 |

---

## 核心概念（在 SA 之上新增 4 项）

| SAX 概念 | SA 等价物 | 用途 |
|---|---|---|
| `<Component name="X">` | `@export` 函数族 | UI 组件边界 |
| `<state> v = 0 </state>` | `alloc` + `Active` 掩码 | 响应式私有状态 |
| `{expr}` 插值 | `load` + Airlock `set_text` | 将状态绑定到 DOM 文本/属性 |
| `onclick={^handler}` | `BorrowView` + Airlock `bind_event` | 挂载事件监听器 |

其余一切——`@handler:`、`L_LABEL:`、`br`、`jmp`、`!var`、`load`、`store`、`add` 等——都**与标准 SA 完全一致**。没有新指令。没有新运算符。

---

## 文件结构

每个 `.sax` 文件包含一个或多个 `<Component>` 块：

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

## 所有权规则（在 R4 之上的 SAX 新增部分）

SAX 在 SA 现有 trap 之上新增了 7 条前端专属 trap。其中一些在 SAX 解析/校验阶段发出，另一些由 verifier hook 发出。

| Trap | 触发条件 |
|---|---|
| `SaxStateLeak` | 组件销毁退出时某个 `<state>` 变量仍为 `Active` |
| `SaxEventEscape` | `^handler` 引用了同一 `<Component>` 之外的函数 |
| `SaxRenderOutsideHandler` | `call @render()` 出现在 `@handler` 函数体之外 |
| `SaxInvalidInterpolation` | `{expr}` 中包含 `^`（Move）或 `!`（Release） |
| `SaxStateWriteFromOutside` | 组件外部的代码写入其状态内存槽 |
| `SaxUnknownTag` | DOM 标签不在白名单中 |
| `SaxUnknownEvent` | 事件名不在白名单中 |

其余所有 SA Trap 仍然有效：`MemoryLeak`、`UseAfterMove`、`BorrowConflict` 等。

---

## 状态变量

```xml
<state>
  count  = 0             <!-- i64 (default integer) -->
  ratio  = 0.0           <!-- f64 (default float) -->
  flag   = 0 as i1       <!-- boolean -->
  buf    = alloc 256     <!-- heap buffer: 256 bytes, ptr type -->
  items  = alloc 24      <!-- dynamic array fat-pointer: data_ptr+len+cap (8+8+8) -->
</state>
```

规则：
- 每行一个声明。
- 类型遵循 SA 的字面量推断规则（与 `.sa` 相同）。
- `alloc N` = 分配 N 字节的堆内存。Lowerer 会发出 `alloc` SA 指令。
- 每个 `<state>` 变量**必须**出现在组件末尾的 `!release_stmt` 中。缺少释放 → `SaxStateLeak`。多释放不存在的变量 → `UseAfterMove`。

---

## DOM 标记

### 静态节点

```xml
<div class="card">
  <h2>Hello</h2>
</div>
```

降级为 Airlock 调用：`sax_dom_create("div")`、`sax_dom_add_class(...)`、`sax_dom_append_child(...)`、`sax_dom_set_text(...)`。

### 文本插值

```xml
<h1>Count: {count}</h1>
<p class="{status_class}">Status</p>
```

`{expr}` 出现在文本中 → `sax_dom_set_text(node, load state+offset)`。  
`{expr}` 出现在属性中 → `sax_dom_set_attr(node, "class", load state+offset)`。

`expr` 必须是**只读**的 SA 表达式：`load`、算术运算，不含 `^` 或 `!`。

### 事件绑定

```xml
<button onclick={^inc}>+1</button>
<input oninput={^handleInput} />
```

`^handler` = 在处理函数引用上的 `BorrowView` 掩码。  
降级为 `sax_dom_bind_event(node_h, evt_ptr, evt_len, handler_ptr, handler_len, ctx)`——处理函数以其 WASM 导出名的字节串形式传入（见 `docs/sax_airlock.md`），而不是函数表索引。

`handler` 必须在**同一个** `<Component>` 中定义。跨组件 → `SaxEventEscape`。

支持的事件：`onclick` `oninput` `onchange` `onsubmit` `onkeydown` `onkeyup` `onfocus` `onblur` `onmouseenter` `onmouseleave`。

---

## 事件处理函数

```
@handlerName:
L_ENTRY:
    // pure SA-ASM: load/store/add/sub/call/br/jmp...
    // modify state, then call @render()
    ret
```

规则：
- 函数体**与 `.sa` 完全一致**——完整的 SA ISA、扁平控制流，没有 `{}`。
- 通过 `load state_ptr+OFFSET as TYPE` 访问状态。
- 通过 `store state_ptr+OFFSET, value as TYPE` 修改状态。
- 状态变更后调用 `call @render()` 来更新 DOM。
- `call @render()` 只能在 `@handler` 内合法调用——其他地方 → `SaxRenderOutsideHandler`。
- 所有分支和循环都使用 `L_LABEL:` + `br`/`jmp`。`if`/`while`/`for` → `ForbiddenSyntax`。

---

## 最小完整示例——计数器

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

构建：

```
sa sax build counter.sax
# → dist/app.wasm  dist/airlock.js  dist/index.html  dist/counter.sa
```

---

## 处理函数中的分支（SA 扁平风格）

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

没有 `if`。没有 `{`。标签 + `br`。这与标准 SA 完全一致。

---

## 处理函数中的循环

```
@renderList:
L_ENTRY:
    i   = 0
    end = items_len
L_LOOP:
    cond = ult i, end
    br cond -> L_BODY, L_END
L_BODY:
    row = call @sax_array_get(&items, i)
    call @sax_dom_append_row(tbody, row)
    i = add i, 1
    jmp L_LOOP
L_END:
    ret
```

---

## 组件生命周期（Phase 2）

Phase 1 没有显式的生命周期钩子——Lowerer 自动生成 init 和 destroy 函数。（注：`docs/sax_design.md` §10 记载 `onMount`/`onUnmount`/`onUpdate` 已在 Phase 2 落地；本节示例描述的就是该 Phase 2 接口。）Phase 2 新增可选的钩子：

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

## Airlock API 快速参考

完整文档：`docs/sax_airlock.md`。最常用的 Phase 1 API：

| API | JS 等价物 |
|---|---|
| `sax_dom_set_text(node, ptr, len)` | `node.textContent = str` |
| `sax_dom_set_attr(node, key_ptr, klen, val_ptr, vlen)` | `node.setAttribute(k, v)` |
| `sax_dom_add_class(node, cls_ptr, len)` | `node.classList.add(cls)` |
| `sax_dom_remove_class(node, cls_ptr, len)` | `node.classList.remove(cls)` |
| `sax_dom_get_value(node, buf, len)` | `input.value` |
| `sax_dom_set_value(node, ptr, len)` | `input.value = str` |
| `sax_dom_bind_event(node_h, evt_ptr, evt_len, handler_ptr, handler_len, ctx)` | `node.addEventListener(evt, fn)` — 处理函数以其 WASM 导出名的字节串形式传入，而非函数表索引 |
| `sax_dom_query(sel_ptr, slen)` | `document.querySelector(sel)` |
| `sax_dom_create(tag_ptr, tlen)` | `document.createElement(tag)` |
| `sax_dom_append_child(parent, child)` | `parent.appendChild(child)` |
| `sax_dom_remove_self(node)` | `node.remove()` |
| `sax_get_time()` | `Date.now()` |
| `sax_itoa(val, buf, len)` | `val.toString()` |

所有 API 都必须在标记了 `@ffi_wrapper` 的函数内调用（Lowerer 会自动生成这些函数）。从普通 `@handler` 代码直接调用会经过生成的包装层。

---

## DOM 标签白名单

只接受以下 HTML5 标签。其他标签 → `SaxUnknownTag`。

**布局**：`div` `section` `article` `header` `footer` `main` `nav` `aside`  
**文本**：`h1` `h2` `h3` `h4` `h5` `h6` `p` `span` `label` `strong` `em`  
**表单**：`button` `input` `textarea` `select` `option` `form`  
**列表**：`ul` `ol` `li`  
**表格**：`table` `thead` `tbody` `tr` `th` `td`  
**媒体**：`img` `video` `canvas`  
**SAX 保留**（大写开头）：`<Router>` `<Page>` `<Slot>`

---

## SAX 专属 Trap 参考

在 SA Trap 集合之外（截至 2026-11-05 已登记 60 条，见 `docs/errorcode.md`），SAX 新增：

| Trap | 阶段 | 消息 |
|---|---|---|
| `SaxStateLeak` | Referee | `<state> variable 'X' not released at component end` |
| `SaxEventEscape` | Referee | `^handler 'X' is not defined in this <Component>` |
| `SaxRenderOutsideHandler` | Referee | `call @render() is only legal inside @handler` |
| `SaxInvalidInterpolation` | SAX Parser | `interpolation {expr} must not contain ^ or !` |
| `SaxStateWriteFromOutside` | Referee | `state slot of 'ComponentX' written from outside component` |
| `SaxUnknownTag` | SAX Parser | `tag <foo> is not in the SAX whitelist` |
| `SaxUnknownEvent` | SAX Parser | `event 'onhover' is not supported; did you mean 'onmouseenter'?` |

---

## 对比：SAX vs React vs Vue

| | React | Vue SFC | **SAX** |
|---|---|---|---|
| 语言 | JS/TS | JS/TS | **SA（汇编级）** |
| 产物 | JS bundle | JS bundle | **WASM** |
| 状态 | `useState` / Hook | `ref` / `reactive` | **`<state>` 显式所有权** |
| 内存安全 | GC | GC | **Referee 编译期** |
| GC 停顿 | 有 | 有 | **无** |
| 内存泄漏 | 运行时，难以定位 | 运行时 | **编译错误：SaxStateLeak** |
| LLM 生成 | 中 | 中 | **高（扁平、结构化）** |
| 控制流 | JSX 表达式 | `v-if` / `v-for` | **扁平 `L_LABEL:` + `br`** |

---

## SAX 有意不提供的内容

- 没有 `v-if` / `v-for` / `v-model` 指令语法
- 没有 JSX 表达式嵌套（`{items.map(...)}`）
- 没有隐式响应式追踪（没有 Proxy，没有运行时依赖图）
- 处理函数中没有 `async`/`await`（使用 CPS / 状态机降级，与 SA 相同）
- 没有 CSS-in-JS（使用外部 `.css` + `class` 属性，或 Phase 2 的 `<style>` 块）
- 没有 SSR / hydration（WASM 优先，Phase 1 仅限浏览器）
- 没有隐藏的 Drop（每个 `<state>` 变量都必须显式 `!released`）
- `{expr}` 中没有运算符优先级（拆分为多条 `load`/`op` SA 指令）

---

## LLM 生成指南

生成 `.sax` 文件时：

1. **以 `<Component name="X">` 开头**——始终是最外层包装。
2. **在 DOM 树之前于 `<state>` 中声明所有状态**。
3. **在 `@handler` 函数体中编写扁平的 SA-ASM**——使用 `L_LABEL:` + `br`/`jmp`，绝不使用 `if`/`while`。
4. **每次状态变更后调用 `call @render()`**——每个处理函数恰好一次，位于逻辑末尾。
5. **以 `!var1 !var2 ...` 结尾**——列出每个 `<state>` 变量，否则 Referee 会拒绝。
6. **仅在只读插值中使用 `{varName}`**——花括号内不得出现 `^`/`!`。
7. **用 `onclick={^handlerName}` 绑定事件**——`handlerName` 必须存在于同一组件中。

发出前的检查清单（可减少首过 Referee 失败）：
- [ ] 每个 `<state>` 变量在末尾都有对应的 `!var`
- [ ] SA 代码块中没有 `{` `}`（只允许出现在 XML 属性/文本中）
- [ ] 没有 `if` / `while` / `for`——使用 `br` + 标签
- [ ] 每个 `@handler` 都以 `ret` 结束
- [ ] `call @render()` 只出现在 `@handler` 内
- [ ] `^handler` 名字与这个 `<Component>` 中定义的 `@handler:` 匹配

---

## 版本

SAX v0.2——外部插件实现，Phase 1 已完成，Phase 2 部分落地。Phase 2 剩余缺口：钩子签名校验、路由切换时的挂载/卸载、inotify/kqueue 文件监听，以及保留状态的 WASM 热替换。Phase 3 将增加原生桌面、JS 降级方案、包集成，以及 WebGPU/3D 渲染路径。
