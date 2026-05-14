const std = @import("std");
const common_instruction = @import("common/instruction.zig");
const call = @import("referee/call.zig");
const referee = @import("referee.zig");

pub const LowerError = error{
    InvalidOperand,
    UnsupportedInstruction,
    OutOfMemory,
};

fn opName(op: common_instruction.OpKind) []const u8 {
    return switch (op) {
        .add => "add",
        .sub => "sub",
        .mul => "mul",
        .div, .sdiv, .udiv => "/",
        .rem, .srem, .urem => "%",
        .gt, .lt, .sgt, .slt, .sge, .sle, .ugt, .ult, .uge, .ule => switch (op) {
            .gt, .sgt, .ugt => ">",
            .lt, .slt, .ult => "<",
            .sge, .uge => ">=",
            .sle, .ule => "<=",
            else => unreachable,
        },
        .eq => "==",
        .@"and" => "&",
        .@"or" => "|",
        .xor => "^",
        .shl => "<<",
        .lshr, .ashr, .shr => ">>",
        .neg => "-",
        .not => "~",
        .fadd => "+",
        .fsub => "-",
        .fmul => "*",
        .fdiv => "/",
        .fneg => "-",
        .fcmp_eq => "==",
        .fcmp_ne => "!=",
        .fcmp_lt => "<",
        .fcmp_le => "<=",
        .fcmp_gt => ">",
        .fcmp_ge => ">=",
        .trunc, .zext, .sext, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext, .bitcast => "cast",
        .add_v128, .sub_v128, .mul_v128 => "v128",
        .shuffle_v128 => "shuffle",
        .extract_lane => "extract",
        .insert_lane => "insert",
    };
}

fn regName(id: u32) []const u8 {
    return switch (id) {
        0 => "r0",
        1 => "r1",
        2 => "r2",
        3 => "r3",
        4 => "r4",
        5 => "r5",
        6 => "r6",
        7 => "r7",
        8 => "r8",
        9 => "r9",
        else => "r",
    };
}

fn operandText(inst: common_instruction.Instruction, index: usize) []const u8 {
    return switch (inst.operands[index]) {
        .text => |s| s,
        .symbol => |id| switch (id) {
            0 => "L0",
            1 => "L1",
            2 => "L2",
            3 => "L3",
            else => "L",
        },
        else => "",
    };
}

fn operandReg(inst: common_instruction.Instruction, index: usize) !u32 {
    return switch (inst.operands[index]) {
        .reg => |id| id,
        else => LowerError.InvalidOperand,
    };
}

fn appendLine(list: *std.ArrayList(u8), text: []const u8) !void {
    try list.appendSlice(text);
    try list.append('\n');
}

fn emitPanicExit(out: *std.ArrayList(u8), code_expr: []const u8) !void {
    try out.writer().print("    const __panic_code: i32 = @as(i32, @intCast({s}));\n", .{code_expr});
    try appendLine(out, "    std.debug.print(\"PANIC: code={d}\\n\", .{__panic_code});");
    try appendLine(out, "    const __panic_exit: u8 = @as(u8, @truncate((@as(u32, @bitCast(__panic_code)) & 0x7f) + 128));");
    try appendLine(out, "    std.process.exit(__panic_exit);");
    try appendLine(out, "    unreachable;");
}

fn emitPanicMsgExit(out: *std.ArrayList(u8), code_expr: []const u8, msg_expr: []const u8, len_expr: []const u8) !void {
    try out.writer().print("    const __panic_code: i32 = @as(i32, @intCast({s}));\n", .{code_expr});
    try out.writer().print("    const __panic_msg_ptr: [*]const u8 = @ptrCast({s});\n", .{msg_expr});
    try out.writer().print("    const __panic_msg = __panic_msg_ptr[0..@as(usize, @intCast({s}))];\n", .{len_expr});
    try appendLine(out, "    std.debug.print(\"PANIC[{d}]: {s}\\n\", .{__panic_code, __panic_msg});");
    try appendLine(out, "    const __panic_exit: u8 = @as(u8, @truncate((@as(u32, @bitCast(__panic_code)) & 0x7f) + 128));");
    try appendLine(out, "    std.process.exit(__panic_exit);");
    try appendLine(out, "    unreachable;");
}

