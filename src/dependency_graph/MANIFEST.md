# sa-dependency-graph — 模块清单（Std 模块化 Phase 4，P4C：图构建器接线，起草）

> 提案：`~/workspace/goals/sci-sa-optimize/files/STD-MODULARIZATION-PROPOSAL.md`
> （§2 懒加载流程与四种模块状态、§3 两层依赖图与 Reachability-based DCE、
> §4 三个独立模块与建议管线、§7 第三种导入语义）。
> Phase 2 结果：盒上 `src/module_resolver/`（types / locator / spec / closure）与
> `src/module_resolver/MANIFEST.md`。
> Phase 3 结果：盒上 `src/module_loader/`（loader / cycle / policy / wiring）与
> `src/module_loader/MANIFEST.md`；Phase 3 RESULT（本机
> `~/workspace/sci2-opt-std/phase3/RESULT.md`，重点 §2 接线与 §6 待裁决项）。
> 工作仓：盒上 `/content/kit-work/sci2-agentP4C`（分支 `sa-optimize`，
> 基线 `d31bcc32`，Phase 3 终推）。本任务只新增 `src/dependency_graph/` 下两个
> 文件，不改任何现有文件，不合 main、不 push。
>
> **本文为起草**：协调 agent 合并 P4A / P4B / P4C 三路工作时定稿；P4A 的
> `ModuleGraph`、P4B 的 `SymbolGraph` / `RetainSet` 落盘后，§2、§3、§4 须按
> 真实图类型补齐接线细节，本清单的契约部分以合并后的定稿为准。

## 1. 模块目的

`sa-dependency-graph` 是提案 §4 三个独立模块之二（Phase 4，模块依赖图），
独立于 Lexer、Referee、Backend。

它承接 Phase 3 懒加载器的产出（`LazyLoader.edges: []SymbolEdge`，不去重），
产出提案 §3 的两层依赖图的输入：

| 依赖图 | 用途（提案 §3） | 本任务的产出 |
| ------ | --------------- | ------------ |
| Module Dependency Graph | 决定哪些模块需要加载、分析 | `[]ModuleEdge`（去重后的模块边） |
| Symbol / Function Dependency Graph | 决定哪些函数、全局数据需要进入最终产物 | `[]SymbolEdge`（只含符号级边） |

它**不是**加载器（Phase 3）、**不是**可达性裁剪（Phase 5）、**不是** DCE
（Phase 6）。它只做边的整理：去重、分流、透传环记录；不解析、不加载、
不检测环、不判定环是否合法、不推进任何模块的状态机。

建议管线中的位置（提案 §4）：

```
Source → Module Resolver → Lazy Loader → Parser → Name Resolution
  → Dependency Graph（本模块：GraphBuilder 整理边 → P4A/P4B 图结构）
  → Semantic Analysis → Flattener → SA IR → Referee
  → Reachability Analysis → WASM / LLVM / JS
```

## 2. 文件分工

| 文件 | 职责 | 行数上限 |
|---|---|---|
| `src/dependency_graph/builder.zig` | `GraphBuilder`：模块边去重、符号边过滤、按状态分流、环记录透传；只定义输入/输出契约，不定义图结构 | ≤700 |
| `src/dependency_graph/MANIFEST.md` | 本清单（起草） | — |

并行三路的分工（合并时协调 agent 核对，**本任务不依赖以下文件的落盘**）：

| 路 | 文件（并行编写中） | 职责 | 与本任务的关系 |
|---|---|---|---|
| P4A | `ModuleGraph` | 模块依赖图结构本身 | 消费本构建器的 `[]ModuleEdge` |
| P4B | `SymbolGraph` / `RetainSet` | 符号依赖图结构与保留集 | 消费本构建器的 `[]SymbolEdge`（与保留规则） |
| P4C（本任务） | `GraphBuilder`（`builder.zig`） | 边整理器：只定义输入/输出契约 | 产出供 P4A / P4B 消费的两个去重后数组 |

