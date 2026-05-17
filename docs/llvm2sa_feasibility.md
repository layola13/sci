# llvm2sa 可行性评估报告

> 评估日期：2026-05-17
> 评估范围：基于本仓库 `src/emit_llvm.zig`（3247 行）、`src/common/instruction.zig`、`.probe_wasm2/hello.wasm.saasm.ll` 及现有编译管线的深度分析。

---

## 一、你已经拥有了半个 llvm2sa

这是最关键的发现。读完 `src/emit_llvm.zig` 之后，现实是：

```
当前管线（正向）：
.saasm → Flattener → Referee → [emit_llvm.zig] → .ll → zig cc → native

llvm2sa 是什么（逆向）：
.bc/.ll → [llvm2sa] → .saasm → 现有管线
```

**要做的，是把 `emit_llvm.zig` 的方向反转**。这带来了一个非常有趣的对称性——现有 Emitter 已经告诉了 llvm2sa 需要处理什么，因为它的输出就是 llvm2sa 的输入。

---

## 二、对称性分析：正向 vs 逆向映射

从 `emit_llvm.zig` 读出来的发射规律，直接反推 llvm2sa 的翻译表：

| LLVM IR（llvm2sa 输入） | SA-ASM（llvm2sa 输出） | 难度 |
|---|---|---|
| `%t = call ptr @malloc(i64 %n)` | `t = alloc n` | ✅ 直译 |
| `%t = alloca i8, i64 N, align 1` | `t = stack_alloc N` | ✅ 直译 |
| `%gep = getelementptr i8, ptr %p, i64 N` + `load` | `t = load p+N as T` | ✅ 字节偏移已展平 |
| `store T %v, ptr %gep` | `store p+N, v as T` | ✅ 直译 |
| `%t = add i64 %a, %b` | `t = add a, b` | ✅ 1:1 |
| `%t = icmp eq i64 %a, %b` | `t = eq a, b` | ✅ 直译 |
| `br i1 %c, label %L1, label %L2` | `br c -> L1, L2` | ✅ 直译 |
| `%t = cmpxchg ptr %p, i64 %e, i64 %n seq_cst acquire` | `t, ok = cmpxchg p+0, e, n seq_cst acquire` | ✅ 现有 ISA 完备 |
| `%t = atomicrmw add ptr %p, i64 %v monotonic` | `t = atomic_rmw_add p+0, v relaxed` | ✅ 直译 |
| **`phi i64 [ %v1, %L1 ], [ %v2, %L2 ]`** | **无对应指令** | ❌ **最大障碍** |
| **GEP 带变量偏移** `getelementptr %T, ptr %p, i32 %i` | 需展开为 `ptr_add` 链 | ⚠️ 需计算 |
| `call void @free(ptr %p)` | `!p`（理论）或 `call @free(p)` | ⚠️ 所有权语义丢失 |

---

## 三、三大技术障碍的逐一解剖

### 障碍 1：PHI 节点（最难，但有成熟解法）

本仓库的 `emit_llvm.zig` 在发射 label 时调用 `state.reloadLiveRegs()`，把 SA 的 capability mask 活跃寄存器全部通过 **alloca + store/load 的 mem-slotting** 方式固定下来。

```llvm
; emit_llvm 实际输出的 label 模式（PHI-free 的内存槽形式）：
%slot_3 = alloca i8, i64 64, align 16   ; 每个 SA 寄存器对应一个 slot
store i64 %t5, ptr %slot_3, align 16    ; 分支前写入
L_LOOP:
%t7 = load i64, ptr %slot_3, align 16   ; 标签后读出（reloadLiveRegs）
```

这已经是 LLVM **mem2reg 逆操作（Reg2Mem）的输出形式**。因此 llvm2sa 解决 PHI 问题有两条路：

1. **外部来源**（真实 Rust/C/Zig 编译产物）：处理前先跑 `opt -passes=reg2mem`，把所有 PHI 强制降级为 alloca+load/store
2. **本仓库自产的 `.ll`**：天生就没有 PHI，`emit_llvm.zig` 本来就是这样设计的

**难度降为可控。**

---

### 障碍 2：GEP 带变量偏移（中等，特定场景才遇到）

`emit_llvm.zig` 始终生成字节级字面量偏移的 GEP：

```llvm
%gep = getelementptr i8, ptr %slot_3, i64 8   ; 始终是 i8 基底 + 字面量偏移
```

但真实 Clang/Rustc 编译产物可能产生变量偏移：

```llvm
; 变量偏移（需要特别处理）
%idx = mul i64 %i, 24
%gep = getelementptr i8, ptr %arr, i64 %idx
```

SA-ASM 的 `ptr_add` 指令可以处理：

```
idx = mul i, 24
t = ptr_add arr, idx
```

**难度：中等**。需要追踪中间计算链，但 `ptr_add` 已在 ISA 中存在（见 `whitepaper.md`）。

---

### 障碍 3：所有权语义蒸发（设计层面的根本取舍）

