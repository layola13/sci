const std = @import("std");
pub const sa_std = @import("../sa_std.zig");
pub const AFT = @import("../sa_std.zig").AFT;
pub const IPPROTOT = @import("../sa_std.zig").IPPROTOT;
pub const IPV6_JOIN_GROUP_OPT = @import("../sa_std.zig").IPV6_JOIN_GROUP_OPT;
pub const IPV6_LEAVE_GROUP_OPT = @import("../sa_std.zig").IPV6_LEAVE_GROUP_OPT;
pub const IPV6_MULTICAST_HOPS_OPT = @import("../sa_std.zig").IPV6_MULTICAST_HOPS_OPT;
pub const IPV6_MULTICAST_IF_OPT = @import("../sa_std.zig").IPV6_MULTICAST_IF_OPT;
pub const IPV6_MULTICAST_LOOP_OPT = @import("../sa_std.zig").IPV6_MULTICAST_LOOP_OPT;
pub const IP_ADD_MEMBERSHIP_OPT = @import("../sa_std.zig").IP_ADD_MEMBERSHIP_OPT;
pub const IP_DROP_MEMBERSHIP_OPT = @import("../sa_std.zig").IP_DROP_MEMBERSHIP_OPT;
pub const IP_MULTICAST_IF_OPT = @import("../sa_std.zig").IP_MULTICAST_IF_OPT;
pub const IP_MULTICAST_LOOP_OPT = @import("../sa_std.zig").IP_MULTICAST_LOOP_OPT;
pub const IP_MULTICAST_TTL_OPT = @import("../sa_std.zig").IP_MULTICAST_TTL_OPT;
pub const MsghdrConstT = @import("../sa_std.zig").MsghdrConstT;
pub const MsghdrT = @import("../sa_std.zig").MsghdrT;
pub const NetAddrHandle = @import("../sa_std.zig").NetAddrHandle;
pub const NetAddress = @import("../sa_std.zig").NetAddress;
pub const SA_NET_IOV_MAX = @import("../sa_std.zig").SA_NET_IOV_MAX;
pub const SA_NET_UNIX_ADDR_ABSTRACT = @import("../sa_std.zig").SA_NET_UNIX_ADDR_ABSTRACT;
pub const SA_NET_UNIX_ADDR_PATHNAME = @import("../sa_std.zig").SA_NET_UNIX_ADDR_PATHNAME;
pub const SA_STD_ERR_ACCESS = @import("../sa_std.zig").SA_STD_ERR_ACCESS;
pub const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
pub const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NET = @import("../sa_std.zig").SA_STD_ERR_NET;
pub const SA_STD_ERR_NOT_FOUND = @import("../sa_std.zig").SA_STD_ERR_NOT_FOUND;
pub const SA_STD_ERR_NO_MEMORY = @import("../sa_std.zig").SA_STD_ERR_NO_MEMORY;
pub const SA_STD_ERR_PERMISSION_DENIED = @import("../sa_std.zig").SA_STD_ERR_PERMISSION_DENIED;
const SA_STD_ERR_TRUNCATED = @import("../sa_std.zig").SA_STD_ERR_TRUNCATED;
pub const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_NET_POLL_ERROR = @import("../sa_std.zig").SA_STD_NET_POLL_ERROR;
const SA_STD_NET_POLL_MAX_HANDLES = @import("../sa_std.zig").SA_STD_NET_POLL_MAX_HANDLES;
const SA_STD_NET_POLL_READ = @import("../sa_std.zig").SA_STD_NET_POLL_READ;
const SA_STD_NET_POLL_WRITE = @import("../sa_std.zig").SA_STD_NET_POLL_WRITE;
pub const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
pub const SOCKT = @import("../sa_std.zig").SOCKT;
pub const SOLT = @import("../sa_std.zig").SOLT;
pub const SOT = @import("../sa_std.zig").SOT;
pub const SO_MARK = @import("../sa_std.zig").SO_MARK;
pub const SO_PASSCRED = @import("../sa_std.zig").SO_PASSCRED;
pub const SockAddrStorageT = @import("../sa_std.zig").SockAddrStorageT;
pub const SockAddrT = @import("../sa_std.zig").SockAddrT;
pub const SockAddrUnT = @import("../sa_std.zig").SockAddrUnT;
pub const SockLenT = @import("../sa_std.zig").SockLenT;
pub const TCP_DEFER_ACCEPT = @import("../sa_std.zig").TCP_DEFER_ACCEPT;
pub const TCP_KEEPCNT = @import("../sa_std.zig").TCP_KEEPCNT;
pub const TCP_KEEPIDLE = @import("../sa_std.zig").TCP_KEEPIDLE;
pub const TCP_KEEPINTVL = @import("../sa_std.zig").TCP_KEEPINTVL;
pub const TCP_QUICKACK = @import("../sa_std.zig").TCP_QUICKACK;
pub const TcpListener = @import("../sa_std.zig").TcpListener;
const addressSocketText = @import("../sa_std.zig").addressSocketText;
pub const armPeerCredHarvest = @import("../sa_std.zig").armPeerCredHarvest;
const buildInterfaceAddressesJson = @import("../sa_std.zig").buildInterfaceAddressesJson;
pub const builtin = @import("../sa_std.zig").builtin;
pub const cmsgAlign = @import("../sa_std.zig").cmsgAlign;
pub const cmsg_level_ip = @import("../sa_std.zig").cmsg_level_ip;
pub const cmsg_level_ipv6 = @import("../sa_std.zig").cmsg_level_ipv6;
pub const cmsg_level_socket = @import("../sa_std.zig").cmsg_level_socket;
pub const cmsg_type_ip_pktinfo = @import("../sa_std.zig").cmsg_type_ip_pktinfo;
pub const cmsg_type_ipv6_pktinfo = @import("../sa_std.zig").cmsg_type_ipv6_pktinfo;
pub const cmsg_type_timestamp = @import("../sa_std.zig").cmsg_type_timestamp;
pub const connectUnixSocketFd = @import("../sa_std.zig").connectUnixSocketFd;
pub const constBytes = @import("../sa_std.zig").constBytes;
pub const ensureSocketHandle = @import("../sa_std.zig").ensureSocketHandle;
pub const fail = @import("../sa_std.zig").fail;
pub const finish = @import("../sa_std.zig").finish;
pub const finishErr = @import("../sa_std.zig").finishErr;
pub const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
pub const getSocketOptBool = @import("../sa_std.zig").getSocketOptBool;
pub const getSocketOptByte = @import("../sa_std.zig").getSocketOptByte;
pub const getSocketOptBytes = @import("../sa_std.zig").getSocketOptBytes;
pub const getSocketOptInt = @import("../sa_std.zig").getSocketOptInt;
pub const getSocketOptLinger = @import("../sa_std.zig").getSocketOptLinger;
pub const getSocketOptTimeval = @import("../sa_std.zig").getSocketOptTimeval;
pub const getSocketOptU32 = @import("../sa_std.zig").getSocketOptU32;
pub const getUnixPeerCred = @import("../sa_std.zig").getUnixPeerCred;
pub const getUnixSockAddr = @import("../sa_std.zig").getUnixSockAddr;
pub const handleToFd = @import("../sa_std.zig").handleToFd;
pub const harvestedPeerCredLocked = @import("../sa_std.zig").harvestedPeerCredLocked;
pub const hostBytes = @import("../sa_std.zig").hostBytes;
pub const is_linux = @import("../sa_std.zig").is_linux;
pub const is_wasm = @import("../sa_std.zig").is_wasm;
const lenAsUsize = @import("../sa_std.zig").lenAsUsize;
pub const libc = @import("../sa_std.zig").libc;
pub const lockRegistry = @import("../sa_std.zig").lockRegistry;
pub const lxAccept = @import("../sa_std.zig").lxAccept;
pub const lxBind = @import("../sa_std.zig").lxBind;
pub const lxClose = @import("../sa_std.zig").lxClose;
pub const lxConnect = @import("../sa_std.zig").lxConnect;
pub const lxDup = @import("../sa_std.zig").lxDup;
pub const lxErr = @import("../sa_std.zig").lxErr;
pub const lxFcntl = @import("../sa_std.zig").lxFcntl;
pub const lxGetpeername = @import("../sa_std.zig").lxGetpeername;
pub const lxGetsockname = @import("../sa_std.zig").lxGetsockname;
pub const lxGetsockoptError = @import("../sa_std.zig").lxGetsockoptError;
pub const lxListen = @import("../sa_std.zig").lxListen;
pub const lxReadv = @import("../sa_std.zig").lxReadv;
pub const lxRecv = @import("../sa_std.zig").lxRecv;
pub const lxRecvfrom = @import("../sa_std.zig").lxRecvfrom;
pub const lxSend = @import("../sa_std.zig").lxSend;
pub const lxSendfile = @import("../sa_std.zig").lxSendfile;
pub const lxSendmsg = @import("../sa_std.zig").lxSendmsg;
pub const lxSendto = @import("../sa_std.zig").lxSendto;
pub const lxSetSocketOptBool = @import("../sa_std.zig").lxSetSocketOptBool;
pub const lxShutdown = @import("../sa_std.zig").lxShutdown;
pub const lxSocket = @import("../sa_std.zig").lxSocket;
pub const lxUnlink = @import("../sa_std.zig").lxUnlink;
pub const lxWritev = @import("../sa_std.zig").lxWritev;
pub const makeIpv4Membership = @import("../sa_std.zig").makeIpv4Membership;
pub const makeIpv6Membership = @import("../sa_std.zig").makeIpv6Membership;
pub const makeSockAddrStorage = @import("../sa_std.zig").makeSockAddrStorage;
pub const msg_peek = @import("../sa_std.zig").msg_peek;
pub const mutBytes = @import("../sa_std.zig").mutBytes;
const netErrorCodeName = @import("../sa_std.zig").netErrorCodeName;
pub const netGetAddressList = @import("../sa_std.zig").netGetAddressList;
const openOwnedByteBuffer = @import("../sa_std.zig").openOwnedByteBuffer;
pub const parseIp4Address = @import("../sa_std.zig").parseIp4Address;
pub const parseIp6Address = @import("../sa_std.zig").parseIp6Address;
pub const pathBytes = @import("../sa_std.zig").pathBytes;
pub const policyAllows = @import("../sa_std.zig").policyAllows;
const poll_wait_stack_handles = @import("../sa_std.zig").poll_wait_stack_handles;
pub const portFromU32 = @import("../sa_std.zig").portFromU32;
pub const portableRecvmsg = @import("../sa_std.zig").portableRecvmsg;
pub const rebuildTcpListenerV6Only = @import("../sa_std.zig").rebuildTcpListenerV6Only;
pub const rebuildUdpSocketV6Only = @import("../sa_std.zig").rebuildUdpSocketV6Only;
pub const recv_msg_flag_ctrunc = @import("../sa_std.zig").recv_msg_flag_ctrunc;
pub const recv_msg_flag_pktinfo = @import("../sa_std.zig").recv_msg_flag_pktinfo;
pub const recv_msg_flag_timestamp = @import("../sa_std.zig").recv_msg_flag_timestamp;
pub const recv_msg_flag_trunc = @import("../sa_std.zig").recv_msg_flag_trunc;
pub const recv_multi_max_msgs = @import("../sa_std.zig").recv_multi_max_msgs;
const registerNetAddrList = @import("../sa_std.zig").registerNetAddrList;
pub const registerNetAddrOutLocked = @import("../sa_std.zig").registerNetAddrOutLocked;
pub const registerResource = @import("../sa_std.zig").registerResource;
pub const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;
pub const registerUnixAddrOutLocked = @import("../sa_std.zig").registerUnixAddrOutLocked;
pub const resolveFirstAddressFromParts = @import("../sa_std.zig").resolveFirstAddressFromParts;
const resolveFirstSocketAddress = @import("../sa_std.zig").resolveFirstSocketAddress;
pub const sa_net_iov = @import("../sa_std.zig").sa_net_iov;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
pub const sa_std_read = @import("../sa_std.zig").sa_std_read;
pub const sa_std_write = @import("../sa_std.zig").sa_std_write;
pub const setSocketOptBool = @import("../sa_std.zig").setSocketOptBool;
pub const setSocketOptByte = @import("../sa_std.zig").setSocketOptByte;
pub const setSocketOptBytes = @import("../sa_std.zig").setSocketOptBytes;
pub const setSocketOptInt = @import("../sa_std.zig").setSocketOptInt;
pub const setSocketOptLinger = @import("../sa_std.zig").setSocketOptLinger;
pub const setSocketOptTimeval = @import("../sa_std.zig").setSocketOptTimeval;
pub const setSocketOptU32 = @import("../sa_std.zig").setSocketOptU32;
pub const socketAcceptConn = @import("../sa_std.zig").socketAcceptConn;
pub const socketAddressFamily = @import("../sa_std.zig").socketAddressFamily;
pub const socketIsDatagram = @import("../sa_std.zig").socketIsDatagram;
pub const socketIsInet = @import("../sa_std.zig").socketIsInet;
pub const socketIsStream = @import("../sa_std.zig").socketIsStream;
pub const socketIsUnix = @import("../sa_std.zig").socketIsUnix;
pub const takeResourceLocked = @import("../sa_std.zig").takeResourceLocked;
pub const tcpConnectAddressTimeout = @import("../sa_std.zig").tcpConnectAddressTimeout;
pub const tcpConnectTimeoutMs = @import("../sa_std.zig").tcpConnectTimeoutMs;
pub const tcpConnectToHostFd = @import("../sa_std.zig").tcpConnectToHostFd;
pub const tcpStreamFd = @import("../sa_std.zig").tcpStreamFd;
pub const tcp_nodelay = @import("../sa_std.zig").tcp_nodelay;
pub const udpSocketFd = @import("../sa_std.zig").udpSocketFd;
pub const unixAddrFromSockaddr = @import("../sa_std.zig").unixAddrFromSockaddr;
pub const unixDatagramRecvFrom = @import("../sa_std.zig").unixDatagramRecvFrom;
pub const unixSockAddrFromHandle = @import("../sa_std.zig").unixSockAddrFromHandle;
const writeFormattedInto = @import("../sa_std.zig").writeFormattedInto;
const writeHexLower = @import("../sa_std.zig").writeHexLower;

