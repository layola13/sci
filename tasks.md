# 架构设计参考 (Technical Design Reference)

> **实施准则**：所有任务实现必须遵循 `.kiro/specs/sa-asm-language/design.md` 中的架构规范。
> - **工业级性能 (P0)**：[`design.md §1.10`](.kiro/specs/sa-asm-language/design.md#110-工业级可伸缩性架构-industrial-scalability-architecture---紧急-p0)
> - **宏驱动高级特性**：[`design.md §1.4`](.kiro/specs/sa-asm-language/design.md#14-宏驱动高级特性演进-macro-driven-advanced-features)
> - **格式化打印 (R39)**：[`design.md §3.7`](.kiro/specs/sa-asm-language/design.md#37-sys_原语--ffi-气闸舱--错误传播-runtime)
> - **物理极限速度 (R40)**：[`design.md §1.10 (Point 3, 4)`](.kiro/specs/sa-asm-language/design.md#110-工业级可伸缩性架构-industrial-scalability-architecture---紧急-p0)

---

# 实现计划：SA 线性所有权语言与编译器（按版本路线图）

## 紧急 P0 任务：工业级性能重构 (Industrial Performance Refactor)

> **当前状态**：通过 `demos/compare` 基准测试发现，由于寄存器 ID 全局化，在大规模（10k+ 函数）工程下编译会触发 $O(N^2)$ 内存爆炸并 OOM。
> **目标**：将内存占用从 $O(Inst \times GlobalReg)$ 降至 $O(Inst \times LocalReg)$，实现真正的线性扩展。

- [x] **Task P0.1: 寄存器作用域局部化**：修改 Flattener 逻辑，确保每个 `@func` 拥有独立的寄存器 ID 空间。
- [x] **Task P0.2: 稀疏状态注解存储**：重构 `AnnotatedInstruction`，由全量 `[]u16` 快照改为记录状态增量（Delta），解决内存爆炸。
- [x] **Task P0.3: 流式 Emitter 改造**：历史文本 emitter 的流式化阶段已被 P0.5 取代；主线现已删除文本后端，只保留 LLVM-C 纯 `.sa.bc` 流。
- [x] **Task P0.4: 声明级并行发射 (Decl-level Parallel Emission)**：借鉴 Zig `Zcu.PerThread` 模型，将发射任务打散至单函数粒度，充分利用多核并行驱动后端。
- [x] **Task P0.5: 内存直通 Emitter 重构**：借鉴 Zig `codegen/llvm.zig`，引入 `llvm-c` 绑定，放弃文本 `.ll` 中转，直接在内存中构造 LLVM bitcode 模块，消除 I/O 瓶颈。
  - [x] P0.5a 核心闭环：默认已走结构化 LLVM-C builder 直接生成 `.sa.bc`，不再通过文本 IR 解析桥接；已覆盖 hello、loop、while 与 FFI handle 对象生成。
  - [x] P0.5a-default-bc：CLI / SAX 构建默认改为 LLVM-C 纯 `.bc` artifact 流，`build-exe` / `build-obj` / `build-wasm` / `test` 正常路径不再调用文本 emitter，也不再保留文本 LLVM 产物路径；SAX 测试替身也已改为真实 LLVM bitcode，使用 `BC c0 de` 魔数与 `llvm-dis` 回归兜底，避免 dummy 文本 bitcode 占位。
  - [x] P0.5b-atomic：LLVM-C 后端已覆盖 `atomic_load` / `atomic_store` / `atomic_rmw_*` / `cmpxchg` / `fence`，atomic smoke 通过默认纯 `.sa.bc` 流生成 bitcode 并以退出码 11 运行。
  - [x] P0.5b-fallible：LLVM-C 后端已覆盖 fallible ABI `{i32, payload}`、fallible call、`?` payload 提取/早返传播、fallible return 打包与 native main wrapper 状态返回；`19_result_question` / `50_error_chain` / `180_try_trait_v2` 默认 `.sa.bc` native smoke 通过。
  - [x] P0.5b-vtable-indirect：LLVM-C 后端已覆盖 vtable 常量、vtable slot provenance、`call_indirect` typed callee cast 与纯 `.sa.bc` native 运行；`07_trait_vtable` / `110_trait_super_vtable` / `32_trait_object_vector` smoke 通过且不生成 `.ll`。
  - [x] P0.5b-sys-wasm：LLVM-C 后端已内建 `@sys_print` / `@sys_exit` / `@sys_argc` / `@sys_argv` / `@sys_read_file` / `@sys_write_file` 最小 runtime，并按 `size_bits` 修正 wasm32 ABI；`demos/support/sys_runtime_probe.sa` native 运行输出 `ok`，wasm32 通过 Node/WASI 输出 `ok`，且只生成 `.sa.bc` 中间产物。
  - [x] P0.5b-memslot：LLVM-C 后端将 SA 可变寄存器固化为按函数实际 slot 数分配的 entry `i64` mem-slot，消除分支/循环合流处的 SSA dominance 错误；`sort_probe` / `hashmap_probe` / `hashset_probe` / `once_probe` / `mpsc_probe` 已通过纯 `.sa.bc` native smoke 且不生成 `.ll`。
  - [x] P0.5b-debug-min：LLVM-C 后端在纯 `.sa.bc` 流中写入最小 DWARF metadata（compile unit / subprogram / instruction location）；`build-exe -g` 通过，`llvm-bcanalyzer-14` 可见 `llvm.dbg.cu`，且未生成 `.ll`。
  - [x] P0.5b-bitcode-reader：修正 LLVM-C sys argv runtime 的 typed-pointer GEP，`demos/support/sys_runtime_probe.sa` 生成的 `.sa.bc` 可被 `llvm-dis-14` 严格反汇编，native 运行输出 `ok`，且未生成 `.ll`。
  - [x] P0.5b-debug-vars：LLVM-C 后端在 debug 模式下为函数参数和 SA slot alloca 写入 `llvm.dbg.declare` / `DILocalVariable`；`build-exe -g` 产物可被 `llvm-dis-14` 反汇编并可见变量元数据，native 运行输出 `21`，且未生成 `.ll`。
  - [x] P0.5b-wasm-sys-e2e：`tests/cli_smoke.zig` 已将 `sys_runtime_probe.sa` 扩展为 native + wasm32-WASI 双轨验收，覆盖 argv、文件读写、打印、退出码、`.wasm.sa.bc` 产物和 Node/WASI 运行，且未生成 `.ll`。
  - [x] P0.5b-wasm-demo-matrix：新增独立 `zig build wasm-matrix` rosetta/support native + wasm32-WASI 等价矩阵，覆盖 110 个 demo：基础 print/control-flow/struct/array/slice/string/loop/while/break/nested-loop/factorial/fibonacci、mutability/box/reference/move/borrow/refcount/resource、常量结构体、Option、generic、method、associated fn、enum/match/tuple/destructuring/tagged union、iterator map/filter/fold、module/import/export/config、cache/mem fill/queue、router/parser/serializer、service/pipeline/graph/component、metrics/workflow/kv/sql/blob/sync/scheduler、protocol/text/job/db/query/log/build/release、state/event/channel/actor/async/counter、fallible `?`/Result、vtable/trait object、callback contract、sort/hashmap/hashset/once/mpsc；修正 wasm32 vtable 8 字节槽宽 ABI，补 `sa_time_sleep_ns` fallible weak fallback，并补 LLVM-C `struct_` 常量字节展开；验证通过且主线不保留文本 LLVM 产物路径，同时从巨大的 `cli_smoke` 拆出，避免单项 matrix 重新编译整套 CLI smoke。
  - [x] P0.5b 覆盖扩展：现有 rosetta/support native stdout smoke demos 已全部纳入 wasm/native 等价矩阵；argv / panic-hook 命名 demo 当前源码为纯确定性输出，也已覆盖。

## Rust Core 模式落地任务

- [x] **1. Cell / RefCell 布局与宏**
  - 产出 `Cell` / `RefCell` 的 `.sal` 布局样例和宏模板
  - 明确借用计数器、归零路径、Trap 分支与显式释放顺序
- [x] **2. Rc / Arc / Weak 双计数控制块**
  - 产出 Strong / Weak 双计数控制块布局
  - 验证 `clone` / `drop` / `downgrade` / `upgrade` / `drop` 的级联逻辑
  - 对齐约束必须显式写入布局文件
- [x] **2.1 SA 单测收口**
  - `tests/rust_core_unit.sa` 已覆盖 `cell` / `refcell` / `rc` / `weak` 的 SA 原生 `@test`
  - 使用仓库内 SA 标准库相对导入，直接由 `sa test` 执行
- [x] **3. Waker / Trait Object 调度模式**
  - 产出 vtable / 间接调用示例
  - 确保宏展开末尾清理所有临时寄存器，并避免标签冲突

### 验收口径
- 只接受“宏 + 布局 + Referee 校验”路线，不接受新增 ISA
- 前端降级失配必须通过结构化 Trap 暴露，不接受运行时静默容错


## 当前执行顺序

1. 先完成主线：标准库收口、单元测试框架、零信任包管理、`sa_net_uring`、`bc2sa`。
2. 插件工作只允许在插件边界内推进：每个插件必须独立交付 `.so` 产物、runtime 加载、热重载、ABI 版本化、失败隔离、skills 元数据和生命周期钩子。
3. 不要把插件实现回写到主线程分发逻辑里；主线程只保留发现、加载、卸载、热重载与派发入口，插件命令、skills、生命周期逻辑和测试必须留在各自目录。
4. 构建期错误和运行期失败隔离分开验收：单个插件编译失败只能影响对应 `.so` 产物或插件自身测试，不应把已稳定的宿主运行路径退回静态注册模型。
5. 任务拆分时默认按插件目录并发推进；如果某个插件已有错误，优先修它自己的目录，不要把修复扩散到主线程或别的插件目录。

## 概述

本实现计划按**版本递进**组织，而不是一次性交付全部 23 条需求。核心思路：

1. **v0.1 MVP（Week 1-14）** — "跑通闭环"。SA 源码 → Flattener → Referee → LLVM bitcode → **全程走 `zig cc`** 产出 `.exe` 和 `.wasm`。不自研任何后端。
2. **v0.2（post-MVP，4-6 周）** — "后端自研"。替换 WASM 产线为手写二进制 Emitter，获得更小体积、wasm64、DWARF-in-WASM 精细控制。
3. **v0.3（post-MVP，6-8 周）** — "性能兑现"。SIMD/并行调度/LLM 微调 / AutoBevy 1M ±30%（最低优先级）路线。

## 插件任务验收标准

- 当前插件实现已统一外置到 `/home/vscode/projects/sa_plugins/` 的独立工程；主线只保留薄宿主层、ABI 约定和最小 loader 边界，不再承载插件业务逻辑。
- 插件必须以 runtime `.so` 形式交付，不能把静态注册或宿主内联实现当成完成态。
- 插件必须支持热重载语义，至少能在宿主进程内完成加载、卸载、重新加载的回归验证。
- 插件必须保持目录隔离，agent 只改本插件目录及其入口文件，不改 `src/cli.zig` 的静态分发逻辑。
- 插件编译失败只能影响对应插件产物与该插件测试，不应让其它插件回退到静态耦合路径。
- 插件目录内必须包含 skills 元数据、命令实现和自己的测试，不能依赖宿主补写业务语义。
- 如果插件有公共 ABI 适配层，必须写在插件目录内，且以 `plugin_descriptor` / `saasm_plugin_descriptor_v1` 作为 runtime 导出验收点。
- “完成”必须同时满足：`.so` 可被宿主 runtime 发现，命令入口可执行，skills 可收集，热重载测试通过，且失败插件不会污染其他插件的加载结果。
- 任何插件相关实现都不得把主线程从 runtime loader 回写成静态注册；如果需要改宿主，只能改 loader/隔离/热重载这一层。
- 任何插件任务的验收都必须写清楚：要修改的目录、是否会影响主线程、是否需要 `.so` build、是否需要 hot reload 测试、是否需要失败隔离验证。
- 如果插件最终要开放给 SA 调用，还要额外验收 `sa run` / `@extern` 直调该插件 ABI，并确认解释器不会把插件 handle 当普通堆指针释放。
- 目前 HTTP client/server 已完成 `sa run` 直调桥接，后续新增插件若要给 SA 调用，必须沿用同样的 runtime `.so` + interpreter bridge 模式，不能回到主线程静态分发。

**v0.1 不做的事**（这是刻意的风险削减）：
- ❌ 不手写 WASM 二进制 Emitter（走 `zig cc -target wasm32-wasi -O ReleaseSmall`）
- ❌ 不自研 DWARF-in-WASM（zig cc 自带）
- ❌ AutoBevy 仅作为最低优先级，1M ±30% 不承诺（只跑 1K 冒烟）
- ❌ 不承诺 LLM 零训练 80% 成功率（只跑 pilot 归档 baseline）
- ❌ Referee 不强求 1500 行（2500 行 MVP 基线）
- ❌ 不做 SIMD opcode 降级（ISA 里有占位，但 Emitter 层先 `unreachable`）

工程根目录：

```
sa/
├── build.zig
├── build.zig.zon
├── src/
│   ├── common/              # Instruction / CapabilityMask / Trap / GasReport / UpstreamLoc
│   ├── flattener/           # 预处理 + #loc + 宏
│   ├── referee/             # 状态机 + Phi + 气闸舱 + 早返回 + 原子 ordering
│   ├── emit_llvm_llvmc.zig    # LLVM-C bitcode builder + DWARF
│   ├── emit_wasm/           # [v0.2] 手写 WASM 二进制（v0.1 为空目录）
│   ├── interp/              # sa run 内存解释器
│   ├── driver/              # zig cc 子进程封装
│   ├── cli/                 # sa 四模命令行
│   ├── runtime/             # @sys_* / __sa_panic / snapshot
│   └── libsa_scope/         # 前端降级 helper (C-ABI)
├── tests/{unit,property,integration,golden,pilot}/
├── bench/
└── docs/{whitepaper.md,whitepaper.txt,ebnf.md}
```

---

# Version 0.1 — MVP：跑通闭环（14 周）

目标：一段可编译的 `.sa` 源码能通过 CLI 四模分别产出可运行的 `.exe`、`.wasm`，并在 Referee 上守住所有权正确性。**WASM 产线这一版完全委托 `zig cc`。**

## v0.1 任务

- [ ] 1. 初始化 Zig 工程脚手架与工具链
  - 创建 `build.zig` / `build.zig.zon`，目标：单文件静态 CLI
  - 约定 src/tests/bench/docs 目录骨架
  - 集成 Zig PBT 库（无合适选项则以 C-ABI 夹心 Rust proptest）
  - 锁定 Zig 内置 LLVM 版本入 CI 矩阵
  - 配置 `zig fmt --check` / `zig build test` / `tokei` LOC 统计
  - _Requirements: R14.11, R16.6_

- [ ] 2. W1-2 协议定型

  - [ ] 2.1 定义 `Instruction` / `Operand` / `InstKind` / `OpKind` / `AtomicOrdering` 数据结构
    - 按 design §4.1 实现全部枚举，包含 `Try` / `EarlyReturn` / `AtomicLoad` / `AtomicStore` / `Cmpxchg` / `Fence` / `RawCast` / `AssumeSafe` / `AssumeBorrow` / `LocHint`
    - `operands: [4]Operand` 固定大小
    - _Requirements: R2.1, R2.2, R2.5, R13.1_

  - [ ]* 2.2 Instruction 编解码单元测试
    - _Requirements: R2.1, R2.2_

  - [ ] 2.3 `CapabilityMask` 8 位真值表常量表
    - 按 design §4.2 定义 `Active` / `Locked_Read` / `Locked_Mut` / `Consumed` / `BorrowView` / `FfiBorrow` / `Untracked` / `Fallible`
    - 编码 TRUTH_TABLE 数组供 Referee 查表
    - _Requirements: R4.1–R4.7, R13.2, R13.3, R18.1_

  - [ ]* 2.4 位运算单元测试
    - _Requirements: R4.1, R4.2_

  - [x] 2.5 `TrapReport` JSON schema
    - 按 design §4.4 含 `upstream_loc` / `function` / `is_ffi_wrapper` 字段
    - 29 种 Trap 枚举在 `src/common/trap.zig` 中已列出；其中一部分仅在路线图中保留，尚未全量接入发射路径
    - _Requirements: R9.3, R13.5, R13.7, R17.7, R18.5, R19.2_

  - [x] 2.5a 错误码与诊断规划
    - 以 `docs/errorcode.md` 作为统一查阅入口；`design.md` §4.4 固定 `TrapReport` schema，`docs/faq.md` 解释为什么公共诊断是 JSON-first
    - 统一字段约定：`trap` / `line` / `source_line` / `register` / `registers` / `expected_mask` / `actual_mask` / `expected_mask_name` / `actual_mask_name` / `upstream_loc` / `function` / `is_ffi_wrapper` / `message` / `hint`
    - 明确 `Trap` enum ordinals 不是公开数值代码，后续如需 `trap_code` 必须显式新增
    - 参考 Zig 编译器的 `ErrorMsg` / `ErrorBundle` 组织方式，保留主消息 + note/hint 的结构化诊断能力
    - _Requirements: R9.3, R16.5, R18.5, R19.2_

  - [x] 2.6 `GasReport` / `FunctionSig` / `ParamSpec` / `UpstreamLoc`
    - `FunctionSig` 含 `kind` / `is_ffi_wrapper` / `return_fallible` / `upstream_file`
    - _Requirements: R5.1, R5.3, R11.1, R13.4, R18.1_

  - [x] 2.7 产出 EBNF 文档
    - `docs/ebnf.md` 按 design 附录 C，含 `loc` / `ffi_wrapper_def` / `try_op` / `panic_op` / `atomic_*` / `rawcast` / `assume_*`
    - _Requirements: R1.6, R3.1, R13.1, R13.9_

  - [x] 2.8 产出 LLM 白皮书 v0.1
    - `docs/whitepaper.md` + `.txt`，≤ 2000 行
    - 覆盖 R23.2 全部章节（五符号 + ISA + CFG + 掩码 + 宏 + 气闸舱 + `@sys_*` + 错误传播 + `#loc` + 降级合约摘要 + 5 组对比 + Trap 代号表）
    - _Requirements: R1.1–R1.5, R20.1–R20.2, R23.1, R23.2, R23.5_

  - [x]* 2.9 白皮书 lint 冒烟（≤ 2000 行）
    - _Requirements: R23.1_

- [x] 3. 检查点 — 协议定型
  - 运行 `zig build test`。

- [ ] 4. W3-5 Flattener

  - [x] 4.1 行分类器（16 种形态）
    - _Requirements: R3.1_

  - [x] 4.2 `#def` 字典 + 常量折叠（`+/-/*`）
    - _Requirements: R7.1–R7.5_

  - [x]* 4.3 常量折叠 PBT — **P8**
    - _Requirements: R7.1, R7.2, R7.5_

  - [x] 4.4 禁用语法扫描（`{` `}` `if` `else` `while` `for` `a.b.c`）
    - _Requirements: R3.3, R6.6_

  - [x]* 4.5 禁用语法 PBT — **P4**
    - _Requirements: R3.2, R3.3, R6.6_

  - [x] 4.6 `#loc` 伪指令收集器
    - 维护 `LocTable: Map<expanded_line, UpstreamLoc>`
    - 下一条真实指令继承最近一次 `#loc` 值
    - _Requirements: R19.1_

  - [x]* 4.7 `#loc` 单调映射 PBT — **P25**
    - 随机插入 `#loc`，断言 Trap 报告与 LocTable 一致
    - _Requirements: R19.1, R19.2_

  - [x] 4.8 宏模板注册 `[MACRO]...[END_MACRO]`
    - _Requirements: R8.1_

  - [x] 4.9 `EXPAND` 文本展开 + 深度栈（上限 256）
    - _Requirements: R8.2, R8.5, R8.6_

  - [x] 4.10 `[REP N]...[END_REP]` + 游标 `%i`
    - _Requirements: R8.3, R8.5_

  - [x]* 4.11 宏展开 PBT — **P6**
    - _Requirements: R8.1, R8.2, R8.3, R8.5_

  - [x] 4.12 宏/常量错误检测（`DuplicateDef` / `RegisterRedefinition` / `MacroRecursionLimit`）
    - _Requirements: R7.4, R8.4, R8.6_

  - [x]* 4.13 非法宏 PBT — **P7**
    - _Requirements: R7.4, R8.4, R8.6_

  - [x] 4.14 寄存器名规范化为 `u32` ID（保留 SymbolTable）
    - _Requirements: R2.1_

  - [x] 4.15 函数签名解析
    - `src/common/signature.zig` 已覆盖 `@func` / `@ffi_wrapper` / `@extern` / `@export` 四类
    - 已解析 `-> T!` 可失败返回并保留 `return_fallible`
    - _Requirements: R3.1, R5.1, R5.3, R13.4, R13.9, R14.9, R14.10, R18.1_

  - [x]* 4.16 签名解析确定性 PBT — **P11**
    - `src/common/signature.zig` 已加入随机函数头生成与双次解析结构等价断言
    - _Requirements: R2.2, R5.1, R5.3_

  - [x] 4.17 原生类型字面量合法性（11 种 + `v128`）
    - `PrimType` / `parsePrimType` / layout / LLVM type mapping 已接入 `v128`
    - `sa run` 遇 `v128` 明确返回 `UnsupportedInstruction`，不伪造语义
    - _Requirements: R2.4_

  - [x]* 4.18 类型字面量 PBT — **P14**
    - `src/common/signature.zig` 已加入合法字面量随机采样与近似非法字面量拒绝测试
    - _Requirements: R2.4_

  - [x] 4.19 原生逃逸块 `$...$` 识别 + 涉及寄存器名列表
    - `src/flattener/line_classifier.zig` 已识别 `$...$` 为 `native`
    - `src/flattener.zig` 已把块内容保存到 `Instruction.native_text`，并提取裸标识符列表到 `Instruction.native_reg_names`
    - _Requirements: R1.5_

  - [x] 4.20 气闸舱指令解析（`*` / `assume_safe` / `assume_borrow`）
    - Flattener / line classifier 已解析 `RawCast` / `AssumeSafe` / `AssumeBorrow` 三类指令
    - _Requirements: R13.1, R13.2, R13.3_

  - [x] 4.20a `ptr_add` 解析（`dst = ptr_add base, off`）
    - Flattener 已解析并保留 base / off 槽位，支持立即数与寄存器偏移
    - _Requirements: R2.5, R4.9, R4.10_

  - [x] 4.21 原子指令解析（`atomic_load` / `atomic_store` / `cmpxchg` / `fence` + ordering）
    - 已接入 Flattener / Referee / LLVM / Interpreter，并补原子冒烟测试
    - _Requirements: R2.1, R2.6_

  - [x] 4.22 错误传播语法糖 `? reg` 展平
    - 前端层直接展平为 `br_ok + L_early_return` + `EarlyReturn` 指令
    - Referee 无需新增指令类型
    - _Requirements: R18.2, R18.3_

  - [x] 4.23 `panic(code)` 解析为特殊 Call
    - _Requirements: R18.4_

  - [x] 4.24 Flattener 公开 API `flatten(allocator, source) !FlattenResult`
    - _Requirements: R7.1, R8.1, R19.1_

  - [x]* 4.25 Flattener 端到端单测
    - _Requirements: R3.1, R7.1, R8.1, R13.1, R18.2, R19.1_

- [x] 5. 检查点 — Flattener 完成
  - 跑过 P4、P6、P7、P8、P11、P14、P25

- [ ] 6. W6-9 Referee（含一周性能调优）

  - [ ] 6.1 `CapabilityTable`（masks / origins / lock_refs / flags）
    - _Requirements: R4.1, R9.2_

  - [ ] 6.2 统一指令校验函数骨架（把 16+ 种 `InstKind` 收敛为"读 N 源 + 写 M 目标"模式）
    - MVP 基线 ≤ 2500 行 Zig；stretch 目标 1500 行
    - _Requirements: R9.1, R9.2, R9.5_

  - [x] 6.3 四仿射规则（alloc / borrow / move / release）
    - _Requirements: R1.1–R1.4, R4.3–R4.4, R4.6–R4.7_

  - [x]* 6.4 所有权状态机 PBT — **P1**
    - _Requirements: R1.1–R1.4, R4.1–R4.7_

  - [x] 6.5 未声明寄存器检测
    - _Requirements: R2.3_

  - [x]* 6.6 `UnknownRegister` PBT — **P13**
    - _Requirements: R2.3_

  - [x] 6.7 函数出口泄漏检测
    - _Requirements: R4.5_

  - [x] 6.8 基本块结束指令 + 重名 Label
    - _Requirements: R3.4, R3.5_

  - [x]* 6.9 CFG 结构完整性 PBT — **P5**
    - _Requirements: R3.4, R3.5, R10.2_

  - [x] 6.10 Phi 汇聚点按位 AND
    - 合法交集 `{0x01, 0x02, 0x04, 0x08, 0x11, 0x12}`
    - _Requirements: R10.1–R10.4_

  - [x]* 6.11 Phi PBT — **P9**
    - _Requirements: R10.1, R10.3_

  - [x] 6.12 调用点契约前缀校验
    - `src/referee/verifier.zig` 已在直接调用路径校验 call-site capability prefix 与声明签名一致
    - `src/referee/call.zig` 同步提供纯解析/校验 helper
    - _Requirements: R5.2_

  - [x]* 6.13 调用契约 PBT — **P12**
    - `src/referee/call.zig` 已加入随机 capability 合约 PBT
    - `src/referee/verifier.zig` 已加入真实程序路径的前缀失配随机回归
    - _Requirements: R5.2_

  - [x] 6.14 原生逃逸保守消费
    - `src/referee/verifier.zig` 已将 `$...$` 视为 contract boundary：引用的已知寄存器按保守消费处理
    - 借用视图按现有消费语义清借用；`stack_alloc` 穿越原生边界直接 `Trap: StackEscape`
    - _Requirements: R5.4_

  - [x]* 6.15 原生逃逸保守消费 PBT — **P3**
    - 已加入确定性负例与随机化回归：`native` 后再访问被引用寄存器触发 `UseAfterMove`
    - _Requirements: R5.4_

  - [x] 6.16 **气闸舱强制隔离**
    - `RawCast` / `AssumeSafe` / `AssumeBorrow` 仅当 `is_ffi_wrapper == true` 通过
    - 否则 `Trap: IllegalUnsafeContext`
    - _Requirements: R13.1, R13.4, R13.5_

  - [x]* 6.17 气闸舱隔离 PBT — **P21**
    - 已加入随机化测试覆盖 `*` / `assume_safe` / `assume_borrow` 在普通函数中的非法使用
    - _Requirements: R13.1–R13.5_

  - [x] 6.18 **FFI 借用不可销毁**
    - Verifier / CapabilityTable 已对 `FfiBorrow` 位寄存器落地：遇 `^` → `Trap: FfiOwnershipViolation`；遇 `!` 仅清记录不发射 free
    - _Requirements: R13.3, R13.7_

  - [x] 6.18a 母借用 / 子指针追踪
    - Verifier 已对 `ptr_add` 与借用相关 `load`/`take` 建立 parent borrow reg -> interior children 映射
    - 母借用 `!` / 解锁时同步将所有派生 `InteriorPtr` 置为 `Consumed`
    - _Requirements: R4.9, R4.10_

  - [x] 6.18b `InteriorPtrEscape` 逃逸拦截
    - Verifier 已在 `@extern` / `@ffi_wrapper` 调用边界拦截 `InteriorPtr`
    - _Requirements: R13.6, R13.7_

  - [x]* 6.18c 内部指针生命周期 PBT — **P26**
    - 已加入随机化测试：释放母借用后访问派生 `InteriorPtr` 触发 `UseAfterMove`
    - 已加入随机化测试：`InteriorPtr` 作为 `@extern` / `@ffi_wrapper` 实参触发 `InteriorPtrEscape`
    - _Requirements: R4.9, R4.10, R13.6, R13.7_

  - [x]* 6.19 FFI 借用不可销毁 PBT — **P22**
    - 已加入 `assume_borrow` 状态位断言、`^`/`return` 违规断言与 CapabilityTable 对应单测
    - _Requirements: R13.3, R13.7_

  - [x] 6.20 **错误传播早返回泄漏校验**
    - `EarlyReturn` 指令作为特殊 `Return` 处理，检查该路径上 Active/Locked 残留 → `Trap: EarlyReturnLeak`
    - `?` 作用于非 Fallible 寄存器 → `Trap: FallibleContractMismatch`
    - _Requirements: R18.5_

  - [x] 6.20a **stack_alloc 退出规则**
    - `stack_alloc` 允许函数出口自动回收，不计入 `MemoryLeak`
    - `stack_alloc` 作为 `^` / `return` / `move` / `call` 实参时必须 `Trap: StackEscape`
    - _Requirements: R2.1, R2.8, R9.1_

  - [x]* 6.21 早返回泄漏 PBT — **P24**
    - `src/referee/verifier.zig` 已加入随机 live allocation 泄漏用例，断言 `?` 的 fail edge 触发 `Trap: EarlyReturnLeak`
    - _Requirements: R18.5_

  - [x] 6.22 原子 ordering 一致性校验
    - 相同地址 RMW 检查 happens-before（简化实现：仅做 ordering 组合表查表，不跨函数追踪）
    - 违规 → `Trap: AtomicOrderingMismatch`
    - 已补 verifier 查表与负例测试
    - _Requirements: R2.6_

  - [x] 6.23 Gas 静态计数
    - Referee 已输出 `GasReport`，包含 `max_alloc_bytes` / `max_instruction_steps` / `call_depth`
    - 真实代码验证覆盖前向跳转 bounded 与回边 unbounded
    - _Requirements: R11.1–R11.3_

  - [x]* 6.24 Gas PBT — **P19**
    - 随机生成 bounded / unbounded 两类真实程序，验证静态 gas 报告与回边判定一致
    - _Requirements: R11.1–R11.3_

  - [x]* 6.25 Referee 确定性 PBT — **P10**
    - 同一输入重复 `verify()`，比较 `ok` / `trap` 的结构化快照完全一致
    - _Requirements: R9.3, R9.4, R11.2_

  - [x] 6.26 真实代码吞吐基准（W9）
    - 生成"含回边 + 多函数 + 气闸舱 + 早返回"的 1M 行合法流（非直线合成）
    - ReleaseFast 实测：1,000,000 行 / 1.886612s = 530,050.82 行/秒，达到 MVP 基线
    - _Requirements: R9.6_

  - [x] 6.27 Referee LOC lint（`tokei src/referee/` ≤ 2500）
    - `tokei src/referee/` = 1981 code lines，已安装并实际跑通
    - _Requirements: R9.5_

- [x] 7. 检查点 — Referee 完成
  - 跑过 P1、P3、P5、P9、P10、P12、P13、P19、P21、P22、P24

- [x] 8. W10-11 LLVM bitcode Emitter + CLI + `zig cc` 全权代劳的 exe/wasm

  - [x] 8.1 基础映射 M01–M07（alloc/free/load/store/运算）
    - `src/emit_llvm_llvmc.zig` 主线已直接覆盖：
      - `alloc -> call ptr @malloc(...)`
      - owned `!r -> call void @free(ptr ...)`
      - borrowed `!r -> no-op`
      - typed `load/store -> getelementptr + load/store`
      - 算术/比较按整数/无符号/浮点类型分别发射；`gt` 已修正为整数路径 `icmp sgt`
    - 已补 emitter 级直接测试：`llvm emitter maps M01-M07 with typed integer ops and owned release`、`llvm emitter maps M03 borrow release to no-op`
    - `src/referee/verifier.zig` 已修正 `AnnotatedInstruction.entry_caps/exit_caps` 快照时机，保证 emitter 基于真实 entry state 判断 release 是否物理 free
    - _Requirements: R14.3–R14.6_

  - [x] 8.2 控制流映射 M08–M13（LLVM 原生 `br` + labels）
    - `jmp` / `br` / `br_null` / direct call / `return` 已有 emitter 级直接测试
    - `call_indirect` 已按签名与 provenance 发射 / 分派，`tests/cli_smoke.zig` 的 `vtable loads preserve indirect call provenance end to end` 覆盖了端到端路径
    - _Requirements: R14.8_

  - [x] 8.3 `take` 映射 M14
    - `src/emit_llvm_llvmc.zig` 主线已将 `take src+off` 发射为 `getelementptr i8, ptr %src, i64 off` + `load ptr`
    - 已补 emitter 级直接测试，断言 LLVM 产物包含 `load ptr, ptr`
    - _Requirements: R14.5_

  - [x] 8.4 原生逃逸块 M15 字节级透传
    - 文本 legacy emitter 已删除；主线 LLVM-C bitcode 后端不再支持文本 IR 原生逃逸透传
    - _Requirements: R14.7_

  - [x]* 8.5 原生逃逸字节透传 PBT — **P2**
    - `src/emit_llvm_llvmc.zig` 已覆盖主线；legacy 文本 emitter 与其文本 IR 测试已移除，避免 `.ll` 后门
    - _Requirements: R14.7_

  - [x] 8.6 函数/Label/`@extern`/`@export` 映射 M16-M17, M21-M22
    - `src/emit_llvm_llvmc.zig` 主线已对普通函数/label 产出 `define` / `L_X:`
    - `@extern` 已产出 LLVM `declare`
    - `@export` 已产出无名称修饰的 `define`
    - `tests/cli_smoke.zig` 与 emitter 单测已覆盖 IR 与目标文件符号证据
    - _Requirements: R14.9, R14.10_

  - [x] 8.7 索引访问物理降维（`mul + GEP + load`）
    - `demos/rosetta/44_slice_iteration/main.sa` 已实测走通 `offset = mul idx, 4` -> `ip = ptr_add data, offset` -> `value = load ip+0 as i32`
    - `tests/cli_smoke.zig` 已固定验证该 demo `build-exe` 后真实运行并打印 `10\n`
    - _Requirements: R6.5_

  - [x]* 8.8 索引访问 PBT — **P15**
    - `src/emit_llvm_llvmc.zig` 已覆盖主线；索引访问回归以 `.sa.bc` 端到端 smoke 为准，不再保留文本 `.ll` 断言
    - `tests/cli_smoke.zig` 已有 `44_slice_iteration` 端到端 `build-exe` 回归，固定验证索引访问 demo 可真实运行并打印 `10\n`
    - _Requirements: R6.5_

  - [x] 8.9 气闸舱指令映射 M18-M20（`ptrtoint` / `inttoptr`）
    - `src/emit_llvm_llvmc.zig` 主线已将 `raw = *safe` 发射为 `ptrtoint ptr ... to i64`
    - `assume_safe` / `assume_borrow` 已发射为 `inttoptr i64 ... to ptr`
    - 已补 emitter 级直接测试：`llvm emitter maps M18-M20 airlock casts`
    - _Requirements: R13.1, R13.2, R13.3_

  - [x] 8.10 原子指令映射 M24-M27
    - `src/emit_llvm_llvmc.zig` 主线已发射 `load atomic` / `store atomic` / `atomicrmw` / `cmpxchg` / `fence`
    - `tests/cli_smoke.zig` 已覆盖端到端 exe/wasm/obj 产物与运行结果
    - 已补 emitter 级直接测试：`llvm emitter maps M24-M27 atomic instructions directly`
    - _Requirements: R2.6, R14.4, R14.5_

  - [x] 8.10a `ptr_add` 映射 M35
    - LLVM Emitter 已生成 `%dst = getelementptr i8, ptr %base, i64 %off`
    - _Requirements: R2.5_

  - [x] 8.11 错误传播展平产物 M28（`extractvalue + icmp + br`）
    - Flattener 已展平为 br + EarlyReturn，Emitter 直接翻译
    - _Requirements: R18.3_

  - [x] 8.12 `panic(code)` 映射 M29
    - Native: `call void @__sa_panic(i32) noreturn`
    - **v0.1 WASM 路径**：由 `zig cc -target wasm32-wasi` 自动把 `@__sa_panic` 降为 `unreachable` 或 WASI exit
    - _Requirements: R18.4_

  - [x] 8.13 Fallible ABI 映射 M30（返回 `{i32 status, T value}`）
    - _Requirements: R18.1_

  - [x] 8.14 `#loc` 上游映射 M31（DWARF `!DILocation` 元数据）
    - 顶部生成 `!DICompileUnit` / `!DIFile` / `!DISubprogram`
    - 每条指令附 `!dbg !N`
    - `--no-debug` 关闭
    - _Requirements: R19.3, R19.5_

  - [x]* 8.15 LLVM bitcode 语法合法性 PBT — **P16**
    - `src/emit_llvm_llvmc.zig` 已覆盖主线；文本 `.ll` 语法校验回归已移除，合法性以 LLVM-C bitcode builder 和 `.sa.bc` 读写验收为准
    - _Requirements: R14.1, R14.3–R14.10_

  - [x]* 8.16 Zig 依赖受限 PBT — **P17**（v0.1 版本：断言产物 `@import` 集合为空，因为我们不生成 Zig 源码）
    - `src/emit_llvm_llvmc.zig` 已覆盖主线；不再生成 Zig/LLVM 文本源码，`@import` 文本断言已无主线路径
    - _Requirements: R14.11_

  - [x] 8.17 LLVM-C bitcode Emitter 公开 API `emitLlvmc(allocator, verified, loc_table) ![]const u8`
    - 附 source map `inst_idx → ir_line`
    - _Requirements: R14.1_

  - [x] 8.18 `zig cc` 子进程封装 `driver/zigcc.zig`
    - 把 `.bc` 写临时文件
    - `sa build-exe` → `zig cc <bc> -o <exe> -O ReleaseSmall`（默认 O1 档，`--release-fast` 切 O3）
    - **`sa build-wasm` → `zig cc <bc> -target wasm32-wasi -o <wasm> -O ReleaseSmall`（全程使用 `.sa.bc` artifact，不生成文本 `.ll`）**
    - `sa build-obj` → `zig cc <bc> -c -o <o>`
    - _Requirements: R14.1, R14.11, R15.1, R15.2, R16.2, R16.3, R16.4_

  - [x] 8.19 CLI `sa run` / `build-exe` / `build-wasm` / `build-obj` 四模路由
    - Trap 返回非零退出码 + JSON 到 stderr
    - _Requirements: R16.1, R16.5_

  - [x] 8.20 CLI 二进制分发约束
    - `zig build -Drelease-small` 产物 ≤ 15 MB（MVP），`zig-out/bin/sa` 为静态、剥离后的 ELF，可直接满足分发约束
    - _Requirements: R16.6_

  - [x] 8.21 `-g` / `--no-debug` 调试开关接入
    - `-g` 默认关，`build-exe -g` 启用 DWARF 生成
    - _Requirements: R19.4, R19.5_

  - [ ] 8.22 Agent-First JSON 诊断体系改造 (NEW)
    - 为 `trap.zig` 中的报错赋予稳定的 `SA-XXX` 错误码
    - 实现全局 `--json` 标志，输出含 `repair`、`compile_tokens` 和 `instruction_count` 的结构化诊断
    - 新增 `sa explain` 和 `sa fix --plan` 骨架命令
    - 当前已落地的子集：`trap.zig` 已支持 `repair` 对象，`src/cli.zig` / `src/cli_util.zig` 已接入 `SA-CLI-001..015` 诊断码，`sa explain` / `sa fix --plan` / `sa skills` 已实现并有 `tests/cli_smoke.zig` 覆盖
    - 仍待补齐：trap 侧稳定 `SA-XXX` 命名与后续 trap 词表统一

  - [x] 8.23 可热插拔 CLI 插件系统重构 (NEW，后置)
    - 完成态必须是 runtime hot-reloadable 的动态库 `.so`，不接受静态注册、静态库 `.a`、或主线程硬编码分支作为替代
    - 每个插件必须独立交付自己的 `.so` 产物，并导出稳定 ABI 版本号、descriptor、命令入口、生命周期钩子与 skills 元数据
    - `src/plugins.zig` 只负责 runtime 发现、`dlopen`、`dlsym`、`dlclose`、热重载和失败隔离，不承载插件命令语义
    - 插件边界必须可热插拔：宿主可在运行时替换 `.so`，新版本生效后旧版本可卸载，同名插件以新版本覆盖旧版本
    - `init` / `prebuild` / `postbuild` / `skills` 必须来自已加载插件的运行时导出，宿主不内建插件行为
    - 插件错误必须局部化：单个插件加载失败、ABI 不匹配、符号缺失、descriptor 空值、命令返回异常，都不能拖垮主程序；宿主应跳过坏插件并保留结构化诊断
    - 主线代码的修改面必须最小化：插件实现只改各自目录与必要的宿主加载器，不回写主线程命令分发逻辑
    - 当前验收口径：
      - 至少 1 个插件完成端到端 `.so` 化，且宿主可在运行时发现、调用、卸载并重新加载
      - 至少 1 个同名插件替换回归测试，验证新 `.so` 覆盖旧版本后重新加载并生效
      - 至少 1 个失败隔离测试，验证坏插件不会阻断其他插件和主程序，且同目录内其他插件仍可加载
      - 至少 1 份最小 ABI 文档，写清版本号、导出符号、回调约定、错误码、兼容规则与 reload 语义
      - 每个插件目录都要有自己的最小运行时测试，覆盖 descriptor 导出、skills 元数据和命令入口
      - 插件构建失败只能影响对应 `.so` 产物或插件测试，不应把宿主退回成静态耦合模型
    - 并发拆分建议：
    - `src/sax/` 负责 SAX 外部插件的 runtime `.so` 完整化与热重载回归
      - `src/db/` 负责 DB 外部插件的 runtime `.so` 完整化与失败隔离
      - `src/pkg/` 负责 fetch/pkg 外部插件的 runtime `.so` 完整化与技能元数据
      - `src/bc2sa/` 负责 bc2sa 外部插件的 runtime `.so` 完整化与命令一致性
      - `src/http_server/` 负责 HTTP server 外部插件的 runtime `.so` 完整化与 scaffold 入口
      - 每个 agent 只允许改自己的插件目录和必要的本地测试，不得跨目录改动其他插件或主线程分发逻辑
      - 宿主侧只允许与动态加载和目录发现相关的最小改动；若无必要，不改 `src/cli.zig` 的主命令分发
      - 任何插件交付如果仍然依赖静态注册、静态库 `.a` 或主线程硬编码分支，视为未完成
    - 已验证完成：
      - `src/http_server/`：descriptor / skills / scaffold / serve / runtime `.so`
      - `src/bc2sa/`：descriptor / skills / command consistency / runtime `.so`
      - `src/sax/`：descriptor / skills / runtime `.so`，并通过 compile-time plugin-mode split 避免将 `std.process.Child.run` 拉进 shared-library 图
      - `src/db/`：descriptor / skills / runtime `.so`，nested test graph 通过本地 stub 收口，runtime wrapper 图通过真实 DB 入口
      - `src/pkg/`：descriptor / skills / prebuild / `fetch` / `install` runtime 命令均有插件本地测试；`install` 无参数读取 `sa.mod` 并真实 vendor 依赖，`install <identity>` 复用真实 fetch 路径；`zig build pkg-plugin-test` 已纳入 `zig build test`
      - `/home/vscode/projects/sa_plugins/sa_plugin_http_client` 与 `/home/vscode/projects/sa_plugins/sa_plugin_http_server`：`sa run` 已可直接调用 `sa_http_client_*` / `sa_http_server_*`，SA bridge 已接通

  - [ ] 8.24 标准库 JSON FFI 与生态剥离 (NEW，后置)
    - 打通 `sa_std/encoding/json` 的 DOM 与流式双模 FFI 桥接
    - 在文档层明确拒绝 YAML/XML 进入标准库，规划至周边 Package 生态

- [x] 9. W10-11 内存解释器（`sa run`）

  - [x] 9.1 大 switch 分派全部 `InstKind`
    - `call_indirect` 现在优先使用寄存器里携带的 vtable provenance；`demos/rosetta/07_trait_vtable/main.sa` 已可在 `sa run` 下打印 `77`
    - 解释器分派和 `call_indirect` 路径已被 `tests/cli_smoke.zig` 的 `trait vtable demo runs through sa run` 覆盖
    - _Requirements: R16.1_

  - [x] 9.2 `@sys_*` 原语原生实现
    - `@sys_print` / `@sys_read_file` / `@sys_write_file` / `@sys_exit` / `@sys_argv` / `@sys_argc`
    - 兼容 legacy `@sa_print_bytes`，`demos/rosetta/01_hello_world/main.sa` 已可在 `sa run` 下真实打印
    - 新增 `demos/support/sys_runtime_probe.sa`，覆盖 `sa run` 下的 argv、文件读写、打印与退出路径
    - _Requirements: R16.1, R17.1–R17.5_

  - [x] 9.3 气闸舱语义（Interp 模式）
    - `demos/support/airlock_probe.sa` 在 `sa run` 下验证 `assume_safe` / `assume_borrow` 保持指针值不变，并由 `tests/cli_smoke.zig` 覆盖 native `build-exe` 真实运行
    - `assume_*` 只更新 mask，不做实际指针操作
    - _Requirements: R13.2, R13.3_

  - [x] 9.4 插件 ABI bridge
    - `sa run` 已可通过 `@extern` 直接调用 `sa_http_client_*` / `sa_http_server_*`
    - 解释器对插件句柄增加了外部所有权标记，避免把插件返回的 handle 当普通堆指针释放
    - 仓库级 `cli_smoke.zig` 仍有少数非 HTTP 回归待清理
    - _Requirements: R16.1, R13.8_

  - [x] 9.5 `panic(code)` 打印 + 退出 128+code
    - _Requirements: R18.4_

  - [x] 9.6 Interpreter API `run(allocator, annotated, argv) !u8`
    - _Requirements: R16.1_

- [x] 10. W12 `@sys_*` 原语 + FFI 气闸舱 + panic runtime

  - [x] 10.1 Native `@sys_*` 原生 stub（`src/runtime/native_sys.zig`）
    - `src/runtime/native_sys.zig` 已实现 `sys_print` / `sys_exit` / `sys_argc` / `sys_argv` / `sys_read_file` / `sys_write_file`
    - `tests/native_sys_runtime.zig` 已覆盖静态 `.o` 构建、`zig cc` 链接、`sys_read_file` / `sys_write_file` / `sys_exit` 行为
    - _Requirements: R17.1–R17.5_

  - [x] 10.2 **v0.1 WASM 路径**：`@sys_*` 映射到 WASI import
    - `tests/cli_smoke.zig` 已验证 `sa build-wasm` 产物包含 `fd_write` / `proc_exit` / `args_get` / `args_sizes_get`
    - 通过 `zig cc -target wasm32-wasi` 自动链接 Zig 的 WASI stub
    - 不需要手写 WASI 绑定（这部分移到 v0.2）
    - _Requirements: R15.2, R15.5, R17.1–R17.5_

  - [x]* 10.3 `@sys_*` 双轨等价 PBT — **P23**
    - `tests/cli_smoke.zig` 已覆盖 `demos/rosetta/01_hello_world/main.sa` 的 `build-exe` + `build-wasm` 双轨运行，并对比 stdout / 退出码
    - _Requirements: R15.5, R17.1–R17.5_

  - [x] 10.4 `__sa_panic` 运行时符号（Native）
    - ≤ 30 行 Zig，写 stderr + `_exit(128+code)`
    - _Requirements: R18.4_

  - [x] 10.5 句柄模式 FFI 集成样例
    - `tests/integration/ffi_handle.sa`：`@extern` 分配返回 ID → 后续查表借用
    - 已补 `tests/integration/ffi_handle_demo.zig` / `tests/integration/ffi_handle/handle.sa` / `tests/integration/ffi_handle/handle_host.c`，并纳入 `zig build test`
    - _Requirements: R13.8_

  - [x] 10.6 `@export` 对外符号样例
    - 不做名称修饰
    - `tests/cli_smoke.zig` 已覆盖 `@export exported() -> i32` 的 LLVM / nm 证据
    - _Requirements: R13.6, R13.9_

  - [x] 10.7 `UnsupportedSysIntrinsic` 错误路径
    - 目标不支持某 `@sys_*` 时在 Emitter 前报错
    - `src/referee/verifier.zig` 现于 verifier 阶段对未知 `sys_*` 直接返回 `UnsupportedSysIntrinsic`
    - `tests/cli_smoke.zig` 已补未知 sys intrinsic 的 CLI 负例
    - _Requirements: R17.7_

- [x] 11. W12 `libsa_scope` helper 库

  - [x] 11.1 C-ABI 头文件 + 实现
    - 按 design §3.8 导出 `scope_new/drop/enter/exit/bind/move/release/branch_*/emit_releases`
    - 已补 `src/libsa_scope.zig` / `src/libsa_scope.h`，并通过 Zig 单测与 C-ABI demo
    - _Requirements: R20.8_

  - [x] 11.2 Demo 前端样例（`tests/integration/libsa_scope_demo/`）
    - 用 C 写一个微型前端调用 helper，验证作用域末尾自动释放
    - 已接入 `zig build test` 回归
    - _Requirements: R20.8_

- [ ] 12. 检查点 — 发射器 + CLI + sys/FFI
  - 跑过 P2、P15、P16、P21、P22、P23、P24、P25
  - Hello-Compute 端到端：`build-exe` → `.exe` 跑通；`build-wasm` → `.wasm` 在 Wasmtime 跑通
  - v0.1 WASM 体积目标 ≤ 48 KB（由 `zig cc -O ReleaseSmall` 产出，允许较大；v0.2 手写 Emitter 再压到 32 KB）

- [x] 12b. `sa layout` 布局生成工具（R7b）

  - [x] 12b.1 实现 `sa layout --name NAME --fields "field:type, ..."` 子命令
    - 解析字段列表，按对齐规则计算偏移量
    - 输出 `#def` 字典文本到 stdout
    - _Requirements: R7b.1, R7b.2, R7b.3, R7b.4_

  - [x] 12b.2 JSON 输出格式
    - `--format json` 输出结构化 JSON
    - _Requirements: R7b.5_

  - [x] 12b.3 32 位目标支持
    - `--target 32` 时 ptr 对齐为 4
    - _Requirements: R7b.8_

  - [x]* 12b.4 布局工具单元测试
    - 覆盖：纯 i32 结构、混合 i32+f64（需 padding）、全 ptr、空结构
    - _Requirements: R7b.1, R7b.2, R7b.3, R7b.4_

- [ ] 13. W13-14 LLM Pilot + Hello-Compute + AutoBevy（最低优先级）端到端

  - [ ] 13.1 AutoBevy Component Buffer + Entity + System 注册（1K 规模，最低优先级）
    - _Requirements: R21.1, R21.4_

  - [ ] 13.2 System 并行分析器（复用 CapabilityMask AND，最低优先级）
    - _Requirements: R21.2_

  - [ ]* 13.3 System 并行分析 PBT — **P20**（最低优先级）
    - _Requirements: R21.2_

  - [ ] 13.4 AutoBevy 1K 冒烟集成测试（最低优先级）
    - 1K 实体 1 帧跑通 Wasmtime
    - _Requirements: R21.3, R21.4_

  - [ ] 13.5 LLM Pilot 30 题执行脚本
    - 10 种基础用例（alloc/borrow/loop/branch/FFI/错误传播/结构体偏移/数组索引/递归/双缓冲）× 3 变种
    - 3 个 LLM（GPT-4o / Claude Opus / DeepSeek-Coder）
    - 记录首次通过 Referee 比例，归档 baseline，**不预设 KPI**
    - _Requirements: R23.3_

  - [ ] 13.6 Pilot baseline 决策点
    - 若 baseline < 50% → 触发 R23.4 讨论（是否引入伪嵌套前端）
    - 结论写入 post-MVP 路线图
    - _Requirements: R23.4_

  - [x] 13.7 Hello-Compute `.exe` + `.wasm` 端到端测试
    - `tests/cli_smoke.zig` 已覆盖 `demos/rosetta/98_build_pipeline/main.sa` 的 native `build-exe` 与 wasm `build-wasm` 端到端输出/退出码
    - _Requirements: R15.1, R15.3, R16.2, R16.3_

  - [x] 13.8 GDB/LLDB 上游行号断点验证
    - `tests/cli_smoke.zig` 以 `-g` 编译最小 `hello.sa`，并用 `gdb` 在 `hello.rs:10` 下断点实际命中
    - `_debug` 路径保留 `.debug_line`，`build-exe -g` 可在 `gdb` 中回溯到上游源文件
    - _Requirements: R19.5, R19.6_

- [ ] 14. 测试基线与 CI 门禁（v0.1）

  - [x] 14.1 13 类黄金用例集
    - 每类 ≥ 10 例：正常 / `DoubleMutableBorrow` / `UseAfterMove` / 借用期 Move / `MemoryLeak` / Phi 冲突 / 宏合法 / 宏递归 / 禁用语法 / 气闸舱违规 / FFI 借用销毁违规 / 早返回泄漏 / 原子 ordering
    - 第一批已完成 10 个最小可跑 `build-exe` 回归：`02_mutability` / `20_boxed_value` / `26_reference_return` / `27_move_semantics` / `28_borrow_chains` / `51_refcount` / `58_borrow_update` / `61_thread_pool` / `67_resource_pool` / `52_queue_rotate`
    - `tests/cli_smoke.zig` 新增 `assertBuildExeStdout`，固定验证以上 demo 均能编译并打印预期 stdout
    - 第二批已补 11 个最小可跑 `build-exe` 回归：`03_if_else` / `05_struct` / `11_tuples` / `13_array_sum` / `15_string_bytes` / `16_methods` / `18_option_map` / `24_factorial` / `25_fibonacci` / `29_const_data` / `31_trait_static_dispatch`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述核心控制流与数据类 demo 均能真实编译、运行并打印 stdout
    - 第三批已补 11 个已实测可跑 `build-exe` 回归：`12_destructuring` / `34_iterator_filter` / `35_iterator_fold` / `36_tuple_struct` / `40_impl_block_state` / `41_module_imports` / `42_export_visibility` / `45_config_merge` / `46_option_default` / `48_generic_pair` / `63_router_table`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述更多结构、导入、泛型与路由表 demo 均能真实编译、运行并打印 stdout
    - 第四批已补 10 个已实测可跑 `build-exe` 回归：`08_closures` / `10_generics_monomorph` / `17_associated_fn` / `30_manual_guard_branch` / `33_iterator_map` / `37_newtype` / `38_generic_struct_i32` / `39_generic_enum_i32` / `59_method_counter` / `60_enum_branch`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述更多闭包、泛型、关联函数、手动守卫分支、迭代器、newtype 与枚举 demo 均能真实编译、运行并打印 stdout
    - 第五批已补 10 个已实测可跑 `build-exe` 回归：`64_file_manifest` / `68_parser_tokens` / `69_serializer` / `70_integration_service` / `71_pipeline_stage` / `72_graph_walk` / `73_scene_nodes` / `74_component_store` / `77_http_route` / `78_cli_args`
    - 第六批已补 9 个已实测可跑 `build-exe` 回归：`79_metrics` / `80_workflow` / `81_kv_store` / `82_sql_scan` / `83_blob_chunk` / `84_sync_gate` / `85_scheduler_tree` / `87_protocol_frame` / `88_text_index`
    - `86_cache_eviction` 已实测可跑并纳入 `tests/cli_smoke.zig`；后续若再变更语义，以 smoke 为准重新验证
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述更多应用型、路由、序列化与工作流 demo 均能真实编译、运行并打印 stdout
    - 第七批已补 18 个已实测可跑 `build-exe` 回归：`79_metrics` / `80_workflow` / `81_kv_store` / `82_sql_scan` / `83_blob_chunk` / `84_sync_gate` / `85_scheduler_tree` / `87_protocol_frame` / `88_text_index` / `89_job_queue` / `90_app_shell` / `91_db_session` / `92_query_plan` / `93_log_aggregator` / `96_task_orchestrator` / `97_sync_service` / `98_build_pipeline` / `99_release_bundle`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述更多任务队列、应用壳、数据库会话、查询计划、日志聚合、编排、同步、构建与发布 demo 均能真实编译、运行并打印 stdout
    - 第八批已补 3 个已实测可跑 `build-exe` 回归：`94_graphql_router` / `95_repl_shell` / `100_full_app`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述查询路由、REPL 壳与完整应用 demo 均能真实编译、运行并打印 stdout
    - 第九批已补 8 个已实测可跑 `build-exe` 回归：`55_builder_pattern` / `56_state_machine` / `57_event_loop` / `62_channel_pingpong` / `65_job_scheduler` / `66_actor_mailbox` / `75_async_bridge` / `76_lockfree_counter`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述构建器、状态机、事件循环、通道、调度器、actor、异步桥与无锁计数器 demo 均能真实编译、运行并打印 stdout
    - 第十批已补 7 个已实测可跑 `build-exe` 回归：`14_slice_window` / `32_trait_object_vector` / `09_async_await` / `47_tuple_swap` / `94_graphql_router` / `95_repl_shell` / `100_full_app`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述切片窗口、trait 对象向量、异步、tuple 交换、查询路由、REPL 壳与完整应用 demo 均能真实编译、运行并打印 stdout
    - 第十一批已补 1 个已修正并实测可跑的 `build-exe` 回归：`53_cache_hits`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证缓存命中 demo 也能真实编译、运行并打印 stdout
    - 第十二批已补 3 个已修正并实测可跑的 `build-exe` 回归：`43_tagged_union` / `49_pipeline_map` / `86_cache_eviction`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述标签联合、流水线映射与缓存驱逐 demo 也能真实编译、运行并打印 stdout
    - 第十三批已补 1 个已修正并实测可跑的 `build-exe` 回归：`06_enum_and_match`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证枚举与匹配 demo 也能真实编译、运行并打印 stdout
    - 第十四批已补 2 个已修正并实测可跑的 `build-exe` 回归：`19_result_question` / `50_error_chain`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证 fallible / `?` demo 也能真实编译、运行并打印 stdout
    - 第二十批已补 2 个已修正并实测可跑的 `build-exe` 回归：`176_result_flattening` / `178_panic_hook_override`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证结果扁平化与 panic hook override demo 也能真实编译、运行并打印 stdout
    - 第十五批已补 1 个已实测可跑的 `build-exe` 回归：`44_slice_iteration`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证 slice iteration demo 也能真实编译、运行并打印 stdout
    - 第十六批已补 1 个已实测可跑的 `build-exe` 回归：`54_mem_fill`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证内存填充 demo 也能真实编译、运行并打印 stdout
    - 第十七批已补 4 个已实测可跑的 `build-exe` 回归：`01_hello_world` / `04_loop` / `07_trait_vtable` / `21_while_loop`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述基础 hello / loop / trait vtable demo 也能真实编译、运行并打印 stdout
    - 第十九批已补 2 个已实测可跑的 `build-exe` 回归：`22_break_continue` / `23_nested_loops`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述 break / nested loop demo 也能真实编译、运行并打印 stdout
    - 第十八批已补 6 个已实测可跑的 `build-exe` 回归：`29_const_data` / `31_trait_static_dispatch` / `37_newtype` / `38_generic_struct_i32` / `39_generic_enum_i32` / `40_impl_block_state`
    - `tests/cli_smoke.zig` 继续扩充 `assertBuildExeStdout`，固定验证上述基础数据、trait、newtype 与泛型 demo 也能真实编译、运行并打印 stdout
    - 第二批已补 9 个最小反例 `build-exe` 回归：`use_after_move` / `return_after_move` / `borrow_conflict` / `read_write_conflict` / `illegal_unsafe_context` / `stack_escape` / `const_mutation` / `early_return_leak` / `ffi_ownership_violation`
    - `tests/cli_smoke.zig` 新增 `assertBuildExeTrap`，固定验证上述反例均输出结构化 JSON trap
    - 新增 1 个宏合法最小回归：`macro_print`，用 `EXPAND PRINT_MSG RESULT, 9` 验证参数替换与 `@sys_print` 打印
    - 新增 1 个宏递归最小反例：`macro_recursion`，验证 `MacroRecursionLimit` 与 `trap_code:1005`
    - 新增 1 个禁用语法最小反例：`forbidden_syntax`，验证属性链 `a.b.c` 触发 `ForbiddenSyntax`
    - 新增 2 个 `MemoryLeak` 最小反例：`memory_leak_after_borrow` / `memory_leak_partial_release`，分别覆盖借用释放后泄漏与部分释放泄漏
    - 新增 1 个原子 ordering 最小反例：`atomic_ordering_mismatch`，验证同地址 RMW ordering 组合冲突触发 `AtomicOrderingMismatch`
    - 新增 1 个原子前端最小反例：`invalid_atomic_ordering`，验证 `cmpxchg` 失败 ordering 强于成功 ordering 触发 `InvalidAtomicOrdering`
    - `DoubleMutableBorrow` 先在 `src/referee/table.zig` 通过能力表单测覆盖；当前前端没有稳定的最小 `demos/` 文本形态，不为补 demo 放宽语法
    - 新增 1 个 `UnknownRegister` 变体：`unknown_register_return`，验证 `return ghost` 也能输出结构化 trap
    - 新增 5 个 `ForbiddenSyntax` 变体：`forbidden_if` / `forbidden_while` / `forbidden_for` / `forbidden_brace` / `forbidden_property_chain`
    - 新增 1 个 `CapabilityMismatch` 最小反例：`capability_mismatch`，验证调用前缀与被调契约不一致触发结构化 trap
    - 第二十一批已补 2 个已实测可跑的 `build-exe` / 链接回归：`220_pkg_lib_dynamic` / `253_contract_callback_registration`
    - `tests/cli_smoke.zig` 已固定验证 `220_pkg_lib_dynamic` 的 `build-obj` + `ar rcs` + `zig cc` 对象归档链路，以及 `253_contract_callback_registration` 的 `build-exe` 真实运行并打印 stdout
    - 第二十二批已补 5 个已实测可跑的结构化 trap 回归：`205_pkg_cyclic_dependency_reject` / `207_pkg_multiple_versions_conflict` / `226_mod_cyclic_import_detect` / `227_mod_shadowing_prevention` / `243_contract_sig_mismatch_link`
    - `tests/cli_smoke.zig` 已固定验证上述 package / module / contract 约束拒绝路径均输出结构化 JSON trap
    - 新增 `test_all_300.sh`：覆盖 1~300 demo 的 native `build-exe` 回归，并对 wasm32 目标执行 `build-wasm` + Node/WASI 运行；`220_pkg_lib_dynamic` 保留对象归档 native 特例，同时显式验证其 wasm 边界
    - _Requirements: R22.1, R22.2_

  - [ ] 14.2 CI 流水线
    - `zig build test` → Property × 25 × 100+ → 集成 15 个 → 基准回归 ±10% → 白皮书 ≤ 2000 → Referee LOC ≤ 2500 → `.wasm` ≤ 48 KB → DWARF 冒烟 → merge
    - _Requirements: R22.3, R23.1, R9.5, R9.6, R15.3, R16.6_
    - 当前仓库已落地版本化 pre-push hook：根目录 `.githooks/pre-push` 调 `zig build pre-push`，并已通过；它是更窄的前置门禁，不等同于完整 CI

  - [x]* 14.3 Trap 基线回归
    - _Requirements: R22.2, R22.3_

  - [ ] 15. v0.1 最终验收
  - 运行全部测试
  - 硬约束：Referee ≤ 2500 行 / 真实代码 ≥ 500K 行每秒 / 白皮书 ≤ 2000 行 / `.wasm` ≤ 48 KB / `.exe` ≤ 800 KB / CLI ≤ 15 MB / LLM pilot baseline 归档 / AutoBevy 1K 通过（最低优先级）
  - Stretch 全部不强求
  - 任何未通关项向用户确认

---

# Version 0.2 — 自研 WASM 后端（post-MVP，4-6 周）

目标：v0.1 已证明语义闭环，但 `zig cc` 产出的 WASM 偏大（48 KB 级别）且不可控 wasm64。v0.2 替换 WASM 产线为手写二进制 Emitter，获得体积、精度、wasm64 三项收益。Native 路径（LLVM bitcode + zig cc）保持不变。

## v0.2 任务

- [ ] 16. WASM 二进制发射器基础设施

  - [x] 16.1 LEB128 变长整数编解码
    - _Requirements: R14.2_

  - [x] 16.2 WASM Section 拼装骨架（Type / Import / Function / Memory / Global / Export / Code / Data）
    - 按 WASM Core 2.0 规范
    - _Requirements: R14.2_

  - [ ] 16.3 wasm32 / wasm64 双目标切换
    - CLI `--target wasm32|wasm64`
    - `i32.load/store` ↔ `i64.load/store` 切换
    - `memory` section memory64 标志位
    - _Requirements: R15.4_

- [ ] 17. WASM opcode 映射层

  - [x] 17.1 基础 opcode 映射（alloc/load/store/运算/控制流）
    - _Requirements: R14.2_

  - [ ] 17.2 原子 opcode 映射（`0xFE` 前缀 atomics proposal）
    - `i32.atomic.load` / `i32.atomic.store` / `i32.atomic.rmw.cmpxchg` / `atomic.fence`
    - _Requirements: R2.6_

  - [ ] 17.3 SIMD 最小集 opcode（`0xFD` 前缀）
    - `v128.load` / `v128.store` / `i32x4.add` / `f32x4.mul` / `i8x16.shuffle`
    - 对应 SA `add.v128` / `mul.v128` / `shuffle.v128` / `extract_lane` / `insert_lane`
    - _Requirements: R2.4, R2.5_

  - [ ] 17.4 `@sys_*` WASI import 段
    - 手写 `wasi_snapshot_preview1` 的 `fd_write` / `fd_read` / `path_open` / `proc_exit` / `args_get` / `args_sizes_get`
    - _Requirements: R15.2, R17.1–R17.5_

  - [x] 17.5 `panic(code)` → `unreachable` opcode
    - _Requirements: R18.4_

- [ ] 18. DWARF-in-WASM

  - [ ] 18.1 `.debug_info` / `.debug_line` / `.debug_abbrev` 自定义段
    - 按 DWARF 5 规范
    - 可被 `wasmtime --debug` / Chrome DevTools / `wasm-objdump` 消费
    - _Requirements: R19.4_

  - [ ] 18.2 `name` 自定义段（函数/局部变量名）
    - _Requirements: R19.4_

- [ ] 19. 体积优化

  - [ ] 19.1 死代码消除（函数级）
    - _Requirements: R15.3_

  - [ ] 19.2 Hello-Compute `.wasm` ≤ 32 KB（v0.2 硬约束）
    - _Requirements: R15.3_

- [ ] 20. v0.2 测试

  - [ ] 20.1 WASM 产物 wasmparser / wasm-validate 通过
    - **Property 17** 升级为真正的二进制合法性检查
    - _Requirements: R14.2, R15.1–R15.4_

  - [ ] 20.2 wasm64 > 4 GB 寻址样例
    - _Requirements: R15.4_

  - [ ] 20.3 Wasmtime `--debug` 断点命中上游行号
    - _Requirements: R19.4, R19.5_

- [ ] 21. v0.2 切换
  - CLI `sa build-wasm` 默认改走手写 Emitter
  - 保留 `--via-zigcc` 开关以便对比回归
  - 更新白皮书与 design 文档中的 WASM 章节

- [ ] 21b. `#mode compact` 紧凑糖前处理器（R24）

  - [ ] 21b.1 在 Flattener 前端（行分类器之前）新增 mode 解析阶段
    - 扫描首个顶层声明之前的 `#mode` 伪指令
    - 出现次数 > 1 或位置错误 → `Trap: InvalidModeDirective`
    - _Requirements: R24.1, R24.6_

  - [ ] 21b.2 8 条中缀形态白名单正则匹配器
    - 严格匹配 `^(\w+)\s*=\s*(\w+|-?\d+)\s*([+\-*/%&|^])\s*(\w+|-?\d+)\s*$`
    - 以及一元 `^(\w+)\s*=\s*-(\w+|-?\d+)\s*$` → `neg`
    - 命中即做单行纯文本替换 → 关键字形态
    - 多操作符（`a + b * c`）→ `Trap: CompactMultipleInfix`
    - _Requirements: R24.2, R24.3_

  - [ ] 21b.3 未启用 `#mode compact` 时的严格拒绝
    - 源码中出现 `+` `-` `*` `/` `%` 作为中缀算术 → `Trap: InfixSugarDisabled`
    - 注意：`^` 作为所有权前缀、`&` 作为借用前缀、`*` 作为裸指针前缀不受此规则影响
    - _Requirements: R24.5_

  - [ ] 21b.4 Trap 报告 `original_text` 字段扩展
    - 若糖被展开，Trap 的 `source_line` 指向原始行，`original_text` 保留糖形式（如 `d = a + b`）
    - LLM 可用此字段反向定位并修复
    - _Requirements: R24.7_

  - [ ]* 21b.5 **Property 30 (NEW)**：紧凑糖语义等价性
    - 生成器：随机合法 SA 代码（关键字形态）→ 同构转为紧凑形态 → 分别跑 Flattener
    - 断言：两次产出的 `Instruction[]` 逐字段深度相等（即糖仅影响源码文本层）
    - 最少 100 次迭代
    - _Requirements: R24.4_

  - [ ]* 21b.6 非法糖用例基线
    - 10 个黄金用例：多操作符、有符号除写成 `/`、`&&`/`||`、`==`、链式、优先级错误预期
    - 每个都必须产出对应 Trap
    - _Requirements: R24.3, R24.5, R24.9_

  - [ ] 21b.7 白皮书章节追加
    - 在 `docs/whitepaper.md` 新增"附录 F：紧凑糖 v0.2"章节
    - 3–5 行代码片段演示关键字/紧凑两种写法的等价性
    - _Requirements: R23.2 (扩展)_

---

# Version 0.3 — 性能兑现（post-MVP，6-8 周）

目标：v0.1/v0.2 证明了功能完备性，v0.3 把性能承诺逐一兑现。

## v0.3 任务

- [ ] 22. SIMD 路径全面启用
  - 前端层支持 `v128` 字面量与 lane 操作
  - LLVM bitcode Emitter 完整映射
  - _Requirements: R2.4, R2.5_

- [ ] 23. AutoBevy 1M 性能追 Bevy ±30%（最低优先级）
  - 并行调度器接真实线程池
  - 缓存布局调优
  - SIMD 批量更新
  - 基准对比 Rust/Bevy 同等 Demo
  - _Requirements: R21.5_

- [ ] 24. Referee 性能 stretch 目标
  - 真实代码吞吐 ≥ 1M 行/秒
  - Referee LOC 压缩 ≤ 1500（抽取重复模式 + 表驱动）
  - Flattener + Referee 1M 行 ≤ 100 ms
  - _Requirements: R9.5, R9.6_

- [ ] 25. 产物体积 stretch
  - `.exe` ≤ 500 KB（LTO + 自定义 panic handler + strip）
  - CLI ≤ 10 MB
  - _Requirements: R16.6_

- [ ] 26. LLM 微调路线
  - 根据 v0.1 pilot baseline 结果决策：
    - 若 baseline ≥ 70% → 仅优化白皮书
    - 若 50% ≤ baseline < 70% → prompt engineering + few-shot 样例库
    - 若 baseline < 50% → R23.4 讨论的"伪嵌套前端"方案落地
  - _Requirements: R23.3, R23.4_

- [x] 27. Rust std 防波堤 demo 完善
  - `cargo build --release` 产 `.a`
  - `zig cc main.o libstd_bridge.a -o demo.exe`
  - 样例覆盖：文件 / 网络 / 线程 / JSON 解析
  - _Requirements: R13.9_

- [ ] 28. VTable 签名静态校验（R25）

  - [ ] 28.1 Referee 在 `@const ... = vtable { slot = @func }` 声明时记录每个槽位的完整签名 tuple
    - _Requirements: R25.1_

  - [ ] 28.2 `call_indirect` 编译期参数 tuple 比对
    - 比对调用点参数 `(cap_prefix, ty)[]` 与 VTable 槽位声明的 tuple
    - 不匹配 → `Trap: VTableSignatureMismatch`
    - _Requirements: R25.2, R25.3_

  - [ ]* 28.3 VTable 签名校验 Property 测试 — **P31 (NEW)**
    - 合法生成器：随机 VTable + 匹配调用点，断言通过
    - 注入式生成器：参数数量/类型不匹配，断言必 Trap
    - 最少 100 次
    - _Requirements: R25.2, R25.3_

  - [ ] 28.4 FFI VTable 豁免
    - 外部传入的裸指针 VTable 不做签名校验（Referee 无法获知外部签名）
    - _Requirements: R25.4_

- [x] 29. `libsa_async` 异步状态机宏模板（R26）

  - [x] 29.1 编写 `libsa_async.sa` 宏文件
    - 包含 `ASYNC_CTX_DEF` / `ASYNC_STATE_BEGIN` / `ASYNC_STATE_END` / `ASYNC_POLL_PROLOGUE` / `ASYNC_AWAIT_POINT` / `ASYNC_AWAIT_POINT_FINAL` / `ASYNC_RETURN_PENDING` / `ASYNC_READY` / `ASYNC_INVALID_STATE` 等标准宏
    - 其中前者覆盖状态机骨架与恢复入口，后者覆盖最终收尾与非法状态处理
    - _Requirements: R26.1, R26.3_

  - [x] 29.2 Flattener 文件拼接机制（`@import "libsa_async.sa"`）
    - 在预处理阶段把外部 `.sa` 文件内容原样插入当前源码
    - _Requirements: R26.4_

  - [x] 29.3 用 `libsa_async` 重写案例 23 的 demo
    - 验证展开后与手写等价
    - _Requirements: R26.2, R26.5_

  - [x] 29.4 宏展开等价性 Property 测试 — **P32 (NEW)**
    - 对比手写 120 行 SA 与 `EXPAND ASYNC_AWAIT_POINT ...` / `EXPAND ASYNC_AWAIT_POINT_FINAL ...` 展开后的 `Instruction[]`
    - 断言字段级相等
    - 最少 100 次
    - _Requirements: R26.2_

- [ ] 30. 发射产物诊断级别（R27）

  - [ ] 30.1 `--release` 模式确认零运行时开销
    - 验证产物中不含 gas 计数器、不含 sanitizer 簿记
    - _Requirements: R27.1_

  - [ ] 30.2 `--debug-gas` 模式实现
    - 在每个函数入口/基本块头部插入 gas 计数器自增
    - 超限触发 `Trap: GasExceeded`，命名与层级以 `docs/errorcode.md` 为准
    - _Requirements: R27.2_

  - [ ] 30.3 `--debug-san` 模式实现
    - 在 `alloc` / `!free` 点插入红黑树/哈希表簿记
    - 运行期侦测 UAF / Double-Free
    - 输出结构化 JSON 报告（字段口径见 `docs/errorcode.md`，含 `upstream_loc`）
    - _Requirements: R27.3, R27.4_

  - [ ] 30.4 白皮书"构建模式"章节
    - 明确三种模式的安全保障边界与性能代价
    - _Requirements: R27.6_

---

# Version 0.4 — 并行开发基建（post-v0.3，4-6 周）

目标：让 SA 从"单人极客工具"进化为"多人/多 LLM 并行协作的工业级基建"。核心能力：接口契约、版本化布局、函数粒度增量编译。

## v0.4 任务

- [ ] 31. 接口契约文件 `.sai`（R28）

  - [ ] 31.1 定义 `.sai` 文件格式
    - 仅包含 `@extern` 签名声明（含 cap_prefix + ty + 返回类型 + `!` 后缀）
    - 不包含函数体、不包含 `#def`、不包含 `@const`
    - _Requirements: R28.1_

  - [ ] 31.2 Flattener 支持 `@import "module.sai"`
    - 将接口文件中的 `@extern` 声明注入当前编译单元
    - 支持相对路径与绝对路径
    - _Requirements: R28.2_

  - [ ] 31.3 Referee 基于接口签名做调用点校验
    - 无需实际函数体存在即可校验 `CapabilityMismatch`
    - _Requirements: R28.3_

  - [ ] 31.4 链接期签名一致性检查
    - 接口声明与实现的签名不一致时 `zig cc` 报 symbol type mismatch
    - _Requirements: R28.4_

  - [ ] 31.5 并行编译验证
    - 多个 `.sa` 文件引用同一 `.sai`，各自独立编译，最后链接
    - 验证结果与串行编译等价
    - _Requirements: R28.5_

  - [ ] 31.6 CI 依赖检测
    - 接口文件修改时自动标记依赖方需重新验证（文件哈希比对）
    - _Requirements: R28.6_

- [ ] 32. 版本化布局文件 `.sal`（R29）

  - [ ] 32.1 定义 `.sal` 文件格式
    - `#version N` 元数据行 + `#def` 常量声明
    - _Requirements: R29.1, R29.6_

  - [ ] 32.2 Flattener 支持 `@import "entity.sal"`
    - 记录引用的 `#version` 值
    - _Requirements: R29.2_

  - [ ] 32.3 版本冲突检测
    - 两个 `.sa` 引用同一布局文件的不同版本 → 链接期 `Trap: LayoutVersionConflict`
    - 通过在 `.o` 文件中嵌入版本元数据实现
    - _Requirements: R29.4_

  - [ ] 32.4 CI 版本递增检查
    - 布局文件内容变更但 `#version` 未递增 → 警告阻断 merge
    - _Requirements: R29.5_

  - [ ] 32.5 版本变更影响扫描
    - `#version` 递增时自动列出所有引用方
    - _Requirements: R29.3_

- [ ] 33. 函数粒度增量编译（R30）

  - [ ] 33.1 `--incremental` 模式骨架
    - 按函数粒度产出独立 `.o`（每个函数一个）
    - _Requirements: R30.1_

  - [ ] 33.2 函数体哈希比对与缓存复用
    - 未修改的函数跳过 Emitter + zig cc，复用 `.sa-cache/` 中的 `.o`
    - _Requirements: R30.2_

  - [ ] 33.3 增量链接
    - 所有函数 `.o` 合并为单一产物
    - 验证与非增量模式产物行为等价
    - _Requirements: R30.3_

  - [ ] 33.4 缓存目录结构
    - `.sa-cache/<func_name_hash>.o` + `.sa-cache/manifest.json`
    - _Requirements: R30.5_

  - [ ] 33.5 增量 + sanitizer 兼容
    - `--incremental --debug-san` 时每个函数 `.o` 独立包含 sanitizer 入口
    - _Requirements: R30.6_

- [ ] 34. 多 LLM 并行生成验证

  - [ ] 34.1 设计"N 个 LLM 实例并行生成 N 个函数"的测试协议
    - 每个 LLM 实例只看到 `.sai` + `.sal`，独立生成一个函数
    - 最后链接，验证 Referee 通过 + 运行正确
    - _Requirements: R28.5, R30.4_

  - [ ] 34.2 冲突检测集成测试
    - 两个 LLM 生成同名函数 → 链接器报 duplicate symbol
    - 签名不匹配 → Referee 报 `CapabilityMismatch`
    - 布局版本不一致 → `LayoutVersionConflict`
    - _Requirements: R28.4, R29.4_

---

# Version 0.5 — 生态基建 + 标准库（post-v0.4，6-8 周）

目标：让 SA 从"能跑通"进化为"LLM 能独立完成完整应用"。核心能力：包管理、标准库、布局标签校验。

## v0.5 任务

- [x] 35. 零信任包管理 `sa.mod` / `sa.lock` / `sa.sum`（R31, R31a–R31g）

  > 完整设计文档：[`docs/package_management.md`](../../../docs/package_management.md)；架构对接：design.md §3.10 / §4.8。

- [x] 35.1 定义 `sa.mod` 文件格式与解析器（`src/pkg/manifest.zig`）
    - 单行扁平 `require <URL> @<ref> sha256:<hash> [grants [...]]`
    - 解析为 `RequireEntry` 结构体（design §4.8）
    - 缺省 grants = `&.{}`（绝对零权限），禁止 nil / magic
    - _Requirements: R31.1_

  - [ ] 35.2 CLI `sa fetch` 哑下载
    - 默认拉到 `./sa_vendor/<URL>/`
    - `-g` 拉到 `~/.sa/pkg/<URL>@<ref>/` 只读
    - 仅 HTTP/Git 文本下载，**不**执行任何 hooks / build / postinstall
    - _Requirements: R31.2, R31a.1, R31a.2, R31b.1_

  - [ ] 35.3 `@import` 解析短路（`src/pkg/resolver.zig`）
    - 顺序：`./sa_vendor/<URL>/` → `~/.sa/pkg/<URL>@<ref>/` → `Trap: PackageNotResolved`
    - 命中全局缓存时通过 `mmap` 只读读取
    - _Requirements: R31a.3, R31a.4_

  - [ ] 35.4 依赖接口与布局自动注入
    - 依赖包的 `.sai` 自动 `@import` 到当前编译单元
    - 依赖包的 `.sal` `#def` 自动注入，带 `pkg_url.FIELD_NAME` 命名空间前缀
    - _Requirements: R31.3, R31.4_

  - [ ] 35.5 重复导出 / 版本冲突 / 预编译产物拒绝
    - 两个依赖包同名 `@export` → 链接期 `Trap: DuplicateExportSymbol`
    - 同一包两个版本被间接依赖 → CLI 报错要求显式选择
    - 拉取目录含 `.so/.dll/.dylib/.a/.lib/.whl/.node` → `Trap: PrecompiledArtifactRejected`
    - _Requirements: R31.5, R31.7, R31b.4_

  - [ ] 35.6 源码 SHA-256 双轨核验
    - 拉取后立刻字节级哈希
    - 与 `sa.mod` 中 `sha256:` 比对，差一比特 → `Trap: UpstreamShaMismatch`
    - _Requirements: R31.6, R31g.3_

  - [x] 35.7 `sa.sum` 全树拍平
    - 自动生成全部传递依赖的哈希记录
    - 任何子树字节变化 → 顶层哈希失配，整棵树物理熔断
    - _Requirements: R31.8, R31b.5_

- [x] 35a. AST X 光扫描与安全信用评分（R31d）

  - [x] 35a.1 实现 `src/pkg/audit.zig`
    - 单遍线性 token 扫描，搜剿 `@sys_*` 调用
    - 单包 ≤ 50ms（MVP）/ ≤ 20ms（stretch）
    - _Requirements: R31d.1_

  - [x] 35a.2 Trust Score 计算（0–100）
    - 100 = pure compute；80 = mem；50 = io；20 及以下 = net / 跨核心
    - _Requirements: R31d.2_

  - [x] 35a.3 报告输出（stdout 文本 + `--format json`）
    - 含等级、权限列表、`upstream_loc`、修复建议
    - _Requirements: R31d.3, R31d.5_

  - [x] 35a.4 `sa audit <URL>` CLI 命令
    - 重新跑扫描，打印同样格式
    - _Requirements: R31d.4_

  - [x]* 35a.5 Audit Score Property 测试 — **P33 (NEW)**
    - 合成三类包（pure / io / net），断言信用分等级与权限列表精确
    - 最少 100 次
    - _Requirements: R31d.2_

- [ ] 35b. 模块级零权限沙箱与 grants 校验（R31c）

  - [ ] 35b.1 实现"包路径反推"
    - 从源码物理路径（`sa_vendor/<URL>/...`）反推所属包
    - 与 `sa.mod` 的 `RequireEntry.grants` 精确匹配
    - _Requirements: R31c.3_

  - [ ] 35b.2 `Trap: UnauthorizedPrimitive` 发射
    - 包内 `@sys_*` 不在 `grants` 列表 → 拒绝生成机器码
    - 错误中精确点出越权原语名 + `upstream_loc` + 当前 grants 列表
    - _Requirements: R31c.1, R31c.2, R31c.4_

  - [ ] 35b.3 跨包能力提升拦截
    - 零权限包 A 调用高权限包 B → `Trap: NonTransitivePrimitive`
    - 在控制流分析阶段实施，不依赖 Referee CapabilityMask
    - _Requirements: R31c.5_

  - [ ]* 35b.4 grants 静态校验 PBT — **P33（同上，复用）**
    - _Requirements: R31c.1, R31c.2, R31c.4_

- [ ] 35c. 破窗确权审判台（R31e）

  - [ ] 35c.1 `BLOCKED_RISK` 内存态机
    - 编译器扫到信用分 ≤ 20 + 越权原语 → 阻塞管线
    - 状态**仅存进程内存**，进程退出蒸发
    - _Requirements: R31e.1, R31e.6_

  - [ ] 35c.2 审判台 banner 输出
    - 醒目标题 + 完整权限列表（带 `upstream_loc`）+ 信用分 + 提示输入完整 URL
    - _Requirements: R31e.2_

  - [ ] 35c.3 完整 URL 字符串校验
    - 不接受 `y`/`n`/简写、不接受任何前缀或裁剪
    - _Requirements: R31e.3_

  - [ ] 35c.4 TTY 探测与 `MissingTtyForConfirmation`
    - `std.os.isatty(stdin) == false` → 立刻退出
    - 防御 `yes |` 管道绕过
    - _Requirements: R31e.4_

  - [ ] 35c.5 拒绝 `--yes` / `--auto-approve` 在 TTY 模式下绕过
    - _Requirements: R31e.7_

  - [ ]* 35c.6 零状态生命周期 PBT — **P35 (NEW)**
    - 验证编译进程退出后状态彻底蒸发
    - 验证审判台**不**修改任何文件（`sa.mod` / `sa.lock` / 全局 / 本地配置）
    - _Requirements: R31e.5, R31e.6_

- [ ] 35d. 指令级哈希钉版与项目级孤岛（R31f）

  - [ ] 35d.1 机器码 SHA-256 计算与 `sa.lock` 写入（`src/pkg/lock.zig`）
    - 审判通过后单独编译该依赖，对生成的机器码字节流计算 SHA
    - 写入项目根的 `sa.lock`，结构按 design §4.8 `LockEntry`
    - _Requirements: R31f.1, R31f.2_

  - [ ] 35d.2 增量哈希命中跳过审判
    - 重新生成机器码，与 `sa.lock` 比对一致 → 直接放行（AOT 红利）
    - 不一致 → `Trap: MachineCodeHashMismatch` + 重弹审判台
    - _Requirements: R31f.3_

  - [ ] 35d.3 项目级孤岛强制
    - `sa.lock` 必须位于项目根；解析器拒绝其它路径
    - `.sa_cache/` 仅本项目可访问；禁止跨项目复用
    - _Requirements: R31f.4, R31f.5, R31f.6_

  - [ ] 35d.4 `sa audit --update-lock` 子命令
    - **唯一**允许写 `sa.lock` 的命令；显式动作
    - _Requirements: R31f.2_

  - [ ] 35d.5 全平台交叉编译 `sa build --all-targets --lock-only`
    - 同时推导 `x86_64-linux-musl` / `x86_64-windows-gnu` / `aarch64-macos` / `wasm32-wasi` 机器码哈希
    - `LockEntry.approved_machine_code_hashes` 多键存储
    - _Requirements: R31f.7_

  - [ ]* 35d.6 项目级孤岛 PBT — **P36 (NEW)**
    - 模拟同机器两个项目共依赖同一高危包，断言审判台各自触发
    - 断言 `~/.sa/pkg/` 不出现 `approved_machine_code_hash`
    - 最少 100 次
    - _Requirements: R31f.4, R31f.6_

  - [ ]* 35d.7 双轨独立性 PBT — **P34 (NEW)**
    - 源码 SHA 一致但机器码变 → 仍熔断
    - 最少 100 次
    - _Requirements: R31.6, R31f.3_

- [ ] 35e. CI/CD 双轨执行与内网/断网模式（R31g）

  - [ ] 35e.1 CI 模式自动探测（`src/pkg/ci.zig`）
    - 信号：`CI=true` / `GITHUB_ACTIONS=true` / `isatty=false` / `--ci`
    - _Requirements: R31g.1_

  - [ ] 35e.2 双轨核验
    - 第一轨：`@sys_*` 在 `grants` 列表？否 → `UnauthorizedPrimitive`
    - 第二轨：源码 SHA == `sa.mod`？否 → `UpstreamShaMismatch`
    - _Requirements: R31g.3_

  - [ ] 35e.3 冷酷熔断 vs 染色放行
    - 默认：发现未审计高危依赖 → 退出码 1
    - `--allow-unaudited-risks`：染色路径，写入 `TAINTED_UNAUDITED_CODE` 元数据 + Job Summary 看板
    - _Requirements: R31g.2_

  - [ ] 35e.4 染色产物运行时警告
    - Referee runtime 探测元数据 → `main()` 入口前 stderr 强行打印三行红字
    - 无法被 `--release` 移除
    - _Requirements: R31g.7_

  - [ ] 35e.5 `sa build --offline` 完全断网
    - 关闭网络模块，仅读 `sa_vendor/`
    - 与 `sa.lock` / `sa.sum` 物理比对
    - _Requirements: R31g.4_

  - [ ] 35e.6 URL 镜像劫持（`src/pkg/mirror.zig`）
    - 来源 1：`SA_MIRROR_<HOST_UPPER>` 进程级环境变量
    - 来源 2：项目本地 `.sa_env` 或 `sa.mod` 的 `[mirrors]` 块
    - 严禁全局配置文件
    - _Requirements: R31g.5_

  - [ ] 35e.7 `Trap: ForbiddenGlobalConfig`
    - 探测 `~/.sa/config.toml` / `~/.sa/mirror.toml` / `/etc/sa/*.toml` 等 → 拒绝启动
    - _Requirements: R31g.6_

  - [ ] 35e.8 全平台 CI 矩阵核验
    - Ubuntu / Windows / macOS Runner 各自算源码 SHA → 与 `sa.mod` 对齐
    - _Requirements: R31g.8_

  - [ ]* 35e.9 CI 模式探测 PBT — **P37 (NEW)**
    - 验证四种信号的非空交集子集均触发 CI 模式
    - 验证 CI 模式下任何 stdin 输入被拒绝
    - 最少 100 次
    - _Requirements: R31g.1, R31g.2, R31e.4_

- [x] 35f. 包管理集成测试基线（design.md §8.5 第 16–27 条）

  - [x] 35f.1 PkgMgr-Fetch-Smoke：基础下载 + 哈希一致 + 不执行源码
  - [x] 35f.2 PkgMgr-Audit-Score：信用分 100/50/12 三档断言
  - [x] 35f.3 PkgMgr-Confirm-Tty：伪 TTY 输入完整 URL 通过
  - [x] 35f.4 PkgMgr-Confirm-NonTty：管道流必报 `MissingTtyForConfirmation`
  - [x] 35f.5 PkgMgr-Lock-Idempotency：第二次跳审判 + 改源码重弹
  - [x] 35f.6 PkgMgr-Sum-Transitive：A→B→C 篡改检测
  - [x] 35f.7 PkgMgr-Offline-Build：拷贝 `sa_vendor/` + `sa.mod` + `sa.lock` 到断网容器
  - [x] 35f.8 PkgMgr-CI-DualTrack：模拟 GitHub Actions 双轨触发
  - [x] 35f.9 PkgMgr-Tainted-Artifact：染色路径产物元数据 + 运行时红字
  - [x] 35f.10 PkgMgr-ForbiddenGlobal：放假全局配置触发 `ForbiddenGlobalConfig`
  - [x] 35f.11 PkgMgr-Mirror-Env：环境变量重定向到内网镜像，进程结束规则消失
  - [x] 35f.12 PkgMgr-PrecompiledRejected：注入 `.so/.dll` 触发 `PrecompiledArtifactRejected`
    - _Requirements: R31, R31a–R31g（全部）_

- [ ] 36. 布局标签校验（R32）

  - [ ] 36.1 `#tag NAME = UNIQUE_ID` 声明
    - Flattener 记录标签为编译期常量
    - _Requirements: R32.1_

  - [ ] 36.2 `alloc N tag NAME` 语法
    - Referee 在寄存器元数据中记录布局标签
    - _Requirements: R32.2_

  - [ ] 36.3 函数签名 `tag NAME` 注解
    - `@func(^d: ptr tag Dog)` 声明期望标签
    - _Requirements: R32.3_

  - [ ] 36.4 调用点标签比对
    - 实参标签与形参标签不匹配 → `Trap: TagMismatch`
    - 无标签寄存器可传给任何函数（向后兼容）
    - _Requirements: R32.4, R32.5_

  - [ ] 36.5 `--no-tag-check` 开关
    - 禁用标签校验（性能敏感场景）
    - _Requirements: R32.7_

  - [ ]* 36.6 标签校验 Property 测试 — **P33 (NEW)**
    - 合法生成器：匹配标签调用，断言通过
    - 注入式：不匹配标签，断言 `TagMismatch`
    - 无标签寄存器传给有标签参数，断言通过
    - 最少 100 次
    - _Requirements: R32.4, R32.5_

- [x] 37. `sa_std` 标准库 v0.1

  - [x] 37.0 SA-facing Zig-backed std facade
    - `sa_std/{io,fs,net,fmt}.sa` 作为只含 `@import` 的模块入口
    - `sa_std/{io,fs,net,fmt}.sai` 声明 Zig-backed `@extern` API
    - `sa_std/{io,fs,net,fmt}.sal` 声明显式布局、错误码和 flag 常量
    - 句柄/缓冲区全部显式传递，并要求调用方显式 `close` / `free` / `flush`
    - 保留 `sa_print_bytes` demo 兼容入口

  - [x] 37.1 `sa_std/string.sa`：字符串操作宏
    - `STR_LEN` / `STR_CONCAT` / `STR_EQ` / `STR_SLICE`
    - 基于胖指针 `[data_ptr | len]` 布局

  - [x] 37.2 `sa_std/vec.sa`：动态数组宏
    - `VEC_NEW` / `VEC_PUSH` / `VEC_GET` / `VEC_LEN` / `VEC_FREE`
    - 基于 `[data_ptr | len | cap]` 布局 + `alloc` 扩容

  - [x] 37.3 `sa_std/hashmap.sa`：哈希表宏
    - 开放寻址法 + FNV-1a 哈希
    - `MAP_NEW` / `MAP_PUT` / `MAP_GET` / `MAP_DEL` / `MAP_FREE`

  - [x] 37.3a `sa_std/hashset.sa`：哈希集合宏
    - 基于现有 `sa_std/hashmap.sa` 封装，值使用非零哨兵
    - `SET_NEW` / `SET_INSERT` / `SET_CONTAINS` / `SET_REMOVE` / `SET_FREE`

  - [x] 37.3b `sa_std/collections/hashset.sa`：集合命名空间入口
    - 仅透出 `../hashset.sa` 作为薄包装

  - [x] 37.4 `sa_std/sort.sa`：排序宏
    - 快速排序（`[MACRO] QSORT %arr, %len, %elem_size, %cmp_fn`）

  - [x] 37.5 `sa_std/io.sa`：IO 便利宏
    - `PRINTLN` / `READ_LINE` / `FORMAT_INT`（基于 `@sys_print` + `@sys_read_file`）

  - [x] 37.6 打包为 `sa_std` 包
    - 创建 `sa_std/sa.pkg` + `sa_std/*.sai`
    - 发布到本地 registry

  - [x] 37.7 `sa_std/time.sa`：时间/日期便利宏
    - `TIME_NOW_NS` / `TIME_NOW_UNIX_S` / `TIME_NOW_UNIX_MS` / `TIME_NOW_UNIX_NS`
    - `TIME_UTC_NOW` / `TIME_SLEEP_MS` / `TIME_SLEEP_NS` / `TIME_DURATION_*`
    - 直连 Zig-backed monotonic / system / UTC calendar ABI

  - [x] 37.8 `sa_std/sync/mutex.sa`：互斥锁宏
    - `MUTEX_NEW` / `MUTEX_LOCK` / `MUTEX_UNLOCK`
    - 基于 `atomic_rmw_xchg` + `sa_time_sleep_ns` 的自旋等待与 release 解锁

  - [x] 37.9 `sa_std/sync/once.sa`：单次初始化宏
    - `ONCE_NEW` / `ONCE_IS_READY` / `ONCE_TRY_CLAIM` / `ONCE_WAIT_READY` / `ONCE_PUBLISH` / `ONCE_GET` / `ONCE_GET_OR_INIT`
    - 基于 `atomic_load` + `cmpxchg` + `sa_time_sleep_ns` 的 OnceCell 懒加载与竞态收敛

  - [x] 37.10 `sa_std/sync/mpsc.sa`：多生产者单消费者通道宏
    - `MPSC_NEW` / `MPSC_FREE` / `MPSC_TRY_SEND` / `MPSC_SEND` / `MPSC_TRY_RECV` / `MPSC_RECV`
    - 基于内联环形缓冲区、原子 head/tail 指针和 slot ready 标志的 bounded MPSC 队列

---

# Version 0.6 — 高可靠性认证（post-v0.5，8-12 周）

目标：让 SA 的 Referee 获得数学可证明的正确性保证，满足 DO-178C Level A / MISRA / 军工审计要求。

## v0.6 任务

- [ ] 38. Referee 形式化规范（R33）

  - [ ] 38.1 提取 Referee 核心状态机为独立的纯函数规范
    - 从 `src/referee/` 中提取 CapabilityMask 转移逻辑为无副作用的纯函数
    - 产出 `formal/referee_spec.lean` 或 `formal/referee_spec.v`（Coq）
    - _Requirements: R33.1_

  - [ ] 38.2 证明健全性（Soundness）
    - 定理：若 Referee 放行指令流 I，则 I 在任何执行路径上不发生 UAF / Double-Free / Memory Leak
    - _Requirements: R33.2_

  - [ ] 38.3 证明完备性（Completeness）
    - 定理：若指令流 I 在所有路径上内存安全，则 Referee 不误报 Trap
    - _Requirements: R33.2_

  - [ ] 38.4 证明终止性（Termination）
    - 定理：对任意有限长度指令流，Referee 在有限步内产出结果
    - _Requirements: R33.2_

  - [ ] 38.5 CI 集成：形式化规范与 Zig 实现同步
    - Referee 代码修改时 CI 要求重新验证 Lean4/Coq 证明
    - _Requirements: R33.4_

- [ ] 39. Referee 硬件化探索（R33.6）

  - [ ] 39.1 将 Referee 位掩码逻辑翻译为 Verilog/VHDL
    - 目标：FPGA 上的硬件所有权检查器原型
    - _Requirements: R33.6_

  - [ ] 39.2 硬件 Referee 与软件 Referee 等价性验证
    - 对同一指令流，硬件与软件产出相同的 Pass/Trap 判决
    - _Requirements: R33.6_

---

# Version 0.7 — 原生单元测试框架（Native Unit Test Framework）

目标：实现 SA-ASM 的原生单元测试支持，提供类似 `cargo test` 的体验，彻底替代基于 Bash/Zig 的外部集成测试调用。

## v0.7 任务

- [x] 40. 编译器前端与测试收集
  - [x] 40.1 支持 `@test "name"()` 声明，含 `ignored` / `should_panic` 修饰符
  - [x] 40.2 验证测试函数签名无参无返（`TestFuncSignatureMismatch`）
  - [x] 40.3 在 Flattener/Verifier 阶段收集测试元数据至 `TestRegistry`（`test_meta.TestList`）

- [x] 41. CLI 与 Test Runner
  - [x] 41.1 扩展 `src/cli.zig` 支持 `sa test`
  - [x] 41.2 支持 `--filter` / `--skip` / `--exact` / `--ignored` / `--include-ignored` 过滤测试
  - [x] 41.3 动态生成测试 harness，使用 `SA_TEST_NAME` 选择目标测试并由子进程隔离执行
  - [x] 41.4 控制台进度打印、隔离进程运行、退出状态判断（含 `should_panic` / signal / launch failure）

- [x] 42. 标准库断言与支持
  - [x] 42.1 增强 `ASSERT_EQ` / `ASSERT_TRUE`：新增 `ASSERT_*_MSG` 诊断宏，支持带文件名、行号及具体 diff 的 `panic_msg`
  - [x] 42.2 提供基础的 Mock 机制（如内存 I/O 缓冲）：新增 `sa_std/testing/mock_io.sal` / `.sa`，提供可 rewind 的内存读写缓冲，并由 `sa test` 回归覆盖写入截断、读取游标和 len/pos 查询

- [ ] 43. 测试用例迁移
  - [ ] 43.1 逐步将 `test_all_300.sh` 中的 demo 转化为原生 `@test` 并用 `sa test` 验证（已有 `tests/unit_framework/feature_suite.sa` 代表性基线；已新增二十八批 demo-derived 覆盖：`04_loop` / `21_while_loop` / `24_factorial` / `25_fibonacci` / `35_iterator_fold`，`10_generics_monomorph` / `18_option_map` / `46_option_default` / `177_unwrap_unwrap_err`，`07_trait_vtable` / `11_tuples` / `12_destructuring` / `13_array_sum` / `14_slice_window` / `17_associated_fn` / `59_method_counter`，`08_closures` / `30_manual_guard_branch` / `33_iterator_map` / `34_iterator_filter` / `40_impl_block_state` / `42_export_visibility` / `45_config_merge` / `60_enum_branch`，`37_newtype` / `38_generic_struct_i32` / `39_generic_enum_i32` / `48_generic_pair` / `63_router_table`，以及 `53_cache_hits` / `54_mem_fill` / `56_state_machine` / `68_parser_tokens` / `69_serializer` / `70_integration_service` / `71_pipeline_stage` / `72_graph_walk`，以及 `73_scene_nodes` / `74_component_store` / `79_metrics` / `80_workflow` / `82_sql_scan` / `83_blob_chunk` / `84_sync_gate` / `85_scheduler_tree` / `87_protocol_frame` / `88_text_index`，以及 `89_job_queue` / `90_app_shell` / `91_db_session` / `92_query_plan` / `93_log_aggregator` / `96_task_orchestrator` / `97_sync_service` / `98_build_pipeline` / `99_release_bundle` / `100_full_app`，以及 `101_custom_drop` / `102_raii_guard` / `103_labeled_break` / `104_if_let_chains` / `105_let_else` / `106_cell_interior_mut` / `107_refcell_dynamic_borrow` / `108_atomic_spin_lock` / `109_atomic_fetch_add` / `110_trait_super_vtable`，以及 `111_extern_c_abi` / `112_raw_pointer_arithmetic` / `113_union_ffi_types` / `114_callback_from_c` / `115_opaque_pointers` / `116_va_list_variadic` / `118_global_mutable_state` / `119_simd_intrinsics` / `120_volatile_memory_access`，以及 `121_rwlock_reader_writer` / `122_condvar_wait_notify` / `123_barrier_sync` / `124_thread_local_storage` / `125_once_cell_lazy` / `126_mpmc_channel` / `127_hazard_pointers` / `128_rcu_read_copy_update` / `129_seqlock_optimistic` / `130_park_unpark_thread`，以及 `131_waker_vtable_mechanics` / `132_pinning_and_unpin` / `133_select_macro_race` / `134_join_all_futures` / `135_async_streams` / `136_executor_task_queue` / `137_io_uring_submission` / `138_epoll_kqueue_event` / `139_cancellation_safety` / `140_yield_now_suspend`，以及 `141_dynamically_sized_types` / `142_zero_sized_types` / `143_never_type_diverge` / `144_phantom_data_marker` / `145_opaque_type_alias` / `146_never_type_fallback` / `147_custom_dst_pointers` / `148_transparent_repr` / `149_packed_repr` / `150_c_repr_alignment`，以及 `151_global_alloc_trait` / `152_memory_layout_struct` / `153_box_into_raw` / `154_box_from_raw` / `155_arena_allocator_bump` / `156_slab_allocator_freelist` / `157_aligned_alloc_simd` / `158_custom_dst_alloc` / `159_mem_forget_leak` / `160_manually_drop_union`，以及 `161_generic_associated_types` / `162_auto_traits_send_sync` / `163_object_safety_rules` / `164_trait_upcasting` / `165_blanket_impl_resolution` / `166_specialization_fallback` / `167_const_generics_expansion` / `168_type_alias_impl_trait` / `169_negative_impls` / `170_marker_traits`，以及 `171_anyhow_dynamic_error` / `172_eyre_color_eyre` / `173_catch_unwind_panic` / `174_backtrace_capture` / `175_thiserror_macro_derive` / `176_result_flattening` / `178_panic_hook_override` / `179_assert_macro_expansion` / `180_try_trait_v2`，以及 `181_file_descriptor_raii` / `182_mmap_memory_mapping` / `183_signal_handling_setup` / `184_pthread_spawn_join` / `185_dynamic_lib_dlopen` / `186_sqlite_c_api_binding` / `187_opengl_context_swap` / `188_websocket_frame_parse` / `189_protobuf_varint_decode` / `190_base64_encode_simd`，以及 `191_macro_rules_ast_emit` / `192_proc_macro_derive_ast` / `193_attribute_macro_rewrite` / `194_cfg_conditional_compilation` / `195_build_script_codegen` / `196_lto_link_time_opt` / `197_profile_guided_opt` / `198_control_flow_guard_cfi` / `199_address_sanitizer_asan` / `200_sa_asm_quine`，以及 `201_pkg_manifest_basic` / `202_pkg_dependencies_local` / `203_pkg_dependencies_git` / `204_pkg_dependencies_registry` / `205_pkg_cyclic_dependency_reject` / `206_pkg_version_resolution` / `207_pkg_multiple_versions_conflict` / `208_pkg_dev_dependencies` / `209_pkg_build_dependencies` / `210_pkg_workspace_root`，以及 `211_pkg_workspace_inheritance` / `212_pkg_feature_flags` / `213_pkg_default_features` / `214_pkg_target_specific_deps` / `215_pkg_patch_override` / `216_pkg_profile_release` / `217_pkg_profile_debug` / `218_pkg_metadata_custom` / `219_pkg_bin_multiple` / `220_pkg_lib_dynamic`，以及 `221_mod_relative_import` / `222_mod_absolute_import` / `223_mod_visibility_private` / `224_mod_reexport_pub_use` / `225_mod_namespace_prefix` / `226_mod_cyclic_import_detect` / `227_mod_shadowing_prevention` / `228_mod_iface_separation` / `229_mod_layout_injection` / `230_mod_std_prelude`，以及 `231_mod_directory_module` / `232_mod_conditional_import` / `233_mod_alias_import` / `234_mod_unused_import_lint` / `235_mod_transitive_dependency` / `236_mod_extern_block_grouping` / `237_mod_inline_submodule` / `238_mod_path_resolution_order` / `239_mod_version_suffix_isolation` / `240_mod_entry_point_override`，以及 `241_contract_layout_stability` / `242_contract_opaque_struct` / `243_contract_sig_mismatch_link` / `244_contract_vtable_export` / `245_contract_generic_monomorph_share` / `246_contract_semver_minor_update` / `247_contract_semver_major_break` / `248_contract_ffi_boundary_trust` / `249_contract_macro_export` / `250_contract_const_export`，以及 `251_contract_resource_ownership` / `252_contract_error_code_mapping` / `253_contract_callback_registration` / `254_contract_plugin_system` / `255_contract_memory_allocator_swap` / `256_contract_panic_handler_propagate` / `257_contract_log_facade` / `258_contract_thread_local_isolation` / `259_contract_static_init_order` / `260_contract_deprecated_warning`，以及 `261_build_rs_codegen_saasm` / `262_build_bindgen_c_header` / `263_build_asset_bundling` / `264_build_env_var_injection` / `265_build_custom_linker_script` / `266_build_pre_compile_hook` / `267_build_post_compile_hook` / `268_build_cross_compile_wasm` / `269_build_cross_compile_windows` / `270_build_sysroot_custom`，以及 `271_build_optimization_passes` / `272_build_sanitizer_flags` / `273_build_test_harness` / `274_build_benchmark_runner` / `275_build_doc_generator` / `276_build_incremental_caching` / `277_build_parallel_compilation` / `278_build_reproducible_builds` / `279_build_artifact_caching_remote` / `280_build_ci_cd_integration`，以及 `281_ffi_link_system_libc` / `282_ffi_link_static_c_lib` / `283_ffi_link_dynamic_c_lib` / `284_ffi_pkg_config_integration` / `285_ffi_objective_c_framework` / `286_ffi_rust_staticlib_integration` / `287_ffi_zig_export_integration` / `288_ffi_cxx_name_mangling` / `289_ffi_opaque_handle_passing` / `290_ffi_callback_thunk`，以及 `291_eco_wasm_host_imports` / `292_eco_wasm_memory_export` / `293_eco_embedded_no_os` / `294_eco_os_kernel_module` / `295_eco_bpf_ebpf_bytecode` / `296_eco_gpu_ptx_shader` / `297_eco_game_engine_ecs` / `298_eco_cryptography_simd` / `299_eco_language_server_protocol` / `300_eco_sa_lang_registry_publish`；尚未全量迁移）

---

# Version 0.6 — SA 零信任列式数据库（12 周）

目标：实现 R34 需求，交付一个与包管理同构的列式数据库引擎，支持预编译查询、SHA-256 锁版、权限 X 光扫描、零拷贝沙箱执行、无锁并发、Blob Arena、冷热分层。

## v0.6 任务

### M1：Schema + 列存 + Arena MemTable + Insert（W1–W3）

- [ ] 1. 实现 `.sadb-schema` 编译器（`src/db/schema.zig`）
  - [ ] 1.1 扫描 `#def COL_*_STRIDE` 与 `#def TABLE_*_ROW_BYTES`
  - [ ] 1.2 生成 `.sai` 接口文件（纯文本 `#def` 副本）
  - [ ] 1.3 验证容量（`MAX_ROWS * TABLE_ROW_BYTES ≤ 64GB`）
  - _Requirements: R34.1, R2.4_

- [ ] 2. 实现 SoA 列存与 MemTable Arena（`src/db/arena.zig`）
  - [ ] 2.1 Zig `ArenaAllocator` 包装（Append-Only，64MB 阈值）
  - [ ] 2.2 `writev` 系统调用落盘（整块写入磁盘）
  - [ ] 2.3 不可变段文件格式（`<table>.col<i>.<seg>.dat` + `<table>.meta`）
  - [ ] 2.4 段内 SoA 列式布局
  - _Requirements: R34.1, R34.2_

- [ ] 3. 实现 Insert 算子（`src/db/exec.zig` 初版）
  - [ ] 3.1 `atomic_rmw_add global_len, 1` 无锁自增游标
  - [ ] 3.2 多列并发写入（`mul + ptr_add + store`）
  - [ ] 3.3 容量检查与 OOM 处理
  - _Requirements: R34.5, R2.7_

- [ ] 4. 单元测试与基准（`tests/db/arena.zig`）
  - [ ] 4.1 Insert 吞吐基线（目标 ≥ 1M rows/sec）
  - [ ] 4.2 MemTable → 段落盘的正确性验证

### M2：Blob Arena + Bump 分配（W4）

- [ ] 5. 实现 Blob Arena（`src/db/blob.zig`）
  - [ ] 5.1 Bump Allocator（纯追加，无碎片）
  - [ ] 5.2 `blob_handle = u64 = (seg_id:24 << 40) | offset:40` 位布局
  - [ ] 5.3 墓碑标记删除（1 字节标志位）
  - [ ] 5.4 段压缩触发（死亡比例 ≥ 50%）
  - _Requirements: R34.6_

- [ ] 6. Blob 写入范式（SA-ASM）
  - [ ] 6.1 `@write_blob_text` 完整实现（原子 bump 指针 + 容量检查）
  - [ ] 6.2 与 Insert 的集成（blob_handle 列写入）
  - _Requirements: R34.6_

- [ ] 7. 单元测试（`tests/db/blob.zig`）
  - [ ] 7.1 Blob 分配与释放正确性
  - [ ] 7.2 段压缩的数据完整性

### M3：查询模块编译 + SHA-256 注册 + X 光扫描（W5–W6）

- [ ] 8. 查询模块编译（`src/db/qmod.zig`）
  - [ ] 8.1 `.query.sa` → `<sha256>.qmod` 二进制编译
  - [ ] 8.2 源码 SHA-256 哈希计算与注册
  - [ ] 8.3 查询模块注册表（内存 HashMap）
  - _Requirements: R34.2_

- [ ] 9. Referee X 光扫描扩展（`src/db/referee_db.zig` + hook 进 `src/verifier.zig`）
  - [ ] 9.1 解析 `grants [db_read:tbl, db_write:tbl, db_atomic_cursor:tbl, db_alloc_blob:arena]`
  - [ ] 9.2 遍历查询模块指令流，校验 `load` / `store` / `atomic_rmw_*` 权限
  - [ ] 9.3 违规返回 `Trap: DbCapabilityEscalation`（附 `upstream_loc`）
  - _Requirements: R34.3, R9.3_

- [ ] 10. 单元测试（`tests/db/qmod.zig`）
  - [ ] 10.1 权限白名单校验（正常 + 越权场景）
  - [ ] 10.2 SHA-256 哈希稳定性

### M4：mmap 沙箱 + SIGSEGV handler + Trap 上报（W7）

- [ ] 11. 列基址注入与 mmap 映射（`src/db/exec.zig` 完整版）
  - [ ] 11.1 `@ffi_wrapper db_inject_cols` 实现
  - [ ] 11.2 mmap `MAP_PRIVATE | PROT_READ` 配置
  - [ ] 11.3 列基址作为 `&col: ptr` 借用传入查询模块
  - _Requirements: R34.4, R7_

- [ ] 12. SIGSEGV handler 与越权保护
  - [ ] 12.1 libc SIGSEGV 信号处理
  - [ ] 12.2 越权写入检测与进程终止
  - [ ] 12.3 `Trap: DbMemoryGuardViolation` 上报
  - _Requirements: R34.4_

- [ ] 13. 单元测试（`tests/db/exec.zig`）
  - [ ] 13.1 越权读写的 SIGSEGV 捕获
  - [ ] 13.2 合法读写的正常执行

### M5：CLI 子命令 + ingest + snapshot（W8）

- [ ] 14. CLI 子命令分发（`src/db/cli_db.zig` + hook 进 `src/cli.zig`）
  - [ ] 14.1 `sa db init <table>.sadb-schema`
  - [ ] 14.2 `sa db register <query>.sa`
  - [ ] 14.3 `sa db exec <sha256> --params <file>`
  - [ ] 14.4 `sa db ingest <table> <csv|jsonl>`
  - [ ] 14.5 `sa db snapshot <table>`
  - [ ] 14.6 `sa db restore <table> <epoch>`
  - [ ] 14.7 `sa db inspect <sha256>`
  - [ ] 14.8 `sa db compact <table>`
  - [ ] 14.9 `sa db lock <table>`
  - [ ] 14.10 `sa db verify <table>`
  - _Requirements: R34.11_

- [ ] 15. Snapshot 与恢复（`src/db/snapshot.zig`）
  - [ ] 15.1 Epoch 快照记录（全局 epoch 号 + 段列表）
  - [ ] 15.2 崩溃恢复（扫描 `.meta` 重建 MemTable 状态）
  - _Requirements: R34.8_

- [ ] 16. 单元测试（`tests/db/cli.zig`）
  - [ ] 16.1 各子命令的基本功能
  - [ ] 16.2 snapshot/restore 的一致性

### M6：冷热分层 + Zstd 压缩 + S3 落冷（W9–W10）

- [ ] 17. 冷热分层策略（`src/db/compact.zig`）
  - [ ] 17.1 后台线程定期扫描段 mtime
  - [ ] 17.2 热数据（7 天）Pin to RAM
  - [ ] 17.3 温数据（1 月）mmap NVMe
  - [ ] 17.4 冷数据（1 年+）Zstd 压缩落 S3
  - _Requirements: R34.7_

- [ ] 18. Zstd 压缩与 S3 集成
  - [ ] 18.1 Zstd 字典压缩（体积目标 10–15%）
  - [ ] 18.2 S3 API 集成（可选本地 mock）
  - [ ] 18.3 按需解压（冷数据访问时）

- [ ] 19. 单元测试（`tests/db/compact.zig`）
  - [ ] 19.1 分层策略的正确性
  - [ ] 19.2 压缩率验证

### M7：测试集 + 双 11 抢购 demo（W11–W12）

- [ ] 20. 完整单元测试套件（`tests/db/`）
  - [ ] 20.1 12 条 Trap 错误码的边界覆盖
  - [ ] 20.2 并发冲突（乐观锁失败）
  - [ ] 20.3 容量溢出（Blob OOM / 行游标溢出）
  - [ ] 20.4 数据完整性（Insert + Query + Snapshot）

- [ ] 21. 双 11 抢购 demo（`demos/flash_sale.sa`）
  - [ ] 21.1 10 万 SKU，初始库存 1000
  - [ ] 21.2 单线程 Insert + Update（扣库存）+ Query（统计）
  - [ ] 21.3 性能目标：1KW TPS 扣减（单线程）
  - [ ] 21.4 查询延迟 ≤ 10ms（p99）

- [ ] 22. 性能基线与文档
  - [ ] 22.1 1 亿行 SoA 列扫描 ≤ 200ms（AVX-512 启用）
  - [ ] 22.2 Insert 吞吐 ≥ 1M rows/sec
  - [ ] 22.3 生成 `docs/database.md` 落地文档

### 新增 Trap 错误码（`src/db/trap_db.zig` + 登记到 `docs/errorcode.md`）

- [ ] 23. 12 条新 Trap 错误码
  - [ ] 23.1 `DbCapabilityEscalation` — 查询模块越权 load/store
  - [ ] 23.2 `DbMemoryGuardViolation` — mmap 越界 SIGSEGV
  - [ ] 23.3 `DbBlobArenaOOM` — Bump 分配器写满
  - [ ] 23.4 `DbConcurrencyConflict` — 行版本号 cmpxchg 失败
  - [ ] 23.5 `DbSchemaMismatch` — 数据列类型与 schema 不符
  - [ ] 23.6 `DbCursorOverflow` — `global_len` ≥ MAX_ROWS
  - [ ] 23.7 `DbColumnTypeMismatch` — qmod 用错列类型偏移
  - [ ] 23.8 `DbQueryHashUnknown` — EXEC 一个未注册的 SHA-256
  - [ ] 23.9 `DbBlobHandleInvalid` — blob_handle 段号或偏移越界
  - [ ] 23.10 `DbSnapshotCorrupted` — 段文件 SHA-256 校验失败
  - [ ] 23.11 `DbDuplicateRegister` — 同 SHA-256 重复注册不同 grants
  - [ ] 23.12 `DbForbiddenSqlString` — 任何运行时 SQL 字符串入口
  - _Requirements: R34.12_

---

## v0.8 网络引擎 `sa_netx`（io_uring + per-core sharded SPSC + DMA 扇出）

> 版本号说明：v0.7 已规划为"原生单元测试框架"（见本文件 Version 0.7 章节），故网络引擎排期至 v0.8。
>
> 实施目录：`src/runtime/sa_net_uring.zig`（新增，与 `sa_std.zig` 并列）+ `sa_std/netx.*` 三件套。**零修改 `flattener/` / `referee/` / `verifier.zig` / `common/` / 现有 `sa_std.zig` 的 117 个 `sa_*` export / 现有 `sa_std/net.*` / `sa_std/sync/mpsc.*` / `sa_std/core/mem.*`**。
>
> 详细蓝图：`docs/network_engine_plan.md` v0.9+。

### M0：编译器与契约准备（W0）

- [ ] 44. 确认 SA-ASM ISA 足够支撑 Ticket 偏移直读
  - [ ] 44.1 复查 `src/common/instruction.zig` 中 `load ... as u32/u64`、`ptr_add`、`atomic_*` 全部就绪
  - [ ] 44.2 确认无需新增向量算子（`v_load / v_xor / v_broadcast` 留给 Zig `@Vector` 完成）
  - [ ] 44.3 确认无需新增 `bitcast` 指令（用 `ptr_add` + `load as T` 替代）
  - _Requirements: R35.4, R35.6_

- [x] 45. 登记 SA 端契约骨架（仅文件骨架，不接入 build）
  - [x] 45.1 创建 `sa_std/netx.sai`：7 条 `@extern` 声明
  - [x] 45.2 创建 `sa_std/netx.sal`：`Ticket_*` 偏移 + `NetxProto_*` 枚举
  - [x] 45.3 创建 `sa_std/netx.sa`：`@import` 上面两个文件
  - _Requirements: R35.10_

### M1：物理基座（W1–W3）

- [ ] 46. 新增 `src/runtime/sa_net_uring.zig` 骨架
  - [ ] 46.1 `ConnectionSlot align(64) struct`：fd + 9 态枚举 + 4 KB inline buffer + overflow 链 + `inflight_zc` 计数
  - [ ] 46.2 `SlotPool`：`mmap(MAP_POPULATE | MAP_HUGETLB)` 一次性预分配 10⁵ – 10⁶ 槽位
  - [ ] 46.3 Zig 侧零分配审计:用 `@memset` 清零，禁止调用 `sa_std/core/mem.sa`
  - _Requirements: R35.1, R35.2_

- [ ] 47. `io_uring` reactor 骨架
  - [ ] 47.1 `IoUring.init` per-core 实例 + `sched_setaffinity` 绑核
  - [ ] 47.2 `IORING_OP_ACCEPT_MULTISHOT` 单 SQE 持续产 CQE
  - [ ] 47.3 `IORING_OP_RECV_MULTISHOT` + `IORING_REGISTER_PBUF_RING` provided buffer 环
  - [ ] 47.4 编译期探测 `RECV_MULTISHOT` / `SEND_ZC` 内核能力，运行时 fallback
  - _Requirements: R35.3_

- [ ] 48. 槽位生命周期九态状态机
  - [ ] 48.1 实现 `Free → Accepting → Handshake → (Http | WebSocket | RawBinary)` 转换
  - [ ] 48.2 实现 `Reading / HalfClosed / Closing` 三态保护重入与半关闭
  - [ ] 48.3 `IORING_OP_TIMEOUT` 配对 idle / handshake 清扫
  - _Requirements: R35.9_

- [ ] 49. M1 验收
  - [ ] 49.1 预分配 100W Slot 启动无 OOM（`ulimit -v` 配套）
  - [ ] 49.2 TCP 握手 + echo 跑通
  - [ ] 49.3 `perf` 抓 `__libc_malloc` 调用次数 == 0（稳态运行 60s）
  - _Requirements: R35.2, R35.3_

### M2：HTTP/WS 拆包（W4–W5）

- [ ] 50. Zig 侧零分配 DFA HTTP 解析器
  - [ ] 50.1 `@Vector(32, u8)` 扫描 `\r\n` 与 `:` 分隔符
  - [ ] 50.2 不创建 `HashMap<String, String>`，仅记录 `(offset, len)` 二元组
  - [ ] 50.3 输出 `Ticket` 紧凑结构压入入站环
  - _Requirements: R35.4_

- [ ] 51. WebSocket 零分配协议升级
  - [ ] 51.1 识别 `Upgrade: websocket` → 栈上 `Base64(SHA1(key + magic))`
  - [ ] 51.2 `slot.state` 由 `Http` 拨至 `WebSocket`，fd / buffer 不迁移
  - _Requirements: R35.6_

- [ ] 52. SIMD 暴力解掩码（Zig `@Vector`）
  - [ ] 52.1 `@Vector(16, u8)` 基线（SSE2/NEON）
  - [ ] 52.2 `@Vector(32, u8)` x86_64 AVX2 路径
  - [ ] 52.3 标量尾收尾（≤ 15 字节）
  - [ ] 52.4 fuzz 1M 次 random payload + mask 不 panic
  - [ ] 52.5 perf 热路径占比 < 1%
  - _Requirements: R35.4_

- [ ] 53. M2 验收
  - [ ] 53.1 `curl http://localhost:PORT/` 通
  - [ ] 53.2 `wscat -c ws://localhost:PORT/` 握手通
  - [ ] 53.3 端到端 echo（HTTP + WS）跑通
  - _Requirements: R35.4, R35.6_

### M3：三环 + SA 贯通（W6–W7）

- [ ] 54. per-core sharded SPSC 三环
  - [ ] 54.1 Inbound Ring：reactor → SA（SPSC，每 reactor↔SA-core 一对）
  - [ ] 54.2 Execution Ring：SA-ASM 算子消费 Ticket
  - [ ] 54.3 Outbound Ring：SA → reactor（SPSC）
  - [ ] 54.4 与现有 `sa_std/sync/mpsc.sa` 共存：MPSC 仅作跨分片回收慢路径
  - _Requirements: R35.5_

- [ ] 55. 7 条 `sa_netx_*` FFI 接入
  - [ ] 55.1 `sa_netx_init(slot_capacity, reactor_count)`
  - [ ] 55.2 `sa_netx_listen(&host, host_len, port)`
  - [ ] 55.3 `sa_netx_recv_ticket(reactor_id, &out_ticket)`
  - [ ] 55.4 `sa_netx_push_outbound(reactor_id, slot_id, &msg, len)`
  - [ ] 55.5 `sa_netx_broadcast(reactor_id, &slot_ids, n, &msg, len)`
  - [ ] 55.6 `sa_netx_close_slot(slot_id)`
  - [ ] 55.7 `sa_netx_shutdown()`
  - _Requirements: R35.10_

- [ ] 56. 背压策略实施
  - [ ] 56.1 入站环满 → reactor 停 arm `RECV_MULTISHOT`（TCP 窗口自然收窄）
  - [ ] 56.2 出站环满 → `sa_netx_push_outbound` 返回 `EAGAIN`
  - [ ] 56.3 验证：满载注入 1M req/s，10s 内零 OOM、零内存分配
  - _Requirements: R35.8_

- [ ] 57. Raw Binary RPC 路径
  - [ ] 57.1 Ticket 偏移直读：`load payload+0 as u32` / `load payload+4 as u64`
  - [ ] 57.2 SA-ASM 业务核心吃 Ticket < 80 ns
  - _Requirements: R35.4_

- [ ] 58. M3 验收
  - [ ] 58.1 `examples/netx_echo/echo.sa` 端到端跑通
  - [ ] 58.2 业务核心吃 Ticket 时间 ≤ 80 ns（micro-benchmark）
  - _Requirements: R35.5, R35.10_

### M4：K1 跑分（对标 Bun ping-pong，W8–W9）

- [ ] 59. ping-pong 基准实施
  - [ ] 59.1 `examples/netx_echo/ws_bench.sa`：32 client × 64B 双向
  - [ ] 59.2 **不启用 SEND_ZC**：只用 `SEND` + provided buffer + sharded SPSC + SIMD unmask
  - [ ] 59.3 CPU pinning + busy-poll 调优
  - _Requirements: R35.7, R35.12_

- [ ] 60. M4 验收
  - [ ] 60.1 单机 32 client 64B ping-pong **≥ 2,500,000 msg/s**（持平 Bun v1.2）
  - [ ] 60.2 CPU 占用 ≤ 50%
  - [ ] 60.3 KPI 表标注内核版本与 Bun 版本
  - _Requirements: R35.12 (K1)_

### M5：SEND_ZC + DMA 扇出（W10）

- [ ] 61. 广播切片生命周期
  - [ ] 61.1 `BroadcastArena`：算子 Arena 内生成 `[WS Header | Payload]` 连续切片
  - [ ] 61.2 `gen: u32` 代纪元号 + `refcount: u16`（= fanout_count）
  - [ ] 61.3 SQE `user_data` 编码 `(gen, slot_id)`，notification CQE 触发 refcount--
  - [ ] 61.4 refcount 归零 → 切片归还 Arena
  - _Requirements: R35.7_

- [ ] 62. `IORING_OP_SEND_ZC` 批量轰炸
  - [ ] 62.1 自动选路：单 payload ≥ 1.5 KB **或** `fanout_count ≥ 8` **或** `NETX_FLAG_BROADCAST` → SEND_ZC；否则 SEND
  - [ ] 62.2 SQ 容量 4096–32768，10⁵ 扇出分批 enter
  - [ ] 62.3 共享物理切片：所有 SQE `addr` 指向同一内存
  - [ ] 62.4 内核版本 < 6.0 降级为 `SENDMSG + MSG_ZEROCOPY` 或 `sendmmsg`
  - _Requirements: R35.7_

- [ ] 63. M5 验收（K2 跑分）
  - [ ] 63.1 1 source × 10⁵ receivers × 1 KB payload **≥ 30 GB/s** 总吞吐（≥ 10× Bun 同场景）
  - [ ] 63.2 CPU 占用 ≤ Bun 同场景的 30%
  - [ ] 63.3 ZC notification CQE 必须全部回收，无 leak（valgrind / mtrack 抽检）
  - _Requirements: R35.12 (K2)_

### M6：反向超越 Bun（W11–W12）

- [ ] 64. 极限调优
  - [ ] 64.1 `IORING_SETUP_SQPOLL` 选择性启用（benchmark / 单租户裸金属）
  - [ ] 64.2 reactor busy-poll 节流 + L1 cache 亲和审计
  - [ ] 64.3 零分配审计：perf 抓 `mmap/brk` 调用 == 0
  - _Requirements: R35.2, R35.3, R35.12_

- [ ] 65. M6 验收
  - [ ] 65.1 单机 32 client 64B ping-pong **≥ 3,500,000 msg/s**（≥ 1.4× Bun）
  - [ ] 65.2 KPI 报告锁定内核版本 / Bun 版本 / 硬件型号
  - _Requirements: R35.12 (K1 stretch)_

### v0.8.5 HTTP 插件增强与 OpenAI 转发 (HubProxy)

- [ ] 65a. `sa_http_client` 插件实现
  - [x] 集成 Zig `std.http.Client`
  - [x] 暴露 `sa_http_req_send` 及流式 Reader
  - [x] 支持 `POST`、自定义 `--header`、请求 body 透传和本地 loopback 回归
  - [x] 实现 HTTPS/TLS 出站请求
  - 说明：当前已完成 HTTP GET / POST / stream / TLS / runtime descriptor / skills 路径；301 HTTP client SAASM demo 已纳入 `cli-special` 主验收并通过 `zig build test --summary all`
- [ ] 65b. `sa_http_server` 高层级封装
  - [x] 基于 `sa_net_uring` 实现 AOT 静态路由
  - [x] 实现 Header 注入与中间件流水线
  - [x] 请求体读取、路由分发和 SSE/chunked 透传
  - 说明：302 HTTP server SAASM demo 已纳入 `cli-special` 主验收并通过 `zig build test --summary all`
  - [ ] 65c. HubProxy 端到端实现
  - [ ] 实现可运行 `main()` 入口，加载 `upstream.json` 并监听本地端口
  - [ ] 实现 `/v1/chat/completions` 与 `/v1/responses` 两条转发路由
  - [ ] 支持 SSE / chunked 流式响应透传，不允许回退为一次性缓冲假流
  - [ ] HubProxy 仅作为示例工程存在，不回写主线程命令分发逻辑
  - [ ] 性能目标：转发延迟损耗 < 1ms

### 文档与生态登记

- [ ] 66. `docs/network_engine_plan.md` 维护至 v0.9+（已含 §0–§8）
  - [ ] 66.1 §0 边界裁决（TLS 由前置代理终结，HTTP/2/3 本期不做）
  - [ ] 66.2 §0.2 项目目录架构（落到现仓库 src/runtime / sa_std / examples / docs）
  - [ ] 66.3 §6 性能模型与 K1/K2 双轨 KPI
  - _Requirements: R35.13_

- [ ] 67. `docs/std_rfc.md` 登记 `sa_netx_*` 加入标准库的 RFC
  - [ ] 67.1 列出 7 条 FFI + Ticket layout
  - [ ] 67.2 标注与现有 `sa_std.net` 的并行关系
  - _Requirements: R35.13_

### 性能基线与回归

- [ ] 68. 持续 benchmark 基线
  - [ ] 68.1 K1 / K2 双轨每次发版跑分入库
  - [ ] 68.2 KPI 回退 ≥ 5% 触发 CI 红灯
  - [ ] 68.3 内核版本兼容矩阵：6.0 / 6.1 / 6.6 LTS / 6.10
  - _Requirements: R35.12_

---

## v0.9 SAX 前端 UI 方言（Symbolic Affine XML，全栈 SA 闭环）

> 实施目录：`src/sax/`（已存在 `parser.zig` / `lowerer.zig` / `airlock_gen.zig` / `sax_rules.zig` / `cli.zig` / `mod.zig`）+ `docs/sax_*.md` 四件套（已存在）。**零修改 `src/flattener/` / `src/common/` / `src/emit_wasm/`**；`src/referee/` / `src/verifier.zig` 仅追加 SAX 规则 hook。**SA-ASM ISA 零扩展**。
>
> 详细蓝图：`docs/sax_whitepaper.md` / `docs/sax_design.md` / `docs/sax_airlock.md` / `docs/sax_syntax.md`。

### Phase 1：MVP 基础渲染闭环（W1–W8）

#### M0：契约与降级蓝图确认（W0）

- [ ] 69. 确认 SAX 不需要扩展 SA-ASM ISA
  - [x] 69.1 复查 `src/common/instruction.zig`，所有 SAX 降级目标指令（`alloc / store / load / call / br / jmp / ret / !release`）就绪
  - [ ] 69.2 确认 `src/emit_wasm/` 支持 `wasm32-unknown-unknown` 目标（非 WASI）
  - [x] 69.3 复查外部插件 `/home/vscode/projects/sa_plugins/sa_plugin_sax/src/sax/` 五件套结构，登记 SAX Parser → SA 文本流的降级契约
  - _Requirements: R36.1, R36.12_

#### M1：SAX Parser 与 Lowerer（W1–W3）

- [x] 70. SAX Parser 完整实现（外部插件 `src/sax/parser.zig`）
  - [x] 70.1 解析 `<Component name="X">` 顶层结构
  - [x] 70.2 解析 `<state>` 块：一行一变量，支持 `i64 / i32 / f64 / i1 / ptr / alloc N` 字面/标注
  - [x] 70.3 解析 DOM 树：标签 + 属性 + `{expr}` 插值 + `onevent={^handler}` 事件
  - [x] 70.4 解析 `@handler:` 函数体（直通 SA-ASM 文本，不变换）
  - [x] 70.5 解析尾部 `!var1 !var2 ...` 释放序列
  - [x] 70.6 **不构造宿主 AST**：解析结果由插件 Lowerer 直接输出 `.sa` 文本流
  - _Requirements: R36.1, R36.2, R36.3_

- [x] 71. SAX Lowerer 完整实现（外部插件 `src/sax/lowerer.zig`）
  - [x] 71.1 状态变量 → `alloc Component_SIZE` + 固定偏移 `store` 初始化
  - [x] 71.2 DOM 树 → `@ffi_wrapper` 内 `sax_dom_create / sax_dom_append_child / sax_dom_set_attr / sax_dom_set_text` 调用序列
  - [x] 71.3 `{expr}` 插值 → typed `load state+offset` + `sax_itoa` / `sax_ftoa_bits` + `sax_dom_set_text(node, &buf, len)`
  - [x] 71.4 `onclick={^handler}` → `sax_dom_bind_event(node, "click", handler_export, ctx)`，handler 走 WASM function export 名称
  - [x] 71.5 自动生成 `sax_X_init` / `sax_X_render` / `sax_X_destroy` 三组 `@export` 函数
  - [x] 71.6 释放序列 `!var` → `destroy` 中释放 state-owned ptr / state / dom / ctx
  - _Requirements: R36.2, R36.3_

- [ ] 72. WASM 目标切换
  - [ ] 72.1 `src/sax/cli.zig` 强制目标为 `wasm32-unknown-unknown`（非 WASI）
  - [ ] 72.2 复用 `src/emit_wasm/` 后端，零修改
  - [x] 72.3 验证：SAX demo 产物 `app.wasm` 体积 < 50 KB（typed demo 2583 bytes；reactive dashboard 4034 bytes）
  - 说明：当前外部插件实测走 `LLVM-C .sa.bc + zig build-exe -target wasm32-freestanding -fno-entry --import-symbols` 浏览器模块路径，不走旧文档里的手写 `src/emit_wasm/` 目标。
  - _Requirements: R36.12_

#### M2：Referee 扩展（W4）

- [ ] 73. SAX 7 条专属 Trap 规则（`src/sax/sax_rules.zig`）
  - [ ] 73.1 `SaxStateLeak`：销毁函数出口 `<state>` 仍 `Active` → Trap
  - [ ] 73.2 `SaxEventEscape`：`^handler` 引用跨 `<Component>` 函数 → Trap
  - [ ] 73.3 `SaxRenderOutsideHandler`：`call @render()` 出现在 `@handler` 外 → Trap
  - [ ] 73.4 `SaxInvalidInterpolation`：`{expr}` 包含 `^` / `!` → Trap（Parser 阶段）
  - [ ] 73.5 `SaxStateWriteFromOutside`：组件外部代码写 `<state>` 内存槽 → Trap
  - [ ] 73.6 `SaxUnknownTag`：DOM 标签不在 HTML5 白名单 → Trap（Parser 阶段）
  - [ ] 73.7 `SaxUnknownEvent`：事件不在白名单 → Trap（Parser 阶段）
  - [ ] 73.8 每条 Trap 携带 `component / handler / tag / event / upstream_loc` 诊断字段
  - _Requirements: R36.4, R36.5, R36.6, R36.7, R36.8, R36.9_

- [ ] 74. Referee hook 接入（`src/verifier.zig` 追加 SAX 规则调用）
  - [ ] 74.1 在 `verifyBody` 主循环内添加 SAX 规则分发（仅当输入源标记为 SAX 派生）
  - [ ] 74.2 不破坏现有 23 条 Trap 规则
  - _Requirements: R36.9_

#### M3：DOM Airlock 与 HTML Shell（W5–W6）

- [ ] 75. Airlock JS 自动生成（外部插件 `src/sax/airlock_gen.zig`）
  - [x] 75.1 ~20 个白名单 API 全部覆盖（查询 / 创建 / 内容 / 属性 / 事件 / 路由 / HTTP / 工具）
  - [x] 75.2 节点句柄走整数 ID（Airlock 内部映射表，WASM 不可伪造）
  - [x] 75.3 `sax_dom_set_text` 强制走 `textContent`（防 XSS）
  - [x] 75.4 `sax_dom_set_attr` 属性白名单：`class / style / value / placeholder / disabled`
  - [x] 75.5 事件绑定走 WASM function export 名称并由 Airlock lookup 调用，不接受任意 inline JS
  - [ ] 75.6 验证：`<script>` 注入 / `innerHTML` 注入 / `eval` 注入三类用例触发 Airlock 拒绝
  - _Requirements: R36.10_

- [x] 76. HTML Shell 生成器
  - [x] 76.1 生成最小 `index.html`（加载 `app.wasm` + `airlock.js`）
  - [x] 76.2 注入 CSP（`Content-Security-Policy`）头部，禁用 inline script / eval
  - [x] 76.3 自动注入 entry 调用：`sax_app_init` 在 DOMContentLoaded 后启动
  - _Requirements: R36.10, R36.11_

#### M4：CLI 子命令（W7）

- [ ] 77. `sa sax` 子命令族（外部插件 runtime command）
  - [x] 77.1 `sa sax build <file.sax>` → `dist/app.sa + dist/app.wasm + dist/airlock.js + dist/index.html`
  - [x] 77.2 `sa sax check <file.sax>` → 仅 Parser/Validation/Referee 验证，不产出产物
  - [x] 77.3 `sa sax new <name>` → 脚手架最小项目（`app.sax` + `package.json` + `README.md`）
  - [ ] 77.4 错误退出码统一：Trap → exit 1，未知命令 → exit 2，IO 错误 → exit 3
  - _Requirements: R36.11_

#### M5：Phase 1 验收（W8）

- [ ] 78. E2E 浏览器验证（Phase 1 验收）
  - [ ] 78.1 `Counter.sax` 编译通过 + 浏览器点击 +1/-1 正确（Chrome / Firefox / Safari 三浏览器）
  - [ ] 78.2 `TodoList.sax` 编译通过 + 增删项 + 输入框 + 列表渲染
  - [ ] 78.3 删掉 `!count` → `sa sax check` 报 `SaxStateLeak`
  - [ ] 78.4 `^handler` 跨组件引用 → 报 `SaxEventEscape`
  - [ ] 78.5 `{count + ^x}` → 报 `SaxInvalidInterpolation`
  - [ ] 78.6 `<foo>` 自定义标签 → 报 `SaxUnknownTag`
  - [ ] 78.7 `<button onhover={^x}>` → 报 `SaxUnknownEvent`
  - [ ] 78.8 包体积对比：TodoList SAX vs React，目标 < 50 KB WASM vs ~130 KB+ React
  - 说明：插件级自动验收已覆盖 `reactive_dashboard` / `buffer_state` / `allowed_attrs` / `expression_interpolation` / `typed_state_interpolation` 的 `sa sax check`、`sa sax build`、WASM import/export、Airlock/事件名验证；三浏览器人工点击和 React 体积对比尚未执行。
  - _Requirements: R36.4, R36.5, R36.6, R36.7, R36.8, R36.9_

### Phase 2：响应式 + 路由 + 生命周期（W9–W14）

- [ ] 79. 编译期细粒度响应式（依赖分析）
  - [x] 79.1 SAX Parser 分析 `{expr}` ↔ `<state>` 依赖关系
  - [x] 79.2 `call @render()` 展开为最小 DOM 更新调用集（仅更新依赖该状态的节点）
  - [ ] 79.3 性能基线：1000 行列表中单行更新 ≤ 1ms（vs 全量 render）
  - _Requirements: R36.2_

- [ ] 80. 生命周期钩子
  - [ ] 80.1 `@onMount:` Lowerer 在 init 末尾追加调用
  - [ ] 80.2 `@onUnmount:` Lowerer 在 destroy 头部插入调用
  - [ ] 80.3 钩子函数签名一致性校验（无参无返）
  - _Requirements: R36.2_

- [ ] 81. `<Router>` / `<Page>` 基础路由
  - [ ] 81.1 `<Router>` 顶层组件，挂载 `popstate` / `hashchange` 事件
  - [ ] 81.2 `<Page path="/x" component="X" />` 声明式路由表
  - [ ] 81.3 路由变化触发对应 `<Page>` 组件的 mount/unmount
  - _Requirements: R36.2_

- [ ] 82. `sa sax dev` 开发服务器
  - [ ] 82.1 HTTP :8080 + 静态文件托管
  - [ ] 82.2 文件监听（`inotify` / `kqueue`）+ 自动重新编译
  - [ ] 82.3 WASM 模块热替换（保留 SA 状态）
  - _Requirements: R36.11_

- [ ] 83. VS Code 插件
  - [ ] 83.1 TextMate grammar for `.sax`（XML + SA-ASM 混合高亮）
  - [ ] 83.2 `sa sax check` 集成到 LSP 诊断
  - _Requirements: R36.11_

### Phase 3：跨端 + 生态（W15–W22）

- [ ] 84. `--target native` 原生桌面 UI
  - [ ] 84.1 自定义渲染器（GLFW / SDL2 / 自研）
  - [ ] 84.2 Airlock 接口在原生侧的等价实现
  - _Requirements: R36.12_

- [ ] 85. `--target js` 降级模式
  - [ ] 85.1 SAX → JS Bundle（兼容旧浏览器 / 扩大受众）
  - [ ] 85.2 与 WASM 路径并行存在，CLI 标志切换
  - _Requirements: R36.12_

- [ ] 86. WebGPU / Canvas 渲染路径
  - [ ] 86.1 `<canvas>` 标签下沉到 WebGPU 调用
  - [ ] 86.2 高性能 Dashboard / 数据可视化场景
  - _Requirements: R36.6_

- [ ] 87. 包管理集成（复用 v0.5 零信任包管理）
  - [ ] 87.1 `sa.mod` 声明 SAX 组件库依赖
  - [ ] 87.2 `grants [dom_query, dom_event_bind, ...]` 模块级权限
  - _Requirements: R36.14_

- [ ] 88. `<style>` 块支持
  - [ ] 88.1 类 Vue SFC 风格，组件作用域 CSS
  - [ ] 88.2 SA 变量驱动动态样式（编译期展开）
  - _Requirements: R36.6_

### 文档与生态登记

- [ ] 89. `docs/sax_*.md` 四件套维护
  - [ ] 89.1 `sax_whitepaper.md` 升级到 v0.2（含 Phase 2 路线）
  - [ ] 89.2 `sax_design.md` 跟进 Lowerer 实际实现细节
  - [ ] 89.3 `sax_airlock.md` 同步白名单 API 变更
  - [ ] 89.4 `sax_syntax.md` 维护 DOM 标签 / 事件白名单
  - _Requirements: R36.14_

- [ ] 90. `docs/std_rfc.md` 登记 SAX 加入标准库的 RFC
  - [ ] 90.1 列出 7 条 SAX Trap + Airlock 白名单 + CLI 命令
  - [ ] 90.2 与 `sa_netx`（v0.8）/ `sa-db`（v0.6）的协同关系
  - _Requirements: R36.14_

---

## 说明

- 带 `*` 的任务为可选 PBT；核心实现任务必做。
- 每条 PBT 显式标注 Property 编号（P1–P32）与验证的需求号。
- **版本分期的核心原则**：v0.1 只证明"能跑通"，v0.2 只证明"WASM 后端可自研"，v0.3 才谈"性能兑现"，v0.4 才谈"多人/多 LLM 并行协作"，v0.5 才谈"生态自给自足"，v0.6 才谈"军工/航空级形式化认证 + 数据库生态"。**不要把这七件事压在 14 周 MVP 里**。
- **v0.1 特别说明**：WASM 产线默认仍委托 `zig cc -target wasm32-wasi`，这意味着：
  - v0.1 的 `.wasm` 体积会比 v0.2 大（48 KB vs 32 KB），这是可接受的权衡
  - `wasm64` 先开放为 freestanding / no-entry 的纯计算路径，不承诺 WASI / I/O 支持；完整 memory64 产线仍归 v0.2
  - v0.1 的 WASI 映射由 Zig 自动完成，不手写（v0.2 手写后可精简）
  - 这一刀砍下去节省约 3-4 周时间
- **v0.6 特别说明**：sa-db 是 v0.5 包管理的自然延伸，复用所有既有基础设施（Referee、`#def`、`grants`、SHA-256、零权限默认）。12 周时间表假设 v0.5 已交付。
- **v0.7 特别说明**：原生单元测试框架（见本文件 Version 0.7 章节），与 v0.6 数据库无强依赖。
- **v0.8 特别说明**：sa_netx 是 v0.6 数据库的同构延伸（mmap 预分配 / SA-ASM 算子内核 / 零拷贝沙箱）。**SA-ASM ISA 零扩展**，**flattener / referee / verifier / common / 现有 sa_std 全部零修改**。所有新增能力落到 `src/runtime/sa_net_uring.zig`（新增）+ `sa_std/netx.*` 三件套（新增）。TLS 由前置 Nginx/Envoy 终结，本期不做 HTTP/2/3。12 周时间表假设 v0.5 + v0.6 已交付（v0.7 可并行）。
- **v0.9 特别说明**：SAX 是 SA 的**前端方言层**而非新语言。**SA-ASM ISA 零扩展**；`src/flattener/` / `src/common/` / `src/emit_wasm/` 全部零修改；`src/referee/` 仅追加 `src/sax/sax_rules.zig`（7 条 SAX Trap）。SAX Parser 直接输出**合法 `.sa` 文本**，不构造 AST。WASM 目标 `wasm32-unknown-unknown`（非 WASI），DOM 通过气闸舱 `airlock.js` 唯一通道访问。Phase 1（MVP）6–8 周交付 Counter / TodoList 闭环；Phase 2 加路由 + 细粒度响应式；Phase 3 跨端。可与 v0.5 / v0.7 / v0.8 解耦并行（仅依赖 SA v0.1 MVP 的 Flattener + Referee + emit_wasm）。
- 实现阶段打开 tasks.md 点击 "Start task" 按钮开始执行。

### Phase X: sa_std Macro Ergonomics & Standardization
- [x] Design and implement `sa_std/core/derive.sa` containing foundational macros for structural operations (e.g., shallow copy, field-wise equality).
- [x] Document the "Naming Contract" pattern for structures (e.g., standardizing `_CLONE`, `_FREE` suffixes for macros).
- [x] Refine and document the `[MACRO] DISPATCH` pattern as the preferred method for simulated dynamic dispatch (defunctionalization) to maintain O(1) ownership tracking by the Referee.
- [ ] Prioritize the next macro wave for data-structure portability, in this order:
  1. container construction and field access (`STRUCT_NEW`, `FIELD_GET`, `FIELD_SET`, `STRUCT_FREE`, `PTR_FIELD`)
  2. `Option` / `Result` convenience helpers (`OPTION_MATCH_SOME_NONE`, `OPTION_UNWRAP_OR_RETURN`, `RESULT_MATCH_OK_ERR`, `RESULT_RETURN_ERR`, `RESULT_MAP_OK`, `RESULT_IS_OK` / `RESULT_IS_ERR`)
  3. loop / index sugar (`FOR_RANGE`, `WHILE`, `WHILE_COND`, `INDEX_LOOP`, `ARRAY_FOR_EACH`, `ARRAY_SCAN_MIN/MAX`, `SLICE_GET_U64`)
  4. bit / mask operations (`BIT_SET`, `BIT_GET`, `BIT_CLEAR`, `BIT_TEST`, `BIT_MASK`, `BIT_INDEX_BYTE`, `BIT_INDEX_BIT`)
  5. hash / probe helpers (`HASH_PTR`, `HASH_MIX`, `HASH_MOD`, `PROBE_START`, `PROBE_NEXT`, `MAP_LOOKUP`, `MAP_INSERT_OR_UPDATE`)
  6. resource cleanup sugar (`DEFER`, `CLEANUP_ON_ERROR`, `WITH_TEMP`, `RETURN_CLEAN`, `FREE_AND_RETURN`)
  7. structured control-flow sugar (`IF`, `ELSE`, `ELIF`, `MATCH_BOOL`, `MATCH_OPTION`, `MATCH_RESULT`, `WHILE_LET`, `BREAK_IF`, `CONTINUE_IF`)
  - Goal: keep future `trie` / `bloom_filter` / `segment_tree` / `graph` ports closer to Rust while still lowering to explicit labels, stores, and branches.

- [x] Implement `Arc<T>` macros in `sa_std/core/arc.sa` using atomic `add`/`sub` operations.
- [x] Refactor `RefCell` to support multiple simultaneous readers.
- [x] Implement `RwLock` in `sa_std/sync/rwlock.sa`.
- [x] Add `BOX_NEW`/`BOX_FREE` ergonomics to `sa_std/core/mem.sa`.
- [x] Wire `line!` / `file!` / `column!` / `module_path!` through the flattener macro path, and add SA unit coverage for source-location expansion.
- [x] Add `include!` SA coverage through `tests/include_macro_expand_unit.sa` and CLI smoke execution.

### sa_std Macro Priority Backlog: Data-Structure Portability Wave 2
- [ ] Container construction and field access macros
  - `STRUCT_NEW`
  - `FIELD_GET`
  - `FIELD_SET`
  - `STRUCT_FREE`
  - `PTR_FIELD`
  - Priority: highest; target `stack` / `queue` / `heap` / `linked_list` / `union_find` / `hash_table` / `fenwick_tree` ports first.
- [ ] `Option` / `Result` convenience macros
  - `OPTION_MATCH_SOME_NONE`
  - `OPTION_UNWRAP_OR_RETURN`
  - `RESULT_MATCH_OK_ERR`
  - `RESULT_RETURN_ERR`
  - `RESULT_MAP_OK`
  - `RESULT_IS_OK` / `RESULT_IS_ERR`
  - Priority: high; target `trie` / `bloom_filter` / `segment_tree` / `graph` next.
- [ ] Loop and index macros
  - `FOR_RANGE`
  - `WHILE`
  - `WHILE_COND`
  - `INDEX_LOOP`
  - `ARRAY_FOR_EACH`
  - `ARRAY_SCAN_MIN/MAX`
  - `SLICE_GET_U64`
  - Priority: high; use to cut `jmp` / `branch` / `idx_slot` boilerplate and reduce `PhiStateConflict` risk.
- [ ] Bit and mask macros
  - `BIT_SET`
  - `BIT_GET`
  - `BIT_CLEAR`
  - `BIT_TEST`
  - `BIT_MASK`
  - `BIT_INDEX_BYTE`
  - `BIT_INDEX_BIT`
  - Priority: medium-high; target `bloom_filter` / `bitset` / `bitmap` / compressed segment-tree layouts.
- [ ] Hash and probe macros
  - `HASH_PTR`
  - `HASH_MIX`
  - `HASH_MOD`
  - `PROBE_START`
  - `PROBE_NEXT`
  - `MAP_LOOKUP`
  - `MAP_INSERT_OR_UPDATE`
  - Priority: medium-high; target `hashmap` / `hashset` / `bloom_filter` / `count_min_sketch`.
- [ ] Resource cleanup macros
  - `DEFER`
  - `CLEANUP_ON_ERROR`
  - `WITH_TEMP`
  - `RETURN_CLEAN`
  - `FREE_AND_RETURN`
  - Priority: medium; make temp alloc cleanup and error-path teardown explicit and repeatable.
- [ ] Structured control-flow sugar
  - `IF`
  - `ELSE`
  - `ELIF`
  - `MATCH_BOOL`
  - `MATCH_OPTION`
  - `MATCH_RESULT`
  - `WHILE_LET`
  - `BREAK_IF`
  - `CONTINUE_IF`
  - Priority: lower than the data-structure helpers; keep the expansion thin and label-based.
- [ ] Add SA unit tests for every new macro family as soon as it lands
  - Smoke coverage for expansion presence
  - Behavior coverage for success / failure / cleanup paths
  - Keep the tests in `tests/rust_core_unit.sa` or adjacent macro-specific SA tests
