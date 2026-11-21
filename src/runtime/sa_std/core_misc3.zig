const std = @import("std");
pub const JsonWriterHandle = @import("../sa_std.zig").JsonWriterHandle;
pub const SO_PASSCRED = @import("../sa_std.zig").SO_PASSCRED;
pub const WasiSOL = @import("../sa_std.zig").WasiSOL;
pub const errnoToAny = @import("../sa_std.zig").errnoToAny;
pub const is_linux = @import("../sa_std.zig").is_linux;
pub const is_wasm = @import("../sa_std.zig").is_wasm;
pub const policyAllows = @import("../sa_std.zig").policyAllows;
const setSocketOptBool = @import("../sa_std.zig").setSocketOptBool;
pub const sio = @import("../sa_std.zig").sio;

pub fn saStdPolicyAllowsRun(program: []const u8) bool {
    return policyAllows(.{ .run = program });
}

pub fn saStdPolicyAllowsFsRead(path: []const u8) bool {
    return policyAllows(.{ .fs = .{ .path = path, .write = false } });
}

pub fn policyEnvOwned(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    return sio.getEnvVarOwned(allocator, name) catch null;
}

pub const SOLT = if (is_wasm) WasiSOL else std.posix.SOL;

pub const RegexMatchC = extern struct {
    rm_so: c_int,
    rm_eo: c_int,
};

pub fn markJsonWriterValueComplete(writer_handle: *JsonWriterHandle) void {
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
}

pub const SaTermEpollEvent = extern struct {
    events: u32,
    data: u64,
};

pub fn lingerSeconds(timeout_ns: u64) !i32 {
    const seconds = timeout_ns / std.time.ns_per_s;
    return std.math.cast(i32, seconds) orelse error.InvalidArgument;
}

pub const LinuxUCred = extern struct {
    pid: i32,
    uid: u32,
    gid: u32,
};

pub fn armPeerCredHarvest(fd: std.posix.fd_t) void {
    if (comptime !is_linux) return;
    setSocketOptBool(fd, SOLT.SOCKET, SO_PASSCRED, true) catch {};
}

pub fn libcErrRc(rc: anytype) !void {
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
}

pub fn libcUsize(rc: isize) !usize {
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
    return @intCast(rc);
}

pub const EnvVarJson = struct {
    key: []const u8,
    value: []const u8,
};

pub fn saNumCheckedTrap(comptime symbol: []const u8, a: i64, b: i64) noreturn {
    std.debug.print("[sa-std] {s}({d}, {d}): i64 overflow, trapping (PANIC_ARITH_OVERFLOW=9001)\n", .{ symbol, a, b });
    std.process.abort();
}

pub const weekdayNames = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };

pub fn groupId(value: u32, enabled: u32) std.c.gid_t {
    return if (enabled != 0) @as(std.c.gid_t, @intCast(value)) else ~@as(std.c.gid_t, 0);
}

pub const recv_msg_flag_pktinfo: u32 = 1;

pub const recv_msg_flag_timestamp: u32 = 2;

pub const recv_msg_flag_ctrunc: u32 = 4;

pub const recv_msg_flag_trunc: u32 = 8;

pub fn expectTimeoutRoundedUpWithin(requested_ns: u64, observed_ns: u64) !void {
    try std.testing.expect(observed_ns >= requested_ns);
    try std.testing.expect(observed_ns - requested_ns <= 10 * std.time.ns_per_ms);
}
