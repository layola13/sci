const std = @import("std");
const sa_std = @import("../sa_std.zig");
const AFT = @import("../sa_std.zig").AFT;
const IPPROTOT = @import("../sa_std.zig").IPPROTOT;
const LinuxUCred = @import("../sa_std.zig").LinuxUCred;
const NetAddress = @import("../sa_std.zig").NetAddress;
const SA_NET_UNIX_ADDR_ABSTRACT = @import("../sa_std.zig").SA_NET_UNIX_ADDR_ABSTRACT;
const SA_NET_UNIX_ADDR_PATHNAME = @import("../sa_std.zig").SA_NET_UNIX_ADDR_PATHNAME;
const SA_NET_UNIX_ADDR_UNNAMED = @import("../sa_std.zig").SA_NET_UNIX_ADDR_UNNAMED;
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const SOCKT = @import("../sa_std.zig").SOCKT;
const SOLT = @import("../sa_std.zig").SOLT;
const SOT = @import("../sa_std.zig").SOT;
const SockAddrStorageT = @import("../sa_std.zig").SockAddrStorageT;
const SockAddrT = @import("../sa_std.zig").SockAddrT;
const SockAddrUnT = @import("../sa_std.zig").SockAddrUnT;
const SockLenT = @import("../sa_std.zig").SockLenT;
const Timeval = @import("../sa_std.zig").Timeval;
const builtin = @import("../sa_std.zig").builtin;
const errnoToAny = @import("../sa_std.zig").errnoToAny;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const is_linux = @import("../sa_std.zig").is_linux;
const is_wasm = @import("../sa_std.zig").is_wasm;
const libc = @import("../sa_std.zig").libc;
const libcErrRc = @import("../sa_std.zig").libcErrRc;
const libcUsize = @import("../sa_std.zig").libcUsize;
const lockRegistry = @import("../sa_std.zig").lockRegistry;
const lxCheck = @import("../sa_std.zig").lxCheck;
const lxClose = @import("../sa_std.zig").lxClose;
const lxSocket = @import("../sa_std.zig").lxSocket;
const mutBytes = @import("../sa_std.zig").mutBytes;
const netGetAddressList = @import("../sa_std.zig").netGetAddressList;
const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;
const sa_std_net_unix_datagram_peer_cred = @import("../sa_std.zig").sa_std_net_unix_datagram_peer_cred;
extern "c" fn __error() *c_int;
extern "c" fn recvmsg(sockfd: std.posix.fd_t, msg: *MsghdrT, flags: c_int) isize;

pub fn makeSockAddrStorage() SockAddrStorageT {
    if (comptime is_wasm) return .{ .family = 0 };
    switch (builtin.os.tag) {
        .linux, .illumos, .windows, .serenity, .haiku, .wasi, .emscripten => return .{ .family = 0 },
        else => return .{ .len = @intCast(@sizeOf(SockAddrStorageT)), .family = 0 },
    }
}

pub const UnixSockAddr = struct { addr: SockAddrUnT, len: SockLenT };

const WasiMsghdr = extern struct { name: ?*anyopaque = null, namelen: u32 = 0, iov: ?*anyopaque = null, iovlen: usize = 0, control: ?*anyopaque = null, controllen: usize = 0, flags: u32 = 0 };

pub const MsghdrT = if (is_wasm) WasiMsghdr else std.posix.msghdr;

pub const MsghdrConstT = if (is_wasm) WasiMsghdr else std.posix.msghdr_const;

pub const msg_peek: u32 = if (builtin.os.tag == .linux) std.posix.MSG.PEEK else 0x2;

