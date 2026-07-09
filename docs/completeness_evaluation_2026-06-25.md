# sci (SA Core) 深度完成度评估

> 评估日期：2026-06-25
> 方法：22 个评估 agent（侦察 + 子系统精读 + 对抗验证）。其中验证类 agent 实际 build 了 `sa` 二进制（zig-out/bin/sa, 18MB, v0.0.3.3）并端到端跑了 referee trap、`sa run`、`sa build-exe/wasm/bc2sa`、`sa fetch`。`zig build test` 全量因链接 LLVM-14 编译超 9 分钟未跑完，相关结论标注为「读代码确认」。
> 所有行号引用对应评估当时的源码树。

## 总评

sci 是三层栈（sci / sla / sla_ecs）中最成熟的一层，**核心约 75–80% 完成度**。安全内核（Referee）已达生产级且零 stub，是整个技术栈可信度的基石。扣分集中在：stdlib 无泛型、手写 WASM 后端是死代码、bc2sa 是原型、所有机器码后端依赖外部 LLVM/zig-cc。

“自给自足工具链”这一表述**过誉**：verifier + IR 层确实自包含，但每条机器码/wasm 路径都是 `zig cc` 的前端。

## 子系统逐项

### Referee 所有权验证器 — 生产级 ✅（栈中最强一环）

真正实现的 O(1) 位掩码仿射状态机，**无任何 stub / TODO / placeholder-panic**。

- **五符号契约 `= & ^ ! *`**：`CapPrefix{by_value, borrow(&), move(^), raw(*)}` 枚举（`common/instruction.zig:6-11`）；实参符号映射 `referee/call.zig:38-55`；签名 `!` 可失败标记 `common/signature.zig:188-190, 290-296`；调用点 prefix-vs-契约强制 `verifier.zig:3045-3065`。
- **位掩码状态模型**：`CapabilityMask` u16 11 态（uninitialized/active/locked_read/locked_mut/consumed/borrow_view/ffi_borrow/untracked/fallible/immutable/interior_ptr），17 行规范真值表 `common/capability.zig:3-15, 66-84`；扁平并行数组 O(1) 查找 `referee/table.zig:20-54`。
- **LOCKED_READ / LOCKED_MUT 区分**：`startReadBorrow`(table.zig:172-193)、`startMutBorrow`(195-215) 拒绝二次 mut（DoubleMutableBorrow）和 mut-over-shared（ReadWriteConflict）；live 验证器 `setBorrowState`(verifier.zig:2134-2146)、`.borrow` dispatch(2794-2823)。
- **分支合并对账**：标签快照 `captureLabelSnapshot`(verifier.zig:706)；回边要求精确兼容 `snapshotStatesCompatible` 否则 trap PhiStateConflict；前向边 lattice 合并 `mergeJoinMask/mergeJoinStates`(667-704)。
- **跨函数验证**：`parseCall/validateCall`(call.zig:219-313) 检查 arity + 逐参能力前缀；可失败返回需 `?`/`try` 传播(verifier.zig:3172-3196)。
- **use-after-move / double-free / leak**：move 消费(active→consumed)，后续读写 move 触发 use_after_move；函数出口扫描所有 live 寄存器查泄漏(3297-3317)。
- **FFI/unsafe**：`raw_cast/assume_safe/assume_borrow` 受 `@ffi_wrapper` 上下文门控(illegal_unsafe_context, 2870-2887)。

测试：~67 个树内单测含 PBT（call.zig:389, verifier.zig:5142），含真 `expectEqual/expectError`。

**已确认的 trap 行为**（agent 实跑）：`return_after_move.sa` → UseAfterMove(trap 1009, mask 8)；`read_write_conflict.sa` → ReadWriteConflict(trap 1011, mask 17)。

**审计要点 / 可深化处**：
- `mergeJoinMask`(673-690) 有三条 inline `PATCH` 注释放宽 join lattice（Active↔Uninitialized→Uninitialized、Active↔Untracked、Untracked↔Uninitialized）以抑制 while-loop / if-without-else 的 PhiStateConflict。这是有意的「健全性 vs 人体工学」权衡，已在代码中文档化，但**确实拓宽了前向边的接受集**，值得正式论证其健全性边界。
- 间接调用 `call_indirect` **跳过能力前缀契约检查**(call.zig:280-282 提前返回)。callee 动态时合理，但比直接调用弱。
- **「完整内存安全验证」这一表述过誉**：`assume_safe`(2874-2878) 把 `.active` 掩码授予裸指针**零校验**——是程序员断言；`$...$` native 块内容**从不分析**，只消费命名寄存器。Referee 在「安全子集」上健全，unsafe 操作被隔离在语法可见标记（`@ffi_wrapper`、`*`、`assume_*`、`$...$`）之后——「无静默逃逸」成立，但「完整」不成立。

