const std = @import("std");
const flattener = @import("./src/flattener.zig");
const referee = @import("./src/referee.zig");

pub fn main() !void {
    const source =
        \\@helper() -> i32!:
        \\return 7
        \\
        \\@main() -> i32:
        \\res = call @helper()
        \\status = load res+0 as u32
        \\ok = eq status, 0
        \\br ok -> L_OK, L_ERR
        \\L_ERR:
        \\!res
        \\return 0
        \\L_OK:
        \\!res
        \\return 7
    ;
    var flat = try flattener.flatten(std.heap.page_allocator, source);
    defer flat.deinit(std.heap.page_allocator);
    const verified = try referee.verify(std.heap.page_allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |t| {
            std.debug.print("trap: {s}\n", .{t.message});
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.heap.page_allocator);
            for (owned.function_sigs) |fs| {
                std.debug.print("fn {s}: ", .{fs.name});
                for (fs.reg_ids, 0..) |rid, idx| {
                    if (idx != 0) std.debug.print(", ", .{});
                    std.debug.print("{d}:{s}", .{ rid, owned.symbols.lookupName(rid).? });
                }
                std.debug.print("\n", .{});
            }
        },
    }
}
