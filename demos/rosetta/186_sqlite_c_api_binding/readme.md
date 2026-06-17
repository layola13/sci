# 186 - SQLite C API Binding

## 目标特性 (Target Feature)
展示 C layout 结构体、语句句柄和 host 调用返回码如何在一条 FFI 链路里串起来。

## 当前示例 (Current Demo Shape)
1. `Row` 结构显式保存 `id`、`count` 和 `total`，当前示例要求把 `7 + 1` 计算成 `8`。
2. SA 版本把 prepare / step / finalize 三个 SQLite 风格入口都展开成独立 extern，并在 wrapper 内集中检查返回值。
3. 这个 demo 关注的是“结构体指针往返 + 语句生命周期”，不是 SQL 解析能力。

