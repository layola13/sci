# 118 - Global Mutable State

## 目标特性 (Target Feature)
展示 Rust static mut 如何被 SA-ASM 拒绝，并迫使用户改用堆分配+指针传递。

## 降级逻辑预演 (Expected Lowering Logic)
1. **原生逃逸点**：`asm!` 必须落到 native escape block，SA 只记录显式读写的寄存器名和副作用，不允许把隐藏行为混进普通指令流。
2. **全局状态约束**：`static mut` 这类共享写入口不能伪装成普通寄存器，前端要么把它改写为显式状态对象，要么让 Referee 按 `ConstMutation` / 共享写冲突拒绝。
3. **向量与 volatile**：SIMD 用 `v128` / lane 操作表达，volatile 则必须保留“可观察读写”的语义，不能被普通优化折叠成无副作用的 load/store。
