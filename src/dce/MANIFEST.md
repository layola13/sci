# sa-dce — 模块清单（Std 模块化 Phase 6，协调合并定稿）

> 提案：`~/workspace/goals/sci-sa-optimize/files/STD-MODULARIZATION-PROPOSAL.md`
> （§2 第 3 点：编译时懒加载不等于 WASM 体积优化、Reachability-based DCE；
> §3 两层依赖图与保留规则；§5 实施顺序：Phase 6 Dead Code Elimination，P1）。
> Phase 5 结果：盒上 `src/reachability/`（analyzer / roots / converge / report）
> 与 `src/reachability/MANIFEST.md`；Phase 5 RESULT（本机
> `~/workspace/sci2-opt-std/phase5/RESULT.md`，重点 §6 待裁决 / 跟进项）。
> 工作仓：盒上 `/content/kit-work/sci2-agentP6C`（分支 `sa-optimize`，
> 基线 `b3c64ca3`，Phase 5 终推）；三路 agent 副本在
> `/content/kit-work/sci2-agentP6A/B/C`。本阶段只新增 `src/dce/` 下的
> 新文件，不改任何现有文件，不合 main，不提交。
>
> **本文为 P6C 起草**：§1–§4、§6–§7 由 P6C 起草；§5 合并对齐留空位，
> 由协调 agent 定稿（见 §5）。本文的契约部分以协调 agent 的定稿为准。

## 1. 模块目的

`sa-dce` 是提案 §5 的 Phase 6（Dead Code Elimination，P1），提案 §3
的 Reachability-based DCE 的执行层，独立于 Lexer、Referee、Backend。

它承接 Phase 5 可达性分析的产出（`ReachabilityReport`：可达符号、
可裁剪候选 `prunable`、按模块统计、P5B 的 `Convergence`），产出提案
§3 要求的结果：只保留实际需要的节点——可达符号与保留模块进入最终
产物，其余符号、边、模块从图中拿掉。

它**不是**可达性分析本身（Phase 5）、**不是**依赖图本身（Phase 4）、
**不是**加载器（Phase 3）。它只做裁剪的接线与报告：本身不直接建新图、
不删符号、不判定任何保留规则（保留规则的判定能力缺口见 §4 关系表
与 §7）。

关键事实（提案 §3 与 Phase 4 落盘）：`SymbolGraph` 与 `ModuleGraph`
都只有 add API，没有 remove / delete API（append-only）。裁剪绝不在
原图上删东西，而是由 P6A 产出全新的 `PrunedGraph`（只含保留内容），
原图原样不动；校验由 P6B 的 `verifyPruned` 做（返回违规列表，空 = 通过）。

建议管线中的位置（提案 §4）：

```
Source → Module Resolver → Lazy Loader → Parser → Name Resolution
  → Dependency Graph（Phase 4）
  → Semantic Analysis → Flattener → SA IR → Referee
  → Reachability Analysis（Phase 5：P5A 分析 → P5B 根与收敛 → P5C 报告与入口）
  → Dead Code Elimination（本模块：P6C 入口 eliminate → P6A 裁剪 → P6B 校验 → DceResult）
  → WASM / LLVM / JS
```

## 2. 文件清单

| 文件 | 职责 | 行数 |
|---|---|---|
| `src/dce/pruner.zig` | `RemovedSymbol` / `PrunedGraph`（正本）；`prune`：P6A 的裁剪实现（产出全新的 `PrunedGraph`） | 405 |
| `src/dce/guard.zig` | `DceViolationKind` / `DceViolation`（正本）/ `DceStats`；`verifyPruned`：P6B 的校验实现（返回违规列表，空 = 通过）；`countStats` | 356 |
| `src/dce/eliminate.zig` | `DceOutcome` / `DceResult`；`eliminate`：Phase 6 集成入口（五步固定顺序）；`summarizeDce`：纯文本摘要；`RemovedSymbol` / `PrunedGraph` / `DceViolationKind` / `DceViolation` 只转发（re-export，正本见 pruner.zig / guard.zig） | 344 |
| `src/dce/MANIFEST.md` | 本清单（P6C 起草；§5 已由协调 agent 定稿） | — |

并行三路的分工（三路各写不同新文件，无文件冲突）：

