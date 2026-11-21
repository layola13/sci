const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_UNSUPPORTED = @import("w01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const closeUdp = @import("w03.zig").closeUdp;
const constBytes = @import("w02.zig").constBytes;
const finish = @import("w02.zig").finish;
const finishErr = @import("w02.zig").finishErr;
const mutBytes = @import("w02.zig").mutBytes;
const parsePortAscii = @import("w03.zig").parsePortAscii;
const registerAddress = @import("w12.zig").registerAddress;
const sa_net_iov = @import("w01.zig").sa_net_iov;
const sa_std_net_udp_bind = @import("w12.zig").sa_std_net_udp_bind;
const sa_std_net_udp_connect = @import("w12.zig").sa_std_net_udp_connect;
const sa_std_net_udp_local_addr = @import("w12.zig").sa_std_net_udp_local_addr;
const sa_std_net_udp_peek = @import("w12.zig").sa_std_net_udp_peek;
const sa_std_net_udp_recv = @import("w12.zig").sa_std_net_udp_recv;
const sa_std_net_udp_send = @import("w12.zig").sa_std_net_udp_send;
const sa_std_net_udp_set_broadcast = @import("w12.zig").sa_std_net_udp_set_broadcast;
const sa_std_net_udp_set_nonblocking = @import("w12.zig").sa_std_net_udp_set_nonblocking;
const sa_std_net_udp_set_read_timeout = @import("w12.zig").sa_std_net_udp_set_read_timeout;
const sa_std_net_udp_set_ttl = @import("w12.zig").sa_std_net_udp_set_ttl;
const sa_std_net_udp_set_write_timeout = @import("w12.zig").sa_std_net_udp_set_write_timeout;
const udpAddress = @import("w12.zig").udpAddress;
const udpHost = @import("w12.zig").udpHost;
const udpReceiveFrom = @import("w12.zig").udpReceiveFrom;
const udpResource = @import("w12.zig").udpResource;
const udp_mutex = @import("w02.zig").udp_mutex;

pub export fn sa_std_net_udp_send_to(socket: u64, buf: ?[*]const u8, len: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32, out_written: ?*u64) i32 {
    const out = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const host = udpHost(host_ptr, host_len) catch |err| return finishErr(err);
    const address = udpAddress(host, port) catch |err| return finishErr(err);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.socket.send(sio.io(), &address, bytes) catch |err| return finishErr(err);
    out.* = bytes.len;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_recv_from(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    return udpReceiveFrom(socket, out, cap, out_read, out_addr);
}

pub export fn sa_std_net_udp_peek_from(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    _ = socket;
    _ = out;
    _ = cap;
    _ = out_addr;
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub fn udpFlattenSlices(iovs: [*]const sa_net_iov, iov_count: u64, allocator: std.mem.Allocator, out_total: *usize) ![]u8 {
    const count = std.math.cast(usize, iov_count) orelse return error.InvalidArgument;
    const slices = iovs[0..count];
    var total: usize = 0;
    for (slices) |slot| total = std.math.add(usize, total, slot.len) catch return error.InvalidArgument;
    const buffer = try allocator.alloc(u8, total);
    var offset: usize = 0;
    for (slices) |slot| {
        @memcpy(buffer[offset..][0..slot.len], slot.base[0..slot.len]);
        offset += slot.len;
    }
    out_total.* = total;
    return buffer;
}

pub export fn sa_std_net_udp_send_vectored(socket: u64, iovs: [*]const sa_net_iov, iov_count: u64, out_written: ?*u64) i32 {
    const out = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var total: usize = 0;
    const buffer = udpFlattenSlices(iovs, iov_count, std.heap.page_allocator, &total) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(buffer);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const peer = resource.peer orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.socket.send(sio.io(), &peer, buffer) catch |err| return finishErr(err);
    out.* = total;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_send_to_vectored(socket: u64, iovs: [*]const sa_net_iov, iov_count: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32, out_written: ?*u64) i32 {
    const out = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const host = udpHost(host_ptr, host_len) catch |err| return finishErr(err);
    const address = udpAddress(host, port) catch |err| return finishErr(err);
    var total: usize = 0;
    const buffer = udpFlattenSlices(iovs, iov_count, std.heap.page_allocator, &total) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(buffer);
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    resource.socket.send(sio.io(), &address, buffer) catch |err| return finishErr(err);
    out.* = total;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_recv_from_vectored(socket: u64, iovs: [*]const sa_net_iov, iov_count: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    const out = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    if (out_addr) |ptr| ptr.* = 0;
    const count = std.math.cast(usize, iov_count) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const slices = iovs[0..count];
    var total: usize = 0;
    for (slices) |slot| total = std.math.add(usize, total, slot.len) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const buffer = std.heap.page_allocator.alloc(u8, total) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(buffer);

    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const message = resource.socket.receive(sio.io(), buffer) catch |err| return finishErr(err);
    out.* = message.data.len;

    var offset: usize = 0;
    for (slices) |slot| {
        const remaining = message.data.len - offset;
        if (remaining == 0) break;
        const take = @min(remaining, slot.len);
        @memcpy(slot.base[0..take], message.data[offset..][0..take]);
        offset += take;
    }

    if (out_addr) |ptr| return registerAddress(message.from, ptr);
    return finish(SA_STD_OK);
}

pub const windows_ipproto_ipv6: i32 = 41;

pub fn udpMembership4(socket: u64, multi_ptr: ?[*]const u8, multi_len: u64, interface_ptr: ?[*]const u8, interface_len: u64, join: bool) i32 {
    _ = socket;
    _ = multi_ptr;
    _ = multi_len;
    _ = interface_ptr;
    _ = interface_len;
    _ = join;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_udp_join_multicast_v4(socket: u64, m: ?[*]const u8, ml: u64, i: ?[*]const u8, il: u64) i32 {
    return udpMembership4(socket, m, ml, i, il, true);
}

pub export fn sa_std_net_udp_leave_multicast_v4(socket: u64, m: ?[*]const u8, ml: u64, i: ?[*]const u8, il: u64) i32 {
    return udpMembership4(socket, m, ml, i, il, false);
}

pub fn udpMembership6(socket: u64, multi_ptr: ?[*]const u8, multi_len: u64, interface_index: u32, join: bool) i32 {
    _ = socket;
    _ = multi_ptr;
    _ = multi_len;
    _ = interface_index;
    _ = join;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_udp_join_multicast_v6(socket: u64, m: ?[*]const u8, ml: u64, index: u32) i32 {
    return udpMembership6(socket, m, ml, index, true);
}

pub export fn sa_std_net_udp_leave_multicast_v6(socket: u64, m: ?[*]const u8, ml: u64, index: u32) i32 {
    return udpMembership6(socket, m, ml, index, false);
}

pub fn udpSetMulticastInt(socket: u64, field: enum { loop_v6, hops_v6, if_v6, loop_v4, ttl_v4, if_v4 }, value: u32) i32 {
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    switch (field) {
        .loop_v6 => resource.mc_loop_v6 = @intCast(value),
        .hops_v6 => resource.mc_hops_v6 = value,
        .if_v6 => resource.mc_if_v6 = value,
        .loop_v4 => resource.mc_loop_v4 = @intCast(value),
        .ttl_v4 => resource.mc_ttl_v4 = value,
        .if_v4 => resource.mc_if_v4 = value,
    }
    return finish(SA_STD_OK);
}

pub fn udpGetMulticastInt(socket: u64, field: enum { loop_v6, hops_v6, if_v6, loop_v4, ttl_v4, if_v4 }, out: *u32) i32 {
    out.* = 0;
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const resource = udpResource(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = switch (field) {
        .loop_v6 => @intCast(resource.mc_loop_v6),
        .hops_v6 => resource.mc_hops_v6,
        .if_v6 => resource.mc_if_v6,
        .loop_v4 => @intCast(resource.mc_loop_v4),
        .ttl_v4 => resource.mc_ttl_v4,
        .if_v4 => resource.mc_if_v4,
    };
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_multicast_loop_v6(socket: u64, enabled: i32) i32 {
    return udpSetMulticastInt(socket, .loop_v6, if (enabled != 0) 1 else 0);
}

pub export fn sa_std_net_udp_set_multicast_hops_v6(socket: u64, hops: u32) i32 {
    return udpSetMulticastInt(socket, .hops_v6, hops);
}

pub export fn sa_std_net_udp_multicast_loop_v6(socket: u64, out_enabled: ?*i32) i32 {
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var value: u32 = 0;
    const status = udpGetMulticastInt(socket, .loop_v6, &value);
    if (status == SA_STD_OK) out.* = @intCast(value);
    return status;
}

pub export fn sa_std_net_udp_set_multicast_if_v4(socket: u64, interface_addr_ptr: ?[*]const u8) i32 {
    _ = socket;
    _ = interface_addr_ptr;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_udp_multicast_if_v4(socket: u64, out_interface_addr: ?[*]u8) i32 {
    _ = socket;
    _ = out_interface_addr;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_udp_set_multicast_if_v6(socket: u64, interface_index: u32) i32 {
    return udpSetMulticastInt(socket, .if_v6, interface_index);
}

pub export fn sa_std_net_udp_multicast_if_v6(socket: u64, out_interface_index: ?*u32) i32 {
    const out = out_interface_index orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpGetMulticastInt(socket, .if_v6, out);
}

pub export fn sa_std_net_udp_multicast_hops_v6(socket: u64, out_hops: ?*u32) i32 {
    const out = out_hops orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpGetMulticastInt(socket, .hops_v6, out);
}

pub export fn sa_std_net_udp_set_multicast_loop_v4(socket: u64, enabled: i32) i32 {
    return udpSetMulticastInt(socket, .loop_v4, if (enabled != 0) 1 else 0);
}

pub export fn sa_std_net_udp_set_multicast_ttl_v4(socket: u64, ttl: u32) i32 {
    return udpSetMulticastInt(socket, .ttl_v4, ttl);
}

pub export fn sa_std_net_udp_multicast_loop_v4(socket: u64, out_enabled: ?*i32) i32 {
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var value: u32 = 0;
    const status = udpGetMulticastInt(socket, .loop_v4, &value);
    if (status == SA_STD_OK) out.* = @intCast(value);
    return status;
}

pub export fn sa_std_net_udp_multicast_ttl_v4(socket: u64, out_ttl: ?*u32) i32 {
    const out = out_ttl orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpGetMulticastInt(socket, .ttl_v4, out);
}

pub export fn sa_net_udp_bind(h: ?[*]const u8, hl: u64, p: u16) i32 {
    var handle: u64 = 0;
    const s = sa_std_net_udp_bind(h, hl, p, &handle);
    return if (s == SA_STD_OK) @intCast(handle) else s;
}

pub export fn sa_net_udp_local_addr(s: u64) i32 {
    var handle: u64 = 0;
    const status = sa_std_net_udp_local_addr(s, &handle);
    return if (status == SA_STD_OK) @intCast(handle) else status;
}

pub export fn sa_net_udp_connect(s: u64, h: ?[*]const u8, hl: u64, p: u16) i32 {
    return sa_std_net_udp_connect(s, h, hl, p);
}

pub export fn sa_net_udp_set_read_timeout(s: u64, v: u64) i32 {
    return sa_std_net_udp_set_read_timeout(s, v);
}

pub export fn sa_net_udp_set_write_timeout(s: u64, v: u64) i32 {
    return sa_std_net_udp_set_write_timeout(s, v);
}

pub export fn sa_net_udp_set_nonblocking(s: u64, v: i32) i32 {
    return sa_std_net_udp_set_nonblocking(s, v);
}

pub export fn sa_net_udp_set_broadcast(s: u64, v: i32) i32 {
    return sa_std_net_udp_set_broadcast(s, v);
}

pub export fn sa_net_udp_set_ttl(s: u64, v: u32) i32 {
    return sa_std_net_udp_set_ttl(s, v);
}

pub export fn sa_net_udp_set_multicast_loop_v4(s: u64, v: i32) i32 {
    return sa_std_net_udp_set_multicast_loop_v4(s, v);
}

pub export fn sa_net_udp_set_multicast_ttl_v4(s: u64, v: u32) i32 {
    return sa_std_net_udp_set_multicast_ttl_v4(s, v);
}

pub export fn sa_net_udp_send(s: u64, b: ?[*]const u8, l: u64) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_send(s, b, l, &n);
    return if (status == SA_STD_OK) @intCast(n) else -status;
}

pub export fn sa_net_udp_recv(s: u64, b: ?[*]u8, l: u64) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_recv(s, b, l, &n);
    return if (status == SA_STD_OK) @intCast(n) else -status;
}

pub export fn sa_net_udp_peek(s: u64, b: ?[*]u8, l: u64) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_peek(s, b, l, &n);
    return if (status == SA_STD_OK) @intCast(n) else -status;
}

pub export fn sa_net_udp_send_to(s: u64, b: ?[*]const u8, l: u64, h: ?[*]const u8, hl: u64, p: u16) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_send_to(s, b, l, h, hl, p, &n);
    return if (status == SA_STD_OK) @intCast(n) else -status;
}

pub export fn sa_net_udp_recv_from(s: u64, b: ?[*]u8, l: u64, a: ?*u64) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_recv_from(s, b, l, &n, a);
    return if (status == SA_STD_OK) @intCast(n) else -status;
}

pub export fn sa_net_udp_peek_from(s: u64, b: ?[*]u8, l: u64, a: ?*u64) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_peek_from(s, b, l, &n, a);
    return if (status == SA_STD_OK) @intCast(n) else -status;
}

pub export fn sa_net_udp_join_multicast_v4(s: u64, m: ?[*]const u8, ml: u64, i: ?[*]const u8, il: u64) i32 {
    return sa_std_net_udp_join_multicast_v4(s, m, ml, i, il);
}

pub export fn sa_net_udp_leave_multicast_v4(s: u64, m: ?[*]const u8, ml: u64, i: ?[*]const u8, il: u64) i32 {
    return sa_std_net_udp_leave_multicast_v4(s, m, ml, i, il);
}

pub export fn sa_net_udp_join_multicast_v6(s: u64, m: ?[*]const u8, ml: u64, i: u32) i32 {
    return sa_std_net_udp_join_multicast_v6(s, m, ml, i);
}

pub export fn sa_net_udp_leave_multicast_v6(s: u64, m: ?[*]const u8, ml: u64, i: u32) i32 {
    return sa_std_net_udp_leave_multicast_v6(s, m, ml, i);
}

pub export fn sa_net_udp_close(s: u64) i32 {
    return closeUdp(s);
}

pub fn writeIpv6SegmentsNative(out: []u8, octets: *const [16]u8) void {
    for (0..8) |index| {
        const segment = std.mem.readInt(u16, octets[index * 2 ..][0..2], .big);
        std.mem.writeInt(u16, out[index * 2 ..][0..2], segment, .little);
    }
}

pub fn parseIpv6Ascii(text: []const u8) ?struct { octets: [16]u8, scope_id: u32 } {
    const parsed = std.Io.net.Ip6Address.resolve(sio.io(), text, 0) catch return null;
    return .{ .octets = parsed.bytes, .scope_id = parsed.interface.index };
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
    if (text.len < 4 or text[0] != '[') return 0;
    const close = std.mem.lastIndexOfScalar(u8, text, ']') orelse return 0;
    if (close == 1 or close + 1 >= text.len or text[close + 1] != ':') return 0;
    const parsed = parseIpv6Ascii(text[1..close]) orelse return 0;
    const port = parsePortAscii(text[close + 2 ..]) orelse return 0;
    writeIpv6SegmentsNative(out[0..16], &parsed.octets);
    std.mem.writeInt(u16, out[16..18], port, .little);
    std.mem.writeInt(u32, out[24..28], parsed.scope_id, .little);
    return 1;
}

pub fn readIpv6SegmentsNative(raw: *const [16]u8) [8]u16 {
    var segments: [8]u16 = undefined;
    for (0..8) |index| segments[index] = std.mem.readInt(u16, raw[index * 2 ..][0..2], .little);
    return segments;
}

pub fn formatIpv6Segments(buffer: []u8, segments: *const [8]u16) ![]u8 {
    var longest_start: usize = 8;
    var longest_len: usize = 0;
    var current_start: usize = 0;
    var current_len: usize = 0;
    for (segments.*, 0..) |segment, index| {
        if (segment == 0) {
            if (current_len == 0) current_start = index;
            current_len += 1;
            if (current_len > longest_len) {
                longest_start = current_start;
                longest_len = current_len;
            }
        } else {
            current_len = 0;
        }
    }
    if (longest_len < 2) {
        longest_start = 8;
        longest_len = 0;
    }

    var w: std.Io.Writer = .fixed(buffer);
    var i: usize = 0;
    var abbreviated = false;
    while (i < segments.len) : (i += 1) {
        if (i == longest_start) {
            if (!abbreviated) {
                try w.writeAll(if (i == 0) "::" else ":");
                abbreviated = true;
            }
            i += longest_len - 1;
            continue;
        }
        if (abbreviated) abbreviated = false;
        try w.print("{x}", .{segments[i]});
        if (i != segments.len - 1) try w.writeByte(':');
    }
    return buffer[0..w.buffered().len];
}

pub export fn sa_net_ipv4_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    const text = std.fmt.bufPrint(buffer, "{d}.{d}.{d}.{d}", .{ addr[0], addr[1], addr[2], addr[3] }) catch return 0;
    len_ptr.* = @intCast(text.len);
    return 1;
}

pub export fn sa_net_ipv6_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    var raw: [16]u8 = undefined;
    @memcpy(&raw, addr[0..16]);
    const segments = readIpv6SegmentsNative(&raw);
    const text = formatIpv6Segments(buffer, &segments) catch return 0;
    len_ptr.* = @intCast(text.len);
    return 1;
}

pub export fn sa_net_socket_addr_v4_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    const port = std.mem.readInt(u16, addr[4..6], .little);
    const text = std.fmt.bufPrint(buffer, "{d}.{d}.{d}.{d}:{d}", .{ addr[0], addr[1], addr[2], addr[3], port }) catch return 0;
    len_ptr.* = @intCast(text.len);
    return 1;
}

pub export fn sa_net_socket_addr_v6_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    var raw: [16]u8 = undefined;
    @memcpy(&raw, addr[0..16]);
    const segments = readIpv6SegmentsNative(&raw);
    const port = std.mem.readInt(u16, addr[16..18], .little);
    const scope_id = std.mem.readInt(u32, addr[24..28], .little);
    var ip_buffer: [64]u8 = undefined;
    const ip = formatIpv6Segments(&ip_buffer, &segments) catch return 0;
    const text = if (scope_id == 0)
        std.fmt.bufPrint(buffer, "[{s}]:{d}", .{ ip, port }) catch return 0
    else
        std.fmt.bufPrint(buffer, "[{s}%{d}]:{d}", .{ ip, scope_id, port }) catch return 0;
    len_ptr.* = @intCast(text.len);
    return 1;
}

// POSIX-only networking and pidfd/epoll APIs have no faithful Windows
// equivalent. Keep every public symbol available while reporting
// UNSUPPORTED and clearing caller-owned outputs.
pub export fn sa_std_net_unix_listen(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_accept(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_accept_addr(_: u64, out_stream: ?*u64, out_addr: ?*u64) i32 {
    if (out_stream) |p| p.* = 0;
    if (out_addr) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_connect(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_pair(out_left: ?*u64, out_right: ?*u64) i32 {
    if (out_left) |p| p.* = 0;
    if (out_right) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_addr_from_abstract_name(_: ?[*]const u8, _: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_addr_from_pathname(_: ?[*]const u8, _: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_listen_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_connect_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_listener_local_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_listener_try_clone(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_listener_from_raw_fd(_: i32, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_stream_local_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_stream_try_clone(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_stream_from_raw_fd(_: i32, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_stream_peer_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_stream_set_passcred(_: u64, _: i32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_stream_passcred(_: u64, out: ?*i32) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_stream_set_mark(_: u64, _: u32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_stream_peer_cred(_: u64, out_pid: ?*i32, out_uid: ?*u32, out_gid: ?*u32) i32 {
    if (out_pid) |p| p.* = 0;
    if (out_uid) |p| p.* = 0;
    if (out_gid) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_unbound(out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_bind(_: ?[*]const u8, _: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_bind_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_pair(out_left: ?*u64, out_right: ?*u64) i32 {
    if (out_left) |p| p.* = 0;
    if (out_right) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_unix_datagram_connect(_: u64, _: ?[*]const u8, _: u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
