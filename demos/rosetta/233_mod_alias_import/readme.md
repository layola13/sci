# 233 - Mod Alias Import

## 目标特性 (Target Feature)
展示用短包装模块模拟别名导入。

## 文件结构
- `alias/index.sa` 提供短名字入口。
- `alias/deep/index.sa` 再转向更深层实现。
- `alias/deep/seed.sa` 保存最终数值。

## 结果
- 编译通过，输出 `233`.
