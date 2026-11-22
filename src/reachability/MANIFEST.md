# sa-reachability — 模块清单（Std 模块化 Phase 5，P5C：可达性报告与集成入口，起草）

> 提案：`~/workspace/goals/sci-sa-optimize/files/STD-MODULARIZATION-PROPOSAL.md`
> （§2 懒加载流程与四种模块状态、§3 两层依赖图与 Reachability-based DCE、
> §4 三个独立模块与建议管线、§7 第三种导入语义）。
> Phase 4 结果：盒上 `src/dependency_graph/`（types / module_graph /
> symbol_graph / retention / builder）与 `src/dependency_graph/MANIFEST.md`；
> Phase 4 RESULT（本机 `~/workspace/sci2-opt-std/phase4/RESULT.md`，重点 §6
> 待裁决 / 跟进项 12 项）。
> 工作仓：盒上 `/content/kit-work/sci2`（分支 `sa-optimize`，
> 基线 `bd353058`，Phase 4 终推）；三路 agent 副本在
> `/content/kit-work/sci2-agentP5A/B/C`。本阶段只新增 `src/reachability/`
> 下 4 个 .zig 文件与本清单，不改任何现有文件，不合 main。
>
> **本文为合并后定稿**：协调 agent 已合并 P5A / P5B / P5C 三路工作；
> §3、§4、§5 已按落盘 API 核对；§6 合并对齐（M1–M6）与 facade 清单
> 由协调 agent 合并时写。本清单的契约部分以本定稿为准。

## 1. 模块目的

`sa-reachability` 是提案 §4 三个独立模块之三（Phase 5，可达性分析），
独立于 Lexer、Referee、Backend。

它承接 Phase 4 两层依赖图的产出（`SymbolGraph` / `ModuleGraph` /
`RetainSet`），产出提案 §3 的 Reachability-based DCE 的输入：哪些符号
可达、哪些符号是可裁剪候选、按模块的统计、模块级收敛结果。

它**不是**加载器（Phase 3）、**不是**依赖图本身（Phase 4）、**不是**
DCE 执行（Phase 6）。它只做分析结果的整理与接线：不删除、不裁剪
任何东西，不判定任何保留规则（保留规则的判定能力缺口见 §4 关系表
与 §7.5）。

建议管线中的位置（提案 §4）：

```
Source → Module Resolver → Lazy Loader → Parser → Name Resolution
  → Dependency Graph（Phase 4）
  → Semantic Analysis → Flattener → SA IR → Referee
  → Reachability Analysis（本模块：P5A 分析 → P5B 根与收敛 → P5C 报告与入口）
  → WASM / LLVM / JS
```

## 2. 文件分工

| 文件 | 职责 | 行数 |
|---|---|---|
| `src/reachability/analyzer.zig` | `ReachabilityAnalyzer` / `ReachabilityResult` / `ReachReason`：带 reason 的 BFS 闭包（邻接索引一次建成） | 280 |
| `src/reachability/roots.zig` | `RootEntry` / `computeRoots`：算根（会修改 `RetainSet`，先 `retainMain` 再 `retainGlobalInits`） | 112 |
| `src/reachability/converge.zig` | `Convergence` / `ConvergedDep` / `converge`：模块级收敛 | 314 |
| `src/reachability/report.zig` | `ReachabilityReport`：可达符号、可裁剪候选、统计、文本摘要；`analyzeAll`：Phase 5 集成入口 | 428 |
| `src/reachability/MANIFEST.md` | 本清单（合并后定稿） | 258 |

并行三路的分工（三路均已落盘，协调合并时已核对）：

