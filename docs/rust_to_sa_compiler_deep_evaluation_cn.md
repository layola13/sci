# Rust 源码直接编译到 SA/SCI：深度可行性评估与架构方案

> 评估日期：2026-07-16
> 评估对象：`rust`、`sci`、`sa_plugins/sa_plugin_sla` 三个本地工程当前快照
> 优先路径：**Rust 源码 -> rustc 前端 -> mono `Instance` + codegen MIR -> SA/SAB -> SCI -> 目标对象**
> 非优先路径：`rustc -> LLVM bitcode -> bc2sa`；本文只把它作为兼容性探针和反例

## 1. 执行结论

### 1.1 决策

| 目标 | 决策 | 前提 |
| --- | --- | --- |
| 单平台、`panic=abort`、受限 Rust 子集的研究型后端 | **Go** | 先完成 target/ABI/布局协议，再做 `rustc_codegen_sci` |
| `no_std`、标量/指针/基本 CFG 的可审计 PoC | **Go** | 与一个 rustc commit 锁定；不允许静默 fallback |
| 跨优化/内联保持 loan 语义的 `sa-verified-subset` | **No-Go（映射 spike 通过前）** | 当前 rustc 不产出可组合的 MIR pass refinement certificate；只能先做研究门禁 |
| 可用于真实 Cargo workspace 的产品级子集 | **Conditional Go** | ABI、聚合、drop、静态分配、增量缓存、sysroot 和证明覆盖率全部过门禁 |
| 当前 SCI 直接承载完整 Rust/std/unsafe/unwind/SIMD/多目标 | **No-Go** | 当前 SA/SAB 和 native emitter 无法表达 Rust 的布局及 `FnAbi` |
| 重写 Rust parser/type checker/borrow checker/query 系统 | **No-Go** | 成本等同于另造 Rust 前中端，并会丢失 rustc 兼容性 |

因此，项目可以立项，但项目名称和承诺应是“**与特定 nightly 绑定的 Rust-to-SA/SCI 受限 codegen backend**”。在完整支持矩阵逐项通过门禁前，不能宣称“SCI 已是完整 Rust 底层”；也不能因为产物经过 Referee 就宣称所有 Rust 代码获得了第二套所有权证明。

### 1.2 最重要的工程判断

1. **机器 lowering 的输入必须是以 mono `Instance` 为上下文的 codegen MIR + generic args，而不是 Rust 源码文本、AST 或 LLVM IR。** `rust-trusted` 可只消费该机器输入；`sa-verified-subset` 还必须在 borrowck 阶段提前捕获 proof sidecar，并用 pass-level refinement certificate 证明其到优化后 MIR/mono `Instance` 的映射，不能事后从 optimized MIR 猜回 NLL facts。
2. **先扩 SCI 契约，再写大量 lowering。** 当前缺口主要是 target、数据布局、聚合、静态分配和 Rust ABI，不是多写若干 SA 指令映射。
3. **参考 `rustc_codegen_cranelift` 的集成方式。** 复用 `rustc_codegen_ssa::base::codegen_crate` 的 mono/CGU 调度和标准 object 缓存，自行读取 `Instance` + codegen MIR 并构造 ownership-rich SCI IR；SCI proof work product 另做定制集成。
4. **SA 文本和 SAB 必须来自同一个 typed lowering plan。** SA 文本用于审计、golden test 和 bring-up；direct SAB 是后续高性能路径。任一不支持项必须结构化报错。
5. **rustc adapter 与 SCI engine 采用进程边界。** 本地 rustc 工具链的 LLVM backend 是 22，而 SCI native 路径主要使用 LLVM 14；不要让 adapter 把后者直接链接进 rustc 进程。
6. **Rust 语义证明与 SCI capability 验证分级。** 默认模式信任 rustc；只有严格限定且具备证明覆盖率的子集，才宣称 SCI 对所有权进行了额外验证。

## 2. 目标、非目标与术语

### 2.1 目标

- 使用官方 rustc 前中端接受真实 Rust，包括宏、泛型、trait 和 Cargo crate graph。
- 将 mono `Instance` 上下文中的 codegen MIR、`TyAndLayout`、`FnAbi`、逐函数 codegen 属性和源码位置降低为可验证的 SCI 中间表示；严格模式另消费 borrowck proof sidecar 与 pass-level refinement certificate。
- 经 SCI Referee 后产出标准目标对象，由 rustc 原有 metadata/archive/link 管线完成最终产物。
- 让 `sa rust check/build/test/emit-sa` 成为用户入口，同时保持 `cargo` 工作流可用。
- 对“不支持”和“未验证”给出确定、可机器读取且不降级的诊断。
- 保持与 rustc commit、SCI ISA/SAB 版本、target 和 sysroot 可追溯绑定。

### 2.2 非目标

- 不在 Zig 或 SLA 前端中重新实现 Rust parser、macro expansion、type checker、NLL borrow checker 或 trait solver。
- 不把 `bc2sa` 当作正式编译路径。
- 不承诺第一阶段支持 `std`、unwind、inline asm、TLS、SIMD、sanitizer 或 LTO。
- 不把所有函数包装成 `@ffi_wrapper`/Untracked 后称为“通过 SCI 所有权证明”。
- 不替换 Cargo、rustc metadata、crate linkage 或最终 linker driver。
- 不假设 SCI 比 rustc LLVM backend 更快；性能必须由阶段性基准证明。

### 2.3 三条必须分离的契约

| 契约 | 权威来源 | 需要保持的内容 |
| --- | --- | --- |
| Rust 语言语义 | rustc 前中端 | 类型、borrowck 结论、drop、panic 行为、有效值约束、单态化 |
| 机器布局与 ABI | rustc `TyAndLayout` / `FnAbi` | size/align、niche、参数拆分、hidden pointer、calling convention、unwind |
| SCI 验证语义 | SCI proof descriptor / Referee | owner、loan、provenance、subobject、raw 边界、drop obligation、CFG 合并 |

当前 SA 的 `CapPrefix + PrimType` 同时承担其中多项职责，不能直接扩展成完整 Rust backend。新协议必须把 **semantic/proof descriptor** 与 **machine ABI descriptor** 正交建模。

## 3. 本地现状与可复现实证

### 3.1 快照

| 工程 | 当前快照 | 关键版本 |
| --- | --- | --- |
| `rust` | `fcbe7917ba18`，2026-07-15 | stage1/stage2 `rustc 1.99.0-nightly`，LLVM `22.1.8` |
| `sci` | `0135014922c9`，工作树另有未提交修改 | `sa 0.0.4`，系统 LLVM-C 工具链 `14.0.0` |
| `sa_plugin_sla` | `975b08ac5bdd` | 直接 SLA -> typed frontend -> SA/SAB 的参考实现 |

本评估未把 SCI 工作树的既有未提交修改当成本次产物，也不依赖它们被回退。

### 3.2 rustc 生成的 LLVM 22 bitcode 不是可靠入口

用本地 rustc 生成最小 Rust bitcode，再走当前 `bc2sa` 路径，默认会调用 `/usr/bin/llvm-dis-14`。LLVM 14 无法读取 LLVM 22 opaque-pointer bitcode，实际结果为：

```text
error[SA-CLI-017]: llvm-dis failed
help: verify the input is valid LLVM bitcode for the installed LLVM toolchain
```

即便改用 LLVM 22 `llvm-dis` 得到文本再转换，所有权信息也已经在 LLVM IR 层丢失。该路径最多用于 bring-up、差分执行或测试 importer，不能作为 Rust -> SA 的主架构。

### 3.3 简单加法也要求生命周期计划

本次 `bc2sa` 兼容性探针生成的最小输出为：

```sa
@export add(a: i32, b: i32) -> i32:
L_start:
    c = add a, b
    return c
```

执行 `sa check` 实际失败：

```text
error[MemoryLeak]: live registers remain at function exit
register: a
state: Active
```

符合当前 Referee 规则的输出至少需要处理仍存活的输入和临时值，例如：

```sa
@export add(a: i32, b: i32) -> i32:
L_start:
    c = add a, b
    !b
    !a
    return c
```

`sa_plugin_sla` 对同类函数也确实生成 `!b`、`!a`。这说明主要工作不是语法翻译，而是为每条 CFG 路径构造一致的 capability/lifetime plan。现有 `sci/docs/demos/rust-to-sa.md` 中的若干示例不能视为已通过 Referee 的实现证据。