这是无法回避的铁律：

```
Rustc/Clang → LLVM IR → llvm2sa → SA-ASM
```

在 LLVM IR 层面，没有 `Active` / `Consumed` / `Locked_Mut` 的任何信息。`@free(ptr %p)` 只是一个普通函数调用，而不是 SA 的显式 release `!p`。

**因此，llvm2sa 生成的 SA-ASM 中，所有寄存器都将是 `Untracked` 状态**，等价于整个函数体都处于 `@ffi_wrapper` 模式。Referee 的 CapabilityMask 验证在这种情况下退化为：**不做所有权检查，只做类型和跳转合法性检查**。

这对于**极速网络引擎**目标而言是完全可以接受的——从 Rust 编译来的代码，安全性已经由 Rustc 在上游保证。SA 在这里提供的价值是：
1. 高速的 `io_uring` 执行框架
2. 统一的系统调用气闸舱拦截（`@sys_net_*` 族）
3. 白嫖 LLVM O3 的优化积累

---

## 四、针对本仓库的具体整合路径

llvm2sa 的最自然落点是作为 `sa_net_uring.zig` 的**输入管道**，而不是替换现有管线：

```
现有管线（保留不动）：
.saasm → Flattener → Referee → emit_llvm → .ll → zig cc → EXE

新增 llvm2sa 管道：
外部 .bc（Rustc/Clang/Zig 编译产物）
    ↓  opt -passes=reg2mem,O3       ← 白嫖 LLVM 优化
    ↓  llc -emit-llvm -filetype=asm → .ll（PHI-free）
    ↓  [src/llvm2sa.zig]            ← 新增，~800-1200 行 Zig
    ↓  .saasm（全 Untracked 模式）
    ↓  Flattener → Referee（气闸舱校验 @sys_net_* 调用）
    ↓  emit_llvm → zig cc
    ↓  sa_net_uring runtime（网络引擎）
```

### 工程规模估计

| 组件 | 行数 | 说明 |
|---|---|---|
| `src/llvm2sa.zig`（文本 .ll 解析 + 逆向翻译） | ~800–1200 | 核心模块 |
| `src/phi_elim.zig`（Phi 消除，可选） | ~200–400 | 前期可用 `opt` 代劳 |
| CLI 扩展 `saasm llvm2sa <file.ll>` | ~50 | 接入现有 `src/cli.zig` |
| 黄金文件测试套件 | ~200 | roundtrip 验证 |
| **合计** | **~1250–1850** | 比 SAX Phase 1 略小或相当 |

---

## 五、和现有 todo.md 的优先级比较

```
P0（已规划，技术底座，不能绕过）：
└── src/runtime/sa_net_uring.zig 网络引擎（~2500-3500 行 Zig）
    └── 这才是"吊打 Bun"的物理地基

P1（有规划，生态必要）：
├── SAX Phase 1 MVP（~1500-2000 行）
├── sa_std 剩余模块（buf_reader / math / env）
└── 零信任包管理 v0.5（task 35 族）

P2（llvm2sa 的正确位置）：
└── llvm2sa（~1250-1850 行）
    ├── 前提：sa_net_uring 已完成并稳定
    └── 价值：把 Rust/C/Zig 写的业务逻辑注入 io_uring 极速基座
```

**llvm2sa 不是现在，是"网络引擎上线后的下一步"。**

---

## 六、可立即开始的 PoC 切入点

不用等到完整实现，可以先做一个**反向验证实验**（~100–200 行 Zig）：

```bash
# 取本仓库已有的 .ll 文件（.probe_wasm2/hello.wasm.saasm.ll）
# 手工反向翻译一次，验证对称性

# 目标：把 hello.wasm.saasm.ll 还原成 hello_roundtrip.saasm
# 再跑 saasm run hello_roundtrip.saasm，输出应与原版一致
```

**为什么这个 PoC 几乎没有障碍**：本仓库自产的 `.ll` 是 PHI-free 的 mem-slot 形式、全字节偏移 GEP、无复杂结构体类型——正是 `emit_llvm.zig` 设计的输出形态。翻译层的忠实度可以在 PoC 阶段快速验证。

PoC 需要实现的最小翻译集：

| 需处理的 LLVM IR 模式 | 对应 SA-ASM |
|---|---|
| `define ... @name(...)` | `@name(...):` |
| `declare ... @extern(...)` | `@extern name(...)` |
| `call ptr @malloc(...)` | `t = alloc n` |
| `getelementptr i8, ptr %p, i64 N` + `load` | `t = load p+N as T` |
| `store T %v, ptr %gep` | `store p+N, v as T` |
| `%t = add/sub/mul/... T %a, %b` | `t = op a, b` |
| `%t = icmp eq/ne/slt/... T %a, %b` | `t = eq/ne/slt/... a, b` |
| `br i1 %c, label %L1, label %L2` | `br c -> L1, L2` |
| `L_NAME:` | `L_NAME:` |
| `ret T %v` / `ret void` | `return v` / `return` |

