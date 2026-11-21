const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const const_decl = @import("../common/const_decl.zig");
const FuncTask = @import("types.zig").FuncTask;

pub fn collectFuncTasks(allocator: std.mem.Allocator, verified: anytype) ![]FuncTask {
    var tasks = std.array_list.Managed(FuncTask).init(allocator);
    errdefer tasks.deinit();
    var sig_index: usize = 0;
    var idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const k = verified.annotated[idx].base.kind;
        switch (k) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                sig_index += 1;
                var end = idx + 1;
                while (end < verified.annotated.len) {
                    const nk = verified.annotated[end].base.kind;
                    switch (nk) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => break,
                        else => end += 1,
                    }
                }
                try tasks.append(.{
                    .fsig_index = sig_index - 1,
                    .start_idx = idx,
                    .end_idx = end,
                    .kind = k,
                });
                idx = end - 1;
            },
            else => {},
        }
    }
    return tasks.toOwnedSlice();
}

pub fn isCReserved(name: []const u8) bool {
    const reserved = [_][]const u8{
        "auto",     "break",  "case",   "char",     "const",      "continue", "default",  "do",
        "double",   "else",   "enum",   "extern",   "float",      "for",      "goto",     "if",
        "inline",   "int",    "long",   "register", "restrict",   "return",   "short",    "signed",
        "sizeof",   "static", "struct", "switch",   "typedef",    "union",    "unsigned", "void",
        "volatile", "while",  "_Bool",  "_Complex", "_Imaginary", "sa_mem",   "sa_brk",
    };
    for (reserved) |word| {
        if (std.mem.eql(u8, name, word)) return true;
    }
    return false;
}

pub fn cIdent(writer: anytype, name: []const u8) !void {
    if (name.len == 0) return writer.writeAll("_anon");
    var first = true;
    for (name) |c| {
        const ok = std.ascii.isAlphanumeric(c) or c == '_';
        if (first) {
            if (std.ascii.isAlphabetic(c) or c == '_') {
                try writer.writeByte(c);
            } else {
                try writer.writeAll("_");
                if (ok) try writer.writeByte(c);
            }
            first = false;
        } else {
            if (ok) try writer.writeByte(c) else try writer.writeByte('_');
        }
    }
    if (isCReserved(name)) try writer.writeAll("_");
}

pub fn cFuncName(writer: anytype, name: []const u8) !void {
    var n = name;
    if (n.len >= 2 and n[0] == '"' and n[n.len - 1] == '"') n = n[1 .. n.len - 1];
    if (n.len >= 1 and n[0] == '@') n = n[1..];
    try writer.writeAll("sa_fn_");
    try cIdent(writer, n);
}

pub fn tagToPrim(tag: u32) sig.PrimType {
    return sig.primTypeFromTag(tag) orelse .i64;
}

pub fn constBytesLen(value: const_decl.ConstValue) !usize {
    return switch (value) {
        .hex, .utf8 => |literal| literal.bytes.len,
        .repeat => |literal| @intCast(literal.repeat_count orelse return error.InvalidOperand),
        .struct_ => |literal| blk: {
            var total: usize = 0;
            for (literal.fields) |field| {
                const len = try constBytesLen(field.value);
                if (len != field.size) return error.InvalidOperand;
                total = std.math.add(usize, total, len) catch return error.InvalidOperand;
            }
            break :blk total;
        },
        else => error.UnsupportedType,
    };
}

pub fn fillConstBytes(out: []u8, value: const_decl.ConstValue) !void {
    switch (value) {
        .hex, .utf8 => |literal| @memcpy(out, literal.bytes),
        .repeat => |literal| @memset(out, literal.repeat_byte orelse 0),
        .struct_ => |literal| {
            var cursor: usize = 0;
            for (literal.fields) |field| {
                const len = try constBytesLen(field.value);
                if (len != field.size or cursor + len > out.len) return error.InvalidOperand;
                try fillConstBytes(out[cursor .. cursor + len], field.value);
                cursor += len;
            }
            if (cursor != out.len) return error.InvalidOperand;
        },
        else => return error.UnsupportedType,
    }
}

pub fn writeCStrEscaped(writer: anytype, text: []const u8) !void {
    for (text) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 32 or c > 126) {
                    try writer.print("\\x{x:0>2}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

pub fn writeConstSym(writer: anytype, name: []const u8) !void {
    try writer.writeAll("SA_CONST_");
    for (name) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            try writer.writeByte(std.ascii.toUpper(c));
        } else {
            try writer.writeByte('_');
        }
    }
}

pub fn taskUsesGlobalRegIds(fsig: sig.FunctionSig, verified: anytype, task: FuncTask) bool {
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        for (verified.annotated[i].base.operands) |operand| {
            if (operand == .reg) {
                const raw = operand.reg;
                if (raw >= fsig.reg_ids.len and fsig.slotOf(raw) != null) return true;
            }
        }
    }
    return false;
}

pub fn regSlot(fsig: sig.FunctionSig, use_global: bool, slot_or_id: u32) !u32 {
    if (use_global) return fsig.slotOf(slot_or_id) orelse return CEmitError.InvalidOperand;
    if (@as(usize, slot_or_id) < fsig.reg_ids.len) return slot_or_id;
    return fsig.slotOf(slot_or_id) orelse return CEmitError.InvalidOperand;
}

pub fn offIsZero(op: inst.Operand) bool {
    return switch (op) {
        .imm_int => |v| v == 0,
        .imm_i64 => |v| v == 0,
        .imm_u64 => |v| v == 0,
        else => false,
    };
}


/// Defined-task lookup by normalized function name (for reachability).
/// Returns the task's fsig_index, or null for externs/unknown names.
pub fn taskIndexByName(tasks: []FuncTask, verified: anytype, norm: []const u8) ?usize {
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        if (std.mem.eql(u8, sigNormName(verified.function_sigs[task.fsig_index].name), norm)) return task.fsig_index;
    }
    return null;
}

pub fn fnIndexOf(fn_idx: anytype, name: []const u8) ?usize {
    if (fn_idx.get(name)) |idx| return idx;
    if (name.len >= 1 and name[0] == '@') {
        if (fn_idx.get(name[1..])) |idx| return idx;
    } else {
        var buf: [512]u8 = undefined;
        if (name.len + 1 <= buf.len) {
            buf[0] = '@';
            @memcpy(buf[1 .. 1 + name.len], name);
            if (fn_idx.get(buf[0 .. 1 + name.len])) |idx| return idx;
        }
    }
    return null;
}

pub fn sigNormName(name: []const u8) []const u8 {
    var n = name;
    if (n.len >= 2 and n[0] == '"' and n[n.len - 1] == '"') n = n[1 .. n.len - 1];
    if (n.len >= 1 and n[0] == '@') n = n[1..];
    return n;
}