### 3.4 MIR 是合适的语义入口

本地 rustc 对简单 checked add 的 MIR 已包含：

```text
_3 = AddWithOverflow(copy _1, copy _2);
assert(!move (_3.1: bool), ...) -> [success: bb1, unwind unreachable];
_0 = move (_3.0: i32);
```

enum match 已包含 `discriminant`、`switchInt`、downcast 和 `unreachable`；slice/dyn trait 已形成静态或动态调用。MIR 因而同时保留了类型化 CFG、place projection、`Copy/Move/Ref/Drop` 和调用实例信息，且位于 LLVM 丢失 Rust 语义之前。

但 MIR 的 `Move` **不能机械映射**为 SA `^`。rustc 自身在 `rust/compiler/rustc_middle/src/mir/syntax.rs:1289-1305` 明确说明普通 `Move` 当前在 codegen 中通常没有运行效果，其内存模型语义仍待澄清；而 SA move/release 会改变 capability 或释放资源。lowering 必须分别建模“值搬运”“place 初始化状态”“drop glue”和“SCI capability 转移”。

### 3.5 当前 SCI 表达能力的直接证据

- `sci/src/common/signature.zig:11-27` 的签名类型只有 `void/i1..i64/u8..u64/f32/f64/ptr/blob_handle/v128`；没有 `i128/u128`、任意聚合、scalar pair 或通用向量类型。
- `sci/src/emit_llvm_llvmc.zig:25-38,109-125` 的 native C bridge 类型范围更小；`v128` 仍会走 `UnsupportedType`，名义类型集合尚未在 native emitter 闭合。
- `sci/src/sab.zig:10-19` 显示当前 SAB v4 只有 symbol、function signature、const 和 instruction 四类 section。
- `sci/src/sab.zig:633-661` 的函数签名只编码 primitive return、参数 primitive/capability 和少量标志，没有 target、calling convention 或 `sret/byval` 等 pass mode。
- `sci/src/emit_llvm_llvmc.zig:83-98` 的 `CModule` 没有 triple、DataLayout、CPU/features、relocation/code model 字段。
- `sci/src/emit_llvm_llvmc_shim.c:364-399` 和 `1985-2016` 固定使用 `LLVMGetDefaultTargetTriple()` 与 host target machine。
- `sci/src/referee/table.zig:20-39` 的 capability table 主要是 register mask、origin 和 lock 引用；它不是 Rust NLL、partial move、UnsafeCell、Pin 或 provenance 模型。

这些是阻断完整 Rust backend 的结构性缺口，而不是单个转换器 bug。

## 4. 候选方案比较

| 方案 | Rust 保真 | SCI 验证价值 | 工程风险 | 结论 |
| --- | ---: | ---: | ---: | --- |
| A. 重写 Rust 前端后直接生成 SA | 低 | 中 | 极高 | 否决 |
| B. rustc AST/HIR -> SA | 中 | 中 | 高 | 不推荐；过早，布局/mono/drop 尚未稳定 |
| C. rustc mono `Instance` + codegen MIR -> typed SCI plan -> SA/SAB | 高 | 高 | 高但可控 | **推荐** |
| D. rustc `rustc_codegen_ssa::Builder` 全量适配 | 高 | 中 | 很高 | 可借接口，不宜完全照搬 LLVM-shaped builder |
| E. LLVM bitcode -> bc2sa -> SA | 机器语义中、Rust 语义低 | 低 | 版本耦合高 | 仅测试/迁移工具 |
| F. rustc 产 object，SCI 只包装/链接 | 高 | 极低 | 低 | 不是 Rust -> SA |

### 4.1 为什么不是重写 rustc query

rustc 在分析完成后才进入 `CodegenBackend::codegen_crate`。expand、resolve、typeck、borrowck、MIR、mono 和 metadata 属于 rustc 的完整 query/provider 图。out-of-tree backend 可以覆盖既有 provider，但不能把 query 系统替换成一个简单插件接口。重写该层没有收益，且会把项目变成 Rust 编译器 fork。

### 4.2 为什么以 Cranelift 后端为模板

当前 rustc 源码中：

- `rust/compiler/rustc_codegen_cranelift/src/lib.rs:123-124,218-242` 实现 `CodegenBackend`，并复用 `rustc_codegen_ssa::base::codegen_crate`。
- `rust/compiler/rustc_codegen_ssa/src/base.rs:692-742` 已负责 mono item 收集、CGU 分区、allocator shim 和异步 codegen 调度。
- Cranelift 后端自行读取 MIR 并降低，而不是实现一套完全 LLVM-shaped `Builder`。
- 当前源码量级约为：cg_clif 16.8K、cg_gcc 25.2K、LLVM backend 30.2K、共享 `rustc_codegen_ssa` 29.6K Rust LOC。

这表明真正的 Rust backend 不是几百行 adapter，但可以复用 rustc 已有的 crate/CGU 调度和标准 object work-product 机制作为起点，避免重复实现大部分外围管线。proof sidecar 的保存、恢复和 link 聚合不在标准路径中，仍需定制 `join_codegen`/缓存集成，不能把“复用 `base::codegen_crate`”理解为证明缓存自动可用。

## 5. 推荐端到端架构

本节以下组件和命令均是**拟议设计，当前仓库尚未实现**；架构图表示目标边界，不表示现有代码已经具备该管线。

```text
Cargo / sa rust
  |
  | target unit: rustc_codegen_sci
  | host build.rs / proc-macro: rustc_codegen_llvm
  v
rustc 官方前中端
  parse -> expand -> resolve -> typeck -> borrowck
  |-- machine path -> optimized MIR -> monomorphization -> CGU partition
  |                   -> TyAndLayout + FnAbi + CodegenFnAttrs + alloc graph
  |-- strict proof -> BorrowckSidecar (before Body steal)
                      + pass-level refinement certificate [spike gate]
                      + pre-opt/mono/inline/crate mapping
  |
  v
rustc_codegen_sci  (与 rustc commit 锁定的薄 adapter)
  -> MonoItem/Instance 收集
  -> RustSemanticPlan
  -> SciLoweringPlan（typed、target-qualified、ownership-rich）
  -> ProofFnContract / .sciproof [严格模式]
  -> SA text emitter  [首期审计/差分]
  -> structured SAB emitter [生产路径]
  |
  | versioned framed IPC / versioned artifact
  v
sci-codegen-worker（独立进程）
  -> schema/feature negotiation
  -> SCI Referee
  -> target object emitter
  -> .o + structured diagnostics + proof report/contract attestation
  |
  v
rustc metadata / rlib / archive + proof aggregator + linker pipeline
```

### 5.1 组件边界

#### `rustc_codegen_sci`

- 实现 rustc `CodegenBackend`，严格绑定一个 rustc commit 和 host triple。
- `-Zcodegen-backend` 暴露的是 rustc-private dylib ABI，不是稳定插件 ABI；adapter 必须与同一版 `rustc_driver` 构建和发布。
- 复用 mono/CGU 调度与标准 object work product；proof artifact 必须由自定义 save/restore/join 路径或可验证的 object section 显式接入。
- 从 rustc 获取最终 `TyAndLayout`、`FnAbi`、materialized `CodegenFnAttrs`、mangled symbol、linkage、静态分配和 span。
- 实现 `ExtraBackendMethods::codegen_allocator`；allocator shim 不是 worker 或 linker 可以自动补出的普通 metadata。
- 显式实现前端可见的 `CodegenBackend` capability hooks：`init` 早期拒绝不支持的 target/panic、显式 Thin/Fat LTO、`linker-plugin-lto`、coverage/sanitizer 和输出组合（可像 cg_clif 一样接受内部 `ThinLocal`）；`target_config` 准确返回 target features，并把 MVP 不支持的 `f16/f128` 及 math reliability 设为 false；M1 的 `supported_crate_types` 只开放 `Executable`/`Rlib`，proc macro 继续走 host LLVM；`thin_lto_supported` 为 false；intrinsic replacement/fallback 列表逐项登记。trait 默认值会宣称 ThinLTO、全部 crate type 和可靠 `f16/f128`，不能沿用。
- `sa-verified-subset` 需要 borrowck capture 和受控/可证明的 MIR pass pipeline；纯 codegen adapter 不能从 optimized MIR 恢复完整 NLL facts，窄 provider 也不能自动证明中间变换。
- 只包含 Rust 内部 API adapter 和 lowering，不直接链接 LLVM 14/SCI Zig internals。
- 每次发布随对应 rustc toolchain 重建，文件名带 rustc commit 与内容 hash。

