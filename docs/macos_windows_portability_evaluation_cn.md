# sci macOS / Windows 可移植性评估与最小改动架构方案

> **评估日期**：2026-07-14
> **代码基线**：`d011df72bc69`，工具链版本 `sa 0.0.4`，Zig `0.14.1`
> **仓库**：`https://github.com/layola13/sci`
> **评估方法**：直接阅读构建、CLI、package、plugin、daemon 和 runtime 实现，并对 macOS / Windows 目标执行只类型检查的交叉目标诊断。
> **目标定义**：让 `sa` 在 Linux、macOS、Windows 宿主上原生运行，并默认生成当前宿主的原生程序。首期不要求从 Linux 完成 macOS / Windows 最终链接。

---

## 0. 执行结论

### 0.1 一句话结论

支持 macOS 和 Windows 是可行的，但当前障碍不是“补大约 15 个系统调用”，而是 **11,191 行 runtime 把 POSIX fd、Linux 系统调用和平台无关的 `u64` handle 混在了同一实现层中**。

最小且稳妥的方案不是复制三份 runtime，也不是立刻设计一个覆盖 io_uring、kqueue、IOCP 的统一 Reactor，而是：

1. 保留现有 `sa_std.h`、导出符号、`u64` handle 和错误码，不破坏 SA 程序与插件 ABI。
2. 增加一个很薄的 **宿主平台边界**，处理 CLI、包管理、插件路径、daemon 传输和链接器参数。
3. 增加一个 **runtime OS 后端边界**，把文件、socket、进程、终端、线程和动态库的原生资源类型隔离出来。
4. Linux 保持当前完整能力；macOS 最大化复用 POSIX；Windows 先实现文件、进程、TCP/UDP、时间、环境、线程和 DLL 等基础能力。
5. io_uring、epoll、pidfd、Linux abstract Unix socket、uid/gid/chroot 和 raw pthread 互操作在非 Linux 平台明确返回 `SA_STD_ERR_UNSUPPORTED`。
6. 各平台在各自的原生 CI runner 上构建和测试，不用 Linux 宿主的 LLVM 去交叉链接其他宿主版本。

### 0.2 工作量判断

| 目标 | 难度 | 主要原因 |
| --- | --- | --- |
| macOS 上让编译器 CLI 可构建、可运行 | 中 | 纯 Zig CLI 已通过 macOS 类型检查，主要剩 LLVM 发现、pthread shim、插件后缀和链接参数 |
| macOS 基础 `sa_std` | 中 | POSIX 可大量复用，但必须隔离 io_uring、epoll、pidfd、Linux socket 选项和 Darwin stat 差异 |
| Windows 上让编译器 CLI 可构建、可运行 | 中高 | package resolver/fetch、路径列表、插件、LLVM/COFF 链接和本地 IPC 都有 Unix 假设 |
| Windows 基础 `sa_std` | 高 | Windows 文件 HANDLE、Winsock SOCKET、进程 HANDLE 不能继续塞进统一的 POSIX fd 路径 |
| macOS / Windows 与 Linux 高级能力完全对齐 | 很高 | io_uring、kqueue、IOCP 的语义并不等价，强行统一会形成新的复杂层 |

对一名熟悉 Zig、LLVM C API 和三平台系统 API 的工程师，较现实的量级是：

- macOS 编译器 + 基础 runtime MVP：约 2 至 4 周。
- Windows 编译器 + 基础 runtime MVP：在 macOS/POSIX 边界完成后约 4 至 8 周。
- 高级网络、完整 daemon、TLS/DTLS 和平台发布硬化：另行排期，不能算在“基础可用”内。

这些是工程评估，不是承诺日期。Windows runtime 的测试矩阵和隐藏 ABI 假设会显著影响实际周期。

---

## 1. 范围与“支持”的定义

### 1.1 首期支持范围

本文的首期目标是 **host-native**：

- Linux 上的 `sa` 生成 Linux 原生程序。
- macOS 上的 `sa` 生成 Mach-O 原生程序。
- Windows 上的 `sa.exe` 生成 PE/COFF 原生程序。
- `build-wasm` 继续作为显式跨目标路径。

这与“在 Linux 上交叉构建一个能链接 Homebrew LLVM 和 macOS 系统框架的最终发行包”是两件事。后者涉及 SDK、系统库、代码签名和 LLVM 宿主库，不应成为首个移植里程碑。

### 1.2 分层验收定义

| 层级 | 验收含义 |
| --- | --- |
| L0：编译器启动 | `sa version/help/check` 可运行，诊断和 parser/referee 正常 |
| L1：宿主原生输出 | `sa build-exe` 能生成并运行本机 Hello World |
| L2：基础 runtime | 文件、目录、环境、时间、基础进程、TCP/UDP/DNS、线程可用 |
| L3：生态 | package fetch、plugin、installer、release archive、daemon 可用 |
| L4：高级平台能力 | io_uring/IOCP/kqueue、TLS server、DTLS、QUIC、平台安全扩展 |

macOS 和 Windows 只有达到 L2，才应在 README 中表述为“支持”；仅能编译 `sa version` 不等于用户程序可用。

### 1.3 明确非目标

首期不做：

- 不重命名已有 `sa_term_epoll_*`、`pthread_*` 或其他公开 ABI。
- 不删除 Linux 专用能力。
- 不要求 Windows 模拟 POSIX uid/gid/chroot/process group。
- 不要求 macOS 用 kqueue 仿真 io_uring 的 completion 语义。
- 不要求 Windows 首期实现 IOCP 版 `sa_netx`。
- 不复制一份 `sa_std_windows.zig` 和一份 `sa_std_macos.zig`。
- 不把所有平台资源强制转换成 `i32 fd`。

---

## 2. 已验证基线

### 2.1 克隆、构建和安装状态

当前工作区已经完成：

- origin：`https://github.com/layola13/sci.git`
- Zig：`0.14.1`
- 当前构建产物：`./zig-out/bin/sa version` 输出 `sa 0.0.4`
- 通过 `tools/install.sh` 安装到 `~/.sa`
- `~/.sa/bin/sa version` 输出 `sa 0.0.4`
- `~/.sa/env` 设置 `PATH` 和 `SA_STD_DIR=~/.sa/std`

当前 Linux 二进制不是自包含文件：

- 动态依赖 `libLLVM-14.so.1`
- 还依赖 LLVM 带入的 `libffi`、`libedit`、`libxml2` 等动态库
- 用户执行 `sa build-exe` 时，driver 会再次启动外部 `zig cc`

因此当前发行模型实际是：

> `sa` 二进制 + `sa_std` 静态库 + 标准库源码 + 宿主 LLVM 14 + 宿主 Zig 0.14.1

安装器和发行说明必须如实表达这一点，或者后续改成自包含发行。

### 2.2 runtime 规模

对 `src/runtime/sa_std.zig` 的静态统计：

| 指标 | 数量 |
| --- | ---: |
| 总行数 | 11,191 |
| `pub export fn` | 535 |
| `std.posix` 引用 | 537 |
| `std.os.linux` 引用 | 78 |

这直接否定了“替换约 15 个底层 API 即可无缝全平台”的判断。不是 535 个导出都要重写，但平台边界至少横跨 process、fs、socket、terminal、thread、dynamic loader 和高级网络。

### 2.3 交叉目标诊断

#### macOS：编译器核心基本可移植

以下只类型检查命令成功，退出码为 0：

~~~sh
zig test -target x86_64-macos -fno-emit-bin -lc \
  --dep build_options \
  -Mroot=src/cli.zig \
  -Mbuild_options=.zig-cache/c/a8d5c0953d5930cca5da60679b6b8305/options.zig
~~~

这说明 parser、flattener、referee、CLI 主体及大部分 package/plugin 代码没有根本性的 Darwin 障碍。

#### macOS：runtime 失败

