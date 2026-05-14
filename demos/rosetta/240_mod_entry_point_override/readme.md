# 240 - Mod Entry Point Override

## 目标特性 (Target Feature)
展示 `entry/index.saasm` 如何把默认入口转发到覆盖入口。

## 文件结构
- `entry/index.saasm` 选择覆盖入口。
- `entry/default/` 保留默认分支。
- `entry/override/` 提供真正被调用的分支。

## 结果
- 编译通过，输出 `240`.