| 路 | 文件（并行编写中） | 职责 | 与本任务的关系 |
|---|---|---|---|
| P5A | `analyzer.zig` | `ReachabilityAnalyzer`：从根出发沿已记录边遍历，得 `ReachabilityResult` | 本任务消费其 `analyze` 结果（`reachable` / `order` / `isReachable` / `reasonFor` / `count` / `reachableNodes` / `reachableModules`） |
| P5B | `roots.zig` | `RootEntry` / `computeRoots`：算根（会修改 `RetainSet`，先 `retainMain` 再 `retainGlobalInits`） | `analyzeAll` 第 1 步调用 |
| P5B | `converge.zig` | `Convergence` / `converge`：模块级收敛（`reachable_modules` / `converged_deps` / `module_only_modules`） | `analyzeAll` 第 4 步调用；结果原样带入报告，不二次计算 |
| P5C（本任务） | `report.zig` | 报告与集成入口：只整理、只接线 | 产出供 Phase 6 消费的 `ReachabilityReport` 与文本摘要 |

不设独立的 `types.zig`：本模块不定义新共享类型——`ModuleId` /
`SymbolNode` / `SymbolKind` / `SymbolGraph` / `ModuleGraph` /
`RetainSet` 复用 Phase 4 的 `src/dependency_graph/`（经
`symbol_graph.zig` / `module_graph.zig` / `retention.zig` 的
re-export 形状）；本文件唯一新增的类型是 `PruneReason` /
`PruneCandidate` / `ModuleStats` / `ReachStats` /
`ReachabilityReport`，五者都只在本模块内有意义。

不写 facade（`src/reachability.zig`）：协调合并时写（见 §6）。

## 3. 公开 API 表

### 3.1 本文件新增（`report.zig`）

| 名字 | 用途 |
|---|---|
| `PruneReason` | 候选被裁剪的原因：`not_referenced`（图中没有任何边指向它） / `referenced_only_by_unreachable`（指向它的边全部来自不可达符号） |
| `PruneCandidate` | 一个可裁剪候选：`node: SymbolNode` / `kind: SymbolKind`（图登记的 kind） / `reason: PruneReason` |
| `ModuleStats` | 一个模块的统计：`module: ModuleId` / `defined` / `reachable` / `prunable` |
| `ReachStats` | 全图统计：`total_defined` / `reachable_count` / `prunable_count` / `modules: []ModuleStats`（按 module 字典序排过） |
| `ReachabilityReport` | 报告：`reachable: []SymbolNode`（发现顺序） / `prunable: []PruneCandidate`（全部已定义但不可达的符号） / `stats: ReachStats` / `convergence: Convergence`（原样带入）；`deinit` 只释容器与 owned 切片 |
| `buildReport` | `buildReport(graph, result, convergence, allocator) !ReachabilityReport`：从 P5A 结果建报告 |
| `summarize` | `summarize(report, allocator) ![]u8`：人类可读文本摘要（总数、可达数、可裁剪数附两档拆分、按模块分表、module_only 模块列表） |
| `analyzeAll` | `analyzeAll(module_graph, symbol_graph, retain, entry_module, allocator) !ReachabilityReport`：Phase 5 集成入口，见 §5 |

### 3.2 复用（不重定义）

| 名字 | 来源 | 用途 |
|---|---|---|
| `ModuleId` / `SymbolNode` / `SymbolKind` / `SymbolRefEdge` / `ModuleDep` / `RefKind` / `SymbolGraph` | `../dependency_graph/symbol_graph.zig`（复用） | Phase 4 符号图层，不重定义 |
| `ModuleGraph` | `../dependency_graph/module_graph.zig`（复用） | Phase 4 模块图层，不重定义 |
| `RetainRule` / `RetainRuleSet` / `RetainSet` | `../dependency_graph/retention.zig`（复用） | Phase 4 保留规则登记集，不重定义 |
| `ReachabilityAnalyzer` / `ReachabilityResult` / `ReachReason` | `analyzer.zig`（P5A，并行编写中） | P5A 的分析器与结果；`ReachReason = union(enum) { retained: RetainRuleSet, reached_via: SymbolRefEdge }` |
| `RootEntry` | `roots.zig`（P5B，并行编写中） | P5B 的根条目：`node: SymbolNode` / `rules: RetainRuleSet` |
| `Convergence` / `ConvergedDep` / `ConvergedStatus` | `converge.zig`（P5B，并行编写中） | P5B 的收敛结果与已收敛依赖 |

