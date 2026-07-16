# SA-ASM Documentation Index

欢迎来到 SA (safe asm, 安全汇编) 语言的核心文档库。为了帮助你快速找到所需的信息，我们将所有文档按照**阅读阶段与用途**进行了分类。

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
  说明插件作为独立工程交付 `sap.json + .so + .sa + .sai + .sal` 的真实契约、插件依赖、权限声明、ABI smoke、能力发现与当前限制。
- ⚙️ **[Network Engine Plan (极速网络基座)](./network_engine_plan.md)**  
  详述 `sa_net_uring` 如何通过 io_uring 和零拷贝实现 10 万并发无开销。
- 🔗 **[Network Protocol Bindings Sinking (网络协议 binding 下沉)](./net_bindings_sink.md)**  
  HTTP/2 (nghttp2) / TLS-server / DTLS (OpenSSL) / QUIC / HTTP/3 真后端从 `sa_plugin_node` 下沉到 `sci` runtime 与 `sa_std` ABI/宏的分级进展、真机状态与严格单测证明。
- 💻 **[Multi-Platform Architecture (全平台架构)](./multi_platform_architecture.md)**  
  PAL 与跨平台 Reactor 的长期概念设计。
- 🧭 **[macOS / Windows Portability Evaluation (可移植性评估与最小改动方案)](./macos_windows_portability_evaluation_cn.md)**
  基于当前代码和交叉目标诊断，给出 ABI 保持、typed resource、宿主/runtime 双边界、原生 CI 与分阶段交付方案。
- 🚄 **[Compiler Performance Optimization (编译器性能优化方案)](./compiler_performance_optimization_cn.md)**
  基于当前 Flattener、SAB、Referee、LLVM-C、缓存、测试与 daemon 实现，给出正确性前置、热点优化、统一 key/预算、路线图和验收门禁。
- **[Rust -> SA/SCI Compiler Evaluation (Rust 直接编译架构评估)](./rust_to_sa_compiler_deep_evaluation_cn.md)**
  以 rustc mono Instance/codegen MIR 为入口，评估 Rust 源码直接降低到 SA/SAB 并由 SCI 验证和发射目标对象的可行性、ABI 缺口、信任边界与分阶段门禁。

## 🧾 2.1 SA 文件后缀与清单速查

| 文件 | 作用域 | 用途 |
| --- | --- | --- |
| `.sa` | 用户代码 / 标准库源码 | SA-ASM 实现文件，包含可验证的指令、函数、宏调用和 `@import`。 |
| `.sai` | 接口契约 | SA Interface 文件，只声明 `@extern` 等外部 ABI，让 Referee 能检查调用边界。 |
| `.sal` | 布局与 facade | SA Layout 文件，声明 `#def` 常量、结构偏移、slot 装配和薄宏 facade。 |
| `sa.mod` | 业务包依赖 | SA Package manifest，声明普通源码包依赖、hash、permissions 和插件需求，不描述 native artifact。 |
| `sap.json` | 插件工程清单 | SA Plugin manifest，声明插件 `.so`、`.sa/.sai/.sal`、skills、permissions、ABI 和插件间依赖。 |

## 🔌 3. 插件开发指南 (Plugin Guides)
专门针对独立插件工程的深度解析与实战。

当前外部插件工作区是 `/home/vscode/projects/sa_plugins/`。截至 2026-06-04，已纳入评估的独立工程包括：`sa_plugin_pkg`、`sa_plugin_db`、`sa_plugin_deno`、`sa_plugin_http_client`、`sa_plugin_http_server`、`sa_plugin_sax`、`sa_plugin_bc2sa`、`sa_plugin_node`、`sa_plugin_ts`、`sa_plugin_vm`、`sa_plugin_wgpu` 和 `sa_plugin_3dengines`。

- 🌐 **[HTTP Client Plugin (独立工程)](./http_client_plugin.md)**  
  如何发送 GET/POST、处理 TLS 和流式响应。
- 🚀 **[HTTP Server Plugin (独立工程)](./http_server_plugin.md)**  
  如何启动监听、处理路由与构建 Echo 服务器。
- 🛡️ **[SAX Airlock (沙箱气闸舱)](./sax_airlock.md)**  
  FFI 调用的安全边界设计。
- 🗄️ **[Database Plugin Design (数据库插件)](./database.md)**  
  说明数据库能力如何通过插件/FFI 与 SA 查询模块协作。

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
