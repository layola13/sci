# matmul 根因修正（实验验证推翻上轮判断）

日期：2026-11-18

## 一、上轮判断（错误）

上轮我判断：matmul 慢是 SLA 的 `fadd acc, 0.0` 冗余复制破坏了 LLVM 浮点 reduction 向量化。

**实验推翻了这个判断。**

## 二、对照实验（实际跑测试）

用 `/tmp/mm.sa.bc`（SLA 编译 matmul 生成的 LLVM bitcode）做三组对照，用 `clang/llvm-as -O3` + sa_std 链接，实测运行时间（5次中位数）：

| 版本 | +0.0 冗余 | fast-math | 运行时间 | 向量化 |
|---|---|---|---:|---|
| base（原样） | 有 | 无 | **903 ms** | ❌ 无 |
| nofix（删掉+0.0） | 无 | 无 | **891 ms** | ❌ 无 |
| fast（加 fast 标记） | 有 | 有 | **298 ms** | ✅ `<2 x double>` |

### 实验方法
1. `llvm-dis /tmp/mm.sa.bc` → IR
2. nofix：正则删除 3 处 `= fadd double X, 0.0` 定义行，替换所有引用为 X
3. fast：正则把 `fmul/fadd double` → `fmul/fadd fast double`
4. `llvm-as` → bc → `zig cc -O3 ... -licuuc -licudata` → exe
5. 运行测时间 + `opt -O3` 后检查向量化 opcode

### IR 证据
- base 优化后：`fmul double`（标量），无向量指令
- nofix 优化后：`fmul double`（标量），无向量指令 → **删 +0.0 无收益**
- fast 优化后：
  ```
  %14 = fadd fast <2 x double> %wide.load, %vec.phi
  %bin.rdx = fadd fast <2 x double>
  %17 = call @llvm.vector.reduce.fadd.v2f64(...)
  ```
  SIMD 向量化 + 水平归约 → 3× 提速

## 三、修正后的真根因

**matmul 慢的真正原因是 LLVM 默认不允许重结合浮点运算（IEEE 语义），所以即使 `acc += a*b` 是单条 fadd，也不能向量化浮点归约循环。Rust 能向量化是因为 rustc 给浮点运算加了 `fast`/`reassoc` 标记（或通过 `-C target-cpu` 等启用）。**

- `+0.0` 冗余（SLA 所有权复制）确实存在，但**不是性能瓶颈**——LLVM 能轻易 fold 掉它（nofix 只快 12ms，噪声级）
- 真正的开关是 **fast-math 标记**：加了就向量化，3× 提速

## 四、为什么 Rust 快 19ms 而我们 298ms（修正后）

用 fast-math 后我们 298ms，Rust 19ms——仍有 15× 差距。剩余差距可能来自：
- Rust 用 AVX `<4 x double>` 或 FMA，我们只有 SSE `<2 x double>`（target-cpu 未设 native）
- Rust 的循环优化/展开更激进
- 我们的内存访问模式（ptr_add + getelementptr 链）可能阻碍更宽的向量化

但 fast-math 证明：**最大的一块（3×）是可以通过标记拿回来的**。

## 五、修复方向（修正后）

1. **给 LLVM emitter 的 fadd/fmul 加 `fast` 标记**（最高 ROI）：在 `emit_llvm_llvmc_shim.c` 的浮点 op 发射处，对 `LLVMBuildFAdd`/`LLVMBuildFMul` 的结果调用 `LLVMSetFastMath` 加 `LLVM_FAST_MATH_FLAG_FAST`。实测可拿回 3×。
   - 风险：改变浮点语义（重结合/NaN/Inf 行为），需评估是否可接受（科学计算可能不行，但基准/游戏通常接受）
2. 设 `-C target-cpu=native` 等价物，让 LLVM 用 AVX `<4 x double>`（再快一截）
3. +0.0 冗余可顺手清（虽然收益小，但减少 IR 噪音）

## 六、诚实结论

上轮根因判断错误，实验纠正：**不是 +0.0 破坏向量化，是缺少 fast-math 标记导致 LLVM 不敢向量化浮点归约**。这是一个明确、可控、高 ROI 的修复点（几行 emitter 代码 + 3× 提速），比之前研究的所有 link/前端优化都更有价值。

## 七、状态

实验产物在 /tmp/{base,nofix2,fast}.exe 和对应 .ll/.bc。本仓库代码未改动，仅验证。
