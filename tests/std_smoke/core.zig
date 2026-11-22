//! core primitives and rust core helpers -- split from tests/std_smoke.zig (shared helpers: helpers.zig).
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

test "sa_std core primitives are concrete and verifiable" {
    const slice_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/slice.sal");
    defer std.testing.allocator.free(slice_layout);
    try std.testing.expectEqualStrings(
        "#def Slice_SIZE = 16\n#def Slice_ptr  = +0\n#def Slice_len  = +8\n",
        slice_layout,
    );

    const slice_src = try readFileAlloc(std.testing.allocator, "sa_std/core/slice.sa");
    defer std.testing.allocator.free(slice_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_AS_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_FIRST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_FIRST_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_FIRST_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_LAST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_LAST_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_LAST_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_SPLIT_FIRST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_SPLIT_LAST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_GET_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_GET_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRIM_PREFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRIM_SUFFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_SPLIT_AT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_SPLIT_AT_MUT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_RANGE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_GET_RANGE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_SWAP_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_SWAP_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_CLONE_FROM_SLICE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_COPY_WITHIN_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_BINARY_SEARCH_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_PARTITION_POINT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_LOWER_BOUND_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_UPPER_BOUND_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_EQUAL_RANGE_U64"));

    var slice_flat = try saasm.flattener.flatten(std.testing.allocator, slice_src);
    defer slice_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.function_sigs.len);

    const slice_fixture =
        \\@import "sa_std/core/slice.sal"
        \\@import "sa_std/core/slice.sa"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    data = alloc 24
        \\    store data+0, 11 as u64
        \\    store data+8, 22 as u64
        \\    store data+16, 33 as u64
        \\    slice = alloc Slice_SIZE
        \\    EXPAND SLICE_NEW slice, data, 3
        \\    EXPAND SLICE_AS_PTR ptr, slice
        \\    EXPAND SLICE_IS_EMPTY empty, slice
        \\    EXPAND SLICE_FIRST_U64 first, slice
        \\    EXPAND SLICE_LAST_U64 last, slice
        \\    EXPAND SLICE_TRY_GET_U64 hit_ok, hit, slice, 1
        \\    EXPAND SLICE_TRY_GET_U64 miss_ok, miss, slice, 9
        \\    ptr_ok = ne ptr, 0
        \\    empty_ok = eq empty, 0
        \\    first_ok = eq first, 11
        \\    last_ok = eq last, 33
        \\    hit_flag_ok = eq hit_ok, 1
        \\    hit_value_ok = eq hit, 22
        \\    miss_flag_ok = eq miss_ok, 0
        \\    miss_value_ok = eq miss, 0
        \\    ok01 = and ptr_ok, empty_ok
        \\    ok02 = and ok01, first_ok
        \\    ok03 = and ok02, last_ok
        \\    ok04 = and ok03, hit_flag_ok
        \\    ok05 = and ok04, hit_value_ok
        \\    ok06 = and ok05, miss_flag_ok
        \\    ok = and ok06, miss_value_ok
        \\    !ptr
        \\    !empty
        \\    !first
        \\    !last
        \\    !hit_ok
        \\    !hit
        \\    !miss_ok
        \\    !miss
        \\    !ptr_ok
        \\    !empty_ok
        \\    !first_ok
        \\    !last_ok
        \\    !hit_flag_ok
        \\    !hit_value_ok
        \\    !miss_flag_ok
        \\    !miss_value_ok
        \\    !ok01
        \\    !ok02
        \\    !ok03
        \\    !ok04
        \\    !ok05
        \\    !ok06
        \\    !slice
        \\    !data
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
    var slice_fixture_flat = try flattenFixture(std.testing.allocator, "tests/slice_fixture.sa", slice_fixture);
    defer slice_fixture_flat.deinit(std.testing.allocator);
    const slice_fixture_verified = try saasm.referee.verify(std.testing.allocator, slice_fixture_flat.instructions, slice_fixture_flat.const_decls);
    switch (slice_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 1), owned.function_sigs.len);
        },
        .trap => |report| {
            std.debug.print("slice fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const mem_src = try readFileAlloc(std.testing.allocator, "sa_std/core/mem.sa");
    defer std.testing.allocator.free(mem_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_copy"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_set"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "panic(1701)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "panic(1702)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "panic(1703)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "[MACRO] BOX_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "[MACRO] BOX_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "ptr_add"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "br done -> L_END, L_BODY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "stack_alloc 8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "store offset_slot+0, 0 as u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "store remaining_slot+0, count as u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "next_remaining = sub remaining, one"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, mem_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, mem_src, 1, "i = 0"));

    var mem_flat = try saasm.flattener.flatten(std.testing.allocator, mem_src);
    defer mem_flat.deinit(std.testing.allocator);
    const verified = try saasm.referee.verify(std.testing.allocator, mem_flat.instructions, mem_flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 2), owned.function_sigs.len);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("std smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std rust core helpers are concrete and verifiable" {
    const option_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/option.sal");
    defer std.testing.allocator.free(option_layout);
    try std.testing.expectEqualStrings(
        "#def Option_SIZE = 16\n#def Option_tag = +0\n#def Option_value = +8\n#def Option_NONE = 0\n#def Option_SOME = 1\n",
        option_layout,
    );

    const result_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/result.sal");
    defer std.testing.allocator.free(result_layout);
    try std.testing.expectEqualStrings(
        "#def Result_SIZE = 24\n#def Result_tag = +0\n#def Result_ok = +8\n#def Result_err = +16\n#def Result_OK = 0\n#def Result_ERR = 1\n",
        result_layout,
    );

    const iter_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/iter.sal");
    defer std.testing.allocator.free(iter_layout);
    try std.testing.expectEqualStrings(
        "#def Iter_SIZE = 24\n#def Iter_ptr = +0\n#def Iter_len = +8\n#def Iter_index = +16\n",
        iter_layout,
    );

    const option_src = try readFileAlloc(std.testing.allocator, "sa_std/core/option.sa");
    defer std.testing.allocator.free(option_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_NEW_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_NEW_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_IS_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_IS_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MAP_OR_ELSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_SET_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_BRANCH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] MATCHES_OPTION"));

    const result_src = try readFileAlloc(std.testing.allocator, "sa_std/core/result.sa");
    defer std.testing.allocator.free(result_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_NEW_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_NEW_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_IS_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_IS_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_GET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_GET_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OR_ELSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_SET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_SET_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_BRANCH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] MATCH_RESULT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] MATCHES_RESULT"));

    const stringify_src = try readFileAlloc(std.testing.allocator, "src/flattener.zig");
    defer std.testing.allocator.free(stringify_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, stringify_src, 1, "STRINGIFY!"));

    const panic_src = try readFileAlloc(std.testing.allocator, "sa_std/core/panic.sa");
    defer std.testing.allocator.free(panic_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] PANIC "));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] PANIC_MSG"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] TODO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] UNIMPLEMENTED"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] UNREACHABLE"));

    const iter_src = try readFileAlloc(std.testing.allocator, "sa_std/core/iter.sa");
    defer std.testing.allocator.free(iter_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_FROM_SLICE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_HAS_NEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_REMAINING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_PEEK_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_NEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_NEXT_U64"));

    const rust_core_src = try readFileAlloc(std.testing.allocator, "sa_std/rust_core.sa");
    defer std.testing.allocator.free(rust_core_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/option.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/result.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/panic.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/iter.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/cell.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/refcell.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/rc.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/weak.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/derive.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "[MACRO] DROP_AND_RETURN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/box.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/dispatch.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/arc.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/future.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/task.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/ascii.sa\""));

    const arc_src = try readFileAlloc(std.testing.allocator, "sa_std/core/arc.sa");
    defer std.testing.allocator.free(arc_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, arc_src, 1, "@import \"../num.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, arc_src, 1, "NUM_U64_MAX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, arc_src, 1, "panic(1501)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, arc_src, 1, "panic(1505)"));

    const ascii_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/ascii.sal");
    defer std.testing.allocator.free(ascii_layout);
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_layout, 1, "#def ASCII_CASE_MASK = 32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_layout, 1, "#def ASCII_MAX = 127"));

    const ascii_src = try readFileAlloc(std.testing.allocator, "sa_std/core/ascii.sa");
    defer std.testing.allocator.free(ascii_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_ASCII"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_ALPHABETIC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_ALPHANUMERIC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_DIGIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_OCTDIGIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_HEXDIGIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_PUNCTUATION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_GRAPHIC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_WHITESPACE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_CONTROL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_TO_UPPERCASE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_TO_LOWERCASE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_EQ_IGNORE_CASE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_SLICE_MAKE_UPPERCASE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_SLICE_MAKE_LOWERCASE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_SLICE_EQ_IGNORE_CASE"));

    const ascii_facade_src = try readFileAlloc(std.testing.allocator, "sa_std/ascii.sa");
    defer std.testing.allocator.free(ascii_facade_src);
    try std.testing.expectEqualStrings("@import \"core/ascii.sal\"\n@import \"core/ascii.sa\"\n", ascii_facade_src);

    const cell_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/cell.sal");
    defer std.testing.allocator.free(cell_layout);
    try std.testing.expectEqualStrings("#def Cell_SIZE = 4\n#def Cell_value = +0\n", cell_layout);

    const refcell_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/refcell.sal");
    defer std.testing.allocator.free(refcell_layout);
    try std.testing.expectEqualStrings("#def RefCell_SIZE = 8\n#def RefCell_value = +0\n#def RefCell_borrows = +4\n", refcell_layout);

    const future_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/future.sal");
    defer std.testing.allocator.free(future_layout);
    try std.testing.expect(std.mem.containsAtLeast(u8, future_layout, 1, "#def Poll_SIZE = 16"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_layout, 1, "#def Context_SIZE = 16"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_layout, 1, "#def Future_SIZE = 16"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_layout, 1, "#def FuturePollSlot = +0"));

    const task_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/task.sal");
    defer std.testing.allocator.free(task_layout);
    try std.testing.expect(std.mem.containsAtLeast(u8, task_layout, 1, "#def Task_SIZE = 32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, task_layout, 1, "#def Executor_SIZE = 16"));

    const rc_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/rc.sal");
    defer std.testing.allocator.free(rc_layout);
    try std.testing.expectEqualStrings("#def RcBox_SIZE = 24\n#def RcBox_strong = +0\n#def RcBox_weak = +8\n#def RcBox_data = +16\n", rc_layout);

    const weak_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/weak.sal");
    defer std.testing.allocator.free(weak_layout);
    try std.testing.expectEqualStrings("#def WeakBox_SIZE = 24\n#def WeakBox_strong = +0\n#def WeakBox_weak = +8\n#def WeakBox_data = +16\n", weak_layout);

    const cell_src = try readFileAlloc(std.testing.allocator, "sa_std/core/cell.sa");
    defer std.testing.allocator.free(cell_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_SET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_REPLACE"));

    const refcell_src = try readFileAlloc(std.testing.allocator, "sa_std/core/refcell.sa");
    defer std.testing.allocator.free(refcell_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_BORROW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_BORROW_MUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_RELEASE"));

    const derive_src = try readFileAlloc(std.testing.allocator, "sa_std/core/derive.sa");
    defer std.testing.allocator.free(derive_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_COPY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_EQ_FIELD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_EQ4"));

    const rc_src = try readFileAlloc(std.testing.allocator, "sa_std/core/rc.sa");
    defer std.testing.allocator.free(rc_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_CLONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_DROP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_DOWNGRADE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_CLONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_DROP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_UPGRADE"));

    const weak_src = try readFileAlloc(std.testing.allocator, "sa_std/core/weak.sa");
    defer std.testing.allocator.free(weak_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, weak_src, 1, "@import \"weak.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, weak_src, 1, "@import \"rc.sa\""));

    const box_src = try readFileAlloc(std.testing.allocator, "sa_std/core/box.sa");
    defer std.testing.allocator.free(box_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, box_src, 1, "@import \"mem.sa\""));
    var box_flat = try saasm.flattener.flatten(std.testing.allocator, box_src);
    defer box_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), box_flat.instructions.len);

    const future_src = try readFileAlloc(std.testing.allocator, "sa_std/core/future.sa");
    defer std.testing.allocator.free(future_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] POLL_PENDING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] POLL_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] POLL_MAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] POLL_RESULT_MAP_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] POLL_RESULT_MAP_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] POLL_OPTION_RESULT_MAP_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] CONTEXT_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] CONTEXT_FROM_WAKER"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] CONTEXT_BUILDER_BUILD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] FUTURE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] FUTURE_POLL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] FUTURE_READY_STATE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] FUTURE_PENDING_STATE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] FUTURE_JOIN2_POLL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] FUTURE_SELECT2_POLL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] FUTURE_JOIN2_STATE_POLL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, future_src, 1, "[MACRO] FUTURE_SELECT2_STATE_POLL"));

    const waker_src = try readFileAlloc(std.testing.allocator, "sa_std/core/waker.sa");
    defer std.testing.allocator.free(waker_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, waker_src, 1, "[MACRO] RAW_WAKER_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, waker_src, 1, "[MACRO] RAW_WAKER_CLONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, waker_src, 1, "[MACRO] WAKER_FROM_RAW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, waker_src, 1, "[MACRO] WAKER_CLONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, waker_src, 1, "[MACRO] WAKER_WILL_WAKE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, waker_src, 1, "[MACRO] LOCAL_WAKER_FROM_RAW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, waker_src, 1, "[MACRO] LOCAL_WAKER_WILL_WAKE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, waker_src, 1, "[MACRO] WAKE_NEW"));

    const task_src = try readFileAlloc(std.testing.allocator, "sa_std/core/task.sa");
    defer std.testing.allocator.free(task_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, task_src, 1, "[MACRO] TASK_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, task_src, 1, "[MACRO] TASK_POLL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, task_src, 1, "[MACRO] EXECUTOR_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, task_src, 1, "[MACRO] EXECUTOR_POLL_ONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, task_src, 1, "[MACRO] EXECUTOR_POLL_READY_COUNT"));

    const future_facade_src = try readFileAlloc(std.testing.allocator, "sa_std/future.sa");
    defer std.testing.allocator.free(future_facade_src);
    try std.testing.expectEqualStrings("@import \"core/future.sal\"\n@import \"core/future.sa\"\n", future_facade_src);

    const future_facade_layout = try readFileAlloc(std.testing.allocator, "sa_std/future.sal");
    defer std.testing.allocator.free(future_facade_layout);
    try std.testing.expectEqualStrings("@import \"core/future.sal\"\n", future_facade_layout);

    const task_facade_src = try readFileAlloc(std.testing.allocator, "sa_std/task.sa");
    defer std.testing.allocator.free(task_facade_src);
    try std.testing.expectEqualStrings("@import \"core/task.sal\"\n@import \"core/task.sa\"\n", task_facade_src);

    const task_facade_layout = try readFileAlloc(std.testing.allocator, "sa_std/task.sal");
    defer std.testing.allocator.free(task_facade_layout);
    try std.testing.expectEqualStrings("@import \"core/task.sal\"\n", task_facade_layout);

    var option_flat = try flattenFixture(std.testing.allocator, "sa_std/core/option.sa", option_src);
    defer option_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), option_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), option_flat.function_sigs.len);

    var result_flat = try flattenFixture(std.testing.allocator, "sa_std/core/result.sa", result_src);
    defer result_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), result_flat.function_sigs.len);

    var panic_flat = try flattenFixture(std.testing.allocator, "sa_std/core/panic.sa", panic_src);
    defer panic_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), panic_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), panic_flat.function_sigs.len);

    var iter_flat = try flattenFixture(std.testing.allocator, "sa_std/core/iter.sa", iter_src);
    defer iter_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), iter_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), iter_flat.function_sigs.len);

    var ascii_flat = try flattenFixture(std.testing.allocator, "sa_std/core/ascii.sa", ascii_src);
    defer ascii_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), ascii_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), ascii_flat.function_sigs.len);

    var future_flat = try flattenFixture(std.testing.allocator, "sa_std/core/future.sa", future_src);
    defer future_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), future_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), future_flat.function_sigs.len);

    var task_flat = try flattenFixture(std.testing.allocator, "sa_std/core/task.sa", task_src);
    defer task_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), task_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), task_flat.function_sigs.len);

    var rust_core_flat = try flattenFixture(std.testing.allocator, "sa_std/rust_core.sa", rust_core_src);
    defer rust_core_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), rust_core_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), rust_core_flat.function_sigs.len);

    const rust_core_fixture = try readFileAlloc(std.testing.allocator, "tests/rust_core_fixture.sa");
    defer std.testing.allocator.free(rust_core_fixture);
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND OPTION_IS_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND OPTION_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND OPTION_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND RESULT_NEW_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND RESULT_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND RESULT_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND ITER_FROM_SLICE"));

    var rust_core_fixture_flat = try flattenFixture(std.testing.allocator, "tests/rust_core_fixture.sa", rust_core_fixture);
    defer rust_core_fixture_flat.deinit(std.testing.allocator);
    try std.testing.expect(rust_core_fixture_flat.instructions.len > 0);
    try std.testing.expect(rust_core_fixture_flat.function_sigs.len >= 1);

    const option_default_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/46_option_default/main.sa");
    defer std.testing.allocator.free(option_default_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, option_default_demo, 1, "@import \"sa_std/core/option.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_default_demo, 1, "Option_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_default_demo, 1, "call @choose(&opt, 1)"));
    var option_default_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/46_option_default/main.sa", option_default_demo);
    defer option_default_flat.deinit(std.testing.allocator);
    try std.testing.expect(option_default_flat.instructions.len > 0);

    const result_question_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/19_result_question/main.sa");
    defer std.testing.allocator.free(result_question_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, result_question_demo, 1, "@import \"sa_std/core/result.sa\""));
    var result_question_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/19_result_question/main.sa", result_question_demo);
    defer result_question_flat.deinit(std.testing.allocator);
    try std.testing.expect(result_question_flat.instructions.len > 0);

    const result_unwrap_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/177_unwrap_unwrap_err/main.sa");
    defer std.testing.allocator.free(result_unwrap_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, result_unwrap_demo, 1, "@import \"sa_std/core/result.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_unwrap_demo, 1, "EXPAND RESULT_UNWRAP_ERR"));
    var result_unwrap_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/177_unwrap_unwrap_err/main.sa", result_unwrap_demo);
    defer result_unwrap_flat.deinit(std.testing.allocator);
    try std.testing.expect(result_unwrap_flat.instructions.len > 0);

    const iterator_fold_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/35_iterator_fold/main.sa");
    defer std.testing.allocator.free(iterator_fold_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, iterator_fold_demo, 1, "@import \"sa_std/core/iter.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, iterator_fold_demo, 1, "ITER_FROM_SLICE"));
    var iterator_fold_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/35_iterator_fold/main.sa", iterator_fold_demo);
    defer iterator_fold_flat.deinit(std.testing.allocator);
    try std.testing.expect(iterator_fold_flat.instructions.len > 0);

    const option_map_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/18_option_map/main.sa");
    defer std.testing.allocator.free(option_map_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, option_map_demo, 1, "@import \"sa_std/core/option.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_map_demo, 1, "!opt"));
    var option_map_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/18_option_map/main.sa", option_map_demo);
    defer option_map_flat.deinit(std.testing.allocator);
    try std.testing.expect(option_map_flat.instructions.len > 0);

    const manual_guard_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/30_manual_guard_branch/main.sa");
    defer std.testing.allocator.free(manual_guard_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, manual_guard_demo, 1, "@import \"sa_std/core/option.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual_guard_demo, 1, "OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual_guard_demo, 1, "OPTION_IS_SOME"));
    var manual_guard_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/30_manual_guard_branch/main.sa", manual_guard_demo);
    defer manual_guard_flat.deinit(std.testing.allocator);
    try std.testing.expect(manual_guard_flat.instructions.len > 0);

    const never_type_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/146_never_type_fallback/main.sa");
    defer std.testing.allocator.free(never_type_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, never_type_demo, 1, "@import \"sa_std/core/option.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, never_type_demo, 1, "OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, never_type_demo, 1, "OPTION_IS_SOME"));
    var never_type_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/146_never_type_fallback/main.sa", never_type_demo);
    defer never_type_flat.deinit(std.testing.allocator);
    try std.testing.expect(never_type_flat.instructions.len > 0);

    const if_let_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/104_if_let_chains/main.sa");
    defer std.testing.allocator.free(if_let_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, if_let_demo, 1, "@import \"sa_std/core/option.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, if_let_demo, 1, "OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, if_let_demo, 1, "OPTION_GET"));
    var if_let_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/104_if_let_chains/main.sa", if_let_demo);
    defer if_let_flat.deinit(std.testing.allocator);
    try std.testing.expect(if_let_flat.instructions.len > 0);

    const let_else_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/105_let_else/main.sa");
    defer std.testing.allocator.free(let_else_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, let_else_demo, 1, "@import \"sa_std/core/option.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, let_else_demo, 1, "OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, let_else_demo, 1, "OPTION_GET"));
    var let_else_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/105_let_else/main.sa", let_else_demo);
    defer let_else_flat.deinit(std.testing.allocator);
    try std.testing.expect(let_else_flat.instructions.len > 0);

    const generics_monomorph_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/10_generics_monomorph/main.sa");
    defer std.testing.allocator.free(generics_monomorph_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, generics_monomorph_demo, 1, "@import \"sa_std/core/option.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, generics_monomorph_demo, 1, "OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, generics_monomorph_demo, 1, "OPTION_IS_SOME"));
    var generics_monomorph_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/10_generics_monomorph/main.sa", generics_monomorph_demo);
    defer generics_monomorph_flat.deinit(std.testing.allocator);
    try std.testing.expect(generics_monomorph_flat.instructions.len > 0);

    const result_flatten_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/176_result_flattening/main.sa");
    defer std.testing.allocator.free(result_flatten_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, result_flatten_demo, 1, "@import \"sa_std/core/result.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_flatten_demo, 1, "RESULT_SET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_flatten_demo, 1, "RESULT_GET_OK"));
    var result_flatten_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/176_result_flattening/main.sa", result_flatten_demo);
    defer result_flatten_flat.deinit(std.testing.allocator);
    try std.testing.expect(result_flatten_flat.instructions.len > 0);

    const assert_macro_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/179_assert_macro_expansion/main.sa");
    defer std.testing.allocator.free(assert_macro_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, assert_macro_demo, 1, "@import \"sa_std/core/panic.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, assert_macro_demo, 1, "EXPAND PANIC_MSG"));
    var assert_macro_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/179_assert_macro_expansion/main.sa", assert_macro_demo);
    defer assert_macro_flat.deinit(std.testing.allocator);
    try std.testing.expect(assert_macro_flat.instructions.len > 0);
}
