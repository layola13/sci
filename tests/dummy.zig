const std = @import("std");
const sig = @import("../src/common/signature.zig");
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    _ = sig.parseFunctionHeader(alloc, "@ffi_wrapper print_wrapper(&msg: ptr, len: i64) -> void:", 0, 0, .ffi_wrapper) catch |e| {
        std.debug.print("Error: {}\n", .{e});
    };
}
