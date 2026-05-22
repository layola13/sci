# SAX 语法规范

> SAX（Symbolic Affine XML）是 SA 语言的前端 UI 方言。本文档是 `.sax` 文件的语法权威参考，
> 包含 BNF 范式、语法元素说明与完整示例。
>
> 前置阅读：`docs/whitepaper.md`（SA 基础语法）、`docs/sax_design.md`（SAX 框架设计）。

---

## 1. BNF 语法范式

```ebnf
sax_file        ::= component+

component       ::= "<Component" "name=" DQUOTE IDENT DQUOTE ">"
                    state_block?
                    dom_tree
                    handler_def*
                    release_stmt
                    "</Component>"

state_block     ::= "<state>" NEWLINE
                    (state_var_decl NEWLINE)+
                    "</state>"

state_var_decl  ::= IDENT "=" state_init_expr

state_init_expr ::= integer_literal              // i64 默认
                  | float_literal                // f64 默认
                  | integer_literal "as" sa_type
                  | "alloc" integer_literal      // 堆分配 N 字节
                  | "0"                          // 通用零值

dom_tree        ::= dom_node+

dom_node        ::= "<" tag_name attr* ">" dom_content "</" tag_name ">"
                  | "<" tag_name attr* "/>"     // 自闭合

tag_name        ::= // HTML5 白名单子集（见 §2.1）

attr            ::= IDENT "=" DQUOTE attr_value DQUOTE
                  | event_attr

attr_value      ::= plain_string
                  | "{" sa_expr "}"             // 动态属性值

event_attr      ::= event_name "=" "{" "^" IDENT "}"
event_name      ::= "onclick" | "oninput" | "onchange" | "onsubmit"
                  | "onkeydown" | "onkeyup" | "onfocus" | "onblur"
                  | "onmouseenter" | "onmouseleave"

dom_content     ::= (dom_node | text_node | interpolation | sa_control_flow)*

text_node       ::= PLAIN_TEXT

interpolation   ::= "{" sa_load_expr "}"
                    // 仅允许 load + 原生数值运算，禁止 ^ / !

sa_load_expr    ::= IDENT                       // 直接引用 state 变量
                  | "load" IDENT "+" integer_literal "as" sa_type
                  | sa_load_expr sa_arith_op sa_load_expr

sa_arith_op     ::= "add" | "sub" | "mul" | "udiv" | "sdiv"

sa_control_flow ::= sa_label | sa_jmp | sa_br   // 直通，与 .sa 一致

handler_def     ::= "@" IDENT ":"  NEWLINE
                    sa_block

sa_block        ::= (sa_label | sa_instruction | sa_control_stmt)+ "ret"

release_stmt    ::= ("!" IDENT)+                // 组件末尾，释放所有 state 变量

// ── SA 原语（直通，完整定义见 whitepaper.md）
sa_label        ::= LABEL_IDENT ":"
sa_instruction  ::= // 完整 SA ISA（load/store/alloc/call/op 等）
sa_type         ::= "i8" | "i16" | "i32" | "i64" | "u8" | "u16" | "u32" | "u64"
                  | "f32" | "f64" | "i1" | "ptr"
```

---

## 2. 词法规则

```ebnf
IDENT         ::= [a-zA-Z_][a-zA-Z0-9_]*
LABEL_IDENT   ::= "L_" [A-Z][A-Z0-9_]*
DQUOTE        ::= '"'
PLAIN_TEXT    ::= // 不含 < > { } 的 UTF-8 文本
NEWLINE       ::= "\n" | "\r\n"
// 注释与 .sa 一致
LINE_COMMENT  ::= "//" ~[\n]* NEWLINE
```

---

## 2.1 DOM 标签白名单

SAX 只接受以下 HTML5 标签子集，其他标签触发 `SaxUnknownTag`：

**布局**：`div` `section` `article` `header` `footer` `main` `nav` `aside`

**文本**：`h1` `h2` `h3` `h4` `h5` `h6` `p` `span` `label` `strong` `em`

**交互**：`button` `input` `textarea` `select` `option` `form`

**列表**：`ul` `ol` `li`

**媒体**：`img` `video` `canvas`

**表格**：`table` `thead` `tbody` `tr` `th` `td`

**特殊**：`<Router>` `<Page>` `<Slot>`（SAX 保留标签，大写开头）

---

## 2.2 属性白名单

