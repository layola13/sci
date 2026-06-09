SA 内核评估与改进计划（设计对齐版 · issue5）

评估日期：2026-06-09
评估方式：逐条通读 src/ 真实源码，并对照 docs/design.md 与 docs/faq.md 校准设计意图
约束：本计划只评估、给建议，不改任何代码。所有结论带 file:line 证据。

## 当前实现状态（2026-06-09）

已完成并提交：
- PERF-1：verify 路径预分类，去除逐指令重复 `classifyLine`。
- PERF-2：移除 `regConsumedLater` 出口处重复前向扫描。
- FUNC-1：收窄 verifier 元数据错误兜底诊断。
- FUNC-2：字段级 interior mutable borrow 检查。
- FUNC-3：核心 `catch {}` 吞错审计与清理。
- SEC-1：`sa run` 遇到 unsupported extern/plugin symbol 时输出结构化符号诊断；完整解释器 broker/FFI 桥接仍是大改，未完成。
- SEC-2：本地插件 artifact sha256 加载前校验。
- SEC-3：插件网络权限 URL 静态校验与宽泛通配告警。
- ENG-1：referee LOC lint 统计范围对齐到 `src/referee/ + src/verifier.zig`。
- ENG-2：主仓生成产物清理和 ignore 规则；外部 `/home/vscode/projects/sa_plugins` 按用户要求未纳入本仓处理。

仍未完成 / 不适合半实现：
- PERF-3：verify 与 emitter 函数级异步流水线。该项需要调度、错误优先级和确定性设计，当前未落地。
- SEC-1 完整版：解释器 native plugin/extern broker 一致执行路径。当前只完成明确诊断，不等价于完整运行能力。

---

## 0. 设计对齐前提



本计划的所有改进，都是为了让实现**回到它自己声明的设计目标**，而不是改变设计。判据来自项目自身的指标：

- design §3.3：Referee「单线程吞吐 ≥ 500K 行/秒」、「MVP 核心代码 ≤ 2500 行 Zig」。
- design §1.3.2：「线性扫描：单次前向扫描；唯一例外是 Phi 汇聚点求交集」。
- design §1.10：工业级可伸缩性架构（P0，10k+ 函数）。
- design §1.7.1：外部插件系统真实契约（含已自认的一致性缺口）。

---

## 第一优先级：性能（回到 §3.3 吞吐目标 与 §1.3.2 单次扫描原则）

### PERF-1：消除验证器逐指令重复行分类（违反 §1.3.2 + 拖累 §3.3 吞吐）

现状（证据）：
- verifyBody 主循环对**每一条指令**调用 `const classified = classifier.classifyLine(item.raw_text);`（src/verifier.zig:2161）。
- 而 flattener 阶段已经对同一批 raw_text 做过行分类（src/flattener/line_classifier.zig，1045 行的分类器）。

为何是问题：
- 这是在「单次前向扫描」里夹带了一次**对全部指令的字符串重解析**。在 10k+ 函数工程（design §1.10 针对的规模）上，等于把分类成本付两遍，直接拉低 §3.3 要求的 500K 行/秒吞吐。
- classifyLine 对 raw_text 做的是纯文本扫描，与已压平的 Instruction.kind 信息高度冗余。

改进方案（不改设计，只去重）：
1. 让 flattener 在产出 Instruction 时，把行分类结果（classified kind / 关键字段）作为一个紧凑字段随指令带出（或放进与指令并行的稀疏数组），与 design §1.10.2「稀疏状态注解 / 只存 Delta」的思路一致。
2. verifyBody 读取该缓存字段，仅在缓存缺失（如宏展开产生的合成指令）时回退到 classifyLine。
3. 若不想扩 Instruction 结构，可在 verifyWithOptions 入口处一次性预计算 `[]ClassifiedLine` 数组（O(n) 单遍），verifyBody 用下标取，避免在循环内反复解析。

验收标准：
- big_bench.sa（10001 函数）下 verify_ns（已有 profile 字段，cli.zig:83）下降可测；
- classifyLine 在 verify 路径的调用次数从 O(指令数) 降到 O(合成指令数)；
- 现有 verifier 单测（src/verifier.zig 内 test 块）全绿。

