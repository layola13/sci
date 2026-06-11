# BinaryHeap (优先队列)

提供了一个基于堆数据结构实现的优先队列。最大（或根据自定比较函数的最小）的元素总是被保证存放在堆顶，可以以 `O(log N)` 时间复杂度进行拉取与出栈。

## 导入
```sa
@import "sa_std/binary_heap.sa"
```

## 核心宏与用法

### `BINARY_HEAP_NEW %out_heap`
```sa
EXPAND BINARY_HEAP_NEW bh
```

### `BINARY_HEAP_PUSH %heap_reg, %value, %elem_size`
推入时内部会自动完成 `sift_up` 的堆层级平衡保护。

```sa
EXPAND BINARY_HEAP_PUSH bh, 100, 8
EXPAND BINARY_HEAP_PUSH bh, 200, 8
EXPAND BINARY_HEAP_PUSH bh, 50, 8
```

### `BINARY_HEAP_TRY_POP_U64 %out_ok, %out_value, %heap_reg`
弹出优先级最大元素。弹出时会自动进行 `sift_down`，重修调整二叉结构。

```sa
// 首次弹出必定为 200
EXPAND BINARY_HEAP_TRY_POP_U64 ok, val, bh
!val
!ok
```

### `BINARY_HEAP_FREE %heap_reg`