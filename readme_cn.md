# SA — WASM 时代的安全运行时

> **Rust 同级内存安全，Zig 同级编译速度，原生 WASM 体积领先。**
> 一份 IR，多语言喂入，全栈 WASM 交付。

📖 English: [`readme.md`](readme.md)

SA（safe asm，安全汇编）不是"又一门给人手写的语言"。它是一条 **可被任何上游语言喂入的安全 IR / 运行时**，配套从浏览器前端到边缘后端的完整插件矩阵。核心仓库提供编译器、Referee 静态验证器、LLVM-C bitcode / WASM 直通发射、`sa_std` 标准库与 `.sa` / `.sai` / `.sal` 三类源文本。

```
┌────────────────────────────────────────────────────────────────┐
│  输入前端                                                       │
│   Rust / C++ ─► bc2sa ┐                                         │
│   TS / JS    ─► ts / deno / node ┐                              │
│   Sla        ─► sla              ├─► .sa / .sai / .sal          │
│   直接手写    ─────────────────────┘                              │
└──────────────────────────┬─────────────────────────────────────┘
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  SA 核心 (本仓库)                                                │
│   Flattener → Referee (O(1) 位掩码) → LLVM-C / WASM Emitter      │
│   sa_std (Vec/HashMap/String/Arc/Mutex/io/fs/net/...)            │
│   Gas Metering · Capability Mask · 气闸舱 FFI                     │
└──────────────────────────┬─────────────────────────────────────┘
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  应用插件                                                        │
│   Web 前端：sax / react / mui / vite / wgpu / 3dengines           │
│   服务端：  http_server / http_client / db / dbnet                │
│   算力：    matmul                                                │
│   平台基建：pkg (零信任包管理) / vm (解释器)                       │
└──────────────────────────┬─────────────────────────────────────┘
                           ▼
              .exe / .o / .a / .wasm  (LLVM O1–O3)
```

---

## 为什么 SA

| 维度 | 数字 |
|------|------|
| **借用检查复杂度** | O(N) 线性扫描 + O(1) 位掩码 vs Rust 的 O(N³) NLL |
| **Referee 代码量** | ≤ 2 500 行 Zig，可逐行审计 / 可烧 FPGA |
| **前端编译速度** | 词法 ~5 ms / 类型检查 0 ms / 借用校验 ~10 ms |
| **WASM Hello World 体积** | ≤ 48 KB（含 DWARF），开 `--no-debug` 更小 |
| **运行时开销** | 零（Release 模式无 Referee 代码，机器码与 Zig / Rust 同级） |
| **沙盒原语** | Gas Metering + Capability Mask 内建，无需运行时 monitor |

**独占赛道**：

| 语言 | 内存安全 | 编译速度 | WASM 体积 / 迭代 |
|------|---------|---------|----------------|
| Rust | ✅ | ❌ 慢 | 大 / 慢 |
| Zig  | ❌（无借用检查） | ✅ | 中 |
| Go   | GC 保证 | ✅ | TinyGo 不稳 |
| **SA** | ✅ | ✅ | **48 KB / 毫秒级 dev loop** |

---

## 多语言喂入：你不需要放弃自己的语言

| 你来自 | 入口插件 | 说明 |
|--------|---------|------|
| Rust / C++ | [`sa_plugin_bc2sa`](../sa_plugins/sa_plugin_bc2sa) **（experimental）** | `clang / rustc` → LLVM bitcode → SA。当前仅翻译保守的 O0 子集（整数操作 + 静态越界检查）；`phi` / `switch` / `select` / 浮点 暂未支持。详见[评估报告](../sa_plugins/sa_plugin_bc2sa/docs/bc2sa_evaluation_cn.md)。 |
| TypeScript | [`sa_plugin_ts`](../sa_plugins/sa_plugin_ts) | TS → SA |
| JS / Deno | [`sa_plugin_deno`](../sa_plugins/sa_plugin_deno) **（experimental）** | Deno API 原生子集 —— 不是 Deno runtime。已实现：sys/env/文本 IO/UUID/base64/mkdir/lstat 等；binary IO / cwd / DNS / permissions 仍属 `planned_native`。详见[评估报告](../sa_plugins/sa_plugin_deno/docs/plugin_evaluation_cn.md)。 |
| Node | [`sa_plugin_node`](../sa_plugins/sa_plugin_node) **（experimental）** | Node API 原生门面 —— 不是 Node runtime；不含 V8 / VM。已交付 43 个模块 facade；真实 npm 兼容性尚未验证。详见[评估报告](../sa_plugins/sa_plugin_node/docs/plugin_evaluation_cn.md)。 |
| 直接写一门 Rust 风格高级语言 | [`sa_plugin_sla`](../sa_plugins/sa_plugin_sla) | Sla 是 SA 的 LLM-友好高级前端 |
| 直接手写 `.sa` | 本仓库 `sa` CLI | LLM 与底层调试的母语 |

