const std = @import("std");

const emit_options = @import("emit_options.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const call = @import("referee/call.zig");
const const_decl = @import("common/const_decl.zig");
const sio = @import("sio");

pub const EmitOptions = emit_options.EmitOptions;
pub const CEmitError = error{ Failed, InvalidOperand, UnknownFunction, UnsupportedInstruction, OutOfMemory };

/// Last instruction raw text seen by the emitter (diagnostics only).
pub threadlocal var last_c_inst: []const u8 = "";
pub threadlocal var last_c_func: []const u8 = "";

pub const CEmitOptions = struct {
    mem_pages: u32 = 256, // 256 * 64KiB = 16MiB initial
    debug_comments: bool = true,
};

const FuncTask = struct {
    fsig_index: usize,
    start_idx: usize,
    end_idx: usize,
    kind: inst.InstKind,
};

fn collectFuncTasks(allocator: std.mem.Allocator, verified: anytype) ![]FuncTask {
    var tasks = std.array_list.Managed(FuncTask).init(allocator);
    errdefer tasks.deinit();
    var sig_index: usize = 0;
    var idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const k = verified.annotated[idx].base.kind;
        switch (k) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                sig_index += 1;
                var end = idx + 1;
                while (end < verified.annotated.len) {
                    const nk = verified.annotated[end].base.kind;
                    switch (nk) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => break,
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

fn isCReserved(name: []const u8) bool {
    const reserved = [_][]const u8{
        "auto", "break", "case", "char", "const", "continue", "default", "do",
        "double", "else", "enum", "extern", "float", "for", "goto", "if",
        "inline", "int", "long", "register", "restrict", "return", "short",
        "signed", "sizeof", "static", "struct", "switch", "typedef", "union",
        "unsigned", "void", "volatile", "while", "_Bool", "_Complex",
        "_Imaginary", "sa_mem", "sa_brk",
    };
    for (reserved) |word| {
        if (std.mem.eql(u8, name, word)) return true;
    }
    return false;
}

fn cIdent(writer: anytype, name: []const u8) !void {
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

fn cFuncName(writer: anytype, name: []const u8) !void {
    var n = name;
    if (n.len >= 2 and n[0] == '"' and n[n.len - 1] == '"') n = n[1 .. n.len - 1];
    if (n.len >= 1 and n[0] == '@') n = n[1..];
    try writer.writeAll("sa_fn_");
    try cIdent(writer, n);
}

fn tagToPrim(tag: u32) sig.PrimType {
    return sig.primTypeFromTag(tag) orelse .i64;
}

fn constBytesLen(value: const_decl.ConstValue) !usize {
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

fn fillConstBytes(out: []u8, value: const_decl.ConstValue) !void {
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

fn writeCStrEscaped(writer: anytype, text: []const u8) !void {
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

fn writeConstSym(writer: anytype, name: []const u8) !void {
    try writer.writeAll("SA_CONST_");
    for (name) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            try writer.writeByte(std.ascii.toUpper(c));
        } else {
            try writer.writeByte('_');
        }
    }
}

fn taskUsesGlobalRegIds(fsig: sig.FunctionSig, verified: anytype, task: FuncTask) bool {
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

fn regSlot(fsig: sig.FunctionSig, use_global: bool, slot_or_id: u32) !u32 {
    if (use_global) return fsig.slotOf(slot_or_id) orelse return CEmitError.InvalidOperand;
    if (@as(usize, slot_or_id) < fsig.reg_ids.len) return slot_or_id;
    return fsig.slotOf(slot_or_id) orelse return CEmitError.InvalidOperand;
}

fn offIsZero(op: inst.Operand) bool {
    return switch (op) {
        .imm_int => |v| v == 0,
        .imm_i64 => |v| v == 0,
        .imm_u64 => |v| v == 0,
        else => false,
    };
}

fn fnIndexOf(fn_idx: anytype, name: []const u8) ?usize {
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

fn resolveTextToC(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, const_addrs: anytype, raw: []const u8) !void {
    var text = std.mem.trim(u8, raw, " \t");
    if (text.len == 0) return CEmitError.InvalidOperand;
    if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
    if (std.mem.lastIndexOf(u8, text, " as ")) |idx| {
        text = std.mem.trim(u8, text[0..idx], " \t\r");
    }
    if (text.len == 0) return CEmitError.InvalidOperand;
    if (std.fmt.parseInt(i64, text, 10)) |v| {
        if (v < 0) {
            try writer.print("(sa_u64)((sa_i64){d})", .{v});
        } else {
            try writer.print("(sa_u64){d}ULL", .{v});
        }
        return;
    } else |_| {}
    if (std.fmt.parseInt(u64, text, 10)) |v| {
        try writer.print("(sa_u64){d}ULL", .{v});
        return;
    } else |_| {}
    if (std.fmt.parseFloat(f64, text)) |v| {
        const bits: u64 = @bitCast(v);
        try writer.print("(sa_u64)0x{x}ULL /* {d} */", .{ bits, v });
        return;
    } else |_| {}
    if (const_addrs.get(text)) |_| {
        try writeConstSym(writer, text);
        return;
    }
    if (symbols.findId(text)) |id| {
        if (fsig.slotOf(id)) |slot| {
            try writer.print("r{d}", .{slot});
            return;
        }
    }
    return CEmitError.InvalidOperand;
}

fn resolveValueToC(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, op: inst.Operand) !void {
    switch (op) {
        .reg => |r| {
            const slot = try regSlot(fsig, use_global, r);
            try writer.print("r{d}", .{slot});
        },
        .symbol, .label => |id| {
            const name = symbols.lookupName(id) orelse return CEmitError.InvalidOperand;
            try resolveTextToC(writer, symbols, fsig, const_addrs, name);
        },
        .func => |id| {
            const name = symbols.lookupName(id) orelse return CEmitError.InvalidOperand;
            const fidx = fnIndexOf(fn_idx, name) orelse return CEmitError.InvalidOperand;
            try writer.print("sa_fnaddr({d})", .{fidx});
        },
        .imm_int => |v| {
            if (v < 0) {
                try writer.print("(sa_u64)((sa_i64){d})", .{v});
            } else {
                try writer.print("(sa_u64){d}ULL", .{v});
            }
        },
        .imm_i64 => |v| {
            if (v < 0) {
                try writer.print("(sa_u64)((sa_i64){d})", .{v});
            } else {
                try writer.print("(sa_u64){d}ULL", .{v});
            }
        },
        .imm_u64 => |v| try writer.print("(sa_u64){d}ULL", .{v}),
        .imm_float => |v| {
            const bits: u64 = @bitCast(v);
            try writer.print("(sa_u64)0x{x}ULL", .{bits});
        },
        .text, .native_text => |t| try resolveTextToC(writer, symbols, fsig, const_addrs, t),
        else => return CEmitError.InvalidOperand,
    }
}

fn memPrimType(base: inst.Instruction) sig.PrimType {
    // operands[3] for load/store is usually .ty tag; fall back to u8/i64.
    for (base.operands) |op| {
        if (op == .ty) return tagToPrim(op.ty);
    }
    return .u8;
}

fn memLoadFn(ty: sig.PrimType) []const u8 {
    return switch (ty) {
        .i8, .i1 => "sa_load_i8",
        .u8 => "sa_load_u8",
        .i16 => "sa_load_i16",
        .u16 => "sa_load_u16",
        .i32 => "sa_load_i32",
        .u32 => "sa_load_u32",
        .i64, .u64, .ptr, .blob_handle => "sa_load_u64",
        .f32 => "sa_load_f32",
        .f64 => "sa_load_f64",
        else => "sa_load_u8",
    };
}

fn memStoreFn(ty: sig.PrimType) []const u8 {
    return switch (ty) {
        .i8, .u8, .i1 => "sa_store_u8",
        .i16, .u16 => "sa_store_u16",
        .i32, .u32 => "sa_store_u32",
        .i64, .u64, .ptr, .blob_handle => "sa_store_u64",
        .f32 => "sa_store_f32",
        .f64 => "sa_store_f64",
        else => "sa_store_u8",
    };
}

/// Statically tracked value widths per slot, ported from the JS backend
/// (see emit_js trackWidths). Keyed by local slot. Cleared at labels;
/// seeded from parameter types and known callee return types, which the
/// C backend can do exactly (both sides share the u64-bits invariant).
/// Packing: low 8 bits = width, bit 30 = signed int domain,
/// bit 31 = float domain.
const WidthMap = std.AutoHashMap(u32, u32);
const WidthSignBit: u32 = 0x40000000;
const WidthFloatBit: u32 = 0x80000000;

fn packWidth(prim: sig.PrimType) ?u32 {
    return switch (prim) {
        .i1 => 1,
        .i8 => 8 | WidthSignBit,
        .i16 => 16 | WidthSignBit,
        .i32 => 32 | WidthSignBit,
        .i64 => 64 | WidthSignBit,
        .u8 => 8,
        .u16 => 16,
        .u32 => 32,
        .u64 => 64,
        .ptr, .blob_handle => 64,
        .f32 => WidthFloatBit | 32,
        .f64 => WidthFloatBit | 64,
        else => null,
    };
}

fn widthIsFloat(code: u32) bool {
    return (code & WidthFloatBit) != 0;
}

fn widthIsSigned(code: u32) bool {
    return (code & WidthSignBit) != 0;
}

fn widthBits(code: u32) u8 {
    return @intCast(code & 0xff);
}

fn widthRemoveSlot(widths: *WidthMap, slot: ?u32) void {
    if (slot) |s| _ = widths.remove(s);
}

fn widthOfOperand(widths: *const WidthMap, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) ?u32 {
    switch (op) {
        .reg => |r| {
            const slot = regSlot(fsig, use_global, r) catch return null;
            return widths.get(slot);
        },
        .symbol => |id| {
            if (fsig.slotOf(id)) |slot| return widths.get(slot);
            return null;
        },
        .imm_int, .imm_i64 => return 64 | WidthSignBit,
        .imm_u64 => return 64,
        .imm_float => return WidthFloatBit | 64,
        else => return null,
    }
}

fn trackWidths(widths: *WidthMap, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, base: inst.Instruction) void {
    const slotOfOp = struct {
        fn f(fsig_inner: sig.FunctionSig, use_global_inner: bool, op: inst.Operand) ?u32 {
            switch (op) {
                .reg => |r| return regSlot(fsig_inner, use_global_inner, r) catch null,
                .symbol => |id| return fsig_inner.slotOf(id),
                else => return null,
            }
        }
    }.f;
    switch (base.kind) {
        .load, .take, .atomic_load => {
            if (slotOfOp(fsig, use_global, base.operands[0])) |dst| {
                if (packWidth(memPrimType(base))) |w| {
                    widths.put(dst, w) catch return;
                } else {
                    _ = widths.remove(dst);
                }
            }
        },
        .op => {
            const dst = slotOfOp(fsig, use_global, base.operands[0]) orelse return;
            const opcode = base.op_kind orelse {
                _ = widths.remove(dst);
                return;
            };
            if (inst.isTypeConversionOpKind(opcode)) {
                if (base.operands[2] != .ty) {
                    _ = widths.remove(dst);
                    return;
                }
                var tgt = tagToPrim(base.operands[2].ty);
                if ((opcode == .sitofp or opcode == .uitofp) and tgt != .f32 and tgt != .f64) {
                    tgt = .f64;
                }
                if (packWidth(tgt)) |w| {
                    widths.put(dst, w) catch return;
                } else {
                    _ = widths.remove(dst);
                }
                return;
            }
            switch (opcode) {
                .neg, .not, .fneg => {
                    if (slotOfOp(fsig, use_global, base.operands[1])) |src| {
                        if (widths.get(src)) |w| {
                            widths.put(dst, w) catch return;
                        } else {
                            _ = widths.remove(dst);
                        }
                    } else {
                        _ = widths.remove(dst);
                    }
                },
                .eq, .ne, .gt, .lt, .sgt, .slt, .sge, .sle, .ugt, .ult, .uge, .ule, .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => widths.put(dst, 1) catch return,
                .fadd, .fsub, .fmul, .fdiv => widths.put(dst, WidthFloatBit | 64) catch return,
                .sdiv, .srem, .ashr => widths.put(dst, 64 | WidthSignBit) catch return,
                .udiv, .urem, .lshr => widths.put(dst, 64) catch return,
                else => widths.put(dst, 64 | WidthSignBit) catch return,
            }
        },
        .assign, .assume_safe, .assume_borrow => {
            const dst = slotOfOp(fsig, use_global, base.operands[0]) orelse return;
            const srcw = widthOfOperand(widths, fsig, use_global, base.operands[1]);
            if (srcw) |w| {
                widths.put(dst, w) catch return;
            } else {
                _ = widths.remove(dst);
            }
        },
        .borrow, .ptr_add, .alloc, .stack_alloc => {
            widthRemoveSlot(widths, slotOfOp(fsig, use_global, base.operands[0]));
            if (base.kind != .borrow) {
                if (slotOfOp(fsig, use_global, base.operands[0])) |dst| {
                    widths.put(dst, 64) catch return;
                }
            } else {
                if (slotOfOp(fsig, use_global, base.operands[0])) |dst| {
                    widths.put(dst, 64) catch return;
                }
            }
        },
        .raw_cast => widthRemoveSlot(widths, slotOfOp(fsig, use_global, base.operands[0])),
        .call, .call_indirect => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                widths.clearRetainingCapacity();
                return;
            };
            defer parsed.deinit(allocator);
            // Callee return seeding happens at emission via sigmap; drop here.
            if (parsed.dest) |dest| {
                if (symbols.findId(dest)) |id| {
                    if (fsig.slotOf(id)) |slot| _ = widths.remove(slot);
                }
            }
        },
        .try_, .early_return => widthRemoveSlot(widths, slotOfOp(fsig, use_global, base.operands[0])),
        .cmpxchg => {
            widthRemoveSlot(widths, slotOfOp(fsig, use_global, base.operands[0]));
            widthRemoveSlot(widths, slotOfOp(fsig, use_global, base.operands[1]));
        },
        .atomic_rmw => widthRemoveSlot(widths, slotOfOp(fsig, use_global, base.operands[0])),
        .move_ => {
            widthRemoveSlot(widths, slotOfOp(fsig, use_global, base.operands[0]));
            widthRemoveSlot(widths, slotOfOp(fsig, use_global, base.operands[1]));
        },
        else => {},
    }
}

/// Float domain of an operand for ALU selection: f32 only if statically
/// known f32; everything else (f64 or unknown) uses f64 arithmetic with
/// f32 sides promoted. Mirrors JS f64-domain float helpers.
fn floatWidthIs32(widths: *const WidthMap, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) bool {
    const w = widthOfOperand(widths, fsig, use_global, op) orelse return false;
    return widthIsFloat(w) and widthBits(w) == 32;
}

fn emitCvtExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, opcode: inst.OpKind, tgt: sig.PrimType, src_op: inst.Operand, widths: *const WidthMap) !void {
    const sfx: []const u8 = switch (tgt) {
        .i1 => "i1", .i8 => "i8", .i16 => "i16", .i32 => "i32", .i64 => "i64",
        .u8 => "u8", .u16 => "u16", .u32 => "u32", .u64 => "u64", .blob_handle => "u64",
        .ptr => "ptr", .f32 => "f32", .f64 => "f64",
        else => return CEmitError.InvalidOperand,
    };
    const opname: []const u8 = switch (opcode) {
        .trunc => "trunc", .zext => "zext", .sext => "sext", .fptosi => "fptosi",
        .sitofp => "sitofp", .uitofp => "uitofp", .fptrunc => "fptrunc",
        .fpext => "fpext", .bitcast => "bitcast",
        else => return CEmitError.InvalidOperand,
    };
    const tgt_is_64 = switch (tgt) {
        .i64, .u64, .ptr, .blob_handle => true,
        else => false,
    };
    // zext/sext to 64 bits from a statically known sub-64 source must
    // extend from the source width (mirrors JS __sa_srcmask sharpening).
    if ((opcode == .zext or opcode == .sext) and tgt_is_64) {
        if (widthOfOperand(widths, fsig, use_global, src_op)) |sw| {
            if (!widthIsFloat(sw) and widthBits(sw) < 64) {
                const sgn: u8 = if (opcode == .sext) 1 else 0;
                try writer.print("sa_cvt_{s}_{s}(sa_srcmask((", .{ opname, sfx });
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
                try writer.print("), {d}, {d}))", .{ widthBits(sw), sgn });
                return;
            }
        } else {
            // Unknown source: assume <=32-bit content like the JS
            // Number-default path (low 32 bits).
            if (opcode == .zext) {
                try writer.print("sa_cvt_{s}_{s}(((sa_u64)(uint32_t)(", .{ opname, sfx });
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
                try writer.writeAll(")))");
                return;
            }
        }
    }
    // fptosi reads float bits: promote f32-domain sources to f64 first.
    if (opcode == .fptosi and floatWidthIs32(widths, fsig, use_global, src_op)) {
        try writer.print("sa_cvt_{s}_{s}(sa_f32_to_f64((", .{ opname, sfx });
        try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.writeAll("))");
        return;
    }
    try writer.print("sa_cvt_{s}_{s}(", .{ opname, sfx });
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
    try writer.writeAll(")");
}

fn emitFloatOperand(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, op: inst.Operand, is32: bool, want32: bool) !void {
    // Emit an operand for a float-domain helper: promote f32 to f64 when
    // the helper wants f64, or demote f64 to f32 when it wants f32.
    if (is32 == want32) {
        try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, op);
    } else if (want32) {
        try writer.writeAll("sa_f64_to_f32((");
        try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, op);
        try writer.writeAll("))");
    } else {
        try writer.writeAll("sa_f32_to_f64((");
        try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, op);
        try writer.writeAll("))");
    }
}

fn emitOpExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, opcode: inst.OpKind, lhs: inst.Operand, rhs: inst.Operand, widths: *const WidthMap) !void {
    // Float ALU: both sides statically f32 -> f32 helpers; otherwise f64
    // helpers with f32 sides promoted (mirrors JS f64-domain helpers).
    switch (opcode) {
        .fadd, .fsub, .fmul, .fdiv => {
            const l32 = floatWidthIs32(widths, fsig, use_global, lhs);
            const r32 = floatWidthIs32(widths, fsig, use_global, rhs);
            const base: []const u8 = switch (opcode) {
                .fadd => "sa_fadd",
                .fsub => "sa_fsub",
                .fmul => "sa_fmul",
                else => "sa_fdiv",
            };
            const want32 = l32 and r32;
            if (want32) try writer.print("{s}32(", .{base}) else try writer.print("{s}(", .{base});
            try emitFloatOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, l32, want32);
            try writer.writeAll(", ");
            try emitFloatOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs, r32, want32);
            try writer.writeAll(")");
            return;
        },
        .fneg => {
            const is32 = floatWidthIs32(widths, fsig, use_global, lhs);
            if (is32) try writer.writeAll("sa_fneg32(") else try writer.writeAll("sa_fneg(");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(")");
            return;
        },
        .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => {
            const l32 = floatWidthIs32(widths, fsig, use_global, lhs);
            const r32 = floatWidthIs32(widths, fsig, use_global, rhs);
            const base: []const u8 = switch (opcode) {
                .fcmp_eq => "sa_fcmp_eq",
                .fcmp_ne => "sa_fcmp_ne",
                .fcmp_lt => "sa_fcmp_lt",
                .fcmp_le => "sa_fcmp_le",
                .fcmp_gt => "sa_fcmp_gt",
                else => "sa_fcmp_ge",
            };
            const want32 = l32 and r32;
            if (want32) try writer.print("{s}32(", .{base}) else try writer.print("{s}(", .{base});
            try emitFloatOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, l32, want32);
            try writer.writeAll(", ");
            try emitFloatOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs, r32, want32);
            try writer.writeAll(")");
            return;
        },
        else => {},
    }
    const name: []const u8 = switch (opcode) {
        .add => "sa_add", .sub => "sa_sub", .mul => "sa_mul",
        .sdiv => "sa_sdiv", .udiv => "sa_udiv", .srem => "sa_srem", .urem => "sa_urem",
        .div => "sa_sdiv", .rem => "sa_srem",
        .@"and" => "sa_band", .@"or" => "sa_bor", .xor => "sa_bxor",
        .shl => "sa_shl", .lshr => "sa_lshr", .ashr => "sa_ashr", .shr => "sa_ashr",
        .not => "sa_bnot",
        .neg => "sa_neg",
        .eq => "sa_eq", .ne => "sa_ne",
        .slt => "sa_slt", .sle => "sa_sle", .sgt => "sa_sgt", .sge => "sa_sge",
        .ult => "sa_ult", .ule => "sa_ule", .ugt => "sa_ugt", .uge => "sa_uge",
        .lt => "sa_slt", .gt => "sa_sgt",
        .fadd => "sa_fadd", .fsub => "sa_fsub", .fmul => "sa_fmul", .fdiv => "sa_fdiv",
        .fneg => "sa_fneg",
        .fcmp_eq => "sa_fcmp_eq", .fcmp_ne => "sa_fcmp_ne",
        .fcmp_lt => "sa_fcmp_lt", .fcmp_le => "sa_fcmp_le",
        .fcmp_gt => "sa_fcmp_gt", .fcmp_ge => "sa_fcmp_ge",
        else => return CEmitError.InvalidOperand,
    };
    if (opcode == .not or opcode == .neg or opcode == .fneg) {
        try writer.print("{s}(", .{name});
        try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
        try writer.writeAll(")");
        return;
    }
    try writer.print("{s}(", .{name});
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
    try writer.writeAll(", ");
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
    try writer.writeAll(")");
}

