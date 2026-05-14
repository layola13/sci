# 103 - Labeled Break

## 目标特性 (Target Feature)
展示 Rust 的嵌套循环以及带标签的 `break 'outer`（直接跳出外层循环）机制。

## 降级逻辑预演 (Expected Lowering Logic)
1. **完全展平**：所有的 `for` / `while` 嵌套都被展平为全局唯一的 `L_XXX:` 标签。
2. **Phi 状态对齐**：`break 'outer` 在 SA-ASM 中就是一个跨越基本块的 `jmp`。为了不触发 `PhiStateConflict` 或 `MemoryLeak`，前端在发射这个长跳转之前，必须逐层清理掉所有内部循环所分配的中间变量（`!reg`），并使寄存器状态完全对齐外部循环出口处的预期状态。