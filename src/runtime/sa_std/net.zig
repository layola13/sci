const std = @import("std");
const AFT = @import("../sa_std.zig").AFT;
const Fallible = @import("../sa_std.zig").Fallible;
const SA_NET_UNIX_ADDR_ABSTRACT = @import("../sa_std.zig").SA_NET_UNIX_ADDR_ABSTRACT;
const SA_NET_UNIX_ADDR_PATHNAME = @import("../sa_std.zig").SA_NET_UNIX_ADDR_PATHNAME;
const SA_NET_UNIX_ADDR_UNNAMED = @import("../sa_std.zig").SA_NET_UNIX_ADDR_UNNAMED;
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const constBytes = @import("../sa_std.zig").constBytes;
const fail = @import("../sa_std.zig").fail;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const formatIpv6Segments = @import("../sa_std.zig").formatIpv6Segments;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const is_wasm = @import("../sa_std.zig").is_wasm;
const lxShutdown = @import("../sa_std.zig").lxShutdown;
const mutBytes = @import("../sa_std.zig").mutBytes;
const ok = @import("../sa_std.zig").ok;
const parseIpv4Ascii = @import("../sa_std.zig").parseIpv4Ascii;
const parseIpv6Ascii = @import("../sa_std.zig").parseIpv6Ascii;
const parsePortAscii = @import("../sa_std.zig").parsePortAscii;
const parseSocketAddrV6Ascii = @import("../sa_std.zig").parseSocketAddrV6Ascii;
const readIpv6SegmentsNative = @import("../sa_std.zig").readIpv6SegmentsNative;
const sa_std = @import("../sa_std.zig");
const sa_io_write_all = @import("../sa_std.zig").sa_io_write_all;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const sa_std_net_tcp_accept = @import("../sa_std.zig").sa_std_net_tcp_accept;
const sa_std_net_tcp_connect = @import("../sa_std.zig").sa_std_net_tcp_connect;
const sa_std_net_tcp_listen = @import("../sa_std.zig").sa_std_net_tcp_listen;
const sa_std_net_tcp_listener_local_addr = @import("../sa_std.zig").sa_std_net_tcp_listener_local_addr;
const sa_std_net_tcp_stream_peek = @import("../sa_std.zig").sa_std_net_tcp_stream_peek;
const sa_std_net_tcp_stream_peer_addr = @import("../sa_std.zig").sa_std_net_tcp_stream_peer_addr;
const sa_std_net_tcp_stream_read = @import("../sa_std.zig").sa_std_net_tcp_stream_read;
const sa_std_net_tcp_stream_set_nodelay = @import("../sa_std.zig").sa_std_net_tcp_stream_set_nodelay;
const sa_std_net_tcp_stream_set_nonblocking = @import("../sa_std.zig").sa_std_net_tcp_stream_set_nonblocking;
const sa_std_net_tcp_stream_set_read_timeout = @import("../sa_std.zig").sa_std_net_tcp_stream_set_read_timeout;
const sa_std_net_tcp_stream_set_ttl = @import("../sa_std.zig").sa_std_net_tcp_stream_set_ttl;
const sa_std_net_tcp_stream_set_write_timeout = @import("../sa_std.zig").sa_std_net_tcp_stream_set_write_timeout;
const sa_std_net_tcp_stream_write = @import("../sa_std.zig").sa_std_net_tcp_stream_write;
const sa_std_net_udp_bind = @import("../sa_std.zig").sa_std_net_udp_bind;
const sa_std_net_udp_connect = @import("../sa_std.zig").sa_std_net_udp_connect;
const sa_std_net_udp_join_multicast_v4 = @import("../sa_std.zig").sa_std_net_udp_join_multicast_v4;
const sa_std_net_udp_join_multicast_v6 = @import("../sa_std.zig").sa_std_net_udp_join_multicast_v6;
const sa_std_net_udp_leave_multicast_v4 = @import("../sa_std.zig").sa_std_net_udp_leave_multicast_v4;
const sa_std_net_udp_leave_multicast_v6 = @import("../sa_std.zig").sa_std_net_udp_leave_multicast_v6;
const sa_std_net_udp_local_addr = @import("../sa_std.zig").sa_std_net_udp_local_addr;
const sa_std_net_udp_peek = @import("../sa_std.zig").sa_std_net_udp_peek;
const sa_std_net_udp_peek_from = @import("../sa_std.zig").sa_std_net_udp_peek_from;
const sa_std_net_udp_recv = @import("../sa_std.zig").sa_std_net_udp_recv;
const sa_std_net_udp_recv_from = @import("../sa_std.zig").sa_std_net_udp_recv_from;
const sa_std_net_udp_send = @import("../sa_std.zig").sa_std_net_udp_send;
const sa_std_net_udp_send_to = @import("../sa_std.zig").sa_std_net_udp_send_to;
const sa_std_net_udp_set_broadcast = @import("../sa_std.zig").sa_std_net_udp_set_broadcast;
const sa_std_net_udp_set_multicast_loop_v4 = @import("../sa_std.zig").sa_std_net_udp_set_multicast_loop_v4;
const sa_std_net_udp_set_multicast_ttl_v4 = @import("../sa_std.zig").sa_std_net_udp_set_multicast_ttl_v4;
const sa_std_net_udp_set_nonblocking = @import("../sa_std.zig").sa_std_net_udp_set_nonblocking;
const sa_std_net_udp_set_read_timeout = @import("../sa_std.zig").sa_std_net_udp_set_read_timeout;
const sa_std_net_udp_set_ttl = @import("../sa_std.zig").sa_std_net_udp_set_ttl;
const sa_std_net_udp_set_write_timeout = @import("../sa_std.zig").sa_std_net_udp_set_write_timeout;
const writeIpv6SegmentsNative = @import("../sa_std.zig").writeIpv6SegmentsNative;