fn dstSlot(fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) !u32 {
    switch (op) {
        .reg => |r| return regSlot(fsig, use_global, r),
        .symbol => |id| return fsig.slotOf(id) orelse return CEmitError.InvalidOperand,
        .text, .native_text => return CEmitError.InvalidOperand,
        else => return CEmitError.InvalidOperand,
    }
}

fn emitReturnStmt(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, operand: inst.Operand, indent: []const u8) !void {
    if (fsig.return_fallible) {
        switch (operand) {
            .none => try writer.print("{s}return sa_ok_none();\n", .{indent}),
            else => {
                try writer.print("{s}return sa_ok_val((", .{indent});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, operand);
                try writer.writeAll("));\n");
            },
        }
    } else switch (operand) {
        .none => try writer.print("{s}return 0;\n", .{indent}),
        else => {
            try writer.print("{s}return (", .{indent});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, operand);
            try writer.writeAll(");\n");
        },
    }
}

fn writeRuntimeHeader(writer: anytype, c_opt: CEmitOptions, size_bits: u16) !void {
    const mem_bytes: usize = @as(usize, c_opt.mem_pages) * 65536;
    try writer.print("/* Generated by `sa build-c` (c backend, MVP). DO NOT EDIT. */\n", .{});
    try writer.print("/* size_bits={d} mem_bytes={d} */\n", .{ size_bits, mem_bytes });
    try writer.writeAll(
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <stdlib.h>
        \\typedef uint64_t sa_u64;
        \\typedef int64_t sa_i64;
        \\typedef uint32_t sa_u32;
        \\typedef int32_t sa_i32;
        \\#ifndef SA_MEM_BYTES
        \\#define SA_MEM_BYTES 16777216UL
        \\#endif
        \\static uint8_t sa_mem[SA_MEM_BYTES];
        \\static uint32_t sa_brk = 65536;
        \\static __attribute__((noreturn)) void sa_trap(const char *msg) { fputs("[sa-trap] ", stderr); fputs(msg, stderr); fputc('\n', stderr); exit(1); }
        \\static __attribute__((noreturn)) void sa_panic(sa_u64 code) { char b[24]; int n = 0; sa_u64 v = code; char t[24]; int m = 0; if (v == 0) t[m++] = '0'; while (v > 0) { t[m++] = (char)('0' + (v % 10)); v /= 10; } fputs("[sa-panic] code=", stderr); while (m > 0) b[n++] = t[--m]; fwrite(b, 1, (size_t)n, stderr); fputc('\n', stderr); exit(1); }
        \\static sa_u64 sa_ok_none(void) { return 0; }
        \\static sa_u64 sa_ok_val(sa_u64 v) { (void)v; return v; }
        \\static int sa_truthy(sa_u64 v) { return v != 0; }
        \\static sa_u64 sa_align(sa_u64 n, sa_u64 a) { return (n + (a - 1)) & ~(a - 1); }
        \\static sa_u64 sa_alloc(sa_u64 size) {
        \\  size = sa_align(size, 8); if (size == 0) size = 8;
        \\  uint32_t base = sa_brk;
        \\  { sa_u64 nb = (sa_u64)base + size + 8; if (nb > (sa_u64)sizeof(sa_mem)) sa_trap("out of memory (bump)"); sa_brk = (uint32_t)nb; } // NOLINT(bugprone-misplaced-widening-cast): nb range-checked above
        \\  { uint32_t i; for (i = 0; i < (uint32_t)(size + 8); i++) sa_mem[base + i] = 0; }
        \\  sa_mem[base] = (uint8_t)(size & 0xFFu); sa_mem[base + 1] = (uint8_t)((size >> 8) & 0xFFu);
        \\  sa_mem[base + 2] = (uint8_t)((size >> 16) & 0xFFu); sa_mem[base + 3] = (uint8_t)((size >> 24) & 0xFFu);
        \\  return (sa_u64)base + 8;
        \\}
        \\static sa_u64 sa_salloc(sa_u64 size) { return sa_alloc(size); }
        \\static sa_u64 sa_free(sa_u64 ptr) { (void)ptr; return 0; }
        \\static sa_u64 sa_ptr_add(sa_u64 base, sa_u64 off) { return base + off; }
        \\static uint32_t sa_addr(sa_u64 a) { return (uint32_t)(a & 0xFFFFFFFFu); }
        \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, size) signature
        \\static uint32_t sa_checked_addr(sa_u64 a, size_t sz) {
        \\  uint32_t x = sa_addr(a);
        \\  if ((size_t)x + sz > (size_t)sizeof(sa_mem)) sa_trap("oob linear-memory access");
        \\  return x;
        \\}
        
        \\static sa_u64 sa_load_u8(sa_u64 a) { return (sa_u64)sa_mem[sa_checked_addr(a, 1)]; }
        \\static sa_u64 sa_load_i8(sa_u64 a) { return (sa_u64)(sa_i64)(int8_t)sa_mem[sa_checked_addr(a, 1)]; }
        \\static sa_u64 sa_load_u16(sa_u64 a) { uint32_t x = sa_checked_addr(a, 2); return (sa_u64)((uint16_t)((uint16_t)sa_mem[x] | ((uint16_t)sa_mem[x + 1] << 8))); }
        \\static sa_u64 sa_load_i16(sa_u64 a) { uint32_t x = sa_checked_addr(a, 2); int16_t v = (int16_t)((uint16_t)sa_mem[x] | ((uint16_t)sa_mem[x + 1] << 8)); return (sa_u64)(sa_i64)v; }
        \\static sa_u64 sa_load_u32(sa_u64 a) { uint32_t x = sa_checked_addr(a, 4); return (sa_u64)((uint32_t)sa_mem[x] | ((uint32_t)sa_mem[x + 1] << 8) | ((uint32_t)sa_mem[x + 2] << 16) | ((uint32_t)sa_mem[x + 3] << 24)); }
        \\static sa_u64 sa_load_i32(sa_u64 a) { uint32_t x = sa_checked_addr(a, 4); int32_t v = (int32_t)((uint32_t)sa_mem[x] | ((uint32_t)sa_mem[x + 1] << 8) | ((uint32_t)sa_mem[x + 2] << 16) | ((uint32_t)sa_mem[x + 3] << 24)); return (sa_u64)(sa_i64)v; }
        \\static sa_u64 sa_load_u64(sa_u64 a) { uint32_t x = sa_checked_addr(a, 8); uint64_t v = 0; unsigned k; for (k = 0; k < 8; k++) v |= ((uint64_t)sa_mem[x + k]) << (k * 8); return v; }
        \\static sa_u64 sa_load_f32(sa_u64 a) { return sa_load_u32(a) & 0xFFFFFFFFULL; }
        \\static sa_u64 sa_load_f64(sa_u64 a) { return sa_load_u64(a); }
        \\static void sa_store_u8(sa_u64 a, sa_u64 v) { sa_mem[sa_checked_addr(a, 1)] = (uint8_t)(v & 0xFFu); }
        \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, value) signature
        \\static void sa_store_u16(sa_u64 a, sa_u64 v) { uint32_t x = sa_checked_addr(a, 2); sa_mem[x] = (uint8_t)(v & 0xFFu); sa_mem[x + 1] = (uint8_t)((v >> 8) & 0xFFu); }
        \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, value) signature
        \\static void sa_store_u32(sa_u64 a, sa_u64 v) { uint32_t x = sa_checked_addr(a, 4); unsigned k; for (k = 0; k < 4; k++) sa_mem[x + k] = (uint8_t)((v >> (k * 8)) & 0xFFu); }
        \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, value) signature
        \\static void sa_store_u64(sa_u64 a, sa_u64 v) { uint32_t x = sa_checked_addr(a, 8); unsigned k; for (k = 0; k < 8; k++) sa_mem[x + k] = (uint8_t)((v >> (k * 8)) & 0xFFu); }
        \\static void sa_store_f32(sa_u64 a, sa_u64 v) { sa_store_u32(a, v & 0xFFFFFFFFULL); }
        \\static void sa_store_f64(sa_u64 a, sa_u64 v) { sa_store_u64(a, v); }
        \\static sa_u64 sa_add(sa_u64 a, sa_u64 b) { return a + b; }
        \\static sa_u64 sa_sub(sa_u64 a, sa_u64 b) { return a - b; }
        \\static sa_u64 sa_mul(sa_u64 a, sa_u64 b) { return a * b; }
        \\static sa_u64 sa_sdiv(sa_u64 a, sa_u64 b) { if ((sa_i64)b==0) sa_trap("div by zero"); return (sa_u64)((sa_i64)a / (sa_i64)b); }
        \\static sa_u64 sa_udiv(sa_u64 a, sa_u64 b) { if (b==0) sa_trap("div by zero"); return a / b; }
        \\static sa_u64 sa_srem(sa_u64 a, sa_u64 b) { if ((sa_i64)b==0) sa_trap("rem by zero"); return (sa_u64)((sa_i64)a % (sa_i64)b); }
        \\static sa_u64 sa_urem(sa_u64 a, sa_u64 b) { if (b==0) sa_trap("rem by zero"); return a % b; }
        \\static sa_u64 sa_band(sa_u64 a, sa_u64 b) { return a & b; }
        \\static sa_u64 sa_bor(sa_u64 a, sa_u64 b) { return a | b; }
        \\static sa_u64 sa_bxor(sa_u64 a, sa_u64 b) { return a ^ b; }
        \\static sa_u64 sa_bnot(sa_u64 a) { return ~a; }
        \\static sa_u64 sa_neg(sa_u64 a) { return (sa_u64)(-(sa_i64)a); }
        \\static sa_u64 sa_shl(sa_u64 a, sa_u64 b) { return a << (b & 63); }
        \\static sa_u64 sa_lshr(sa_u64 a, sa_u64 b) { return a >> (b & 63); }
        \\static sa_u64 sa_ashr(sa_u64 a, sa_u64 b) { return (sa_u64)((sa_i64)a >> (b & 63)); }
        \\static sa_u64 sa_eq(sa_u64 a, sa_u64 b) { return a == b ? 1 : 0; }
        \\static sa_u64 sa_ne(sa_u64 a, sa_u64 b) { return a != b ? 1 : 0; }
        \\static sa_u64 sa_slt(sa_u64 a, sa_u64 b) { return (sa_i64)a < (sa_i64)b ? 1 : 0; }
        \\static sa_u64 sa_sle(sa_u64 a, sa_u64 b) { return (sa_i64)a <= (sa_i64)b ? 1 : 0; }
        \\static sa_u64 sa_sgt(sa_u64 a, sa_u64 b) { return (sa_i64)a > (sa_i64)b ? 1 : 0; }
        \\static sa_u64 sa_sge(sa_u64 a, sa_u64 b) { return (sa_i64)a >= (sa_i64)b ? 1 : 0; }
        \\static sa_u64 sa_ult(sa_u64 a, sa_u64 b) { return a < b ? 1 : 0; }
        \\static sa_u64 sa_ule(sa_u64 a, sa_u64 b) { return a <= b ? 1 : 0; }
        \\static sa_u64 sa_ugt(sa_u64 a, sa_u64 b) { return a > b ? 1 : 0; }
        \\static sa_u64 sa_uge(sa_u64 a, sa_u64 b) { return a >= b ? 1 : 0; }
        \\static double sa_bits_f64(sa_u64 v) { union { sa_u64 u; double d; } t; t.u = v; return t.d; }
        \\static sa_u64 sa_f64_bits(double d) { union { sa_u64 u; double d; } t; t.d = d; return t.u; }
        \\static float sa_bits_f32(sa_u64 v) { union { uint32_t u; float f; } t; t.u = (uint32_t)v; return t.f; }
        \\static sa_u64 sa_f32_bits(float f) { union { uint32_t u; float f; } t; t.f = f; return (sa_u64)t.u; }
        \\static sa_u64 sa_fadd(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)+sa_bits_f64(b)); }
        \\static sa_u64 sa_fsub(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)-sa_bits_f64(b)); }
        \\static sa_u64 sa_fmul(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)*sa_bits_f64(b)); }
        \\static sa_u64 sa_fdiv(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)/sa_bits_f64(b)); }
        \\static sa_u64 sa_fneg(sa_u64 a) { return sa_f64_bits(-sa_bits_f64(a)); }
        \\static sa_u64 sa_fcmp_eq(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)==sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_fcmp_ne(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)!=sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_fcmp_lt(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)<sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_fcmp_le(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)<=sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_fcmp_gt(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)>sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_fcmp_ge(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)>=sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_cvt_trunc_i1(sa_u64 v){return v&1;} static sa_u64 sa_cvt_trunc_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;}
        \\static sa_u64 sa_cvt_trunc_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;} static sa_u64 sa_cvt_trunc_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;}
        \\static sa_u64 sa_cvt_trunc_i64(sa_u64 v){return v;} static sa_u64 sa_cvt_trunc_u8(sa_u64 v){return v&0xFFu;}
        \\static sa_u64 sa_cvt_trunc_u16(sa_u64 v){return v&0xFFFFu;} static sa_u64 sa_cvt_trunc_u32(sa_u64 v){return v&0xFFFFFFFFu;}
        \\static sa_u64 sa_cvt_trunc_u64(sa_u64 v){return v;} static sa_u64 sa_cvt_trunc_ptr(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_zext_i1(sa_u64 v){return v&1;} static sa_u64 sa_cvt_zext_i8(sa_u64 v){return v&0xFFu;}
        \\static sa_u64 sa_cvt_zext_i16(sa_u64 v){return v&0xFFFFu;} static sa_u64 sa_cvt_zext_i32(sa_u64 v){return v&0xFFFFFFFFu;}
        \\static sa_u64 sa_cvt_zext_i64(sa_u64 v){return v;} static sa_u64 sa_cvt_zext_u8(sa_u64 v){return v&0xFFu;}
        \\static sa_u64 sa_cvt_zext_u16(sa_u64 v){return v&0xFFFFu;} static sa_u64 sa_cvt_zext_u32(sa_u64 v){return v&0xFFFFFFFFu;}
        \\static sa_u64 sa_cvt_zext_u64(sa_u64 v){return v;} static sa_u64 sa_cvt_zext_ptr(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_sext_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;} static sa_u64 sa_cvt_sext_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;}
        \\static sa_u64 sa_cvt_sext_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;} static sa_u64 sa_cvt_sext_i64(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_sext_i1(sa_u64 v){return (sa_u64)(sa_i64)(v&1? -1:0);} static sa_u64 sa_cvt_sext_u8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;}
        \\static sa_u64 sa_cvt_sext_u16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;} static sa_u64 sa_cvt_sext_u32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;}
        \\static sa_u64 sa_cvt_sext_u64(sa_u64 v){return v;} static sa_u64 sa_cvt_sext_ptr(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_sitofp_f32(sa_u64 v){return sa_f32_bits((float)(sa_i64)v);} static sa_u64 sa_cvt_sitofp_f64(sa_u64 v){return sa_f64_bits((double)(sa_i64)v);}
        \\static sa_u64 sa_cvt_uitofp_f32(sa_u64 v){return sa_f32_bits((float)v);} static sa_u64 sa_cvt_uitofp_f64(sa_u64 v){return sa_f64_bits((double)v);}
        \\static sa_u64 sa_cvt_fptosi_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)sa_bits_f64(v);} static sa_u64 sa_cvt_fptosi_i64(sa_u64 v){return (sa_u64)(sa_i64)sa_bits_f64(v);}
        \\static sa_u64 sa_cvt_fptosi_u32(sa_u64 v){return (sa_u64)(uint32_t)sa_bits_f64(v);} static sa_u64 sa_cvt_fptosi_u64(sa_u64 v){return (sa_u64)sa_bits_f64(v);}
        \\static sa_u64 sa_cvt_fptosi_i1(sa_u64 v){return ((sa_i64)sa_bits_f64(v))&1;} static sa_u64 sa_cvt_fptosi_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)sa_bits_f64(v);}
        \\static sa_u64 sa_cvt_fptosi_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)sa_bits_f64(v);} static sa_u64 sa_cvt_fptosi_u8(sa_u64 v){return (sa_u64)(uint8_t)sa_bits_f64(v);}
        \\static sa_u64 sa_cvt_fptosi_u16(sa_u64 v){return (sa_u64)(uint16_t)sa_bits_f64(v);} static sa_u64 sa_cvt_fptosi_ptr(sa_u64 v){return (sa_u64)sa_bits_f64(v);}
        \\static sa_u64 sa_cvt_fptrunc_f32(sa_u64 v){return sa_f32_bits((float)sa_bits_f64(v));} static sa_u64 sa_cvt_fpext_f64(sa_u64 v){float f=sa_bits_f32(v); return sa_f64_bits((double)f);}
        \\static sa_u64 sa_cvt_bitcast_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)(uint32_t)v;} static sa_u64 sa_cvt_bitcast_u32(sa_u64 v){return v&0xFFFFFFFFu;}
        \\static sa_u64 sa_cvt_bitcast_i64(sa_u64 v){return v;} static sa_u64 sa_cvt_bitcast_u64(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_bitcast_f32(sa_u64 v){return v&0xFFFFFFFFu;} static sa_u64 sa_cvt_bitcast_f64(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_bitcast_ptr(sa_u64 v){return v;} static sa_u64 sa_cvt_bitcast_i8(sa_u64 v){return v&0xFFu;}
        \\static sa_u64 sa_cvt_bitcast_u8(sa_u64 v){return v&0xFFu;} static sa_u64 sa_cvt_bitcast_i16(sa_u64 v){return v&0xFFFFu;}
        \\static sa_u64 sa_cvt_bitcast_u16(sa_u64 v){return v&0xFFFFu;} static sa_u64 sa_cvt_bitcast_i1(sa_u64 v){return v&1;}
        \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, len) signature
        \\static sa_u64 sa_print_bytes(sa_u64 addr, sa_u64 len) { uint32_t a=sa_addr(addr); if ((size_t)a+(size_t)len>sizeof(sa_mem)) sa_trap("print oob"); fwrite(&sa_mem[a],1,(size_t)len,stdout); return 0; }
        \\static sa_u64 sa_f32_to_f64(sa_u64 v) { return sa_f64_bits((double)sa_bits_f32(v)); }
        \\static sa_u64 sa_f64_to_f32(sa_u64 v) { return sa_f32_bits((float)sa_bits_f64(v)); }
        \\static sa_u64 sa_fadd32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)+sa_bits_f32(b)); }
        \\static sa_u64 sa_fsub32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)-sa_bits_f32(b)); }
        \\static sa_u64 sa_fmul32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)*sa_bits_f32(b)); }
        \\static sa_u64 sa_fdiv32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)/sa_bits_f32(b)); }
        \\static sa_u64 sa_fneg32(sa_u64 a) { return sa_f32_bits(-sa_bits_f32(a)); }
        \\static sa_u64 sa_fcmp_eq32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)==sa_bits_f32(b)?1:0; }
        \\static sa_u64 sa_fcmp_ne32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)!=sa_bits_f32(b)?1:0; }
        \\static sa_u64 sa_fcmp_lt32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)<sa_bits_f32(b)?1:0; }
        \\static sa_u64 sa_fcmp_le32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)<=sa_bits_f32(b)?1:0; }
        \\static sa_u64 sa_fcmp_gt32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)>sa_bits_f32(b)?1:0; }
        \\static sa_u64 sa_fcmp_ge32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)>=sa_bits_f32(b)?1:0; }
        \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (value, width, sign) signature
        \\static sa_u64 sa_srcmask(sa_u64 v, unsigned w, int sgn) {
        \\  if (w >= 64) return v;
        \\  if (w == 32) return sgn ? (sa_u64)(sa_i64)(int32_t)(uint32_t)v : (sa_u64)(uint32_t)v;
        \\  if (w == 1) return v & 1u;
        \\  { sa_u64 m = (w == 64) ? ~(sa_u64)0 : ((((sa_u64)1) << w) - 1); sa_u64 r = v & m;
        \\    if (sgn && (r >> (w - 1)) & 1u) r |= ~m; return r; }
        \\}
        \\static sa_u64 sa_fnaddr(int i) { return (sa_u64)(uint64_t)(1000000 + i); }
        \\
    );
}

