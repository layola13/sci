const std = @import("std");
const IPPROTOT = @import("std_net_tcp.zig").IPPROTOT;
const NetAddrHandle = @import("std_net_tcp.zig").NetAddrHandle;
const NetAddress = @import("std_net_tcp.zig").NetAddress;
const SA_NET_IOV_MAX = @import("std_net_tcp.zig").SA_NET_IOV_MAX;
const SA_STD_ERR_INVALID_ARGUMENT = @import("std_net_tcp.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("std_net_tcp.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_UNSUPPORTED = @import("std_net_tcp.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("std_net_tcp.zig").SA_STD_OK;
const SOLT = @import("std_net_tcp.zig").SOLT;
const SOT = @import("std_net_tcp.zig").SOT;
const SockAddrStorageT = @import("std_net_tcp.zig").SockAddrStorageT;
const SockLenT = @import("std_net_tcp.zig").SockLenT;
const TCP_DEFER_ACCEPT = @import("std_net_tcp.zig").TCP_DEFER_ACCEPT;
const TCP_KEEPCNT = @import("std_net_tcp.zig").TCP_KEEPCNT;
const TCP_KEEPIDLE = @import("std_net_tcp.zig").TCP_KEEPIDLE;
const TCP_KEEPINTVL = @import("std_net_tcp.zig").TCP_KEEPINTVL;
const TCP_QUICKACK = @import("std_net_tcp.zig").TCP_QUICKACK;
const ensureSocketHandle = @import("std_net_tcp.zig").ensureSocketHandle;
const finish = @import("std_net_tcp.zig").finish;
const finishErr = @import("std_net_tcp.zig").finishErr;
const getResourceLocked = @import("std_net_tcp.zig").getResourceLocked;
const getSocketOptBool = @import("std_net_tcp.zig").getSocketOptBool;
const getSocketOptInt = @import("std_net_tcp.zig").getSocketOptInt;
const getSocketOptLinger = @import("std_net_tcp.zig").getSocketOptLinger;
const getSocketOptTimeval = @import("std_net_tcp.zig").getSocketOptTimeval;
const is_linux = @import("std_net_tcp.zig").is_linux;
const is_wasm = @import("std_net_tcp.zig").is_wasm;
const lxClose = @import("std_net_tcp.zig").lxClose;
const lxDup = @import("std_net_tcp.zig").lxDup;
const lxFcntl = @import("std_net_tcp.zig").lxFcntl;
const lxGetpeername = @import("std_net_tcp.zig").lxGetpeername;
const lxGetsockname = @import("std_net_tcp.zig").lxGetsockname;
const lxReadv = @import("std_net_tcp.zig").lxReadv;
const lxRecv = @import("std_net_tcp.zig").lxRecv;
const lxSendfile = @import("std_net_tcp.zig").lxSendfile;
const lxWritev = @import("std_net_tcp.zig").lxWritev;
const msg_peek = @import("std_net_tcp.zig").msg_peek;
const mutBytes = @import("std_net_tcp.zig").mutBytes;
const registerNetAddrOutLocked = @import("std_net_tcp.zig").registerNetAddrOutLocked;
const registerResource = @import("std_net_tcp.zig").registerResource;
const registerResourceLocked = @import("std_net_tcp.zig").registerResourceLocked;
const sa_net_iov = @import("std_net_tcp.zig").sa_net_iov;
const sa_std = @import("std_net_tcp.zig").sa_std;
const sa_std_read = @import("std_net_tcp.zig").sa_std_read;
const sa_std_write = @import("std_net_tcp.zig").sa_std_write;
const setSocketOptBool = @import("std_net_tcp.zig").setSocketOptBool;
const setSocketOptInt = @import("std_net_tcp.zig").setSocketOptInt;
const setSocketOptLinger = @import("std_net_tcp.zig").setSocketOptLinger;
const setSocketOptTimeval = @import("std_net_tcp.zig").setSocketOptTimeval;
const socketAcceptConn = @import("std_net_tcp.zig").socketAcceptConn;
const socketIsInet = @import("std_net_tcp.zig").socketIsInet;
const socketIsStream = @import("std_net_tcp.zig").socketIsStream;
const socketIsUnix = @import("std_net_tcp.zig").socketIsUnix;
const tcpStreamFd = @import("std_net_tcp.zig").tcpStreamFd;
const tcp_nodelay = @import("std_net_tcp.zig").tcp_nodelay;

pub export fn sa_std_net_tcp_stream_read(stream: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_read(stream, out, cap, out_read);
}

pub export fn sa_std_net_tcp_stream_read_vectored(stream: u64, iovs: [*]const sa_net_iov, iov_count: u64, out_read: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    if (iov_count == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const count = std.math.cast(usize, iov_count) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const slices = iovs[0..count];


    const fd = tcpStreamFd(stream) orelse return finish(SA_STD_ERR_INVALID_HANDLE);

    var ziovec: [SA_NET_IOV_MAX]std.posix.iovec = undefined;
    var filled: usize = 0;
    for (slices) |slot| {
        if (filled >= ziovec.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
        const len = std.math.cast(usize, slot.len) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
        ziovec[filled] = .{ .base = slot.base, .len = len };
        filled += 1;
    }
    const read = lxReadv(fd, ziovec[0..filled]) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(read));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_write_vectored(stream: u64, iovs: [*]const sa_net_iov, iov_count: u64, out_written: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    written_ptr.* = 0;
    if (iov_count == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const count = std.math.cast(usize, iov_count) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const slices = iovs[0..count];


    const fd = tcpStreamFd(stream) orelse return finish(SA_STD_ERR_INVALID_HANDLE);

    var ziovec: [SA_NET_IOV_MAX]std.posix.iovec_const = undefined;
    var filled: usize = 0;
    for (slices) |slot| {
        if (filled >= ziovec.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
        const len = std.math.cast(usize, slot.len) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
        ziovec[filled] = .{ .base = slot.base, .len = len };
        filled += 1;
    }
    const written = lxWritev(fd, ziovec[0..filled]) catch |err| return finishErr(err);
    written_ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_peek(stream: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);

    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    const fd = blk: {
        const resource = getResourceLocked(stream) orelse {
            sa_std.registry_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        };
        break :blk switch (resource.*) {
            .tcp_stream => |s| s,
            else => {
                sa_std.registry_mutex.unlock();
                return finish(SA_STD_ERR_INVALID_HANDLE);
            },
        };
    };
    sa_std.registry_mutex.unlock();

    const read = lxRecv(fd, buffer, msg_peek) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(read));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_write(stream: u64, out: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_write(stream, out, len, out_written);
}

pub export fn sa_std_net_tcp_stream_peer_addr(stream: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .tcp_stream => |s| {
            var addr = NetAddress{};
            var len: SockLenT = @sizeOf(SockAddrStorageT);
            lxGetpeername(s, addr.sockAddrMut(), &len) catch |err| return finishErr(err);
            addr.len = len;
            var net_addr = NetAddrHandle.init(std.heap.page_allocator, addr) catch |err| return finishErr(err);
            const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
                net_addr.deinit();
                return finishErr(err);
            };
            handle_ptr.* = handle;
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_net_tcp_stream_local_addr(stream: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .tcp_stream => |s| {
            var addr = NetAddress{};
            var len: SockLenT = @sizeOf(SockAddrStorageT);
            lxGetsockname(s, addr.sockAddrMut(), &len) catch |err| return finishErr(err);
            addr.len = len;
            return registerNetAddrOutLocked(addr, handle_ptr);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_net_tcp_stream_try_clone(stream: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const fd = switch (resource.*) {
        .tcp_stream => |value| value,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    const dup_fd = lxDup(fd) catch |err| return finishErr(err);
    const handle = registerResourceLocked(.{ .tcp_stream = dup_fd }) catch |err| {
        lxClose(dup_fd);
        return finishErr(err);
    };
    out.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_nonblocking(stream: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    const flags = lxFcntl(handle.fd, std.posix.F.GETFL, 0) catch |err| return finishErr(err);
    const new_flags = if (enabled != 0)
        flags | @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK")
    else
        flags & ~(@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"));
    _ = lxFcntl(handle.fd, std.posix.F.SETFL, new_flags) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_nodelay(stream: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptBool(handle.fd, IPPROTOT.TCP, tcp_nodelay, enabled != 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_linger(stream: u64, enabled: i32, timeout_ns: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptLinger(handle.fd, enabled != 0, timeout_ns) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_linger(stream: u64, out_enabled: ?*i32, out_timeout_ns: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const enabled = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const timeout_ns = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    enabled.* = 0;
    timeout_ns.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    const value = getSocketOptLinger(handle.fd) catch |err| return finishErr(err);
    if (value.onoff == 0) return finish(SA_STD_OK);
    if (value.linger < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    timeout_ns.* = std.math.mul(u64, @as(u64, @intCast(value.linger)), std.time.ns_per_s) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    enabled.* = 1;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_quickack(stream: u64, enabled: i32) i32 {
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (socketIsUnix(handle.fd) catch |err| return finishErr(err)) return finish(SA_STD_OK);
    setSocketOptBool(handle.fd, IPPROTOT.TCP, TCP_QUICKACK, enabled != 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_quickack(stream: u64, out_enabled: ?*i32) i32 {
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (socketIsUnix(handle.fd) catch |err| return finishErr(err)) return finish(SA_STD_OK);
    out.* = if (getSocketOptBool(handle.fd, IPPROTOT.TCP, TCP_QUICKACK) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_deferaccept(stream: u64, seconds: u32) i32 {
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (seconds > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (socketIsUnix(handle.fd) catch |err| return finishErr(err)) return finish(SA_STD_OK);
    setSocketOptInt(handle.fd, IPPROTOT.TCP, TCP_DEFER_ACCEPT, @as(i32, @intCast(seconds))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_deferaccept(stream: u64, out_seconds: ?*u32) i32 {
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_seconds orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (socketIsUnix(handle.fd) catch |err| return finishErr(err)) return finish(SA_STD_OK);
    const seconds = getSocketOptInt(handle.fd, IPPROTOT.TCP, TCP_DEFER_ACCEPT) catch |err| return finishErr(err);
    if (seconds < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @as(u32, @intCast(seconds));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_keepalive(stream: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (socketIsUnix(handle.fd) catch |err| return finishErr(err)) return finish(SA_STD_OK);
    setSocketOptBool(handle.fd, SOLT.SOCKET, SOT.KEEPALIVE, enabled != 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_keepalive(stream: u64, out_enabled: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (socketIsUnix(handle.fd) catch |err| return finishErr(err)) return finish(SA_STD_OK);
    out.* = if (getSocketOptBool(handle.fd, SOLT.SOCKET, SOT.KEEPALIVE) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_keepalive_params(stream: u64, idle_secs: u32, interval_secs: u32, count: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (idle_secs > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (interval_secs > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (count > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (socketIsUnix(handle.fd) catch |err| return finishErr(err)) return finish(SA_STD_OK);
    setSocketOptInt(handle.fd, IPPROTOT.TCP, TCP_KEEPIDLE, @as(i32, @intCast(idle_secs))) catch |err| return finishErr(err);
    setSocketOptInt(handle.fd, IPPROTOT.TCP, TCP_KEEPINTVL, @as(i32, @intCast(interval_secs))) catch |err| return finishErr(err);
    setSocketOptInt(handle.fd, IPPROTOT.TCP, TCP_KEEPCNT, @as(i32, @intCast(count))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_read_timeout(stream: u64, timeout_ns: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptTimeval(handle.fd, SOLT.SOCKET, SOT.RCVTIMEO, timeout_ns) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_write_timeout(stream: u64, timeout_ns: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptTimeval(handle.fd, SOLT.SOCKET, SOT.SNDTIMEO, timeout_ns) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_ttl(stream: u64, ttl: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (ttl > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    setSocketOptInt(handle.fd, IPPROTOT.IP, std.posix.IP.TTL, @as(i32, @intCast(ttl))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_read_timeout(stream: u64, out_timeout_ns: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = getSocketOptTimeval(handle.fd, SOLT.SOCKET, SOT.RCVTIMEO) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_write_timeout(stream: u64, out_timeout_ns: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = getSocketOptTimeval(handle.fd, SOLT.SOCKET, SOT.SNDTIMEO) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_nodelay(stream: u64, out_enabled: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = if (getSocketOptBool(handle.fd, IPPROTOT.TCP, tcp_nodelay) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_ttl(stream: u64, out_ttl: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_ttl orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    const ttl = getSocketOptInt(handle.fd, IPPROTOT.IP, std.posix.IP.TTL) catch |err| return finishErr(err);
    if (ttl < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @as(u32, @intCast(ttl));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_recv_buffer_size(stream: u64, size: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (size > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    setSocketOptInt(handle.fd, SOLT.SOCKET, SOT.RCVBUF, @as(i32, @intCast(size))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_recv_buffer_size(stream: u64, out_size: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_size orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    const value = getSocketOptInt(handle.fd, SOLT.SOCKET, SOT.RCVBUF) catch |err| return finishErr(err);
    if (value < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @as(u32, @intCast(value));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_set_send_buffer_size(stream: u64, size: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (size > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    setSocketOptInt(handle.fd, SOLT.SOCKET, SOT.SNDBUF, @as(i32, @intCast(size))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_send_buffer_size(stream: u64, out_size: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_size orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    const value = getSocketOptInt(handle.fd, SOLT.SOCKET, SOT.SNDBUF) catch |err| return finishErr(err);
    if (value < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @as(u32, @intCast(value));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_take_error(stream: u64, out_error: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_error orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = getSocketOptInt(handle.fd, SOLT.SOCKET, SOT.ERROR) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_send_file(stream: u64, file: u64, offset: u64, count: u64, out_sent: ?*u64, out_next_offset: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    const sent_ptr = out_sent orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    sent_ptr.* = 0;
    if (out_next_offset) |slot| slot.* = offset;
    var out_fd_opt: ?std.posix.fd_t = null;
    var in_fd_opt: ?std.posix.fd_t = null;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    if (getResourceLocked(stream)) |resource| {
        switch (resource.*) {
            .tcp_stream => |fd| out_fd_opt = fd,
            else => {},
        }
    }
    if (getResourceLocked(file)) |resource| {
        switch (resource.*) {
            .file => |handle| in_fd_opt = handle.inner.handle,
            else => {},
        }
    }
    sa_std.registry_mutex.unlock();
    const out_fd = out_fd_opt orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const in_fd = in_fd_opt orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var next_offset = offset;
    var sent_total: u64 = 0;
    while (sent_total < count) {
        const remaining = count - sent_total;
        const chunk: usize = @intCast(@min(remaining, @as(u64, 0x7ffff000)));
        const n = lxSendfile(out_fd, in_fd, &next_offset, chunk) catch |err| {
            if (out_next_offset) |slot| slot.* = next_offset;
            sent_ptr.* = sent_total;
            return finishErr(err);
        };
        if (n == 0) break; // EOF: short send, reported via out_sent.
        sent_total += @as(u64, @intCast(n));
    }
    if (out_next_offset) |slot| slot.* = next_offset;
    sent_ptr.* = sent_total;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const posix_fd = @as(std.posix.fd_t, @intCast(fd));
    if (!(socketIsInet(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsStream(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (socketAcceptConn(posix_fd) catch |err| return finishErr(err)) return finish(SA_STD_ERR_INVALID_HANDLE);
    const handle = registerResource(.{ .tcp_stream = posix_fd }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}