`sa_std.zig` 的 macOS 类型检查暴露：

- `sa_net_uring.zig` 被无条件导入，导致 Zig 标准库 Linux `IoUring` 类型进入 Darwin 编译。
- `W.EXITED`、pidfd 等 Linux wait 语义在 Darwin 不存在。
- epoll event 类型在 Darwin 变成不可用或 `void`。
- 多处直接使用 Linux 风格 `MSG.PEEK`、socket option 常量。
- metadata 使用 `atim/ctim` 等 Linux stat 字段，而 Darwin 使用不同字段布局。

单独编译 pthread shim：

~~~sh
zig cc -target x86_64-macos -fsyntax-only src/runtime/sa_pthread_host.c
~~~

会在 `dlvsym` 失败，因为它是 glibc/GNU 扩展，不是 macOS API。

#### Windows：CLI 首个阻塞点在 package resolver

Windows CLI 类型检查首先失败于：

~~~text
src/pkg/resolver.zig:280: type 'void' does not support struct initialization syntax
~~~

对应实现是 POSIX `mmap(..., .{ .TYPE = .SHARED }, ...)`。这不是编译器核心问题，改为 portable 文件读取即可解除首个阻塞点。

#### Windows：package fetch 失败

`src/pkg/fetch.zig` 的 Windows 类型检查暴露：

- `std.posix.fork()` 在 Windows 返回类型/实现不可用。
- `execvpeZ`、`waitpid` 不可用。
- `file.chmod` / `dir.chmod` 依赖 POSIX mode bit。

#### Windows：runtime 是结构性失败

Windows runtime 的首批错误包括：

- `RegexC` 对 glibc regex 布局做固定 64 字节断言。
- Windows `fd_t`、文件 HANDLE 和 Winsock SOCKET 不是同一种整数 fd。
- `handleToFd` 不能返回 `STDIN_FILENO` 等 POSIX 常量。
- Linux `getsockopt` 接受 `i32`，Windows socket 是 opaque SOCKET。
- `wait4`、pidfd、POSIX signals、`AT.FDCWD`、`fstatat`、`fcntl` 均不可用。
- Unix socket、termios、pthread 和 Linux stat 字段进入同一编译单元。
- TLS server ABI 当前接受 `fd: i32`，不能无损承载 Win64 `SOCKET`。

这说明 Windows 不能靠增加几个 `if (builtin.os.tag == .windows)` 修完；必须先移除内部“所有资源都是 fd”的假设。

---

## 3. 当前架构图

### 3.1 编译路径

~~~text
.sa source
   |
   v
CLI / flattener / Referee
   |
   v
emit_llvm_llvmc.zig
   |
   +-- in-process LLVM C API --> *.sa.bc
   |
   v
driver/zigcc.zig
   |
   +-- external \"zig cc\" + libsa_std.{a|lib} + plugin native inputs
   |
   v
host-native executable
~~~

这里有两套独立的宿主依赖：

1. 构建 `sa` 本身时，要链接系统 `libLLVM`。
2. `sa` 为用户生成程序时，要能在 `PATH` 中启动外部 `zig cc`。

### 3.2 runtime 路径

~~~text
SA std macros / .sai declarations
   |
   v
stable C ABI in sa_std.h
   |
   v
sa_std.zig: 535 exports + global u64 Resource registry
   |
   +-- std.fs / std.net
   +-- std.posix
   +-- std.os.linux
   +-- raw pthread/dlfcn C shim
   +-- forced io_uring module import
~~~

外部 `u64` handle registry 是可移植性的有利基础；真正的问题是 registry 内部又被 `handleToFd` 压回 POSIX fd。

### 3.3 生态路径

- package fetch 直接 `fork/exec/waitpid`。
- package resolver 直接 POSIX `mmap`。
- plugin path list 固定用冒号分隔。
- plugin discovery 只识别 `.so`。
- plugin manifest 优先写死 `linux-x86_64` artifact。
- daemon 只支持 Unix domain socket。
- release workflow 只发布 Linux x86_64。

---

## 4. 代码级问题清单

### 4.1 构建系统

| 位置 | 当前问题 | 影响 |
| --- | --- | --- |
| `build.zig:41-43` | LLVM include/lib/name 默认写死 Debian/Ubuntu LLVM 14 | macOS/Windows 必须手工覆盖，自动发行不可用 |
| `build.zig:90-92` | 默认 install 会把构建结果复制回 `artifacts/sa_std/libsa_std.a` | 构建污染源码树，多 target 会互相覆盖 |
| `build.zig:156-166` | LLVM 测试再次硬编码 Linux 路径和 `LLVM-14` | 即使主程序参数化，测试仍不能跨平台 |
| `build.zig:680-682` | 所有 target 都编译 GNU pthread shim | macOS 因 `dlvsym` 失败，Windows 无 pthread |
| `build.zig:221-234` | CLI module 和 compile step 都链接 LLVM | 配置重复，平台差异更难控制 |

`tools/release.sh` 宣称依赖 Zig 交叉编译能力，但 `sa` 自身要链接 **目标平台的 LLVM C 库**。只有 target libc/SDK 并不足以从 Linux 产生可运行的 macOS/Windows compiler。

### 4.2 CLI 与 package

CLI 主体对 macOS 已表现良好。真正需要隔离的宿主操作不多：

- package child process
- package 只读策略
- resolver 映射/读取
- path-list delimiter
- daemon local endpoint
- linker/rpath 参数
- 动态库扩展名与 target key

这部分适合薄宿主层，不应把 parser/referee 搬进 PAL。

### 4.3 runtime

关键耦合点：

1. `src/runtime/sa_std.zig:9-15` 无条件保留 HTTP2/TLS/DTLS/QUIC/io_uring exports，其中 io_uring 模块不能在非 Linux 目标类型检查。
2. `src/runtime/sa_std.zig:205-209` 同时保存 portable `std.fs.File.Stat` 和 raw `std.posix.Stat`，后续大量 getter 直接读 raw 字段。
3. `src/runtime/sa_std.zig:995-1026` 的进程对象直接固化 pid、pidfd 和 POSIX pipe fd。
4. `src/runtime/sa_std.zig:1029-1082` 的 Resource union 混合 portable 对象和 POSIX-only 对象。
5. `src/runtime/sa_std.zig:1715-1733` 的 `handleToFd` 把 file、TCP、listener、UDP、terminal 全部压成 `std.posix.fd_t`。
6. `src/runtime/sa_std.zig:1997+` 的 wait status、signal、process group、uid/gid、chroot 与 pidfd 路径是 Linux/POSIX 专用实现。
7. `src/runtime/sa_std.zig:6090+` 动态库 API 明确只允许 Linux，尽管 `std.DynLib` 本身支持更多宿主。
8. `src/runtime/sa_std.zig:7290+` 公开 epoll 相关能力。
9. `src/runtime/sa_std.zig:8100+` metadata 依赖 `fstatat`、`AT.SYMLINK_NOFOLLOW` 和 Linux raw stat 字段。
10. `src/runtime/sa_pthread_host.c:1-33` 使用 `dlvsym(..., GLIBC_*)`。

### 4.4 链接 driver

`src/driver/zigcc.zig:32-60` 的 native executable 参数：

- 固定启动命令 `zig cc`
- 固定加入 Linux rpath：`-Wl,-rpath,$ORIGIN`
- 没有 host/target 参数
- 没有在启动前检查 Zig 版本

macOS 应使用 `@loader_path` 语义，Windows 不应传 rpath。首期 host-native 可直接按 `builtin.os.tag` 选择参数，不必引入完整 target abstraction。

### 4.5 插件

| 位置 | 假设 |
| --- | --- |
| `src/plugins.zig:1170-1176` | `SA_PLUGINS_PATH` 固定用 `:` 分隔，Windows 应为 `;` |
| `src/plugins.zig:1191` | 直接路径只接受 `.so` |
| `src/plugins.zig:1477` | 目录扫描只寻找 `.so` |
| `src/plugins.zig:2742-2752` | manifest 优先 `linux-x86_64`，否则取第一个 artifact |