不设独立的 `types.zig`：本模块不定义新共享类型——`ModuleId` /
`ModuleState` / `ImportKind` / `SymbolEdge` 复用 Phase 2 的
`src/module_resolver/types.zig`，`CycleRecord` 复用 Phase 2 的
`src/module_resolver/closure.zig`（经 `loader.zig` 同款 re-export 形状）；
本文件唯一新增的类型是 `ModuleEdge`（模块边：`from` / `to` / 首条 kind）
与 `FilterResult`（分流结果），两者都只在本模块内有意义。

## 3. GraphBuilder 输入 / 输出契约

### 3.1 输入

| 输入 | 形状 | 来源 | 约定 |
|---|---|---|---|
| 原始边集 | `edges: []const SymbolEdge` | 通常为 `loader.edges.items`（Phase 3，不去重） | builder 只读，不改 loader / flattener / resolver 的任何状态 |
| 模块状态查询接口 | `stateOf: StateFn`，即 `*const fn (ModuleId) ?ModuleState` | 调用方提供的适配器函数 | 见 §3.3；函数指针不带上下文，适配器由调用方写 |
| 环记录 | `records: []const CycleRecord` | 通常为 `loader.cycles.items`（Phase 3，只记不报错） | 只透传，不重新检测 |

### 3.2 输出

| 输出 | 形状 | 规则 |
|---|---|---|
| 模块边列表 | `[]ModuleEdge` | 按 `(from, to)` 去重，保留首条 kind；跳过 `from == to` 的自边并计数（`skipped_self_edges`）；重复边计数（`duplicate_module_edges`）。符号级边与模块级边在此处不区分，都落成一条模块边（提案 §7：两种导入统一成依赖图） |
| 符号边列表 | `[]SymbolEdge` | 只取 `symbol != null` 的边，保持输入顺序，不去重（去重是 P4B SymbolGraph 的职责）；模块级边（`symbol == null`）不展开，记入 `skipped_module_edges` 计数 |
| 分流结果 | `FilterResult{ ready, pending }` | `loaded` / `analyzed` 进 `ready`；`unloaded` / `loading` / 未登记（`stateOf` 返回 null）进 `pending`。只读状态，不推进状态机 |
| 环记录列表 | `[]CycleRecord` | 透传输入记录，不重新检测、不改写、不判定环是否合法 |

计数器（`GraphBuilder` 的公开字段，`reset` 清零）：`skipped_self_edges`、
`duplicate_module_edges`、`skipped_module_edges`、`kept_symbol_edges`。

### 3.3 状态查询适配器

`StateFn` 是裸函数指针，不带上下文；调用方须在自己的作用域里写一个薄
适配器（完整示例见 `builder.zig` 中 `StateFn` 的文档注释）：

- 对 `LazyLoader`：包着 `loader.stateOf(id)`（`loader.zig` 的公开方法，
  未登记返回 null）；
- 对 `ModuleTable`：包着 `table.stateOf(id)`（`wiring.zig` 的公开方法，
  只读 `states` 覆盖层；经旧 map 路径展开的模块可能查不到，返回 null，
  按保守口径归入 `pending`）。

真正的适配器落点（`LoaderState`↔`LazyLoader` 适配器 M1、
`ModuleTable`↔`LazyLoader` 统一 M2）是合并 / 后续接线 Phase 的事，
只记不写（见 §6）。

### 3.4 所有权规则

与 Phase 2 的 A8、Phase 3 的 loader 一致（arena 规则）：调用方传入一个
arena 分配器，builder 用它分配一切输出切片与内部容器；`deinit` 只释放
容器本身，不释放任何字符串与 `cycle_path` 切片（由调用方统一释放 arena）。
返回的切片在 builder 下一次改变同一列表的调用前有效；需跨多次构建长期
持有时，调用方自行复制。`buildModuleEdges` 跨多次调用时，已产出的边同样
参与去重（先登记进本轮的临时表）。

