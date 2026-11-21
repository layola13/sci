const std = @import("std");
const AFT = @import("std_net_unix.zig").AFT;
const NetAddress = @import("std_net_unix.zig").NetAddress;
const SA_STD_ERR_ACCESS = @import("std_net_unix.zig").SA_STD_ERR_ACCESS;
const SA_STD_ERR_INVALID_ARGUMENT = @import("std_net_unix.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("std_net_unix.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("std_net_unix.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NOT_FOUND = @import("std_net_unix.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("std_net_unix.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_UNSUPPORTED = @import("std_net_unix.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("std_net_unix.zig").SA_STD_OK;
const SOCKT = @import("std_net_unix.zig").SOCKT;
const SOLT = @import("std_net_unix.zig").SOLT;
const SO_MARK = @import("std_net_unix.zig").SO_MARK;
const SO_PASSCRED = @import("std_net_unix.zig").SO_PASSCRED;
const SockAddrStorageT = @import("std_net_unix.zig").SockAddrStorageT;
const SockAddrT = @import("std_net_unix.zig").SockAddrT;
const SockLenT = @import("std_net_unix.zig").SockLenT;
const armPeerCredHarvest = @import("std_net_unix.zig").armPeerCredHarvest;
const builtin = @import("std_net_unix.zig").builtin;
const constBytes = @import("std_net_unix.zig").constBytes;
const ensureSocketHandle = @import("std_net_unix.zig").ensureSocketHandle;
const finish = @import("std_net_unix.zig").finish;
const finishErr = @import("std_net_unix.zig").finishErr;
const getResourceLocked = @import("std_net_unix.zig").getResourceLocked;
const getSocketOptBool = @import("std_net_unix.zig").getSocketOptBool;
const getUnixPeerCred = @import("std_net_unix.zig").getUnixPeerCred;
const getUnixSockAddr = @import("std_net_unix.zig").getUnixSockAddr;
const harvestedPeerCredLocked = @import("std_net_unix.zig").harvestedPeerCredLocked;
const is_linux = @import("std_net_unix.zig").is_linux;
const is_wasm = @import("std_net_unix.zig").is_wasm;
const libc = @import("std_net_unix.zig").libc;
const lockRegistry = @import("std_net_unix.zig").lockRegistry;
const lxBind = @import("std_net_unix.zig").lxBind;
const lxClose = @import("std_net_unix.zig").lxClose;
const lxConnect = @import("std_net_unix.zig").lxConnect;
const lxDup = @import("std_net_unix.zig").lxDup;
const lxGetpeername = @import("std_net_unix.zig").lxGetpeername;
const lxSendto = @import("std_net_unix.zig").lxSendto;
const lxShutdown = @import("std_net_unix.zig").lxShutdown;
const lxSocket = @import("std_net_unix.zig").lxSocket;
const lxUnlink = @import("std_net_unix.zig").lxUnlink;
const msg_peek = @import("std_net_unix.zig").msg_peek;
const pathBytes = @import("std_net_unix.zig").pathBytes;
const registerResource = @import("std_net_unix.zig").registerResource;
const registerResourceLocked = @import("std_net_unix.zig").registerResourceLocked;
const registerUnixAddrOutLocked = @import("std_net_unix.zig").registerUnixAddrOutLocked;
const sa_std = @import("std_net_unix.zig").sa_std;
const setSocketOptBool = @import("std_net_unix.zig").setSocketOptBool;
const setSocketOptU32 = @import("std_net_unix.zig").setSocketOptU32;
const socketIsDatagram = @import("std_net_unix.zig").socketIsDatagram;
const socketIsUnix = @import("std_net_unix.zig").socketIsUnix;
const takeResourceLocked = @import("std_net_unix.zig").takeResourceLocked;
const unixDatagramRecvFrom = @import("std_net_unix.zig").unixDatagramRecvFrom;
const unixSockAddrFromHandle = @import("std_net_unix.zig").unixSockAddrFromHandle;

pub export fn sa_std_net_unix_datagram_peer_cred(socket: u64, out_pid: ?*i32, out_uid: ?*u32, out_gid: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const pid_ptr = out_pid orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const uid_ptr = out_uid orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const gid_ptr = out_gid orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pid_ptr.* = 0;
    uid_ptr.* = 0;
    gid_ptr.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const cred = getUnixPeerCred(handle.fd) catch |err| return finishErr(err);
    if (cred.pid != 0) {
        pid_ptr.* = cred.pid;
        uid_ptr.* = cred.uid;
        gid_ptr.* = cred.gid;
        return finish(SA_STD_OK);
    }
    // SO_PEERCRED answers only the zero sentinel for path-bound
    // datagram sockets (see the harvest note at getUnixPeerCred).
    // Fall back to the credential harvested from SCM_CREDENTIALS
    // when this socket has received a datagram from its peer.
    lockRegistry();
    const harvested = harvestedPeerCredLocked(socket, handle.fd);
    sa_std.registry_mutex.unlock();
    if (harvested) |hc| {
        pid_ptr.* = hc.pid;
        uid_ptr.* = hc.uid;
        gid_ptr.* = hc.gid;
        return finish(SA_STD_OK);
    }
    // A connected socket whose peer never sent us anything has no
    // truthful credential source: report NOT_FOUND loudly instead
    // of dressing the zero sentinel up as an answer. An
    // unconnected socket keeps the documented zero sentinel
    // (pid 0) with OK.
    var peer_addr = NetAddress{};
    var peer_len: SockLenT = @sizeOf(SockAddrStorageT);
    lxGetpeername(handle.fd, peer_addr.sockAddrMut(), &peer_len) catch {
        return finish(SA_STD_OK);
    };
    return finish(SA_STD_ERR_NOT_FOUND);
}

pub export fn sa_std_net_unix_datagram_unbound(out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);
    const fd = lxSocket(AFT.UNIX, SOCKT.DGRAM | SOCKT.CLOEXEC, 0) catch |err| return finishErr(err);
    errdefer lxClose(fd);
    armPeerCredHarvest(fd);
    const handle = registerResource(.{ .udp_socket = fd }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_bind(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    var address = NetAddress.initUnix(path) catch |err| return finishErr(err);

    lxUnlink(path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => {},
    };

    const fd = lxSocket(AFT.UNIX, SOCKT.DGRAM | SOCKT.CLOEXEC, 0) catch |err| return finishErr(err);
    errdefer lxClose(fd);
    lxBind(fd, address.sockAddr(), address.getOsSockLen()) catch |err| return finishErr(err);
    armPeerCredHarvest(fd);
    const handle = registerResource(.{ .udp_socket = fd }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_bind_addr(addr_handle: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const sockaddr = unixSockAddrFromHandle(addr_handle) catch |err| return finishErr(err);
    const fd = lxSocket(AFT.UNIX, SOCKT.DGRAM | SOCKT.CLOEXEC, 0) catch |err| return finishErr(err);
    errdefer lxClose(fd);
    lxBind(fd, @as(*const SockAddrT, @ptrCast(&sockaddr.addr)), sockaddr.len) catch |err| return finishErr(err);
    armPeerCredHarvest(fd);
    const handle = registerResource(.{ .udp_socket = fd }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_pair(out_left: ?*u64, out_right: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const left_ptr = out_left orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const right_ptr = out_right orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    left_ptr.* = 0;
    right_ptr.* = 0;
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);

    var fds: [2]i32 = undefined;
    const socket_type = @as(i32, @intCast(SOCKT.DGRAM | SOCKT.CLOEXEC));
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

    armPeerCredHarvest(fds[0]);
    armPeerCredHarvest(fds[1]);
    const left_handle = registerResourceLocked(.{ .udp_socket = fds[0] }) catch |err| return finishErr(err);
    owns_left_fd = false;
    errdefer {
        if (takeResourceLocked(left_handle)) |taken| {
            var mutable = taken;
            mutable.close() catch {};
        }
    }
    const right_handle = registerResourceLocked(.{ .udp_socket = fds[1] }) catch |err| return finishErr(err);
    owns_right_fd = false;
    left_ptr.* = left_handle;
    right_ptr.* = right_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_connect(socket: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    var address = NetAddress.initUnix(path) catch |err| return finishErr(err);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    lxConnect(handle.fd, address.sockAddr(), address.getOsSockLen()) catch |err| return finishErr(err);
    armPeerCredHarvest(handle.fd);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_connect_addr(socket: u64, addr_handle: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const sockaddr = unixSockAddrFromHandle(addr_handle) catch |err| return finishErr(err);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    lxConnect(handle.fd, @as(*const SockAddrT, @ptrCast(&sockaddr.addr)), sockaddr.len) catch |err| return finishErr(err);
    armPeerCredHarvest(handle.fd);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_try_clone(socket: u64, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const fd = switch (resource.*) {
        .udp_socket => |fd| fd,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (!(socketIsUnix(fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsDatagram(fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const dup_fd = lxDup(fd) catch |err| return finishErr(err);
    const handle = registerResourceLocked(.{ .udp_socket = dup_fd }) catch |err| {
        lxClose(dup_fd);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const posix_fd = @as(std.posix.fd_t, @intCast(fd));
    if (!(socketIsUnix(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsDatagram(posix_fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const handle = registerResource(.{ .udp_socket = posix_fd }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_local_addr(socket: u64, out_handle: ?*u64) i32 {
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
            if (!(socketIsUnix(fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
            const got = getUnixSockAddr(fd, false) catch |err| return finishErr(err);
            return registerUnixAddrOutLocked(got.addr, got.len, handle_ptr);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_net_unix_datagram_peer_addr(socket: u64, out_handle: ?*u64) i32 {
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
            if (!(socketIsUnix(fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
            const got = getUnixSockAddr(fd, true) catch |err| return finishErr(err);
            return registerUnixAddrOutLocked(got.addr, got.len, handle_ptr);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_net_unix_datagram_set_passcred(socket: u64, enabled: i32) i32 {
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptBool(handle.fd, SOLT.SOCKET, SO_PASSCRED, enabled != 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_passcred(socket: u64, out_enabled: ?*i32) i32 {
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = if (getSocketOptBool(handle.fd, SOLT.SOCKET, SO_PASSCRED) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_set_mark(socket: u64, mark: u32) i32 {
    if (comptime !is_linux) return finish(SA_STD_ERR_UNSUPPORTED);
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    setSocketOptU32(handle.fd, SOLT.SOCKET, SO_MARK, mark) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_shutdown(socket: u64, how: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const shutdown: i32 = switch (how) {
        0 => std.posix.SHUT.RD,
        1 => std.posix.SHUT.WR,
        2 => std.posix.SHUT.RDWR,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    lxShutdown(handle.fd, shutdown) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_send_to(socket: u64, buf: ?[*]const u8, len: u64, path_ptr: ?[*]const u8, path_len: u64, out_written: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    written_ptr.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    var address = NetAddress.initUnix(path) catch |err| return finishErr(err);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const written = lxSendto(handle.fd, bytes, 0, address.sockAddr(), address.getOsSockLen()) catch |err| return finishErr(err);
    written_ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_send_to_addr(socket: u64, buf: ?[*]const u8, len: u64, addr_handle: u64, out_written: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    written_ptr.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const sockaddr = unixSockAddrFromHandle(addr_handle) catch |err| return finishErr(err);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    const written = lxSendto(handle.fd, bytes, 0, @as(*const SockAddrT, @ptrCast(&sockaddr.addr)), sockaddr.len) catch |err| return finishErr(err);
    written_ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_unix_datagram_recv_from(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return unixDatagramRecvFrom(socket, out, cap, 0, out_read, out_addr);
}

pub export fn sa_std_net_unix_datagram_peek_from(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    return unixDatagramRecvFrom(socket, out, cap, msg_peek, out_read, out_addr);
}