无论哪条路径，最终都收敛到统一的 `.sa` IR，被同一个 Referee 校验，发射成同一种 WASM / native 产物。

---

## 全栈应用插件矩阵

### Web 前端（WASM-first）

| 插件 | 角色 |
|------|------|
| [`sa_plugin_sax`](../sa_plugins/sa_plugin_sax) | SA UI 方言；`.sax` → `app.wasm + airlock.js + index.html` |
| [`sa_plugin_react`](../sa_plugins/sa_plugin_react) | React-on-SAX：用 React 心智模型写 SA 组件 |
| [`sa_plugin_mui`](../sa_plugins/sa_plugin_mui) | Material UI 组件库（早期） |
| [`sa_plugin_vite`](../sa_plugins/sa_plugin_vite) | 开发服务器 + `.sax` 热重载（Phase 2） |
| [`sa_plugin_wgpu`](../sa_plugins/sa_plugin_wgpu) | 浏览器 WebGPU sidecar |
| [`sa_plugin_3dengines`](../sa_plugins/sa_plugin_3dengines) | 3D 引擎栈（对齐 Bevy 中） |

### 服务端 / 数据

| 插件 | 角色 |
|------|------|
| [`sa_plugin_http_server`](../sa_plugins/sa_plugin_http_server) | HTTP 服务端 |
| [`sa_plugin_http_client`](../sa_plugins/sa_plugin_http_client) | HTTP 客户端 |
| [`sa_plugin_db`](../sa_plugins/sa_plugin_db) | Native 列存数据库（本地文件） |
| [`sa_plugin_dbnet`](../sa_plugins/sa_plugin_dbnet) | 数据库网络层 |

### 算力 / 系统

| 插件 | 角色 |
|------|------|
| [`sa_plugin_matmul`](../sa_plugins/sa_plugin_matmul) | 物理极限优化的 GEMM 矩阵乘法 |
| [`sa_plugin_vm`](../sa_plugins/sa_plugin_vm) | 独立动态 VM 解释器 |

### 平台基建

| 插件 | 角色 |
|------|------|
| [`sa_plugin_pkg`](../sa_plugins/sa_plugin_pkg) | **大众主入口**：零信任包管理（URL-as-namespace，SHA-256 钉版，无中心化 registry，模块级 `grants` 沙盒） |

---

## 主要使用场景

| 场景 | 为什么是 SA |
|------|-----------|
| **边缘 Serverless**（Cloudflare Workers / Vercel Edge / Fastly） | 48 KB 冷启动 + Gas 上限 + capability sandbox |
| **WASM 插件宿主**（Envoy / Wasmtime / Browser） | 仿射所有权 + Referee 一次性验证，无需运行时监督 |
| **LLM Agent 代码沙盒** | Gas 预报 + Capability 白名单 = 不可信代码的物理熔断 |
| **场景**（航空 / 医疗 / 国防） | Referee 可形式化验证、可烧 FPGA，与 Ada/SPARK 形成双层防线 |
| **浏览器前端**（React 替代） | `sax + react + vite + wgpu` 全栈 WASM，体积/启动时间领先 |
| **嵌入式 / IoT** | 无 GC、无运行时、WASI 兼容、可交叉到 ARM |
| **混合 Rust/C++ 工程** | bc2sa（experimental）让既有 `.rs` / `.cpp` 不改写就能拿 SA 的验证 |

---

## 快速开始

```bash
# 构建编译器（本仓库）
zig build -Doptimize=ReleaseFast

# 直接运行
./zig-out/bin/sa run examples/hello.sa

# 编译到 WASM
./zig-out/bin/sa build-wasm examples/hello.sa -o hello.wasm

# 编译到原生可执行
./zig-out/bin/sa build-exe examples/hello.sa -o hello

# 安装应用插件（以 SAX 为例）
SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_sax
sa sax build demos/counter.sax --out-dir /tmp/counter
```

更多入口命令见各插件 README。

---

## 文档地图

