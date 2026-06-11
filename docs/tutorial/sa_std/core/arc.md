# Arc (Atomic Reference Counting)

`Arc` 提供了线程安全的共享所有权。当多个线程需要读取同一个堆上的数据时，`Arc` 可以保证数据存活直到最后一个使用者释放。

SA 的 `Arc` 包含底层溢出检查保护（强、弱引用计数防止下溢和上溢）。

## 导入
```sa
@import "sa_std/core/arc.sa"
```

## 核心宏与用法

### `ARC_NEW %out_arc, %value`
分配一个新的 `Arc` 实例封装给定的值。

```sa
EXPAND ARC_NEW arc_ptr, 1024
```

### `ARC_CLONE %arc_reg`
增加对该数据的强引用计数。每次将该 Arc 传递给其他线程或者其他需要持久占用的结构前调用。

```sa
EXPAND ARC_CLONE arc_ptr
```

### `ARC_GET %out_value, %arc_reg`
获取被 `Arc` 保护的内部数据的值。

```sa
EXPAND ARC_GET val, arc_ptr
// val 就是 1024
```

### `ARC_DECREMENT_STRONG_COUNT %arc_reg`
主动递减引用计数（通常在使用完毕时或者作为析构函数）。如果计数归零，底层堆内存将被自动释放。

```sa
EXPAND ARC_DECREMENT_STRONG_COUNT arc_ptr
```

### `ARC_TRY_UNWRAP %out_ok, %out_value, %arc_reg`
尝试剥离 `Arc`。如果此时它是**唯一**的强引用者，那么返回内部数据并且消耗该 Arc（释放包裹壳）。否则，`%out_ok` 返回 `0`。

```sa
EXPAND ARC_TRY_UNWRAP ok, val, arc_ptr
br ok -> L_UNWRAP_OK, L_UNWRAP_FAIL
```

### `ARC_GET_MUT %out_ok, %out_ptr, %arc_reg`
尝试获取独占的内部可变指针。只有当强引用和弱引用都**仅有 1 个**时才成功，否则返回失败。用于无竞争情况下的修改。

```sa
EXPAND ARC_GET_MUT ok, mut_ptr, arc_ptr
br ok -> L_MUT_OK, L_MUT_FAIL
L_MUT_OK:
    store mut_ptr+0, 2048 as u64
    !ok
    !mut_ptr
    jmp L_DONE
```