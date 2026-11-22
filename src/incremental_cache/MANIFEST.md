# SA 标准库模块化 Phase 7 — `sa-incremental-cache` 模块清单（协调定稿）

> 阶段：Phase 7（P2）增量编译缓存。只做实现，不跑构建/测试、不修 bug（与 Phase 6 同款硬约束；修与测试验证另行安排）。
> 工作仓：盒上 `/content/kit-work/sci2`（主副本），分支 `sa-optimize`，基线 `4735d6ff`（Phase 6 终推）。只动 sci2，`/content/sa_all/sci` 原仓未动，未合 main。
> 三路 agent 并行编写（P7A types.zig、P7B store.zig、P7C driver.zig + MANIFEST 起草），协调 agent 合并对齐并写 facade、定稿本 MANIFEST；§5 为合并对齐 C1–C6 + M1–M6。

## 1. 模块目的

提案顺序的下一步（Phase 6 RESULT §7）：增量编译缓存。`sa-incremental-cache` 回答一次编译“哪些模块可以复用上次的编译产物、哪些必须重编”：

- 输入：缓存库（P7B 的 `CacheStore`）、懒加载器的模块表（Phase 3 的 `LazyLoader.modules`）、模块依赖图（Phase 4 的 `ModuleGraph`）、本次变化的模块列表（`changed`）、编译器版本 / 插件版本 / 优化级别、以及一个取模块内容的回调（`content_of`）。
- 输出：`ReusePlan`——复用集（`reuse`）、重编集（`rebuild`）、本次失效集（`invalidated`）、本次计数的拷贝（`stats`），外加一行纯文本摘要（`summarizePlan`）。
- 本模块只做计划：不编译任何模块，不写缓存条目，不删 loader / 图里的任何东西，不读文件。复用产物的取用与重编的执行是调用方的事；缓存条目的增删是 P7B 的事。

与 Phase 2 / 3 / 4 / 5 / 6 的分工见 §4；与 Phase 6 的关系最直接：DCE 决定“哪些符号不进产物”，本模块决定“哪些模块不用重编”——两者都消费同一批图，但不互相调用。

## 2. 文件清单

| 文件 | 职责 | 行数 | 编写 |
|---|---|---|---|
| `src/incremental_cache.zig` | facade：薄 re-export，不含逻辑（15/15 公开名） | 34 | 协调 |
| `src/incremental_cache/types.zig` | `CacheFormatVersion` / `CacheKey` / `CacheEntry` / `CacheError` / `CacheStats`：缓存键与核心类型 | 216 | P7A |
| `src/incremental_cache/store.zig` | `CacheStore` / `validateAll` / `invalidate`：内存存储与失效 | 289 | P7B（合并时改 4 处错误集，见 §5 M1） |
| `src/incremental_cache/driver.zig` | `ReusePlan` / `planIncremental` / `summarizePlan`：五步集成入口与报告 | 321 | P7C（合并时改 3 处调用点，见 §5 M2–M3） |
| `src/incremental_cache/MANIFEST.md` | 本清单（目的、分工、API 表、关系表、合并对齐、已知缺口、待裁决合订指针） | 见落盘 | P7C 起草 + 协调定稿 |

改动文件：无（Phase 7 只新增，不改既有文件；与 Phase 2–6 同款）。

## 3. API 表

### 3.1 本文件新增（`driver.zig`）

| 名字 | 形状 | 说明 |
|---|---|---|
| `ReusePlan` | struct（`allocator` / `reuse` / `rebuild` / `invalidated` / `stats`；`deinit`） | 一次计划的全部产出；`deinit` 统一释放三个 owned 切片（长度为 0 的不释放） |
| `planIncremental` | `(store: *CacheStore, loader: *const LazyLoader, module_graph: *const ModuleGraph, changed: []const ModuleId, compiler_version: []const u8, plugin_version: []const u8, opt_level: u8, content_of: *const fn (module: ModuleId) []const u8, allocator: std.mem.Allocator) !ReusePlan` | 五步集成入口（见 §3.2）；推断错误集，实为 `Allocator.Error` |
| `summarizePlan` | `(plan: *const ReusePlan) []const u8` | 纯文本摘要一行（复用数、重编数、失效数、命中率）；返回静态缓冲区的借用切片（见 §3.3） |

`planIncremental` 的五步（缺一不可，顺序固定）：① `validateAll` 整库版本校验（版本对不上先整库失效）；② `invalidate` 求失效闭包（changed + 反向依赖，loaded / analyzed 态才进闭包）；③ 对 `loader.modules` 表里每个 loaded / analyzed 态模块算 `CacheKey`（内容经 `content_of` 回调取，不直接读文件）；④ 键命中 store 即 reuse、未命中即 rebuild（已失效的模块不算键，直接进 rebuild）；⑤ 返回 `ReusePlan`。

