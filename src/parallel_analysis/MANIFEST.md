# SA 标准库模块化 Phase 8 — `sa-parallel-analysis` 模块清单（P8C 起草稿）

> 阶段：Phase 8（P2）并行模块分析。只做整理/实现，不跑构建/测试、不修 bug（用户 2026-11-22 10:02 令；修与测试验证另行安排）。
> 工作仓：盒上 `/content/kit-work/sci2`（主副本），分支 `sa-optimize`，基线 `5884db2e`（Phase 7 终推）。只新增 `src/parallel_analysis.zig` 与 `src/parallel_analysis/`，`/content/sa_all/sci` 原仓未动，未合 main。
> 本稿为 P8C 起草、协调 agent 合并定稿：§5 合并对齐已填裁决（A1–A8 + M1–M6）；§2 文件清单已按落盘行数修正。

## 1. 模块目的

回答一次全量分析“哪些模块可以按层并行分析、每层实际分析 / 跳过 / 已分析 / 失败了多少”。只做分层调度与结果汇总：按 P8A 的分层（`Schedule`）逐层走，每层先按 Phase 7 的复用计划（`ReusePlan`）切分出可跳过的模块，其余逐个调 P8B 的单模块分析（`analyzeOne`），核对 loader 状态后汇总成 `RunReport`。不并行执行（本轮是进程内串行回退）、不编译模块本身、不写缓存、不改依赖图。

提案 §5 第 8 阶段（并行模块分析，P2）与 §2（四态：`unloaded` / `loading` / `loaded` / `analyzed`）：只有 `loaded` 态的模块值得分析（`analyzeOne` 把它推到 `analyzed`），已是 `analyzed` 态的记 `already_analyzed` 不重做；分层保证同层模块之间无依赖关系，是可并行的单位。

## 2. 文件清单

| 文件 | 职责 | 行数 | 编写 |
|---|---|---|---|
| `src/parallel_analysis/driver.zig` | `LayerReport` / `RunReport` / `runSchedule` / `analyzeAllParallel` / `summarize`：五步分层驱动与报告 | 390 | P8C |
| `src/parallel_analysis/MANIFEST.md` | 模块清单（目的、分工、API 表、关系表、合并对齐、已知缺口） | 144 | P8C 起草 + 协调定稿 |
| `src/parallel_analysis/types.zig` | `AnalysisOutcome` / `ParallelError` / `Schedule` / `Layer` / `ParallelConfig`：并行类型正本 | 108 | P8A |
| `src/parallel_analysis/scheduler.zig` | `computeLayers`：由模块图算分层 | 178 | P8A |
| `src/parallel_analysis/worker.zig` | `WorkItem` / `WorkResult` / `analyzeOne`：单模块分析 | 142 | P8B |
| `src/parallel_analysis/cache_filter.zig` | `LayerSplit` / `splitLayer` / `isReuse` / `isRebuild`：层内复用切分 | 149 | P8B |
| `src/parallel_analysis.zig` | facade：薄 re-export，不含逻辑 | 55 | 协调 |

## 3. API 表

### 3.1 本文件新增（`driver.zig`）

| 名字 | 形状 | 说明 |
|---|---|---|
| `LayerReport` | `struct { depth, analyzed, skipped, already, failed: usize }` | 一层的值类型报告，不拥有切片 |
| `RunReport` | `struct { layers: []LayerReport, total_analyzed, total_skipped, total_already, total_failed: usize, allocator }` + `deinit` + `summarize` | 一轮的全部产出；`deinit` 只释 `layers`（长度为 0 的不释放）；`summarize` 纯文本一行，静态 512 字节缓冲区借用切片 |
| `DriverError` | `ParallelError \|\| LoaderError` | 分层 / 切分失败或单模块分析抛错都以错误返回整轮；`.failed` 的 `WorkResult` 不是错误 |
| `runSchedule` | `(loader: *LazyLoader, schedule: *const Schedule, plan: *const ReusePlan, allocator) DriverError!RunReport` | 五步分层驱动（见 §3.2） |
| `analyzeAllParallel` | `(loader: *LazyLoader, graph: *ModuleGraph, plan: *const ReusePlan, allocator) DriverError!RunReport` | 便捷入口：`computeLayers` → `runSchedule`，`Schedule` 用完即 `deinit` |

