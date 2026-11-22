const std = @import("std");
const common = @import("../std_smoke_common.zig");
const saasm = common.saasm;
const flattenFixture = @import("helpers.zig").flattenFixture;

test "sa_std alloc helpers are concrete and verifiable" {
    const vec_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/alloc/vec.sal");
    defer std.testing.allocator.free(vec_layout);
    try std.testing.expectEqualStrings(
        "#def Vec_SIZE = 24\n#def Vec_ptr  = +0\n#def Vec_cap  = +8\n#def Vec_len  = +16",
        vec_layout,
    );

    const vec_src = try common.readFileAlloc(std.testing.allocator, "sa_std/alloc/vec.sa");
    defer std.testing.allocator.free(vec_src);
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "假定"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "示例"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "[DEBUG]"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "sa_print_bytes"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "@import \"../num.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "EXPAND NUM_U64_CHECKED_MUL bytes_ok, bytes, cap, elem_size"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "EXPAND NUM_U64_CHECKED_ADD next_cap_ok, next_cap, cap, cap"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "EXPAND NUM_U64_CHECKED_MUL shrink_new_bytes_ok, new_bytes, target_cap, elem_size"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "panic(1201)"));
    var vec_flat = try flattenFixture(std.testing.allocator, "sa_std/alloc/vec.sa", vec_src);
    defer vec_flat.deinit(std.testing.allocator);
    const vec_verified = try saasm.referee.verify(std.testing.allocator, vec_flat.instructions, vec_flat.const_decls);
    switch (vec_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 11);
        },
        .trap => |report| {
            std.debug.print("vec smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const vec_macro_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/vec.sal");
    defer std.testing.allocator.free(vec_macro_layout);
    try std.testing.expectEqualStrings("#def Vec_data = +0\n", vec_macro_layout);

    const vec_macro_src = try common.readFileAlloc(std.testing.allocator, "sa_std/vec.sa");
    defer std.testing.allocator.free(vec_macro_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "@import \"alloc/vec.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_AS_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_AS_SLICE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_GET_UNCHECKED"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_GET_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "EXPAND VEC_TRY_GET __vec_get_ok_%out_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_GET_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_FRONT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_BACK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_FRONT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_FRONT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_BACK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_BACK_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_PUSH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_PUSH_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_RESERVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_RESERVE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_RESERVE_EXACT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_RESERVE_EXACT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRUNCATE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_POP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_POP_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_POP_IF_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_POP_IF_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_POP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_POP_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_WITH_CAPACITY_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_CONTAINS_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_STARTS_WITH_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_ENDS_WITH_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_STRIP_PREFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_STRIP_SUFFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRIM_PREFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRIM_SUFFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_SPLIT_AT_U64"));

    var vec_macro_error_ctx = saasm.flattener.ErrorContext{};
    var vec_macro_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/vec.sa", vec_macro_src, &vec_macro_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&vec_macro_error_ctx) orelse 0;
        std.debug.print("vec macro flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer vec_macro_flat.deinit(std.testing.allocator);
    try std.testing.expect(vec_macro_flat.instructions.len > 0);
    try std.testing.expect(vec_macro_flat.function_sigs.len >= 11);

    const vec_macro_verified = try saasm.referee.verify(std.testing.allocator, vec_macro_flat.instructions, vec_macro_flat.const_decls);
    switch (vec_macro_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 11);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("vec macro verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const vec_fixture = try common.readFileAlloc(std.testing.allocator, "tests/vec_fixture.sa");
    defer std.testing.allocator.free(vec_fixture);
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_TRY_POP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_TRY_FRONT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_TRY_BACK_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_RESERVE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_RESERVE_EXACT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_CONTAINS_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_STARTS_WITH_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_ENDS_WITH_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_TRY_STRIP_PREFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_TRY_STRIP_SUFFIX_U64"));

    var vec_fixture_error_ctx = saasm.flattener.ErrorContext{};
    var vec_fixture_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "tests/vec_fixture.sa", vec_fixture, &vec_fixture_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&vec_fixture_error_ctx) orelse 0;
        std.debug.print("vec fixture flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer vec_fixture_flat.deinit(std.testing.allocator);
    try std.testing.expect(vec_fixture_flat.instructions.len > 0);
    const vec_fixture_verified = try saasm.referee.verify(std.testing.allocator, vec_fixture_flat.instructions, vec_fixture_flat.const_decls);
    switch (vec_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 11);
        },
        .trap => |report| {
            std.debug.print("vec fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const string_src = try common.readFileAlloc(std.testing.allocator, "sa_std/alloc/string.sa");
    defer std.testing.allocator.free(string_src);
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "假定"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "示例"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_src, 1, "[MACRO] STR_FROM_CONST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_src, 1, "EXPAND SLICE_NEW"));

    const string_macro_src = try common.readFileAlloc(std.testing.allocator, "sa_std/string.sa");
    defer std.testing.allocator.free(string_macro_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "@import \"fmt.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_AS_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_AS_BYTES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_CONTAINS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_CONTAINS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_STARTS_WITH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_STARTS_WITH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_ENDS_WITH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_ENDS_WITH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_TRY_STRIP_PREFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_TRY_STRIP_PREFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_TRY_STRIP_SUFFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_TRY_STRIP_SUFFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_TRIM_PREFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_TRIM_PREFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_TRIM_SUFFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_TRIM_SUFFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_TRY_SPLIT_AT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_TRY_SPLIT_AT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_CONCAT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "sa_fmt_buffer_data"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "sa_fmt_buffer_len"));

    const string_fixture =
        \\@import "sa_std/core/slice.sal"
        \\@import "sa_std/core/slice.sa"
        \\@import "sa_std/alloc/string.sa"
        \\
        \\@const WORD = utf8:"rust"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    word = alloc Slice_SIZE
        \\    EXPAND STR_FROM_CONST word, WORD, 4
        \\    EXPAND SLICE_GET_LEN len, word
        \\    ok = eq len, 4
        \\    !len
        \\    !word
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
    var string_flat = try flattenFixture(std.testing.allocator, "demos/rosetta/15_string_bytes/main.sa", string_fixture);
    defer string_flat.deinit(std.testing.allocator);
    const string_verified = try saasm.referee.verify(std.testing.allocator, string_flat.instructions, string_flat.const_decls);
    switch (string_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 1), owned.function_sigs.len);
        },
        .trap => |report| {
            std.debug.print("string smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const string_macro_fixture =
        \\@import "sa_std/string.sa"
        \\
        \\@const WORD = utf8:"rust"
        \\@const PREFIX = utf8:"ru"
        \\@const SUFFIX = utf8:"st"
        \\@const INFIX = utf8:"us"
        \\@const MISS = utf8:"zz"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND STR_FROM_PARTS word, &WORD, 4
        \\    EXPAND STR_FROM_PARTS prefix, &PREFIX, 2
        \\    EXPAND STR_FROM_PARTS suffix, &SUFFIX, 2
        \\    EXPAND STR_FROM_PARTS infix, &INFIX, 2
        \\    EXPAND STR_FROM_PARTS miss, &MISS, 2
        \\    EXPAND STR_EMPTY empty
        \\    EXPAND STRING_LEN len, word
        \\    EXPAND STR_CONTAINS contains_ok, word, infix
        \\    EXPAND STRING_CONTAINS contains_empty_ok, word, empty
        \\    EXPAND STRING_CONTAINS contains_miss, word, miss
        \\    EXPAND STR_STARTS_WITH starts_ok, word, prefix
        \\    EXPAND STRING_STARTS_WITH starts_miss, word, miss
        \\    EXPAND STR_ENDS_WITH ends_ok, word, suffix
        \\    EXPAND STRING_ENDS_WITH ends_miss, word, miss
        \\    EXPAND STR_TRY_STRIP_PREFIX strip_prefix_ok, strip_prefix_tail, word, prefix
        \\    EXPAND STRING_TRY_STRIP_SUFFIX strip_suffix_ok, strip_suffix_head, word, suffix
        \\    EXPAND STR_TRY_STRIP_PREFIX strip_prefix_miss_ok, strip_prefix_miss, word, miss
        \\    EXPAND STRING_TRY_STRIP_SUFFIX strip_suffix_miss_ok, strip_suffix_miss, word, miss
        \\    EXPAND STR_EQ strip_prefix_tail_eq, strip_prefix_tail, suffix
        \\    EXPAND STR_EQ strip_suffix_head_eq, strip_suffix_head, prefix
        \\    EXPAND STR_IS_EMPTY strip_prefix_miss_empty, strip_prefix_miss
        \\    EXPAND STR_IS_EMPTY strip_suffix_miss_empty, strip_suffix_miss
        \\    len_ok = eq len, 4
        \\    contains_match_ok = eq contains_ok, 1
        \\    contains_empty_match_ok = eq contains_empty_ok, 1
        \\    contains_miss_ok = eq contains_miss, 0
        \\    starts_match_ok = eq starts_ok, 1
        \\    starts_miss_ok = eq starts_miss, 0
        \\    ends_match_ok = eq ends_ok, 1
        \\    ends_miss_ok = eq ends_miss, 0
        \\    strip_prefix_flag_ok = eq strip_prefix_ok, 1
        \\    strip_suffix_flag_ok = eq strip_suffix_ok, 1
        \\    strip_prefix_miss_flag_ok = eq strip_prefix_miss_ok, 0
        \\    strip_suffix_miss_flag_ok = eq strip_suffix_miss_ok, 0
        \\    strip_prefix_tail_ok = eq strip_prefix_tail_eq, 1
        \\    strip_suffix_head_ok = eq strip_suffix_head_eq, 1
        \\    strip_prefix_miss_empty_ok = eq strip_prefix_miss_empty, 1
        \\    strip_suffix_miss_empty_ok = eq strip_suffix_miss_empty, 1
        \\    ok01 = and len_ok, contains_match_ok
        \\    ok02 = and ok01, contains_empty_match_ok
        \\    ok03 = and ok02, contains_miss_ok
        \\    ok04 = and ok03, starts_match_ok
        \\    ok05 = and ok04, starts_miss_ok
        \\    ok06 = and ok05, ends_match_ok
        \\    ok07 = and ok06, ends_miss_ok
        \\    ok08 = and ok07, strip_prefix_flag_ok
        \\    ok09 = and ok08, strip_suffix_flag_ok
        \\    ok10 = and ok09, strip_prefix_miss_flag_ok
        \\    ok11 = and ok10, strip_suffix_miss_flag_ok
        \\    ok12 = and ok11, strip_prefix_tail_ok
        \\    ok13 = and ok12, strip_suffix_head_ok
        \\    ok14 = and ok13, strip_prefix_miss_empty_ok
        \\    ok = and ok14, strip_suffix_miss_empty_ok
        \\    !len
        \\    !contains_ok
        \\    !contains_empty_ok
        \\    !contains_miss
        \\    !starts_ok
        \\    !starts_miss
        \\    !ends_ok
        \\    !ends_miss
        \\    !strip_prefix_ok
        \\    !strip_prefix_tail
        \\    !strip_suffix_ok
        \\    !strip_suffix_head
        \\    !strip_prefix_miss_ok
        \\    !strip_prefix_miss
        \\    !strip_suffix_miss_ok
        \\    !strip_suffix_miss
        \\    !strip_prefix_tail_eq
        \\    !strip_suffix_head_eq
        \\    !strip_prefix_miss_empty
        \\    !strip_suffix_miss_empty
        \\    !len_ok
        \\    !contains_match_ok
        \\    !contains_empty_match_ok
        \\    !contains_miss_ok
        \\    !starts_match_ok
        \\    !starts_miss_ok
        \\    !ends_match_ok
        \\    !ends_miss_ok
        \\    !strip_prefix_flag_ok
        \\    !strip_suffix_flag_ok
        \\    !strip_prefix_miss_flag_ok
        \\    !strip_suffix_miss_flag_ok
        \\    !strip_prefix_tail_ok
        \\    !strip_suffix_head_ok
        \\    !strip_prefix_miss_empty_ok
        \\    !strip_suffix_miss_empty_ok
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
        \\    !ok13
        \\    !ok14
        \\    !word
        \\    !prefix
        \\    !suffix
        \\    !infix
        \\    !miss
        \\    !empty
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
    var string_macro_flat = try flattenFixture(std.testing.allocator, "tests/string_macro_fixture.sa", string_macro_fixture);
    defer string_macro_flat.deinit(std.testing.allocator);
    const string_macro_verified = try saasm.referee.verify(std.testing.allocator, string_macro_flat.instructions, string_macro_flat.const_decls);
    switch (string_macro_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 1);
            var saw_concat = false;
            for (owned.function_sigs) |sig| {
                if (std.mem.eql(u8, sig.name, "sa_string_concat")) saw_concat = true;
            }
            try std.testing.expect(saw_concat);
        },
        .trap => |report| {
            std.debug.print("string macro verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}
