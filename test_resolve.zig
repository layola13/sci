const std = @import("std");
pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const import_path = "support/index.sa";
    const base_dir = "/home/vscode/projects/sci/tests/unit_framework";
    const candidate = try std.fs.path.join(alloc, &.{ base_dir, import_path });
    std.debug.print("candidate: {s}\n", .{candidate});
    const canonical = std.fs.cwd().realpathAlloc(alloc, candidate) catch |err| {
        std.debug.print("realpathAlloc failed: {}\n", .{err});
        return;
    };
    std.debug.print("canonical: {s}\n", .{canonical});
}
