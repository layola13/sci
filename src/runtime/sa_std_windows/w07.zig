const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const appendIsoUtcWin = @import("w05.zig").appendIsoUtcWin;
const constBytes = @import("w02.zig").constBytes;
const finish = @import("w02.zig").finish;
const finishErr = @import("w02.zig").finishErr;
const isAsciiWhitespace = @import("w02.zig").isAsciiWhitespace;
const lenAsUsize = @import("w02.zig").lenAsUsize;
const monotonicNowNs = @import("w02.zig").monotonicNowNs;
const openOwnedByteBuffer = @import("w02.zig").openOwnedByteBuffer;
const utf8CharRangeAt = @import("w02.zig").utf8CharRangeAt;
const utf8LossyInvalidWidth = @import("w02.zig").utf8LossyInvalidWidth;
const utf8ScalarAt = @import("w02.zig").utf8ScalarAt;

/// JS `String.prototype.indexOf` over byte-oriented strings (mirrors the
/// non-Windows variant): first needle index at/after `from`, or -1.
pub export fn sa_string_index_of(hay_ptr: ?[*]const u8, hay_len: u64, ndl_ptr: ?[*]const u8, ndl_len: u64, from: u64) i32 {
    const hay = constBytes(hay_ptr, hay_len) catch return -1;
    const ndl = constBytes(ndl_ptr, ndl_len) catch return -1;
    const start: usize = @as(usize, @intCast(@min(from, hay_len)));
    if (ndl.len == 0) return @as(i32, @intCast(@min(start, hay.len)));
    if (ndl.len > hay.len) return -1;
    var i: usize = start;
    while (i + ndl.len <= hay.len) : (i += 1) {
        if (std.mem.eql(u8, hay[i..][0..ndl.len], ndl)) return @as(i32, @intCast(i));
    }
    return -1;
}

/// JS `String.prototype.lastIndexOf` (mirrors the non-Windows variant).
pub export fn sa_string_last_index_of(hay_ptr: ?[*]const u8, hay_len: u64, ndl_ptr: ?[*]const u8, ndl_len: u64, from: u64) i32 {
    const hay = constBytes(hay_ptr, hay_len) catch return -1;
    const ndl = constBytes(ndl_ptr, ndl_len) catch return -1;
    const start: usize = @as(usize, @intCast(@min(from, hay_len)));
    if (ndl.len == 0) return @as(i32, @intCast(@min(start, hay.len)));
    if (ndl.len > hay.len) return -1;
    var i: usize = @min(start, hay.len - ndl.len);
    while (true) {
        if (std.mem.eql(u8, hay[i..][0..ndl.len], ndl)) return @as(i32, @intCast(i));
        if (i == 0) break;
        i -= 1;
    }
    return -1;
}

/// JS `String.prototype.startsWith` (mirrors the non-Windows variant): 1/0.
pub export fn sa_string_starts_with(hay_ptr: ?[*]const u8, hay_len: u64, ndl_ptr: ?[*]const u8, ndl_len: u64) i32 {
    const hay = constBytes(hay_ptr, hay_len) catch return 0;
    const ndl = constBytes(ndl_ptr, ndl_len) catch return 0;
    if (ndl.len > hay.len) return 0;
    return if (std.mem.eql(u8, hay[0..ndl.len], ndl)) 1 else 0;
}

/// JS `String.prototype.endsWith` (mirrors the non-Windows variant): 1/0.
pub export fn sa_string_ends_with(hay_ptr: ?[*]const u8, hay_len: u64, ndl_ptr: ?[*]const u8, ndl_len: u64) i32 {
    const hay = constBytes(hay_ptr, hay_len) catch return 0;
    const ndl = constBytes(ndl_ptr, ndl_len) catch return 0;
    if (ndl.len > hay.len) return 0;
    return if (std.mem.eql(u8, hay[hay.len - ndl.len ..], ndl)) 1 else 0;
}