| 路 | 文件（并行编写中） | 职责 | 与本任务的关系 |
|---|---|---|---|
| P6A | `pruner.zig` | `prune`：按 Phase 5 报告的 `prunable` 产出全新的 `PrunedGraph`（只含保留内容；原图不动） | `eliminate` 第 2 步调用；`PrunedGraph` / `RemovedSymbol` 的正本（见 §5 C1） |
| P6B | `guard.zig` | `verifyPruned`：校验裁剪后图（可达的都在、该删的都删了、无悬空边），返回 `[]DceViolation`（空 = 通过） | `eliminate` 第 3 步调用；`DceViolationKind` / `DceViolation` 的正本（见 §5 C4） |
| P6C（本任务） | `eliminate.zig` | DCE 类型、集成入口与报告：只接线、只报告 | 产出供调用方消费的 `DceResult` 与文本摘要 |
| P6C（本任务） | `MANIFEST.md` | 本清单（起草；§5 由协调 agent 定稿） | — |

facade 已写（`src/dce.zig`）：薄 re-export 25 个公开名（见 §5 C5）。

不设独立的 `types.zig`：本模块不定义新的共享类型层——`ModuleId` /
`SymbolNode` / `SymbolKind` / `SymbolGraph` / `ModuleGraph` /
`RetainSet` 复用 Phase 4 的 `src/dependency_graph/`（经
`symbol_graph.zig` / `module_graph.zig` / `retention.zig` 的
re-export 形状）；`PruneReason` / `ReachabilityReport` 复用 Phase 5
的 `src/reachability/report.zig`。本文件新增的类型只在 DCE 内有意义
（`RemovedSymbol` / `PrunedGraph` / `DceViolationKind` /
`DceViolation` / `DceOutcome` / `DceResult`）。

## 3. API 表

### 3.1 本文件新增（`eliminate.zig`）

| 名字 | 用途 |
|---|---|
| `RemovedSymbol` | 一个被删除的符号：`node: SymbolNode`（值拷贝，字符串仍借用） / `kind: SymbolKind`（图登记的 kind） / `reason: PruneReason`（Phase 5 的两档） |
| `PrunedGraph` | 裁剪后的图：`allocator` / `symbols: SymbolGraph`（新建，只含保留内容） / `modules: ModuleGraph`（新建） / `removed_symbols: []RemovedSymbol` / `removed_edges: usize`（删除的符号引用边数） / `removed_modules: []ModuleId`（整模块被删的模块）；`deinit` 只释容器与 owned 切片（长度为 0 的切片不释放，与 P5B `Convergence.deinit` 同款口径） |
| `DceViolationKind` | 校验违规的种类（七档）：`reachable_missing`（可达符号缺失） / `prunable_survived`（可裁剪符号仍存活） / `dangling_edge`（悬空边） / `pruned_module_survived`（已裁剪模块仍存活） / `retained_missing`（保留集符号缺失） / `unknown_pruned`（被删清单里出现未知符号） / `count_mismatch`（计数不一致） |
| `DceViolation` | 一条校验违规：`kind: DceViolationKind` / `node: ?SymbolNode`（无相关节点时为 null） / `detail: []const u8`（借用串，`deinit` 不释放） |
| `DceOutcome` | `eliminate` 的结果状态（三态）：`pruned`（校验通过，且删掉了东西） / `nothing_to_prune`（校验通过，但 prunable 为空；仍产出 `PrunedGraph`） / `verification_failed`（校验失败；仍保留 `PrunedGraph` 与违规列表供诊断） |
| `DceResult` | `eliminate` 的结果：`outcome: DceOutcome` / `pruned: ?PrunedGraph`（三态下均为非 null） / `violations: []DceViolation`（通过时为空切片） / `report: ReachabilityReport`；`deinit` 统一释放三者（调用方只调一次，不得再单独释放其中的 `report` 或 `pruned`） |
| `eliminate` | `eliminate(module_graph, symbol_graph, retain, entry_module, allocator) std.mem.Allocator.Error!DceResult`：Phase 6 集成入口，见 §5 接线顺序 |
| `summarizeDce` | `summarizeDce(result, allocator) std.mem.Allocator.Error![]u8`：人类可读文本摘要（总定义数、可达数、删除数按 kind 五档与 reason 两档拆分、删除边数、删除模块数、保留模块数、module_only 模块列表、outcome 一行；不逐个列出被删符号，无 JSON 输出） |

