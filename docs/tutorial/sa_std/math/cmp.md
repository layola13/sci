# Cmp & Sort (排序与比较)

内置在 SA 标准库中的集合排序算法及通用比较原语。它们在运行时实现了高效率的原地排序以及二分查找所需的基础构建。

## 导入
```sa
@import "sa_std/cmp.sa"
@import "sa_std/sort.sa"
```

## 核心宏与用法

### `CMP_U64 %out_res, %lhs, %rhs`
对无符号整数进行三路比较（Less, Equal, Greater）。`res` 为 -1，0，或 1。

```sa
@import "sa_std/cmp.sa"

@main() -> i32:
L_ENTRY:
    EXPAND CMP_U64 res, 10, 20
    // res 会是 -1
    !res
    return 0
```

### `SORT_SLICE_U64 %slice_reg`
基于 `O(N log N)` 的混合排序算法，在原内存地址上直接修改给定的 U64 数组切片。

```sa
@import "sa_std/sort.sa"
@import "sa_std/core/slice.sa"

@main() -> i32:
L_ENTRY:
    // ... 假定 my_slice 已经具备数据
    EXPAND SORT_SLICE_U64 my_slice
    return 0
```