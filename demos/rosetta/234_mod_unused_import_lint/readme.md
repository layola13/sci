# 234 - Mod Unused Import Lint

## 目标特性 (Target Feature)
展示一个被导入但不被使用的 `lint/unused` 分支。

## 文件结构
- `lint/index.saasm` 导入 `used/` 和 `unused/` 两个分支。
- `lint/used/index.saasm` 提供真正使用的路径。
- `lint/unused/index.saasm` 保留成故意未命中的导入候选。

## 结果
- 编译通过，`unused` 分支目前只是静态保留。
