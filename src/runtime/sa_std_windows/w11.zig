const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const FallibleI32 = @import("w01.zig").FallibleI32;
const SA_NET_IOV_MAX = @import("w01.zig").SA_NET_IOV_MAX;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_TRUNCATED = @import("w01.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_ERR_UNSUPPORTED = @import("w01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const SockOptions = @import("w01.zig").SockOptions;
const closeNetAddr = @import("w03.zig").closeNetAddr;
const closeNetAddrList = @import("w03.zig").closeNetAddrList;
const constBytes = @import("w02.zig").constBytes;
const dnsResolveList = @import("w03.zig").dnsResolveList;
const finish = @import("w02.zig").finish;
const finishErr = @import("w02.zig").finishErr;
const last_error = @import("w01.zig").last_error;
const mutBytes = @import("w02.zig").mutBytes;
const netAddrListSlotLocked = @import("w03.zig").netAddrListSlotLocked;
const netAddrSlotLocked = @import("w03.zig").netAddrSlotLocked;
const net_addr_list_mutex = @import("w02.zig").net_addr_list_mutex;
const net_addr_list_slots = @import("w02.zig").net_addr_list_slots;
const net_addr_mutex = @import("w02.zig").net_addr_mutex;
const net_addr_slots = @import("w02.zig").net_addr_slots;
const parseIpv4Ascii = @import("w03.zig").parseIpv4Ascii;
const pathBytes = @import("w02.zig").pathBytes;
const registerNetAddrList = @import("w03.zig").registerNetAddrList;
const registerSocketAddress = @import("w03.zig").registerSocketAddress;
const registerTcpListenerLocked = @import("w03.zig").registerTcpListenerLocked;
const registerTcpStreamLocked = @import("w03.zig").registerTcpStreamLocked;
const resolveSocketAddress = @import("w03.zig").resolveSocketAddress;
const sa_net_iov = @import("w01.zig").sa_net_iov;
const tcpListenerSlotLocked = @import("w03.zig").tcpListenerSlotLocked;
const tcpStreamSlotLocked = @import("w03.zig").tcpStreamSlotLocked;
const tcp_listener_slots = @import("w02.zig").tcp_listener_slots;
const tcp_mutex = @import("w02.zig").tcp_mutex;
const tcp_stream_free_slots = @import("w02.zig").tcp_stream_free_slots;
const tcp_stream_slots = @import("w02.zig").tcp_stream_slots;
const timeoutMs = @import("w02.zig").timeoutMs;
const windows_ipproto_ipv6 = @import("w13.zig").windows_ipproto_ipv6;

pub export fn sa_net_addr_host(addr: u64) ?[*]u8 {
    while (!net_addr_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return null;
    };
    return net_addr_slots.items[idx].?.host.ptr;
}

pub export fn sa_net_addr_host_len(addr: u64) u64 {
    while (!net_addr_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return @as(u64, @intCast(net_addr_slots.items[idx].?.host.len));
}

pub export fn sa_net_addr_port(addr: u64) u32 {
    while (!net_addr_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return @as(u32, net_addr_slots.items[idx].?.port);
}

pub export fn sa_net_addr_family(addr: u64) u32 {
    while (!net_addr_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return net_addr_slots.items[idx].?.family;
}

pub export fn sa_net_addr_scope_id(addr: u64) u64 {
    while (!net_addr_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return net_addr_slots.items[idx].?.scope_id;
}

pub export fn sa_std_net_addr_format(addr: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_ptr.* = 0;
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    while (!net_addr_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = net_addr_slots.items[idx].?;
    const text = if (resource.family == 23 and resource.scope_id != 0)
        std.fmt.bufPrint(buffer, "[{s}%{d}]:{d}", .{ resource.host, resource.scope_id, resource.port }) catch return finish(SA_STD_ERR_TRUNCATED)
    else if (resource.family == 23)
        std.fmt.bufPrint(buffer, "[{s}]:{d}", .{ resource.host, resource.port }) catch return finish(SA_STD_ERR_TRUNCATED)
    else
        std.fmt.bufPrint(buffer, "{s}:{d}", .{ resource.host, resource.port }) catch return finish(SA_STD_ERR_TRUNCATED);
    len_ptr.* = @intCast(text.len);
    return finish(SA_STD_OK);
}

pub export fn sa_net_addr_free(addr: u64) FallibleI32 {
    const status = closeNetAddr(addr);
    if (status != SA_STD_OK) return .{ .status = status, .value = 0 };
    return .{ .status = SA_STD_OK, .value = 0 };
}

pub export fn sa_net_ipv4_parse_ascii(text_ptr: ?[*]const u8, text_len: u64, out_addr: ?[*]u8) i32 {
    const out = out_addr orelse return 0;
    out[0] = 0;
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;

    const text = constBytes(text_ptr, text_len) catch return 0;
    const parts = parseIpv4Ascii(text) orelse return 0;
    @memcpy(out[0..4], &parts);
    return 1;
}

pub export fn sa_std_net_to_socket_addr_list(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    if (port > std.math.maxInt(u16)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = registerNetAddrList(host, @intCast(port)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_addr_list_next(list_handle: u64, out_ok: ?*i32, out_addr: ?*u64) i32 {
    const ok_ptr = out_ok orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const addr_ptr = out_addr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ok_ptr.* = 0;
    addr_ptr.* = 0;
    while (!net_addr_list_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_list_mutex.unlock();
    const idx = netAddrListSlotLocked(list_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const list = &net_addr_list_slots.items[idx].?;
    if (list.next_index >= list.addresses.len) return finish(SA_STD_OK);
    const address = list.addresses[list.next_index];
    list.next_index += 1;
    addr_ptr.* = registerSocketAddress(address) catch |err| {
        list.next_index -= 1;
        return finishErr(err);
    };
    ok_ptr.* = 1;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_addr_list_remaining(list_handle: u64, out_remaining: ?*u64) i32 {
    const out = out_remaining orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!net_addr_list_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_list_mutex.unlock();
    const idx = netAddrListSlotLocked(list_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const list = &net_addr_list_slots.items[idx].?;
    out.* = @as(u64, @intCast(list.addresses.len -| list.next_index));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_addr_list_reset(list_handle: u64) i32 {
    while (!net_addr_list_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_list_mutex.unlock();
    const idx = netAddrListSlotLocked(list_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    net_addr_list_slots.items[idx].?.next_index = 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_addr_list_free(list_handle: u64) i32 {
    return closeNetAddrList(list_handle);
}

pub export fn sa_std_net_to_socket_addr_first(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const address = resolveSocketAddress(host_ptr, host_len, port) catch |err| return finishErr(err);
    out.* = registerSocketAddress(address) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    if (port > std.math.maxInt(u16)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const hn = std.Io.net.HostName.init(host) catch |err| return finishErr(err);
    var stream = hn.connect(sio.io(), @intCast(port), .{ .mode = .stream }) catch |err| return finishErr(err);
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    out.* = registerTcpStreamLocked(stream) catch |err| {
        stream.close(sio.io());
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect_timeout(host_ptr: ?[*]const u8, host_len: u64, port: u32, timeout_ns: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    if (timeout_ns == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const timeout_ms = timeoutMs(timeout_ns) catch |err| return finishErr(err);
    const address = resolveSocketAddress(host_ptr, host_len, port) catch |err| return finishErr(err);
    var stream = tcpConnectAddressTimeout(address, timeout_ms) catch |err| return finishErr(err);
    errdefer stream.close(sio.io());
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    out.* = registerTcpStreamLocked(stream) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect_timeout_addr(addr_handle: u64, timeout_ns: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const timeout_ms = timeoutMs(timeout_ns) catch |err| return finishErr(err);
    while (!net_addr_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const address = blk: {
        const idx = netAddrSlotLocked(addr_handle) orelse {
            net_addr_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        };
        const resource = net_addr_slots.items[idx].?;
        if (resource.family != 2 and resource.family != 10) {
            net_addr_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_ARGUMENT);
        }
        var parsed = std.Io.net.IpAddress.resolve(sio.io(), resource.host, resource.port) catch |err| {
            net_addr_mutex.unlock();
            return finishErr(err);
        };
        const parsed_is_v4 = switch (parsed) {
            .ip4 => true,
            .ip6 => false,
        };
        if ((resource.family == 2 and !parsed_is_v4) or
            (resource.family == 10 and parsed_is_v4)) {
            net_addr_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_ARGUMENT);
        }
        if (resource.family == 10 and resource.scope_id != 0) parsed.ip6.interface = .{ .index = @intCast(resource.scope_id) };
        break :blk parsed;
    };
    net_addr_mutex.unlock();
    var stream = tcpConnectAddressTimeout(address, timeout_ms) catch |err| return finishErr(err);
    errdefer stream.close(sio.io());
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    out.* = registerTcpStreamLocked(stream) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub fn tcpConnectAddressTimeout(address: std.Io.net.IpAddress, timeout_ms: i32) !std.Io.net.Stream {
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(@as(i64, timeout_ms)), .clock = .awake } };
    return address.connect(sio.io(), .{ .mode = .stream, .timeout = timeout });
}

pub export fn sa_std_net_tcp_connect_timeout_all(host_ptr: ?[*]const u8, host_len: u64, port: u32, timeout_ns: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const timeout_ms = timeoutMs(timeout_ns) catch |err| return finishErr(err);
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    if (port > std.math.maxInt(u16)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const addrs = dnsResolveList(std.heap.page_allocator, host, @intCast(port)) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(addrs);
    if (addrs.len == 0) return finishErr(error.HostLacksNetworkAddresses);
    var last_connect_error: anyerror = error.ConnectionRefused;
    for (addrs) |address| {
        var stream = tcpConnectAddressTimeout(address, timeout_ms) catch |err| {
            last_connect_error = err;
            continue;
        };
        while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
        out.* = registerTcpStreamLocked(stream) catch |err| {
            tcp_mutex.unlock();
            stream.close(sio.io());
            return finishErr(err);
        };
        tcp_mutex.unlock();
        return finish(SA_STD_OK);
    }
    return finishErr(last_connect_error);
}

pub export fn sa_std_net_tcp_listen(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64, out_bound_port: ?*u32) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    if (out_bound_port) |bound| bound.* = 0;
    const address = resolveSocketAddress(host_ptr, host_len, port) catch |err| return finishErr(err);
    var server = address.listen(sio.io(), .{ .reuse_address = true, .mode = .stream }) catch |err| return finishErr(err);
    const bound_port = server.socket.address.getPort();
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    out.* = registerTcpListenerLocked(server) catch |err| {
        server.deinit(sio.io());
        return finishErr(err);
    };
    if (out_bound_port) |bound| bound.* = bound_port;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_accept(listener_handle: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = tcpListenerSlotLocked(listener_handle) orelse {
        tcp_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    var server = tcp_listener_slots.items[idx].?.server;
    tcp_mutex.unlock();
    var connection = server.accept(sio.io()) catch |err| return finishErr(err);
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    out.* = registerTcpStreamLocked(connection) catch |err| {
        connection.close(sio.io());
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_accept_addr(listener_handle: u64, out_stream: ?*u64, out_addr: ?*u64) i32 {
    const stream_out = out_stream orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const addr_out = out_addr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    stream_out.* = 0;
    addr_out.* = 0;
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = tcpListenerSlotLocked(listener_handle) orelse {
        tcp_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    var server = tcp_listener_slots.items[idx].?.server;
    tcp_mutex.unlock();
    var connection = server.accept(sio.io()) catch |err| return finishErr(err);
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const stream_handle = registerTcpStreamLocked(connection) catch |err| {
        tcp_mutex.unlock();
        connection.close(sio.io());
        return finishErr(err);
    };
    // 0.17 `Server.accept` no longer reports the peer address; register the
    // accepted socket's local address so the out-param stays populated.
    const addr_handle = registerSocketAddress(connection.socket.address) catch |err| {
        if (tcpStreamSlotLocked(stream_handle)) |stream_idx| {
            var stream_resource = tcp_stream_slots.items[stream_idx].?;
            stream_resource.close();
            tcp_stream_slots.items[stream_idx] = null;
            tcp_stream_free_slots.append(stream_idx) catch {};
        }
        tcp_mutex.unlock();
        return finishErr(err);
    };
    tcp_mutex.unlock();
    stream_out.* = stream_handle;
    addr_out.* = addr_handle;
    return finish(SA_STD_OK);
}

pub fn tcpAddress(handle: u64, peer: bool, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    const stream_idx = tcpStreamSlotLocked(handle);
    const listener_idx = tcpListenerSlotLocked(handle);
    var address: std.Io.net.IpAddress = undefined;
    if (stream_idx) |idx| {
        // Raw getsockname/getpeername have no 0.17 std counterpart on this
        // branch (posix dropped them; os.windows exposes no socket
        // syscalls); fall back to the stream's bound address.
        // NOTE: peer/local distinction is therefore lost here.
        address = tcp_stream_slots.items[idx].?.stream.socket.address;
    } else if (listener_idx) |idx| {
        if (peer) return finish(SA_STD_ERR_INVALID_HANDLE);
        address = tcp_listener_slots.items[idx].?.server.socket.address;
    } else return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = registerSocketAddress(address) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_peer_addr(handle: u64, out: ?*u64) i32 {
    return tcpAddress(handle, true, out);
}

pub export fn sa_std_net_tcp_stream_local_addr(handle: u64, out: ?*u64) i32 {
    return tcpAddress(handle, false, out);
}

pub export fn sa_std_net_tcp_listener_local_addr(handle: u64, out: ?*u64) i32 {
    return tcpAddress(handle, false, out);
}

pub export fn sa_std_net_tcp_stream_read(handle: u64, out_ptr: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const result = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    const bytes = mutBytes(out_ptr, cap) catch |err| return finishErr(err);
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    const idx = tcpStreamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var bufs: [1][]u8 = .{bytes};
    const read_result = tcp_stream_slots.items[idx].?.stream.readWithControl(sio.io(), &bufs, &.{}) catch |err| return finishErr(err);
    const count = read_result.data_len;
    result.* = count;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_write(handle: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const result = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    const idx = tcpStreamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const s = &tcp_stream_slots.items[idx].?.stream;
    var wbuf_net: [8192]u8 = undefined;
    var w_net = s.writer(sio.io(), &wbuf_net);
    w_net.interface.writeAll(bytes) catch |err| return finishErr(err);
    w_net.interface.flush() catch |err| return finishErr(err);
    result.* = bytes.len;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_read_vectored(handle: u64, iovs: [*]const sa_net_iov, iov_count: u64, out_read: ?*u64) i32 {
    const result = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    if (iov_count == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const count = std.math.cast(usize, iov_count) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const slices = iovs[0..count];
    if (slices.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);

    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    const idx = tcpStreamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const stream = &tcp_stream_slots.items[idx].?.stream;

    var bufs: [SA_NET_IOV_MAX][]u8 = undefined;
    var filled: usize = 0;
    for (slices) |slot| {
        if (filled >= bufs.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
        bufs[filled] = slot.base[0..slot.len];
        filled += 1;
    }

    const read_result = stream.readWithControl(sio.io(), bufs[0..filled], &.{}) catch |err| return finishErr(err);
    result.* = read_result.data_len;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_write_vectored(handle: u64, iovs: [*]const sa_net_iov, iov_count: u64, out_written: ?*u64) i32 {
    const result = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    if (iov_count == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const count = std.math.cast(usize, iov_count) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const slices = iovs[0..count];
    if (slices.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);

    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    const idx = tcpStreamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const stream = &tcp_stream_slots.items[idx].?.stream;

    var wbuf_net: [8192]u8 = undefined;
    var w_net = stream.writer(sio.io(), &wbuf_net);
    var total: u64 = 0;
    for (slices) |slot| {
        w_net.interface.writeAll(slot.base[0..slot.len]) catch |err| return finishErr(err);
        total += slot.len;
    }
    w_net.interface.flush() catch |err| return finishErr(err);
    result.* = total;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_peek(handle: u64, out_ptr: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const result = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    _ = handle;
    _ = out_ptr;
    _ = cap;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_listener_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    if (out_handle) |out| out.* = 0 else return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub fn tcpOptionsPtr(handle: u64, listener: bool) ?*SockOptions {
    if (listener) {
        const idx = tcpListenerSlotLocked(handle) orelse return null;
        return &tcp_listener_slots.items[idx].?.options;
    }
    const idx = tcpStreamSlotLocked(handle) orelse return null;
    return &tcp_stream_slots.items[idx].?.options;
}

pub fn tcpSetNonblocking(handle: u64, listener: bool, enabled: i32) i32 {
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    const options = tcpOptionsPtr(handle, listener) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    options.nonblocking = if (enabled != 0) 1 else 0;
    return finish(SA_STD_OK);
}

pub fn tcpSetOption(handle: u64, listener: bool, level: i32, option: u32, value: i32) i32 {
    _ = level;
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    const options = tcpOptionsPtr(handle, listener) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    switch (option) {
        std.posix.SO.RCVTIMEO => options.recv_timeout_ms = value,
        std.posix.SO.SNDTIMEO => options.send_timeout_ms = value,
        std.posix.SO.RCVBUF => options.recv_buf = value,
        std.posix.SO.SNDBUF => options.send_buf = value,
        std.posix.SO.ERROR => options.last_error = value,
        1 => options.nodelay = value,
        4 => options.ttl = value,
        27 => options.only_v6 = value,
        else => return finish(SA_STD_ERR_UNSUPPORTED),
    }
    return finish(SA_STD_OK);
}

pub fn tcpGetOption(handle: u64, listener: bool, level: i32, option: i32, out: ?*i32) i32 {
    _ = level;
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    const options = tcpOptionsPtr(handle, listener) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    result.* = switch (option) {
        std.posix.SO.RCVTIMEO => options.recv_timeout_ms,
        std.posix.SO.SNDTIMEO => options.send_timeout_ms,
        std.posix.SO.RCVBUF => options.recv_buf,
        std.posix.SO.SNDBUF => options.send_buf,
        std.posix.SO.ERROR => options.last_error,
        1 => options.nodelay,
        4 => options.ttl,
        27 => options.only_v6,
        else => return finish(SA_STD_ERR_UNSUPPORTED),
    };
    return finish(SA_STD_OK);
}

pub fn tcpSetLinger(handle: u64, enabled: i32, timeout_ns: u64) i32 {
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    const options = tcpOptionsPtr(handle, false) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    options.linger_on = if (enabled != 0) 1 else 0;
    options.linger_ns = if (enabled != 0) timeout_ns else 0;
    return finish(SA_STD_OK);
}

pub fn tcpGetLinger(handle: u64, out_enabled: *i32, out_timeout_ns: *u64) i32 {
    out_enabled.* = 0;
    out_timeout_ns.* = 0;
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    const options = tcpOptionsPtr(handle, false) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    out_enabled.* = options.linger_on;
    out_timeout_ns.* = options.linger_ns;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_try_clone(stream: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    _ = stream;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_listener_try_clone(listener: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    _ = listener;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_tcp_stream_set_nonblocking(h: u64, enabled: i32) i32 {
    return tcpSetNonblocking(h, false, enabled);
}

pub export fn sa_std_net_tcp_stream_set_linger(h: u64, enabled: i32, timeout_ns: u64) i32 {
    return tcpSetLinger(h, enabled, timeout_ns);
}

pub export fn sa_std_net_tcp_stream_linger(h: u64, out_enabled: ?*i32, out_timeout_ns: ?*u64) i32 {
    const enabled = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const timeout_ns = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return tcpGetLinger(h, enabled, timeout_ns);
}

pub export fn sa_std_net_tcp_listener_set_only_v6(h: u64, enabled: i32) i32 {
    return tcpSetOption(h, true, windows_ipproto_ipv6, 27, if (enabled != 0) 1 else 0);
}

pub export fn sa_std_net_tcp_listener_only_v6(h: u64, out: ?*i32) i32 {
    return tcpGetOption(h, true, windows_ipproto_ipv6, 27, out);
}

pub export fn sa_std_net_tcp_listener_set_nonblocking(h: u64, enabled: i32) i32 {
    return tcpSetNonblocking(h, true, enabled);
}

pub export fn sa_std_net_tcp_stream_set_nodelay(h: u64, enabled: i32) i32 {
    return tcpSetOption(h, false, std.posix.IPPROTO.TCP, 1, if (enabled != 0) 1 else 0);
}

pub export fn sa_std_net_tcp_stream_nodelay(h: u64, out: ?*i32) i32 {
    return tcpGetOption(h, false, std.posix.IPPROTO.TCP, 1, out);
}

pub export fn sa_std_net_tcp_stream_set_ttl(h: u64, ttl: u32) i32 {
    if (ttl > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return tcpSetOption(h, false, std.posix.IPPROTO.IP, 4, @intCast(ttl));
}

pub export fn sa_std_net_tcp_listener_set_ttl(h: u64, ttl: u32) i32 {
    if (ttl > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return tcpSetOption(h, true, std.posix.IPPROTO.IP, 4, @intCast(ttl));
}