## 4. 公开 API 表

| 名字 | 来源 | 用途 |
|---|---|---|
| `ModuleId` / `ModuleState` / `ImportKind` / `SymbolEdge` | `../module_resolver/types.zig`（复用） | Phase 2 共享类型，不重定义 |
| `CycleRecord` | `../module_resolver/closure.zig`（复用） | 一条导入环：`cycle_path: []ModuleId`、`entry: ModuleId`；只透传 |
| `ModuleEdge` | `types.zig`（新增；A2 合并统一，builder.zig 已改为 re-export） | 模块边：`from` / `to` / `via: ?ImportKind`（首条边的粒度；null = 未知/未记录） |
| `StateFn` | `builder.zig`（新增） | 模块状态查询接口：`*const fn (ModuleId) ?ModuleState` |
| `FilterResult` | `builder.zig`（新增） | 分流结果：`ready: []ModuleId`、`pending: []ModuleId` |
| `GraphBuilder` | `builder.zig`（新增） | 边整理器，见 §5 方法表 |

## 5. GraphBuilder 方法表

| 方法 | 签名 | 说明 |
|---|---|---|
| `init` | `init(allocator: std.mem.Allocator) GraphBuilder` | 构造；allocator 为调用方传入的 arena |
| `deinit` | `deinit(self: *GraphBuilder) void` | 只释容器；字符串由调用方统一释放 arena |
| `reset` | `reset(self: *GraphBuilder) void` | 清空累计产出与计数器（保留容量），供下一轮构建复用 |
| `buildModuleEdges` | `buildModuleEdges(edges: []const SymbolEdge) ![]ModuleEdge` | 模块边去重（§3.2）；自边跳过并计数 |
| `buildSymbolEdges` | `buildSymbolEdges(edges: []const SymbolEdge) ![]SymbolEdge` | 只取符号级边；模块级边不展开，计数 |
| `filterByState` | `filterByState(ids: []const ModuleId, stateOf: StateFn) !FilterResult` | 按状态分流；只读，不推进状态机 |
| `cyclesFrom` | `cyclesFrom(records: []const CycleRecord) ![]CycleRecord` | 透传环记录，不重新检测 |

## 6. 与 Phase 2 / Phase 3 的关系表

| Phase | 产出 | 本任务的用法 | 备注 |
|---|---|---|---|
| Phase 2（types） | `ModuleId` / `ModuleState` / `ImportKind` / `SymbolEdge` | 复用，不重定义 | `SymbolEdge.symbol == null` 即模块级边 |
| Phase 2（closure） | `CycleRecord`（`cycle_path` + `entry`）、`ClosureBuilder.edges`（不去重） | `CycleRecord` 复用、透传 | builder 的去重口径与 ClosureBuilder 的“不去重”互补：去重是 Phase 4 图层的事 |
| Phase 2（spec） | `parseImportSpec` / `extractImportStrings` | 不直接调用 | 边由 loader 产出，本构建器只消费边 |
| Phase 3（loader） | `LazyLoader.edges` / `cycles` / `order`、`stateOf(id)`、`markAnalyzed` | `edges` / `cycles` 为本构建器的典型输入；`stateOf` 为 `StateFn` 的适配源 | loader 的边不去重（与 ClosureBuilder 一致）；本构建器不调 `markAnalyzed`，不推进状态机 |
| Phase 3（cycle） | `CyclePolicy` / `detectCycle` / `checkCycle` / `cyclePathString` | 不调用 | 环的检测与合法性判定仍在 cycle.zig；本构建器只透传记录 |
| Phase 3（wiring） | `ModuleTable.stateOf` / `markAnalyzed` | `stateOf` 为 `StateFn` 的另一适配源（flattener 过渡层） | 只读使用，不改 flattener 接线（M2） |
| Phase 3（policy） | 消歧“优先文件”等三项裁决 | 不直接依赖 | 裁决影响的是边的产生（定位侧），不是边的整理 |

