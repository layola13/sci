# SAX 框架实现 - 下一步行动计划

## 当前状态（已完成）

✅ **规划文档**：4 份，1,958 行
- sax_design.md：框架完整设计
- sax_syntax.md：语法规范 + 4 个完整示例
- sax_airlock.md：26 个 API 白名单
- sax_whitepaper.md：LLM 即读即用白皮书

✅ **源码框架**：7 个模块，1,076 行
- parser.zig：XML 解析基础框架
- lowerer.zig：降级逻辑框架
- airlock_gen.zig：JS 胶水生成
- sax_rules.zig：Referee 规则扩展
- cli.zig：CLI 命令框架
- mod.zig + sax.zig：模块导出

✅ **示例文件**：2 个
- counter.sax：Counter 组件
- todo_list.sax：TodoList 组件

---

## Phase 1 MVP 实现清单（优先级排序）

### 1️⃣ 完善 SAX Parser（关键路径）
**目标**：能正确解析 .sax 文件，输出合法的 .sa 指令流

**任务**：
- [ ] 完整的 XML 标签解析（支持嵌套、属性、文本内容）
- [ ] `{expr}` 插值识别和验证
- [ ] `^handler` 事件绑定解析
- [ ] `@handler:` 函数块识别（复制 SA 代码直到下一个 @ 或 !）
- [ ] `!var` 释放语句解析
- [ ] 错误位置追踪和诊断

**预期输出**：
```
counter.sax → counter.sa（合法的 SA 指令流）
```

**工作量**：~300-400 行 Zig

---

### 2️⃣ 完善 SAX Lowerer（关键路径）
**目标**：将 Component/state/DOM 结构降级为 SA 指令序列

**任务**：
- [ ] 状态变量内存布局计算（对齐规则）
- [ ] 初始化函数生成（`sax_counter_init`）
  - 分配状态内存
  - 查询 DOM 节点（`sax_dom_query`）
  - 绑定事件（`sax_dom_bind_event`）
- [ ] 渲染函数生成（`sax_counter_render`）
  - 遍历状态变量
  - 生成 DOM 更新指令
- [ ] 销毁函数生成（`sax_counter_destroy`）
  - 释放所有状态变量

**预期输出**：
```sa
@export sax_counter_init():
L_ENTRY:
  state = alloc 16
  store state+0, 0 as i64
  ...
  ret
```

**工作量**：~400-500 行 Zig

---

### 3️⃣ 集成 Referee SAX 规则（关键路径）
**目标**：在现有 Referee 中集成 5 条 SAX 专属验证规则

**任务**：
- [ ] 在 Referee 主流程中调用 `sax_rules.checkStateLeak()`
- [ ] 在 Referee 主流程中调用 `sax_rules.checkEventBinding()`
- [ ] 在 Referee 主流程中调用 `sax_rules.checkRenderCall()`
- [ ] 在 Referee 主流程中调用 `sax_rules.checkInterpolation()`
- [ ] 在 Referee 主流程中调用 `sax_rules.checkStateWrite()`
- [ ] 新增 5 个 SAX Trap 类型到 `common/trap.zig`

**预期输出**：
```
counter.sa → Referee Pass（无 SaxStateLeak / SaxEventEscape 等）
```

**工作量**：~200-300 行 Zig

---

### 4️⃣ WASM 目标代码生成（关键路径）
**目标**：将 .sa 编译到 wasm32-unknown-unknown

**任务**：
- [ ] 在 emit_wasm 中切换目标为 `wasm32-unknown-unknown`
- [ ] 生成 WASM 线性内存布局（状态槽）
- [ ] 生成 WASM 导出函数（`sax_counter_init` / `sax_counter_render` / `sax_counter_destroy`）
- [ ] 生成 WASM 外部函数声明（Airlock API）

**预期输出**：
```
counter.sa → counter.wasm（可在浏览器中加载）
```

**工作量**：~200-300 行 Zig（复用现有 emit_wasm）

---

### 5️⃣ CLI 命令完整实现（关键路径）
**目标**：`sa sax build/check` 子命令可用

**任务**：
- [ ] 在 cli.zig 中添加 `sax` 子命令识别
- [ ] 实现 `sa sax build counter.sax` 完整流程
  - 读取 .sax 文件
  - 调用 SAX Parser
  - 调用 Flattener
  - 调用 Referee（含 SAX 规则）
  - 调用 WASM Emitter
  - 调用 Airlock 生成器
  - 输出 app.wasm + airlock.js + index.html
- [ ] 实现 `sa sax check counter.sax` 验证流程

**预期输出**：
```bash
$ sa sax build counter.sax
✓ SAX build successful
  .wasm: dist/counter.wasm
  airlock.js: dist/airlock.js
  index.html: dist/index.html
```

**工作量**：~150-200 行 Zig

---

### 6️⃣ 浏览器集成测试（验证）
**目标**：Counter 组件在浏览器中正常运行

**任务**：
- [ ] 生成 index.html 的完整版本（包含样式）
- [ ] 在浏览器中加载 counter.wasm + airlock.js
- [ ] 点击 +1/-1 按钮，验证计数正常
- [ ] 验证 DOM 更新正确

**预期输出**：
```
浏览器中显示 Counter 组件，点击按钮计数正常
```

**工作量**：~100 行 HTML/CSS + 测试

---

## 实现顺序（推荐）

