# SlaX: 基于 Sla 驱动的安全 UI 框架设计与集成方案

> **设计日期**：2026年6月14日
> **版本**：v0.1-草案
> **模块路径**：`/home/vscode/projects/sa_plugins/sa_plugin_sax`
> **核心思想**：将 Sla 语言的静态类型、表达式语法、方法链接和生命周期自动释放引入 SAX（Safe ASM XML）框架，彻底消除手写低级 SA 汇编进行 UI 开发的痛点，构建安全、高效的 **SlaX（Sla + SAX）** 前端开发模式。

---

## 1. 动机与痛点分析

在现有的 **SAX** 框架中（见 [sax_design.md](file:///home/vscode/projects/sci/docs/sax_design.md)），开发者虽然能使用 XML 声明式地编写 DOM 树，但底层的组件状态维护与事件处理逻辑（`@handler`）依然必须使用**低级的 SA 汇编**编写。这带来了以下显著痛点：
1. **显式内存泄漏管理压力**：在组件末尾必须手动列出 `!stateVar1 !stateVar2` 释放所有状态，遗漏任何一个变量都会触发 `SaxStateLeak`。
2. **繁琐的手动加载与写入**：必须手动编写 `load state+Counter_count as i64` 和 `store` 偏移量来读写状态变量，心智负担极重。
3. **扁平控制流限制**：事件处理函数内禁止使用 `{}`、`if/else`、`for` 循环，必须手写 `br` 和 `jmp` 以及扁平的 Label 跳转。
4. **无法进行高级链式操作**：对于 `Vec` 或 `String` 等常用 UI 数据结构，无法使用 `items.push(x)`，只能手写 FFI 函数调用嵌套。

**SlaX** 通过将 **Sla 编译前端**直接融入 SAX 编译链，使开发者能用高级 Sla 语法书写组件状态和方法逻辑。

---

## 2. 编译管线演进：从 SAX 到 SlaX

通过引入 Sla，SlaX 编译器管道的复杂性在低级 SA 层面得到了极大简化：

```
                    .slax 源文件 (XML 结构 + Sla 语法)
                             │
                             ▼
                     [SlaX Parser]
                       ├── 解析 DOM 树为结构化表示
                       └── 提取 Sla 状态声明和 Sla 函数体
                             │
                             ▼
                   [Airlock Sla 代码生成器]
                       └── 将 DOM 树翻译为高层 Sla 代码 
                           (自动生成 init() 与 render() 函数)
                             │
                             ▼
                   [Sla 编译器前端 (Merged AST)]
                       ├── 1. 语法/语义分析与类型检查
                       ├── 2. 泛型单态化 (Monomorphization)
                       ├── 3. 卫生宏展开 (Hygienic Macro Expansion)
                       ├── 4. 自动生存期分析与 `!` 释放指令注入
                       └── 5. 循环内局部栈分配自动提升 (Hoisting)
                             │
                             ▼
                    生成的目标 .sa 汇编与 .sal 布局
                             │
                             ▼
                [SA Referee 静态验证器] (verifier.zig)
                             │
                             ▼
               [LLVM-C 后端] ➔ WebAssembly (.wasm)
```

**关键优势**：
*   **SAX 降级逻辑极大简化**：SAX Parser 不再需要自己处理低级的 SA 寄存器分配和状态释放，只需输出高层的 Sla 代码，交给 Sla 编译器即可。
*   **零泄露保证**：利用 Sla 的**隐式生存期代偿**机制，组件状态和事件处理函数内的局部变量在作用域结束时由 Sla 编译器自动插入 `!` 指令，彻底消除了手写 `!count` 的漏写隐患。

---

## 3. SlaX 语法定义与文件格式 (`.slax`)

`.slax` 是 SlaX 框架的源文件格式。它的基本结构如下：

```xml
<Component name="ComponentName">
  <state>
    // 状态声明：使用 Sla 变量定义语法 (let)
    let state_var1: Type = init_expr;
  </state>

  <!-- 声明式 DOM 树 -->
  <div class="container">
    <h1>{state_var1}</h1>
    <button onclick={^handler}>Action</button>
  </div>

  // 事件处理逻辑：使用 Sla 强类型函数定义
  fn handler() {
      // 结构化 Sla 表达式，支持 if/else, for 循环，方法链式调用
  }
</Component>
```

与 `.sax` 的关键区别：
*   去除了组件末尾的 `release_stmt` 块（`!stateVar1 ...`）。
*   `<state>` 块内部改用标准的 `let` 语法进行初始化。
*   所有的 `@handler:` 块被替换为标准的 Sla 函数形式 `fn handler_name() { ... }`，免去 `L_ENTRY:` 样板标签和手动 `ret`。

---

## 4. 典型集成示例：Counter（计数器）

### SlaX 源码 (`Counter.slax`)
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

  // 增加计数
  fn inc() {
      count = count + 1;
      last = sax_get_time();
      render(); // 触发 UI 重渲染
  }

  // 减少计数
  fn dec() {
      count = count - 1;
      last = sax_get_time();
      render();
  }

  // 重置
  fn reset() {
      count = 0;
      last = sax_get_time();
      render();
  }
</Component>
```

### 降级转换后的 Sla 表达形式（由 SlaX Parser 在编译内存中拼接生成）

SlaX Parser 将 DOM 树结构编译为与 Airlock 交互的 Sla 代码，并与用户的 Sla 状态及函数融合成单一编译单元：

```sla
// 1. 自动生成的组件状态与 DOM 结构体
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

// 2. 自动生成的组件挂载与初始化函数
fn sax_counter_init() {
    let state = CounterState { count: 0, last: 0 };
    
    // 查询 DOM 元素
    let dom = CounterDom {
        node_display: sax_dom_query("#display"),
        node_btn_inc: sax_dom_query(".btn-inc"),
        node_btn_dec: sax_dom_query(".btn-dec"),
        node_btn_reset: sax_dom_query(".btn-reset")
    };
    
    // 绑定事件处理器（Borrow 借用事件响应函数）
    sax_dom_bind_event(&dom.node_btn_inc, "click", &sax_counter_inc);
    sax_dom_bind_event(&dom.node_btn_dec, "click", &sax_counter_dec);
    sax_dom_bind_event(&dom.node_btn_reset, "click", &sax_counter_reset);
    
    // 执行初次渲染
    sax_counter_render(&state, &dom);
}

// 3. 自动生成的渲染器函数
fn sax_counter_render(state: &CounterState, dom: &CounterDom) {
    let buf = stack_alloc(32);
    let blen = sax_itoa(state.count, &buf);
    sax_dom_set_text(dom.node_display, &buf, blen);
}

// 4. 用户编写的事件处理器降级形式 (传入当前状态上下文)
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
*最后，Sla 编译器再把上述 Sla 代码一并翻译为符合 Referee 静态验证的 SA 汇编。*

---

## 5. 进阶示例：TodoList（待办列表，含方法链与自动生存期）

此示例展示了在 SlaX 中使用 `Vec` 泛型容器、方法链接以及 SlaX 的自动生存期管理。

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
      <!-- 动态行节点 -->
    </ul>
  </div>

  // 处理输入变化
  fn handleInput(val: String) {
      input_buf = ^val; // 转移所有权，更新输入缓冲区
      render();
  }

  // 增加待办项
  fn addTodo() {
      if input_buf.len() > 0 {
          let item = TodoItem {
              text: ^input_buf, // 转移文本所有权
              completed: false
          };
          
          // 链式调用与自动 Borrow/Move 转换
          items.push(^item); 
          
          // 重置输入框
          input_buf = String::new();
          render();
      }
      // items 和 input_buf 的所有权在组件生命周期内由框架安全持有，
      // 不需要任何手动的释放，且编译后完全无内存泄漏。
  }
</Component>
```

---

## 6. SlaX 专属 Referee 校验优化

将 Sla 编译管线引入 SAX 后，原先需要在 SAX 插件中繁琐检查的规则大幅度精简：

1.  **`SaxStateLeak` (消除)**：因为 Sla 编译前端自带活跃变量分析与生命周期代偿，编译器会自动在 init / destroy 函数的出口节点精确生成 `!state` 和 `!dom` 指令，开发者完全不需要手动编写释放逻辑。
2.  **`SaxRenderOutsideHandler` (编译期规避)**：在 Sla 中，`render()` 是一个局部的普通 Sla 函数。编译器可以静态分析其调用图，并阻止非 `@handler` 或非生命周期相关的外部函数调用它。
3.  **`ForbiddenSyntax` (消除)**：由于 Sla 编译器的主要特性就是支持 `if/else` 与 `for` 循环，因此原先 SAX `@handler` 中禁止的分支语句在 SlaX 中完全解禁，由编译器后端自动生成平铺的 SA 跳转，彻底解放了开发者的表达力。
