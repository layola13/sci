# 实现计划：SA 线性所有权语言与编译器（按版本路线图）

## 概述

本实现计划按**版本递进**组织，而不是一次性交付全部 23 条需求。核心思路：

1. **v0.1 MVP（Week 1-14）** — "跑通闭环"。SA 源码 → Flattener → Referee → LLVM IR → **全程走 `zig cc`** 产出 `.exe` 和 `.wasm`。不自研任何后端。
2. **v0.2（post-MVP，4-6 周）** — "后端自研"。替换 WASM 产线为手写二进制 Emitter，获得更小体积、wasm64、DWARF-in-WASM 精细控制。
3. **v0.3（post-MVP，6-8 周）** — "性能兑现"。SIMD/并行调度/AutoBevy 1M ±30% / LLM 微调路线。

**v0.1 不做的事**（这是刻意的风险削减）：
- ❌ 不手写 WASM 二进制 Emitter（走 `zig cc -target wasm32-wasi -O ReleaseSmall`）
- ❌ 不自研 DWARF-in-WASM（zig cc 自带）
- ❌ 不承诺 AutoBevy 1M ±30%（只跑 1K 冒烟）
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
│   ├── emit_llvm/           # LLVM IR 文本发射器 + DWARF
│   ├── emit_wasm/           # [v0.2] 手写 WASM 二进制（v0.1 为空目录）
│   ├── interp/              # saasm run 内存解释器
│   ├── driver/              # zig cc 子进程封装
│   ├── cli/                 # saasm 四模命令行
│   ├── runtime/             # @sys_* / __sa_panic / snapshot
│   └── libsa_scope/         # 前端降级 helper (C-ABI)
├── tests/{unit,property,integration,golden,pilot}/
├── bench/
└── docs/{whitepaper.md,whitepaper.txt,ebnf.md}
```

---

# Version 0.1 — MVP：跑通闭环（14 周）

目标：一段可编译的 `.saasm` 源码能通过 CLI 四模分别产出可运行的 `.exe`、`.wasm`，并在 Referee 上守住所有权正确性。**WASM 产线这一版完全委托 `zig cc`。**

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

  - [ ] 2.5 `TrapReport` JSON schema
    - 按 design §4.4 含 `upstream_loc` / `function` / `is_ffi_wrapper` 字段
    - 24 种 Trap 枚举（原 21 + `EarlyReturnLeak` + `AtomicOrderingMismatch` + `FallibleContractMismatch`）
    - _Requirements: R9.3, R13.5, R13.7, R17.7, R18.5, R19.2_

  - [ ] 2.6 `GasReport` / `FunctionSig` / `ParamSpec` / `UpstreamLoc`
    - `FunctionSig` 含 `kind` / `is_ffi_wrapper` / `return_fallible` / `upstream_file`
    - _Requirements: R5.1, R5.3, R11.1, R13.4, R18.1_

  - [ ] 2.7 产出 EBNF 文档
    - `docs/ebnf.md` 按 design 附录 C，含 `loc` / `ffi_wrapper_def` / `try_op` / `panic_op` / `atomic_*` / `rawcast` / `assume_*`
    - _Requirements: R1.6, R3.1, R13.1, R13.9_

  - [ ] 2.8 产出 LLM 白皮书 v0.1
    - `docs/whitepaper.md` + `.txt`，≤ 2000 行
    - 覆盖 R23.2 全部章节（五符号 + ISA + CFG + 掩码 + 宏 + 气闸舱 + `@sys_*` + 错误传播 + `#loc` + 降级合约摘要 + 5 组对比 + Trap 代号表）
    - _Requirements: R1.1–R1.5, R20.1–R20.2, R23.1, R23.2, R23.5_

  - [ ]* 2.9 白皮书 lint 冒烟（≤ 2000 行）
    - _Requirements: R23.1_

- [ ] 3. 检查点 — 协议定型
  - 运行 `zig build test`。