pub fn portableRecvmsg(fd: std.posix.fd_t, msg: *MsghdrT, flags: u32) !usize {
    if (builtin.os.tag == .linux) {
        const rc = std.os.linux.recvmsg(fd, @as(*std.os.linux.msghdr, @ptrCast(msg)), flags);
        return switch (std.os.linux.errno(rc)) {
            .SUCCESS => @as(usize, @intCast(rc)),
            else => |e| std.posix.unexpectedErrno(e),
        };
    } else {
        const rc = recvmsg(fd, msg, @as(c_int, @intCast(flags)));
        if (rc < 0) {
            const e = @as(std.posix.E, @fromBackingInt(@intCast(__error().*)));
            return std.posix.unexpectedErrno(e);
        }
        return @as(usize, @intCast(rc));
    }
}

pub const UnixAddrHandle = struct {
    allocator: std.mem.Allocator,
    kind: u32,
    bytes: []u8,

    pub fn deinit(self: *UnixAddrHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

const unix_sockaddr_path_offset: usize = if (is_wasm) 2 else @offsetOf(SockAddrUnT, "path");

pub fn unixAddrFromSockaddr(allocator: std.mem.Allocator, addr: SockAddrUnT, len_raw: SockLenT) !UnixAddrHandle {
    var len = @as(usize, @intCast(len_raw));
    if (len == 0) len = unix_sockaddr_path_offset;
    if (len <= unix_sockaddr_path_offset) {
        return .{ .allocator = allocator, .kind = SA_NET_UNIX_ADDR_UNNAMED, .bytes = &.{} };
    }
    if (addr.family != AFT.UNIX) return error.InvalidArgument;

    const available = @min(len - unix_sockaddr_path_offset, addr.path.len);
    if (available == 0) {
        return .{ .allocator = allocator, .kind = SA_NET_UNIX_ADDR_UNNAMED, .bytes = &.{} };
    }

    if (addr.path[0] == 0) {
        if (available <= 1) return .{ .allocator = allocator, .kind = SA_NET_UNIX_ADDR_UNNAMED, .bytes = &.{} };
        const name = try allocator.dupe(u8, addr.path[1..available]);
        return .{ .allocator = allocator, .kind = SA_NET_UNIX_ADDR_ABSTRACT, .bytes = name };
    }

    var path_len = available;
    if (path_len > 0 and addr.path[path_len - 1] == 0) path_len -= 1;
    const path = try allocator.dupe(u8, addr.path[0..path_len]);
    return .{ .allocator = allocator, .kind = SA_NET_UNIX_ADDR_PATHNAME, .bytes = path };
}

pub fn registerUnixAddrOutLocked(addr: SockAddrUnT, len: SockLenT, out_handle: *u64) i32 {
    var unix_addr = unixAddrFromSockaddr(std.heap.page_allocator, addr, len) catch |err| return finishErr(err);
    const handle = registerResourceLocked(.{ .unix_addr = unix_addr }) catch |err| {
        unix_addr.deinit();
        return finishErr(err);
    };
    out_handle.* = handle;
    return finish(SA_STD_OK);
}

pub fn unixSockAddrFromHandle(handle: u64) !UnixSockAddr {
    // wasm32-wasi has no unix sockets; stub to keep archive compilable.
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
    return switch (resource.*) {
        .unix_addr => |unix_addr| blk: {
            var addr: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
            @memset(&addr.path, 0);
            switch (unix_addr.kind) {
                SA_NET_UNIX_ADDR_UNNAMED => break :blk .{ .addr = addr, .len = @as(SockLenT, @intCast(unix_sockaddr_path_offset)) },
                SA_NET_UNIX_ADDR_PATHNAME => {
                    if (unix_addr.bytes.len == 0 or unix_addr.bytes.len >= addr.path.len) return error.InvalidArgument;
                    if (std.mem.indexOfScalar(u8, unix_addr.bytes, 0) != null) return error.InvalidArgument;
                    @memcpy(addr.path[0..unix_addr.bytes.len], unix_addr.bytes);
                    break :blk .{ .addr = addr, .len = @as(SockLenT, @intCast(unix_sockaddr_path_offset + unix_addr.bytes.len + 1)) };
                },
                SA_NET_UNIX_ADDR_ABSTRACT => {
                    if (unix_addr.bytes.len + 1 > addr.path.len) return error.InvalidArgument;
                    addr.path[0] = 0;
                    if (unix_addr.bytes.len != 0) @memcpy(addr.path[1 .. 1 + unix_addr.bytes.len], unix_addr.bytes);
                    break :blk .{ .addr = addr, .len = @as(SockLenT, @intCast(unix_sockaddr_path_offset + 1 + unix_addr.bytes.len)) };
                },
                else => return error.InvalidArgument,
            }
        },
        else => error.InvalidHandle,
    };
}

const TimevalSec = @TypeOf(@as(Timeval, .{ .sec = 0, .usec = 0 }).sec);

const TimevalUsec = @TypeOf(@as(Timeval, .{ .sec = 0, .usec = 0 }).usec);

pub fn timevalFromNs(ns: u64) !Timeval {
    const sec = ns / std.time.ns_per_s;
    const usec = (ns % std.time.ns_per_s) / std.time.ns_per_us;
    return .{
        .sec = std.math.cast(TimevalSec, sec) orelse return error.InvalidArgument,
        .usec = std.math.cast(TimevalUsec, usec) orelse return error.InvalidArgument,
    };
}

pub fn nsFromTimeval(tv: Timeval) !u64 {
    const sec = std.math.cast(u64, tv.sec) orelse return error.InvalidArgument;
    const usec = std.math.cast(u64, tv.usec) orelse return error.InvalidArgument;
    const sec_ns = std.math.mul(u64, sec, std.time.ns_per_s) catch return error.InvalidArgument;
    const usec_ns = std.math.mul(u64, usec, std.time.ns_per_us) catch return error.InvalidArgument;
    return std.math.add(u64, sec_ns, usec_ns) catch return error.InvalidArgument;
}

pub fn setSocketOptTimeval(fd: std.posix.fd_t, level: i32, optname: u32, ns: u64) !void {
    const tv = try timevalFromNs(ns);
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&tv));
}

