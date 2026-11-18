# matmul / sort 性能差距根因（反汇编级分析）

日期：2026-11-18

## 一、数据时实（sala 基准，native）

| 程序 | SLA | Rust | 倍数 | 编译 SLA/Rust |
|---|---:|---:|---:|---:|
| matmul（运行） | 678 ms | 19 ms | **Rust 快 35.7×** | 13480/131 ms |
| sort（运行） | 199 ms | 269 ms | **SLA 快 1.35×** | 834/148 ms |

注意：**sort 运行时其实 SLA 更快**；sort 只在编译时间上慢。真正的"惨败"是 matmul（运行 + 编译双输）。

## 二、根因链条（反汇编确证）

### 2.1 SLA lowering 出的 .sa（matmul 内层循环）
```
tmp_64 = fmul tmp_58, tmp_63     # a[k] * b[k]
tmp_65 = fadd acc, tmp_64        # acc + a*b
!acc
tmp_66 = 0.0
acc = fadd tmp_65, tmp_66        # ← 多余！+0.0 复制
```
源文件 `matmul.sla:20` 的 `acc = acc + a * b` 被 lower 成**两条 fadd**。

### 2.2 产生位置：SLA codegen 的仿射所有权复制
`sa_plugin_sla/src/codegen.zig:13554 emitPrimitiveCopy()`：
- SLA 是仿射类型系统，变量重新赋值必须"消费旧寄存器、产生新寄存器"
- 复制方式：整数 `add src, 0`；浮点 `fadd src, 0.0`
- 注释明确：浮点用 fadd 而非 add，是因为 `add src, 0.0` 会被后端当整数 identity 折叠，导致 source/dest 共享寄存器（后续修改互相污染），所以故意用 fadd 产生独立副本

### 2.3 LLVM IR 层（llvm-dis 确证）
matmul 核心 `L_WHILE_BODY_13`：
```llvm
%fop501 = fmul double %load731732, %load495733734
%fop507 = fadd double %4, %fop501
%fop513 = fadd double %fop507, 0.000000e+00    ; 多余的 +0.0
```
- `fmul`/`fadd` 全是**标量**，无 `fast`/`reassoc` 标记
- 循环里有**两条 fadd**（其中一条是 +0.0 冗余），且浮点 reduction 无 fast-math 许可
- LLVM 循环向量化器**无法把它识别成可向量化的 reduction** → 退化为标量逐元素（678ms）

对比 Rust：`acc += a*b` 是单条 fadd，LLVM 能向量化成 `fmul <4x double>` + 水平归约（19ms）。

### 2.4 为什么 sort 反而快
sort 是分支密集的整数堆排序（比较/交换），LLVM 本来就向量化不了。+0 冗余（sort 有 28 条）淹没在分支逻辑里。SLA 反而因为生成代码**省略边界检查**（Rust 的 `v[i as usize]` 有 bounds check，SLA 的 `load` 没有）而快 1.35×。

## 三、根因总结（一句话）

**matmul 慢 = SLA 仿射所有权系统导致的"每次变量重绑定都插入 `fadd x, 0.0` 复制"，破坏了 LLVM 对浮点归约循环的向量化；Rust 无此开销，单条 fadd 被向量化。sort 因是分支密集整数运算，不受影响，且省边界检查反而更快。**

## 四、编译时间 13.5s 的根因（另一回事）

matmul native 冷编译 13480ms vs Rust 131ms：
- IEEE 浮点无 reassoc 标记时，LLVM 对深层嵌套/大常量的优化可能爆炸
- 数组初始化 `[1.5; 4096]` 曾导致 >5min（已通过 `.repeat`+`@memset` 优化降到 4.6s）
- 具体仍剩余 13.5s 的 O3 优化瓶颈，与运行时 35× 是同源（浮点循环 + 冗余指令让优化器工作量激增）

## 五、潜在修复方向（如果要做）

1. **消除 matmul 内层循环的 +0.0 复制**：让 `acc = acc + a*b` 这种"表达式自赋值"走原地更新 lowering，而非"复制+重绑定"。但仿射所有权要求新寄存器，需 Referee 支持"原地消费"模式（已有 `assign` 指令？）。
2. **给浮点 op 加 fast-math 标记**：在 LLVM emitter 里对 fadd/fmul 加 `fast` flag，让 LLVM 敢向量化浮点归约。但会改变浮点语义（舍入顺序），需权衡。
3. **专门识别 `x = fadd x, 0.0` 模式**：在 flattener 或 emitter 层把它优化成 no-op（值传递），减少一条指令。但需证明不破坏所有权（>0.0 复制的独立性保证）。

方向 3 最小侵入、风险最低：**识别 `dst = fadd src, 0.0`（src 即将被 `!` 释放）模式，直接 emit 成寄存器别名**，省掉冗余 fadd。

## 六、结论

matmul 的惨败不是"LLVM 不如 Rust"，而是**SA 的所有权语义在 lowering 时产生了冗余浮点指令，恰好破坏了 LLVM 的浮点循环向量化**。这是一个具体、可定位、理论上可修复的问题——不是架构性死局。sort 的表现说明 SA 的代码生成本身在整数/分支场景是有竞争力的（省边界检查）。

相比之下，前面研究的 link/契约加载/.mi 都是"编译速度"问题；matmul 是"运行时性能"问题，根因清晰得多，ROI 可能更高。
