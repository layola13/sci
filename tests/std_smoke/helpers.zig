//! Shared helpers for the tests/std_smoke/*.zig split.
//! Verbatim from the former tests/std_smoke.zig (only `pub` added).
const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");

pub fn repoRoot(allocator: std.mem.Allocator) ![]u8 {
    return sio.cwd().realpathAlloc(allocator, ".");
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try sio.cwd().openFile(path, .{});
    defer file.close(std.testing.io);
    return try sio.readToEndAlloc(file, allocator, 1 << 20);
}

pub fn writeSource(dir: std.Io.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(std.testing.io, path, .{ .truncate = true });
    defer file.close(std.testing.io);
    var wbuf: [8192]u8 = undefined;
    var w = file.writer(std.testing.io, &wbuf);
    try w.interface.writeAll(source);
    try w.interface.flush();
}

pub fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !sio.Child.RunResult {
    return try sio.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

pub fn runCommandWithEnvMap(allocator: std.mem.Allocator, argv: []const []const u8, env_map: *const sio.EnvMap) !sio.Child.RunResult {
    return try sio.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .env_map = env_map,
    });
}

pub fn runCommandAnyExit(allocator: std.mem.Allocator, argv: []const []const u8) !sio.Child.RunResult {
    return try sio.Child.run(.{
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

pub fn flattenFixture(allocator: std.mem.Allocator, source_path: []const u8, source: []const u8) !saasm.flattener.FlattenResult {
    const repo_root = try repoRoot(allocator);
    defer allocator.free(repo_root);
    var resolve_ctx = saasm.flattener.ResolveContext{};
    resolve_ctx.options.std_root = try std.fs.path.join(allocator, &.{ repo_root, "sa_std" });
    defer allocator.free(resolve_ctx.options.std_root.?);
    return saasm.flattener.flattenFileWithPackages(allocator, source_path, source, resolve_ctx);
}
