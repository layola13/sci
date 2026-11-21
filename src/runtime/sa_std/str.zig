const std = @import("std");
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const constBytes = @import("../sa_std.zig").constBytes;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const isAsciiWhitespace = @import("../sa_std.zig").isAsciiWhitespace;
const utf8CharRangeAt = @import("../sa_std.zig").utf8CharRangeAt;
const utf8LossyInvalidWidth = @import("../sa_std.zig").utf8LossyInvalidWidth;
const utf8ScalarAt = @import("../sa_std.zig").utf8ScalarAt;

pub export fn sa_str_is_ascii(ptr: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(ptr, len) catch return 0;
    for (bytes) |byte| {
        if (byte > 0x7f) return 0;
    }
    return 1;
}

pub export fn sa_str_eq_ignore_ascii_case(left_ptr: ?[*]const u8, left_len: u64, right_ptr: ?[*]const u8, right_len: u64) i32 {
    const left = constBytes(left_ptr, left_len) catch return 0;
    const right = constBytes(right_ptr, right_len) catch return 0;
    if (left.len != right.len) return 0;
    return if (std.ascii.eqlIgnoreCase(left, right)) 1 else 0;
}

pub export fn sa_str_utf8_char_count(ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    var byte_index: usize = 0;
    var count: u64 = 0;
    while (byte_index < bytes.len) {
        const decoded = utf8ScalarAt(bytes, byte_index) catch return 0;
        byte_index += decoded.width;
        count += 1;
    }
    return count;
}

pub export fn sa_str_utf8_validate(ptr: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(ptr, len) catch |err| return finishErr(err);
    var byte_index: usize = 0;
    while (byte_index < bytes.len) {
        const decoded = utf8ScalarAt(bytes, byte_index) catch |err| return finishErr(err);
        byte_index += decoded.width;
    }
    return finish(SA_STD_OK);
}

pub export fn sa_str_utf8_char_at(ptr: ?[*]const u8, len: u64, char_index: u64, out_codepoint: ?*u64) i32 {
    const out = out_codepoint orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const bytes = constBytes(ptr, len) catch |err| return finishErr(err);
    const range = utf8CharRangeAt(bytes, char_index) catch |err| return finishErr(err);
    out.* = range.scalar;
    return finish(SA_STD_OK);
}

pub export fn sa_str_utf8_char_at_byte(ptr: ?[*]const u8, len: u64, byte_index: u64, out_codepoint: ?*u64, out_len: ?*u64) i32 {
    const codepoint_ptr = out_codepoint orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    codepoint_ptr.* = 0;
    len_ptr.* = 0;
    const bytes = constBytes(ptr, len) catch |err| return finishErr(err);
    if (byte_index > std.math.maxInt(usize)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const decoded = utf8ScalarAt(bytes, @as(usize, @intCast(byte_index))) catch |err| return finishErr(err);
    codepoint_ptr.* = decoded.scalar;
    len_ptr.* = @as(u64, @intCast(decoded.width));
    return finish(SA_STD_OK);
}

pub export fn sa_str_utf8_lossy_next(ptr: ?[*]const u8, len: u64, byte_index: u64, out_codepoint: ?*u64, out_len: ?*u64) i32 {
    const codepoint_ptr = out_codepoint orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    codepoint_ptr.* = 0;
    len_ptr.* = 0;
    const bytes = constBytes(ptr, len) catch |err| return finishErr(err);
    if (byte_index > std.math.maxInt(usize)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const idx: usize = @intCast(byte_index);
    if (idx >= bytes.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const decoded = utf8ScalarAt(bytes, idx) catch {
        codepoint_ptr.* = 65533;
        len_ptr.* = @as(u64, @intCast(utf8LossyInvalidWidth(bytes, idx)));
        return finish(SA_STD_OK);
    };
    codepoint_ptr.* = decoded.scalar;
    len_ptr.* = @as(u64, @intCast(decoded.width));
    return finish(SA_STD_OK);
}

pub export fn sa_str_utf8_char_range_at(ptr: ?[*]const u8, len: u64, char_index: u64, out_start: ?*u64, out_len: ?*u64) i32 {
    const start_ptr = out_start orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    start_ptr.* = 0;
    len_ptr.* = 0;
    const bytes = constBytes(ptr, len) catch |err| return finishErr(err);
    const range = utf8CharRangeAt(bytes, char_index) catch |err| return finishErr(err);
    start_ptr.* = @as(u64, @intCast(range.start));
    len_ptr.* = @as(u64, @intCast(range.len));
    return finish(SA_STD_OK);
}

pub export fn sa_str_trim_ascii_start_index(ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    var index: usize = 0;
    while (index < bytes.len and isAsciiWhitespace(bytes[index])) : (index += 1) {}
    return @as(u64, @intCast(index));
}

pub export fn sa_str_trim_ascii_end_len(ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    var end = bytes.len;
    while (end > 0 and isAsciiWhitespace(bytes[end - 1])) : (end -= 1) {}
    return @as(u64, @intCast(end));
}