工作量：中（1–2 天）。风险：低（纯缓存/去重，语义不变）。

---

### PERF-2：regConsumedLater 的前向全扫描违反「单次前向扫描」原则（§1.3.2）

现状（证据）：
- 函数出口泄漏检查里，对每个仍活跃的寄存器调用 `regConsumedLater(...)`（src/verifier.zig:2968）。
- regConsumedLater（src/verifier.zig:845-874）从 `function_start_idx+1` 一直**向前扫描到函数末尾**，逐条比对寄存器是否在后续被 move/release/assign/return/try 消费，且每条都跑一次 `callTextMentionsMovedRegister(item.raw_text, reg_name)`（871 行，又是文本扫描）。

为何是问题：
- 出口处每个活跃寄存器扫一遍剩余指令 ⇒ 最坏 O(寄存器数 × 函数指令数) ≈ **函数级 O(n²)**，且内层还叠加文本匹配。
- design §1.3.2 明确只允许「单次前向扫描 + Phi 求交集」这一种非线性例外；这里引入了第二种 super-linear 扫描，正是 §1.10 大规模场景下的隐性瓶颈。

改进方案：
1. 在函数体的那一次前向扫描中，顺带维护一个「后续是否被消费」的信息：对每个寄存器记录其最后一次出现/消费的指令下标（last_use 索引），或维护一个 `consumed_later` 位集，在扫描推进时增量更新。
2. 出口泄漏检查改为 O(1) 查表，彻底删掉 regConsumedLater 的二次扫描。
3. 把 callTextMentionsMovedRegister 的文本判断也并入主扫描时记录的结构化信息（move/call 的操作数已在 Instruction.operands 中，无需再扫 raw_text）。

验收标准：
- 构造一个「单函数、大量活跃寄存器、长尾指令」的用例，验证 verify 时间从二次增长变为线性；
- MemoryLeak / EarlyReturnLeak 相关单测不回归（这两类 trap 依赖该判断）。

工作量：中（2–3 天，需小心保持泄漏判定语义完全一致）。风险：中（触及内存安全判定核心，必须有对照测试）。

---

### PERF-3：补齐 §1.10.5「Referee 验证 ⇄ Emitter 异步重叠」（roadmap 收尾项）

现状（证据，先肯定已完成的部分）：
- §1.10.3 声明级并行**已落地两处**：验证侧 verifyParallel + 按 decl 切 chunk + 每 job 独立 arena（src/verifier.zig:3009/3066/3090）；发射侧 chooseEmitWorkerCount + ParallelEmitJob + arena-per-job（src/emit_llvm_llvmc.zig:854/849/1150）。这是实打实的多核并行，应予肯定。
- §1.10.4 内存直通 llvm-c 也已落地（emit 直接走 sa_llvmc_emit_module_*，无文本 IR 落盘，emit_llvm_llvmc.zig:15-17）。

剩余缺口：
- §1.10.5「Referee 验证与 In-memory Emitter 异步重叠」尚未体现：当前 compileSource 是**先 verify 完再 emit**（cli.zig:3862 → 之后才调用 emitLlvmc*），两阶段串行。

改进方案：
1. 既然 verify 已按函数 chunk 化、emit 已按函数 task 化，可让「某函数验证通过」即作为「该函数可发射」的就绪信号，形成函数粒度的流水线（verify(fn_i) 与 emit(fn_{i-1}) 重叠）。
2. 用一个就绪队列连接两侧的 worker 池，验证产出的 annotated 函数直接推给 emit worker。
3. 注意保持错误优先级：任一函数 verify trap 时，整体仍以该 trap 退出（不能因为已并行发射了别的函数而吞掉错误）。

验收标准：
- 大工程下 total_ns < flatten_ns + verify_ns + emit_ns（出现重叠即达标，profile 字段已具备，cli.zig:82-84）。

