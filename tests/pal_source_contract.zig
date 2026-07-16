const std = @import("std");

fn readSource(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, 8 * 1024 * 1024);
}

fn expectContains(source: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, source, needle) != null);
}

fn expectNotContains(source: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, source, needle) == null);
}

test "PAL selector routes supported OS targets to platform backends" {
    const allocator = std.testing.allocator;
    const selector = try readSource(allocator, "src/runtime/pal.zig");
    defer allocator.free(selector);

    try expectContains(selector, "const builtin = @import(\"builtin\")");
    try expectContains(selector, "pub const sys = switch (builtin.os.tag)");
    try expectContains(selector, ".linux => @import(\"pal_linux.zig\")");
    try expectContains(selector, ".macos => @import(\"pal_macos.zig\")");
    try expectContains(selector, ".windows => @import(\"pal_windows.zig\")");
    try expectContains(selector, "else => @compileError(\"Unsupported OS\")");
    try expectContains(selector, "pub const SaEvent = sys.SaEvent");
    try expectContains(selector, "PAL selector event loop drains submitted events through sys");
    try expectContains(selector, "PAL selector event loop wait blocks until submit wakes sys backend");
    try expectContains(selector, "sys.event_loop_create");
    try expectContains(selector, "sys.event_loop_wait(loop, &out, 1, 2000)");
}

test "runtime system entry points route executable path and args through PAL" {
    const allocator = std.testing.allocator;
    const root = try readSource(allocator, "src/runtime/sa_std.zig");
    defer allocator.free(root);
    const sources = [_][]const u8{
        "src/runtime/native_sys.zig",
        "src/runtime/sa_std_posix.zig",
        "src/runtime/sa_std_windows.zig",
    };

    try expectContains(root, "pub usingnamespace switch (builtin.os.tag)");
    try expectContains(root, ".windows => @import(\"sa_std_windows.zig\")");
    try expectContains(root, "else => @import(\"sa_std_posix.zig\")");
    try expectNotContains(root, "@import(\"pal_linux.zig\")");
    try expectNotContains(root, "@import(\"pal_macos.zig\")");
    try expectNotContains(root, "@import(\"pal_windows.zig\")");

    for (sources) |path| {
        const source = try readSource(allocator, path);
        defer allocator.free(source);
        try expectNotContains(source, "/proc/self/cmdline");
        try expectNotContains(source, "std.fs.selfExePathAlloc");
        try expectNotContains(source, "std.process.argsAlloc");
        try expectNotContains(source, "@import(\"pal_linux.zig\")");
        try expectNotContains(source, "@import(\"pal_macos.zig\")");
        try expectNotContains(source, "@import(\"pal_windows.zig\")");
    }

    const native_sys = try readSource(allocator, "src/runtime/native_sys.zig");
    defer allocator.free(native_sys);
    try expectContains(native_sys, "@import(\"pal.zig\")");
    try expectContains(native_sys, "pal_sys.process_args_alloc");
    try expectContains(native_sys, "pal_sys.process_args_free");

    const posix = try readSource(allocator, "src/runtime/sa_std_posix.zig");
    defer allocator.free(posix);
    try expectContains(posix, "@import(\"pal.zig\")");
    try expectContains(posix, "pal_sys.get_executable_path");
    try expectContains(posix, "pal_sys.process_args_json_alloc");

    const windows = try readSource(allocator, "src/runtime/sa_std_windows.zig");
    defer allocator.free(windows);
    try expectContains(windows, "@import(\"pal.zig\")");
    try expectContains(windows, "pal_sys.get_executable_path");
    try expectContains(windows, "pal_sys.process_args_json_alloc");

    const windows_pal = try readSource(allocator, "src/runtime/pal_windows.zig");
    defer allocator.free(windows_pal);
    try expectContains(windows_pal, "GetModuleFileNameW");
    try expectContains(windows_pal, "GetCommandLineW");
    try expectContains(windows_pal, "std.process.ArgIteratorWindows");
    try expectNotContains(windows_pal, "std.fs.selfExePathAlloc");
    try expectNotContains(windows_pal, "std.process.argsAlloc");

    const linux_pal = try readSource(allocator, "src/runtime/pal_linux.zig");
    defer allocator.free(linux_pal);
    try expectContains(linux_pal, "/proc/self/exe");
    try expectNotContains(linux_pal, "std.fs.selfExePathAlloc");

    const macos_pal = try readSource(allocator, "src/runtime/pal_macos.zig");
    defer allocator.free(macos_pal);
    try expectContains(macos_pal, "_NSGetExecutablePath");
    try expectContains(macos_pal, "realpathZ");
    try expectNotContains(macos_pal, "std.fs.selfExePathAlloc");
}