### 3.2 `runSchedule` 五步（缺一不可，顺序固定）

1. 按层号从小到大走 `schedule.layers`（层间串行：后一层开始前，前一层全部完成——依赖保证；信任 `computeLayers` 已按 `depth` 升序，不重排）；
2. 每层先调 `splitLayer(layer.modules, plan, allocator)` 切分：`plan.reuse` 里的记 skipped（不调 `analyzeOne`）；其余进 `to_analyze`；
3. 层内按 modules 顺序（已按 `(package, path)` 排过）逐个调 `analyzeOne(loader, id)`，串行执行；outcome 分别计入 analyzed / already_analyzed / failed（`analyzeOne` 自身返回 `.skipped_cached` 时也记 skipped）；`analyzeOne` 返回 `.failed`（`WorkResult`，非错误）时记 failed 继续下一模块，不中断整层；`analyzeOne` 抛错误（`LoaderError`）时整轮返回错误（调用方凭错误集区分可恢复失败与硬错误）；
4. 每模块 `analyzeOne` 返回 `.analyzed` 后核对 `loader.stateOf(id) == .analyzed`，不对则该模块改记 failed（detail 记 `"state not analyzed after analyzeOne"`）；
5. 返回 `RunReport`。

### 3.3 P8A / P8B 的调用形状（假设，见 §5 A1–A4）

| 名字 | 假设形状 | 正本 |
|---|---|---|
| `AnalysisOutcome` | `enum { analyzed, skipped_cached, already_analyzed, failed }` | P8A `types.zig` |
| `ParallelError` | `GraphError \|\| std.mem.Allocator.Error` | P8A `types.zig` |
| `Schedule` | `layers: []Layer` / `total_modules: usize` / `max_width: usize` / `deinit` | P8A `types.zig` |
| `Layer` | `depth: usize` / `modules: []ModuleId` | P8A `types.zig` |
| `ParallelConfig` | 执行器配置（本驱动不消费，留给后续线程池执行器） | P8A `types.zig` |
| `computeLayers` | `(graph: *ModuleGraph, allocator) ParallelError!Schedule`（`graph` 可写：内调 `topoSort()`；`layers` 按 `depth` 升序） | P8A `scheduler.zig` |
| `WorkItem` / `WorkResult` | `WorkResult` 含 `module: ModuleId`、`outcome: AnalysisOutcome` 与可写 `detail: []const u8` | P8B `worker.zig` |
| `analyzeOne` | `(loader: *LazyLoader, id: ModuleId) LoaderError!WorkResult` | P8B `worker.zig` |
| `LayerSplit` | `skipped` / `to_analyze` 两个 owned `[]ModuleId` 切片 + `allocator` + `deinit` | P8B `cache_filter.zig` |
| `splitLayer` | `(modules: []const ModuleId, plan: *const ReusePlan, allocator) std.mem.Allocator.Error!LayerSplit` | P8B `cache_filter.zig` |
| `isReuse` / `isRebuild` | `(plan: *const ReusePlan, id: ModuleId) bool`（切分谓词；本驱动不直接调，仅 re-export） | P8B `cache_filter.zig` |

### 3.4 复用（不重定义）

| 名字 | 正本 |
|---|---|
| `ReusePlan`（`reuse` / `rebuild` / `invalidated` 三个 `[]ModuleId` 切片，均按 `(package, path)` 字典序） | Phase 7 `src/incremental_cache/driver.zig` |
| `ModuleId` / `ModuleState` / `LazyLoader` / `LoaderError`（`stateOf` 为 loader 权威状态读口） | Phase 3 `src/module_loader/loader.zig` |
| `ModuleGraph` / `GraphError`（`topoSort() GraphError![]ModuleId`，有环报 `CycleDetected`） | Phase 4 `src/dependency_graph/module_graph.zig` |

### 3.5 所有权要点

