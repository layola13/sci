const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const call = @import("../referee/call.zig");
const cap = @import("../common/capability.zig");
const atomic = @import("../common/atomic.zig");
const gas = @import("../common/gas.zig");
const const_decl = @import("../common/const_decl.zig");
const inst = @import("../common/instruction.zig");
const pkg_manifest = @import("../pkg/manifest.zig");
const sig = @import("../common/signature.zig");
const trap = @import("../common/trap.zig");
const upstream = @import("../common/upstream_loc.zig");
const classifier = @import("../flattener/line_classifier.zig");
const symbol = @import("../flattener/symbol.zig");

const AnnotatedInstruction = @import("reg_state_change.zig").AnnotatedInstruction;
const VerifyResult = @import("reg_state_change.zig").VerifyResult;
const verify = @import("free_annotated_slice.zig").verify;
const verifyWithOptions = @import("free_annotated_slice.zig").verifyWithOptions;

test "native escape conservatively consumes referenced registers" {
    const source =
        \\@main() -> i32:
        \\value = alloc 8
        \\$touch value$
        \\probe = load value+0 as i8
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.use_after_move, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "native escape rejects stack allocations crossing the boundary" {
    const source =
        \\@main() -> i32:
        \\tmp = stack_alloc 8
        \\$touch tmp$
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.stack_escape, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "native escape PBT conservatively consumes random referenced registers" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6300);
    const random = prng.random();

    for (0..32) |_| {
        const size = random.intRangeAtMost(u64, 1, 64);
        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\@main() -> i32:
            \\value = alloc {d}
            \\$touch value$
            \\probe = load value+0 as i8
            \\return 0
        , .{size});
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.use_after_move, report.trap),
            .ok => |ok| {
                var owned = ok;
                owned.deinit(std.testing.allocator);
                return error.TestUnexpectedResult;
            },
        }
    }
}

test "early return leak PBT traps when random live allocations survive the fail edge" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6244);
    const random = prng.random();

    for (0..32) |_| {
        const extra_count = random.intRangeAtMost(usize, 1, 4);
        var source = std.array_list.Managed(u8).init(std.testing.allocator);
        defer source.deinit();

        try source.appendSlice(
            \\@fail() -> i32!:
            \\return 1
            \\@main() -> i32!:
            \\res = call @fail()
        );
        try source.append('\n');

        for (0..extra_count) |idx| {
            try source.print("leak_{d} = alloc {d}\n", .{ idx, random.intRangeAtMost(u64, 1, 64) });
        }

        try source.appendSlice(
            \\ok = ? res
            \\return ok
        );
        try source.append('\n');

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source.items);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.early_return_leak, report.trap),
            .ok => return error.TestUnexpectedResult,
        }
    }
}

