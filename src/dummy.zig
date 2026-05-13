const std = @import("std");
const flattener = @import("flattener.zig");
const referee = @import("referee/verifier.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    
    const source = 
        \\@foo(&p: ptr) -> &ptr:
        \\return p
        \\
        \\@main() -> i32:
        \\base = alloc 8
        \\view = call @foo(&base)
        \\store base+0, 1 as i64
        \\val = load view+0 as i64
        \\!view
        \\!val
        \\!base
        \\return 0
    ;
    
    const flat = try flattener.flatten(alloc, source);
    const verified = try referee.verify(alloc, flat.instructions, flat.const_decls);
    std.debug.print("Verified: {s}\n", .{@tagName(verified)});
    if (verified == .trap) {
        std.debug.print("Trap: {s}\n", .{@tagName(verified.trap.trap)});
    }
}