- [ ] 4. W3-5 Flattener

  - [ ] 4.1 行分类器（16 种形态）
    - _Requirements: R3.1_

  - [ ] 4.2 `#def` 字典 + 常量折叠（`+/-/*`）
    - _Requirements: R7.1–R7.5_

  - [ ]* 4.3 常量折叠 PBT — **P8**
    - _Requirements: R7.1, R7.2, R7.5_

  - [ ] 4.4 禁用语法扫描（`{` `}` `if` `else` `while` `for` `a.b.c`）
    - _Requirements: R3.3, R6.6_

  - [ ]* 4.5 禁用语法 PBT — **P4**
    - _Requirements: R3.2, R3.3, R6.6_

  - [ ] 4.6 `#loc` 伪指令收集器
    - 维护 `LocTable: Map<expanded_line, UpstreamLoc>`
    - 下一条真实指令继承最近一次 `#loc` 值
    - _Requirements: R19.1_

  - [ ]* 4.7 `#loc` 单调映射 PBT — **P25**
    - 随机插入 `#loc`，断言 Trap 报告与 LocTable 一致
    - _Requirements: R19.1, R19.2_

  - [ ] 4.8 宏模板注册 `[MACRO]...[END_MACRO]`
    - _Requirements: R8.1_

  - [ ] 4.9 `EXPAND` 文本展开 + 深度栈（上限 256）
    - _Requirements: R8.2, R8.5, R8.6_

  - [ ] 4.10 `[REP N]...[END_REP]` + 游标 `%i`
    - _Requirements: R8.3, R8.5_

  - [ ]* 4.11 宏展开 PBT — **P6**
    - _Requirements: R8.1, R8.2, R8.3, R8.5_

  - [ ] 4.12 宏/常量错误检测（`DuplicateDef` / `RegisterRedefinition` / `MacroRecursionLimit`）
    - _Requirements: R7.4, R8.4, R8.6_

  - [ ]* 4.13 非法宏 PBT — **P7**
    - _Requirements: R7.4, R8.4, R8.6_

  - [ ] 4.14 寄存器名规范化为 `u32` ID（保留 SymbolTable）
    - _Requirements: R2.1_

  - [ ] 4.15 函数签名解析
    - 识别 `@func` / `@ffi_wrapper` / `@extern` / `@export` 四类
    - 识别 `-> T!` 可失败标记，设置 `return_fallible`
    - _Requirements: R3.1, R5.1, R5.3, R13.4, R13.9, R14.9, R14.10, R18.1_

  - [ ]* 4.16 签名解析确定性 PBT — **P11**
    - _Requirements: R2.2, R5.1, R5.3_

  - [ ] 4.17 原生类型字面量合法性（11 种 + `v128`）
    - _Requirements: R2.4_

  - [ ]* 4.18 类型字面量 PBT — **P14**
    - _Requirements: R2.4_

  - [ ] 4.19 原生逃逸块 `$...$` 识别 + 涉及寄存器名列表
    - _Requirements: R1.5_

  - [ ] 4.20 气闸舱指令解析（`*` / `assume_safe` / `assume_borrow`）
    - _Requirements: R13.1, R13.2, R13.3_

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

- [ ] 5. 检查点 — Flattener 完成
  - 跑过 P4、P6、P7、P8、P11、P14、P25