test "gas report stays bounded for forward jumps" {
    const program = [_]inst.Instruction{
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
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .jmp,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .symbol = 1 },
                .{ .label = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "jmp L_END",
        },
        .{
            .kind = .label,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .symbol = 1 },
                .{ .label = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "L_END:",
        },
        .{
            .kind = .return_,
            .source_line = 4,
            .expanded_line = 3,
            .operands = .{
                .{ .text = "0" },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "return 0",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(u64, 0), owned.gas.max_alloc_bytes);
            try std.testing.expectEqual(false, owned.gas.has_unbounded_loop);
            switch (owned.gas.max_instruction_steps) {
                .bounded => |steps| try std.testing.expectEqual(@as(u64, 2), steps),
                .unbounded => return error.TestUnexpectedResult,
            }
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "gas report marks backward jumps as unbounded" {
    const program = [_]inst.Instruction{
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
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .label,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .symbol = 1 },
                .{ .label = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "L_LOOP:",
        },
        .{
            .kind = .jmp,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .symbol = 1 },
                .{ .label = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "jmp L_LOOP",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(true, owned.gas.has_unbounded_loop);
            switch (owned.gas.max_instruction_steps) {
                .unbounded => |info| try std.testing.expectEqual(@as(u64, 1), info.bounded_prefix),
                .bounded => return error.TestUnexpectedResult,
            }
        },
        .trap => return error.TestUnexpectedResult,
    }
}

pub const VerifyOkSnapshot = struct {
    annotated: []const AnnotatedInstruction,
    function_sigs: []const sig.FunctionSig,
    symbol_names: []const []const u8,
    gas: gas.GasReport,
};

pub const VerifySnapshot = union(enum) {
    ok: VerifyOkSnapshot,
    trap: trap.TrapReport,
};

pub fn trapSnapshot(report: trap.TrapReport) struct {
    trap: trap.Trap,
    trap_code: u32,
    line: u32,
    source_line: u32,
    message: []const u8,
    register: []const u8,
    function: []const u8,
} {
    return .{
        .trap = report.trap,
        .trap_code = report.trap_code orelse 0,
        .line = report.line,
        .source_line = report.source_line,
        .message = report.message,
        .register = if (report.register) |text| text else std.mem.sliceTo(&report.register_buf, 0),
        .function = if (report.function) |text| text else std.mem.sliceTo(&report.function_buf, 0),
    };
}

pub fn expectVerifyResultEqual(lhs: VerifyResult, rhs: VerifyResult) !void {
    switch (lhs) {
        .ok => |l_ok| switch (rhs) {
            .ok => |r_ok| {
                try std.testing.expectEqual(l_ok.annotated.len, r_ok.annotated.len);
                try std.testing.expectEqual(l_ok.function_sigs.len, r_ok.function_sigs.len);
                try std.testing.expectEqualDeep(l_ok.gas, r_ok.gas);
                try std.testing.expectEqualDeep(l_ok.symbols.names.items, r_ok.symbols.names.items);
            },
            .trap => return error.TestUnexpectedResult,
        },
        .trap => |l_trap| switch (rhs) {
            .trap => |r_trap| {
                const lhs_snap = trapSnapshot(l_trap);
                const rhs_snap = trapSnapshot(r_trap);
                try std.testing.expectEqualDeep(lhs_snap, rhs_snap);
            },
            .ok => return error.TestUnexpectedResult,
        },
    }
}

test "verifyWithOptions serial and parallel results are identical" {
    const source =
        \\@first() -> i32:
        \\a = alloc 8
        \\!a
        \\return 0
        \\
        \\@second() -> i32:
        \\b = alloc 8
        \\!b
        \\return 1
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const serial = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .jobs = 1 });
    const parallel = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .jobs = 2 });

    defer switch (serial) {
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
        },
        .trap => {},
    };
    defer switch (parallel) {
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
        },
        .trap => {},
    };

    try expectVerifyResultEqual(serial, parallel);
}

test "verifyWithOptions serial and parallel traps are identical" {
    const source =
        \\@first() -> i32:
        \\return missing_value
        \\
        \\@second() -> i32:
        \\return 0
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const serial = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .jobs = 1 });
    const parallel = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .jobs = 2 });

    try expectVerifyResultEqual(serial, parallel);
}

pub const GasFixture = struct {
    instructions: []inst.Instruction,
    owned_texts: [][]u8,
    expected_alloc_bytes: u64,
    expected_steps: u64,
    has_unbounded_loop: bool,

    fn deinit(self: *GasFixture, allocator: std.mem.Allocator) void {
        for (self.owned_texts) |text| allocator.free(text);
        allocator.free(self.owned_texts);
        allocator.free(self.instructions);
        self.* = undefined;
    }
};

pub fn snapshotResult(result: VerifyResult) VerifySnapshot {
    return switch (result) {
        .ok => |ok| .{
            .ok = .{
                .annotated = ok.annotated,
                .function_sigs = ok.function_sigs,
                .symbol_names = ok.symbols.names.items,
                .gas = ok.gas,
            },
        },
        .trap => |report| .{ .trap = report },
    };
}

