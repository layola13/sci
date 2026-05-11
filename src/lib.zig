const std = @import("std");

pub const common = struct {
    pub const instruction = @import("common/instruction.zig");
    pub const capability = @import("common/capability.zig");
    pub const trap = @import("common/trap.zig");
    pub const upstream_loc = @import("common/upstream_loc.zig");
    pub const gas = @import("common/gas.zig");
    pub const signature = @import("common/signature.zig");
};

pub const flattener = @import("flattener.zig");
pub const referee = @import("referee.zig");
pub const cli = @import("cli.zig");

test "root module imports common types" {
    const inst = @import("common/instruction.zig");
    const cap = @import("common/capability.zig");
    const trap = @import("common/trap.zig");
    const upstream_loc = @import("common/upstream_loc.zig");
    const gas = @import("common/gas.zig");
    const sig = @import("common/signature.zig");
    const flatten = @import("flattener.zig");
    const verify = @import("referee.zig");

    _ = inst.InstKind.alloc;
    _ = cap.CapabilityMask.active;
    _ = trap.Trap.forbidden_syntax;
    _ = upstream_loc.UpstreamLoc;
    _ = gas.GasReport;
    _ = sig.FunctionSig;

    const source =
        \\#def SIZE = 16
        \\L_START:
        \\node = alloc 8
    ;
    const lines = try flatten.scanSource(std.testing.allocator, source);
    defer std.testing.allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqual(flatten.LineKind.def, lines[0].classified.kind);
    try std.testing.expectEqual(flatten.LineKind.label, lines[1].classified.kind);
    try std.testing.expectEqual(flatten.InstructionForm.alloc, lines[2].classified.inst_form.?);

    const program = [_]flatten.Instruction{
        .{
            .kind = .alloc,
            .source_line = 1,
            .expanded_line = 0,
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
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 0 },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "return node",
        },
    };
    const verified = try verify.verify(std.testing.allocator, program[0..]);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            try std.testing.expectEqual(@as(usize, 2), owned.annotated.len);
            owned.deinit(std.testing.allocator);
        },
        .trap => return error.TestUnexpectedResult,
    }

    var flat_result = try flatten.flatten(std.testing.allocator, source);
    defer flat_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), flat_result.instructions.len);
}
