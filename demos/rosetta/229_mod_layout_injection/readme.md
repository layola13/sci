# 229 - Mod Layout Injection

## 目标特性 (Target Feature)
展示布局常量如何进入 `alloc`、`store`、`load` 和 `@ffi_wrapper`。

## 文件结构
- `layout/record.saasm-layout` 定义 `Record_SIZE` 和字段偏移。
- `api/record.saasm-iface` 声明 FFI 边界。
- `bridge/record.saasm` 在 `@ffi_wrapper` 中读取布局字段。

## 结果
- 编译通过，输出 `229`.