fn hasReturnValue(annotated: []const referee.AnnotatedInstruction) bool {
    for (annotated) |item| {
        if (item.base.kind == .return_ and item.base.operands[0] == .reg) {
            return true;
        }
    }
    return false;
}

pub fn lower(allocator: std.mem.Allocator, annotated: []const referee.AnnotatedInstruction) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    try appendLine(&out, "const std = @import(\"std\");");
    try appendLine(&out, "const builtin = @import(\"builtin\");");
    try appendLine(&out, "const Allocator = std.mem.Allocator;");
    try appendLine(&out, "");
    if (hasReturnValue(annotated)) {
        try appendLine(&out, "pub fn generated(allocator: Allocator) ![]u8 {");
    } else {
        try appendLine(&out, "pub fn generated(allocator: Allocator) !void {");
    }

    for (annotated) |item| {
        const inst = item.base;
        switch (inst.kind) {
            .alloc => {
                const dst = try operandReg(inst, 0);
                const size = switch (inst.operands[1]) {
                    .imm_u64 => |n| n,
                    .imm_i64 => |n| @as(u64, @intCast(if (n > 0) n else 0)),
                    else => return LowerError.InvalidOperand,
                };
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                try out.writer().print("    const {s} = try allocator.alloc(u8, {d});\n", .{ regName(dst), size });
            },
            .borrow => {
                const dst = try operandReg(inst, 0);
                const source = try operandReg(inst, 1);
                const mode = operandText(inst, 2);
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                if (std.mem.eql(u8, mode, "mut")) {
                    try out.writer().print("    const {s} = &{s};\n", .{ regName(dst), regName(source) });
                } else {
                    try out.writer().print("    const {s} = {s};\n", .{ regName(dst), regName(source) });
                }
            },
            .move_ => {
                const reg = try operandReg(inst, 0);
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                try out.writer().print("    const {s}_moved = {s};\n", .{ regName(reg), regName(reg) });
            },
            .release => {
                const reg = try operandReg(inst, 0);
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                try out.writer().print("    _ = {s};\n", .{regName(reg)});
            },
            .assign => {
                const dst = try operandReg(inst, 0);
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                try out.writer().print("    const {s} = ", .{regName(dst)});
                switch (inst.operands[1]) {
                    .reg => |id| try out.writer().print("{s}", .{regName(id)}),
                    .imm_i64 => |v| try out.writer().print("{d}", .{v}),
                    .imm_u64 => |v| try out.writer().print("{d}", .{v}),
                    .imm_int => |v| try out.writer().print("{d}", .{v}),
                    .imm_float => |v| try out.writer().print("{d}", .{v}),
                    .text => |t| try out.writer().print("{s}", .{t}),
                    else => return LowerError.InvalidOperand,
                }
                try out.appendSlice(";\n");
            },
            .load => {
                const dst = try operandReg(inst, 0);
                const src = try operandReg(inst, 1);
                const offset = switch (inst.operands[2]) {
                    .imm_u64 => |n| n,
                    .imm_i64 => |n| @as(u64, @intCast(if (n > 0) n else 0)),
                    else => return LowerError.InvalidOperand,
                };
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                try out.writer().print("    const {s} = @as(*u8, @ptrCast(@alignCast({s}.ptr + {d}))).*;\n", .{ regName(dst), regName(src), offset });
            },
            .store => {
                const base = try operandReg(inst, 0);
                const offset = switch (inst.operands[1]) {
                    .imm_u64 => |n| n,
                    .imm_i64 => |n| @as(u64, @intCast(if (n > 0) n else 0)),
                    else => return LowerError.InvalidOperand,
                };
                const value = operandText(inst, 2);
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                try out.writer().print("    @as(*u8, @ptrCast(@alignCast({s}.ptr + {d}))).* = {s};\n", .{ regName(base), offset, value });
            },
            .op => {
                const dst = try operandReg(inst, 0);
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                if (inst.op_kind) |op_kind| {
                    switch (op_kind) {
                        .neg, .not, .fneg => {
                            const src = try operandReg(inst, 1);
                            try out.writer().print("    const {s} = {s}{s};\n", .{ regName(dst), opName(op_kind), regName(src) });
                        },
                        .trunc, .zext, .sext, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext, .bitcast => {
                            const src = try operandReg(inst, 1);
                            try out.writer().print("    const {s} = {s}({s});\n", .{ regName(dst), opName(op_kind), regName(src) });
                        },
                        .extract_lane => {
                            const vec = try operandReg(inst, 1);
                            const lane = try operandReg(inst, 2);
                            try out.writer().print("    const {s} = {s}({s}, {s});\n", .{ regName(dst), opName(op_kind), regName(vec), regName(lane) });
                        },
                        .insert_lane, .shuffle_v128 => {
                            const a = try operandReg(inst, 1);
                            const b = try operandReg(inst, 2);
                            const c = try operandReg(inst, 3);
                            try out.writer().print("    const {s} = {s}({s}, {s}, {s});\n", .{ regName(dst), opName(op_kind), regName(a), regName(b), regName(c) });
                        },
                        else => {
                            const lhs = try operandReg(inst, 1);
                            const rhs = try operandReg(inst, 2);
                            try out.writer().print("    const {s} = {s} {s} {s};\n", .{ regName(dst), regName(lhs), opName(op_kind), regName(rhs) });
                        },
                    }
                } else {
                    return LowerError.InvalidOperand;
                }
            },
            .take => {
                const dst = try operandReg(inst, 0);
                const base = try operandReg(inst, 1);
                const offset = switch (inst.operands[2]) {
                    .imm_u64 => |n| n,
                    .imm_i64 => |n| @as(u64, @intCast(if (n > 0) n else 0)),
                    else => return LowerError.InvalidOperand,
                };
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                try out.writer().print("    const {s} = @as(*usize, @ptrCast(@alignCast({s}.ptr + {d}))).*;\n", .{ regName(dst), regName(base), offset });
            },
            .jmp => {
                return LowerError.UnsupportedInstruction;
            },
            .br => {
                return LowerError.UnsupportedInstruction;
            },
            .br_null => {
                return LowerError.UnsupportedInstruction;
            },
            .call => {
                return LowerError.UnsupportedInstruction;
            },
            .call_indirect => {
                return LowerError.UnsupportedInstruction;
            },
            .panic => {
                var parsed = call.parseCall(allocator, inst.raw_text) catch return LowerError.InvalidOperand;
                defer parsed.deinit(allocator);
                if (parsed.args.len != 1) return LowerError.InvalidOperand;
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                try emitPanicExit(&out, parsed.args[0].text);
            },
            .panic_msg => {
                var parsed = call.parseCall(allocator, inst.raw_text) catch return LowerError.InvalidOperand;
                defer parsed.deinit(allocator);
                if (parsed.args.len != 3) return LowerError.InvalidOperand;
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                try emitPanicMsgExit(&out, parsed.args[0].text, parsed.args[1].text, parsed.args[2].text);
            },
            .return_ => {
                try out.writer().print("    // {s}\n", .{inst.raw_text});
                if (inst.operands[0] == .reg) {
                    const reg = try operandReg(inst, 0);
                    try out.writer().print("    return {s};\n", .{regName(reg)});
                } else {
                    try appendLine(&out, "    return;");
                }
            },
            .func_decl => {
                return LowerError.UnsupportedInstruction;
            },
            .ffi_wrapper_decl => {
                return LowerError.UnsupportedInstruction;
            },
            .extern_decl => {
                return LowerError.UnsupportedInstruction;
            },
            .export_decl => {
                return LowerError.UnsupportedInstruction;
            },
            .label => {
                return LowerError.UnsupportedInstruction;
            },
            .raw_cast => {
                return LowerError.UnsupportedInstruction;
            },
            .assume_safe => {
                return LowerError.UnsupportedInstruction;
            },
            .assume_borrow => {
                return LowerError.UnsupportedInstruction;
            },
            .native => {
                try out.writer().print("    {s}\n", .{operandText(inst, 0)});
            },
        }
    }

    try appendLine(&out, "}");

    return try out.toOwnedSlice();
}