/// JS `String.prototype.toLowerCase` (mirrors the non-Windows variant).
pub export fn sa_string_to_lower_ascii(ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    const owned = std.heap.page_allocator.alloc(u8, bytes.len) catch return 0;
    for (bytes, 0..) |byte, i| {
        owned[i] = if (byte >= 'A' and byte <= 'Z') byte + ('a' - 'A') else byte;
    }
    return openOwnedByteBuffer(owned) catch return 0;
}

/// JS `String.prototype.toUpperCase` (mirrors the non-Windows variant).
pub export fn sa_string_to_upper_ascii(ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    const owned = std.heap.page_allocator.alloc(u8, bytes.len) catch return 0;
    for (bytes, 0..) |byte, i| {
        owned[i] = if (byte >= 'a' and byte <= 'z') byte - ('a' - 'A') else byte;
    }
    return openOwnedByteBuffer(owned) catch return 0;
}

/// JS `parseFloat` (mirrors the non-Windows variant).
pub export fn sa_parse_float(ptr: ?[*]const u8, len: u64) f64 {
    const bytes = constBytes(ptr, len) catch return std.math.nan(f64);
    var i: usize = 0;
    while (i < bytes.len and isAsciiWhitespace(bytes[i])) : (i += 1) {}
    var negative = false;
    if (i < bytes.len and (bytes[i] == '+' or bytes[i] == '-')) {
        negative = bytes[i] == '-';
        i += 1;
    }
    const rest = bytes[i..];
    if (rest.len >= 8 and std.mem.eql(u8, rest[0..8], "Infinity")) return if (negative) -std.math.inf(f64) else std.math.inf(f64);
    if (rest.len >= 3 and std.mem.eql(u8, rest[0..3], "NaN")) return std.math.nan(f64);
    var j: usize = 0;
    while (j < rest.len and rest[j] >= '0' and rest[j] <= '9') : (j += 1) {}
    const int_digits = j;
    if (j < rest.len and rest[j] == '.') {
        j += 1;
        while (j < rest.len and rest[j] >= '0' and rest[j] <= '9') : (j += 1) {}
    }
    const frac_digits = j - int_digits - @as(usize, if (j > int_digits and rest[int_digits] == '.') 1 else 0);
    if (int_digits == 0 and frac_digits == 0) return std.math.nan(f64);
    var k: usize = j;
    if (k < rest.len and (rest[k] == 'e' or rest[k] == 'E')) {
        var m: usize = k + 1;
        if (m < rest.len and (rest[m] == '+' or rest[m] == '-')) m += 1;
        const exp_start = m;
        while (m < rest.len and rest[m] >= '0' and rest[m] <= '9') : (m += 1) {}
        if (m > exp_start) k = m;
    }
    const num = std.fmt.parseFloat(f64, rest[0..k]) catch |err| {
        if (err == error.Overflow) return if (negative) -std.math.inf(f64) else std.math.inf(f64);
        return std.math.nan(f64);
    };
    return if (negative) -num else num;
}

/// JS `String.prototype.repeat` (mirrors the non-Windows variant).
pub export fn sa_string_repeat(ptr: ?[*]const u8, len: u64, count: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    const n = lenAsUsize(count) catch return 0;
    if (n == 0 or bytes.len == 0) {
        const owned = std.heap.page_allocator.alloc(u8, 0) catch return 0;
        return openOwnedByteBuffer(owned) catch return 0;
    }
    if (bytes.len > std.math.maxInt(usize) / n) return 0;
    const owned = std.heap.page_allocator.alloc(u8, bytes.len * n) catch return 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        std.mem.copyForwards(u8, owned[i * bytes.len ..][0..bytes.len], bytes);
    }
    return openOwnedByteBuffer(owned) catch return 0;
}

pub fn tilePadWin(owned: []u8, pad: []const u8) void {
    var i: usize = 0;
    while (i < owned.len) {
        const n = @min(pad.len, owned.len - i);
        std.mem.copyForwards(u8, owned[i..][0..n], pad[0..n]);
        i += n;
    }
}