“取第一个 artifact”在多平台 manifest 中是危险行为：Windows 可能加载 Linux `.so`，而不是报告当前 target 缺失。

### 4.6 daemon

- client 在 `src/daemon_client.zig:21` 调 `connectUnixSocket`。
- server 在 `src/cli.zig:3472+` 默认监听 `/tmp/sa-daemon.sock`。

macOS 可继续使用 Unix socket。Windows 应使用 named pipe，或在首期明确禁用 daemon 并继续走现有的 in-process fallback。为了不扩大首期范围，建议 Windows L2 完成后再加入 named pipe。

### 4.7 installer 与 release

当前发布链有四个必须先修的事实错误：

1. `tools/install.sh:321` 和 `tools/install.ps1:132` 指向 `https://github.com/sci/sa/releases`，正确仓库是 `layola13/sci`。
2. `.github/workflows/release.yml:41+` 的 macOS/Windows matrix 被注释。
3. release job 只下载名为 `linux-x86_64` 的 artifact，并只发布 `*.tar.gz`。
4. installer 下载 `<archive>.sha256`，但 workflow 没有上传或发布这些 sidecar 文件。

即使 runtime 明天完成，当前 installer 也无法安装正式的 macOS/Windows release。

---

## 5. 对现有 PAL 文档的校正

`docs/multi_platform_architecture.md` 可以保留为长期 PAL 愿景，但不适合作为近期实施估算，原因有三点。

### 5.1 不应先破坏 ABI

原文建议把 `sa_term_epoll_wait` 等接口重命名为统一 event loop。这样会同时影响：

- `sa_std.h`
- `.sai/.sal` 契约
- 已编译插件
- 用户程序
- ABI smoke 和文档

最小改动方案应保留旧符号。在非 Linux 平台返回 `SA_STD_ERR_UNSUPPORTED`；未来如确有跨平台 Reactor 需求，再 **新增** `sa_event_loop_v2_*`，而不是替换 v1 ABI。

### 5.2 io_uring、kqueue、IOCP 不是同一个抽象

- io_uring 是 submission/completion 模型。
- kqueue 主要是 readiness/change notification 模型。
- IOCP 是 completion 模型，并与 OVERLAPPED 生命周期紧密绑定。

把它们过早压成三个 `create/submit/wait` 函数，会把 buffer ownership、取消、backpressure 和 completion 生命周期藏进不透明实现，后续反而更难保证性能与安全。

近期只需：

- Linux 保留 `sa_net_uring`。
- 非 Linux 提供同符号 unsupported backend。
- 基础 TCP/UDP 继续走普通 socket API。
- 等真实 macOS/Windows 高并发需求和测试出现后，再设计中立 v2 API。

### 5.3 PAL 不应覆盖平台无关逻辑

JSON、fmt、buffer、Referee、parser、绝大多数标准库算法不应进入 PAL。平台边界只包住“拥有原生资源或调用宿主 API”的操作。

---

## 6. 推荐架构

### 6.1 总体结构

建议新增以下小型边界，文件名可按现有命名风格调整：

~~~text
src/
├── host/
│   ├── root.zig          # compile-time dispatch
│   ├── posix.zig         # Linux + macOS 宿主行为
│   └── windows.zig       # Windows 宿主行为
└── runtime/
    ├── os/
    │   ├── root.zig      # compile-time dispatch
    │   ├── posix.zig     # POSIX 可共享部分
    │   ├── linux.zig     # pidfd/epoll/Linux socket options
    │   ├── darwin.zig    # Darwin stat/kqueue/terminal 差异
    │   └── windows.zig   # HANDLE/SOCKET/process/console
    ├── sa_net_uring.zig
    └── sa_netx_unsupported.zig
~~~

这不是要求一次性把 `sa_std.zig` 全部搬走。采用“触达即抽取”：

1. 先抽 package child process、resolver read、plugin suffix。
2. 再抽 runtime resource 原生类型。
3. 每修复一个导出族，把对应 syscall 移到 backend。
4. `sa_std.zig` 保留 C ABI wrapper、参数校验、handle registry 和跨平台算法。

### 6.2 编译期 dispatch，不用运行时 vtable

~~~zig
const builtin = @import("builtin");

pub const impl = switch (builtin.os.tag) {
    .linux => @import("linux.zig"),
    .macos => @import("darwin.zig"),
    .windows => @import("windows.zig"),
    else => @compileError("unsupported host OS"),
};
~~~

这是零运行时分派，符合现有 Zig 风格，也避免在 535 个导出上引入函数指针表。

### 6.3 两个边界的职责

**宿主平台边界**只服务 `sa` 工具：

- `runChild`
- `makePackageReadOnly`
- `readPackageSource`
- `pathListDelimiter`
- `dynamicLibraryExtension`
- `localDaemonEndpoint`
- `nativeLinkerArgs`

**runtime OS 后端**只服务用户程序：

- 文件/目录和 metadata
- process spawn/wait/terminate
- TCP/UDP/socket options
- terminal/console
- thread
- dynamic library
- 平台能力查询

这两个边界不能合并。编译器 package fetch 与用户程序的 process ABI 生命周期、安全策略和错误映射都不同。

### 6.4 错误与 capability 规则

继续使用已有：

- `SA_STD_OK`
- `SA_STD_ERR_UNSUPPORTED`
- `SA_STD_ERR_INVALID_ARGUMENT`
- `SA_STD_ERR_INVALID_HANDLE`

规则：

1. 平台不支持必须明确返回 `UNSUPPORTED`，不能伪造成功。
2. 不支持的 scalar getter 应设置 `last_error=UNSUPPORTED` 并返回文档化的零值。
3. capability probe 与实际调用必须一致。
4. Linux 回归测试保证原有成功路径不退化。
5. 不把当前 `fd_open/mmap/signal` 等 compatibility fake-success shim 当作跨平台实现。

---

## 7. 保持 ABI，重做内部资源类型

### 7.1 外部 handle 不变

当前公开约定已经适合跨平台：

~~~c
uint64_t handle;
int32_t status;
~~~

继续让 `u64` 只是 registry key，不暴露 fd/HANDLE/SOCKET。

### 7.2 删除“万能 fd”内部路径

当前 `handleToFd` 同时接受：

- file
- TCP stream
- TCP listener
- UDP socket
- owned fd
- terminal session

在 Windows：

- 文件是 `HANDLE`
- TCP/UDP 是 `SOCKET`
- console 也是特殊 `HANDLE`
- 三者的关闭、等待和错误域不同

因此推荐按操作需要返回强类型 view，而不是一个 fd：

~~~zig
const ReadTarget = union(enum) {
    file: *std.fs.File,
    tcp_stream: *std.net.Stream,
    terminal: *os.Terminal,
    stdin: void,
};

const SocketTarget = union(enum) {
    tcp_stream: *std.net.Stream,
    tcp_listener: *std.net.Server,
    udp: *os.UdpSocket,
};
~~~

随后：

- `read/write` 对 `ReadTarget` dispatch。
- socket option 只接受 `SocketTarget`。
- terminal API 只接受 terminal。
- epoll/fcntl/raw-fd API 只在 POSIX/Linux backend 提供。

### 7.3 Resource union 的目标形态

~~~zig
const Resource = union(enum) {
    file: std.fs.File,
    dynamic_lib: os.DynamicLibrary,
    tcp_stream: std.net.Stream,
    tcp_listener: std.net.Server,
    udp_socket: os.UdpSocket,
    metadata: os.Metadata,
    process: os.Process,
    terminal_session: os.Terminal,

    // buffer/json/fmt/regex 等平台无关资源保持原样
};
~~~

