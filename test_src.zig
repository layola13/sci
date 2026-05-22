const std = @import("std");
pub fn main() !void {
    const source_path = @src().file;
    std.debug.print("source_path: {s}\n", .{source_path});
    var current: []const u8 = source_path;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        current = std.fs.path.dirname(current) orelse {
            std.debug.print("failed to get dirname for {s}\n", .{current});
            return;
        };
        std.debug.print("dirname {}: {s}\n", .{i, current});
    }
}