pub fn getSocketOptBool(fd: std.posix.fd_t, level: i32, optname: u32) !bool {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value: i32 = 0;
    var len: SockLenT = @sizeOf(i32);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(i32)) return error.UnexpectedSize;
            return value != 0;
        },
        else => return error.InvalidArgument,
    }
}

pub fn lxSetSocketOptBool(fd: std.posix.fd_t, level: i32, optname: u32, enabled: bool) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value: i32 = if (enabled) 1 else 0;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.setsockopt(fd, level, optname, @as([*]const u8, @ptrCast(&value)), @as(SockLenT, @sizeOf(i32))));
        return;
    }
    try libcErrRc(libc.setsockopt(fd, level, @as(c_int, @intCast(optname)), @as(*const anyopaque, @ptrCast(&value)), @as(libc_socklen_t, @sizeOf(i32))));
}

pub fn rebuildTcpListenerV6Only(listener: u64, enabled: bool) !void {
    if (comptime is_wasm) return error.Unsupported;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(listener) orelse return error.InvalidHandle;
    const server = switch (resource.*) {
        .tcp_listener => |value| value,
        else => return error.InvalidHandle,
    };
    const orig_only_v6 = getSocketOptBool(server.fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY) catch false;
    const flags = lxFcntl(server.fd, std.posix.F.GETFL, 0) catch 0;
    const nb_mask = @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK");
    const new_fd = try lxSocket(AFT.INET6, SOCKT.STREAM | SOCKT.CLOEXEC, IPPROTOT.TCP);
    lxSetSocketOptBool(new_fd, SOLT.SOCKET, SOT.REUSEADDR, true) catch |err| {
        lxClose(new_fd);
        return err;
    };
    lxSetSocketOptBool(new_fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY, enabled) catch |err| {
        lxClose(new_fd);
        return err;
    };
    if (flags & nb_mask != 0) {
        _ = lxFcntl(new_fd, std.posix.F.SETFL, nb_mask) catch {};
    }
    lxClose(server.fd);
    lxBind(new_fd, server.addr.sockAddr(), server.addr.getOsSockLen()) catch |err| {
        lxClose(new_fd);
        const fallback = lxSocket(AFT.INET6, SOCKT.STREAM | SOCKT.CLOEXEC, IPPROTOT.TCP) catch return err;
        lxSetSocketOptBool(fallback, SOLT.SOCKET, SOT.REUSEADDR, true) catch {};
        lxSetSocketOptBool(fallback, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY, orig_only_v6) catch {};
        if (flags & nb_mask != 0) {
            _ = lxFcntl(fallback, std.posix.F.SETFL, nb_mask) catch {};
        }
        lxBind(fallback, server.addr.sockAddr(), server.addr.getOsSockLen()) catch {
            lxClose(fallback);
            return err;
        };
        resource.* = .{ .tcp_listener = .{ .fd = fallback, .addr = server.addr } };
        lxListen(fallback, 128) catch {};
        return err;
    };
    resource.* = .{ .tcp_listener = .{ .fd = new_fd, .addr = server.addr } };
    try lxListen(new_fd, 128);
}

