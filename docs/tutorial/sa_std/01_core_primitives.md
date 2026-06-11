# 1. 基础核心类型 (Core/Primitives)

SA 线性所有权系统的基石。它们提供堆分配的数据包裹、共享指针与内部可变性。

## `Arc` (线程安全的原子引用计数)
`Arc` (Atomic Reference Counting) 提供了针对单实例的线程安全多重持有能力。内部已经对强/弱引用绕回溢出进行了 `panic(1501)` 等严格的安全防护。

```sa
@import "sa_std/core/arc.sa"

@main() -> i32:
L_ENTRY:
    // 创建一个新的 Arc 智能指针封装数字 42
    EXPAND ARC_NEW arc_ptr, 42
    
    // 增加引用计数 (克隆)
    EXPAND ARC_CLONE arc_ptr

    // 获取内部数值
    EXPAND ARC_GET val, arc_ptr
    !val

    // 递减强引用计数，如果计数降为 0 将释放资源 (宏会自动处理)
    EXPAND ARC_DECREMENT_STRONG_COUNT arc_ptr
    EXPAND ARC_DECREMENT_STRONG_COUNT arc_ptr
    return 0
```

## `RefCell` (内部可变性)
用于单线程环境下的借用检查。若被并发修改，请改用 `RwLock` 或 `Mutex`。

```sa
@import "sa_std/core/refcell.sa"

@main() -> i32:
L_ENTRY:
    EXPAND REFCELL_NEW cell, 100

    // 不可变借用
    EXPAND REFCELL_BORROW ok, b_guard, cell, L_ERR
    !b_guard
    !ok
    
    !cell
    return 0
    
L_ERR:
    !cell
    return 1
```