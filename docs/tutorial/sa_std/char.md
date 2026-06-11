# Char & Ascii (字符处理)

这部分提供了针对单个字符进行判断、转码的快速操作。

## 导入
```sa
@import "sa_std/char.sa"
@import "sa_std/ascii.sa"
```

## 核心宏与用法

### `ASCII_IS_LOWER %out_bool, %char_val`
### `ASCII_IS_UPPER %out_bool, %char_val`
### `ASCII_IS_DIGIT %out_bool, %char_val`

这些宏通过查表和范围比较法，迅速返回对应 ASCII 状态的布尔值。

```sa
@import "sa_std/ascii.sa"

@main() -> i32:
L_ENTRY:
    // 'a' 对应 97
    EXPAND ASCII_IS_LOWER is_lower, 97
    // is_lower 为 1
    !is_lower
    return 0
```

### `ASCII_TO_LOWER %out_char, %char_val`
转换成对应的小写字符。如果不是字母，则原样返回。