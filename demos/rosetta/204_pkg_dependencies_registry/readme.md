# 204 - Package Dependencies Registry

## 目标特性
展示 registry 索引命中后如何落到本地的 codec 依赖源码。

## 文件树
- `main.saasm`: compiler input entrypoint.
- `src/lib.saasm`: compiler input library module.
- `registry/codec.saasm`: compiler input registry snapshot.
- `sa.pkg`: future metadata only.
- `main.rs`: legacy reference only.

## 说明
`src/lib.saasm` 只通过 `registry/codec.saasm` 取值，模拟“从 registry 解析到本地缓存源码”的流程。`sa.pkg` 只描述未来的 registry 配置形状，当前编译器不读取它。