#### `SciLoweringPlan`

- 是唯一语义来源，不让 SA 文本和 direct SAB 各自实现 Rust 规则。
- 固定 target、类型级 `TypeLayoutRecipe`、值级 allocation/place-init/memory-op plan、调用 ABI、逐函数 feature/属性、drop glue、临时值、CFG merge、trait shim/vtable、源码位置和 proof descriptor。
- 具备 feature bitmap；不支持项在构造 plan 时失败，不进入 emitter。
- 可确定性序列化，用于审计、缓存和 worker IPC。

#### SA text emitter

- 首期主产物，便于人工检查和 golden diff。
- 只做 plan 的无损序列化，不在 emitter 中推断所有权或修补 ABI。
- 允许 `--emit=sa`，但生产构建仍必须经过 Referee。

#### direct SAB emitter

- 与文本 emitter 消费相同 plan。
- 必须有 `--no-fallback`；禁止“direct SAB 失败后静默走 SA 文本”。
- 输出前后都校验版本、target 和 feature，缓存写入前必须通过 Referee。

#### `sci-codegen-worker` / 稳定 engine API

- 使用独立进程把 SCI/LLVM engine 的版本、panic、OOM 和 ABI 漂移与 rustc adapter 隔离。
- framed RPC 至少包含：协议 major/minor、request id、deadline/cancel、target descriptor、artifact、结构化诊断、proof report 和 exit category。
- 长期可同时提供稳定 C ABI `libsci_codegen`，但 ABI 中只能使用定长整数、pointer+length、opaque handle 和配套 free；不能暴露 Zig allocator/slice 布局。
- engine 接收显式 target，不能再选择 host default target。

#### `sa_plugin_rust`

- 只做 `sa rust check/build/test/emit-sa` 命令编排、权限确认和 artifact 注册。
- 通过子进程调用与 rustc commit 锁定的 `rustc-sa-driver`，不在 `sa` 宿主进程 `dlopen` rustc/LLVM；该外层进程边界负责隔离 rustc ICE。
- 不承担 Rust parser/type checker，也不把 SCI plugin command ABI 当 codegen SDK。

### 5.2 为什么需要进程边界

本地 rustc 工具链携带 LLVM 22 backend，SCI native emitter 当前基于 LLVM-C 14。若 adapter 把 SCI engine 及 LLVM 14 直接链接进 rustc 进程，一旦同一进程还加载 LLVM backend 或相关符号，就会引入全局符号、插件生命周期、线程状态和崩溃隔离风险。序列化成本相对 LLVM object emission 通常可控，并可通过每次构建一个持久 worker、共享只读 schema 和 content-addressed artifact 降低。

## 6. MIR -> SCI lowering 契约

### 6.1 机器 lowering 与严格 proof 是双输入

每个单态化 `Instance` 的**机器 lowering 输入**至少携带：

- optimized/drop-elaborated MIR 和实例化 generic args；
- 每个 local/place 的 `TyAndLayout`；
- function/call-site 的 `FnAbi`；
- symbol、linkage、visibility、section、COMDAT/TLS 等对象属性；
- CTFE allocation graph、relocation/provenance；
- span、inline scope 和必要的 debug location；
- panic strategy、target spec、CPU/features、opt/codegen flags；
- materialized `CodegenFnAttrs`，包括逐函数 target features、instruction set、linkage/section 和 sanitizer policy；
- 可获得的 retag/provenance 提示及 proof coverage 分类。

`sa-verified-subset` 另需**borrowck proof sidecar**：与 borrowck body 使用相同 region ID 的 `BorrowSet`、region inference/Polonius facts、loan 起止、place 与 source location。move/init path 不在 `BodyWithBorrowckFacts` 中直接提供，还必须在同一阶段捕获或由同版 rustc 重算 `MoveData`/初始化 dataflow。`rust/compiler/rustc_borrowck/src/consumers.rs:80-122` 明确指出 borrowck facts 必须与对应 body 一起消费，且 body 被 steal 后再请求会 panic；`optimized_mir` 随后还会 steal body、优化、内联和重排 CFG。

因此严格模式需要在 borrowck 时捕获 sidecar，并解决四个映射：pre-opt -> codegen MIR、generic body -> mono `Instance`、inline source -> caller、local crate -> metadata/依赖 crate。Polonius consumer API 本身也不稳定，必须与 rustc commit 一起版本化。若任一 sidecar 或映射缺失，只能进入 `rust-trusted`，不能以 optimized MIR/`RetagInfo` 重建后宣称 NLL 等价。

这里存在一个当前阻断项：rustc 不为 drop elaboration、inlining、SROA、GVN 等变换输出可组合的 loan/place/location refinement certificate，span 和 inline scope 也不能替代该证明。`sa-verified-subset` 在映射 spike 通过前是 **No-Go**；可选路径只有锁定并禁用尚未证明保持映射的 pass、逐 pass 证明 refinement，或 fork/instrument MIR pipeline 产出 transformation certificate。仅增加窄 provider/callback 只能取得输入 facts，不能闭合从 borrowck body 到 codegen MIR 的证明。

### 6.2 lowering 表

| MIR 构造 | SCI lowering | 所有权/ABI注意点 | MVP |
| --- | --- | --- | --- |
| `Local` / `Place` | SSA value 或 stack slot | offset/align 只取 rustc layout | 是 |
| field/index/deref projection | typed address + checked offset | 保留 base provenance、subobject range | 受限 |
| `StorageLive/Dead` | slot lifetime/debug marker | 不是 Drop，也不是物理 free | 是 |
| `Operand::Copy` | value read | 不创建 owner；保持 validity | 是 |
| `Operand::Move` | value transfer + init-state 更新 | 不能机械发 SA `^` 或 `!` | 受限 |
| `Rvalue::Ref` | loan/provenance descriptor | 区分 shared/mut、Freeze/UnsafeCell | M2 |
| `AddressOf` / raw pointer | raw boundary | 必须计入 proof coverage | M2 |
| 整数/浮点运算 | typed op | signedness、overflow、fast-math 显式 | 是 |
| `CheckedBinaryOp` | op + overflow flag | debug assert/panic 路径保持 | 是 |
| cast/transmute/unsize | typed conversion plan | address space、validity、fat pointer | 后续 |
| aggregate/tuple/ADT | byte aggregate + field stores | padding、niche、discriminant由 rustc提供 | M2 |
| `Len` / `Discriminant` | layout-driven load/constant | 不由 SCI 重算 enum layout | M2 |
| `SetDiscriminant` | concrete tag-write recipe | direct/niche 编码与最小写入范围来自 rustc | M2 |
| `Goto` | `jmp` | capability state传递 | 是 |
| `SwitchInt` | 多路 switch 或比较树 | 每条边保存 state delta，merge 必须一致 | 是 |
| `Assert` | branch + 对应 panic lang item | `panic=abort` 只禁止 unwind；仍保留 handler/hook/Location | 是 |
| `Call` | `FnAbiCallPlan` + `ProofFnContract` | pass mode、hidden args、逐函数 feature、proof requires/ensures | 受限 |
| virtual call | vtable slot + indirect call | vtable layout、receiver ABI、shim | 后续 |
| `Drop` | 调用 drop glue，然后终结 obligation | drop 与 deallocation/cap release 分离 | M2 |
| `Return` | ABI return plan | sret/pair/cast 必须精确 | 受限 |
| unwind/cleanup edge | EH region/personality | MVP early reject | 否 |
| coroutine/async | state-machine MIR lowering | 依赖聚合、drop、pin/provenance | 后续 |
| inline/global/naked asm | target asm artifact | MVP early reject | 否 |
| intrinsic | 显式 intrinsic registry | 不允许按名称静默当 extern C | 逐项 |

### 6.3 CFG capability plan

不能在遍历 MIR 时遇到局部变量就立即插 `!`。推荐先构造全函数数据流：

