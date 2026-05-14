# 105 - Let Else

## 目标特性 (Target Feature)
展示 Rust 的 `let Some(x) = expr else { return }` 发散匹配（Diverging Match）。

## 降级逻辑预演 (Expected Lowering Logic)
1. **强制终止**：`else` 块必须发散（`return`、`break` 或 `panic`）。
2. **清理责任转移**：在发散块内部，前端必须注入全量的上下文清理指令（`!reg`），否则会被 `EarlyReturnLeak` 机制拦截。SA-ASM 强制要求“无论是正常流还是发散流，内存都要账账相符”。