pub fn rebuildUdpSocketV6Only(socket: u64, enabled: bool) !void {
    if (comptime is_wasm) return error.Unsupported;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(socket) orelse return error.InvalidHandle;
    const old_fd = switch (resource.*) {
        .udp_socket => |value| value,
        else => return error.InvalidHandle,
    };
    var addr = NetAddress{};
    var addr_len: SockLenT = @sizeOf(SockAddrStorageT);
    try lxGetsockname(old_fd, addr.sockAddrMut(), &addr_len);
    addr.len = addr_len;
    const orig_only_v6 = getSocketOptBool(old_fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY) catch false;
    const broadcast = getSocketOptBool(old_fd, SOLT.SOCKET, SOT.BROADCAST) catch false;
    const rcv_timeout = getSocketOptTimeval(old_fd, SOLT.SOCKET, SOT.RCVTIMEO) catch 0;
    const snd_timeout = getSocketOptTimeval(old_fd, SOLT.SOCKET, SOT.SNDTIMEO) catch 0;
    const flags = lxFcntl(old_fd, std.posix.F.GETFL, 0) catch 0;
    const nb_mask = @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK");
    const prep = struct {
        fn apply(fd: std.posix.fd_t, only_v6: bool, bcast: bool, rcv_ns: u64, snd_ns: u64, nb: usize) !void {
            try lxSetSocketOptBool(fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY, only_v6);
            if (bcast) try lxSetSocketOptBool(fd, SOLT.SOCKET, SOT.BROADCAST, true);
            if (rcv_ns != 0) try setSocketOptTimeval(fd, SOLT.SOCKET, SOT.RCVTIMEO, rcv_ns);
            if (snd_ns != 0) try setSocketOptTimeval(fd, SOLT.SOCKET, SOT.SNDTIMEO, snd_ns);
            if (nb != 0) {
                _ = try lxFcntl(fd, std.posix.F.SETFL, nb);
            }
        }
    };
    const new_fd = try lxSocket(AFT.INET6, SOCKT.DGRAM | SOCKT.CLOEXEC, IPPROTOT.UDP);
    prep.apply(new_fd, enabled, broadcast, rcv_timeout, snd_timeout, flags & nb_mask) catch |err| {
        lxClose(new_fd);
        return err;
    };
    lxClose(old_fd);
    lxBind(new_fd, addr.sockAddr(), addr.getOsSockLen()) catch |err| {
        lxClose(new_fd);
        const fallback = lxSocket(AFT.INET6, SOCKT.DGRAM | SOCKT.CLOEXEC, IPPROTOT.UDP) catch return err;
        prep.apply(fallback, orig_only_v6, broadcast, rcv_timeout, snd_timeout, flags & nb_mask) catch {};
        lxBind(fallback, addr.sockAddr(), addr.getOsSockLen()) catch {
            lxClose(fallback);
            return err;
        };
        resource.* = .{ .udp_socket = fallback };
        return err;
    };
    resource.* = .{ .udp_socket = new_fd };
}

