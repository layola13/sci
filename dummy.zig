const std = @import("std");
const classifier = @import("src/flattener/line_classifier.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    var file = try std.fs.cwd().openFile("demos/rosetta/01_hello_world/main.sa", .{});
    const source = try file.readToEndAlloc(alloc, 1024 * 1024);
    
    var it = std.mem.splitScalar(u8, source, '\n');
    var i: usize = 1;
    while (it.next()) |line| : (i += 1) {
        const classified = classifier.classifyLine(line);
        if (classified.kind == .unknown) {
            std.debug.print("Line {d} UNKNOWN: {s}\n", .{i, line});
        }
    }
}
