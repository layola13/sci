# 228 - Mod Iface Separation

## 目标特性 (Target Feature)
展示 `api/`, `layout/`, `impl/` 三层拆分后的接口与实现分离。

## 文件结构
- `api/contract.sai` 暴露 ABI。
- `layout/contract.sal` 固定记录大小和偏移。
- `impl/contract.sa` 提供真正的读取实现。

## 结果
- 编译通过，输出 `228`.
