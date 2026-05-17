const std = @import("std");
const saasm = @import("src/lib.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    
    // Simulate what std_smoke does: first flatten vec.saasm
    const vec_src = try std.fs.cwd().readFileAlloc(alloc, "sa_std/vec.saasm", 1024 * 1024);
    var vec_err = saasm.flattener.ErrorContext{};
    var vec_flat = try saasm.flattener.flattenFileWithContext(alloc, "sa_std/vec.saasm", vec_src, &vec_err);
    vec_flat.deinit(alloc);
    alloc.free(vec_src);

    const heap_src = try std.fs.cwd().readFileAlloc(alloc, "sa_std/binary_heap.saasm", 1024 * 1024 * 10);
    var heap_error_ctx = saasm.flattener.ErrorContext{};
    const heap_flat = try saasm.flattener.flattenFileWithContext(alloc, "sa_std/binary_heap.saasm", heap_src, &heap_error_ctx);
    const heap_verified = saasm.referee.verify(alloc, heap_flat.instructions, heap_flat.const_decls) catch unreachable;
    if (heap_verified == .trap) {
       std.debug.print("TRAP: {s} {s}\n", .{heap_verified.trap.message, std.mem.sliceTo(&heap_verified.trap.source_text_buf, 0)});
    } else {
       std.debug.print("OK!\n", .{});
    }
}
