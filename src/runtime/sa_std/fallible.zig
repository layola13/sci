const std = @import("std");
const SA_STD_ERR_ACCESS = @import("../sa_std.zig").SA_STD_ERR_ACCESS;
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NET = @import("../sa_std.zig").SA_STD_ERR_NET;
const SA_STD_ERR_NOT_FOUND = @import("../sa_std.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("../sa_std.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_PERMISSION_DENIED = @import("../sa_std.zig").SA_STD_ERR_PERMISSION_DENIED;
const SA_STD_ERR_TRUNCATED = @import("../sa_std.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_ERR_UNKNOWN = @import("../sa_std.zig").SA_STD_ERR_UNKNOWN;
const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const constBytes = @import("../sa_std.zig").constBytes;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const lenAsUsize = @import("../sa_std.zig").lenAsUsize;
const sio = @import("../sa_std.zig").sio;

fn statusName(code: i32) []const u8 {
    return switch (code) {
        SA_STD_OK => "ok",
        SA_STD_ERR_INVALID_ARGUMENT => "invalid_argument",
        SA_STD_ERR_INVALID_HANDLE => "invalid_handle",
        SA_STD_ERR_NOT_FOUND => "not_found",
        SA_STD_ERR_ACCESS => "access",
        SA_STD_ERR_NO_MEMORY => "no_memory",
        SA_STD_ERR_IO => "io",
        SA_STD_ERR_NET => "net",
        SA_STD_ERR_UNSUPPORTED => "unsupported",
        SA_STD_ERR_TRUNCATED => "truncated",
        SA_STD_ERR_PERMISSION_DENIED => "permission_denied",
        SA_STD_ERR_UNKNOWN => "unknown",
        else => "unknown",
    };
}

pub fn Fallible(comptime T: type) type {
    return extern struct {
        status: i32,
        value: T,
    };
}

pub fn ok(comptime T: type, value: T) Fallible(T) {
    return .{ .status = SA_STD_OK, .value = value };
}

pub fn fail(comptime T: type, status: i32) Fallible(T) {
    return .{ .status = status, .value = std.mem.zeroes(T) };
}

pub fn netErrorCodeName(code: i32) []const u8 {
    return switch (code) {
        0 => "ok",
        1 => "unknown",
        2 => "dns",
        3 => "connection_refused",
        4 => "timed_out",
        5 => "connection_closed",
        6 => "would_block",
        7 => "invalid_address",
        8 => "permission_denied",
        9 => "unsupported",
        10 => "invalid_input",
        11 => "invalid_handle",
        12 => "not_found",
        13 => "out_of_memory",
        14 => "io",
        15 => "network_unreachable",
        16 => "addr_in_use",
        17 => "addr_not_available",
        18 => "connection_reset",
        19 => "connection_aborted",
        20 => "not_connected",
        21 => "host_unreachable",
        22 => "broken_pipe",
        23 => "already_exists",
        24 => "interrupted",
        25 => "unexpected_eof",
        26 => "invalid_data",
        27 => "network_down",
        28 => "write_zero",
        else => "unknown",
    };
}

pub export fn sa_std_error_name(code: i32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const name = statusName(code);
    if (out_len) |len_ptr| len_ptr.* = @as(u64, @intCast(name.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const cap = lenAsUsize(out_cap) catch |err| return finishErr(err);
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const copy_len = @min(cap, name.len);
    @memcpy(out_ptr[0..copy_len], name[0..copy_len]);
    if (copy_len != name.len) return finish(SA_STD_ERR_TRUNCATED);
    return finish(SA_STD_OK);
}

pub export fn sa_std_println(data: ?[*]const u8, len: u64) Fallible(i32) {
    // Contract alignment (A_min): io.sai declares `-> i32!`, and the
    // interpreter already returns a fallible cell; the native runtime
    // used to return the bare status word, so compiled callers read
    // the payload slot of a cell that was never written.
    const bytes = constBytes(data, len) catch |err| return fail(i32, finishErr(err));
    sio.getStdOut().writeAll(bytes) catch |err| return fail(i32, finishErr(err));
    sio.getStdOut().writeAll("\n") catch |err| return fail(i32, finishErr(err));
    return ok(i32, 0);
}

pub export fn sa_test_fallible_i32_value(value: i32) Fallible(i32) {
    return ok(i32, value);
}
