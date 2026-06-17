# 192 - Proc Macro Derive

## 目标特性 (Target Feature)
展示 derive 类前端生成逻辑被摊平成字段级复制后是什么形状。

## 当前示例 (Current Demo Shape)
1. 当前 SA 版本不是抽象 trait 调用，而是把 `Triple` 的三个字段逐个 load/store 到副本。
2. 成功条件同时检查 `copied_left == 1`、`copied_mid == 2`、`copied_right == 3` 和总和 `6`。
3. 这个目录关注的是“derive 产物长什么样”，不是 proc macro 动态加载机制本身。

