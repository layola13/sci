# 202 - Package Dependencies Local

## 目标特性
展示同一 checkout 内的本地路径依赖如何挂到 `pkg/` 目录下。

## 文件树
- `main.sa`: compiler input entrypoint.
- `src/lib.sa`: compiler input library module.
- `pkg/local_dep.sa`: compiler input local dependency module.
- `sa.pkg`: future metadata only.
- `main.rs`: legacy reference only.

## 说明
`main.sa` 进入 `src/lib.sa`，`src/lib.sa` 再导入 `pkg/local_dep.sa`。这条链路只使用当前支持的 SA-ASM 语法；`sa.pkg` 只是把 path dependency 的未来文件形状摆出来。