### 3.3 本文件引用的 P5A / P5B 方法（合并时已按落盘核对）

| 方法 | 约定形状 | 用途 |
|---|---|---|
| `computeRoots` | `computeRoots(graph, retain_set, entry_module, allocator) ![]RootEntry` | 算根；会修改传入的 `RetainSet`（先 `retainMain` 再 `retainGlobalInits`） |
| `ReachabilityAnalyzer.init` / `analyze` / `deinit` | `init(allocator)` 构造；`analyze(graph, roots) !ReachabilityResult`；`deinit()` 释放 | P5A 可达性分析 |
| `ReachabilityResult.reachableNodes` / `reachableModules` | `(allocator) ![]SymbolNode` / `(allocator) ![]ModuleId` | 取可达符号（发现顺序）/ 可达模块 |
| `ReachabilityResult.isReachable` / `reasonFor` / `count` | 判定 / 取原因 / 计数 | 报告建表时逐个判定可达性 |
| `converge` | `converge(symbol_graph, module_graph, reachable_modules, allocator) !Convergence`（自由函数） | P5B 模块收敛 |

## 4. 与 Phase 2 / Phase 3 / Phase 4 的关系表

| Phase | 产出 | 本任务的用法 | 备注 |
|---|---|---|---|
| Phase 2（types） | `ModuleId` / `ModuleState` / `ImportKind` / `SymbolEdge` | 经 Phase 4 re-export 复用，不重定义 | `SymbolNode` 的身份仍是 (module, name) |
| Phase 2（closure） | `CycleRecord`、`ClosureBuilder.edges`（不去重） | 不直接调用 | 边由 loader 产出、Phase 4 图整理，本任务只消费已建好的图 |
| Phase 3（loader） | `LazyLoader.edges` / `cycles` / `order`、`stateOf(id)`、`markAnalyzed` | 不直接调用 | 图的边源；本任务只读已建好的图，不推进状态机 |
| Phase 3（cycle） | `CyclePolicy` / `detectCycle` / `checkCycle` | 不调用 | 环的检测与合法性判定仍在 cycle.zig；可达性遍历只走已记录的边 |
| Phase 3（wiring） | `ModuleTable.stateOf` / `markAnalyzed` | 不调用 | 只读使用关系已在 Phase 4 终结，本任务不改 flattener 接线（M2） |
| Phase 4（types） | `SymbolKind` / `SymbolNode` / `ModuleEdge` / `GraphError` | 复用，不重定义 | `SymbolNode.key` / `moduleRoot` / `isModuleRoot` 见 types.zig |
| Phase 4（module_graph） | `ModuleGraph`（`reachableFrom` / `contains` / `stateOf` 等） | `analyzeAll` 只把它传给 `converge`；本文件不直接调它的查询方法 | 模块级可达性由 P5B 的 `converge` 定，本文件不二次计算 |
| Phase 4（symbol_graph） | `SymbolGraph`（`nodes` / `edges` / `module_deps`；`nodeCount` / `definedSymbols` / `referencedSymbols` / `moduleDependencies`） | `buildReport` 读 `nodes`（定义集）与 `edges`（入边核对）；`analyzeAll` 把图传给 `computeRoots` / `analyze` / `converge` | 本文件只读图，不改图 |
| Phase 4（retention） | `RetainSet`（`retainedNodes` / `rulesFor` / `isRetained`；`retainMain` / `retainGlobalInits`） | `analyzeAll` 的 `retain` 入参（`*RetainSet`，`computeRoots` 会改它）；`ReachReason.retained` 的 `RetainRuleSet` 即登记集的规则 | 宏展开 / 反射 / 动态调用 / 导出的判定逻辑今天没有（`rule_notes` 只登记文本），本文件不发明判定逻辑 |
| Phase 4（builder） | `GraphBuilder`（边整理：去重 / 分流 / 透传） | 不直接调用 | 边的整理已在 Phase 4 做完，本任务只消费已建好的图 |