| 文档 | 内容 |
|------|------|
| [`docs/design.md`](docs/design.md) | 完整技术设计（编译管线 / Referee / Emitter / 数据模型 / 41 项需求映射） |
| [`docs/requirements.md`](docs/requirements.md) | 强约束需求规约 |
| [`docs/faq.md`](docs/faq.md) | "为什么没有 X" 深度问答（控制流 / 类型 / 所有权 / 并发 / 内存 / 模块 / 包管理 / 高可靠场景） |
| [`docs/ebnf.md`](docs/ebnf.md) | SA 文本语法 EBNF |
| [`docs/errorcode.md`](docs/errorcode.md) | 结构化 Trap / CLI 错误码总目录 |
| [`docs/database.md`](docs/database.md) | sa-db 列存设计 |
| [`docs/agent_first_toolchain.md`](docs/agent_first_toolchain.md) | Agent-First CLI / `--json` / `compile_tokens` |
| [`docs/llm_cheat_sheet.md`](docs/llm_cheat_sheet.md) | LLM 生成 SA 的速查表 |
| [`docs/sla_language_specification_cn.md`](docs/sla_language_specification_cn.md) | Sla 高级前端语言规范 |
| [`docs/sla2sa_evaluation_cn.md`](docs/lua2sa_evaluation_cn.md) / [`lua2sa_*`](docs/lua2sa_deep_evaluation_cn.md) | Lua → SA 路径评估 |
| [`docs/llvm2sa_feasibility.md`](docs/llvm2sa_feasibility.md) | LLVM bitcode → SA 可行性 |
| `tasks.md` | 权威任务台账（按版本路线图） |
| `docs/progress.md` | 最新完成度审计快照 |

---

## 仓库结构

```
sci/
├── src/                   编译器、Flattener、Referee、Emitter、CLI（Zig）
├── sa_std/                标准库（.sa / .sai / .sal + Zig-backed runtime）
├── docs/                  设计 / 需求 / FAQ / 错误码 / Cheat Sheet
├── examples/              示例 .sa 程序
├── demos/                 端到端 demo（含 rosetta 对照与基准）
├── bench/                 基准测试
├── artifacts/             预编译标准库 (artifacts/sa_std/libsa_std.a)
├── tasks.md / progress.md 任务台账与进度审计
└── readme.md
```

外部插件目录：`/home/vscode/projects/sa_plugins/`，每个插件独立 `sap.json` + `.sai` + `.sal` + `.so`，可独立安装升级。

---

## 当前状态（诚实评估）

| 模块 | 状态 |
|------|------|
| 编译器核心（Flattener / Referee / LLVM Emitter / WASM Emitter / 解释器） | 主线稳定，持续优化（见 P0 工业级性能重构） |
| `sa_std` 标准库 | Wave 1/2 宏波次已落地（Vec/HashMap/String/Option/Result/Rc/Arc/Mutex 等） |
| 包管理 `sa pkg` | 早期，URL 命名空间 + SHA-256 钉版基础已具备，待深化 |
| 应用插件 | sax / react / db / http_server / vm / bc2sa / matmul 可用；mui / vite / 3dengines / deno 早期 |
| 形式化验证（Coq/Lean4） | 路线图（v0.6+） |
| FPGA 硬件化 Referee | 路线图（R33.6） |

`tasks.md` 是权威任务台账；`docs/progress.md` 是最新一次完成度审计快照。

---

## 设计哲学（一句话）

> **零 AST、线性扫描、O(1) 位掩码、五符号契约（`= & ^ ! *`）、前端责任制、显式优于隐式。**
> SA 不为人类手写而设计，它是为 LLM / 编译器前端生成、为 Referee 验证、为 LLVM / WASM 发射而设计的**中间协议**与**安全运行时**。

完整哲学与对比（vs Go / Zig / Rust / Ada/SPARK）见 [`docs/faq.md`](docs/faq.md)。

---

## 许可证

本项目以 Apache License 2.0 开源，详见 `LICENSE`。仓库附带强制性 `NOTICE` 归属文件。

Copyright 2026 zhanhaiyang.

允许在以下条件下使用、复制、修改、合并、发布、分发、再许可与销售本作品的副本：每一次源码或二进制再分发必须保留：

- 版权声明；
- 本许可证声明；
- 原作品名：`SA (safe asm, 安全汇编)`；
- 原作者署名：`zhanhaiyang`；
- 随分发附带的 NOTICE 文本。

衍生作品可使用自己的名称，但不得移除或遮蔽上述原作品名与作者署名。

Apache License 2.0 全文：`LICENSE` 或 https://www.apache.org/licenses/LICENSE-2.0
