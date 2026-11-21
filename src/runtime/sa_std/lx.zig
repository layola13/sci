const std = @import("std");
const SockAddrT = @import("../sa_std.zig").SockAddrT;
const SockLenT = @import("../sa_std.zig").SockLenT;
const is_linux = @import("../sa_std.zig").is_linux;
const is_wasm = @import("../sa_std.zig").is_wasm;
const libc = @import("../sa_std.zig").libc;
const libcErrRc = @import("../sa_std.zig").libcErrRc;
const libcUsize = @import("../sa_std.zig").libcUsize;
const libcFd = @import("fd_core.zig").libcFd;
const lxErr = @import("spawn.zig").lxErr;

pub fn lxCheck(rc: usize) !usize {
    if (comptime is_wasm) return error.Unsupported;
    const e = std.os.linux.errno(rc);
    if (e != .SUCCESS) return lxErr(e);
    return rc;
}

pub fn lxClose(fd: std.posix.fd_t) void {
    if (comptime is_wasm) return;
    if (comptime is_linux) {
        _ = std.os.linux.close(fd);
    } else {
        _ = libc.close(fd);
    }
}

pub fn lxWrite(fd: std.posix.fd_t, bytes: []const u8) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (bytes.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.write(fd, bytes.ptr, bytes.len));
    return try libcUsize(libc.write(fd, bytes.ptr, bytes.len));
}

pub fn lxReadv(fd: std.posix.fd_t, iov: []std.posix.iovec) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) return try lxCheck(std.os.linux.readv(fd, iov.ptr, iov.len));
    return try libcUsize(libc.readv(fd, iov.ptr, @intCast(iov.len)));
}

pub fn lxWritev(fd: std.posix.fd_t, iov: []const std.posix.iovec_const) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) return try lxCheck(std.os.linux.writev(fd, iov.ptr, iov.len));
    return try libcUsize(libc.writev(fd, iov.ptr, @intCast(iov.len)));
}

pub fn lxSocket(domain: u32, sock_type: u32, protocol: u32) !std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const rc = try lxCheck(std.os.linux.socket(domain, sock_type, protocol));
        return @as(std.posix.fd_t, @bitCast(@as(u32, @truncate(rc))));
    }
    return try libcFd(libc.socket(@intCast(domain), @intCast(sock_type), @intCast(protocol)));
}

pub fn lxShutdown(fd: std.posix.fd_t, how: i32) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.shutdown(fd, how));
        return;
    }
    try libcErrRc(libc.shutdown(fd, @intCast(how)));
}

pub fn lxSend(fd: std.posix.fd_t, bytes: []const u8, flags: u32) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (bytes.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.sendto(fd, bytes.ptr, bytes.len, flags, null, 0));
    return try libcUsize(libc.sendto(fd, bytes.ptr, bytes.len, @intCast(flags), null, 0));
}

pub fn lxRecv(fd: std.posix.fd_t, buf: []u8, flags: u32) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (buf.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.recvfrom(fd, buf.ptr, buf.len, flags, null, null));
    return try libcUsize(libc.recvfrom(fd, buf.ptr, buf.len, @intCast(flags), null, null));
}

pub fn lxSendto(fd: std.posix.fd_t, bytes: []const u8, flags: u32, addr: ?*const SockAddrT, len: SockLenT) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (bytes.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.sendto(fd, bytes.ptr, bytes.len, flags, addr, len));
    return try libcUsize(libc.sendto(fd, bytes.ptr, bytes.len, @intCast(flags), addr, @intCast(len)));
}

pub fn lxRecvfrom(fd: std.posix.fd_t, buf: []u8, flags: u32, addr: ?*SockAddrT, len: ?*SockLenT) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (buf.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.recvfrom(fd, buf.ptr, buf.len, flags, addr, len));
    return try libcUsize(libc.recvfrom(fd, buf.ptr, buf.len, @intCast(flags), addr, @ptrCast(len)));
}

pub fn lxUnlink(path: []const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.unlink(&z));
        return;
    }
    try libcErrRc(libc.unlink(&z));
}

pub fn lxMkdirat(dirfd: std.posix.fd_t, path: []const u8, mode: std.posix.mode_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.mkdirat(dirfd, &z, mode));
        return;
    }
    try libcErrRc(libc.mkdirat(dirfd, &z, @intCast(mode)));
}

pub fn lxFchmodat(dirfd: std.posix.fd_t, path: []const u8, mode: std.posix.mode_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.fchmodat(dirfd, &z, mode));
        return;
    }
    try libcErrRc(libc.fchmodat(dirfd, &z, @intCast(mode), 0));
}

pub fn lxLink(old: []const u8, new: []const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    const old_z = try std.posix.toPosixPath(old);
    const new_z = try std.posix.toPosixPath(new);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.link(&old_z, &new_z));
        return;
    }
    try libcErrRc(libc.link(&old_z, &new_z));
}

pub fn lxFutimens(fd: std.posix.fd_t, times: *const [2]std.posix.timespec) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.futimens(fd, times));
        return;
    }
    try libcErrRc(libc.futimens(fd, times));
}

pub fn lxKill(pid: std.posix.pid_t, sig: u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.kill(pid, @fromBackingInt(@intCast(sig))));
        return;
    }
    try libcErrRc(libc.kill(@intCast(pid), @intCast(sig)));
}

pub fn lxGetpeername(fd: std.posix.fd_t, addr: *SockAddrT, len: *SockLenT) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.getpeername(fd, addr, len));
        return;
    }
    try libcErrRc(libc.getpeername(fd, addr, @ptrCast(len)));
}

pub fn lxEpollCreate1(flags: u32) !std.posix.fd_t {
    if (comptime !is_linux) return error.Unsupported;
    if (comptime is_wasm) return error.Unsupported;
    const rc = try lxCheck(std.os.linux.epoll_create1(flags));
    return @as(std.posix.fd_t, @bitCast(@as(u32, @truncate(rc))));
}

pub fn lxEpollCtl(epfd: std.posix.fd_t, op: u32, fd: std.posix.fd_t, event: ?*std.os.linux.epoll_event) !void {
    if (comptime !is_linux) return error.Unsupported;
    if (comptime is_wasm) return error.Unsupported;
    _ = try lxCheck(std.os.linux.epoll_ctl(epfd, op, fd, event));
}

pub fn lxEpollWait(epfd: std.posix.fd_t, events: []std.os.linux.epoll_event, timeout_ms: i32) usize {
    if (comptime !is_linux) return 0;
    if (comptime is_wasm) return;
    const rc = std.os.linux.epoll_wait(epfd, events.ptr, @as(u32, @intCast(events.len)), timeout_ms);
    if (std.os.linux.errno(rc) != .SUCCESS) return 0;
    return rc;
}

pub fn lxSendfile(out_fd: std.posix.fd_t, in_fd: std.posix.fd_t, offset: *u64, count: usize) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        var off: i64 = @intCast(offset.*);
        const rc = try lxCheck(std.os.linux.sendfile(out_fd, in_fd, &off, count));
        offset.* = @intCast(off);
        return rc;
    }
    return error.Unsupported;
}
