const std = @import("std");
pub const EnvVarJson = @import("../sa_std.zig").EnvVarJson;
pub const JsonWriterHandle = @import("../sa_std.zig").JsonWriterHandle;
const SA_JSON_KIND_ARRAY = @import("consts.zig").SA_JSON_KIND_ARRAY;
const SA_JSON_KIND_BOOL = @import("../sa_std.zig").SA_JSON_KIND_BOOL;
const SA_JSON_KIND_FLOAT = @import("consts.zig").SA_JSON_KIND_FLOAT;
const SA_JSON_KIND_INTEGER = @import("consts.zig").SA_JSON_KIND_INTEGER;
const SA_JSON_KIND_NULL = @import("consts.zig").SA_JSON_KIND_NULL;
const SA_JSON_KIND_NUMBER_STRING = @import("consts.zig").SA_JSON_KIND_NUMBER_STRING;
const SA_JSON_KIND_OBJECT = @import("consts.zig").SA_JSON_KIND_OBJECT;
const SA_JSON_KIND_STRING = @import("consts.zig").SA_JSON_KIND_STRING;
const SA_JSON_TOKEN_ALLOCATED_NUMBER = @import("../sa_std.zig").SA_JSON_TOKEN_ALLOCATED_NUMBER;
const SA_JSON_TOKEN_ALLOCATED_STRING = @import("consts.zig").SA_JSON_TOKEN_ALLOCATED_STRING;
const SA_JSON_TOKEN_ARRAY_BEGIN = @import("consts.zig").SA_JSON_TOKEN_ARRAY_BEGIN;
const SA_JSON_TOKEN_ARRAY_END = @import("consts.zig").SA_JSON_TOKEN_ARRAY_END;
const SA_JSON_TOKEN_END_OF_DOCUMENT = @import("consts.zig").SA_JSON_TOKEN_END_OF_DOCUMENT;
const SA_JSON_TOKEN_FALSE = @import("consts.zig").SA_JSON_TOKEN_FALSE;
const SA_JSON_TOKEN_NULL = @import("consts.zig").SA_JSON_TOKEN_NULL;
const SA_JSON_TOKEN_NUMBER = @import("consts.zig").SA_JSON_TOKEN_NUMBER;
const SA_JSON_TOKEN_OBJECT_BEGIN = @import("../sa_std.zig").SA_JSON_TOKEN_OBJECT_BEGIN;
const SA_JSON_TOKEN_OBJECT_END = @import("consts.zig").SA_JSON_TOKEN_OBJECT_END;
const SA_JSON_TOKEN_PARTIAL_NUMBER = @import("../sa_std.zig").SA_JSON_TOKEN_PARTIAL_NUMBER;
const SA_JSON_TOKEN_PARTIAL_STRING = @import("consts.zig").SA_JSON_TOKEN_PARTIAL_STRING;
const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1 = @import("consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1;
const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2 = @import("consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2;
const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3 = @import("consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3;
const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4 = @import("consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4;
const SA_JSON_TOKEN_STRING = @import("consts.zig").SA_JSON_TOKEN_STRING;
const SA_JSON_TOKEN_TRUE = @import("consts.zig").SA_JSON_TOKEN_TRUE;
pub const constBytes = @import("../sa_std.zig").constBytes;

pub fn jsonKindOf(value: std.json.Value) u32 {
    return switch (value) {
        .null => SA_JSON_KIND_NULL,
        .bool => SA_JSON_KIND_BOOL,
        .integer => SA_JSON_KIND_INTEGER,
        .float => SA_JSON_KIND_FLOAT,
        .number_string => SA_JSON_KIND_NUMBER_STRING,
        .string => SA_JSON_KIND_STRING,
        .array => SA_JSON_KIND_ARRAY,
        .object => SA_JSON_KIND_OBJECT,
    };
}

pub fn jsonValueAsF64(value: std.json.Value) !f64 {
    return switch (value) {
        .integer => |inner| @as(f64, @floatFromInt(inner)),
        .float => |inner| {
            if (!std.math.isFinite(inner)) return error.InvalidArgument;
            return inner;
        },
        .number_string => |text| blk: {
            const parsed = std.fmt.parseFloat(f64, text) catch return error.InvalidArgument;
            if (!std.math.isFinite(parsed)) break :blk error.InvalidArgument;
            break :blk parsed;
        },
        else => error.InvalidArgument,
    };
}

pub fn jsonValueAsI64(value: std.json.Value) !i64 {
    return switch (value) {
        .integer => |inner| inner,
        .float => |inner| blk: {
            if (!std.math.isFinite(inner)) break :blk error.InvalidArgument;
            if (@round(inner) != inner) break :blk error.InvalidArgument;
            if (inner > @as(f64, @floatFromInt(std.math.maxInt(i64)))) break :blk error.InvalidArgument;
            if (inner < @as(f64, @floatFromInt(std.math.minInt(i64)))) break :blk error.InvalidArgument;
            break :blk @as(i64, @intFromFloat(inner));
        },
        .number_string => |text| std.fmt.parseInt(i64, text, 10) catch |err| switch (err) {
            error.Overflow, error.InvalidCharacter => return error.InvalidArgument,
        },
        else => error.InvalidArgument,
    };
}

pub fn jsonValueAsBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |inner| inner,
        else => error.InvalidArgument,
    };
}

pub fn jsonValueClone(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    return switch (value) {
        .null => .null,
        .bool => |inner| .{ .bool = inner },
        .integer => |inner| .{ .integer = inner },
        .float => |inner| .{ .float = inner },
        .number_string => |text| .{ .number_string = try allocator.dupe(u8, text) },
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .array => |array| blk: {
            var cloned = std.json.Array.init(allocator);
            errdefer cloned.deinit();
            for (array.items) |item| {
                try cloned.append(try jsonValueClone(allocator, item));
            }
            break :blk .{ .array = cloned };
        },
        .object => |object| blk: {
            var cloned: std.json.ObjectMap = .empty;
            var it = object.iterator();
            while (it.next()) |entry| {
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                try cloned.put(allocator, key_copy, try jsonValueClone(allocator, entry.value_ptr.*));
            }
            break :blk .{ .object = cloned };
        },
    };
}

pub fn jsonWriterObjectFieldLocked(writer_handle: *JsonWriterHandle, key: []const u8) !void {
    if (writer_handle.result_buffer != null) return error.InvalidHandle;
    if (writer_handle.open_depth == 0) return error.InvalidArgument;
    try writer_handle.stream.objectField(key);
}

pub fn tokenTypeOf(token: std.json.Token) u32 {
    return switch (token) {
        .object_begin => SA_JSON_TOKEN_OBJECT_BEGIN,
        .object_end => SA_JSON_TOKEN_OBJECT_END,
        .array_begin => SA_JSON_TOKEN_ARRAY_BEGIN,
        .array_end => SA_JSON_TOKEN_ARRAY_END,
        .true => SA_JSON_TOKEN_TRUE,
        .false => SA_JSON_TOKEN_FALSE,
        .null => SA_JSON_TOKEN_NULL,
        .number => SA_JSON_TOKEN_NUMBER,
        .partial_number => SA_JSON_TOKEN_PARTIAL_NUMBER,
        .allocated_number => SA_JSON_TOKEN_ALLOCATED_NUMBER,
        .string => SA_JSON_TOKEN_STRING,
        .partial_string => SA_JSON_TOKEN_PARTIAL_STRING,
        .partial_string_escaped_1 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1,
        .partial_string_escaped_2 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2,
        .partial_string_escaped_3 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3,
        .partial_string_escaped_4 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4,
        .allocated_string => SA_JSON_TOKEN_ALLOCATED_STRING,
        .end_of_document => SA_JSON_TOKEN_END_OF_DOCUMENT,
    };
}

pub fn tokenTextSlice(token: std.json.Token) ?[]const u8 {
    return switch (token) {
        .number => |slice| slice,
        .partial_number => |slice| slice,
        .string => |slice| slice,
        .partial_string => |slice| slice,
        else => null,
    };
}

pub fn formatInteger(value: anytype, base: u32) ![]u8 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return error.InvalidArgument,
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const n = std.fmt.printInt(&buf, value, actual_base, case, .{});
    const text = buf[0..n];
    return std.heap.page_allocator.dupe(u8, text);
}

pub fn formatFloat(value: f64, precision: u32) ![]u8 {
    var buf: [256]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, "{d:.[1]}", .{ value, @as(usize, @intCast(precision)) });
    return std.heap.page_allocator.dupe(u8, text);
}

