# 235 - Mod Transitive Dependency

## 目标特性 (Target Feature)
展示 `Main -> dep/index -> dep/mid -> dep/leaf` 的依赖传递。

## 文件结构
- `dep/index.saasm` 是新的入口层。
- `dep/mid.saasm` 再向下转发到叶子。
- `dep/leaf.saasm` 保存最终值。

## 结果
- 编译通过，输出 `235`.