test "platform event loop syscalls stay behind PAL backends" {
    const allocator = std.testing.allocator;
    const core_sources = [_][]const u8{
        "src/runtime/sa_std_posix.zig",
        "src/runtime/sa_std_windows.zig",
    };

    for (core_sources) |path| {
        const source = try readSource(allocator, path);
        defer allocator.free(source);
        try expectNotContains(source, "epoll_create1");
        try expectNotContains(source, "std.posix.epoll_ctl");
        try expectNotContains(source, "std.posix.epoll_wait");
        try expectNotContains(source, "std.posix.kqueue");
        try expectNotContains(source, "std.posix.kevent");
        try expectNotContains(source, "CreateIoCompletionPort");
        try expectNotContains(source, "PostQueuedCompletionStatus");
        try expectNotContains(source, "GetQueuedCompletionStatus");
    }

    const linux = try readSource(allocator, "src/runtime/pal_linux.zig");
    defer allocator.free(linux);
    try expectContains(linux, "epoll_create1");
    try expectContains(linux, "eventfd");

    const macos = try readSource(allocator, "src/runtime/pal_macos.zig");
    defer allocator.free(macos);
    try expectContains(macos, "kqueue");
    try expectContains(macos, "kevent");
    try expectContains(macos, "PAL event loop wait blocks until submit wakes the kqueue backend");

    const windows = try readSource(allocator, "src/runtime/pal_windows.zig");
    defer allocator.free(windows);
    try expectContains(windows, "CreateIoCompletionPort");
    try expectContains(windows, "PostQueuedCompletionStatus");
    try expectContains(windows, "GetQueuedCompletionStatus");
    try expectContains(windows, "PAL event loop wait blocks until submit wakes the IOCP backend");
}

test "build gates PAL backends by target" {
    const allocator = std.testing.allocator;
    const build = try readSource(allocator, "build.zig");
    defer allocator.free(build);

    try expectContains(build, "fn palFileForOsTag");
    try expectContains(build, ".linux => \"src/runtime/pal_linux.zig\"");
    try expectContains(build, ".macos => \"src/runtime/pal_macos.zig\"");
    try expectContains(build, ".windows => \"src/runtime/pal_windows.zig\"");
    try expectContains(build, "const pal_typecheck_step = b.step(\"pal-typecheck\"");
    try expectContains(build, ".{ .triple = \"x86_64-linux-gnu\", .file = palFileForOsTag(.linux).? }");
    try expectContains(build, ".{ .triple = \"x86_64-macos\", .file = palFileForOsTag(.macos).? }");
    try expectContains(build, ".{ .triple = \"x86_64-windows-gnu\", .file = palFileForOsTag(.windows).? }");
    try expectContains(build, "const pal_selector_typecheck = b.addSystemCommand");
    try expectContains(build, "\"src/runtime/pal.zig\"");
    try expectContains(build, "pal_typecheck_step.dependOn(&pal_selector_typecheck.step)");
    try expectContains(build, "const runtime_pal_module = b.createModule");
    try expectContains(build, ".root_source_file = b.path(\"src/runtime/pal.zig\")");
    try expectContains(build, "b.step(\"test-runtime-pal\"");
    try expectContains(build, "test-runtime-pal requires a native Linux, macOS, or Windows host and target");
    try expectContains(build, "portability_check_step.dependOn(pal_typecheck_step)");
    try expectContains(build, "portability_check_step.dependOn(pal_source_contract_step)");
    try expectContains(build, "const netx_backend_source = if (std.mem.indexOf(u8, portable_runtime_target, \"macos\") != null)");
    try expectContains(build, "\"src/runtime/sa_netx_macos.zig\"");
    try expectContains(build, "\"src/runtime/sa_netx_windows.zig\"");
    try expectContains(build, "portable_runtime_typecheck.dependOn(&netx_backend_typecheck.step)");
}

