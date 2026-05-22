# SAX 框架技术设计文档

> SAX（Symbolic Affine XML）是 SA 语言的前端 UI 方言扩展，在 `.sa` 基础上增加 XML 结构层，
> 编译目标为 **WebAssembly + HTML**，实现全栈 SA：后端出单文件 EXE，前端出 WASM。
>
> 本文档承接 SA 语言的核心哲学（见 `design.md` / `requirements.md`），所有设计决策均以
> **不破坏 SA 零 AST、线性扫描、O(1) 位掩码、气闸舱 FFI** 为前提。

---

## 1. 定位与动机

### 1.1 为什么需要 SAX

SA 已经能编译到 WASM，但它是一门"给机器写的汇编级语言"，缺乏描述 UI 结构的能力：

- 没有 DOM 树的声明式语法
- 没有状态与视图的绑定机制
- 没有事件处理的高层抽象

SAX 就是填补这个缺口的**最小化前端方言**：在 `.sa` 的基础上增加一层 XML 结构描述，
然后由 SAX Parser 将其**降级为合法 `.sa`**，再走现有的 Flattener → Referee → WASM 管线。

### 1.2 为什么不直接输出 JS

聊天记录中已充分讨论（见 `web.md`），结论是：

- JS 路线浪费了 SA 的核心优势（所有权安全、零 GC、LLM 可验证）
- WASM 路线：无 GC 暂停、内存安全编译期保证、性能接近原生
- 当前 Web 高性能场景（Figma、Photoshop Web）已在重度使用 WASM
- 全栈 SA：后端 → EXE，前端 → WASM，技术栈统一，多 Agent 并行开发收益最高

### 1.3 与现有 SA 编译器的关系

SAX 是 SA 编译器的**前端方言层**，不是独立工具：

```
SA 编译器（现有 src/）
├── flattener/      ← SAX 直接复用，零修改
├── referee/        ← SAX 扩展约 200 行（新增 5 条 SAX 专属规则）
├── emit_wasm/      ← SAX 复用，切换 target 为 wasm32-unknown-unknown
├── common/         ← SAX 完全复用
└── sax/            ← 新增：SAX 前端扩展层
    ├── parser.zig      # XML + SA 混合解析，输出合法 .sa 文本
    ├── lowerer.zig     # Component/state/DOM 节点 → SA 指令序列
    ├── dom_schema.zig  # HTML5 白名单标签/属性表
    ├── airlock_gen.zig # 自动生成 airlock.js
    └── html_shell_gen.zig  # 自动生成 index.html
```

---

## 2. 文件格式：`.sax`

`.sax` 是 SAX 的源文件格式。每个文件定义一个或多个 `<Component>`。

### 2.1 顶层结构

```
<Component name="ComponentName">

  <state>
    // SA 变量声明（对应 alloc + 初始化）
  </state>

  // DOM 树（XML 标签，支持 {expr} 插值）

  @handlerName:
  L_ENTRY:
    // 纯 SA-ASM 指令（与 .sa 完全一致）
    ret

  !stateVar1 !stateVar2   // 显式释放所有状态变量
</Component>
```

### 2.2 语法元素全表

| SAX 语法 | SA 语义 | 降级后的 SA 原语 |
|----------|---------|----------------|
| `<Component name="X">` | 组件边界 / 模块单元 | 生成一组 `@export` 函数族 |
| `<state> v = expr </state>` | 组件私有响应式状态 | `alloc N` + `store` 初始化 |
| `<div>` / `<h1>` / `<button>` 等 | DOM 节点声明 | `@ffi_wrapper` 内调用 Airlock API |
| `{expr}` | DOM 插值（文本/属性值） | `load` + `@extern sax_dom_set_text(...)` |
| `onclick={^handler}` 等事件 | 事件借用绑定 | `BorrowView` 掩码 + `@extern sax_dom_bind_event(...)` |
| `@name:` | 事件处理函数定义 | 普通 SA 函数声明 |
| `!var` | 显式释放状态变量 | `!reg`（`Consumed` 掩码） |
| `call @render()` | 触发组件重渲染 | 展开为一系列 Airlock DOM 更新调用 |
| `L_LABEL:` / `br` / `jmp` | 控制流（与 SA 完全一致） | 直通，零转换 |

### 2.3 状态变量类型系统

SAX 的状态变量与 SA 保持一致，**不引入新的类型关键字**：