| 类别 | 允许属性 |
|------|---------|
| 通用 | `id` `class` `style` `hidden` `title` |
| 表单 | `type` `value` `placeholder` `disabled` `readonly` `checked` `name` |
| 媒体 | `src` `alt` `width` `height` |
| 路由 | `path` `component`（`<Page>` 专用） |
| 事件 | `onclick` `oninput` `onchange` `onsubmit` `onkeydown` `onkeyup` `onfocus` `onblur` `onmouseenter` `onmouseleave` |

动态属性值：`class="{expr}"` 中的 `expr` 必须是 `sa_load_expr`（只读，禁止 `^`/`!`）。

---

## 3. 语法规则详解

### 3.1 `<Component>`

每个 `.sax` 文件的顶层容器。一个文件可定义多个 `<Component>`，相互独立。

```xml
<Component name="MyWidget">
  <!-- 内容 -->
</Component>
```

`name` 属性：
- 必须是合法 `IDENT`
- 首字母大写（约定，非强制）
- 用于生成的 SA 函数族命名前缀（如 `sax_mywidget_init`）

### 3.2 `<state>` 块

声明组件的私有响应式状态。`<state>` 块是**可选的**——无状态组件（纯展示）可省略。

```xml
<state>
  count   = 0              // i64，整数默认
  ratio   = 0.0            // f64，浮点默认
  flag    = 0 as i1        // 布尔
  name    = alloc 24       // 胖指针（data_ptr 8 + len 8 + cap 8）
  items   = alloc 24       // 动态数组胖指针
  status  = 0 as i32       // 显式指定 i32
</state>
```

规则：
- 每个声明独占一行
- 变量名不能与 SA 保留字冲突
- `alloc N` 分配 N 字节堆内存，由 Lowerer 自动插入 `alloc` SA 指令
- 所有 `<state>` 变量**必须**在组件末尾的 `release_stmt` 中显式释放，否则 Referee 报 `SaxStateLeak`

### 3.3 DOM 树

DOM 树紧跟在 `<state>` 块（或 `<Component>` 开标签）之后，描述组件的 UI 结构。

```xml
<div class="card">
  <h2>{title}</h2>
  <p class="desc">{desc}</p>
  <button onclick={^handleClick} disabled="{is_loading}">
    Submit
  </button>
</div>
```

**插值 `{expr}`**：
- 出现在文本节点或属性值中
- `expr` 只能是 `sa_load_expr`（只读访问 state 变量）
- 禁止在插值中使用 `^`（Move）或 `!`（释放）
- 插值由 Lowerer 展开为 `load` 指令 + Airlock `sax_dom_set_text/sax_dom_set_attr` 调用

**事件绑定 `event={^handler}`**：
- `^` 表示借用函数引用（`BorrowView` 掩码）
- `handler` 必须是同一 `<Component>` 内定义的 `@handler`，否则 Referee 报 `SaxEventEscape`
- Lowerer 展开为 Airlock `sax_dom_bind_event(node, event_name, ^handler)` 调用

### 3.4 `@handler:` 事件处理函数

组件内部的事件处理逻辑，语法与 `.sa` 函数体完全一致（SA-ASM 风格）。

```
@handlerName:
L_ENTRY:
  // 纯 SA 指令（load/store/add/sub/call/br/jmp 等）
  // 修改 state 变量后调用 call @render()
  ret
```

规则：
- 函数名以 `@` 开头，冒号结尾
- 函数体是纯 SA-ASM：`L_ENTRY:` 开始，`ret` 结束
- 控制流使用 `L_LABEL:` + `br`/`jmp`，**禁止** `{}`/`if`/`while`
- `call @render()` 触发 DOM 更新，只能在 `@handler` 内调用
- 可访问组件 `<state>` 变量（通过 `load state_ptr+offset`）

### 3.5 `!var` 释放语句

组件末尾，显式释放所有 `<state>` 声明的变量，顺序不限。

```
!count !last !name !items
```

或分行：

```
!count
!last
!name
!items
```

Referee 验证：组件销毁函数出口处，所有 `<state>` 变量必须全部出现在释放语句中。
缺少任何一个 → `SaxStateLeak`。多写不存在的变量 → `UseAfterMove`（复用 SA 原有规则）。

---

## 4. 完整示例

> 注：4.3 / 4.4 里的路由、HTTP、数组与表格 API 属于 Phase 2 草案；当前 `src/sax/airlock_gen.zig` / `src/sax/lowerer.zig` 不会生成这些函数。

### 4.1 Counter（计数器）