状态门（第 ② / ③ 步共用同一口径，与 Phase 4 的 `stateIsTraversable` 一致）：unloaded 态模块不进 plan（还没加载，无物可缓存）；loading 态模块不进 plan（正在加载中，留待下轮）。

### 3.2 P7A / P7B 的调用形状（假设，见 §5 C1–C5）

P7A / P7B 尚未落盘，以下形状是 P7C 按任务书给定的名字写下的假设，合并时以落盘为准：

| 名字 | 形状（合并后落盘） | 出处 |
|---|---|---|
| `CacheKey.compute` | `(content: []const u8, compiler_version: []const u8, plugin_version: []const u8, opt_level: u8) CacheKey`（纯函数，无分配器、无错误集） | P7A `types.zig`；C1 已核对一致，无改动 |
| `validateAll` | `(store: *CacheStore, expected_compiler: []const u8, expected_plugin: []const u8, expected_opt: u8, allocator: std.mem.Allocator) Allocator.Error![]ModuleId`（返回因版本失配而失效的模块列表，owned） | P7B `store.zig`；C2 合并裁决 M2：`driver.zig` 第 ① 步按落盘改调用点，取回的列表立即释放（长度为 0 的不释放） |
| `invalidate` | `(store: *CacheStore, changed: []const ModuleId, module_graph: *const ModuleGraph, allocator: std.mem.Allocator) Allocator.Error![]ModuleId`（既丢弃库内对应条目，又返回 owned 失效闭包） | P7B `store.zig`；C3 已核对一致（自由函数，无 `loader` 参数），无改动 |
| `lookup` | `store.lookup(key: CacheKey) ?CacheEntry`（方法调用，null = 未命中） | P7B `CacheStore` 的方法；C4 已核对一致，无改动 |
| `CacheStats` | 字段为 `hits` / `misses` / `invalidated` / `evicted`（皆 `u64`，无 `total`） | P7A `types.zig`；C5 合并裁决 M3：`driver.zig` 第 ⑤ 步的字面量按落盘写，`evicted = 0` |

### 3.3 复用（不重定义）

| 名字 | 正本 |
|---|---|
| `CacheKey` / `CacheEntry` / `CacheStats` | P7A `types.zig`（本文件 re-export） |
| `CacheStore` / `invalidate` | P7B `store.zig`（本文件 re-export） |
| `ModuleId` / `ModuleState` / `LazyLoader` | Phase 3 `src/module_loader/loader.zig`（经 Phase 2 `src/module_resolver/types.zig`） |
| `ModuleGraph` | Phase 4 `src/dependency_graph/module_graph.zig` |
| `stateIsTraversable` 的口径（loaded / analyzed 可参与） | Phase 4 `src/dependency_graph/types.zig`（本文件只沿用口径，不 import 该符号） |

### 3.4 所有权要点

- `summarizePlan` 的所有权（任务书二选一，本文件选静态拼接）：返回指向文件级静态缓冲区（`summary_buf`，512 字节）的借用切片；调用方如需久存请自行复制；连续两次调用后一次覆盖前一次；非线程安全；摘要只有 4 个数字，最长约 140 字节，512 字节的缓冲区在事实上不会溢出，溢出时退化为一条固定短句（不断言、不报错）。
- `ReusePlan` 存一份调用方传入的 arena 分配器（`allocator` 字段，与 `ReachabilityReport` / `Convergence` 同款），`deinit` 用它释放；调用方只调一次 `ReusePlan.deinit`，不得再单独释放其中任一切片。
- `content_of` 回调返回的内容只借用、不拥有，至少在当次 `CacheKey.compute` 调用期间有效；未知模块返回空串 `""`，不得返回 null（签名为非可选 `[]const u8`）。

## 4. 与 Phase 2 / Phase 3 / Phase 4 / Phase 5 / Phase 6 的关系表

