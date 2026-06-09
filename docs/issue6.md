SA 缓存与单元测试框架评估及改进计划（issue6）

评估日期：2026-06-09
评估方式：逐条通读 src/cli.zig（项目缓存）、src/flattener.zig（import 缓存）、tests/unit_framework/runner.zig（测试框架），并对照 docs/design.md §1.10 / docs/test_performance.md。
约束：本文件只评估、给建议，不改任何代码。所有结论带 file:line 证据。

## 当前实现状态（2026-06-09）

已完成并提交：
- CACHE-1：source-tree digest 进程内 mtime/size fast path，未变化时避免重复全树读盘算内容哈希。
- IMP-2：flattener import source cache 支持显式 stable roots，CLI 为 `tests/unit_framework/support` 配置稳定根。
- TEST-3：拆分 `std_string_vec_macro_surface.sa` 为 string / slice+vec / vec 三个可调度文件。
- CACHE-2：source-tree hashing 通过 flattener `readImportSourceFile` 复用同一 import-source cache。
- TEST-4：unit-framework runner 从 `.sa` 源文件自动生成测试预期，去除大段硬编码 pass 列表。
- IMP-1 低风险切片：`.sa_cache/test` 写入 `test-metadata.json`，`sa test` cache hit 时可跳过前端 discovery/list/filter。
- IMP-1 进一步切片：新增进程级 expanded-import fragment cache，缓存已展开的 import 文本片段、传递文件 mtime/size、layout metadata，并通过 `SA_EXPANDED_IMPORT_CACHE_MAX_ENTRIES=N` 支持 opt-in LRU；当前仅缓存无 package identity/hash 的 std/稳定根片段，尚不是完整 `FlattenResult`/verify IR cache。
- IMP-1 重定位基础：新增已测试的 symbol-id remap helper，可将 `Instruction` 中的 `reg`/`symbol`/`label`/`func` operand 从缓存片段的 `SymbolTable` ID 映射到消费者 `SymbolTable` ID；另新增 `FunctionSig.param_ids` / `reg_ids` 风格 immutable ID slice 的 clone-remap helper，以及完整 `FunctionSig` 深拷贝+ID remap+entry offset helper。raw_text 名称碰撞策略和 def/const 合并仍待完整设计。
- IMP-3：通过 `SA_IMPORT_CACHE_MAX_ENTRIES=N` 提供 opt-in LRU；默认 CLI 路径保持无界 borrowed source cache 以保短命进程性能。
- CACHE-HYGIENE：通过 `SA_SOURCE_TREE_HASH_CACHE_MAX_ENTRIES=N` 提供 opt-in source-tree digest cache LRU；默认 CLI 路径保持无界进程内 digest cache。
- PERF-ALLOC：`scanSource` 与 import expansion 输出/行元数据已按源大小和行数预分配，减少 flattener 热路径 ArrayList 增长分配。

仍未完成 / 不适合半实现：
- IMP-1 完整 per-module frontend IR 持久缓存（flatten + 宏展开 + verify 产物复用）。当前代码的 import 展开先合并为全局 source，再统一 scan/emit；完整实现需要模块边界、SymbolTable ID 重定位、def_dict/const 合并和 cache-on/off 等价测试。当前 metadata cache 只是安全切片，不等同于完整 IR cache。

---

## 0. 统一根因：缓存只做到「产物级」和「源码字节级」，从未做到「前端 IR 级」

SA 目前有两层缓存，但**都不缓存 flatten + 宏展开 + verify 的结果**。而 sa_std 的展开与验证，正是单元测试变慢的主因。证据链：

1. `sa test <file>` 每次都先算 project build key：`computeProjectBuildKey(..., hash_source_tree=true)`（src/cli.zig:5499），它内部调用 `hashResolvedSourceTree`（src/cli.zig:4036-4075），把整棵导入树（含它引用的全部 sa_std）**逐文件 realpath + loadSource + 逐行 classifyLine + resolveImport** 一遍，只为算出缓存键。
2. 即使命中缓存（`projectCacheHit`，src/cli.zig:5504），**前端仍要完整再跑**：test_performance.md:211 明说「does not bypass frontend compilation, because test discovery and filtering still require current metadata」。缓存只省了 LLVM emit/link。
3. 因此每个测试文件：sa_std 导入树**被读两遍**（算键一遍 + flatten 一遍），**展开 + 验证一遍**；约 50 个 macro surface 文件各付一次。这就是 `std_string_vec_macro_surface.sa` 48s、`unit-framework` 约 3m 的来源（test_performance.md:185-193）。