- [ ] 6. W6-9 Referee（含一周性能调优）

  - [ ] 6.1 `CapabilityTable`（masks / origins / lock_refs / flags）
    - _Requirements: R4.1, R9.2_

  - [ ] 6.2 统一指令校验函数骨架（把 16+ 种 `InstKind` 收敛为"读 N 源 + 写 M 目标"模式）
    - MVP 基线 ≤ 2500 行 Zig；stretch 目标 1500 行
    - _Requirements: R9.1, R9.2, R9.5_

  - [ ] 6.3 四仿射规则（alloc / borrow / move / release）
    - _Requirements: R1.1–R1.4, R4.3–R4.4, R4.6–R4.7_

  - [ ]* 6.4 所有权状态机 PBT — **P1**
    - _Requirements: R1.1–R1.4, R4.1–R4.7_

  - [ ] 6.5 未声明寄存器检测
    - _Requirements: R2.3_

  - [ ]* 6.6 `UnknownRegister` PBT — **P13**
    - _Requirements: R2.3_

  - [ ] 6.7 函数出口泄漏检测
    - _Requirements: R4.5_

  - [ ] 6.8 基本块结束指令 + 重名 Label
    - _Requirements: R3.4, R3.5_

  - [ ]* 6.9 CFG 结构完整性 PBT — **P5**
    - _Requirements: R3.4, R3.5, R10.2_

  - [ ] 6.10 Phi 汇聚点按位 AND
    - 合法交集 `{0x01, 0x02, 0x04, 0x08, 0x11, 0x12}`
    - _Requirements: R10.1–R10.4_

  - [ ]* 6.11 Phi PBT — **P9**
    - _Requirements: R10.1, R10.3_

  - [ ] 6.12 调用点契约前缀校验
    - _Requirements: R5.2_

  - [ ]* 6.13 调用契约 PBT — **P12**
    - _Requirements: R5.2_

  - [ ] 6.14 原生逃逸保守消费
    - _Requirements: R5.4_

  - [ ]* 6.15 原生逃逸保守消费 PBT — **P3**
    - _Requirements: R5.4_

  - [ ] 6.16 **气闸舱强制隔离**
    - `RawCast` / `AssumeSafe` / `AssumeBorrow` 仅当 `is_ffi_wrapper == true` 通过
    - 否则 `Trap: IllegalUnsafeContext`
    - _Requirements: R13.1, R13.4, R13.5_

  - [ ]* 6.17 气闸舱隔离 PBT — **P21**
    - _Requirements: R13.1–R13.5_

  - [ ] 6.18 **FFI 借用不可销毁**
    - `FfiBorrow` 位寄存器遇 `^` → `Trap: FfiOwnershipViolation`；遇 `!` 仅清记录不发射 free
    - _Requirements: R13.3, R13.7_

  - [ ]* 6.19 FFI 借用不可销毁 PBT — **P22**
    - _Requirements: R13.3, R13.7_

  - [x] 6.20 **错误传播早返回泄漏校验**
    - `EarlyReturn` 指令作为特殊 `Return` 处理，检查该路径上 Active/Locked 残留 → `Trap: EarlyReturnLeak`
    - `?` 作用于非 Fallible 寄存器 → `Trap: FallibleContractMismatch`
    - _Requirements: R18.5_

  - [x] 6.20a **stack_alloc 退出规则**
    - `stack_alloc` 允许函数出口自动回收，不计入 `MemoryLeak`
    - `stack_alloc` 作为 `^` / `return` / `move` / `call` 实参时必须 `Trap: StackEscape`
    - _Requirements: R2.1, R2.8, R9.1_

  - [ ]* 6.21 早返回泄漏 PBT — **P24**
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

- [ ] 7. 检查点 — Referee 完成
  - 跑过 P1、P3、P5、P9、P10、P12、P13、P19、P21、P22、P24

