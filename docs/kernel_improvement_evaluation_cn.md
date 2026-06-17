# SA 内核改进评估报告（性能 / 安全）

> **评估日期**：2026-06-15
> **评估范围**：仅 SA 编译器内核（`sci/src/` 下 ~36K 行 Zig）。插件目录 `/home/vscode/projects/sa_plugins/` 暂不评估，因为还在开发阶段。
> **评估基线**：tasks.md P0.1–P0.5b 已完成、progress.md 最新 issue6/7/8 微优化已落地。

---

## 一、内核现状的诚实定位

**已经做到位的，不再重复做（避免无效投入）**

| 已落地 | 出处 |
|-------|------|
| 寄存器作用域局部化（解 O(N²) 内存爆炸） | tasks.md P0.1 |
| 稀疏增量状态注解 | tasks.md P0.2 |
| 声明级并行发射（per-decl LLVM 模块） | tasks.md P0.4 |
| 内存直通 LLVM-C，绕过文本 IR | tasks.md P0.5 / P0.5a |
| LLVM-C 后端覆盖 atomic / fallible / vtable / sys / wasm | tasks.md P0.5b 系列 |
| WASM 矩阵 110 demo 等价验证 | tasks.md P0.5b-wasm-demo-matrix |
| `StaticStringMap` 替代字符串级联 | progress.md issue8 Tier-1 |
| Verifier `sig_index_by_name` 一次构建复用 | progress.md issue8 Tier-1 |
| Interpreter 标签/槽位缓存（消除每次重建） | progress.md issue8 Tier-1 |
| 内存块二分查找（替代线性扫描） | progress.md issue8 Tier-1 |
| `VerifierBufferPool` 缓冲复用 | progress.md issue8 |
| `DefDict.foldText` 单趟懒输出 | progress.md issue8 |
| Expanded-import fragment cache（LRU） | progress.md issue6 IMP-1 |
| `appendFlattenFragment` + `cached_macro_defs` 等增量地基 | progress.md issue6 |

**这意味着"低垂的果实已经摘完"，下面所有改进 ROI 都会陡降，需要精挑细选。**

---

## 二、性能：还能改的，按 ROI 排序

### ⭐⭐⭐⭐⭐ 1. 函数级增量编译缓存（最大单一杠杆）

**现状**：你已经在做"expanded-import fragment cache"+`appendFlattenFragment`+`cached_macro_defs`，这是地基。但**端到端"改一个函数只重编一个函数"还没接通**。

**做法**：
- 以 `(function_source_sha256, def_dict_hash, sai_hash)` 为 key
- 缓存 `FlattenResult.function_fragment` + `AnnotatedFunction` + `.o` 单函数对象
- `sa.lock` 加 `function_artifact_hash` 字段
- 链接期增量 `ld.lld --incremental` 或自写 `.a` 重打包

**预期收益**：10K 行工程一行改动，编译从 ~6s → ~200ms。**这是把 SA 从"Zig 速度"推到"interpreted 体验"的关键。**

**工程量**：2-3 周。地基已铺好，剩下的是工程拼装 + 等价性测试矩阵。

**风险**：缓存失效边界（宏依赖、`#def` 依赖、`#loc` 行号偏移）容易踩错；必须有"缓存开/关等价性 PBT"作为门禁。

---

### ⭐⭐⭐⭐ 2. 多层 Codegen Tier（绕开 LLVM O3）

**现状**：FAQ §性能对比 自己承认"LLVM O3 是秒级到十秒级瓶颈"。Release 路径无法避免，但 **dev 路径完全可以绕开**。

**做法**：

| 命令 | 后端 | 用途 |
|------|------|------|
| `sa run` | Interpreter（已有） | <1ms 启动 |
| `sa build --dev` | **Cranelift**（新） | dev iteration，O0，秒内 |
| `sa build-exe` | LLVM-C O1（默认） | CI / 集成 |
| `sa build-exe --release-fast` | LLVM-C O3 | 发布 |

Cranelift 一个函数 ~1ms codegen，且能直接吐 ELF/Mach-O/COFF/Wasm，无需链接器外置。Bytecodealliance 自己用它做 wasm runtime jit。

**预期收益**：dev build 从秒级 → 毫秒级，让 SA 的"编译速度"叙事在边缘 serverless 场景能真正打过 Rust。

**工程量**：4-6 周。需要写一个 `src/emit_cranelift.zig`，但 IR 已是三地址码，映射比 LLVM 还简单。

