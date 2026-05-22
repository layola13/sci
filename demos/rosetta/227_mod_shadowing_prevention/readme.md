# 227 - Mod Shadowing Prevention

## 目标特性 (Target Feature)
展示 `shadow/registry` 汇总 `shadow/left` 和 `shadow/right` 两个分支时的同名 `#def` 冲突。

## 文件结构
- `main.sa` 只导入 `shadow/registry/index.sa`。
- `shadow/registry/index.sa` 汇总左右两侧模块。
- `shadow/left/index.sa` 与 `shadow/right/index.sa` 分别导入各自的 `layout.sal`。
- `shadow/left/detail/seed.sa` 与 `shadow/right/detail/seed.sa` 作为各自分支的支撑文件。
- `shadow/left/layout.sal` 和 `shadow/right/layout.sal` 都声明了 `SHADOW_SIZE`，因此 flatten 时会冲突。

## 结果
- 编译意图失败，重复 `#def` 会被拦截。