pub export fn sa_std_net_error_code_from_status(status: i32) i32 {
    return switch (status) {
        SA_STD_OK => 0,
        SA_STD_ERR_INVALID_ARGUMENT => 10,
        SA_STD_ERR_INVALID_HANDLE => 11,
        SA_STD_ERR_NOT_FOUND => 12,
        SA_STD_ERR_ACCESS => 8,
        SA_STD_ERR_NO_MEMORY => 13,
        SA_STD_ERR_IO => 14,
        SA_STD_ERR_NET => 15,
        SA_STD_ERR_UNSUPPORTED => 9,
        SA_STD_ERR_TRUNCATED => 14,
        else => 1,
    };
}

pub export fn sa_std_net_error_code_from_posix_errno(errno: i32) i32 {
    return switch (errno) {
        0 => 0,
        1, 13 => 8,
        2, 20 => 12,
        4 => 24,
        9 => 11,
        11 => 6,
        12 => 13,
        14, 22 => 10,
        17 => 23,
        32 => 22,
        98 => 16,
        99 => 17,
        100 => 27,
        101 => 15,
        103 => 19,
        104 => 18,
        107 => 20,
        110 => 4,
        111 => 3,
        113 => 21,
        -2, -4, -5 => 2,
        -3 => 4,
        -6, -7 => 9,
        -8 => 10,
        -10 => 13,
        -11 => 14,
        else => 1,
    };
}

