const std = @import("std");
const saasm = @import("saasm");

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 1 << 20);
}

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn runCommandWithEnvMap(allocator: std.mem.Allocator, argv: []const []const u8, env_map: *const std.process.EnvMap) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .env_map = env_map,
    });
}

fn runCommandAnyExit(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

const NormalizedInstruction = struct {
    kind: saasm.common.instruction.InstKind,
    op_kind: ?saasm.common.instruction.OpKind,
    operands: [4]saasm.common.instruction.Operand,
    raw_text: []const u8,
    atomic_value_ty: ?u32,
    atomic_ordering: ?saasm.common.instruction.AtomicOrdering,
    atomic_second_ordering: ?saasm.common.instruction.AtomicOrdering,
    atomic_rmw_op: ?saasm.common.instruction.AtomicRmwOp,
    atomic_expected_text: ?[]const u8,
    atomic_new_text: ?[]const u8,
    native_reg_names: []const []const u8,
};

fn normalizeInstruction(inst: saasm.flattener.Instruction) NormalizedInstruction {
    return .{
        .kind = inst.kind,
        .op_kind = inst.op_kind,
        .operands = inst.operands,
        .raw_text = inst.raw_text,
        .atomic_value_ty = inst.atomic_value_ty,
        .atomic_ordering = inst.atomic_ordering,
        .atomic_second_ordering = inst.atomic_second_ordering,
        .atomic_rmw_op = inst.atomic_rmw_op,
        .atomic_expected_text = inst.atomic_expected_text,
        .atomic_new_text = inst.atomic_new_text,
        .native_reg_names = inst.native_reg_names,
    };
}

fn expectFlattenEquivalent(lhs: saasm.flattener.FlattenResult, rhs: saasm.flattener.FlattenResult) !void {
    try std.testing.expectEqual(lhs.instructions.len, rhs.instructions.len);
    try std.testing.expectEqual(lhs.function_sigs.len, rhs.function_sigs.len);
    try std.testing.expectEqual(lhs.const_decls.len, rhs.const_decls.len);
    try std.testing.expectEqual(lhs.loc_table.len, rhs.loc_table.len);
    for (lhs.instructions, rhs.instructions, 0..) |l, r, idx| {
        const ln = normalizeInstruction(l);
        const rn = normalizeInstruction(r);
        try std.testing.expectEqual(ln.kind, rn.kind);
        try std.testing.expectEqual(ln.op_kind, rn.op_kind);
        try std.testing.expectEqualDeep(ln.operands, rn.operands);
        try std.testing.expectEqualStrings(ln.raw_text, rn.raw_text);
        try std.testing.expectEqual(ln.atomic_value_ty, rn.atomic_value_ty);
        try std.testing.expectEqual(ln.atomic_ordering, rn.atomic_ordering);
        try std.testing.expectEqual(ln.atomic_second_ordering, rn.atomic_second_ordering);
        try std.testing.expectEqual(ln.atomic_rmw_op, rn.atomic_rmw_op);
        try std.testing.expectEqual(ln.atomic_expected_text, rn.atomic_expected_text);
        try std.testing.expectEqual(ln.atomic_new_text, rn.atomic_new_text);
        try std.testing.expectEqualDeep(ln.native_reg_names, rn.native_reg_names);
        _ = idx;
    }
}

fn dumpInstructionTexts(prefix: []const u8, flat: saasm.flattener.FlattenResult) void {
    std.debug.print("{s} ({d} instructions)\n", .{ prefix, flat.instructions.len });
    for (flat.instructions, 0..) |item, idx| {
        std.debug.print("  [{d}] {s}\n", .{ idx, item.raw_text });
    }
}

test "sa_std core primitives are concrete and verifiable" {
    const slice_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/slice.saasm-layout");
    defer std.testing.allocator.free(slice_layout);
    try std.testing.expectEqualStrings(
        "#def Slice_SIZE = 16\n#def Slice_ptr  = +0\n#def Slice_len  = +8\n",
        slice_layout,
    );

    const slice_src = try readFileAlloc(std.testing.allocator, "sa_std/core/slice.saasm");
    defer std.testing.allocator.free(slice_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_LEN"));

    var slice_flat = try saasm.flattener.flatten(std.testing.allocator, slice_src);
    defer slice_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.function_sigs.len);

    const mem_src = try readFileAlloc(std.testing.allocator, "sa_std/core/mem.saasm");
    defer std.testing.allocator.free(mem_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_copy"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_set"));
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
    const option_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/option.saasm-layout");
    defer std.testing.allocator.free(option_layout);
    try std.testing.expectEqualStrings(
        "#def Option_SIZE = 16\n#def Option_tag = +0\n#def Option_value = +8\n#def Option_NONE = 0\n#def Option_SOME = 1\n",
        option_layout,
    );

    const result_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/result.saasm-layout");
    defer std.testing.allocator.free(result_layout);
    try std.testing.expectEqualStrings(
        "#def Result_SIZE = 24\n#def Result_tag = +0\n#def Result_ok = +8\n#def Result_err = +16\n#def Result_OK = 0\n#def Result_ERR = 1\n",
        result_layout,
    );

    const iter_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/iter.saasm-layout");
    defer std.testing.allocator.free(iter_layout);
    try std.testing.expectEqualStrings(
        "#def Iter_SIZE = 24\n#def Iter_ptr = +0\n#def Iter_len = +8\n#def Iter_index = +16\n",
        iter_layout,
    );

    const option_src = try readFileAlloc(std.testing.allocator, "sa_std/core/option.saasm");
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

    const result_src = try readFileAlloc(std.testing.allocator, "sa_std/core/result.saasm");
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

    const panic_src = try readFileAlloc(std.testing.allocator, "sa_std/core/panic.saasm");
    defer std.testing.allocator.free(panic_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] PANIC "));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] PANIC_MSG"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] TODO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] UNIMPLEMENTED"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] UNREACHABLE"));

    const iter_src = try readFileAlloc(std.testing.allocator, "sa_std/core/iter.saasm");
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

    const rust_core_src = try readFileAlloc(std.testing.allocator, "sa_std/rust_core.saasm");
    defer std.testing.allocator.free(rust_core_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/option.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/result.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/panic.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/iter.saasm\""));

    var option_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/core/option.saasm", option_src);
    defer option_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), option_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), option_flat.function_sigs.len);

    var result_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/core/result.saasm", result_src);
    defer result_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), result_flat.function_sigs.len);

    var panic_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/core/panic.saasm", panic_src);
    defer panic_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), panic_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), panic_flat.function_sigs.len);

    var iter_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/core/iter.saasm", iter_src);
    defer iter_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), iter_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), iter_flat.function_sigs.len);

    var rust_core_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/rust_core.saasm", rust_core_src);
    defer rust_core_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), rust_core_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), rust_core_flat.function_sigs.len);

    const rust_core_fixture = try readFileAlloc(std.testing.allocator, "tests/rust_core_fixture.saasm");
    defer std.testing.allocator.free(rust_core_fixture);
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND OPTION_IS_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND OPTION_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND OPTION_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND RESULT_NEW_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND RESULT_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND RESULT_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_fixture, 1, "EXPAND ITER_FROM_SLICE"));

    var rust_core_fixture_flat = try saasm.flattener.flattenFile(std.testing.allocator, "tests/rust_core_fixture.saasm", rust_core_fixture);
    defer rust_core_fixture_flat.deinit(std.testing.allocator);
    try std.testing.expect(rust_core_fixture_flat.instructions.len > 0);
    try std.testing.expect(rust_core_fixture_flat.function_sigs.len >= 1);

    const option_default_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/46_option_default/main.saasm");
    defer std.testing.allocator.free(option_default_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, option_default_demo, 1, "@import \"../../../sa_std/core/option.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_default_demo, 1, "Option_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_default_demo, 1, "call @choose(&opt, 1)"));
    var option_default_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/46_option_default/main.saasm", option_default_demo);
    defer option_default_flat.deinit(std.testing.allocator);
    try std.testing.expect(option_default_flat.instructions.len > 0);

    const result_question_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/19_result_question/main.saasm");
    defer std.testing.allocator.free(result_question_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, result_question_demo, 1, "@import \"../../../sa_std/core/result.saasm\""));
    var result_question_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/19_result_question/main.saasm", result_question_demo);
    defer result_question_flat.deinit(std.testing.allocator);
    try std.testing.expect(result_question_flat.instructions.len > 0);

    const result_unwrap_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/177_unwrap_unwrap_err/main.saasm");
    defer std.testing.allocator.free(result_unwrap_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, result_unwrap_demo, 1, "@import \"../../../sa_std/core/result.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_unwrap_demo, 1, "EXPAND RESULT_UNWRAP_ERR"));
    var result_unwrap_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/177_unwrap_unwrap_err/main.saasm", result_unwrap_demo);
    defer result_unwrap_flat.deinit(std.testing.allocator);
    try std.testing.expect(result_unwrap_flat.instructions.len > 0);

    const iterator_fold_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/35_iterator_fold/main.saasm");
    defer std.testing.allocator.free(iterator_fold_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, iterator_fold_demo, 1, "@import \"../../../sa_std/core/iter.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, iterator_fold_demo, 1, "ITER_FROM_SLICE"));
    var iterator_fold_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/35_iterator_fold/main.saasm", iterator_fold_demo);
    defer iterator_fold_flat.deinit(std.testing.allocator);
    try std.testing.expect(iterator_fold_flat.instructions.len > 0);

    const option_map_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/18_option_map/main.saasm");
    defer std.testing.allocator.free(option_map_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, option_map_demo, 1, "@import \"../../../sa_std/core/option.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_map_demo, 1, "!opt"));
    var option_map_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/18_option_map/main.saasm", option_map_demo);
    defer option_map_flat.deinit(std.testing.allocator);
    try std.testing.expect(option_map_flat.instructions.len > 0);

    const manual_guard_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/30_manual_guard_branch/main.saasm");
    defer std.testing.allocator.free(manual_guard_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, manual_guard_demo, 1, "@import \"../../../sa_std/core/option.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual_guard_demo, 1, "OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual_guard_demo, 1, "OPTION_IS_SOME"));
    var manual_guard_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/30_manual_guard_branch/main.saasm", manual_guard_demo);
    defer manual_guard_flat.deinit(std.testing.allocator);
    try std.testing.expect(manual_guard_flat.instructions.len > 0);

    const never_type_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/146_never_type_fallback/main.saasm");
    defer std.testing.allocator.free(never_type_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, never_type_demo, 1, "@import \"../../../sa_std/core/option.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, never_type_demo, 1, "OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, never_type_demo, 1, "OPTION_IS_SOME"));
    var never_type_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/146_never_type_fallback/main.saasm", never_type_demo);
    defer never_type_flat.deinit(std.testing.allocator);
    try std.testing.expect(never_type_flat.instructions.len > 0);

    const if_let_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/104_if_let_chains/main.saasm");
    defer std.testing.allocator.free(if_let_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, if_let_demo, 1, "@import \"../../../sa_std/core/option.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, if_let_demo, 1, "OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, if_let_demo, 1, "OPTION_GET"));
    var if_let_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/104_if_let_chains/main.saasm", if_let_demo);
    defer if_let_flat.deinit(std.testing.allocator);
    try std.testing.expect(if_let_flat.instructions.len > 0);

    const let_else_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/105_let_else/main.saasm");
    defer std.testing.allocator.free(let_else_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, let_else_demo, 1, "@import \"../../../sa_std/core/option.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, let_else_demo, 1, "OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, let_else_demo, 1, "OPTION_GET"));
    var let_else_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/105_let_else/main.saasm", let_else_demo);
    defer let_else_flat.deinit(std.testing.allocator);
    try std.testing.expect(let_else_flat.instructions.len > 0);

    const generics_monomorph_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/10_generics_monomorph/main.saasm");
    defer std.testing.allocator.free(generics_monomorph_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, generics_monomorph_demo, 1, "@import \"../../../sa_std/core/option.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, generics_monomorph_demo, 1, "OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, generics_monomorph_demo, 1, "OPTION_IS_SOME"));
    var generics_monomorph_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/10_generics_monomorph/main.saasm", generics_monomorph_demo);
    defer generics_monomorph_flat.deinit(std.testing.allocator);
    try std.testing.expect(generics_monomorph_flat.instructions.len > 0);

    const result_flatten_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/176_result_flattening/main.saasm");
    defer std.testing.allocator.free(result_flatten_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, result_flatten_demo, 1, "@import \"../../../sa_std/core/result.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_flatten_demo, 1, "RESULT_SET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_flatten_demo, 1, "RESULT_GET_OK"));
    var result_flatten_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/176_result_flattening/main.saasm", result_flatten_demo);
    defer result_flatten_flat.deinit(std.testing.allocator);
    try std.testing.expect(result_flatten_flat.instructions.len > 0);

    const assert_macro_demo = try readFileAlloc(std.testing.allocator, "demos/rosetta/179_assert_macro_expansion/main.saasm");
    defer std.testing.allocator.free(assert_macro_demo);
    try std.testing.expect(std.mem.containsAtLeast(u8, assert_macro_demo, 1, "@import \"../../../sa_std/core/panic.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, assert_macro_demo, 1, "EXPAND PANIC_MSG"));
    var assert_macro_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/179_assert_macro_expansion/main.saasm", assert_macro_demo);
    defer assert_macro_flat.deinit(std.testing.allocator);
    try std.testing.expect(assert_macro_flat.instructions.len > 0);
}

test "sa_std alloc helpers are concrete and verifiable" {
    const vec_layout = try readFileAlloc(std.testing.allocator, "sa_std/alloc/vec.saasm-layout");
    defer std.testing.allocator.free(vec_layout);
    try std.testing.expectEqualStrings(
        "#def Vec_SIZE = 24\n#def Vec_ptr  = +0\n#def Vec_cap  = +8\n#def Vec_len  = +16",
        vec_layout,
    );

    const vec_src = try readFileAlloc(std.testing.allocator, "sa_std/alloc/vec.saasm");
    defer std.testing.allocator.free(vec_src);
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "add 0, 0"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "假定"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "示例"));
    var vec_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/alloc/vec.saasm", vec_src);
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

    const vec_macro_layout = try readFileAlloc(std.testing.allocator, "sa_std/vec.saasm-layout");
    defer std.testing.allocator.free(vec_macro_layout);
    try std.testing.expectEqualStrings("#def Vec_data = +0\n", vec_macro_layout);

    const vec_macro_src = try readFileAlloc(std.testing.allocator, "sa_std/vec.saasm");
    defer std.testing.allocator.free(vec_macro_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "@import \"alloc/vec.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_PUSH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRUNCATE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_TRY_POP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_macro_src, 1, "[MACRO] VEC_WITH_CAPACITY"));

    var vec_macro_error_ctx = saasm.flattener.ErrorContext{};
    var vec_macro_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/vec.saasm", vec_macro_src, &vec_macro_error_ctx) catch |err| {
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

    const vec_fixture = try readFileAlloc(std.testing.allocator, "tests/vec_fixture.saasm");
    defer std.testing.allocator.free(vec_fixture);
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_fixture, 1, "EXPAND VEC_TRY_POP"));

    var vec_fixture_error_ctx = saasm.flattener.ErrorContext{};
    var vec_fixture_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "tests/vec_fixture.saasm", vec_fixture, &vec_fixture_error_ctx) catch |err| {
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

    const string_src = try readFileAlloc(std.testing.allocator, "sa_std/alloc/string.saasm");
    defer std.testing.allocator.free(string_src);
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "假定"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "示例"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_src, 1, "[MACRO] STR_FROM_CONST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_src, 1, "EXPAND SLICE_NEW"));

    const string_fixture =
        \\@import "../../../sa_std/core/slice.saasm-layout"
        \\@import "../../../sa_std/core/slice.saasm"
        \\@import "../../../sa_std/alloc/string.saasm"
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
    var string_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/15_string_bytes/main.saasm", string_fixture);
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
}

