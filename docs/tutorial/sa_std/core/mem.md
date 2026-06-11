# Mem (内存操作)

提供系统级的底层内存复制、重置。带有内置防止空指针读写的边界保护。

## 导入
```sa
@import "sa_std/core/mem.sa"
```

## 核心宏与用法

### `MEM_COPY %dst_ptr, %src_ptr, %byte_count`
将 `%src_ptr` 中的数据拷贝到 `%dst_ptr`。
此宏会展开调用底层的 `@sa_mem_copy`。当 `count` 不为 0 且出现 `dst` 或 `src` 为空指针的情况，它会触发诸如 `panic(1701)` 等安全断言，防止越界损害。

```sa
EXPAND MEM_COPY dst, src, 128
```

### `MEM_SET %dst_ptr, %val_u8, %byte_count`
填充指定的值。

```sa
// 将 dst 后面的 256 字节填为 0
EXPAND MEM_SET dst, 0, 256
```

### 常量大小宏
使用这些宏避免硬编码体系结构的字长：
- `MEM_SIZE_OF_U8`
- `MEM_SIZE_OF_U64`
- `MEM_SIZE_OF_PTR`

```sa
EXPAND MEM_SIZE_OF_U64 u64_size
// u64_size 为 8
```