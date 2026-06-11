# Math & Hash (底层数学与散列)

提供了高级数学计算指令的统一入口与数据散列哈希能力。

## 导入
```sa
@import "sa_std/math.sa"
@import "sa_std/hash.sa"
```

## Hash 核心宏

由于在内存地址防碰撞以及数据去重设计上的要求，SA 对外部直接暴露了高效的内部 Hash 操作接口。

### `HASH_U64 %out_hash, %value`
根据平台特定的哈希种子与内建的高性能函数对一个 64 位整型进行随机化散列生成，保障键分布均匀。

```sa
@import "sa_std/hash.sa"

@main() -> i32:
L_ENTRY:
    EXPAND HASH_U64 my_hash, 9999
    !my_hash
    return 0
```

### `HASH_SLICE %out_hash, %slice_reg`
为整段内存块切片执行哈希计算，常见于字符串哈希生成。

## Math 核心宏

除了基础操作码外，部分高级数学求值或具有分支控制的数学操作在 `math.sa` 得到封装：

### `MATH_MIN_U64 %out_res, %a, %b`
### `MATH_MAX_U64 %out_res, %a, %b`

```sa
@import "sa_std/math.sa"

@main() -> i32:
L_ENTRY:
    EXPAND MATH_MAX_U64 res, 50, 100
    // res 将为 100
    !res
    return 0
```