/// Best-effort slot resolution for liveness: reg/symbol/text operands that
/// denote a local slot. Returns null for immediates, labels, funcs, consts.
fn readSlotOf(fsig: sig.FunctionSig, use_global: bool, symbols: anytype, op: inst.Operand) ?u32 {
    switch (op) {
        .reg => |r| return regSlot(fsig, use_global, r) catch null,
        .symbol => |id| return fsig.slotOf(id),
        .text, .native_text => |t| {
            var text = std.mem.trim(u8, t, " \t");
            if (text.len == 0) return null;
            if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
            if (std.mem.lastIndexOf(u8, text, " as ")) |idx| text = std.mem.trim(u8, text[0..idx], " \t\r");
            if (text.len == 0) return null;
            if (symbols.findId(text)) |id| return fsig.slotOf(id);
            return null;
        },
        else => return null,
    }
}

fn defSlotOf(fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) ?u32 {
    switch (op) {
        .reg => |r| return regSlot(fsig, use_global, r) catch null,
        .symbol => |id| return fsig.slotOf(id),
        else => return null,
    }
}

/// Slots defined but never read in the function body. Skipping emission for
/// these is semantics-preserving ONLY for side-effect-free definitions
/// (the emitter filters by kind); callers must still emit trapping or
/// memory-observably-effectful instructions.
/// Per-instruction def/use classification shared by the forward
/// (never-read slots) and backward (point-wise dead defs) passes.
fn collectDefUse(allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, use_global: bool, base: inst.Instruction, defs: *std.array_list.Managed(u32), uses: *std.array_list.Managed(u32)) !void {
    switch (base.kind) {
        .return_ => {
            if (readSlotOf(fsig, use_global, verified.symbols, base.operands[0])) |sl| try uses.append(sl);
        },
        .try_, .early_return => {
            if (defSlotOf(fsig, use_global, base.operands[0])) |sl| try defs.append(sl);
            if (readSlotOf(fsig, use_global, verified.symbols, base.operands[1])) |sl| try uses.append(sl);
        },
        .op, .alloc, .stack_alloc, .ptr_add, .load, .take, .atomic_load => {
            if (defSlotOf(fsig, use_global, base.operands[0])) |sl| try defs.append(sl);
            for (base.operands[1..]) |opnd| {
                if (readSlotOf(fsig, use_global, verified.symbols, opnd)) |sl| try uses.append(sl);
            }
        },
        .store, .atomic_store, .release => {
            for (base.operands) |opnd| {
                if (readSlotOf(fsig, use_global, verified.symbols, opnd)) |sl| try uses.append(sl);
            }
        },
        .call, .call_indirect => {
            if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                var parsed = pc.*;
                defer parsed.deinit(allocator);
                if (parsed.dest) |dest| {
                    if (verified.symbols.findId(dest)) |id| {
                        if (fsig.slotOf(id)) |sl| try defs.append(sl);
                    }
                }
                for (parsed.args) |arg| {
                    if (readSlotOf(fsig, use_global, verified.symbols, inst.Operand{ .text = arg.text })) |sl| try uses.append(sl);
                }
                if (parsed.is_indirect) {
                    if (readSlotOf(fsig, use_global, verified.symbols, inst.Operand{ .text = parsed.callee })) |sl| try uses.append(sl);
                }
            } else |_| {}
        },
        .cmpxchg => {
            if (defSlotOf(fsig, use_global, base.operands[0])) |sl| try defs.append(sl);
            if (defSlotOf(fsig, use_global, base.operands[1])) |sl| try defs.append(sl);
            for (base.operands[2..]) |opnd| {
                if (readSlotOf(fsig, use_global, verified.symbols, opnd)) |sl| try uses.append(sl);
            }
            if (base.atomic_expected_text) |t| {
                if (readSlotOf(fsig, use_global, verified.symbols, inst.Operand{ .text = t })) |sl| try uses.append(sl);
            }
            if (base.atomic_new_text) |t| {
                if (readSlotOf(fsig, use_global, verified.symbols, inst.Operand{ .text = t })) |sl| try uses.append(sl);
            }
        },
        .atomic_rmw => {
            if (defSlotOf(fsig, use_global, base.operands[0])) |sl| try defs.append(sl);
            for (base.operands[1..]) |opnd| {
                if (readSlotOf(fsig, use_global, verified.symbols, opnd)) |sl| try uses.append(sl);
            }
        },
        .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow => {
            if (defSlotOf(fsig, use_global, base.operands[0])) |sl| try defs.append(sl);
            if (readSlotOf(fsig, use_global, verified.symbols, base.operands[1])) |sl| try uses.append(sl);
        },
        .panic => {
            if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                var parsed = pc.*;
                defer parsed.deinit(allocator);
                for (parsed.args) |arg| {
                    if (readSlotOf(fsig, use_global, verified.symbols, inst.Operand{ .text = arg.text })) |sl| try uses.append(sl);
                }
            } else |_| {}
        },
        .br, .br_null => {
            if (readSlotOf(fsig, use_global, verified.symbols, base.operands[0])) |sl| try uses.append(sl);
        },
        else => {
            for (base.operands) |opnd| {
                if (readSlotOf(fsig, use_global, verified.symbols, opnd)) |sl| try uses.append(sl);
            }
        },
    }
}

