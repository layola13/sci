# 105 - Let Else

## 目标特性 (Target Feature)
展示 Rust 的 `let Some(x) = expr else { return }` 发散匹配（Diverging Match）。

## 降级逻辑预演 (Expected Lowering Logic)
1. **显式控制流**：前端把 `Drop`、`break 'outer`、`if let` 链和 `let else` 全部展开成显式的 `call`、`br`、`jmp` 与失败块，不允许把隐式语义留给 SA。
2. **逐层清理**：任何提前退出、匹配失败或外层跳转前，都必须先释放当前作用域里仍然活跃的寄存器；否则按 `EarlyReturnLeak` / `MemoryLeak` / `PhiStateConflict` 处理。
3. **作用域对齐**：嵌套块的退出顺序必须和资源生命周期一致，先清理内层临时值，再把控制流送到外层出口。