| Phase | 本模块消费什么 | 本模块不碰什么 |
|---|---|---|
| Phase 2（模块解析器） | `ModuleId` 的身份口径（包名 + 规范路径）与 `ModuleState` 四态 | 定位器、import 说明符解析、shim 机制 |
| Phase 3（懒加载器） | `LazyLoader.modules` 表（权威状态）与 `LazyLoader` / `ModuleEntry` 类型；只读 | loader 的状态机迁移、钩子、工作表；不调 `loadRoot` / `markLoaded` / `markAnalyzed` |
| Phase 4（依赖图） | `ModuleGraph`（失效闭包的反向依赖边；节点状态）与 `stateIsTraversable` 的口径 | 图的 add / topoSort / reachableFrom；不建图、不改图（图 append-only，本模块也不产新图） |
| Phase 5（可达性） | 无直接调用（可达性分析与收敛不在增量计划的路径上） | `analyzeAll` / `converge` / `ReachabilityReport` |
| Phase 6（DCE） | 无直接调用；两者都消费同一批图，但不互相调用（DCE 决定哪些符号不进产物，本模块决定哪些模块不用重编） | `eliminate` / `prune` / `verifyPruned` / `PrunedGraph` |

导入语义按用户已定第三种：符号级与模块级都支持，底层统一符号依赖图。本模块不展开模块级边（失效闭包走模块级边即可；符号级失效粒度是后续 Phase 的事，见 §6 第 4 项）。

## 5. 合并对齐（协调 agent 合并时核对，C1–C6 + M1–M6）

P7A / P7B 与 P7C 并行编写，各写不同新文件，无文件冲突；facade 与本 MANIFEST §5 由协调 agent 合并时写。以下对齐点是 P7C 按任务书给定的名字写下的假设，合并时按 P7A / P7B 落盘逐项核对，裁决如下：

| # | 出入 | 裁决（合并时） |
|---|---|---|
| C1 | `CacheKey.compute` 的形状 | 以 P7A 落盘为准：形状与假设一致（纯函数，四参），`driver.zig` 第 ④ 步调用点无改动 |
| C2 | `validateAll` 的形状与返回值 | 以 P7B 落盘为准：不是 `bool`，而是 `(store, compiler, plugin, opt, allocator) Allocator.Error![]ModuleId`（返回失配模块列表）；改 `driver.zig` 第 ① 步这一处调用点，取回的列表立即释放（见 M2） |
| C3 | `invalidate` 是自由函数还是方法、参数是否含 `loader` | 以 P7B 落盘为准：自由函数，参数与假设一致，无 `loader` 参数；`driver.zig` 第 ② 步调用点无改动 |
| C4 | 命中查询是 `lookup` 还是 `contains` | 以 P7B 落盘为准：`lookup(key) ?CacheEntry` 方法存在，第 ④ 步调用点无改动 |
| C5 | `CacheStats` 的字段名 | 以 P7A 落盘为准：字段为 `hits` / `misses` / `invalidated` / `evicted`（皆 `u64`），无 `total`；改第 ⑤ 步这一处结构体字面量为 `evicted = 0`（见 M3） |
| C6 | `driver.zig` 的 `content_of` 参数位置 | 任务书参数表未列 `content_of`，只定“函数签名里用 `content_of` 回调取内容”；P7C 把它放在 `opt_level` 之后、`allocator` 之前（内容来源挨着版本参数，分配器仍居末，合全仓惯例）。合并时位置不变 |
| M1 | P7B 假设 `CacheError` 含 `OutOfMemory`，P7A 落盘只有三项（不含） | 以 P7A 落盘为准：`store` / `evictModules` / `invalidate` / `validateAll` 的错误集一律改为 `std.mem.Allocator.Error!T`（与 Phase 6 `prune` 同款口径：唯一可达错误是 OutOfMemory）；`dependents()` 的 GraphError 在 `invalidate` 内按 NodeNotFound 跳过 / OutOfMemory 直传 / 其余 unreachable 收窄（CycleDetected / InvalidState 在 dependents 路径上不可达） |
| M2 | 版本失配是否需要专用字段（§7.3 第 2 项） | 合并时已决：Phase 7 不补字段。`validateAll` 失配的条目已从库里删掉（记入 `store.stats.invalidated` 累计），受影响的模块在第 ④ 步自然全不命中、进 rebuild；失配只表现为命中率 0%。`ReusePlan.invalidated` 仍只含第 ② 步的闭包 |
| M3 | `CacheStats` 无 `total` 字段（C5） | 第 ⑤ 步字面量按落盘写 `evicted = 0`（本次计划不淘汰条目）；`ReusePlan` 与 `planIncremental` 的文档注释同步改掉 `total` 的表述 |
| M4 | facade 由谁写、公开名清单 | 协调写 `src/incremental_cache.zig`，薄 re-export 15 个公开名（见 §2）：`CacheFormatVersion` / `CacheKey` / `CacheEntry` / `CacheError` / `CacheStats` / `ModuleId` / `ModuleState` / `CacheStore` / `invalidate` / `validateAll` / `ReusePlan` / `planIncremental` / `summarizePlan` / `LazyLoader` / `ModuleGraph` |
| M5 | P7B 写时 `types.zig` 尚未落盘（静态核对 MISS）、P7C 写时 `types.zig` / `store.zig` 两处 import 悬空 | 合并后三文件同落主副本，5 处 import 全部解析（见 §8）；悬空只是并行编写期的预期跨 agent 依赖，不是新增的意外悬空 |
| M6 | MANIFEST §5 留对齐假设、§2 文件清单写的是假设行数、§6 第 1 项与 §7.3 第 2 项待定稿 | §5 按落盘裁决定稿（C1–C6 + M1–M6）；§2 按合并后行数修正（store.zig 282→289，driver.zig 311→321）；§6 第 1 项更新为已解决；§7.3 第 2 项按 M2 定稿 |

