const std = @import("std");
const common = @import("../std_smoke_common.zig");
const saasm = common.saasm;
const flattenFixture = @import("helpers.zig").flattenFixture;

test "sa_std deque and binary heap capacity arithmetic is checked" {
    const deque_src = try common.readFileAlloc(std.testing.allocator, "sa_std/collections/deque/vec_deque.sa");
    defer std.testing.allocator.free(deque_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@import \"../../alloc/vec.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@import \"../../num.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "EXPAND NUM_U64_CHECKED_MUL with_cap_bytes_ok, bytes, capacity, VecDeque_SLOT_SIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "EXPAND NUM_U64_CHECKED_ADD next_cap_ok, next_cap, cap, cap"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "EXPAND NUM_U64_CHECKED_ADD reserve_needed_ok, needed, len, additional"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "EXPAND NUM_U64_CHECKED_MUL clear_bytes_ok, bytes, cap, VecDeque_SLOT_SIZE"));

    var deque_flat = try flattenFixture(std.testing.allocator, "sa_std/collections/deque/vec_deque.sa", deque_src);
    defer deque_flat.deinit(std.testing.allocator);
    try std.testing.expect(deque_flat.instructions.len > 0);
    const deque_verified = try saasm.referee.verify(std.testing.allocator, deque_flat.instructions, deque_flat.const_decls);
    switch (deque_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 20);
        },
        .trap => |report| {
            std.debug.print("vec_deque smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const heap_src = try common.readFileAlloc(std.testing.allocator, "sa_std/collections/heap/binary_heap.sa");
    defer std.testing.allocator.free(heap_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@import \"../../num.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "EXPAND NUM_U64_CHECKED_ADD next_cap_ok, next_cap, cap, cap"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "EXPAND NUM_U64_CHECKED_MUL bytes_ok, bytes, target_cap, BinaryHeap_SLOT_SIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "EXPAND NUM_U64_CHECKED_ADD reserve_needed_ok, needed, len, additional"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "EXPAND NUM_U64_CHECKED_MUL new_bytes_ok, new_bytes, next_cap, BinaryHeap_SLOT_SIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "EXPAND NUM_U64_CHECKED_MUL clear_bytes_ok, bytes, cap, BinaryHeap_SLOT_SIZE"));

    var heap_flat = try flattenFixture(std.testing.allocator, "sa_std/collections/heap/binary_heap.sa", heap_src);
    defer heap_flat.deinit(std.testing.allocator);
    try std.testing.expect(heap_flat.instructions.len > 0);
    const heap_verified = try saasm.referee.verify(std.testing.allocator, heap_flat.instructions, heap_flat.const_decls);
    switch (heap_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 20);
        },
        .trap => |report| {
            std.debug.print("binary_heap smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}