工作量：大（1–2 周，调度 + 错误传播 + 确定性）。风险：中高（并发正确性 + 错误可重现性）。建议排在 PERF-1/2 之后。

---

## 第二优先级：功能 / 正确性（服务 §1.7 结构化诊断 与 设计 §1.4.3）

### FUNC-1：收窄错误归类兜底 `else => .forbidden_syntax`（损害 §1.7 稳定错误码）

现状（证据）：
- collectMetadata 失败时，未显式枚举的错误一律映射为 `.forbidden_syntax`（src/verifier.zig:3235）。

为何是问题：
- design §1.7 把「结构化诊断 + 稳定错误码 + repair 建议」当作 Agent-First 的核心卖点。把任意未知错误伪装成「语法禁止」，会让 Agent 拿到误导性的错误码与 repair_hint，与该设计目标直接冲突。

改进方案：
1. 审计 collectMetadata 可能返回的全部 error 变体，为每个补一个对应 trap（或新增一个诚实的 `.internal_error` / `.unsupported_construct`，而不是复用 forbidden_syntax）。
2. 兜底分支至少在 message/hint 中标注「未分类的元数据构建错误」，避免 repair 给出针对语法的错误修复。

验收标准：每条 collectMetadata 错误路径都有对应单测，断言 trap 种类正确。
工作量：小（1 天）。风险：低。

---

### FUNC-2：核对/落地「字段级互斥借用」（design §1.4.3，设计自身列出的改进线）

现状（设计意图）：
- design §1.4.3 指出痛点：Referee 把借用绑在整块内存上，大结构体（如 ConnectionSlot）会被整块锁死；改进方向是**强化对 ptr_add 的识别**，让 `ptr_add obj, 4` 与 `ptr_add obj, 8` 被视为互不干涉的独立借用。
- 这是设计**明确批准**的改进线，不是新语法。

待核实/落地：
1. 先确认当前 verifier 对 interior pointer（已有 interior_parent / interior_first_child / interior_next_sibling 三叉树，src/verifier.zig:2112-2124）是否已按**偏移**区分子借用，还是仍按母块整体锁。
2. 若仍整块锁：在 interior 子节点上记录字节偏移区间，借用冲突判定改为「偏移区间相交才冲突」。

验收标准：两个不同偏移的字段同时持可变借用应通过；重叠偏移仍报 BorrowConflict / DoubleMutableBorrow。
工作量：中（3–5 天）。风险：中（借用判定是安全核心，需充分用例）。
备注：需先做第 1 步核实，避免重复实现已存在的能力。

---

### FUNC-3：审计 `catch {}` 吞错点，确认未掩盖安全相关错误

现状（证据）：
- 静默吞错计数：verifier 14 处、interp 7 处、cli 9 处（grep `catch {`）。核心文件 `catch unreachable` 计数为 0（纪律良好，值得肯定）。

为何是问题：
- 多数 `catch {}` 是合法的 best-effort 清理（deinit、注解释放），但内存安全工具链里，任何吞掉「校验/解析」类错误的点都可能让一条本应 trap 的路径静默通过。

改进方案：逐一标注这 30 处的意图，对「清理类」保留并加注释，对「校验/解析类」改为向上传播或显式记录。可加一条 lint 约束（类似已有的 referee-loc-lint，tools/）禁止在校验路径裸 `catch {}`。
验收标准：每处 `catch {}` 有明确分类注释；校验路径零裸吞错。
工作量：小–中（1–2 天）。风险：低。

---

## 第三优先级：安全 / 插件契约（服务 §1.7.1）

### SEC-1：消除 `sa run` 解释器 与 native build 的插件路径不一致（§1.7.1 自认缺口）

现状（设计自认）：
- design §1.7.1 明确写道：「部分 extern-heavy 插件在 native build 可工作，但解释执行路径仍可能暴露 InvalidInstruction，这属于宿主运行路径一致性缺口。」

为何是问题：
- 同一份 SA 代码在 `sa run`（内存解释器 src/interp.zig）与 `sa build-exe` 下行为不一致，破坏「四模驱动」（§1.6）的可信度，也让 Agent 在 run 下得到的反馈无法外推到 build。

