# os 域边界清单（MANIFEST）

域入口：`sa_std/os/prelude.sa`（.sa 聚合）、`sa_std/os/prelude.sal`（布局聚合）。
旧路径 shim：`sa_std/env.sa`、`env.sai`、`process.sa`、`process.sai`、`process.sal`、`term.sa`、`term.sai`、`term.sal`。
（`os/fd.*` 与 `os/unix_ffi.sa` 本就在域内，未移动。）

## 1. 公共模块

| 模块 | 文件 | 职责 | 宏数 |
|---|---|---|---|
| os/fd | os/fd.sa/sai/sal | 句柄↔原生 fd 转换：FD_AS_RAW/FD_DUP/FD_FROM_RAW/FD_INTO_RAW/FD_CLOSE_RAW 等；SA_FD_* 状态码 | 19 |
| os/unix | os/unix_ffi.sa | OS 字符串/OsStr：OS_STR_*/OS_STRING_*（48+1）；依赖 core/slice、vec、string、hash | 49 |
| os/env | os/env.sa/sai | 环境变量/当前目录/可执行路径/参数 JSON/XDG：ENV_* | 69 |
| os/process | os/process.sa/sai/sal | 进程生成/等待/信号/pidfd/退出状态/捕获输出：PROCESS_*、PIDFD_* | 148 |
| os/term | os/term.sa/sai/sal | 终端 raw 模式、epoll、PTY：SA_TERM_*（契约在 .sai；.sa 本身是 facade，无宏） | 0 |

合计：285 个宏；契约/布局文件 7 个。

## 2. 职责

- 操作系统原语：文件描述符、OS 字符串、环境、进程、终端。os 是 io/file 与 path 的下层依赖。
- 不负责：字节流读写（io 域）、格式化（fmt 域）、时间（time 域）、网络（net 域）。

## 3. 允许的依赖方向

```
os/fd      -> （仅自身 .sai/.sal）
os/unix    -> core/slice、vec、string、hash
os/env     -> core/slice（Slice_ptr/len）、env.sai
os/process -> os/fd（FD_*）、io/file（FS_READ_BUFFER_*）、core/slice
os/term    -> （仅自身 .sai/.sal）
os 整体   -> core、vec、string、hash、io/file（仅 process→fs 的读缓冲宏）
os 整体 -/-> fmt、net、db、http、sync、time
```

- os 不依赖 fmt/io（除 process→fs 这一处：PROCESS_EXEC_CAPTURE_* 用 FS_READ_BUFFER_* 读捕获输出——这是既有边，
  方向是 os→io/file，与 io→os/fd 并存，文件级无环，域级 os↔io 各取所需；若将来要彻底解耦，需把捕获缓冲抽到 io 侧，Phase 1 不动）。
- io/file/path 依赖 os/fd 与 os/unix_ffi（见 MANIFEST-io.md）；os 不反向依赖 io 的宏定义文件（只依赖 io/file/fs.sa 这一个实现文件）。
- 反向依赖（谁依赖 os）：io（FD_AS_RAW、OS_*、fs→fd）、path、process、net.sa（经 os/fd？——net.sa 只 import io.sal 与 os/fd.sa，已核对）、
  http_proxy.sla、smtp.sla（os/fd.sai）、sync（不依赖 os）、tests（经 shim）。

## 4. 内部依赖图

- fd.sa：内部闭包（FD_* 互 EXPAND）。
- unix_ffi.sa：EXPAND SLICE_*/VEC_*/STRING_*/HASH_*（core/vec/string/hash）+ OS_*（内部）。
- env.sa：EXPAND 仅 ENV_*（内部闭包）。
- process.sa：EXPAND FD_*（os/fd）+ FS_READ_BUFFER_*（io/file/fs）+ PROCESS_*/PIDFD_*（内部）。
- term.sa：无宏；纯 facade。

## 5. 边界规则

1. 新宏按前缀归属：FD_*（fd）、OS_STR_*/OS_STRING_*（unix）、ENV_*（env）、PROCESS_*/PIDFD_*（process）、终端契约进 term.sai（term）。
2. os/fd.sai、env.sai、process.sai、term.sai 是各自唯一的 @extern 契约文件；不得跨文件重复声明同一 `sa_*` 符号（见 DEFECTS.md D1 的教训）。
3. os 不得新增对 fmt/net/db/http/sync/time 的依赖；process→fs 是唯一允许的 os→io 边，新增类似边需登记。
4. unix_ffi 是 os 域内唯一的“重”模块（49 宏，依赖 4 个域外文件）；path 对它的依赖是传递性的，改动它要先看 MANIFEST-io.md §4。
5. 旧路径 shim 不得删除（tests 仍在用 `sa_std/env.sa`、`sa_std/process.sa` 等旧路径）。
