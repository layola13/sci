# SA-ASM 全平台架构设计评估方案

本文档评估了 SA-ASM 当前架构对多平台（Windows, macOS, Linux）的支持现状，并提出了改进建议。

## 1. 当前现状评估

目前 SA-ASM 的运行时（Runtime）深度绑定了 Linux 特性，主要体现在以下几个方面：

### 1.1 系统服务层 (System Services)
- **问题**：`src/runtime/native_sys.zig` 依赖 `/proc/self/cmdline` 来获取进程参数，这在 Windows 和 macOS 上不可用。
- **现状**：仅能在支持 procfs 的类 Unix 系统运行。

### 1.2 事件驱动基座 (Event Loop / Reactor)
- **问题**：`src/runtime/sa_net_uring.zig` 核心实现完全基于 Linux 的 `io_uring`。
- **问题**：`sa_std.h` 接口中直接暴露了 `epoll` 相关的结构（如 `SaTermEpollEvent`）和函数。
- **现状**：无法在 Windows (IOCP) 和 macOS (kqueue) 上编译或运行。

### 1.3 核心标准库 (sa_std)
- **问题**：部分网络地址处理逻辑直接使用了 `std.posix` 中的特定常量，虽然 Zig 提供了跨平台包装，但在某些边缘情况（如 Unix Domain Socket）下仍存在差异。

## 2. 架构改进建议

为了实现全平台支持，建议将架构从“面向 Linux 实现”转变为“面向平台抽象接口”。

### 2.1 引入 PAL (Platform Abstraction Layer)
建议在 `src/runtime/` 下建立 PAL 结构：
- `pal.zig`: 核心分发层，通过 `@import("builtin").os.tag` 调度。
- `pal/linux.zig`: 实现 Linux 特有逻辑。
- `pal/windows.zig`: 使用 Win32 API (如 `GetCommandLineW`) 实现。
- `pal/macos.zig`: 使用 `sysctl` 实现。

### 2.2 Reactor 模式抽象
将 `sa_net_uring` 从核心逻辑中剥离，定义通用的 `Reactor` 接口：
```zig
pub const Reactor = struct {
    // 定义统一的 init, deinit, poll, send, recv 等接口
};
```
针对不同平台提供不同驱动：
- **Linux**: `reactor_uring.zig`
- **Windows**: `reactor_iocp.zig` (待开发)
- **macOS**: `reactor_kqueue.zig` (待开发)

### 2.3 API 泛化
重构 `sa_std.h`，删除 `epoll` 字样，改为更通用的 `event_loop`：
- `sa_term_epoll_create` -> `sa_event_loop_create`
- `sa_term_epoll_wait` -> `sa_event_loop_wait`

## 3. 构建系统调整

在 `build.zig` 中，根据 `target.os.tag` 动态选择参与编译的文件：
```zig
const os_tag = target.result.os.tag;
if (os_tag == .linux) {
    sa_std_module.addExtraSourceFile(.{ .file = b.path("src/runtime/pal/linux.zig") });
} else if (os_tag == .windows) {
    sa_std_module.addExtraSourceFile(.{ .file = b.path("src/runtime/pal/windows.zig") });
}
```

## 4. 结论
当前架构具备良好的模块化基础，但“Linux 优先”的倾向非常明显。通过引入 PAL 和泛化 Reactor 接口，可以在不牺牲 Linux 性能的前提下，实现对 Windows 和 macOS 的原生支持。
