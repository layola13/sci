const std = @import("std");
const AFT = @import("std_net.zig").AFT;
pub const IPPROTOT = @import("std_net.zig").IPPROTOT;
pub const NetAddrHandle = @import("std_net.zig").NetAddrHandle;
pub const NetAddress = @import("std_net.zig").NetAddress;
pub const SA_NET_IOV_MAX = @import("std_net.zig").SA_NET_IOV_MAX;
pub const SA_STD_ERR_INVALID_ARGUMENT = @import("std_net.zig").SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_STD_ERR_INVALID_HANDLE = @import("std_net.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_PERMISSION_DENIED = @import("std_net.zig").SA_STD_ERR_PERMISSION_DENIED;
pub const SA_STD_ERR_UNSUPPORTED = @import("std_net.zig").SA_STD_ERR_UNSUPPORTED;
pub const SA_STD_OK = @import("std_net.zig").SA_STD_OK;
const SOCKT = @import("std_net.zig").SOCKT;
pub const SOLT = @import("std_net.zig").SOLT;
pub const SOT = @import("std_net.zig").SOT;
pub const SockAddrStorageT = @import("std_net.zig").SockAddrStorageT;
pub const SockLenT = @import("std_net.zig").SockLenT;
pub const TCP_DEFER_ACCEPT = @import("std_net.zig").TCP_DEFER_ACCEPT;
pub const TCP_KEEPCNT = @import("std_net.zig").TCP_KEEPCNT;
pub const TCP_KEEPIDLE = @import("std_net.zig").TCP_KEEPIDLE;
pub const TCP_KEEPINTVL = @import("std_net.zig").TCP_KEEPINTVL;
pub const TCP_QUICKACK = @import("std_net.zig").TCP_QUICKACK;
const TcpListener = @import("std_net.zig").TcpListener;
pub const ensureSocketHandle = @import("std_net.zig").ensureSocketHandle;
pub const finish = @import("std_net.zig").finish;
pub const finishErr = @import("std_net.zig").finishErr;
pub const getResourceLocked = @import("std_net.zig").getResourceLocked;
pub const getSocketOptBool = @import("std_net.zig").getSocketOptBool;
pub const getSocketOptInt = @import("std_net.zig").getSocketOptInt;
pub const getSocketOptLinger = @import("std_net.zig").getSocketOptLinger;
pub const getSocketOptTimeval = @import("std_net.zig").getSocketOptTimeval;
pub const is_linux = @import("std_net.zig").is_linux;
pub const is_wasm = @import("std_net.zig").is_wasm;
const lxAccept = @import("std_net.zig").lxAccept;
const lxBind = @import("std_net.zig").lxBind;
pub const lxClose = @import("std_net.zig").lxClose;
const lxConnect = @import("std_net.zig").lxConnect;
pub const lxDup = @import("std_net.zig").lxDup;
pub const lxFcntl = @import("std_net.zig").lxFcntl;
pub const lxGetpeername = @import("std_net.zig").lxGetpeername;
pub const lxGetsockname = @import("std_net.zig").lxGetsockname;
const lxGetsockoptError = @import("std_net.zig").lxGetsockoptError;
const lxListen = @import("std_net.zig").lxListen;
pub const lxReadv = @import("std_net.zig").lxReadv;
pub const lxRecv = @import("std_net.zig").lxRecv;
pub const lxSendfile = @import("std_net.zig").lxSendfile;
const lxSetSocketOptBool = @import("std_net.zig").lxSetSocketOptBool;
const lxSocket = @import("std_net.zig").lxSocket;
pub const lxWritev = @import("std_net.zig").lxWritev;
const makeSockAddrStorage = @import("std_net.zig").makeSockAddrStorage;
pub const msg_peek = @import("std_net.zig").msg_peek;
pub const mutBytes = @import("std_net.zig").mutBytes;
const netGetAddressList = @import("std_net.zig").netGetAddressList;
const pathBytes = @import("std_net.zig").pathBytes;
const policyAllows = @import("std_net.zig").policyAllows;
const portFromU32 = @import("std_net.zig").portFromU32;
const rebuildTcpListenerV6Only = @import("std_net.zig").rebuildTcpListenerV6Only;
pub const registerNetAddrOutLocked = @import("std_net.zig").registerNetAddrOutLocked;
pub const registerResource = @import("std_net.zig").registerResource;
pub const registerResourceLocked = @import("std_net.zig").registerResourceLocked;
const resolveFirstAddressFromParts = @import("std_net.zig").resolveFirstAddressFromParts;
pub const sa_net_iov = @import("std_net.zig").sa_net_iov;
pub const sa_std = @import("std_net.zig").sa_std;
pub const sa_std_read = @import("std_net.zig").sa_std_read;
pub const sa_std_write = @import("std_net.zig").sa_std_write;
pub const setSocketOptBool = @import("std_net.zig").setSocketOptBool;
pub const setSocketOptInt = @import("std_net.zig").setSocketOptInt;
pub const setSocketOptLinger = @import("std_net.zig").setSocketOptLinger;
pub const setSocketOptTimeval = @import("std_net.zig").setSocketOptTimeval;
pub const socketAcceptConn = @import("std_net.zig").socketAcceptConn;
const socketAddressFamily = @import("std_net.zig").socketAddressFamily;
pub const socketIsInet = @import("std_net.zig").socketIsInet;
pub const socketIsStream = @import("std_net.zig").socketIsStream;
pub const socketIsUnix = @import("std_net.zig").socketIsUnix;
const takeResourceLocked = @import("std_net.zig").takeResourceLocked;
const tcpConnectAddressTimeout = @import("std_net.zig").tcpConnectAddressTimeout;
const tcpConnectTimeoutMs = @import("std_net.zig").tcpConnectTimeoutMs;
const tcpConnectToHostFd = @import("std_net.zig").tcpConnectToHostFd;
pub const tcpStreamFd = @import("std_net.zig").tcpStreamFd;
pub const tcp_nodelay = @import("std_net.zig").tcp_nodelay;

pub const sa_std_net_tcp_stream_read = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_read;

pub const sa_std_net_tcp_stream_read_vectored = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_read_vectored;

pub const sa_std_net_tcp_stream_write_vectored = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_write_vectored;

pub const sa_std_net_tcp_stream_peek = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_peek;

pub const sa_std_net_tcp_stream_write = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_write;

pub const sa_std_net_tcp_stream_peer_addr = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_peer_addr;

pub const sa_std_net_tcp_stream_local_addr = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_local_addr;

pub const sa_std_net_tcp_stream_try_clone = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_try_clone;

pub const sa_std_net_tcp_stream_set_nonblocking = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_nonblocking;

pub const sa_std_net_tcp_stream_set_nodelay = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_nodelay;

pub const sa_std_net_tcp_stream_set_linger = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_linger;

pub const sa_std_net_tcp_stream_linger = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_linger;

pub const sa_std_net_tcp_stream_set_quickack = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_quickack;

pub const sa_std_net_tcp_stream_quickack = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_quickack;

pub const sa_std_net_tcp_stream_set_deferaccept = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_deferaccept;

pub const sa_std_net_tcp_stream_deferaccept = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_deferaccept;

pub const sa_std_net_tcp_stream_set_keepalive = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_keepalive;

pub const sa_std_net_tcp_stream_keepalive = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_keepalive;

pub const sa_std_net_tcp_stream_set_keepalive_params = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_keepalive_params;

pub export fn sa_std_net_tcp_listener_set_reuseaddr(listener: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(listener) catch |err| return finishErr(err);
    if (handle.kind != .tcp_listener) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (socketIsUnix(handle.fd) catch |err| return finishErr(err)) return finish(SA_STD_OK);
    setSocketOptBool(handle.fd, SOLT.SOCKET, SOT.REUSEADDR, enabled != 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listener_set_reuseport(listener: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(listener) catch |err| return finishErr(err);
    if (handle.kind != .tcp_listener) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (socketIsUnix(handle.fd) catch |err| return finishErr(err)) return finish(SA_STD_OK);
    setSocketOptBool(handle.fd, SOLT.SOCKET, SOT.REUSEPORT, enabled != 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub const sa_std_net_tcp_stream_set_read_timeout = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_read_timeout;

pub const sa_std_net_tcp_stream_set_write_timeout = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_write_timeout;

pub const sa_std_net_tcp_stream_set_ttl = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_ttl;

pub const sa_std_net_tcp_stream_read_timeout = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_read_timeout;

pub const sa_std_net_tcp_stream_write_timeout = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_write_timeout;

pub const sa_std_net_tcp_stream_nodelay = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_nodelay;

pub const sa_std_net_tcp_stream_ttl = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_ttl;

pub const sa_std_net_tcp_stream_set_recv_buffer_size = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_recv_buffer_size;

pub const sa_std_net_tcp_stream_recv_buffer_size = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_recv_buffer_size;

pub const sa_std_net_tcp_stream_set_send_buffer_size = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_send_buffer_size;

pub const sa_std_net_tcp_stream_send_buffer_size = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_send_buffer_size;

pub const sa_std_net_tcp_stream_take_error = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_take_error;

pub export fn sa_std_net_tcp_listener_try_clone(listener: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(listener) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var listen_address: NetAddress = undefined;
    const fd = switch (resource.*) {
        .tcp_listener => |server| blk: {
            listen_address = server.addr;
            break :blk server.fd;
        },
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    const dup_fd = lxDup(fd) catch |err| return finishErr(err);
    const cloned = TcpListener{ .fd = dup_fd, .addr = listen_address };
    const handle = registerResourceLocked(.{ .tcp_listener = cloned }) catch |err| {
        lxClose(dup_fd);
        return finishErr(err);
    };
    out.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listener_set_only_v6(listener: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(listener) catch |err| return finishErr(err);
    if (handle.kind != .tcp_listener) return finish(SA_STD_ERR_INVALID_HANDLE);
    const family = socketAddressFamily(handle.fd) catch |err| return finishErr(err);
    if (family != AFT.INET6) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    lxSetSocketOptBool(handle.fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY, enabled != 0) catch |err| {
        // A bound socket refuses IPV6_V6ONLY with EINVAL (bind-time
        // option); rebuild the socket with the option applied pre-bind.
        if (err != error.InvalidArgument) return finishErr(err);
        rebuildTcpListenerV6Only(listener, enabled != 0) catch |err2| return finishErr(err2);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listener_only_v6(listener: u64, out_enabled: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(listener) catch |err| return finishErr(err);
    if (handle.kind != .tcp_listener) return finish(SA_STD_ERR_INVALID_HANDLE);
    const family = socketAddressFamily(handle.fd) catch |err| return finishErr(err);
    if (family != AFT.INET6) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = if (getSocketOptBool(handle.fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listener_set_nonblocking(listener: u64, enabled: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(listener) catch |err| return finishErr(err);
    if (handle.kind != .tcp_listener) return finish(SA_STD_ERR_INVALID_HANDLE);
    const flags = lxFcntl(handle.fd, std.posix.F.GETFL, 0) catch |err| return finishErr(err);
    const new_flags = if (enabled != 0)
        flags | @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK")
    else
        flags & ~(@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"));
    _ = lxFcntl(handle.fd, std.posix.F.SETFL, new_flags) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listener_set_ttl(listener: u64, ttl: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(listener) catch |err| return finishErr(err);
    if (handle.kind != .tcp_listener) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (ttl > @as(u32, @intCast(std.math.maxInt(i32)))) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    setSocketOptInt(handle.fd, IPPROTOT.IP, std.posix.IP.TTL, @as(i32, @intCast(ttl))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listener_ttl(listener: u64, out_ttl: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_ttl orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(listener) catch |err| return finishErr(err);
    if (handle.kind != .tcp_listener) return finish(SA_STD_ERR_INVALID_HANDLE);
    const ttl = getSocketOptInt(handle.fd, IPPROTOT.IP, std.posix.IP.TTL) catch |err| return finishErr(err);
    if (ttl < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @as(u32, @intCast(ttl));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listener_take_error(listener: u64, out_error: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_error orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(listener) catch |err| return finishErr(err);
    if (handle.kind != .tcp_listener) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = getSocketOptInt(handle.fd, SOLT.SOCKET, SOT.ERROR) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub const sa_std_net_tcp_stream_send_file = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_send_file;

pub export fn sa_std_net_tcp_listen(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64, out_bound_port: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (out_bound_port) |port_ptr| port_ptr.* = 0;
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);

    const address = resolveFirstAddressFromParts(host, port16) catch |err| return finishErr(err);
    const listen_fd = lxSocket(address.storage.family, SOCKT.STREAM | SOCKT.CLOEXEC, IPPROTOT.TCP) catch |err| return finishErr(err);
    errdefer lxClose(listen_fd);
    setSocketOptBool(listen_fd, SOLT.SOCKET, SOT.REUSEADDR, true) catch |err| return finishErr(err);
    lxBind(listen_fd, address.sockAddr(), address.getOsSockLen()) catch |err| return finishErr(err);
    lxListen(listen_fd, 128) catch |err| return finishErr(err);
    const handle = registerResource(.{ .tcp_listener = .{ .fd = listen_fd, .addr = address } }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    if (out_bound_port) |port_ptr| {
        var addr = NetAddress{};
        var addr_len: SockLenT = @sizeOf(SockAddrStorageT);
        lxGetsockname(listen_fd, addr.sockAddrMut(), &addr_len) catch |err| return finishErr(err);
        addr.len = addr_len;
        port_ptr.* = addr.getPort();
    }
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_accept(listener_handle: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    const resource = getResourceLocked(listener_handle) orelse {
        sa_std.registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const listener = switch (resource.*) {
        .tcp_listener => |server| server,
        else => {
            sa_std.registry_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        },
    };
    sa_std.registry_mutex.unlock();

    const accepted_fd = lxAccept(listener.fd, null, null, SOCKT.CLOEXEC) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    const handle = registerResourceLocked(.{ .tcp_stream = accepted_fd }) catch |err| {
        sa_std.registry_mutex.unlock();
        lxClose(accepted_fd);
        return finishErr(err);
    };
    sa_std.registry_mutex.unlock();
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_accept_addr(listener_handle: u64, out_stream: ?*u64, out_addr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const stream_ptr = out_stream orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const addr_ptr = out_addr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    stream_ptr.* = 0;
    addr_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    const resource = getResourceLocked(listener_handle) orelse {
        sa_std.registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const listener = switch (resource.*) {
        .tcp_listener => |server| server,
        else => {
            sa_std.registry_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        },
    };
    sa_std.registry_mutex.unlock();

    var peer_storage: SockAddrStorageT = makeSockAddrStorage();
    var peer_len: SockLenT = @sizeOf(SockAddrStorageT);
    const accepted_fd = lxAccept(listener.fd, @ptrCast(&peer_storage), &peer_len, SOCKT.CLOEXEC) catch |err| return finishErr(err);
    var peer_addr = NetAddrHandle.init(std.heap.page_allocator, .{ .storage = peer_storage, .len = peer_len }) catch |err| {
        lxClose(accepted_fd);
        return finishErr(err);
    };
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    const stream_handle = registerResourceLocked(.{ .tcp_stream = accepted_fd }) catch |err| {
        sa_std.registry_mutex.unlock();
        peer_addr.deinit();
        lxClose(accepted_fd);
        return finishErr(err);
    };
    const addr_handle = registerResourceLocked(.{ .net_addr = peer_addr }) catch |err| {
        if (takeResourceLocked(stream_handle)) |taken| {
            var mutable = taken;
            mutable.close() catch {};
        }
        sa_std.registry_mutex.unlock();
        peer_addr.deinit();
        return finishErr(err);
    };
    sa_std.registry_mutex.unlock();
    stream_ptr.* = stream_handle;
    addr_ptr.* = addr_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listener_local_addr(listener_handle: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(listener_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .tcp_listener => |server| {
            var addr = NetAddress{};
            var addr_len: SockLenT = @sizeOf(SockAddrStorageT);
            lxGetsockname(server.fd, addr.sockAddrMut(), &addr_len) catch |err| return finishErr(err);
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

pub export fn sa_std_net_tcp_listener_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const posix_fd = @as(std.posix.fd_t, @intCast(fd));
    if (!(socketIsInet(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsStream(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketAcceptConn(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    var addr = NetAddress{};
    var addr_len: SockLenT = @sizeOf(SockAddrStorageT);
    lxGetsockname(posix_fd, addr.sockAddrMut(), &addr_len) catch |err| return finishErr(err);
    addr.len = addr_len;
    const server = TcpListener{ .fd = posix_fd, .addr = addr };
    const handle = registerResource(.{ .tcp_listener = server }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    if (!policyAllows(.{ .net = .{ .host = host, .port = port16 } })) return finish(SA_STD_ERR_PERMISSION_DENIED);

    const stream_fd = tcpConnectToHostFd(host, port16) catch |err| return finishErr(err);
    errdefer lxClose(stream_fd);
    const handle = registerResource(.{ .tcp_stream = stream_fd }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect_timeout(host_ptr: ?[*]const u8, host_len: u64, port: u32, timeout_ns: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const timeout_ms = tcpConnectTimeoutMs(timeout_ns) catch |err| return finishErr(err);
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    const address = resolveFirstAddressFromParts(host, port16) catch |err| return finishErr(err);
    const fd = lxSocket(address.storage.family, SOCKT.STREAM | SOCKT.NONBLOCK | SOCKT.CLOEXEC, IPPROTOT.TCP) catch |err| return finishErr(err);
    errdefer lxClose(fd);
    lxConnect(fd, address.sockAddr(), address.getOsSockLen()) catch |err| switch (err) {
        error.WouldBlock, error.ConnectionPending => {
            var poll_fds = [_]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.OUT, .revents = 0 }};
            const ready = std.posix.poll(&poll_fds, timeout_ms) catch |poll_err| return finishErr(poll_err);
            if (ready == 0) return finishErr(error.ConnectionTimedOut);
            lxGetsockoptError(fd) catch |socket_err| return finishErr(socket_err);
        },
        else => return finishErr(err),
    };
    const flags = lxFcntl(fd, std.posix.F.GETFL, 0) catch |err| return finishErr(err);
    const blocking_flags = flags & ~(@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"));
    _ = lxFcntl(fd, std.posix.F.SETFL, blocking_flags) catch |err| return finishErr(err);
    handle_ptr.* = registerResource(.{ .tcp_stream = fd }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect_timeout_addr(addr_handle: u64, timeout_ns: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const timeout_ms = tcpConnectTimeoutMs(timeout_ns) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    const address = blk: {
        const resource = getResourceLocked(addr_handle) orelse {
            sa_std.registry_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        };
        break :blk switch (resource.*) {
            .net_addr => |net_addr| net_addr.addr,
            else => {
                sa_std.registry_mutex.unlock();
                return finish(SA_STD_ERR_INVALID_HANDLE);
            },
        };
    };
    sa_std.registry_mutex.unlock();
    const stream_fd = tcpConnectAddressTimeout(address, timeout_ms) catch |err| return finishErr(err);
    errdefer lxClose(stream_fd);
    handle_ptr.* = registerResource(.{ .tcp_stream = stream_fd }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect_timeout_all(host_ptr: ?[*]const u8, host_len: u64, port: u32, timeout_ns: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const timeout_ms = tcpConnectTimeoutMs(timeout_ns) catch |err| return finishErr(err);
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);
    var list = netGetAddressList(std.heap.page_allocator, host, port16) catch |err| return finishErr(err);
    defer list.deinit();
    if (list.addrs.len == 0) return finishErr(error.HostLacksNetworkAddresses);
    var last_connect_error: anyerror = error.ConnectionRefused;
    for (list.addrs) |address| {
        const stream_fd = tcpConnectAddressTimeout(address, timeout_ms) catch |err| {
            last_connect_error = err;
            continue;
        };
        handle_ptr.* = registerResource(.{ .tcp_stream = stream_fd }) catch |err| {
            lxClose(stream_fd);
            return finishErr(err);
        };
        return finish(SA_STD_OK);
    }
    return finishErr(last_connect_error);
}

pub const sa_std_net_tcp_stream_from_raw_fd = @import("std_net_tcp_stream.zig").sa_std_net_tcp_stream_from_raw_fd;
