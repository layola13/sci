//! hashmap / hashset / vec_deque helpers -- split from tests/std_smoke.zig (shared helpers: helpers.zig).
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

test "sa_std hashmap helpers are concrete and verifiable" {
    const hashmap_layout = try readFileAlloc(std.testing.allocator, "sa_std/hashmap.sal");
    defer std.testing.allocator.free(hashmap_layout);
    try std.testing.expectEqualStrings(
        "#def HashMap_SIZE = 40\n#def HashMap_slots = +0\n#def HashMap_cap = +8\n#def HashMap_len = +16\n#def HashMap_tombs = +24\n#def HashMap_seed = +32\n\n#def HashMapSlot_SIZE = 32\n#def HashMapSlot_hash = +0\n#def HashMapSlot_key = +8\n#def HashMapSlot_value = +16\n#def HashMapSlot_state = +24\n\n#def HashMap_INITIAL_CAP = 8\n#def HashMap_STATE_EMPTY = 0\n#def HashMap_STATE_FILLED = 1\n#def HashMap_STATE_TOMB = 2\n\n#def HashMap_FNV_OFFSET = -3750763034362895579\n#def HashMap_FNV_PRIME = 1099511628211\n",
        hashmap_layout,
    );

    const collections_hashmap = try readFileAlloc(std.testing.allocator, "sa_std/collections/hashmap.sa");
    defer std.testing.allocator.free(collections_hashmap);
    try std.testing.expect(std.mem.containsAtLeast(u8, collections_hashmap, 1, "@import \"../hashmap.sa\""));

    const hashmap_src = try readFileAlloc(std.testing.allocator, "sa_std/hashmap.sa");
    defer std.testing.allocator.free(hashmap_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"core/mem.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"alloc/vec.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"vec.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"num.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"hashmap.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "EXPAND NUM_U64_CHECKED_MUL new_bytes_ok, new_bytes, new_cap, HashMapSlot_SIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "EXPAND NUM_U64_CHECKED_ADD needed_ok, needed, len, additional"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "EXPAND NUM_U64_CHECKED_MUL clear_bytes_ok, bytes, cap, HashMapSlot_SIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_with_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_put"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_del"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_contains_key"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_reserve"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_shrink_to_fit"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_with_seed"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_with_capacity_seed"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_try_get_disjoint_mut_ptrs"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_try_insert"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_keys_vec"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_values_vec"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_value_mut_ptrs_vec"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_WITH_SEED"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_WITH_CAPACITY_SEED"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_TRY_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_RESERVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_TRY_RESERVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_SHRINK_TO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_SHRINK_TO_FIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_CONTAINS_KEY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_PUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_TRY_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_GET_KEY_VALUE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_GET_MUT_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_TRY_GET_DISJOINT_MUT_PTRS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_TRY_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_KEYS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_VALUES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_VALUES_MUT_PTRS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_DRAIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_EXTRACT_IF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_REMOVE_ENTRY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_DEL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_LIT1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_LIT2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_LIT3"));

    var hashmap_error_ctx = saasm.flattener.ErrorContext{};
    var hashmap_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/hashmap.sa", hashmap_src, &hashmap_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&hashmap_error_ctx) orelse 0;
        std.debug.print("hashmap flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer hashmap_flat.deinit(std.testing.allocator);
    try std.testing.expect(hashmap_flat.instructions.len > 0);
    try std.testing.expect(hashmap_flat.function_sigs.len >= 19);

    const hashmap_verified = try saasm.referee.verify(std.testing.allocator, hashmap_flat.instructions, hashmap_flat.const_decls);
    switch (hashmap_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 19);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print(
                "hashmap smoke verifier trap: {s} (line={d}, source_line={d}, function={s}, text={s}, register={s}, expected={s}, actual={s})\n",
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

    const hashmap_fixture =
        \\@import "sa_std/collections/hashmap.sa"
        \\
        \\@const KEY = utf8:"alpha"
        \\@const VALUE = utf8:"A\n"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND MAP_WITH_CAPACITY map, 9
        \\    EXPAND MAP_LEN len0, map
        \\    EXPAND MAP_CAPACITY cap0, map
        \\    EXPAND MAP_IS_EMPTY empty0, map
        \\    key = &KEY
        \\    value = &VALUE
        \\    EXPAND MAP_CONTAINS_KEY has0, map, key
        \\    EXPAND MAP_PUT map, key, value
        \\    EXPAND MAP_LEN len1, map
        \\    EXPAND MAP_CAPACITY cap1, map
        \\    EXPAND MAP_RESERVE map, 20
        \\    EXPAND MAP_CAPACITY cap_after_reserve, map
        \\    EXPAND MAP_IS_EMPTY empty1, map
        \\    EXPAND MAP_CONTAINS_KEY has1, map, key
        \\    EXPAND MAP_GET got1, map, key
        \\    EXPAND MAP_CLEAR map
        \\    EXPAND MAP_LEN len2, map
        \\    EXPAND MAP_IS_EMPTY empty2, map
        \\    EXPAND MAP_CONTAINS_KEY has2, map, key
        \\    EXPAND MAP_GET got2, map, key
        \\    ok_len0 = eq len0, 0
        \\    ok_cap0 = eq cap0, 16
        \\    ok_empty0 = eq empty0, 1
        \\    ok_has0 = eq has0, 0
        \\    ok_len1 = eq len1, 1
        \\    ok_cap1 = eq cap1, 16
        \\    ok_cap_after_reserve = eq cap_after_reserve, 32
        \\    ok_empty1 = eq empty1, 0
        \\    ok_has1 = eq has1, 1
        \\    ok_got1 = eq got1, value
        \\    ok_len2 = eq len2, 0
        \\    ok_empty2 = eq empty2, 1
        \\    ok_has2 = eq has2, 0
        \\    ok_got2 = eq got2, 0
        \\    ok01 = and ok_len0, ok_cap0
        \\    ok02 = and ok01, ok_empty0
        \\    ok03 = and ok02, ok_has0
        \\    ok04 = and ok03, ok_len1
        \\    ok05 = and ok04, ok_cap1
        \\    ok06 = and ok05, ok_cap_after_reserve
        \\    ok07 = and ok06, ok_empty1
        \\    ok08 = and ok07, ok_has1
        \\    ok09 = and ok08, ok_got1
        \\    ok10 = and ok09, ok_len2
        \\    ok11 = and ok10, ok_empty2
        \\    ok12 = and ok11, ok_has2
        \\    ok = and ok12, ok_got2
        \\    !got2
        \\    !has2
        \\    !empty2
        \\    !len2
        \\    !got1
        \\    !has1
        \\    !empty1
        \\    !cap_after_reserve
        \\    !len1
        \\    !has0
        \\    !empty0
        \\    !cap1
        \\    !cap0
        \\    !len0
        \\    !value
        \\    !key
        \\    !ok_len0
        \\    !ok_cap0
        \\    !ok_empty0
        \\    !ok_has0
        \\    !ok_len1
        \\    !ok_cap1
        \\    !ok_cap_after_reserve
        \\    !ok_empty1
        \\    !ok_has1
        \\    !ok_got1
        \\    !ok_len2
        \\    !ok_empty2
        \\    !ok_has2
        \\    !ok_got2
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
        \\    EXPAND MAP_FREE map
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
    var hashmap_fixture_flat = try flattenFixture(std.testing.allocator, "tests/hashmap_fixture.sa", hashmap_fixture);
    defer hashmap_fixture_flat.deinit(std.testing.allocator);
    const hashmap_fixture_verified = try saasm.referee.verify(std.testing.allocator, hashmap_fixture_flat.instructions, hashmap_fixture_flat.const_decls);
    switch (hashmap_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 15);
        },
        .trap => |report| {
            std.debug.print("hashmap fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std hashset helpers are concrete and verifiable" {
    const hashset_layout = try readFileAlloc(std.testing.allocator, "sa_std/hashset.sal");
    defer std.testing.allocator.free(hashset_layout);
    try std.testing.expectEqualStrings(
        "#def HashSet_SIZE = 32\n#def HashSet_slots = +0\n#def HashSet_cap = +8\n#def HashSet_len = +16\n#def HashSet_tombs = +24\n\n#def HashSetSlot_SIZE = 32\n#def HashSetSlot_hash = +0\n#def HashSetSlot_key = +8\n#def HashSetSlot_value = +16\n#def HashSetSlot_state = +24\n\n#def HashSet_INITIAL_CAP = 8\n#def HashSet_STATE_EMPTY = 0\n#def HashSet_STATE_FILLED = 1\n#def HashSet_STATE_TOMB = 2\n\n#def HashSet_VALUE_SENTINEL = 1\n",
        hashset_layout,
    );

    const collections_hashset = try readFileAlloc(std.testing.allocator, "sa_std/collections/hashset.sa");
    defer std.testing.allocator.free(collections_hashset);
    try std.testing.expect(std.mem.containsAtLeast(u8, collections_hashset, 1, "@import \"../hashset.sa\""));

    const hashset_src = try readFileAlloc(std.testing.allocator, "sa_std/hashset.sa");
    defer std.testing.allocator.free(hashset_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"hashset.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"hashmap.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"vec.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_new"));
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
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_union"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_intersection"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_difference"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_symmetric_difference"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_TRY_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_RESERVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_TRY_RESERVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_SHRINK_TO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_SHRINK_TO_FIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_CONTAINS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_TAKE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_REPLACE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_IS_DISJOINT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_IS_SUBSET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_IS_SUPERSET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_REMOVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_DRAIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_EXTRACT_IF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_UNION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_INTERSECTION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_DIFFERENCE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_SYMMETRIC_DIFFERENCE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_LIT1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_LIT2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_LIT3"));

    var hashset_error_ctx = saasm.flattener.ErrorContext{};
    var hashset_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/hashset.sa", hashset_src, &hashset_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&hashset_error_ctx) orelse 0;
        std.debug.print("hashset flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer hashset_flat.deinit(std.testing.allocator);
    try std.testing.expect(hashset_flat.instructions.len > 0);
    try std.testing.expect(hashset_flat.function_sigs.len >= 27);

    const hashset_verified = try saasm.referee.verify(std.testing.allocator, hashset_flat.instructions, hashset_flat.const_decls);
    switch (hashset_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 27);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print(
                "hashset smoke verifier trap: {s} (line={d}, source_line={d}, function={s}, text={s}, register={s}, expected={s}, actual={s})\n",
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

    const hashset_fixture =
        \\@import "sa_std/collections/hashset.sa"
        \\
        \\@const KEY_A = utf8:"alpha"
        \\@const KEY_B = utf8:"bravo"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND SET_NEW set
        \\    EXPAND SET_LEN len0, set
        \\    EXPAND SET_CAPACITY cap0, set
        \\    EXPAND SET_IS_EMPTY empty0, set
        \\    key_a = &KEY_A
        \\    key_b = &KEY_B
        \\    EXPAND SET_INSERT ins_a, set, key_a
        \\    EXPAND SET_INSERT ins_b, set, key_b
        \\    EXPAND SET_LEN len1, set
        \\    EXPAND SET_CAPACITY cap1, set
        \\    EXPAND SET_RESERVE set, 20
        \\    EXPAND SET_CAPACITY cap_after_reserve, set
        \\    EXPAND SET_IS_EMPTY empty1, set
        \\    EXPAND SET_CONTAINS has_a, set, key_a
        \\    EXPAND SET_CLEAR set
        \\    EXPAND SET_LEN len2, set
        \\    EXPAND SET_IS_EMPTY empty2, set
        \\    EXPAND SET_CONTAINS has_a_after, set, key_a
        \\    ok_len0 = eq len0, 0
        \\    ok_cap0 = eq cap0, 0
        \\    ok_empty0 = eq empty0, 1
        \\    ok_ins_a = eq ins_a, 1
        \\    ok_ins_b = eq ins_b, 1
        \\    ok_len1 = eq len1, 2
        \\    ok_cap1 = eq cap1, 8
        \\    ok_cap_after_reserve = eq cap_after_reserve, 32
        \\    ok_empty1 = eq empty1, 0
        \\    ok_has_a = eq has_a, 1
        \\    ok_len2 = eq len2, 0
        \\    ok_empty2 = eq empty2, 1
        \\    ok_has_a_after = eq has_a_after, 0
        \\    ok01 = and ok_len0, ok_cap0
        \\    ok02 = and ok01, ok_empty0
        \\    ok03 = and ok02, ok_ins_a
        \\    ok04 = and ok03, ok_ins_b
        \\    ok05 = and ok04, ok_len1
        \\    ok06 = and ok05, ok_cap1
        \\    ok07 = and ok06, ok_cap_after_reserve
        \\    ok08 = and ok07, ok_empty1
        \\    ok09 = and ok08, ok_has_a
        \\    ok10 = and ok09, ok_len2
        \\    ok11 = and ok10, ok_empty2
        \\    ok = and ok11, ok_has_a_after
        \\    !has_a_after
        \\    !len2
        \\    !has_a
        \\    !empty2
        \\    !empty1
        \\    !cap_after_reserve
        \\    !cap1
        \\    !len1
        \\    !ins_b
        \\    !ins_a
        \\    !empty0
        \\    !cap0
        \\    !len0
        \\    !key_b
        \\    !key_a
        \\    !ok_cap_after_reserve
        \\    !ok11
        \\    EXPAND SET_FREE set
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
    var hashset_fixture_flat = try flattenFixture(std.testing.allocator, "tests/hashset_fixture.sa", hashset_fixture);
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

test "sa_std vec_deque helpers are concrete and verifiable" {
    const deque_layout = try readFileAlloc(std.testing.allocator, "sa_std/vec_deque.sal");
    defer std.testing.allocator.free(deque_layout);
    try std.testing.expectEqualStrings(
        "#def VecDeque_SIZE = 32\n#def VecDeque_buf = +0\n#def VecDeque_cap = +8\n#def VecDeque_head = +16\n#def VecDeque_len = +24\n\n#def VecDeque_INITIAL_CAP = 8\n#def VecDeque_SLOT_SIZE = 8\n",
        deque_layout,
    );

    const collections_vec_deque = try readFileAlloc(std.testing.allocator, "sa_std/collections/vec_deque.sa");
    defer std.testing.allocator.free(collections_vec_deque);
    try std.testing.expectEqualStrings("@import \"../vec_deque.sa\"\n", collections_vec_deque);

    const deque_src = try readFileAlloc(std.testing.allocator, "sa_std/vec_deque.sa");
    defer std.testing.allocator.free(deque_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@import \"core/mem.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@import \"core/slice.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@import \"core/slice.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@import \"vec.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_with_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_reserve"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_reserve_exact"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_reserve"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_reserve_exact"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_shrink_to"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_shrink_to_fit"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_shrink_to"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_shrink_to_fit"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_as_slices"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_as_mut_slices"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_make_contiguous"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_push_back"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_push_front"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_get_mut_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_front_mut_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_back_mut_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_set"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_contains"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_swap"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_insert"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_remove"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_swap_remove_front"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_swap_remove_back"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_pop_front"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_pop_back"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_front"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_back"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_front"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_back"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_rotate_left"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_rotate_right"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_truncate"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_split_off"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_append"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_GET_MUT_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_FRONT_MUT_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_BACK_MUT_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_SET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_CONTAINS_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_SWAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_REMOVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_REMOVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_SWAP_REMOVE_FRONT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_SWAP_REMOVE_BACK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_POP_FRONT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_POP_BACK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_POP_FRONT_IF_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_POP_FRONT_IF_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_POP_BACK_IF_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_POP_BACK_IF_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_FRONT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_FRONT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_BACK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_BACK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_DRAIN_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_RESERVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_RESERVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_AS_SLICES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_AS_MUT_SLICES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_MAKE_CONTIGUOUS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_RETAIN_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_SHRINK_TO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_SHRINK_TO_FIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_SHRINK_TO_FIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRUNCATE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_APPEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_LIT1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_LIT2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_LIT3"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_FROM_SLICE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_FROM_VEC_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_SPLIT_OFF"));

    var deque_error_ctx = saasm.flattener.ErrorContext{};
    var deque_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/vec_deque.sa", deque_src, &deque_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&deque_error_ctx) orelse 0;
        std.debug.print("vec_deque flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer deque_flat.deinit(std.testing.allocator);
    try std.testing.expect(deque_flat.instructions.len > 0);
    try std.testing.expect(deque_flat.function_sigs.len >= 43);

    const deque_verified = try saasm.referee.verify(std.testing.allocator, deque_flat.instructions, deque_flat.const_decls);
    switch (deque_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 43);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print(
                "vec_deque smoke verifier trap: {s} (line={d}, source_line={d}, function={s}, text={s}, register={s}, expected={s}, actual={s})\n",
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

    const deque_fixture = try readFileAlloc(std.testing.allocator, "tests/vec_deque_fixture.sa");
    defer std.testing.allocator.free(deque_fixture);

    var deque_fixture_flat = try flattenFixture(std.testing.allocator, "tests/vec_deque_fixture.sa", deque_fixture);
    defer deque_fixture_flat.deinit(std.testing.allocator);
    const deque_fixture_verified = try saasm.referee.verify(std.testing.allocator, deque_fixture_flat.instructions, deque_fixture_flat.const_decls);
    switch (deque_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 15);
        },
        .trap => |report| {
            std.debug.print("vec_deque fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}
