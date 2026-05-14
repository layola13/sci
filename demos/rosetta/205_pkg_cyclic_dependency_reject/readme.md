# 205 - Package Cyclic Dependency Reject

## 目标特性
展示包解析器如何在 `pkg_a` 和 `pkg_b` 之间拒绝 import cycle。

## 文件树
- `main.saasm`: compiler input root entrypoint.
- `pkg_a/main.saasm`: compiler input side A of the cycle.
- `pkg_b/main.saasm`: compiler input side B of the cycle.
- `sa.pkg`: future metadata only.
- `main.rs`: legacy reference only.

## 说明
`main.saasm -> pkg_a/main.saasm -> pkg_b/main.saasm -> pkg_a/main.saasm` 这个链路是故意写出来的，目的是让编译器在导入解析阶段直接报循环依赖错误，而不是走到代码生成或运行时。
