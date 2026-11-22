# sa-module-resolver — 模块清单（Phase 2，Import Resolver）

> 提案：`~/workspace/goals/sci-sa-optimize/files/STD-MODULARIZATION-PROPOSAL.md`
> （§2 懒加载流程与四种模块状态、§3 两层依赖图、§4 三个独立模块、§7 第三种子导入语义）。
> Phase 1 结果：`~/workspace/sci2-opt-std/RESULT.md`（§5 静态验证口径、§6 留给 Phase 2 的接口）。
> 工作仓：盒上 `/content/kit-work/sci2`（分支 `sa-optimize`，HEAD `08d1fe2f`）；
> 本模块文件由 P2A/P2B/P2C 在各自盒上副本中编写，协调 agent 合并进主副本（只新增、不改已有文件；合并对齐见 §7）。

## 1. 模块目的

`sa-module-resolver` 是提案 §4 三个独立模块之首：**模块定位、import 解析、版本解析**。
它回答“一个 `@import` 串对应文件系统上的哪个模块、是哪种导入（符号级还是模块级）、
带不带版本”，并能从入口 import 出发算出依赖闭包（哪些模块要加载、按什么顺序、
之间有什么边、有没有环）。

它**不是**懒加载本体（Phase 3）、**不是**依赖图（Phase 4）、**不是**可达性裁剪（Phase 5）。
Phase 2 只定义结构与状态流转，不接线：闭包构建器产出的 `states/order/edges/cycles`
是后续 Phase 的输入。

## 2. 文件分工

| 文件 | 职责 | 行数上限 |
|---|---|---|
| `src/module_resolver.zig` | facade：薄 re-export（仿任务 28 的 shim 模式），不含逻辑 | ≤700 |
| `src/module_resolver/types.zig` | 共享类型：`ModuleState`、`ImportKind`、`ResolveError`、`ImportSpec`、`ModuleId`、`ModuleInfo`、`SymbolEdge`（P2A 编写） | ≤700 |
| `src/module_resolver/locator.zig` | 模块定位：`Locator`、`domains` 表、`normalizeSpecifier`、`probeExtensions`、`findPrelude`（P2A 编写） | ≤700 |
| `src/module_resolver/spec.zig` | import 串解析：`parseImportSpec`、`classifyImport`、`canonicalize`、`VersionSpec`、`parseVersionSpec`、`extractImportStrings`（P2B 编写） | ≤700 |
| `src/module_resolver/closure.zig` | 依赖闭包构建器：`CycleRecord`、`ClosureBuilder`（P2C 编写，即本任务） | ≤700 |
| `src/module_resolver/MANIFEST.md` | 本清单 | — |

## 3. 公开 API 表

| 名字 | 来源 | 用途 |
|---|---|---|
| `ModuleState` | types.zig | 四态枚举：`unloaded`（只知道路径，尚未读取）、`loading`（正在读取和解析）、`loaded`（AST/模块内容已加载）、`analyzed`（名称解析、语义分析已完成；Phase 2 为占位态） |
| `ImportKind` | types.zig | 导入种类：符号级 `.symbol`（`import sa_std.io.print`，只加载 print 及其依赖）与模块级 `.module`（`import sa_std.io`，加载 io 模块，但只把实际使用的符号编入产物）；两种都支持，底层统一转换成符号依赖图（提案 §7） |
| `ResolveError` | types.zig | 定位/解析失败的错误集（`locate`、`parseImportSpec` 的返回错误） |
| `ImportSpec` | types.zig | 一条 import 的解析结果：`raw`（原文）、`kind`、`package`（包名，借用 path 首段；相对路径为空串）、`path`（归一化斜杠路径）、`symbol`（符号级为符号名，借用 path 末段去扩展名；模块级为 null）、`version`（请求版本原文）；`raw/path/version` 为 owned，释放用 `deinit` |
| `ModuleId` | types.zig | 模块身份：可 AutoHash 的值类型（约定见 §7 对齐清单 A1） |
| `ModuleInfo` | types.zig | `locate` 的返回：`id: ModuleId`（`package` 恒为字面量 `"sa_std"`）、`state`（刚定位为 `.unloaded`）、`fs_path`（磁盘路径）、`kind`、`is_shim`；`id.path` 与 `fs_path` 为定位器分配的字符串，按 §7 A8 的 arena 规则统一释放 |
| `SymbolEdge` | types.zig | 一条依赖边：`from`/`to`（ModuleId）、`symbol: ?[]const u8`（符号级为符号名，模块级为 null）、`kind: ImportKind`；符号级与模块级 import 统一落成边（提案 §3 两层依赖图的输入） |
| `Locator` | locator.zig | 模块定位器（持 sa_std 根等定位上下文，`locate` 方法） |
| `domains` | locator.zig | 域表（P2A/P2B 核对：任务简报称 19 域；见 §8 未决项） |
| `normalizeSpecifier` | locator.zig | import 串规范化 |
| `probeExtensions` | locator.zig | 扩展名探测（`.sa` / `.sal` / `.sla` / `.sai` 的定位顺序） |
| `findPrelude` | locator.zig | 取某域 prelude 的相对路径（如 `io/prelude.sa`，调用方所有）；无 prelude 的域（string/）或未知域名返回 null；模块级定位用 `Locator.locatePrelude`（返回 ModuleInfo） |
| `parseImportSpec` | spec.zig | 把原始 import 串解析成 `ImportSpec` |
| `classifyImport` | spec.zig | 判定 import 串是符号级还是模块级 |
| `canonicalize` | spec.zig | import 串/路径规范化 |
| `VersionSpec` | spec.zig | 版本规约类型 |
| `parseVersionSpec` | spec.zig | 解析版本规约串 |
| `extractImportStrings` | spec.zig | 行级文本扫描：从模块源码中抽出全部 `@import` 原始串；返回的每个字符串与外层切片均为 owned，调用方须逐个 free 再 free 切片 |
| `CycleRecord` | closure.zig | 一条被发现的导入环：`cycle_path: []ModuleId`（按发现顺序的环路径，首元素即 entry，末尾不重复 entry）、`entry: ModuleId`（环入口） |
| `ClosureBuilder` | closure.zig | 依赖闭包构建器：字段 `allocator`、`locator: Locator`、`states`（ModuleId → ModuleState）、`order`（后序拓扑顺序）、`edges: []SymbolEdge`、`cycles: []CycleRecord`；方法 `init`、`addRoot(spec)`（登记入口 import）、`build()`（工作表算法直至闭包）、`stateOf(id)`（查询）、`deinit`（释放） |

