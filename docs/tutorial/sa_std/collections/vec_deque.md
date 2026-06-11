# VecDeque (双端队列)

允许在队列的头部和尾部实现均摊 `O(1)` 时间复杂度插入与弹出。非常适合用来做队列消费系统。

## 导入
```sa
@import "sa_std/vec_deque.sa"
```

## 核心宏与用法

### `VEC_DEQUE_NEW %out_deque`
```sa
EXPAND VEC_DEQUE_NEW dq
```

### 队列两侧插入
#### `VEC_DEQUE_PUSH_BACK %deque_reg, %value, %elem_size`
#### `VEC_DEQUE_PUSH_FRONT %deque_reg, %value, %elem_size`

```sa
EXPAND VEC_DEQUE_PUSH_BACK dq, 99, 8
EXPAND VEC_DEQUE_PUSH_FRONT dq, 11, 8
```

### 队列两侧弹取
带有严格判定，如果没有元素返回失败：

#### `VEC_DEQUE_TRY_POP_BACK_U64 %out_ok, %out_value, %deque_reg`
#### `VEC_DEQUE_TRY_POP_FRONT_U64 %out_ok, %out_value, %deque_reg`

```sa
EXPAND VEC_DEQUE_TRY_POP_FRONT_U64 ok, val, dq
```

### `VEC_DEQUE_FREE %deque_reg`