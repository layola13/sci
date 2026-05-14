# 223 - Mod Visibility Private

## 目标特性 (Target Feature)
展示 `public/` 与 `internal/` 分层后的公开包装和私有实现。

## 文件结构
- `public/index.saasm` 是唯一对外入口。
- `internal/bridge.saasm` 只在包装层内部被导入。
- `internal/detail/seed.saasm` 保存最底层实现。

## 结果
- 编译通过，输出 `223`.
