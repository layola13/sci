# 109 - Atomic Fetch Add

## 目标特性 (Target Feature)
展示 Rust 的 `AtomicI32::fetch_add` 如何完美映射到底层。

## 降级逻辑预演 (Expected Lowering Logic)
1. **原子 RMW**：无需通过循环 CAS，直接映射为 SA-ASM 提供的 `atomic_rmw_add` 指令。
2. **安全隔离**：如果被操作的寄存器带有 `Immutable` (`@const`) 掩码，SA 编译器会在静态阶段直接抛出 `ConstMutation` 拦截写入操作。原子数据必须是动态分配或受控的堆/栈内存。