```xml
<Component name="Counter">

  <state>
    count = 0
    last  = 0
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

  @reset:
  L_ENTRY:
    store state+Counter_count, 0 as i64
    last  = call @sax_get_time()
    store state+Counter_last, last as i64
    call @render()
    ret

  !count !last
</Component>
```

### 4.2 TodoList（待办列表）

```xml
<Component name="TodoList">

  <state>
    items     = alloc 24    // []TodoItem 胖指针（data_ptr+len+cap）
    input_buf = alloc 256   // 输入缓冲区
    input_len = 0           // 当前输入长度
  </state>

  <div class="todo-app">
    <h1>Todo List</h1>

    <div class="input-row">
      <input
        type="text"
        id="todo-input"
        placeholder="What needs to be done?"
        value="{input_len}"
        oninput={^handleInput} />
      <button onclick={^addTodo}>Add</button>
    </div>

    <ul id="todo-list">
      <!-- 列表项由 @render 动态生成 -->
    </ul>

    <p>Total: {input_len} chars typed</p>
  </div>

  @handleInput:
  L_ENTRY:
    // 从 DOM input 事件读取新值（通过 Airlock）
    new_len = call @sax_dom_get_value(&input_buf, 256)
    store state+TodoList_input_len, new_len as i64
    call @render()
    ret

  @addTodo:
  L_ENTRY:
    // 检查输入非空
    len = load state+TodoList_input_len as i64
    ok  = sgt len, 0
    br ok -> L_DO_ADD, L_SKIP
  L_DO_ADD:
    // 将 input_buf 内容追加到 items 数组
    call @sax_array_push(&items, &input_buf, len)
    // 清空输入
    store state+TodoList_input_len, 0 as i64
    todo_input = call @sax_dom_query(utf8:"#todo-input", 11)
    call @sax_dom_set_value(todo_input, utf8:"", 0)
    call @render()
    jmp L_END
  L_SKIP:
    jmp L_END
  L_END:
    ret

  @deleteTodo:
  L_ENTRY:
    // 参数 idx 由事件绑定时携带（通过 data-idx 属性）
    idx = call @sax_dom_get_event_data()
    call @sax_array_remove(&items, idx)
    call @render()
    ret

  !items !input_buf !input_len
</Component>
```

### 4.3 LoginForm（Phase 2 草案）

```xml
<Component name="LoginForm">

  <state>
    username_buf = alloc 128
    password_buf = alloc 128
    error_msg    = alloc 256
    is_loading   = 0 as i1
    has_error    = 0 as i1
  </state>

  <form class="login-form" onsubmit={^handleSubmit}>
    <h2>Login</h2>

    <div class="field">
      <label>Username</label>
      <input
        type="text"
        placeholder="Enter username"
        oninput={^handleUsername} />
    </div>

    <div class="field">
      <label>Password</label>
      <input
        type="password"
        placeholder="Enter password"
        oninput={^handlePassword} />
    </div>

    <button type="submit" disabled="{is_loading}">
      Login
    </button>

    <p class="error">{has_error}</p>
  </form>

  @handleUsername:
  L_ENTRY:
    call @sax_dom_get_value(&username_buf, 128)
    ret

  @handlePassword:
  L_ENTRY:
    call @sax_dom_get_value(&password_buf, 128)
    ret

  @handleSubmit:
  L_ENTRY:
    // 设置 loading 状态
    store state+LoginForm_is_loading, 1 as i1
    call @render()
    // 发起认证请求（通过 @extern HTTP Airlock）
    result = call @sax_http_post(utf8:"/api/login", 10, &username_buf, &password_buf)
    status = load result+0 as i32
    ok     = eq status, 200
    br ok -> L_SUCCESS, L_FAIL
  L_SUCCESS:
    store state+LoginForm_is_loading, 0 as i1
    store state+LoginForm_has_error, 0 as i1
    // 跳转到首页
    call @sax_router_push(utf8:"/", 1)
    jmp L_END
  L_FAIL:
    store state+LoginForm_is_loading, 0 as i1
    store state+LoginForm_has_error, 1 as i1
    // 复制错误消息
    err_ptr = load result+8 as ptr
    err_len = load result+16 as i64
    call @sax_mem_copy(&error_msg, err_ptr, err_len)
    call @render()
    jmp L_END
  L_END:
    !result
    ret

  !username_buf !password_buf !error_msg !is_loading !has_error
</Component>
```

### 4.4 DataTable（Phase 2 草案）

无状态组件（省略 `<state>` 块），props 通过 SA 函数参数传入：