pub fn appendOwnedText(
    texts: *std.array_list.Managed([]u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) ![]const u8 {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    errdefer allocator.free(text);
    try texts.append(text);
    return text;
}

pub fn buildGasFixture(
    allocator: std.mem.Allocator,
    random: std.Random,
    bounded: bool,
) !GasFixture {
    var instructions = std.array_list.Managed(inst.Instruction).init(allocator);
    var instructions_moved = false;
    defer if (!instructions_moved) instructions.deinit();

    var owned_texts = std.array_list.Managed([]u8).init(allocator);
    var owned_texts_moved = false;
    defer if (!owned_texts_moved) {
        for (owned_texts.items) |text| allocator.free(text);
        owned_texts.deinit();
    };

    const size_choices = [_]u64{ 0, 1, 2, 8, 13, 21, 34, 55, 89, 144 };
    const size = size_choices[random.intRangeLessThan(usize, 0, size_choices.len)];
    const fence_count = random.intRangeAtMost(usize, 0, 4);
    const stack_text = try appendOwnedText(&owned_texts, allocator, "tmp = stack_alloc {d}", .{size});

    var item = inst.makeInstruction(.func_decl, 1, 0, null, "@main() -> i32:");
    item.operands[0] = .{ .symbol = 0 };
    item.operands[1] = .{ .func = 0 };
    try instructions.append(item);

    item = inst.makeInstruction(.stack_alloc, 2, 1, null, stack_text);
    item.operands[0] = .{ .reg = 1 };
    item.operands[1] = .{ .imm_u64 = size };
    try instructions.append(item);

    for (0..fence_count) |idx| {
        item = inst.makeInstruction(.fence, @intCast(3 + idx), @intCast(2 + idx), null, "fence seq_cst");
        try instructions.append(item);
    }

    const next_source_line: u32 = @intCast(3 + fence_count);
    const next_expanded_line: u32 = @intCast(2 + fence_count);

    if (bounded) {
        item = inst.makeInstruction(.jmp, next_source_line, next_expanded_line, null, "jmp L_END");
        item.operands[0] = .{ .symbol = 2 };
        item.operands[1] = .{ .label = 2 };
        try instructions.append(item);

        item = inst.makeInstruction(.label, next_source_line + 1, next_expanded_line + 1, null, "L_END:");
        item.operands[0] = .{ .symbol = 2 };
        item.operands[1] = .{ .label = 2 };
        try instructions.append(item);

        item = inst.makeInstruction(.return_, next_source_line + 2, next_expanded_line + 2, null, "return 0");
        item.operands[0] = .{ .text = "0" };
        try instructions.append(item);
    } else {
        item = inst.makeInstruction(.label, next_source_line, next_expanded_line, null, "L_LOOP:");
        item.operands[0] = .{ .symbol = 2 };
        item.operands[1] = .{ .label = 2 };
        try instructions.append(item);

        item = inst.makeInstruction(.jmp, next_source_line + 1, next_expanded_line + 1, null, "jmp L_LOOP");
        item.operands[0] = .{ .symbol = 2 };
        item.operands[1] = .{ .label = 2 };
        try instructions.append(item);
    }

    const owned_instructions = try instructions.toOwnedSlice();
    instructions_moved = true;
    const owned_text_slice = try owned_texts.toOwnedSlice();
    owned_texts_moved = true;

    var step_count: usize = fence_count + 2;
    if (bounded) step_count += 1;

    return .{
        .instructions = owned_instructions,
        .owned_texts = owned_text_slice,
        .expected_alloc_bytes = size,
        .expected_steps = @intCast(step_count),
        .has_unbounded_loop = !bounded,
    };
}

pub fn verifyTwiceAndExpectEqual(allocator: std.mem.Allocator, program: []const inst.Instruction) !void {
    const first = try verify(allocator, program, &.{});
    defer switch (first) {
        .ok => |ok| {
            var owned = ok;
            owned.deinit(allocator);
        },
        .trap => {},
    };

    const second = try verify(allocator, program, &.{});
    defer switch (second) {
        .ok => |ok| {
            var owned = ok;
            owned.deinit(allocator);
        },
        .trap => {},
    };

    try std.testing.expectEqualDeep(snapshotResult(first), snapshotResult(second));
}

test "gas PBT stays bounded for random forward-jump programs" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6244);
    const random = prng.random();

    for (0..32) |_| {
        var fixture = try buildGasFixture(std.testing.allocator, random, true);
        defer fixture.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, fixture.instructions, &.{});
        switch (verified) {
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(std.testing.allocator);

                try std.testing.expectEqual(fixture.expected_alloc_bytes, owned.gas.max_alloc_bytes);
                try std.testing.expectEqual(false, owned.gas.has_unbounded_loop);
                switch (owned.gas.max_instruction_steps) {
                    .bounded => |steps| try std.testing.expectEqual(fixture.expected_steps, steps),
                    .unbounded => return error.TestUnexpectedResult,
                }
            },
            .trap => return error.TestUnexpectedResult,
        }
    }
}

test "gas PBT marks random back-edge programs as unbounded" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6245);
    const random = prng.random();

    for (0..32) |_| {
        var fixture = try buildGasFixture(std.testing.allocator, random, false);
        defer fixture.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, fixture.instructions, &.{});
        switch (verified) {
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(std.testing.allocator);

                try std.testing.expectEqual(fixture.expected_alloc_bytes, owned.gas.max_alloc_bytes);
                try std.testing.expectEqual(true, owned.gas.has_unbounded_loop);
                switch (owned.gas.max_instruction_steps) {
                    .unbounded => |info| try std.testing.expectEqual(fixture.expected_steps, info.bounded_prefix),
                    .bounded => return error.TestUnexpectedResult,
                }
            },
            .trap => return error.TestUnexpectedResult,
        }
    }
}

test "referee determinism PBT stays stable across repeated verify runs" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6250);
    const random = prng.random();

    for (0..32) |idx| {
        var fixture = try buildGasFixture(std.testing.allocator, random, (idx & 1) == 0);
        defer fixture.deinit(std.testing.allocator);

        try verifyTwiceAndExpectEqual(std.testing.allocator, fixture.instructions);
    }
}