```xml
<state>
  count  = 0          // i64（默认整数）
  ratio  = 0.0        // f64（默认浮点）
  name   = alloc 24   // ptr（胖指针：data_ptr+len+cap 各 8 字节）
  flag   = 0 as i1    // i1（布尔）
  items  = alloc 24   // ptr（动态数组胖指针，同上）
</state>
```

类型由字面量或 `as T` 标注决定，与 `.sa` 规则完全一致（见 `whitepaper.md` §ISA）。

---

## 3. 编译器管线

### 3.1 完整管线

```
.sax 源文件
    │
    ▼
[SAX Parser]                     ← 新增，约 400-600 行 Zig
  • 解析 <Component> / <state> / DOM 标签
  • 识别 {expr} 插值 / ^handler 借用 / @name: 函数块
  • 不构建任何 AST，直接输出 .sa 文本流
    │
    ▼ 合法 .sa 文本
    │
[SA Flattener]                   ← 完全复用 src/flattener/，零修改
  • #def 展开 / 宏展开 / #loc 收集
  • 禁用语法扫描（{} if else while for a.b.c）
    │
    ▼ Instruction[]
    │
[SA Referee]                     ← 复用 src/referee/，新增 sax_rules.zig（+200 行）
  • 现有：Capability Mask O(1) 位运算、气闸舱校验、Phi 一致性
  • 新增：SaxStateLeak / SaxEventEscape / SaxRenderOutsideHandler 等规则
    │
    ▼ AnnotatedInstruction[]
    │
[WASM Emitter]                   ← 复用 src/emit_wasm/
  • target: wasm32-unknown-unknown（无 WASI，纯浏览器环境）
  • 组件状态 → WASM 线性内存固定槽
  • DOM 操作 → @extern 气闸舱函数（由 Airlock JS 实现）
    │
    ▼ .wasm 字节
    │
[Airlock JS 生成器]              ← 新增，约 200 行生成模板
  • 自动生成 airlock.js（WASM ↔ DOM 胶水层）
  • 白名单 DOM API，~20 个
    │
[HTML Shell 生成器]              ← 新增，约 50 行
  • 生成最小 index.html（加载 .wasm + airlock.js）
    │
    ▼
输出：app.wasm + airlock.js + index.html + 生成的 .sa
```

### 3.2 SAX Parser 降级策略

SAX Parser 的核心工作是**将高层 XML 结构降级为合法的 .sa 指令序列**，
不构建任何 AST，遵守 SA "零 AST、线性扫描" 原则。

以 Counter 组件为例，降级过程如下：

**输入（Counter.sax）**：

```xml
<Component name="Counter">

  <state>
    count = 0
    last  = 0
  </state>

  <div class="counter">
    <h1 id="display">Count: {count}</h1>
    <button onclick={^inc}>+1</button>
    <button onclick={^dec}>-1</button>
  </div>

  @inc:
  L_ENTRY:
    count = add count, 1
    last  = call @sax_get_time()
    call @render()
    ret

  @dec:
  L_ENTRY:
    count = sub count, 1
    last  = call @sax_get_time()
    call @render()
    ret

  !count !last
</Component>
```

**输出（Counter.sa，由 SAX Parser 自动生成）**：

