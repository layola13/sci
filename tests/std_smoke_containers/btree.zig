const std = @import("std");
const common = @import("../std_smoke_common.zig");
const saasm = common.saasm;
const flattenFixture = @import("helpers.zig").flattenFixture;

test "sa_std btree_set helpers are concrete and verifiable" {
    const btree_set_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/collections/btree/btree_set.sal");
    defer std.testing.allocator.free(btree_set_layout);
    try std.testing.expectEqualStrings(
        "#def BTreeSet_SIZE = 24\n#def BTreeSet_entries = +0\n#def BTreeSet_cap = +8\n#def BTreeSet_len = +16\n\n#def BTreeSet_INITIAL_CAP = 8\n",
        btree_set_layout,
    );

    const collections_btree_set = try common.readFileAlloc(std.testing.allocator, "sa_std/collections/btree_set.sa");
    defer std.testing.allocator.free(collections_btree_set);
    try std.testing.expect(std.mem.containsAtLeast(u8, collections_btree_set, 1, "@import \"btree/btree_set.sa\""));

    const btree_set_src = try common.readFileAlloc(std.testing.allocator, "sa_std/collections/btree/btree_set.sa");
    defer std.testing.allocator.free(btree_set_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@import \"btree_set.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@import \"btree_map.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_contains"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_first"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_last"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_take"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_replace"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_pop_first"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_pop_last"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_is_subset"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_is_superset"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_is_disjoint"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_append"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_split_off"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_insert"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_remove"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_CONTAINS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_FIRST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_LAST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_REMOVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_TAKE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_REPLACE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_POP_FIRST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_POP_LAST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_IS_DISJOINT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_IS_SUBSET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_IS_SUPERSET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_APPEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_SPLIT_OFF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_LIT2"));

    const btree_map_src = try common.readFileAlloc(std.testing.allocator, "sa_std/collections/btree/btree_map.sa");
    defer std.testing.allocator.free(btree_map_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_map_src, 1, "@import \"../../num.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_map_src, 1, "EXPAND NUM_U64_CHECKED_ADD next_cap_ok, next_cap, old_cap, old_cap"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_map_src, 1, "EXPAND NUM_U64_CHECKED_MUL new_bytes_ok, new_bytes, next_cap, BTreeMapEntry_SIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_map_src, 1, "EXPAND NUM_U64_CHECKED_MUL clear_bytes_ok, bytes, cap, BTreeMapEntry_SIZE"));

    const hashmap_src = try common.readFileAlloc(std.testing.allocator, "sa_std/collections/hashmap/hashmap.sa");
    defer std.testing.allocator.free(hashmap_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"../../core/slice.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"../../alloc/vec.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"../../collections/vec/vec.sa\""));

    var btree_set_error_ctx = saasm.flattener.ErrorContext{};
    var btree_set_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/collections/btree/btree_set.sa", btree_set_src, &btree_set_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&btree_set_error_ctx) orelse 0;
        std.debug.print("btree_set flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer btree_set_flat.deinit(std.testing.allocator);
    try std.testing.expect(btree_set_flat.instructions.len > 0);
    try std.testing.expect(btree_set_flat.function_sigs.len >= 47);

    const btree_set_verified = try saasm.referee.verify(std.testing.allocator, btree_set_flat.instructions, btree_set_flat.const_decls);
    switch (btree_set_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 47);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("btree_set smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const btree_set_fixture =
        \\@import "sa_std/core/slice.sal"
        \\@import "sa_std/core/slice.sa"
        \\@import "sa_std/collections/btree_set.sa"
        \\
        \\@const KEY_ALPHA = utf8:"alpha"
        \\@const KEY_BRAVO = utf8:"bravo"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    set = 0 as ptr
        \\    alpha = alloc Slice_SIZE
        \\    bravo = alloc Slice_SIZE
        \\    lookup = alloc Slice_SIZE
        \\    EXPAND SLICE_NEW alpha, &KEY_ALPHA, 5
        \\    EXPAND SLICE_NEW bravo, &KEY_BRAVO, 5
        \\    EXPAND SLICE_NEW lookup, &KEY_ALPHA, 5
        \\    EXPAND BTREE_SET_NEW set
        \\    EXPAND BTREE_SET_IS_EMPTY empty0, set
        \\    EXPAND BTREE_SET_INSERT insert_alpha, set, alpha
        \\    EXPAND BTREE_SET_INSERT insert_alpha_again, set, lookup
        \\    EXPAND BTREE_SET_INSERT insert_bravo, set, bravo
        \\    EXPAND BTREE_SET_CONTAINS has_alpha, set, alpha
        \\    EXPAND BTREE_SET_CONTAINS has_lookup, set, lookup
        \\    EXPAND BTREE_SET_REMOVE removed_alpha, set, alpha
        \\    EXPAND BTREE_SET_CONTAINS has_alpha_after, set, alpha
        \\    EXPAND BTREE_SET_LEN len, set
        \\    EXPAND BTREE_SET_CLEAR set
        \\    EXPAND BTREE_SET_IS_EMPTY empty1, set
        \\    ok_empty0 = eq empty0, 1
        \\    ok_insert_alpha = eq insert_alpha, 1
        \\    ok_insert_alpha_again = eq insert_alpha_again, 0
        \\    ok_insert_bravo = eq insert_bravo, 1
        \\    ok_has_alpha = eq has_alpha, 1
        \\    ok_has_lookup = eq has_lookup, 1
        \\    ok_removed_alpha = eq removed_alpha, 1
        \\    ok_has_alpha_after = eq has_alpha_after, 0
        \\    ok_len = eq len, 1
        \\    ok_empty1 = eq empty1, 1
        \\    ok01 = and ok_empty0, ok_insert_alpha
        \\    ok02 = and ok01, ok_insert_alpha_again
        \\    ok03 = and ok02, ok_insert_bravo
        \\    ok04 = and ok03, ok_has_alpha
        \\    ok05 = and ok04, ok_has_lookup
        \\    ok06 = and ok05, ok_removed_alpha
        \\    ok07 = and ok06, ok_has_alpha_after
        \\    ok08 = and ok07, ok_len
        \\    ok = and ok08, ok_empty1
        \\    !empty0
        \\    !insert_alpha
        \\    !insert_alpha_again
        \\    !insert_bravo
        \\    !has_alpha
        \\    !has_lookup
        \\    !removed_alpha
        \\    !has_alpha_after
        \\    !len
        \\    !empty1
        \\    !ok_empty0
        \\    !ok_insert_alpha
        \\    !ok_insert_alpha_again
        \\    !ok_insert_bravo
        \\    !ok_has_alpha
        \\    !ok_has_lookup
        \\    !ok_removed_alpha
        \\    !ok_has_alpha_after
        \\    !ok_len
        \\    !ok_empty1
        \\    !ok01
        \\    !ok02
        \\    !ok03
        \\    !ok04
        \\    !ok05
        \\    !ok06
        \\    !ok07
        \\    !ok08
        \\    !lookup
        \\    !bravo
        \\    !alpha
        \\    EXPAND BTREE_SET_FREE set
        \\    br ok -> L_OK, L_ERR
        \\
        \\L_OK:
        \\    !ok
        \\    return 0
        \\
        \\L_ERR:
        \\    !ok
        \\    return 1
    ;
    var btree_set_fixture_flat = try flattenFixture(std.testing.allocator, "tests/btree_set_fixture.sa", btree_set_fixture);
    defer btree_set_fixture_flat.deinit(std.testing.allocator);
    const btree_set_fixture_verified = try saasm.referee.verify(std.testing.allocator, btree_set_fixture_flat.instructions, btree_set_fixture_flat.const_decls);
    switch (btree_set_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 48);
        },
        .trap => |report| {
            std.debug.print("btree_set fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}
