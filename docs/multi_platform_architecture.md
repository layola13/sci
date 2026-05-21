# SA-ASM 全平台架构设计与 PAL 实施指南

## 1. 架构现状与痛点评估
SA-ASM 初期开发为了追求极致性能，将运行时的核心系统服务（System Services）和事件驱动基座（Reactor）深度绑定了 Linux 特性：
- 进程与路径处理依赖 `/proc/self/cmdline`。
- 网络引擎 `sa_net_uring` 完全基于 Linux 的 `io_uring`。
- 甚至底层的 `sa_std.h` 接口暴露了特定于 `epoll` 的结构体（如 `SaTermEpollEvent`）。

这导致当前版本无法在 Windows 和 macOS 上原生运行。为了真正实现“一次编写，到处链接”的全平台愿景，我们正在全面推行 **PAL (Platform Abstraction Layer)** 架构。

## 2. 架构重构蓝图：PAL (平台抽象层)

我们必须将“面向 Linux 编程”转变为“面向抽象接口编程”。

### 2.1 引入 PAL 调度中枢
在 `src/runtime/` 下建立 PAL 目录：
```text
src/runtime/
├── pal.zig          (核心中枢，使用 @import("builtin").os.tag 动态路由)
├── pal_linux.zig    (基于 io_uring, epoll, procfs)
├── pal_macos.zig    (基于 kqueue, sysctl, mach ports)
└── pal_windows.zig  (基于 IOCP, GetCommandLineW)
```

在 `pal.zig` 中：
```zig
const builtin = @import("builtin");

pub const sys = switch (builtin.os.tag) {
    .linux => @import("pal_linux.zig"),
    .windows => @import("pal_windows.zig"),
    .macos => @import("pal_macos.zig"),
    else => @compileError("Unsupported OS"),
};
```
在 SA-ASM 的核心代码中，一律调用 `sys.get_executable_path()`，严禁直接调用操作系统的裸接口。

## 3. 核心驱动抽象：跨平台 Reactor 模型

要把极速网络基座 `sa_net_uring` 泛化，我们需要定义一套标准的 C-ABI 接口，让所有平台的轮询机制都能对接。

### 3.1 C-ABI 统一接口 (消灭平台特定名词)
废弃 `sa_term_epoll_wait` 这种带有强烈 Linux 色彩的命名，改为 `event_loop`：

```c
// sa_std.h - 统一的跨平台 C ABI
typedef struct {
    uint64_t user_data;
    uint32_t flags;
    int32_t res;
} SaEvent;

// 无论底层是 io_uring, IOCP 还是 kqueue，外部只看这套接口
int32_t sa_event_loop_create(void** out_loop);
int32_t sa_event_loop_submit(void* loop, SaEvent* ev);
int32_t sa_event_loop_wait(void* loop, SaEvent* out_events, uint32_t max_events, int32_t timeout_ms);
```

### 3.2 平台对接实现示例

**Windows (IOCP / I/O Completion Ports)**：
Windows 上没有任何类似 `epoll` 的机制，但它天生拥有支持异步 I/O 的 IOCP，且在最新版本中加入了类似 `io_uring` 的 `IoRing`。我们将优先对接 IOCP。
```zig
// pal_windows.zig
const win = std.os.windows;

pub fn event_loop_create(out_loop: *?*anyopaque) i32 {
    const handle = win.kernel32.CreateIoCompletionPort(win.INVALID_HANDLE_VALUE, null, 0, 0);
    if (handle == null) return -1;
    out_loop.* = @ptrCast(handle);
    return 0;
}

// 通过 GetQueuedCompletionStatus 获取事件
```

**macOS (kqueue)**：
macOS 依靠 `kqueue`，它属于事件通知机制。
```zig
// pal_macos.zig
const posix = std.posix;

pub fn event_loop_create(out_loop: *?*anyopaque) i32 {
    const kq = posix.kqueue() catch return -1;
    // 分配一个堆结构来保存 fd 并转换为指针
    out_loop.* = @ptrFromInt(@as(usize, @intCast(kq)));
    return 0;
}

// 通过 kevent 获取事件
```

## 4. 构建系统的动态配置

我们需要在 `build.zig` 中，根据构建目标（Target）的不同，只编译对应的文件：

```zig
// build.zig
const os_tag = target.result.os.tag;

var pal_file: []const u8 = "";
if (os_tag == .linux) {
    pal_file = "src/runtime/pal_linux.zig";
} else if (os_tag == .windows) {
    pal_file = "src/runtime/pal_windows.zig";
} else if (os_tag == .macos) {
    pal_file = "src/runtime/pal_macos.zig";
}

// 仅把当前平台的代码打进静态库
sa_std_module.addExtraSourceFile(.{ .file = b.path(pal_file) });
```

## 5. 结论与排期
当前我们虽然带有明显的“Linux 优先”特征，但底层引擎 `src/runtime` 和上层编译器完全是解耦的。只要完成了 `pal.zig` 接口层的设计（大约需要替换 15 个底层的 OS API 调用），SA 就可以无缝实现全平台原生运行，无需为跨平台妥协任何运行效率。