导入语义（提案 §7，用户已定第三种）：符号级与模块级都支持，底层统一
落成 `SymbolEdge`；本构建器在模块边层面把两者统一成 `ModuleEdge`，
在符号边层面保留粒度区分（模块级边不展开，具体符号收敛是 Phase 5 的事）。

## 7. 已知缺口（只记，不擅自改结构）

### 7.1 合并对齐（Phase 3 的 M1–M5，本任务相关部分）

| # | 缺口 | 状态 |
|---|---|---|
| M1 | `LoaderState`（`cycle.zig`，取 `*const AutoHashMap(ModuleId, ModuleState)` + `[]ModuleId` 栈投影）↔ `LazyLoader`（`modules` 为 `HashMap(ModuleId, ModuleEntry)`）类型不同，无适配器 | 只记。本任务的 `StateFn` 是裸函数指针，适配器由调用方写；真正的适配器是后续接线 Phase 的事 |
| M2 | `ModuleTable`（`wiring.zig`，独立薄适配）与 `LazyLoader` 未统一：flattener 现走 `ModuleTable` 而非 `LazyLoader`；`LazyLoader` 未接入 flattener | 只记。本构建器对两者都只读（`stateOf` 适配），不改 flattener 接线；统一是后续步骤 |
| M5 | loader 走相对路径缺口：`loadRoot` 路径无 `base_dir`，相对导入在排空时报 `InvalidImportSpec` / `ModuleNotFound`；P3C 已实现 `Locator.locateRelative(spec, base_dir)`，loader 后续接线时改走它 | 只记。本构建器不拼基准目录、不定位，只消费已产出的边 |
| M3（相关） | spec.zig 两处 `.both => error.AmbiguousImport` 改为 `.symbol`（P3B 裁决“消歧优先文件”的接线，`policy.zig` 文件头已有指引，本次未改） | 跟进项。改的是边的产生（定位侧），本构建器只消费边 |
| M4（相关） | `injectimportedfile.zig:484` 的旧签名 `expandImportsInto` 调用点未迁到表核心，旧签名薄适配器暂留；该调用点迁移后即可删除适配器 | 跟进项。本任务不改 flattener 文件 |

### 7.2 其他未决 / 缺口

1. **版本 `@` 语法未决**（Phase 2 待裁决 #6）：版本 `@` 后缀与操作符是否采纳为正式语法。`ImportSpec.version` 只记录不校验；本构建器的边不携带版本信息，版本维度的图边是后续议题。
2. **`extractImportStrings` 无行号**（Phase 2 待裁决 #8）：环诊断暂用入口路径 + 行号 0（Phase 3 `reportCycle` 的口径）。本构建器透传的 `CycleRecord` 同样无行号。
3. **`string/` 无 prelude**：模块级边回退到域模块本身（Phase 2 已知缺口）。`buildSymbolEdges` 跳过的模块级边里，`string/` 域的边在 Phase 5 之前无法收敛到具体符号。
4. **P4A / P4B 的真实图类型已落盘（合并时，见 §10）**：`ModuleGraph`（types.zig + module_graph.zig）、`SymbolGraph` / `RetainSet`（symbol_graph.zig + retention.zig）已由协调 agent 合并进主副本；`GraphBuilder` 的 `[]ModuleEdge` / `[]SymbolEdge` 产出与真实图类型已统一（A1–A2）；符号边是否在图层二次去重仍待明确（见 §8 第 2 项）。
5. **钩子均为空实现**（Phase 3 遗留）：parse / type-check / analyze 未接任何解析器，`markAnalyzed` 只推进状态。`filterByState` 的 `ready` 只看状态机位置，不保证语义分析真正完成。
6. **宏 / 反射 / 动态调用 / 全局初始化的保留规则未定**（提案 §3）：Reachability 分析必须考虑 Flattener 展开后的实际引用，不能只看源码 import；保留规则是 Phase 5 的事，本构建器不做任何保留判断。

