# Phase 1 Agent B — 模块映射表（旧路径 → 新路径）

工作仓：盒上 `/content/kit-work/sci2-agentS1B`（分支 sa-optimize，HEAD be42fa97）。
域：io、fmt、os、time。未 commit，未 push。顶层文件数 216 → 216（每个移走的文件都留了薄 shim）；
sa_std 文件总数 364 → 407（净 +43：34 个 shim + 5 个拆分新文件 + 10 个新建 prelude，减 6 个覆写）。

## 0. 兼容策略（已验证，非假设）

SA 的 `@import` 是**文本包含 + 按规范路径去重**：`src/flattener/expandimportsinto.zig`
用 `seen_paths`（规范 entry_path）跳过重复包含，用 `active_paths` 对环报 `ImportCycle`。
`sa_std/...` 前缀由 `src/pkg/resolver.zig:resolveStandardImport` 解析（SA_STD_DIR → 仓根 sa_std/ → 工程根）。
因此**薄 shim 转发是语言支持的 re-export 机制**：旧路径留一个只含 `@import "新路径"` 的文件，
新老路径在同一程序里混用会被去重，不会重复定义，不成环。**本次不是 breaking change。**

- 仓内（sa_std/）的引用已全部改到新规范路径；
- tests/、demos/ 未动（任务禁令），靠 shim 继续工作：2947 个 demos 仍 `@import "sa_std/io/print.sai"`，
  约 100 个 tests 文件仍用 `sa_std/io.sa` / `sa_std/fs.sa` 等旧路径——shim 是它们的生命线，删除 shim 前必须先迁移它们。

## 1. 整体移动（git mv，内容除 @import 行外逐字节未变）

| 旧路径 | 新路径 | 说明 |
|---|---|---|
| sa_std/io.sai | sa_std/io/io.sai | io 对外契约（@extern sa_io_*） |
| sa_std/io.sal | sa_std/io/io.sal | io 状态码 + IoSlice/IoCursor 等布局 |
| sa_std/fs.sa | sa_std/io/file/fs.sa | 178 个 FS_* 宏，整体移动 |
| sa_std/fs.sai | sa_std/io/file/fs.sai | |
| sa_std/fs.sal | sa_std/io/file/fs.sal | |
| sa_std/path.sa | sa_std/io/file/path.sa | 195 个 PATH_* 宏，整体移动；见 §4 决策 P1 |
| sa_std/path.sal | sa_std/io/file/path.sal | |
| sa_std/io/buf_reader.sa | sa_std/io/buffer/buf_reader.sa | 8 个 BUF_READER_* 宏 |
| sa_std/io/buf_writer.sa | sa_std/io/buffer/buf_writer.sa | 7 个 BUF_WRITER_* 宏 |
| sa_std/io/bufio.sa | sa_std/io/buffer/bufio.sa | 聚合 |
| sa_std/io/bufio.sal | sa_std/io/buffer/bufio.sal | 聚合 |
| sa_std/io/print.sa | sa_std/io/print/print.sa | 旧文件仅 2 行 import；新文件承接 io.sa 拆出的 print 组（见 §2） |
| sa_std/io/print.sai | sa_std/io/print/print.sai | 仅声明 sa_print_bytes |
| sa_std/fmt.sai | sa_std/fmt/fmt.sai | fmt 对外契约（@extern sa_fmt_*） |
| sa_std/fmt.sal | sa_std/fmt/fmt.sal | SA_FMT_* + SaFmtBuffer/FmtResult 布局 |
| sa_std/string_format.sa | sa_std/fmt/format/string_format.sa | 40 个 STRFMT_*/FORMAT_* 宏，整体移动 |
| sa_std/env.sa | sa_std/os/env.sa | 69 个 ENV_* 宏 |
| sa_std/env.sai | sa_std/os/env.sai | |
| sa_std/process.sa | sa_std/os/process.sa | 148 个 PROCESS_* 宏 |
| sa_std/process.sai | sa_std/os/process.sai | |
| sa_std/process.sal | sa_std/os/process.sal | |
| sa_std/term.sa | sa_std/os/term.sa | 2 行 facade（term.sal + term.sai） |
| sa_std/term.sai | sa_std/os/term.sai | 终端 + epoll + PTY 契约 |
| sa_std/term.sal | sa_std/os/term.sal | |
| sa_std/time.sa | sa_std/time/time.sa | 128 个 TIME_* 宏 |
| sa_std/time.sai | sa_std/time/time.sai | |
| sa_std/time.sal | sa_std/time/time.sal | |
| sa_std/time.sla | sa_std/time/time.sla | Duration/Instant/SystemTime（SLA） |

未移动：`sa_std/os/fd.*`、`sa_std/os/unix_ffi.sa`、`sa_std/time/duration.*`、`sa_std/time/instant.*`
（已在域内，只改了内部 @import 指向）。