**风险**：多一个后端 = 多一套等价性测试 = CI 时间线性膨胀。建议默认 off，`--dev` 才启用。

---

### ⭐⭐⭐ 3. Instruction 数组改 SoA + 字符串去重池

**现状**：`Instruction` 是 AoS（数组对象），fields 包括 op kind / operands / text / atomic meta / upstream_loc。cache line 利用率低。

**做法**：
- 把 `instructions: []Instruction` 拆成 `kinds: []InstKind`（u8）+ `operands: []u32x3` + `text_idx: []u32` + `loc_idx: []?u32`
- 字符串/文本走 interned pool，operand 存 `u32` 索引
- verifier 热路径只触 `kinds[i]` 和 `operands[i]`，一个 cache line 装 16-32 条指令

**预期收益**：verifier 单线程吞吐 500K 行/秒 → 估计 1.2-1.5M 行/秒。`AnnotatedInstruction` 内存占用降 30-40%。

**工程量**：2-3 周。改动表面广（flattener / verifier / emitter 全要 touch），但变换机械。

**风险**：与并行 verifier 的内存视图协调；diagnostic 输出需要按需 reconstruct。

---

### ⭐⭐⭐ 4. Verifier 完全函数级并行 + 工作偷取

**现状**：`ParallelVerifyJob/Worker` 已存在，但需要确认：(a) 调度粒度是函数还是文件？(b) 是否有工作偷取？(c) 内存 contention？

**做法**：
- 工作单元 = 函数，不是文件
- `std.Thread.Pool` + lock-free MPMC 队列 + 工作偷取（参考 Zig 自己的 `ThreadPool`）
- 每 worker 独立 `VerifierBufferPool` 减少 cache line ping-pong

**预期收益**：32 核机器上 verifier 吞吐 ~25-30×（受 Amdahl 限制）。10K 函数工程 verify 从 ~200ms → ~10ms。

**工程量**：1-2 周（前提是 `Referee` 本身已经是函数局部，从 P0.1 看是的）。

---

### ⭐⭐ 5. WASM emitter 体积进一步压缩

**现状**：48KB hello world 已经领先，但还能更小。

**做法**：
- 死代码消除提前到 IR 层（不依赖 wasm-opt）
- 字符串/常量去重在 emitter 内做
- Custom section 压缩（DWARF-in-WASM 可选压缩）
- 多函数 outlining：识别相同 bit-pattern 的函数模板，emit 一次

**预期收益**：hello ~48KB → ~20KB；中型应用减 30-50%。

**工程量**：2-3 周。

---

### ⭐⭐ 6. Interpreter JIT 化

**现状**：`interp.zig` 2330 行，是个大 switch dispatch。

**做法**：用 Cranelift 把热函数 JIT 编译，threshold 触发；冷代码继续解释。

**预期收益**：`sa run` 重计算场景速度 5-20×；但启动延迟略增。

**工程量**：3-4 周。但与 Cranelift 后端有协同。

**优先级偏低**：`sa run` 主要是 dev / sandbox 用途，启动快比稳态吞吐重要。建议 Tier 2 之后再做。

---

## 三、安全：还能改的，按 ROI 排序

### ⭐⭐⭐⭐⭐ 1. Referee 形式化验证（Coq/Lean4）

**现状**：FAQ 与 design.md §6 Property 1-32 已经把正确性属性列清楚；R33 Coq 证明是路线图但**还没动**。

**做法**：
- 把 `referee/table.zig`（仅 293 行）翻译成 Coq inductive definition
- 把"位掩码状态转移"定义为 small-step semantics
- 证明 4 条核心性质：Progress、Preservation、NoMemoryLeak、NoUseAfterMove
- 用 Coq 提取出 reference implementation，与 Zig 实现差分测试

**预期收益**：
- 这是 SA 唯一一个 Rust **无法复现** 的硬护城河
- 一旦完成，可以印在所有宣传物上："SA 是世界上第一门 Referee 经数学证明健全的高级语言"
- 直接打开 / 航空 / 医疗市场

**工程量**：3-6 个月（需要懂 Coq 的人）。但 ≤2500 行 Referee 是世界上**最适合形式化的借用检查器**，比 Rust 现实可行。

**风险**：找不到能做的人；中途发现 Property 描述与实现有 gap（这反而是大收获）。

---

### ⭐⭐⭐⭐ 2. `--strict-tags` 类型混淆护栏

**现状**：design.md §1.5 / FAQ §高可靠列了这是 **SA 当前最大安全缺口** —— "把 f64 坐标误当 i32 标志位，Referee 不拦截"。v0.5 路线图。

