# 502 - Bare Cross-Dir Import Reject

## 目标特性 (Target Feature)
展示嵌套文件使用裸跨目录路径导入同级目录时的拒绝行为。

## 文件结构
- `main.sa` 只导入 `east/alpha.sa`。
- `east/alpha.sa` 以裸路径 `west/beta.sa` 导入同级目录（缺少 `east/../` 锚定）。
- `west/beta.sa` 提供被引用的符号。

## 结果
- 编译意图失败，导入解析会被拦截（所有后端一致，见 488 的可用写法）。
