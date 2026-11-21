const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const FallibleI32 = @import("w01.zig").FallibleI32;
const FallibleU64 = @import("w01.zig").FallibleU64;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("w01.zig").SA_STD_ERR_IO;
const SA_STD_ERR_UNSUPPORTED = @import("w01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const UdpResource = @import("w01.zig").UdpResource;
const constBytes = @import("w02.zig").constBytes;
const failU64 = @import("w02.zig").failU64;
const finish = @import("w02.zig").finish;
const finishErr = @import("w02.zig").finishErr;
const formatIpv6Segments = @import("w13.zig").formatIpv6Segments;
const last_error = @import("w01.zig").last_error;
const mutBytes = @import("w02.zig").mutBytes;
const netAddrSlotLocked = @import("w03.zig").netAddrSlotLocked;
const net_addr_mutex = @import("w02.zig").net_addr_mutex;
const net_addr_slots = @import("w02.zig").net_addr_slots;
const okU64 = @import("w02.zig").okU64;
const parseIpv4Ascii = @import("w03.zig").parseIpv4Ascii;
const parsePortAscii = @import("w03.zig").parsePortAscii;
const registerNetAddr = @import("w03.zig").registerNetAddr;
const registerUdp = @import("w03.zig").registerUdp;
const resolveOne = @import("w03.zig").resolveOne;
const sa_io_write_all = @import("w10.zig").sa_io_write_all;
const sa_std_close = @import("w10.zig").sa_std_close;
const sa_std_net_tcp_accept = @import("w11.zig").sa_std_net_tcp_accept;
const sa_std_net_tcp_connect = @import("w11.zig").sa_std_net_tcp_connect;
const sa_std_net_tcp_listen = @import("w11.zig").sa_std_net_tcp_listen;
const sa_std_net_tcp_listener_local_addr = @import("w11.zig").sa_std_net_tcp_listener_local_addr;
const sa_std_net_tcp_stream_peek = @import("w11.zig").sa_std_net_tcp_stream_peek;
const sa_std_net_tcp_stream_read = @import("w11.zig").sa_std_net_tcp_stream_read;
const sa_std_net_tcp_stream_set_nodelay = @import("w11.zig").sa_std_net_tcp_stream_set_nodelay;
const sa_std_net_tcp_stream_set_nonblocking = @import("w11.zig").sa_std_net_tcp_stream_set_nonblocking;
const sa_std_net_tcp_stream_set_ttl = @import("w11.zig").sa_std_net_tcp_stream_set_ttl;
const sa_std_net_tcp_stream_write = @import("w11.zig").sa_std_net_tcp_stream_write;
const tcpGetOption = @import("w11.zig").tcpGetOption;
const tcpSetOption = @import("w11.zig").tcpSetOption;
const timeoutMs = @import("w02.zig").timeoutMs;
const udpSlotLocked = @import("w03.zig").udpSlotLocked;
const udp_mutex = @import("w02.zig").udp_mutex;
const udp_slots = @import("w02.zig").udp_slots;

pub export fn sa_std_net_tcp_stream_ttl(h: u64, out: ?*u32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    var value: i32 = 0;
    const status = tcpGetOption(h, false, std.posix.IPPROTO.IP, 4, &value);
    if (status == SA_STD_OK and value >= 0) result.* = @intCast(value);
    return status;
}

pub export fn sa_std_net_tcp_listener_ttl(h: u64, out: ?*u32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    var value: i32 = 0;
    const status = tcpGetOption(h, true, std.posix.IPPROTO.IP, 4, &value);
    if (status == SA_STD_OK and value >= 0) result.* = @intCast(value);
    return status;
}

pub export fn sa_std_net_tcp_stream_set_read_timeout(h: u64, ns: u64) i32 {
    const value = timeoutMs(ns) catch |err| return finishErr(err);
    return tcpSetOption(h, false, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, value);
}

pub export fn sa_std_net_tcp_stream_set_write_timeout(h: u64, ns: u64) i32 {
    const value = timeoutMs(ns) catch |err| return finishErr(err);
    return tcpSetOption(h, false, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, value);
}

pub export fn sa_std_net_tcp_stream_read_timeout(h: u64, out_timeout_ns: ?*u64) i32 {
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var ms: i32 = 0;
    const status = tcpGetOption(h, false, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, &ms);
    if (status != SA_STD_OK) return status;
    out.* = std.math.mul(u64, @intCast(@max(ms, 0)), std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_write_timeout(h: u64, out_timeout_ns: ?*u64) i32 {
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var ms: i32 = 0;
    const status = tcpGetOption(h, false, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, &ms);
    if (status != SA_STD_OK) return status;
    out.* = std.math.mul(u64, @intCast(@max(ms, 0)), std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_take_error(h: u64, out: ?*i32) i32 {
    return tcpGetOption(h, false, std.posix.SOL.SOCKET, std.posix.SO.ERROR, out);
}

pub export fn sa_std_net_tcp_stream_set_keepalive(h: u64, enabled: i32) i32 {
    _ = h;
    _ = enabled;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_stream_keepalive(h: u64, out: ?*i32) i32 {
    _ = h;
    if (out) |value| value.* = 0 else return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_stream_set_keepalive_params(h: u64, idle_secs: u32, interval_secs: u32, count: u32) i32 {
    _ = h;
    _ = idle_secs;
    _ = interval_secs;
    _ = count;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_listener_take_error(h: u64, out: ?*i32) i32 {
    return tcpGetOption(h, true, std.posix.SOL.SOCKET, std.posix.SO.ERROR, out);
}

pub export fn sa_std_net_tcp_listener_set_reuseaddr(h: u64, enabled: i32) i32 {
    _ = h;
    _ = enabled;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_listener_set_reuseport(h: u64, enabled: i32) i32 {
    _ = h;
    _ = enabled;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_stream_set_recv_buffer_size(h: u64, size: u32) i32 {
    if (size > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return tcpSetOption(h, false, std.posix.SOL.SOCKET, std.os.windows.ws2_32.SO.RCVBUF, @intCast(size));
}

pub export fn sa_std_net_tcp_stream_recv_buffer_size(h: u64, out: ?*u32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    var value: i32 = 0;
    const status = tcpGetOption(h, false, std.posix.SOL.SOCKET, std.os.windows.ws2_32.SO.RCVBUF, &value);
    if (status == SA_STD_OK and value >= 0) result.* = @intCast(value);
    return status;
}

pub export fn sa_std_net_tcp_stream_set_send_buffer_size(h: u64, size: u32) i32 {
    if (size > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return tcpSetOption(h, false, std.posix.SOL.SOCKET, std.os.windows.ws2_32.SO.SNDBUF, @intCast(size));
}

pub export fn sa_std_net_tcp_stream_send_buffer_size(h: u64, out: ?*u32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    var value: i32 = 0;
    const status = tcpGetOption(h, false, std.posix.SOL.SOCKET, std.os.windows.ws2_32.SO.SNDBUF, &value);
    if (status == SA_STD_OK and value >= 0) result.* = @intCast(value);
    return status;
}

pub export fn sa_std_net_tcp_stream_set_quickack(h: u64, enabled: i32) i32 {
    _ = h;
    _ = enabled;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_stream_quickack(h: u64, out: ?*i32) i32 {
    _ = h;
    if (out) |value| value.* = 0 else return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_stream_set_deferaccept(h: u64, seconds: u32) i32 {
    _ = h;
    _ = seconds;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_stream_deferaccept(h: u64, out: ?*u32) i32 {
    _ = h;
    if (out) |value| value.* = 0 else return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_stream_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    if (out_handle) |out| out.* = 0 else return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_net_tcp_stream_peek(stream: u64, out: ?[*]u8, cap: u64) i32 {
    var read: u64 = 0;
    const status = sa_std_net_tcp_stream_peek(stream, out, cap, &read);
    // Count wrapper: errors go out negated (see sa_std.zig,
    // W1-DEF-NET-WRITE-AFTER-SHUTDOWN).
    if (status != SA_STD_OK) return -status;
    return finish(@as(i32, @intCast(read)));
}

pub export fn sa_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32) FallibleU64 {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_connect(host_ptr, host_len, port, &handle);
    if (status != SA_STD_OK) return failU64(status);
    return okU64(handle);
}

pub export fn sa_net_tcp_stream_read(stream: u64, out: ?[*]u8, cap: u64) FallibleU64 {
    var read: u64 = 0;
    const status = sa_std_net_tcp_stream_read(stream, out, cap, &read);
    if (status != SA_STD_OK) return failU64(status);
    return okU64(read);
}

pub export fn sa_net_tcp_stream_write(stream: u64, out: ?[*]const u8, len: u64) i32 {
    var written: u64 = 0;
    const status = sa_std_net_tcp_stream_write(stream, out, len, &written);
    if (status != SA_STD_OK) return -status;
    return finish(@as(i32, @intCast(written)));
}

pub export fn sa_net_tcp_stream_write_all(stream: u64, out: ?[*]const u8, len: u64) FallibleI32 {
    const status = sa_io_write_all(stream, out, len);
    if (status != SA_STD_OK) return .{ .status = finish(status), .value = 0 };
    return .{ .status = finish(SA_STD_OK), .value = 0 };
}

pub export fn sa_net_tcp_stream_read_exact(stream: u64, out: ?[*]u8, len: u64) FallibleI32 {
    var remaining: u64 = len;
    var cursor: u64 = 0;
    while (remaining != 0) {
        var chunk: u64 = 0;
        const status = sa_std_net_tcp_stream_read(stream, if (out) |p| p + cursor else null, remaining, &chunk);
        if (status != SA_STD_OK) return .{ .status = finish(status), .value = 0 };
        if (chunk == 0) return .{ .status = finish(SA_STD_ERR_IO), .value = 0 };
        cursor += chunk;
        remaining -= chunk;
    }
    return .{ .status = finish(SA_STD_OK), .value = 0 };
}

pub export fn sa_net_tcp_stream_flush(stream: u64) i32 {
    _ = stream;
    return finish(SA_STD_OK);
}

pub export fn sa_net_tcp_stream_set_read_timeout(stream: u64, timeout_ns: u64) i32 {
    return sa_std_net_tcp_stream_set_read_timeout(stream, timeout_ns);
}

pub export fn sa_net_tcp_stream_set_write_timeout(stream: u64, timeout_ns: u64) i32 {
    return sa_std_net_tcp_stream_set_write_timeout(stream, timeout_ns);
}

pub export fn sa_net_tcp_stream_set_nonblocking(stream: u64, enabled: i32) i32 {
    return sa_std_net_tcp_stream_set_nonblocking(stream, enabled);
}

pub export fn sa_net_tcp_stream_set_nodelay(stream: u64, enabled: i32) i32 {
    return sa_std_net_tcp_stream_set_nodelay(stream, enabled);
}

pub export fn sa_net_tcp_stream_set_ttl(stream: u64, ttl: u32) i32 {
    return sa_std_net_tcp_stream_set_ttl(stream, ttl);
}

pub export fn sa_net_tcp_stream_close(stream: u64) FallibleI32 {
    const status = sa_std_close(stream);
    if (status != SA_STD_OK) return .{ .status = finish(status), .value = 0 };
    return .{ .status = finish(SA_STD_OK), .value = 0 };
}

pub export fn sa_net_tcp_listener_bind(host_ptr: ?[*]const u8, host_len: u64, port: u16) FallibleU64 {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_listen(host_ptr, host_len, port, &handle, null);
    if (status != SA_STD_OK) return failU64(status);
    return okU64(handle);
}

pub export fn sa_net_tcp_listener_accept(listener: u64) FallibleU64 {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_accept(listener, &handle);
    if (status != SA_STD_OK) return failU64(status);
    return okU64(handle);
}

pub export fn sa_net_tcp_listener_local_addr(listener: u64) FallibleU64 {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_listener_local_addr(listener, &handle);
    if (status != SA_STD_OK) return failU64(status);
    return okU64(handle);
}

pub export fn sa_net_tcp_listener_close(listener: u64) FallibleI32 {
    const status = sa_std_close(listener);
    if (status != SA_STD_OK) return .{ .status = finish(status), .value = 0 };
    return .{ .status = finish(SA_STD_OK), .value = 0 };
}

pub export fn sa_net_socket_addr_v4_parse_ascii(text_ptr: ?[*]const u8, text_len: u64, out_socket_addr: ?[*]u8) i32 {
    const out = out_socket_addr orelse return 0;
    for (out[0..8]) |*byte| byte.* = 0;

    const text = constBytes(text_ptr, text_len) catch return 0;
    const colon = std.mem.lastIndexOfScalar(u8, text, ':') orelse return 0;
    const ip = parseIpv4Ascii(text[0..colon]) orelse return 0;
    const port = parsePortAscii(text[colon + 1 ..]) orelse return 0;
    @memcpy(out[0..4], &ip);
    std.mem.writeInt(u16, out[4..6], port, .little);
    return 1;
}

pub fn udpHost(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const host = try constBytes(ptr, len);
    if (host.len == 0 or std.mem.indexOfScalar(u8, host, 0) != null) return error.InvalidArgument;
    return host;
}

pub fn udpAddress(host: []const u8, port: u32) !std.Io.net.IpAddress {
    if (port > std.math.maxInt(u16)) return error.InvalidArgument;
    return resolveOne(host, @intCast(port)) catch return error.FileNotFound;
}

pub fn addressHostAlloc(address: std.Io.net.IpAddress) ![]u8 {
    return switch (address) {
        .ip4 => |v| try std.fmt.allocPrint(std.heap.page_allocator, "{d}.{d}.{d}.{d}", .{ v.bytes[0], v.bytes[1], v.bytes[2], v.bytes[3] }),
        .ip6 => |v| {
            var segments: [8]u16 = undefined;
            for (0..8) |i| segments[i] = std.mem.readInt(u16, v.bytes[i * 2 ..][0..2], .big);
            var buf: [64]u8 = undefined;
            const text = try formatIpv6Segments(&buf, &segments);
            return try std.heap.page_allocator.dupe(u8, text);
        },
    };
}

pub fn registerAddress(address: std.Io.net.IpAddress, out: *u64) i32 {
    const host = addressHostAlloc(address) catch |err| return finishErr(err);
    const family: u32 = switch (address) {
        .ip4 => 2,
        .ip6 => 10,
    };
    const scope_id: u64 = switch (address) {
        .ip4 => 0,
        .ip6 => |v| v.interface.index,
    };
    const handle = registerNetAddr(.{ .host = host, .family = family, .port = address.getPort(), .scope_id = scope_id }) catch |err| {
        std.heap.page_allocator.free(host);
        return finishErr(err);
    };
    out.* = handle;
    return finish(SA_STD_OK);
}

pub fn udpResource(handle: u64) ?*UdpResource {
    const idx = udpSlotLocked(handle) orelse return null;
    return &udp_slots.items[idx].?;
}

pub fn udpAddressFromHandle(addr_handle: u64) !std.Io.net.IpAddress {
    while (!net_addr_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = netAddrSlotLocked(addr_handle) orelse {
        net_addr_mutex.unlock();
        return error.InvalidHandle;
    };
    const resource = net_addr_slots.items[idx].?;
    const host = std.heap.page_allocator.dupe(u8, resource.host) catch |err| {
        net_addr_mutex.unlock();
        return err;
    };
    const port = resource.port;
    net_addr_mutex.unlock();
    defer std.heap.page_allocator.free(host);
    return std.Io.net.IpAddress.resolve(sio.io(), host, port);
}

pub export fn sa_std_net_udp_try_clone(socket: u64, out_handle: ?*u64) i32 {
    _ = socket;
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_udp_bind(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const host = udpHost(host_ptr, host_len) catch |err| return finishErr(err);
    const address = udpAddress(host, port) catch |err| return finishErr(err);
    var socket = std.Io.net.IpAddress.bind(&address, sio.io(), .{
        .mode = .dgram,
        .allow_broadcast = true,
    }) catch |err| return finishErr(err);
    errdefer socket.close(sio.io());
    out.* = registerUdp(.{ .socket = socket }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_udp_local_addr(socket: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return registerAddress(resource.socket.address, out);
}

pub export fn sa_std_net_udp_peer_addr(socket: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const peer = resource.peer orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return registerAddress(peer, out);
}

pub export fn sa_std_net_udp_connect(socket: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32) i32 {
    const host = udpHost(host_ptr, host_len) catch |err| return finishErr(err);
    const address = udpAddress(host, port) catch |err| return finishErr(err);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.peer = address;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_connect_addr(socket: u64, addr_handle: u64) i32 {
    const address = udpAddressFromHandle(addr_handle) catch |err| return finishErr(err);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.peer = address;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_only_v6(socket: u64, enabled: i32) i32 {
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.options.only_v6 = if (enabled != 0) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_only_v6(socket: u64, out: ?*i32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    result.* = resource.options.only_v6;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_nonblocking(socket: u64, enabled: i32) i32 {
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.options.nonblocking = if (enabled != 0) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_read_timeout(socket: u64, timeout_ns: u64) i32 {
    const value = timeoutMs(timeout_ns) catch |err| return finishErr(err);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.options.recv_timeout_ms = value;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_write_timeout(socket: u64, timeout_ns: u64) i32 {
    const value = timeoutMs(timeout_ns) catch |err| return finishErr(err);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.options.send_timeout_ms = value;
    return finish(SA_STD_OK);
}

pub fn udpGetOption(socket: u64, option: i32, out: *i32) i32 {
    out.* = 0;
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = switch (option) {
        std.posix.SO.RCVTIMEO => resource.options.recv_timeout_ms,
        std.posix.SO.SNDTIMEO => resource.options.send_timeout_ms,
        std.posix.SO.RCVBUF => resource.options.recv_buf,
        std.posix.SO.SNDBUF => resource.options.send_buf,
        std.posix.SO.ERROR => resource.options.last_error,
        std.posix.SO.BROADCAST => resource.broadcast,
        4 => resource.options.ttl,
        27 => resource.options.only_v6,
        else => return finish(SA_STD_ERR_UNSUPPORTED),
    };
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_recv_buffer_size(socket: u64, size: u32) i32 {
    if (size > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.options.recv_buf = @intCast(size);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_recv_buffer_size(socket: u64, out: ?*u32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    var value: i32 = 0;
    const status = udpGetOption(socket, std.posix.SO.RCVBUF, &value);
    if (status == SA_STD_OK and value >= 0) result.* = @intCast(value);
    return status;
}

pub export fn sa_std_net_udp_set_send_buffer_size(socket: u64, size: u32) i32 {
    if (size > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.options.send_buf = @intCast(size);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_send_buffer_size(socket: u64, out: ?*u32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    var value: i32 = 0;
    const status = udpGetOption(socket, std.posix.SO.SNDBUF, &value);
    if (status == SA_STD_OK and value >= 0) result.* = @intCast(value);
    return status;
}

pub export fn sa_std_net_udp_read_timeout(socket: u64, out_timeout_ns: ?*u64) i32 {
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var ms: i32 = 0;
    const status = udpGetOption(socket, std.posix.SO.RCVTIMEO, &ms);
    if (status != SA_STD_OK) return status;
    out.* = std.math.mul(u64, @intCast(@max(ms, 0)), std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_write_timeout(socket: u64, out_timeout_ns: ?*u64) i32 {
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var ms: i32 = 0;
    const status = udpGetOption(socket, std.posix.SO.SNDTIMEO, &ms);
    if (status != SA_STD_OK) return status;
    out.* = std.math.mul(u64, @intCast(@max(ms, 0)), std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_broadcast(socket: u64, enabled: i32) i32 {
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.broadcast = if (enabled != 0) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_broadcast(socket: u64, out_enabled: ?*i32) i32 {
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpGetOption(socket, std.posix.SO.BROADCAST, out);
}

pub export fn sa_std_net_udp_set_ttl(socket: u64, ttl: u32) i32 {
    if (ttl > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.options.ttl = @intCast(ttl);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_ttl(socket: u64, out_ttl: ?*u32) i32 {
    const out = out_ttl orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    if (resource.options.ttl < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @intCast(resource.options.ttl);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_take_error(socket: u64, out_error: ?*i32) i32 {
    const out = out_error orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpGetOption(socket, std.posix.SO.ERROR, out);
}

pub export fn sa_std_net_udp_send(socket: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const out = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const peer = resource.peer orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.socket.send(sio.io(), &peer, bytes) catch |err| return finishErr(err);
    out.* = bytes.len;
    return finish(SA_STD_OK);
}

pub fn udpReceiveFrom(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    if (out_addr) |ptr| ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const message = resource.socket.receive(sio.io(), buffer) catch |err| return finishErr(err);
    read_ptr.* = message.data.len;
    if (out_addr) |ptr| return registerAddress(message.from, ptr);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_recv(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    return udpReceiveFrom(socket, out, cap, out_read, null);
}

pub export fn sa_std_net_udp_peek(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    _ = socket;
    _ = out;
    _ = cap;
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
