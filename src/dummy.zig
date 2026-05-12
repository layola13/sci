const std = @import("std");
const flattener = @import("flattener.zig");
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    var file = try std.fs.cwd().openFile("../demos/rosetta/01_hello_world/main.saasm", .{});
    const source = try file.readToEndAlloc(alloc, 1024 * 1024);
    _ = flattener.flatten(alloc, source) catch |e| {
        // do nothing
    };
}
