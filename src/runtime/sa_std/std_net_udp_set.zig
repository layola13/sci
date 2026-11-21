const std = @import("std");
const AFT = @import("std_net_udp.zig").AFT;
const IPPROTOT = @import("std_net_udp.zig").IPPROTOT;
const IPV6_MULTICAST_HOPS_OPT = @import("std_net_udp.zig").IPV6_MULTICAST_HOPS_OPT;
const IPV6_MULTICAST_IF_OPT = @import("std_net_udp.zig").IPV6_MULTICAST_IF_OPT;
const IPV6_MULTICAST_LOOP_OPT = @import("std_net_udp.zig").IPV6_MULTICAST_LOOP_OPT;
const IP_MULTICAST_IF_OPT = @import("std_net_udp.zig").IP_MULTICAST_IF_OPT;
const IP_MULTICAST_LOOP_OPT = @import("std_net_udp.zig").IP_MULTICAST_LOOP_OPT;
const IP_MULTICAST_TTL_OPT = @import("std_net_udp.zig").IP_MULTICAST_TTL_OPT;
const SA_STD_ERR_INVALID_ARGUMENT = @import("std_net_udp.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("std_net_udp.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_UNSUPPORTED = @import("std_net_udp.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("std_net_udp.zig").SA_STD_OK;
const SOLT = @import("std_net_udp.zig").SOLT;
const SOT = @import("std_net_udp.zig").SOT;
const constBytes = @import("std_net_udp.zig").constBytes;
const ensureSocketHandle = @import("std_net_udp.zig").ensureSocketHandle;
const finish = @import("std_net_udp.zig").finish;
const finishErr = @import("std_net_udp.zig").finishErr;
const is_wasm = @import("std_net_udp.zig").is_wasm;
const lxFcntl = @import("std_net_udp.zig").lxFcntl;
const lxSetSocketOptBool = @import("std_net_udp.zig").lxSetSocketOptBool;
const rebuildUdpSocketV6Only = @import("std_net_udp.zig").rebuildUdpSocketV6Only;
const setSocketOptBool = @import("std_net_udp.zig").setSocketOptBool;
const setSocketOptByte = @import("std_net_udp.zig").setSocketOptByte;
const setSocketOptBytes = @import("std_net_udp.zig").setSocketOptBytes;
const setSocketOptInt = @import("std_net_udp.zig").setSocketOptInt;
const setSocketOptTimeval = @import("std_net_udp.zig").setSocketOptTimeval;
const setSocketOptU32 = @import("std_net_udp.zig").setSocketOptU32;
const socketAddressFamily = @import("std_net_udp.zig").socketAddressFamily;

pub export fn sa_std_net_udp_set_only_v6(socket: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const family = socketAddressFamily(handle.fd) catch |err| return finishErr(err);
    if (family != AFT.INET6) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    lxSetSocketOptBool(handle.fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY, enabled != 0) catch |err| {
        // A bound socket refuses IPV6_V6ONLY with EINVAL (bind-time
        // option); rebuild the socket with the option applied pre-bind.
        if (err != error.InvalidArgument) return finishErr(err);
        rebuildUdpSocketV6Only(socket, enabled != 0) catch |err2| return finishErr(err2);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_nonblocking(socket: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const flags = lxFcntl(handle.fd, std.posix.F.GETFL, 0) catch |err| return finishErr(err);
    const new_flags = if (enabled != 0)
        flags | @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK")
    else
        flags & ~(@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"));
    _ = lxFcntl(handle.fd, std.posix.F.SETFL, new_flags) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_broadcast(socket: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptBool(handle.fd, SOLT.SOCKET, SOT.BROADCAST, enabled != 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_ttl(socket: u64, ttl: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (ttl > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    setSocketOptInt(handle.fd, IPPROTOT.IP, std.posix.IP.TTL, @as(i32, @intCast(ttl))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_read_timeout(socket: u64, timeout_ns: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptTimeval(handle.fd, SOLT.SOCKET, SOT.RCVTIMEO, timeout_ns) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_write_timeout(socket: u64, timeout_ns: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptTimeval(handle.fd, SOLT.SOCKET, SOT.SNDTIMEO, timeout_ns) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_recv_buffer_size(socket: u64, size: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (size > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    setSocketOptInt(handle.fd, SOLT.SOCKET, SOT.RCVBUF, @as(i32, @intCast(size))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_send_buffer_size(socket: u64, size: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (size > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    setSocketOptInt(handle.fd, SOLT.SOCKET, SOT.SNDBUF, @as(i32, @intCast(size))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_multicast_loop_v4(socket: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptByte(handle.fd, IPPROTOT.IP, IP_MULTICAST_LOOP_OPT, if (enabled != 0) 1 else 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_multicast_ttl_v4(socket: u64, ttl: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (ttl > std.math.maxInt(u8)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    setSocketOptByte(handle.fd, IPPROTOT.IP, IP_MULTICAST_TTL_OPT, @as(u8, @intCast(ttl))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_multicast_loop_v6(socket: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptInt(handle.fd, IPPROTOT.IPV6, IPV6_MULTICAST_LOOP_OPT, if (enabled != 0) 1 else 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_multicast_hops_v6(socket: u64, hops: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (hops > 255) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptInt(handle.fd, IPPROTOT.IPV6, IPV6_MULTICAST_HOPS_OPT, @intCast(hops)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_multicast_if_v4(socket: u64, interface_addr_ptr: ?[*]const u8) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const interface_addr = constBytes(interface_addr_ptr, 4) catch |err| return finishErr(err);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptBytes(handle.fd, IPPROTOT.IP, IP_MULTICAST_IF_OPT, interface_addr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_multicast_if_v6(socket: u64, interface_index: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptU32(handle.fd, IPPROTOT.IPV6, IPV6_MULTICAST_IF_OPT, interface_index) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