改进方案：
1. 在 interp.zig 中为 extern/插件符号建立与 native 一致的调用入口（broker / FFI 桥接），而不是遇到未知 extern 就抛 InvalidInstruction。
2. 至少先做到「优雅降级 + 明确诊断」：解释器遇到未实现的 extern 时，给出结构化错误（哪个符号、属于哪个插件、native 下可用），而非通用 InvalidInstruction。

验收标准：对每个官方插件，`sa run` 要么与 native 行为一致，要么给出指明插件/符号的结构化诊断。
工作量：大（依赖插件面，1–2 周）。风险：中。

---

### SEC-2：本地插件 .so 加载前做完整性校验（对齐 §1.7.1 sha256 强约束）

现状（证据）：
- 远程归档安装强制 `#sha256:`（src/plugins.zig:1935-1936、2088-2091）。
- 但 sap.json 的 artifacts 已声明每个 .so 的 sha256（design §1.7.1「artifacts: target triple → 动态库路径与 sha256」），本地 dlopen 路径未见在加载前比对该 sha256。
- ABI 层校验是有的：加载后校验 abi_version 与 descriptor_size（src/plugins.zig:3368-3369）。

为何是问题：
- §1.7.1 把 sha256 完整性哈希列为默认强约束（且明确禁止用 MD5）。本地 .so 若不在 dlopen 前比对清单声明的 sha256，篡改/损坏的库会被直接加载，ABI 校验只能挡住版本不匹配，挡不住「同 ABI 但被替换的实现」。

改进方案：在 dlopen 之前，对将要加载的 .so 计算 sha256 并与 sap.json artifacts 中声明值比对，不一致则拒绝加载并报 machine_code_hash_mismatch（该 trap 已存在，common/trap.zig:58）。
验收标准：替换/损坏 .so 后加载被拒并报对应 trap；正常 .so 不受影响。
工作量：小（1 天）。风险：低。

---

### SEC-3：核实网络权限「仅 https / 拒裸 IP 远程」在安装器中已强制（§1.7.1）

现状：
- design §1.7.1 规定：远程地址只允许 https://，本地只允许 localhost/127.0.0.1/[::1]；普通远程 http://、裸 IP 远程、缺 scheme 必须**拒绝安装**。
- 运行时匹配函数存在（matchesUrlPermissionPattern，src/plugins.zig:503），但部分插件 sap.json 仍声明 `https://*` 通配（http_client / deno / pkg）。

待核实：安装阶段是否对 sap.json 的 net 声明做了上述「拒绝裸 IP / 非 https 远程」的静态校验，还是仅在运行时按声明放行。若仅运行时放行，则 `https://*` 通配等于放行任意 HTTPS 目标（含内网 → SSRF 面）。
改进方案：在插件安装/解析 sap.json 时加入 §1.7.1 的 net 声明校验；并评估把 `https://*` 收窄为具体域名。
验收标准：声明 http:// 远程或裸 IP 的插件安装被拒；通配域名给出告警。
工作量：小（1–2 天）。风险：低。

---

## 第四优先级：工程治理

### ENG-1：验证逻辑实际复杂度已迁出 referee-loc-lint 的度量范围

现状（证据）：
- design §3.3 要求「Referee 核心 ≤ 2500 行」，CI 有 referee-loc-lint 门禁（build.zig:518-521）。
- 但该 lint 只统计 `src/referee/` 目录（tools/referee_loc_lint.zig:4），当前 642 行 PASS（实测 `[referee-loc] PASS: 642 <= 2500`）。
- 真正的验证引擎在 `src/verifier.zig`（5393 行），**不在 lint 度量范围内**。

为何是问题：
- 「Referee ≤ 2500 行」这个设计目标在 lint 口径下「通过」，但实际验证复杂度（5393 行）已迁移到 verifier.zig，门禁失去了对真实复杂度的约束力——这是度量与意图的脱节，不是代码本身的 bug。