fn computeDeadSlots(allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, use_global: bool, task: FuncTask) !std.AutoHashMap(u32, void) {
    var defs = std.AutoHashMap(u32, void).init(allocator);
    defer defs.deinit();
    var reads = std.AutoHashMap(u32, void).init(allocator);
    defer reads.deinit();
    // Seed defs with parameter slots: the prologue maps params into them,
    // so an unread param is a dead store too (e.g. unused `ptr` above).
    for (fsig.param_ids) |pid| {
        if (fsig.slotOf(pid)) |sl| try defs.put(sl, {});
    }
    var tmp_defs = std.array_list.Managed(u32).init(allocator);
    defer tmp_defs.deinit();
    var tmp_uses = std.array_list.Managed(u32).init(allocator);
    defer tmp_uses.deinit();
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        tmp_defs.clearRetainingCapacity();
        tmp_uses.clearRetainingCapacity();
        try collectDefUse(allocator, verified, fsig, use_global, base, &tmp_defs, &tmp_uses);
        for (tmp_defs.items) |sl| try defs.put(sl, {});
        for (tmp_uses.items) |sl| try reads.put(sl, {});
    }
    var dead = std.AutoHashMap(u32, void).init(allocator);
    var it = defs.iterator();
    while (it.next()) |e| {
        if (reads.get(e.key_ptr.*) == null) try dead.put(e.key_ptr.*, {});
    }
    return dead;
}

