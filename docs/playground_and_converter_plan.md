# 全局架构演进与 Playground (Rust2SA) 详细设计方案

本文档汇总了本轮对话中关于**全平台架构改进**与 **Playground 建设**的评估结果，并针对“不依赖 LLVM 的极简 Rust2SA 转换器”提供了所有实施细节。

---

## 第一部分：本轮对话与评估总结

### 1. 架构改造评估：支持全平台 (Windows, macOS, Linux)
- **问题现状**：当前 SA-ASM 运行时深度绑定 Linux (`io_uring` 网络引擎、`epoll` 事件系统、读取 `/proc/self/cmdline` 等)。
- **解决方案**：引入平台抽象层 (PAL)。将 `io_uring` 抽象为通用的 `Reactor` 接口（后续可接入 Windows IOCP 和 macOS kqueue）；将平台相关系统调用抽离至 `src/runtime/pal/` 目录下，由 `build.zig` 根据目标 OS 动态编译。
- **状态**：已输出评估报告，未修改代码。

### 2. Playground 架构选型评估
- **需求**：一个支持 Rust 和 SA-ASM 互转并能在线运行的 Web Playground。
- **编译路径（Rust -> SA）**：
  - *方案 A（依赖后端）*：前端 -> 后端 `rustc` 输出 LLVM bitcode -> 后端 `bc2sa` -> 前端。优点是完全兼容 Rust 生态。
  - *方案 B（纯前端，无 LLVM）*：编写轻量级转换器编译为 WASM。优点是零网络延迟，全本地运行。
- **运行路径**：将 SA 的解释器（`src/interp.zig`）编译为 WASM，直接在浏览器沙箱中执行 SA-ASM 源码并拦截输出。

---

## 第二部分：极简 Rust2SA 转换器 (No-LLVM) 详细设计

为了响应“利用现有特性做一个简单 converter”的需求，我们将设计一个纯 Zig 编写的轻量级前端（Transpiler），它将直接把 Rust 的一个指令级子集（Safe-Subset Rust, **SS-Rust**）编译为 SA-ASM。

这个转换器可以直接编译进 WASM，在 Playground 中实现**毫秒级的全本地 Rust 编译与执行**。

### 1. 语言子集 (SS-Rust) 的边界定义
由于不依赖 LLVM，我们不实现复杂的 Rust 特性（如 Trait、生命周期推导、宏）。
我们定义一个严格的子集，使其语义能够与 SA-ASM 的 ISA 发生 1:1 的完美映射：
- **数据类型**：支持 `i64`, `f64`, `bool`, 指针。不支持复杂的 `struct` 嵌套（或强制退化为内存偏移）。
- **控制流**：支持 `if / else`, `while`, `loop`。不支持 `match` 模式匹配。
- **内存与所有权**：支持 `let mut`, `&` (借用), `drop()` (显式释放)。**不执行复杂的借用检查**，直接将语法翻译为 SA 指令，**安全校验交由 SA 本身的 Referee (所有权状态机) 在下一阶段完成**。

### 2. 转换器架构与模块划分
在 `src/` 目录下新建 `rust2sa/` 模块，包含三个核心组件：

1. **`lexer.zig` (词法分析)**：将 Rust 源码切分为 Token（如 `KwLet`, `Ident`, `OpAdd`, `LBrace`）。
2. **`parser.zig` (递归下降解析器)**：构建轻量级抽象语法树 (AST)。
3. **`emitter.zig` (指令展平与发射器)**：遍历 AST，生成无嵌套的 SA-ASM 文本。

### 3. 核心转换逻辑与映射细节

#### 3.1 表达式展平 (Expression Flattening)
SA-ASM 是三地址指令集，没有嵌套表达式。Emitter 必须负责将复杂的 Rust 表达式展平，自动分配虚拟寄存器。

**输入 (Rust)**:
```rust
let a = (b + c) * d;
```
**内部 AST**: `Assign("a", Mul(Add("b", "c"), "d"))`
**输出 (SA-ASM)**:
```
// Emitter 自动生成临时变量 tmp_0
tmp_0 = add b, c
a = mul tmp_0, d
```

