const std = @import("std");
const sa_std = @import("../sa_std.zig");
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NO_MEMORY = @import("../sa_std.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const constBytes = @import("../sa_std.zig").constBytes;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const formatBool = @import("../sa_std.zig").formatBool;
const formatBytes = @import("../sa_std.zig").formatBytes;
const formatFloat = @import("../sa_std.zig").formatFloat;
const formatInteger = @import("../sa_std.zig").formatInteger;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const lockRegistry = @import("../sa_std.zig").lockRegistry;
const openOwnedBuffer = @import("../sa_std.zig").openOwnedBuffer;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const writeFormattedInto = @import("../sa_std.zig").writeFormattedInto;
const writeHandle = @import("../sa_std.zig").writeHandle;

pub export fn sa_fmt_i64(value: i64, base: u32) u64 {
    const bytes = formatInteger(value, base) catch return 0;
    return openOwnedBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_i64_into(value: i64, base: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const n = std.fmt.printInt(&buf, value, actual_base, case, .{});
    const text = buf[0..n];
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_u64(value: u64, base: u32) u64 {
    const bytes = formatInteger(value, base) catch return 0;
    return openOwnedBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_u64_into(value: u64, base: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const n = std.fmt.printInt(&buf, value, actual_base, case, .{});
    const text = buf[0..n];
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_f64(value: f64, precision: u32) u64 {
    const bytes = formatFloat(value, precision) catch return 0;
    return openOwnedBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_f64_into(value: f64, precision: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    var buf: [256]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d:.[1]}", .{ value, @as(usize, @intCast(precision)) }) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_bool(value: bool) u64 {
    const bytes = formatBool(value) catch return 0;
    return openOwnedBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_bool_into(value: bool, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    return writeFormattedInto(out, out_cap, out_len, if (value) "true" else "false");
}

pub export fn sa_fmt_bytes(buf: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(buf, len) catch return 0;
    const owned = formatBytes(bytes) catch return 0;
    return openOwnedBuffer(owned) catch return 0;
}

pub export fn sa_fmt_bytes_into(buf: ?[*]const u8, len: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    return writeFormattedInto(out, out_cap, out_len, bytes);
}

pub export fn sa_fmt_buffer_data(buffer: u64) ?[*]u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return null;
    return switch (resource.*) {
        .fmt => |*fmt| fmt.bytes.ptr,
        else => null,
    };
}

pub export fn sa_fmt_buffer_len(buffer: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return 0;
    return switch (resource.*) {
        .fmt => |fmt| @as(u64, @intCast(fmt.bytes.len)),
        else => 0,
    };
}

pub export fn sa_fmt_buffer_write_to(buffer: u64, writer: u64) i32 {
    // Snapshot the formatted bytes under the lock (the slice
    // points into the fmt resource), then write unlocked via
    // the DEF-R5 data path: the write itself can block.
    lockRegistry();
    const resource = getResourceLocked(buffer) orelse {
        sa_std.registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const bytes = switch (resource.*) {
        .fmt => |fmt| fmt.bytes,
        else => {
            sa_std.registry_mutex.unlock();
            return finish(SA_STD_ERR_INVALID_HANDLE);
        },
    };
    const copy = std.heap.page_allocator.dupe(u8, bytes) catch {
        sa_std.registry_mutex.unlock();
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    sa_std.registry_mutex.unlock();
    defer std.heap.page_allocator.free(copy);
    const written = writeHandle(writer, copy) catch |err| return finishErr(err);
    if (written != copy.len) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_fmt_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}
