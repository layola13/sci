const std = @import("std");

pub const Buffer = std.ArrayList(u8);

fn writeUnsignedLeb128(writer: anytype, value: u64) !void {
    var remaining = value;
    while (true) {
        const byte: u8 = @intCast(remaining & 0x7f);
        remaining >>= 7;
        if (remaining == 0) {
            try writer.writeByte(byte);
            return;
        }
        try writer.writeByte(byte | 0x80);
    }
}

fn writeSignedLeb128(writer: anytype, value: i64) !void {
    var remaining = value;
    while (true) {
        const raw: u64 = @bitCast(remaining);
        const byte: u8 = @intCast(raw & 0x7f);
        const sign_bit_set = (byte & 0x40) != 0;
        remaining >>= 7;
        const done = (remaining == 0 and !sign_bit_set) or (remaining == -1 and sign_bit_set);
        if (done) {
            try writer.writeByte(byte);
            return;
        }
        try writer.writeByte(byte | 0x80);
    }
}

pub fn writeUleb32(writer: anytype, value: u32) !void {
    try writeUnsignedLeb128(writer, value);
}

pub fn writeUleb64(writer: anytype, value: u64) !void {
    try writeUnsignedLeb128(writer, value);
}

pub fn writeSleb32(writer: anytype, value: i32) !void {
    try writeSignedLeb128(writer, value);
}

pub fn writeSleb64(writer: anytype, value: i64) !void {
    try writeSignedLeb128(writer, value);
}

fn expectEncoding(comptime encode_fn: anytype, value: anytype, expected: []const u8) !void {
    var buffer = Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    try encode_fn(buffer.writer(), value);
    try std.testing.expectEqualSlices(u8, expected, buffer.items);
}

test "unsigned leb128 encodes 32-bit and 64-bit values" {
    try expectEncoding(writeUleb32, @as(u32, 0), &[_]u8{0x00});
    try expectEncoding(writeUleb32, @as(u32, 1), &[_]u8{0x01});
    try expectEncoding(writeUleb32, @as(u32, 127), &[_]u8{0x7f});
    try expectEncoding(writeUleb32, @as(u32, 128), &[_]u8{0x80, 0x01});
    try expectEncoding(writeUleb32, @as(u32, 624485), &[_]u8{ 0xe5, 0x8e, 0x26 });
    try expectEncoding(writeUleb64, @as(u64, 1) << 63, &[_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 });
}

test "signed leb128 encodes 32-bit and 64-bit values" {
    try expectEncoding(writeSleb32, @as(i32, 0), &[_]u8{0x00});
    try expectEncoding(writeSleb32, @as(i32, 1), &[_]u8{0x01});
    try expectEncoding(writeSleb32, @as(i32, -1), &[_]u8{0x7f});
    try expectEncoding(writeSleb32, @as(i32, -624485), &[_]u8{ 0x9b, 0xf1, 0x59 });
    try expectEncoding(writeSleb64, std.math.minInt(i64), &[_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x7f });
}
