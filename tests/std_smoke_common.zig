const Std = @import("std");
const Saasm = @import("saasm");
const test_build_options = @import("test_build_options");

pub const std = Std;
pub const saasm = Saasm;

pub fn repoRoot(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.cwd().realpathAlloc(allocator, ".");
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const full_path = if (std.fs.path.isAbsolute(path)) path else try std.fs.path.join(allocator, &.{ test_build_options.repo_root, path });
    defer if (!std.fs.path.isAbsolute(path)) allocator.free(full_path);
    const file = try std.fs.cwd().openFile(full_path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 1 << 20);
}

pub fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

pub fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

pub fn runCommandWithEnvMap(allocator: std.mem.Allocator, argv: []const []const u8, env_map: *const std.process.EnvMap) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .env_map = env_map,
    });
}

pub fn runCommandAnyExit(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

pub const NormalizedInstruction = struct {
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

pub fn normalizeInstruction(inst: saasm.flattener.Instruction) NormalizedInstruction {
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

pub fn expectFlattenEquivalent(lhs: saasm.flattener.FlattenResult, rhs: saasm.flattener.FlattenResult) !void {
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

pub fn dumpInstructionTexts(prefix: []const u8, flat: saasm.flattener.FlattenResult) void {
    std.debug.print("{s} ({d} instructions)\n", .{ prefix, flat.instructions.len });
    for (flat.instructions, 0..) |item, idx| {
        std.debug.print("  [{d}] {s}\n", .{ idx, item.raw_text });
    }
}
