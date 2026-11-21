const std = @import("std");
pub const AFT = @import("std_net.zig").AFT;
pub const NetAddress = @import("std_net.zig").NetAddress;
const SA_NET_UNIX_ADDR_ABSTRACT = @import("std_net.zig").SA_NET_UNIX_ADDR_ABSTRACT;
const SA_NET_UNIX_ADDR_PATHNAME = @import("std_net.zig").SA_NET_UNIX_ADDR_PATHNAME;
pub const SA_STD_ERR_ACCESS = @import("std_net.zig").SA_STD_ERR_ACCESS;
pub const SA_STD_ERR_INVALID_ARGUMENT = @import("std_net.zig").SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_STD_ERR_INVALID_HANDLE = @import("std_net.zig").SA_STD_ERR_INVALID_HANDLE;
pub const SA_STD_ERR_IO = @import("std_net.zig").SA_STD_ERR_IO;
pub const SA_STD_ERR_NOT_FOUND = @import("std_net.zig").SA_STD_ERR_NOT_FOUND;
pub const SA_STD_ERR_NO_MEMORY = @import("std_net.zig").SA_STD_ERR_NO_MEMORY;
pub const SA_STD_ERR_UNSUPPORTED = @import("std_net.zig").SA_STD_ERR_UNSUPPORTED;
pub const SA_STD_OK = @import("std_net.zig").SA_STD_OK;
pub const SOCKT = @import("std_net.zig").SOCKT;
pub const SOLT = @import("std_net.zig").SOLT;
pub const SO_MARK = @import("std_net.zig").SO_MARK;
pub const SO_PASSCRED = @import("std_net.zig").SO_PASSCRED;
pub const SockAddrStorageT = @import("std_net.zig").SockAddrStorageT;
pub const SockAddrT = @import("std_net.zig").SockAddrT;
const SockAddrUnT = @import("std_net.zig").SockAddrUnT;
pub const SockLenT = @import("std_net.zig").SockLenT;
const TcpListener = @import("std_net.zig").TcpListener;
pub const armPeerCredHarvest = @import("std_net.zig").armPeerCredHarvest;
pub const builtin = @import("std_net.zig").builtin;
const connectUnixSocketFd = @import("std_net.zig").connectUnixSocketFd;
pub const constBytes = @import("std_net.zig").constBytes;
pub const ensureSocketHandle = @import("std_net.zig").ensureSocketHandle;
const fail = @import("std_net.zig").fail;
pub const finish = @import("std_net.zig").finish;
pub const finishErr = @import("std_net.zig").finishErr;
pub const getResourceLocked = @import("std_net.zig").getResourceLocked;
pub const getSocketOptBool = @import("std_net.zig").getSocketOptBool;
pub const getUnixPeerCred = @import("std_net.zig").getUnixPeerCred;
pub const getUnixSockAddr = @import("std_net.zig").getUnixSockAddr;
pub const harvestedPeerCredLocked = @import("std_net.zig").harvestedPeerCredLocked;
pub const is_linux = @import("std_net.zig").is_linux;
pub const is_wasm = @import("std_net.zig").is_wasm;
pub const libc = @import("std_net.zig").libc;
pub const lockRegistry = @import("std_net.zig").lockRegistry;
const lxAccept = @import("std_net.zig").lxAccept;
pub const lxBind = @import("std_net.zig").lxBind;
pub const lxClose = @import("std_net.zig").lxClose;
pub const lxConnect = @import("std_net.zig").lxConnect;
pub const lxDup = @import("std_net.zig").lxDup;
pub const lxGetpeername = @import("std_net.zig").lxGetpeername;
const lxListen = @import("std_net.zig").lxListen;
pub const lxSendto = @import("std_net.zig").lxSendto;
pub const lxShutdown = @import("std_net.zig").lxShutdown;
pub const lxSocket = @import("std_net.zig").lxSocket;
pub const lxUnlink = @import("std_net.zig").lxUnlink;
pub const msg_peek = @import("std_net.zig").msg_peek;
pub const pathBytes = @import("std_net.zig").pathBytes;
pub const registerResource = @import("std_net.zig").registerResource;
pub const registerResourceLocked = @import("std_net.zig").registerResourceLocked;
pub const registerUnixAddrOutLocked = @import("std_net.zig").registerUnixAddrOutLocked;
pub const sa_std = @import("std_net.zig").sa_std;
const sa_std_net_tcp_accept = @import("std_net_tcp.zig").sa_std_net_tcp_accept;
pub const setSocketOptBool = @import("std_net.zig").setSocketOptBool;
pub const setSocketOptU32 = @import("std_net.zig").setSocketOptU32;
const socketAcceptConn = @import("std_net.zig").socketAcceptConn;
pub const socketIsDatagram = @import("std_net.zig").socketIsDatagram;
const socketIsStream = @import("std_net.zig").socketIsStream;
pub const socketIsUnix = @import("std_net.zig").socketIsUnix;
pub const takeResourceLocked = @import("std_net.zig").takeResourceLocked;
const unixAddrFromSockaddr = @import("std_net.zig").unixAddrFromSockaddr;
pub const unixDatagramRecvFrom = @import("std_net.zig").unixDatagramRecvFrom;
pub const unixSockAddrFromHandle = @import("std_net.zig").unixSockAddrFromHandle;

