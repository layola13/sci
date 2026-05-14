# 181 - File Descriptor RAII

## 目标特性 (Target Feature)
展示 POSIX fd 作为所有权资源的封装。

## 降级逻辑预演 (Expected Lowering Logic)
1. **资源句柄化**：文件描述符、线程句柄、动态库句柄、mmap 区域和数据库连接都应被看成显式 owned handle，生命周期由 `close` / `join` / `unmap` / `free` 控制。
2. **宿主边界**：`signal`、`pthread`、`dlopen`、SQLite、OpenGL 这类系统或 FFI 入口必须通过 `@extern` / `@ffi_wrapper` 写清楚参数、返回值和所有权，SA 不替宿主猜 ABI。
3. **解析与编码**：WebSocket、Protobuf 和 Base64 这类缓冲区算法，本质上是循环、位运算和表驱动；如果要用 `v128` 加速，也必须先把数据路径和尾处理写明白。
