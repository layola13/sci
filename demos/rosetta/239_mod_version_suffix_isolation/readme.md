# 239 - Mod Version Suffix Isolation

## 目标特性 (Target Feature)
展示 `v1/` 和 `v2/` 两个版本后缀目录如何隔离各自的布局和辅助函数。

## 文件结构
- `versions/index.saasm` 聚合两个版本目录。
- `versions/v1/` 和 `versions/v2/` 各自带有独立的布局文件。
- `main.saasm` 只依赖 `versions/index.saasm`。

## 结果
- 编译通过，输出 `239`.
