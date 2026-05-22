# 237 - Mod Inline Submodule

## 目标特性 (Target Feature)
展示用 `submodule/index.sa` 和更深的普通文件来模拟 inline submodule。

## 文件结构
- `submodule/index.sa` 是对外层。
- `submodule/inline/index.sa` 再转入更深实现。
- `submodule/inline/deep/seed.sa` 是最底层数据源。

## 结果
- 编译通过，输出 `237`.