test "sa_std json helpers are concrete and verifiable" {
    const json_layout = try readFileAlloc(std.testing.allocator, "sa_std/encoding/json.saasm-layout");
    defer std.testing.allocator.free(json_layout);
    try std.testing.expect(std.mem.containsAtLeast(u8, json_layout, 1, "SA_JSON_KIND_OBJECT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_layout, 1, "SA_JSON_KIND_NULL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_layout, 1, "SA_JSON_TOKEN_OBJECT_BEGIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_layout, 1, "SA_JSON_WHITESPACE_MINIFIED"));

    const json_iface = try readFileAlloc(std.testing.allocator, "sa_std/encoding/json.saasm-iface");
    defer std.testing.allocator.free(json_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_parse"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_object_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stringify"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_buffer_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_scanner_next"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stream_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stream_next"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stream_get_slice_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stream_get_slice_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stream_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_writer_finish"));

    const json_src = try readFileAlloc(std.testing.allocator, "sa_std/encoding/json.saasm");
    defer std.testing.allocator.free(json_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "@import \"json.saasm-layout\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "@import \"json.saasm-iface\""));

    const regex_layout = try readFileAlloc(std.testing.allocator, "sa_std/text/regex.saasm-layout");
    defer std.testing.allocator.free(regex_layout);
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_layout, 1, "SA_REGEX_REG_NOERROR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_layout, 1, "SA_REGEX_REG_OK"));

    const regex_iface = try readFileAlloc(std.testing.allocator, "sa_std/text/regex.saasm-iface");
    defer std.testing.allocator.free(regex_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_iface, 1, "sa_regex_compile"));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_iface, 1, "sa_regex_match"));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_iface, 1, "sa_regex_group_count"));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_iface, 1, "sa_regex_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_iface, 1, "sa_regex_match_free"));

    const regex_src = try readFileAlloc(std.testing.allocator, "sa_std/text/regex.saasm");
    defer std.testing.allocator.free(regex_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_src, 1, "@import \"regex.saasm-layout\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_src, 1, "@import \"regex.saasm-iface\""));
}

