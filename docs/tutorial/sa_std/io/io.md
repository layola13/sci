# IO 流读写

SA 提供了处理字节数据流输入与输出的功能，封装在 `sa_std/io.sa` 系列中。它支持原生字节数组的游标操作以及对底层流对象的控制。

## 导入
```sa
@import "sa_std/io.sa"
@import "sa_std/io/buf_reader.sa"
@import "sa_std/io/buf_writer.sa"
```

## 核心宏与用法

### `PRINT` 与 `PRINTLN`
最直接的用于向控制台 stdout 输出内容的宏：

```sa
@const GREETING = utf8:"Hello, World!"

@main() -> i32:
L_ENTRY:
    // 13是字符长度
    EXPAND PRINTLN GREETING, 13
    return 0
```

### IO Cursor (字节游标读写)
它提供了一个带有内部游标索引的包裹，让你像处理文件流一样依次读取内存字节：

#### `IO_CURSOR_NEW %out_cursor, %data_ptr, %data_len`
#### `IO_CURSOR_READ %out_ok, %out_len, %cursor_reg, %dst_ptr, %dst_cap`
#### `IO_CURSOR_WRITE %out_ok, %out_len, %cursor_reg, %src_ptr, %src_len`

```sa
// 创建游标包裹
EXPAND IO_CURSOR_NEW cur, &GREETING, 13

// 提供目标缓冲 dst_buf
EXPAND IO_CURSOR_READ ok, read_len, cur, &dst_buf, 5
// 此时成功将 "Hello" 读入了目标内存，并且游标偏移到了 5
```

### BufWriter / BufReader
当流操作非常频繁时，使用缓冲将多次系统读写合并为整块吞吐，极大拉升 I/O 的效能表现。

```sa
EXPAND BUF_WRITER_NEW w_writer, raw_stream
// 填充
EXPAND BUF_WRITER_WRITE ok, w_len, w_writer, &data, 10
// 只有在 FLUSH 阶段，才发起实质的底层提交
EXPAND BUF_WRITER_FLUSH ok, w_writer
```