**做法**：
- `alloc N tag <Name>` 语法（已设计）
- Verifier 在 `load r+off as T` 时校验 `(tag, off, T)` 三元组合法
- `#tag <Name> { field: T @ +N }` 在 `.sal` 声明
- `--strict-tags` flag 强制全局开启

**预期收益**：把 SA 从"内存安全"升级到"内存安全 + 类型不混淆"。直接补齐与 Rust safe 子集的唯一语义差距。

**工程量**：3-4 周。tag 元数据从 `.sal` 一路穿到 verifier 表，改动面中等。

---

### ⭐⭐⭐⭐ 3. 跨函数 / FFI 边界的契约一致性检查

**现状**：FAQ §"为什么没有 lifetime"自己承认这是 SA 的**安全下限缺口**："跨函数借用安全由前端保证；前端降级错了，运行时会段错误"。`libsa_scope` 是 helper，不做全局校验。

**做法**：
- 加一个 link-time pass（不在 Referee，而在 linker driver 里）
- 扫所有 `.sai` 契约 + 所有 `@extern` 调用点
- 校验：所有权前缀（`^`/`&`/value）在调用方和实现方一致
- 在 `sa build-exe` 中加 `--link-check` flag
- 加入 `sa.lock` 的 `contract_consistency_hash`

**预期收益**：补齐 SA 的"已知缺口"。可以从文档里删掉那条 caveat。

**工程量**：2-3 周。不影响热路径（链接期一次性）。

---

### ⭐⭐⭐ 4. 差分 fuzzing（interp ↔ llvm-bc ↔ wasm）

**现状**：你已有 `wasm-matrix` 110 demo 等价矩阵（P0.5b-wasm-demo-matrix），但都是固定 demo，不是 fuzz 生成。

**做法**：
- 写一个 SA 程序生成器（基于 EBNF + 类型 / 所有权约束）
- 用 `zig build fuzz-diff` 跑：interp 输出 vs LLVM bc 输出 vs wasm 输出，三路必须 byte-equal
- 任何分歧 = 自动缩小 + 入回归库

**预期收益**：捕到 emit 后端 / interp 的语义漂移；这种 bug 单靠测试用例几乎抓不到。

**工程量**：3-4 周。生成器是核心难点。

---

### ⭐⭐⭐ 5. Trap 诊断精度审计

**现状**：progress.md 提到 `snapshotFirstMismatch` 之前有过"slot vs globalId 错位导致报错的寄存器名不对"的诊断 bug；可能不是孤例。

**做法**：
- 对每个 Trap kind 写一个"故意触发"的最小化样本
- 校验 `TrapReport` 的 `register / source_line / upstream_loc / hint` 全部精确
- 加入 CI gate

**预期收益**：LLM 自修复闭环 1-shot 成功率提升。直接转化为"用 SA 写代码比 Rust 容易"的卖点数字。

**工程量**：1 周（机械工作）。

---

### ⭐⭐⭐ 6. Capability mask 扩展评审

**现状**：design.md §4.2 是 9 位。FAQ 自己提到不计划扩展（§4.9）。

**但需要评审**：
- 是否覆盖了 timing channel（恒时执行声明）？
- 是否区分 `unsafe_raw_ptr_read` 和 `unsafe_raw_ptr_write`？
- 是否标记 `floating_nondeterminism`（IEEE 浮点非结合性等）？

**建议**：不扩展，但需要文档明示"这 9 位不覆盖侧信道 / 浮点 / 计时通道"，避免承诺过度。

---

### ⭐⭐ 7. Gas metering 边界审计

**现状**：Property 11 要求 `max_instruction_steps` 为可证明上界。但循环上界推断的覆盖度？

**做法**：
- 列出当前能识别的 bounded loop 模式（`for i in 0..N`、while + 严格递减 induction variable）
- 列出会标 `unbounded` 的模式
- 对边界 case 加测试

**预期收益**：避免"声称 bounded 实际 unbounded"。这对边缘 serverless 场景的 Gas 上限承诺至关重要。

**工程量**：1-2 周（审计 + 加测试，不动算法）。

---

### ⭐⭐ 8. 并行 / 增量编译的确定性保证

**现状**：P0.4 已经做了并行发射；future P1 是增量。

**做法**：
- 黄金规则："同样输入 ⇒ 字节相同输出"，包括 wasm / .o / `.sa.bc`
- 加 CI：跑同一 demo 100 次，diff 输出
- 跑并行 vs 串行，diff 输出