/// JS `String.prototype.padStart` (mirrors the non-Windows variant).
pub export fn sa_string_pad_start(ptr: ?[*]const u8, len: u64, target_len: u64, pad_ptr: ?[*]const u8, pad_len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    const pad = constBytes(pad_ptr, pad_len) catch return 0;
    const target = lenAsUsize(target_len) catch return 0;
    if (target <= bytes.len or pad.len == 0) {
        const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 0;
        return openOwnedByteBuffer(owned) catch return 0;
    }
    const owned = std.heap.page_allocator.alloc(u8, target) catch return 0;
    const fill = target - bytes.len;
    tilePadWin(owned[0..fill], pad);
    std.mem.copyForwards(u8, owned[fill..][0..bytes.len], bytes);
    return openOwnedByteBuffer(owned) catch return 0;
}

/// JS `String.prototype.padEnd` (mirrors the non-Windows variant).
pub export fn sa_string_pad_end(ptr: ?[*]const u8, len: u64, target_len: u64, pad_ptr: ?[*]const u8, pad_len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    const pad = constBytes(pad_ptr, pad_len) catch return 0;
    const target = lenAsUsize(target_len) catch return 0;
    if (target <= bytes.len or pad.len == 0) {
        const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 0;
        return openOwnedByteBuffer(owned) catch return 0;
    }
    const owned = std.heap.page_allocator.alloc(u8, target) catch return 0;
    std.mem.copyForwards(u8, owned[0..bytes.len], bytes);
    tilePadWin(owned[bytes.len..], pad);
    return openOwnedByteBuffer(owned) catch return 0;
}

/// JS `String.prototype.replace` / `replaceAll` (mirrors the non-Windows variant).
pub export fn sa_string_replace(hay_ptr: ?[*]const u8, hay_len: u64, ndl_ptr: ?[*]const u8, ndl_len: u64, rep_ptr: ?[*]const u8, rep_len: u64, all: u64) u64 {
    const hay = constBytes(hay_ptr, hay_len) catch return 0;
    const ndl = constBytes(ndl_ptr, ndl_len) catch return 0;
    const rep = constBytes(rep_ptr, rep_len) catch return 0;
    const replace_all = all != 0;
    if (ndl.len == 0) {
        if (!replace_all) {
            const owned = std.heap.page_allocator.alloc(u8, rep.len + hay.len) catch return 0;
            std.mem.copyForwards(u8, owned[0..rep.len], rep);
            std.mem.copyForwards(u8, owned[rep.len..][0..hay.len], hay);
            return openOwnedByteBuffer(owned) catch return 0;
        }
        const slots = std.math.add(usize, hay.len, 1) catch return 0;
        const extra = std.math.mul(usize, rep.len, slots) catch return 0;
        const total_empty = std.math.add(usize, hay.len, extra) catch return 0;
        const owned = std.heap.page_allocator.alloc(u8, total_empty) catch return 0;
        var o: usize = 0;
        for (hay) |byte| {
            std.mem.copyForwards(u8, owned[o..][0..rep.len], rep);
            o += rep.len;
            owned[o] = byte;
            o += 1;
        }
        std.mem.copyForwards(u8, owned[o..][0..rep.len], rep);
        o += rep.len;
        return openOwnedByteBuffer(owned[0..o]) catch return 0;
    }
    if (ndl.len > hay.len) {
        const owned = std.heap.page_allocator.dupe(u8, hay) catch return 0;
        return openOwnedByteBuffer(owned) catch return 0;
    }
    var starts_i: usize = 0;
    var count: usize = 0;
    var i: usize = 0;
    while (i + ndl.len <= hay.len) {
        if (std.mem.eql(u8, hay[i..][0..ndl.len], ndl)) {
            count += 1;
            if (!replace_all) {
                starts_i = i;
                break;
            }
            i += ndl.len;
            continue;
        }
        i += 1;
    }
    if (count == 0) {
        const owned = std.heap.page_allocator.dupe(u8, hay) catch return 0;
        return openOwnedByteBuffer(owned) catch return 0;
    }
    if (!replace_all) {
        const total = std.math.add(usize, hay.len - ndl.len, rep.len) catch return 0;
        const owned = std.heap.page_allocator.alloc(u8, total) catch return 0;
        std.mem.copyForwards(u8, owned[0..starts_i], hay[0..starts_i]);
        std.mem.copyForwards(u8, owned[starts_i..][0..rep.len], rep);
        std.mem.copyForwards(u8, owned[starts_i + rep.len ..], hay[starts_i + ndl.len ..]);
        return openOwnedByteBuffer(owned) catch return 0;
    }
    var total: usize = hay.len;
    i = 0;
    while (i + ndl.len <= hay.len) {
        if (std.mem.eql(u8, hay[i..][0..ndl.len], ndl)) {
            total = std.math.add(usize, total - ndl.len, rep.len) catch return 0;
            i += ndl.len;
        } else {
            i += 1;
        }
    }
    const owned = std.heap.page_allocator.alloc(u8, total) catch return 0;
    var s: usize = 0;
    var o: usize = 0;
    i = 0;
    while (i + ndl.len <= hay.len) {
        if (std.mem.eql(u8, hay[i..][0..ndl.len], ndl)) {
            std.mem.copyForwards(u8, owned[o..][0..(i - s)], hay[s..i]);
            o += i - s;
            std.mem.copyForwards(u8, owned[o..][0..rep.len], rep);
            o += rep.len;
            i += ndl.len;
            s = i;
        } else {
            i += 1;
        }
    }
    std.mem.copyForwards(u8, owned[o..][0..(hay.len - s)], hay[s..]);
    o += hay.len - s;
    return openOwnedByteBuffer(owned[0..o]) catch return 0;
}

