const std = @import("std");
const sa_std = @import("../sa_std.zig");
pub const AFT = @import("../sa_std.zig").AFT;
pub const EnvVarJson = @import("../sa_std.zig").EnvVarJson;
const FIRST_DYNAMIC_HANDLE = @import("spawn.zig").FIRST_DYNAMIC_HANDLE;
pub const LingerOption = @import("../sa_std.zig").LingerOption;
pub const NetAddrHandle = @import("../sa_std.zig").NetAddrHandle;
pub const NetAddress = @import("../sa_std.zig").NetAddress;
pub const Resource = @import("../sa_std.zig").Resource;
pub const SA_STD_ERR_ACCESS = @import("consts.zig").SA_STD_ERR_ACCESS;
pub const SA_STD_ERR_INVALID_ARGUMENT = @import("consts.zig").SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_STD_ERR_INVALID_HANDLE = @import("consts.zig").SA_STD_ERR_INVALID_HANDLE;
pub const SA_STD_ERR_IO = @import("consts.zig").SA_STD_ERR_IO;
pub const SA_STD_ERR_NOT_FOUND = @import("consts.zig").SA_STD_ERR_NOT_FOUND;
pub const SA_STD_ERR_NO_MEMORY = @import("consts.zig").SA_STD_ERR_NO_MEMORY;
pub const SA_STD_OK = @import("consts.zig").SA_STD_OK;
pub const SOCKT = @import("../sa_std.zig").SOCKT;
pub const SOLT = @import("../sa_std.zig").SOLT;
pub const SOT = @import("../sa_std.zig").SOT;
pub const SockAddrT = @import("../sa_std.zig").SockAddrT;
pub const SockAddrUnT = @import("../sa_std.zig").SockAddrUnT;
pub const SockLenT = @import("../sa_std.zig").SockLenT;
const appendEnvVarJson = @import("../sa_std.zig").appendEnvVarJson;
const builtin = @import("../sa_std.zig").builtin;
pub const constBytes = @import("../sa_std.zig").constBytes;
const dynamicIndex = @import("spawn.zig").dynamicIndex;
pub const lingerSeconds = @import("../sa_std.zig").lingerSeconds;
pub const lockRegistry = @import("../sa_std.zig").lockRegistry;
const lxGetpeername = @import("../sa_std.zig").lxGetpeername;
const lxGetsockname = @import("../sa_std.zig").lxGetsockname;
pub const mapError = @import("../sa_std.zig").mapError;
pub const netGetAddressList = @import("../sa_std.zig").netGetAddressList;
const parseIp6FreebsdParts = @import("ip_parse.zig").parseIp6FreebsdParts;
extern "c" var environ: [*:null]?[*:0]u8;
extern fn if_nametoindex(ifname: [*:0]const u8) c_uint;
const sio = @import("../sa_std.zig").sio;
const spawn = @import("../sa_std.zig").spawn;

pub const tcp_nodelay: u32 = 1;

pub fn registerNetAddrList(host: []const u8, port: u16) !u64 {
    var list = try netGetAddressList(std.heap.page_allocator, host, port);
    defer list.deinit();
    if (list.addrs.len == 0) return error.HostLacksNetworkAddresses;
    const addresses = try std.heap.page_allocator.dupe(NetAddress, list.addrs);
    errdefer std.heap.page_allocator.free(addresses);
    return registerResource(.{ .net_addr_list = .{
        .allocator = std.heap.page_allocator,
        .addresses = addresses,
    } });
}

pub fn registerNetAddrOutLocked(address: NetAddress, out_handle: *u64) i32 {
    var net_addr = NetAddrHandle.init(std.heap.page_allocator, address) catch |err| return finishErr(err);
    const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
        net_addr.deinit();
        return finishErr(err);
    };
    out_handle.* = handle;
    return finish(SA_STD_OK);
}

pub fn finish(status: i32) i32 {
    sa_std.last_error = status;
    return status;
}

pub fn finishErr(err: anyerror) i32 {
    return finish(mapError(err));
}

pub fn setSocketOptBool(fd: std.posix.fd_t, level: i32, optname: u32, enabled: bool) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value: i32 = if (enabled) 1 else 0;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&value));
}

pub fn setSocketOptInt(fd: std.posix.fd_t, level: i32, optname: u32, value: i32) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var mutable = value;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&mutable));
}

pub fn setSocketOptU32(fd: std.posix.fd_t, level: i32, optname: u32, value: u32) !void {
    var mutable = value;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&mutable));
}

pub fn setSocketOptByte(fd: std.posix.fd_t, level: i32, optname: u32, value: u8) !void {
    var mutable = value;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&mutable));
}