## 4. 依赖关系

| 依赖 | 用途 | 说明 |
|---|---|---|
| `std`（Zig 标准库） | 容器与分配：`AutoHashMap`（states 表）、`array_list.Managed`（order/edges/cycles/roots/stack）、`meta.eql`（栈上环入口比较）、`Allocator.dupe/alloc/free` | 无第三方依赖 |
| `sio` | 文件存在性判断与读取：locator 侧存在性判断与扩展名探测、closure 侧读文件都走仓库既有 `sio` 封装（Zig 0.17 的 `std.fs` 已无 Dir/cwd；`std.fs.path.*` 与 `std.fs.max_path_bytes` 仍有效）；closure 读文件与 `src/llvm2sa/translate.zig` 同款 `sio.cwd().readFileAlloc(allocator, path, limit)` | `sio` 是仓库对新版 `std.Io` 的封装，不是新依赖 |
| Lexer / Referee / Backend | — | **独立**：本模块不依赖词法器、裁判器（Referee）、后端（提案 §4）。`analyzed` 态的真正内容（名称解析、语义分析）在 Phase 3 才与这些部分接线 |
| flattener | — | **不依赖、不替换**：见 §5 关系表 |

## 5. 与现有机制的关系表

| 现有机制 | 位置 | 关系 |
|---|---|---|
| `seen_paths` 去重 + `error.ImportCycle` | `src/flattener/expandimportsinto.zig`（约 110 行处） | **并存，不替换**。flattener 用 `seen_paths` 按规范路径去重，用 `active_paths`（递归栈）检测环并立即报 `error.ImportCycle`，是真正展开 `@import` 的地方。闭包构建器用同样的“在栈上 = loading 态”判定，但遇到环只记一条 `CycleRecord`、不递归、不报错。环是否合法由语义规则定（提案 §2），Phase 3 决定；Phase 2 不改变 flattener 的任何行为 |
| `pkg/resolver.zig` | `src/pkg/resolver.zig` | **底层复用关系**。`sa_std/` 前缀由它解析；`Locator.locate` 在 Phase 3 接线时应复用其解析规则，而不是另起一套前缀解析。Phase 2 的 `Locator` 只定义接口，不改 `pkg/resolver.zig` |
| `.sai`/`.sal` 自动注入 | `src/flattener/injectimportedfile.zig` | **互补**。导入 `.sa` 时同目录同 stem 的 `.sai`/`.sal` 由它自动注入。`.sai`/`.sal` 是伴生文件而非 `@import` 目标，**不作为闭包节点**；闭包构建器只扫描定位到的模块文件本身的 `@import` 行。Phase 3 懒加载若需把伴生文件当节点，另行决定 |
| re-export 机制 | SA 语言现状 | 已确认：SA 的 re-export 就是 1 行 `@import` 转发文件（无 `pub use`）；`@import` 为文本包含 + 按规范路径去重。prelude 聚合各子目录 prelude；`.sa`/`.sal` shim 用相对路径、`.sla` shim 用 `sa_std/` 前缀，两种写法均有先例（Phase 1 RESULT §6） |
| `.sla` 与 prelude | Phase 1 结论 | `.sla` 不进 `.sa` prelude（全仓零个 `.sa` 文件 import `.sla`，不存在 `prelude.sla`）；db/crypto/tree_sitter 的 prelude 只聚合 SA 侧公共面，`.sla` 按完整新路径单独 import |