### 3.2 P6A / P6B 的调用形状（已合并，以落盘为准，见 §5 C2 / C3）

| 方法 | 约定形状 | 用途 |
|---|---|---|
| `prune` | `prune(symbol_graph, module_graph, report, allocator) !PrunedGraph` | P6A 裁剪：输入原两张图与 Phase 5 报告，返回全新的裁剪后图；错误集为 `Allocator.Error`（只报分配失败） |
| `verifyPruned` | `verifyPruned(symbol_graph, module_graph, pruned, report, retain, allocator) ![]DceViolation` | P6B 校验：输入原两张图、裁剪后图、Phase 5 报告与保留集，返回违规列表（空 = 通过）；校验发现的问题记进返回的列表，不以 error 形式报出；错误集为 `Allocator.Error`。落盘比 P6C 假设多一个 `retain` 参数（校验不变量 4 需读保留集），`eliminate` 调用点已按落盘补齐（C3） |

### 3.3 复用（不重定义）

| 名字 | 来源 | 用途 |
|---|---|---|
| `ModuleId` / `SymbolNode` / `SymbolKind` / `SymbolGraph` | `../dependency_graph/symbol_graph.zig`（复用） | Phase 4 符号图层，不重定义 |
| `ModuleGraph` | `../dependency_graph/module_graph.zig`（复用） | Phase 4 模块图层，不重定义 |
| `RetainRule` / `RetainSet` | `../dependency_graph/retention.zig`（复用） | Phase 4 保留规则登记集，不重定义 |
| `PruneReason` / `PruneCandidate` / `ReachabilityReport` / `analyzeAll` | `../reachability/report.zig`（复用） | Phase 5 报告与集成入口，不重定义 |

## 4. 与 Phase 2 / Phase 3 / Phase 4 / Phase 5 的关系表

| Phase | 产出 | 本任务的用法 | 备注 |
|---|---|---|---|
| Phase 2（types） | `ModuleId` / `ModuleState` / `ImportKind` / `SymbolEdge` | 经 Phase 4 re-export 复用，不重定义 | `SymbolNode` 的身份仍是 (module, name) |
| Phase 2（closure） | `CycleRecord`、`ClosureBuilder.edges`（不去重） | 不直接调用 | 边由 loader 产出、Phase 4 图整理，本任务只消费已建好的图与 Phase 5 报告 |
| Phase 3（loader） | `LazyLoader.edges` / `cycles` / `order`、`stateOf(id)`、`markAnalyzed` | 不直接调用 | 图的边源；本任务只读已建好的图，不推进状态机 |
| Phase 3（cycle） | `CyclePolicy` / `detectCycle` / `checkCycle` | 不调用 | 环的检测与合法性判定仍在 cycle.zig；裁剪只拿掉不可达节点，不改环语义 |
| Phase 3（wiring） | `ModuleTable.stateOf` / `markAnalyzed` | 不调用 | 只读使用关系已在 Phase 4 终结，本任务不改 flattener 接线 |
| Phase 4（types） | `SymbolKind` / `SymbolNode` / `ModuleEdge` / `GraphError` | 复用，不重定义 | `SymbolNode.key` / `moduleRoot` / `isModuleRoot` 见 types.zig |
| Phase 4（module_graph） | `ModuleGraph`（`reachableFrom` / `contains` / `stateOf` 等） | `eliminate` 只把它传给 `analyzeAll` / `prune` / `verifyPruned`；本文件不直接调它的查询方法 | 模块级可达性由 P5B 的 `converge` 定，本文件不二次计算；两张图均无 remove API（append-only），裁剪产新图 |
| Phase 4（symbol_graph） | `SymbolGraph`（`nodes` / `edges` / `module_deps`；`nodeCount` / `definedSymbols` / `referencedSymbols` / `moduleDependencies`） | `eliminate` 只把它传给 `analyzeAll` / `prune` / `verifyPruned`；本文件不直接读它的 `nodes` / `edges` | 本文件只接线，不直接读图、不改图 |
| Phase 4（retention） | `RetainSet`（`retainedNodes` / `rulesFor` / `isRetained`；`retainMain` / `retainGlobalInits`） | `eliminate` 的 `retain` 入参（`*RetainSet`，`analyzeAll` 经 `computeRoots` 会改它）；`ReachReason.retained` 的 `RetainRuleSet` 即登记集的规则 | 宏展开 / 反射 / 动态调用 / 导出的判定逻辑今天没有（`rule_notes` 只登记文本），本文件不发明判定逻辑 |
| Phase 4（builder） | `GraphBuilder`（边整理：去重 / 分流 / 透传） | 不直接调用 | 边的整理已在 Phase 4 做完，本任务只消费已建好的图 |
| Phase 5（analyzer） | `ReachabilityAnalyzer` / `ReachabilityResult` / `ReachReason` | 不直接调用 | 已包在 `analyzeAll` 里；本文件只消费 `analyzeAll` 的报告 |
| Phase 5（roots） | `RootEntry` / `computeRoots` | 不直接调用 | 已包在 `analyzeAll` 第 1 步里（会修改 `RetainSet`，先 `retainMain` 再 `retainGlobalInits`） |
| Phase 5（converge） | `Convergence` / `ConvergedDep` / `converge` | 不直接调用 | 已包在 `analyzeAll` 第 4 步里；结果原样带入报告，`summarizeDce` 读它的 `reachable_modules`（保留模块数）与 `module_only_modules`（module_only 列表） |
| Phase 5（report） | `ReachabilityReport` / `PruneReason` / `PruneCandidate` / `buildReport` / `summarize` / `analyzeAll` | `eliminate` 第 1 步调 `analyzeAll`；`DceResult.report` 即该报告；`RemovedSymbol.reason` 复用 `PruneReason` 两档；outcome 判定读 `report.prunable.len` | 本文件只做分析结果的消费与接线，不做可达性分析本身 |

