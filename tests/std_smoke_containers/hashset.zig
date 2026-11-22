const std = @import("std");
const common = @import("../std_smoke_common.zig");
const saasm = common.saasm;

test "sa_std hashset helpers are concrete and verifiable" {
    const hashset_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/hashset.sal");
    defer std.testing.allocator.free(hashset_layout);
    try std.testing.expectEqualStrings(
        "#def HashSet_SIZE = 32\n#def HashSet_slots = +0\n#def HashSet_cap = +8\n#def HashSet_len = +16\n#def HashSet_tombs = +24\n\n#def HashSetSlot_SIZE = 32\n#def HashSetSlot_hash = +0\n#def HashSetSlot_key = +8\n#def HashSetSlot_value = +16\n#def HashSetSlot_state = +24\n\n#def HashSet_INITIAL_CAP = 8\n#def HashSet_STATE_EMPTY = 0\n#def HashSet_STATE_FILLED = 1\n#def HashSet_STATE_TOMB = 2\n\n#def HashSet_VALUE_SENTINEL = 1\n",
        hashset_layout,
    );

    const collections_hashset = try common.readFileAlloc(std.testing.allocator, "sa_std/collections/hashset.sa");
    defer std.testing.allocator.free(collections_hashset);
    try std.testing.expect(std.mem.containsAtLeast(u8, collections_hashset, 1, "@import \"../hashset.sa\""));

    const hashset_src = try common.readFileAlloc(std.testing.allocator, "sa_std/hashset.sa");
    defer std.testing.allocator.free(hashset_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"hashset.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"hashmap.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"core/slice.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"alloc/vec.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"vec.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"num.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "EXPAND NUM_U64_CHECKED_MUL __set_drain_bytes_ok_%out_vec"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_with_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_insert"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_contains"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_remove"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_reserve"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_shrink_to_fit"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_RESERVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_SHRINK_TO_FIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_CONTAINS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_REMOVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_DRAIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_EXTRACT_IF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_LIT2"));

    var hashset_error_ctx = saasm.flattener.ErrorContext{};
    var hashset_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/hashset.sa", hashset_src, &hashset_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&hashset_error_ctx) orelse 0;
        std.debug.print("hashset flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer hashset_flat.deinit(std.testing.allocator);
    try std.testing.expect(hashset_flat.instructions.len > 0);
    try std.testing.expect(hashset_flat.function_sigs.len >= 20);

    const hashset_verified = try saasm.referee.verify(std.testing.allocator, hashset_flat.instructions, hashset_flat.const_decls);
    switch (hashset_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 20);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("hashset smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const hashset_fixture = try common.readFileAlloc(std.testing.allocator, "tests/hashset_fixture.sa");
    defer std.testing.allocator.free(hashset_fixture);
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_fixture, 1, "EXPAND SET_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_fixture, 1, "EXPAND SET_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_fixture, 1, "EXPAND SET_RESERVE"));

    var hashset_fixture_error_ctx = saasm.flattener.ErrorContext{};
    var hashset_fixture_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "tests/hashset_fixture.sa", hashset_fixture, &hashset_fixture_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&hashset_fixture_error_ctx) orelse 0;
        std.debug.print("hashset fixture flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer hashset_fixture_flat.deinit(std.testing.allocator);
    const hashset_fixture_verified = try saasm.referee.verify(std.testing.allocator, hashset_fixture_flat.instructions, hashset_fixture_flat.const_decls);
    switch (hashset_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 20);
        },
        .trap => |report| {
            std.debug.print("hashset fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}
