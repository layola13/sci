const std = @import("std");
const IPPROTOT = @import("std_net_udp.zig").IPPROTOT;
const IPV6_MULTICAST_HOPS_OPT = @import("std_net_udp.zig").IPV6_MULTICAST_HOPS_OPT;
const IPV6_MULTICAST_IF_OPT = @import("std_net_udp.zig").IPV6_MULTICAST_IF_OPT;
const IPV6_MULTICAST_LOOP_OPT = @import("std_net_udp.zig").IPV6_MULTICAST_LOOP_OPT;
const IP_MULTICAST_IF_OPT = @import("std_net_udp.zig").IP_MULTICAST_IF_OPT;
const IP_MULTICAST_LOOP_OPT = @import("std_net_udp.zig").IP_MULTICAST_LOOP_OPT;
const IP_MULTICAST_TTL_OPT = @import("std_net_udp.zig").IP_MULTICAST_TTL_OPT;
const MsghdrConstT = @import("std_net_udp.zig").MsghdrConstT;
const MsghdrT = @import("std_net_udp.zig").MsghdrT;
const NetAddrHandle = @import("std_net_udp.zig").NetAddrHandle;
const NetAddress = @import("std_net_udp.zig").NetAddress;
const SA_NET_IOV_MAX = @import("std_net_udp.zig").SA_NET_IOV_MAX;
const SA_STD_ERR_INVALID_ARGUMENT = @import("std_net_udp.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("std_net_udp.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_UNSUPPORTED = @import("std_net_udp.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("std_net_udp.zig").SA_STD_OK;
const SOLT = @import("std_net_udp.zig").SOLT;
const SOT = @import("std_net_udp.zig").SOT;
const SockAddrStorageT = @import("std_net_udp.zig").SockAddrStorageT;
const SockLenT = @import("std_net_udp.zig").SockLenT;
const builtin = @import("std_net_udp.zig").builtin;
const cmsgAlign = @import("std_net_udp.zig").cmsgAlign;
const cmsg_level_ip = @import("std_net_udp.zig").cmsg_level_ip;
const cmsg_level_ipv6 = @import("std_net_udp.zig").cmsg_level_ipv6;
const cmsg_level_socket = @import("std_net_udp.zig").cmsg_level_socket;
const cmsg_type_ip_pktinfo = @import("std_net_udp.zig").cmsg_type_ip_pktinfo;
const cmsg_type_ipv6_pktinfo = @import("std_net_udp.zig").cmsg_type_ipv6_pktinfo;
const cmsg_type_timestamp = @import("std_net_udp.zig").cmsg_type_timestamp;
const constBytes = @import("std_net_udp.zig").constBytes;
const ensureSocketHandle = @import("std_net_udp.zig").ensureSocketHandle;
const finish = @import("std_net_udp.zig").finish;
const finishErr = @import("std_net_udp.zig").finishErr;
const getResourceLocked = @import("std_net_udp.zig").getResourceLocked;
const getSocketOptByte = @import("std_net_udp.zig").getSocketOptByte;
const getSocketOptBytes = @import("std_net_udp.zig").getSocketOptBytes;
const getSocketOptInt = @import("std_net_udp.zig").getSocketOptInt;
const getSocketOptU32 = @import("std_net_udp.zig").getSocketOptU32;
const handleToFd = @import("std_net_udp.zig").handleToFd;
const hostBytes = @import("std_net_udp.zig").hostBytes;
const is_wasm = @import("std_net_udp.zig").is_wasm;
const lockRegistry = @import("std_net_udp.zig").lockRegistry;
const lxErr = @import("std_net_udp.zig").lxErr;
const lxGetsockname = @import("std_net_udp.zig").lxGetsockname;
const lxRecvfrom = @import("std_net_udp.zig").lxRecvfrom;
const lxSendmsg = @import("std_net_udp.zig").lxSendmsg;
const lxSendto = @import("std_net_udp.zig").lxSendto;
const lxWritev = @import("std_net_udp.zig").lxWritev;
const mutBytes = @import("std_net_udp.zig").mutBytes;
const portFromU32 = @import("std_net_udp.zig").portFromU32;
const portableRecvmsg = @import("std_net_udp.zig").portableRecvmsg;
const recv_msg_flag_ctrunc = @import("std_net_udp.zig").recv_msg_flag_ctrunc;
const recv_msg_flag_pktinfo = @import("std_net_udp.zig").recv_msg_flag_pktinfo;
const recv_msg_flag_timestamp = @import("std_net_udp.zig").recv_msg_flag_timestamp;
const recv_msg_flag_trunc = @import("std_net_udp.zig").recv_msg_flag_trunc;
const recv_multi_max_msgs = @import("std_net_udp.zig").recv_multi_max_msgs;
const registerResource = @import("std_net_udp.zig").registerResource;
const registerResourceLocked = @import("std_net_udp.zig").registerResourceLocked;
const resolveFirstAddressFromParts = @import("std_net_udp.zig").resolveFirstAddressFromParts;
const sa_net_iov = @import("std_net_udp.zig").sa_net_iov;
const sa_std = @import("std_net_udp.zig").sa_std;
const udpSocketFd = @import("std_net_udp.zig").udpSocketFd;

pub export fn sa_std_net_udp_recv_buffer_size(socket: u64, out_size: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_size orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const value = getSocketOptInt(handle.fd, SOLT.SOCKET, SOT.RCVBUF) catch |err| return finishErr(err);
    if (value < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @as(u32, @intCast(value));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_send_buffer_size(socket: u64, out_size: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_size orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const value = getSocketOptInt(handle.fd, SOLT.SOCKET, SOT.SNDBUF) catch |err| return finishErr(err);
    if (value < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @as(u32, @intCast(value));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_multicast_loop_v4(socket: u64, out_enabled: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = if ((getSocketOptByte(handle.fd, IPPROTOT.IP, IP_MULTICAST_LOOP_OPT) catch |err| return finishErr(err)) != 0) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_multicast_ttl_v4(socket: u64, out_ttl: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_ttl orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = @as(u32, getSocketOptByte(handle.fd, IPPROTOT.IP, IP_MULTICAST_TTL_OPT) catch |err| return finishErr(err));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_multicast_loop_v6(socket: u64, out_enabled: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = if ((getSocketOptInt(handle.fd, IPPROTOT.IPV6, IPV6_MULTICAST_LOOP_OPT) catch |err| return finishErr(err)) != 0) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_multicast_hops_v6(socket: u64, out_hops: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_hops orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const hops = getSocketOptInt(handle.fd, IPPROTOT.IPV6, IPV6_MULTICAST_HOPS_OPT) catch |err| return finishErr(err);
    if (hops < 0 or hops > 255) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @intCast(hops);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_multicast_if_v4(socket: u64, out_interface_addr: ?[*]u8) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_interface_addr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    getSocketOptBytes(handle.fd, IPPROTOT.IP, IP_MULTICAST_IF_OPT, out[0..4]) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_multicast_if_v6(socket: u64, out_interface_index: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_interface_index orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = getSocketOptU32(handle.fd, IPPROTOT.IPV6, IPV6_MULTICAST_IF_OPT) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_send_to(socket: u64, buf: ?[*]const u8, len: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32, out_written: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    written_ptr.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const host = hostBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    const address = resolveFirstAddressFromParts(host, port16) catch |err| return finishErr(err);
    lockRegistry();
    const fd = handleToFd(socket) catch |err| {
        sa_std.registry_mutex.unlock();
        return finishErr(err);
    };
    sa_std.registry_mutex.unlock();
    const written = lxSendto(fd, bytes, 0, address.sockAddr(), address.getOsSockLen()) catch |err| return finishErr(err);
    written_ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_recv_from(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);
    lockRegistry();
    const fd = handleToFd(socket) catch |err| {
        sa_std.registry_mutex.unlock();
        return finishErr(err);
    };
    sa_std.registry_mutex.unlock();
    var addr = NetAddress{};
    var addr_len: SockLenT = @sizeOf(SockAddrStorageT);
    const read = lxRecvfrom(fd, buffer, 0, addr.sockAddrMut(), &addr_len) catch |err| return finishErr(err);
    addr.len = addr_len;
    read_ptr.* = @as(u64, @intCast(read));
    if (out_addr) |ptr| {
        var net_addr = NetAddrHandle.init(std.heap.page_allocator, addr) catch |err| return finishErr(err);
        const handle = registerResource(.{ .net_addr = net_addr }) catch |err| {
            net_addr.deinit();
            return finishErr(err);
        };
        ptr.* = handle;
    }
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_send_vectored(socket: u64, iovs: [*]const sa_net_iov, iov_count: u64, out_written: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    written_ptr.* = 0;
    if (iov_count == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const count = std.math.cast(usize, iov_count) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const slices = iovs[0..count];


    const fd = udpSocketFd(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);

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

pub export fn sa_std_net_udp_send_to_vectored(socket: u64, iovs: [*]const sa_net_iov, iov_count: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32, out_written: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    written_ptr.* = 0;
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (iov_count == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const count = std.math.cast(usize, iov_count) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const slices = iovs[0..count];
    const host = hostBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    const address = resolveFirstAddressFromParts(host, port16) catch |err| return finishErr(err);


    const fd = udpSocketFd(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);

    var ziovec: [SA_NET_IOV_MAX]std.posix.iovec_const = undefined;
    var filled: usize = 0;
    for (slices) |slot| {
        if (filled >= ziovec.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
        const len = std.math.cast(usize, slot.len) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
        ziovec[filled] = .{ .base = slot.base, .len = len };
        filled += 1;
    }

    var msg: MsghdrConstT = std.mem.zeroes(MsghdrConstT);
    msg.name = @ptrCast(@constCast(address.sockAddr()));
    msg.namelen = address.getOsSockLen();
    msg.iov = ziovec[0..filled].ptr;
    msg.iovlen = @intCast(filled);

    const written = lxSendmsg(fd, &msg, 0) catch |err| return finishErr(err);
    written_ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_recv_from_vectored(socket: u64, iovs: [*]const sa_net_iov, iov_count: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    if (iov_count == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const count = std.math.cast(usize, iov_count) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const slices = iovs[0..count];


    const fd = udpSocketFd(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);

    var ziovec: [SA_NET_IOV_MAX]std.posix.iovec = undefined;
    var filled: usize = 0;
    for (slices) |slot| {
        if (filled >= ziovec.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
        const len = std.math.cast(usize, slot.len) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
        ziovec[filled] = .{ .base = slot.base, .len = len };
        filled += 1;
    }

    var addr = NetAddress{};
    var msg: MsghdrT = std.mem.zeroes(MsghdrT);
    msg.name = @ptrCast(addr.sockAddrMut());
    msg.namelen = @as(SockLenT, @intCast(@sizeOf(SockAddrStorageT)));
    msg.iov = ziovec[0..filled].ptr;
    msg.iovlen = @intCast(filled);

    const read_n = portableRecvmsg(fd, &msg, 0) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(read_n));
    if (out_addr) |ptr| {
        var net_addr = NetAddrHandle.init(std.heap.page_allocator, addr) catch |err| return finishErr(err);
        const handle = registerResource(.{ .net_addr = net_addr }) catch |err| {
            net_addr.deinit();
            return finishErr(err);
        };
        ptr.* = handle;
    }
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_recv_msg(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64, out_dest_addr: ?*u64, out_ifindex: ?*u32, out_timestamp_ns: ?*u64, out_flags: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    if (out_ifindex) |ptr| ptr.* = 0;
    if (out_timestamp_ns) |ptr| ptr.* = 0;
    if (out_flags) |ptr| ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);

    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const fd = switch (resource.*) {
        .udp_socket => |value| value,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };

    var addr = NetAddress{};
    var ziovec = std.posix.iovec{ .base = buffer.ptr, .len = buffer.len };
    var control: [256]u8 align(8) = undefined;
    var msg: MsghdrT = std.mem.zeroes(MsghdrT);
    msg.name = @ptrCast(addr.sockAddrMut());
    msg.namelen = @as(SockLenT, @intCast(@sizeOf(SockAddrStorageT)));
    msg.iov = @ptrCast(&ziovec);
    msg.iovlen = 1;
    msg.control = @ptrCast(&control);
    msg.controllen = control.len;

    const read = portableRecvmsg(fd, &msg, 0) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(read));
    addr.len = msg.namelen;

    if (out_addr) |ptr| {
        var net_addr = NetAddrHandle.init(std.heap.page_allocator, addr) catch |err| return finishErr(err);
        const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
            net_addr.deinit();
            return finishErr(err);
        };
        ptr.* = handle;
    }

    var flags: u32 = 0;
    if ((msg.flags & std.os.linux.MSG.CTRUNC) != 0) flags |= recv_msg_flag_ctrunc;
    if ((msg.flags & std.os.linux.MSG.TRUNC) != 0) flags |= recv_msg_flag_trunc;

    // Walk the control-message chain. Layout (Linux): cmsg_len u64,
    // cmsg_level i32, cmsg_type i32, then the payload; each message
    // is padded to usize alignment.
    const ctrl = control[0..@as(usize, @intCast(msg.controllen))];
    var off: usize = 0;
    while (off + 16 <= ctrl.len) {
        const cmsg_len = @as(usize, @intCast(std.mem.readInt(u64, ctrl[off..][0..8], .little)));
        if (cmsg_len < 16 or off + cmsg_len > ctrl.len) break;
        const level = std.mem.readInt(i32, ctrl[off + 8 ..][0..4], .little);
        const ctype = std.mem.readInt(i32, ctrl[off + 12 ..][0..4], .little);
        const data = ctrl[off + 16 .. off + cmsg_len];
        if (level == cmsg_level_ip and ctype == cmsg_type_ip_pktinfo and data.len >= 12) {
            // struct in_pktinfo { i32 ifindex; u32 spec_dst; u32 addr; }
            // The destination the datagram was sent to is ipi_addr.
            flags |= recv_msg_flag_pktinfo;
            if (out_ifindex) |ptr| ptr.* = @as(u32, @bitCast(std.mem.readInt(i32, data[0..4], .little)));
            if (out_dest_addr) |ptr| {
                var local = NetAddress{};
                var local_len: SockLenT = @sizeOf(SockAddrStorageT);
                lxGetsockname(fd, local.sockAddrMut(), &local_len) catch |err| return finishErr(err);
                var parts: [4]u8 = undefined;
                @memcpy(&parts, data[8..12]);
                const dest = NetAddress.initIp4(parts, local.getPort());
                var net_addr = NetAddrHandle.init(std.heap.page_allocator, dest) catch |err| return finishErr(err);
                const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
                    net_addr.deinit();
                    return finishErr(err);
                };
                ptr.* = handle;
            }
        } else if (level == cmsg_level_ipv6 and ctype == cmsg_type_ipv6_pktinfo and data.len >= 20) {
            // struct in6_pktinfo { u8 addr[16]; u32 ifindex; }
            flags |= recv_msg_flag_pktinfo;
            if (out_ifindex) |ptr| ptr.* = std.mem.readInt(u32, data[16..20], .little);
            if (out_dest_addr) |ptr| {
                var local = NetAddress{};
                var local_len: SockLenT = @sizeOf(SockAddrStorageT);
                lxGetsockname(fd, local.sockAddrMut(), &local_len) catch |err| return finishErr(err);
                local.len = local_len;
                var bytes: [16]u8 = undefined;
                @memcpy(&bytes, data[0..16]);
                const dest = NetAddress.initIp6(bytes, local.getPort(), 0, std.mem.readInt(u32, data[16..20], .little));
                var net_addr = NetAddrHandle.init(std.heap.page_allocator, dest) catch |err| return finishErr(err);
                const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
                    net_addr.deinit();
                    return finishErr(err);
                };
                ptr.* = handle;
            }
        } else if (level == cmsg_level_socket and ctype == cmsg_type_timestamp and data.len >= 16) {
            // struct timeval { i64 sec; i64 usec; }
            flags |= recv_msg_flag_timestamp;
            if (out_timestamp_ns) |ptr| {
                const sec = std.mem.readInt(i64, data[0..8], .little);
                const usec = std.mem.readInt(i64, data[8..16], .little);
                if (sec >= 0 and usec >= 0) {
                    const ns = @as(i128, sec) * std.time.ns_per_s + @as(i128, usec) * std.time.ns_per_us;
                    ptr.* = @as(u64, @intCast(ns));
                }
            }
        }
        const step = cmsgAlign(cmsg_len);
        if (step == 0) break;
        off += step;
    }
    if (out_flags) |ptr| ptr.* = flags;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_recv_multi(socket: u64, out: ?[*]u8, buf_cap: u64, slot_size: u64, max_msgs: u64, out_count: ?*u64, out_lens: ?[*]u64, out_addrs: ?[*]u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);
    const count_ptr = out_count orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    count_ptr.* = 0;
    const lens = out_lens orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (max_msgs == 0 or max_msgs > recv_multi_max_msgs) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (slot_size == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const n = @as(usize, @intCast(max_msgs));
    const slot = @as(usize, @intCast(slot_size));
    const buffer = mutBytes(out, buf_cap) catch |err| return finishErr(err);
    if (buffer.len < slot * n) return finish(SA_STD_ERR_INVALID_ARGUMENT);

    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const fd = switch (resource.*) {
        .udp_socket => |value| value,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };

    var vec: [recv_multi_max_msgs]std.os.linux.mmsghdr = undefined;
    var iovs: [recv_multi_max_msgs]std.posix.iovec = undefined;
    var addrs: [recv_multi_max_msgs]NetAddress = undefined;
    for (0..n) |i| {
        addrs[i] = NetAddress{};
        iovs[i] = .{ .base = buffer.ptr + i * slot, .len = slot };
        vec[i] = .{
            .hdr = .{
                .name = @ptrCast(addrs[i].sockAddrMut()),
                .namelen = @as(SockLenT, @intCast(@sizeOf(SockAddrStorageT))),
                .iov = @ptrCast(&iovs[i]),
                .iovlen = 1,
                .control = null,
                .controllen = 0,
                .flags = 0,
            },
            .len = 0,
        };
    }

    const rc = std.os.linux.recvmmsg(fd, vec[0..n].ptr, @as(u32, @intCast(n)), @as(u32, std.os.linux.MSG.WAITFORONE), null);
    const rc_signed: isize = @as(isize, @bitCast(rc));
    if (rc_signed < 0) return finishErr(lxErr(std.os.linux.errno(rc)));
    const received = @as(usize, @intCast(rc_signed));
    count_ptr.* = @as(u64, @intCast(received));
    for (0..received) |i| {
        lens[i] = @as(u64, @intCast(vec[i].len));
        if (out_addrs) |arr| {
            arr[i] = 0;
            addrs[i].len = vec[i].hdr.namelen;
            var net_addr = NetAddrHandle.init(std.heap.page_allocator, addrs[i]) catch |err| return finishErr(err);
            const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
                net_addr.deinit();
                return finishErr(err);
            };
            arr[i] = handle;
        }
    }
    return finish(SA_STD_OK);
}