pub const sa_net_iov = extern struct {
    base: [*]u8,
    len: usize,
};

pub export fn sa_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32) Fallible(u64) {
    if (comptime is_wasm) return fail(u64, SA_STD_ERR_UNSUPPORTED);
    var handle: u64 = 0;
    const status = sa_std_net_tcp_connect(host_ptr, host_len, port, &handle);
    if (status != SA_STD_OK) return fail(u64, status);
    return ok(u64, handle);
}

pub export fn sa_net_tcp_stream_read(stream: u64, out: ?[*]u8, cap: u64) Fallible(u64) {
    if (comptime is_wasm) return fail(u64, SA_STD_ERR_UNSUPPORTED);
    var read: u64 = 0;
    const status = sa_std_net_tcp_stream_read(stream, out, cap, &read);
    if (status != SA_STD_OK) return fail(u64, status);
    return ok(u64, read);
}

pub export fn sa_net_tcp_stream_peek(stream: u64, out: ?[*]u8, cap: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var read: u64 = 0;
    const status = sa_std_net_tcp_stream_peek(stream, out, cap, &read);
    if (status != SA_STD_OK) return -status;
    return finish(@as(i32, @intCast(read)));
}

pub export fn sa_net_tcp_stream_write(stream: u64, out: ?[*]const u8, len: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var written: u64 = 0;
    const status = sa_std_net_tcp_stream_write(stream, out, len, &written);
    // W1-DEF-NET-WRITE-AFTER-SHUTDOWN: this wrapper returns a byte
    // count, so an error status must go out negated -- returning
    // the positive code made a failed write (e.g. EPIPE after
    // shutdown) indistinguishable from a successful short write.
    // The inner std call already recorded last_error. The same
    // convention applies to every plain count wrapper below
    // (tcp peek, udp send/recv/peek/send_to/recv_from).
    if (status != SA_STD_OK) return -status;
    return finish(@as(i32, @intCast(written)));
}