```
// === SAX 自动降级：Component Counter ===
// 状态内存布局
#def Counter_count = +0    // i64, 8 bytes
#def Counter_last  = +8    // i64, 8 bytes
#def Counter_SIZE  = 16

// DOM 节点 ID 槽（由 Airlock 运行时分配）
#def Counter_node_display = +0   // ptr to h1#display
#def Counter_node_btn_inc = +8   // ptr to button[0]
#def Counter_node_btn_dec = +16  // ptr to button[1]
#def Counter_dom_SIZE = 24

// ── 初始化函数（组件挂载）
@export sax_counter_init():
L_ENTRY:
  state = alloc Counter_SIZE
  store state+Counter_count, 0 as i64
  store state+Counter_last,  0 as i64
  dom = alloc Counter_dom_SIZE
  // 查询 DOM 节点
  h1_ref  = call @sax_dom_query(utf8:"#display", 8)
  btn_inc = call @sax_dom_query(utf8:".btn-inc",  8)
  btn_dec = call @sax_dom_query(utf8:".btn-dec",  8)
  store dom+Counter_node_display, ^h1_ref
  store dom+Counter_node_btn_inc, ^btn_inc
  store dom+Counter_node_btn_dec, ^btn_dec
  // 绑定事件
  call @sax_dom_bind_event(&dom, Counter_node_btn_inc, utf8:"click", 5, ^sax_counter_inc)
  call @sax_dom_bind_event(&dom, Counter_node_btn_dec, utf8:"click", 5, ^sax_counter_dec)
  // 初始渲染
  call @sax_counter_render(&state, &dom)
  ret

// ── 渲染函数（对应 call @render()）
@export sax_counter_render(^state, ^dom):
L_ENTRY:
  count_val = load state+Counter_count as i64
  h1        = load dom+Counter_node_display as ptr
  // 将 count_val 格式化为字符串并更新 DOM
  buf   = stack_alloc 32
  blen  = call @sax_itoa(count_val, &buf, 32)
  call @sax_dom_set_text(h1, &buf, blen)
  ret

// ── 事件处理：+1（对应 @inc:）
@export sax_counter_inc():
L_ENTRY:
  count = load state+Counter_count as i64
  count = add count, 1
  store state+Counter_count, count as i64
  last  = call @sax_get_time()
  store state+Counter_last, last as i64
  call @sax_counter_render(&state, &dom)
  ret

// ── 事件处理：-1（对应 @dec:）
@export sax_counter_dec():
L_ENTRY:
  count = load state+Counter_count as i64
  count = sub count, 1
  store state+Counter_count, count as i64
  last  = call @sax_get_time()
  store state+Counter_last, last as i64
  call @sax_counter_render(&state, &dom)
  ret

// ── 销毁函数（对应 !count !last）
@export sax_counter_destroy():
L_ENTRY:
  !state
  !dom
  ret
```

---

## 4. Referee SAX 扩展规则

在现有 Referee 基础上新增 5 条 SAX 专属规则，约 200 行 Zig，放在 `src/referee/sax_rules.zig`。

### 4.1 新增 Trap 类型

| Trap 名称 | 触发条件 | 对应 SA 原有规则 |
|-----------|---------|----------------|
| `SaxStateLeak` | `<state>` 声明的变量在组件末尾未全部 `!释放` | 类比 `MemoryLeak`（R4.5） |
| `SaxEventEscape` | `^handler` 绑定的函数不在同一 `<Component>` 内定义 | 类比借用逃逸 |
| `SaxRenderOutsideHandler` | `call @render()` 出现在 `@handler` 函数体之外 | 新增规则 |
| `SaxInvalidInterpolation` | `{expr}` 插值中出现 `^` / `!` 操作（禁止状态转移） | 类比 `ForbiddenSyntax` |
| `SaxStateWriteFromOutside` | 从组件外部直接写入 `<state>` 内存槽 | 组件封装性保证 |

### 4.2 规则说明

**SaxStateLeak**：组件状态变量是通过 `alloc` 分配的，Referee 在组件销毁函数出口处检查：
若有任何 `<state>` 变量仍处于 `Active` 状态而未被 `!释放`，则报此 Trap。

**SaxEventEscape**：`^handler` 产生的是 `BorrowView` 掩码的函数引用，Referee 检查该引用
的目标函数必须是同一 `<Component>` 内部定义的 `@handler`，防止事件处理函数逃逸到组件外。

**SaxRenderOutsideHandler**：`@render()` 函数会修改 DOM，只允许在事件处理函数（`@handler`）
体内调用，防止在初始化、生命周期钩子之外的意外位置触发 DOM 更新（初始化时由 Lowerer 自动
插入首次渲染，不需要手动调用）。

---

## 5. 响应式状态系统

### 5.1 Phase 1：手动 render（MVP）

与 web.md 最终讨论一致，Phase 1 采用最简单的手动触发模型：

- `<state>` 变量存储在 WASM 线性内存中（由 Lowerer 计算固定偏移）
- `@handler` 修改状态后手动调用 `call @render()`
- `@render()` 由 Lowerer 展开为一系列 Airlock DOM 更新调用
- **全量更新**：每次 render 重新计算所有 `{expr}` 插值并更新对应 DOM 节点

```xml
@inc:
L_ENTRY:
  count = add count, 1
  call @render()    // 手动触发，更新所有绑定了 {count} 的 DOM 节点
  ret
```

### 5.2 Phase 2：细粒度响应式（编译期依赖分析）

Phase 2 在编译期由 SAX Parser 分析 `{expr}` 插值与 `<state>` 变量的依赖关系，
自动生成最小 DOM 更新代码：

