# 230 - Mod Std Prelude

## 目标特性 (Target Feature)
展示本地 `prelude/` 目录如何模拟预导入模块。

## 文件结构
- `prelude/index.sa` 聚合 `index.sai`、`index.sal` 和 `core/seed.sa`。
- `prelude/core/seed.sa` 保存基础值。
- `main.sa` 只导入预导入入口。

## 结果
- 编译通过，输出 `230`.
