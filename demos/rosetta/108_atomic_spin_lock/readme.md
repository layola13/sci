# 108 - Atomic Spin Lock

## 目标特性 (Target Feature)
展示如何利用 SA-ASM 新增的原子指令实现一个自旋锁（Spin Lock）。

## 降级逻辑预演 (Expected Lowering Logic)
1. **内部可变性**：`Cell<T>` / `RefCell<T>` 都只能在前端展开成显式状态字段、借用计数器或掩码；SA 侧只看见普通内存读写和分支。
2. **受控越权**：`Cell::set` 这类写入若要穿过只读视图，必须被限制在 `@ffi_wrapper` 或等价气闸边界内，再通过 `raw_cast` / `store` 完成；否则应按 `IllegalUnsafeContext` 或 `ReadWriteConflict` 拦截。
3. **原子语义**：自旋锁与 fetch-add 这类原语应分别降级成 `cmpxchg` 循环或 `atomic_rmw_*`，并显式携带 ordering，不能靠普通算术伪装成并发同步。