改进方案（二选一或并行）：
1. 扩大 loc-lint 度量范围，把 src/verifier.zig 纳入，并重新设定一个诚实的上限（承认现状或制定收敛目标）。
2. 把 verifier.zig 按职责拆分（元数据收集 / 单函数线性校验 / Phi 合并 / 泄漏检查 / 并行调度），让每个子模块可单独度量与测试。
验收标准：loc-lint 的统计对象与「Referee 核心」语义一致。
工作量：拆分为大（1 周+），仅扩度量为小（半天）。风险：低（不改语义）。

### ENG-2：仓库卫生（与内核质量无关但影响审计与 CI）

现状（证据）：
- 主仓 git 跟踪了 14 个二进制（.so/.exe/.o），合计约 48MB（git ls-files | grep -iE '\.(o|so|exe)$'）；根目录还混入 .tmp_*、repro*、test_*.zig、dummy.zig 等约 20+ 脚手架文件。
- ~/projects/sa_plugins（插件 Zig 共 136,368 行）**不是 git 仓库**（git rev-parse 返回 fatal）。

改进方案：
1. `git rm --cached` 移除二进制与脚手架，补 .gitignore（zig-out/、.zig-cache/、*.so/*.o/*.exe、.tmp_*）。
2. 给 sa_plugins 建立 git 仓库（与 §1.7.1「sai↔.so 双向可审计」的可审计性诉求一致）。
验收标准：clone 体积下降；插件代码进入版本控制。
工作量：小（半天）。风险：低（注意先确认这些二进制不是测试夹具的必需输入）。

---

## 优先级汇总

| 编号 | 主题 | 对齐的设计目标 | 优先级 | 工作量 |
|---|---|---|---|---|
| PERF-1 | 去除 verify 逐指令重分类 | §3.3 吞吐 / §1.10.2 | P0 | 中 |
| PERF-2 | regConsumedLater 去 O(n²) | §1.3.2 单次扫描 | P0 | 中 |
| PERF-3 | verify⇄emit 异步重叠 | §1.10.5 | P1 | 大 |
| FUNC-1 | 收窄错误归类兜底 | §1.7 诊断 | P1 | 小 |
| FUNC-2 | 字段级互斥借用 | §1.4.3 | P1 | 中 |
| FUNC-3 | catch{} 吞错审计 | 安全纪律 | P1 | 小 |
| SEC-1 | run/build 插件路径一致 | §1.6 / §1.7.1 | P1 | 大 |
| SEC-2 | 本地 .so sha256 校验 | §1.7.1 | P1 | 小 |
| SEC-3 | net 声明静态校验 | §1.7.1 | P2 | 小 |
| ENG-1 | loc-lint 度量对齐 | §3.3 | P2 | 小–大 |
| ENG-2 | 仓库卫生 / 插件入 VCS | 可审计性 | P2 | 小 |

建议执行顺序：PERF-1 → PERF-2 → SEC-2 → FUNC-1/FUNC-3 → FUNC-2 → SEC-3/ENG-2 → SEC-1 → PERF-3 → ENG-1。
理由：先吃掉两个违反自身设计原则、且 ROI 最高的性能点；再补低成本高价值的安全/诊断；大改（异步流水线、run/build 统一、verifier 拆分）放后面。

---

附：本次评估读过的关键源码位置
- 管线：src/main.zig:13、src/cli.zig:3806/3855/3862
- 验证器：src/verifier.zig:2097(verifyBody)/2161(classifyLine)/2553(loop 检测)/2961(出口泄漏)/2968+845(regConsumedLater)/3009(chunk)/3090(parallel)/3235(错误兜底)
- 后端：src/emit_llvm_llvmc.zig:15-17/854/1150
- gas：src/common/gas.zig（静态边界报告，非运行时计量）
- trap 分类：src/common/trap.zig:5-63（60+ 种）
- 插件：src/plugins.zig:503/1935/3368-3369、~/projects/sa_plugins/*/sap.json
- 设计依据：docs/design.md §1.3/§1.4/§1.7.1/§1.10/§3.3、docs/faq.md（刻意省略特性的论证）
