# SA-ASM Documentation Index

欢迎来到 SA (Symbolic Affine) 语言的核心文档库。为了帮助你快速找到所需的信息，我们将所有文档按照**阅读阶段与用途**进行了分类。

## 🎯 1. 入门与初学者教程 (Tutorials)
如果你是第一次接触 SA 语言，请**务必**从这里开始。

- 📖 **[Beginner's Guide (初学者教程)](./tutorial/beginner_guide.md)**  
  👉 **必读**：包含安装、Hello World、核心 5 符号、扁平控制流及日常编写指南。
- 🧱 **[SAX Basics (SAX 基础)](./tutorial/08_sax_basics.md)**  
  说明 `.sax` 如何真实生成 `app.wasm`、`airlock.js`、`index.html` 和 `.sa`，以及如何在浏览器里验证。
- ⚡ **[LLM Cheat Sheet (AI 极简速查表)](./llm_cheat_sheet.md)**  
  高浓度提取的语法规范与核心限制，专门写给 LLM (GPT/Claude) 读的 Prompt 底稿。
- ❓ **[FAQ (常见问题解答)](./faq.md)**  
  详细解释了为什么 SA 抛弃了 `if/else`、`while`、`struct` 以及 `try-catch`。

## 🏗️ 2. 核心架构与白皮书 (Architecture & Whitepapers)
深入了解 SA 作为“极速、零信任、内存安全汇编”的底层设计。

- 📜 **[SA Whitepaper v0.1 (白皮书)](./whitepaper.md)**  
  全景式概述 SA 的设计哲学、内存安全定理及能力。
- 🔒 **[Zero-Trust Package Management (零信任包管理)](./package_management.md)**  
  介绍 SA 独创的“哈希锁死 + 零权限默认 + AST X光扫描”供应链安全体系。
- 🧩 **[External Plugin System (外部插件系统)](./pluginssytem.md)**  
  教你如何把插件作为独立工程交付为 `.so` 动态库，并在宿主外部完成热重载。
- ⚙️ **[Network Engine Plan (极速网络基座)](./network_engine_plan.md)**  
  详述 `sa_net_uring` 如何通过 io_uring 和零拷贝实现 10 万并发无开销。
- 💻 **[Multi-Platform Architecture (全平台架构)](./multi_platform_architecture.md)**  
  PAL 抽象层设计，支持 Windows IOCP 与 macOS kqueue。

## 🔌 3. 插件开发指南 (Plugin Guides)
专门针对独立插件工程的深度解析与实战。

- 🌐 **[HTTP Client Plugin (独立工程)](./http_client_plugin.md)**  
  如何发送 GET/POST、处理 TLS 和流式响应。
- 🚀 **[HTTP Server Plugin (独立工程)](./http_server_plugin.md)**  
  如何启动监听、处理路由与构建 Echo 服务器。
- 🛡️ **[SAX Airlock (沙箱气闸舱)](./sax_airlock.md)**  
  FFI 调用的安全边界设计。
- 🗄️ **[Database Plugin Design (数据库插件)](./database.md)**  

## 🔬 4. 底层规范与语言定义 (Specifications & Internals)
给编译器前端开发者和 SA 核心贡献者看的硬核参考。

- 📝 **[EBNF Syntax (语法标准)](./ebnf.md)**  
  SA-ASM 语言的严谨形式化文法定义。
- ⚠️ **[Error Codes & Traps (错误与陷阱码)](./errorcode.md)**  
  详尽的编译器 Panic 列表（如 `MemoryLeak`, `UseAfterMove`）及排查指南。
- 🧪 **[Native Unit Test Framework (原生单元测试)](./unit_test_framework.md)**  
  如何编写 `@test` 以及 `sa test` CLI 的隔离架构。
- 🔄 **[BC2SA Feasibility (LLVM bitcode 降级反编译)](./llvm2sa_feasibility.md)**  
  将 Rust/C 的 `.bc` 无损翻译回 SA-ASM 的可行性与实战对比。
- 📚 **[Standard Library RFCs (标准库提案)](./std_rfc.md)**  
  SA 标准库的扩充计划与演进记录。

---
> *Tip: 大多数 `.md` 文件内都附带了丰富的 Mermaid 时序图与 SA-ASM 源码示例。请配合 `src/` 和 `demos/` 目录进行对照阅读。*