/// JS `String.prototype.charCodeAt` (mirrors the non-Windows variant):
/// byte at `idx`, -1 when out of bounds.
pub export fn sa_string_code_point_at(ptr: ?[*]const u8, len: u64, idx: u64) i32 {
    const bytes = constBytes(ptr, len) catch return -1;
    const i = lenAsUsize(idx) catch return -1;
    if (i >= bytes.len) return -1;
    return @as(i32, bytes[i]);
}

/// JS `String.fromCodePoint` (mirrors the non-Windows variant): UTF-8
/// encoding of one scalar; out-of-range yields U+FFFD bytes.
pub export fn sa_string_from_code_point(code: i32) u64 {
    const scalar: u32 = if (code < 0) 0xfffd else @as(u32, @intCast(code));
    const cp: u32 = if (scalar > 0x10ffff or (scalar >= 0xd800 and scalar <= 0xdfff)) 0xfffd else scalar;
    var buf: [4]u8 = undefined;
    const n: usize = if (cp < 0x80) blk: {
        buf[0] = @as(u8, @intCast(cp));
        break :blk 1;
    } else if (cp < 0x800) blk: {
        buf[0] = @as(u8, @intCast(0xc0 | (cp >> 6)));
        buf[1] = @as(u8, @intCast(0x80 | (cp & 0x3f)));
        break :blk 2;
    } else if (cp < 0x10000) blk: {
        buf[0] = @as(u8, @intCast(0xe0 | (cp >> 12)));
        buf[1] = @as(u8, @intCast(0x80 | ((cp >> 6) & 0x3f)));
        buf[2] = @as(u8, @intCast(0x80 | (cp & 0x3f)));
        break :blk 3;
    } else blk: {
        buf[0] = @as(u8, @intCast(0xf0 | (cp >> 18)));
        buf[1] = @as(u8, @intCast(0x80 | ((cp >> 12) & 0x3f)));
        buf[2] = @as(u8, @intCast(0x80 | ((cp >> 6) & 0x3f)));
        buf[3] = @as(u8, @intCast(0x80 | (cp & 0x3f)));
        break :blk 4;
    };
    const owned = std.heap.page_allocator.dupe(u8, buf[0..n]) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

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

pub export fn sa_time_instant_ns() u64 {
    return monotonicNowNs() catch return 0;
}

pub export fn sa_time_unix_s() i64 {
    return sio.timestampSeconds();
}

pub export fn sa_time_unix_ms() i64 {
    return std.Io.Clock.awake.now(sio.io()).toMilliseconds();
}

/// JS `Date.toISOString` shape (mirrors the non-Windows variant).
pub export fn sa_time_iso_from_unix_ms(ms: i64) u64 {
    const ms_per_day: i64 = 86400000;
    var days = @divFloor(ms, ms_per_day);
    var day_ms = @mod(ms, ms_per_day);
    if (day_ms < 0) {
        day_ms += ms_per_day;
        days -= 1;
    }
    const z: i64 = days + 719468;
    const era: i64 = if (z >= 0) @divFloor(z, 146097) else @divFloor(z - 146096, 146097);
    const doe: i64 = z - era * 146097;
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const day: i64 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const month: i64 = if (mp < 10) mp + 3 else mp - 9;
    const year: i64 = if (month <= 2) y + 1 else y;
    const hour: i64 = @divFloor(day_ms, 3600000);
    const minute: i64 = @divFloor(@mod(day_ms, 3600000), 60000);
    const second: i64 = @divFloor(@mod(day_ms, 60000), 1000);
    const milli: i64 = @mod(day_ms, 1000);
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    appendIsoUtcWin(&out, year, month, day, hour, minute, second, milli) catch return 0;
    return openOwnedByteBuffer(out.toOwnedSlice() catch return 0) catch return 0;
}

/// Strict-ISO `Date.parse` (mirrors the non-Windows variant).
pub export fn sa_time_parse_iso(iso_ptr: ?[*]const u8, iso_len: u64, out_ms: ?*i64) i32 {
    const out = out_ms orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const bytes = constBytes(iso_ptr, iso_len) catch |err| return finishErr(err);
    const bad = finish(SA_STD_ERR_INVALID_ARGUMENT);
    var p: usize = 0;
    const take = struct {
        fn digits(b: []const u8, pos: *usize, n: usize) ?i64 {
            if (pos.* + n > b.len) return null;
            var v: i64 = 0;
            for (b[pos.*..][0..n]) |c| {
                if (c < '0' or c > '9') return null;
                v = v * 10 + @as(i64, c - '0');
            }
            pos.* += n;
            return v;
        }
    }.digits;
    const year = take(bytes, &p, 4) orelse return bad;
    if (p >= bytes.len or bytes[p] != '-') return bad;
    p += 1;
    const month = take(bytes, &p, 2) orelse return bad;
    if (p >= bytes.len or bytes[p] != '-') return bad;
    p += 1;
    const day = take(bytes, &p, 2) orelse return bad;
    var hour: i64 = 0;
    var minute: i64 = 0;
    var second: i64 = 0;
    var milli: i64 = 0;
    if (p < bytes.len) {
        if (bytes[p] != 'T' and bytes[p] != 't' and bytes[p] != ' ') return bad;
        p += 1;
        hour = take(bytes, &p, 2) orelse return bad;
        if (p >= bytes.len or bytes[p] != ':') return bad;
        p += 1;
        minute = take(bytes, &p, 2) orelse return bad;
        if (p >= bytes.len or bytes[p] != ':') return bad;
        p += 1;
        second = take(bytes, &p, 2) orelse return bad;
        if (p < bytes.len and bytes[p] == '.') {
            p += 1;
            const fstart = p;
            while (p < bytes.len and bytes[p] >= '0' and bytes[p] <= '9') : (p += 1) {}
            const flen = p - fstart;
            if (flen == 0 or flen > 3) return bad;
            var f: i64 = 0;
            for (bytes[fstart..p]) |c| f = f * 10 + @as(i64, c - '0');
            milli = if (flen == 1) f * 100 else if (flen == 2) f * 10 else f;
        }
    }
    var offset_min: i64 = 0;
    if (p < bytes.len) {
        if (bytes[p] == 'Z' or bytes[p] == 'z') {
            p += 1;
        } else if (bytes[p] == '+' or bytes[p] == '-') {
            const neg = bytes[p] == '-';
            p += 1;
            const oh = take(bytes, &p, 2) orelse return bad;
            if (p >= bytes.len or bytes[p] != ':') return bad;
            p += 1;
            const om = take(bytes, &p, 2) orelse return bad;
            if (oh > 23 or om > 59) return bad;
            offset_min = oh * 60 + om;
            if (neg) offset_min = -offset_min;
        } else {
            return bad;
        }
    }
    if (p != bytes.len) return bad;
    if (month < 1 or month > 12) return bad;
    const leap = @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
    const dim: i64 = switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        else => if (leap) 29 else 28,
    };
    if (day < 1 or day > dim) return bad;
    if (hour > 23 or minute > 59 or second > 59) return bad;
    const y: i64 = if (month <= 2) year - 1 else year;
    const era: i64 = if (y >= 0) @divFloor(y, 400) else @divFloor(y - 399, 400);
    const yoe: i64 = y - era * 400;
    const mp: i64 = @mod(month - 3, 12);
    const doy: i64 = @divFloor(153 * mp + 2, 5) + day - 1;
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    const days: i64 = era * 146097 + doe - 719468;
    out.* = ((days * 86400 + hour * 3600 + minute * 60 + second) * 1000 + milli) - offset_min * 60000;
    return finish(SA_STD_OK);
}

