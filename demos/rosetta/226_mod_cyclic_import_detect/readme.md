# 226 - Mod Cyclic Import Detect

## 目标特性 (Target Feature)
展示一个跨 `cycle/core/a -> cycle/core/b -> cycle/core/a` 的导入环。

## 文件结构
- `main.sa` 只导入 `cycle/index.sa`。
- `cycle/index.sa` 下沉到 `cycle/core/index.sa`。
- `cycle/core/index.sa` 进入 `cycle/core/a.sa`。
- `cycle/core/a.sa` 和 `cycle/core/b.sa` 互相导入，形成环。
- `cycle/core/a/detail/seed.sa` 与 `cycle/core/b/detail/seed.sa` 提供各自的支撑数据。

## 结果
- 编译意图失败，导入环会被拦截。
