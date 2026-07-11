# Agent-Native 编译后端：能力评估与开发计划

> 目标定位（用户战略判断）：大模型时代，代码生成能力正在商品化，真正稀缺的是
> **编译 / 验证 / 运行反馈的吞吐量**。SA/SAB 的核心竞争力应是
> **"AI 多 Agent 并发生成代码时，编译器和验证器能否扛住高频反馈"**。
>
> 一句话：**AI 会写代码，但工具链决定 AI 能试错多少次。**

本文档基于对 `sci/src` 的**代码级核实**（不是文档声称）给出当前真实支持度，
并把缺口拆成可执行的开发计划。核实日期：2026-07-11。核实方法：直接读
`src/cli.zig` / `src/flattener.zig` / `src/referee.zig` / `src/sab.zig` /
`src/emit_llvm_llvmc.zig` 的实现，配合 `Command` 枚举与实跑行为，不采信任何未经
代码确认的百分比。

---

## 0. 结论速览（能力矩阵）

按你在战略描述里列出的 Agent-native 特性逐项核实：

| # | 特性 | 战略要求 | 当前真实状态（代码核实） | 完成度 |
|---|------|----------|--------------------------|--------|
| 1 | 结构化 JSON 诊断 | 机器可读、稳定错误码 | ✅ `--json` 全局标志真实实现；`SA-FLAT-001/SA-REF-010/011` 等稳定码存在于 `cli.zig` | **~85%** |
| 2 | `explain`/`fix`/`skills` 子命令 | Agent 自学习/修复计划 | ✅ 三个命令都在 `Command` 枚举里真实存在，有 `--json` | **~80%** |
| 3 | `graph`/`size`/`layout --json` | 爆炸半径 / 体积分析 | ✅ 命令存在；`graph` 依赖/调用图、`size` 函数级体积 | **~70%** |
| 4 | 编译期 token / gas 计量 | `compile_tokens`/`instruction_count` | ⚠️ 文档设计完整，代码里 metrics 字段部分存在，未全量接线 | **~40%** |
| 5 | 文件级增量缓存 | 改动后避免全量重编 | ✅ 默认开启（`--no-incremental` 关闭）；`build-obj-incremental` 复用 per-function `.o`，按 mtime+size+sha256 判定 | **~70%** |
| 6 | **函数级增量 SAB delta** | 只重编改动的函数 | ❌ 无。缓存是文件/artifact 粒度，非 function-body 粒度 delta | **~15%** |
| 7 | **增量 Referee（summary hash 复用）** | 未变函数不重验 | ❌ 无 function-body-hash / effect-summary / capability-hash 复用机制 | **~5%** |
| 8 | **选择性测试执行** | 只跑受影响测试 | ❌ 无 test dependency graph / affected-test 选择；`--jobs` 仅并行执行已选测试 | **~10%** |
| 9 | **daemon / server 常驻模式** | Agent 连常驻服务，不重启进程 | ❌ 无 `daemon`/`watch`/`serve` 编译入口（`serve` 仅出现在 plugin 上下文，非编译守护） | **0%** |
| 10 | **可取消编译 (cancellable jobs)** | 过期任务取消 | ❌ 无 job 调度器 / cancellation | **0%** |
| 11 | **speculative / branch-aware 编译** | 多候选共享 base cache | ❌ 无 branch delta 机制 | **0%** |
| 12 | 资源隔离 / 调度器 | per-agent quota、优先级队列 | ❌ 无；`--jobs N` 只是单进程内并行度 | **~5%** |
| 13 | 快速分层失败 | Syntax<5ms … Referee<50ms 分层拒绝 | ⚠️ 分阶段错误存在且早期拒绝，但无显式延迟预算 / 分层 SLA | **~50%** |
| 14 | 多语言统一 SAB（TS/RS/SLA→SAB） | 统一增量构建图 | ⚠️ SLA→SAB 已成熟；RS→SAB 未见；统一构建图未建 | **~30%** |
| 15 | SAB 分布式/模块级编译 | 模块级并行 + 缓存 | ⚠️ 文档 `sab_distributed_compilation.md` 设计完整；代码里 `module` 相关有 21 处，但模块级 SAB 缓存管线未落地 | **~25%** |

**核实要点：**
- 已存在三份高质量设计文档：`agent_first_toolchain.md`、`multi_agent_workflow_cn.md`、
  `sab_distributed_compilation.md`。**设计走在实现前面很多。**
- `multi_agent_workflow_cn.md` 声称的 `sa contract freeze` / `sa func verify` /
  `sa func emit` / `sa coordinate` / `sa link --contract` **在 `Command` 枚举里
  全部不存在**（各 0 处匹配）。这些是纯设计，尚未落地。
- `@reserved` / `@stub` 源码声明未被 parser/flattener 识别。