/// Straight-line kill: indices of side-effect-free definitions overwritten
/// by a later redefinition with no read in between and no control-flow join
/// in between (no label/jmp/br/return/trap). Eliding these silences
/// clang-analyzer-deadcode.DeadStores without changing behavior. A full
/// backward dataflow would be unsound here without a CFG (a positional
/// predecessor kill does not dominate across branches), so this stays
/// deliberately local: anything crossing a join is left to the never-read
/// (global) filter instead.
fn computeElideIdx(allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, use_global: bool, task: FuncTask) !std.AutoHashMap(usize, void) {
    var elide = std.AutoHashMap(usize, void).init(allocator);
    errdefer elide.deinit();
    var tmp_defs = std.array_list.Managed(u32).init(allocator);
    defer tmp_defs.deinit();
    var tmp_uses = std.array_list.Managed(u32).init(allocator);
    defer tmp_uses.deinit();
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        const pure_def = switch (base.kind) {
            .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow, .ptr_add, .try_, .early_return => true,
            .op => blk: {
                const opcode = base.op_kind orelse break :blk false;
                break :blk !opCanTrap(opcode);
            },
            else => false,
        };
        if (!pure_def) continue;
        tmp_defs.clearRetainingCapacity();
        tmp_uses.clearRetainingCapacity();
        try collectDefUse(allocator, verified, fsig, use_global, base, &tmp_defs, &tmp_uses);
        if (tmp_defs.items.len != 1) continue;
        const dst = tmp_defs.items[0];
        var j: usize = i + 1;
        while (j < task.end_idx) : (j += 1) {
            const nb = verified.annotated[j].base;
            switch (nb.kind) {
                .label, .jmp, .br, .br_null, .return_, .panic, .panic_msg, .native => break,
                else => {},
            }
            tmp_defs.clearRetainingCapacity();
            tmp_uses.clearRetainingCapacity();
            try collectDefUse(allocator, verified, fsig, use_global, nb, &tmp_defs, &tmp_uses);
            var is_read = false;
            for (tmp_uses.items) |sl| {
                if (sl == dst) {
                    is_read = true;
                    break;
                }
            }
            if (is_read) break;
            var is_kill = false;
            for (tmp_defs.items) |sl| {
                if (sl == dst) {
                    is_kill = true;
                    break;
                }
            }
            if (is_kill) {
                try elide.put(i, {});
                break;
            }
        }
    }
    return elide;
}

fn sigNormName(name: []const u8) []const u8 {
    var n = name;
    if (n.len >= 2 and n[0] == '"' and n[n.len - 1] == '"') n = n[1 .. n.len - 1];
    if (n.len >= 1 and n[0] == '@') n = n[1..];
    return n;
}

fn sigReturnWidth(sigmap: anytype, callee: []const u8) ?u32 {
    const key = sigNormName(callee);
    if (sigmap.get(key)) |ty| {
        if (ty == .void) return null;
        return packWidth(ty);
    }
    return null;
}

fn opCanTrap(opcode: inst.OpKind) bool {
    return switch (opcode) {
        .sdiv, .udiv, .srem, .urem, .div, .rem => true,
        else => false,
    };
}

