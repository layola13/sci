const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const build_options = @import("build_options");

// Static demos link libsa_std.a, which carries no link dependencies, so
// demos add the ICU libraries the Unicode runtime (sa_unicode_normalize)
// needs on Linux themselves. Empty elsewhere; other platforms arrange ICU
// differently and must not gain a bogus -licuuc flag.
pub const icu_demo_link_args: [if (builtin.os.tag == .linux) 2 else 0][]const u8 = if (builtin.os.tag == .linux)
    .{ "-licuuc", "-licudata" }
else
    .{};

pub fn writeSource(dir: std.Io.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(std.testing.io, path, .{ .truncate = true });
    defer file.close(std.testing.io);
    var wbuf: [8192]u8 = undefined;
    var w = file.writer(std.testing.io, &wbuf);
    try w.interface.writeAll(source);
    try w.interface.flush();
}

pub fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !sio.Child.RunResult {
    return try sio.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

pub fn copyRuntimeArchiveToCwd() !void {
    var src = try sio.openFileAbsolute(build_options.sa_std_archive_path, .{});
    defer src.close();
    var dst = try sio.cwd().createFile("libsa_std.a", .{ .truncate = true });
    defer dst.close();
    const data = try src.readToEndAlloc(std.heap.page_allocator, 256 * 1024 * 1024);
    defer std.heap.page_allocator.free(data);
    try dst.writeAll(data);
}

pub fn expectSuccess(result: sio.Child.RunResult) !void {
    if (result.stderr.len != 0) {
        std.debug.print("{s}", .{result.stderr});
    }
    switch (result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

pub fn expectSuccessCode(result: sio.Child.RunResult) !void {
    if (result.stderr.len != 0) {
        std.debug.print("{s}", .{result.stderr});
    }
    switch (result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

/// Probe whether the sandbox permits the raw sendto(2) syscall. Some
/// containers block sendto via seccomp (EPERM) while allowing connected
/// send(); the loopback C-ABI test cannot exercise send_to there, so it
/// skips instead of reporting environment incapability as product failure.
pub fn udpSendtoPermitted() bool {
    // NOTE(Zig 0.17): raw io_uring-era std has no posix.socket/Address
    // helpers; probe with raw Linux syscalls (this module runs on Linux).
    if (builtin.os.tag != .linux) return false;
    const os = std.os.linux;
    const fd = os.socket(os.AF.INET, os.SOCK.DGRAM, 0);
    if (@as(isize, @bitCast(fd)) < 0) return false;
    const sock: os.fd_t = @intCast(fd);
    defer _ = os.close(sock);
    var addr = os.sockaddr.in{
        .port = std.mem.nativeToBig(u16, 9999),
        .addr = 0x0100007f, // 127.0.0.1
    };
    // Raw syscall: a seccomp-blocked sendto(2) returns -EPERM directly,
    // without any errno-mapping helper (0.17 has no E.init).
    const neg_eperm: usize = @bitCast(@as(isize, -1)); // EPERM == 1
    const rc = os.sendto(sock, "probe".ptr, "probe".len, 0, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
    return rc != neg_eperm;
}

/// Probe whether the sandbox permits IPv6 multicast joins. Some containers
/// lack a multicast-capable interface (join returns ENODEV) while IPv4
/// multicast works; the udp multicast C-ABI test then verifies only its v4
/// section instead of reporting environment incapability as product failure.
pub fn udpMulticastV6JoinPermitted() bool {
    if (builtin.os.tag != .linux) return false;
    const os = std.os.linux;
    const fd = os.socket(os.AF.INET6, os.SOCK.DGRAM, 0);
    if (@as(isize, @bitCast(fd)) < 0) return false;
    const sock: os.fd_t = @intCast(fd);
    defer _ = os.close(sock);
    var mreq = [_]u8{ 0xFF, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x14, 0, 0, 0, 0 };
    const rc = os.setsockopt(sock, 41, 20, &mreq, mreq.len);
    return rc == 0;
}

pub fn writeProcessArgv(
    allocator: std.mem.Allocator,
    args: []const []const u8,
) !struct { ptr: [*]const u8, len: u64, backing: [][]const u8 } {
    const backing = try allocator.alloc([]const u8, args.len);
    for (args, 0..) |arg, i| {
        backing[i] = try allocator.dupe(u8, arg);
    }
    return .{
        .ptr = @ptrCast(backing.ptr),
        .len = @as(u64, @intCast(backing.len)),
        .backing = backing,
    };
}
