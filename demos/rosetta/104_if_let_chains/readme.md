# 104 - If Let Chains

## 目标特性 (Target Feature)
展示 Rust 的 `if let Some(x) = opt && let Some(y) = opt2` 链式模式匹配。

## 降级逻辑预演 (Expected Lowering Logic)
1. **短路求值**：复杂的链式匹配被前端转换为级联的 `br` 指令（类似于 AST 的降维展开）。
2. **所有权穿透**：如果匹配失败，由于是短路求值，中途被分配的临时变量必须在每一个 `L_FAIL` 块里得到正确的清理。SA-ASM 要求所有汇聚到结束块的执行流必须携带完全一致的活动寄存器掩码。