fn emitLinearInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, widths: *WidthMap, sigmap: anytype, uniform_arity: usize, dead: *const std.AutoHashMap(u32, void)) !void {
    last_c_inst = base.raw_text;
    last_c_func = fsig.name;
    trackWidths(widths, allocator, symbols, fsig, use_global, base);
    // Sharpen knowledge the generic transfer drops: known callee return
    // types, atomic old-value types, and try_ payload passthrough.
    switch (base.kind) {
        .call => {
            if (call.parseInstructionCall(allocator, base, symbols)) |*parsed_const| {
                var parsed = parsed_const.*;
                defer parsed.deinit(allocator);
                if (!parsed.is_indirect) {
                    if (parsed.dest) |dest| {
                        if (symbols.findId(dest)) |id| {
                            if (fsig.slotOf(id)) |slot| {
                                if (sigReturnWidth(sigmap, parsed.callee)) |w| {
                                    widths.put(slot, w) catch {};
                                }
                            }
                        }
                    }
                }
            } else |_| {}
        },
        .try_, .early_return => {
            const dstslot: ?u32 = switch (base.operands[0]) {
                .reg => |r| regSlot(fsig, use_global, r) catch null,
                .symbol => |id| fsig.slotOf(id),
                else => null,
            };
            if (dstslot) |dst| {
                if (widthOfOperand(widths, fsig, use_global, base.operands[1])) |w| {
                    widths.put(dst, w) catch {};
                }
            }
        },
        .cmpxchg => {
            const ty = memPrimType(base);
            if (packWidth(ty)) |w| {
                const s0: ?u32 = switch (base.operands[0]) {
                    .reg => |r| regSlot(fsig, use_global, r) catch null,
                    .symbol => |id| fsig.slotOf(id),
                    else => null,
                };
                if (s0) |dst| widths.put(dst, w) catch {};
            }
            if (base.operands[1] == .reg or base.operands[1] == .symbol) {
                const s1: ?u32 = switch (base.operands[1]) {
                    .reg => |r| regSlot(fsig, use_global, r) catch null,
                    .symbol => |id| fsig.slotOf(id),
                    else => null,
                };
                if (s1) |dst| widths.put(dst, 1) catch {};
            }
        },
        .atomic_rmw => {
            const ty = memPrimType(base);
            if (packWidth(ty)) |w| {
                const s0: ?u32 = switch (base.operands[0]) {
                    .reg => |r| regSlot(fsig, use_global, r) catch null,
                    .symbol => |id| fsig.slotOf(id),
                    else => null,
                };
                if (s0) |dst| widths.put(dst, w) catch {};
            }
        },
        else => {},
    }
    switch (base.kind) {
        .return_ => try emitReturnStmt(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0], "  "),
        .try_, .early_return => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            if (dead.get(slot) != null) {
                try writer.print("  /* dead store elided: {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            }
            try writer.writeAll("  { sa_u64 sa_t = (");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.print("); r{d} = sa_t; }}\n", .{slot});
        },
        .op => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            const opcode = base.op_kind orelse return CEmitError.InvalidOperand;
            if (dead.get(slot) != null and !opCanTrap(opcode)) {
                try writer.print("  /* dead store elided: {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            }
            if (inst.isTypeConversionOpKind(opcode)) {
                if (base.operands[2] != .ty) return CEmitError.InvalidOperand;
                var tgt = tagToPrim(base.operands[2].ty);
                if ((opcode == .sitofp or opcode == .uitofp) and tgt != .f32 and tgt != .f64) tgt = .f64;
                try writer.print("  r{d} = ", .{slot});
                try emitCvtExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, tgt, base.operands[1], widths);
                try writer.writeAll(";\n");
                return;
            }
            try writer.print("  r{d} = ", .{slot});
            try emitOpExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, base.operands[1], base.operands[2], widths);
            try writer.writeAll(";\n");
        },
        .alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            try writer.print("  r{d} = sa_alloc(", .{slot});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(");\n");
        },
        .stack_alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            try writer.print("  r{d} = sa_salloc(", .{slot});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(");\n");
        },
        .ptr_add => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            if (dead.get(slot) != null) {
                try writer.print("  /* dead store elided: {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            }
            if (offIsZero(base.operands[2])) {
                try writer.print("  r{d} = ", .{slot});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(";\n");
            } else {
                try writer.print("  r{d} = sa_ptr_add(", .{slot});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            }
        },
        .load, .take, .atomic_load => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            if (offIsZero(base.operands[2])) {
                try writer.print("  r{d} = {s}(", .{ slot, load_fn });
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  r{d} = {s}(sa_ptr_add(", .{ slot, load_fn });
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll("));\n");
            }
        },
        .store, .atomic_store => {
            const ty = memPrimType(base);
            const store_fn = memStoreFn(ty);
            if (offIsZero(base.operands[1])) {
                try writer.print("  {s}(", .{store_fn});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  {s}(sa_ptr_add(", .{store_fn});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll("), ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            }
        },
        .call => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                try writer.print("  sa_trap(\"unsupported call: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            };
            defer parsed.deinit(allocator);
            var dest_dead = false;
            if (parsed.dest) |dest| {
                const id = symbols.findId(dest) orelse return CEmitError.InvalidOperand;
                const slot = fsig.slotOf(id) orelse return CEmitError.InvalidOperand;
                if (dead.get(slot) != null) {
                    dest_dead = true;
                    try writer.writeAll("  (void)(");
                } else {
                    try writer.print("  r{d} = ", .{slot});
                }
            } else {
                try writer.writeAll("  ");
            }
            if (parsed.is_indirect) {
                try writer.writeAll("sa_call_indirect(");
                try resolveTextToC(writer, symbols, fsig, const_addrs, parsed.callee);
                var argc: usize = 0;
                for (parsed.args) |arg| {
                    try writer.writeAll(", ");
                    try resolveTextToC(writer, symbols, fsig, const_addrs, arg.text);
                    argc += 1;
                }
                while (argc < uniform_arity) : (argc += 1) {
                    try writer.writeAll(", 0");
                }
                if (dest_dead) try writer.writeAll("));\n") else try writer.writeAll(");\n");
            } else {
                // known host shims map to runtime helpers
                if (std.mem.eql(u8, parsed.callee, "sa_print_bytes") or std.mem.eql(u8, parsed.callee, "@sa_print_bytes")) {
                    try writer.writeAll("sa_print_bytes(");
                    for (parsed.args, 0..) |arg, idx| {
                        if (idx != 0) try writer.writeAll(", ");
                        try resolveTextToC(writer, symbols, fsig, const_addrs, arg.text);
                    }
                    if (dest_dead) try writer.writeAll("));\n") else try writer.writeAll(");\n");
                } else {
                    try cFuncName(writer, parsed.callee);
                    try writer.writeAll("(");
                    var argc: usize = 0;
                    for (parsed.args) |arg| {
                        if (argc != 0) try writer.writeAll(", ");
                        try resolveTextToC(writer, symbols, fsig, const_addrs, arg.text);
                        argc += 1;
                    }
                    while (argc < uniform_arity) : (argc += 1) {
                        if (argc != 0) try writer.writeAll(", ");
                        try writer.writeAll("0");
                    }
                    if (dest_dead) try writer.writeAll("));\n") else try writer.writeAll(");\n");
                }
            }
        },
        .call_indirect => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                try writer.writeAll("  sa_trap(\"unsupported call_indirect\");\n");
                return;
            };
            defer parsed.deinit(allocator);
            var ind_dead = false;
            if (parsed.dest) |dest| {
                const id = symbols.findId(dest) orelse return CEmitError.InvalidOperand;
                const slot = fsig.slotOf(id) orelse return CEmitError.InvalidOperand;
                if (dead.get(slot) != null) {
                    ind_dead = true;
                    try writer.writeAll("  (void)(");
                } else {
                    try writer.print("  r{d} = ", .{slot});
                }
            } else {
                try writer.writeAll("  ");
            }
            try writer.writeAll("sa_call_indirect(");
            try resolveTextToC(writer, symbols, fsig, const_addrs, parsed.callee);
            var ind_argc: usize = 0;
            for (parsed.args) |arg| {
                try writer.writeAll(", ");
                try resolveTextToC(writer, symbols, fsig, const_addrs, arg.text);
                ind_argc += 1;
            }
            while (ind_argc < uniform_arity) : (ind_argc += 1) {
                try writer.writeAll(", 0");
            }
            if (ind_dead) try writer.writeAll("));\n") else try writer.writeAll(");\n");
        },
        .cmpxchg => {
            const dst_old = try dstSlot(fsig, use_global, base.operands[0]);
            const dst_ok = try dstSlot(fsig, use_global, base.operands[1]);
            const expected = base.atomic_expected_text orelse return CEmitError.InvalidOperand;
            const new_text = base.atomic_new_text orelse return CEmitError.InvalidOperand;
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            const store_fn = memStoreFn(ty);
            try writer.writeAll("  { sa_u64 sa_ad = sa_ptr_add(");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.writeAll(", ");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[3]);
            try writer.print("); sa_u64 sa_old = {s}(sa_ad); sa_u64 sa_ex = (", .{load_fn});
            try resolveTextToC(writer, symbols, fsig, const_addrs, expected);
            try writer.writeAll("); sa_u64 sa_ok = (sa_old == sa_ex) ? 1 : 0; if (sa_ok) ");
            try writer.print("{s}(sa_ad, (", .{store_fn});
            try resolveTextToC(writer, symbols, fsig, const_addrs, new_text);
            if (dead.get(dst_old) != null) {
                try writer.writeAll(")); (void)sa_old; ");
            } else {
                try writer.print(")); r{d} = sa_old; ", .{dst_old});
            }
            if (dead.get(dst_ok) != null) {
                try writer.writeAll("(void)sa_ok; }}\n");
            } else {
                try writer.print("r{d} = sa_ok; }}\n", .{dst_ok});
            }
        },
        .atomic_rmw => {
            const op = base.atomic_rmw_op orelse return CEmitError.InvalidOperand;
            const dst = try dstSlot(fsig, use_global, base.operands[0]);
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            const store_fn = memStoreFn(ty);
            try writer.writeAll("  { sa_u64 sa_ad = sa_ptr_add(");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(", ");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.print("); sa_u64 sa_old = {s}(sa_ad); sa_u64 sa_vl = (", .{load_fn});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[3]);
            try writer.writeAll("); sa_u64 sa_nw = ");
            switch (op) {
                .add => try writer.writeAll("sa_add(sa_old, sa_vl)"),
                .sub => try writer.writeAll("sa_sub(sa_old, sa_vl)"),
                .@"and" => try writer.writeAll("sa_band(sa_old, sa_vl)"),
                .@"or" => try writer.writeAll("sa_bor(sa_old, sa_vl)"),
                .xor => try writer.writeAll("sa_bxor(sa_old, sa_vl)"),
                .xchg => try writer.writeAll("sa_vl"),
                .min => try writer.writeAll("(sa_sle(sa_old, sa_vl) ? sa_old : sa_vl)"),
                .max => try writer.writeAll("(sa_sge(sa_old, sa_vl) ? sa_old : sa_vl)"),
                .umin => try writer.writeAll("(sa_ule(sa_old, sa_vl) ? sa_old : sa_vl)"),
                .umax => try writer.writeAll("(sa_uge(sa_old, sa_vl) ? sa_old : sa_vl)"),
            }
            if (dead.get(dst) != null) {
                try writer.print("; {s}(sa_ad, sa_nw); (void)sa_old; }}\n", .{store_fn});
            } else {
                try writer.print("; {s}(sa_ad, sa_nw); r{d} = sa_old; }}\n", .{ store_fn, dst });
            }
        },
        .fence => {
            try writer.writeAll("  /* fence: no-op on C backend */\n");
        },
        .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            if (dead.get(slot) != null) {
                try writer.print("  /* dead store elided: {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            }
            try writer.print("  r{d} = (", .{slot});
            switch (base.operands[1]) {
                .reg, .symbol, .func, .label, .imm_i64, .imm_int, .imm_u64, .imm_float, .text, .native_text => {
                    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                },
                else => return CEmitError.InvalidOperand,
            }
            try writer.writeAll(");\n");
        },
        .panic => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                try writer.print("  sa_trap(\"panic: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            };
            defer parsed.deinit(allocator);
            if (parsed.args.len != 1) {
                try writer.writeAll("  sa_trap(\"panic\");\n");
                return;
            }
            try writer.writeAll("  sa_panic(");
            try resolveTextToC(writer, symbols, fsig, const_addrs, parsed.args[0].text);
            try writer.writeAll(");\n");
        },
        .panic_msg => {
            try writer.writeAll("  sa_trap(\"panic_msg\");\n");
        },
        .move_ => {
            try writer.print("  /* no-op {s}: {s} */\n", .{ @tagName(base.kind), std.mem.trim(u8, base.raw_text, " \t\r\n") });
        },
        .release => {
            try writer.writeAll("  sa_free(");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
            try writer.writeAll(");\n");
        },
        .native => {
            const raw = std.mem.trim(u8, base.raw_text, " \t\r\n");
            if (std.mem.indexOf(u8, raw, "asm sideeffect \"\"") != null) {
                try writer.writeAll("  /* no-op empty inline asm */\n");
            } else {
                try writer.writeAll("  sa_trap(\"unsupported native: ");
                try writeCStrEscaped(writer, raw);
                try writer.writeAll("\");\n");
            }
        },
        else => {
            // jmp/br/br_null/label/func_decl/extern/export/test_decl handled by caller
            try writer.print("  sa_trap(\"unsupported {s}: ", .{@tagName(base.kind)});
            try writeCStrEscaped(writer, std.mem.trim(u8, base.raw_text, " \t\r\n"));
            try writer.writeAll("\");\n");
        },
    }
}

