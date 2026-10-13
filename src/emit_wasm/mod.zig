const std = @import("std");
const encoder = @import("encoder.zig");

pub const Buffer = encoder.Buffer;
pub const writeUleb32 = encoder.writeUleb32;
pub const writeUleb64 = encoder.writeUleb64;
pub const writeSleb32 = encoder.writeSleb32;
pub const writeSleb64 = encoder.writeSleb64;

pub fn writeModuleHeader(writer: *std.Io.Writer) !void {
    try writer.writeAll(std.wasm.magic[0..]);
    try writer.writeAll(std.wasm.version[0..]);
}

test "writeModuleHeader emits wasm magic and version bytes" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    try writeModuleHeader(&aw.writer);
    const items = aw.writer.buffered();
    try std.testing.expectEqual(@as(usize, 8), items.len);
    try std.testing.expectEqualSlices(u8, std.wasm.magic[0..], items[0..4]);
    try std.testing.expectEqualSlices(u8, std.wasm.version[0..], items[4..8]);
}