## 2. io.sa 拆分（925 行，83 个宏，宏体逐字节未变——已用脚本对 HEAD 校验）

| 新文件 | 宏（数量） | 来源 |
|---|---|---|
| sa_std/io/print/print.sa | PRINT, PRINTLN, WRITE, WRITELN, EPRINT, EPRINTLN（6）+ `@const IO_NEWLINE` | io.sa |
| sa_std/io/stdin/stdin.sa | IO_STDIN, IO_STDIN_AS_RAW_FD, IO_STDIN_AS_FD, READ_LINE, IO_READ_LINE, READ, IO_READ_SOME（7） | io.sa |
| sa_std/io/stdout/stdout.sa | IO_STDOUT, IO_STDERR, IO_STDOUT_AS_RAW_FD, IO_STDOUT_AS_FD, IO_STDERR_AS_RAW_FD, IO_STDERR_AS_FD, WRITE_SOME, IO_WRITE_SOME, IO_FLUSH_STDOUT, IO_FLUSH_STDERR（10） | io.sa |
| sa_std/io/handle.sa | IO_READ, IO_READ_BYTES, IO_READ_EXACT, IO_READ_EXACT_BYTES, IO_WRITE, IO_WRITE_BYTES, IO_WRITE_ALL, IO_WRITE_ALL_BYTES, IO_FLUSH, IO_CLOSE, IO_ERROR_KIND_FROM_STATUS, IO_ERROR_KIND_IS_RETRYABLE, IO_COPY, IO_COPY_N, IO_COPY_SLICE（15） | io.sa |
| sa_std/io/buffer/cursor.sa | IO_SLICE_*(8), IO_CURSOR_*(22), IO_EMPTY_*(3), IO_TAKE_*(6), IO_REPEAT_*(3), IO_SINK_*(2)（44） | io.sa |
| sa_std/fmt/format/format.sa | FORMAT_INT（1） | io.sa（跨域移动，见 §4 决策 F1） |

拆分依据是 EXPAND 依赖图（实测）：print 组只 EXPAND 组内（EPRINT→WRITE）；
stdin/stdout 组 EXPAND FD_AS_RAW（os/fd.sa）；stdout 的 IO_FLUSH_STDOUT/STDERR EXPAND IO_FLUSH（→ handle.sa）；
cursor 组内部 EXPAND 成闭包（IO_CURSOR_REMAINING / IO_SLICE_NEW / IO_CURSOR_READ / IO_TAKE_READ…）；
handle 组无组外 EXPAND。详见 MANIFEST-io.md。

## 3. 新建 prelude（聚合入口，沿用各域既有 prelude 模式）

| 文件 | 聚合内容 |
|---|---|
| sa_std/io/prelude.sa | handle, print/print, stdin/stdin, stdout/stdout, buffer/bufio, buffer/cursor, file/fs, file/path |
| sa_std/io/prelude.sal | io.sal, buffer/bufio.sal, file/fs.sal, file/path.sal |
| sa_std/io/print/prelude.sa | print.sa |
| sa_std/io/stdin/prelude.sa | stdin.sa |
| sa_std/io/stdout/prelude.sa | stdout.sa |
| sa_std/io/file/prelude.sa | fs.sa, path.sa |
| sa_std/io/buffer/prelude.sa | bufio.sa, cursor.sa |
| sa_std/fmt/prelude.sa | fmt.sal, fmt.sai, format/prelude.sa |
| sa_std/fmt/prelude.sal | fmt.sal |
| sa_std/fmt/format/prelude.sa | string_format.sa, format.sa |
| sa_std/fmt/display/prelude.sa | **占位**：sa_std 全仓无 Display 内容（见 DEFECTS.md D7） |
| sa_std/fmt/debug/prelude.sa | **占位**：sa_std 全仓无 Debug 内容（见 DEFECTS.md D7） |
| sa_std/os/prelude.sa | fd.sa, unix_ffi.sa, env.sa, process.sa, term.sa（改写，原只含 fd + unix_ffi） |
| sa_std/os/prelude.sal | fd.sal, process.sal, term.sal（改写，原只含 fd.sal） |
| sa_std/time/prelude.sa | duration.sa, instant.sa, time.sa（`../time.sa` → `time.sa`） |
| sa_std/time/prelude.sal | duration.sal, instant.sal, time.sai（`../time.sai` → `time.sai`） |

## 4. 旧路径 shim 清单（34 个，全部只含注释 + 一行 @import）