- 调用方传入一个 arena 分配器；`RunReport` 用它分配唯一的 owned 切片（`layers`），`deinit` 用它释放；长度为 0 的切片不释放（与 Phase 5 / 6 / 7 同款口径）。
- `LayerSplit` 的 owned 切片（`skipped` / `to_analyze`）由驱动在每层结束时 `deinit` 释放，不带出本轮；`Schedule` 由调用方拥有，`runSchedule` 只借用（`*const`），`analyzeAllParallel` 内部建的 `Schedule` 用完即 `deinit`。
- `summarize` 返回文件级静态缓冲区（512 字节）的借用切片：调用方久存请自行复制；连续两次调用后一次覆盖前一次；非线程安全；层数极多溢出时退化为已写出的前缀（总数行完整，层明细截断）。
- `plan` / `graph` 只借用，不拥有、不修改；`loader` 的状态机只由 `analyzeOne` 内部推进，本驱动不直接改状态。

## 4. 与 Phase 2 / Phase 3 / Phase 4 / Phase 5 / Phase 6 / Phase 7 的关系表

| Phase | 本模块用它的什么 | 关系说明 |
|---|---|---|
| Phase 2（Import Resolver） | `ModuleId`（`package` / `path`，`(package, path)` 字典序）、`ModuleState` 四态 | 层内 modules 顺序与 `plan` 三个切片的顺序口径都源于此 |
| Phase 3（Lazy Module Loading） | `LazyLoader` / `stateOf` / `LoaderError` / `markAnalyzed`（经 `analyzeOne` 间接） | 驱动的第 ④ 步以 `loader.stateOf` 为权威核对；`analyzeOne` 把 `loaded` 推到 `analyzed` |
| Phase 4（模块依赖图） | `ModuleGraph` / `topoSort` / `GraphError`（经 `computeLayers` 间接） | 分层是拓扑序按深度分组；有环时 `computeLayers` 报 `CycleDetected`，整轮返回错误、不产出报告 |
| Phase 5（符号级 Reachability） | `summarize` 纯文本、无 JSON 的口径 | `RunReport.summarize` 与 Phase 5 `summarize` 同款口径 |
| Phase 6（Dead Code Elimination） | `summarizeDce` 纯文本、无 JSON 的口径；`deinit` 长度为 0 不释放的口径 | 同上；`RunReport.deinit` 与 `DceResult` 同款口径 |
| Phase 7（增量编译缓存） | `ReusePlan` / `planIncremental` 五步顺序 / `summarizePlan` 静态 512 字节缓冲区口径 / `moduleIdLessThan` 口径 | 本驱动第 ② 步的切分以 `plan.reuse` 为准：命中缓存的模块不调 `analyzeOne`；`summarize` 与 `summarizePlan` 同款静态缓冲口径 |

## 5. 合并对齐（协调 agent 合并时核对，A1–A8；本稿为起草，留空位待定稿）

> 三 agent 并行编写，各写不同新文件，无文件冲突；facade 与本节定稿由协调 agent 合并时写。
> 以下 A1–A8 为 P8C 写 `driver.zig` 时的假设（P8A / P8B 尚未落盘，写时按任务书约定形状写）；合并时以落盘为准逐项核对，逐项填裁决。

