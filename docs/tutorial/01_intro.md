# 01. SA 简介与环境搭建

## 什么是 SA？
SA (System Architecture / Safe Assembly) 是一种**强类型、带所有权验证的线性汇编语言**。它的设计目标是取代 C/C++ 在高性能服务器、中间件和嵌入式领域中的地位，同时提供不亚于 Rust 的内存安全性。

### 核心特性
1.  **物理所有权 (Linear Ownership)**：内存不仅是被引用的，更是被"持有"的。一旦移动，原持有者将无法访问。
2.  **零开销抽象**：SA-ASM 指令直接对应底层硬件或 LLVM 指令，没有运行时开销。
3.  **极速 IO**：内置对 `io_uring` 的原生支持，专为单机百万并发设计。
4.  **SAX 架构**：独特的 XML+SA 混合语法，用于开发极高性能的 UI 组件。

## 环境搭建

### 1. 安装 Zig 编译器
SA 的运行时和编译器核心基于 Zig 开发，请确保你的系统中安装了 Zig (推荐版本 0.13.0 或更高)。

```bash
# Ubuntu/Debian
snap install zig --classic --beta
```

### 2. 获取 SA 命令行工具
克隆本仓库并编译：

```bash
git clone https://github.com/sci/sa.git
cd sa
zig build -Doptimize=ReleaseSafe
```

编译完成后，建议将 `zig-out/bin/saasm` 添加到你的 `PATH` 环境变量中。

### 3. VS Code 插件
搜索并安装 `SA-ASM Language Support` 插件，以获得语法高亮和代码补全支持。

## 验证安装
在终端输入：

```bash
saasm --version
```

如果你看到版本号输出，恭喜你，你已经准备好开启 SA 之旅了！
