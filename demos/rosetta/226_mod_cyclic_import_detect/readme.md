# 226 - Mod Cyclic Import Detect

## 目标特性 (Target Feature)
展示一个跨 `cycle/core/a -> cycle/core/b -> cycle/core/a` 的导入环。

## 文件结构
- `main.saasm` 只导入 `cycle/index.saasm`。
- `cycle/index.saasm` 下沉到 `cycle/core/index.saasm`。
- `cycle/core/index.saasm` 进入 `cycle/core/a.saasm`。
- `cycle/core/a.saasm` 和 `cycle/core/b.saasm` 互相导入，形成环。
- `cycle/core/a/detail/seed.saasm` 与 `cycle/core/b/detail/seed.saasm` 提供各自的支撑数据。

## 结果
- 编译意图失败，导入环会被拦截。
