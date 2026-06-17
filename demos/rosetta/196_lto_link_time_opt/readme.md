# 196 - LTO Link Time Optimization

## 目标特性 (Target Feature)
展示多个小函数之间的调用图如何形成典型的 LTO 内联候选。

## 当前示例 (Current Demo Shape)
1. SA 版本保留了 `leaf`、`inner`、`cold_path` 三层函数，但把热路径和冷路径都展开成了固定总和。
2. 当前成功值是 `37`，说明 `inner` 和 `cold_path` 都带着额外叶子调用参与总计。
3. 这个目录关注的是“可内联的调用形状”，不是在源码层伪造优化开关。

