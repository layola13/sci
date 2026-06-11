# String (动态字符串)

在 SA 中，动态处理且具有内存增长特性的字符串数据由 `String` 容器提供。它可以像 `Vec` 一样被操作和维护。

## 导入
```sa
@import "sa_std/string.sa"
```

## 核心宏与用法

### `STRING_NEW %out_str`
创建一个空的动态字符串。

```sa
EXPAND STRING_NEW my_str
```

### `STRING_PUSH_STR %str_reg, %slice_reg`
拼接切片形式的其他字符串（不包含以 NUL 结尾的静态字符）。

```sa
EXPAND STRING_PUSH_STR my_str, my_slice
```

### `STRING_PUSH_CHAR %str_reg, %char_val`
压入一个 ASCII 字符或者 UTF-8 字符。

```sa
// 压入字符 'A'，其 ASCII 码为 65
EXPAND STRING_PUSH_CHAR my_str, 65
```

### `STRING_LEN %out_len, %str_reg`
获取字符串占用的字节数（而非单纯字符数）。

```sa
EXPAND STRING_LEN len, my_str
```

### `STRING_FREE %str_reg`
释放包含该字符串内容的内存堆空间。