1. 为每个 owner、loan、raw pointer、subobject 和 drop obligation 分配稳定 ID。
2. 对基本块求 entry/exit proof state，edge 上记录 move/borrow/end-loan/drop delta。
3. 用已捕获/重算的 `MoveData` 与初始化 dataflow 区分 partial move 和再次初始化，并识别 drop elaboration 生成的普通布尔 local/branch；不能假定 codegen MIR 暴露语义化的 drop-flag API。
4. 在 join 处验证 state 可合并；必要时拆边或发显式 merge，不允许任选一条前驱状态。
5. 最后由同一个计划生成 SA `&/^/!` 或 structured SAB proof op。

rustc 的实验性 `-Zcodegen-emit-retag` 和 `RetagInfo` 已能提供 size、mutable/Box/Freeze/protected、UnsafeCell/UnsafePinned layout，可作为输入设计参考，但它不是稳定 Rust 内存模型，也不能单独证明 NLL 等价。

### 6.4 跨函数 proof contract

`FnAbi` 只描述机器调用，不能表达“返回引用来自参数 0”“参数被消费”“loan 跨调用持续”或 drop/escape effect。每个可验证函数还需要版本化 `ProofFnContract`：

- 参数/返回值的 plain/owned/shared/mut/raw 分类与 provenance relation；
- consume、borrow、escape、may-drop、may-allocate 和 raw/FFI effects；
- 返回 loan 的来源、subobject range 和调用后 obligation；
- contract version/hash、proof policy、callee body/attestation identity；
- 间接调用允许的 contract signature。

声明处与 call site 双向校验，跨 CGU/crate 的 summary 作为 `.sciproof` sidecar 随 rlib/metadata 分发，并在最终链接前聚合。同一 rustc toolchain 中由 LLVM backend 构建的 sysroot、compiler-builtins 和 native object 若没有 contract，只能作为显式 trusted boundary 计入覆盖率；严格的 whole-program 声明要求依赖闭包都有可验证 contract/attestation。闭包不完整时，结论只能是“这些本地函数已验证”，不能是“整个程序已验证”。

## 7. SCI/SA/SAB 必须先完成的契约扩展

### 7.1 target-qualified module header

SAB vNext/engine request 必须显式包含：

- target triple、object format、endianness、pointer width、完整 DataLayout；
- module 默认 CPU/target features、relocation model、code model；逐函数 override 另附在函数记录中；
- panic strategy、TLS model、PIC/PIE、optimization/debug options；
- rustc commit、SCI engine ABI、SA ISA、SAB schema、sysroot identity；
- required/optional feature bitmap。

worker 必须拒绝未知 required feature 或 header 与 object emitter 不一致的 artifact。不能以运行 worker 的 host triple 代替目标 triple。

### 7.2 类型与内存模型

- 任意位宽整数，至少补齐 `i128/u128`；后续支持 `f16/f128` 和可扩展 SIMD。
- 带 address space 的 pointer；pointer machine value 与 provenance ID 分离。
- opaque byte aggregate/tuple/scalar pair 之外，还需要 rustc 降低出的类型级 `TypeLayoutRecipe`：size/align、`BackendRepr`、field offset/order、scalar valid range、variant-specific padding/overlap，以及 direct/niche variant tag encoding。SCI 不得自行重算 Rust ADT。
- `TyAndLayout` 不提供某个运行时值的 init mask。CTFE/static 的 bytes、逐字节初始化状态、relocation 和 provenance 属于 `AllocationImage`；move/partial-init/variant/field 的确定初始化状态属于由捕获/重算的 move/init dataflow 驱动的 `PlaceInitState`。
- copy/assignment/load/store 如何处理 padding、未初始化字节和 provenance 属于逐操作 `MemoryOpPlan`。`MaybeUninit` 横跨上述三层，不能由类型布局单独推导，也不能把 allocation 的值级 init mask 固化进 `TypeLayoutRecipe`。
- load/store 携带 value size、alignment、volatile、nontemporal、atomic ordering 和 unaligned 语义。
- stack/global allocation 携带 size、alignment、mutability、section、TLS 和初始化状态。
- GEP/field address 携带 inbounds 语义与 subobject/provenance 信息。

### 7.3 完整 `FnAbiPlan`

rustc `rust/compiler/rustc_target/src/callconv/mod.rs:39-75` 定义的参数模式包括：

- `Ignore`
- `Direct`
- `Pair`
- `Cast { pad_i32, CastTarget }`
- `Indirect { attrs, meta_attrs, on_stack }`

`FnAbi` 还包含 variadic、fixed argument count、calling convention 和 `can_unwind`。因此 vNext 至少需要：

- return 和每个参数的 pass mode；
- hidden `sret`、unsized metadata、byval/on-stack 及 pointee size/align；
- scalar extension、`inreg` 和 ABI-critical attributes；
- calling convention、variadic、unwind；
- `#[track_caller]` 等已 materialize 到 `FnAbi` 的 hidden argument；
- call-site 与 declaration 双边一致性校验。

`NoAlias/NonNull/ReadOnly/NoUndef/dereferenceable` 等属性可在首期保守少发以损失优化，但不能伪造；sign/zero extension、inreg、sret/byval 等会改变 ABI，不能省略。

每个函数还必须携带降低后的 `CodegenFnAttrs`：逐函数 target features、instruction set、alignment、linkage/section、nounwind/sanitizer 等支持状态。worker 必须按函数设置 target machine 属性，或在 plan 阶段明确拒绝；只看 module header 会让 `#[target_feature]` 函数生成非法指令。proof contract 与机器 `FnAbiPlan` 分开编码、共同绑定到函数 identity。

### 7.4 静态分配和 relocation graph

Rust 常量不是只有字节字符串。协议需要表示：

- arbitrary bytes、padding/未初始化区间和 alignment；
- 指向 static/function/vtable 的 relocation 与 addend；
- provenance、mutability、linkage、visibility、unnamed_addr；
- TLS、COMDAT、weak/extern、section、used/compiler_used；
- alias、函数地址和跨 CGU 引用。

没有该能力，即使最小函数能运行，也无法可靠编译常见 enum、trait object、字符串、panic metadata 和 `core/alloc`。

### 7.5 structured diagnostics 和 source map

- 每个 lowering/proof/object 错误必须带 stable code、severity、rust span、mono instance、MIR location、SCI instruction 和 cause chain。
- `unsupported` 与 `compiler bug` 分开；禁止让用户看到无上下文的 `UnsupportedType` 或 worker crash。
- SA/SAB 保留 upstream location，rustc adapter 把 worker 诊断重映射为标准 rustc diagnostic。
- proof report 单独输出覆盖率与 escape 原因，不能把“验证通过”和“未跟踪但允许”混成一个布尔值。

## 8. 所有权、安全与信任边界

### 8.1 两种明确模式

#### `rust-trusted`

- Rust 安全性依赖 rustc borrow checker、标准库和已审计 unsafe 代码。
- SCI 验证结构、CFG、类型/ABI、包权限、显式资源和已能建模的 capability。
- codegen-ready MIR 足以驱动该模式；borrowck sidecar 缺失会被报告，但不伪造成第二次 Rust proof。
- raw/UnsafeCell/FFI 等边界必须出现在 proof report 中。
- 不宣称 Referee 重新证明了完整 Rust 所有权。

这是常规 Rust/Cargo 兼容模式，也是最先可交付的模式。

#### `sa-verified-subset`（当前为映射 spike 门禁）

- 限定 `panic=abort`，禁止或严格白名单 unsafe、raw pointer、FFI、asm、unwind、TLS 和未知 intrinsic。
- 同时消费 codegen MIR、borrowck proof sidecar 和可组合的 pass-level refinement certificate，经已验证的位置/单态化映射保留 owner、loan、drop、subobject 和 CFG 信息；`RetagInfo` 只能补充，不能替代 sidecar/certificate。
- 每个调用都校验 `ProofFnContract`；whole-program 声明要求跨 CGU/crate/sysroot/native 的 contract/attestation 闭包完整。
- 所有 escape 都有结构化理由；超过阈值或进入未知语义即编译失败。
- 只有该模式可表述为“通过 SCI capability 验证的 Rust 子集”。

该模式目前不是普通的 M2 实现承诺。只有 MIR 映射 spike 证明“所有启用 pass 均可追溯或已禁用”，才可从 No-Go 转为 Conditional Go；在此之前，即使 Referee 接受生成的 SA，也只能报告 `rust-trusted` 或某个与 Rust borrowck 无等价声明的局部 SCI proof。

