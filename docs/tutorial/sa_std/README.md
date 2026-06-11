# SA 标准库 (sa_std) 全景指南

在编写实际的 SA (Safe Assembly) 应用程序时，`sa_std` 提供了开箱即用的标准能力。与传统高级语言不同，SA 的标准库以宏 (Macro) 和底层 ABI 函数为主要暴露形式。

这篇指南将分类梳理 `sa_std` 中的核心模块、常见用法以及最佳实践。由于 SA 在近期版本对底层进行了深度的内存越界、溢出保护以及原子化并发优化，使用标准库（尤其是安全的宏封装）将比你直接书写裸汇编要安全得多。

## 目录
1. [基础核心类型 (Core/Primitives)](01_core_primitives.md)
2. [动态容器 (Collections)](02_collections.md)
3. [并发与同步 (Sync & Concurrency)](03_sync_concurrency.md)
4. [IO 与网络 (I/O & Network)](04_io_network.md)
5. [安全算术运算 (Checked Arithmetic)](05_checked_arithmetic.md)

---

这只是 `sa_std` 的冰山一角，更多像 `std_ffi_cstr`、`std_time` 等高级宏同样存在于对应的文件中。深入阅读对应的 `.sa` 文件，是进阶 SA 大师之路的必经途径！