pub fn setSocketOptBytes(fd: std.posix.fd_t, level: i32, optname: u32, bytes: []const u8) !void {
    try std.posix.setsockopt(fd, level, optname, bytes);
}

pub fn setSocketOptLinger(fd: std.posix.fd_t, enabled: bool, timeout_ns: u64) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    const seconds = if (enabled) try lingerSeconds(timeout_ns) else 0;
    var value = LingerOption{ .onoff = if (enabled) 1 else 0, .linger = seconds };
    try std.posix.setsockopt(fd, SOLT.SOCKET, SOT.LINGER, std.mem.asBytes(&value));
}

pub fn getSocketOptLinger(fd: std.posix.fd_t) !LingerOption {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value = LingerOption{ .onoff = 0, .linger = 0 };
    var len: SockLenT = @sizeOf(LingerOption);
    const rc = std.os.linux.getsockopt(fd, SOLT.SOCKET, SOT.LINGER, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(LingerOption)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptInt(fd: std.posix.fd_t, level: i32, optname: u32) !i32 {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value: i32 = 0;
    var len: SockLenT = @sizeOf(i32);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(i32)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptByte(fd: std.posix.fd_t, level: i32, optname: u32) !u8 {
    var value: u8 = 0;
    var len: SockLenT = @sizeOf(u8);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(u8)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptU32(fd: std.posix.fd_t, level: i32, optname: u32) !u32 {
    var value: u32 = 0;
    var len: SockLenT = @sizeOf(u32);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(u32)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptBytes(fd: std.posix.fd_t, level: i32, optname: u32, out: []u8) !void {
    var len: SockLenT = @intCast(out.len);
    const rc = std.os.linux.getsockopt(fd, level, optname, out.ptr, &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != out.len) return error.UnexpectedSize;
        },
        else => return error.InvalidArgument,
    }
}

pub fn socketIsStream(fd: std.posix.fd_t) !bool {
    const socket_type = try getSocketOptInt(fd, SOLT.SOCKET, std.os.linux.SO.TYPE);
    return socket_type == @as(i32, @intCast(SOCKT.STREAM));
}

pub fn socketIsDatagram(fd: std.posix.fd_t) !bool {
    const socket_type = try getSocketOptInt(fd, SOLT.SOCKET, std.os.linux.SO.TYPE);
    return socket_type == @as(i32, @intCast(SOCKT.DGRAM));
}

pub fn getUnixSockAddr(fd: std.posix.fd_t, peer: bool) !struct { addr: SockAddrUnT, len: SockLenT } {
    var addr: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
    @memset(&addr.path, 0);
    var len: SockLenT = @sizeOf(SockAddrUnT);
    if (peer) {
        try lxGetpeername(fd, @as(*SockAddrT, @ptrCast(&addr)), &len);
    } else {
        try lxGetsockname(fd, @as(*SockAddrT, @ptrCast(&addr)), &len);
    }
    return .{ .addr = addr, .len = len };
}

pub fn getResourceLocked(handle: u64) ?*Resource {
    const idx = dynamicIndex(handle) orelse return null;
    if (idx >= spawn.registry_slots.items.len) return null;
    if (spawn.registry_slots.items[idx]) |*resource| return resource;
    return null;
}

pub fn registerResourceLocked(resource: Resource) !u64 {
    for (spawn.registry_slots.items, 0..) |slot, idx| {
        if (slot == null) {
            spawn.registry_slots.items[idx] = resource;
            return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(idx));
        }
    }
    const idx = spawn.registry_slots.items.len;
    try spawn.registry_slots.append(resource);
    return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(idx));
}

pub fn registerResource(resource: Resource) !u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    return try registerResourceLocked(resource);
}

pub fn tcpStreamFd(handle: u64) ?std.posix.fd_t {
    lockRegistry();
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .tcp_stream => |s| s,
        else => null,
    };
}

pub fn envKeyBytes(key_ptr: ?[*]const u8, key_len: u64) ![]const u8 {
    const key = try constBytes(key_ptr, key_len);
    if (key.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, 0) != null) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, '=') != null) return error.InvalidArgument;
    return key;
}

pub fn envVarsJsonAlloc(allocator: std.mem.Allocator) ![]u8 {
    var pairs = std.array_list.Managed(EnvVarJson).init(allocator);
    defer pairs.deinit();

    {
        var i: usize = 0;
        while (environ[i] != null) : (i += 1) {
            try appendEnvVarJson(&pairs, std.mem.span(environ[i].?));
        }
    }

    return std.json.Stringify.valueAlloc(allocator, pairs.items, .{});
}

