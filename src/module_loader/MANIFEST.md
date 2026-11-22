# sa-lazy-loader — 模块清单（Std 模块化 Phase 3，P3A：LazyLoader）

> 提案：`~/workspace/goals/sci-sa-optimize/files/STD-MODULARIZATION-PROPOSAL.md`
> （§2 懒加载流程与四种模块状态、§3 两层依赖图、§4 三个独立模块、§7 第三种导入语义）。
> Phase 2 结果：盒上 `src/module_resolver/`（types / locator / spec / closure）与
> `src/module_resolver/MANIFEST.md`。
> 工作仓：盒上 `/content/kit-work/sci2-agentP3A`（分支 `sa-optimize`，基线 `7adf9695`）。
> 本任务只新增 `src/module_loader/` 下文件，不改任何现有文件，不合 main、不 push。

## 1. 模块目的

`sa-lazy-loader` 是提案 §4 三个独立模块之二（Phase 3，Lazy Module Loading）的核心：
按需加载模块（定位 → 读文件 → 抽 @import → 工作表循环），并推进四态状态机
`unloaded → loading → loaded → analyzed`。

它**不是**解析器、类型检查器、语义分析器（那三件事以钩子槽位留出，见 §4），
**不是**依赖图（Phase 4）、**不是**可达性裁剪（Phase 5）。
本文件只做加载驱动与状态机，产出的 `modules / order / edges / cycles` 是后续 Phase 的输入。

## 2. 文件分工

| 文件 | 职责 | 行数上限 |
|---|---|---|
| `src/module_loader/loader.zig` | LazyLoader：模块表、状态机、loadRoot + 工作表循环、shim 跟随、SymbolEdge、三个钩子槽位 | ≤700 |
| `src/module_loader/MANIFEST.md` | 本清单 | — |

不设独立的 `types.zig`：loader 专有类型只有 `LoaderError`、`ModuleEntry` 与三个
钩子函数指针类型；其中钩子类型引用 `LazyLoader` 本身，拆文件会造成循环 import，
故全部放在 `loader.zig` 内。`ModuleState` / `ModuleId` 等 Phase 2 类型一律复用，
不重定义。

## 3. 公开 API 表

| 名字 | 来源 | 用途 |
|---|---|---|
| `ModuleState` / `ImportKind` / `ResolveError` / `ImportSpec` / `ModuleId` / `ModuleInfo` / `SymbolEdge` | `../module_resolver/types.zig`（re-export） | Phase 2 共享类型，复用 |
| `Locator` | `../module_resolver/locator.zig`（re-export） | 模块定位器，按值持有 |
| `CycleRecord` | `../module_resolver/closure.zig`（re-export，形状复用） | 一条导入环：`cycle_path: []ModuleId`、`entry: ModuleId` |
| `LoaderError` | 本文件 | `ResolveError` 全集 + 新增三变体：`InvalidStateTransition`（非法迁移）、`MalformedShim`（shim 无转发行）、`ReadFailed`（定位成功后文件读不出；OutOfMemory 仍按原样返回） |
| `ModuleEntry` | 本文件 | 模块表条目：`info: ModuleInfo`、`state: ModuleState`、`source: ?[]const u8`（已读源码，arena 所有） |
| `ParseHook` / `TypeCheckHook` / `AnalyzeHook` | 本文件 | 钩子函数指针类型（见 §4） |
| `noopParseHook` / `noopTypeCheckHook` / `noopAnalyzeHook` | 本文件 | 默认空实现（也是三个钩子槽位的初始值） |
| `LazyLoader` | 本文件 | 懒加载器（见 §5 方法表） |

## 4. 钩子（延迟点）

parse / type-check / analyze 的真正实现不属于本文件。三个槽位是 `LazyLoader` 的
公开字段，调用方直接赋值替换（`loader.parse_hook = myParse;`），不赋值即默认空实现。

| 钩子 | 类型 | 调用点与顺序 |
|---|---|---|
| `parse_hook` | `ParseHook = *const fn (*LazyLoader, ModuleId, []const u8) LoaderError!void` | 模块到达 `loaded` 态时（`markLoaded` 内，先置状态再调）。第 3 参为 loader 读到的模块源码（只借用，不拥有；未经 loader 读取时为空串） |
| `type_check_hook` | `TypeCheckHook = *const fn (*LazyLoader, ModuleId) LoaderError!void` | 模块到达 `analyzed` 态时（`markAnalyzed` 内，先置状态再调），顺序在 analyze 钩子之前 |
| `analyze_hook` | `AnalyzeHook = *const fn (*LazyLoader, ModuleId) LoaderError!void` | 模块到达 `analyzed` 态时（`markAnalyzed` 内），顺序在 type-check 钩子之后 |

