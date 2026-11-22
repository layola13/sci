# io 域边界清单（MANIFEST）

域入口：`sa_std/io/prelude.sa`（.sa 聚合）、`sa_std/io/prelude.sal`（布局聚合）。
旧路径 shim：`sa_std/io.sa`、`io.sai`、`io.sal`（顶层）、`sa_std/io/bufio.*`、`buf_reader.sa`、`buf_writer.sa`、`print.sa`、`print.sai`。

## 1. 公共模块

| 模块 | 文件 | 职责 | 宏数 |
|---|---|---|---|
| io（契约） | io/io.sai | Zig 后端 `sa_io_*` / `sa_print_bytes` 的 @extern 声明 | — |
| io（布局） | io/io.sal | SA_IO_* 状态码、IO_ERROR_KIND_*、IoSlice/IoCursor/IoTake/IoRepeat/SaIoBuffer 布局 | — |
| io/print | io/print/print.sa、print.sai | PRINT/PRINTLN/WRITE/WRITELN/EPRINT/EPRINTLN；`@const IO_NEWLINE` | 6 |
| io/stdin | io/stdin/stdin.sa | IO_STDIN*、READ_LINE/IO_READ_LINE、READ/IO_READ_SOME | 7 |
| io/stdout | io/stdout/stdout.sa | IO_STDOUT*/IO_STDERR*、WRITE_SOME/IO_WRITE_SOME、IO_FLUSH_STDOUT/STDERR | 10 |
| io/handle | io/handle.sa | 通用句柄 IO_READ/WRITE/FLUSH/CLOSE、IO_COPY/COPY_N/COPY_SLICE、IO_ERROR_KIND_* 映射 | 15 |
| io/buffer | io/buffer/buf_reader.sa、buf_writer.sa、bufio.sa/sal、cursor.sa | BUF_READER_*/BUF_WRITER_*、IO_SLICE_*/IO_CURSOR_*/IO_EMPTY_*/IO_TAKE_*/IO_REPEAT_*/IO_SINK_* | 8+7+44 |
| io/file | io/file/fs.sa/sai/sal、path.sa/sal | FS_*（178）、PATH_*（195）；文件系统 + 路径 | 178+195 |

合计：83（原 io.sa）+ 15（bufio）+ 178（fs）+ 195（path）= 471 个宏；契约/布局文件 6 个。

## 2. 职责

- 字节流抽象：stdin/stdout/stderr 句柄、通用 read/write/flush/close、内存 cursor/slice/take/repeat/sink。
- 文件系统：打开/读写/寻址/元数据/目录/权限/链接/监视（FS_* 全集），以及 POSIX 风格路径操作（PATH_* 全集）。
- 不负责：格式化（fmt 域）、网络（net 域）、进程/环境/终端（os 域，io 只消费 os/fd 的 FD_AS_RAW 等）。

## 3. 允许的依赖方向

```
io/print  -> io（io.sai/io.sal）
io/stdin  -> io（io.sai）、os/fd（FD_AS_RAW）
io/stdout -> io（io.sai）、os/fd（FD_AS_RAW）、io/handle（IO_FLUSH）
io/handle -> io（io.sai/io.sal）、core/mem（sa_mem_copy）
io/buffer -> io（io.sai/io.sal）、core/mem、string（sa_str_utf8_validate）、io/print
io/file   -> io（io.sai/io.sal via fs）、os/fd、os/unix_ffi、core/slice、string、num、hash（经 string/unix_ffi 传递）
io 整体  -> core、os（仅 fd/unix_ffi 两个叶子）、string、num、vec、hash
io 整体 -/-> fmt、net、db、http、sync、time
```

- io 依赖 core 与 os 的叶子模块；**不依赖 fmt**（FORMAT_INT 已移出，见 MAPPING.md F1）、不依赖 net/db/http/time/sync。
- 依赖是传递的文本包含：path.sa 未直接 @import hash.sa，但经 os/unix_ffi.sa 与 string.sa 传递获得
  DEFAULT_HASHER_*（见 DEFECTS.md D10）；清单按直接 @import 边 + 传递闭包两层记录。
- 反向依赖（谁依赖 io）：fmt/format（FORMAT_WRITE_* 调 sa_io_write_all）、net.sa（io.sal）、
  string_format 经 fmt、tests/demos（经 shim）。sync/time 不依赖 io。

## 4. 内部依赖图（文件级，EXPAND 边）

- print：内部闭包（EPRINT→WRITE，EPRINTLN→WRITELN）。
- stdin：IO_READ_LINE→READ_LINE，IO_READ_SOME→READ；FD_AS_RAW（os/fd）。
- stdout：IO_WRITE_SOME→WRITE_SOME；IO_FLUSH_STDOUT→IO_STDOUT+IO_FLUSH（handle）；FD_AS_RAW（os/fd）。
- handle：无组外 EXPAND；IO_READ_BYTES→IO_READ，IO_WRITE_BYTES→IO_WRITE，IO_WRITE_ALL_BYTES→IO_WRITE_ALL，IO_READ_EXACT_BYTES→IO_READ_EXACT。
- buffer/cursor：内部闭包（IO_CURSOR_REMAINING → READ/WRITE/READ_TO_END；IO_SLICE_NEW → READ_TO_STRING/TAKE_READ_TO_STRING；IO_TAKE_READ → TAKE_READ_TO_END → TAKE_READ_TO_STRING）。
- file/fs：EXPAND FD_*（os/fd）+ FS_*（内部）。
- file/path：EXPAND FS_*（file/fs）+ OS_*（os/unix_ffi）+ SLICE_*（core）+ STRING_*/STR_*（string）+ NUM_*（num）+ DEFAULT_HASHER_*/RANDOM_STATE_*（hash，经传递）。

## 5. 边界规则

1. 新宏按前缀归属：PRINT*/WRITE*（print）、IO_STDIN*（stdin）、IO_STDOUT*/IO_STDERR*（stdout）、
   IO_READ*/IO_WRITE*/IO_FLUSH/IO_CLOSE/IO_COPY*（handle）、IO_SLICE*/IO_CURSOR*/IO_TAKE*/IO_REPEAT*/IO_SINK*/IO_EMPTY*/BUF_*（buffer）、
   FS_*/PATH_*（file）。前缀与目录一一对应，不跨目录放宏。
2. io.sai/io.sal 是域内唯一契约/布局文件；子模块不得私自声明 `sa_io_*` @extern。
3. 子模块只 @import 自己直接用的文件（extern、布局、EXPAND 目标所在文件）；不许为“方便” import 整个 prelude。
4. 不得新增对 fmt/net/db/http/time/sync 的依赖；新增对 os 的依赖只允许 fd/unix_ffi 两个叶子，且需在清单里登记。
5. 旧路径 shim 不得删除——2947 个 demos 与约 100 处 tests 仍在用；删除前须先迁移消费者并经构建验证。
