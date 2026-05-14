# 106 - Cell (Interior Mutability)

## 目标特性 (Target Feature)
展示 Rust 的 `Cell<T>` 内部可变性模型（针对 `Copy` 类型）。

## 降级逻辑预演 (Expected Lowering Logic)
1. **绕过静态检查**：在 SA-ASM 中，如果我们只有一个对结构体的不可变借用（`&` 也就是 `Locked_Read`），我们是无法使用 `store` 写入的（会报 `ReadWriteConflict`）。
2. **Unsafe 降级**：前端在处理 `Cell::set` 时，必须使用 FFI 气闸舱（`@ffi_wrapper`），利用 `raw_cast` 将不可变借用转化为裸指针，然后再通过指针算术和 `store` 强制写入。这体现了 SA-ASM 对内部可变性的零容忍态度：一切内部可变性必须隔离在气闸舱中！