pub fn formatBool(value: bool) ![]u8 {
    return std.heap.page_allocator.dupe(u8, if (value) "true" else "false");
}

pub fn formatBytes(bytes: []const u8) ![]u8 {
    return std.heap.page_allocator.dupe(u8, bytes);
}

pub fn jsonStringValue(value: ?std.json.Value) []const u8 {
    const actual = value orelse return "";
    return switch (actual) {
        .string => |text| text,
        else => "",
    };
}

pub fn appendEnvVarJson(pairs: *std.array_list.Managed(EnvVarJson), entry: []const u8) !void {
    const eq = std.mem.indexOfScalar(u8, entry, '=') orelse return;
    if (eq == 0) return;
    try pairs.append(.{ .key = entry[0..eq], .value = entry[eq + 1 ..] });
}

fn hexSimdNibbleVal(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    return null;
}

pub export fn sa_hexdec_simd(in_ptr: ?[*]const u8, in_len: u64, out_ptr: ?[*]u8) u64 {
    const input = constBytes(in_ptr, in_len) catch return 0;
    const n = input.len;
    if (n == 0) return 0;
    const out_p = out_ptr orelse return 0;
    const out = out_p[0 .. n / 2];
    const V32 = @Vector(32, u8);
    const z0: V32 = @splat(@as(u8, '0'));
    const z9: V32 = @splat(@as(u8, '9'));
    const zA: V32 = @splat(@as(u8, 'A'));
    const zF: V32 = @splat(@as(u8, 'F'));
    const za: V32 = @splat(@as(u8, 'a'));
    const zf: V32 = @splat(@as(u8, 'f'));
    const ten: V32 = @splat(@as(u8, 10));
    const one: V32 = @splat(@as(u8, 1));
    const zero: V32 = @splat(@as(u8, 0));
    const four: @Vector(16, u8) = @splat(@as(u8, 4));
    const even_idx: [16]i32 = .{ 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30 };
    const odd_idx: [16]i32 = .{ 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31 };
    var i: usize = 0;
    var w: usize = 0;
    while (i + 32 <= n) {
        const chunk: V32 = input[i..][0..32].*;
        const in09 = @select(u8, chunk >= z0, @select(u8, chunk <= z9, one, zero), zero);
        const inAF = @select(u8, chunk >= zA, @select(u8, chunk <= zF, one, zero), zero);
        const inaf = @select(u8, chunk >= za, @select(u8, chunk <= zf, one, zero), zero);
        const valid = in09 | inAF | inaf;
        if (@reduce(.Min, valid) == 0) break;
        const nib = in09 * (chunk -% z0) + inAF * (chunk -% (zA -% ten)) + inaf * (chunk -% (za -% ten));
        const evens = @shuffle(u8, nib, @as(V32, undefined), even_idx);
        const odds = @shuffle(u8, nib, @as(V32, undefined), odd_idx);
        const joined: @Vector(16, u8) = (evens << four) | odds;
        out[w..][0..16].* = joined;
        i += 32;
        w += 16;
    }
    while (i + 2 <= n) {
        const hi = hexSimdNibbleVal(input[i]) orelse break;
        const lo = hexSimdNibbleVal(input[i + 1]) orelse break;
        out[w] = (hi << 4) | lo;
        i += 2;
        w += 1;
    }
    return @intCast(w);
}