## 6. Phase 1 的 8 项待裁决（原样登记，照现状、不由本任务定）

1. `jwt.sla` 归属：现放 `db/core/`，本质是 crypto 应用，候选 `crypto/`。
2. `compress` 归属：现放 `crypto/encoding/`，候选 `encoding/` 域。
3. `crypto.sai` 拆分（哈希/随机数/口令等六类）与 `redis.sla` 的 RESP 编解码/TCP 客户端拆分。
4. 是否把 `db/crypto/testing/tree_sitter` 的 prelude 纳入顶层 `sa_std/prelude.sa`（F 报告待定项；Phase 1 未纳入）。
5. F 域“其他”文件：`oop.sal`→建议 core、`sse.sla`→建议 http、`ctx.sla`→建议 task，均保留顶层原位未移动；`dtls` 只记不碰。
6. `core/future/`（future/task/waker）是否抽出到 task 域（A 报告未定）。
7. `.sai` shim 机制：全仓零个 `.sai` 文件含 `@import`，.sai shim 未经验证；E 的 13 个 `.sai` 无 shim 是本次唯一 breaking change（demos/tests 的 8 处引用已在合并修正中改到新路径）。
8. E 的缺陷 D1：`net/socket/net.sal` 里 `SA_NET_ERR_ACCESS` 与 `SA_NET_ERR_TIMEOUT` 同值 4（疑似真 bug，只记未修）。

（另见 Phase 1 RESULT §6：core → sync 11 边、core → collections 2 边为已知既存层级倒置，Phase 1 未修；`core/sa_core.sa` 第 36–37 行重复 import `../sync/rwlock.sal` 两次。）

## 7. 合并对齐（协调 agent 合并时核对，已落实）

三 agent 并行编写时对接口的假设有出入，合并时以 P2A 的 types.zig/locator.zig
为准改 spec.zig/closure.zig（P2B 自述“以 P2A 为准改本文件”；P2C 的清单要求
协调方核对）。以下为合并后的约定：

- A1. `types.ModuleId` 为值类型，可 AutoHash（`ModuleId.Context`）；`types.ModuleInfo`
  含 `id: ModuleId`、`state`、`fs_path: []const u8`（磁盘路径）、`kind`、`is_shim`——
  没有 `path` 字段，读文件用 `fs_path`。`ModuleId.package` 恒为字面量 `"sa_std"`
  （locator 的 makeInfo 不借用 spec 字符串）；`id.path`/`fs_path` 为定位器分配的
  字符串，按 A8 的 arena 规则统一释放，builder 不逐个释放。
- A2. `Locator.locate(self: Locator, spec: ImportSpec) ResolveError!ModuleInfo`
  （self 按值传；ClosureBuilder 按值持有 locator 副本）。
- A3. 模块级边的 `to` 取法：调 `locator.locatePrelude(domain)` 得 ModuleInfo，
  用其 `.id`；无 prelude 的域（如 string/）报 ModuleNotFound 时 `to` 保持为域
  模块本身。自由函数 `locator.findPrelude(allocator, domain)` 只返回 prelude
  相对路径（`?[]u8`），不直接返回 ModuleId。
- A4. `spec.extractImportStrings(allocator, source) ![][]const u8`，返回的每个
  字符串与外层切片均为 owned（`allocator.dupe`）；帧弹出/出错时须逐个 free
  再 free 切片（closure.zig 的 pushModule/build/deinit 三处）。
- A5. `spec.parseImportSpec(allocator, raw: []const u8) ResolveError!ImportSpec`；
  `ImportSpec` 含 `raw/kind/package/path/symbol/version`（package 与 symbol
  借用 path 的子串；无 `domain` 字段——域名由 closure.zig 的 `domainOf(spec)`
  从 path 取）。歧义时 parseImportSpec 透传 `error.AmbiguousImport`。
- A6. `ImportKind` 只有 `.symbol` 与 `.module` 两态（无 `.ambiguous` 变体——
  歧义是错误，不是 kind）；`SymbolEdge` 含 `from/to/symbol/kind`。
  `closure.zig` 的 `emitEdge` switch 为穷尽 switch。
- A7. 文件读取走仓库既有 `sio` 封装（与 `src/llvm2sa/translate.zig` 同款调用）。
  Zig 0.17 的 `std.fs` 已无 Dir/cwd（只剩 path 等），spec.zig 的探针同样
  走 `sio`，不用裸 `std.fs`。
