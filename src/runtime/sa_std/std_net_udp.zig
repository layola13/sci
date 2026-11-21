const std = @import("std");
pub const AFT = @import("std_net.zig").AFT;
pub const IPPROTOT = @import("std_net.zig").IPPROTOT;
const IPV6_JOIN_GROUP_OPT = @import("std_net.zig").IPV6_JOIN_GROUP_OPT;
const IPV6_LEAVE_GROUP_OPT = @import("std_net.zig").IPV6_LEAVE_GROUP_OPT;
pub const IPV6_MULTICAST_HOPS_OPT = @import("std_net.zig").IPV6_MULTICAST_HOPS_OPT;
pub const IPV6_MULTICAST_IF_OPT = @import("std_net.zig").IPV6_MULTICAST_IF_OPT;
pub const IPV6_MULTICAST_LOOP_OPT = @import("std_net.zig").IPV6_MULTICAST_LOOP_OPT;
const IP_ADD_MEMBERSHIP_OPT = @import("std_net.zig").IP_ADD_MEMBERSHIP_OPT;
const IP_DROP_MEMBERSHIP_OPT = @import("std_net.zig").IP_DROP_MEMBERSHIP_OPT;
pub const IP_MULTICAST_IF_OPT = @import("std_net.zig").IP_MULTICAST_IF_OPT;
pub const IP_MULTICAST_LOOP_OPT = @import("std_net.zig").IP_MULTICAST_LOOP_OPT;
pub const IP_MULTICAST_TTL_OPT = @import("std_net.zig").IP_MULTICAST_TTL_OPT;
pub const MsghdrConstT = @import("std_net.zig").MsghdrConstT;
pub const MsghdrT = @import("std_net.zig").MsghdrT;
pub const NetAddrHandle = @import("std_net.zig").NetAddrHandle;
pub const NetAddress = @import("std_net.zig").NetAddress;
pub const SA_NET_IOV_MAX = @import("std_net.zig").SA_NET_IOV_MAX;
pub const SA_STD_ERR_INVALID_ARGUMENT = @import("std_net.zig").SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_STD_ERR_INVALID_HANDLE = @import("std_net.zig").SA_STD_ERR_INVALID_HANDLE;
pub const SA_STD_ERR_UNSUPPORTED = @import("std_net.zig").SA_STD_ERR_UNSUPPORTED;
pub const SA_STD_OK = @import("std_net.zig").SA_STD_OK;
const SOCKT = @import("std_net.zig").SOCKT;
pub const SOLT = @import("std_net.zig").SOLT;
pub const SOT = @import("std_net.zig").SOT;
pub const SockAddrStorageT = @import("std_net.zig").SockAddrStorageT;
pub const SockLenT = @import("std_net.zig").SockLenT;
pub const builtin = @import("std_net.zig").builtin;
pub const cmsgAlign = @import("std_net.zig").cmsgAlign;
pub const cmsg_level_ip = @import("std_net.zig").cmsg_level_ip;
pub const cmsg_level_ipv6 = @import("std_net.zig").cmsg_level_ipv6;
pub const cmsg_level_socket = @import("std_net.zig").cmsg_level_socket;
pub const cmsg_type_ip_pktinfo = @import("std_net.zig").cmsg_type_ip_pktinfo;
pub const cmsg_type_ipv6_pktinfo = @import("std_net.zig").cmsg_type_ipv6_pktinfo;
pub const cmsg_type_timestamp = @import("std_net.zig").cmsg_type_timestamp;
pub const constBytes = @import("std_net.zig").constBytes;
pub const ensureSocketHandle = @import("std_net.zig").ensureSocketHandle;
pub const finish = @import("std_net.zig").finish;
pub const finishErr = @import("std_net.zig").finishErr;
pub const getResourceLocked = @import("std_net.zig").getResourceLocked;
const getSocketOptBool = @import("std_net.zig").getSocketOptBool;
pub const getSocketOptByte = @import("std_net.zig").getSocketOptByte;
pub const getSocketOptBytes = @import("std_net.zig").getSocketOptBytes;
pub const getSocketOptInt = @import("std_net.zig").getSocketOptInt;
const getSocketOptTimeval = @import("std_net.zig").getSocketOptTimeval;
pub const getSocketOptU32 = @import("std_net.zig").getSocketOptU32;
pub const handleToFd = @import("std_net.zig").handleToFd;
pub const hostBytes = @import("std_net.zig").hostBytes;
pub const is_wasm = @import("std_net.zig").is_wasm;
pub const lockRegistry = @import("std_net.zig").lockRegistry;
const lxBind = @import("std_net.zig").lxBind;
const lxClose = @import("std_net.zig").lxClose;
const lxConnect = @import("std_net.zig").lxConnect;
const lxDup = @import("std_net.zig").lxDup;
pub const lxErr = @import("std_net.zig").lxErr;
pub const lxFcntl = @import("std_net.zig").lxFcntl;
const lxGetpeername = @import("std_net.zig").lxGetpeername;
pub const lxGetsockname = @import("std_net.zig").lxGetsockname;
const lxRecv = @import("std_net.zig").lxRecv;
pub const lxRecvfrom = @import("std_net.zig").lxRecvfrom;
const lxSend = @import("std_net.zig").lxSend;
pub const lxSendmsg = @import("std_net.zig").lxSendmsg;
pub const lxSendto = @import("std_net.zig").lxSendto;
pub const lxSetSocketOptBool = @import("std_net.zig").lxSetSocketOptBool;
const lxSocket = @import("std_net.zig").lxSocket;
pub const lxWritev = @import("std_net.zig").lxWritev;
const makeIpv4Membership = @import("std_net.zig").makeIpv4Membership;
const makeIpv6Membership = @import("std_net.zig").makeIpv6Membership;
const msg_peek = @import("std_net.zig").msg_peek;
pub const mutBytes = @import("std_net.zig").mutBytes;
const parseIp4Address = @import("std_net.zig").parseIp4Address;
const parseIp6Address = @import("std_net.zig").parseIp6Address;
pub const portFromU32 = @import("std_net.zig").portFromU32;
pub const portableRecvmsg = @import("std_net.zig").portableRecvmsg;
pub const rebuildUdpSocketV6Only = @import("std_net.zig").rebuildUdpSocketV6Only;
pub const recv_msg_flag_ctrunc = @import("std_net.zig").recv_msg_flag_ctrunc;
pub const recv_msg_flag_pktinfo = @import("std_net.zig").recv_msg_flag_pktinfo;
pub const recv_msg_flag_timestamp = @import("std_net.zig").recv_msg_flag_timestamp;
pub const recv_msg_flag_trunc = @import("std_net.zig").recv_msg_flag_trunc;
pub const recv_multi_max_msgs = @import("std_net.zig").recv_multi_max_msgs;
const registerNetAddrOutLocked = @import("std_net.zig").registerNetAddrOutLocked;
pub const registerResource = @import("std_net.zig").registerResource;
pub const registerResourceLocked = @import("std_net.zig").registerResourceLocked;
pub const resolveFirstAddressFromParts = @import("std_net.zig").resolveFirstAddressFromParts;
pub const sa_net_iov = @import("std_net.zig").sa_net_iov;
pub const sa_std = @import("std_net.zig").sa_std;
pub const setSocketOptBool = @import("std_net.zig").setSocketOptBool;
pub const setSocketOptByte = @import("std_net.zig").setSocketOptByte;
pub const setSocketOptBytes = @import("std_net.zig").setSocketOptBytes;
pub const setSocketOptInt = @import("std_net.zig").setSocketOptInt;
pub const setSocketOptTimeval = @import("std_net.zig").setSocketOptTimeval;
pub const setSocketOptU32 = @import("std_net.zig").setSocketOptU32;
pub const socketAddressFamily = @import("std_net.zig").socketAddressFamily;
const socketIsDatagram = @import("std_net.zig").socketIsDatagram;
const socketIsInet = @import("std_net.zig").socketIsInet;
pub const udpSocketFd = @import("std_net.zig").udpSocketFd;