### 8.2 必须公开的 proof coverage

每个 crate 和 CGU 至少报告：

- tracked functions / total functions；
- tracked pointer operations / total pointer operations；
- tracked allocations / total allocations；
- `raw`、`assume_safe`、`native`、`ffi_wrapper` 和 unknown intrinsic 数量；
- 未证明的 UnsafeCell、FFI、asm、runtime、syscall 边界；
- 缺失 contract 的 direct/indirect calls、trusted sysroot/native boundaries 及其传递闭包；
- capability merge/drop obligation 的验证结果。

release gate 应要求 safe-Rust corpus 除明确审计的 runtime/FFI 边界外不自动退化为 Untracked。单纯“Referee 返回 OK”不能代替覆盖率。

### 8.3 TCB 与端到端声明

`object hash` 只把 proof report 绑定到某个对象，不证明 verified SCI IR 到机器码的语义保持。若没有可检查的 translation certificate、独立 object validator 或最终 linked-image validator，下列组件都属于 trusted computing base（TCB）：

- rustc 前中端/borrowck 及所绑定的 sysroot；
- borrowck capture、pass mapping、Rust -> lowering plan、SA/SAB codec；
- SCI Referee、worker 中的 LLVM/object emitter；
- archive/linker/relocator，以及声明覆盖范围内的 runtime/native boundary。

proof report 必须记录这些组件的版本/content hash、目标、policy 和未验证边界。当前严格模式最多声明“**SCI IR 已验证，并由所列 TCB 编译为该对象**”；不能仅凭 Referee verdict + object hash 宣称最终机器程序获得端到端 capability proof。后一个声明必须进一步验证 emission/link composition，或对最终 linked image 执行独立检查。

### 8.4 Drop 与释放不是同一个操作

Rust `Drop` 可能运行任意用户代码，`Box` 的 drop glue 才会最终调用 allocator；`StorageDead` 也不表示应运行析构。正确顺序是：

```text
MIR Drop terminator
  -> 调用准确的 monomorphized drop glue
  -> glue 正常返回后完成 place init-state/drop obligation
  -> 仅在 SCI proof 层终结对应 capability
```

不能为每个 MIR `Move` 发 `!`，也不能把 `!ptr` 同时解释为“析构对象”“释放 allocator 内存”和“结束借用”。vNext proof op 与 runtime deallocation 必须分离。

### 8.5 沙箱边界

Rust target code 经过 SA 不会自动获得系统调用沙箱。普通 `std`/unsafe crate 可通过 libc、syscall、线程或动态库绕过 SA package permission；proc macro 和 build script 更会在编译期执行任意 host 代码。安全声明必须分别覆盖：

- 编译 worker 的进程隔离和资源限制；
- proc macro/build script 的 host 执行策略；
- 目标程序的 runtime syscall/broker enforcement；
- SA package manifest 与实际 OS sandbox 的对应关系。

## 9. Cargo、sysroot、链接与增量

### 9.1 Cargo 接入

当前 nightly Cargo 已支持按 profile 选择 codegen backend，并允许 `build-override` 覆盖 build script、proc macro 及其依赖。推荐由 `sa rust init` 生成类似配置：

```toml
# .cargo/config.toml
[unstable]
codegen-backend = true

[profile.dev]
codegen-backend = "sci"
panic = "abort"

[profile.dev.build-override]
codegen-backend = "llvm"
```

release/test/bench profile 需要分别配置。该能力仍是 unstable，发布物必须捆绑匹配 nightly，而不是声称适用于任意系统 rustc。

上例中的 `"sci"` 假定对应 backend 已按 rustc 约定安装到绑定 toolchain；开发态也可使用 rustc 接受的 backend 路径。`"llvm"` 必须在该 toolchain 中可用。

Cargo 会忽略 tests、benchmarks、build scripts 和 proc macros 的 profile `panic` 设置；默认 test graph 会改用 unwind。`sa rust test` 若要维持首期 `panic=abort`，必须显式集成 nightly `-Z panic-abort-tests`、libtest 的 test-per-process 路径，并单独验证 rustdoc/doctest；在该门禁完成前，CLI 应早期拒绝 `test`，不能把普通 `cargo test` 列为 MVP 已支持能力。

### 9.2 proc macro 和 build script

- proc macro 必须生成 host dylib并由 rustc 加载；build script 也始终是 host unit。
- 初期统一用 LLVM backend 构建 host unit，target crate 用 SCI backend。
- 不尝试用 `sa_plugin_sla` 或 SCI command plugin 替代 proc-macro ABI。
- host 脚本的权限与可重复性另行治理，不能计入 target artifact 的 Referee 结论。

### 9.3 sysroot 策略

分三步：

1. **M1：mini_core / `#![no_core]` bring-up。** 避免把 sysroot 能力误判为基本 lowering 能力。
2. **M2/M3：同一 rustc toolchain 的 LLVM-backend-built sysroot 互操作。** 约束来自 rustc commit、target、metadata 和 ABI identity，不要求 SCI worker 与 rustc LLVM backend 使用同一 LLVM major。非泛型 object 可复用；泛型和 inline MIR 会在 SCI crate 的 mono `Instance` 上下文中降低，仍要求 backend 支持相关 intrinsic/layout。无 `.sciproof` contract 的 sysroot object 在严格模式中属于 trusted boundary。
3. **M4：构建 SCI core/alloc/std。** 先 `panic=abort`，同时交付 allocator shim、compiler-builtins 和 panic runtime/handler，再逐项开放 thread/TLS/unwind 等能力。

Rust ABI 本身不稳定，因此 adapter、sysroot、依赖 metadata 和 rustc commit 必须一致。对 `extern "C"` 也只能承诺目标 C ABI 子集，不可仅凭 `repr(C)` 名称假定实现正确。

### 9.4 对象、rlib 和最终链接

- SCI 每个 CGU 生成标准 `.o`，并把 rustc 需要的 symbol/linkage 元数据返回 adapter。
- rustc 继续负责 `.rmeta`、rlib/archive、native library propagation 和最终 linker invocation。
- `rustc_codegen_ssa` 只决定 allocator shim 的内容并调 `ExtraBackendMethods::codegen_allocator`；SCI backend 必须实现该方法并生成 allocator module。compiler-builtins 与 panic runtime/handler 也必须由匹配 sysroot/backend 提供。
- `.sciproof` contract/attestation 随 rlib 或并行 artifact 分发；最终 link 前由 adapter 聚合，不由系统 linker 猜测。
- 初期不要让 `sa build-exe` 重新解释 Cargo crate graph；它可作为单 artifact 测试工具。
- link-time 错误必须保留 rustc crate/instance 与 SCI symbol 的映射。

### 9.5 增量缓存

保留 rustc red-green/query DAG 和 CGU `WorkProductMap`，但先区分三类产物：`BorrowckSidecar` 是前中端 facts，`.sciproof` 是跨 crate 函数 contract/attestation，`VerifiedCguManifest`/`CguProofReport` 才是与单个 object 绑定的增量验证产物。

`WorkProduct.saved_files` 的 key 本身可扩展，但 stock `rustc_codegen_ssa::back::write` 的 join/save/restore 只复制 object、asm、DWO、LLVM IR/bitcode 等已知 `CompiledModule` 产物，不会自动保存上述 SCI 文件；增量 loader 也只检查 saved file 存在，不验证内容 hash。因此 SCI 的 `join_codegen` 必须在 stock join 后把每 CGU 的 plan、`VerifiedCguManifest` 和 `CguProofReport` 原子复制进 incremental directory，并以独立 key 合并进对应 `WorkProduct`，或者把等价完整信息嵌入可验证的 object section。manifest 自身必须绑定 object/plan/proof/policy/contract-set hash，内容损坏由 adapter 检出。

SCI 的 plan/SAB/proof/object 必须是同一个不可拆分的 verified work product；二级缓存 key 至少包括：

```text
rustc commit + adapter content hash
+ SCI engine ABI + SA ISA + SAB schema
+ target triple/DataLayout/CPU/features
+ panic/opt/codegen/debug flags
+ sysroot/metadata identity
+ CGU/mono-item stable hash
+ lowering/proof policy version
```

