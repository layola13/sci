# SA-ASM Playground & Rust2SA 演进计划

本文档评估了构建 SA-ASM Playground 的可行性，并详细探讨了 Rust 到 SA-ASM (Rust2SA) 的转换路径及实现方案。

## 1. 核心需求
- **Playground 界面**：支持 Rust 和 SA-ASM 双代码编辑器。
- **转换功能**：核心关注 Rust -> SA-ASM 的一键转换。
- **即时运行**：支持在浏览器中直接运行 SA-ASM 并查看输出。

## 2. Rust2SA 技术路径评估

用户提问：*“WASM 内嵌是否有可能还是要通过网络调用 native 编译？”*

### 2.1 路径 A：全 WASM 内嵌（浏览器端编译）
- **方案**：将 `rustc` 及其依赖编译为 WASM 并在浏览器运行。
- **优点**：无需后端服务器，完全本地运行，隐私性好。
- **缺点**：`rustc` 的 WASM 产物体积极大（数百 MB），加载极其缓慢；且 LLVM 在 WASM 下的性能受限。
- **结论**：**不推荐**。对于 Playground 这种轻量级交互工具，前端加载成本过高。

### 2.2 路径 B：后端网络编译（推荐）
- **方案**：
    1. 前端发送 Rust 源码到后端。
    2. 后端调用 native `rustc --emit=llvm-ir` 生成 LLVM IR。
    3. 后端调用 `llvm2sa` 工具将 LLVM IR 转换为 SA-ASM。
    4. 后端返回 SA-ASM 源码。
- **优点**：响应速度快，可利用完整的 LLVM 优化套件，开发复杂度较低。
- **结论**：**强烈推荐**。这是 Rust Playground 和 Godbolt 等主流工具的通用做法。

## 3. Playground 架构设计

### 3.1 编译器后端 (Conversion Service)
- **输入**：Rust 源码。
- **处理流**：
    - `rustc -C opt-level=3 --emit=llvm-ir` -> 生成优化后的 `.ll` 文件。
    - `llvm2sa` (基于 `src/llvm2sa.zig` 开发) -> 解析 `.ll` 并生成 `.sa`。
    - **注意**：生成的 SA-ASM 将处于 `Untracked` 模式，所有权验证在 Rust 层完成。
- **输出**：SA-ASM 源码。

### 3.2 前端执行引擎 (Execution Engine)
- **方案**：将 `src/interp.zig` 编译为 WASM。
- **优势**：
    - 运行 SA-ASM 代码时无需网络交互，实现“毫秒级”运行。
    - 安全隔离：在浏览器沙箱内运行，不会威胁服务器安全。
- **VFS 支持**：需实现一个极简的虚拟文件系统，将 `sys_print` 重定向到编辑器的控制台输出。

## 4. 实施阶段

### 第一阶段：PoC 验证 (Proof of Concept)
1.  **WASM 解释器**：尝试将 `src/interp.zig` 编译为 WASM，并跑通简单的 "Hello World" SA-ASM 代码。
2.  **llvm2sa 原型**：按照 `docs/llvm2sa_feasibility.md` 的描述，手动或编写脚本将一个简单的 LLVM IR 片段转换为 SA-ASM。

### 第二阶段：工具链整合
1.  实现 `src/llvm2sa.zig` 核心翻译逻辑。
2.  构建一个简单的后端服务（基于 Node.js 或 Zig），暴露编译接口。

### 第三阶段：前端集成
1.  基于 Monaco Editor 或 CodeMirror 构建前端界面。
2.  整合 WASM 解释器实现“一键运行”。

## 5. 关键考量：所有权语义
由于 LLVM IR 丢失了 Rust 的所有权元数据，`llvm2sa` 转换后的代码将默认使用 `Untracked` 寄存器。这意味着在 Playground 中运行转换后的代码时，SA 的所有权验证器（Referee）将处于“放行模式”，安全性完全由上游 Rust 编译器保证。这符合极速执行引擎的定位。