pub export fn sa_std_net_error_code_from_wsa_error(native_error: i32) i32 {
    return switch (native_error) {
        0 => 0,
        10004 => 24,
        10013 => 8,
        10022 => 10,
        10024, 10055 => 13,
        10035, 10036, 10037 => 6,
        10038 => 11,
        10040 => 26,
        10041, 10042, 10043, 10044, 10045, 10046, 10047 => 9,
        10048 => 16,
        10049 => 17,
        10050, 10052 => 27,
        10051 => 15,
        10053 => 19,
        10054 => 18,
        10057, 10058 => 20,
        10060 => 4,
        10061 => 3,
        10064, 10065 => 21,
        11001, 11003, 11004 => 2,
        11002 => 4,
        else => 1,
    };
}

pub export fn sa_std_net_error_code_name(code: i32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const name = netErrorCodeName(code);
    if (out_len) |len_ptr| len_ptr.* = @as(u64, @intCast(name.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const cap = lenAsUsize(out_cap) catch |err| return finishErr(err);
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const copy_len = @min(cap, name.len);
    @memcpy(out_ptr[0..copy_len], name[0..copy_len]);
    if (copy_len != name.len) return finish(SA_STD_ERR_TRUNCATED);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_error_platform() i32 {
    return 1;
}

pub export fn sa_std_net_error_code_from_native_error(native_error: i32) i32 {
    return sa_std_net_error_code_from_posix_errno(native_error);
}

pub export fn sa_std_net_hostname(out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    _ = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    // wasm32-wasi: no HOST_NAME_MAX / gethostname; stub as unsupported.
    if (comptime builtin.cpu.arch.isWasm()) return finish(SA_STD_ERR_UNSUPPORTED);
    var buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const name = std.posix.gethostname(&buffer) catch |err| return finishErr(err);
    return writeFormattedInto(out, out_cap, out_len, name);
}

pub export fn sa_std_net_interface_addresses_json(out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const bytes = buildInterfaceAddressesJson(std.heap.page_allocator) catch |err| switch (err) {
        error.OutOfMemory => return finish(SA_STD_ERR_NO_MEMORY),
        else => return finish(SA_STD_ERR_IO),
    };
    const handle = openOwnedByteBuffer(bytes) catch return finish(SA_STD_ERR_NO_MEMORY);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_to_socket_addr_list(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const host = hostBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    out.* = registerNetAddrList(host, port16) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_addr_list_next(list_handle: u64, out_ok: ?*i32, out_addr: ?*u64) i32 {
    const ok_ptr = out_ok orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const addr_ptr = out_addr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ok_ptr.* = 0;
    addr_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(list_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const list = switch (resource.*) {
        .net_addr_list => |*value| value,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (list.next_index >= list.addresses.len) return finish(SA_STD_OK);
    const address = list.addresses[list.next_index];
    list.next_index += 1;
    const status = registerNetAddrOutLocked(address, addr_ptr);
    if (status != SA_STD_OK) {
        list.next_index -= 1;
        return status;
    }
    ok_ptr.* = 1;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_addr_list_remaining(list_handle: u64, out_remaining: ?*u64) i32 {
    const out = out_remaining orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(list_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const list = switch (resource.*) {
        .net_addr_list => |*value| value,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    out.* = @as(u64, @intCast(list.addresses.len -| list.next_index));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_addr_list_reset(list_handle: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(list_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const list = switch (resource.*) {
        .net_addr_list => |*value| value,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    list.next_index = 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_addr_list_free(list_handle: u64) i32 {
    return sa_std_close(list_handle);
}

pub export fn sa_std_net_addr_reverse_lookup(addr_handle: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    _ = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (comptime builtin.cpu.arch.isWasm()) return finish(SA_STD_ERR_UNSUPPORTED);
    // Snapshot the sockaddr under the registry lock; getnameinfo itself can
    // block on DNS and must not hold the registry.
    var address: NetAddress = undefined;
    {
        while (!sa_std.registry_mutex.tryLock()) {
            std.Thread.yield() catch {};
        }
        defer sa_std.registry_mutex.unlock();
        const resource = getResourceLocked(addr_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
        address = switch (resource.*) {
            .net_addr => |*value| value.addr,
            else => return finish(SA_STD_ERR_INVALID_HANDLE),
        };
    }
    var name_buf: [1025]u8 = undefined;
    const rc = std.c.getnameinfo(address.sockAddr(), address.getOsSockLen(), &name_buf, name_buf.len, null, 0, .{ .NAMEREQD = true });
    if (@backingInt(rc) != 0) return finish(SA_STD_ERR_IO);
    const name = std.mem.sliceTo(&name_buf, 0);
    return writeFormattedInto(out, out_cap, out_len, name);
}

pub export fn sa_std_net_to_socket_addr_first(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const address = resolveFirstSocketAddress(host_ptr, host_len, port) catch |err| return finishErr(err);
    var net_addr = NetAddrHandle.init(std.heap.page_allocator, address) catch |err| return finishErr(err);
    const handle = registerResource(.{ .net_addr = net_addr }) catch |err| {
        net_addr.deinit();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}










pub export fn sa_std_net_poll_wait(handles_ptr: ?[*]const u64, interests_ptr: ?[*]const u32, count: u64, timeout_ms: i32, ready_ptr: ?[*]u32, out_ready_count: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const ready_count_slot = out_ready_count orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ready_count_slot.* = 0;
    if (count > SA_STD_NET_POLL_MAX_HANDLES) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const n = lenAsUsize(count) catch |err| return finishErr(err);
    if (n == 0) {
        // A wait over an empty set is a plain timed sleep.
        var no_fds: [0]std.posix.pollfd = .{};
        _ = std.posix.poll(&no_fds, timeout_ms) catch |err| return finishErr(err);
        return finish(SA_STD_OK);
    }
    const handles = handles_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const interests = interests_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const ready = ready_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var stack_fds: [poll_wait_stack_handles]std.posix.pollfd = undefined;
    const heap_fds = if (n > poll_wait_stack_handles)
        std.heap.page_allocator.alloc(std.posix.pollfd, n) catch |err| return finishErr(err)
    else
        null;
    defer if (heap_fds) |buf| std.heap.page_allocator.free(buf);
    const fds: []std.posix.pollfd = if (heap_fds) |buf| buf else stack_fds[0..n];
    for (0..n) |i| {
        ready[i] = 0;
        const resolved = ensureSocketHandle(handles[i]) catch |err| return finishErr(err);
        var events: i16 = 0;
        if (interests[i] & SA_STD_NET_POLL_READ != 0) events |= std.posix.POLL.IN;
        if (interests[i] & SA_STD_NET_POLL_WRITE != 0) events |= std.posix.POLL.OUT;
        fds[i] = .{ .fd = resolved.fd, .events = events, .revents = 0 };
    }
    _ = std.posix.poll(fds, timeout_ms) catch |err| return finishErr(err);
    var ready_total: u64 = 0;
    for (0..n) |i| {
        const rev = fds[i].revents;
        var mask: u32 = 0;
        if (rev & std.posix.POLL.IN != 0) mask |= SA_STD_NET_POLL_READ;
        if (rev & std.posix.POLL.OUT != 0) mask |= SA_STD_NET_POLL_WRITE;
        if (rev & (std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0) mask |= SA_STD_NET_POLL_ERROR;
        if (rev & std.posix.POLL.HUP != 0) mask |= SA_STD_NET_POLL_ERROR | SA_STD_NET_POLL_READ;
        ready[i] = mask;
        if (mask != 0) ready_total += 1;
    }
    ready_count_slot.* = ready_total;
    return finish(SA_STD_OK);
}


































pub export fn sa_std_net_raw_socket(domain: u32, sock_type: u32, protocol: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (domain != AFT.INET and domain != AFT.INET6) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (sock_type != SOCKT.RAW and sock_type != SOCKT.DGRAM) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (protocol > 255) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const fd = lxSocket(domain, sock_type | SOCKT.CLOEXEC, protocol) catch |err| return finishErr(err);
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
















































pub export fn sa_std_net_socket_setsockopt(handle: u64, level: i32, optname: u32, value_ptr: ?[*]const u8, value_len: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const socket = ensureSocketHandle(handle) catch |err| return finishErr(err);
    const value = constBytes(value_ptr, value_len) catch |err| return finishErr(err);
    std.posix.setsockopt(socket.fd, level, optname, value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_socket_getsockopt(handle: u64, level: i32, optname: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_ptr.* = 0;
    const socket = ensureSocketHandle(handle) catch |err| return finishErr(err);
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (buffer.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var len: SockLenT = @as(SockLenT, @intCast(buffer.len));
    const rc = std.os.linux.getsockopt(socket.fd, level, optname, buffer.ptr, &len);
    const e = std.os.linux.errno(rc);
    if (e != .SUCCESS) return finishErr(lxErr(e));
    len_ptr.* = @as(u64, @intCast(len));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_socket_setsockopt_int(handle: u64, level: i32, optname: u32, value: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const socket = ensureSocketHandle(handle) catch |err| return finishErr(err);
    setSocketOptInt(socket.fd, level, optname, value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_socket_getsockopt_int(handle: u64, level: i32, optname: u32, out_value: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    const socket = ensureSocketHandle(handle) catch |err| return finishErr(err);
    value_ptr.* = getSocketOptInt(socket.fd, level, optname) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}



pub export fn sa_std_net_addr_format(addr: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_ptr.* = 0;
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(addr) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .net_addr => |net_addr| {
            const owned = addressSocketText(std.heap.page_allocator, net_addr.addr) catch |err| return finishErr(err);
            defer std.heap.page_allocator.free(owned);
            if (owned.len > buffer.len) return finish(SA_STD_ERR_TRUNCATED);
            @memcpy(buffer[0..owned.len], owned);
            len_ptr.* = @as(u64, @intCast(owned.len));
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}


















































pub export fn sa_std_net_ja3_hash(input_ptr: ?[*]const u8, input_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_slot.* = 0;
    if (out_cap < 32) return finish(SA_STD_ERR_TRUNCATED);
    const input = constBytes(input_ptr, input_len) catch |err| return finishErr(err);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var digest: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(input, &digest, .{});
    writeHexLower(out[0..32], digest[0..]);
    len_slot.* = 32;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_sha256_hex(input_ptr: ?[*]const u8, input_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_slot.* = 0;
    if (out_cap < 64) return finish(SA_STD_ERR_TRUNCATED);
    const input = constBytes(input_ptr, input_len) catch |err| return finishErr(err);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});
    writeHexLower(out[0..64], digest[0..]);
    len_slot.* = 64;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_ja4_hash12(input_ptr: ?[*]const u8, input_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_slot.* = 0;
    if (out_cap < 12) return finish(SA_STD_ERR_TRUNCATED);
    const input = constBytes(input_ptr, input_len) catch |err| return finishErr(err);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});
    // 12 hex chars = 6 bytes of digest.
    writeHexLower(out[0..12], digest[0..6]);
    len_slot.* = 12;
    return finish(SA_STD_OK);
}