pub export fn sa_mfind_u8(hay_ptr: ?[*]const u8, hay_len: u64, ndl_ptr: ?[*]const u8, ndl_len: u64) u64 {
    const hay = constBytes(hay_ptr, hay_len) catch return hay_len;
    const ndl = constBytes(ndl_ptr, ndl_len) catch return hay.len;
    if (ndl.len == 0) return 0;
    if (ndl.len > hay.len) return hay.len;
    if (std.mem.indexOf(u8, hay, ndl)) |idx| return @intCast(idx);
    return hay.len;
}

fn appendPadded(out: *std.array_list.Managed(u8), val: i64, width: usize) !void {
    if (val < 0) {
        try out.append('-');
        const rest = if (width > 0) width - 1 else 0;
        // Years never approach minInt; negation is safe here.
        return appendPadded(out, -val, rest);
    }
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < width) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

pub fn appendIsoUtc(out: *std.array_list.Managed(u8), year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64, milli: i64) !void {
    try appendPadded(out, year, 4);
    try out.append('-');
    try appendPadded(out, month, 2);
    try out.append('-');
    try appendPadded(out, day, 2);
    try out.append('T');
    try appendPadded(out, hour, 2);
    try out.append(':');
    try appendPadded(out, minute, 2);
    try out.append(':');
    try appendPadded(out, second, 2);
    try out.append('.');
    try appendPadded(out, milli, 3);
    try out.append('Z');
}

