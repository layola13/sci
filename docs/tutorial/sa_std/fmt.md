# Fmt (格式化)

SA 运行时提供的对基本数据类型与自定义内存结构进行格式化的底层支持。相比于高级语言中的 `printf("%d")`，SA 使用显式寄存器配置的缓冲区写入风格。

## 导入
```sa
@import "sa_std/fmt.sa"
```

## 核心宏与用法

在 SA 中格式化通常涉及到提供一块预先分配的缓冲区栈或者由堆分配的 `String` 容器：

### `FMT_U64_TO_STRING %out_ok, %str_reg, %value`
直接把整数转化成动态字符串。

```sa
@import "sa_std/fmt.sa"
@import "sa_std/string.sa"

@main() -> i32:
L_ENTRY:
    EXPAND STRING_NEW my_str
    
    // 把数字 4096 作为文本写入到 my_str 中
    EXPAND FMT_U64_TO_STRING ok, my_str, 4096
    
    EXPAND STRING_FREE my_str
    !ok
    return 0
```

### `FMT_I64_TO_STRING %out_ok, %str_reg, %value`
将带符号整型转化为字符串（包含负号逻辑）。

### `FMT_F64_TO_STRING %out_ok, %str_reg, %value`
格式化浮点数，内部处理 NaN 与 Inf 控制。