# 131 - Waker VTable Mechanics

## 目标特性 (Target Feature)
展示 RawWakerVTable 的 4 个函数指针布局与动态调用。

## 降级逻辑预演 (Expected Lowering Logic)
1. **poll 驱动**：`RawWakerVTable`、`select!`、`join_all`、`Stream`、executor 队列和 `yield_now` 都要先展开成 poll 循环、状态上下文和 `Pending` / `Ready` 分支。
2. **唤醒表与调度**：waker 只是一组显式函数指针，`call_indirect` 或 host callback 负责驱动任务重新入队；没有“自动恢复”的隐式魔法。
3. **I/O 事件化**：`io_uring`、`epoll` / `kqueue` 这一类 I/O 事件面需要通过 `@extern` / `@ffi_wrapper` 暴露成句柄注册、等待和取回结果的显式步骤。
