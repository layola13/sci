# 232 - Mod Conditional Import

## 目标特性 (Target Feature)
展示用 `profiles/native` 和 `profiles/portable` 的普通导入来模拟条件选择。

## 文件结构
- `profiles/index.sa` 作为分支选择器。
- `profiles/native/index.sa` 是当前被选中的实现。
- `profiles/portable/index.sa` 保留成明确的另一条分支。

## 结果
- 编译通过，输出 `232`.