## 6. 已知缺口（只记，不擅自改结构）

1. C1–C5 合并时已逐项核对落盘并定稿（见 §5）：`types.zig` / `store.zig` 两处 import 在合并后全部解析，5 处跨文件 import 均无悬空（见 §8）。并行编写期的悬空只是预期的跨 agent 依赖，不是新增的意外悬空。
2. 第 ② 步的状态门以模块图的节点状态为准（`invalidate` 在图内设门）；若 loader 在建图（`fromLoader`）后继续推进（`markLoaded` / `markAnalyzed`），图里状态可能比 loader 旧，门可能读到旧状态。调用方须在计划前重建图或同步状态；本文件不替调用方同步（同步策略是后续接线 Phase 的事）。
3. `summarizePlan` 只产纯文本，无结构化（JSON）输出；不逐个列出复用 / 重编模块（要看明细读 `plan.reuse` / `plan.rebuild`）。
4. 失效粒度是模块级：`invalidate` 的闭包按模块走反向依赖；某模块内单个符号变化仍使整个模块及其反向依赖失效。符号级失效粒度（只重编受影响的符号）是后续 Phase 的事，需符号图（Phase 4）与内容哈希的符号级拆分，今天没有。
5. `content_of` 的内容来源由调用方定：可以是 `loader.sourceOf(id)`（已读源码）、也可以是重新读盘的内容；两者不一致时（loader 读后文件又被改）键的含义由调用方负责，本文件不校验内容新鲜度。
6. `ReusePlan` 不携带缓存条目本身（只有模块 id）：调用方取复用产物时须凭 `CacheKey` 再向 store 查询一次（或凭 `reuse` 里的 id 另行取回）。是否把条目随计划一起带出，由后续接线 Phase 定。
7. `string/` 无 prelude 仍是缺口（模块级边回退到域模块本身，Phase 2 已知缺口；本模块的失效闭包沿用该口径）。

## 7. 待裁决（原样登记，不做定夺）

### 7.1 Phase 6 RESULT §6 的 10 项（原文编号）

1. P6A 取舍：符号节点插入顺序无法从原图 `HashMap` 恢复（按边首次出现 → reachable → prunable → 排序防御剩余复制）；新图节点表同样是 `HashMap`，节点顺序本身不可观测。
2. P6A 取舍：两处防御性保留（`reachable` 有、原图无的符号仍复制；既不在 `reachable` 也不在 `prunable` 的原图符号保守保留、不计入 `removed_symbols`）；`module_only` 模块若原先不在模块图里，以 `.unloaded` 态补建。
3. P6A 取舍：`prune` 的 `GraphError` → `Allocator.Error` 用 `oomOnly` 收窄（其余分支 `unreachable`）。
4. Phase 5 RESULT §6 实际为 **9 条编号**（非任务书所称 8 项）——P6C 核对发现，第 1–6 条为 Phase 5 自身项，第 7 条为 Phase 4 的 12 项合订指针，第 8 条为 Phase 3/2/1 合订指针，第 9 条为 `build.zig` 注册；MANIFEST §7.1 照原文 9 条编号登记，并在节首写明了该差异，未按“8 项”裁剪原文。
5. module_only 模块的符号后续引用发现策略（Phase 5 §6 第 3 项，未决）。
6. `PruneReason` 是否需要第三档（Phase 5 §6 第 4 项，未决）。
7. 是否需要结构化（JSON）报告输出（Phase 5 §6 第 5 项，未决；`summarizeDce` 只产纯文本）。
8. 保留规则判定逻辑仍缺（Phase 5 §6 第 6 项）：`macro_expanded` / `reflective` / `dynamic_call` / `exported` 四条规则只登记文本，判定需解析器 / 后端能力（宏展开表、反射元数据、动态分发表、导出表），今天没有；本阶段不发明判定逻辑。
9. Phase 5 的 9 项（RESULT §6；MANIFEST §7.1 按原文出处登记，未做定夺）、Phase 4 的 12 项、Phase 3 的 7 项、Phase 2 的 10 项、Phase 1 的 8 项——原样登记，未做定夺。
10. `build.zig` 注册：`dce`（与 Phase 2/3/4/5 同样）未接 build；注册是后续 Phase / 协调方的事。