```
1. SAX Parser 完善
   ↓
2. SAX Lowerer 完善
   ↓
3. Referee SAX 规则集成
   ↓
4. WASM 目标代码生成
   ↓
5. CLI 命令完整实现
   ↓
6. 浏览器集成测试
```

**预计总工作量**：1,500-2,000 行 Zig + 测试

---

## 技术细节

### SAX Parser 的关键算法

```zig
// 伪代码
fn parseComponent(source: []const u8) -> SasmCode {
    // 1. 解析 <Component name="X">
    // 2. 解析可选的 <state> 块
    //    - 记录所有 state_vars
    //    - 计算内存布局
    // 3. 解析 DOM 树
    //    - 递归解析 XML 标签
    //    - 识别 {expr} 插值
    //    - 识别 onclick={^handler} 事件
    // 4. 解析 @handler 函数块
    //    - 复制 SA-ASM 代码直到下一个 @ 或 !
    // 5. 解析 !var1 !var2 ... 释放语句
    // 6. 输出 .sa 文本
}
```

### SAX Lowerer 的关键算法

```zig
// 伪代码
fn generateInit(component: Component) -> SasmCode {
    // 1. 分配状态内存：state = alloc SIZE
    // 2. 初始化状态变量：store state+OFFSET, VALUE
    // 3. 查询 DOM 节点：node = call @sax_dom_query(selector)
    // 4. 绑定事件：call @sax_dom_bind_event(node, event, handler)
    // 5. 首次渲染：call @sax_counter_render()
}

fn generateRender(component: Component) -> SasmCode {
    // 1. 遍历所有 {expr} 插值
    // 2. 对每个插值生成更新指令
    //    - load state+OFFSET
    //    - call @sax_dom_set_text(node, value)
}
```

### Referee SAX 规则的关键检查

```zig
// 伪代码
fn checkStateLeak(component: Component, released_vars: Set) {
    for var in component.state_vars {
        if var not in released_vars {
            return error.SaxStateLeak
        }
    }
}

fn checkEventBinding(handler_name: []const u8, component: Component) {
    if handler_name not in component.handlers {
        return error.SaxEventEscape
    }
}

fn checkRenderCall(current_context: Context) {
    if current_context != .inside_handler {
        return error.SaxRenderOutsideHandler
    }
}
```

---

## 测试计划

### 单元测试
- [ ] SAX Parser 解析 counter.sax 正确
- [ ] SAX Lowerer 生成合法的 .sa
- [ ] Referee 验证通过
- [ ] WASM Emitter 生成有效的 .wasm

### 集成测试
- [ ] `sa sax build counter.sax` 完整流程
- [ ] 生成的 app.wasm + airlock.js + index.html 可用
- [ ] 在浏览器中加载并运行

### E2E 测试
- [ ] 打开 index.html
- [ ] 点击 +1 按钮，计数从 0 变为 1
- [ ] 点击 -1 按钮，计数从 1 变为 0
- [ ] 点击 Reset 按钮，计数变为 0

---

## 风险与缓解

| 风险 | 缓解方案 |
|------|---------|
| SAX Parser 复杂度高 | 分阶段实现，先支持简单 XML，逐步扩展 |
| WASM 生成困难 | 复用现有 emit_wasm，仅切换 target |
| Referee 规则冲突 | 在 sax_rules.zig 中独立实现，不修改核心 |
| 浏览器兼容性 | 使用标准 WebAssembly API，支持所有现代浏览器 |

---

## 成功标准

✅ **Phase 1 MVP 完成**：
1. `sa sax build counter.sax` 成功生成 app.wasm + airlock.js + index.html
2. 在浏览器中打开 index.html，Counter 组件正常运行
3. 点击按钮，计数正确更新
4. 所有 SAX Trap 规则正确触发

✅ **代码质量**：
- 总代码量 < 3,000 行 Zig（包括注释）
- 编译无警告
- 所有单元测试通过

---

## 后续 Phase 2/3 预告

### Phase 2（4-6 周）
- 细粒度响应式（编译期依赖分析）
- 生命周期钩子（@onMount / @onUnmount）
- 基础路由（<Router> / <Page>）
- 开发服务器与热重载

### Phase 3（6-8 周）
- 原生桌面 UI（--target native）
- JS 兼容模式（--target js）
- WebGPU / Canvas 渲染
- 完整生态工具链

---

## 参考资源

- **规划文档**：/home/vscode/projects/sci/SAX_IMPLEMENTATION_SUMMARY.md
- **设计文档**：/home/vscode/projects/sci/docs/sax_design.md
- **语法规范**：/home/vscode/projects/sci/docs/sax_syntax.md
- **API 文档**：/home/vscode/projects/sci/docs/sax_airlock.md
- **白皮书**：/home/vscode/projects/sci/docs/sax_whitepaper.md
- **示例**：/home/vscode/projects/sci/examples/counter.sax

---

## 快速开始

```bash
# 1. 查看规划
cat SAX_IMPLEMENTATION_SUMMARY.md

# 2. 查看示例
cat examples/counter.sax

# 3. 运行集成测试
bash test_sax_integration.sh

# 4. 开始实现 Phase 1
# 按照上述清单逐步完善各模块
```

---

**目标**：在 2-3 周内完成 Phase 1 MVP，实现 Counter 组件在浏览器中的正常运行。