约定：钩子失败不回滚迁移（状态保持新状态、错误向上传）；钩子内不得重入
`loadRoot` / `drainWorklist`（无重入保护）；钩子只读 loader 状态或登记自己的产物。

## 5. LazyLoader 方法表

| 方法 | 用途 |
|---|---|
| `init(allocator, locator)` | 构造。`allocator` 为调用方传入的 arena 分配器（见 §6）；`locator` 按值持有 |
| `deinit()` | 只释放容器本身的表 / 缓冲；字符串由调用方统一释放 arena；不释放 locator |
| `count()` | 模块表条目数 |
| `stateOf(id) ?ModuleState` | 查询状态；未登记返回 null |
| `entryOf(id) ?ModuleEntry` | 查询条目（值拷贝）；未登记返回 null |
| `sourceOf(id) ?[]const u8` | 查询已读源码；未登记或未读取返回 null |
| `register(info)` | 登记已定位模块（幂等，先登记的为准），状态 `.unloaded`，不读文件 |
| `addRoot(spec)` | 定位 + 登记入口（与 ClosureBuilder.addRoot 同款），不读文件、不展开 |
| `markLoading(id)` | `unloaded → loading`；表里无此模块报 `ModuleNotFound`，状态不对报 `InvalidStateTransition` |
| `markLoaded(id)` | `loading → loaded`，调 parse 钩子；非法迁移同上 |
| `markAnalyzed(id)` | `loaded → analyzed`，依次调 type-check 与 analyze 钩子；非法迁移同上 |
| `loadRoot(spec) LoaderError!ModuleId` | 定位入口 → 压栈 → 排空工作表直至闭包，返回入口规范 id。已 loaded / analyzed 的根直接返回；正在 loading 的根直接返回（外层排空会完成它） |
| `analyzeAll()` | 把已加载（loaded 态）的全部模块按 `order` 顺序逐一推进到 analyzed 态 |
| `drainWorklist()` | 排空工作表（显式栈循环，见 §7） |
| `pushFrame(info)`（私有） | 读文件 → 抽 @import → shim 截断 → 帧入栈 → 置 loading |
| `emitEdge(importer, spec, info)`（私有） | 每定位到一个模块发一条 SymbolEdge（与 ClosureBuilder.emitEdge 同口径） |
| `recordCycle(entry)`（私有） | 记一条 CycleRecord（栈上从 entry 到栈顶的连续段） |

公开字段（供后续 Phase 读）：`allocator`、`locator`、`modules`（HashMap）、
`worklist`（帧栈）、`edges`、`cycles`、`order`、`parse_hook` / `type_check_hook` /
`analyze_hook`。

## 6. 所有权 / arena 规则（与 Phase 2 的 A8 一致）

- 调用方传入一个 arena 分配器，loader 用它分配一切：定位产物串、源码、import 串、
  边符号串、环路径。loader 不逐个追踪释放——`deinit` 只释放容器本身，字符串由
  调用方统一释放 arena。
- 例外：工作表循环内每轮的 `ImportSpec` 在迭代结束即 `deinit`（与 ClosureBuilder.build 同款）。
- 与 ClosureBuilder 的一处不同：本 loader 的帧出栈时不释放 `source` / `imports`
  （arena 规则）；ClosureBuilder 的帧出栈时逐个释放（它不假定 arena）。

## 7. 工作表循环与状态机不变量

- 显式栈工作表（与 ClosureBuilder 的栈同构）：栈顶帧的 import 处理完 → 该模块
  `loading → loaded`（调 parse 钩子）→ 记入 `order` → 出栈；每条 import 行：
  解析 → 定位 → 发边 → 目标状态分流（`loading` 记环不递归；`unloaded` 压栈；
  `loaded` / `analyzed` 跳过）。
- 不变量：`loading ⟺ 在工作表栈上`。`pushFrame` 先读文件、抽 import、帧入栈成功后
  才置 loading；入栈失败时状态仍为 unloaded，不留半截状态。
- `analyzed` 不在工作表循环里推进：加载只到 `loaded`；分析由 `analyzeAll` /
  `markAnalyzed` 单独驱动（Phase 2 的 `analyzed` 占位语义到此为止：本 loader 的
  `analyzed` 只有在钩子接线后才代表真正的分析完成；钩子为空实现时 `markAnalyzed`
  只推进状态，不做分析——见 §8 缺口）。
- 出错后的状态：排空途中若某步失败，loader 停在局部完成状态（部分模块仍为 loading
  且帧在栈上），实例视为脏状态：调用方应丢弃重建，不得继续用它加载。

