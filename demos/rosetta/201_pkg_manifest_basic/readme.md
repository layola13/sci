# 201 - Package Manifest Basic

## 目标特性
展示一个最小的 package 目录如何拆成入口、包级 manifest、以及 src 内部辅助模块。

## 文件树
- `main.saasm`: compiler input entrypoint.
- `src/entry.saasm`: compiler input entry helper.
- `src/meta.saasm`: compiler input metadata helper.
- `pkg/manifest.saasm`: compiler input package manifest helper.
- `sa.pkg`: future metadata only, not parsed by the current compiler.
- `main.rs`: legacy reference translation only.

## 说明
`main.saasm` 直接进入 `src/entry.saasm`，`src/entry.saasm` 再走到 `pkg/manifest.saasm`，最后由 `pkg/manifest.saasm` 读取 `src/meta.saasm`。这条链路只使用当前已经支持的 SA-ASM 语法。