顶层（28）：`io.sa → io/prelude.sa`、`io.sai → io/io.sai`、`io.sal → io/io.sal`、
`fs.sa → io/file/fs.sa`、`fs.sai → io/file/fs.sai`、`fs.sal → io/file/fs.sal`、
`path.sa → io/file/path.sa`、`path.sal → io/file/path.sal`、
`fmt.sa → fmt/prelude.sa`、`fmt.sai → fmt/fmt.sai`、`fmt.sal → fmt/fmt.sal`、
`string_format.sa → fmt/format/string_format.sa`、
`env.sa → os/env.sa`、`env.sai → os/env.sai`、
`process.sa → os/process.sa`、`process.sai → os/process.sai`、`process.sal → os/process.sal`、
`term.sa → os/term.sa`、`term.sai → os/term.sai`、`term.sal → os/term.sal`、
`time.sa → time/prelude.sa`、`time.sai → time/time.sai`、`time.sal → time/time.sal`、
`time.sla → sa_std/time/time.sla`、`duration.sa → time/duration.sa`、`duration.sal → time/duration.sal`、
`instant.sa → time/instant.sa`、`instant.sal → time/instant.sal`。

io/ 内（6）：`io/bufio.sa → buffer/bufio.sa`、`io/bufio.sal → buffer/bufio.sal`、
`io/buf_reader.sa → buffer/buf_reader.sa`、`io/buf_writer.sa → buffer/buf_writer.sa`、
`io/print.sa → print/print.sa`、`io/print.sai → print/print.sai`。

## 5. 仓内 @import 引用更新（sa_std 内，tests/demos 除外）

域内：fs.sa（`os/fd.sa` → `../../os/fd.sa`）、path.sa（5 行：core/slice.*、string.sa、os/unix_ffi.sa、num.sa 各加 `../../`）、
path.sal、env.sa（`core/slice.sal` → `../core/slice.sal`）、process.sa（`fs.sa` → `../io/file/fs.sa`、`os/fd.sa` → `fd.sa`、`core/slice.sal` → `../core/slice.sal`）、
string_format.sa（5 行）、time.sa（`hash.sa` → `../hash.sa`）、time.sla（`sa_std/time.sa` → `sa_std/time/time.sla`）、
time/duration.*、time/instant.*（`../time.*` → 同目录 `time.*`）、bufio.sa（`print.sa` → `../print/print.sa`）、
bufio.sal（`print.sai` → `../print/print.sai`）、fmt.sal（`core/result.sal` → `../core/result.sal`）。
注：`io/buffer/buf_reader.sa`、`buf_writer.sa` 的 `../io.sai`、`io/buffer/bufio.sal` 的 `../io.sal`、
`io/print/print.sa` 的 `../io.sal` 字面未变，但解析目标已从顶层旧文件变为 `io/io.sai` / `io/io.sal`（已校验）。

跨域（其他域文件，只改 import 行）：net.sa、string.sa、ts_string.sa、thread.sa、
sync/{barrier,condvar,mpsc,mpsc_list,mutex,once,rwlock}.sa、
dns.sla、http_proxy.sla、icmp.sla、jwt.sla、supervisor.sla、ip.sla、net_info.sla、str.sla、url.sla、
async.sla、timer.sla、prelude.sa（7 行重定向 + 删除与 `io/prelude.sa` 重复的 `io.sa` 行）、prelude.sal（7 行重定向）。

未改：tests/（约 100 处旧路径 import，靠 shim）、demos/（2947 处 `sa_std/io/print.sai`，靠 shim）、
src/（Zig 侧只引 `src/runtime/sa_std/*.zig`，与 .sa 路径无关——已核对 `src/runtime/sa_std.zig`）、
docs/*.md 与 tests/std_smoke/*.zig 里的路径字符串（仅文档/注释性引用，非 @import；见 DEFECTS.md D11）。

## 6. 关键边界决策（供 parent / 用户复核）

- **P1 path 归属**：path.sa → `io/file/` 而非 `os/`。path.sa EXPAND 大量 FS_*（FS_READ_FILE、FS_COPY、FS_METADATA…），
  且 os/ 已有 unix_ffi 提供 OS 字符串；放 os/ 会造成 os→io→os 的域级环（path→fs→fd），放 io/file/ 则保持既有方向 io→os。
- **F1 FORMAT_INT 跨域**：io.sa 唯一的 fmt 依赖（调 `@sa_fmt_i64`）随宏移到 `fmt/format/format.sa`；
  此后 io→fmt 边消失，只剩 fmt→io（FORMAT_WRITE_* 调 `@sa_io_write_all`），方向单一、无环。
- **T1 time.sla**：`sa_std/time.sla` → `sa_std/time/time.sla`，旧路径留 `.sla` shim（`@import "sa_std/time/time.sla"`）；
  其 importers async.sla、timer.sla 已改到新路径。**shim 本身未经过构建验证**（Phase 1 禁跑构建），见 DEFECTS.md D8。
- **D1 display/debug 为空**：fmt/display/、fmt/debug/ 只有占位 prelude（见 MANIFEST-fmt.md）。
- **prelude.sa 清理克制**：只重定向、不做聚合重构；`io.sa` 行因与既有 `io/prelude.sa` 行重复而删除，其余冗余保留（loader 去重，无行为变化），
  待后续清理阶段再收敛。
