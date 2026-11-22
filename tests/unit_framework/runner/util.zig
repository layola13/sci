const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

pub extern "c" fn unsetenv(name: [*:0]const u8) c_int;

pub extern "c" fn _putenv_s(name: [*:0]const u8, value: [*:0]const u8) c_int;

pub fn expectContains(text: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, text, needle) != null);
}

pub fn expectNotContains(text: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, text, needle) == null);
}

/// Probe whether the host permits IPv6 multicast joins. Some containers
/// lack a multicast-capable interface (join returns ENODEV) while IPv4
/// multicast works; the v6-only macro surface suite is then skipped
/// instead of reporting environment incapability as product failure.
/// Precedent: udpSendtoPermitted / udpMulticastV6JoinPermitted in
/// tests/sa_std_runtime.zig (sci@71e02f12).
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

pub fn writeSource(dir: std.Io.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(std.testing.io, path, .{ .truncate = true });
    defer file.close(std.testing.io);
    var wbuf: [8192]u8 = undefined;
    var w = file.writer(std.testing.io, &wbuf);
    try w.interface.writeAll(source);
    try w.interface.flush();
}

pub fn setEnvVarZ(name: [:0]const u8, value: [:0]const u8) !void {
    const rc = if (builtin.os.tag == .windows)
        _putenv_s(name.ptr, value.ptr)
    else
        setenv(name.ptr, value.ptr, 1);
    if (rc != 0) return error.SetEnvFailed;
}

pub fn unsetEnvVarZ(name: [:0]const u8) void {
    if (builtin.os.tag == .windows) {
        _ = _putenv_s(name.ptr, "");
    } else {
        _ = unsetenv(name.ptr);
    }
}

pub fn saveEnvVarZ(allocator: std.mem.Allocator, name: []const u8) !?[:0]u8 {
    const value = sio.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(value);
    return try allocator.dupeSentinel(u8, value, 0);
}

pub fn restoreEnvVarZ(name: [:0]const u8, value: ?[:0]const u8) !void {
    if (value) |saved| {
        try setEnvVarZ(name, saved);
    } else {
        unsetEnvVarZ(name);
    }
}

pub fn saTestJobsArg(allocator: std.mem.Allocator) ![]const u8 {
    const env_names = [_][]const u8{ "SA_TEST_JOBS", "SA_ZIG_JOBS", "ZIG_BUILD_JOBS" };
    for (env_names) |name| {
        if (sio.getEnvVarOwned(allocator, name)) |value| {
            if (value.len != 0) return value;
            allocator.free(value);
        } else |_| {}
    }
    return allocator.dupe(u8, "auto");
}

pub fn saTestJobsArgForPath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    _ = path;
    if (saUnitFileJobs() > 1 and !hasEnvVar(allocator, "SA_TEST_JOBS")) {
        return allocator.dupe(u8, "1");
    }
    return saTestJobsArg(allocator);
}

pub fn hasEnvVar(allocator: std.mem.Allocator, name: []const u8) bool {
    const value = sio.getEnvVarOwned(allocator, name) catch return false;
    allocator.free(value);
    return true;
}

pub fn parsePositiveUsize(text: []const u8) ?usize {
    if (text.len == 0 or std.mem.eql(u8, text, "auto")) return null;
    const parsed = std.fmt.parseUnsigned(usize, text, 10) catch return null;
    return if (parsed == 0) null else parsed;
}

pub fn saUnitFileJobs() usize {
    const value = sio.getEnvVarOwned(std.heap.page_allocator, "SA_UNIT_FILE_JOBS") catch return 1;
    defer std.heap.page_allocator.free(value);
    if (parsePositiveUsize(value)) |requested| {
        const cpu_count = std.Thread.getCpuCount() catch 1;
        return @min(requested, @max(cpu_count, @as(usize, 1)));
    }
    return 1;
}

pub fn saBinaryPath(allocator: std.mem.Allocator) ?[]u8 {
    const value = sio.getEnvVarOwned(allocator, "SA_BIN") catch return null;
    if (value.len == 0) {
        allocator.free(value);
        return null;
    }
    return value;
}

pub fn elapsedMs(start_ns: i128) i128 {
    return @divTrunc(sio.nanoTimestamp() - start_ns, std.time.ns_per_ms);
}

pub fn startSaFileLog(path: []const u8, mode: []const u8, jobs_arg: []const u8, index: usize, total: usize) i128 {
    if (total == 0) {
        std.debug.print("[unit-framework] START file={s} mode={s} jobs={s}\n", .{ path, mode, jobs_arg });
    } else {
        std.debug.print("[unit-framework] START index={}/{} file={s} mode={s} jobs={s}\n", .{ index, total, path, mode, jobs_arg });
    }
    return sio.nanoTimestamp();
}

pub fn endSaFileLog(
    path: []const u8,
    mode: []const u8,
    jobs_arg: []const u8,
    index: usize,
    total: usize,
    start_ns: i128,
    stdout_len: usize,
    stderr_len: usize,
) void {
    if (total == 0) {
        std.debug.print(
            "[unit-framework] END   file={s} mode={s} elapsed={}ms jobs={s} stdout_bytes={} stderr_bytes={}\n",
            .{ path, mode, elapsedMs(start_ns), jobs_arg, stdout_len, stderr_len },
        );
    } else {
        std.debug.print(
            "[unit-framework] END   index={}/{} file={s} mode={s} elapsed={}ms jobs={s} stdout_bytes={} stderr_bytes={}\n",
            .{ index, total, path, mode, elapsedMs(start_ns), jobs_arg, stdout_len, stderr_len },
        );
    }
}

pub fn errorSaFileLog(path: []const u8, mode: []const u8, index: usize, total: usize, err: anyerror) void {
    if (total == 0) {
        std.debug.print("[unit-framework] END   file={s} mode={s} status=error err={s}\n", .{ path, mode, @errorName(err) });
    } else {
        std.debug.print("[unit-framework] END   index={}/{} file={s} mode={s} status=error err={s}\n", .{ index, total, path, mode, @errorName(err) });
    }
}