- A8. 所有权/arena 规则：解析产物字符串（spec 的 raw/path/version、ModuleInfo
  的 id.path/fs_path、extractImportStrings 的串）均由调用方分配器分配，
  Phase 2 不逐个追踪释放；预期用法是调用方用 arena（或短命分配器）跑一次
  构建后统一释放。`ClosureBuilder.deinit` 只释放自身 dup 的东西（边符号串、
  环路径、帧的 source 与 imports 串）；不释放 locator（调用方拥有）。
  例外：build() 循环内每轮的 spec 在迭代结束即 `deinit`（此时 locate/emitEdge
  已用完它，且不借用它的串）。
- A9. 域数 19 vs 23：任务文本“19 个域”为笔误（其枚举的域名本身就是 23 个）；
  以磁盘实际为准，domains 表 23 条，核对 23/23 通过。不是设计决策，不阻塞。

## 8. 已知缺口

| 缺口 | 现状 | 影响与后续 |
|---|---|---|
| `string/` 无域 prelude | `sa_std/` 23 个子目录中 22 个有 `prelude.sa`，唯独 `string/` 没有（只有 `string/`、`builder/` 子目录与顶层 `str.sla`）；见 §9 验证输出 | 模块级边 `import sa_std.string` 的 `to` 指向该域模块本身（`locatePrelude` 报 ModuleNotFound 时的回退），不是 prelude。string 域 prelude 是否补建由后续 Phase 定，Phase 2 不新建 |
| `sa.mod` 无版本字段 | `sa_std/sa.mod` 只有 `package "sa_std"` 一行；“依赖、版本、feature、ABI-release 字段仍不受当前 manifest 语法支持”（文件内原话） | `VersionSpec` / `parseVersionSpec` 在 Phase 2 只有解析形态，无清单可对；版本语义是后续 Phase 的事 |
| `analyzed` 态为占位 | `build()` 里 `loaded` 之后直接置 `analyzed`，中间无名称解析/语义分析 | Phase 3 在 `loaded → analyzed` 之间插入真正的名称解析/语义分析；此前 `analyzed` 只表示“本构建器已完成对该模块的发现工作”，不得理解为语义分析已完成 |
| 相对路径解析责任在 caller | 闭包构建器把行内原始串原样交给 `parseImportSpec` 与 `locator.locate`，不自己拼基准目录 | `locate` 是否接 `base_dir` 参数（复用 `pkg/resolver.zig` 的 `resolveImport(allocator, deps, base_dir, import_path, options)` 形态）是合并/Phase 3 的决定；`sa_std/` 内大量相对 import（如 `../sync/rwlock.sal`）未经 `locate` 前是未验证路径 |
| `extractImportStrings` 不带行号 | 只返回 specifier 串，不返回所在行 | `parseImportSpec` / `locate` 失败时报错无法指到导入行；Phase 3 诊断若需行号，须改 `extractImportStrings` 的返回形态 |
| 边不去重 | 同一 import 行出现两次（如 `core/sa_core.sa` 重复 import `../sync/rwlock.sal`）会发两条边 | 如实记录；去重是 Phase 4 依赖图的事 |
| `domains` 表 19 域 vs 实际 23 子目录 | 任务简报称 domains 表 19 域；`sa_std/` 实际有 23 个子目录（`alloc collections core crypto db encoding ffi fmt http io marker mem net num os string sync task testing text thread time tree_sitter`） | **已解决**：合并时以磁盘实际为准，domains 表按 23 条落实（locator.zig 表头注释已记“19”为任务文本笔误）；核对脚本 23/23 通过。不是设计决策，不阻塞 |
| `order` 为后序拓扑序 | `order` 在模块全部 import 发现完毕后才追加（依赖先于使用方）；发现顺序（先序）未单独存表 | 环内成员在 `order` 中相邻，严格拓扑序不存在是环的固有性质，不是 bug |

## 9. 静态验证口径（Phase 1 基线，HEAD `08d1fe2f`）

- `sa_std/` @import 总数：**1113**；sa_std/ 内部悬空：**0**；全仓 @import 悬空总数：**617**（demos 611 + tests 6），0 新增。
- 验证脚本 `~/workspace/check_phase2.py`（本地，不进仓；盒上副本在 `/tmp/check_phase2.py`）：核对新文件行数（每 Zig 文件 ≤700）、`zig ast-check` 逐文件通过、domains 表与实际目录对照、sa_std/ @import 总数与悬空数与本基线对照。脚本只打印数字与 PASS/FAIL，不改任何文件。
- 本任务不跑 `zig build`、不跑 `zig test`、不跑任何测试；不改任何已有文件；不合 main、不 push、不 commit。