pub export fn sa_net_tcp_stream_write_all(stream: u64, out: ?[*]const u8, len: u64) Fallible(i32) {
    if (comptime is_wasm) return fail(i32, SA_STD_ERR_UNSUPPORTED);
    const status = sa_io_write_all(stream, out, len);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_net_tcp_stream_read_exact(stream: u64, out: ?[*]u8, len: u64) Fallible(i32) {
    if (comptime is_wasm) return fail(i32, SA_STD_ERR_UNSUPPORTED);
    var remaining: u64 = len;
    var cursor: u64 = 0;
    while (remaining != 0) {
        var chunk: u64 = 0;
        // wasm32-wasi: pointer arithmetic needs usize offset; checked cast.
        const cursor_usize = std.math.cast(usize, cursor) orelse return fail(i32, SA_STD_ERR_INVALID_ARGUMENT);
        const status = sa_std_net_tcp_stream_read(stream, if (out) |p| p + cursor_usize else null, remaining, &chunk);
        if (status != SA_STD_OK) return fail(i32, status);
        if (chunk == 0) return fail(i32, SA_STD_ERR_IO);
        cursor += chunk;
        remaining -= chunk;
    }
    return ok(i32, 0);
}

pub export fn sa_net_tcp_stream_flush(stream: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    _ = stream;
    return finish(SA_STD_OK);
}

pub export fn sa_net_tcp_stream_peer_addr(stream: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var handle: u64 = 0;
    const status = sa_std_net_tcp_stream_peer_addr(stream, &handle);
    if (status != SA_STD_OK) return status;
    return finish(@as(i32, @intCast(handle)));
}

pub export fn sa_net_tcp_stream_shutdown(stream: u64, how: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .tcp_stream => |s| {
            const shutdown: i32 = switch (how) {
                0 => std.posix.SHUT.RD,
                1 => std.posix.SHUT.WR,
                2 => std.posix.SHUT.RDWR,
                else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
            };
            lxShutdown(s, shutdown) catch |err| return finishErr(err);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_net_tcp_stream_set_read_timeout(stream: u64, timeout_ns: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_tcp_stream_set_read_timeout(stream, timeout_ns);
}

pub export fn sa_net_tcp_stream_set_write_timeout(stream: u64, timeout_ns: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_tcp_stream_set_write_timeout(stream, timeout_ns);
}

pub export fn sa_net_tcp_stream_set_nonblocking(stream: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_tcp_stream_set_nonblocking(stream, enabled);
}

pub export fn sa_net_tcp_stream_set_nodelay(stream: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_tcp_stream_set_nodelay(stream, enabled);
}

pub export fn sa_net_tcp_stream_set_ttl(stream: u64, ttl: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_tcp_stream_set_ttl(stream, ttl);
}

pub export fn sa_net_tcp_stream_close(stream: u64) Fallible(i32) {
    if (comptime is_wasm) return fail(i32, SA_STD_ERR_UNSUPPORTED);
    const status = sa_std_close(stream);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_net_tcp_listener_bind(host_ptr: ?[*]const u8, host_len: u64, port: u16) Fallible(u64) {
    if (comptime is_wasm) return fail(u64, SA_STD_ERR_UNSUPPORTED);
    var handle: u64 = 0;
    const status = sa_std_net_tcp_listen(host_ptr, host_len, port, &handle, null);
    if (status != SA_STD_OK) return fail(u64, status);
    return ok(u64, handle);
}

pub export fn sa_net_tcp_listener_accept(listener: u64) Fallible(u64) {
    if (comptime is_wasm) return fail(u64, SA_STD_ERR_UNSUPPORTED);
    var handle: u64 = 0;
    const status = sa_std_net_tcp_accept(listener, &handle);
    if (status != SA_STD_OK) return fail(u64, status);
    return ok(u64, handle);
}

pub export fn sa_net_tcp_listener_local_addr(listener: u64) Fallible(u64) {
    if (comptime is_wasm) return fail(u64, SA_STD_ERR_UNSUPPORTED);
    var handle: u64 = 0;
    const status = sa_std_net_tcp_listener_local_addr(listener, &handle);
    if (status != SA_STD_OK) return fail(u64, status);
    return ok(u64, handle);
}

pub export fn sa_net_tcp_listener_close(listener: u64) Fallible(i32) {
    if (comptime is_wasm) return fail(i32, SA_STD_ERR_UNSUPPORTED);
    const status = sa_std_close(listener);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_net_udp_set_read_timeout(socket: u64, timeout_ns: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_set_read_timeout(socket, timeout_ns);
}

pub export fn sa_net_udp_set_write_timeout(socket: u64, timeout_ns: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_set_write_timeout(socket, timeout_ns);
}

pub export fn sa_net_udp_set_nonblocking(socket: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_set_nonblocking(socket, enabled);
}

pub export fn sa_net_udp_set_broadcast(socket: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_set_broadcast(socket, enabled);
}

pub export fn sa_net_udp_set_ttl(socket: u64, ttl: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_set_ttl(socket, ttl);
}

pub export fn sa_net_udp_set_multicast_loop_v4(socket: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_set_multicast_loop_v4(socket, enabled);
}

pub export fn sa_net_udp_set_multicast_ttl_v4(socket: u64, ttl: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_set_multicast_ttl_v4(socket, ttl);
}

pub export fn sa_net_udp_join_multicast_v4(socket: u64, multi_host_ptr: ?[*]const u8, multi_host_len: u64, interface_host_ptr: ?[*]const u8, interface_host_len: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_join_multicast_v4(socket, multi_host_ptr, multi_host_len, interface_host_ptr, interface_host_len);
}

pub export fn sa_net_udp_leave_multicast_v4(socket: u64, multi_host_ptr: ?[*]const u8, multi_host_len: u64, interface_host_ptr: ?[*]const u8, interface_host_len: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_leave_multicast_v4(socket, multi_host_ptr, multi_host_len, interface_host_ptr, interface_host_len);
}

pub export fn sa_net_udp_join_multicast_v6(socket: u64, multi_host_ptr: ?[*]const u8, multi_host_len: u64, interface_index: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_join_multicast_v6(socket, multi_host_ptr, multi_host_len, interface_index);
}

pub export fn sa_net_udp_leave_multicast_v6(socket: u64, multi_host_ptr: ?[*]const u8, multi_host_len: u64, interface_index: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_leave_multicast_v6(socket, multi_host_ptr, multi_host_len, interface_index);
}

pub export fn sa_net_udp_bind(host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var handle: u64 = 0;
    const status = sa_std_net_udp_bind(host_ptr, host_len, port, &handle);
    if (status != SA_STD_OK) return status;
    return @as(i32, @intCast(handle));
}

pub export fn sa_net_udp_connect(socket: u64, host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_udp_connect(socket, host_ptr, host_len, port);
}

pub export fn sa_net_udp_local_addr(socket: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var handle: u64 = 0;
    const status = sa_std_net_udp_local_addr(socket, &handle);
    if (status != SA_STD_OK) return status;
    return @as(i32, @intCast(handle));
}

pub export fn sa_net_udp_send(socket: u64, buf: ?[*]const u8, len: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var written: u64 = 0;
    const status = sa_std_net_udp_send(socket, buf, len, &written);
    if (status != SA_STD_OK) return -status;
    return @as(i32, @intCast(written));
}

pub export fn sa_net_udp_recv(socket: u64, out: ?[*]u8, cap: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var read: u64 = 0;
    const status = sa_std_net_udp_recv(socket, out, cap, &read);
    if (status != SA_STD_OK) return -status;
    return @as(i32, @intCast(read));
}

pub export fn sa_net_udp_peek(socket: u64, out: ?[*]u8, cap: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var read: u64 = 0;
    const status = sa_std_net_udp_peek(socket, out, cap, &read);
    if (status != SA_STD_OK) return -status;
    return @as(i32, @intCast(read));
}

pub export fn sa_net_udp_send_to(socket: u64, buf: ?[*]const u8, len: u64, host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var written: u64 = 0;
    const status = sa_std_net_udp_send_to(socket, buf, len, host_ptr, host_len, port, &written);
    if (status != SA_STD_OK) return -status;
    return @as(i32, @intCast(written));
}

pub export fn sa_net_udp_recv_from(socket: u64, out: ?[*]u8, cap: u64, out_addr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var read: u64 = 0;
    const status = sa_std_net_udp_recv_from(socket, out, cap, &read, out_addr);
    if (status != SA_STD_OK) return -status;
    return @as(i32, @intCast(read));
}

pub export fn sa_net_udp_peek_from(socket: u64, out: ?[*]u8, cap: u64, out_addr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    var read: u64 = 0;
    const status = sa_std_net_udp_peek_from(socket, out, cap, &read, out_addr);
    if (status != SA_STD_OK) return -status;
    return @as(i32, @intCast(read));
}

pub export fn sa_net_udp_close(socket: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_close(socket);
}

pub export fn sa_net_addr_host(addr: u64) ?[*]u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return null;
    };
    return switch (resource.*) {
        .net_addr => |net_addr| net_addr.host.ptr,
        else => {
            _ = finish(SA_STD_ERR_INVALID_HANDLE);
            return null;
        },
    };
}

pub export fn sa_net_addr_host_len(addr: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return switch (resource.*) {
        .net_addr => |net_addr| @as(u64, @intCast(net_addr.host.len)),
        else => {
            _ = finish(SA_STD_ERR_INVALID_HANDLE);
            return 0;
        },
    };
}

pub export fn sa_net_addr_port(addr: u64) u32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return switch (resource.*) {
        .net_addr => |net_addr| @as(u32, net_addr.addr.getPort()),
        else => {
            _ = finish(SA_STD_ERR_INVALID_HANDLE);
            return 0;
        },
    };
}

pub export fn sa_net_addr_family(addr: u64) u32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return switch (resource.*) {
        .net_addr => |net_addr| @as(u32, @intCast(net_addr.addr.storage.family)),
        else => {
            _ = finish(SA_STD_ERR_INVALID_HANDLE);
            return 0;
        },
    };
}

pub export fn sa_net_addr_scope_id(addr: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return switch (resource.*) {
        .net_addr => |net_addr| switch (net_addr.addr.storage.family) {
            AFT.INET6 => @as(u64, @intCast(net_addr.addr.in6ScopeId())),
            else => 0,
        },
        else => {
            _ = finish(SA_STD_ERR_INVALID_HANDLE);
            return 0;
        },
    };
}

pub export fn sa_net_addr_free(addr: u64) Fallible(i32) {
    const status = sa_std_close(addr);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_net_ipv4_parse_ascii(text_ptr: ?[*]const u8, text_len: u64, out_addr: ?[*]u8) i32 {
    const out = out_addr orelse return 0;
    out[0] = 0;
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;

    const text = constBytes(text_ptr, text_len) catch return 0;
    const parts = parseIpv4Ascii(text) orelse return 0;

    out[0] = parts[0];
    out[1] = parts[1];
    out[2] = parts[2];
    out[3] = parts[3];
    return 1;
}

pub export fn sa_net_socket_addr_v4_parse_ascii(text_ptr: ?[*]const u8, text_len: u64, out_socket_addr: ?[*]u8) i32 {
    const out = out_socket_addr orelse return 0;
    for (out[0..8]) |*byte| byte.* = 0;

    const text = constBytes(text_ptr, text_len) catch return 0;
    const colon = std.mem.lastIndexOfScalar(u8, text, ':') orelse return 0;
    const ip = parseIpv4Ascii(text[0..colon]) orelse return 0;
    const port = parsePortAscii(text[colon + 1 ..]) orelse return 0;

    out[0] = ip[0];
    out[1] = ip[1];
    out[2] = ip[2];
    out[3] = ip[3];
    std.mem.writeInt(u16, out[4..6], port, .little);
    return 1;
}

pub export fn sa_net_ipv6_parse_ascii(text_ptr: ?[*]const u8, text_len: u64, out_addr: ?[*]u8) i32 {
    const out = out_addr orelse return 0;
    @memset(out[0..16], 0);

    const text = constBytes(text_ptr, text_len) catch return 0;
    const parsed = parseIpv6Ascii(text) orelse return 0;
    writeIpv6SegmentsNative(out[0..16], &parsed.octets);
    return 1;
}

pub export fn sa_net_socket_addr_v6_parse_ascii(text_ptr: ?[*]const u8, text_len: u64, out_socket_addr: ?[*]u8) i32 {
    const out = out_socket_addr orelse return 0;
    @memset(out[0..32], 0);

    const text = constBytes(text_ptr, text_len) catch return 0;
    const parsed = parseSocketAddrV6Ascii(text) orelse return 0;
    writeIpv6SegmentsNative(out[0..16], &parsed.octets);
    std.mem.writeInt(u16, out[16..18], parsed.port, .little);
    std.mem.writeInt(u32, out[20..24], 0, .little);
    std.mem.writeInt(u32, out[24..28], parsed.scope_id, .little);
    return 1;
}

pub export fn sa_net_ipv4_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    const text = std.fmt.bufPrint(buffer, "{d}.{d}.{d}.{d}", .{ addr[0], addr[1], addr[2], addr[3] }) catch return 0;
    len_ptr.* = @as(u64, @intCast(text.len));
    return 1;
}

pub export fn sa_net_ipv6_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr_raw = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    var raw: [16]u8 = undefined;
    @memcpy(raw[0..], addr_raw[0..16]);
    const segments = readIpv6SegmentsNative(&raw);
    const text = formatIpv6Segments(buffer, &segments) catch return 0;
    len_ptr.* = @as(u64, @intCast(text.len));
    return 1;
}