/// Shared civil split (mirrors the non-Windows variant).
pub const CivilPartsWin = struct {
    year: i64,
    month: i64,
    day: i64,
    hour: i64,
    minute: i64,
    second: i64,
    milli: i64,
    days: i64,
};

pub fn civilPartsWin(ms: i64) CivilPartsWin {
    const ms_per_day: i64 = 86400000;
    var days = @divFloor(ms, ms_per_day);
    var day_ms = @mod(ms, ms_per_day);
    if (day_ms < 0) {
        day_ms += ms_per_day;
        days -= 1;
    }
    const z: i64 = days + 719468;
    const era: i64 = if (z >= 0) @divFloor(z, 146097) else @divFloor(z - 146096, 146097);
    const doe: i64 = z - era * 146097;
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const month: i64 = if (mp < 10) mp + 3 else mp - 9;
    return .{
        .year = if (month <= 2) y + 1 else y,
        .month = month,
        .day = doy - @divFloor(153 * mp + 2, 5) + 1,
        .hour = @divFloor(day_ms, 3600000),
        .minute = @divFloor(@mod(day_ms, 3600000), 60000),
        .second = @divFloor(@mod(day_ms, 60000), 1000),
        .milli = @mod(day_ms, 1000),
        .days = days,
    };
}

/// JS Date getters (mirrors the non-Windows variant).
pub export fn sa_time_get_full_year(ms: i64) i64 {
    return civilPartsWin(ms).year;
}

pub export fn sa_time_get_month(ms: i64) i64 {
    return civilPartsWin(ms).month - 1;
}

pub export fn sa_time_get_date(ms: i64) i64 {
    return civilPartsWin(ms).day;
}

pub export fn sa_time_get_hours(ms: i64) i64 {
    return civilPartsWin(ms).hour;
}

pub export fn sa_time_get_minutes(ms: i64) i64 {
    return civilPartsWin(ms).minute;
}

pub export fn sa_time_get_seconds(ms: i64) i64 {
    return civilPartsWin(ms).second;
}

pub export fn sa_time_get_milliseconds(ms: i64) i64 {
    return civilPartsWin(ms).milli;
}

pub export fn sa_time_get_day(ms: i64) i64 {
    const days = civilPartsWin(ms).days;
    return @mod(days + 4, 7);
}

pub const weekdayNamesWin = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