pub fn getUnixPeerCred(fd: std.posix.fd_t) !LinuxUCred {
    if (comptime is_wasm) return error.Unsupported;
    var value: LinuxUCred = .{ .pid = 0, .uid = 0, .gid = 0 };
    var len: SockLenT = @sizeOf(LinuxUCred);
    const rc = std.os.linux.getsockopt(fd, SOLT.SOCKET, std.os.linux.SO.PEERCRED, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(LinuxUCred)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub const PeerCredSlot = struct {
    handle: u64 = 0,
    fd: std.posix.fd_t = -1,
    cred: LinuxUCred = .{ .pid = 0, .uid = 0, .gid = 0 },
};

var peer_cred_slots: [128]PeerCredSlot = blk: {
    var slots: [128]PeerCredSlot = undefined;
    for (&slots) |*slot| slot.* = .{};
    break :blk slots;
};

var peer_cred_cursor: usize = 0;

fn storeHarvestedPeerCredLocked(handle: u64, fd: std.posix.fd_t, cred: LinuxUCred) void {
    for (&peer_cred_slots) |*slot| {
        if (slot.handle == handle and slot.fd == fd) {
            slot.cred = cred;
            return;
        }
    }
    peer_cred_slots[peer_cred_cursor] = .{ .handle = handle, .fd = fd, .cred = cred };
    peer_cred_cursor = (peer_cred_cursor + 1) % peer_cred_slots.len;
}

pub fn harvestedPeerCredLocked(handle: u64, fd: std.posix.fd_t) ?LinuxUCred {
    const resource = getResourceLocked(handle) orelse return null;
    const live_fd = switch (resource.*) {
        .udp_socket => |value| value,
        else => return null,
    };
    if (live_fd != fd) return null;
    for (&peer_cred_slots) |*slot| {
        if (slot.handle == handle and slot.fd == fd) return slot.cred;
    }
    return null;
}

fn scmCredentials(ctrl: []const u8) ?LinuxUCred {
    var off: usize = 0;
    while (off + 16 <= ctrl.len) {
        const cmsg_len = @as(usize, @intCast(std.mem.readInt(u64, ctrl[off..][0..8], .little)));
        if (cmsg_len < 16 or off + cmsg_len > ctrl.len) break;
        const level = std.mem.readInt(i32, ctrl[off + 8 ..][0..4], .little);
        const ctype = std.mem.readInt(i32, ctrl[off + 12 ..][0..4], .little);
        const data = ctrl[off + 16 .. off + cmsg_len];
        if (level == cmsg_level_socket and ctype == 2 and data.len >= @sizeOf(LinuxUCred)) {
            return .{
                .pid = std.mem.readInt(i32, data[0..4], .little),
                .uid = std.mem.readInt(u32, data[4..8], .little),
                .gid = std.mem.readInt(u32, data[8..12], .little),
            };
        }
        const step = cmsgAlign(cmsg_len);
        if (step == 0) break;
        off += step;
    }
    return null;
}

pub fn getSocketOptTimeval(fd: std.posix.fd_t, level: i32, optname: u32) !u64 {
    if (comptime is_wasm) return error.Unsupported;
    var tv: Timeval = .{ .sec = 0, .usec = 0 };
    var len: SockLenT = @sizeOf(Timeval);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&tv)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(Timeval)) return error.UnexpectedSize;
            return try nsFromTimeval(tv);
        },
        else => return error.InvalidArgument,
    }
}

