const std = @import("std");
const sa_std = @import("../sa_std.zig");
pub const AFT = @import("../sa_std.zig").AFT;
pub const RegexC = @import("../sa_std.zig").RegexC;
const SA_REGEX_REG_NOERROR = @import("../sa_std.zig").SA_REGEX_REG_NOERROR;
pub const SA_STD_ERR_UNSUPPORTED = @import("consts.zig").SA_STD_ERR_UNSUPPORTED;
pub const SockAddrIn6T = @import("../sa_std.zig").SockAddrIn6T;
pub const SockAddrInT = @import("../sa_std.zig").SockAddrInT;
pub const SockAddrStorageT = @import("../sa_std.zig").SockAddrStorageT;
pub const SockAddrT = @import("../sa_std.zig").SockAddrT;
pub const SockAddrUnT = @import("../sa_std.zig").SockAddrUnT;
pub const SockLenT = @import("../sa_std.zig").SockLenT;
pub const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
pub const is_linux = @import("../sa_std.zig").is_linux;
const makeSockAddrStorage = @import("../sa_std.zig").makeSockAddrStorage;
pub const netGetAddressList = @import("../sa_std.zig").netGetAddressList;
const regexErrorToZig = @import("regex_core.zig").regexErrorToZig;
extern fn regcomp(preg: ?*RegexC, pattern: [*c]const u8, cflags: c_int) c_int;
extern fn regfree(preg: ?*RegexC) void;

pub const SO_MARK: u32 = if (is_linux) std.os.linux.SO.MARK else 0;

pub const RegexHandle = struct {
    allocator: std.mem.Allocator,
    pattern_z: []u8,
    compiled: RegexC,
    compiled_valid: bool = false,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8, cflags: c_int) !*RegexHandle {
        if (std.mem.indexOfScalar(u8, pattern, 0) != null) return error.InvalidArgument;
        const owned_pattern = try allocator.alloc(u8, pattern.len + 1);
        errdefer allocator.free(owned_pattern);
        @memcpy(owned_pattern[0..pattern.len], pattern);
        owned_pattern[pattern.len] = 0;
        const handle = try allocator.create(RegexHandle);
        errdefer allocator.destroy(handle);
        handle.* = .{
            .allocator = allocator,
            .pattern_z = owned_pattern,
            .compiled = undefined,
            .compiled_valid = false,
        };
        const pattern_c: [*:0]const u8 = @ptrCast(owned_pattern.ptr);
        const rc = regcomp(&handle.compiled, pattern_c, cflags);
        if (rc != SA_REGEX_REG_NOERROR) {
            return regexErrorToZig(rc);
        }
        handle.compiled_valid = true;
        return handle;
    }

    pub fn deinit(self: *RegexHandle) void {
        if (self.compiled_valid) regfree(&self.compiled);
        if (self.pattern_z.len != 0) self.allocator.free(self.pattern_z);
        self.pattern_z = &.{};
        self.compiled_valid = false;
    }

    pub fn destroy(self: *RegexHandle) void {
        self.deinit();
        self.allocator.destroy(self);
    }
};