**总判断：**
- **单次 Agent 交互层（JSON/explain/fix/skills/graph/size）：真实 ~75%，是当前最大亮点。**
- **并发 / 增量 / 反馈吞吐量层（daemon/函数级增量/增量 Referee/选择性测试/可取消/推测编译）：真实 ~10%。这正是战略定位的核心，却是当前最大空白。**

即：**"Agent 能读懂编译器"已基本做到；"编译器能扛住 N 个 Agent 高频并发试错"几乎从零开始。**

---

## 1. 现状详解（代码证据）

### 1.1 已经具备（可验证）

- **全局 `--json`**：`cli.zig:hasJsonFlag` + 各子命令 `--json` 帮助项。诊断可机器解析。
- **稳定错误码**：`cli.zig:1472+` 有 `SA-FLAT-001`(ForbiddenSyntax)、`SA-FLAT-050`
  (ImportResolutionFailed)、`SA-REF-010`(RegisterRedefinition)、`SA-REF-011`
  (UnknownRegister) 等映射表。
- **Agent 子命令**：`Command` 枚举含 `explain`、`fix`、`skills`、`graph`、`size`、`layout`。
- **文件级增量缓存**：默认开启。`BuildCacheKind.build_obj_incremental` 复用
  per-function `.o`；`SourceTreeHashCacheEntry` 按 (mtime,size) + sha256 判定失效。
- **并行 emit**：`emit_llvm_llvmc.zig` 用 `std.Thread.spawn` 起 `emitWorker`，
  当 `--jobs>1` 且函数数 ≥100 时启用 codegen-unit 并行。
- **导入源缓存**：`flattener.zig` 有 `import_source_cache` / `expanded_import_cache`
  （带 mutex、tick、命中计数），跨编译复用导入展开结果。

### 1.2 关键空白（战略核心，却缺失）

1. **没有 daemon**。每次 Agent 调用都是冷启动进程。20 个 Agent = 20 次进程冷启 +
   缓存无法在进程间充分复用（现有 cache 多为进程内 static + 磁盘 artifact）。
2. **增量粒度是文件，不是函数**。改一个函数仍触发该文件所在编译单元的重处理；
   没有 "只 parse/lower/emit/verify 这一个函数 + 受影响调用边" 的路径。
3. **Referee 无增量**。没有 function-body-hash / type-layout-hash / capability-hash /
   effect-summary。每次验证都是全量，N-Agent 并发时会线性放大成本。
4. **测试无选择性**。没有 test dependency graph；改 `can_access()` 会连带跑
   `parser` 测试。`--jobs` 只是把已选测试并行跑，不减少测试集。
5. **无 job 调度 / 取消 / 配额**。过期任务（Agent 已生成 v2 仍在等 v1）无法取消；
   无 per-agent 内存/并发配额，多 Agent 易打爆机器（本机 3.5GB/无 swap 已多次 OOM，
   正是这个风险的实证）。

---

## 2. 开发计划（分阶段，按"反馈吞吐量"收益排序）

设计原则：**先把冷启动 + 全量验证这两个最大放大器干掉，再做函数级增量与调度。**

### Phase A —— 常驻 daemon + 进程间缓存复用（最高杠杆）

**目标 KPI：把 N-Agent 的冷启动成本从 O(N) 降到 O(1)，缓存跨请求命中。**

- `sa daemon`（新 `Command`）：常驻服务，维护进程内 AST/import/SAB/Referee 缓存。
- 简单本地协议（Unix socket + JSON 行协议，复用现有 `--json` 诊断模型）。
- 请求类型：`build` / `check` / `test` / `explain` / `cancel`。
- CLI 瘦客户端：`sa build --daemon` 优先连 daemon，失败回落到进程内。
- 把现有 static 缓存（`import_source_cache`、`source_tree_hash_cache`）迁移为
  daemon 生命周期内的共享缓存，天然被多 Agent 复用。

**验收**：10-Agent benchmark（见 §3），daemon 模式相对冷启动模式的 P50 反馈延迟下降 ≥5×。

**落地文档**：扩写 `agent_first_toolchain.md` 增加 "§5 Daemon 模式" 章节。
Phase A 的完整可执行协议规范（进程模型 / 线协议 / 复用 `executeWithWritersAndOptions`
的执行路径 / 缓存迁移 / 验收标准）见 `agent_daemon_protocol_cn.md`。

### Phase B —— 函数级内容哈希 + 增量 Referee

**目标 KPI：未变函数零重验；改一个函数的验证成本从 O(module) 降到 O(1+调用边)。**

- 在 `sab.zig` 为每个 function body 计算稳定 content hash（指令流 + 常量 + 类型布局）。
  已有 `writeOptionalHash`/`readOptionalHash` 基础设施，扩展为 per-function。
- `referee.zig` 输出并缓存 per-function summary：
  ```json
  {"function":"can_access","hash":"...","effects":[],"borrows":"ok",
   "capabilities":[],"verified":true}
  ```
