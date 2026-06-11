# Vec (动态数组)

`Vec` 是 SA 应用程序中最常用的动态容器之一，功能对标 C++ 的 `std::vector`。

`Vec` 内部实现了均摊 `O(1)` 的基于两倍容量的扩容机制（有效消除线性追加时的性能恶化）。底层所有容量与字节相乘的计算均由安全的数学宏防卫（如 `NUM_U64_CHECKED_MUL`），发生溢出计算时将主动拒绝和 Panic。

## 导入
```sa
@import "sa_std/vec.sa"
```

## 核心宏与用法

### `VEC_NEW %out_vec`
初始化一个新的可变数组。

```sa
EXPAND VEC_NEW my_vec
```

### `VEC_PUSH %vec_reg, %value, %elem_size`
追加数据。由于 SA 不像高级语言可以在编译器自动推导泛型大小，在存放指针或普通结构时通常需要显式指定所存放元素占用的字节数。存放通常数值时可以用专用宏。

```sa
// 推入数字 99，占用 8 字节（对应 U64）
EXPAND VEC_PUSH my_vec, 99, 8
```

### `VEC_PUSH_U64 %vec_reg, %value`
专门为 8 字节 `u64` 操作定制的高效入栈操作。

### 安全的切片化边界检索
`Vec` 读取已被设计为极为安全的 `TRY_` 语法以防范下标越界读取：

#### `VEC_TRY_GET_U64 %out_ok, %out_value, %vec_reg, %index`
```sa
EXPAND VEC_TRY_GET_U64 ok, val, my_vec, 1
br ok -> L_GOT, L_FAIL
L_GOT:
    // 获取成功
    !val
    !ok
    jmp L_DONE
```

#### `VEC_TRY_FIRST_U64 %out_ok, %out_value, %vec_reg`
#### `VEC_TRY_LAST_U64 %out_ok, %out_value, %vec_reg`
分别安全地获取第一个与最后一个元素。

### `VEC_TRY_POP_U64 %out_ok, %out_value, %vec_reg`
安全地剔除和弹出最后一个元素，数组如果为空则返回 `ok=0`。

### 长度与内存管理

#### `VEC_LEN %out_len, %vec_reg`
获取目前内部堆装载的实际元素数。

#### `VEC_CAPACITY %out_cap, %vec_reg`
获取目前容器在底层实际持有的能够支持的容量。

#### `VEC_CLEAR %vec_reg`
清除内部数据（`len` 被重置为 0），但不释放分配的内存容量。

#### `VEC_FREE %vec_reg`
释放整个容器（包括内存）。在函数最后不再使用容器时必须调用。