`Resource.close` 继续是统一入口，但每个 variant 调自己的 typed close/deinit。

### 7.4 raw fd / raw pthread 的处理

已有 ABI 中带 raw POSIX 语义的接口不删除：

- Linux：保持当前行为。
- macOS：仅在语义确实等价时支持。
- Windows：返回 `SA_STD_ERR_UNSUPPORTED`。

不要把 Win64 `SOCKET` 截断成 `i32` 来满足旧签名。需要 Windows raw socket interop 时，应新增接受 `u64` 或 SA handle 的 v2 API。

---

## 8. macOS 最小实施方案

macOS 应先做，因为它可以验证平台边界是否足够窄，同时不用立即处理 Windows 的 HANDLE/SOCKET 分裂。

### 8.1 第一步：让 host compiler 原生构建

1. LLVM 配置不再使用 Linux 默认路径。
2. 优先读取显式 `-Dllvm-include-dir/-Dllvm-lib-dir/-Dllvm-lib-name`。
3. 其次支持 `LLVM_CONFIG` 或 `llvm-config` 发现。
4. Homebrew Intel 和 Apple Silicon 路径只作为最后 fallback，不写进核心逻辑。
5. LLVM C backend 测试复用同一组配置，不再单独硬编码 `/usr/lib/llvm-14`。
6. `zigcc.zig` 在 macOS 加 `-Wl,-rpath,@loader_path`，Linux 才加 `$ORIGIN`，Windows不加 rpath。

首期建议继续固定 LLVM major 14，避免移植和 LLVM 升级同时发生。

### 8.2 第二步：隔离 Linux-only module

`sa_std.zig` 顶部不再无条件导入 `sa_net_uring.zig`：

~~~zig
const netx = switch (builtin.os.tag) {
    .linux => @import("sa_net_uring.zig"),
    else => @import("sa_netx_unsupported.zig"),
};

comptime {
    _ = &netx.sa_netx_init;
}
~~~

`sa_netx_unsupported.zig` 保留相同导出名：

- 可纯算法实现的 WebSocket key/frame 和 URL parse 继续可用，最好逐步移到 common module。
- `sa_netx_init/listen/recv_ticket/push_outbound/broadcast/close/shutdown` 返回 `UNSUPPORTED`。

这样不会修改 SA ABI，也不会让 Linux 路径退化。

### 8.3 第三步：pthread shim

最小方案：

- Linux 保留当前 `dlvsym + dlsym` shim。
- macOS 新增只使用 `dlsym(RTLD_NEXT, ...)` 的 shim。
- `build.zig` 按 target 只编译一个 shim。

长期更干净的方案是让普通 `pthread_spawn/join/drop` 内部改用 `std.Thread`，只把 `sa_thread_as_pthread_t` 等 raw interop 留给 POSIX backend。这样 Windows 也能复用普通线程 API。

### 8.4 第四步：Darwin metadata

优先使用 `std.fs.File.Stat` 提供的 portable 字段：

- kind
- size
- mode（存在时）
- atime/mtime/ctime

只有 dev/ino/nlink/blocks 等平台扩展才由 `os.Metadata` backend 提供。Darwin 字段名不能通过 Linux 字符串 `"atim"`、`"ctim"` 直接反射。

建议：

~~~zig
pub const Metadata = struct {
    common: std.fs.File.Stat,
    native: NativeMetadata,
};
~~~

其中 `NativeMetadata` 在 Linux、Darwin、Windows 分别定义，不泄漏到 ABI wrapper。

### 8.5 第五步：process 分层

macOS 可支持：

- spawn
- cwd/env
- stdout/stderr capture
- wait / try-wait
- terminate / signal
- POSIX process group（经测试后启用）

macOS 不支持或首期不承诺：

- pidfd
- Linux `waitid(P_PIDFD)`
- Linux-specific setgroups/chroot 组合行为
- pidfd send signal

generic process API 应在 Darwin backend 用 `waitpid` 回退，而不是让所有 generic wait 都依赖 pidfd。

### 8.6 第六步：socket 与 Unix socket

macOS 可复用大部分 `std.posix` TCP/UDP 路径，但必须：

- 用 Darwin 可用的 socket option 常量。
- peer credentials 使用 Darwin 对应能力，未实现前返回 `UNSUPPORTED`。
- pathname Unix socket 可以支持。
- Linux abstract Unix socket 明确不支持。
- epoll exports 保留符号但返回 `UNSUPPORTED`。

不建议为了让旧 epoll API“成功”而在内部偷偷转成 kqueue。两者事件标志与生命周期不同。

### 8.7 第七步：动态库、插件和 daemon

- `sa_dl_open/sym/close` 放宽为 Linux + macOS，底层继续 `std.DynLib`。
- plugin 后缀支持 `.dylib`。
- manifest 精确选择 `macos-x86_64` 或 `macos-aarch64`。
- `SA_PLUGINS_PATH` 使用 `std.fs.path.delimiter`。
- daemon 继续 Unix socket，但默认路径应来自 temp dir，并考虑用户隔离。

### 8.8 macOS MVP 验收

在 Intel 和 Apple Silicon runner 上至少通过：

1. `sa version/help/check`
2. parser/referee/package 单测
3. `sa build-exe` + 运行 Hello World
4. 文件读写、目录遍历、metadata portable 字段
5. process spawn/capture/wait
6. TCP client/server、UDP、DNS
7. generic thread spawn/join
8. `.dylib` plugin smoke
9. daemon Unix socket smoke
10. Linux-only API 返回 `SA_STD_ERR_UNSUPPORTED`

---

## 9. Windows 最小实施方案

Windows 应分成“host compiler”与“用户 runtime”两阶段。先让 `sa.exe` 的纯编译器功能工作，再接入基础 runtime。

### 9.1 package fetch：删除 fork/exec

`runGitClone` 可直接改成现有代码库已经大量使用的 `std.process.Child.run`：

~~~zig
const result = try std.process.Child.run(.{
    .allocator = allocator,
    .argv = argv.items,
    .env_map = &env_map,
});
~~~

检查 `result.term` 即可，不需要手工 fork、构造 null-delimited argv/envp 和 waitpid。

这项改动同时简化 Linux/macOS 代码，应作为第一批跨平台修复。

Windows 的 `GIT_ASKPASS=/bin/false` 也应替换为平台策略：

- 保留 `GIT_TERMINAL_PROMPT=0`
- 保留 `GCM_INTERACTIVE=Never`
- 只有 POSIX 才设置 `/bin/false`

### 9.2 resolver：用 portable owned bytes 代替 mmap

package 源文件通常远小于 LLVM artifact。为移植保留 POSIX mmap 没有足够收益。

推荐把 resolver storage 明确为：

~~~zig
const SourceStorage = union(enum) {
    owned: []u8,
    mapped: []align(std.heap.page_size_min) u8,
};
~~~

最小版本甚至可以全平台统一 `readToEndAlloc`，删除 mmap 分支。这样 Windows CLI 的首个编译阻塞点会直接消失，生命周期也更容易验证。

### 9.3 package 只读策略

POSIX 的 `0444/0555` 不能直接映射为 Windows 安全边界：

- Windows read-only attribute 对目录不提供等价保护。
- 真正不可写需要 ACL。

首期建议：

1. 文件设置 `FILE_ATTRIBUTE_READONLY`。
2. 安装/解析前后都重新校验 source tree SHA-256。
3. 不声称目录 ACL 已提供 POSIX 等价不可变性。
4. 如果 threat model 要求恶意本地进程也不能修改缓存，再单独实现用户 ACL。

哈希复核比伪造一个“chmod 成功”更符合当前零信任 package 设计。

### 9.4 UTF-8 API 与 Windows path

SA ABI 继续接受 UTF-8 byte slice。backend 负责转换：

~~~text
SA UTF-8 bytes -> validated UTF-8 -> Windows WTF-16/UTF-16 API
~~~