下面三块的改进，最终都指向「把前端 IR 也纳入内容寻址缓存」这一根本动作（IMP-1）。其余是低风险的即时收益项。

---

## 一、编译缓存（.sa_cache）

设计正确性无可挑剔：内容寻址键含编译器版本（src/cli.zig:4097）、全量源码树内容哈希（4056-4059）、debug/release/incremental/wasm flags（4103-4106）；命中前校验 artifact/output/manifest 三件套非空（4360）；有 manifest.json sha256 校验 + 过期清理 + `sa cache clean`（test_performance.md:195-211）。问题都在**为正确性付出的 I/O 代价**。

### CACHE-1：缓存命中也要把整棵导入树读盘算键

现状（证据）：
- `hashResolvedSourceTree`（src/cli.zig:4036-4075）无条件对入口及每个传递依赖做 `realpathAlloc` + `loadSource`（全文件读）+ 逐行 `classifyLine` + `resolveImport`，即使本次马上就要命中缓存。
- 对一个引用大半个 sa_std（91 模块）的文件，单是算键就要读几十个文件。

为何是问题：
- 这是「即使命中也付全树读盘」的固定成本，违背缓存「命中应接近零成本」的预期；在测试/CI 这种高频小编译场景被放大。

改进方案（两级键）：
1. 第一级用 (入口 + 树) 的 **mtime + size 指纹** 作为快速键。import 缓存里已用过这招（`cachedImportStillValid`，src/flattener.zig:247-250），可直接借鉴。
2. 仅当 mtime/size 指纹未命中（文件确实动过）时，才回退到现在的 sha256 全量内容哈希。
3. 快路径下命中是「stat 几十个文件」而非「读几十个文件」，I/O 量级下降。

验收标准：
- 对未改动的项目，连续两次 `sa build`/`sa test` 的第二次，键计算阶段不再出现全树 `loadSource`（可用 strace/计数器验证）；
- 改动任一源文件后仍正确失效并重编（现有 cache 单测不回归）。

工作量：中（1–2 天）。风险：低（mtime 不可信时回退内容哈希，正确性不变）。

### CACHE-2：算键路径与 flatten 路径各自独立读解析导入树

现状（证据）：
- 算键用的是 `pkg_resolver.resolveImport`（src/cli.zig:4066），**绕过** flattener 的进程级 `import_source_cache`（src/flattener.zig:148-156）。
- 于是同一次 build 内，sa_std 至少被「解析导入」两遍：算键一遍、真正 flatten 一遍。

改进方案：
- 让算键路径复用 flattener 的 `import_source_cache`（或抽一个共享的 resolved-import-tree 缓存，两边都查），一次 build 内每个导入只解析一次。

验收标准：单次 build 中对同一 sa_std 文件的 resolveImport/读盘次数从 ≥2 降到 1。
工作量：中（1–2 天）。风险：低。

---

## 二、import 缓存（flattener 进程级）

已落地的优化都到位且值得肯定：进程级 + mutex（src/flattener.zig:148-149）、mtime+size 失效（247-250）、命中借用源码不再克隆（`owned_source=null`，215-231）、tracing 默认静默（`SAASM_TRACE_IMPORTS`，158-162）。

### IMP-1（决定性，最大价值）：只缓存源码字节，未缓存展开/验证结果

现状（证据）：
- `ImportSourceCacheEntry.source` 存的是磁盘原文（src/flattener.zig:142），命中只省磁盘 I/O；每个导入者仍要重新 flatten + 宏展开 + 之后再被 verify。
- 这正是 §0 根因，也是 test_performance.md 反复点名的「repeated SA import expansion」(136、167、193)。

改进方向：把缓存升级为缓存 **per-module 的前端产物（FlattenResult 片段）**，键 = `source_sha256` + 编译器版本。基础设施半就位：`package_source_sha256` 已记录（src/flattener.zig:69）、`FlattenResult` 已是结构化产物（289）。

可行性与核心难点（已读符号编号逻辑后给出）：
- `SymbolTable.intern`（src/flattener/symbol.zig:24-34）是**全局单调 intern 表**：`id = names.items.len`，按名字去重。
- 因此一份缓存模块里指令操作数的 `.reg / .symbol / .label`（均为 u32，见 src/flattener.zig:1034-1038 标签 intern）都是相对**该模块自己符号表**的 id。
- 直接把缓存模块的指令拼进消费者的指令流会**id 串号**。所以跨文件复用必须做一次**重定位（id remap）**：
  1. 缓存条目同时保存「该模块的 names 表」（id → 名字）。
  2. 拼接时遍历缓存指令的每个 symbol/label/reg 操作数，用其名字在消费者 `SymbolTable` 里重新 `intern`，把旧 id 替换成新 id。
  3. 这是 O(指令数 × 操作数) 的一遍线性重映射，远便宜于重新词法+宏展开。