| # | 出入 | 裁决（合并时填） |
|---|---|---|
| A1 | `types.zig` 正本形状：`AnalysisOutcome` 四变体、`ParallelError`、`Schedule`（`layers` / `total_modules` / `max_width` / `deinit`）、`Layer`（`depth` / `modules`）、`ParallelConfig` | 以 P8A 落盘为准，无出入：四变体 / `ParallelError` / `Schedule` / `Layer` / `ParallelConfig` 均与任务书约定一致；facade 转发其中 8 个名。 |
| A2 | `computeLayers(graph, allocator)` 的 `graph` 是否可写（`*ModuleGraph` 还是 `*const ModuleGraph`）、`layers` 是否按 `depth` 升序 | 以 P8A 落盘为准：`graph` 为 `*ModuleGraph`（可写，内调 `topoSort()` 写 `lastCycles`）；`layers` 按 `depth` 升序，`runSchedule` 不重排。另：`topoSort()` 实际输出使用方在前（见 §7.2 第 7 项），`computeLayers` 倒序遍历算层——合并时未改方向。 |
| A3 | `analyzeOne(loader, id)` 的 `loader` 是否为 `*LazyLoader`、`WorkResult` 的字段（`id` / `outcome` / `detail` 是否存在、类型） | 以 P8B 落盘为准：`loader` 为 `*LazyLoader`；`WorkResult` 字段为 `module`（非 `id`）/ `outcome` / `detail: []const u8`；`driver.zig` 的 A3 文档已按落盘改回（M2）。 |
| A4 | `splitLayer(modules, plan, allocator)` 的参数顺序与返回值、`LayerSplit` 的字段名（`reuse` / `to_analyze`）、`isReuse` / `isRebuild` 的参数顺序 | 以 P8B 落盘为准：`splitLayer(modules, plan, allocator) std.mem.Allocator.Error!LayerSplit`；`LayerSplit` 字段为 `skipped` / `to_analyze`（非 `reuse`）；`isReuse` / `isRebuild` 参数顺序为 `(plan, id)`；`driver.zig` 的 A4 文档与 `split.reuse.len` 代码行已按落盘改回（M2）。 |
| A5 | `ReusePlan` 的形状（Phase 7 已落盘：`reuse` / `rebuild` / `invalidated` + `stats`） | Phase 7 落盘为准，无改动：`reuse` / `rebuild` / `invalidated` + `stats`；`splitLayer` 的切分规则（rebuild 优先、未进计划保守进 `to_analyze`）与之一致。 |
| A6 | `DriverError = ParallelError \|\| LoaderError` 的拼法（Zig 0.17 错误集 `||` 并集） | 写法与 Phase 7 的错误集并集同款（`GraphError \|\| Allocator.Error` 已在 `types.zig` 落盘）；未经编译验证，构建验证时核对。 |
| A7 | 第 ④ 步改写 `result.detail`：若 P8B 落盘的 `WorkResult` 无 `detail` 字段，删这一行赋值、只计 failed | P8B 落盘的 `WorkResult` 有 `detail: []const u8` 字段且 `result` 为 `var`，改写保留，无需删行。 |
| A8 | `Schedule.deinit` 与 `LayerSplit.deinit` 是否存在、口径（长度为 0 的不释放） | 均存在：`Schedule.deinit`（`types.zig`）、`LayerSplit.deinit`（`cache_filter.zig`），口径均为“只释 owned 切片，长度为 0 的不释放”；`driver.zig` 的两处 `deinit` 调用点无改动。 |
| M1 | facade 由谁写、公开名清单 | 协调写 `src/parallel_analysis.zig`（55 行），薄 re-export 24 个公开名：`types` 8（`ParallelError` / `AnalysisOutcome` / `Layer` / `Schedule` / `ParallelConfig` / `ModuleId` / `ModuleState` / `GraphError`）、`computeLayers`、`worker` 3（`WorkItem` / `WorkResult` / `analyzeOne`）、`cache_filter` 4（`LayerSplit` / `splitLayer` / `isReuse` / `isRebuild`）、`driver` 5（`LayerReport` / `RunReport` / `DriverError` / `runSchedule` / `analyzeAllParallel`）、复用 3（`LazyLoader` / `ModuleGraph` / `ReusePlan`）。 |
| M2 | P8A 写时 `types.zig` / `scheduler.zig`、P8B 写时 `worker.zig` / `cache_filter.zig` 的 import 悬空；另 `driver.zig` 的字段名与文档错误 | 合并后六文件同落主副本，`check_phase8.py` 核对 0 悬空；悬空只是并行编写期的预期跨 agent 依赖。另按 P8B 落盘改回：`driver.zig` 的 `split.reuse.len` 代码行改为 `split.skipped.len`；A3/A4 文档的 `WorkResult.id`→`module`、`LayerSplit.reuse`→`skipped`、`splitLayer` 错误集 `ParallelError`→`Allocator.Error`、`isReuse`/`isRebuild` 参数顺序→`(plan, id)`；§3.3 / §3.5 同步改回。 |
| M3 | MANIFEST §2 文件清单的行数（P8A / P8B 文件行数） | 合并后按落盘行数修正：`types` 108、`scheduler` 178、`worker` 142、`cache_filter` 149、`driver` 394、`facade` 55、MANIFEST（定稿行数见本表）。 |
| M4 | `ParallelConfig` 是否进 `runSchedule` / `analyzeAllParallel` 的参数（P8C 未接：串行回退不消费配置） | 未进：串行回退不消费配置；留给后续线程池执行器接线时定（见 §7.2 第 1 项）。 |
| M5 | `worker.zig` N1：`analyzeOne` 的钩子调用顺序（P8B 按任务书字面顺序先调 `analyze_hook`、再调 `markAnalyzed`，非 noop 钩子会被调两次） | 合并时改：`analyzeOne` 不再直接调 `analyze_hook`，只调 `markAnalyzed`（由它置态并驱动两钩子一次；与 loader 自身的 `analyzeAll` 同款模式）。钩子失败不回滚是 Phase 3 已文档化的语义（`markAnalyzed` 先置状态再调钩子）。 |
| M6 | `scheduler.zig`：`topoSort()` / `dependsOn()` 返回切片的释放分配器 | 合并时改：两处 `allocator.free` 改为 `graph.allocator.free`（切片由图的分配器分配）；`Schedule` 自身的 `layers` 仍用传入的 `allocator`。 |

