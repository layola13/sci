# 2. 动态容器 (Collections)

SA 为开发者提供了极为高效且具备底层内存防御机制的容器实现。在发生内存乘法计算溢出等极端状况时会安全中止。

## `Vec` (动态数组)
`Vec` 内部实现了均摊 `O(1)` 的基于两倍容量的扩容机制，并在容量计算溢出时主动断言退出。

`Vec` 封装了极为丰富的宏集，用于查询、弹出、切片以及范围操作：

```sa
@import "sa_std/vec.sa"

@main() -> i32:
L_ENTRY:
    EXPAND VEC_NEW v
    
    // 压入元素：容器寄存器，值，元素字节大小
    EXPAND VEC_PUSH v, 10, 8
    EXPAND VEC_PUSH v, 20, 8

    // 安全获取索引为 1 的元素。如果索引越界，`ok` 为 0
    EXPAND VEC_TRY_GET_U64 ok, val, v, 1
    br ok -> L_GET_OK, L_GET_FAIL

L_GET_OK:
    // 获取第一个元素
    EXPAND VEC_TRY_FIRST_U64 first_ok, first_val, v
    
    // 弹出尾部元素
    EXPAND VEC_TRY_POP_U64 pop_ok, pop_val, v

    // 获取长度与容量
    EXPAND VEC_LEN len, v
    EXPAND VEC_CAPACITY cap, v
    
    // 清空数据（不释放内存）
    EXPAND VEC_CLEAR v

    !first_ok
    !first_val
    !pop_ok
    !pop_val
    !len
    !cap
    !val
    !ok
    jmp L_CLEANUP

L_GET_FAIL:
    !ok
    !val
    jmp L_CLEANUP

L_CLEANUP:
    EXPAND VEC_FREE v
    return 0
```

## `HashMap` (哈希表)
支持键值对存储的字典，底层散列具有完整的插槽和探针分配保护。

```sa
@import "sa_std/hashmap.sa"

@main() -> i32:
L_ENTRY:
    EXPAND HASHMAP_NEW map

    // 插入键值对
    key = utf8:"user_id"
    EXPAND HASHMAP_INSERT map, &key, 1024

    // 获取元素
    EXPAND HASHMAP_GET ok, val, map, &key
    !ok
    !val

    EXPAND HASHMAP_FREE map
    return 0
```