pub export fn sa_std_net_unix_listen(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);

    var address = NetAddress.initUnix(path) catch |err| return finishErr(err);

    // Remove any stale socket file so bind() does not fail with AddrInUse.
    // Best-effort: a missing path is fine; other unlink errors surface at bind.
    lxUnlink(path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => {},
    };

    const fd = lxSocket(AFT.UNIX, SOCKT.STREAM | SOCKT.CLOEXEC, 0) catch |err| return finishErr(err);
    errdefer lxClose(fd);
    lxBind(fd, address.sockAddr(), address.getOsSockLen()) catch |err| return finishErr(err);
    lxListen(fd, 128) catch |err| return finishErr(err);

    const server = TcpListener{ .fd = fd, .addr = address };
    const handle = registerResource(.{ .tcp_listener = server }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_addr_from_abstract_name(name_ptr: ?[*]const u8, name_len: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const name = constBytes(name_ptr, name_len) catch |err| return finishErr(err);
    const tmp: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
    if (name.len + 1 > tmp.path.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const bytes = std.heap.page_allocator.dupe(u8, name) catch |err| return finishErr(err);
    const handle = registerResource(.{ .unix_addr = .{ .allocator = std.heap.page_allocator, .kind = SA_NET_UNIX_ADDR_ABSTRACT, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_addr_from_pathname(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    _ = NetAddress.initUnix(path) catch |err| return finishErr(err);
    const bytes = std.heap.page_allocator.dupe(u8, path) catch |err| return finishErr(err);
    const handle = registerResource(.{ .unix_addr = .{ .allocator = std.heap.page_allocator, .kind = SA_NET_UNIX_ADDR_PATHNAME, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_listen_addr(addr_handle: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const sockaddr = unixSockAddrFromHandle(addr_handle) catch |err| return finishErr(err);

    const fd = lxSocket(AFT.UNIX, SOCKT.STREAM | SOCKT.CLOEXEC, 0) catch |err| return finishErr(err);
    errdefer lxClose(fd);
    lxBind(fd, @as(*const SockAddrT, @ptrCast(&sockaddr.addr)), sockaddr.len) catch |err| return finishErr(err);
    lxListen(fd, 128) catch |err| return finishErr(err);

    const server = TcpListener{ .fd = fd, .addr = NetAddress.fromUnixSockaddr(sockaddr.addr, sockaddr.len) };
    const handle = registerResource(.{ .tcp_listener = server }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_accept(listener: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return sa_std_net_tcp_accept(listener, out_handle);
}

pub export fn sa_std_net_unix_accept_addr(listener: u64, out_stream: ?*u64, out_addr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const stream_ptr = out_stream orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const addr_ptr = out_addr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    stream_ptr.* = 0;
    addr_ptr.* = 0;

    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    const resource = getResourceLocked(listener) orelse {
        sa_std.registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const fd = switch (resource.*) {
        .tcp_listener => |server| server.fd,
        else => {
            sa_std.registry_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        },
    };
    if (!(socketIsUnix(fd) catch |err| {
        sa_std.registry_mutex.unlock();
        return finishErr(err);
    })) {
        sa_std.registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    }
    sa_std.registry_mutex.unlock();

    var accepted_addr: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
    @memset(&accepted_addr.path, 0);
    var addr_len: SockLenT = @sizeOf(SockAddrUnT);
    const accepted_fd = lxAccept(fd, @as(*SockAddrT, @ptrCast(&accepted_addr)), &addr_len, SOCKT.CLOEXEC) catch |err| return finishErr(err);

    var unix_addr = unixAddrFromSockaddr(std.heap.page_allocator, accepted_addr, addr_len) catch |err| {
        lxClose(accepted_fd);
        return finishErr(err);
    };

    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const stream_handle = registerResourceLocked(.{ .tcp_stream = accepted_fd }) catch |err| {
        unix_addr.deinit();
        lxClose(accepted_fd);
        return finishErr(err);
    };
    const addr_handle = registerResourceLocked(.{ .unix_addr = unix_addr }) catch |err| {
        if (takeResourceLocked(stream_handle)) |taken| {
            var mutable = taken;
            mutable.close() catch {};
        }
        unix_addr.deinit();
        return finishErr(err);
    };
    stream_ptr.* = stream_handle;
    addr_ptr.* = addr_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_pair(out_left: ?*u64, out_right: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const left_ptr = out_left orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const right_ptr = out_right orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    left_ptr.* = 0;
    right_ptr.* = 0;
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);

    var fds: [2]i32 = undefined;
    const socket_type = @as(i32, @intCast(SOCKT.STREAM | SOCKT.CLOEXEC));
    if (comptime is_linux) {
        const rc = std.os.linux.socketpair(AFT.UNIX, socket_type, 0, &fds);
        switch (std.os.linux.errno(rc)) {
            .SUCCESS => {},
            .INVAL => return finish(SA_STD_ERR_INVALID_ARGUMENT),
            .MFILE, .NFILE, .NOMEM => return finish(SA_STD_ERR_NO_MEMORY),
            .ACCES, .PERM => return finish(SA_STD_ERR_ACCESS),
            else => return finish(SA_STD_ERR_IO),
        }
    } else {
        var cfds: [2]c_int = undefined;
        const rc = libc.socketpair(@intCast(AFT.UNIX), socket_type, 0, &cfds);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {},
            .INVAL => return finish(SA_STD_ERR_INVALID_ARGUMENT),
            .MFILE, .NFILE, .NOMEM => return finish(SA_STD_ERR_NO_MEMORY),
            .ACCES, .PERM => return finish(SA_STD_ERR_ACCESS),
            else => return finish(SA_STD_ERR_IO),
        }
        _ = libc.fcntl(cfds[0], std.c.F.SETFD, @as(c_int, 1));
        _ = libc.fcntl(cfds[1], std.c.F.SETFD, @as(c_int, 1));
        fds = .{ cfds[0], cfds[1] };
    }

    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    var owns_left_fd = true;
    var owns_right_fd = true;
    errdefer {
        if (owns_left_fd) lxClose(fds[0]);
        if (owns_right_fd) lxClose(fds[1]);
    }

    const left_handle = registerResourceLocked(.{ .tcp_stream = fds[0] }) catch |err| return finishErr(err);
    owns_left_fd = false;
    errdefer {
        if (takeResourceLocked(left_handle)) |taken| {
            var mutable = taken;
            mutable.close() catch {};
        }
    }
    const right_handle = registerResourceLocked(.{ .tcp_stream = fds[1] }) catch |err| return finishErr(err);
    owns_right_fd = false;
    left_ptr.* = left_handle;
    right_ptr.* = right_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_listener_local_addr(listener: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(listener) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .tcp_listener => |server| {
            if (!(socketIsUnix(server.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
            const got = getUnixSockAddr(server.fd, false) catch |err| return finishErr(err);
            return registerUnixAddrOutLocked(got.addr, got.len, handle_ptr);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_net_unix_listener_try_clone(listener: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
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
    if (!(socketIsUnix(fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const dup_fd = lxDup(fd) catch |err| return finishErr(err);
    const cloned = TcpListener{ .fd = dup_fd, .addr = listen_address };
    const handle = registerResourceLocked(.{ .tcp_listener = cloned }) catch |err| {
        lxClose(dup_fd);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_listener_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const posix_fd = @as(std.posix.fd_t, @intCast(fd));
    if (!(socketIsUnix(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsStream(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketAcceptConn(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const got = getUnixSockAddr(posix_fd, false) catch |err| return finishErr(err);
    const server = TcpListener{ .fd = posix_fd, .addr = NetAddress.fromUnixSockaddr(got.addr, got.len) };
    const handle = registerResource(.{ .tcp_listener = server }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_stream_local_addr(stream: u64, out_handle: ?*u64) i32 {
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
            if (!(socketIsUnix(s) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
            const got = getUnixSockAddr(s, false) catch |err| return finishErr(err);
            return registerUnixAddrOutLocked(got.addr, got.len, handle_ptr);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_net_unix_stream_try_clone(stream: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const fd = switch (resource.*) {
        .tcp_stream => |s| s,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (!(socketIsUnix(fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const dup_fd = lxDup(fd) catch |err| return finishErr(err);
    const handle = registerResourceLocked(.{ .tcp_stream = dup_fd }) catch |err| {
        lxClose(dup_fd);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_stream_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const posix_fd = @as(std.posix.fd_t, @intCast(fd));
    if (!(socketIsUnix(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsStream(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (socketAcceptConn(posix_fd) catch |err| return finishErr(err)) return finish(SA_STD_ERR_INVALID_HANDLE);
    const handle = registerResource(.{ .tcp_stream = posix_fd }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_stream_peer_addr(stream: u64, out_handle: ?*u64) i32 {
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
            if (!(socketIsUnix(s) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
            const got = getUnixSockAddr(s, true) catch |err| return finishErr(err);
            return registerUnixAddrOutLocked(got.addr, got.len, handle_ptr);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_net_unix_stream_set_passcred(stream: u64, enabled: i32) i32 {
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptBool(handle.fd, SOLT.SOCKET, SO_PASSCRED, enabled != 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_stream_passcred(stream: u64, out_enabled: ?*i32) i32 {
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = if (getSocketOptBool(handle.fd, SOLT.SOCKET, SO_PASSCRED) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_stream_set_mark(stream: u64, mark: u32) i32 {
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptU32(handle.fd, SOLT.SOCKET, SO_MARK, mark) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_stream_peer_cred(stream: u64, out_pid: ?*i32, out_uid: ?*u32, out_gid: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const pid_ptr = out_pid orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const uid_ptr = out_uid orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const gid_ptr = out_gid orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pid_ptr.* = 0;
    uid_ptr.* = 0;
    gid_ptr.* = 0;
    const handle = ensureSocketHandle(stream) catch |err| return finishErr(err);
    if (handle.kind != .tcp_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const cred = getUnixPeerCred(handle.fd) catch |err| return finishErr(err);
    pid_ptr.* = cred.pid;
    uid_ptr.* = cred.uid;
    gid_ptr.* = cred.gid;
    return finish(SA_STD_OK);
}

pub const sa_std_net_unix_datagram_peer_cred = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_peer_cred;

pub const sa_std_net_unix_datagram_unbound = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_unbound;

pub const sa_std_net_unix_datagram_bind = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_bind;

pub const sa_std_net_unix_datagram_bind_addr = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_bind_addr;

pub const sa_std_net_unix_datagram_pair = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_pair;

pub const sa_std_net_unix_datagram_connect = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_connect;

pub const sa_std_net_unix_datagram_connect_addr = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_connect_addr;

pub const sa_std_net_unix_datagram_try_clone = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_try_clone;

pub const sa_std_net_unix_datagram_from_raw_fd = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_from_raw_fd;

pub const sa_std_net_unix_datagram_local_addr = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_local_addr;

pub const sa_std_net_unix_datagram_peer_addr = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_peer_addr;

pub const sa_std_net_unix_datagram_set_passcred = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_set_passcred;

pub const sa_std_net_unix_datagram_passcred = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_passcred;

pub const sa_std_net_unix_datagram_set_mark = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_set_mark;

pub const sa_std_net_unix_datagram_shutdown = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_shutdown;

pub const sa_std_net_unix_datagram_send_to = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_send_to;

pub const sa_std_net_unix_datagram_send_to_addr = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_send_to_addr;

pub const sa_std_net_unix_datagram_recv_from = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_recv_from;

pub const sa_std_net_unix_datagram_peek_from = @import("std_net_unix_dgram.zig").sa_std_net_unix_datagram_peek_from;

pub export fn sa_std_net_unix_connect(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);

    const stream_fd = connectUnixSocketFd(path) catch |err| return finishErr(err);
    errdefer lxClose(stream_fd);
    const handle = registerResource(.{ .tcp_stream = stream_fd }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_connect_addr(addr_handle: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const sockaddr = unixSockAddrFromHandle(addr_handle) catch |err| return finishErr(err);

    const fd = lxSocket(AFT.UNIX, SOCKT.STREAM | SOCKT.CLOEXEC, 0) catch |err| return finishErr(err);
    errdefer lxClose(fd);
    lxConnect(fd, @as(*const SockAddrT, @ptrCast(&sockaddr.addr)), sockaddr.len) catch |err| return finishErr(err);

    const handle = registerResource(.{ .tcp_stream = fd }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}