导入语义（提案 §7，用户已定第三种）：符号级与模块级都支持，底层统一
落成 `SymbolEdge`；模块级导入没有对应的 `SymbolNode`，具体用到哪些
符号由可达性分析再收敛——本文件的 `module_only_modules`（P5B 的
`Convergence` 字段）即只被模块级导入触及的模块集合，其符号的后续
引用发现策略见 §7.5 第 3 项。

## 5. `analyzeAll` 接线顺序（五步，缺一不可，顺序固定）

| 步 | 调用 | 输入 → 输出 | 说明 |
|---|---|---|---|
| 1 | `computeRoots(symbol_graph, retain, entry_module, allocator)` | 图 + 保留集 + 入口模块 → `[]RootEntry` | 算根。**会修改 `retain`**（先 `retainMain` 再 `retainGlobalInits`）；调用方须传入可写的登记集 |
| 2 | `ReachabilityAnalyzer.analyze(symbol_graph, roots)` | 图 + 根 → `ReachabilityResult` | P5A 可达性分析（单遍遍历，无不动点迭代；见 §7.5 第 2 项） |
| 3 | `result.reachableModules(allocator)` | 分析结果 → `[]ModuleId` | 取可达模块集 |
| 4 | `converge(symbol_graph, module_graph, reachable_modules, allocator)` | 两层图 + 可达模块 → `Convergence` | P5B 模块收敛 |
| 5 | `buildReport(symbol_graph, &result, convergence, allocator)` | 图 + 分析结果 + 收敛结果 → `ReachabilityReport` | 建报告；`convergence` 所有权转移给报告 |

只做分析，不删除、不裁剪任何东西（裁剪是 Phase 6 的事）。中间产物
（`roots` / `reachable_modules` 切片）由 `analyzeAll` 分配并在返回前
释放；分析器与收敛器只拷贝它们需要的值，不保留切片本身。报告建好后，
分析器即可释放（报告不持有分析器内部存储的引用，见 `report.zig`
文件头“所有权”）。

## 6. 合并对齐（协调 agent 合并时落实，M1–M6）

三路并行编写，各写不同新文件，无文件冲突；facade 与本节由协调 agent 合并时写。

| # | 出入 | 裁决（合并时） |
|---|---|---|
| M1 | P5C 起草的 §7.5 第 1 项称“Phase 5 沿用线性扫描，不建邻接索引”，与 P5A 落盘不符：`analyzer.zig` 的 `analyze` 先从 `graph.edges.items` 建一次邻接索引（`HashMap(SymbolNode, ArrayList(SymbolRefEdge))`），再 BFS 展开 | 以落盘为准，§7.5 第 1 项已按实改写：分析器建索引；`classifyPrune`（P5C 的剪枝分类）仍用全边线性扫描。P4B `reachableSymbols` 的全边扫描口径不变（Phase 4 文件未动） |
| M2 | P5B `converge` 的收敛状态是模块粒度：判定“存在从可达符号发出的边”时只看 from 符号所属模块是否可达，未精确到符号本身 | 接受现状，记为跟进项：后续若调用方能传入可达符号集，状态可再收紧。收敛状态只是报告信息，不影响 P5A 可达集本身的正确性（可达集由真实边算出，是精确的） |
| M3 | P5A 的 `ReachabilityAnalyzer` 多了一个约定外方法 `invalidateIndex()`（索引缓存失效入口） | 保留：索引缓存假设图边只追加（`SymbolGraph` 无删边 / 改边 API）；若将来图支持删边，改图后须调 `invalidateIndex`，否则可能用旧索引。方法是 struct 成员，随类型 re-export，无需 facade 另列 |
| M4 | P5A `analyzer.zig` 以 `@import("roots.zig")` 引用 `RootEntry`；P5B `roots.zig` 是否落盘决定 import 能否解析 | 已核对：`roots.zig` 已落盘（112 行），`RootEntry = struct { node: SymbolNode, rules: RetainRuleSet }` 与约定逐字一致；`analyzer.zig` 只消费 `node` / `rules`，不构造、不判定规则来源 |
| M5 | P5C `report.zig` 内含 Phase 4 类型与 P5A / P5B 类型的 re-export（供本文件内调用方便），facade 是否重复转发 | 不冲突：`report.zig` 的 re-export 只服务本文件；facade（`src/reachability.zig`）从各原文件直接转发规范名（见本节末的清单），两者分属不同文件，无重定义 |
| M6 | `Convergence` 所有权：`converge` 按值返回；`buildReport` 按值接收并转移给 `ReachabilityReport`；失败时谁释放 | 已核对代码：`analyzeAll` 不另设 errdefer；`buildReport` 有 `errdefer freeConvergence`，失败时由它释放，成功时报告持有；`ReachabilityReport.deinit` 释放 `convergence` 的三字段。单所有权，无重复释放。`Convergence` 长度为 0 的切片不释放（可能为编译期空切片，见 `converge.zig` 注释） |

