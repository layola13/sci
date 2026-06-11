# Slice (内存切片)

切片 (Slice) 代表对一段连续内存（如 `Vec` 内部缓存、静态数组）的一个视图。切片仅包含了起始指针和长度信息，并不拥有底层数据。

## 导入
```sa
@import "sa_std/core/slice.sa"
```

## 核心宏与用法

### `SLICE_NEW %slice_reg, %data_ptr, %length`
构造切片。

```sa
EXPAND SLICE_NEW my_slice, ptr_base, 10
```

### `SLICE_TRY_GET_U64 %out_ok, %out_value, %slice_reg, %index`
**安全查询**：这是最常用的操作！底层附带了严格的 `ult %index, __slice_len` 边界检查。如果在边界内，`ok` 等于 1；如果越界，`ok` 为 0。

```sa
EXPAND SLICE_TRY_GET_U64 ok, val, my_slice, 5
br ok -> L_GET_OK, L_GET_FAIL
```

### `SLICE_TRY_GET_MUT_PTR_U64 %out_ok, %out_ptr, %slice_reg, %index`
安全的获取用于修改的可变指针。

```sa
EXPAND SLICE_TRY_GET_MUT_PTR_U64 ok, mut_ptr, my_slice, 2
br ok -> L_MUT_OK, L_FAIL
L_MUT_OK:
    store mut_ptr+0, 888 as u64
    !mut_ptr
    !ok
```

### `SLICE_TRY_FIRST_U64 %out_ok, %out_value, %slice_reg`
### `SLICE_TRY_LAST_U64 %out_ok, %out_value, %slice_reg`
分别获取头部或尾部的元素。如果空数组则返回 `ok=0` 失败。

```sa
EXPAND SLICE_TRY_LAST_U64 ok, last_val, my_slice
```

### `SLICE_IS_EMPTY %out_bool, %slice_reg`
获取布尔值判断切片长度是否为 0。