pub export fn sa_std_net_udp_try_clone(socket: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const fd = switch (resource.*) {
        .udp_socket => |value| value,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    const dup_fd = lxDup(fd) catch |err| return finishErr(err);
    const handle = registerResourceLocked(.{ .udp_socket = dup_fd }) catch |err| {
        lxClose(dup_fd);
        return finishErr(err);
    };
    out.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_bind(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const host = hostBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    const address = resolveFirstAddressFromParts(host, port16) catch |err| return finishErr(err);
    const fd = lxSocket(address.storage.family, SOCKT.DGRAM | SOCKT.CLOEXEC, IPPROTOT.UDP) catch |err| return finishErr(err);
    errdefer lxClose(fd);
    var bind_addr = address;
    lxBind(fd, bind_addr.sockAddr(), bind_addr.getOsSockLen()) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const handle = registerResourceLocked(.{ .udp_socket = fd }) catch |err| {
        lxClose(fd);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const posix_fd = @as(std.posix.fd_t, @intCast(fd));
    if (!(socketIsInet(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsDatagram(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const handle = registerResource(.{ .udp_socket = posix_fd }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_local_addr(socket: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .udp_socket => |fd| {
            var addr = NetAddress{};
            var addr_len: SockLenT = @sizeOf(SockAddrStorageT);
            lxGetsockname(fd, addr.sockAddrMut(), &addr_len) catch |err| return finishErr(err);
            addr.len = addr_len;
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

pub export fn sa_std_net_udp_peer_addr(socket: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .udp_socket => |fd| {
            var addr = NetAddress{};
            var addr_len: SockLenT = @sizeOf(SockAddrStorageT);
            lxGetpeername(fd, addr.sockAddrMut(), &addr_len) catch |err| return finishErr(err);
            addr.len = addr_len;
            return registerNetAddrOutLocked(addr, handle_ptr);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_net_udp_connect(socket: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const host = hostBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    const address = resolveFirstAddressFromParts(host, port16) catch |err| return finishErr(err);


    const fd = udpSocketFd(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    lxConnect(fd, address.sockAddr(), address.getOsSockLen()) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_connect_addr(socket: u64, addr_handle: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    lockRegistry();
    const socket_resource = getResourceLocked(socket) orelse {
        sa_std.registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const fd = switch (socket_resource.*) {
        .udp_socket => |value| value,
        else => {
            sa_std.registry_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        },
    };
    const addr_resource = getResourceLocked(addr_handle) orelse {
        sa_std.registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const address = switch (addr_resource.*) {
        .net_addr => |value| value.addr,
        else => {
            sa_std.registry_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        },
    };
    sa_std.registry_mutex.unlock();
    lxConnect(fd, address.sockAddr(), address.getOsSockLen()) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub const sa_std_net_udp_set_only_v6 = @import("std_net_udp_set.zig").sa_std_net_udp_set_only_v6;

pub export fn sa_std_net_udp_only_v6(socket: u64, out_enabled: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const family = socketAddressFamily(handle.fd) catch |err| return finishErr(err);
    if (family != AFT.INET6) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = if (getSocketOptBool(handle.fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub const sa_std_net_udp_set_nonblocking = @import("std_net_udp_set.zig").sa_std_net_udp_set_nonblocking;

pub const sa_std_net_udp_set_broadcast = @import("std_net_udp_set.zig").sa_std_net_udp_set_broadcast;

pub const sa_std_net_udp_set_ttl = @import("std_net_udp_set.zig").sa_std_net_udp_set_ttl;

pub const sa_std_net_udp_set_read_timeout = @import("std_net_udp_set.zig").sa_std_net_udp_set_read_timeout;

pub const sa_std_net_udp_set_write_timeout = @import("std_net_udp_set.zig").sa_std_net_udp_set_write_timeout;

pub const sa_std_net_udp_set_recv_buffer_size = @import("std_net_udp_set.zig").sa_std_net_udp_set_recv_buffer_size;

pub const sa_std_net_udp_recv_buffer_size = @import("std_net_udp_io.zig").sa_std_net_udp_recv_buffer_size;

pub const sa_std_net_udp_set_send_buffer_size = @import("std_net_udp_set.zig").sa_std_net_udp_set_send_buffer_size;

pub const sa_std_net_udp_send_buffer_size = @import("std_net_udp_io.zig").sa_std_net_udp_send_buffer_size;

pub export fn sa_std_net_udp_read_timeout(socket: u64, out_timeout_ns: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = getSocketOptTimeval(handle.fd, SOLT.SOCKET, SOT.RCVTIMEO) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_write_timeout(socket: u64, out_timeout_ns: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = getSocketOptTimeval(handle.fd, SOLT.SOCKET, SOT.SNDTIMEO) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_broadcast(socket: u64, out_enabled: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = if (getSocketOptBool(handle.fd, SOLT.SOCKET, SOT.BROADCAST) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub const sa_std_net_udp_set_multicast_loop_v4 = @import("std_net_udp_set.zig").sa_std_net_udp_set_multicast_loop_v4;

pub const sa_std_net_udp_set_multicast_ttl_v4 = @import("std_net_udp_set.zig").sa_std_net_udp_set_multicast_ttl_v4;

pub const sa_std_net_udp_multicast_loop_v4 = @import("std_net_udp_io.zig").sa_std_net_udp_multicast_loop_v4;

pub const sa_std_net_udp_multicast_ttl_v4 = @import("std_net_udp_io.zig").sa_std_net_udp_multicast_ttl_v4;

pub const sa_std_net_udp_set_multicast_loop_v6 = @import("std_net_udp_set.zig").sa_std_net_udp_set_multicast_loop_v6;

pub const sa_std_net_udp_set_multicast_hops_v6 = @import("std_net_udp_set.zig").sa_std_net_udp_set_multicast_hops_v6;

pub const sa_std_net_udp_multicast_loop_v6 = @import("std_net_udp_io.zig").sa_std_net_udp_multicast_loop_v6;

pub const sa_std_net_udp_multicast_hops_v6 = @import("std_net_udp_io.zig").sa_std_net_udp_multicast_hops_v6;

pub const sa_std_net_udp_set_multicast_if_v4 = @import("std_net_udp_set.zig").sa_std_net_udp_set_multicast_if_v4;

pub const sa_std_net_udp_multicast_if_v4 = @import("std_net_udp_io.zig").sa_std_net_udp_multicast_if_v4;

pub const sa_std_net_udp_set_multicast_if_v6 = @import("std_net_udp_set.zig").sa_std_net_udp_set_multicast_if_v6;

pub const sa_std_net_udp_multicast_if_v6 = @import("std_net_udp_io.zig").sa_std_net_udp_multicast_if_v6;

pub export fn sa_std_net_udp_join_multicast_v4(socket: u64, multi_host_ptr: ?[*]const u8, multi_host_len: u64, interface_host_ptr: ?[*]const u8, interface_host_len: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const multicast_addr = parseIp4Address(multi_host_ptr, multi_host_len, 0) catch |err| return finishErr(err);
    const interface_addr = parseIp4Address(interface_host_ptr, interface_host_len, 0) catch |err| return finishErr(err);
    var membership = makeIpv4Membership(multicast_addr, interface_addr);
    setSocketOptBytes(handle.fd, IPPROTOT.IP, IP_ADD_MEMBERSHIP_OPT, std.mem.asBytes(&membership)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_leave_multicast_v4(socket: u64, multi_host_ptr: ?[*]const u8, multi_host_len: u64, interface_host_ptr: ?[*]const u8, interface_host_len: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const multicast_addr = parseIp4Address(multi_host_ptr, multi_host_len, 0) catch |err| return finishErr(err);
    const interface_addr = parseIp4Address(interface_host_ptr, interface_host_len, 0) catch |err| return finishErr(err);
    var membership = makeIpv4Membership(multicast_addr, interface_addr);
    setSocketOptBytes(handle.fd, IPPROTOT.IP, IP_DROP_MEMBERSHIP_OPT, std.mem.asBytes(&membership)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_join_multicast_v6(socket: u64, multi_host_ptr: ?[*]const u8, multi_host_len: u64, interface_index: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const multicast_addr = parseIp6Address(multi_host_ptr, multi_host_len, 0) catch |err| return finishErr(err);
    var membership = makeIpv6Membership(multicast_addr, interface_index);
    setSocketOptBytes(handle.fd, IPPROTOT.IPV6, IPV6_JOIN_GROUP_OPT, std.mem.asBytes(&membership)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_leave_multicast_v6(socket: u64, multi_host_ptr: ?[*]const u8, multi_host_len: u64, interface_index: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const multicast_addr = parseIp6Address(multi_host_ptr, multi_host_len, 0) catch |err| return finishErr(err);
    var membership = makeIpv6Membership(multicast_addr, interface_index);
    setSocketOptBytes(handle.fd, IPPROTOT.IPV6, IPV6_LEAVE_GROUP_OPT, std.mem.asBytes(&membership)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_ttl(socket: u64, out_ttl: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_ttl orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    const ttl = getSocketOptInt(handle.fd, IPPROTOT.IP, std.posix.IP.TTL) catch |err| return finishErr(err);
    if (ttl < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @as(u32, @intCast(ttl));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_take_error(socket: u64, out_error: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_error orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = getSocketOptInt(handle.fd, SOLT.SOCKET, SOT.ERROR) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_send(socket: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    written_ptr.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);


    const fd = udpSocketFd(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const written = lxSend(fd, bytes, 0) catch |err| return finishErr(err);
    written_ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_recv(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);


    const fd = udpSocketFd(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const read = lxRecv(fd, buffer, 0) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(read));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_peek(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);


    const fd = udpSocketFd(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const read = lxRecv(fd, buffer, msg_peek) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(read));
    return finish(SA_STD_OK);
}

pub const sa_std_net_udp_send_to = @import("std_net_udp_io.zig").sa_std_net_udp_send_to;

pub const sa_std_net_udp_recv_from = @import("std_net_udp_io.zig").sa_std_net_udp_recv_from;

pub export fn sa_std_net_udp_peek_from(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
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
    const read = lxRecvfrom(fd, buffer, msg_peek, addr.sockAddrMut(), &addr_len) catch |err| return finishErr(err);
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

pub const sa_std_net_udp_send_vectored = @import("std_net_udp_io.zig").sa_std_net_udp_send_vectored;

pub const sa_std_net_udp_send_to_vectored = @import("std_net_udp_io.zig").sa_std_net_udp_send_to_vectored;

pub const sa_std_net_udp_recv_from_vectored = @import("std_net_udp_io.zig").sa_std_net_udp_recv_from_vectored;

pub const sa_std_net_udp_recv_msg = @import("std_net_udp_io.zig").sa_std_net_udp_recv_msg;

pub const sa_std_net_udp_recv_multi = @import("std_net_udp_io.zig").sa_std_net_udp_recv_multi;