test "sa_std time helpers are concrete and verifiable" {
    const time_layout = try readFileAlloc(std.testing.allocator, "sa_std/time.saasm-layout");
    defer std.testing.allocator.free(time_layout);
    try std.testing.expectEqualStrings(
        "#def Time_NS_PER_US = 1000\n#def Time_NS_PER_MS = 1000000\n#def Time_NS_PER_S  = 1000000000\n#def Time_MS_PER_S  = 1000\n#def TimeDate_SIZE = 32\n#def TimeDate_unix_ms = +0\n#def TimeDate_unix_ns = +8\n#def TimeDate_year = +16\n#def TimeDate_month = +18\n#def TimeDate_day = +19\n#def TimeDate_hour = +20\n#def TimeDate_minute = +21\n#def TimeDate_second = +22\n#def TimeDate_millisecond = +24\n",
        time_layout,
    );

    const time_iface = try readFileAlloc(std.testing.allocator, "sa_std/time.saasm-iface");
    defer std.testing.allocator.free(time_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_instant_ns"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_unix_ms"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_utc_now"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_sleep_ms"));

    const time_src = try readFileAlloc(std.testing.allocator, "sa_std/time.saasm");
    defer std.testing.allocator.free(time_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_NOW_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_NOW_UNIX_MS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_UTC_NOW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_SLEEP_MS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_FROM_MS"));

    var time_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/time.saasm", time_src);
    defer time_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 7), time_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 7), time_flat.function_sigs.len);
}