### 7.2 Phase 5 的 9 项、Phase 4 的 12 项、Phase 3 的 7 项、Phase 2 的 10 项、Phase 1 的 8 项（合订指针）

以上 48 项已原样登记于 `src/dce/MANIFEST.md` §7.1–§7.5（Phase 5 的 9 项见该文件 §7.1；Phase 4 的 12 项见 §7.2；Phase 3 的 7 项见 §7.3；Phase 2 的 10 项见 §7.4；Phase 1 的 8 项见 §7.5），出处分别为 Phase 5 / 4 / 3 / 2 RESULT §6 与 `src/module_resolver/MANIFEST.md` §6。本文件不再转抄全文——转抄会产生第二份正本、随时间漂移；此处只记指针与条数，未改写、未删减、未做定夺。核对时以 `src/dce/MANIFEST.md` §7 为准。

另：`incremental_cache` 同样未接 `build.zig`（与 Phase 2/3/4/5/6 同样）；注册是后续 Phase / 协调方的事。

### 7.3 Phase 7 自身（本文件新立，只记、待协调裁决）

1. 对齐点 C1–C5（见 §5）：P7A / P7B 落盘后逐项核对，调用形状以落盘为准。
2. 版本失配是否需要专用字段：合并时已决（M2）：Phase 7 不补字段。`validateAll` 失配的条目已从库里删掉（记入 `store.stats.invalidated` 累计），受影响的模块在第 ④ 步自然全不命中、进 rebuild；失配只表现为命中率 0%。`ReusePlan.invalidated` 仍只含第 ② 步的闭包。是否在接线 Phase 补字段，由后续 Phase 定。
3. 第 ② 步状态门的权威来源：目前以模块图节点状态为准（见 §6 第 2 项）；是否改为以 `loader.modules` 表的权威状态为准（`invalidate` 多一个 `loader` 参数，或 driver 在闭包后二次过滤），由协调定。
4. `ReusePlan` 是否携带缓存条目本身（见 §6 第 6 项）：目前只带模块 id；调用方取复用产物须再查一次 store。
5. 失效粒度是否下探到符号级（见 §6 第 4 项）：目前是模块级。

## 8. 未做的事（按任务硬约束，另行安排）

- **无构建/测试结果可报**：未跑 `zig build`、未跑 `zig test`、未跑任何测试。ast-check 只是 parse-only 静态检查；本文件的类型正确性（含跨文件调用形状，合并时只靠读代码逐项核对签名，未经编译）留待构建/测试验证阶段。
- 静态验证（盒上实测，合并后对主副本）：`zig ast-check` 4/4 通过（facade + 3 新文件，Zig 0.17.0，盒上 `/usr/local/bin/zig`）；行数 39 / 216 / 289 / 321，全部 ≤700；`@import` 悬空自查：4 新文件全部 import 均已解析，0 悬空（P7B 写时的 `types.zig` MISS 与 P7C 写时的 2 处悬空均已由合并消除）；facade 15/15 公开名；sa_std/ @import 总数 1113、内部悬空 0、全仓悬空 617，0 新增悬空（见 RESULT.md §3）。
- 未接线：`planIncremental` 只定义调用顺序与契约，未接入任何真实调用方；`build.zig` 未注册 `incremental_cache`（Phase 2 的 module_resolver、Phase 3 的 module_loader、Phase 4 的 dependency_graph、Phase 5 的 reachability、Phase 6 的 dce 同样未接 build）。
- 未修任何 bug：包括 Phase 1 的构建断裂（`no @extern declarations parsed from sa_std/growvec.sai`）、sci 7ecae6d 的 double-free、任务 79 报告的 6 项基线缺陷、Phase 1–6 的待裁决项。
- 未动 `sa_std/`、`tests/`、`build.zig*`；未合 main；未动 `/content/sa_all/sci` 原仓。
- 未编译、未缓存任何真实模块：`ReusePlan` 只产出计划，复用与重编的执行是调用方的事；是否把计划结果写回构建流程、由哪个后端消费，是后续接线阶段的事。
- 钩子均为空实现（Phase 3 遗留）：parse / type-check / analyze 未接任何解析器（与本模块无关，照现状记录）。
