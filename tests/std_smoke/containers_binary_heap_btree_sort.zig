//! binary_heap / btree_map / sort helpers -- split from tests/std_smoke.zig (shared helpers: helpers.zig).
const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const repoRoot = helpers.repoRoot;
const readFileAlloc = helpers.readFileAlloc;
const writeSource = helpers.writeSource;
const runCommand = helpers.runCommand;
const runCommandWithEnvMap = helpers.runCommandWithEnvMap;
const runCommandAnyExit = helpers.runCommandAnyExit;
const NormalizedInstruction = helpers.NormalizedInstruction;
const normalizeInstruction = helpers.normalizeInstruction;
const expectFlattenEquivalent = helpers.expectFlattenEquivalent;
const dumpInstructionTexts = helpers.dumpInstructionTexts;
const flattenFixture = helpers.flattenFixture;

test "sa_std binary_heap helpers are concrete and verifiable" {
    const heap_layout = try readFileAlloc(std.testing.allocator, "sa_std/binary_heap.sal");
    defer std.testing.allocator.free(heap_layout);
    try std.testing.expectEqualStrings(
        "#def BinaryHeap_SIZE = 24\n#def BinaryHeap_buf = +0\n#def BinaryHeap_cap = +8\n#def BinaryHeap_len = +16\n\n#def BinaryHeap_INITIAL_CAP = 8\n#def BinaryHeap_SLOT_SIZE = 8\n",
        heap_layout,
    );

    const collections_binary_heap = try readFileAlloc(std.testing.allocator, "sa_std/collections/binary_heap.sa");
    defer std.testing.allocator.free(collections_binary_heap);
    try std.testing.expectEqualStrings("@import \"../binary_heap.sa\"\n", collections_binary_heap);

    const heap_src = try readFileAlloc(std.testing.allocator, "sa_std/binary_heap.sa");
    defer std.testing.allocator.free(heap_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@import \"core/mem.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@import \"core/slice.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@import \"core/slice.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@import \"alloc/vec.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@import \"vec.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_with_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_try_with_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_reserve"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_reserve_exact"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_try_reserve"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_try_reserve_exact"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_shrink_to"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_shrink_to_fit"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_as_slice"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_as_mut_slice"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_into_vec"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_into_sorted_vec"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_peek"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_try_peek_mut_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_push"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_try_pop"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_append"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_TRY_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_RESERVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_RESERVE_EXACT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_TRY_RESERVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_TRY_RESERVE_EXACT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_SHRINK_TO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_SHRINK_TO_FIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_AS_SLICE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_AS_MUT_SLICE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_INTO_VEC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_INTO_SORTED_VEC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_PEEK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_TRY_PEEK_MUT_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_PEEK_MUT_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_PUSH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_TRY_POP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_DRAIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_APPEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_LIT1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_LIT2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_LIT3"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_FROM_SLICE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_FROM_VEC_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_EXTEND_FROM_SLICE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_EXTEND_FROM_VEC_U64"));

    var heap_error_ctx = saasm.flattener.ErrorContext{};
    var heap_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/binary_heap.sa", heap_src, &heap_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&heap_error_ctx) orelse 0;
        std.debug.print("binary_heap flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer heap_flat.deinit(std.testing.allocator);
    try std.testing.expect(heap_flat.instructions.len > 0);
    try std.testing.expect(heap_flat.function_sigs.len >= 28);

    const heap_verified = try saasm.referee.verify(std.testing.allocator, heap_flat.instructions, heap_flat.const_decls);
    switch (heap_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 28);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            for (heap_flat.instructions, 0..) |inst, i| {
                if (i >= 415 and i <= 425) {
                    std.debug.print("[{d}] {s}\n", .{ i, inst.raw_text });
                }
            }
            std.debug.print(
                "binary_heap smoke verifier trap: {s} (line={d}, source_line={d}, function={s}, text={s}, register={s}, expected={s}, actual={s})\n",
                .{
                    report.message,
                    report.line,
                    report.source_line,
                    std.mem.sliceTo(&report.function_buf, 0),
                    std.mem.sliceTo(&report.source_text_buf, 0),
                    if (report.register) |r| r else std.mem.sliceTo(&report.register_buf, 0),
                    if (report.expected_mask_name) |r| r else "",
                    if (report.actual_mask_name) |r| r else "",
                },
            );
            return error.TestUnexpectedResult;
        },
    }

    const heap_fixture =
        \\@import "sa_std/collections/binary_heap.sa"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND BINARY_HEAP_NEW heap
        \\    EXPAND BINARY_HEAP_PUSH heap, 4
        \\    EXPAND BINARY_HEAP_PUSH heap, 1
        \\    EXPAND BINARY_HEAP_PUSH heap, 7
        \\    EXPAND BINARY_HEAP_PUSH heap, 2
        \\    EXPAND BINARY_HEAP_PUSH heap, 9
        \\    EXPAND BINARY_HEAP_PUSH heap, 3
        \\    EXPAND BINARY_HEAP_PUSH heap, 8
        \\    EXPAND BINARY_HEAP_PUSH heap, 6
        \\    EXPAND BINARY_HEAP_PUSH heap, 5
        \\    EXPAND BINARY_HEAP_LEN len0, heap
        \\    EXPAND BINARY_HEAP_PEEK peek0, heap
        \\    EXPAND BINARY_HEAP_TRY_POP ok0, pop0, heap
        \\    EXPAND BINARY_HEAP_TRY_POP ok1, pop1, heap
        \\    EXPAND BINARY_HEAP_TRY_POP ok2, pop2, heap
        \\    EXPAND BINARY_HEAP_TRY_POP ok3, pop3, heap
        \\    EXPAND BINARY_HEAP_TRY_POP ok4, pop4, heap
        \\    EXPAND BINARY_HEAP_TRY_POP ok5, pop5, heap
        \\    EXPAND BINARY_HEAP_TRY_POP ok6, pop6, heap
        \\    EXPAND BINARY_HEAP_TRY_POP ok7, pop7, heap
        \\    EXPAND BINARY_HEAP_TRY_POP ok8, pop8, heap
        \\    EXPAND BINARY_HEAP_TRY_POP ok_empty, empty_value, heap
        \\    EXPAND BINARY_HEAP_LEN len1, heap
        \\    ok_len0 = eq len0, 9
        \\    ok_peek = eq peek0, 9
        \\    ok0v = eq pop0, 9
        \\    ok1v = eq pop1, 8
        \\    ok2v = eq pop2, 7
        \\    ok3v = eq pop3, 6
        \\    ok4v = eq pop4, 5
        \\    ok5v = eq pop5, 4
        \\    ok6v = eq pop6, 3
        \\    ok7v = eq pop7, 2
        \\    ok8v = eq pop8, 1
        \\    ok_empty_ok = eq ok_empty, 0
        \\    ok_empty_value = eq empty_value, 0
        \\    ok_len1 = eq len1, 0
        \\    ok01 = and ok_len0, ok_peek
        \\    ok02 = and ok01, ok0v
        \\    ok03 = and ok02, ok1v
        \\    ok04 = and ok03, ok2v
        \\    ok05 = and ok04, ok3v
        \\    ok06 = and ok05, ok4v
        \\    ok07 = and ok06, ok5v
        \\    ok08 = and ok07, ok6v
        \\    ok09 = and ok08, ok7v
        \\    ok10 = and ok09, ok8v
        \\    ok11 = and ok10, ok_empty_ok
        \\    ok12 = and ok11, ok_empty_value
        \\    ok = and ok12, ok_len1
        \\    !peek0
        \\    !pop0
        \\    !pop1
        \\    !pop2
        \\    !pop3
        \\    !pop4
        \\    !pop5
        \\    !pop6
        \\    !pop7
        \\    !pop8
        \\    !empty_value
        \\    !ok0
        \\    !ok1
        \\    !ok2
        \\    !ok3
        \\    !ok4
        \\    !ok5
        \\    !ok6
        \\    !ok7
        \\    !ok8
        \\    !ok_empty
        \\    !len0
        \\    !len1
        \\    !ok_len0
        \\    !ok_peek
        \\    !ok0v
        \\    !ok1v
        \\    !ok2v
        \\    !ok3v
        \\    !ok4v
        \\    !ok5v
        \\    !ok6v
        \\    !ok7v
        \\    !ok8v
        \\    !ok_empty_ok
        \\    !ok_empty_value
        \\    !ok_len1
        \\    !ok01
        \\    !ok02
        \\    !ok03
        \\    !ok04
        \\    !ok05
        \\    !ok06
        \\    !ok07
        \\    !ok08
        \\    !ok09
        \\    !ok10
        \\    !ok11
        \\    !ok12
        \\    EXPAND BINARY_HEAP_FREE heap
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
    var heap_fixture_flat = try flattenFixture(std.testing.allocator, "tests/binary_heap_fixture.sa", heap_fixture);
    defer heap_fixture_flat.deinit(std.testing.allocator);
    const heap_fixture_verified = try saasm.referee.verify(std.testing.allocator, heap_fixture_flat.instructions, heap_fixture_flat.const_decls);
    switch (heap_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 31);
        },
        .trap => |report| {
            std.debug.print("binary_heap fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std btree_map helpers are concrete and verifiable" {
    const btree_layout = try readFileAlloc(std.testing.allocator, "sa_std/btree_map.sal");
    defer std.testing.allocator.free(btree_layout);
    try std.testing.expectEqualStrings(
        "#def BTreeMap_SIZE = 24\n#def BTreeMap_entries = +0\n#def BTreeMap_cap = +8\n#def BTreeMap_len = +16\n\n#def BTreeMapEntry_SIZE = 24\n#def BTreeMapEntry_key_ptr = +0\n#def BTreeMapEntry_key_len = +8\n#def BTreeMapEntry_value = +16\n\n#def BTreeMap_INITIAL_CAP = 8\n",
        btree_layout,
    );

    const collections_btree_map = try readFileAlloc(std.testing.allocator, "sa_std/collections/btree_map.sa");
    defer std.testing.allocator.free(collections_btree_map);
    try std.testing.expectEqualStrings("@import \"../btree_map.sa\"\n", collections_btree_map);

    const btree_src = try readFileAlloc(std.testing.allocator, "sa_std/btree_map.sa");
    defer std.testing.allocator.free(btree_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@import \"core/mem.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@import \"core/slice.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@import \"alloc/vec.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_try_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_try_get_key_value"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_get_mut_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_first_entry_mut_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_last_entry_mut_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_try_get_disjoint_mut_ptrs"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_first_key_value"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_last_key_value"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_contains_key"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_remove"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_remove_entry"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_insert"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_insert_old"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_try_insert"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_keys_set"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_values_vec"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_value_mut_ptrs_vec"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_pop_first"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_pop_last"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_append"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_split_off"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_range"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_TRY_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_GET_KEY_VALUE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_GET_MUT_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_FIRST_ENTRY_MUT_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_LAST_ENTRY_MUT_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_TRY_GET_DISJOINT_MUT_PTRS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_FIRST_KEY_VALUE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_LAST_KEY_VALUE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_CONTAINS_KEY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_REMOVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_REMOVE_ENTRY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_INSERT_OLD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_TRY_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_KEYS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_VALUES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_VALUES_MUT_PTRS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_POP_FIRST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_POP_LAST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_APPEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_SPLIT_OFF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_RANGE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_LIT1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_LIT2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_LIT3"));

    const btree_set_src = try readFileAlloc(std.testing.allocator, "sa_std/btree_set.sa");
    defer std.testing.allocator.free(btree_set_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_range"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_union"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_intersection"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_difference"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "@export sa_btree_set_symmetric_difference"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_FIRST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_LAST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_TAKE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_REPLACE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_POP_FIRST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_POP_LAST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_IS_DISJOINT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_IS_SUBSET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_IS_SUPERSET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_APPEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_SPLIT_OFF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_RANGE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_UNION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_INTERSECTION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_DIFFERENCE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_SYMMETRIC_DIFFERENCE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_LIT1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_LIT2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_set_src, 1, "[MACRO] BTREE_SET_LIT3"));

    var btree_error_ctx = saasm.flattener.ErrorContext{};
    var btree_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/btree_map.sa", btree_src, &btree_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&btree_error_ctx) orelse 0;
        std.debug.print("btree_map flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer btree_flat.deinit(std.testing.allocator);
    try std.testing.expect(btree_flat.instructions.len > 0);
    try std.testing.expect(btree_flat.function_sigs.len >= 35);

    const btree_verified = try saasm.referee.verify(std.testing.allocator, btree_flat.instructions, btree_flat.const_decls);
    switch (btree_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 35);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print(
                "btree_map smoke verifier trap: {s} (line={d}, source_line={d}, function={s}, text={s}, register={s}, expected={s}, actual={s})\n",
                .{
                    report.message,
                    report.line,
                    report.source_line,
                    std.mem.sliceTo(&report.function_buf, 0),
                    std.mem.sliceTo(&report.source_text_buf, 0),
                    if (report.register) |r| r else std.mem.sliceTo(&report.register_buf, 0),
                    if (report.expected_mask_name) |r| r else "",
                    if (report.actual_mask_name) |r| r else "",
                },
            );
            return error.TestUnexpectedResult;
        },
    }

    const btree_fixture =
        \\@import "sa_std/core/slice.sal"
        \\@import "sa_std/core/slice.sa"
        \\@import "sa_std/collections/btree_map.sa"
        \\
        \\@const KEY_ALPHA = utf8:"alpha"
        \\@const KEY_BRAVO = utf8:"bravo"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    map = 0 as ptr
        \\    alpha = alloc Slice_SIZE
        \\    bravo = alloc Slice_SIZE
        \\    lookup = alloc Slice_SIZE
        \\    EXPAND SLICE_NEW alpha, &KEY_ALPHA, 5
        \\    EXPAND SLICE_NEW bravo, &KEY_BRAVO, 5
        \\    EXPAND SLICE_NEW lookup, &KEY_ALPHA, 5
        \\    EXPAND BTREE_MAP_NEW map
        \\    EXPAND BTREE_MAP_IS_EMPTY empty0, map
        \\    EXPAND BTREE_MAP_INSERT map, bravo, 2
        \\    EXPAND BTREE_MAP_INSERT map, alpha, 1
        \\    EXPAND BTREE_MAP_INSERT map, lookup, 3
        \\    EXPAND BTREE_MAP_CONTAINS_KEY has_alpha, map, alpha
        \\    EXPAND BTREE_MAP_CONTAINS_KEY has_lookup, map, lookup
        \\    value_alpha = call @sa_btree_map_get(&map, &alpha)
        \\    value_bravo = call @sa_btree_map_get(&map, &bravo)
        \\    removed_alpha = call @sa_btree_map_remove(&map, &alpha)
        \\    EXPAND BTREE_MAP_CONTAINS_KEY has_alpha_after, map, alpha
        \\    len = call @sa_btree_map_len(&map)
        \\    EXPAND BTREE_MAP_CLEAR map
        \\    EXPAND BTREE_MAP_IS_EMPTY empty1, map
        \\    ok_alpha = eq value_alpha, 3
        \\    ok_bravo = eq value_bravo, 2
        \\    ok_removed = ne removed_alpha, 0
        \\    ok_len = eq len, 1
        \\    ok_empty0 = eq empty0, 1
        \\    ok_empty1 = eq empty1, 1
        \\    ok_has_alpha = eq has_alpha, 1
        \\    ok_has_lookup = eq has_lookup, 1
        \\    ok_has_alpha_after = eq has_alpha_after, 0
        \\    ok01 = and ok_alpha, ok_bravo
        \\    ok02 = and ok01, ok_removed
        \\    ok03 = and ok02, ok_len
        \\    ok04 = and ok03, ok_empty0
        \\    ok05 = and ok04, ok_empty1
        \\    ok06 = and ok05, ok_has_alpha
        \\    ok07 = and ok06, ok_has_lookup
        \\    ok = and ok07, ok_has_alpha_after
        \\    !ok_has_alpha_after
        \\    !ok_has_lookup
        \\    !ok_has_alpha
        \\    !ok_empty1
        \\    !ok_empty0
        \\    !ok_len
        \\    !ok_removed
        \\    !ok_bravo
        \\    !ok_alpha
        \\    !len
        \\    !value_bravo
        \\    !value_alpha
        \\    !empty1
        \\    !empty0
        \\    !removed_alpha
        \\    !has_alpha_after
        \\    !has_lookup
        \\    !has_alpha
        \\    !lookup
        \\    !bravo
        \\    !alpha
        \\    EXPAND BTREE_MAP_FREE map
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
    var btree_fixture_flat = try flattenFixture(std.testing.allocator, "tests/btree_map_fixture.sa", btree_fixture);
    defer btree_fixture_flat.deinit(std.testing.allocator);
    const btree_fixture_verified = try saasm.referee.verify(std.testing.allocator, btree_fixture_flat.instructions, btree_fixture_flat.const_decls);
    switch (btree_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 28);
        },
        .trap => |report| {
            std.debug.print("btree_map fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std sort helpers are concrete and verifiable" {
    const sort_src = try readFileAlloc(std.testing.allocator, "sa_std/sort.sa");
    defer std.testing.allocator.free(sort_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@import \"core/mem.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "[MACRO] QSORT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_swap_bytes"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_partition_bounds"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_qsort_bounds"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_qsort_len"));

    var sort_flat = try flattenFixture(std.testing.allocator, "sa_std/sort.sa", sort_src);
    defer sort_flat.deinit(std.testing.allocator);
    try std.testing.expect(sort_flat.instructions.len > 0);
    try std.testing.expect(sort_flat.function_sigs.len >= 4);
}
