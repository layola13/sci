const std = @import("std");
const common = @import("std_smoke_common.zig");
const saasm = common.saasm;

fn flattenFixture(allocator: std.mem.Allocator, path: []const u8, source: []const u8) !saasm.flattener.FlattenResult {
    return try saasm.flattener.flattenFile(allocator, path, source);
}

test "sa_std core primitives are concrete and verifiable" {
    const slice_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/slice.sal");
    defer std.testing.allocator.free(slice_layout);
    try std.testing.expectEqualStrings(
        "#def Slice_SIZE = 16\n#def Slice_ptr  = +0\n#def Slice_len  = +8\n",
        slice_layout,
    );

    const slice_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/slice.sa");
    defer std.testing.allocator.free(slice_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_LEN"));

    var slice_flat = try saasm.flattener.flatten(std.testing.allocator, slice_src);
    defer slice_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.function_sigs.len);

    const mem_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/mem.sa");
    defer std.testing.allocator.free(mem_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_copy"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_set"));
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

test "sa_std package manifest parses as an empty package boundary" {
    const manifest_src = try common.readFileAlloc(std.testing.allocator, "sa_std/sa.mod");
    defer std.testing.allocator.free(manifest_src);

    var manifest_file = try saasm.pkg.manifest.parseManifestWithFile(std.testing.allocator, manifest_src, "sa_std/sa.mod");
    defer manifest_file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), manifest_file.requires.len);
    try std.testing.expectEqual(@as(usize, 0), manifest_file.mirrors.len);
}

test "sa_std rust core helpers are concrete and verifiable" {
    const option_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/option.sal");
    defer std.testing.allocator.free(option_layout);
    try std.testing.expectEqualStrings(
        "#def Option_SIZE = 16\n#def Option_tag = +0\n#def Option_value = +8\n#def Option_NONE = 0\n#def Option_SOME = 1\n",
        option_layout,
    );

    const result_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/result.sal");
    defer std.testing.allocator.free(result_layout);
    try std.testing.expectEqualStrings(
        "#def Result_SIZE = 24\n#def Result_tag = +0\n#def Result_ok = +8\n#def Result_err = +16\n#def Result_OK = 0\n#def Result_ERR = 1\n",
        result_layout,
    );

    const iter_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/iter.sal");
    defer std.testing.allocator.free(iter_layout);
    try std.testing.expectEqualStrings(
        "#def Iter_SIZE = 24\n#def Iter_ptr = +0\n#def Iter_len = +8\n#def Iter_index = +16\n",
        iter_layout,
    );

    const option_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/option.sa");
    defer std.testing.allocator.free(option_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_NEW_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_NEW_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_IS_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_IS_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP_OR_RETURN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MAP_OR_ELSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_SET_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_BRANCH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] MATCHES_OPTION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] MATCH_OPTION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MATCH_SOME_NONE"));

    const result_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/result.sa");
    defer std.testing.allocator.free(result_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_NEW_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_NEW_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_IS_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_IS_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_GET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_GET_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_RETURN_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OR_ELSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_SET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_SET_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_BRANCH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] MATCH_RESULT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] MATCHES_RESULT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MATCH_OK_ERR"));

    const stringify_src = try common.readFileAlloc(std.testing.allocator, "src/flattener.zig");
    defer std.testing.allocator.free(stringify_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, stringify_src, 1, "STRINGIFY!"));

    const sa_core_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/sa_core.sa");
    defer std.testing.allocator.free(sa_core_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, sa_core_src, 1, "[MACRO] CFG"));

    const panic_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/panic.sa");
    defer std.testing.allocator.free(panic_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] PANIC "));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] PANIC_MSG"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] TODO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] UNIMPLEMENTED"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] UNREACHABLE"));

    const iter_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/iter.sa");
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

    const loop_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/loop.sa");
    defer std.testing.allocator.free(loop_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] WHILE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] WHILE_COND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] FOR_RANGE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] INDEX_LOOP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] ARRAY_SCAN_MIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] ARRAY_SCAN_MAX"));

    const control_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/control.sa");
    defer std.testing.allocator.free(control_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] MATCH_BOOL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] ELIF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] WHILE_LET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] BREAK_IF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] CONTINUE_IF"));

    const bit_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/bit.sa");
    defer std.testing.allocator.free(bit_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_MASK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_SET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_TEST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_INDEX_BYTE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_INDEX_BIT"));

    const hash_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/hash.sa");
    defer std.testing.allocator.free(hash_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] HASH_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] HASH_MIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] HASH_MOD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] PROBE_START"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] PROBE_NEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] MAP_LOOKUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] MAP_INSERT_OR_UPDATE"));

    const cleanup_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cleanup.sa");
    defer std.testing.allocator.free(cleanup_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] DEFER"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] CLEANUP_ON_ERROR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] WITH_TEMP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] RETURN_CLEAN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] FREE_AND_RETURN"));

    const rust_core_src = try common.readFileAlloc(std.testing.allocator, "sa_std/rust_core.sa");
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
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/loop.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/control.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/bit.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/hash.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/cleanup.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"sync/rwlock.sa\""));

    const cell_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell.sal");
    defer std.testing.allocator.free(cell_layout);
    try std.testing.expectEqualStrings("#def Cell_SIZE = 4\n#def Cell_value = +0\n", cell_layout);

    const refcell_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/refcell.sal");
    defer std.testing.allocator.free(refcell_layout);
    try std.testing.expectEqualStrings("#def RefCell_SIZE = 8\n#def RefCell_value = +0\n#def RefCell_borrows = +4\n", refcell_layout);

    const rc_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/rc.sal");
    defer std.testing.allocator.free(rc_layout);
    try std.testing.expectEqualStrings("#def RcBox_SIZE = 24\n#def RcBox_strong = +0\n#def RcBox_weak = +8\n#def RcBox_data = +16\n", rc_layout);

    const weak_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/weak.sal");
    defer std.testing.allocator.free(weak_layout);
    try std.testing.expectEqualStrings("#def WeakBox_SIZE = 24\n#def WeakBox_strong = +0\n#def WeakBox_weak = +8\n#def WeakBox_data = +16\n", weak_layout);

    const cell_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell.sa");
    defer std.testing.allocator.free(cell_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_SET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_REPLACE"));

    const refcell_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/refcell.sa");
    defer std.testing.allocator.free(refcell_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_BORROW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_BORROW_MUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_RELEASE"));

    const derive_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/derive.sa");
    defer std.testing.allocator.free(derive_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_COPY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_EQ_FIELD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_EQ4"));

    const rc_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/rc.sa");
    defer std.testing.allocator.free(rc_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_CLONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_DROP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_DOWNGRADE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_CLONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_DROP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_UPGRADE"));

    const weak_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/weak.sa");
    defer std.testing.allocator.free(weak_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, weak_src, 1, "@import \"weak.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, weak_src, 1, "@import \"rc.sa\""));

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

    var rust_core_flat = try flattenFixture(std.testing.allocator, "sa_std/rust_core.sa", rust_core_src);
    defer rust_core_flat.deinit(std.testing.allocator);
    try std.testing.expect(rust_core_flat.instructions.len > 0);
    try std.testing.expect(rust_core_flat.function_sigs.len > 0);
    try std.testing.expect(rust_core_flat.instructions.len >= 1);
}
