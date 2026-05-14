# 107 - RefCell (Dynamic Borrowing)

## 目标特性 (Target Feature)
展示 Rust 的 `RefCell<T>` 动态借用检查机制。

## 降级逻辑预演 (Expected Lowering Logic)
1. **运行时锁**：`RefCell` 除了数据本身，还包含一个 `borrow_count` 和 `borrow_mut_count` 字段。
2. **分支判断**：调用 `borrow_mut()` 时，前端降级出的 SA-ASM 代码必须显式 `load` 这两个计数器。如果计数器 > 0，必须执行 `br` 跳转到 Panic 块（调用 `panic_msg`）。
3. **物理借用分离**：与编译器 `table.zig` 提供的编译期 O(1) 掩码不同，这是存活在堆栈数据段的动态计数器，SA-ASM 本身不提供这层语法糖，完全依赖前端的翻译忠实度。