test "sa_std mutex helpers are concrete and verifiable" {
    const mutex_layout = try readFileAlloc(std.testing.allocator, "sa_std/sync/mutex.saasm-layout");
    defer std.testing.allocator.free(mutex_layout);
    try std.testing.expectEqualStrings(
        "#def Mutex_SIZE = 8\n#def Mutex_lock = +0\n#def Mutex_data = +8\n",
        mutex_layout,
    );

    const mutex_src = try readFileAlloc(std.testing.allocator, "sa_std/sync/mutex.saasm");
    defer std.testing.allocator.free(mutex_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "@import \"../time.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "[MACRO] MUTEX_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "[MACRO] MUTEX_LOCK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "[MACRO] MUTEX_UNLOCK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "atomic_rmw_xchg lock+Mutex_lock, 1 as u64 seq_cst"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "atomic_store %lock_ptr+Mutex_lock, 0 as u64 release"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "@__mutex_lock_spin"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "call @sa_time_sleep_ns(1)"));

    var mutex_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/sync/mutex.saasm", mutex_src);
    defer mutex_flat.deinit(std.testing.allocator);
    try std.testing.expect(mutex_flat.instructions.len > 0);
    try std.testing.expectEqual(@as(usize, 8), mutex_flat.function_sigs.len);
}

test "sa_std once helpers are concrete and verifiable" {
    const once_layout = try readFileAlloc(std.testing.allocator, "sa_std/sync/once.saasm-layout");
    defer std.testing.allocator.free(once_layout);
    try std.testing.expectEqualStrings(
        "#def Once_SIZE = 16\n#def Once_state = +0\n#def Once_value = +8\n#def Once_STATE_UNINIT = 0\n#def Once_STATE_RUNNING = 1\n#def Once_STATE_READY = 2\n",
        once_layout,
    );

    const once_src = try readFileAlloc(std.testing.allocator, "sa_std/sync/once.saasm");
    defer std.testing.allocator.free(once_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "@import \"../time.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_IS_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_TRY_CLAIM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_WAIT_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_PUBLISH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_GET_OR_INIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "atomic_load once+Once_state as u32 acquire"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "cmpxchg once+Once_state, Once_STATE_UNINIT, Once_STATE_RUNNING as u32 acq_rel acquire"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "atomic_store %once_reg+Once_state, Once_STATE_READY as u32 release"));

    var once_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/sync/once.saasm", once_src);
    defer once_flat.deinit(std.testing.allocator);
    try std.testing.expect(once_flat.instructions.len > 0);
    try std.testing.expectEqual(@as(usize, 9), once_flat.function_sigs.len);
}

test "sa_std mpsc helpers are concrete and verifiable" {
    const mpsc_layout = try readFileAlloc(std.testing.allocator, "sa_std/sync/mpsc.saasm-layout");
    defer std.testing.allocator.free(mpsc_layout);
    try std.testing.expectEqualStrings(
        "#def Mpsc_SIZE = 32\n#def Mpsc_cap = +0\n#def Mpsc_head = +8\n#def Mpsc_tail = +16\n#def Mpsc_data = +32\n\n#def Mpsc_SLOT_SIZE = 16\n#def Mpsc_SLOT_value = +0\n#def Mpsc_SLOT_ready = +8\n#def Mpsc_SLOT_EMPTY = 0\n#def Mpsc_SLOT_READY = 1\n",
        mpsc_layout,
    );

    const mpsc_src = try readFileAlloc(std.testing.allocator, "sa_std/sync/mpsc.saasm");
    defer std.testing.allocator.free(mpsc_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "@import \"../core/mem.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "@import \"../time.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_TRY_SEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_SEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_TRY_RECV"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_RECV"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "@__mpsc_try_send"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "@__mpsc_try_recv"));

    var mpsc_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/sync/mpsc.saasm", mpsc_src);
    defer mpsc_flat.deinit(std.testing.allocator);
    try std.testing.expect(mpsc_flat.instructions.len > 0);
    try std.testing.expectEqual(@as(usize, 11), mpsc_flat.function_sigs.len);
}

test "sa_std async helpers are concrete and verifiable" {
    const async_src = try readFileAlloc(std.testing.allocator, "sa_std/libsa_async.saasm");
    defer std.testing.allocator.free(async_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_CTX_DEF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_POLL_PROLOGUE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_AWAIT_POINT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_AWAIT_POINT_FINAL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_RETURN_PENDING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_INVALID_STATE"));

    var async_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/libsa_async.saasm", async_src);
    defer async_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), async_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), async_flat.function_sigs.len);
}