- 注意点：
  - 标签是函数内可见、按名字 intern 的，需保证不同模块同名标签不串（design §1.10.1 要求「进入每个函数声明时重置寄存器 ID」——确认该重置已实现可降低风险；若寄存器名带函数前缀则天然隔离）。
  - def_dict（宏字典）与 const_decls 的合并需要同样的去重/冲突检测（同名宏不同体应报错而非静默覆盖）。
  - 缓存键必须纳入「影响展开结果的上下文」：被展开时可见的常量、`#def`、`std_root`、编译器版本——否则同源不同上下文会误命中（参考 import 缓存键已包含的上下文项，src/flattener.zig:169-197）。

验收标准：
- 一个 build 内多个文件导入同一 sa_std 模块时，该模块只 flatten/展开一次；
- 重定位后产出的指令流与「不走缓存全量展开」逐字节等价（加一条对照测试：cache-on vs cache-off 的 FlattenResult 结构相等）。

工作量：大（1–2 周，重点在 id 重定位 + def_dict 合并 + 上下文键设计）。风险：中（触及前端正确性，必须有 cache-on/off 等价对照测试）。

### IMP-2：缓存候选只认 sa_std，测试 support 文件每次重展开

现状（证据）：
- `isStdImportCacheCandidate`（src/flattener.zig:199-213）只放行 `sa_std/` 及 std_root 下的导入。
- 但 `tests/unit_framework/support/index.sa`（363 个函数，见 .code_index 摘要）在 `tests/` 下，**不是候选**，于是每个测试文件都重新读 + 重展开它。
- 测试套件普遍 `@import "sa_std/..."`（如 std_path_macro_surface.sa:1-3），support/index.sa 又被各套件共享，重复成本明显。

改进方案：把候选根从「硬编码 sa_std」改为「可配置的稳定根集合」（sa_std + 显式声明的测试 support 根），仍按 mtime+size 失效。
验收标准：同一进程内多个测试文件导入 support/index.sa 时只展开一次。
工作量：小（半天–1 天）。风险：低（改动文件后按 mtime 自动失效）。

### IMP-3：进程级缓存无界、不回收

现状（证据）：
- `import_source_cache` 用 page_allocator、进程生命周期内只增不减（src/flattener.zig:148-156, 277）；失效条目还故意保留旧 source 防止悬垂借用（test_performance.md:213）。
- 对短命 CLI、以及「单进程跑 50 文件」的测试 harness，这是**好事**（缓存热）；但对未来 LSP/daemon 长驻进程会内存泄漏式增长。

改进方案：加容量上限 / LRU，仅在长驻场景启用；CLI 短命路径维持现状。
工作量：小。风险：低。优先级低（当前无长驻消费者）。

---

## 三、单元测试框架（变慢的真正原因与解法）

框架架构（tests/unit_framework/runner.zig）：这是一个 Zig test harness，对每个 SA 文件调用 `sa test <file>`：
- 串行（默认 `SA_UNIT_FILE_JOBS<=1`）走进程内 `saasm.cli.executeWithWriters`（runner.zig:121）；
- 并行（`SA_UNIT_FILE_JOBS>1`）spawn 新建的 `sa` 二进制子进程跑每个文件（runner.zig:154-188、221）。
团队已把 unit-framework 从 284s 压到约 1m（test_performance.md:232），方向正确。残留瓶颈如下。

### TEST-1（决定性）：前端无缓存 → 每文件重展开 + 重验证 sa_std

- 即 §0 根因。**IMP-1 的前端 IR 持久缓存一旦落地，本框架受益最大**：约 50 个 surface 文件不再各自重展开/重验证 sa_std。
- test_performance.md:167 自己承认「Shell-level changes alone cannot remove the repeated SA compile/import cost」——所以这必须靠 IMP-1，调度层改不动。

### TEST-2：并行与缓存热度互斥，可被 IMP-1 解开