test "NetX runtime entry points route through the platform selector" {
    const allocator = std.testing.allocator;

    const posix = try readSource(allocator, "src/runtime/sa_std_posix.zig");
    defer allocator.free(posix);
    try expectContains(posix, "@import(\"sa_netx.zig\")");
    try expectNotContains(posix, "@import(\"sa_net_uring.zig\")");
    try expectNotContains(posix, "@import(\"sa_netx_unsupported.zig\")");

    const windows = try readSource(allocator, "src/runtime/sa_std_windows.zig");
    defer allocator.free(windows);
    try expectContains(windows, "@import(\"sa_netx.zig\")");
    try expectNotContains(windows, "@import(\"sa_net_uring.zig\")");
    try expectNotContains(windows, "@import(\"sa_netx_unsupported.zig\")");

    const selector = try readSource(allocator, "src/runtime/sa_netx.zig");
    defer allocator.free(selector);
    try expectContains(selector, "@import(\"sa_netx_backend_contract.zig\")");
    try expectContains(selector, "backend_contract.assertBackend(backend)");
    try expectContains(selector, ".linux => @import(\"sa_net_uring.zig\")");
    try expectContains(selector, ".macos => @import(\"sa_netx_macos.zig\")");
    try expectContains(selector, ".windows => @import(\"sa_netx_windows.zig\")");
    try expectContains(selector, "else => @compileError(\"Unsupported NetX target OS\")");
    try expectNotContains(selector, "else => @import(\"sa_netx_portable.zig\")");
    try expectContains(selector, "pub const BackendTraits = struct");
    try expectContains(selector, "pub const supports_reactor = backend.supports_native_reactor");
    try expectNotContains(selector, "pub const supports_reactor = builtin.os.tag == .linux");
    try expectContains(selector, "pub const backend_traits = switch (builtin.os.tag)");
    try expectContains(selector, ".reactor = backend.platform_reactor");
    try expectContains(selector, ".native_reactor = backend.supports_native_reactor");

    const contract = try readSource(allocator, "src/runtime/sa_netx_backend_contract.zig");
    defer allocator.free(contract);
    try expectContains(contract, "backend.backend_name");
    try expectContains(contract, "backend.platform_reactor");
    try expectContains(contract, "backend.supports_native_reactor");
    try expectContains(contract, "backend.sa_netx_init");
    try expectContains(contract, "backend.sa_std_ws_frame_build_unmasked");

    const linux = try readSource(allocator, "src/runtime/sa_net_uring.zig");
    defer allocator.free(linux);
    try expectContains(linux, "backend_name = \"io_uring\"");
    try expectContains(linux, "platform_reactor = \"io_uring\"");
    try expectContains(linux, "supports_native_reactor = true");

    const macos = try readSource(allocator, "src/runtime/sa_netx_macos.zig");
    defer allocator.free(macos);
    try expectContains(macos, "@import(\"sa_netx_kqueue.zig\")");
    try expectContains(macos, "@import(\"pal_macos.zig\")");
    try expectContains(macos, "core.backend_name");
    try expectContains(macos, "core.platform_reactor");
    try expectContains(macos, "core.supports_native_reactor");

    const kqueue = try readSource(allocator, "src/runtime/sa_netx_kqueue.zig");
    defer allocator.free(kqueue);
    try expectContains(kqueue, "backend_name = \"kqueue\"");
    try expectContains(kqueue, "platform_reactor = \"kqueue\"");
    try expectContains(kqueue, "supports_native_reactor = true");
    try expectContains(kqueue, "posix.kqueue");
    try expectContains(kqueue, "std.c.EVFILT.READ");
    try expectContains(kqueue, "std.c.EVFILT.WRITE");
    try expectContains(kqueue, "posix.accept");
    try expectContains(kqueue, "posix.recv");
    try expectContains(kqueue, "posix.send");
    try expectNotContains(kqueue, "Thread.spawn(.{}, connectionLoop");

    const windows_netx = try readSource(allocator, "src/runtime/sa_netx_windows.zig");
    defer allocator.free(windows_netx);
    try expectContains(windows_netx, "@import(\"sa_netx_iocp.zig\")");
    try expectContains(windows_netx, "@import(\"pal_windows.zig\")");
    try expectContains(windows_netx, "core.backend_name");
    try expectContains(windows_netx, "core.platform_reactor");
    try expectContains(windows_netx, "core.supports_native_reactor");

    const iocp = try readSource(allocator, "src/runtime/sa_netx_iocp.zig");
    defer allocator.free(iocp);
    try expectContains(iocp, "backend_name = \"iocp\"");
    try expectContains(iocp, "platform_reactor = \"iocp\"");
    try expectContains(iocp, "supports_native_reactor = true");
    try expectContains(iocp, "windows.CreateIoCompletionPort");
    try expectContains(iocp, "windows.GetQueuedCompletionStatus");
    try expectContains(iocp, "ws.AcceptEx");
    try expectContains(iocp, "ws.WSARecv");
    try expectContains(iocp, "ws.WSASend");
    try expectNotContains(iocp, "Thread.spawn(.{}, connectionLoop");

    const portable = try readSource(allocator, "src/runtime/sa_netx_portable.zig");
    defer allocator.free(portable);
    try expectContains(portable, "@import(\"pal.zig\")");
    try expectContains(portable, "pal_sys.event_loop_create");
    try expectContains(portable, "pal_sys.event_loop_submit");
    try expectContains(portable, "pal_sys.event_loop_wait");
    try expectContains(portable, "pal_sys.event_loop_close");
    try expectContains(portable, "pal.SaEvent");
    try expectContains(portable, "reactor_wait_forever_ms");
    try expectNotContains(portable, "reactor_wait_timeout_ms");
}

