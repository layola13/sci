# 05. 堆与栈：动态内存管理

在 SA 中，内存管理是显式的。你需要清楚地知道每一块内存是分配在**栈 (Stack)** 上还是**堆 (Heap)** 上。

## 1. 栈分配 (`stack_alloc`)
栈分配用于函数内部的临时存储。它的速度极快，且在函数返回时自动回收（由编译器插入回收逻辑）。

```sa
@example() -> void:
L_ENTRY:
    // 在栈上分配 16 字节
    buf = stack_alloc 16
    store buf+0, 42 as i64
    !buf
    return
```

## 2. 堆分配 (`alloc`)
当你需要跨函数传递大型数据或动态大小的数据时，使用 `alloc` 指令。这会调用运行时环境的 `malloc` 实现。

```sa
@main() -> i32:
L_ENTRY:
    // 在堆上分配 1024 字节
    p = alloc 1024
    // 使用 p...
    !p  // 这里的 !p 会调用底层 free()
    return 0
```

## 3. 数据布局与 `#def`
SA 不支持 `struct` 关键字，而是使用**偏移量 (Offset)** 来模拟结构体。为了代码可读性，我们强烈建议使用 `#def` 定义布局。

### 定义一个 Person 结构
```sa
#def Person_SIZE = 16
#def Person_age  = +0   // i32
#def Person_id   = +8   // u64

@init_person(ptr: ptr) -> void:
L_ENTRY:
    store ptr+Person_age, 25 as i32
    store ptr+Person_id, 1001 as u64
    return
```

## 4. 类型惩罚与对齐
- **对齐要求**：SA 遵循 CPU 原生对齐。`i64` 应当放在 8 字节对齐的地址上。
- **类型转换**：SA 是强类型的。你不能直接把 `i64` 当作 `ptr` 使用，必须通过编译器允许的显式指令（如 `inttoptr`，但在安全模式下受限）。

## Pro Tip: 内存池优化
由于 `alloc` 涉及系统调用开销，SA 开发者通常会预分配一个大型 `Buffer` 并手动管理其偏移，或者直接使用 `sa_std` 提供的 `Arena` 分配器。

## 练习
1. 使用 `#def` 定义一个 `Point` 结构 (x, y)，并编写一个计算两点距离的函数。
2. 观察 `stack_alloc` 与 `alloc` 在生成的 LLVM bitcode 形态中的区别。
