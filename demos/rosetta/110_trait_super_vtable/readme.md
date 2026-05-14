# 110 - Trait Super Traits VTable

## 目标特性 (Target Feature)
展示 Rust 中的 Super Trait（如 `trait B: A`）的虚表是如何排布的。

## 降级逻辑预演 (Expected Lowering Logic)
1. **虚表与向上转型**：`dyn Trait`、super trait 和 upcasting 在 SA 侧都落实为 `@const` 里的函数指针数组，再配合 `call_indirect` 取槽调用；如果虚表排布变了，前端必须同步调整偏移。
2. **ABI 边界**：`extern "C"`、回调、`*const T`、`va_list`、union FFI 类型都要通过 `@extern` / `@export` / `@ffi_wrapper` 展开成显式 `ptr` 传递；跨气闸边界的裸指针必须按 `IllegalUnsafeContext` / `InteriorPtrEscape` 规则处理。
3. **布局外显**：不透明指针、原始指针运算和变参访问都依赖 `#def` 偏移字典，前端负责把高层类型压成固定内存形状，SA 不替它推导。