**预期收益**：`sa pkg` 的"机器码 SHA-256"才有意义；不然 sa.lock 的所有承诺破产。

**工程量**：1 周（已经在做的话；如果还没有 CI gate，必须立刻加）。

---

## 四、不建议做（成本高、价值低）

| 想法 | 为什么不做 |
|------|-----------|
| 给 SA 加类型系统 | 直接违背"无类型系统"哲学；--strict-tags 已经覆盖核心需求 |
| 全函数 NLL 借用图 | Rust 已经走过这条路，复杂度爆炸；SA 的 O(1) 优势会消失 |
| 加 `mut` / `&mut` 语法 | 同上，违背设计 |
| 重写 Referee 成 SIMD | 已是 O(1) 位运算，SIMD 改写收益小，复杂度大 |
| 自写链接器替代 `zig cc` | `zig cc` 已经是最简单方案；自写 = 维护地狱 |
| 把 cli.zig 6967 行拆分 | 大文件不影响运行时性能；拆完工作量大且容易引入 bug |

---

## 五、推荐的"下一季度 3 件套"

如果只能挑三件做（按战略价值，不按工程量）：

| # | 任务 | 战略价值 | 工程量 |
|---|------|---------|--------|
| 1 | **函数级增量编译缓存** | 把 SA 的"编译速度"从纸面优势变成可演示的 dev loop | 2-3 周 |
| 2 | **`--strict-tags` 落地** | 补齐唯一与 Rust safe 子集的语义差距 | 3-4 周 |
| 3 | **Referee Coq 形式化（启动）** | 唯一不可复制的护城河，是叙事的最高点 | 3-6 月（长期，但先启动） |

加上一条**必须做的 hygiene**：**并行/增量输出字节确定性 CI gate**（1 周）。这是 sa.lock SHA 锚定可信的前提，不做会让其他所有安全宣传破产。

剩余六项（Cranelift dev tier / SoA / 完全并行 verifier / WASM 压缩 / fuzzing / 跨函数契约 / Trap 诊断审计 / Gas 边界 / Capability 文档）作为 backlog，按用户反馈优先级排。

---

## 六、一句话结论

**内核大改的红利期已过，进入"打磨期"。** 真正还能产生战略价值的不是热路径再快 20%，而是：

1. **形式化验证**（拿不可复制的护城河）
2. **函数级增量编译**（把"快"做成可感知的体验）
3. **`--strict-tags`**（补齐与 Rust safe 的最后一道差距）

剩下的微优化和小修补按 ROI 排队，不必担心"再不做就晚了"。

---

## 附录：评估时参考的内核文件清单

| 文件 | 行数 | 角色 |
|------|------|------|
| `src/flattener.zig` | 7,231 | 文本扫描、宏展开、`#loc`、`#def`、函数签名 |
| `src/cli.zig` | 6,967 | CLI 子命令、build 驱动 |
| `src/verifier.zig` | 5,885 | Referee 核心、位掩码、Phi 汇聚、原子 ordering |
| `src/plugins.zig` | 3,532 | 插件发现与 manifest 解析 |
| `src/interp.zig` | 2,330 | `sa run` 内存解释器 |
| `src/emit_llvm_llvmc.zig` | 1,696 | LLVM-C 内存直通 emitter |
| `src/flattener/line_classifier.zig` | 1,045 | 单行 16 形态分类器 |
| `src/llvm2sa.zig` | 917 | bitcode → SA 逆向翻译（保守子集） |
| `src/common/signature.zig` | 796 | 函数签名表 |
| `src/common/trap.zig` | 595 | TrapReport 数据结构 |
| `src/common/const_decl.zig` | 582 | `#def` / `@const` |
| `src/lowerer.zig` | 518 | IR 降级辅助 |
| `src/referee/call.zig` | 436 | 调用点所有权契约 |
| `src/common/atomic.zig` | 394 | 原子 ordering lattice |
| `src/common/instruction.zig` | 378 | Instruction / InstKind |
| `src/libsa_scope.zig` | 365 | 前端降级 helper |
| `src/flattener/def_dict.zig` | 350 | `#def` 字典展开 |
| `src/referee/table.zig` | 293 | **Referee 状态转移表（形式化目标）** |
| `src/common/capability.zig` | 100 | CapabilityMask |
| `src/common/gas.zig` | 29 | Gas 计数 |

内核合计 ~36,000 行 Zig（不含插件、不含运行时 `sa_std.zig` 8,179 行、不含 `sa_net_uring.zig` 2,485 行）。