pub fn envSplitPathsJsonAlloc(allocator: std.mem.Allocator, path_list: []const u8) ![]u8 {
    var parts = std.array_list.Managed([]const u8).init(allocator);
    defer parts.deinit();

    var it = std.mem.splitScalar(u8, path_list, ':');
    while (it.next()) |part| {
        try parts.append(part);
    }

    return std.json.Stringify.valueAlloc(allocator, parts.items, .{});
}

pub fn envJoinPathsJsonAlloc(allocator: std.mem.Allocator, paths_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice([]const []const u8, allocator, paths_json, .{});
    defer parsed.deinit();

    for (parsed.value) |path| {
        if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    }

    return std.mem.join(allocator, ":", parsed.value);
}

pub fn sqlite3_prepare(sqlite: ?[*]u8, sql: ?[*]const u8, len: i32, stmt_out: ?[*]u8) callconv(.c) i32 {
    _ = sqlite;
    _ = sql;
    _ = len;
    _ = stmt_out;
    sa_std.last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn sqlite3_step(stmt: ?[*]u8) callconv(.c) i32 {
    _ = stmt;
    sa_std.last_error = SA_STD_OK;
    return 1;
}

pub fn sqlite3_finalize(stmt: ?[*]u8) callconv(.c) i32 {
    _ = stmt;
    sa_std.last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn finishErrnoAny(e: anytype) i32 {
    const n = @tagName(e);
    if (std.mem.eql(u8, n, "SUCCESS")) return finish(SA_STD_OK);
    if (std.mem.eql(u8, n, "INTR")) return finish(SA_STD_ERR_IO);
    if (std.mem.eql(u8, n, "BADF")) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (std.mem.eql(u8, n, "ACCES") or std.mem.eql(u8, n, "PERM") or std.mem.eql(u8, n, "ROFS")) return finish(SA_STD_ERR_ACCESS);
    if (std.mem.eql(u8, n, "NOENT") or std.mem.eql(u8, n, "NOTDIR")) return finish(SA_STD_ERR_NOT_FOUND);
    if (std.mem.eql(u8, n, "FAULT") or std.mem.eql(u8, n, "INVAL") or std.mem.eql(u8, n, "NAMETOOLONG") or std.mem.eql(u8, n, "LOOP")) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (std.mem.eql(u8, n, "NOMEM")) return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_ERR_IO);
}

pub fn finishChownErrno(rc: usize) i32 {
    return finishErrnoAny(std.os.linux.errno(rc));
}

pub fn parsePortAscii(text: []const u8) ?u16 {
    if (text.len == 0) return null;
    var value: u32 = 0;
    for (text) |byte| {
        if (byte < '0' or byte > '9') return null;
        value = value * 10 + @as(u32, byte - '0');
        if (value > std.math.maxInt(u16)) return null;
    }
    return @as(u16, @intCast(value));
}

pub fn parseIpv6Ascii(text: []const u8) ?struct { octets: [16]u8, scope_id: u32 } {
    // FreeBSD: Ip6Address.resolve reaches unimplemented if_nametoindex.
    if (comptime builtin.os.tag == .freebsd) {
        const parsed = parseIp6FreebsdParts(text) orelse return null;
        return .{ .octets = parsed.addr, .scope_id = parsed.scope_id };
    }
    const parsed = std.Io.net.IpAddress.resolve(sio.io(), text, 0) catch return null;
    return switch (parsed) {
        .ip6 => |v6| .{ .octets = v6.bytes, .scope_id = v6.interface.index },
        .ip4 => null,
    };
}

pub fn parseSocketAddrV6Ascii(text: []const u8) ?struct { octets: [16]u8, port: u16, scope_id: u32 } {
    if (text.len < 4 or text[0] != '[') return null;
    const close = std.mem.lastIndexOfScalar(u8, text, ']') orelse return null;
    if (close == 0 or close + 1 >= text.len or text[close + 1] != ':') return null;
    const ip_text = text[1..close];
    if (ip_text.len == 0) return null;
    const port = parsePortAscii(text[close + 2 ..]) orelse return null;
    const parsed = parseIpv6Ascii(ip_text) orelse return null;
    return .{
        .octets = parsed.octets,
        .port = port,
        .scope_id = parsed.scope_id,
    };
}

pub fn tcpConnectTimeoutMs(timeout_ns: u64) !i32 {
    if (timeout_ns == 0) return error.InvalidArgument;
    const whole_ms = timeout_ns / std.time.ns_per_ms;
    const rounded_ms = whole_ms + @intFromBool(timeout_ns % std.time.ns_per_ms != 0);
    return std.math.cast(i32, rounded_ms) orelse error.InvalidArgument;
}
