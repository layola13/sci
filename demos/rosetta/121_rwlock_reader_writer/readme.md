# 121 - RwLock Reader Writer

## 目标特性 (Target Feature)
展示读写锁的状态机降级，包含读计数器和写标志。

## 降级逻辑预演 (Expected Lowering Logic)
1. **状态机同步**：`RwLock`、`Condvar`、`Barrier`、`OnceCell`、`park/unpark` 和类似原语都应该写成显式状态字段、计数器、标志位和分支回环，SA 只看到可追踪的控制流。
2. **原子协调**：`MPMC` 队列、`hazard pointer`、`RCU`、`seqlock` 这类方案靠 `atomic_rmw_*` / `cmpxchg` / version counter / quiescent point 表达，不能依赖隐式调度。
3. **释放时机**：读锁、写锁、等待句柄和延迟回收资源都必须在明确的边界上 `!` 掉；如果前端漏掉清理，Referee 就会按活跃寄存器和锁状态直接报错。