- [ ] 8. W10-11 LLVM IR Emitter + CLI + `zig cc` 全权代劳的 exe/wasm

  - [ ] 8.1 基础映射 M01–M07（alloc/free/load/store/运算）
    - 按 design 附录 A 精确输出
    - _Requirements: R14.3–R14.6_

  - [ ] 8.2 控制流映射 M08–M13（LLVM 原生 `br` + labels）
    - _Requirements: R14.8_

  - [ ] 8.3 `take` 映射 M14
    - _Requirements: R14.5_

  - [ ] 8.4 原生逃逸块 M15 字节级透传
    - _Requirements: R14.7_

  - [ ]* 8.5 原生逃逸字节透传 PBT — **P2**
    - _Requirements: R14.7_

  - [ ] 8.6 函数/Label/`@extern`/`@export` 映射 M16-M17, M21-M22
    - 无名称修饰；标准 C-ABI 布局
    - _Requirements: R14.9, R14.10_

  - [ ] 8.7 索引访问物理降维（`mul + GEP + load`）
    - _Requirements: R6.5_

  - [ ]* 8.8 索引访问 PBT — **P15**
    - _Requirements: R6.5_

  - [ ] 8.9 气闸舱指令映射 M18-M20（`ptrtoint` / `inttoptr`）
    - _Requirements: R13.1, R13.2, R13.3_

  - [ ] 8.10 原子指令映射 M24-M27
    - 对接 LLVM `atomic` 关键字 + ordering 语法
    - _Requirements: R2.6, R14.4, R14.5_

  - [ ] 8.10a `ptr_add` 映射 M35
    - 生成对应的 `%dst = getelementptr i8, ptr %base, i64 %off`。
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

  - [ ]* 8.15 LLVM IR 语法合法性 PBT — **P16**
    - 用 `opt -verify` 解析产物
    - _Requirements: R14.1, R14.3–R14.10_

  - [ ]* 8.16 Zig 依赖受限 PBT — **P17**（v0.1 版本：断言产物 `@import` 集合为空，因为我们不生成 Zig 源码）
    - _Requirements: R14.11_

  - [x] 8.17 LLVM IR Emitter 公开 API `emitLlvm(allocator, annotated, loc_table) ![]const u8`
    - 附 source map `inst_idx → ir_line`
    - _Requirements: R14.1_

  - [x] 8.18 `zig cc` 子进程封装 `driver/zigcc.zig`
    - 把 `.ll` 写临时文件
    - `saasm build-exe` → `zig cc <ll> -o <exe> -O ReleaseSmall`（默认 O1 档，`--release-fast` 切 O3）
    - **`saasm build-wasm` → `zig cc <ll> -target wasm32-wasi -o <wasm> -O ReleaseSmall`（v0.1 全委托 Zig，不用手写 Emitter）**
    - `saasm build-obj` → `zig cc <ll> -c -o <o>`
    - _Requirements: R14.1, R14.11, R15.1, R15.2, R16.2, R16.3, R16.4_

  - [x] 8.19 CLI `saasm run` / `build-exe` / `build-wasm` / `build-obj` 四模路由
    - Trap 返回非零退出码 + JSON 到 stderr
    - _Requirements: R16.1, R16.5_

  - [ ] 8.20 CLI 二进制分发约束
    - `zig build -Drelease-small` 产物 ≤ 15 MB（MVP），libc 外无依赖
    - _Requirements: R16.6_

  - [x] 8.21 `-g` / `--no-debug` 调试开关接入
    - `-g` 默认关，`build-exe -g` 启用 DWARF 生成
    - _Requirements: R19.4, R19.5_

- [ ] 9. W10-11 内存解释器（`saasm run`）

  - [ ] 9.1 大 switch 分派全部 `InstKind`
    - _Requirements: R16.1_

  - [ ] 9.2 `@sys_*` 原语原生实现
    - `@sys_print` / `@sys_read_file` / `@sys_write_file` / `@sys_exit` / `@sys_argv` / `@sys_argc`
    - _Requirements: R16.1, R17.1–R17.5_

  - [ ] 9.3 气闸舱语义（Interp 模式）
    - `assume_*` 只更新 mask，不做实际指针操作
    - _Requirements: R13.2, R13.3_

  - [x] 9.4 `panic(code)` 打印 + 退出 128+code
    - _Requirements: R18.4_

  - [x] 9.5 Interpreter API `run(allocator, annotated, argv) !u8`
    - _Requirements: R16.1_

- [ ] 10. W12 `@sys_*` 原语 + FFI 气闸舱 + panic runtime

  - [ ] 10.1 Native `@sys_*` 原生 stub（`src/runtime/native_sys.zig`）
    - 用 `std.fs` / `std.process` 实现，编译为静态 `.o` 被 `zig cc` 链接
    - _Requirements: R17.1–R17.5_

  - [ ] 10.2 **v0.1 WASM 路径**：`@sys_*` 映射到 WASI import
    - 通过 `zig cc -target wasm32-wasi` 自动链接 Zig 的 WASI stub
    - 不需要手写 WASI 绑定（这部分移到 v0.2）
    - _Requirements: R15.2, R15.5, R17.1–R17.5_

  - [ ]* 10.3 `@sys_*` 双轨等价 PBT — **P23**
    - 同一 `.saasm` 分别走 `build-exe` + `build-wasm`，对比输出/退出码
    - _Requirements: R15.5, R17.1–R17.5_

  - [x] 10.4 `__sa_panic` 运行时符号（Native）
    - ≤ 30 行 Zig，写 stderr + `_exit(128+code)`
    - _Requirements: R18.4_

  - [x] 10.5 句柄模式 FFI 集成样例
    - `tests/integration/ffi_handle.saasm`：`@extern` 分配返回 ID → 后续查表借用
    - 已补 `tests/integration/ffi_handle_demo.zig` / `tests/integration/ffi_handle/handle.saasm` / `tests/integration/ffi_handle/handle_host.c`，并纳入 `zig build test`
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