pub fn appendTwo(out: *std.array_list.Managed(u8), val: i64) !void {
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < 2) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

pub fn appendFour(out: *std.array_list.Managed(u8), val: i64) !void {
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < 4) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

pub fn formatIpv6Segments(buffer: []u8, segments: *const [8]u16) ![]u8 {
    var longest_start: usize = 8;
    var longest_len: usize = 0;
    var current_start: usize = 0;
    var current_len: usize = 0;
    for (segments.*, 0..) |segment, index| {
        if (segment == 0) {
            if (current_len == 0) current_start = index;
            current_len += 1;
            if (current_len > longest_len) {
                longest_start = current_start;
                longest_len = current_len;
            }
        } else {
            current_len = 0;
        }
    }
    if (longest_len < 2) {
        longest_start = 8;
        longest_len = 0;
    }

    var w: std.Io.Writer = .fixed(buffer);
    var i: usize = 0;
    var abbreviated = false;
    while (i < segments.len) : (i += 1) {
        if (i == longest_start) {
            if (!abbreviated) {
                try w.writeAll(if (i == 0) "::" else ":");
                abbreviated = true;
            }
            i += longest_len - 1;
            continue;
        }
        if (abbreviated) abbreviated = false;
        try w.print("{x}", .{segments[i]});
        if (i != segments.len - 1) try w.writeByte(':');
    }
    return w.buffered();
}

pub fn utf8ScalarAt(bytes: []const u8, index: usize) !struct { scalar: u32, width: usize } {
    if (index >= bytes.len) return error.FileNotFound;
    const b0 = bytes[index];
    if (b0 < 0x80) return .{ .scalar = b0, .width = 1 };

    const width: usize = if (b0 >= 0xc2 and b0 <= 0xdf) 2 else if (b0 >= 0xe0 and b0 <= 0xef) 3 else if (b0 >= 0xf0 and b0 <= 0xf4) 4 else return error.InvalidArgument;
    if (index + width > bytes.len) return error.InvalidArgument;

    const b1 = bytes[index + 1];
    if (b1 < 0x80 or b1 > 0xbf) return error.InvalidArgument;
    if (width == 2) return .{ .scalar = ((@as(u32, b0) & 0x1f) << 6) | (@as(u32, b1) & 0x3f), .width = 2 };

    const b2 = bytes[index + 2];
    if (b2 < 0x80 or b2 > 0xbf) return error.InvalidArgument;
    if (width == 3) {
        if (b0 == 0xe0 and b1 < 0xa0) return error.InvalidArgument;
        if (b0 == 0xed and b1 >= 0xa0) return error.InvalidArgument;
        return .{ .scalar = ((@as(u32, b0) & 0x0f) << 12) | ((@as(u32, b1) & 0x3f) << 6) | (@as(u32, b2) & 0x3f), .width = 3 };
    }

    const b3 = bytes[index + 3];
    if (b3 < 0x80 or b3 > 0xbf) return error.InvalidArgument;
    if (b0 == 0xf0 and b1 < 0x90) return error.InvalidArgument;
    if (b0 == 0xf4 and b1 >= 0x90) return error.InvalidArgument;
    return .{ .scalar = ((@as(u32, b0) & 0x07) << 18) | ((@as(u32, b1) & 0x3f) << 12) | ((@as(u32, b2) & 0x3f) << 6) | (@as(u32, b3) & 0x3f), .width = 4 };
}

pub fn utf8LossyInvalidWidth(bytes: []const u8, index: usize) usize {
    const b0 = bytes[index];
    const expected_width: usize = if (b0 >= 0xc2 and b0 <= 0xdf) 2 else if (b0 >= 0xe0 and b0 <= 0xef) 3 else if (b0 >= 0xf0 and b0 <= 0xf4) 4 else return 1;
    var width: usize = 1;
    while (width < expected_width and index + width < bytes.len) : (width += 1) {
        const byte = bytes[index + width];
        if (byte < 0x80 or byte > 0xbf) break;
    }
    return width;
}

pub fn utf8CharRangeAt(bytes: []const u8, char_index: u64) !struct { start: usize, len: usize, scalar: u32 } {
    var byte_index: usize = 0;
    var current: u64 = 0;
    while (byte_index < bytes.len) {
        const decoded = try utf8ScalarAt(bytes, byte_index);
        if (current == char_index) return .{ .start = byte_index, .len = decoded.width, .scalar = decoded.scalar };
        byte_index += decoded.width;
        current += 1;
    }
    return error.FileNotFound;
}
