const std = @import("std");

const flattener = @import("src/flattener.zig");
const sab = @import("src/sab.zig");
const sig = @import("src/common/signature.zig");
const inst = @import("src/common/instruction.zig");

fn nextFunctionStart(function_sigs: []const sig.FunctionSig, entry_idx: u32) usize {
    var next: usize = std.math.maxInt(usize);
    for (function_sigs) |fsig| {
        if (fsig.entry_inst_idx > entry_idx and fsig.entry_inst_idx < next) next = fsig.entry_inst_idx;
    }
    return next;
}

fn printOperand(writer: anytype, fsig: sig.FunctionSig, symbols: []const []const u8, operand: inst.Operand, op_idx: usize) !void {
    switch (operand) {
        .reg => |value| {
            try writer.print("      op[{d}] reg={d}", .{ op_idx, value });
            if (value < fsig.reg_ids.len) {
                const global_id = fsig.globalId(value);
                try writer.print(" slot->id={d} name={s}", .{ global_id, symbols[global_id] });
            } else if (value < symbols.len) {
                try writer.print(" global-name={s}", .{symbols[value]});
                if (fsig.slotOf(value)) |slot| try writer.print(" slot={d}", .{slot});
            }
            try writer.writeByte('\n');
        },
        .symbol => |value| try writer.print("      op[{d}] symbol={d} name={s}\n", .{ op_idx, value, symbols[value] }),
        .label => |value| try writer.print("      op[{d}] label={d} name={s}\n", .{ op_idx, value, symbols[value] }),
        .func => |value| try writer.print("      op[{d}] func={d} name={s}\n", .{ op_idx, value, symbols[value] }),
        .text => |text| try writer.print("      op[{d}] text={s}\n", .{ op_idx, text }),
        .ty => |ty| try writer.print("      op[{d}] ty={d}\n", .{ op_idx, ty }),
        .imm_i64 => |v| try writer.print("      op[{d}] imm_i64={d}\n", .{ op_idx, v }),
        .imm_u64 => |v| try writer.print("      op[{d}] imm_u64={d}\n", .{ op_idx, v }),
        .imm_float => |v| try writer.print("      op[{d}] imm_float={d}\n", .{ op_idx, v }),
        .none => {},
        else => try writer.print("      op[{d}] kind={s}\n", .{ op_idx, @tagName(operand) }),
    }
}

fn inspectFunction(writer: anytype, symbols: []const []const u8, function_sigs: []const sig.FunctionSig, instructions: []const inst.Instruction, wanted: []const u8) !void {
    for (function_sigs) |fsig| {
        if (!std.mem.eql(u8, fsig.name, wanted)) continue;
        try writer.print("function {s} entry={d} reg_ids={d}\n", .{ fsig.name, fsig.entry_inst_idx, fsig.reg_ids.len });
        for (fsig.reg_ids, 0..) |reg_id, slot| {
            try writer.print("  slot {d} -> id {d} name={s}\n", .{ slot, reg_id, symbols[reg_id] });
        }
        const end_idx = nextFunctionStart(function_sigs, fsig.entry_inst_idx);
        var idx: usize = fsig.entry_inst_idx;
        while (idx < instructions.len and idx < end_idx and idx < fsig.entry_inst_idx + 16) : (idx += 1) {
            const item = instructions[idx];
            try writer.print("  inst[{d}] kind={s} text='{s}'\n", .{ idx, @tagName(item.kind), item.raw_text });
            for (item.operands, 0..) |operand, op_idx| try printOperand(writer, fsig, symbols, operand, op_idx);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    const path = args.next() orelse return error.InvalidArgument;
    const function_name = args.next() orelse return error.InvalidArgument;

    const stdout = std.io.getStdOut().writer();
    if (std.mem.endsWith(u8, path, ".sab")) {
        const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024);
        defer allocator.free(bytes);
        var module = try sab.decodeModule(allocator, bytes);
        defer module.deinit(allocator);
        try inspectFunction(stdout, module.symbols, module.function_sigs, module.instructions, function_name);
        return;
    }

    const source = try std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024);
    defer allocator.free(source);
    var flat = try flattener.flattenFile(allocator, path, source);
    defer flat.deinit(allocator);
    try inspectFunction(stdout, flat.symbols.names.items, flat.function_sigs, flat.instructions, function_name);
}
