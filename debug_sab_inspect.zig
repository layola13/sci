const std = @import("std");

const sab = @import("src/sab.zig");
const sig = @import("src/common/signature.zig");
const inst = @import("src/common/instruction.zig");
const call = @import("src/referee/call.zig");

const SliceLookup = struct {
    symbols: []const []const u8,

    pub fn lookupName(self: SliceLookup, id: u32) ?[]const u8 {
        const idx: usize = @intCast(id);
        if (idx >= self.symbols.len) return null;
        return self.symbols[idx];
    }
};

fn findSymbolId(symbols: []const []const u8, name: []const u8) ?u32 {
    for (symbols, 0..) |symbol_name, idx| {
        if (std.mem.eql(u8, symbol_name, name)) return @intCast(idx);
    }
    return null;
}

fn nextFunctionStart(function_sigs: []const sig.FunctionSig, entry_idx: u32) usize {
    var next: usize = std.math.maxInt(usize);
    for (function_sigs) |fsig| {
        if (fsig.entry_inst_idx > entry_idx and fsig.entry_inst_idx < next) next = fsig.entry_inst_idx;
    }
    return next;
}

fn printArgMapping(writer: anytype, module: sab.Module, fsig: sig.FunctionSig, parsed: call.ParsedCall) !void {
    for (parsed.args, 0..) |arg, idx| {
        const id = findSymbolId(module.symbols, arg.text);
        const slot = if (id) |global_id| fsig.slotOf(global_id) else null;
        try writer.print("      arg[{d}] prefix={s} text={s}", .{ idx, @tagName(arg.prefix), arg.text });
        if (id) |global_id| {
            try writer.print(" id={d}", .{global_id});
            if (slot) |local_slot| try writer.print(" slot={d}", .{local_slot});
        }
        try writer.writeByte('\n');
    }
}

fn inspectFunction(writer: anytype, module: sab.Module, fsig: sig.FunctionSig) !void {
    try writer.print("function {s} entry={d} reg_ids={d}\n", .{ fsig.name, fsig.entry_inst_idx, fsig.reg_ids.len });
    for (fsig.reg_ids, 0..) |reg_id, slot| {
        try writer.print("  slot {d} -> id {d} name={s}\n", .{ slot, reg_id, module.symbols[reg_id] });
    }

    const end_idx = nextFunctionStart(module.function_sigs, fsig.entry_inst_idx);
    const lookup = SliceLookup{ .symbols = module.symbols };
    var idx: usize = fsig.entry_inst_idx;
    while (idx < module.instructions.len and idx < end_idx) : (idx += 1) {
        const item = module.instructions[idx];
        if (idx < fsig.entry_inst_idx + 12) {
            try writer.print("  raw inst[{d}] kind={s} text='{s}'\n", .{ idx, @tagName(item.kind), item.raw_text });
            for (item.operands, 0..) |operand, op_idx| {
                switch (operand) {
                    .reg => |slot| {
                        try writer.print("      op[{d}] reg slot={d}", .{ op_idx, slot });
                        if (slot < fsig.reg_ids.len) {
                            const global_id = fsig.globalId(slot);
                            try writer.print(" -> id={d} name={s}", .{ global_id, module.symbols[global_id] });
                        }
                        try writer.writeByte('\n');
                    },
                    .text => |text| try writer.print("      op[{d}] text={s}\n", .{ op_idx, text }),
                    .offset => |off| try writer.print("      op[{d}] offset={d}\n", .{ op_idx, off }),
                    .ty => |ty| try writer.print("      op[{d}] ty={d}\n", .{ op_idx, ty }),
                    .imm_i64 => |v| try writer.print("      op[{d}] imm_i64={d}\n", .{ op_idx, v }),
                    .imm_u64 => |v| try writer.print("      op[{d}] imm_u64={d}\n", .{ op_idx, v }),
                    .none => {},
                    else => try writer.print("      op[{d}] kind={s}\n", .{ op_idx, @tagName(operand) }),
                }
            }
        }
        if (item.kind != .call and item.kind != .call_indirect) continue;
        var parsed = call.parseInstructionCall(std.heap.page_allocator, item, lookup) catch continue;
        defer parsed.deinit(std.heap.page_allocator);
        if (!std.mem.eql(u8, parsed.callee, "sa_json_parse") and !std.mem.eql(u8, parsed.callee, "sa_json_object_get") and !std.mem.eql(u8, parsed.callee, "sa_json_string_ptr") and !std.mem.eql(u8, parsed.callee, "sa_json_string_len") and !std.mem.eql(u8, parsed.callee, "sla__imported_json_get_type") and !std.mem.eql(u8, parsed.callee, "sla__imported_json_struct") and !std.mem.eql(u8, parsed.callee, "sla__imported_json_struct_field_key")) continue;

        try writer.print("  inst[{d}] callee={s}\n", .{ idx, parsed.callee });
        if (parsed.dest) |dest| {
            try writer.print("    dest={s}", .{dest});
            if (findSymbolId(module.symbols, dest)) |global_id| {
                try writer.print(" id={d}", .{global_id});
                if (fsig.slotOf(global_id)) |local_slot| try writer.print(" slot={d}", .{local_slot});
            }
            try writer.writeByte('\n');
        }
        try printArgMapping(writer, module, fsig, parsed);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    const path = args.next() orelse {
        std.debug.print("usage: debug_sab_inspect <file.sab> [function-name]\n", .{});
        return;
    };
    const wanted = args.next();

    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024);
    defer allocator.free(bytes);

    var module = try sab.decodeModule(allocator, bytes);
    defer module.deinit(allocator);

    const stdout = std.io.getStdOut().writer();
    for (module.function_sigs) |fsig| {
        if (wanted) |name| {
            if (!std.mem.eql(u8, fsig.name, name)) continue;
        }
        try inspectFunction(stdout, module, fsig);
    }
}