### 7.3 Phase 1 的 8 项待裁决（原样登记，照现状、不由本任务定）

转录自 `src/module_resolver/MANIFEST.md` §6，原样登记：

1. `jwt.sla` 归属：现放 `db/core/`，本质是 crypto 应用，候选 `crypto/`。
2. `compress` 归属：现放 `crypto/encoding/`，候选 `encoding/` 域。
3. `crypto.sai` 拆分（哈希/随机数/口令等六类）与 `redis.sla` 的 RESP 编解码/TCP 客户端拆分。
4. 是否把 `db/crypto/testing/tree_sitter` 的 prelude 纳入顶层 `sa_std/prelude.sa`（F 报告待定项；Phase 1 未纳入）。
5. F 域“其他”文件：`oop.sal`→建议 core、`sse.sla`→建议 http、`ctx.sla`→建议 task，均保留顶层原位未移动；`dtls` 只记不碰。
6. `core/future/`（future/task/waker）是否抽出到 task 域（A 报告未定）。
7. `.sai` shim 机制：全仓零个 `.sai` 文件含 `@import`，.sai shim 未经验证；E 的 13 个 `.sai` 无 shim 是本次唯一 breaking change（demos/tests 的 8 处引用已在合并修正中改到新路径）。
8. E 的缺陷 D1：`net/socket/net.sal` 里 `SA_NET_ERR_ACCESS` 与 `SA_NET_ERR_TIMEOUT` 同值 4（疑似真 bug，只记未修）。

（另见 Phase 1 RESULT §6：core → sync 11 边、core → collections 2 边为已知既存层级倒置，Phase 1 未修；`core/sa_core.sa` 第 36–37 行重复 import `../sync/rwlock.sal` 两次。）

## 8. 未决问题（协调 agent / 后续 Phase 裁决）

1. `StateFn` 适配器的最终落点：`LoaderState`↔`LazyLoader` 适配器（M1）与 `ModuleTable`↔`LazyLoader` 统一（M2）由谁在哪一步写——本任务只给了裸函数指针契约与调用方示例，未写任何适配器实现（未经编译验证的适配代码风险大于收益，Phase 3 M1 同款理由）。
2. 符号边是否在图层二次去重：本构建器 `buildSymbolEdges` 不去重；P4B 的 `SymbolGraph` 是否去重、按什么键去重，待 P4B 定稿时明确。
3. 模块边的 kind 语义：同一 `(from, to)` 上符号级边与模块级边并存时，本构建器保留首条 kind；图层是否需要记录“两种粒度都出现过”，待 P4A 定稿时明确。
4. `pending` 模块的重跑策略：`filterByState` 只分流不等待；加载推进后由调用方重跑构建器，还是由图层增量接纳，待后续接线 Phase 明确。
5. `build.zig` 注册：`dependency_graph`（与 Phase 2 的 `module_resolver`、Phase 3 的 `module_loader` 同样）未接 build；注册是后续 Phase / 协调方的事。

## 9. 未做的事（按任务硬约束，另行安排）

- **无构建/测试结果可报**：未跑 `zig build`、未跑 `zig test`、未跑任何测试。只跑 `zig ast-check`（parse-only 静态检查）与行数核对。
- 未修任何 bug：包括 Phase 1 的构建断裂（`no @extern declarations parsed from sa_std/growvec.sai`）、sci 7ecae6d 的 double-free、任务 79 报告的 6 项基线缺陷、Phase 1/2/3 的待裁决项。
- 未改任何现有文件（只新增 `src/dependency_graph/` 下的 `builder.zig` 与本清单）；未动 `sa_std/`、`tests/`、`build.zig*`；未合 main；未动 `/content/sa_all/sci` 原仓；未动主副本 `/content/kit-work/sci2`（只写副本 `/content/kit-work/sci2-agentP4C`）。
- 未接线：`GraphBuilder` 未接入 `LazyLoader` / `ModuleTable` / flattener（只定义契约与适配示例）；P4A / P4B 的图结构未在本任务内定义。