fn emitOneFunction(writer: anytype, allocator: std.mem.Allocator, verified: anytype, task: FuncTask, const_addrs: anytype, fn_idx: anytype, c_opt: CEmitOptions, sigmap: anytype, uniform_arity: usize) !void {
    const fsig = verified.function_sigs[task.fsig_index];
    const use_global = taskUsesGlobalRegIds(fsig, verified, task);
    last_c_func = fsig.name;
    var widths = WidthMap.init(allocator);
    defer widths.deinit();
    // Definitely-unread slots: pure redefinitions elided, effectful calls
    // kept in (void) form (silences clang-analyzer-deadcode.DeadStores).
    var dead = computeDeadSlots(allocator, verified, fsig, use_global, task) catch std.AutoHashMap(u32, void).init(allocator);
    defer dead.deinit();
    var elide = computeElideIdx(allocator, verified, fsig, use_global, task) catch std.AutoHashMap(usize, void).init(allocator);
    defer elide.deinit();
    // Seed parameter slots with their declared types: caller and callee
    // share the u64-bits invariant, so this is exact (unlike JS, which
    // must infer argument domains at runtime).
    for (fsig.param_ids, 0..) |pid, pi| {
        if (pi >= fsig.params.len) break;
        if (fsig.slotOf(pid)) |slot| {
            if (packWidth(fsig.params[pi].ty)) |w| {
                widths.put(slot, w) catch {};
            }
        }
    }
    // Uniform-arity prototype: every function takes exactly uniform_arity
    // u64 params (extras ignored, missing padded with 0 at call sites).
    // This makes direct calls, the ftable, and indirect dispatch share
    // one C signature shape.
    try writer.writeAll("static sa_u64 ");
    try cFuncName(writer, fsig.name);
    try writer.writeAll("(");
    if (uniform_arity == 0) {
        try writer.writeAll("void");
    } else {
        for (0..uniform_arity) |pi| {
            if (pi != 0) try writer.writeAll(", ");
            try writer.print("sa_u64 a{d}", .{pi});
        }
    }
    try writer.writeAll(") {\n");
    const nregs = fsig.reg_ids.len;
    if (nregs > 0) {
        // Declare registers. Slots aliasing static consts are
        // initialized to the const address (mirrors the JS backend);
        // all other slots start at 0. Params bind into their slots after.
        var s: usize = 0;
        while (s < nregs) : (s += 1) {
            if (s == 0) try writer.writeAll("  sa_u64 ") else try writer.writeAll(", ");
            try writer.print("r{d} = ", .{s});
            const gid = fsig.reg_ids[s];
            if (verified.symbols.lookupName(gid)) |gname| {
                if (const_addrs.get(gname) != null) {
                    try writeConstSym(writer, gname);
                } else {
                    try writer.writeAll("0");
                }
            } else {
                try writer.writeAll("0");
            }
        }
        try writer.writeAll(";\n");
    }
    // map params to slots (skip slots never read in the body)
    for (fsig.param_ids, 0..) |pid, pi| {
        if (fsig.slotOf(pid)) |slot| {
            if (dead.get(slot) != null) {
                try writer.print("  /* dead param elided: r{d} = a{d}; */\n", .{ slot, pi });
                continue;
            }
            try writer.print("  r{d} = a{d};\n", .{ slot, pi });
        }
    }
    // Silence misc-unused-parameters for padded uniform-arity params.
    for (0..uniform_arity) |pi| {
        try writer.print("  (void)a{d};\n", .{pi});
    }
    if (c_opt.debug_comments) {
        try writer.print("  /* fn {s} regs={d} */\n", .{ fsig.name, nregs });
    }
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        if (elide.get(i) != null) {
            try writer.print("  /* dead store elided: {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
            continue;
        }
        switch (base.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                try writer.writeAll("  sa_trap(\"nested decl\");\n");
            },
            .label => {
                const id: u32 = switch (base.operands[0]) {
                    .label => |v| v, .symbol => |v| v, else => 0,
                };
                // Join point: merges are untracked, drop widths (sound
                // fallback; mirrors the JS backend clearing at labels).
                widths.clearRetainingCapacity();
                try writer.print("SA_L_{d}:\n", .{id});
                if (c_opt.debug_comments) {
                    try writer.print("  /* {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                }
            },
            .jmp => {
                const id: u32 = switch (base.operands[1]) {
                    .label => |v| v, .symbol => |v| v, else => return CEmitError.InvalidOperand,
                };
                try writer.print("  goto SA_L_{d};\n", .{id});
            },
            .br => {
                const t: u32 = switch (base.operands[1]) {
                    .label => |v| v, .symbol => |v| v, else => return CEmitError.InvalidOperand,
                };
                const f: u32 = switch (base.operands[3]) {
                    .label => |v| v, .symbol => |v| v, else => return CEmitError.InvalidOperand,
                };
                if (t == f) {
                    try writer.print("  goto SA_L_{d};\n", .{t});
                    continue;
                }
                try writer.writeAll("  if (sa_truthy(");
                try resolveValueToC(writer, verified.symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.print(")) goto SA_L_{d}; else goto SA_L_{d};\n", .{ t, f });
            },
            .br_null => {
                const t: u32 = switch (base.operands[1]) {
                    .label => |v| v, .symbol => |v| v, else => return CEmitError.InvalidOperand,
                };
                const f: u32 = switch (base.operands[3]) {
                    .label => |v| v, .symbol => |v| v, else => return CEmitError.InvalidOperand,
                };
                if (t == f) {
                    try writer.print("  goto SA_L_{d};\n", .{t});
                    continue;
                }
                try writer.writeAll("  if ((");
                try resolveValueToC(writer, verified.symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.print(") == 0) goto SA_L_{d}; else goto SA_L_{d};\n", .{ t, f });
            },
            else => {
                if (c_opt.debug_comments) {
                    try writer.print("  /* {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                }
                try emitLinearInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, base, &widths, sigmap, uniform_arity, &dead);
            },
        }
    }
    // default return for fallthrough
    if (fsig.return_ty == .void and !fsig.return_fallible) {
        try writer.writeAll("  return 0;\n}\n");
    } else {
        try writer.writeAll("  return 0;\n}\n");
    }
}

pub fn emitCToString(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, c_opt: CEmitOptions) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    var fn_names = std.array_list.Managed([]const u8).init(allocator);
    defer fn_names.deinit();
    var fn_idx = std.StringHashMap(usize).init(allocator);
    defer fn_idx.deinit();
    for (verified.const_decls) |decl| {
        if (decl.value != .vtable) continue;
        for (decl.value.vtable.slots) |slot| {
            if (fn_idx.contains(slot.func_name)) continue;
            try fn_idx.put(slot.func_name, fn_names.items.len);
            try fn_names.append(slot.func_name);
        }
    }
    const tasks = try collectFuncTasks(allocator, verified);
    defer allocator.free(tasks);
    // Callee return-type map for width seeding (normalized names).
    var sigmap = std.StringHashMap(sig.PrimType).init(allocator);
    defer sigmap.deinit();
    for (verified.function_sigs) |fs| {
        const key = sigNormName(fs.name);
        if (!sigmap.contains(key)) try sigmap.put(key, fs.return_ty);
    }
    // Uniform arity: every emitted function takes exactly W params.
    var uniform_arity: usize = 1;
    for (tasks) |task| {
        uniform_arity = @max(uniform_arity, verified.function_sigs[task.fsig_index].params.len);
    }
    try writeRuntimeHeader(writer, c_opt, size_bits);
    try writer.print("/* source: {s} */\n", .{source_path});
    // const addresses
    var const_addrs = std.StringHashMap(usize).init(allocator);
    defer const_addrs.deinit();
    var const_cursor: usize = 4096;
    const bump_start: usize = 65536;
    for (verified.const_decls) |decl| {
        const len = constBytesLen(decl.value) catch 0;
        const aligned = std.mem.alignForward(usize, const_cursor, 8);
        if (decl.value == .vtable or len == 0) {
            const is_vt = decl.value == .vtable;
            const slots: usize = if (is_vt) decl.value.vtable.slots.len * 8 else 8;
            const a2 = std.mem.alignForward(usize, const_cursor, 8);
            if (a2 + slots > bump_start) return CEmitError.Failed;
            try const_addrs.put(decl.name, a2);
            try writer.writeAll("#define ");
            try writeConstSym(writer, decl.name);
            try writer.print(" {d}UL /* {s} */\n", .{ a2, @tagName(decl.value) });
            const_cursor = a2 + slots;
            continue;
        }
        if (aligned + len > bump_start) return CEmitError.Failed;
        try const_addrs.put(decl.name, aligned);
        try writer.writeAll("#define ");
        try writeConstSym(writer, decl.name);
        try writer.print(" {d}UL\n", .{aligned});
        const_cursor = aligned + len;
    }
    // forward decls (uniform arity)
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        try writer.writeAll("static sa_u64 ");
        try cFuncName(writer, fsig.name);
        try writer.writeAll("(");
        if (uniform_arity == 0) {
            try writer.writeAll("void");
        } else {
            for (0..uniform_arity) |pi| {
                if (pi != 0) try writer.writeAll(", ");
                try writer.writeAll("sa_u64");
            }
        }
        try writer.writeAll(");\n");
    }
    // forward declaration for the indirect dispatcher (defined after
    // all functions so the ftable can reference them)
    try writer.writeAll("// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform calling convention\nstatic sa_u64 sa_call_indirect(sa_u64 f");
    for (0..uniform_arity) |k| {
        try writer.print(", sa_u64 a{d}", .{k});
    }
    try writer.writeAll(");\n");
    // forward declarations for extern trap stubs (defined at the end):
    // without these, calls to externs hit implicit-declaration errors.
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (std.mem.eql(u8, sigNormName(fsig.name), "sa_print_bytes")) continue;
        try writer.writeAll("static sa_u64 ");
        try cFuncName(writer, fsig.name);
        try writer.writeAll("(");
        if (uniform_arity == 0) {
            try writer.writeAll("void");
        } else {
            for (0..uniform_arity) |pi| {
                if (pi != 0) try writer.writeAll(", ");
                try writer.writeAll("sa_u64");
            }
        }
        try writer.writeAll(");\n");
    }
    for (fn_names.items) |fname| {
        var defined = false;
        for (tasks) |task| {
            if (task.kind == .extern_decl) continue;
            if (std.mem.eql(u8, verified.function_sigs[task.fsig_index].name, fname)) {
                defined = true;
                break;
            }
        }
        if (defined) continue;
        try writer.writeAll("static sa_u64 ");
        try cFuncName(writer, fname);
        try writer.writeAll("(");
        if (uniform_arity == 0) {
            try writer.writeAll("void");
        } else {
            for (0..uniform_arity) |pi| {
                if (pi != 0) try writer.writeAll(", ");
                try writer.writeAll("sa_u64");
            }
        }
        try writer.writeAll(");\n");
    }
    // const init
    try writer.writeAll("static void sa_init_consts(void) {\n  static int done = 0; if (done) return; done = 1;\n");
    for (verified.const_decls) |decl| {
        const len = constBytesLen(decl.value) catch 0;
        if (decl.value == .vtable or len == 0) {
            if (decl.value == .vtable) {
                var sidx: usize = 0;
                for (decl.value.vtable.slots) |vslot| {
                    const fidx = fnIndexOf(fn_idx, vslot.func_name) orelse return CEmitError.UnknownFunction;
                    const addr = const_addrs.get(decl.name) orelse return CEmitError.InvalidOperand;
                    const le: u64 = 1000000 + @as(u64, @intCast(fidx));
                    try writer.print("  sa_store_u64({d}ULL, {d}ULL);\n", .{ addr + sidx * 8, le });
                    sidx += 1;
                }
            }
            continue;
        }
        const bytes = try allocator.alloc(u8, len);
        defer allocator.free(bytes);
        try fillConstBytes(bytes, decl.value);
        const addr = const_addrs.get(decl.name) orelse return CEmitError.InvalidOperand;
        try writer.print("  {{ static const uint8_t b[] = {{", .{});
        for (bytes, 0..) |b, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writer.print("{d}", .{b});
        }
        try writer.print("}}; {{ size_t i; for (i = 0; i < {d}; i++) sa_mem[{d} + i] = b[i]; }} }}\n", .{ len, addr });
    }
    try writer.writeAll("}\n");
    var emitted = std.StringHashMap(void).init(allocator);
    defer emitted.deinit();
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (emitted.contains(fsig.name)) continue;
        try emitOneFunction(writer, allocator, verified, task, &const_addrs, &fn_idx, c_opt, &sigmap, uniform_arity);
        try emitted.put(fsig.name, {});
    }
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (emitted.contains(fsig.name)) continue;
        if (std.mem.eql(u8, sigNormName(fsig.name), "sa_print_bytes")) continue; // runtime provides it
        // trap stub (uniform arity)
        try writer.writeAll("static sa_u64 ");
        try cFuncName(writer, fsig.name);
        try writer.writeAll("(");
        if (uniform_arity == 0) {
            try writer.writeAll("void");
        } else {
            for (0..uniform_arity) |pi| {
                if (pi != 0) try writer.writeAll(", ");
                try writer.print("sa_u64 a{d}", .{pi});
            }
        }
        try writer.writeAll(") {");
        for (0..uniform_arity) |pi| {
            try writer.print(" (void)a{d};", .{pi});
        }
        try writer.print(" sa_trap(\"extern {s}\"); return 0; }}\n", .{fsig.name});
        try emitted.put(fsig.name, {});
    }
    // Trap stubs for vtable-referenced functions with no definition.
    for (fn_names.items) |fname| {
        if (emitted.contains(fname)) continue;
        var found = false;
        for (tasks) |task| {
            if (std.mem.eql(u8, verified.function_sigs[task.fsig_index].name, fname)) {
                found = true;
                break;
            }
        }
        if (found) continue;
        try writer.writeAll("static sa_u64 ");
        try cFuncName(writer, fname);
        try writer.writeAll("(");
        if (uniform_arity == 0) {
            try writer.writeAll("void");
        } else {
            for (0..uniform_arity) |pi| {
                if (pi != 0) try writer.writeAll(", ");
                try writer.print("sa_u64 a{d}", .{pi});
            }
        }
        try writer.writeAll(") {");
        for (0..uniform_arity) |pi| {
            try writer.print(" (void)a{d};", .{pi});
        }
        try writer.print(" sa_trap(\"missing {s}\"); return 0; }}\n", .{fname});
        try emitted.put(fname, {});
    }
    // Indirect dispatch: uniform signature makes a plain function-pointer
    // table exact (indices match fn_idx / vtable const encoding).
    try writer.writeAll("typedef sa_u64 (*sa_fn_t)(");
    if (uniform_arity == 0) {
        try writer.writeAll("void");
    } else {
        for (0..uniform_arity) |pi| {
            if (pi != 0) try writer.writeAll(", ");
            try writer.writeAll("sa_u64");
        }
    }
    // A zero-length array is a GNU extension and makes the bounds check
    // tautological; pin a single NULL entry instead.
    if (fn_names.items.len == 0) {
        try writer.writeAll(");\nstatic sa_fn_t sa_ftable[1] = {0};\n");
    } else {
        try writer.writeAll(");\nstatic sa_fn_t sa_ftable[] = {");
        for (fn_names.items, 0..) |fname, fi| {
            if (fi != 0) try writer.writeAll(", ");
            try cFuncName(writer, fname);
        }
        try writer.writeAll("};\n");
    }
    try writer.writeAll("// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform calling convention\nstatic sa_u64 sa_call_indirect(sa_u64 f");
    for (0..uniform_arity) |k| {
        try writer.print(", sa_u64 a{d}", .{k});
    }
    try writer.writeAll(") {\n  uint64_t idx = (uint64_t)(f - 1000000);\n");
    try writer.print("  if (idx >= {d}ULL) {{ sa_trap(\"bad indirect callee\"); return 0; }}\n", .{fn_names.items.len});
    try writer.writeAll("  return sa_ftable[idx](");
    for (0..uniform_arity) |k| {
        if (k != 0) try writer.writeAll(", ");
        try writer.print("a{d}", .{k});
    }
    try writer.writeAll(");\n}\n");
    try writer.writeAll("int main(void) { sa_init_consts();\n");
    // call sa main if present
    var found_main = false;
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (std.mem.eql(u8, fsig.name, "main")) {
            found_main = true;
            break;
        }
    }
    if (found_main) {
        try writer.writeAll("  sa_u64 rc = sa_fn_main(");
        for (0..uniform_arity) |k| {
            if (k != 0) try writer.writeAll(", ");
            try writer.writeAll("0");
        }
        try writer.writeAll(");\n  return (int)(rc & 0xFF);\n}\n");
    } else {
        try writer.writeAll("  return 0;\n}\n");
    }
    return out.toOwnedSlice();
}

pub fn emitCToFile(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, c_opt: CEmitOptions, path: []const u8) !void {
    const text = try emitCToString(allocator, verified, source_path, size_bits, c_opt);
    defer allocator.free(text);
    const dir = std.fs.path.dirname(path);
    if (dir) |d| try sio.cwd().makePath(d);
    const f = try sio.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(text);
}

test "c ident sanitizes names" {
    var buf: [64]u8 = undefined;
    var fbs = std.Io.Writer.fixed(&buf);
    try cIdent(&fbs, "hello-world.foo");
    try std.testing.expectEqualStrings("hello_world_foo", fbs.buffered());
}