pub const NetAddress = struct {
    storage: SockAddrStorageT = makeSockAddrStorage(),
    len: SockLenT = @sizeOf(SockAddrStorageT),

    pub fn sockAddr(self: *const NetAddress) *const SockAddrT {
        return @ptrCast(&self.storage);
    }

    pub fn sockAddrMut(self: *NetAddress) *SockAddrT {
        return @ptrCast(&self.storage);
    }

    pub fn getOsSockLen(self: NetAddress) SockLenT {
        return self.len;
    }

    pub fn getPort(self: NetAddress) u16 {
        return switch (self.storage.family) {
            AFT.INET => blk: {
                const sin: *const SockAddrInT = @ptrCast(@alignCast(&self.storage));
                break :blk std.mem.bigToNative(u16, sin.port);
            },
            AFT.INET6 => blk: {
                const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&self.storage));
                break :blk std.mem.bigToNative(u16, sin6.port);
            },
            else => 0,
        };
    }

    pub fn initIp4(parts: [4]u8, port: u16) NetAddress {
        const sin = SockAddrInT{
            .port = std.mem.nativeToBig(u16, port),
            .addr = @bitCast(parts),
        };
        var a = NetAddress{ .len = @sizeOf(SockAddrInT) };
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrInT)], std.mem.asBytes(&sin));
        return a;
    }

    pub fn initIp6(bytes: [16]u8, port: u16, flowinfo: u32, scope_id: u32) NetAddress {
        const sin6 = SockAddrIn6T{
            .port = std.mem.nativeToBig(u16, port),
            .flowinfo = flowinfo,
            .addr = bytes,
            .scope_id = scope_id,
        };
        var a = NetAddress{ .len = @sizeOf(SockAddrIn6T) };
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrIn6T)], std.mem.asBytes(&sin6));
        return a;
    }

    pub fn initUnix(path: []const u8) !NetAddress {
        const off = @offsetOf(SockAddrUnT, "path");
        if (off + path.len + 1 > @sizeOf(SockAddrUnT)) return error.NameTooLong;
        var sun: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
        @memcpy(sun.path[0..path.len], path);
        sun.path[path.len] = 0;
        var a = NetAddress{ .len = @as(SockLenT, @intCast(off + path.len + 1)) };
        @memset(std.mem.asBytes(&a.storage), 0);
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrUnT)], std.mem.asBytes(&sun));
        return a;
    }

    pub fn fromIp(ip: std.Io.net.IpAddress) NetAddress {
        return switch (ip) {
            .ip4 => |v4| initIp4(v4.bytes, v4.port),
            .ip6 => |v6| initIp6(v6.bytes, v6.port, v6.flow, v6.interface.index),
        };
    }

    pub fn resolveIp(host: []const u8, port: u16) !NetAddress {
        if (std.Io.net.IpAddress.parse(host, port)) |ip| {
            return fromIp(ip);
        } else |_| {}
        var list = try netGetAddressList(std.heap.page_allocator, host, port);
        defer list.deinit();
        if (list.addrs.len == 0) return error.HostLacksNetworkAddresses;
        return list.addrs[0];
    }

    pub fn unixPath(self: *const NetAddress) []const u8 {
        const sun: *const SockAddrUnT = @ptrCast(&self.storage);
        return std.mem.sliceTo(&sun.path, 0);
    }

    pub fn fromUnixSockaddr(sun: SockAddrUnT, len: SockLenT) NetAddress {
        var a = NetAddress{ .len = len };
        @memset(std.mem.asBytes(&a.storage), 0);
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrUnT)], std.mem.asBytes(&sun));
        return a;
    }

    pub fn in6ScopeId(self: *const NetAddress) u32 {
        const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&self.storage));
        return sin6.scope_id;
    }

    pub fn in4AddrU32(self: *const NetAddress) u32 {
        const sin: *const SockAddrInT = @ptrCast(@alignCast(&self.storage));
        return sin.addr;
    }

    pub fn in6AddrBytes(self: *const NetAddress) [16]u8 {
        const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&self.storage));
        return sin6.addr;
    }
};

pub const NetAddressList = struct {
    addrs: []NetAddress,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *NetAddressList) void {
        self.allocator.free(self.addrs);
        self.addrs = &.{};
    }
};

pub fn stringConcat(left: []const u8, right: []const u8) ![]u8 {
    var bytes = try std.heap.page_allocator.alloc(u8, left.len + right.len);
    if (left.len != 0) std.mem.copyForwards(u8, bytes[0..left.len], left);
    if (right.len != 0) std.mem.copyForwards(u8, bytes[left.len .. left.len + right.len], right);
    return bytes;
}

pub fn dlclose(handle: ?[*]u8) callconv(.c) i32 {
    _ = handle;
    sa_std.last_error = SA_STD_ERR_UNSUPPORTED;
    return SA_STD_ERR_UNSUPPORTED;
}

pub const ProcessOutputStream = enum { stdout, stderr };

pub fn metadataModeMatches(handle: u64, mode_bits: u64) u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| if ((@as(u64, @intCast(metadata.raw.mode)) & std.posix.S.IFMT) == mode_bits) 1 else 0,
        else => 0,
    };
}

pub const poll_wait_stack_handles: usize = 256;

pub const recv_multi_max_msgs: usize = 64;

pub fn isAsciiWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
        else => false,
    };
}
