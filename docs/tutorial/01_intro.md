# 01. SA 简介与环境搭建

## 什么是 SA？
SA (Symbolic Affine) 是一种带所有权验证的线性汇编语言。它的目标不是提供高级语法糖，而是提供一套扁平、显式、容易由机器和 LLM 检查的低层 IR。

### 核心特性
1.  **物理所有权 (Linear Ownership)**：内存不仅是被引用的，更是被"持有"的。一旦移动，原持有者将无法访问。
2.  **零开销抽象**：SA-ASM 指令直接对应底层硬件或 LLVM 指令，没有运行时开销。
3.  **显式控制流**：没有嵌套块，只有标签、`br`、`jmp` 和 `return`。
4.  **FFI 气闸舱**：裸指针和外部 ABI 操作集中在 `@ffi_wrapper` 内。

## 环境搭建

### 1. 安装 Zig 编译器
SA 的运行时和编译器核心基于 Zig 开发。本仓库当前开发环境使用 Zig `0.14.1`。

```bash
zig version
```

### 2. 获取 SA 命令行工具
在仓库根目录编译：

```bash
zig build
```

编译完成后，可以直接运行：

```bash
./zig-out/bin/sa --help
./zig-out/bin/sa version
```

如果你已经把 `zig-out/bin` 或安装目录加入 `PATH`，也可以直接运行：

```bash
sa --help
sa version
```

### 3. 标准库路径
`@import "sa_std/..."` 默认会优先解析仓库内 `sa_std/`，也可以通过 `SA_STD_DIR` 指向另一份标准库。