---

## 七、架构师总结

| 维度 | 评分 | 说明 |
|---|---|---|
| 技术可行性 | ⭐⭐⭐⭐⭐ | LLVM IR 与 SA-ASM 天然同构（SSA + 寄存器机），PHI 有成熟消除路径 |
| 工程工作量 | ⭐⭐⭐⭐ | ~1250–1850 行，约 3–5 周全职开发 |
| 生态价值 | ⭐⭐⭐⭐⭐ | 接入 Clang/Rustc/Zig 全生态，语言霸权 |
| 所有权安全性 | ⭐⭐ | 上游语言保证，SA 层退化为 Untracked 执行模式 |
| 当前优先级 | ⭐⭐ | 网络引擎先行，llvm2sa 是"第二阶段武器" |

**一句话**：llvm2sa 放弃了在 SA 层面的极致所有权证明（交由前端语言保证），换来的是无敌的生态兼容性和直插硬件的运行速度。本仓库的 `emit_llvm.zig` 已经是一份完整的翻译词典——先建 `sa_net_uring` 基座，再焊 llvm2sa 管道，这是最优的工程序列。

---
---

## 附录：llvm2sa 生态同化与进阶架构推演
> 本节由后续架构研讨追加，对 `llvm2sa` 的生态白嫖战略、与 FFI 的本质区别以及首批实验标靶进行了深度展开。

### 附录 A：为什么是 llvm2sa 而不是 FFI？（降维打击的四个维度）

SA-ASM 已有 `@ffi_wrapper` 和 `@extern`，为什么还需要 `llvm2sa`？这本质上是**“打电话（FFI）”与“全资收购并入大平层（llvm2sa）”**的区别。

1. **全局极限内联 (Global Inlining)**：FFI 必须跨越 C ABI（保存寄存器/压栈），阻断了流水线。而 `llvm2sa` 将 C/Rust 翻译为 `.saasm` 后，外语代码变成了 SA 的“一等公民”，SA 优化器能实现跨语言内联，彻底消除调用开销。
2. **白盒透明审计**：引入第三方 `libfoo.so` 是盲盒，极度危险。`llvm2sa` 会将外部依赖碾碎为透明的 `.saasm` 汇编，必须接受 SA Flattener/Verifier 的审查，从根源上防御恶意投毒。
3. **消除平台碎片化**：脱离了 `.so`/`.dll` 的羁绊。C/Rust 编译出的 LLVM IR 经 `llvm2sa` 转换后，全量变成 SA 纯文本，最终编译出的可执行文件或 WASM 模块是 **100% 毫无外部依赖**的单一实体。
4. **同化为可挂起协程**：被转化为 SA 寄存器机状态的外部代码，可以被 SA 引擎极轻量地快照和挂起（Yield），避免了由于阻塞的 FFI 调用卡死 io_uring 主线程的噩梦。

### 附录 B：生态白嫖战略（Crates.io 的雷区与宝藏）

`llvm2sa` 为 SA-ASM 砸开了 crates.io 的大门，但必须认清物理边界：

1. **绝对的宝藏：`#![no_std]` 生态**
   完全不依赖操作系统的纯计算库，可 100% 完美白嫖。
   - 密码学：`ring`, `sha1_smol` (极速处理 WebSocket 握手)。
   - 序列化：`serde-json-core`。
   - 协议拆包：`httparse` (极速零分配 HTTP 头解析)。
2. **需修桥的半成品：`alloc` 生态**
   LLVM IR 中的 `__rust_alloc` 等外部调用，可以在 SA 端硬连线（Hardwire）映射到 `sa_std/alloc` 的底层分配器上。
3. **狸猫换太子的伪装术：强吃 `std`**
   直接引入依赖 `std::fs` / `std::net` 的库会因找不到 `libc` 崩溃。终极解法是：**手写一个伪装的 `sa-std-rs` 库**，对外暴露相同的 API，但在其内部，将 `TcpStream::write` 强行路由、调用 SA 的 `sys_net_push_outbound` 气闸舱。
   - **结果**：第三方库以为自己在调用操作系统的阻塞 API，实际上数据被零拷贝地砸进了 SA 的无锁三环 io_uring 引擎！

### 附录 C：四大标靶（llvm2sa 落成后的实验序列）

当 `llvm2sa` 管道建好，验证其战力的最佳标靶（必须是计算密集且状态机复杂）：

1. **极速协议解析器 (`httparse`)**：验证控制流打平与极速循环性能，实现零分配切片。
2. **密码学与哈希引擎 (`sha1_smol` + `base64`)**：验证密集位运算（Bitwise）与算术指令翻译的正确性。
3. **高性能序列化 (`serde-json-core`)**：用 SA-ASM 跑通庞大的 Serde 状态机，验证翻译器的工业级鲁棒性。
4. **极简内存 B+ 树 / 基数树 (Radix Tree)**：作为纯计算核心算子放入执行环，完成 SA-ASM 作为极速内存数据库的终极拼图。