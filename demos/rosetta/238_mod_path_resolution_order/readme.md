# 238 - Mod Path Resolution Order

## 目标特性 (Target Feature)
展示用 `paths/index.saasm` 显式列出同级模块的优先顺序。

## 文件结构
- `paths/index.saasm` 同时导入 `first/` 与 `second/`。
- `paths/first/index.saasm` 和 `paths/second/index.saasm` 各自有自己的深层 seed。
- `main.saasm` 只看见包装后的单一入口。

## 结果
- 编译通过，输出 `238`.