## 6. 已知缺口（只记，不擅自改结构）

1. 线程执行器未实现：本驱动在进程内串行执行各层（可验证的回退行为）；层本身就是并行结构，将来线程池执行器替换第 ③ 步的串行循环即可，无需改计划结构；线程本身的创建 / 同步是后续接线阶段的事。
2. `build.zig` 未注册：`parallel_analysis`（与 Phase 2 的 module_resolver、Phase 3 的 module_loader、Phase 4 的 dependency_graph、Phase 5 的 reachability、Phase 6 的 dce、Phase 7 的 incremental_cache 同样）未接 build；注册是后续 Phase / 协调方的事。
3. 钩子为空实现（Phase 3 遗留）：parse / type-check / analyze 未接任何解析器；`analyzeOne` 实际分析能力的落地依赖钩子接线。
4. `string/` 无 prelude 仍是缺口（模块级边回退到域模块本身，Phase 2 已知缺口）：分层与切分只按模块级边走，符号级粒度是后续 Phase 的事。
5. A1–A8 未经编译验证（只跑 ast-check；P8A / P8B 尚未落盘，四处 import 在合并前悬空，见 §8）。
6. `summarize` 只产纯文本，无结构化（JSON）输出（与 Phase 5 `summarize` / Phase 6 `summarizeDce` / Phase 7 `summarizePlan` 同款口径；JSON 输出本身是 Phase 5 §6 第 5 项待裁决）；不逐个列出分析 / 跳过 / 失败模块。
7. `analyzeOne` 抛错即整轮返回：本驱动不重试、不跳过单模块硬错误；重试 / 降级策略是调用方的事（见 driver.zig 文件头“错误语义”）。

## 7. 待裁决（原样登记，不做定夺）

### 7.1 Phase 7 RESULT §6 的 10 项、Phase 6 的 10 项、Phase 5 的 9 项、Phase 4 的 12 项、Phase 3 的 7 项、Phase 2 的 10 项、Phase 1 的 8 项（合订指针）

原样登记，未做定夺。出处：Phase 7 `~/workspace/sci2-opt-std/phase7/RESULT.md` §6（10 项）；Phase 6 RESULT §6（10 项）；Phase 5 的 9 项、Phase 4 的 12 项、Phase 3 的 7 项、Phase 2 的 10 项、Phase 1 的 8 项（Phase 7 RESULT §6 第 8 项合订指针）。

### 7.2 Phase 8 自身（本文件新立，只记、待协调裁决）

