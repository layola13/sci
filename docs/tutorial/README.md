# SA 编程入门教程 (SA for Beginners)

欢迎来到 SA 语言的世界。SA 是一款面向机器验证和 LLM 代码生成的底层语言，它结合了汇编级的控制力与现代的线性所有权系统。

如果你只想从当前工具链可复制运行的内容开始，先读 [Beginner's Guide](beginner_guide.md)，再按 01-06 的顺序推进。

## 教程目录

### 第一阶段：初识 SA
1. [SA 简介与环境搭建](01_intro.md) - 了解 SA 的起源、核心哲学以及如何配置开发环境。
2. [Hello SA: 基础语法与指令](02_basics.md) - 编写第一个程序，学习寄存器、立即数和基本算术指令。
3. [控制流：分支与循环](03_control_flow.md) - 掌握标签（Label）、条件跳转与函数调用。

### 第二阶段：内存安全与所有权
4. [线性所有权系统](04_ownership.md) - SA 的灵魂：理解为什么 SA 不需要垃圾回收也能保证内存安全。
5. [堆与栈：动态内存管理](05_memory.md) - 使用 `alloc` 和 `sa_std` 内存分配器。

### 第三阶段：标准库与实战
6. [标准库 (sa_std) 入门](06_std_library.md) - 学习使用字符串、向量（Vec）和常用 IO 操作。

### 第四阶段：高级设计稿
7. [极速网络：Netx 引擎](07_networking.md) - `sa_netx` 的规划性网络设计。
8. [SAX: 声明式组件开发](08_sax_basics.md) - SAX 前端方言设计说明。
9. [Airlock: SA 与 UI 的桥梁](09_airlock.md) - UI 气闸舱设计说明。

### 综合实战
- [项目：构建高性能 Echo 服务器](project_echo_server.md)
- [项目：实时聊天室 (WebSocket)](project_chat.md)

---

## 学习建议
- **不要跳过第四章**：所有权系统是 SA 最难也是最核心的部分。
- **理解 bitcode 形态**：SA 与 LLVM bitcode 映射紧密相关，理解底层有助于写出更快的代码。
- **区分现状和蓝图**：01-06 是入门主线；网络、SAX、数据库和插件文档仍包含设计目标，需要对照当前源码和测试阅读。