### flattener + layout — 生产级 ✅

真正接进 live 编译管线（`cli.zig:4253` 调 `flattenFileWithContextAndPackages`；`layout.compute` at `cli.zig:6159`）。

- `flattener.zig`（7294 行，55 test 块）：两级 source/expanded 缓存 + mtime 校验、REP 展开带真预算 + 逐迭代卫生重命名、IF/ELSE 编译期条件选择、`[MACRO]/EXPAND` 定义+调用、`PRINT!/FORMAT!/STRINGIFY!/ENV!` 展开、def-dict 常量折叠（含完整递归下降算术求值器）、符号 interning、逐行指令分类（含 jmp/br/br_null/call/call_indirect/label/return）、quote-aware forbidden-construct 检测。
- `layout.zig`（396 行）：32/64 位目标的 struct 字段 offset/size/align/padding，输出 text/json/dict/debug-macro，全测试通过。

**缺口**：layout 仅处理基本类型字段的 struct，**无 enum/union/嵌套-struct 布局**（`layout.zig:64-79`）；def-dict 算术求值器**无除法/取模**（仅 `+ - *`，`def_dict.zig:256-283`）。

### 后端（LLVM / WASM / interp / bc2sa）— 异质，整体 partial

四个后端成熟度差异极大：

- **LLVM 后端**（`emit_llvm_llvmc.zig` + `.shim.c`）= **生产级**。Zig 构 C-struct IR，2091 行 LLVM-C shim，246 个 `LLVMBuild*`，完整 `SA_OP_*` dispatch（alloc/load/store/binop/jmp/br/call/atomic/cmpxchg/fence/try/release），多线程 worker-pool emit + DCE。原生 **和** wasm 目标都走它。
- **解释器**（`interp.zig`, 2330 行）= **扎实**。接进 `sa run`，几乎所有 InstKind 含真原子语义、可失败流、vtable 间接调用。缺口：`.native` 逃逸和 extern/FFI 返回 Unsupported；inline 测试仅 4 个。
- **llvm2sa / bc2sa**（`llvm2sa.zig`, 917 行）= **原型**。**不解析 bitcode**，shell 出 `llvm-dis-14` 取文本 IR 再字符串解析。仅标量整数子集；无 phi/switch/select/float/vector/struct。`phi` → SA-CLI-018 unsupported。LLVM18 的 .bc → SA-CLI-017（只装了 llvm-dis-14），**版本脆弱**。
- **`emit_wasm/`**（encoder/opcodes/sections, ~1400 行）= **死代码 ⚠️**。完整 LEB128 编码器 + 全 8 个 wasm section（且是最佳测试的部分，10 个 inline 测试），但**没有任何源文件 import 它**：不在 `lib.zig` 导出、不在 `build.zig`、grep `@import("emit_wasm")` 零命中。实际 `build-wasm` 走 `executeBuildWasm`(cli.zig:6080) → LLVM 后端 wasm_compat=true → `zig cc -target wasm32-wasi`。README 架构图里的「WASM Emitter」框误导。

### pkg manager + workspace + 插件 + 测试框架 — 扎实 ✅

安全意识强，在年轻工具链里属于罕见的成熟度。

- **解析**（`pkg/resolver.zig`）：分层 resolveImport（std → 相对路径 → 插件接口根 → 本地 `sa_vendor/` → 全局 `~/.sa/pkg/<id>@<ref>` 缓存，mmap 只读）；确定性树哈希（排序相对路径 + NUL 分隔 + 文件字节）+ pinned sha 校验；symlink 逃逸拒绝；预编译产物排除。8 个 tmpDir 测试。
- **Lockfile**（`pkg/lock.zig`）：原子 temp+fsync+rename 写、幂等、stale-hash 清除、拒绝 `~/.sa`、`/etc/sa` 等全局路径。
- **审计/CI**（`audit.zig/ci.zig`）：扫描 `@sys_*` 原语 → 能力映射 → 风险评分 → text+JSON 报告；双轨 verify（source-sha + 未授权原语拒绝 + 高风险阻断）。
- **Fetch**（`fetch.zig`）：硬化环境 `git clone`（GIT_TERMINAL_PROMPT=0/GIT_ASKPASS=/bin/false/depth-1）；**显式测试断言 postinstall.sh 不被执行**(493-527)。
- **插件**（`plugins.zig`, 155KB）：C-ABI PluginDescriptor、dlopen 加载、per-plugin 权限策略（env/fs/net/process）、install 管线（拒绝裸 .so、要求源码、symbol-smoke/extern-conflict/policy 校验、写 sap.lock + permissions.lock）。
- **测试框架**：从已验证签名发现测试 → 编译为原生可执行 → 每测试子进程隔离运行（SA_TEST_NAME）→ worker-pool 并行 + 缓存。