facade（`src/reachability.zig`，协调合并时写）：薄 re-export，28 个公开名——
`ReachReason` / `ReachabilityResult` / `ReachabilityAnalyzer`（analyzer.zig）、
`RootEntry` / `computeRoots`（roots.zig）、`ConvergedStatus` / `ConvergedDep` /
`Convergence` / `converge`（converge.zig）、`PruneReason` / `PruneCandidate` /
`ModuleStats` / `ReachStats` / `ReachabilityReport` / `buildReport` / `summarize` /
`analyzeAll`（report.zig），以及复用的 Phase 4 类型 `ModuleId` / `SymbolNode` /
`SymbolKind` / `SymbolRefEdge` / `RefKind` / `ModuleDep` / `SymbolGraph` /
`ModuleGraph` / `RetainRule` / `RetainRuleSet` / `RetainSet`（与 Phase 4 facade
复用 Phase 2 类型同款做法，使本 facade 对调用方自含）。

## 7. 已知缺口（只记，不擅自改结构）

以下各期条目**按原文引用出处，不全文照抄**：每项只记短标题与精确
出处（文件 + 章节 + 项号），原文以出处文件为准。

### 7.1 Phase 4 RESULT §6 的 12 项

出处：`/content/kit-work/sci2-opt-std/phase4/RESULT.md` §6（待裁决 /
跟进项），另见 `src/dependency_graph/MANIFEST.md` §7–§8、§10。

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
| 11 | Phase 1 的 8 项待裁决（见 §7.4） | 原样登记，未做定夺 |
| 12 | `build.zig` 注册（`dependency_graph` 与 Phase 2/3 同样未接 build） | 后续 Phase / 协调方的事 |

### 7.2 Phase 3 RESULT §6 的 7 项

出处：`/content/kit-work/sci2-opt-std/phase3/RESULT.md` §6（待裁决 /
跟进项），另见 `src/module_loader/MANIFEST.md` §8、§10。

| # | 项（短标题） | 状态 |
|---|---|---|
| 1 | spec.zig 两处 `.both => error.AmbiguousImport` 改为 `.symbol`（P3B 裁决 file_first 的接线，policy.zig 文件头已有指引） | 跟进项，未接线 |
| 2 | `LoaderState`↔`LazyLoader` 适配器（M1）；`ModuleTable`↔`LazyLoader` 统一（M2）；loader 走 `locateRelative`（M5） | 未决，后续接线 Phase 的事 |
| 3 | `injectimportedfile.zig:484` 的旧签名调用点迁移到表核心，之后删除 `expandImportsInto` 旧签名适配器（M4） | 跟进项 |
| 4 | 版本 `@` 后缀与操作符是否采纳为正式语法（Phase 2 待裁决 #6） | 未决 |
| 5 | `extractImportStrings` 不带行号（Phase 2 待裁决 #8；环诊断暂用入口路径 + 行号 0） | 未决 |
| 6 | Phase 1 的 8 项待裁决（见 §7.4） | 原样登记，未做定夺 |
| 7 | 盒子主机名现为 `bd4991109185`，与任务所述一致，不影响工作 | 只记 |