能使用 `std.fs`、`std.process` 的地方优先使用 Zig 标准库，让 Zig 处理转换。只有直接调用 Win32 API 时才显式转换，不在上层散布 `[*:0]u16`。

### 9.5 Windows runtime 基础能力

#### 文件与目录

优先使用：

- `std.fs.File`
- `std.fs.Dir`
- `std.fs.File.Stat`

实现：

- open/read/write/seek/flush/close
- create/remove/rename
- directory iteration
- portable metadata kind/size/time

POSIX-only metadata getter：

- uid/gid/mode bits
- block/char/fifo/socket node
- inode/device semantics

首期返回 `UNSUPPORTED` 或文档化零值，不能伪造 Linux 值。

#### 进程

基础路径使用 `std.process.Child` 或 Windows backend：

- CreateProcess
- inherited/stdout/stderr pipes
- wait
- try-wait
- exit code
- TerminateProcess

不支持：

- POSIX signal number语义
- uid/gid/setgroups
- chroot
- setsid/process group 等价物
- pidfd

Windows Job Object 可在后续用于 process group、递归终止和 resource limit，但不应阻塞首个 MVP。

#### TCP/UDP/DNS

使用 `std.net` + 独立 `UdpSocket` wrapper。关键要求：

- socket variant 内保存 `SOCKET`，不进入 `i32 fd`。
- socket close 使用 Winsock close 语义。
- WSA error 映射到 SA error code。
- 初始化/清理 Winsock 生命周期由 backend 管理。

首期不支持 Unix domain socket；现代 Windows 的 AF_UNIX 可以作为后续增强。

#### terminal

POSIX termios 路径不能编译到 Windows。Windows backend 使用：

- `GetConsoleMode`
- `SetConsoleMode`
- `GetConsoleScreenBufferInfo`

raw mode 只映射可证明等价的 flag。不是 console 的重定向 stdin/stdout 应继续走普通 file/pipe 路径。

#### 线程

普通 SA thread API 改用 `std.Thread` 后可跨平台：

- spawn
- detached spawn
- join
- drop

所有 raw pthread 转换 API 在 Windows 返回 `UNSUPPORTED`。

#### 动态库

`std.DynLib` 可作为 DLL loader。需要：

- 识别 `.dll`
- target-specific artifact selection
- 明确 DLL 搜索目录，避免不安全的当前目录搜索
- symbol smoke 使用同一 `std.DynLib.lookup`

### 9.6 TLS server / DTLS 的 Windows 限制

现有接口将 socket 参数定义为 `i32 fd`。Win64 `SOCKET` 不能安全截断到 `i32`。

所以首期：

- Windows 上 TLS server 和 DTLS 返回 `UNSUPPORTED`。
- 不通过 cast 强行接 OpenSSL。
- 后续新增接受 SA socket handle 的 v2 API，再由 backend 取出 native SOCKET。

HTTP/2 中不直接依赖 fd 的纯协议部分可继续工作，但 Linux-only `.so` candidate 列表要按平台拆分。

### 9.7 daemon

最小交付顺序：

1. Windows L0-L2 阶段不设置 daemon endpoint，CLI 自动 in-process。
2. L3 使用 `\\.\pipe\sa-daemon-<user>` named pipe。
3. host 层提供统一的 `connect/read/write/close`，上层 JSON line protocol 不变。
4. named pipe ACL 限制为当前用户。

不建议用固定 localhost TCP port 作为默认方案，因为要额外解决端口发现、认证和其他本地用户连接。

### 9.8 Windows MVP 验收

在 Windows x86_64 runner 上至少通过：

1. `sa.exe version/help/check`
2. package offline resolve 和 `git clone` fetch
3. `sa build-exe` 生成并运行 `.exe`
4. 文件/目录/portable metadata
5. process spawn/capture/wait/terminate
6. TCP/UDP/DNS
7. generic thread spawn/join
8. DLL plugin smoke
9. PowerShell installer clean-machine smoke
10. POSIX/Linux-only API 稳定返回 `UNSUPPORTED`

---

## 10. 目标 capability 矩阵

图例：

- **S**：首期支持并进入 CI。
- **P**：可部分支持，行为由平台文档限定。
- **U**：首期明确 unsupported。
- **L**：后续独立里程碑。

| 能力 | Linux | macOS MVP | Windows MVP | 说明 |
| --- | :---: | :---: | :---: | --- |
| `version/help/check/referee` | S | S | S | 编译器核心 |
| host-native `build-exe` | S | S | S | 各宿主原生构建 |
| `build-wasm` | S | S | S | 仍依赖外部 Zig |
| package local/offline resolve | S | S | S | Windows 改 owned read |
| package git fetch | S | S | S | 统一 Child.run |
| POSIX chmod 等价保护 | S | S | U | Windows 用 attribute + hash recheck |
| 基础文件/目录 | S | S | S | portable std.fs |
| portable metadata | S | S | S | kind/size/time |
| uid/gid/device/block metadata | S | P | U | 平台扩展 |
| 基础 process spawn/wait | S | S | S | backend 实现 |
| POSIX signals/process group | S | P | U | Windows 后续 Job Object 不等价 |
| pidfd | S | U | U | Linux-only |
| uid/gid/chroot/setgroups | S | P | U | macOS 需单独测试 |
| TCP/UDP/DNS | S | S | S | typed socket |
| pathname Unix socket | S | S | U | Windows 后续可评估 AF_UNIX |
| abstract Unix socket | S | U | U | Linux-only |
| epoll ABI | S | U | U | 保留符号并返回 unsupported |
| `sa_netx` io_uring backend | S | U | U | 高级 backend 后续另做 |
| terminal raw mode | S | S | S | Windows Console backend |
| generic SA threads | S | S | S | 建议 std.Thread |
| raw pthread interop | S | S/P | U | Windows 无 pthread |
| dynamic library | S | S | S | .so/.dylib/.dll |
| native plugin | S | S | S | target-specific artifact |
| daemon | S | S | L | Windows named pipe 后续 |
| HTTP/2 pure protocol | S | P | P | 动态库 candidate 需平台化 |
| TLS server/DTLS raw-fd ABI | S | P | U | Windows 需要 v2 socket-handle ABI |
| QUIC | P | U | U | 当前本身仍是 capability facade |

该矩阵应转成机器可测试的 capability contract，而不是只存在文档里。

---

## 11. LLVM 与 Zig 依赖策略

### 11.1 首期策略：保持依赖，先把它管理正确

最小改动下继续使用：

- Zig `0.14.1`
- LLVM `14.x` C API
- 外部 `zig cc`

不要在同一个移植里同时升级 Zig/LLVM，否则平台错误与 API 迁移错误无法区分。

### 11.2 LLVM 发现顺序

建议构建时按以下顺序：

1. 显式 `-Dllvm-include-dir/-Dllvm-lib-dir/-Dllvm-lib-name`
2. 环境变量 `LLVM_CONFIG`
3. `llvm-config` / `llvm-config-14`
4. 平台包管理器已知位置
5. 输出包含实际探测路径的明确错误

Windows 不能假定库名一定是 `LLVM`；应允许 `LLVM-C` 或具体发行包提供的 import library 名称。

### 11.3 发行依赖的两个可选方向

**方向 A：最小工程量**

- release archive 不捆绑 LLVM 和 Zig。
- installer 检查并安装/提示固定版本依赖。
- 文档明确 `sa build-exe` 需要 Zig。
- 每个平台 package manager 提供安装说明。

优点是改动小；缺点是用户体验和版本一致性较弱。

**方向 B：自包含发行**

- 静态链接 LLVM，或随 archive 带平台对应动态库。
- 随工具链捆绑 Zig，或移除 external `zig cc` 依赖。
- 处理 LLVM/第三方库许可证、体积、rpath/DLL search、代码签名。

