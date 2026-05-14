# 227 - Mod Shadowing Prevention

## 目标特性 (Target Feature)
展示 `shadow/registry` 汇总 `shadow/left` 和 `shadow/right` 两个分支时的同名 `#def` 冲突。

## 文件结构
- `main.saasm` 只导入 `shadow/registry/index.saasm`。
- `shadow/registry/index.saasm` 汇总左右两侧模块。
- `shadow/left/index.saasm` 与 `shadow/right/index.saasm` 分别导入各自的 `layout.saasm-layout`。
- `shadow/left/detail/seed.saasm` 与 `shadow/right/detail/seed.saasm` 作为各自分支的支撑文件。
- `shadow/left/layout.saasm-layout` 和 `shadow/right/layout.saasm-layout` 都声明了 `SHADOW_SIZE`，因此 flatten 时会冲突。

## 结果
- 编译意图失败，重复 `#def` 会被拦截。