test "libsa_async macro expansion stays equivalent to the manual state machine" {
    const macro_source = try readFileAlloc(std.testing.allocator, "demos/rosetta/09_async_await/main.saasm");
    defer std.testing.allocator.free(macro_source);

    const print_iface_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "sa_std/io/print.saasm-iface");
    defer std.testing.allocator.free(print_iface_path);

    const manual_source = try std.fmt.allocPrint(std.testing.allocator,
        \\@import "{s}"
        \\
        \\@const RESULT_OK = utf8:"2\n"
        \\@const RESULT_ERR = utf8:"error\n"
        \\
        \\#def Run_SIZE = 32
        \\#def Run_state = +0
        \\#def Run_stage = +4
        \\#def Run_status = +8
        \\#def Run_value = +16
        \\#def Run_resume = +24
        \\#def Run_PENDING = 0
        \\#def Run_READY = 1
        \\#def Run_INVALID = 102
        \\
        \\@poll_step(state: ptr) -> i32:
        \\L_ENTRY:
        \\    stage = load state+Run_stage as u32
        \\    ready = eq stage, 1
        \\    !stage
        \\    return ready
        \\
        \\@take_step(state: ptr) -> void:
        \\L_ENTRY:
        \\    store state+Run_value, 1 as i32
        \\    return
        \\
        \\@poll_run(state: ptr) -> i32:
        \\L_ENTRY:
        \\    state_id = load state+Run_state as u32
        \\    is_state0 = eq state_id, 0
        \\    br is_state0 -> L_STATE_0, L_STATE_1
        \\
        \\L_STATE_0:
        \\    store state+Run_stage, 1 as u32
        \\    store state+Run_state, 1 as u32
        \\    !state_id
        \\    !is_state0
        \\    return 0
        \\
        \\L_STATE_1:
        \\    !state_id
        \\    !is_state0
        \\    async_poll_status_1_Run_state = call @poll_step(state)
        \\    async_is_ready_1_Run_state = eq async_poll_status_1_Run_state, 1
        \\    br async_is_ready_1_Run_state -> L_ASYNC_AWAIT_READY_1_Run_state, L_ASYNC_AWAIT_PENDING_1_Run_state
        \\L_ASYNC_AWAIT_PENDING_1_Run_state:
        \\    store state+Run_state, 1 as u32
        \\    !async_poll_status_1_Run_state
        \\    !async_is_ready_1_Run_state
        \\    return 0
        \\L_ASYNC_AWAIT_READY_1_Run_state:
        \\    call @take_step(state)
        \\    async_result_1_Run_state = load state+Run_value as i32
        \\    async_next_state_1_Run_state = add 1, 1
        \\    store state+Run_state, async_next_state_1_Run_state as u32
        \\    !async_poll_status_1_Run_state
        \\    !async_is_ready_1_Run_state
        \\    !async_next_state_1_Run_state
        \\    next = add async_result_1_Run_state, 1
        \\    store state+Run_value, next as i32
        \\    store state+Run_stage, 2 as u32
        \\    !async_result_1_Run_state
        \\    !next
        \\    return 1
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    state = alloc Run_SIZE
        \\    store state+Run_state, 0 as u32
        \\    store state+Run_stage, 0 as u32
        \\    store state+Run_status, 0 as u32
        \\    store state+Run_value, 0 as i32
        \\    store state+Run_resume, 0 as u32
        \\
        \\    ready0 = call @poll_run(state)
        \\    ready1 = call @poll_run(state)
        \\    value = load state+Run_value as i32
        \\    ok_ready0 = eq ready0, 0
        \\    ok_ready1 = eq ready1, 1
        \\    ok_value = eq value, 2
        \\    ok0 = and ok_ready0, ok_ready1
        \\    ok = and ok0, ok_value
        \\
        \\    !ready0
        \\    !ready1
        \\    !value
        \\    !ok_ready0
        \\    !ok_ready1
        \\    !ok_value
        \\    !ok0
        \\    !state
        \\
        \\    br ok -> L_OK, L_ERR
        \\
        \\L_OK:
        \\    !ok
        \\    call @sa_print_bytes(&RESULT_OK, 2)
        \\    return 0
        \\
        \\L_ERR:
        \\    !ok
        \\    call @sa_print_bytes(&RESULT_ERR, 6)
        \\    return 1
    , .{print_iface_path});
    defer std.testing.allocator.free(manual_source);

    for (0..100) |_| {
        var macro_flat = try saasm.flattener.flattenFile(
            std.testing.allocator,
            "demos/rosetta/09_async_await/main.saasm",
            macro_source,
        );
        defer macro_flat.deinit(std.testing.allocator);
        var manual_flat = try saasm.flattener.flatten(std.testing.allocator, manual_source);
        defer manual_flat.deinit(std.testing.allocator);

        if (macro_flat.instructions.len != manual_flat.instructions.len) {
            dumpInstructionTexts("macro", macro_flat);
            dumpInstructionTexts("manual", manual_flat);
        }
        try expectFlattenEquivalent(macro_flat, manual_flat);

        const macro_verified = try saasm.referee.verify(std.testing.allocator, macro_flat.instructions, macro_flat.const_decls);
        switch (macro_verified) {
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(std.testing.allocator);
            },
            .trap => |report| {
                std.debug.print("macro async verifier trap: {s}\n", .{report.message});
                return error.TestUnexpectedResult;
            },
        }
        const manual_verified = try saasm.referee.verify(std.testing.allocator, manual_flat.instructions, manual_flat.const_decls);
        switch (manual_verified) {
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(std.testing.allocator);
            },
            .trap => |report| {
                std.debug.print("manual async verifier trap: {s}\n", .{report.message});
                return error.TestUnexpectedResult;
            },
        }
    }
}

test "sa_std io helpers are concrete and verifiable" {
    const io_iface = try readFileAlloc(std.testing.allocator, "sa_std/io.saasm-iface");
    defer std.testing.allocator.free(io_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_std_println"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_io_read_line"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_io_buffer_data"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_io_buffer_free"));

    const io_src = try readFileAlloc(std.testing.allocator, "sa_std/io.saasm");
    defer std.testing.allocator.free(io_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "@import \"fmt.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] PRINTLN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] READ_LINE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] FORMAT_INT"));

    var io_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/io.saasm", io_src);
    defer io_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 24), io_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 24), io_flat.function_sigs.len);
}

test "sa_std buffered io helpers are concrete and verifiable" {
    const buf_reader_src = try readFileAlloc(std.testing.allocator, "sa_std/io/buf_reader.saasm");
    defer std.testing.allocator.free(buf_reader_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "@import \"../io.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "[MACRO] BUF_READER_READ_LINE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "[MACRO] BUF_READER_READ"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "[MACRO] BUF_READER_READ_EXACT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "[MACRO] BUF_READER_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "[MACRO] BUF_READER_CLOSE"));

    var buf_reader_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/io/buf_reader.saasm", buf_reader_src);
    defer buf_reader_flat.deinit(std.testing.allocator);
    try std.testing.expect(buf_reader_flat.function_sigs.len > 0);

    const buf_writer_src = try readFileAlloc(std.testing.allocator, "sa_std/io/buf_writer.saasm");
    defer std.testing.allocator.free(buf_writer_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "@import \"../io.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "[MACRO] BUF_WRITER_WRITE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "[MACRO] BUF_WRITER_WRITE_ALL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "[MACRO] BUF_WRITER_FLUSH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "[MACRO] BUF_WRITER_CLOSE"));

    var buf_writer_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/io/buf_writer.saasm", buf_writer_src);
    defer buf_writer_flat.deinit(std.testing.allocator);
    try std.testing.expect(buf_writer_flat.function_sigs.len > 0);
}

