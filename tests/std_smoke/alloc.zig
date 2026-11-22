//! alloc helpers -- split from tests/std_smoke.zig (shared helpers: helpers.zig).
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

test "sa_std alloc helpers are concrete and verifiable" {
    const vec_layout = try readFileAlloc(std.testing.allocator, "sa_std/alloc/vec.sal");
    defer std.testing.allocator.free(vec_layout);
    try std.testing.expectEqualStrings(
        "#def Vec_SIZE = 24\n#def Vec_ptr  = +0\n#def Vec_cap  = +8\n#def Vec_len  = +16",
        vec_layout,
    );

    const vec_src = try readFileAlloc(std.testing.allocator, "sa_std/alloc/vec.sa");
    defer std.testing.allocator.free(vec_src);
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "假定"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "示例"));
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

    const vec_macro_layout = try readFileAlloc(std.testing.allocator, "sa_std/vec.sal");
    defer std.testing.allocator.free(vec_macro_layout);
    try std.testing.expectEqualStrings("#def Vec_data = +0\n", vec_macro_layout);

    const vec_macro_src = try readFileAlloc(std.testing.allocator, "sa_std/vec.sa");
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
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_EXTEND_FROM_SLICE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_EXTEND_FROM_SLICE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_EXTEND_FROM_WITHIN_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_EXTEND_FROM_WITHIN_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_APPEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_APPEND_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_SWAP_REMOVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_SWAP_REMOVE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_REMOVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_SPLIT_OFF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_RESIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_AS_MUT_SLICE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_SET_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_SHRINK_TO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_SHRINK_TO_FIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_SHRINK_TO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_SHRINK_TO_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_SHRINK_TO_FIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_SHRINK_TO_FIT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_FRONT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_BACK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_FIRST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_LAST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_FIRST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_LAST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_SPLIT_FIRST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_SPLIT_LAST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_PUSH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_PUSH_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_LIT1_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_LIT2_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_LIT3_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_CAPACITY"));
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

    const vec_fixture = try readFileAlloc(std.testing.allocator, "tests/vec_fixture.sa");
    defer std.testing.allocator.free(vec_fixture);
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_TRY_POP"));

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

    const string_src = try readFileAlloc(std.testing.allocator, "sa_std/alloc/string.sa");
    defer std.testing.allocator.free(string_src);
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "假定"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "示例"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_src, 1, "[MACRO] STR_FROM_CONST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_src, 1, "EXPAND SLICE_NEW"));

    const string_macro_src = try readFileAlloc(std.testing.allocator, "sa_std/string.sa");
    defer std.testing.allocator.free(string_macro_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "@import \"fmt.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_AS_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_AS_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_AS_BYTES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_AS_BYTES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_AS_STR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_FROM_PARTS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_FROM_PARTS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_TRY_FIND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_TRY_RFIND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_CONCAT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "sa_fmt_buffer_data"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "sa_fmt_buffer_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_TRIM_PREFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_TRIM_SUFFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STR_TRY_SPLIT_AT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_BUF_TRY_PUSH_CHAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_BUF_PUSH_CHAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_BUF_TRY_INSERT_CHAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_BUF_INSERT_CHAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_BUF_LIT1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_BUF_LIT2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_macro_src, 1, "[MACRO] STRING_BUF_LIT3"));

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
        \\@const EMPTY = utf8:""
        \\@const INFIX = utf8:"us"
        \\@const MISS = utf8:"zz"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND STR_FROM_PARTS word, &WORD, 4
        \\    EXPAND STRING_LEN len, word
        \\    EXPAND STR_PTR ptr, word
        \\    EXPAND STR_AS_PTR as_ptr, word
        \\    EXPAND STRING_AS_BYTES bytes, word
        \\    EXPAND STRING_AS_STR str_view, word
        \\    EXPAND STR_LEN bytes_len, bytes
        \\    EXPAND STRING_LEN str_len, str_view
        \\    EXPAND STRING_FROM_PARTS empty, &EMPTY, 0
        \\    EXPAND STR_FROM_PARTS infix, &INFIX, 2
        \\    EXPAND STR_FROM_PARTS miss, &MISS, 2
        \\    EXPAND STRING_NEW new_empty
        \\    EXPAND STR_EMPTY str_empty
        \\    EXPAND STR_IS_EMPTY word_empty, word
        \\    EXPAND STRING_IS_EMPTY empty_ok, empty
        \\    EXPAND STRING_IS_EMPTY new_empty_ok, new_empty
        \\    EXPAND STR_IS_EMPTY str_empty_ok, str_empty
        \\    EXPAND STR_TRY_FIND find_ok, find_idx, word, infix
        \\    EXPAND STRING_TRY_RFIND rfind_ok, rfind_idx, word, infix
        \\    EXPAND STR_TRY_FIND find_miss_ok, find_miss_idx, word, miss
        \\    EXPAND STRING_TRY_RFIND rfind_miss_ok, rfind_miss_idx, word, miss
        \\    len_ok = eq len, 4
        \\    ptr_ok = ne ptr, 0
        \\    as_ptr_ok = ne as_ptr, 0
        \\    bytes_len_ok = eq bytes_len, 4
        \\    str_len_ok = eq str_len, 4
        \\    word_not_empty = eq word_empty, 0
        \\    find_flag_ok = eq find_ok, 1
        \\    find_idx_ok = eq find_idx, 1
        \\    rfind_flag_ok = eq rfind_ok, 1
        \\    rfind_idx_ok = eq rfind_idx, 1
        \\    find_miss_flag_ok = eq find_miss_ok, 0
        \\    find_miss_idx_ok = eq find_miss_idx, 0
        \\    rfind_miss_flag_ok = eq rfind_miss_ok, 0
        \\    rfind_miss_idx_ok = eq rfind_miss_idx, 0
        \\    ok01 = and len_ok, ptr_ok
        \\    ok02 = and ok01, as_ptr_ok
        \\    ok03 = and ok02, bytes_len_ok
        \\    ok04 = and ok03, str_len_ok
        \\    ok05 = and ok04, word_not_empty
        \\    ok06 = and ok05, empty_ok
        \\    ok07 = and ok06, new_empty_ok
        \\    ok08 = and ok07, str_empty_ok
        \\    ok09 = and ok08, find_flag_ok
        \\    ok10 = and ok09, find_idx_ok
        \\    ok11 = and ok10, rfind_flag_ok
        \\    ok12 = and ok11, rfind_idx_ok
        \\    ok13 = and ok12, find_miss_flag_ok
        \\    ok14 = and ok13, find_miss_idx_ok
        \\    ok15 = and ok14, rfind_miss_flag_ok
        \\    ok = and ok15, rfind_miss_idx_ok
        \\    !len
        \\    !ptr
        \\    !as_ptr
        \\    !bytes
        \\    !str_view
        \\    !bytes_len
        \\    !str_len
        \\    !word_empty
        \\    !empty_ok
        \\    !new_empty_ok
        \\    !str_empty_ok
        \\    !find_ok
        \\    !find_idx
        \\    !rfind_ok
        \\    !rfind_idx
        \\    !find_miss_ok
        \\    !find_miss_idx
        \\    !rfind_miss_ok
        \\    !rfind_miss_idx
        \\    !len_ok
        \\    !ptr_ok
        \\    !as_ptr_ok
        \\    !bytes_len_ok
        \\    !str_len_ok
        \\    !word_not_empty
        \\    !find_flag_ok
        \\    !find_idx_ok
        \\    !rfind_flag_ok
        \\    !rfind_idx_ok
        \\    !find_miss_flag_ok
        \\    !find_miss_idx_ok
        \\    !rfind_miss_flag_ok
        \\    !rfind_miss_idx_ok
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
        \\    !ok15
        \\    !word
        \\    !empty
        \\    !infix
        \\    !miss
        \\    !new_empty
        \\    !str_empty
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
            try std.testing.expectEqual(@as(usize, 1), owned.function_sigs.len);
        },
        .trap => |report| {
            std.debug.print("string macro verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}