缓存值至少绑定 `{plan hash, proof-policy hash, proof report/hash, object hash, target, contract set hash}`。关键时序是：stock `determine_cgu_reuse` 在 `join_codegen` 之前已依据 previous work product + green dep-node 决定复用，不能等到 stock join 发现 manifest 损坏后再透明地把同一 CGU 改回 codegen。因此 adapter 必须在 reuse 决策前预检 manifest/内容 hash 或定制 reuse 调度；早期 bring-up 可暂时关闭 backend incremental caching，但 M1 在 proof-aware reuse 完成前不得宣称退出。如果缓存 plan 和 object binding 仍有效，也可重跑 Referee 后聚合；需要重新 codegen 时不能假装 stock join 能同次补做。

proof policy、engine/schema 和 adapter identity 必须进入 rustc 可跟踪的缓存身份。`-Zcodegen-backend` 只提供 backend 路径身份，因此推荐使用含完整 adapter/engine/policy hash 的文件名或独立 incremental namespace；不能原路径覆盖 dylib 后继续信任旧 CGU。其余要求包括：原子写入、header 二次校验、损坏隔离、LRU/预算、并发锁和负缓存边界。

## 10. MVP 范围与兼容矩阵

### 10.1 首个可信 MVP

- target：`x86_64-unknown-linux-gnu`，little-endian，64-bit pointer；
- crate：先 mini_core，再 `#![no_std]`；
- panic：`abort`，但仍精确调用 panic lang item/handler 并传 `#[track_caller]` location；只有 `immediate-abort` 才可直接发 abort；
- 类型：bool、`i8..i64/u8..u64`、`f32/f64`、受限 pointer；
- 控制流：直接调用、基本块、goto/switch、无 unwind edge 的 panic assert；
- 内存：显式 size/align 的 stack local 和受限 global；
- ABI：先 Rust/C scalar Direct，随后有限 Pair/Indirect；
- 输出：可审计 SA + structured SAB + `.o`；
- backend 声明：只暴露已支持的 target features/crate types/intrinsic，`f16/f128`、ThinLTO 和未实现选项在前端阶段准确关闭或拒绝；
- 限制：无 unwind、TLS、SIMD、i128、asm、sanitizer、LTO、variadic、跨目标；标准 `cargo test` 在 `-Z panic-abort-tests` 集成前不支持。

### 10.2 能力矩阵

| 场景 | 当前可行性 | 主要缺口 |
| --- | --- | --- |
| mini_core 标量函数 | 高 | target-qualified ABI/worker API |
| `no_std` 基本 CFG | 中高 | 聚合、静态分配、intrinsic、drop |
| `sa-verified-subset` 跨 MIR pass 等价证明 | 当前不具备 | transformation certificate/受控 pass pipeline、TCB/emission 证明 |
| enum/tuple/struct | 中 | niche/layout/Pair/Cast/Indirect |
| `Box`/slice/trait object | 中低 | alloc/drop/fat pointer/vtable/provenance |
| 常规 Cargo + proc macro/build.rs | 中 | host 分流可用；target 生态能力不足 |
| `sa rust test` (`panic=abort`) | 中低 | nightly flag、test-per-process、libtest/rustdoc/doctest |
| 同一 rustc toolchain 的 LLVM-built sysroot 互操作 | 中 | rustc/target/metadata/ABI identity、泛型/intrinsic 覆盖 |
| SCI-built core/alloc/std | 低到中 | backend 完整性、TLS/thread/panic/runtime |
| panic unwind | 低 | EH/personality/cleanup ABI |
| unsafe/raw/UnsafeCell 完整证明 | 低 | Rust 内存模型与 SCI proof contract |
| asm/SIMD/sanitizer/LTO | 低 | IR、target emitter、工具链协议 |
| 多 target 完整 Rust | 当前不具备 | 长期 backend 维护工程 |

## 11. 测试、诊断和性能门禁

### 11.1 正确性测试金字塔

1. **schema/IR 单测**：所有 type、layout、ABI、relocation、proof op 编解码 roundtrip。
2. **MIR lowering golden**：每种 statement/terminator/place projection 的 plan、SA、SAB 三方一致。
3. **ABI fixture**：Rust LLVM caller <-> SCI callee 双向调用；逐项覆盖 Direct/Pair/Cast/Indirect、extension、sret/byval。
4. **差分执行**：同一 Rust corpus 分别用 LLVM 和 SCI backend 运行，对比 stdout、exit、memory、panic/abort。
5. **Miri/UB corpus**：对可由 Miri 执行的 safe/subset 用例对照；Miri 不是最终规范，但可发现 provenance/drop 偏差。
6. **Referee negative tests**：use-after-move、double drop、CFG merge、partial move、borrow conflict 必须稳定拒绝。
7. **Cargo E2E**：真实 workspace、proc macro、build.rs、依赖泛型、rlib、incremental clean/dirty build，以及 `-Z panic-abort-tests`/rustdoc 路径。
8. **fuzz/property**：MIR plan decoder、SAB decoder、ABI plan、CFG proof dataflow 和 worker protocol。

可采用 `abi-cafe` 基础集做 ABI 对照，并复用 rustc codegen backend test 体系。任一 unsupported feature 都要有 compile-fail 用例，不能落到链接错误或错误机器码。

### 11.2 no-fallback 和对等门禁

- CI 必须运行 direct SAB `--no-fallback`。
- 同一 plan 的 SA 路径与 SAB 路径应产生等价 Referee 结论和运行结果。
- fallback 只能作为开发诊断命令，并在 artifact/proof report 中显式标记；release 构建完全禁用。
- 每次扩展能力都需要更新 feature matrix 和 proof coverage，不以测试数量替代覆盖率。

### 11.3 性能评估

SCI 当前最终仍走 LLVM，因此 rustc 前端成本不会消失，还会增加 MIR -> SCI、序列化和 Referee 成本。首期不得承诺比 rustc LLVM 更快。基准至少记录：

- clean/dirty/no-op build wall time 和 CPU time；
- rustc adapter、IPC、Referee、LLVM emission、link 各阶段耗时；
- peak RSS、worker restart、cache hit rate；
- `.sa/.sab/.o/exe` 大小；
- 运行时吞吐、延迟和机器码质量；
- 同机同 commit 下 LLVM、Cranelift、SCI 三方对照的 p50/p95。

若目标是 debug 编译速度，长期需要 SCI -> Cranelift 或直接 object emitter；仅在 LLVM 前增加验证层通常不会自然获得 Cranelift 级编译速度。

## 12. 分阶段路线与退出条件

### 12.1 M0：冻结 ABI/IR 契约

交付：target descriptor、`TypeLayoutRecipe`、`AllocationImage`、`PlaceInitState`、`MemoryOpPlan`、`FnAbiPlan`、materialized function attrs、`ProofFnContract` schema、relocation graph、proof descriptor、TCB manifest、版本化 worker wire protocol、结构化诊断和版本协商。另冻结 backend capability hooks，以及 proof work-product 的 save/restore、pre-reuse validation 和失效协议；M0 包含能运行这些 conformance fixture 的最小 hook/cache harness，不要求已有可编译 Rust corpus。稳定 C ABI 可后续提供，不是首期必需条件。

退出条件：

- native emitter 对声明支持的 PrimType 闭合；
- target 不再取 host default；
- `target_config`、`supported_crate_types`、`thin_lto_supported`、`init` 和 intrinsic fallback/replacement 对所有声明能力准确，默认 `f16/f128`/ThinLTO/未知 crate type 不会泄漏，`linker-plugin-lto` 被早期拒绝；
- LLVM caller/callee ABI fixture 双向一致；
- schema roundtrip、未知 feature 拒绝、损坏 artifact 测试通过；
- enum direct/niche tag、`SetDiscriminant`、`track_caller` 和逐函数 target-feature fixture 通过；
- 写出 vNext 规范并由 rustc/SCI 两侧共同评审。

### 12.2 M1：backend bring-up

交付：绑定 nightly 的 `rustc_codegen_sci`、mini_core、scalar/CFG/call/static、CGU object 和 rustc link。

退出条件：