## 8. 已知缺口（只记，不修）

| 缺口 | 现状 | 影响与后续 |
|---|---|---|
| 钩子均为空实现 | parse / type-check / analyze 三个槽位默认 noop，未接任何解析器 | `markLoaded` / `markAnalyzed` 只推进状态，不做真正的解析与分析；钩子实现是后续 Phase / 现有解析器接线的事 |
| 相对路径 import 无基准目录 | `../sync/rwlock.sal` 等在排空时报 `InvalidImportSpec` / `ModuleNotFound`（Phase 2 已知缺口，定位器无 base_dir 参数） | 含相对 import 的模块加载会在首个相对 import 处失败（`loadRoot` 报错、实例变脏）；基准目录解析是后续 Phase 的事，本 loader 不私自拼基准目录 |
| shim 转发只认域裸写 / 包限定写法 | shim 转发串经正常工作表路径解析；`..` 形式的转发同样命中相对路径缺口 | 域裸写（如 `collections/vec/vec.sa`）与包限定转发可跟随；`..` 转发跟随失败 |
| `string/` 无域 prelude | 模块级边 `import sa_std.string` 的 `to` 指向该域模块本身（Phase 2 已知缺口，`locatePrelude` 报 `ModuleNotFound` 时的回退） | 与 ClosureBuilder.emitEdge 同口径；是否补 prelude 由后续 Phase 定 |
| 边不去重 | 同一 import 行出现两次会发两条边 | 如实记录；去重是 Phase 4 依赖图的事 |
| 无 build 接线 | `build.zig` 未注册本模块（任务禁改现有文件）；Phase 2 的 `module_resolver` 同样未接 build | 验证只跑 `zig ast-check` 与 @import 悬空核对；构建接线是后续 Phase / 协调方的事 |
| 单线程 | 工作表循环是串行的（提案 §5：先把依赖语义弄正确，再考虑并行） | 与 ClosureBuilder 一致 |

## 9. 静态验证口径（本任务）

- 基线：盒上 `/content/kit-work/sci2-agentP3A`，分支 `sa-optimize`，HEAD `7adf9695`，工作区干净。
- 本任务不跑 `zig build`、不跑 `zig test`、不修任何 bug；只新增 `src/module_loader/` 下文件。
- 验证：`/usr/local/bin/zig ast-check` 逐个新文件通过；grep 核对新文件里的 `@import`
  无悬空（相对路径以 `src/` 为基准）；每 Zig 文件 ≤700 行。

## 10. 合并补充（Phase 3 协调 agent 合并时，基线 7adf9695）

三 agent 并行编写，合并时文件无冲突（各写不同文件；locator.zig 只有 P3C 动过，
只加 `locateRelative` 方法，未改现有方法行为）。本节补齐 P3B/P3C 与 facade 的
清单，并记录合并对齐项。

### 10.1 文件分工（续 §2）

| 文件 | 职责 | 行数 |
|---|---|---|
| `src/module_loader/cycle.zig` | 循环检测与诊断：CyclePolicy、LoaderState、detectCycle、checkCycle、cyclePathString、reportCycle（P3B） | 309 |
| `src/module_loader/policy.zig` | 加载策略与裁决：LoaderPolicy、Disambiguation、SpellingRule、UnknownExtensionRule、三项待裁决结论（P3B） | 382 |
| `src/module_loader/wiring.zig` | flattener 接线适配：ModuleTable、ImportCheck、adoptMaps/restoreMaps（P3C） | 143 |
| `src/module_loader.zig` | facade：薄 re-export，不含逻辑（协调 agent 合并时写） | ~70 |
| `src/flattener/expandimportsinto.zig` | 接线：核心改名 `expandImportsIntoTable`，走 ModuleTable；旧签名 `expandImportsInto` 暂留作薄适配器（P3C） | 698 |
| `src/flattener/importexpansion.zig` | 接线：`ImportExpansion` 的 seen/active 字段改为 `modules: ModuleTable`（P3C） | 629 |
| `src/module_resolver/locator.zig` | 只加 `locateRelative(spec, base_dir)` 方法（P3C）；现有方法行为未改 | 477 |
| `src/pkg/resolver.zig` | 接线：`sa_std/` 分支改走 `parseImportSpec` → `Locator.locate`（P3C） | 699 |

### 10.2 合并对齐（M1–M5）