pub fn socketAddressFamily(fd: std.posix.fd_t) !u16 {
    var storage: SockAddrStorageT = makeSockAddrStorage();
    var addr_len: SockLenT = @sizeOf(SockAddrStorageT);
    try lxGetsockname(fd, @ptrCast(&storage), &addr_len);
    return storage.family;
}

pub fn socketIsUnix(fd: std.posix.fd_t) !bool {
    return (try socketAddressFamily(fd)) == AFT.UNIX;
}

pub fn socketIsInet(fd: std.posix.fd_t) !bool {
    const family = try socketAddressFamily(fd);
    return family == AFT.INET or family == AFT.INET6;
}

pub fn socketAcceptConn(fd: std.posix.fd_t) !bool {
    return try getSocketOptBool(fd, SOLT.SOCKET, std.os.linux.SO.ACCEPTCONN);
}

pub fn ensureSocketHandle(handle: u64) !struct { fd: std.posix.fd_t, kind: enum { tcp_stream, tcp_listener, udp_socket } } {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
    return switch (resource.*) {
        .tcp_stream => |stream| .{ .fd = stream, .kind = .tcp_stream },
        .tcp_listener => |server| .{ .fd = server.fd, .kind = .tcp_listener },
        .udp_socket => |fd| .{ .fd = fd, .kind = .udp_socket },
        else => error.InvalidHandle,
    };
}

const libc_socklen_t = std.c.socklen_t;

pub fn lxBind(fd: std.posix.fd_t, addr: *const SockAddrT, len: SockLenT) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.bind(fd, addr, len));
        return;
    }
    try libcErrRc(libc.bind(fd, addr, @intCast(len)));
}

pub fn lxListen(fd: std.posix.fd_t, backlog: u32) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.listen(fd, backlog));
        return;
    }
    try libcErrRc(libc.listen(fd, @intCast(backlog)));
}

pub fn lxConnect(fd: std.posix.fd_t, addr: *const SockAddrT, len: SockLenT) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.connect(fd, @ptrCast(addr), len));
        return;
    }
    try libcErrRc(libc.connect(fd, addr, @intCast(len)));
}

pub fn lxSendmsg(fd: std.posix.fd_t, msg: *const MsghdrConstT, flags: u32) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) return try lxCheck(std.os.linux.sendmsg(fd, msg, flags));
    return try libcUsize(libc.sendmsg(fd, msg, @intCast(flags)));
}

pub fn lxFcntl(fd: std.posix.fd_t, cmd: i32, arg: usize) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) return try lxCheck(std.os.linux.fcntl(fd, cmd, arg));
    const rc = libc.fcntl(fd, @intCast(cmd), @as(c_int, @intCast(arg)));
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
    return @intCast(rc);
}

pub fn lxGetsockname(fd: std.posix.fd_t, addr: *SockAddrT, len: *SockLenT) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.getsockname(fd, addr, len));
        return;
    }
    try libcErrRc(libc.getsockname(fd, addr, @ptrCast(len)));
}

pub fn lxGetsockoptError(fd: std.posix.fd_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    var value: i32 = 0;
    var len: SockLenT = @sizeOf(i32);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.getsockopt(fd, SOLT.SOCKET, SOT.ERROR, @ptrCast(&value), &len));
    } else {
        try libcErrRc(libc.getsockopt(fd, @intCast(SOLT.SOCKET), @intCast(SOT.ERROR), @ptrCast(&value), @ptrCast(&len)));
    }
    if (value != 0) {
        const e: std.posix.E = @fromBackingInt(@intCast(value));
        return errnoToAny(e);
    }
}

pub const cmsg_level_socket: i32 = 1; // SOL_SOCKET

pub fn cmsgAlign(len: usize) usize {
    const mask: usize = @sizeOf(usize) - 1;
    return (len + mask) & ~mask;
}

