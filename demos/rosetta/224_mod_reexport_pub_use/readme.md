# 224 - Mod Reexport Pub Use

## 目标特性 (Target Feature)
展示由 `bridge/index.saasm` 向更深层实现文件转发的包装方式。

## 文件结构
- `bridge/index.saasm` 作为转发层。
- `bridge/deep/value.saasm` 保存实际实现。
- `bridge/deep/seed.saasm` 负责最底层常量。

## 结果
- 编译通过，输出 `224`.
