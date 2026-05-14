# 237 - Mod Inline Submodule

## 目标特性 (Target Feature)
展示用 `submodule/index.saasm` 和更深的普通文件来模拟 inline submodule。

## 文件结构
- `submodule/index.saasm` 是对外层。
- `submodule/inline/index.saasm` 再转入更深实现。
- `submodule/inline/deep/seed.saasm` 是最底层数据源。

## 结果
- 编译通过，输出 `237`.
