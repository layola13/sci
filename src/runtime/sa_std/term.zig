const std = @import("std");
const sa_std = @import("../sa_std.zig");
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const SaTermEpollEvent = @import("../sa_std.zig").SaTermEpollEvent;
const SaTermWinsize = @import("../sa_std.zig").SaTermWinsize;
const applyRawMode = @import("../sa_std.zig").applyRawMode;
const builtin = @import("../sa_std.zig").builtin;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const handleToFd = @import("../sa_std.zig").handleToFd;
const is_linux = @import("../sa_std.zig").is_linux;
const is_wasm = @import("../sa_std.zig").is_wasm;
const lenAsUsize = @import("../sa_std.zig").lenAsUsize;
const libc = @import("../sa_std.zig").libc;
const lxClose = @import("../sa_std.zig").lxClose;
const lxEpollCreate1 = @import("../sa_std.zig").lxEpollCreate1;
const lxEpollCtl = @import("../sa_std.zig").lxEpollCtl;
const lxEpollWait = @import("../sa_std.zig").lxEpollWait;
const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;
const sa_std_close = @import("../sa_std.zig").sa_std_close;

pub export fn sa_term_raw_enter(handle: u64, out_session: ?*u64) i32 {
    // WASI has no ttys (no tcgetattr/tcsetattr in wasi-libc).
    if (is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const session_ptr = out_session orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    session_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();

    const fd = handleToFd(handle) catch |err| return finishErr(err);
    const original = std.posix.tcgetattr(fd) catch |err| return finishErr(err);
    var raw = original;
    applyRawMode(&raw);
    std.posix.tcsetattr(fd, .FLUSH, raw) catch |err| return finishErr(err);

    const session = registerResourceLocked(.{ .terminal_session = .{ .fd = fd, .saved = original } }) catch |err| {
        std.posix.tcsetattr(fd, .FLUSH, original) catch |restore_err| return finishErr(restore_err);
        return finishErr(err);
    };
    session_ptr.* = session;
    return finish(SA_STD_OK);
}

pub export fn sa_term_raw_leave(session_handle: u64) i32 {
    return sa_std_close(session_handle);
}

pub export fn sa_term_winsize(handle: u64, out_size: ?*SaTermWinsize) i32 {
    const size_ptr = out_size orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    size_ptr.* = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();

    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const fd = handleToFd(handle) catch |err| return finishErr(err);
    const WinSize = extern struct { row: u16, col: u16, xpixel: u16, ypixel: u16 };
    var wsz: WinSize = undefined;
    while (true) {
        const e: std.posix.E = if (comptime is_linux)
            std.os.linux.errno(std.os.linux.ioctl(fd, std.os.linux.T.IOCGWINSZ, @intFromPtr(&wsz)))
        else
            std.posix.errno(libc.ioctl(fd, 0x40087468, @as(*anyopaque, @ptrCast(&wsz))));
        switch (e) {
            .SUCCESS => {
                size_ptr.* = .{
                    .row = wsz.row,
                    .col = wsz.col,
                    .xpixel = wsz.xpixel,
                    .ypixel = wsz.ypixel,
                };
                return finish(SA_STD_OK);
            },
            .INTR => continue,
            .BADF => return finish(SA_STD_ERR_INVALID_HANDLE),
            .NOTTY => return finish(SA_STD_ERR_UNSUPPORTED),
            else => return finish(SA_STD_ERR_IO),
        }
    }
}

pub export fn sa_term_epoll_create(flags: u32, out_handle: ?*u64) i32 {
    if (comptime builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_term_epoll_create_linux(flags, out_handle);
}

fn sa_term_epoll_create_linux(flags: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const cloexec_flag: u32 = @as(u32, @intCast(std.os.linux.EPOLL.CLOEXEC));
    if ((flags & ~cloexec_flag) != 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const fd = lxEpollCreate1(flags) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const handle = registerResourceLocked(.{ .owned_fd = .{ .fd = fd } }) catch |err| {
        lxClose(fd);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_term_epoll_ctl(epoll_handle: u64, op: u32, target_handle: u64, events: u32, data: u64) i32 {
    if (comptime builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_term_epoll_ctl_linux(epoll_handle, op, target_handle, events, data);
}

fn sa_term_epoll_ctl_linux(epoll_handle: u64, op: u32, target_handle: u64, events: u32, data: u64) i32 {
    if (op != std.os.linux.EPOLL.CTL_ADD and op != std.os.linux.EPOLL.CTL_MOD and op != std.os.linux.EPOLL.CTL_DEL) {
        return finish(SA_STD_ERR_INVALID_ARGUMENT);
    }
    if (op != std.os.linux.EPOLL.CTL_DEL and events == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();

    const epoll_fd = handleToFd(epoll_handle) catch |err| return finishErr(err);
    const target_fd = handleToFd(target_handle) catch |err| return finishErr(err);
    var event: std.os.linux.epoll_event = .{
        .events = events,
        .data = .{ .u64 = data },
    };
    const event_ptr = if (op == std.os.linux.EPOLL.CTL_DEL) null else &event;
    lxEpollCtl(epoll_fd, op, target_fd, event_ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_term_epoll_wait(epoll_handle: u64, out_events: ?[*]SaTermEpollEvent, max_events: u64, timeout_ms: i32, out_count: ?*u64) i32 {
    if (comptime builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_term_epoll_wait_linux(epoll_handle, out_events, max_events, timeout_ms, out_count);
}

fn sa_term_epoll_wait_linux(epoll_handle: u64, out_events: ?[*]SaTermEpollEvent, max_events: u64, timeout_ms: i32, out_count: ?*u64) i32 {
    const events_ptr = out_events orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const count_ptr = out_count orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    count_ptr.* = 0;
    const event_count = lenAsUsize(max_events) catch |err| return finishErr(err);
    if (event_count == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);

    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();

    const epoll_fd = handleToFd(epoll_handle) catch |err| return finishErr(err);
    const kernel_events = std.heap.page_allocator.alloc(std.os.linux.epoll_event, event_count) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(kernel_events);

    const ready = lxEpollWait(epoll_fd, kernel_events, timeout_ms);
    for (kernel_events[0..ready], 0..) |event, i| {
        events_ptr[i] = .{
            .events = event.events,
            .data = event.data.u64,
        };
    }
    count_ptr.* = @as(u64, @intCast(ready));
    return finish(SA_STD_OK);
}

pub export fn sa_term_epoll_close(handle: u64) i32 {
    if (comptime builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_term_epoll_close_linux(handle);
}

fn sa_term_epoll_close_linux(handle: u64) i32 {
    return sa_std_close(handle);
}