```
分析阶段：
  <h1>{count}</h1>        → h1 节点依赖 count
  <p>Last: {last} ms</p>  → p 节点依赖 last

生成阶段（@inc 的 render 展开）：
  // 只更新依赖 count 的节点，不更新依赖 last 的节点
  call @sax_dom_update_h1(&state)   // 而非全量 render
```

优势：DOM 更新粒度更细，性能更高，类似 Solid.js 的信号系统，但在**编译期**完成依赖追踪
（而非运行时），零运行时开销。

---

## 6. DOM Airlock 设计

详细 API 清单见 `docs/sax_airlock.md`。

### 6.1 设计原则

完全遵守 SA 气闸舱机制（design.md §3.7 / R13）：

- 所有 DOM 操作通过 `@extern` 声明，只能在 `@ffi_wrapper` 内调用
- JS 胶水层（airlock.js）是唯一与浏览器 DOM 交互的边界
- WASM 模块无法直接访问 JS 全局对象
- 白名单 API 仅 ~20 个，超出白名单的 DOM 操作需显式扩展

### 6.2 安全模型

```
WASM 沙箱（SA 代码）
    │  只能调用白名单 @extern
    ▼
Airlock（airlock.js）
    │  只做 WASM ↔ DOM 转发，无业务逻辑
    ▼
浏览器 DOM（受 Content Security Policy 保护）
```

- `sax_dom_set_text` 使用 `textContent`（非 `innerHTML`），天然防 XSS
- `sax_dom_set_attr` 白名单属性（`class` / `style` / `value` / `placeholder` / `disabled`）
- 事件绑定通过函数索引（非字符串 eval），防代码注入

---

## 7. 组件生命周期

### 7.1 生命周期钩子（Phase 2）

```xml
<Component name="TimerWidget">
  <state>
    tick = 0
    timer_id = 0
  </state>

  <div><p>Tick: {tick}</p></div>

  @onMount:
  L_ENTRY:
    // 挂载后启动定时器（通过 Airlock 调用 setInterval）
    id = call @sax_set_interval(^onTick, 1000)
    store state+TimerWidget_timer_id, id as i64
    ret

  @onUnmount:
  L_ENTRY:
    // 卸载前清理定时器
    id = load state+TimerWidget_timer_id as i64
    call @sax_clear_interval(id)
    ret

  @onTick:
  L_ENTRY:
    tick = load state+TimerWidget_tick as i64
    tick = add tick, 1
    store state+TimerWidget_tick, tick as i64
    call @render()
    ret

  !tick !timer_id
</Component>
```

### 7.2 生命周期对应关系

| SAX 钩子 | React 等价 | Vue 等价 | 触发时机 |
|----------|-----------|---------|---------|
| `@onMount:` | `useEffect(fn, [])` | `mounted` | 组件首次插入 DOM 后 |
| `@onUnmount:` | `useEffect(() => cleanup)` | `beforeUnmount` | 组件从 DOM 移除前 |
| `@onUpdate:` | `useEffect(fn, [deps])` | `updated` | 状态变化触发 render 后（Phase 2） |

---

## 8. 路由系统（Phase 2）

SAX 路由基于 `<Router>` 和 `<Page>` 组件，保持极简风格：

```xml
<Component name="App">
  <state>
    current_path = alloc 64
  </state>

  <Router>
    <Page path="/" component="HomePage" />
    <Page path="/about" component="AboutPage" />
    <Page path="/todo" component="TodoList" />
  </Router>

  @onMount:
  L_ENTRY:
    // 读取当前 URL，渲染对应 Page
    call @sax_router_init(&current_path)
    ret

  !current_path
</Component>
```

路由变化通过 `popstate` / `hashchange` 事件（Airlock 提供）触发对应 `<Page>` 组件的
挂载/卸载。

---

## 9. 工具链命令

在现有 `sa` CLI 下新增 `sax` 子命令：

| 命令 | 说明 | 输出 |
|------|------|------|
| `sa sax build <file.sax>` | 完整编译 | `app.wasm + airlock.js + index.html + 生成的 .sa` |
| `sa sax check <file.sax>` | 仅 Referee 验证（含 SAX 规则），不产出产物 | Trap 报告或 OK |
| `sa sax dev` | 开发服务器 + 文件监听 + WASM 热替换 | HTTP :8080 |
| `sa sax new <name>` | 脚手架：生成最小项目结构 | 目录 + 示例文件 |