导入语义（提案 §7，用户已定第三种）：符号级与模块级都支持，底层统一
落成 `SymbolEdge`；模块级导入没有对应的 `SymbolNode`，具体用到哪些
符号由可达性分析再收敛——`summarizeDce` 的 module_only 模块列表（P5B
的 `Convergence.module_only_modules`）即只被模块级导入触及的模块集合，
其符号的后续引用发现策略见 §7.1 Phase 5 RESULT §6 第 3 项（待裁决）。

`eliminate` 接线顺序（五步，缺一不可，顺序固定）：

| 步 | 调用 | 输入 → 输出 | 说明 |
|---|---|---|---|
| 1 | `analyzeAll(module_graph, symbol_graph, retain, entry_module, allocator)` | 两张图 + 保留集 + 入口模块 → `ReachabilityReport` | Phase 5 可达性分析。**会修改 `retain`**（先 `retainMain` 再 `retainGlobalInits`）；调用方须传入可写的登记集 |
| 2 | `prune(symbol_graph, module_graph, &report, allocator)` | 原两张图 + 报告 → `PrunedGraph` | P6A 裁剪：产出全新的图（原图不动） |
| 3 | `verifyPruned(symbol_graph, module_graph, &pruned, &report, allocator)` | 原两张图 + 裁剪后图 + 报告 → `[]DceViolation` | P6B 校验：违规列表（空 = 通过）；问题记进列表，不以 error 报出 |
| 4 | 定 outcome | 违规列表 + `report.prunable` → `DceOutcome` | 优先级：违规非空 → `.verification_failed`；否则 prunable 为空 → `.nothing_to_prune`（仍产出 `PrunedGraph`）；否则 → `.pruned` |
| 5 | 返回 `DceResult` | report / pruned / violations → `DceResult` | `DceResult` 拥有三者，`deinit` 统一释放 |

只做裁剪的接线与报告，不直接建新图、不删符号、不判定任何保留规则
（裁剪实现是 P6A 的事，校验实现是 P6B 的事）。中间产物（`report` /
`pruned` / `violations`）的所有权随第 5 步转移给 `DceResult`；中间
步骤报分配失败时，已得的中间产物由 `eliminate` 的 errdefer 清理，
不留半成品 `DceResult`。

## 5. 合并对齐（协调 agent 定稿）

三路并行编写，各写不同新文件，无文件冲突；facade 与本节由协调 agent
合并时定稿。以下对齐点均已按 P6A / P6B / P6C 的落盘定稿：