test "lowerer emits concrete zig text" {
    const entry0 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(entry0);
    @memset(entry0, 0);
    const exit0 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(exit0);
    @memset(exit0, 0);
    const entry1 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(entry1);
    @memset(entry1, 0);
    const exit1 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(exit1);
    @memset(exit1, 0);

    const annotated = [_]referee.AnnotatedInstruction{
        .{
            .base = .{
                .kind = .alloc,
                .source_line = 1,
                .expanded_line = 0,
                .operands = .{
                    .{ .reg = 0 },
                    .{ .imm_u64 = 16 },
                    .{ .none = {} },
                    .{ .none = {} },
                },
                .raw_text = "node = alloc 16",
            },
            .entry_caps = entry0,
            .exit_caps = exit0,
            .gas_step_cost = 1,
        },
        .{
            .base = .{
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
            .entry_caps = entry1,
            .exit_caps = exit1,
            .gas_step_cost = 1,
        },
    };

    const text = try lower(std.testing.allocator, annotated[0..]);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "allocator.alloc(u8, 16)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "return r0;"));
}

test "lowerer lowers panic builtins explicitly" {
    const entry0 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(entry0);
    @memset(entry0, 0);
    const exit0 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(exit0);
    @memset(exit0, 0);
    const entry1 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(entry1);
    @memset(entry1, 0);
    const exit1 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(exit1);
    @memset(exit1, 0);

    const annotated = [_]referee.AnnotatedInstruction{
        .{
            .base = .{
                .kind = .panic,
                .source_line = 1,
                .expanded_line = 0,
                .operands = .{
                    .{ .none = {} },
                    .{ .none = {} },
                    .{ .none = {} },
                    .{ .none = {} },
                },
                .raw_text = "panic(7)",
            },
            .entry_caps = entry0,
            .exit_caps = exit0,
            .gas_step_cost = 1,
        },
        .{
            .base = .{
                .kind = .panic_msg,
                .source_line = 2,
                .expanded_line = 1,
                .operands = .{
                    .{ .none = {} },
                    .{ .none = {} },
                    .{ .none = {} },
                    .{ .none = {} },
                },
                .raw_text = "panic_msg(7, msg, len)",
            },
            .entry_caps = entry1,
            .exit_caps = exit1,
            .gas_step_cost = 1,
        },
    };

    const text = try lower(std.testing.allocator, annotated[0..]);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "std.debug.print(\"PANIC: code={d}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "std.debug.print(\"PANIC[{d}]: {s}\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "std.process.exit(128 + @as(u8, @intCast(@as(u32, @bitCast(__panic_code)) & 0x7f)));"));
}

test "lowerer output survives zig fmt" {
    const entry0 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(entry0);
    @memset(entry0, 0);
    const exit0 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(exit0);
    @memset(exit0, 0);
    const entry1 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(entry1);
    @memset(entry1, 0);
    const exit1 = try std.testing.allocator.alloc(u8, 4);
    defer std.testing.allocator.free(exit1);
    @memset(exit1, 0);

    const annotated = [_]referee.AnnotatedInstruction{
        .{
            .base = .{
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
            .entry_caps = entry0,
            .exit_caps = exit0,
            .gas_step_cost = 1,
        },
        .{
            .base = .{
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
            .entry_caps = entry1,
            .exit_caps = exit1,
            .gas_step_cost = 1,
        },
    };

    const text = try lower(std.testing.allocator, annotated[0..]);
    defer std.testing.allocator.free(text);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const file = try tmp.dir.createFile("generated.zig", .{ .truncate = true });
    defer file.close();
    try file.writeAll(text);

    const child = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "zig", "fmt", "--check", "generated.zig" },
        .cwd_dir = tmp.dir,
    });
    defer std.testing.allocator.free(child.stdout);
    defer std.testing.allocator.free(child.stderr);
    switch (child.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("generated:\n{s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ text, child.stdout, child.stderr });
                return error.TestUnexpectedResult;
            }
        },
        else => {
            std.debug.print("generated:\n{s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ text, child.stdout, child.stderr });
            return error.TestUnexpectedResult;
        },
    }
}