- 最小 corpus 与 LLVM backend 差分执行通过；
- SA 文本和 SAB no-fallback 对等；
- object 可重复，clean/dirty incremental 正确；
- 自定义 join/cache 路径或 object-section 方案能原子保存并恢复 `{plan, proof report, object, contract}` binding，首次与 clean/dirty 复用构建一致；
- 缺失/篡改 `VerifiedCguManifest` 或 `CguProofReport`、object/plan/proof hash 不一致时绝不复用，并走已冻结的 pre-reuse veto、自定义调度或 hard-fail 路径；
- proof policy、contract set、adapter、engine 或 schema 变化会可靠失效旧 CGU；
- clean reuse 的 `CguProofReport` 确实进入 crate/link proof 聚合。

### 12.3 M2：`no_std` + ownership-rich lowering

`rust-trusted` 交付：aggregate/enum/niche、Pair/Cast/Indirect、drop glue、Box/ref/raw 边界、partial move、field borrow、CFG capability join、显式 proof coverage 和跨函数 boundary summary；不宣称这些机器 lowering 已重新证明 Rust borrowck。

`sa-verified-subset` 是独立研究 spike，不计入承诺性 M2 交付。spike 捕获 borrowck sidecar，枚举每个启用的 MIR pass，并选择“禁用未证明 pass”或“instrument pass 产出可组合 refinement certificate”；在该门禁通过后，才实现跨函数 `ProofFnContract` 的严格闭合。

退出条件：

- drop/borrow/partial move negative corpus 稳定；
- LLVM/Miri 差分通过并无 ABI mismatch；
- strict spike 只有在所有启用的 drop elaboration/inline/SROA/GVN 等 pass 都有可组合 refinement certificate 或被禁止后才可转为 Conditional Go；sidecar、certificate 或映射缺失一律 hard fail；
- 转为 Conditional Go 后，safe corpus 不自动降级为 Untracked，proof coverage 达到冻结阈值，闭合 corpus 的 direct/indirect call contract 全部验证；开放依赖只能报告局部 proof；
- 若要声明机器码端到端 proof，还需 translation certificate/object validator/linked-image validator 门禁；否则声明必须明确列出 TCB。

### 12.4 M3：Cargo 生态

交付：profile backend 分流、host LLVM proc macro/build.rs、同一 rustc toolchain 的 LLVM-built sysroot 互操作、core/alloc 常用 intrinsic，以及 `-Z panic-abort-tests`/rustdoc 测试路径。

退出条件：

- 含 derive proc macro 和真实 build.rs 的 workspace 端到端构建；
- host/target artifact 分离且可重复；
- test/bench/release profile 行为明确，abort test-per-process 与 doctest 门禁通过；
- 跨 crate 泛型、rlib 和 native dependency smoke 通过。

### 12.5 M4：SCI sysroot 与增量产品化

交付：SCI 编译的 core/alloc，随后是受限 std (`panic=abort`)；allocator shim、compiler-builtins、panic runtime/handler、稳定 artifact/cache 生命周期和发布工具链。

退出条件：

- 目标 sysroot 测试与 rustc backend tests 通过；
- ABI/metadata/rlib 升级兼容策略明确；
- cache corruption、eviction、并发和升级测试通过；
- 有可复现的 toolchain bundle 与支持矩阵。

### 12.6 M5：困难特性逐项开放

unwind、TLS、asm、i128、SIMD、多 target、LTO、debuginfo、sanitizer 分别立项。每项必须有 capability flag、早期诊断、ABI/运行测试和性能门槛，不能一次性标记“完整 Rust”。

### 12.7 人力与时间量级

以下仅用于预算，不是交付承诺：

| 范围 | 建议团队 | 量级 |
| --- | --- | --- |
| M0 契约 + M1 bring-up | 2 名 Rust backend + 1 名 SCI/LLVM | 3-5 个月 |
| M2 可用 `no_std` `rust-trusted` 子集 | 3-4 名全职工程师 | 再 4-7 个月；不含 strict mapping/certificate 研究 |
| M3/M4 产品级 Cargo 子集 | 4-6 名，含测试/发布工程 | 再 6-12 个月 |
| M5 与持续追随 rustc | 专职长期维护 | 按特性持续投入 |

完整 alternative backend 的成本应按“多年维护的编译器后端”估算，而不是一次性 converter。rustc internal ABI 不稳定，每次升级都要重编 adapter、跑 ABI/差分/sysroot 回归。

## 13. 风险矩阵与停止条件

| 风险 | 概率 | 影响 | 控制措施 |
| --- | --- | --- | --- |
| `FnAbi`/layout 错配产生静默错误码 | 高 | 致命 | M0 先行、双向 ABI fixture、rustc 为唯一布局权威 |
| MIR move/drop 与 SA capability 误映射 | 高 | 致命 | 分离值/init/drop/proof；CFG 数据流；negative corpus |
| optimized MIR 与 borrowck facts 无 refinement certificate | 高 | 致命 | strict 当前 No-Go；禁用未证明 pass 或 instrument/fork pass pipeline；缺失即 hard fail |
| 跨函数/crate contract 不闭合却宣称 whole-program proof | 高 | 致命 | `ProofFnContract`、rlib sidecar、link attestation、trusted boundary 计数 |
| Referee verdict + object hash 被误称机器码端到端 proof | 高 | 致命 | 明列 TCB；translation certificate/object/linked-image validation 单独门禁 |
| 类型布局混入值级 init mask | 中高 | 致命 | `TypeLayoutRecipe`、`AllocationImage`、`PlaceInitState`、`MemoryOpPlan` 分层 |
| backend trait 默认值虚报能力 | 高 | 高 | M0 显式实现并测试 capability hooks，未支持项在前端早拒绝 |
| raw/UnsafeCell 使 proof coverage 归零 | 高 | 高 | 双模式、覆盖率报告、strict subset hard fail |
| rustc internal API 高频漂移 | 高 | 高 | commit 锁定、薄 adapter、bundled toolchain、自动升级测试 |
| LLVM 22/14 同进程冲突 | 中高 | 高 | worker 进程隔离、稳定 wire protocol |
| sysroot/intrinsic 长尾 | 高 | 高 | mini_core 起步、feature matrix、逐项门禁 |
| 标准 work-product 路径漏存 proof 或错误复用 object | 中高 | 高 | 自定义 join/save/restore 或可验证 object section；内容 hash、原子绑定、破坏性测试 |
| “经过 SA 即沙箱/已证明”的错误宣传 | 中 | 高 | 信任边界文档、proof coverage、OS enforcement 分离 |
| 编译速度低于 LLVM baseline | 中高 | 中 | 分阶段 profiling；direct SAB；并行 worker；必要时换 emitter |
| SLA/SCI 内部 API 被当稳定 SDK | 高 | 中高 | 发布稳定 engine API，禁止 sibling 源码 import |

满足以下任一条件应暂停扩面，而不是增加 fallback：

- M0 不能在不猜测布局的情况下表达声明支持的 `FnAbi`；
- 同一 ABI fixture 在 LLVM/SCI 间出现无法定位的非确定 mismatch；
- strict safe corpus 需要大面积自动 `ffi_wrapper`/Untracked 才能通过；
- strict 模式无法可靠取得/映射 borrowck sidecar，或跨调用 contract 不能闭合；
- 所有启用 MIR pass 无法提供 refinement certificate 且不能被 strict pipeline 禁用；
- 项目要求机器码端到端 proof，却拒绝把 emitter/linker 列入 TCB且没有 translation/final-image validator；
- worker/artifact 无法可靠绑定 target、rustc 和 SCI 版本；
- 增量构建会复用 ABI 或 proof policy 已变化的旧 object；
- 项目要求“完整 std/多平台”但不提供长期 backend 维护团队。

## 14. 从 `sa_plugin_sla` 借鉴什么

### 14.1 可借鉴

- 高级语言前端直接进入类型化 lowering，再分叉 SA text/direct SAB 的 Y 型结构。
- 共享 call/ABI/argument/refcell 等 lowering plan，避免两个 emitter 各自解释语义。
- direct SAB no-fallback、SA/SAB parity、host install 和端到端验证门禁。
- 托管中间产物、稳定性元数据和 benchmark 分类。
- buffer + length + 配套 free 的窄 C ABI 所有权模式。

### 14.2 不能复用为 Rust 实现