这是发行工程，不是基础移植的先决条件。建议先完成方向 A，再基于实际下载体积和支持成本决定。

### 11.4 启动时诊断

`sa build-exe` 在启动 external compiler 前应：

- 查找 `zig`
- 校验 major/minor 为 `0.14.x`
- 找不到时输出稳定错误码和安装提示

不要等到 `ChildProcessFailed` 才把“找不到 Zig”混成普通链接失败。

---

## 12. `build.zig` 最小改造清单

### 12.1 必改项

1. 增加统一 LLVM discovery，主库、CLI 和 LLVM 测试复用。
2. `addPthreadHostShimToModule` 按 target 选择 Linux/macOS，Windows 不加入 POSIX shim。
3. runtime root 按 target 选择 netx backend。
4. 删除默认 `addUpdateSourceFiles` 对 `artifacts/sa_std/libsa_std.a` 的回写。
5. `sa_std_archive_path` 不再永久嵌入构建机绝对路径。
6. archive 名按 target 使用 `libsa_std.a` 或 `sa_std.lib`。
7. test step 按平台分组，不让 Linux-only runtime test 阻塞 portable test。
8. Linux-only system library 只在 Linux 链接；macOS/Windows 设置各自依赖。

### 12.2 artifact 布局

推荐 release 构建只从 `zig-out` 取目标产物：

~~~text
zig-out/
├── bin/sa[.exe]
├── lib/libsa_std.a | sa_std.lib
├── lib/libsa_std.so | libsa_std.dylib | sa_std.dll
└── include/sa_std.h
~~~

如果仓库确实需要 checked-in runtime archive，应改成显式命令：

~~~sh
zig build sync-sa-std-artifact -Dtarget=<triple>
~~~

并写到 target-specific 目录，例如 `artifacts/sa_std/<triple>/`。不能让普通 `zig build` 修改 git worktree。

### 12.3 安装后 runtime 定位

建议定位顺序：

1. `SA_STD_DIR`
2. 可执行文件相对路径 `../std`
3. 构建时开发 fallback

这样 release binary 不依赖构建机上的 `/root/projects/sci/artifacts/...`。

### 12.4 测试分组

建议 build step：

| step | 内容 |
| --- | --- |
| `test-portable` | parser/referee/layout/package portable 单测 |
| `test-runtime-basic` | fs/process/net/time/env/thread 基础契约 |
| `test-runtime-linux` | io_uring/epoll/pidfd/abstract socket |
| `test-runtime-darwin` | Darwin metadata/Unix socket/terminal |
| `test-runtime-windows` | HANDLE/SOCKET/console/process |
| `portability-check` | 三目标 `-fno-emit-bin` 类型检查 |

Linux 当前 `ci` step 可继续作为完整基线，但非 Linux job 不应尝试运行 Linux-only 测试。

---

## 13. 插件与 daemon 的平台化

### 13.1 插件 target key

统一从编译目标生成 key：

~~~text
linux-x86_64
linux-aarch64
macos-x86_64
macos-aarch64
windows-x86_64
windows-aarch64
~~~

`selectArtifact` 必须只选择当前 key。不存在时返回明确的 `PluginTargetUnsupported`，不能 fallback 到 JSON 对象第一项。

### 13.2 动态库识别

增加一个共享 helper：

~~~zig
fn nativeDynamicLibraryExtension() []const u8 {
    return switch (builtin.os.tag) {
        .linux => ".so",
        .macos => ".dylib",
        .windows => ".dll",
        else => "",
    };
}
~~~

以下路径都使用同一个 helper：

- 直接 `SA_PLUGINS_PATH`
- 安装目录扫描
- raw artifact 拒绝规则
- manifest artifact 验证
- symbol smoke

### 13.3 path list

使用 Zig 已提供的 `std.fs.path.delimiter`：

- POSIX：`:`
- Windows：`;`

这同时避免把 `C:\plugins\foo.dll` 的盘符冒号拆开。

### 13.4 插件构建

当前插件安装器执行：

~~~text
zig build -Doptimize=ReleaseFast
~~~

为了让多平台 manifest 可重现，应追加：

- 当前 target key 传给 plugin build，或要求原生 runner 构建当前宿主 artifact。
- 安装后验证 artifact extension 与 target key 一致。
- `.sai` symbol smoke 在每个平台执行。
- 插件工程的 `sap.json` 同时列出多 target 时，不要求本机生成其他平台产物。

外部插件仓库也必须增加对应 artifact。仅修改 `sci` 不能自动让 Linux-only 插件成为 Windows DLL。

### 13.5 daemon transport interface

JSON line protocol和 cancellation/generation 逻辑可以不变，只抽 transport：

~~~zig
pub const LocalConnection = struct {
    pub fn read(...);
    pub fn writeAll(...);
    pub fn close(...);
};

pub fn connect(endpoint: Endpoint) !LocalConnection;
pub fn listen(endpoint: Endpoint) !LocalListener;
~~~

backend：

- Linux/macOS：Unix socket
- Windows：named pipe

首期 Windows 关闭 daemon 时，CLI 已有连接失败后本地执行的 fallback，应保留这一行为并加入测试。

---

## 14. installer 与 release 改造

### 14.1 立即修正

`tools/install.sh`：

~~~text
https://github.com/layola13/sci/releases
~~~

`tools/install.ps1` 使用同一 base URL。

archive 和 sidecar 命名必须一致：

~~~text
sa-linux-x86_64.tar.gz
sa-linux-x86_64.tar.gz.sha256
sa-macos-aarch64.tar.gz
sa-macos-aarch64.tar.gz.sha256
sa-windows-x86_64.zip
sa-windows-x86_64.zip.sha256
~~~

### 14.2 workflow 修正

release job 应：

1. 下载所有成功的 matrix artifacts，而不是指定 `linux-x86_64`。
2. 发布 `*.tar.gz` 和 `*.zip`。
3. 发布每个 archive 的 `.sha256`。
4. 合并生成 `sha256sums.txt`。
5. 对必选 target 使用 `allow_failure=false`。
6. 在创建 release 前运行 archive 内容 smoke。

### 14.3 host-native packaging

matrix runner 各自只构建自己：

| artifact | runner |
| --- | --- |
| linux-x86_64 | Ubuntu x86_64 |
| linux-aarch64 | Ubuntu ARM64 |
| macos-x86_64 | macOS Intel |
| macos-aarch64 | macOS Apple Silicon |
| windows-x86_64 | Windows x86_64 |

Windows ARM64 在有稳定 runner 和 runtime 后再启用，不要一开始扩大矩阵。

`tools/release.sh` 可以保留 archive layout 逻辑，但不再承担“一个 Linux runner 交叉编译所有宿主”的职责。

### 14.4 installer 依赖检查

方向 A 的非自包含发行至少检查：

- `sa`/ `sa.exe` 自身需要的 LLVM 动态库是否可加载。
- `zig version` 是否为 0.14.x。
- `SA_STD_DIR` payload 是否完整。
- archive checksum 是否验证成功。

缺少依赖时输出具体安装命令或文档链接，不能安装成功后第一次运行才报 loader error。

### 14.5 平台签名

它们不是基础编译阻塞项，但正式对外发布前需要：

- macOS codesign + notarization，避免 Gatekeeper 阻断下载产物。
- Windows Authenticode，降低 SmartScreen 和企业终端拦截。

签名密钥只存在 release environment，不进入普通 PR workflow。

---

## 15. CI 矩阵与验收测试

### 15.1 PR CI

| Job | 必跑内容 |
| --- | --- |
| Linux x86_64 | 完整现有 CI + Linux runtime |
| macOS aarch64 | portable + Darwin runtime + build/run smoke |
| macOS x86_64 | compile/build smoke，完整测试可按成本调整 |
| Windows x86_64 | portable + Windows runtime + build/run smoke |
| Linux cross-typecheck | macOS/Windows `-fno-emit-bin`，用于尽早发现无条件 import |