## 10. 合并对齐（协调 agent 合并时落实，A1–A5）

三 agent 并行编写，各写不同新文件，无文件冲突；facade（`src/dependency_graph.zig`）与本节由协调 agent 合并时写。

| # | 出入 | 裁决（合并时） |
|---|---|---|
| A1 | P4A 的 `types.zig` 与 P4B 的 `symbol_graph.zig` 各自含一套 `SymbolNode` / `SymbolKind`（字段与成员逐字相同，P4B 另有 `key` / `moduleRoot` / `isModuleRoot` 三个方法） | 以 `types.zig` 为准：把 P4B 的三个方法逐字并入 `types.zig` 的 `SymbolNode`（`key` / `moduleRoot` / `isModuleRoot`，P4B 原文）；`symbol_graph.zig` 的 `SymbolKind` / `SymbolNode` 改为 `dep_types` 的 re-export；`symbol_graph.zig` 文件头“自含定义”注记已更新。方法签名与命名约定不变 |
| A2 | P4A 的 `ModuleEdge`（`from` / `to` / `via: ?ImportKind`）与 P4C 的 `builder.zig` 自含 `ModuleEdge`（`from` / `to` / `kind: ImportKind`）字段名与可选性不同 | 以 `types.zig` 为准：`builder.zig` 的 `ModuleEdge` 改为 re-export；唯一构造点 `.kind = edge.kind` 改为 `.via = edge.kind`；相关文档注记同步改 `via`。`via = null` 表示粒度未知/未记录，不是第三种导入方式（与 P4A 的 `ModuleEdge` 文档一致） |
| A3 | 两套 `GraphError` 同名不同集：`types.zig` 的 `GraphError`（OutOfMemory / NodeNotFound / CycleDetected / InvalidState）与 `symbol_graph.zig` 自含的 `GraphError`（Allocator.Error \|\| InvalidExpandedEdgeKind） | 本次不合一：facade 只转发 `types.zig` 的 `GraphError`（规范错误集）；`SymbolGraph` 方法仍返回其局部错误集。统一错误集是后续接线 Phase 的跟进项（见 §7.2 新增第 7 项） |
| A4 | P4B 的 `ModuleDep`（symbol_graph.zig 内部的模块级依赖记录）与 P4A 的 `ModuleEdge` 形状相近但分属两层 | 本次不合一：`ModuleDep` 留作符号层的内部记录，`ModuleEdge` 为模块层的规范边。是否合一是后续接线 Phase 的跟进项（见 §7.2 新增第 7 项） |
| A5 | facade（`src/dependency_graph.zig`，52 行）：薄 re-export 27 个公开名（types.zig 13 个 + `ModuleGraph` + symbol_graph.zig 4 个 + retention.zig 6 个 + builder.zig 3 个）；`symbol_graph.zig` 的局部 `GraphError` 未转发（见 A3） | 协调 agent 合并时写；验证脚本 `check_phase4.py` 断言 27/27 |

### 7.2 新增跟进项（合并时）

7. **错误集统一**（A3）：`types.zig` 的 `GraphError` 与 `symbol_graph.zig` 的局部 `GraphError` 是否合一、合一后 `SymbolGraph` 方法的错误集形状，由后续接线 Phase 定。
8. **`ModuleDep` 与 `ModuleEdge` 是否合一**（A4）：符号层的模块级依赖记录与模块层的规范边是否同构，由后续接线 Phase 定。
9. **同一 `(from, to)` 上两种粒度并存**（§8 第 3 项的延续）：构建器只保留首条 kind；图层是否需记录“两种粒度都出现过”，待 P4A 定稿时明确（`ModuleGraph.addEdge` 的去重口径已定：保留首条）。