**缺口**：remote（纯 URL 无 path）插件依赖未实现(plugins.zig:1965)，但 url-bearing 的会 fetch；无 semver 约束求解（精确 pin 查找，by design）；`sa pkg ...` 子命令不存在（命令是顶层 fetch/install/audit）。

### sa_std 标准库 — 扎实 ✅（但是 u64 单态混编）

92 个 .sa 源文件、~3157 个 `[MACRO]` 定义、340KB Zig 运行时（359 导出 fn）+ pthread C shim。

- **容器全实**（非 stub，含增长 + checked 算术 + 移除/搜索/排序）：Vec、VecDeque（circular buffer）、HashMap（open-addressing 倍增）、HashSet、BTreeMap/Set、BinaryHeap、Slice(132KB)、String(116KB)、num(259KB)。
- **同步**：Mutex（atomic xchg 自旋 + 指数退避）、RwLock、Once、mpsc 有界 channel；Atomics 152 macros 全宽度覆盖。
- **线程**：真 OS 线程 THREAD_SPAWN/JOIN/DETACH → pthread。
- **IO**：full Cursor/IoSlice。

**核心限制（vs 真 stdlib）**：
- **无泛型**：每个容器硬编码 u64/8 字节元素（VEC_*_U64、hashmap u64 values）。`docs/std_missing.md` 自己诚实列出。
- **无惰性迭代器**：所有 adapter（map/filter/zip）EAGER 物化进 Vec<u64>；Vec/VecDeque 无 iter()/into_iter。
- **锁是自旋/睡眠**，非 futex/阻塞；**无 park/unpark、无 Condvar、无 Barrier**。
- **trait 系统全程缺席**；Box/Rc/Arc/Cell 只持 in-place u64 payload，非泛型 T；无 u128/i128。

`docs/std_missing.md` 的诚实度值得表扬——准确枚举了 scope 限制而非过度宣称。

### lowerer.zig — 孤儿原型 ⚠️

零调用点（grep 全树仅自引用），不在 `lib.zig` 导出。所有控制流（jmp/br/call/label 等）`return LowerError.UnsupportedInstruction`(253-318)。regName/operandText 用截断占位 fallback（reg id≥10 全渲染为裸 `r`，会冲突）——明显是 toy。注意：**「控制流降级到 jmp/br」在本代码库里不存在**——REP 是编译期 unroll、IF 是编译期分支选择、jmp/br/label 是手写 SA 原语被 classifier 透传。

## 自报 vs 实测的偏差清单

| 自报 | 实测 |
|---|---|
| progress.md「Current progress: 100%」 | 实为逐 low-risk slice 100%，撇看像整层完成 |
| README「Referee ≤2500 行可审计 Zig」 | 真实 `verifier.zig` **5951 行**；`referee.zig` 22 行转发壳 |
| 架构图「WASM Emitter」 | 手写 `emit_wasm/` 是**死代码**；实际走 LLVM+zig cc |
| 「自给自足工具链」 | 后端全是 `zig cc` 前端，依赖 zig 0.14.1 / llvm-dis-14 / git |
| 「完整内存安全验证」 | 安全子集健全；FFI/native/assume_safe 靠程序员断言 |

源码树有大量 aspirational 叙事文档（SAX_*.md、talk.md 329KB、tasks.md 132KB、Agents.md 185KB），是「过度宣称完成度」的典型气味，但核心代码本身扎实。

## 建议深化优先级（待审核）

1. **正式论证 mergeJoinMask 三条 PATCH 的健全性边界** —— 安全核心唯一的「软」处，最值得形式化。
2. **stdlib 泛型化** —— u64 单态是 stdlib 距「真 stdlib」最大的鸿沟，且会限制 sla 上层能写什么。
3. **决策 emit_wasm/ 去留** —— 要么接进管线做真原生 SA→WASM，要么删掉/明确标注为实验，停止误导。
4. **bc2sa 直读 bitcode + phi/switch 支持** —— 当前 llvm-dis-14 文本解析既脆弱又受限。
5. **间接调用的能力契约检查** —— call_indirect 当前完全跳过。