| # | 出入 | 状态 |
|---|---|---|
| C1 | `PrunedGraph` / `RemovedSymbol` 的正本在 `pruner.zig`（P6A 产出）；`guard.zig` 与 `eliminate.zig` 的本地声明改为 re-export。三处落盘字段逐字一致（6 字段同序），`deinit` 口径一致（只释 owned 切片与子图容器，长度为 0 的切片不释放） | 已定稿 |
| C2 | `prune` 的形状与约定一致，无改动：`prune(symbol_graph, module_graph, report, allocator) !PrunedGraph` | 已定稿 |
| C3 | `verifyPruned` 落盘比 P6C 假设多一个 `retain` 参数（P6B 任务书原有，P6C 写调用点时遗漏）；`eliminate` 调用点已按落盘补齐 `retain`。`violations` 切片同一分配器、`detail` 为借用串——P6B 落盘与约定一致（`detail` 均为静态字面量），`DceResult.deinit` 不改 | 已定稿 |
| C4 | `DceViolationKind` / `DceViolation` 的正本在 `guard.zig`（P6B 产出）；`eliminate.zig` 的本地声明改为 re-export。两处 7 变体同名同序；`unknown_pruned` 的注释表述略有出入，以 `guard.zig`（与 7 条不变量一一映射）为准 | 已定稿 |
| C5 | facade 已写 `src/dce.zig`，薄 re-export 25 个公开名：`RemovedSymbol` / `PrunedGraph` / `prune`（P6A）；`DceViolationKind` / `DceViolation` / `DceStats` / `verifyPruned` / `countStats`（P6B）；`DceOutcome` / `DceResult` / `eliminate` / `summarizeDce`（P6C）；复用 Phase 4 / Phase 5 类型 13 个 | 已定稿 |
| C6 | `build.zig` 注册：`dce`（与 Phase 2 的 `module_resolver`、Phase 3 的 `module_loader`、Phase 4 的 `dependency_graph`、Phase 5 的 `reachability` 同样）未接 build；注册是后续 Phase / 协调方的事 | 已定稿 |

## 6. 已知缺口（只记，不擅自改结构）

| # | 项 | 状态 |
|---|---|---|
| 1 | `SymbolGraph` / `ModuleGraph` 均无 remove / delete API（append-only）：裁剪只能产出全新的 `PrunedGraph`，不能在原图上删东西；原图在 `eliminate` 全程只读 | 已定（Phase 4 落盘事实） |
| 2 | `prune` / `verifyPruned` 的调用形状已按落盘对齐（`verifyPruned` 补 `retain` 参数，见 §5 C3），但未经编译验证（只跑 `zig ast-check`，parse-only，不解析 import） | 已对齐，未编译验证 |
| 3 | `PrunedGraph` / `RemovedSymbol` / `DceViolationKind` / `DceViolation` 的正本落点已定：`PrunedGraph` / `RemovedSymbol` 在 `pruner.zig`，`DceViolationKind` / `DceViolation` 在 `guard.zig`；其余文件只转发 | 已定稿（§5 C1 / C4） |
| 4 | `DceResult.deinit` 释放 `violations` 切片用 `report.allocator`：约定 `verifyPruned` 须用与 `eliminate` 同一个分配器分配该切片；`detail` 为借用串，`deinit` 不释放 | 约定，待 §5 C3 确认 |
| 5 | outcome 判定优先级：违规非空一律 `.verification_failed`，压倒“无事可删”；违规为空且 prunable 为空才是 `.nothing_to_prune`（见 `eliminate.zig` 文件头） | 已定（本任务契约） |
| 6 | `PruneReason` 两档下的不一致情形无处可记（Phase 5 MANIFEST §7.5 第 5 项，见 §7.1 第 4 项）：某条入边来自可达符号、节点本身却不可达时，仍归入 `referenced_only_by_unreachable`；是否要第三档或单独的诊断通道，待裁决 | 待裁决 |
| 7 | 保留规则判定逻辑仍缺：`macro_expanded` / `reflective` / `dynamic_call` / `exported` 四条规则只登记文本（`retention.zig` 的 `rule_notes`），判定需解析器 / 后端能力（宏展开表、反射元数据、动态分发表、导出表），今天没有；本文件不发明判定逻辑 | 只记 |
| 8 | `summarizeDce` 只产纯文本，无结构化（JSON）输出；不逐个列出被删符号（要看明细读 `result.pruned.?.removed_symbols`） | 只记（见 §7.1 第 5 项） |
| 9 | facade（`src/dce.zig`）已写；`build.zig` 未注册 `dce` | facade 已定稿（§5 C5）；注册待后续（§5 C6） |
| 10 | 钩子均为空实现（Phase 3 遗留）：parse / type-check / analyze 未接任何解析器，`markAnalyzed` 只推进状态；`filterByState` 的 `ready` 只看状态机位置，不保证语义分析真正完成——可达性分析消费的边若来自未真正分析完的模块，其完备性不受本文件保证 | 只记 |