1. `ParallelConfig` 是否进驱动入口参数（见 §5 M4）：串行回退不消费配置；线程池执行器接线时再定是驱动取配置还是执行器自取。
2. `analyzeOne` 返回 `.skipped_cached` 时的计数口径：本驱动记入 `skipped`（与 `plan.reuse` 的跳过同口径）；若 P8B 的语义是“worker 内部复用命中”，是否应在 `RunReport` 里单列一栏，待定。
3. 第 ④ 步状态核对的权威来源：目前以 `loader.stateOf` 为准（Phase 7 RESULT §6 第 2 项同款问题：图状态可能滞后）；`analyzeOne` 内部是否已保证置态，待 P8B 落盘后核对。
4. `RunReport` 是否携带逐模块明细（目前只记数）：调用方要明细须读 `schedule` 各层与 `plan` 的三个切片再结合 loader 状态；是否补逐模块 outcome 表，待接线 Phase 定。
5. 线程池执行器的归属：是 Phase 8 内的后续文件，还是独立的接线 Phase；执行器是否复用 `ParallelConfig` 的字段，待定。
6. 有环图的失败口径：`computeLayers` 报 `CycleDetected` 时整轮返回错误；是否应先产出一份“截至环前已完成层”的部分报告，待定（目前不产出半成品报告）。
7. **`topoSort()` 文档与实现相反（P8A 发现、协调 agent 亲读落盘证实，Phase 4 缺陷，修复阶段裁决）**：文档两处（`module_graph.zig:40`、`:296`）称“依赖先于使用方”，实现按 `edge.to` 计入度、零入度种子是无人依赖的根模块，实际输出使用方在前、依赖在后（A→B→C 链输出 A、B、C）。全仓无任何 `topoSort` 代码消费者（只有文档引用），今天无既有行为受影响；`computeLayers` 倒序遍历算层，合并时未改方向。裁决二选一：(a) 上游把 `topoSort()` 改成与文档一致的“依赖在前”，`computeLayers` 的倒序同步改回正序；(b) 改文档认领现状，倒序保留。**在裁决前不要动 `topoSort()` 或 `scheduler.zig` 的遍历方向。**
8. `stateOf` 返回 null（未登记模块）的 detail 文案（P8B N2）：目前按 `.unloaded` 同款处理，detail 为 `"module not loaded"`；是否改为独立 detail（如 `"module not registered"`），待定。
9. `splitLayer` 只信计划、不查 loader 状态（P8B N1）：计划算出后、切分前 loader 状态若变了，仍按旧计划划进 `skipped`；计划与切分应在同一轮内先后完成（P8C 驱动的责任）；是否切分时二次核对 loader 状态，待定。

## 8. 未做的事（按任务硬约束，另行安排）

- **无构建/测试结果可报**：未跑 `zig build`、未跑 `zig test`、未跑任何测试。只对 `driver.zig` 跑 `zig ast-check`（parse-only）与行数核对；四处跨文件调用形状（`types.zig` / `scheduler.zig` / `worker.zig` / `cache_filter.zig`）只靠读任务书与 Phase 7 / Phase 4 / Phase 3 落盘代码核对签名，未经编译。
- 未接线：`runSchedule` / `analyzeAllParallel` 只定义调用顺序与契约，未接入任何真实调用方；`build.zig` 未注册 `parallel_analysis`（与 Phase 2/3/4/5/6/7 同样未接 build）。
- 未修任何 bug：包括 Phase 1 的构建断裂（`growvec.sai` @extern panic）、sci 7ecae6d 的 double-free、任务 79 报告的 6 项基线缺陷、Phase 1–7 的待裁决项。
- 未动 `sa_std/`、`tests/`、`build.zig*`；未写 facade（facade 由协调 agent 合并时写）；未合 main；未动 `/content/sa_all/sci` 原仓。
- 未实现线程执行器：线程创建 / 同步、任务窃取 / 工作队列、跨层屏障均未实现；本驱动是串行回退。
- 未编译、未分析任何真实模块：`RunReport` 只汇总计数，分析的执行是 P8B 的 `analyzeOne` 的事；是否把报告写回构建流程、由哪个后端消费，是后续接线阶段的事。