交叉 typecheck 是补充，不替代原生 runner。只有原生 runner 能验证动态库加载、系统 linker、进程、socket、终端和生成程序。

### 15.2 ABI gate

新增提交到仓库的 v1 symbol baseline，例如：

~~~text
tests/abi/sa_std_symbols_v1.txt
~~~

每个平台从静态/动态 runtime 提取 exports 并比较：

- 旧符号不得消失。
- 新符号必须显式评审。
- unsupported backend 也必须保留需要的旧符号。
- C struct size/alignment 在 ABI 允许的平台间一致。

工具可分别使用 `nm`、`otool/nm`、`dumpbin /exports` 或 LLVM 等价工具。

### 15.3 基础 runtime contract

同一组跨平台 contract tests：

- handle 分配、复用、double close
- file read/write/seek
- directory iteration
- portable metadata
- process stdout/stderr/exit code
- TCP loopback
- UDP loopback
- DNS localhost
- environment get/set/unset
- wall/monotonic time
- thread spawn/join
- dynamic library open/symbol/close

平台测试只补差异，不复制全部 contract。

### 15.4 unsupported contract

对每个平台显式断言：

- 返回 `SA_STD_ERR_UNSUPPORTED`
- out 参数保持安全零值
- 不泄漏 handle
- `last_error` 与返回码一致
- 不发生 panic、unreachable 或错误类型截断

这类测试对 Windows 尤其重要，因为很多旧接口没有 Windows 等价物。

### 15.5 端到端 smoke

每个平台至少执行：

~~~text
sa version
sa check demos/<portable>.sa
sa build-exe demos/<portable>.sa -o <native-output>
<native-output>
sa build-wasm demos/<portable>.sa -o app.wasm
sa plugin ... smoke
~~~

还应验证：

- 生成程序能找到 runtime 依赖。
- 路径中含空格和非 ASCII 字符。
- 临时目录和 HOME/USERPROFILE 正常。
- release archive 解压到非默认目录仍能运行。

### 15.6 构建洁净度

CI 在普通 build 后检查：

~~~sh
git diff --exit-code -- artifacts/sa_std
~~~

目标是防止 `build.zig` 再次把 host/target archive 写回源码树。

---

## 16. 分阶段交付计划

### Phase 0：锁定契约与诊断

目标：在改 runtime 前建立防回归门。

- 保存 ABI symbol baseline。
- 加三目标 typecheck。
- 把测试分成 portable/Linux-only。
- 修正 installer release URL 和 checksum artifact。
- 文档化 capability matrix。

退出条件：Linux 全绿，macOS/Windows 失败点稳定且可归类。

### Phase 1：宿主层公共修复

目标：解除不必要的 Unix 假设。

- fetch 改 `Child.run`。
- resolver 改 owned file bytes。
- path list 改 `std.fs.path.delimiter`。
- plugin 后缀和 target key 平台化。
- linker rpath 按宿主选择。
- LLVM discovery 统一。
- 移除默认 source artifact 回写。

这些改动应该先在 Linux 落地并保证行为不变。

退出条件：Windows CLI typecheck 不再停在 package 层；macOS host compiler 可原生链接。

### Phase 2：macOS MVP

目标：用 POSIX 共用层验证架构。

- conditional netx backend。
- Darwin pthread shim。
- Darwin metadata。
- process waitpid fallback。
- socket option/Unix socket 差异。
- dylib plugin。
- macOS build/run/runtime contract。

退出条件：macOS 达到 L2，并且 Linux runtime 回归无退化。

### Phase 3：内部 typed resource

目标：为 Windows 清除万能 fd。

- Resource union 原生类型化。
- read/write/socket/terminal helper 分离。
- ProcessHandle 进入 OS backend。
- raw fd API 与 generic handle API 分离。
- generic thread 改 `std.Thread` 或独立 backend。

这一步改动风险最高，应拆成小提交，每次只迁移一个导出族。

退出条件：Linux/macOS contract 全绿，`handleToFd` 不再是 generic I/O 的中心。

### Phase 4：Windows L0-L2

目标：`sa.exe` 可生成并运行基础 SA 程序。

- Windows fs/metadata backend。
- Windows process backend。
- Winsock TCP/UDP backend。
- Windows Console backend。
- DLL loader/plugin。
- PowerShell installer。
- unsupported contract。

退出条件：Windows x86_64 原生 CI 全绿，release archive 可在干净 VM 安装并编译 Hello World。

### Phase 5：生态与发行硬化

- Windows named-pipe daemon。
- macOS notarization。
- Windows Authenticode。
- 自包含 LLVM/Zig 发行决策。
- package manager 安装渠道。
- 外部插件 target matrix。

### Phase 6：高级网络

只有基础平台稳定后再评估：

- macOS kqueue backend。
- Windows IOCP backend。
- 中立的 v2 async API。
- Windows TLS server/DTLS socket-handle ABI。

该阶段不应反向阻塞 L0-L3。

---

## 17. 逐文件最小改动清单

| 文件 | 最小改动 |
| --- | --- |
| `build.zig` | LLVM discovery、target shim、平台测试、停止 source archive 回写 |
| `src/driver/zigcc.zig` | host rpath、Zig version/availability、Windows 参数 |
| `src/pkg/fetch.zig` | fork/exec 改 Child.run；只读策略平台化 |
| `src/pkg/resolver.zig` | mmap 改 owned read 或 storage union |
| `src/plugins.zig` | delimiter、suffix、target key、禁止错误 fallback |
| `src/daemon_client.zig` | transport interface；Windows 后续 named pipe |
| `src/cli.zig` | daemon listener backend；runtime archive 定位 |
| `src/runtime/sa_std.zig` | conditional imports、typed Resource、OS backend calls |
| `src/runtime/sa_pthread_host.c` | 仅 Linux |
| 新增 Darwin pthread shim | dlsym-only 或迁移到 std.Thread |
| `src/runtime/sa_net_uring.zig` | 保持 Linux backend；逐步拆出纯协议 helper |
| 新增 unsupported netx backend | 非 Linux 保留 ABI 并返回 unsupported |
| `src/runtime/sa_http2.zig` | 动态库 candidate 按平台 |
| `src/runtime/sa_tls_server.zig` | macOS candidate；Windows 首期 unsupported |
| `src/runtime/sa_dtls.zig` | 同上 |
| `src/runtime/sa_quic.zig` | candidate 与 capability 结果平台化 |
| `tools/release.sh` | host-native 单 target packaging |
| `tools/install.sh` | 正确 URL、依赖检查、sidecar checksum |
| `tools/install.ps1` | 正确 URL、依赖检查、Windows archive smoke |
| `.github/workflows/release.yml` | 原生 matrix、全 artifact 发布、zip/sidecar |

不需要重写 flattener、Referee、layout、SAB、JSON、fmt 或大部分标准库算法。

---

## 18. 风险矩阵

| 风险 | 严重度 | 触发方式 | 缓解 |
| --- | :---: | --- | --- |
| Linux runtime 回归 | 高 | 抽取 OS backend 时改变 fd/process/socket 行为 | 先建 ABI + runtime contract，逐导出族迁移 |
| Windows HANDLE/SOCKET 截断 | 高 | 继续 cast 到 `i32` | typed Resource，禁止 generic fd |
| unsupported 被伪装为成功 | 高 | compatibility shim 返回假 handle/OK | unsupported contract + capability 一致性 |
| LLVM 动态库版本不匹配 | 高 | 系统装了其他 LLVM major | 固定 14，统一 discovery，启动诊断 |
| release 不能在干净机器运行 | 高 | 构建机已有 LLVM/Zig，用户机器没有 | clean VM installer test，明确依赖或捆绑 |
| plugin 载入错误平台 artifact | 高 | fallback 到 manifest 第一项 | target key 精确匹配，无 fallback |
| Windows package cache 可被修改 | 中高 | read-only attribute 不等价 ACL | hash recheck，后续 ACL |
| macOS/Windows 路径编码 | 中高 | 非 ASCII、长路径、盘符 | UTF-8 ABI，std.fs 优先，专门测试 |
| process 语义被错误统一 | 中 | signal/process group/exit status 差异 | basic 与 advanced capability 分层 |
| 高级 Reactor 抽象过早固化 | 中高 | 用最低公共接口统一三种模型 | Linux backend 保留，v2 延后 |
| 构建污染源码树 | 中 | 默认 copy 到 artifacts | 显式 sync step + CI clean check |
| 外部插件未同步移植 | 中 | sci 支持 DLL，但插件只有 .so | 插件仓库独立 target matrix |