pub fn tcpConnectToHostFd(host: []const u8, port: u16) !std.posix.fd_t {
    var list = try netGetAddressList(std.heap.page_allocator, host, port);
    defer list.deinit();
    var last: anyerror = error.HostLacksNetworkAddresses;
    for (list.addrs) |addr| {
        const fd = lxSocket(addr.storage.family, SOCKT.STREAM | SOCKT.CLOEXEC, IPPROTOT.TCP) catch |err| {
            last = err;
            continue;
        };
        errdefer lxClose(fd);
        lxConnect(fd, addr.sockAddr(), addr.getOsSockLen()) catch |err| {
            last = err;
            continue;
        };
        return fd;
    }
    return last;
}

pub fn connectUnixSocketFd(path: []const u8) !std.posix.fd_t {
    const addr = try NetAddress.initUnix(path);
    const fd = try lxSocket(AFT.UNIX, SOCKT.STREAM | SOCKT.CLOEXEC, 0);
    errdefer lxClose(fd);
    try lxConnect(fd, addr.sockAddr(), addr.getOsSockLen());
    return fd;
}

pub fn tcpConnectAddressTimeout(address: NetAddress, timeout_ms: i32) !std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    const fd = try lxSocket(address.storage.family, SOCKT.STREAM | SOCKT.NONBLOCK | SOCKT.CLOEXEC, IPPROTOT.TCP);
    errdefer lxClose(fd);
    lxConnect(fd, address.sockAddr(), address.getOsSockLen()) catch |err| switch (err) {
        error.WouldBlock, error.ConnectionPending => {
            var poll_fds = [_]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.OUT, .revents = 0 }};
            const ready = try std.posix.poll(&poll_fds, timeout_ms);
            if (ready == 0) return error.ConnectionTimedOut;
            try lxGetsockoptError(fd);
        },
        else => return err,
    };
    const flags = try lxFcntl(fd, std.posix.F.GETFL, 0);
    const blocking_flags = flags & ~(@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"));
    _ = try lxFcntl(fd, std.posix.F.SETFL, blocking_flags);
    return fd;
}

pub fn unixDatagramRecvFrom(socket: u64, out: ?[*]u8, cap: u64, flags: u32, out_read: ?*u64, out_addr: ?*u64) i32 {
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const addr_ptr = out_addr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    addr_ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    var addr: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
    @memset(&addr.path, 0);
    // recvmsg (not recvfrom) so SCM_CREDENTIALS ancillary data can
    // be harvested for sa_std_net_unix_datagram_peer_cred; see the
    // note at getUnixPeerCred. Peek receives do not harvest.
    var control: [128]u8 align(8) = undefined;
    var ziovec = std.posix.iovec{ .base = buffer.ptr, .len = buffer.len };
    var msg: MsghdrT = std.mem.zeroes(MsghdrT);
    msg.name = @as(*SockAddrT, @ptrCast(&addr));
    msg.namelen = @as(SockLenT, @intCast(@sizeOf(SockAddrUnT)));
    msg.iov = @ptrCast(&ziovec);
    msg.iovlen = 1;
    msg.control = @ptrCast(&control);
    msg.controllen = control.len;
    const read = portableRecvmsg(handle.fd, &msg, flags) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(read));
    const addr_len: SockLenT = msg.namelen;
    if ((flags & msg_peek) == 0) {
        const ctrl = control[0..@as(usize, @intCast(msg.controllen))];
        if (scmCredentials(ctrl)) |cred| {
            lockRegistry();
            storeHarvestedPeerCredLocked(socket, handle.fd, cred);
            sa_std.registry_mutex.unlock();
        }
    }

    var unix_addr = unixAddrFromSockaddr(std.heap.page_allocator, addr, addr_len) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const addr_handle = registerResourceLocked(.{ .unix_addr = unix_addr }) catch |err| {
        unix_addr.deinit();
        return finishErr(err);
    };
    addr_ptr.* = addr_handle;
    return finish(SA_STD_OK);
}