#### 3.2 控制流降级 (Control Flow Lowering)
利用现有的 `SymbolTable` 思想，为每个控制流块生成全局唯一的 Label 计数器。

**输入 (Rust)**:
```rust
if count > 10 {
    count = 0;
} else {
    count = count + 1;
}
```
**输出 (SA-ASM)**:
```
  cond_0 = sgt count, 10
  br cond_0 -> L_IF_0_TRUE, L_IF_0_FALSE
L_IF_0_TRUE:
  count = 0 as i64
  jmp L_IF_0_END
L_IF_0_FALSE:
  count = add count, 1
L_IF_0_END:
```
*细节：`while` 循环同理，被降级为 `L_WHILE_COND`, `L_WHILE_BODY`, `L_WHILE_END` 三个标签加上有条件 `br` 和无条件 `jmp`。*

#### 3.3 所有权与内存语义映射
这是利用 SA 现有特性的关键所在。我们不需要在转换器中写一个 NLL (非词法作用域生命周期) 检查器，而是直接产生带有 SA 所有权标记的代码。

| Rust 语法 | 翻译后的 SA-ASM | 校验阶段 |
|---|---|---|
| `let x = 5;` | `x = 5 as i64` | `Active` 掩码初始化 |
| `drop(x);` | `!x` | 显式标记为 `Consumed` |
| `let y = &x;` | `y = borrow x` | 生成 `BorrowView`，原始 `x` 进入 `Locked` |
| `foo(x);` (Move语义) | `call @foo(x)` | 传值后，Referee 会自动剥夺 `x` 的所有权 |

如果在 Rust 代码中写了 `drop(x); let y = x + 1;`，转换器会忠实地生成：
```
!x
y = add x, 1
```
然后在执行时，**SA 编译器现存的 Referee 会抛出 `UseAfterMove` 陷阱**。
这意味着：**我们用极简的转换器借用了 SA 强大的后端校验能力！**

#### 3.4 函数声明与调用约定
**输入 (Rust)**:
```rust
fn calculate(base: i64, factor: i64) -> i64 {
    return base * factor;
}
```
**输出 (SA-ASM)**:
```
@calculate(base: i64, factor: i64) -> i64:
L_ENTRY:
  res_0 = mul base, factor
  return res_0
```

### 4. Playground 集成工作流

通过将 `rust2sa/` 和 `interp.zig` 编译为单一的 `playground.wasm`，整个交互流程如下：

1. **编辑阶段**：用户在 Web UI 的 Monaco Editor 中输入 SS-Rust 源码。
2. **编译 API**：JS 调用 WASM 导出的 `sa_playground_compile_rust(src_ptr, len, out_buf, out_len)`。
3. **AST 转换**：WASM 内部走 `lexer -> parser -> emitter`，将生成的 SA-ASM 字符串写入 `out_buf`。
4. **验证阶段**：JS 获取 SA-ASM 后，UI 立即显示汇编代码。同时 WASM 内部调用 SA 的 `flattener` 和 `referee` 对生成的 SA-ASM 进行校验。如果有所有权错误，直接在 UI 提示（例如 `UseAfterMove`）。
5. **运行阶段**：用户点击 "Run"，JS 调用 WASM 的 `sa_playground_run()`。
6. **I/O 气闸舱拦截**：`interp.zig` 中执行到 `sys_print` 等外部函数时，通过 WASM Import 回调到 JS 环境，将打印结果输出到网页的虚拟 Console 窗口中。

### 5. 方案优势总结
这套 "No-LLVM" 的直接降级方案，彻底放弃了与真实 `rustc` 的绑定，换来了：
- **极小体积**：整个 WASM 文件预计 < 500KB。
- **极致速度**：编译 + 执行的端到端延迟可控制在几毫秒，非常适合高频交互的 Playground。
- **完美契合教学**：用户可以直观地看到高层 Rust 语法是如何被展平为低层 SA-ASM 寄存器指令的，并且所有权错误直接由 SA 解释器报出，具有极强的教育意义。