## 7. 待裁决（原样登记，不做定夺）

以下各期条目**按原文引用出处，不全文照抄**：每项只记短标题与精确
出处（文件 + 章节 + 项号），原文以出处文件为准。本任务不做任何定夺。

> 计数说明：任务书称 Phase 5 RESULT §6 为“8 项”；原文
> `~/workspace/sci2-opt-std/phase5/RESULT.md` §6 实际为 9 条编号
> （第 1–6 条为 Phase 5 自身的待裁决项，第 7 条为 Phase 4 的 12 项
> 的合订指针，第 8 条为 Phase 3 / Phase 2 / Phase 1 的合订指针，
> 第 9 条为 `build.zig` 注册）。本清单 §7.1 照原文 9 条编号登记，
> 第 7、8 条的展开见 §7.2–§7.5；计数差异如实记下，由协调 agent 核对。

### 7.1 Phase 5 RESULT §6 的 9 条（原文编号）

出处：`~/workspace/sci2-opt-std/phase5/RESULT.md` §6（待裁决 /
跟进项），另见 `src/reachability/MANIFEST.md` §7.5、§8。

| # | 项（短标题） | 状态 |
|---|---|---|
| 1 | M2 跟进项：`converge` 收敛状态的符号级收紧——后续若调用方能传入可达符号集（而非仅可达模块列表），状态可再精确到符号；目前为模块粒度 | 未决 |
| 2 | M3 跟进项：索引缓存的删边假设——`SymbolGraph` 目前无删边 / 改边 API，假设成立；若将来图支持删边，改图后须调 `invalidateIndex`，否则 `analyze` 可能用旧索引 | 未决 |
| 3 | module_only 模块的符号后续引用发现策略（MANIFEST §7.5 第 3 项）：module_only 模块只有模块级导入、无符号级边；其符号若在分析后被新发现引用，是由 Phase 5 内二次扫描发现，还是留给 Phase 6 裁剪时按需展开 | 待裁决 |
| 4 | `PruneReason` 是否需要第三档（MANIFEST §7.5 第 5 项）：某条入边来自可达符号、节点本身却不可达的不一致情形，目前仍归入 `referenced_only_by_unreachable`；是否要第三档或单独的诊断通道 | 待裁决 |
| 5 | 是否需要结构化（JSON）报告输出（MANIFEST §7.5 第 7 项）：`summarize` 目前只产纯文本 | 待定 |
| 6 | 保留规则判定逻辑仍缺（MANIFEST §7.5 第 6 项）：`macro_expanded` / `reflective` / `dynamic_call` / `exported` 四条规则只登记文本，判定需解析器 / 后端能力（宏展开表、反射元数据、动态分发表、导出表），今天没有；本阶段不发明判定逻辑 | 只记 |
| 7 | Phase 4 的 12 项待裁决 / 跟进项（Phase 4 RESULT §6；MANIFEST §7.1 按原文出处登记，未做定夺） | 原样登记，展开见 §7.2 |
| 8 | Phase 3 的 7 项（Phase 3 RESULT §6；MANIFEST §7.2），Phase 2 的 10 项（Phase 2 RESULT §6；MANIFEST §7.3），Phase 1 的 8 项（MANIFEST §7.4）——原样登记，未做定夺 | 原样登记，展开见 §7.3–§7.5 |
| 9 | `build.zig` 注册：`reachability`（与 Phase 2/3/4 同样）未接 build；注册是后续 Phase / 协调方的事 | 后续 Phase / 协调方的事 |

### 7.2 Phase 4 RESULT §6 的 12 项

出处：`/content/kit-work/sci2-opt-std/phase4/RESULT.md` §6（待裁决 /
跟进项），另见 `src/dependency_graph/MANIFEST.md` §7–§8、§10；
短标题转录自 `src/reachability/MANIFEST.md` §7.1。

