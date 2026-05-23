const std = @import("std");
const saasm = @import("saasm");

test "root module imports common types" {
    _ = saasm.common.instruction.InstKind.alloc;
    _ = saasm.common.capability.CapabilityMask.active;
    _ = saasm.common.trap.Trap.forbidden_syntax;
    _ = saasm.common.upstream_loc.UpstreamLoc;
    _ = saasm.common.gas.GasReport;
    _ = saasm.common.signature.FunctionSig;
    _ = saasm.test_executor.TestExecutor;
    _ = saasm.test_formatter.RunSummary{ .passed = 0, .failed = 0, .skipped = 0, .ignored = 0 };
    _ = saasm.test_meta.TestListOrder.Unsorted;
    _ = saasm.test_result.Termination{ .exited = 0 };
    _ = saasm.test_runner.run;
    _ = saasm.pkg.manifest.Capability.mem_alloc;
    _ = saasm.pkg.resolver.Dependency{ .url = "example", .ref = "HEAD" };

    const source =
        \\#def SIZE = 16
        \\L_START:
        \\node = alloc 8
    ;
    const lines = try saasm.flattener.scanSource(std.testing.allocator, source, &.{}, &.{});
    defer std.testing.allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqual(saasm.flattener.LineKind.def, lines[0].classified.kind);
    try std.testing.expectEqual(saasm.flattener.LineKind.label, lines[1].classified.kind);
    try std.testing.expectEqual(saasm.flattener.InstructionForm.alloc, lines[2].classified.inst_form.?);

    const program = [_]saasm.flattener.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> ptr:",
        },
        .{
            .kind = .alloc,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 0 },
                .{ .imm_u64 = 8 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "node = alloc 8",
        },
        .{
            .kind = .return_,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .reg = 0 },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "return node",
        },
    };
    const verified = try saasm.referee.verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            try std.testing.expectEqual(@as(usize, 3), owned.annotated.len);
            owned.deinit(std.testing.allocator);
        },
        .trap => return error.TestUnexpectedResult,
    }

    var flat_result = try saasm.flattener.flatten(std.testing.allocator, source);
    defer flat_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), flat_result.instructions.len);

    var layout_result = try saasm.layout.compute(std.testing.allocator, "Entity", "id:u32, pos:f64", 64);
    defer layout_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 16), layout_result.size);
    try std.testing.expectEqual(@as(u32, 8), layout_result.fields[1].offset);
}