- [x] 12b. `saasm layout` 布局生成工具（R7b）

  - [x] 12b.1 实现 `saasm layout --name NAME --fields "field:type, ..."` 子命令
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

- [ ] 13. W13-14 AutoBevy 1K + LLM Pilot + Hello-Compute 端到端

  - [ ] 13.1 AutoBevy Component Buffer + Entity + System 注册（1K 规模）
    - _Requirements: R21.1, R21.4_

  - [ ] 13.2 System 并行分析器（复用 CapabilityMask AND）
    - _Requirements: R21.2_

  - [ ]* 13.3 System 并行分析 PBT — **P20**
    - _Requirements: R21.2_

  - [ ] 13.4 AutoBevy 1K 冒烟集成测试
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

  - [ ] 13.7 Hello-Compute `.exe` + `.wasm` 端到端测试
    - _Requirements: R15.1, R15.3, R16.2, R16.3_

  - [ ] 13.8 GDB/LLDB 上游行号断点验证
    - 编 `saasm build-exe -g hello.saasm`（含 `#loc` 指向 `hello.rs`）
    - gdb 能按 `hello.rs:N` 下断点并命中
    - _Requirements: R19.5, R19.6_

- [ ] 14. 测试基线与 CI 门禁（v0.1）

  - [ ] 14.1 13 类黄金用例集
    - 每类 ≥ 10 例：正常 / `DoubleMutableBorrow` / `UseAfterMove` / 借用期 Move / `MemoryLeak` / Phi 冲突 / 宏合法 / 宏递归 / 禁用语法 / 气闸舱违规 / FFI 借用销毁违规 / 早返回泄漏 / 原子 ordering
    - _Requirements: R22.1, R22.2_

  - [ ] 14.2 CI 流水线
    - `zig build test` → Property × 25 × 100+ → 集成 15 个 → 基准回归 ±10% → 白皮书 ≤ 2000 → Referee LOC ≤ 2500 → `.wasm` ≤ 48 KB → DWARF 冒烟 → merge
    - _Requirements: R22.3, R23.1, R9.5, R9.6, R15.3, R16.6_

  - [ ]* 14.3 Trap 基线回归
    - _Requirements: R22.2, R22.3_

- [ ] 15. v0.1 最终验收
  - 运行全部测试
  - 硬约束：Referee ≤ 2500 行 / 真实代码 ≥ 500K 行每秒 / 白皮书 ≤ 2000 行 / `.wasm` ≤ 48 KB / `.exe` ≤ 800 KB / CLI ≤ 15 MB / AutoBevy 1K 通过 / LLM pilot baseline 归档
  - Stretch 全部不强求
  - 任何未通关项向用户确认

---

# Version 0.2 — 自研 WASM 后端（post-MVP，4-6 周）

目标：v0.1 已证明语义闭环，但 `zig cc` 产出的 WASM 偏大（48 KB 级别）且不可控 wasm64。v0.2 替换 WASM 产线为手写二进制 Emitter，获得体积、精度、wasm64 三项收益。Native 路径（LLVM IR + zig cc）保持不变。

## v0.2 任务

- [ ] 16. WASM 二进制发射器基础设施

  - [ ] 16.1 LEB128 变长整数编解码
    - _Requirements: R14.2_

  - [ ] 16.2 WASM Section 拼装骨架（Type / Import / Function / Memory / Global / Export / Code / Data）
    - 按 WASM Core 2.0 规范
    - _Requirements: R14.2_

  - [ ] 16.3 wasm32 / wasm64 双目标切换
    - CLI `--target wasm32|wasm64`
    - `i32.load/store` ↔ `i64.load/store` 切换
    - `memory` section memory64 标志位
    - _Requirements: R15.4_

- [ ] 17. WASM opcode 映射层

  - [ ] 17.1 基础 opcode 映射（alloc/load/store/运算/控制流）
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

  - [ ] 17.5 `panic(code)` → `unreachable` opcode
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
  - CLI `saasm build-wasm` 默认改走手写 Emitter
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
  - LLVM IR Emitter 完整映射
  - _Requirements: R2.4, R2.5_

- [ ] 23. AutoBevy 1M 性能追 Bevy ±30%
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

- [ ] 27. Rust std 防波堤 demo 完善
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

