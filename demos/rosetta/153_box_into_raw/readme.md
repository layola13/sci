# 153 - Box::into_raw

## 目标特性 (Target Feature)
展示剥夺编译器对 Box 的内存释放追踪（转换为 Untracked）。

## 降级逻辑预演 (Expected Lowering Logic)
1. **显式所有权**：`Box`、arena、slab、aligned alloc 和手动布局结构都必须回到 `alloc` / `stack_alloc` / `!` / `^` 这些原语，不能靠 GC 或隐式析构补位。
2. **裸指针转移**：`Box::into_raw` / `Box::from_raw` 只是在改变所有权归属，前端必须把“谁负责释放”写清楚；错误地丢掉 release 路径就是泄漏。
3. **受控遗留**：`mem::forget` / `ManuallyDrop` 允许故意不释放，但这应当是被设计出来的例外，不是默认控制流；一旦跨到不该活着的路径上，Referee 仍然按活跃资源检查。