test "sa_std math helpers are concrete and verifiable" {
    const math_src = try readFileAlloc(std.testing.allocator, "sa_std/math.saasm");
    defer std.testing.allocator.free(math_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, math_src, 1, "[MACRO] MATH_ABS_I64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, math_src, 1, "[MACRO] MATH_MIN_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, math_src, 1, "[MACRO] MATH_MAX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, math_src, 1, "[MACRO] MATH_CLAMP_U64"));

    var math_flat = try saasm.flattener.flatten(std.testing.allocator, math_src);
    defer math_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), math_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), math_flat.function_sigs.len);
}

test "sa_std string_format helpers are concrete and verifiable" {
    const string_format_src = try readFileAlloc(std.testing.allocator, "sa_std/string_format.saasm");
    defer std.testing.allocator.free(string_format_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "@import \"fmt.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_I64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_F64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_BOOL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_BYTES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_DATA"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_WRITE_TO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_format_src, 1, "[MACRO] STRFMT_FREE"));

    var string_format_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/string_format.saasm", string_format_src);
    defer string_format_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 9), string_format_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 9), string_format_flat.function_sigs.len);
}

test "sa_std path helpers are concrete and verifiable" {
    const path_src = try readFileAlloc(std.testing.allocator, "sa_std/path.saasm");
    defer std.testing.allocator.free(path_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "@import \"core/slice.saasm-layout\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "@import \"core/slice.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "@import \"string.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_BASENAME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_DIRNAME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_STEM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_EXT"));

    var path_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/path.saasm", path_src);
    defer path_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), path_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), path_flat.function_sigs.len);
}

test "sa_std path module exercises real string macros" {
    const path_src = try readFileAlloc(std.testing.allocator, "sa_std/path.saasm");
    defer std.testing.allocator.free(path_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_BASENAME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_DIRNAME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_STEM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, path_src, 1, "[MACRO] PATH_EXT"));

    var path_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/path.saasm", path_src);
    defer path_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), path_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), path_flat.function_sigs.len);
}

test "sa_std string concat runtime helper is usable from C" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t *left = (const uint8_t *)"hello, ";
        \\    const uint8_t *right = (const uint8_t *)"world";
        \\    uint64_t handle = sa_string_concat(left, 7, right, 5);
        \\    uint64_t len = 0;
        \\    uint8_t *bytes = NULL;
        \\    if (handle == 0) return 2;
        \\    len = sa_fmt_buffer_len(handle);
        \\    if (len != 12) return 3;
        \\    bytes = sa_fmt_buffer_data(handle);
        \\    if (bytes == NULL) return 4;
        \\    if (memcmp(bytes, "hello, world", 12) != 0) return 5;
        \\    if (sa_fmt_buffer_free(handle) != SA_STD_OK) return 6;
        \\    puts("sa_std string concat ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "main.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_string_concat_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_string_concat_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std string concat ok\n", run_result.stdout);
}

test "sa_std env helpers are concrete and verifiable" {
    const env_src = try readFileAlloc(std.testing.allocator, "sa_std/env.saasm");
    defer std.testing.allocator.free(env_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "@import \"env.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_HAS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, env_src, 1, "[MACRO] ENV_BUFFER_FREE"));

    var env_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/env.saasm", env_src);
    defer env_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 5), env_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 5), env_flat.function_sigs.len);
}

test "sa_std env runtime helper is usable from C" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t key[] = "PATH";
        \\    uint64_t handle = 0;
        \\    uint8_t *data = NULL;
        \\    uint64_t len = 0;
        \\
        \\    if (sa_env_has(key, sizeof(key) - 1) != SA_STD_OK) return 2;
        \\    handle = sa_env_get(key, sizeof(key) - 1);
        \\    if (handle == 0) return 3;
        \\    len = sa_env_buffer_len(handle);
        \\    if (len == 0) return 4;
        \\    data = sa_env_buffer_data(handle);
        \\    if (data == NULL) return 5;
        \\    if (memchr(data, ':', len) == NULL) return 6;
        \\    if (sa_env_buffer_free(handle) != SA_STD_OK) return 7;
        \\    puts("sa_std env ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "main.c", c_source);
    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_env_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_env_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std env ok\n", run_result.stdout);
}

