# 184 - Pthread Spawn / Join

## 目标特性 (Target Feature)
展示线程句柄、工作参数和 join 结果如何通过显式线程槽位贯通。

## 当前示例 (Current Demo Shape)
1. `Thread` 结构同时保存 `handle` 和 `value`，worker 从槽位读取 `value`，再把结果写回去。
2. 成功路径是“初始值 1，经 worker 加 4 后变成 5，join 返回 0”，最后输出 `5`。
3. SA 版本把 `pthread_spawn`、`pthread_join`、`pthread_drop` 都写成独立 host ABI 调用，强调生命周期收口。

