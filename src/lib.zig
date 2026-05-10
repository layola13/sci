const std = @import("std");

pub const common = struct {
    pub const instruction = @import("common/instruction.zig");
    pub const capability = @import("common/capability.zig");
    pub const trap = @import("common/trap.zig");
    pub const gas = @import("common/gas.zig");
    pub const signature = @import("common/signature.zig");
};

pub const flattener = @import("flattener.zig");
pub const referee = @import("referee.zig");
pub const lowerer = @import("lowerer.zig");

test "root module imports common types" {
    const inst = @import("common/instruction.zig");
    const cap = @import("common/capability.zig");
    const trap = @import("common/trap.zig");
    const gas = @import("common/gas.zig");
    const sig = @import("common/signature.zig");
    const flatten = @import("flattener.zig");
    const verify = @import("referee.zig");
    const lower = @import("lowerer.zig");

    _ = inst.InstKind.alloc;
    _ = cap.CapabilityMask.active;
    _ = trap.Trap.forbidden_syntax;
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
            try std.testing.expectEqual(@as(usize, 2), ok.annotated.len);
            std.testing.allocator.free(ok.annotated[0].entry_caps);
            std.testing.allocator.free(ok.annotated[0].exit_caps);
            std.testing.allocator.free(ok.annotated[1].entry_caps);
            std.testing.allocator.free(ok.annotated[1].exit_caps);
            std.testing.allocator.free(ok.annotated);
        },
        .trap => return error.TestUnexpectedResult,
    }

    const lowered_entry0 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(lowered_entry0);
    @memset(lowered_entry0, 0);
    const lowered_exit0 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(lowered_exit0);
    @memset(lowered_exit0, 0);
    const lowered_entry1 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(lowered_entry1);
    @memset(lowered_entry1, 0);
    const lowered_exit1 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(lowered_exit1);
    @memset(lowered_exit1, 0);

    const lowered = try lower.lower(std.testing.allocator, &[_]referee.AnnotatedInstruction{ .{
        .base = program[0],
        .entry_caps = lowered_entry0,
        .exit_caps = lowered_exit0,
        .gas_step_cost = 1,
    }, .{
        .base = program[1],
        .entry_caps = lowered_entry1,
        .exit_caps = lowered_exit1,
        .gas_step_cost = 1,
    } });
    defer std.testing.allocator.free(lowered);
    try std.testing.expect(std.mem.containsAtLeast(u8, lowered, 1, "allocator.alloc(u8, 8)"));

    var flat_result = try flatten.flatten(std.testing.allocator, source);
    defer flat_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), flat_result.instructions.len);
}
