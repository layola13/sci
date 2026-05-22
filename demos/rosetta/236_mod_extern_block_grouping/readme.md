# 236 - Mod Extern Block Grouping

## 目标特性 (Target Feature)
展示把外部声明集中在 `ffi/group/index.sai` 的做法。

## 文件结构
- `ffi/group/index.sai` 集中列出外部入口。
- `ffi/group/layout.sal` 固定共享记录布局。
- `ffi/group/bridge.sa` 提供实现，`ffi/group/core/seed.sa` 提供最底层辅助值。

## 结果
- 编译通过，输出 `236`.