### 7.3 Phase 2 RESULT §6 的 10 项

出处：`/content/kit-work/sci2-opt-std/phase2/RESULT.md` §6（待裁决 /
判断类问题），另见 `src/module_resolver/MANIFEST.md` §8。

| # | 项（短标题） | 状态 |
|---|---|---|
| 1 | 消歧规则：真实歧义（`sa_std/io`、`sa_std/fmt`、`sa_std/io/print` 等）优先文件还是优先 prelude | Phase 3 已裁决：优先文件（policy.zig）；spec.zig 的 `.both` 分支改动未接线，见 §7.2 第 1 项 |
| 2 | 斜杠 / 点分同形不同义是否统一 | Phase 3 已裁决：不统一，各走各的（policy.zig） |
| 3 | 相对导入的基准目录：给 `Locator` 加 `locateRelative(spec, base_dir)`，还是由调用方预先解析成包限定形式 | Phase 3 已实现 `locateRelative`（P3C）；loader 侧接线为跟进项（M5） |
| 4 | 中间层 shim（`collections/<name>.sa` 等 6 处）：Phase 3 是否扩展 shim 搜索层级 | Phase 3 已裁决：不扩展（P3C 实测） |
| 5 | `sa_std/<name>` 且 `<name>` 非域名时（如 `sa_std/vec.sa`）是否试顶层 shim | Phase 3 已裁决：先试顶层 shim（按现状口径，P3C） |
| 6 | 版本 `@` 后缀与操作符是否采纳为正式语法 | 未决 |
| 7 | 未知扩展名（如 `.txt`）不判 symbol、落到探针 / 默认分支的口径是否合适 | Phase 3 已确认合适（policy.zig） |
| 8 | `extractImportStrings` 不带行号 | 未决；行号支持需改返回形态，留待后续 |
| 9 | Phase 1 的 8 项待裁决（见 §7.4） | 原样登记，未做定夺 |
| 10 | 盒子主机名（先前记录的 `bd00ae7b9304` 已变，疑似换机） | 只记，不影响工作 |

### 7.4 Phase 1 的 8 项

出处：`src/module_resolver/MANIFEST.md` §6（转录自 Phase 1 RESULT §6），
照现状、不由本任务定。

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

### 7.5 Phase 5 自身的新增项

| # | 项 | 状态 |
|---|---|---|
| 1 | **邻接索引与线性扫描的取舍已定**：分析器（P5A）每次 `analyze` 先从 `graph.edges.items` 建一次邻接索引（`HashMap(SymbolNode, ArrayList(SymbolRefEdge))`），再 BFS 展开，不做每步全边扫描；索引在分析器内缓存复用，缓存键为（图指针，边数），换图或边数变化时自动重建，另有 `invalidateIndex()` 手动失效入口。`classifyPrune`（P5C 的剪枝分类）仍用全边线性扫描（O(E) / 符号）。P4B `reachableSymbols` 的全边扫描口径不变（Phase 4 文件未动） | 已定（合并时按落盘更正，见 §6 M1） |
| 2 | **单遍分析，无不动点迭代（已定）**：可达性分析为从根出发、沿已记录边的一次遍历即得闭包，不做不动点迭代。前提是边集在分析前已完整（Flattener 展开边已落图）；边集若在分析后追加，须重跑分析（无增量接纳） | 已定 |
| 3 | **module_only 模块的符号后续引用发现策略（待定）**：module_only 模块只有模块级导入、无符号级边；其符号若在分析后被新发现引用，是由 Phase 5 内二次扫描发现，还是留给 Phase 6 裁剪时按需展开，待协调裁决 | 待裁决 |
| 4 | P5A / P5B 调用形状已由协调合并时核对确认：`ReachabilityAnalyzer.init(allocator)` / `analyze(graph, roots)` / `deinit` 实例形态；`computeRoots(graph, retain, entry_module, allocator) ![]RootEntry`；`converge(symbol_graph, module_graph, reachable_modules, allocator) !Convergence`；错误集均为 `Allocator.Error`；`Convergence` 三字段为 owned 切片（长度 0 者不释放，见 §6 M6）。`report.zig` 的调用点与落盘逐字一致 | 已确认（合并时） |
| 5 | `PruneReason` 两档下的不一致情形无处可记：某条入边来自可达符号、节点本身却不可达时，说明分析器与图不一致，仍归入 `referenced_only_by_unreachable`；是否要第三档或单独的诊断通道，待协调裁决 | 待裁决 |
| 6 | 保留规则判定逻辑仍缺：`macro_expanded` / `reflective` / `dynamic_call` / `exported` 四条规则只登记文本（`retention.zig` 的 `rule_notes`），判定需解析器 / 后端能力（宏展开表、反射元数据、动态分发表、导出表），今天没有；本文件不发明判定逻辑 | 只记 |
| 7 | `summarize` 只产纯文本，无结构化（JSON）输出；结构化报告是否是后续需求，待定 | 待定 |
| 8 | `string/` 无 prelude 仍是缺口（Phase 2 已知缺口）：模块级边回退到域模块本身；`buildReport` 的按模块分表里 string 域模块的符号收敛仍受此限 | 只记 |
| 9 | 钩子均为空实现（Phase 3 遗留）：parse / type-check / analyze 未接任何解析器，`markAnalyzed` 只推进状态；`filterByState` 的 `ready` 只看状态机位置，不保证语义分析真正完成——可达性分析消费的边若来自未真正分析完的模块，其完备性不受本文件保证 | 只记 |

