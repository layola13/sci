const std = @import("std");
const sio = @import("../sa_std.zig").sio;

const TestDebugScalar = struct {
    name: [64]u8 = std.mem.zeroes([64]u8),
    name_len: usize = 0,
    value: i64 = 0,
};

var test_debug_scalars: [16]TestDebugScalar = std.mem.zeroes([16]TestDebugScalar);

var test_debug_next: usize = 0;

var test_debug_count: usize = 0;

var test_debug_mutex: std.atomic.Mutex = .unlocked;

pub fn cryptoRandomU64() u64 {
    var rb: [8]u8 = undefined;
    sio.io().random(&rb);
    return std.mem.readInt(u64, &rb, .little);
}

pub fn envValueFromCurrentProcess(key: []const u8) ?[]const u8 {
    const key_z = std.heap.page_allocator.dupeSentinel(u8, key, 0) catch return null;
    defer std.heap.page_allocator.free(key_z);

    const getenv = @extern(*const fn ([*:0]const u8) callconv(.c) ?[*:0]u8, .{ .name = "getenv" });
    const value = getenv(key_z.ptr) orelse return null;
    return std.mem.span(value);
}

pub fn envGetOwned(key: []const u8) ![]u8 {
    const value = envValueFromCurrentProcess(key) orelse return error.FileNotFound;
    return std.heap.page_allocator.dupe(u8, value);
}

fn xdgHomeDirAlloc(allocator: std.mem.Allocator) ![]u8 {
    const home = envValueFromCurrentProcess("HOME") orelse return error.FileNotFound;
    if (home.len == 0) return allocator.dupe(u8, "/");
    return allocator.dupe(u8, home);
}

pub fn xdgHomeSubdirAlloc(allocator: std.mem.Allocator, env_key: []const u8, fallback_home_subdir: []const u8) ![]u8 {
    if (envValueFromCurrentProcess(env_key)) |value| {
        if (value.len != 0) return allocator.dupe(u8, value);
    }
    const home = try xdgHomeDirAlloc(allocator);
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, fallback_home_subdir });
}

pub fn xdgDirsAlloc(allocator: std.mem.Allocator, env_key: []const u8, default_value: []const u8) ![]u8 {
    if (envValueFromCurrentProcess(env_key)) |value| {
        if (value.len != 0) return allocator.dupe(u8, value);
    }
    return allocator.dupe(u8, default_value);
}

pub fn tempRootAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (envValueFromCurrentProcess("TMPDIR")) |value| {
        if (value.len != 0) return allocator.dupe(u8, value);
    }
    if (envValueFromCurrentProcess("TMP")) |value| {
        if (value.len != 0) return allocator.dupe(u8, value);
    }
    if (envValueFromCurrentProcess("TEMP")) |value| {
        if (value.len != 0) return allocator.dupe(u8, value);
    }
    return allocator.dupe(u8, "/tmp");
}

pub fn tempPathAlloc(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    suffix: []const u8,
) ![]u8 {
    const root = try tempRootAlloc(allocator);
    defer allocator.free(root);
    const normalized_prefix = if (prefix.len == 0) "sa-deno-" else prefix;
    const a = cryptoRandomU64();
    const b = cryptoRandomU64();
    const name = try std.fmt.allocPrint(allocator, "{s}{x:0>16}{x:0>16}{s}", .{ normalized_prefix, a, b, suffix });
    defer allocator.free(name);
    return std.fs.path.join(allocator, &.{ root, name });
}

pub export fn sa_test_debug_i64(name: ?[*]const u8, name_len: u64, value: i64) void {
    const raw_name = name orelse return;
    while (!test_debug_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer test_debug_mutex.unlock();
    const slot_index = test_debug_next % test_debug_scalars.len;
    var slot = &test_debug_scalars[slot_index];
    const requested_len = std.math.cast(usize, name_len) orelse slot.name.len;
    const copy_len = @min(requested_len, slot.name.len);
    @memset(slot.name[0..], 0);
    if (copy_len != 0) @memcpy(slot.name[0..copy_len], raw_name[0..copy_len]);
    slot.name_len = copy_len;
    slot.value = value;
    test_debug_next = (test_debug_next + 1) % test_debug_scalars.len;
    if (test_debug_count < test_debug_scalars.len) test_debug_count += 1;
}

fn testTracePanicEnabled() bool {
    const value = envValueFromCurrentProcess("SA_TEST_TRACE_PANIC") orelse return false;
    return value.len != 0 and !std.mem.eql(u8, value, "0");
}

fn printRecentTestScalars() void {
    while (!test_debug_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer test_debug_mutex.unlock();
    if (test_debug_count == 0) return;
    std.debug.print("recent scalars:\n", .{});
    var index: usize = test_debug_next + test_debug_scalars.len - test_debug_count;
    var remaining = test_debug_count;
    while (remaining > 0) : (remaining -= 1) {
        const slot = test_debug_scalars[index % test_debug_scalars.len];
        if (slot.name_len != 0) {
            std.debug.print("  {s}={d}\n", .{ slot.name[0..slot.name_len], slot.value });
        }
        index += 1;
    }
}

fn exitAfterAssertPanic(code: i32) noreturn {
    if (testTracePanicEnabled()) printRecentTestScalars();
    const raw_code: u32 = @bitCast(code);
    const exit_code: u8 = @as(u8, @truncate((raw_code & 0x7f) + 128));
    std.process.exit(exit_code);
}

pub export fn sa_assert_eq_i64(actual: i64, expected: i64, code: i32) void {
    if (actual == expected) return;
    std.debug.print("PANIC[{d}]: expected={d} actual={d}\n", .{ code, expected, actual });
    exitAfterAssertPanic(code);
}

pub export fn sa_assert_eq_i64_at(actual: i64, expected: i64, code: i32, file: ?[*]const u8, file_len: u64, line: u32, col: u32) void {
    if (actual == expected) return;
    const file_slice = if (file) |ptr| ptr[0..@as(usize, @intCast(file_len))] else "";
    if (file_slice.len != 0 and line != 0) {
        std.debug.print("PANIC[{d}]: {s}:{d}:{d}: expected={d} actual={d}\n", .{ code, file_slice, line, col, expected, actual });
    } else {
        std.debug.print("PANIC[{d}]: expected={d} actual={d}\n", .{ code, expected, actual });
    }
    exitAfterAssertPanic(code);
}
