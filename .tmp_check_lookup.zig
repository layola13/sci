const std = @import("std");
const plugin_api = @import("src/plugin_api.zig");

pub fn main() !void {
    var lib = try std.DynLib.open("/home/vscode/projects/sci/.tmp_plugin_check/libalpha.so");
    defer lib.close();
    const ptr = lib.lookup(plugin_api.DescriptorPtr, "saasm_plugin_descriptor_v1") orelse return error.Missing;
    const addr = @intFromPtr(ptr);
    std.debug.print("addr=0x{x}\n", .{addr});
    const maps = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/proc/self/maps", 64 * 1024);
    defer std.heap.page_allocator.free(maps);
    var it = std.mem.splitScalar(u8, maps, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        var parts_it = std.mem.splitScalar(u8, line, ' ');
        const range = parts_it.next() orelse continue;
        const perm = parts_it.next() orelse continue;
        if (std.mem.indexOf(u8, line, "libalpha.so") == null) continue;
        const dash = std.mem.indexOfScalar(u8, range, '-') orelse continue;
        const start = try std.fmt.parseInt(usize, range[0..dash], 16);
        const end = try std.fmt.parseInt(usize, range[dash+1..], 16);
        if (addr >= start and addr < end) {
            std.debug.print("HIT {s} {s}\n", .{ perm, line });
        } else {
            std.debug.print("MISS {s} {s}\n", .{ perm, line });
        }
    }
}