pub export fn sa_net_socket_addr_v4_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    const port = std.mem.readInt(u16, addr[4..6], .little);
    const text = std.fmt.bufPrint(buffer, "{d}.{d}.{d}.{d}:{d}", .{ addr[0], addr[1], addr[2], addr[3], port }) catch return 0;
    len_ptr.* = @as(u64, @intCast(text.len));
    return 1;
}

pub export fn sa_net_socket_addr_v6_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    var raw: [16]u8 = undefined;
    @memcpy(raw[0..], addr[0..16]);
    const segments = readIpv6SegmentsNative(&raw);
    const port = std.mem.readInt(u16, addr[16..18], .little);
    const scope_id = std.mem.readInt(u32, addr[24..28], .little);
    var ip_buf: [64]u8 = undefined;
    const ip_text = formatIpv6Segments(&ip_buf, &segments) catch return 0;
    if (scope_id == 0) {
        const text = std.fmt.bufPrint(buffer, "[{s}]:{d}", .{ ip_text, port }) catch return 0;
        len_ptr.* = @as(u64, @intCast(text.len));
        return 1;
    }
    const text = std.fmt.bufPrint(buffer, "[{s}%{d}]:{d}", .{ ip_text, scope_id, port }) catch return 0;
    len_ptr.* = @as(u64, @intCast(text.len));
    return 1;
}

