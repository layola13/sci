const std = @import("std");

pub const TranslateError = error{
    OutOfMemory,
    UnsupportedBitcodeInput,
};

pub fn translateBitcodeFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    _ = allocator;
    _ = path;
    return TranslateError.UnsupportedBitcodeInput;
}

test "bc2sa is bitcode-only and rejects input until importer is implemented" {
    try std.testing.expectError(
        TranslateError.UnsupportedBitcodeInput,
        translateBitcodeFile(std.testing.allocator, "input.bc"),
    );
}