| # | 项（短标题） | 状态 |
|---|---|---|
| 1 | `GraphError` 统一（A3） | 未决，后续接线 Phase 定 |
| 2 | `ModuleDep` 与 `ModuleEdge` 是否合一（A4） | 未决，后续接线 Phase 定 |
| 3 | 同一 `(from, to)` 上符号级边与模块级边并存，图层是否需记录“两种粒度都出现过” | 未决，待 P4A 定稿时明确 |
| 4 | `pending` 模块的重跑策略（调用方重跑构建器，还是图层增量接纳） | 未决，后续接线 Phase 明确 |
| 5 | `StateFn` 适配器的最终落点（M1 / M2） | 未决，后续步骤写适配器 |
| 6 | spec.zig 两处 `.both => error.AmbiguousImport` 改为 `.symbol`（P3B 裁决 file_first 的接线） | 跟进项，未接线 |
| 7 | `injectimportedfile.zig:484` 的旧签名调用点迁移到表核心，之后删除 `expandImportsInto` 旧签名适配器（M4） | 跟进项 |
| 8 | 版本 `@` 后缀与操作符是否采纳为正式语法（Phase 2 待裁决 #6） | 未决 |
| 9 | `extractImportStrings` 不带行号（Phase 2 待裁决 #8；环诊断暂用入口路径 + 行号 0） | 未决 |
| 10 | `reachableFrom` 起点自身状态不设门、`topoSort` 遇多环时环下游非环节点只通过“未出队”隐含、`addEdge` 自动补建缺失端点为 `.unloaded`——三处语义若调用方希望改严格，需单独一步 | 只记 |
| 11 | Phase 1 的 8 项待裁决（见 §7.5） | 原样登记，未做定夺 |
| 12 | `build.zig` 注册（`dependency_graph` 与 Phase 2/3 同样未接 build） | 后续 Phase / 协调方的事 |

### 7.3 Phase 3 RESULT §6 的 7 项

出处：`/content/kit-work/sci2-opt-std/phase3/RESULT.md` §6（待裁决 /
跟进项），另见 `src/module_loader/MANIFEST.md` §8、§10；
短标题转录自 `src/reachability/MANIFEST.md` §7.2。

| # | 项（短标题） | 状态 |
|---|---|---|
| 1 | spec.zig 两处 `.both => error.AmbiguousImport` 改为 `.symbol`（P3B 裁决 file_first 的接线，policy.zig 文件头已有指引） | 跟进项，未接线 |
| 2 | `LoaderState`↔`LazyLoader` 适配器（M1）；`ModuleTable`↔`LazyLoader` 统一（M2）；loader 走 `locateRelative`（M5） | 未决，后续接线 Phase 的事 |
| 3 | `injectimportedfile.zig:484` 的旧签名调用点迁移到表核心，之后删除 `expandImportsInto` 旧签名适配器（M4） | 跟进项 |
| 4 | 版本 `@` 后缀与操作符是否采纳为正式语法（Phase 2 待裁决 #6） | 未决 |
| 5 | `extractImportStrings` 不带行号（Phase 2 待裁决 #8；环诊断暂用入口路径 + 行号 0） | 未决 |
| 6 | Phase 1 的 8 项待裁决（见 §7.5） | 原样登记，未做定夺 |
| 7 | 盒子主机名现为 `bd4991109185`，与任务所述一致，不影响工作 | 只记 |

### 7.4 Phase 2 RESULT §6 的 10 项

出处：`/content/kit-work/sci2-opt-std/phase2/RESULT.md` §6（待裁决 /
判断类问题），另见 `src/module_resolver/MANIFEST.md` §8；
短标题转录自 `src/reachability/MANIFEST.md` §7.3。