```xml
<Component name="DataTable">
  <!-- 无 <state> 块：纯展示，数据由父组件传入 -->

  <div class="table-wrapper">
    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Name</th>
          <th>Status</th>
          <th>Action</th>
        </tr>
      </thead>
      <tbody id="table-body">
        <!-- 行由 @render 根据传入数组动态生成 -->
      </tbody>
    </table>
  </div>

  @render:
  L_ENTRY:
    // items_ptr / items_len 由外部传入（父组件调用时注入）
    i   = 0
    end = items_len
  L_LOOP:
    cond = ult i, end
    br cond -> L_BODY, L_END
  L_BODY:
    row_ptr = call @sax_array_get(&items, i)
    call @sax_table_append_row(tbody, row_ptr)
    i = add i, 1
    jmp L_LOOP
  L_END:
    ret

  // 无 <state>，无需 !释放语句
</Component>
```

---

## 5. 常见错误与修复

### 5.1 SaxStateLeak — 状态变量未释放

```xml
<!-- 错误：声明了 count 但末尾未释放 -->
<Component name="Bad">
  <state>
    count = 0
  </state>
  <div>{count}</div>
  @inc:
  L_ENTRY:
    count = add count, 1
    call @render()
    ret
  <!-- 缺少 !count → SaxStateLeak -->
</Component>

<!-- 修复 -->
  !count
</Component>
```

### 5.2 SaxEventEscape — 跨组件事件绑定

```xml
<!-- 错误：^handler 引用了另一个组件的函数 -->
<Component name="Bad">
  <state> x = 0 </state>
  <button onclick={^other_component_handler}>Click</button>
  <!-- SaxEventEscape: handler 不在本组件内 -->
  !x
</Component>

<!-- 修复：在本组件内定义处理函数 -->
<Component name="Good">
  <state> x = 0 </state>
  <button onclick={^localHandler}>Click</button>
  @localHandler:
  L_ENTRY:
    x = add x, 1
    call @render()
    ret
  !x
</Component>
```

### 5.3 SaxRenderOutsideHandler — render 位置错误

```xml
<!-- 错误：在 <state> 后直接调用 render（只能在 @handler 内） -->
<Component name="Bad">
  <state> x = 0 </state>
  call @render()   <!-- SaxRenderOutsideHandler -->
  <div>{x}</div>
  !x
</Component>
```

### 5.4 ForbiddenSyntax — 使用了 SA 禁用语法

```xml
<!-- 错误：在 @handler 内使用了 if/else（SA 禁止） -->
@handler:
L_ENTRY:
  if count > 0 {        // ForbiddenSyntax: 'if'
    count = sub count, 1
  }
  ret

<!-- 修复：使用 br 扁平控制流 -->
@handler:
L_ENTRY:
  ok = sgt count, 0
  br ok -> L_DEC, L_SKIP
L_DEC:
  count = sub count, 1
  jmp L_END
L_SKIP:
  jmp L_END
L_END:
  call @render()
  ret
```

### 5.5 SaxInvalidInterpolation — 插值中使用了 Move/Release

```xml
<!-- 错误：插值中不能有 ^ 或 ! -->
<h1>{^count}</h1>        <!-- SaxInvalidInterpolation -->
<p>{!count}</p>          <!-- SaxInvalidInterpolation -->

<!-- 正确：只能是只读 load 表达式 -->
<h1>{count}</h1>
<p>{load state+Counter_count as i64}</p>
```

---

## 6. 与 `.sa` 的兼容性

SAX 是 `.sa` 的超集，`@handler` 函数体内的所有语法**与 `.sa` 完全一致**：

- 所有 SA 指令（`load`/`store`/`alloc`/`call`/`op`/`br`/`jmp` 等）在 `@handler` 内均合法
- SA 的五符号契约（`=` `&` `^` `!` `*`）在 `@handler` 内完全有效
- SA 的 `#def` 伪指令可在 `.sax` 文件顶部使用（在 `<Component>` 外）
- SA 的 `@extern` 声明可在 `.sax` 文件顶部使用（声明 Airlock API）
- `$...$` 原生代码逃逸在 `@ffi_wrapper` 标记的 handler 内可用

不兼容项（SAX 专属限制）：

- `{` `}` 在 XML 属性之外不允许出现（SA 本身已禁止花括号）
- `call @render()` 只能在 `@handler` 内（SAX 新增规则）
- `^handler` 只能绑定本组件内函数（SAX 新增规则）
- `<state>` 变量必须在末尾全部 `!释放`（SAX 新增规则）
