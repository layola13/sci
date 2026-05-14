# 222 - Mod Absolute Import

## 目标特性 (Target Feature)
展示把“绝对路径导入”落到明确的 `shared/` 树上。

## 文件结构
- `main.saasm` 从 `shared/root/index.saasm` 进入。
- `shared/root/index.saasm` 再向下导入 `shared/root/codec/index.saasm`。
- `shared/root/codec/index.saasm` 最终落到 `leaf.saasm`。

## 结果
- 编译通过，输出 `222`.