- 验证前查 summary 缓存：hash 命中 → 跳过；未命中 → 验证并写回。
- 受影响集：仅重验 body-hash 变化的函数 + 其直接调用边（layout/capability 依赖）。

**验收**：改单函数后 `sa check` 的 Referee 阶段耗时与项目规模解耦（近似常数）。

**落地文档**：把 `sab_distributed_compilation.md` §3.2/§3.3 的缓存与跨模块验证协议
细化为 function-level，并补 "增量 Referee summary 格式" 小节。

### Phase C —— 选择性测试执行

**目标 KPI：改 `can_access()` 只跑 policy 测试，不跑 parser 测试。**

- 构建 test → function 覆盖依赖图（可复用 Phase B 的调用图）。
- `sa test --affected`：只跑与变更函数有依赖边的测试。
- daemon 内维护 test 结果缓存（按覆盖到的函数 hash 判定失效）。

**验收**：单函数改动触发的测试数 ≤ 该函数被引用的测试闭包，而非全量。

### Phase D —— job 调度器 / 取消 / 配额（多 Agent 抗压）

**目标 KPI：N 个 Agent 并发时机器不被打爆；过期任务被取消。**

- daemon 内置调度器：`max_parallel_{parse,lower,referee,emit}`、`max_memory_mb`、
  `per_agent_quota`、`priority_queue`、`dedupe_same_job`、`cancel_stale_jobs`。
- 可取消编译：请求携带 `agent_id` + `generation`；同 agent 新 generation 到达时
  取消旧 generation 的在途任务。
- 背压：超配额请求排队而非 OOM（直接回应本机 3.5GB/无 swap 的实测 OOM 风险）。

**验收**：50-Agent 压测下峰值内存有界、无 OOM、过期任务取消率可观测。

### Phase E —— 分层失败 SLA + token 计量补全

- 为每个拒绝阶段设显式延迟预算并在 `--json` 输出实测耗时：
  Syntax<5ms / Resolve<10ms / Layout<20ms / Capability<20ms / Referee<50ms。
- 补全 `compile_tokens` / `instruction_count` 全量接线（Phase 4 特性，当前 ~40%）。

### Phase F（长期）—— 多语言统一 SAB 构建图 + 分布式

- RS→SAB 前端（`sa_plugin_rs`）接入统一 SAB 增量构建图。
- 落地 `sab_distributed_compilation.md` 的模块级并行 + 跨模块 SAB 缓存。
- `multi_agent_workflow_cn.md` 的 `contract freeze/diff` / `func verify/emit` /
  `link --contract` 落到 `Command` 枚举（目前全为设计）。

---

## 3. 建议的 MVP：不是 hello world，是并发 benchmark

按战略描述，MVP 应直接证明"抗并发"，而非"能编译"：

```text
模拟 10 个 Agent 各改一个 rule_NN.sla / rule_NN.rs
对比：
  A) 冷启动全量：10 × 冷启进程 × 全量 check/test    → 排队/打满
  B) daemon + 函数级增量 + affected-test           → 共享缓存 + 只重验改动函数
指标：Concurrent jobs/sec、P50/P99 反馈延迟、峰值内存、cache 命中率、
      cancelled stale jobs
```

**公开指标表**（daemon 应可 `--json` 吐出）：
`cold_compile_ms` / `incremental_compile_ms` / `sab_emit_ms` / `referee_verify_ms` /
`wasm_emit_ms` / `test_feedback_ms` / `concurrent_jobs_per_sec` /
`peak_memory_mb_under_N_agents` / `cache_hit_rate` / `cancelled_stale_jobs`。

其中 **`concurrent_jobs_per_sec`** 是 Agent 时代的新头号指标。

---

## 4. 诚信备注

- 本文档的"完成度%"来自代码核实，不等于 `tasks.md` 的自我声称。三份既有设计文档
  质量很高，但 **设计 ≠ 实现**：多处声称的 CLI 命令在 `Command` 枚举里不存在。
- 单次交互层（§1.1）是真实且扎实的工程成果，可作为 daemon 的现成协议基座。
- 战略核心的并发/增量/吞吐层（§1.2）基本空白——这既是最大缺口，也是最大机会：
  **它决定 SA 在 AI-Agent 时代是否具备差异化竞争力。**

---

## 附：与既有文档的关系

- `agent_first_toolchain.md` —— 单次交互层设计（已大部分实现）。本计划的 Phase A 为其补 daemon。
- `multi_agent_workflow_cn.md` —— 多 Agent 协议 + 契约冻结（纯设计）。本计划 Phase F 落地其 CLI。
- `sab_distributed_compilation.md` —— 模块级 SAB 缓存/并行（纯设计）。本计划 Phase B/F 细化到函数级并落地。
- 本文档定位：**把三份设计的实现状态钉死 + 按吞吐量收益重排优先级 + 给出可压测的 MVP。**