| # | 出入 | 裁决（合并时） |
|---|---|---|
| M1 | P3B 的 `LoaderState` 取 `*const AutoHashMap(ModuleId, ModuleState)` + `[]ModuleId` 栈投影；P3A 的 `LazyLoader.modules` 是 `HashMap(ModuleId, ModuleEntry)`（条目含 state 字段） | 两者类型不同，**本次不写适配器**：未经编译验证的适配代码风险大于收益。cycle.zig 注释里已给接线示例；真正的 LoaderState↔LazyLoader 适配是后续接线 Phase 的事，只记不修 |
| M2 | P3C 的 `ModuleTable` 是独立薄适配，不依赖 P3A 的 loader.zig；flattener 现走 ModuleTable 而非 LazyLoader | 保持现状：ModuleTable 是过渡层，`states` 覆盖层只记 flattener 经手的状态。flattener 直接用 LazyLoader 是后续统一步骤，本次不强行合一 |
| M3 | P3B 裁决消歧优先文件（spec.zig 两处 `.both => error.AmbiguousImport` 改为 `.symbol`，接线指引写在 policy.zig 文件头）；P3C 的 resolver 用 `fallbackModuleSpec` 把 AmbiguousImport 以 kind=`.module` 重试、由 Locator 确定性裁决 | 两者都保留：`.both → .symbol` 的分类器改动是语义改动，需单独一步做，本次不改 spec.zig；resolver 的 fallback 是现行状态下的安全网，不冲突。跟进项见 §10.3 |
| M4 | P3C 的 `expandImportsInto` 旧签名适配器暂时保留（`injectimportedfile.zig:484` 的调用点不在本次可改范围） | 保留适配器；该调用点迁到表核心后即可删除适配器。`expandImports` 的公开签名未变 |
| M5 | P3A 的 loader 仍命中相对路径缺口（loadRoot 路径无 base_dir）；P3C 已实现 `Locator.locateRelative` | loader 后续接线时改走 `locateRelative`；本次不改 loader.zig，只记 |

### 10.3 Phase 2 待裁决项在本 Phase 的状态

| # | Phase 2 §6 项 | Phase 3 状态 |
|---|---|---|
| 1 | 消歧规则（文件 vs prelude） | 已裁决：优先文件（policy.zig，实测支撑）；spec.zig 的 `.both` 分支改动未接线，列为跟进项 |
| 2 | 斜杠/点分是否统一 | 已裁决：不统一，各走各的（policy.zig）；重开条件：点分或斜杠裸写在真实代码中出现 |
| 3 | 相对导入基准目录 | 已实现：`Locator.locateRelative(spec, base_dir)`（P3C，定位器内解析方案）；loader 侧接线为跟进项（M5） |
| 4 | 中间层 shim 是否扩展搜索 | 已裁决：不扩展（P3C 实测：6 个中间 shim 本身落在旧域级路径上，第 1 步规范试探直接命中） |
| 5 | `sa_std/<非域名>` 是否试顶层 shim | 已裁决：先试顶层 shim（按现状口径，P3C） |
| 6 | 版本 `@` 后缀与操作符是否采纳为正式语法 | 未决：本次未动，留待后续 Phase |
| 7 | 未知扩展名口径 | 已确认合适（policy.zig）；spec.zig 文件头一处不精确表述的修正已记录，接线时顺手改注释 |
| 8 | `extractImportStrings` 不带行号 | 未决：环诊断用入口路径 + 行号 0（cycle.zig）；行号支持需改返回形态，留待后续 |
| 9 | Phase 1 的 8 项待裁决 | 原样登记，未做定夺（见 module_resolver/MANIFEST.md §6） |
| 10 | 盒子主机名 | 现为 `bd4991109185`，与任务所述一致，不影响工作 |

### 10.4 已知缺口（合并后全貌，只记）

- 钩子均为空实现（P3A §8）；`markAnalyzed` 只推进状态。
- `LoaderState`↔`LazyLoader` 无适配器（M1）；`ModuleTable`↔`LazyLoader` 未统一（M2）。
- `injectimportedfile.zig:484` 的旧签名调用点未迁移（M4）；经旧 map 路径（`.sai` 接口展开）的模块在 `states` 里查不到。
- `reportCycle` 的 detail 受 ErrorContext 128 字节缓冲截断（既有行为，未改）。
- 无 build 接线：`build.zig` 未注册 `module_loader`（Phase 2 的 module_resolver 同样未接）；验证只跑 `zig ast-check` 与 @import 悬空核对。
- ast-check 是 parse-only：四文件的类型正确性未经 `zig check`/`zig build` 验证，需后续接线 Phase 在构建中验证。
- 不修：growvec.sai 构建断裂、7ecae6d double-free、任务 79 的 6 项基线缺陷、Phase 1/2 的待裁决项（除本节已裁决者外）。