test "public header exposes the platform neutral event and NetX ABI" {
    const allocator = std.testing.allocator;
    const header = try readSource(allocator, "src/runtime/sa_std.h");
    defer allocator.free(header);
    const runtime_basic = try readSource(allocator, "tests/runtime_basic_contract.c");
    defer allocator.free(runtime_basic);

    try expectContains(header, "typedef struct SaEvent");
    try expectContains(header, "int32_t sa_event_loop_create(void **out_loop)");
    try expectContains(header, "int32_t sa_event_loop_submit(void *loop, const SaEvent *ev)");
    try expectContains(header, "int32_t sa_event_loop_wait(void *loop, SaEvent *out_events");
    try expectContains(header, "int32_t sa_event_loop_close(void *loop)");
    try expectContains(header, "Linux uses io_uring, macOS uses kqueue, and");
    try expectContains(header, "Windows uses IOCP behind this stable ticket surface");
    try expectNotContains(header, "native reactor backends are implemented");
    try expectContains(header, "typedef struct SaNetxTicket");
    try expectContains(header, "int32_t sa_netx_init(uint64_t slot_capacity, uint32_t reactor_count)");
    try expectContains(header, "int32_t sa_netx_recv_ticket(uint32_t reactor_id, SaNetxTicket *out_ticket)");

    try expectContains(runtime_basic, "event_loop_wait_worker");
    try expectContains(runtime_basic, "sa_event_loop_wait(state->event_loop, &state->observed, 1, 2000)");
    try expectContains(runtime_basic, "pthread_spawn((const uint8_t *)(uintptr_t)&event_loop_wait_worker");
    try expectContains(runtime_basic, "sa_event_loop_submit(event_loop, &delayed)");
    try expectContains(runtime_basic, "pthread_join(thread_handle, (uint8_t *)&wait_thread_result)");
}
