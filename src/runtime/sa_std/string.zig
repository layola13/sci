const std = @import("std");
const constBytes = @import("../sa_std.zig").constBytes;
const lenAsUsize = @import("../sa_std.zig").lenAsUsize;
const openOwnedBuffer = @import("../sa_std.zig").openOwnedBuffer;
const stringConcat = @import("../sa_std.zig").stringConcat;
const tilePad = @import("../sa_std.zig").tilePad;

pub export fn sa_string_concat(left_ptr: ?[*]const u8, left_len: u64, right_ptr: ?[*]const u8, right_len: u64) u64 {
    const left = constBytes(left_ptr, left_len) catch return 0;
    const right = constBytes(right_ptr, right_len) catch return 0;
    const owned = stringConcat(left, right) catch return 0;
    return openOwnedBuffer(owned) catch return 0;
}

pub export fn sa_string_from_char_code(code: i32) u64 {
    const byte: u8 = @truncate(@as(u32, @bitCast(code)));
    const owned = std.heap.page_allocator.alloc(u8, 1) catch return 0;
    owned[0] = byte;
    return openOwnedBuffer(owned) catch return 0;
}

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

pub export fn sa_string_starts_with(hay_ptr: ?[*]const u8, hay_len: u64, ndl_ptr: ?[*]const u8, ndl_len: u64) i32 {
    const hay = constBytes(hay_ptr, hay_len) catch return 0;
    const ndl = constBytes(ndl_ptr, ndl_len) catch return 0;
    if (ndl.len > hay.len) return 0;
    return if (std.mem.eql(u8, hay[0..ndl.len], ndl)) 1 else 0;
}

pub export fn sa_string_ends_with(hay_ptr: ?[*]const u8, hay_len: u64, ndl_ptr: ?[*]const u8, ndl_len: u64) i32 {
    const hay = constBytes(hay_ptr, hay_len) catch return 0;
    const ndl = constBytes(ndl_ptr, ndl_len) catch return 0;
    if (ndl.len > hay.len) return 0;
    return if (std.mem.eql(u8, hay[hay.len - ndl.len ..], ndl)) 1 else 0;
}

pub export fn sa_string_to_lower_ascii(ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    const owned = std.heap.page_allocator.alloc(u8, bytes.len) catch return 0;
    for (bytes, 0..) |byte, i| {
        owned[i] = if (byte >= 'A' and byte <= 'Z') byte + ('a' - 'A') else byte;
    }
    return openOwnedBuffer(owned) catch return 0;
}

pub export fn sa_string_to_upper_ascii(ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    const owned = std.heap.page_allocator.alloc(u8, bytes.len) catch return 0;
    for (bytes, 0..) |byte, i| {
        owned[i] = if (byte >= 'a' and byte <= 'z') byte - ('a' - 'A') else byte;
    }
    return openOwnedBuffer(owned) catch return 0;
}

pub export fn sa_string_repeat(ptr: ?[*]const u8, len: u64, count: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    const n = lenAsUsize(count) catch return 0;
    if (n == 0 or bytes.len == 0) {
        const owned = std.heap.page_allocator.alloc(u8, 0) catch return 0;
        return openOwnedBuffer(owned) catch return 0;
    }
    if (bytes.len > std.math.maxInt(usize) / n) return 0;
    const owned = std.heap.page_allocator.alloc(u8, bytes.len * n) catch return 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        std.mem.copyForwards(u8, owned[i * bytes.len ..][0..bytes.len], bytes);
    }
    return openOwnedBuffer(owned) catch return 0;
}

pub export fn sa_string_pad_start(ptr: ?[*]const u8, len: u64, target_len: u64, pad_ptr: ?[*]const u8, pad_len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    const pad = constBytes(pad_ptr, pad_len) catch return 0;
    const target = lenAsUsize(target_len) catch return 0;
    if (target <= bytes.len or pad.len == 0) {
        const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 0;
        return openOwnedBuffer(owned) catch return 0;
    }
    const owned = std.heap.page_allocator.alloc(u8, target) catch return 0;
    const fill = target - bytes.len;
    tilePad(owned[0..fill], pad);
    std.mem.copyForwards(u8, owned[fill..][0..bytes.len], bytes);
    return openOwnedBuffer(owned) catch return 0;
}

pub export fn sa_string_pad_end(ptr: ?[*]const u8, len: u64, target_len: u64, pad_ptr: ?[*]const u8, pad_len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    const pad = constBytes(pad_ptr, pad_len) catch return 0;
    const target = lenAsUsize(target_len) catch return 0;
    if (target <= bytes.len or pad.len == 0) {
        const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 0;
        return openOwnedBuffer(owned) catch return 0;
    }
    const owned = std.heap.page_allocator.alloc(u8, target) catch return 0;
    std.mem.copyForwards(u8, owned[0..bytes.len], bytes);
    tilePad(owned[bytes.len..], pad);
    return openOwnedBuffer(owned) catch return 0;
}

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
            return openOwnedBuffer(owned) catch return 0;
        }
        // "abc" -> "XaXbXcX": hay.len + 1 slots (checked arithmetic).
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
        return openOwnedBuffer(owned[0..o]) catch return 0;
    }
    if (ndl.len > hay.len) {
        const owned = std.heap.page_allocator.dupe(u8, hay) catch return 0;
        return openOwnedBuffer(owned) catch return 0;
    }
    // Locate match starts (first only, or all non-overlapping).
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
        return openOwnedBuffer(owned) catch return 0;
    }
    if (!replace_all) {
        const total = std.math.add(usize, hay.len - ndl.len, rep.len) catch return 0;
        const owned = std.heap.page_allocator.alloc(u8, total) catch return 0;
        std.mem.copyForwards(u8, owned[0..starts_i], hay[0..starts_i]);
        std.mem.copyForwards(u8, owned[starts_i..][0..rep.len], rep);
        std.mem.copyForwards(u8, owned[starts_i + rep.len ..], hay[starts_i + ndl.len ..]);
        return openOwnedBuffer(owned) catch return 0;
    }
    // Second pass emits with all matches swapped (checked arithmetic).
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
    return openOwnedBuffer(owned[0..o]) catch return 0;
}

pub export fn sa_string_code_point_at(ptr: ?[*]const u8, len: u64, idx: u64) i32 {
    const bytes = constBytes(ptr, len) catch return -1;
    const i = lenAsUsize(idx) catch return -1;
    if (i >= bytes.len) return -1;
    return @as(i32, bytes[i]);
}

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
    return openOwnedBuffer(owned) catch return 0;
}