`sa sax build` 的完整流程：

```
sa sax build app.sax
  1. SAX Parser: app.sax → app.sa
  2. Flattener:  app.sa → Instruction[]
  3. Referee:    Instruction[] → AnnotatedInstruction[] (含 SAX 规则)
  4. WASM Emitter: → app.wasm
  5. Airlock Gen:  → airlock.js
  6. HTML Shell:   → index.html
  输出: dist/app.wasm + dist/airlock.js + dist/index.html + dist/app.sa
```

---

## 10. 分阶段路线图

### Phase 1（MVP，约 6-8 周）：基础渲染闭环

目标：Counter + TodoList 在浏览器中正常运行

- [ ] SAX Parser（XML 层 + SA 代码块混合解析 → .sa）
- [ ] Lowerer（Component/state/DOM → SA 指令序列）
- [ ] DOM Airlock 白名单（~20 个 API + airlock.js 生成）
- [ ] Referee SAX 规则扩展（5 条新规则）
- [ ] WASM 目标切换（wasm32-unknown-unknown）
- [ ] `sa sax build` / `sax check` CLI 子命令
- [ ] HTML Shell 生成器
- 不做：生命周期钩子、路由、细粒度响应式

### Phase 2（约 4-6 周）：响应式 + 路由 + 生命周期

- [ ] 细粒度响应式（编译期依赖分析 + 最小 DOM 更新）
- [ ] `@onMount:` / `@onUnmount:` 生命周期钩子
- [ ] `<Router>` + `<Page>` 基础路由
- [ ] `sa sax dev` 热重载开发服务器
- [ ] VS Code 语法高亮插件（TextMate grammar for .sax）

### Phase 3（约 6-8 周）：跨端 + 生态

- [ ] `--target native`：原生桌面 UI（SA + 自定义渲染器）
- [ ] `--target js`：降级 JS 兼容模式（扩大受众）
- [ ] WebGPU / Canvas 渲染路径（高性能 Dashboard）
- [ ] SA 包管理集成（复用 sci 项目 v0.5 零信任包管理）
- [ ] `<style>` 块支持（类 Vue SFC，SA 变量驱动动态样式）

---

## 11. 与 React / Vue 对比

| 特性 | React | Vue SFC | Solid | **SAX** |
|------|-------|---------|-------|---------|
| 语言 | JS/TS | JS/TS | JS/TS | **SA（汇编级）** |
| 编译目标 | JS Bundle | JS Bundle | JS Bundle | **WASM** |
| 状态管理 | useState Hook | ref/reactive | Signal（编译期） | **`<state>` 显式所有权** |
| 内存安全 | GC | GC | GC | **Referee 编译期验证** |
| 运行时 GC | 有 | 有 | 有 | **无** |
| 内存泄漏 | 可能（闭包引用） | 可能 | 可能 | **编译期报 SaxStateLeak** |
| 控制流语法 | JSX 表达式 | v-if/v-for | JSX 表达式 | **扁平 `L_LABEL:` + `br`** |
| LLM 生成友好 | 中 | 中 | 中 | **高（结构化 + 无嵌套）** |
| 首屏加载 | JS 解析 + JIT | JS 解析 + JIT | JS 解析 + JIT | **WASM AOT** |
| 长时稳定性 | GC 暂停 | GC 暂停 | GC 暂停 | **无 GC 暂停** |
| 生态成熟度 | 极强 | 强 | 中 | 初期弱 |

**SAX 的差异化核心**：它不是又一个"用新语法写 JS"的框架，而是在
**编译期用所有权验证保证内存安全**，在**运行期用 WASM 跑在沙箱里**，
彻底消灭了前端中最常见的一类 bug：内存泄漏与状态不一致。

---

## 12. 验证方式

1. **Parser 降级测试**：`sa sax check counter.sax` → Referee Pass（无 Trap）
2. **泄漏检测测试**：删掉 `!count` → Referee 报 `SaxStateLeak`
3. **事件逃逸测试**：`^handler` 引用外部函数 → Referee 报 `SaxEventEscape`
4. **E2E 浏览器测试**：`sa sax build counter.sax` → 打开 index.html → 点击按钮计数正常
5. **包体积对比**：相同功能 TodoList 对比 React（目标：< 50KB WASM vs ~130KB+ React）
6. **LLM 生成测试**：将 `sax_whitepaper.md` 喂给 LLM，零训练生成合法 .sax 文件