---

## 19. 必须避免的实现方式

1. **不要复制 11K 行 runtime。** 三份文件会立刻产生安全修复和 ABI 漂移。
2. **不要继续扩大 `handleToFd`。** Windows 的正确模型不是“更聪明的 cast”。
3. **不要重命名现有 ABI 来获得表面整洁。** 新语义使用 v2 新符号。
4. **不要让非 Linux stub 返回假成功。** unsupported 比静默错误更安全。
5. **不要让一个 Linux release job 链接其他宿主 LLVM。** 用原生 runner。
6. **不要把 IOCP/kqueue 当成 epoll/io_uring 的简单替身。**
7. **不要在移植同时升级 Zig 和 LLVM major。**
8. **不要把“能 typecheck”写成“平台已支持”。** 必须原生 build/run/runtime/install。
9. **不要通过取 manifest 第一项掩盖 target 缺失。**
10. **不要把 Windows read-only attribute 描述成 POSIX ACL 等价物。**

---

## 20. 最终验收标准

一个平台可以标记为 supported，必须同时满足：

- 原生 runner 构建 `sa` 和 `sa_std`。
- `sa version/check/build-exe/build-wasm` 通过。
- 生成的原生 Hello World 在同一 clean runner/VM 运行。
- L2 runtime contract 通过。
- ABI symbol baseline 通过。
- unsupported contract 通过。
- plugin target smoke 通过。
- release archive 内容和 checksum 通过。
- installer 在无源码目录的 clean 环境安装成功。
- 依赖缺失时给出可执行诊断。
- 普通 build 不修改 git tracked artifact。

只有全部满足后，才在 release matrix 中把该 target 的 `allow_failure` 设为 false 并对外宣称支持。

---

## 21. 推荐决策摘要

| 决策 | 推荐 |
| --- | --- |
| 首期输出模式 | host-native |
| 外部 C ABI | 保持 v1 不变 |
| 平台分派 | Zig compile-time import |
| macOS 基础 | POSIX 共用 + Darwin 差异 |
| Windows 基础 | typed HANDLE/SOCKET/process backend |
| Linux 高级能力 | 原样保留 |
| 非 Linux 高级能力 | 明确 unsupported |
| Reactor v2 | 基础平台完成后再设计 |
| Zig | 固定 0.14.1 |
| LLVM | 首期固定 14.x |
| 发行依赖 | 先方向 A，后评估自包含 |
| CI | 各平台原生 runner |
| 迁移策略 | 触达即抽取、按导出族提交 |

这是对当前代码改动最小、对 Linux 风险最低、又不会把 Windows 错误建模成 POSIX fd 的路线。

---

## 附录 A：复现命令

### A.1 当前 Linux 基线

~~~sh
zig version
./zig-out/bin/sa version
~/.sa/bin/sa version
file ./zig-out/bin/sa
ldd ./zig-out/bin/sa
~~~

### A.2 runtime 统计

~~~sh
wc -l src/runtime/sa_std.zig
rg -o 'std\.posix' src/runtime/sa_std.zig | wc -l
rg -o 'std\.os\.linux' src/runtime/sa_std.zig | wc -l
rg '^pub export fn ' src/runtime/sa_std.zig | wc -l
~~~

### A.3 macOS CLI typecheck

~~~sh
zig test -target x86_64-macos -fno-emit-bin -lc \
  --dep build_options \
  -Mroot=src/cli.zig \
  -Mbuild_options=.zig-cache/c/a8d5c0953d5930cca5da60679b6b8305/options.zig
~~~

### A.4 macOS runtime typecheck

~~~sh
zig test -target x86_64-macos -fno-emit-bin -lc \
  src/runtime/sa_std.zig

zig cc -target x86_64-macos -fsyntax-only \
  src/runtime/sa_pthread_host.c
~~~

### A.5 Windows host/package typecheck

~~~sh
zig test -target x86_64-windows-gnu -fno-emit-bin -lc \
  --dep build_options \
  -Mroot=src/cli.zig \
  -Mbuild_options=.zig-cache/c/a8d5c0953d5930cca5da60679b6b8305/options.zig

zig test -target x86_64-windows-gnu -fno-emit-bin \
  src/pkg/fetch.zig

zig test -target x86_64-windows-gnu -fno-emit-bin \
  src/pkg/resolver.zig
~~~

### A.6 Windows runtime typecheck

~~~sh
zig test -target x86_64-windows-gnu -fno-emit-bin -lc \
  src/runtime/sa_std.zig
~~~

这些命令用于发现无条件 import 和类型假设，不等价于原生平台链接/运行验证。

---

## 附录 B：关键源码位置

| 主题 | 位置 |
| --- | --- |
| LLVM Linux 默认值 | `build.zig:41-43` |
| runtime archive 回写源码 | `build.zig:90-92` |
| LLVM test 再次硬编码 | `build.zig:156-166` |
| CLI LLVM 链接 | `build.zig:221-234` |
| forced runtime imports | `src/runtime/sa_std.zig:9-15` |
| raw POSIX metadata | `src/runtime/sa_std.zig:205-209` |
| process pidfd model | `src/runtime/sa_std.zig:995-1026` |
| Resource union | `src/runtime/sa_std.zig:1029-1082` |
| pthread model | `src/runtime/sa_std.zig:1089-1259` |
| universal fd bottleneck | `src/runtime/sa_std.zig:1715-1733` |
| Linux process primitives | `src/runtime/sa_std.zig:1997+` |
| dynamic loader Linux gate | `src/runtime/sa_std.zig:6109-6168` |
| metadata fstatat/raw fields | `src/runtime/sa_std.zig:8099-8257` |
| GNU pthread shim | `src/runtime/sa_pthread_host.c:1-33` |
| Linux rpath | `src/driver/zigcc.zig:32-60` |
| package fork/exec | `src/pkg/fetch.zig:244-293` |
| package chmod | `src/pkg/fetch.zig:159-241` |
| package mmap | `src/pkg/resolver.zig:268-288` |
| plugin path delimiter | `src/plugins.zig:1170-1176` |
| plugin .so assumptions | `src/plugins.zig:1191`, `1477` |
| plugin artifact selection | `src/plugins.zig:2742-2752` |
| Unix-only daemon client | `src/daemon_client.zig:12-22` |
| Unix-only daemon server | `src/cli.zig:3472-3500` |
| disabled release targets | `.github/workflows/release.yml:41-73` |
| release only downloads Linux | `.github/workflows/release.yml:127-149` |
| incorrect shell installer URL | `tools/install.sh:321` |
| incorrect PowerShell URL | `tools/install.ps1:132` |

行号对应本文评估基线，后续修改后应以符号搜索为准。

---

## 附录 C：与其他文档的关系

- [Multi-Platform Architecture](./multi_platform_architecture.md) 保留长期 PAL/Reactor 愿景。
- 本文是基于当前代码和编译诊断的近期实施基线。
- 两者冲突时，近期迁移以本文的 ABI 保持、typed resource、host-native 和 capability 分层为准。