## 8. 待裁决项（协调 agent / 后续 Phase 裁决）

1. §6 合并对齐已由协调 agent 合并时定稿（M1–M6，facade 28 个公开名）；M2（收敛状态的符号级收紧）与 M3（索引缓存的删边假设）为跟进项。
2. §7.5 第 3 项：module_only 模块的符号后续引用发现策略（Phase 5 内二次扫描，还是 Phase 6 裁剪时按需展开）。
3. §7.5 第 5 项：`PruneReason` 是否需要第三档（或单独的诊断通道）来记“入边来自可达符号而节点仍不可达”的不一致情形。
4. §7.5 第 7 项：是否需要结构化（JSON）报告输出。
5. §7.1–§7.4 的全部历史遗留项（Phase 4 的 12 项、Phase 3 的 7 项、Phase 2 的 10 项、Phase 1 的 8 项）——原样登记，本任务不做定夺。
6. `build.zig` 注册：`reachability`（与 Phase 2 的 `module_resolver`、Phase 3 的 `module_loader`、Phase 4 的 `dependency_graph` 同样）未接 build；注册是后续 Phase / 协调方的事。

## 9. 未做的事（按任务硬约束，另行安排）

- **无构建/测试结果可报**：未跑 `zig build`、未跑 `zig test`、未跑任何测试。只跑 `zig ast-check`（parse-only 静态检查）与行数核对。
- 未修任何 bug：包括 Phase 1 的构建断裂（`no @extern declarations parsed from sa_std/growvec.sai`）、sci 7ecae6d 的 double-free、任务 79 报告的 6 项基线缺陷、Phase 1/2/3/4 的待裁决项。
- 未改任何现有文件（只新增 `src/reachability/` 下的 4 个 .zig 文件与本清单；合并时由协调 agent 把三路文件拷入主副本 `/content/kit-work/sci2` 并写 facade）；未动 `sa_std/`、`tests/`、`build.zig*`；未合 main；未动 `/content/sa_all/sci` 原仓；三路 agent 副本保留在 `/content/kit-work/sci2-agentP5A/B/C`。
- 未接线：`analyzeAll` 的接线只定义调用顺序与契约，未接入任何真实调用方；facade（`src/reachability.zig`）已由协调合并时写（28 个公开名，见 §6）。
- 未裁剪、未删除任何东西：`ReachabilityReport` 只报告可裁剪候选，删除与否是 Phase 6 的事。