| # | 项（短标题） | 状态 |
|---|---|---|
| 1 | 消歧规则：真实歧义（`sa_std/io`、`sa_std/fmt`、`sa_std/io/print` 等）优先文件还是优先 prelude | Phase 3 已裁决：优先文件（policy.zig）；spec.zig 的 `.both` 分支改动未接线，见 §7.3 第 1 项 |
| 2 | 斜杠 / 点分同形不同义是否统一 | Phase 3 已裁决：不统一，各走各的（policy.zig） |
| 3 | 相对导入的基准目录：给 `Locator` 加 `locateRelative(spec, base_dir)`，还是由调用方预先解析成包限定形式 | Phase 3 已实现 `locateRelative`（P3C）；loader 侧接线为跟进项（M5） |
| 4 | 中间层 shim（`collections/<name>.sa` 等 6 处）：Phase 3 是否扩展 shim 搜索层级 | Phase 3 已裁决：不扩展（P3C 实测） |
| 5 | `sa_std/<name>` 且 `<name>` 非域名时（如 `sa_std/vec.sa`）是否试顶层 shim | Phase 3 已裁决：先试顶层 shim（按现状口径，P3C） |
| 6 | 版本 `@` 后缀与操作符是否采纳为正式语法 | 未决 |
| 7 | 未知扩展名（如 `.txt`）不判 symbol、落到探针 / 默认分支的口径是否合适 | Phase 3 已确认合适（policy.zig） |
| 8 | `extractImportStrings` 不带行号 | 未决；行号支持需改返回形态，留待后续 |
| 9 | Phase 1 的 8 项待裁决（见 §7.5） | 原样登记，未做定夺 |
| 10 | 盒子主机名（先前记录的 `bd00ae7b9304` 已变，疑似换机） | 只记，不影响工作 |

### 7.5 Phase 1 的 8 项

出处：`src/module_resolver/MANIFEST.md` §6（转录自 Phase 1 RESULT §6），
照现状、不由本任务定；短标题转录自 `src/reachability/MANIFEST.md` §7.4。

| # | 项（短标题） | 状态 |
|---|---|---|
| 1 | `jwt.sla` 归属：现放 `db/core/`，本质是 crypto 应用，候选 `crypto/` | 未决 |
| 2 | `compress` 归属：现放 `crypto/encoding/`，候选 `encoding/` 域 | 未决 |
| 3 | `crypto.sai` 拆分（哈希 / 随机数 / 口令等六类）与 `redis.sla` 的 RESP 编解码 / TCP 客户端拆分 | 未决 |
| 4 | 是否把 `db/crypto/testing/tree_sitter` 的 prelude 纳入顶层 `sa_std/prelude.sa`（F 报告待定项；Phase 1 未纳入） | 未决 |
| 5 | F 域“其他”文件：`oop.sal`→建议 core、`sse.sla`→建议 http、`ctx.sla`→建议 task，均保留顶层原位未移动；`dtls` 只记不碰 | 未决 |
| 6 | `core/future/`（future/task/waker）是否抽出到 task 域（A 报告未定） | 未决 |
| 7 | `.sai` shim 机制：全仓零个 `.sai` 文件含 `@import`，.sai shim 未经验证；E 的 13 个 `.sai` 无 shim 是本次唯一 breaking change | 只记 |
| 8 | E 的缺陷 D1：`net/socket/net.sal` 里 `SA_NET_ERR_ACCESS` 与 `SA_NET_ERR_TIMEOUT` 同值 4（疑似真 bug，只记未修） | 只记未修 |

（另见 Phase 1 RESULT §6：core → sync 11 边、core → collections 2 边为
已知既存层级倒置，Phase 1 未修；`core/sa_core.sa` 第 36–37 行重复
import `../sync/rwlock.sal` 两次。）

## 8. 未做的事（按任务硬约束，另行安排）

- **无构建/测试结果可报**：未跑 `zig build`、未跑 `zig test`、未跑任何测试。只跑 `zig ast-check`（parse-only 静态检查）、`@import` 相对路径 grep 核对与行数核对。
- 未修任何 bug：包括 Phase 1 的构建断裂、sci 7ecae6d 的 double-free、任务 79 报告的 6 项基线缺陷、Phase 1/2/3/4/5 的待裁决项。
- 未改任何现有文件（只新增 `src/dce/` 下的 2 个文件：`eliminate.zig` 与本清单）；未动 `sa_std/`、`tests/`、`build.zig`；未合 main；未动 `/content/sa_all/sci` 原仓；未提交。
- 未接线：`eliminate` 的接线只定义调用顺序与契约，未接入任何真实调用方；facade（`src/dce.zig`）与 `build.zig` 注册由协调合并时 / 后续 Phase 接线。
- 未实现裁剪与校验：`prune`（P6A）与 `verifyPruned`（P6B）在各自副本中并行编写，不在本副本；本文件的调用点按任务契约写，调用形状以落盘为准（见 §5 C2 / C3）。
- 未裁剪、未删除任何东西：本文件只接线与报告；实际的裁剪删除发生在 P6A 的 `prune` 产出的新图里，原图全程只读。
