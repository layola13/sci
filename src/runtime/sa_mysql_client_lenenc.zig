const std = @import("std");

pub const LenencInt = struct { value: u64, is_null: bool, next: usize };

pub fn readLenencInt(bytes: []const u8, pos: usize) ?LenencInt {
    if (pos >= bytes.len) return null;
    const b = bytes[pos];
    switch (b) {
        0x00...0xFA => return .{ .value = b, .is_null = false, .next = pos + 1 },
        0xFB => return .{ .value = 0, .is_null = true, .next = pos + 1 },
        0xFC => {
            if (pos + 3 > bytes.len) return null;
            return .{ .value = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little), .is_null = false, .next = pos + 3 };
        },
        0xFD => {
            if (pos + 4 > bytes.len) return null;
            const v3: u64 = @as(u64, bytes[pos + 1]) | (@as(u64, bytes[pos + 2]) << 8) | (@as(u64, bytes[pos + 3]) << 16);
            return .{ .value = v3, .is_null = false, .next = pos + 4 };
        },
        0xFE => {
            if (pos + 9 > bytes.len) return null;
            return .{ .value = std.mem.readInt(u64, bytes[pos + 1 ..][0..8], .little), .is_null = false, .next = pos + 9 };
        },
        0xFF => return null,
    }
}

pub fn writeLenencInt(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u64) !void {
    if (value < 251) {
        try out.append(a, @intCast(value));
    } else if (value < 65536) {
        try out.append(a, 0xFC);
        var buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &buf, @intCast(value), .little);
        try out.appendSlice(a, &buf);
    } else if (value < 16777216) {
        try out.append(a, 0xFD);
        try out.append(a, @intCast(value & 0xFF));
        try out.append(a, @intCast((value >> 8) & 0xFF));
        try out.append(a, @intCast((value >> 16) & 0xFF));
    } else {
        try out.append(a, 0xFE);
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, value, .little);
        try out.appendSlice(a, &buf);
    }
}

pub fn writeLenencString(out: *std.ArrayList(u8), a: std.mem.Allocator, s: []const u8) !void {
    try writeLenencInt(out, a, s.len);
    try out.appendSlice(a, s);
}