- [ ] 29. `libsa_async` 异步状态机宏模板（R26）

  - [ ] 29.1 编写 `libsa_async.saasm` 宏文件
    - 包含 `ASYNC_CTX_DEF` / `ASYNC_POLL_PROLOGUE` / `ASYNC_AWAIT_POINT` / `ASYNC_RETURN_PENDING` 四个标准宏
    - _Requirements: R26.1, R26.3_

  - [ ] 29.2 Flattener 文件拼接机制（`#include "libsa_async.saasm"`）
    - 在预处理阶段把外部 `.saasm` 文件内容原样插入当前源码
    - _Requirements: R26.4_

  - [ ] 29.3 用 `libsa_async` 重写案例 23 的 demo
    - 验证展开后与手写等价
    - _Requirements: R26.2, R26.5_

  - [ ]* 29.4 宏展开等价性 Property 测试 — **P32 (NEW)**
    - 对比手写 120 行 SA 与 `EXPAND ASYNC_AWAIT_POINT ...` 展开后的 `Instruction[]`
    - 断言字段级相等
    - 最少 100 次
    - _Requirements: R26.2_

- [ ] 30. 发射产物诊断级别（R27）

  - [ ] 30.1 `--release` 模式确认零运行时开销
    - 验证产物中不含 gas 计数器、不含 sanitizer 簿记
    - _Requirements: R27.1_

  - [ ] 30.2 `--debug-gas` 模式实现
    - 在每个函数入口/基本块头部插入 gas 计数器自增
    - 超限触发 `Trap: GasExceeded`
    - _Requirements: R27.2_

  - [ ] 30.3 `--debug-san` 模式实现
    - 在 `alloc` / `!free` 点插入红黑树/哈希表簿记
    - 运行期侦测 UAF / Double-Free
    - 输出结构化 JSON 报告（含 `upstream_loc`）
    - _Requirements: R27.3, R27.4_

  - [ ] 30.4 白皮书"构建模式"章节
    - 明确三种模式的安全保障边界与性能代价
    - _Requirements: R27.6_

---

# Version 0.4 — 并行开发基建（post-v0.3，4-6 周）

目标：让 SA 从"单人极客工具"进化为"多人/多 LLM 并行协作的工业级基建"。核心能力：接口契约、版本化布局、函数粒度增量编译。

## v0.4 任务

- [ ] 31. 接口契约文件 `.saasm-iface`（R28）

  - [ ] 31.1 定义 `.saasm-iface` 文件格式
    - 仅包含 `@extern` 签名声明（含 cap_prefix + ty + 返回类型 + `!` 后缀）
    - 不包含函数体、不包含 `#def`、不包含 `@const`
    - _Requirements: R28.1_

  - [ ] 31.2 Flattener 支持 `#include "module.saasm-iface"`
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
    - 多个 `.saasm` 文件引用同一 `.saasm-iface`，各自独立编译，最后链接
    - 验证结果与串行编译等价
    - _Requirements: R28.5_

  - [ ] 31.6 CI 依赖检测
    - 接口文件修改时自动标记依赖方需重新验证（文件哈希比对）
    - _Requirements: R28.6_

- [ ] 32. 版本化布局文件 `.saasm-layout`（R29）

  - [ ] 32.1 定义 `.saasm-layout` 文件格式
    - `#version N` 元数据行 + `#def` 常量声明
    - _Requirements: R29.1, R29.6_

  - [ ] 32.2 Flattener 支持 `#include "entity.saasm-layout"`
    - 记录引用的 `#version` 值
    - _Requirements: R29.2_

  - [ ] 32.3 版本冲突检测
    - 两个 `.saasm` 引用同一布局文件的不同版本 → 链接期 `Trap: LayoutVersionConflict`
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
    - 每个 LLM 实例只看到 `.saasm-iface` + `.saasm-layout`，独立生成一个函数
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