现状（证据）：
- 进程内串行：import 缓存热（sa_std 字节读一次全程复用），但单核（runner.zig:107-137）。
- 子进程并行：多核，但每个子进程是**冷缓存**——进程级 `import_source_cache` 不跨进程（runner.zig:221 明确说明「process-local import caches are not shared across concurrent SA test files」）。
- 这是一个真实两难：要么热缓存单核，要么多核冷缓存。

解法：IMP-1 做成**磁盘持久**的前端 IR 缓存后，并行子进程能共享磁盘缓存 → **既并行又命中**，两难消失。故 IMP-1 是 TEST-2 的前置条件。

### TEST-3：巨型套件拆分（即时收益）

现状（证据）：
- 单点最慢是 `std_string_vec_macro_surface.sa`（38 个 @test，约 48s，test_performance.md:185；runner.zig:949-993 列出全部 38 条期望）。
- 它在一个文件里串行跑 38 个 test，且整文件是 file-jobs 的最小并行单位。

改进方案：把超大 surface 套件按主题拆成多个独立文件（如 string / vec / slice 各一份），让 `SA_UNIT_FILE_JOBS` 能把它们分到不同核。
验收标准：拆分后该组在多核下墙钟时间下降，且测试总数/通过数不变。
工作量：小（机械拆分 + 同步 runner 期望表）。风险：低。

### TEST-4：约 1300 行硬编码期望串，易脆

现状（证据）：
- runner.zig 把每个 test 名逐条 `expectContains` 硬编码（如 270-535 的 feature_suite、949-993 的 string_vec），全文件 1314 行大部分是这类断言。
- test_performance.md:157 记录过：新增一个 owned CString 测试后，`std_ffi_cstr_macro_surface.sa` 期望计数变化导致整轮在跑到后面慢套件前就失败。

改进方案：弱化为「断言 summary 行（`test result: ok. N passed...`）+ 抽样关键 test 名」，或由套件源自动生成期望清单，去掉逐条硬编码。
验收标准：新增/删改单个 @test 时，runner 不再因计数漂移而需要手改几十行。
工作量：小–中（1–2 天）。风险：低（降低覆盖断言粒度需权衡，可保留对关键 test 名的少量抽样）。

---

## 优先级汇总（按 ROI）

| 编号 | 主题 | 影响面 | 工作量 | 风险 |
|---|---|---|---|---|
| CACHE-1 | 缓存键加 mtime+size 快路径 | 每次 build/test 少一遍全树读盘 | 中 | 低 |
| IMP-2 | 缓存候选扩到测试 support 根 | 测试每文件少重展开 363 函数 | 小 | 低 |
| TEST-3 | 拆分巨型 surface 套件 | 立即多核收益 | 小 | 低 |
| CACHE-2 | 算键与 flatten 共用导入解析 | build 内 sa_std 只解析一遍 | 中 | 低 |
| TEST-4 | 期望清单去硬编码 | 降脆性、减维护 | 小–中 | 低 |
| **IMP-1** | **前端 IR 级持久缓存（展开+验证）** | **三块全部受益，测试提速最大** | 大 | 中 |
| IMP-3 | import 缓存加 LRU（仅长驻） | 防未来 daemon 泄漏 | 小 | 低 |

建议顺序：
1. 先做低风险即时收益：**CACHE-1 + IMP-2 + TEST-3**（各 ≤1–2 天，立刻缩短本地/CI 时间）。
2. 再做 **CACHE-2 + TEST-4**（清理重复 I/O 与脆性）。
3. 并行启动 **IMP-1** 的设计与实现（决定性收益，但需先定 id 重定位 + def_dict 合并 + 上下文键三件事）；IMP-1 落地后 TEST-2 的并行/缓存两难自动解决。
4. IMP-3 等出现长驻消费者（LSP/daemon）再做。

---

附：本次评估读过的关键源码位置
- 编译缓存：src/cli.zig:3977(BuildCacheKind)/4006(ProjectCacheKey)/4036(hashResolvedSourceTree)/4077(computeProjectBuildKey)/4282(projectCacheHit)/5499-5538(sa test 缓存路径)
- import 缓存：src/flattener.zig:138-287(缓存结构/键/校验/存取)/69(package_source_sha256)/289(FlattenResult)/1034-1038(标签 intern)
- 符号编号：src/flattener/symbol.zig:24-48(全局单调 intern 表)
- 测试框架：tests/unit_framework/runner.zig:100-237(串行/并行执行)/245-585(feature_suite)/642-1186(macro surface 套件)
- 性能记录：docs/test_performance.md（团队既有计时与瓶颈分析）
- 设计依据：docs/design.md §1.10（工业级可伸缩性架构）