- SLA parser/type checker/monomorphizer 只实现 Rust-like surface，不是 Rust 语义。
- SLA 不具备完整 Drop、NLL/Polonius、proc macro、trait/unsafe/Pin/UnsafeCell 语义。
- 当前 direct SAB 仍可默认 fallback，且部分路径未强制 Referee 后再写 artifact。
- 插件命令 ABI 只有 argv/stdout/stderr/status，不是结构化 codegen SDK。
- 插件同进程加载且依赖 Zig slice/allocator 布局，不适合作 rustc 稳定边界。
- 构建直接 import sibling SCI 源码、存在绝对路径探测和 dev-mode 权限绕过，不能复制到发布架构。

因此，SLA 证明的是“**typed frontend -> SA/SAB 的工程形态可工作**”，不是“它已经实现 Rust -> SA”。Rust 项目的语言语义主干必须来自 rustc。

## 15. 建议立即执行的工作包

1. **先写 RFC，不先写 converter**：冻结 `TargetDescriptor`、`FnAbiPlan`、`TypeLayoutRecipe`、`AllocationImage`、`PlaceInitState`、`MemoryOpPlan`、`BorrowckSidecar`、`ProofFnContract`、`ProofDescriptor`、TCB manifest 和诊断 schema。
2. **做 ABI spike**：手工从 rustc 导出 20-30 个 scalar/pair/sret/byval fixture，经 worker 发 object，与 LLVM 双向调用。
3. **做 backend skeleton**：复制 cg_clif 的最小 `CodegenBackend`/CGU lifecycle，显式实现 capability hooks 与 proof work-product save/restore，先生成空 object 和 metadata，再接 mini_core add/branch/call。
4. **拆开 proof 工作**：先在 `rust-trusted` 覆盖 scalar locals 和基本 CFG；另做 borrowck sidecar + MIR pass refinement certificate spike，未过门禁不排期 `sa-verified-subset`。
5. **建立 no-fallback CI**：SA/SAB/referee/object/LLVM differential 五联门禁和 proof coverage 报告。
6. **最后接 CLI/plugin**：后端和 worker 合同稳定后，再提供 `sa rust` 用户入口。

在 M0 评审通过前，不建议继续投资 `bc2sa` 来解决 Rust 主路径，也不建议从 SLA parser 补 Rust 语法。

## 16. 主要源码证据与官方资料

### 16.1 本地源码证据

- rustc backend capability 默认值/lifecycle：`rust/compiler/rustc_codegen_ssa/src/traits/backend.rs:36-105,107-150`
- backend hooks 的启动顺序与 crate-type 过滤：`rust/compiler/rustc_interface/src/interface.rs:438-458`、`rust/compiler/rustc_interface/src/passes.rs:927-947`
- rustc 动态 backend 的同版约束：`rust/compiler/rustc_interface/src/util.rs:313-360`
- mono/CGU 调度：`rust/compiler/rustc_codegen_ssa/src/base.rs:692-742`
- CGU reuse 在 join 前决定：`rust/compiler/rustc_codegen_ssa/src/base.rs:1216-1235`
- work product 结构、stock save/restore 与 loader 存在性检查：`rust/compiler/rustc_middle/src/dep_graph/graph.rs:1126-1137`、`rust/compiler/rustc_codegen_ssa/src/back/write.rs:462-504,913-949,2185-2189`、`rust/compiler/rustc_incremental/src/persist/load.rs:55-85`
- cg_clif 集成：`rust/compiler/rustc_codegen_cranelift/src/lib.rs:218-242`
- MIR `Move` 语义警告：`rust/compiler/rustc_middle/src/mir/syntax.rs:1289-1305`
- borrowck consumer/body-steal 约束：`rust/compiler/rustc_borrowck/src/consumers.rs:80-122`
- optimized MIR steal/重写：`rust/compiler/rustc_mir_transform/src/lib.rs:800-824`
- MIR inline/SROA/GVN pass pipeline：`rust/compiler/rustc_mir_transform/src/lib.rs:728-769`
- rustc `RetagInfo`：`rust/compiler/rustc_codegen_ssa/src/lib.rs:179-207`
- `PassMode` / `FnAbi`：`rust/compiler/rustc_target/src/callconv/mod.rs:39-75,591-620`
- enum tag 与 `SetDiscriminant`：`rust/compiler/rustc_abi/src/lib.rs:1984-2025`、`rust/compiler/rustc_middle/src/mir/syntax.rs:357-362`
- function codegen attrs：`rust/compiler/rustc_middle/src/middle/codegen_fn_attrs.rs:71-125`
- panic assert lang item lowering：`rust/compiler/rustc_codegen_ssa/src/mir/block.rs:723-825`
- `panic=abort` 与 immediate-abort 区别：`rust/library/core/src/panicking.rs:35-80`
- allocator shim backend hook：`rust/compiler/rustc_codegen_ssa/src/traits/backend.rs:163-179`、`rust/compiler/rustc_codegen_ssa/src/base.rs:728-742`
- Cargo backend profile：`rust/src/tools/cargo/src/doc/src/reference/unstable.md:1320-1347`
- Cargo build override：`rust/src/tools/cargo/src/doc/src/reference/profiles.md:435-460`
- Cargo abort test 限制：`rust/src/tools/cargo/src/doc/src/reference/profiles.md:192-214`
- SA primitive signature：`sci/src/common/signature.zig:11-49`
- SAB v4 sections/signature：`sci/src/sab.zig:10-19,633-661`
- native module/target：`sci/src/emit_llvm_llvmc.zig:25-98`、`sci/src/emit_llvm_llvmc_shim.c:364-399`
- Referee capability table：`sci/src/referee/table.zig:20-39`
- SLA Y 型 frontend/emitter：`sa_plugins/sa_plugin_sla/src/plugin_compile.zig:432-602,739-786`
- SLA no-fallback 测试策略：`sa_plugins/sa_plugin_sla/docs/testing_and_verification_cn.md:71-151`

### 16.2 官方资料

- [Backend-agnostic codegen](https://rustc-dev-guide.rust-lang.org/backend/backend-agnostic.html)
- [Lowering MIR](https://rustc-dev-guide.rust-lang.org/backend/lowering-mir.html)
- [Monomorphization and codegen units](https://rustc-dev-guide.rust-lang.org/backend/monomorph.html)
- [rustc query system](https://rustc-dev-guide.rust-lang.org/query.html)
- [Incremental compilation](https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation.html)
- [Libraries and metadata](https://rustc-dev-guide.rust-lang.org/backend/libs-and-metadata.html)
- [`-Zcodegen-backend`](https://doc.rust-lang.org/nightly/unstable-book/compiler-flags/codegen-backend.html)
- [Cargo per-profile codegen backend](https://doc.rust-lang.org/nightly/cargo/reference/unstable.html#codegen-backend)
- [Cargo build dependencies/profile override](https://doc.rust-lang.org/cargo/reference/profiles.html#build-dependencies)
- [Cargo `panic-abort-tests`](https://doc.rust-lang.org/nightly/cargo/reference/unstable.html#panic-abort-tests)
- [Rust ABI](https://doc.rust-lang.org/reference/items/external-blocks.html#abi)
- [Rust type layout](https://doc.rust-lang.org/reference/type-layout.html)

## 17. 最终判定

**Rust -> SA -> SCI 在技术上可行，但必须被实现为 rustc codegen backend 项目，而不是源码字符串转换器或 bc2sa 包装。**

最短可信路径是：锁定本地 nightly，在 x86_64 Linux + `panic=abort` 上先完成 target/ABI/布局协议，复用 rustc 的 mono/CGU 调度，从 mono `Instance` + codegen MIR 构造统一 typed lowering plan，用 SA 文本审计、direct SAB 交付，经独立 SCI worker 强制 Referee 后产 `.o`，最后回到 rustc 链接。若要进入 `sa-verified-subset`，除了 borrowck sidecar 和跨函数 `ProofFnContract`，还必须先通过 MIR pass refinement certificate spike；当前没有该证书，因此 strict 模式仍是 No-Go。若没有 translation/final-image validator，证明结论也只能是“SCI IR 已验证并由声明的 TCB 编译”，而非机器码端到端 proof。

在该路径上，`rust-trusted` 研究型受限子集可以 Go；`sa-verified-subset` 在映射 spike 前 No-Go；完整 Rust backend 目前 No-Go。决定项目能否升级为产品的，不是“能否翻译 add 指令”，而是 M0 的 ABI/target/layout/capability/cache 契约、M2 的 drop 与 strict refinement/call-contract 门禁，以及 M3/M4 的 Cargo/sysroot/增量证据是否全部通过。
