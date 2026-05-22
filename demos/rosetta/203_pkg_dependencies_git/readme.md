# 203 - Package Dependencies Git

## 目标特性
展示 git 源依赖如何被锁定到一个 vendored checkout。

## 文件树
- `main.sa`: compiler input entrypoint.
- `src/lib.sa`: compiler input library module.
- `vendor/git_dep.sa`: compiler input vendored git dependency.
- `sa.pkg`: future metadata only.
- `main.rs`: legacy reference only.

## 说明
`src/lib.sa` 只从 `vendor/git_dep.sa` 取值，模拟“先从 git 拉下来，再在本地 checkout 中编译”的流程。`sa.pkg` 里的 git 字段只是未来元数据形状，不是当前编译器输入。
