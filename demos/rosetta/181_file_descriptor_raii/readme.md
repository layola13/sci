# 181 - File Descriptor RAII

## 目标特性 (Target Feature)
展示把文件描述符包装成显式 handle，并按 `open -> read -> close` 顺序完成回收。

## 当前示例 (Current Demo Shape)
1. `main.rs` 和 `main.sa` 都围绕 `/dev/null` 的 host 句柄展开，目录重点是 fd 生命周期，而不是 `std::fs::File` 的高级接口。
2. SA 版本把 `fd_open`、`fd_read`、`fd_close` 明确建模为 extern 调用，并在成功路径上输出 `3`。
3. `Handle` 结构里保留了 fd 与状态槽位，说明这个题目关注“资源所有权外显”。