- [ ] 35. 包管理 `sa.pkg`（R31）

  - [ ] 35.1 定义 `sa.pkg` 文件格式
    - `#pkg name/version/deps` 声明
    - deps 支持远程 URL 与本地路径
    - _Requirements: R31.1_

  - [ ] 35.2 CLI `saasm pkg fetch` 命令
    - 下载远程依赖到 `.sa-cache/deps/`
    - _Requirements: R31.6_

  - [ ] 35.3 依赖拓扑排序与自动编译
    - `saasm build-exe` 时自动解析 `sa.pkg`，按拓扑序编译依赖
    - _Requirements: R31.2_

  - [ ] 35.4 依赖接口自动注入
    - 依赖包的 `.saasm-iface` 自动 `#include` 到当前编译单元
    - _Requirements: R31.3_

  - [ ] 35.5 依赖布局自动注入（带命名空间前缀）
    - `pkg_name.FIELD_NAME` 避免 `#def` 冲突
    - _Requirements: R31.4_

  - [ ] 35.6 重复导出符号检测
    - 两个依赖包同名 `@export` → `Trap: DuplicateExportSymbol`
    - _Requirements: R31.5_

  - [ ] 35.7 版本冲突报错
    - 同一包两个版本被间接依赖 → 报错要求用户选择
    - _Requirements: R31.8_

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

- [ ] 37. `sa_std` 标准库 v0.1

  - [ ] 37.1 `sa_std/string.saasm`：字符串操作宏
    - `STR_LEN` / `STR_CONCAT` / `STR_EQ` / `STR_SLICE`
    - 基于胖指针 `[data_ptr | len]` 布局

  - [ ] 37.2 `sa_std/vec.saasm`：动态数组宏
    - `VEC_NEW` / `VEC_PUSH` / `VEC_GET` / `VEC_LEN` / `VEC_FREE`
    - 基于 `[data_ptr | len | cap]` 布局 + `alloc` 扩容

  - [ ] 37.3 `sa_std/hashmap.saasm`：哈希表宏
    - 开放寻址法 + FNV-1a 哈希
    - `MAP_NEW` / `MAP_PUT` / `MAP_GET` / `MAP_DEL` / `MAP_FREE`

  - [ ] 37.4 `sa_std/sort.saasm`：排序宏
    - 快速排序（`[MACRO] QSORT %arr, %len, %elem_size, %cmp_fn`）

  - [ ] 37.5 `sa_std/io.saasm`：IO 便利宏
    - `PRINTLN` / `READ_LINE` / `FORMAT_INT`（基于 `@sys_print` + `@sys_read_file`）

  - [ ] 37.6 打包为 `sa_std` 包
    - 创建 `sa_std/sa.pkg` + `sa_std/*.saasm-iface`
    - 发布到本地 registry

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

## 说明

- 带 `*` 的任务为可选 PBT；核心实现任务必做。
- 每条 PBT 显式标注 Property 编号（P1–P25）与验证的需求号。
- **版本分期的核心原则**：v0.1 只证明"能跑通"，v0.2 只证明"WASM 后端可自研"，v0.3 才谈"性能兑现"，v0.4 才谈"多人/多 LLM 并行协作"，v0.5 才谈"生态自给自足"，v0.6 才谈"军工/航空级形式化认证"。**不要把这六件事压在 14 周 MVP 里**。
- **v0.1 特别说明**：WASM 产线全程委托 `zig cc -target wasm32-wasi`，这意味着：
  - v0.1 的 `.wasm` 体积会比 v0.2 大（48 KB vs 32 KB），这是可接受的权衡
  - v0.1 不支持 wasm64（Zig wasm64 freestanding 尚不成熟），这是 v0.2 的工作
  - v0.1 的 WASI 映射由 Zig 自动完成，不手写（v0.2 手写后可精简）
  - 这一刀砍下去节省约 3-4 周时间
- 实现阶段打开 tasks.md 点击 "Start task" 按钮开始执行。
钮开始执行。
6 才谈"军工/航空级形式化认证"。**不要把这六件事压在 14 周 MVP 里**。
- **v0.1 特别说明**：WASM 产线全程委托 `zig cc -target wasm32-wasi`，这意味着：
  - v0.1 的 `.wasm` 体积会比 v0.2 大（48 KB vs 32 KB），这是可接受的权衡
  - v0.1 不支持 wasm64（Zig wasm64 freestanding 尚不成熟），这是 v0.2 的工作
  - v0.1 的 WASI 映射由 Zig 自动完成，不手写（v0.2 手写后可精简）
  - 这一刀砍下去节省约 3-4 周时间
- 实现阶段打开 tasks.md 点击 "Start task" 按钮开始执行。