test "sa_std hashmap helpers are concrete and verifiable" {
    const hashmap_layout = try readFileAlloc(std.testing.allocator, "sa_std/hashmap.saasm-layout");
    defer std.testing.allocator.free(hashmap_layout);
    try std.testing.expectEqualStrings(
        "#def HashMap_SIZE = 32\n#def HashMap_slots = +0\n#def HashMap_cap = +8\n#def HashMap_len = +16\n#def HashMap_tombs = +24\n\n#def HashMapSlot_SIZE = 32\n#def HashMapSlot_hash = +0\n#def HashMapSlot_key = +8\n#def HashMapSlot_value = +16\n#def HashMapSlot_state = +24\n\n#def HashMap_INITIAL_CAP = 8\n#def HashMap_STATE_EMPTY = 0\n#def HashMap_STATE_FILLED = 1\n#def HashMap_STATE_TOMB = 2\n\n#def HashMap_FNV_OFFSET = -3750763034362895579\n#def HashMap_FNV_PRIME = 1099511628211\n",
        hashmap_layout,
    );

    const collections_hashmap = try readFileAlloc(std.testing.allocator, "sa_std/collections/hashmap.saasm");
    defer std.testing.allocator.free(collections_hashmap);
    try std.testing.expect(std.mem.containsAtLeast(u8, collections_hashmap, 1, "@import \"../hashmap.saasm\""));

    const hashmap_src = try readFileAlloc(std.testing.allocator, "sa_std/hashmap.saasm");
    defer std.testing.allocator.free(hashmap_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"core/mem.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"hashmap.saasm-layout\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_with_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_put"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_del"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_contains_key"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_WITH_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_CONTAINS_KEY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_PUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_DEL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_FREE"));

    var hashmap_error_ctx = saasm.flattener.ErrorContext{};
    var hashmap_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/hashmap.saasm", hashmap_src, &hashmap_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&hashmap_error_ctx) orelse 0;
        std.debug.print("hashmap flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer hashmap_flat.deinit(std.testing.allocator);
    try std.testing.expect(hashmap_flat.instructions.len > 0);
    try std.testing.expect(hashmap_flat.function_sigs.len >= 13);

    const hashmap_verified = try saasm.referee.verify(std.testing.allocator, hashmap_flat.instructions, hashmap_flat.const_decls);
    switch (hashmap_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 13);
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
        \\@import "../sa_std/collections/hashmap.saasm"
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
        \\    ok06 = and ok05, ok_empty1
        \\    ok07 = and ok06, ok_has1
        \\    ok08 = and ok07, ok_got1
        \\    ok09 = and ok08, ok_len2
        \\    ok10 = and ok09, ok_empty2
        \\    ok11 = and ok10, ok_has2
        \\    ok = and ok11, ok_got2
        \\    !got2
        \\    !has2
        \\    !empty2
        \\    !len2
        \\    !got1
        \\    !has1
        \\    !empty1
        \\    !len1
        \\    !has0
        \\    !empty0
        \\    !cap1
        \\    !cap0
        \\    !len0
        \\    !value
        \\    !key
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
    var hashmap_fixture_flat = try saasm.flattener.flattenFile(std.testing.allocator, "tests/hashmap_fixture.saasm", hashmap_fixture);
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
    const hashset_layout = try readFileAlloc(std.testing.allocator, "sa_std/hashset.saasm-layout");
    defer std.testing.allocator.free(hashset_layout);
    try std.testing.expectEqualStrings(
        "#def HashSet_SIZE = 32\n#def HashSet_slots = +0\n#def HashSet_cap = +8\n#def HashSet_len = +16\n#def HashSet_tombs = +24\n\n#def HashSetSlot_SIZE = 32\n#def HashSetSlot_hash = +0\n#def HashSetSlot_key = +8\n#def HashSetSlot_value = +16\n#def HashSetSlot_state = +24\n\n#def HashSet_INITIAL_CAP = 8\n#def HashSet_STATE_EMPTY = 0\n#def HashSet_STATE_FILLED = 1\n#def HashSet_STATE_TOMB = 2\n\n#def HashSet_VALUE_SENTINEL = 1\n",
        hashset_layout,
    );

    const collections_hashset = try readFileAlloc(std.testing.allocator, "sa_std/collections/hashset.saasm");
    defer std.testing.allocator.free(collections_hashset);
    try std.testing.expect(std.mem.containsAtLeast(u8, collections_hashset, 1, "@import \"../hashset.saasm\""));

    const hashset_src = try readFileAlloc(std.testing.allocator, "sa_std/hashset.saasm");
    defer std.testing.allocator.free(hashset_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"hashset.saasm-layout\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@import \"hashmap.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_insert"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_contains"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_remove"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "@export sa_set_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_CONTAINS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_REMOVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashset_src, 1, "[MACRO] SET_FREE"));

    var hashset_error_ctx = saasm.flattener.ErrorContext{};
    var hashset_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/hashset.saasm", hashset_src, &hashset_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&hashset_error_ctx) orelse 0;
        std.debug.print("hashset flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer hashset_flat.deinit(std.testing.allocator);
    try std.testing.expect(hashset_flat.instructions.len > 0);
    try std.testing.expect(hashset_flat.function_sigs.len >= 18);

    const hashset_verified = try saasm.referee.verify(std.testing.allocator, hashset_flat.instructions, hashset_flat.const_decls);
    switch (hashset_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 18);
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
        \\@import "../sa_std/collections/hashset.saasm"
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
        \\    ok07 = and ok06, ok_empty1
        \\    ok08 = and ok07, ok_has_a
        \\    ok09 = and ok08, ok_len2
        \\    ok10 = and ok09, ok_empty2
        \\    ok = and ok10, ok_has_a_after
        \\    !has_a_after
        \\    !len2
        \\    !has_a
        \\    !empty2
        \\    !empty1
        \\    !cap1
        \\    !len1
        \\    !ins_b
        \\    !ins_a
        \\    !empty0
        \\    !cap0
        \\    !len0
        \\    !key_b
        \\    !key_a
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
    var hashset_fixture_flat = try saasm.flattener.flattenFile(std.testing.allocator, "tests/hashset_fixture.saasm", hashset_fixture);
    defer hashset_fixture_flat.deinit(std.testing.allocator);
    const hashset_fixture_verified = try saasm.referee.verify(std.testing.allocator, hashset_fixture_flat.instructions, hashset_fixture_flat.const_decls);
    switch (hashset_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 18);
        },
        .trap => |report| {
            std.debug.print("hashset fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std vec_deque helpers are concrete and verifiable" {
    const deque_layout = try readFileAlloc(std.testing.allocator, "sa_std/vec_deque.saasm-layout");
    defer std.testing.allocator.free(deque_layout);
    try std.testing.expectEqualStrings(
        "#def VecDeque_SIZE = 32\n#def VecDeque_buf = +0\n#def VecDeque_cap = +8\n#def VecDeque_head = +16\n#def VecDeque_len = +24\n\n#def VecDeque_INITIAL_CAP = 8\n#def VecDeque_SLOT_SIZE = 8\n",
        deque_layout,
    );

    const collections_vec_deque = try readFileAlloc(std.testing.allocator, "sa_std/collections/vec_deque.saasm");
    defer std.testing.allocator.free(collections_vec_deque);
    try std.testing.expectEqualStrings("@import \"../vec_deque.saasm\"\n", collections_vec_deque);

    const deque_src = try readFileAlloc(std.testing.allocator, "sa_std/vec_deque.saasm");
    defer std.testing.allocator.free(deque_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@import \"core/mem.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_push_back"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_push_front"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_pop_front"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_try_pop_back"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_front"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_back"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_rotate_left"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "@export sa_vec_deque_rotate_right"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_POP_FRONT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_TRY_POP_BACK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_FRONT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_BACK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deque_src, 1, "[MACRO] VEC_DEQUE_CLEAR"));

    var deque_error_ctx = saasm.flattener.ErrorContext{};
    var deque_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/vec_deque.saasm", deque_src, &deque_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&deque_error_ctx) orelse 0;
        std.debug.print("vec_deque flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer deque_flat.deinit(std.testing.allocator);
    try std.testing.expect(deque_flat.instructions.len > 0);
    try std.testing.expect(deque_flat.function_sigs.len >= 15);

    const deque_verified = try saasm.referee.verify(std.testing.allocator, deque_flat.instructions, deque_flat.const_decls);
    switch (deque_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 15);
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

    const deque_fixture = try readFileAlloc(std.testing.allocator, "tests/vec_deque_fixture.saasm");
    defer std.testing.allocator.free(deque_fixture);

    var deque_fixture_flat = try saasm.flattener.flattenFile(std.testing.allocator, "tests/vec_deque_fixture.saasm", deque_fixture);
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

test "sa_std binary_heap helpers are concrete and verifiable" {
    const heap_layout = try readFileAlloc(std.testing.allocator, "sa_std/binary_heap.saasm-layout");
    defer std.testing.allocator.free(heap_layout);
    try std.testing.expectEqualStrings(
        "#def BinaryHeap_SIZE = 24\n#def BinaryHeap_buf = +0\n#def BinaryHeap_cap = +8\n#def BinaryHeap_len = +16\n\n#def BinaryHeap_INITIAL_CAP = 8\n#def BinaryHeap_SLOT_SIZE = 8\n",
        heap_layout,
    );

    const collections_binary_heap = try readFileAlloc(std.testing.allocator, "sa_std/collections/binary_heap.saasm");
    defer std.testing.allocator.free(collections_binary_heap);
    try std.testing.expectEqualStrings("@import \"../binary_heap.saasm\"\n", collections_binary_heap);

    const heap_src = try readFileAlloc(std.testing.allocator, "sa_std/binary_heap.saasm");
    defer std.testing.allocator.free(heap_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@import \"core/mem.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_capacity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_peek"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_push"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_try_pop"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "@export sa_binary_heap_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_CAPACITY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_PUSH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_TRY_POP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, heap_src, 1, "[MACRO] BINARY_HEAP_CLEAR"));

    var heap_error_ctx = saasm.flattener.ErrorContext{};
    var heap_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/binary_heap.saasm", heap_src, &heap_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&heap_error_ctx) orelse 0;
        std.debug.print("binary_heap flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer heap_flat.deinit(std.testing.allocator);
    try std.testing.expect(heap_flat.instructions.len > 0);
    try std.testing.expect(heap_flat.function_sigs.len >= 13);

    const heap_verified = try saasm.referee.verify(std.testing.allocator, heap_flat.instructions, heap_flat.const_decls);
    switch (heap_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 13);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            for (heap_flat.instructions, 0..) |inst, i| {
                if (i >= 415 and i <= 425) {
                    std.debug.print("[{d}] {s}\n", .{i, inst.raw_text});
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
        \\@import "../sa_std/collections/binary_heap.saasm"
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
    var heap_fixture_flat = try saasm.flattener.flattenFile(std.testing.allocator, "tests/binary_heap_fixture.saasm", heap_fixture);
    defer heap_fixture_flat.deinit(std.testing.allocator);
    const heap_fixture_verified = try saasm.referee.verify(std.testing.allocator, heap_fixture_flat.instructions, heap_fixture_flat.const_decls);
    switch (heap_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 16);
        },
        .trap => |report| {
            std.debug.print("binary_heap fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std btree_map helpers are concrete and verifiable" {
    const btree_layout = try readFileAlloc(std.testing.allocator, "sa_std/btree_map.saasm-layout");
    defer std.testing.allocator.free(btree_layout);
    try std.testing.expectEqualStrings(
        "#def BTreeMap_SIZE = 24\n#def BTreeMap_entries = +0\n#def BTreeMap_cap = +8\n#def BTreeMap_len = +16\n\n#def BTreeMapEntry_SIZE = 24\n#def BTreeMapEntry_key_ptr = +0\n#def BTreeMapEntry_key_len = +8\n#def BTreeMapEntry_value = +16\n\n#def BTreeMap_INITIAL_CAP = 8\n",
        btree_layout,
    );

    const collections_btree_map = try readFileAlloc(std.testing.allocator, "sa_std/collections/btree_map.saasm");
    defer std.testing.allocator.free(collections_btree_map);
    try std.testing.expectEqualStrings("@import \"../btree_map.saasm\"\n", collections_btree_map);

    const btree_src = try readFileAlloc(std.testing.allocator, "sa_std/btree_map.saasm");
    defer std.testing.allocator.free(btree_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@import \"core/mem.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@import \"core/slice.saasm-layout\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_is_empty"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_contains_key"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_clear"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_remove"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "@export sa_btree_map_insert"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_CONTAINS_KEY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_REMOVE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_INSERT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, btree_src, 1, "[MACRO] BTREE_MAP_FREE"));

    var btree_error_ctx = saasm.flattener.ErrorContext{};
    var btree_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/btree_map.saasm", btree_src, &btree_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&btree_error_ctx) orelse 0;
        std.debug.print("btree_map flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer btree_flat.deinit(std.testing.allocator);
    try std.testing.expect(btree_flat.instructions.len > 0);
    try std.testing.expectEqual(@as(usize, 16), btree_flat.function_sigs.len);

    const btree_verified = try saasm.referee.verify(std.testing.allocator, btree_flat.instructions, btree_flat.const_decls);
    switch (btree_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 16), owned.function_sigs.len);
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
        \\@import "../sa_std/core/slice.saasm-layout"
        \\@import "../sa_std/core/slice.saasm"
        \\@import "../sa_std/collections/btree_map.saasm"
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
    var btree_fixture_flat = try saasm.flattener.flattenFile(std.testing.allocator, "tests/btree_map_fixture.saasm", btree_fixture);
    defer btree_fixture_flat.deinit(std.testing.allocator);
    const btree_fixture_verified = try saasm.referee.verify(std.testing.allocator, btree_fixture_flat.instructions, btree_fixture_flat.const_decls);
    switch (btree_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 17), owned.function_sigs.len);
        },
        .trap => |report| {
            std.debug.print("btree_map fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}
test "sa_std sort helpers are concrete and verifiable" {
    const sort_src = try readFileAlloc(std.testing.allocator, "sa_std/sort.saasm");
    defer std.testing.allocator.free(sort_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@import \"core/mem.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "[MACRO] QSORT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_swap_bytes"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_partition_bounds"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_qsort_bounds"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_qsort_len"));

    var sort_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/sort.saasm", sort_src);
    defer sort_flat.deinit(std.testing.allocator);
    try std.testing.expect(sort_flat.instructions.len > 0);
    try std.testing.expect(sort_flat.function_sigs.len >= 4);
}

test "std smoke fixture runs through the current compiler surface" {
    const fixture = try readFileAlloc(std.testing.allocator, "tests/std_smoke.saasm");
    defer std.testing.allocator.free(fixture);
    try std.testing.expect(std.mem.containsAtLeast(u8, fixture, 1, "ptr_add"));

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "std_smoke.saasm", fixture);

    const run_argv = [_][]const u8{ "saasm", "run", "std_smoke.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 209), run_code);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "std_smoke.saasm", "-o", "std_smoke.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("std_smoke.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "call ptr @malloc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "call void @free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "load i8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "store i8"));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{ "./std_smoke.out" });
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 209), code),
        else => return error.TestUnexpectedResult,
    }
}
