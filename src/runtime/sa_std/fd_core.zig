const std = @import("std");
const sa_std = @import("../sa_std.zig");
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const SA_STD_STDERR = @import("../sa_std.zig").SA_STD_STDERR;
const SA_STD_STDIN = @import("../sa_std.zig").SA_STD_STDIN;
const SA_STD_STDOUT = @import("../sa_std.zig").SA_STD_STDOUT;
const SOCKT = @import("../sa_std.zig").SOCKT;
const SockAddrT = @import("../sa_std.zig").SockAddrT;
const SockLenT = @import("../sa_std.zig").SockLenT;
const errnoToAny = @import("../sa_std.zig").errnoToAny;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const is_linux = @import("../sa_std.zig").is_linux;
const is_wasm = @import("../sa_std.zig").is_wasm;
const libc = @import("../sa_std.zig").libc;
const lxCheck = @import("../sa_std.zig").lxCheck;
const lxClose = @import("../sa_std.zig").lxClose;
const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;

fn socketFdFromHandle(handle: u64) !std.posix.fd_t {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    return try handleToFd(handle);
}

pub fn handleToFd(handle: u64) !std.posix.fd_t {
    return switch (handle) {
        SA_STD_STDIN => std.posix.STDIN_FILENO,
        SA_STD_STDOUT => std.posix.STDOUT_FILENO,
        SA_STD_STDERR => std.posix.STDERR_FILENO,
        else => {
            const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
            return switch (resource.*) {
                .file => |file| file.inner.handle,
                .tcp_stream => |stream| stream,
                .tcp_listener => |server| server.fd,
                .udp_socket => |fd| fd,
                .owned_fd => |fd| fd.fd,
                .terminal_session => |session| session.fd,
                else => error.InvalidHandle,
            };
        },
    };
}

fn libcFd(rc: c_int) !std.posix.fd_t {
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
    return @intCast(rc);
}

pub fn lxAccept(fd: std.posix.fd_t, addr: ?*SockAddrT, len: ?*SockLenT, flags: u32) !std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const rc = try lxCheck(std.os.linux.accept4(fd, addr, len, flags));
        return @as(std.posix.fd_t, @bitCast(@as(u32, @truncate(rc))));
    }
    const rc = libc.accept(fd, addr, @ptrCast(len));
    const new_fd = try libcFd(rc);
    if ((flags & SOCKT.CLOEXEC) != 0) {
        _ = libc.fcntl(new_fd, std.c.F.SETFD, @as(c_int, 1));
    }
    return new_fd;
}

pub fn lxDup(old: std.posix.fd_t) !std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const rc = try lxCheck(std.os.linux.dup(old));
        return @as(std.posix.fd_t, @bitCast(@as(u32, @truncate(rc))));
    }
    return try libcFd(libc.dup(old));
}

fn lxIsatty(fd: std.posix.fd_t) bool {
    if (comptime is_wasm) return false;
    _ = std.posix.tcgetattr(fd) catch return false;
    return true;
}

pub export fn sa_std_fd_as_raw(handle: u64, out_fd: ?*i32) i32 {
    const fd_ptr = out_fd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fd_ptr.* = -1;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const fd = handleToFd(handle) catch |err| return finishErr(err);
    fd_ptr.* = @as(i32, @intCast(fd));
    return finish(SA_STD_OK);
}

pub export fn sa_std_fd_dup(handle: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const fd = handleToFd(handle) catch |err| return finishErr(err);
    const dup_fd = lxDup(fd) catch |err| return finishErr(err);
    const dup_handle = registerResourceLocked(.{ .owned_fd = .{ .fd = dup_fd } }) catch |err| {
        lxClose(dup_fd);
        return finishErr(err);
    };
    handle_ptr.* = dup_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fd_dup_raw(fd: i32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);

    const source_fd = @as(std.posix.fd_t, @intCast(fd));
    const dup_fd = lxDup(source_fd) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const dup_handle = registerResourceLocked(.{ .owned_fd = .{ .fd = dup_fd } }) catch |err| {
        lxClose(dup_fd);
        return finishErr(err);
    };
    handle_ptr.* = dup_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fd_is_terminal(handle: u64, out_flag: ?*u8) i32 {
    const flag_ptr = out_flag orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    flag_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const fd = handleToFd(handle) catch |err| return finishErr(err);
    flag_ptr.* = if (lxIsatty(fd)) 1 else 0;
    return finish(SA_STD_OK);
}