pub export fn sa_net_unix_addr_kind(addr: u64) u32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse return SA_NET_UNIX_ADDR_UNNAMED;
    return switch (resource.*) {
        .unix_addr => |unix_addr| unix_addr.kind,
        else => SA_NET_UNIX_ADDR_UNNAMED,
    };
}

pub export fn sa_net_unix_addr_is_unnamed(addr: u64) u8 {
    return if (sa_net_unix_addr_kind(addr) == SA_NET_UNIX_ADDR_UNNAMED) 1 else 0;
}

pub export fn sa_net_unix_addr_path_ptr(addr: u64) ?[*]u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse return null;
    return switch (resource.*) {
        .unix_addr => |unix_addr| if (unix_addr.kind == SA_NET_UNIX_ADDR_PATHNAME and unix_addr.bytes.len != 0) unix_addr.bytes.ptr else null,
        else => null,
    };
}

pub export fn sa_net_unix_addr_path_len(addr: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse return 0;
    return switch (resource.*) {
        .unix_addr => |unix_addr| if (unix_addr.kind == SA_NET_UNIX_ADDR_PATHNAME) @as(u64, @intCast(unix_addr.bytes.len)) else 0,
        else => 0,
    };
}

pub export fn sa_net_unix_addr_abstract_ptr(addr: u64) ?[*]u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse return null;
    return switch (resource.*) {
        .unix_addr => |unix_addr| if (unix_addr.kind == SA_NET_UNIX_ADDR_ABSTRACT and unix_addr.bytes.len != 0) unix_addr.bytes.ptr else null,
        else => null,
    };
}

pub export fn sa_net_unix_addr_abstract_len(addr: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse return 0;
    return switch (resource.*) {
        .unix_addr => |unix_addr| if (unix_addr.kind == SA_NET_UNIX_ADDR_ABSTRACT) @as(u64, @intCast(unix_addr.bytes.len)) else 0,
        else => 0,
    };
}

pub export fn sa_net_unix_addr_free(addr: u64) Fallible(i32) {
    const status = sa_std_close(addr);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}
