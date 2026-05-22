# SA-ASM 极简 Rust 转换器 (No-LLVM) 设计方案

本方案旨在响应用户需求，不通过 LLVM，直接利用 SA 现有特性（如 Flattener 和 SAX 降级思想）实现一个极简的 Rust 到 SA-ASM 的 Source-to-Source (S2S) 转换器。

## 1. 核心设计：基于模式匹配的语法降级 (DMT - Direct Mapping Transpiler)

既然不追求完整的 Rust 语义（如 Trait、复杂的泛型等），我们可以将目标锁定在 **Rust 的指令级子集**。这个子集与 SA-ASM 的 ISA 几乎是 1:1 映射的。

### 1.1 核心映射表

| Rust 语法 (输入) | SA-ASM 语义 | 内部降级逻辑 |
|---|---|---|
| `fn name(a: i64) -> i64 { ... }` | `@name(a: i64) -> i64:` | 自动插入 `L_ENTRY:` 标签 |
| `let x = a + b;` | `x = add a, b` | 简单的表达式展平 |
| `if cond { A } else { B }` | `br cond -> L_TRUE, L_FALSE` | 生成唯一标签并实现分支跳转 |
| `drop(x);` | `!x` | 显式释放所有权 |
| `return val;` | `return val` | 函数返回 |

## 2. 利用现有特性实现

### 2.1 借用 SAX 的降级思想
项目中的 `src/sax/parser.zig` 已经实现了一套从 XML 结构降级到 `.sa` 的逻辑。我们可以参考此逻辑，编写一个 `src/sax/rust_flavor.zig`，它：
- 使用正则或简单的词法分析器（Lexer）提取 Rust 的 `fn` 块。
- **不构建复杂的 AST**，而是直接线性扫描并将大括号 `{}` 块展平为 SA-ASM 的标签流。

### 2.2 利用 Flattener 的宏系统
可以定义一套 Rust 风格的宏（如 `#def_fn`, `#let`），让 Flattener 在预处理阶段完成部分转换工作。

## 3. 实现细节

### 3.1 控制流展平 (Control Flow Flattening)
这是该转换器唯一需要一点逻辑的地方。例如将 Rust 的 `if` 块：
```rust
if c {
    x = 1;
} else {
    x = 2;
}
```
自动转换为 SA-ASM：
```
    br c -> L_IF_1_TRUE, L_IF_1_FALSE
L_IF_1_TRUE:
    x = 1
    jmp L_IF_1_END
L_IF_1_FALSE:
    x = 2
L_IF_1_END:
```

### 3.2 变量映射
Rust 的变量名直接映射为 SA-ASM 的寄存器名。SA 的寄存器是虚拟的且数量无限，这与 Rust 的局部变量行为高度一致。

## 4. Playground 集成建议

- **前端层**：在 Monaco Editor 中增加一个 "Simple Rust to SA" 按钮。
- **执行层**：
    - 调用这个轻量级的 Zig 脚本（编译进 WASM）。
    - 转换结果直接输入到现有的 `src/interp.zig` (WASM版) 运行。
- **优点**：
    - **极快**：无需在服务器端运行 `rustc` 和 LLVM。
    - **纯浏览器实现**：由于逻辑简单，转换逻辑可以完全跑在前端。

## 5. 结论
这种“极简转换器”本质上是 SA-ASM 的一个 Rust 语法糖层。它牺牲了 Rust 的生态兼容性，但极大地提升了 Playground 的响应速度和开发便捷性，非常适合用于演示 SA 的所有权核心概念。
