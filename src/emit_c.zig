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
    gas: bool = true, // emit SA_GAS_CHECK metering (fn entry + every label)
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

/// Defined-task lookup by normalized function name (for reachability).
/// Returns the task's fsig_index, or null for externs/unknown names.
fn taskIndexByName(tasks: []FuncTask, verified: anytype, norm: []const u8) ?usize {
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        if (std.mem.eql(u8, sigNormName(verified.function_sigs[task.fsig_index].name), norm)) return task.fsig_index;
    }
    return null;
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
                .fadd, .fsub, .fmul, .fdiv => {
                    // Result domain mirrors emission (floatOpDomain): f32
                    // whenever the 32-bit helper is selected, otherwise
                    // f64. Must stay in sync with emitOpExpr or downstream
                    // domain selection breaks for float chains.
                    if (floatOpDomain(widths, fsig, use_global, base.operands[1], base.operands[2]) == .f64) {
                        widths.put(dst, WidthFloatBit | 64) catch return;
                    } else {
                        widths.put(dst, WidthFloatBit | 32) catch return;
                    }
                },
                .div, .rem, .shr => {
                    // Compat aliases: result width follows the selected
                    // helper (mirrors cAliasCallee), so chained aliases
                    // propagate the resolved domain instead of the old
                    // forced-signed default. (gt/lt results stay in the
                    // `=> 1` arm above, exactly like the JS backend.)
                    const kk = cCombinedKind(
                        cOperandKind(widths, fsig, use_global, base.operands[1]),
                        cOperandKind(widths, fsig, use_global, base.operands[2]),
                    );
                    switch (opcode) {
                        .div => {
                            if (kk == .float) widths.put(dst, WidthFloatBit | 64) catch return;
                            if (kk == .unsigned) widths.put(dst, 64) catch return;
                            widths.put(dst, 64 | WidthSignBit) catch return;
                        },
                        else => {
                            // .rem: unsigned only when proven; .shr:
                            // lshr unless proven signed (mirrors JS).
                            if (kk == .unsigned or (opcode == .shr and kk != .signed)) widths.put(dst, 64) catch return;
                            widths.put(dst, 64 | WidthSignBit) catch return;
                        },
                    }
                },
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

/// Operand domain for kind-driven compat aliases (div/rem/gt/lt/shr),
/// mirroring the interpreter and the JS backend: float wins, then signed,
/// else unsigned. Unknown preserves forced-signed lowering, so only
/// statically-known shapes change behavior.
const COpndKind = enum { float, signed, unsigned, unknown };

fn cOperandKind(widths: *const WidthMap, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) COpndKind {
    if (widthOfOperand(widths, fsig, use_global, op)) |w| {
        if (widthIsFloat(w)) return .float;
        return if (widthIsSigned(w)) .signed else .unsigned;
    }
    // Text immediates: same numeric cascade as the JS backend.
    switch (op) {
        .text, .native_text => |t| {
            var text = std.mem.trim(u8, t, " \t");
            if (text.len == 0) return .unknown;
            if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
            if (std.mem.lastIndexOf(u8, text, " as ")) |idx| text = std.mem.trim(u8, text[0..idx], " \t\r");
            if (text.len == 0) return .unknown;
            if (std.fmt.parseInt(i64, text, 10)) |_| return .signed else |_| {}
            if (std.fmt.parseInt(u64, text, 10)) |_| return .unsigned else |_| {}
            if (std.mem.indexOfAny(u8, text, ".eE")) |_| {
                if (std.fmt.parseFloat(f64, text)) |_| return .float else |_| {}
            }
            return .unknown;
        },
        else => return .unknown,
    }
}

fn cCombinedKind(a: COpndKind, b: COpndKind) COpndKind {
    if (a == .float or b == .float) return .float;
    if (a == .signed or b == .signed) return .signed;
    if (a == .unsigned and b == .unsigned) return .unsigned;
    return .unknown;
}

/// C helper for kind-driven compat aliases (div/rem/gt/lt/shr), mirroring
/// JS aliasCallee. Unknown keeps forced-signed lowering (except shr, where
/// JS lowers unknown to lshr).
fn cAliasCallee(opcode: inst.OpKind, k: COpndKind) []const u8 {
    return switch (opcode) {
        .div => switch (k) {
            .float => "sa_fdiv",
            .unsigned => "sa_udiv",
            else => "sa_sdiv",
        },
        .rem => switch (k) {
            .unsigned => "sa_urem",
            else => "sa_srem",
        },
        .shr => switch (k) {
            .signed => "sa_ashr",
            else => "sa_lshr",
        },
        .gt => switch (k) {
            .float => "sa_fcmp_gt",
            .unsigned => "sa_ugt",
            else => "sa_sgt",
        },
        .lt => switch (k) {
            .float => "sa_fcmp_lt",
            .unsigned => "sa_ult",
            else => "sa_slt",
        },
        else => unreachable,
    };
}

/// Narrow logical shift: with a statically sub-64-bit lhs, mask the value
/// to its width and the count to 5 bits (347: an i32-held 0xFFFFFFFF must
/// shift as u32, not as sign-extended u64). 64-bit/unknown shapes keep the
/// plain 64-bit helper. Returns true when the narrow form was emitted.
fn emitNarrowLshr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, lhs: inst.Operand, rhs: inst.Operand, widths: *const WidthMap) !bool {
    const w = widthOfOperand(widths, fsig, use_global, lhs) orelse return false;
    if (widthIsFloat(w) or widthBits(w) >= 64) return false;
    try writer.print("sa_lshr(sa_srcmask(", .{});
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
    try writer.print(", {d}, 0), sa_band(", .{widthBits(w)});
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
    try writer.writeAll(", 31))");
    return true;
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

/// Float-domain decision for binary float ops: .f32 uses the 32-bit
/// helper, .f64 the 64-bit one. f32 iff both sides are proven f32;
/// everything else computes in f64 (int sides convert with JS Numbers
/// parity; unknowns go raw, with f32 sides promoted). Unknowns are
/// overwhelmingly f64 loop vars/indirect results, and promotion of a
/// known f32 side is exact, so f64 is the safe default.
const FDom = enum { f32, f64 };

fn floatOpDomain(widths: *const WidthMap, fsig: sig.FunctionSig, use_global: bool, lhs: inst.Operand, rhs: inst.Operand) FDom {
    const lk = cOperandKind(widths, fsig, use_global, lhs);
    const rk = cOperandKind(widths, fsig, use_global, rhs);
    if (lk != .float and rk != .float) return .f64;
    const l32 = floatWidthIs32(widths, fsig, use_global, lhs);
    const r32 = floatWidthIs32(widths, fsig, use_global, rhs);
    return if (l32 and r32) .f32 else .f64;
}

/// Emit one side of a float-domain op: floats promote/demote as needed,
/// ints convert (signedness from kind), unknowns keep legacy behavior
/// (truncate in f32 domain, raw in f64).
fn emitFNumOperand(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, widths: *const WidthMap, op: inst.Operand, kind: COpndKind, want: FDom) !void {
    switch (kind) {
        .float => try emitFloatOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, op, floatWidthIs32(widths, fsig, use_global, op), want == .f32),
        .signed => {
            try writer.print("sa_cvt_sitofp_f{s}(", .{if (want == .f32) "32" else "64"});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, op);
            try writer.writeAll(")");
        },
        .unsigned => {
            try writer.print("sa_cvt_uitofp_f{s}(", .{if (want == .f32) "32" else "64"});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, op);
            try writer.writeAll(")");
        },
        .unknown => {
            // f32 domain with an unknown side is unreachable (f32
            // requires both sides proven); raw is the f64 behavior.
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, op);
        },
    }
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
    // Float ALU: both sides statically f32 -> f32 helpers; one side f32
    // with the other unproven -> f32 helpers with truncation; otherwise
    // f64 helpers with f32 sides promoted (mirrors JS f64-domain helpers).
    switch (opcode) {
        .fadd, .fsub, .fmul, .fdiv => {
            const base: []const u8 = switch (opcode) {
                .fadd => "sa_fadd",
                .fsub => "sa_fsub",
                .fmul => "sa_fmul",
                else => "sa_fdiv",
            };
            const lk = cOperandKind(widths, fsig, use_global, lhs);
            const rk = cOperandKind(widths, fsig, use_global, rhs);
            const dom = floatOpDomain(widths, fsig, use_global, lhs, rhs);
            const li = lk == .signed or lk == .unsigned;
            const ri = rk == .signed or rk == .unsigned;
            const lu = lk == .unknown;
            const ru = rk == .unknown;
            // Legacy raw path only when no float side exists and no
            // unknown/int mixing needs conversion; everything else goes
            // through domain-correct operand emission.
            if (dom == .f64 and lk != .float and rk != .float and !((lu and ri) or (li and ru))) {
                try writer.print("{s}(", .{base});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
                try writer.writeAll(")");
                return;
            }
            if (dom == .f32) {
                try writer.print("{s}32(", .{base});
            } else {
                try writer.print("{s}(", .{base});
            }
            try emitFNumOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, widths, lhs, lk, dom);
            try writer.writeAll(", ");
            try emitFNumOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, widths, rhs, rk, dom);
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
            const base: []const u8 = switch (opcode) {
                .fcmp_eq => "sa_fcmp_eq",
                .fcmp_ne => "sa_fcmp_ne",
                .fcmp_lt => "sa_fcmp_lt",
                .fcmp_le => "sa_fcmp_le",
                .fcmp_gt => "sa_fcmp_gt",
                else => "sa_fcmp_ge",
            };
            const lk = cOperandKind(widths, fsig, use_global, lhs);
            const rk = cOperandKind(widths, fsig, use_global, rhs);
            const dom = floatOpDomain(widths, fsig, use_global, lhs, rhs);
            const li = lk == .signed or lk == .unsigned;
            const ri = rk == .signed or rk == .unsigned;
            const lu = lk == .unknown;
            const ru = rk == .unknown;
            if (dom == .f64 and lk != .float and rk != .float and !((lu and ri) or (li and ru))) {
                // No float side and no convertible mixing: legacy raw path.
                try writer.print("{s}(", .{base});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
                try writer.writeAll(")");
                return;
            }
            if (dom == .f32) {
                try writer.print("{s}32(", .{base});
            } else {
                try writer.print("{s}(", .{base});
            }
            try emitFNumOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, widths, lhs, lk, dom);
            try writer.writeAll(", ");
            try emitFNumOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, widths, rhs, rk, dom);
            try writer.writeAll(")");
            return;
        },
        else => {},
    }
    // Kind-driven compat aliases (div/rem/gt/lt/shr): signedness (and
    // float domain) follows the operand kinds, mirroring the interpreter
    // and the JS backend. Unknown keeps forced-signed lowering (except
    // shr, where JS lowers unknown to lshr), so only statically-known
    // shapes change behavior.
    switch (opcode) {
        .div, .rem, .shr, .gt, .lt => {
            const k = cCombinedKind(cOperandKind(widths, fsig, use_global, lhs), cOperandKind(widths, fsig, use_global, rhs));
            const callee = cAliasCallee(opcode, k);
            if ((opcode == .gt or opcode == .lt) and k == .float) {
                // Float comparisons use the fcmp family with f32 sides
                // promoted (C holds f32 as low-32-bit patterns).
                try writer.print("{s}(", .{callee});
                try emitFloatOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, floatWidthIs32(widths, fsig, use_global, lhs), false);
                try writer.writeAll(", ");
                try emitFloatOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs, floatWidthIs32(widths, fsig, use_global, rhs), false);
                try writer.writeAll(")");
                return;
            }
            if (opcode == .div and k == .float) {
                try writer.writeAll("sa_fdiv(");
                try emitFloatOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, floatWidthIs32(widths, fsig, use_global, lhs), false);
                try writer.writeAll(", ");
                try emitFloatOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs, floatWidthIs32(widths, fsig, use_global, rhs), false);
                try writer.writeAll(")");
                return;
            }
            // shr-via-lshr on a narrow lhs needs the 32-bit form too.
            if (std.mem.eql(u8, callee, "sa_lshr")) {
                if (try emitNarrowLshr(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs, widths)) return;
            }
            try writer.print("{s}(", .{callee});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
            return;
        },
        .lshr => {
            if (try emitNarrowLshr(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs, widths)) return;
            try writer.writeAll("sa_lshr(");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
            return;
        },
        else => {},
    }
    const name: []const u8 = switch (opcode) {
        .add => "sa_add", .sub => "sa_sub", .mul => "sa_mul",
        .sdiv => "sa_sdiv", .udiv => "sa_udiv", .srem => "sa_srem", .urem => "sa_urem",
        .@"and" => "sa_band", .@"or" => "sa_bor", .xor => "sa_bxor",
        .shl => "sa_shl", .lshr => "sa_lshr", .ashr => "sa_ashr",
        .not => "sa_bnot",
        .neg => "sa_neg",
        .eq => "sa_eq", .ne => "sa_ne",
        .slt => "sa_slt", .sle => "sa_sle", .sgt => "sa_sgt", .sge => "sa_sge",
        .ult => "sa_ult", .ule => "sa_ule", .ugt => "sa_ugt", .uge => "sa_uge",
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

/// Runtime helper catalog. The always-needed core (includes, memory,
/// sa_trap, gas) is emitted unconditionally by writePreamble; everything
/// below is emitted ONLY when the generated body references it (plus
/// transitive deps). `name` doubles as the usage needle (`name ++ "("`),
/// so it must be the exact C function name. `deps` lists other catalog
/// entries required by `code` (`sa_trap` is implicit: always emitted).
/// Emission preserves table order, which keeps callees before callers.
const HelperDef = struct {
    name: []const u8,
    code: []const u8,
    deps: []const []const u8,
};

const kRuntimeHelpers: []const HelperDef = &.{
    .{ .name = "sa_panic", .code =
    \\static __attribute__((noreturn)) void sa_panic(sa_u64 code) { char b[24]; int n = 0; sa_u64 v = code; char t[24]; int m = 0; if (v == 0) t[m++] = '0'; while (v > 0) { t[m++] = (char)('0' + (v % 10)); v /= 10; } fputs("[sa-panic] code=", stderr); while (m > 0) b[n++] = t[--m]; fwrite(b, 1, (size_t)n, stderr); fputc('\n', stderr); exit(1); }
    , .deps = &.{} },
    .{ .name = "sa_ok_none", .code =
    \\static sa_u64 sa_ok_none(void) { return 0; }
    , .deps = &.{} },
    .{ .name = "sa_ok_val", .code =
    \\static sa_u64 sa_ok_val(sa_u64 v) { (void)v; return v; }
    , .deps = &.{} },
    .{ .name = "sa_truthy", .code =
    \\static int sa_truthy(sa_u64 v) { return v != 0; }
    , .deps = &.{} },
    .{ .name = "sa_align", .code =
    \\static sa_u64 sa_align(sa_u64 n, sa_u64 a) { return (n + (a - 1)) & ~(a - 1); }
    , .deps = &.{} },
    .{ .name = "sa_alloc", .code =
    \\static sa_u64 sa_alloc(sa_u64 size) {
    \\  size = sa_align(size, 8); if (size == 0) size = 8;
    \\  uint32_t base = sa_brk;
    \\  { sa_u64 nb = (sa_u64)base + size + 8; if (nb > (sa_u64)sizeof(sa_mem)) sa_trap("out of memory (bump)"); sa_brk = (uint32_t)nb; } // NOLINT(bugprone-misplaced-widening-cast): nb range-checked above
    \\  { uint32_t i; for (i = 0; i < (uint32_t)(size + 8); i++) sa_mem[base + i] = 0; }
    \\  sa_mem[base] = (uint8_t)(size & 0xFFu); sa_mem[base + 1] = (uint8_t)((size >> 8) & 0xFFu);
    \\  sa_mem[base + 2] = (uint8_t)((size >> 16) & 0xFFu); sa_mem[base + 3] = (uint8_t)((size >> 24) & 0xFFu);
    \\  return (sa_u64)base + 8;
    \\}
    , .deps = &.{"sa_align"} },
    .{ .name = "sa_salloc", .code =
    \\static sa_u64 sa_salloc(sa_u64 size) { return sa_alloc(size); }
    , .deps = &.{"sa_alloc"} },
    .{ .name = "sa_free", .code =
    \\static sa_u64 sa_free(sa_u64 ptr) { (void)ptr; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_ptr_add", .code =
    \\static sa_u64 sa_ptr_add(sa_u64 base, sa_u64 off) { return base + off; }
    , .deps = &.{} },
    .{ .name = "sa_addr", .code =
    \\static uint32_t sa_addr(sa_u64 a) { return (uint32_t)(a & 0xFFFFFFFFu); }
    , .deps = &.{} },
    .{ .name = "sa_checked_addr", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, size) signature
    \\static uint32_t sa_checked_addr(sa_u64 a, size_t sz) {
    \\  uint32_t x = sa_addr(a);
    \\  if ((size_t)x + sz > (size_t)sizeof(sa_mem)) sa_trap("oob linear-memory access");
    \\  return x;
    \\}
    , .deps = &.{"sa_addr"} },
    .{ .name = "sa_load_u8", .code =
    \\static sa_u64 sa_load_u8(sa_u64 a) { return (sa_u64)sa_mem[sa_checked_addr(a, 1)]; }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_i8", .code =
    \\static sa_u64 sa_load_i8(sa_u64 a) { return (sa_u64)(sa_i64)(int8_t)sa_mem[sa_checked_addr(a, 1)]; }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_u16", .code =
    \\static sa_u64 sa_load_u16(sa_u64 a) { uint32_t x = sa_checked_addr(a, 2); return (sa_u64)((uint16_t)((uint16_t)sa_mem[x] | ((uint16_t)sa_mem[x + 1] << 8))); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_i16", .code =
    \\static sa_u64 sa_load_i16(sa_u64 a) { uint32_t x = sa_checked_addr(a, 2); int16_t v = (int16_t)((uint16_t)sa_mem[x] | ((uint16_t)sa_mem[x + 1] << 8)); return (sa_u64)(sa_i64)v; }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_u32", .code =
    \\static sa_u64 sa_load_u32(sa_u64 a) { uint32_t x = sa_checked_addr(a, 4); return (sa_u64)((uint32_t)sa_mem[x] | ((uint32_t)sa_mem[x + 1] << 8) | ((uint32_t)sa_mem[x + 2] << 16) | ((uint32_t)sa_mem[x + 3] << 24)); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_i32", .code =
    \\static sa_u64 sa_load_i32(sa_u64 a) { uint32_t x = sa_checked_addr(a, 4); int32_t v = (int32_t)((uint32_t)sa_mem[x] | ((uint32_t)sa_mem[x + 1] << 8) | ((uint32_t)sa_mem[x + 2] << 16) | ((uint32_t)sa_mem[x + 3] << 24)); return (sa_u64)(sa_i64)v; }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_u64", .code =
    \\static sa_u64 sa_load_u64(sa_u64 a) { uint32_t x = sa_checked_addr(a, 8); uint64_t v = 0; unsigned k; for (k = 0; k < 8; k++) v |= ((uint64_t)sa_mem[x + k]) << (k * 8); return v; }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_load_f32", .code =
    \\static sa_u64 sa_load_f32(sa_u64 a) { return sa_load_u32(a) & 0xFFFFFFFFULL; }
    , .deps = &.{"sa_load_u32"} },
    .{ .name = "sa_load_f64", .code =
    \\static sa_u64 sa_load_f64(sa_u64 a) { return sa_load_u64(a); }
    , .deps = &.{"sa_load_u64"} },
    .{ .name = "sa_store_u8", .code =
    \\static void sa_store_u8(sa_u64 a, sa_u64 v) { sa_mem[sa_checked_addr(a, 1)] = (uint8_t)(v & 0xFFu); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_store_u16", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, value) signature
    \\static void sa_store_u16(sa_u64 a, sa_u64 v) { uint32_t x = sa_checked_addr(a, 2); sa_mem[x] = (uint8_t)(v & 0xFFu); sa_mem[x + 1] = (uint8_t)((v >> 8) & 0xFFu); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_store_u32", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, value) signature
    \\static void sa_store_u32(sa_u64 a, sa_u64 v) { uint32_t x = sa_checked_addr(a, 4); unsigned k; for (k = 0; k < 4; k++) sa_mem[x + k] = (uint8_t)((v >> (k * 8)) & 0xFFu); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_store_u64", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, value) signature
    \\static void sa_store_u64(sa_u64 a, sa_u64 v) { uint32_t x = sa_checked_addr(a, 8); unsigned k; for (k = 0; k < 8; k++) sa_mem[x + k] = (uint8_t)((v >> (k * 8)) & 0xFFu); }
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_store_f32", .code =
    \\static void sa_store_f32(sa_u64 a, sa_u64 v) { sa_store_u32(a, v & 0xFFFFFFFFULL); }
    , .deps = &.{"sa_store_u32"} },
    .{ .name = "sa_store_f64", .code =
    \\static void sa_store_f64(sa_u64 a, sa_u64 v) { sa_store_u64(a, v); }
    , .deps = &.{"sa_store_u64"} },
    .{ .name = "sa_add", .code =
    \\static sa_u64 sa_add(sa_u64 a, sa_u64 b) { return a + b; }
    , .deps = &.{} },
    .{ .name = "sa_sub", .code =
    \\static sa_u64 sa_sub(sa_u64 a, sa_u64 b) { return a - b; }
    , .deps = &.{} },
    .{ .name = "sa_mul", .code =
    \\static sa_u64 sa_mul(sa_u64 a, sa_u64 b) { return a * b; }
    , .deps = &.{} },
    .{ .name = "sa_sdiv", .code =
    \\static sa_u64 sa_sdiv(sa_u64 a, sa_u64 b) { if ((sa_i64)b==0) sa_trap("div by zero"); return (sa_u64)((sa_i64)a / (sa_i64)b); }
    , .deps = &.{} },
    .{ .name = "sa_udiv", .code =
    \\static sa_u64 sa_udiv(sa_u64 a, sa_u64 b) { if (b==0) sa_trap("div by zero"); return a / b; }
    , .deps = &.{} },
    .{ .name = "sa_srem", .code =
    \\static sa_u64 sa_srem(sa_u64 a, sa_u64 b) { if ((sa_i64)b==0) sa_trap("rem by zero"); return (sa_u64)((sa_i64)a % (sa_i64)b); }
    , .deps = &.{} },
    .{ .name = "sa_urem", .code =
    \\static sa_u64 sa_urem(sa_u64 a, sa_u64 b) { if (b==0) sa_trap("rem by zero"); return a % b; }
    , .deps = &.{} },
    .{ .name = "sa_band", .code =
    \\static sa_u64 sa_band(sa_u64 a, sa_u64 b) { return a & b; }
    , .deps = &.{} },
    .{ .name = "sa_bor", .code =
    \\static sa_u64 sa_bor(sa_u64 a, sa_u64 b) { return a | b; }
    , .deps = &.{} },
    .{ .name = "sa_bxor", .code =
    \\static sa_u64 sa_bxor(sa_u64 a, sa_u64 b) { return a ^ b; }
    , .deps = &.{} },
    .{ .name = "sa_bnot", .code =
    \\static sa_u64 sa_bnot(sa_u64 a) { return ~a; }
    , .deps = &.{} },
    .{ .name = "sa_neg", .code =
    \\static sa_u64 sa_neg(sa_u64 a) { return (sa_u64)(-(sa_i64)a); }
    , .deps = &.{} },
    .{ .name = "sa_shl", .code =
    \\static sa_u64 sa_shl(sa_u64 a, sa_u64 b) { return a << (b & 63); }
    , .deps = &.{} },
    .{ .name = "sa_lshr", .code =
    \\static sa_u64 sa_lshr(sa_u64 a, sa_u64 b) { return a >> (b & 63); }
    , .deps = &.{} },
    .{ .name = "sa_ashr", .code =
    \\static sa_u64 sa_ashr(sa_u64 a, sa_u64 b) { return (sa_u64)((sa_i64)a >> (b & 63)); }
    , .deps = &.{} },
    .{ .name = "sa_eq", .code =
    \\static sa_u64 sa_eq(sa_u64 a, sa_u64 b) { return a == b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_ne", .code =
    \\static sa_u64 sa_ne(sa_u64 a, sa_u64 b) { return a != b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_slt", .code =
    \\static sa_u64 sa_slt(sa_u64 a, sa_u64 b) { return (sa_i64)a < (sa_i64)b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_sle", .code =
    \\static sa_u64 sa_sle(sa_u64 a, sa_u64 b) { return (sa_i64)a <= (sa_i64)b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_sgt", .code =
    \\static sa_u64 sa_sgt(sa_u64 a, sa_u64 b) { return (sa_i64)a > (sa_i64)b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_sge", .code =
    \\static sa_u64 sa_sge(sa_u64 a, sa_u64 b) { return (sa_i64)a >= (sa_i64)b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_ult", .code =
    \\static sa_u64 sa_ult(sa_u64 a, sa_u64 b) { return a < b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_ule", .code =
    \\static sa_u64 sa_ule(sa_u64 a, sa_u64 b) { return a <= b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_ugt", .code =
    \\static sa_u64 sa_ugt(sa_u64 a, sa_u64 b) { return a > b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_uge", .code =
    \\static sa_u64 sa_uge(sa_u64 a, sa_u64 b) { return a >= b ? 1 : 0; }
    , .deps = &.{} },
    .{ .name = "sa_bits_f64", .code =
    \\static double sa_bits_f64(sa_u64 v) { union { sa_u64 u; double d; } t; t.u = v; return t.d; }
    , .deps = &.{} },
    .{ .name = "sa_f64_bits", .code =
    \\static sa_u64 sa_f64_bits(double d) { union { sa_u64 u; double d; } t; t.d = d; return t.u; }
    , .deps = &.{} },
    .{ .name = "sa_bits_f32", .code =
    \\static float sa_bits_f32(sa_u64 v) { union { uint32_t u; float f; } t; t.u = (uint32_t)v; return t.f; }
    , .deps = &.{} },
    .{ .name = "sa_f32_bits", .code =
    \\static sa_u64 sa_f32_bits(float f) { union { uint32_t u; float f; } t; t.f = f; return (sa_u64)t.u; }
    , .deps = &.{} },
    .{ .name = "sa_fadd", .code =
    \\static sa_u64 sa_fadd(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)+sa_bits_f64(b)); }
    , .deps = &.{ "sa_bits_f64", "sa_f64_bits" } },
    .{ .name = "sa_fsub", .code =
    \\static sa_u64 sa_fsub(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)-sa_bits_f64(b)); }
    , .deps = &.{ "sa_bits_f64", "sa_f64_bits" } },
    .{ .name = "sa_fmul", .code =
    \\static sa_u64 sa_fmul(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)*sa_bits_f64(b)); }
    , .deps = &.{ "sa_bits_f64", "sa_f64_bits" } },
    .{ .name = "sa_fdiv", .code =
    \\static sa_u64 sa_fdiv(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)/sa_bits_f64(b)); }
    , .deps = &.{ "sa_bits_f64", "sa_f64_bits" } },
    .{ .name = "sa_fneg", .code =
    \\static sa_u64 sa_fneg(sa_u64 a) { return sa_f64_bits(-sa_bits_f64(a)); }
    , .deps = &.{ "sa_bits_f64", "sa_f64_bits" } },
    .{ .name = "sa_fcmp_eq", .code =
    \\static sa_u64 sa_fcmp_eq(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)==sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_fcmp_ne", .code =
    \\static sa_u64 sa_fcmp_ne(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)!=sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_fcmp_lt", .code =
    \\static sa_u64 sa_fcmp_lt(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)<sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_fcmp_le", .code =
    \\static sa_u64 sa_fcmp_le(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)<=sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_fcmp_gt", .code =
    \\static sa_u64 sa_fcmp_gt(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)>sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_fcmp_ge", .code =
    \\static sa_u64 sa_fcmp_ge(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)>=sa_bits_f64(b)?1:0; }
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_trunc_i1", .code =
    \\static sa_u64 sa_cvt_trunc_i1(sa_u64 v){return v&1;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_i8", .code =
    \\static sa_u64 sa_cvt_trunc_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_i16", .code =
    \\static sa_u64 sa_cvt_trunc_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_i32", .code =
    \\static sa_u64 sa_cvt_trunc_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_i64", .code =
    \\static sa_u64 sa_cvt_trunc_i64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_u8", .code =
    \\static sa_u64 sa_cvt_trunc_u8(sa_u64 v){return v&0xFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_u16", .code =
    \\static sa_u64 sa_cvt_trunc_u16(sa_u64 v){return v&0xFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_u32", .code =
    \\static sa_u64 sa_cvt_trunc_u32(sa_u64 v){return v&0xFFFFFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_u64", .code =
    \\static sa_u64 sa_cvt_trunc_u64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_trunc_ptr", .code =
    \\static sa_u64 sa_cvt_trunc_ptr(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_i1", .code =
    \\static sa_u64 sa_cvt_zext_i1(sa_u64 v){return v&1;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_i8", .code =
    \\static sa_u64 sa_cvt_zext_i8(sa_u64 v){return v&0xFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_i16", .code =
    \\static sa_u64 sa_cvt_zext_i16(sa_u64 v){return v&0xFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_i32", .code =
    \\static sa_u64 sa_cvt_zext_i32(sa_u64 v){return v&0xFFFFFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_i64", .code =
    \\static sa_u64 sa_cvt_zext_i64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_u8", .code =
    \\static sa_u64 sa_cvt_zext_u8(sa_u64 v){return v&0xFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_u16", .code =
    \\static sa_u64 sa_cvt_zext_u16(sa_u64 v){return v&0xFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_u32", .code =
    \\static sa_u64 sa_cvt_zext_u32(sa_u64 v){return v&0xFFFFFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_u64", .code =
    \\static sa_u64 sa_cvt_zext_u64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_zext_ptr", .code =
    \\static sa_u64 sa_cvt_zext_ptr(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_i1", .code =
    \\static sa_u64 sa_cvt_sext_i1(sa_u64 v){return (sa_u64)(sa_i64)(v&1? -1:0);}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_i8", .code =
    \\static sa_u64 sa_cvt_sext_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_i16", .code =
    \\static sa_u64 sa_cvt_sext_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_i32", .code =
    \\static sa_u64 sa_cvt_sext_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_i64", .code =
    \\static sa_u64 sa_cvt_sext_i64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_u8", .code =
    \\static sa_u64 sa_cvt_sext_u8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_u16", .code =
    \\static sa_u64 sa_cvt_sext_u16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_u32", .code =
    \\static sa_u64 sa_cvt_sext_u32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_u64", .code =
    \\static sa_u64 sa_cvt_sext_u64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sext_ptr", .code =
    \\static sa_u64 sa_cvt_sext_ptr(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_sitofp_f32", .code =
    \\static sa_u64 sa_cvt_sitofp_f32(sa_u64 v){return sa_f32_bits((float)(sa_i64)v);}
    , .deps = &.{"sa_f32_bits"} },
    .{ .name = "sa_cvt_sitofp_f64", .code =
    \\static sa_u64 sa_cvt_sitofp_f64(sa_u64 v){return sa_f64_bits((double)(sa_i64)v);}
    , .deps = &.{"sa_f64_bits"} },
    .{ .name = "sa_cvt_uitofp_f32", .code =
    \\static sa_u64 sa_cvt_uitofp_f32(sa_u64 v){return sa_f32_bits((float)v);}
    , .deps = &.{"sa_f32_bits"} },
    .{ .name = "sa_cvt_uitofp_f64", .code =
    \\static sa_u64 sa_cvt_uitofp_f64(sa_u64 v){return sa_f64_bits((double)v);}
    , .deps = &.{"sa_f64_bits"} },
    .{ .name = "sa_cvt_fptosi_i1", .code =
    \\static sa_u64 sa_cvt_fptosi_i1(sa_u64 v){return ((sa_i64)sa_bits_f64(v))&1;}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_i8", .code =
    \\static sa_u64 sa_cvt_fptosi_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_i16", .code =
    \\static sa_u64 sa_cvt_fptosi_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_i32", .code =
    \\static sa_u64 sa_cvt_fptosi_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_i64", .code =
    \\static sa_u64 sa_cvt_fptosi_i64(sa_u64 v){return (sa_u64)(sa_i64)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_u8", .code =
    \\static sa_u64 sa_cvt_fptosi_u8(sa_u64 v){return (sa_u64)(uint8_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_u16", .code =
    \\static sa_u64 sa_cvt_fptosi_u16(sa_u64 v){return (sa_u64)(uint16_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_u32", .code =
    \\static sa_u64 sa_cvt_fptosi_u32(sa_u64 v){return (sa_u64)(uint32_t)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_u64", .code =
    \\static sa_u64 sa_cvt_fptosi_u64(sa_u64 v){return (sa_u64)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptosi_ptr", .code =
    \\static sa_u64 sa_cvt_fptosi_ptr(sa_u64 v){return (sa_u64)sa_bits_f64(v);}
    , .deps = &.{"sa_bits_f64"} },
    .{ .name = "sa_cvt_fptrunc_f32", .code =
    \\static sa_u64 sa_cvt_fptrunc_f32(sa_u64 v){return sa_f32_bits((float)sa_bits_f64(v));}
    , .deps = &.{ "sa_bits_f64", "sa_f32_bits" } },
    .{ .name = "sa_cvt_fpext_f64", .code =
    \\static sa_u64 sa_cvt_fpext_f64(sa_u64 v){float f=sa_bits_f32(v); return sa_f64_bits((double)f);}
    , .deps = &.{ "sa_bits_f32", "sa_f64_bits" } },
    .{ .name = "sa_cvt_bitcast_i1", .code =
    \\static sa_u64 sa_cvt_bitcast_i1(sa_u64 v){return v&1;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_i8", .code =
    \\static sa_u64 sa_cvt_bitcast_i8(sa_u64 v){return v&0xFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_u8", .code =
    \\static sa_u64 sa_cvt_bitcast_u8(sa_u64 v){return v&0xFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_i16", .code =
    \\static sa_u64 sa_cvt_bitcast_i16(sa_u64 v){return v&0xFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_u16", .code =
    \\static sa_u64 sa_cvt_bitcast_u16(sa_u64 v){return v&0xFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_i32", .code =
    \\static sa_u64 sa_cvt_bitcast_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)(uint32_t)v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_u32", .code =
    \\static sa_u64 sa_cvt_bitcast_u32(sa_u64 v){return v&0xFFFFFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_i64", .code =
    \\static sa_u64 sa_cvt_bitcast_i64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_u64", .code =
    \\static sa_u64 sa_cvt_bitcast_u64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_f32", .code =
    \\static sa_u64 sa_cvt_bitcast_f32(sa_u64 v){return v&0xFFFFFFFFu;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_f64", .code =
    \\static sa_u64 sa_cvt_bitcast_f64(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_cvt_bitcast_ptr", .code =
    \\static sa_u64 sa_cvt_bitcast_ptr(sa_u64 v){return v;}
    , .deps = &.{} },
    .{ .name = "sa_print_bytes", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (addr, len) signature
    \\static sa_u64 sa_print_bytes(sa_u64 addr, sa_u64 len) { uint32_t a=sa_addr(addr); if ((size_t)a+(size_t)len>sizeof(sa_mem)) sa_trap("print oob"); fwrite(&sa_mem[a],1,(size_t)len,stdout); return 0; }
    , .deps = &.{"sa_addr"} },
    .{ .name = "sa_f32_to_f64", .code =
    \\static sa_u64 sa_f32_to_f64(sa_u64 v) { return sa_f64_bits((double)sa_bits_f32(v)); }
    , .deps = &.{ "sa_bits_f32", "sa_f64_bits" } },
    .{ .name = "sa_f64_to_f32", .code =
    \\static sa_u64 sa_f64_to_f32(sa_u64 v) { return sa_f32_bits((float)sa_bits_f64(v)); }
    , .deps = &.{ "sa_bits_f64", "sa_f32_bits" } },
    .{ .name = "sa_fadd32", .code =
    \\static sa_u64 sa_fadd32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)+sa_bits_f32(b)); }
    , .deps = &.{ "sa_bits_f32", "sa_f32_bits" } },
    .{ .name = "sa_fsub32", .code =
    \\static sa_u64 sa_fsub32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)-sa_bits_f32(b)); }
    , .deps = &.{ "sa_bits_f32", "sa_f32_bits" } },
    .{ .name = "sa_fmul32", .code =
    \\static sa_u64 sa_fmul32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)*sa_bits_f32(b)); }
    , .deps = &.{ "sa_bits_f32", "sa_f32_bits" } },
    .{ .name = "sa_fdiv32", .code =
    \\static sa_u64 sa_fdiv32(sa_u64 a, sa_u64 b) { return sa_f32_bits(sa_bits_f32(a)/sa_bits_f32(b)); }
    , .deps = &.{ "sa_bits_f32", "sa_f32_bits" } },
    .{ .name = "sa_fneg32", .code =
    \\static sa_u64 sa_fneg32(sa_u64 a) { return sa_f32_bits(-sa_bits_f32(a)); }
    , .deps = &.{ "sa_bits_f32", "sa_f32_bits" } },
    .{ .name = "sa_fcmp_eq32", .code =
    \\static sa_u64 sa_fcmp_eq32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)==sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_fcmp_ne32", .code =
    \\static sa_u64 sa_fcmp_ne32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)!=sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_fcmp_lt32", .code =
    \\static sa_u64 sa_fcmp_lt32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)<sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_fcmp_le32", .code =
    \\static sa_u64 sa_fcmp_le32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)<=sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_fcmp_gt32", .code =
    \\static sa_u64 sa_fcmp_gt32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)>sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_fcmp_ge32", .code =
    \\static sa_u64 sa_fcmp_ge32(sa_u64 a, sa_u64 b) { return sa_bits_f32(a)>=sa_bits_f32(b)?1:0; }
    , .deps = &.{"sa_bits_f32"} },
    .{ .name = "sa_srcmask", .code =
    \\// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform (value, width, sign) signature
    \\static sa_u64 sa_srcmask(sa_u64 v, unsigned w, int sgn) {
    \\  if (w >= 64) return v;
    \\  if (w == 32) return sgn ? (sa_u64)(sa_i64)(int32_t)(uint32_t)v : (sa_u64)(uint32_t)v;
    \\  if (w == 1) return v & 1u;
    \\  { sa_u64 m = (w == 64) ? ~(sa_u64)0 : ((((sa_u64)1) << w) - 1); sa_u64 r = v & m;
    \\    if (sgn && (r >> (w - 1)) & 1u) { r |= ~m; } return r; }
    \\}
    , .deps = &.{} },
    .{ .name = "sa_fnaddr", .code =
    \\static sa_u64 sa_fnaddr(int i) { return (sa_u64)(uint64_t)(1000000 + i); }
    , .deps = &.{} },
    .{ .name = "sa_http_find", .code =
    \\static sa_http_obj_t *sa_http_find(sa_http_obj_t *t, sa_u64 h) { unsigned i; for (i = 0; i < SA_HTTP_MAX_OBJS; i++) if (t[i].h == h) return &t[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_http_slot", .code =
    \\static sa_http_obj_t *sa_http_slot(sa_http_obj_t *t) { unsigned i; for (i = 0; i < SA_HTTP_MAX_OBJS; i++) if (t[i].h == 0) return &t[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_http_drop", .code =
    \\static void sa_http_drop(sa_http_obj_t *t, sa_u64 h) { sa_http_obj_t *o = sa_http_find(t, h); if (o != 0) o->h = 0; }
    , .deps = &.{"sa_http_find"} },
    .{ .name = "sa_fmt_int", .code =
    \\static int sa_fmt_int(char *d, sa_u64 v, unsigned base, int sgn, int up) {
    \\  unsigned b; sa_u64 mag; int neg = 0; char t[64]; int m = 0; int o; int i;
    \\  if (base != 2 && base != 8 && base != 10 && base != 16 && base != 17) return -1;
    \\  b = (base == 17) ? 16 : base;
    \\  if (sgn && ((sa_i64)v) < 0) { neg = 1; mag = (~v) + 1u; } else { mag = v; }
    \\  if (mag == 0) t[m++] = '0';
    \\  while (mag > 0) { unsigned dg = (unsigned)(mag % b); t[m++] = (char)(dg < 10 ? '0' + dg : (up ? 'A' + dg - 10 : 'a' + dg - 10)); mag /= b; }
    \\  o = neg ? 1 : 0; if (neg) d[0] = '-';
    \\  for (i = 0; i < m; i++) d[o + i] = t[m - 1 - i];
    \\  return o + m;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_owned_new", .code =
    \\static sa_u64 sa_owned_new(sa_u64 ptr, sa_u64 len, unsigned kind) { unsigned i; for (i = 0; i < SA_OWNED_MAX_OBJS; i++) if (sa_owned_bufs[i].h == 0) { sa_u64 h = sa_owned_next++; sa_owned_bufs[i].h = h; sa_owned_bufs[i].ptr = ptr; sa_owned_bufs[i].len = len; sa_owned_bufs[i].kind = kind; return h; } return 0; }
    , .deps = &.{} },
    .{ .name = "sa_owned_find", .code =
    \\static sa_owned_buf_t *sa_owned_find(sa_u64 h) { unsigned i; for (i = 0; i < SA_OWNED_MAX_OBJS; i++) if (sa_owned_bufs[i].h == h) return &sa_owned_bufs[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_owned_drop", .code =
    \\static void sa_owned_drop(sa_u64 h) { sa_owned_buf_t *o = sa_owned_find(h); if (o != 0) o->h = 0; }
    , .deps = &.{"sa_owned_find"} },
    .{ .name = "sa_regex_find", .code =
    \\static sa_regex_t *sa_regex_find(sa_u64 h) { unsigned i; for (i = 0; i < SA_REGEX_MAX_OBJS; i++) if (sa_regexes[i].h == h) return &sa_regexes[i]; return 0; }
    , .deps = &.{} },
};

/// True iff the already-emitted body text calls `func_name` directly
/// (rendered as `sa_fn_<name>(`). Externs are only reachable via direct
/// calls, so this scan is exact; unrenderable names stay conservative.
fn bodyCallsFunction(body_text: []const u8, func_name: []const u8) bool {
    var nbuf: [1024]u8 = undefined;
    var fw = std.Io.Writer.fixed(&nbuf);
    cFuncName(&fw, func_name) catch return true;
    const needle = fw.buffered();
    if (needle.len + 1 > nbuf.len) return true;
    nbuf[needle.len] = '(';
    return std.mem.indexOf(u8, body_text, nbuf[0 .. needle.len + 1]) != null;
}

/// Seed `used` from textual references in the already-emitted body text
/// (`init` + function bodies): a helper is needed iff `name ++ "("`
/// occurs. Comments can only add false positives (safe direction: an
/// extra helper emitted, never a missing one).
fn collectUsedHelpers(allocator: std.mem.Allocator, body_text: []const u8) !std.StringHashMap(void) {
    var used = std.StringHashMap(void).init(allocator);
    errdefer used.deinit();
    var needle: [64]u8 = undefined;
    for (kRuntimeHelpers) |h| {
        if (h.name.len + 1 > needle.len) continue;
        @memcpy(needle[0..h.name.len], h.name);
        needle[h.name.len] = '(';
        if (std.mem.indexOf(u8, body_text, needle[0 .. h.name.len + 1]) != null) {
            try used.put(h.name, {});
        }
    }
    // Fixpoint over deps (table order preserved at emission).
    var changed = true;
    while (changed) {
        changed = false;
        for (kRuntimeHelpers) |h| {
            if (used.get(h.name) == null) continue;
            for (h.deps) |dep| {
                if (used.get(dep) == null) {
                    try used.put(dep, {});
                    changed = true;
                }
            }
        }
    }
    return used;
}

/// True for staged bindings that dispatch guest code host-side (via
/// sa_call_indirect): programs calling them force need_indirect so the
/// dispatcher+ftable are emitted even without a call_indirect inst.
fn bindingNeedsDispatcher(norm_name: []const u8) bool {
    return std.mem.eql(u8, norm_name, "pthread_spawn");
}

/// Staged host bindings for well-known externs (fd/mmap/signal/npm).
/// These mirror the interpreter/JS staged semantics the demos assert on
/// (fake fds, echo signal, byte-level npm checks) — NOT real syscalls,
/// so output stays deterministic with no host dependencies. Emits the
/// definition with the uniform-arity signature and returns true; unknown
/// names return false and the caller falls back to the trap stub.
fn writeExternBinding(writer: anytype, raw_name: []const u8, uniform_arity: usize, gas: bool) !bool {
    const name = sigNormName(raw_name);
    // `voids` bitmask: bit i set => emit `(void)a{i};`. Bit positions
    // follow the extern's own arg order (a0 = first arg), so e.g. mmap
    // voids a0 (fd, staged) while consuming a1 (len).
    const Binding = struct { voids: u64, tag: enum {
        fd_open,
        fd_close,
        fd_read,
        mmap,
        munmap,
        signal,
        npm_totalmem,
        npm_parallelism,
        npm_isabs,
        npm_iseq,
        pthread_spawn,
        pthread_join,
        pthread_drop,
        dlopen,
        dlsym,
        dlclose,
        sqlite3_prepare,
        sqlite3_step,
        sqlite3_finalize,
        fmt_i64_into,
        fmt_u64_into,
        fmt_f64_into,
        fmt_bool_into,
        fmt_bytes_into,
        fmt_i64,
        fmt_u64,
        fmt_f64,
        fmt_bool,
        fmt_bytes,
        fmt_buffer_data,
        fmt_buffer_len,
        fmt_buffer_free,
        modstate_get_u64,
        modstate_set_u64,
        string_concat,
        string_index_of,
        string_last_index_of,
        string_starts_with,
        string_ends_with,
        string_to_lower_ascii,
        string_to_upper_ascii,
        string_repeat,
        string_pad_start,
        string_pad_end,
        string_from_char_code,
        string_from_code_point,
        string_code_point_at,
        string_replace,
        parse_float,
        regex_compile,
        regex_match,
        regex_group_ptr,
        regex_group_len,
        regex_group_start,
        regex_group_count,
        regex_free,
        regex_match_free,
        http_client_new,
        http_client_req_new,
        http_client_req_add_header,
        http_client_req_set_body,
        http_client_req_send,
        http_client_resp_status,
        http_client_resp_body_reader,
        http_client_resp_read_chunk,
        http_client_resp_free,
        http_client_body_reader_free,
        http_client_req_free,
        http_client_free,
        http_server_new,
        http_server_start,
        http_server_accept,
        http_server_req_get_path,
        http_server_req_get_header,
        http_server_req_get_body,
        http_server_resp_stream_new,
        http_server_resp_stream_write,
        http_server_resp_stream_flush,
        http_server_resp_stream_end,
        http_server_resp_stream_free,
        http_server_req_free,
        http_server_free,
    } };
    const all_void: u64 = ~@as(u64, 0);
    const b: ?Binding = if (std.mem.eql(u8, name, "fd_open"))
        .{ .voids = all_void, .tag = .fd_open }
    else if (std.mem.eql(u8, name, "fd_close"))
        .{ .voids = all_void, .tag = .fd_close }
    else if (std.mem.eql(u8, name, "fd_read"))
        .{ .voids = all_void, .tag = .fd_read }
    else if (std.mem.eql(u8, name, "mmap"))
        .{ .voids = 0b1, .tag = .mmap }
    else if (std.mem.eql(u8, name, "munmap"))
        .{ .voids = all_void, .tag = .munmap }
    else if (std.mem.eql(u8, name, "signal"))
        .{ .voids = all_void ^ 0b1, .tag = .signal }
    else if (std.mem.eql(u8, name, "npm_totalmem"))
        .{ .voids = all_void, .tag = .npm_totalmem }
    else if (std.mem.eql(u8, name, "npm_parallelism"))
        .{ .voids = all_void, .tag = .npm_parallelism }
    else if (std.mem.eql(u8, name, "npm_isabs") or std.mem.eql(u8, name, "npm_ns_isabs"))
        .{ .voids = all_void ^ 0b11, .tag = .npm_isabs }
    else if (std.mem.eql(u8, name, "npm_iseq") or std.mem.eql(u8, name, "npm_ns_iseq"))
        .{ .voids = all_void ^ 0b1111, .tag = .npm_iseq }
    else if (std.mem.eql(u8, name, "pthread_spawn"))
        .{ .voids = all_void ^ 0b11, .tag = .pthread_spawn }
    else if (std.mem.eql(u8, name, "pthread_join"))
        .{ .voids = all_void, .tag = .pthread_join }
    else if (std.mem.eql(u8, name, "pthread_drop"))
        .{ .voids = all_void, .tag = .pthread_drop }
    else if (std.mem.eql(u8, name, "dlopen"))
        .{ .voids = all_void, .tag = .dlopen }
    else if (std.mem.eql(u8, name, "dlsym"))
        .{ .voids = all_void, .tag = .dlsym }
    else if (std.mem.eql(u8, name, "dlclose"))
        .{ .voids = all_void, .tag = .dlclose }
    else if (std.mem.eql(u8, name, "sqlite3_prepare"))
        .{ .voids = all_void, .tag = .sqlite3_prepare }
    else if (std.mem.eql(u8, name, "sqlite3_step"))
        .{ .voids = all_void, .tag = .sqlite3_step }
    else if (std.mem.eql(u8, name, "sqlite3_finalize"))
        .{ .voids = all_void, .tag = .sqlite3_finalize }
    else if (std.mem.eql(u8, name, "sa_fmt_i64_into"))
        .{ .voids = all_void ^ 0b11111, .tag = .fmt_i64_into }
    else if (std.mem.eql(u8, name, "sa_fmt_u64_into"))
        .{ .voids = all_void ^ 0b11111, .tag = .fmt_u64_into }
    else if (std.mem.eql(u8, name, "sa_fmt_f64_into"))
        .{ .voids = all_void ^ 0b11111, .tag = .fmt_f64_into }
    else if (std.mem.eql(u8, name, "sa_fmt_bool_into"))
        .{ .voids = all_void ^ 0b1111, .tag = .fmt_bool_into }
    else if (std.mem.eql(u8, name, "sa_fmt_bytes_into"))
        .{ .voids = all_void ^ 0b11111, .tag = .fmt_bytes_into }
    else if (std.mem.eql(u8, name, "sa_fmt_i64"))
        .{ .voids = all_void ^ 0b11, .tag = .fmt_i64 }
    else if (std.mem.eql(u8, name, "sa_fmt_u64"))
        .{ .voids = all_void ^ 0b11, .tag = .fmt_u64 }
    else if (std.mem.eql(u8, name, "sa_fmt_f64"))
        .{ .voids = all_void ^ 0b11, .tag = .fmt_f64 }
    else if (std.mem.eql(u8, name, "sa_fmt_bool"))
        .{ .voids = all_void ^ 0b1, .tag = .fmt_bool }
    else if (std.mem.eql(u8, name, "sa_fmt_bytes"))
        .{ .voids = all_void ^ 0b11, .tag = .fmt_bytes }
    else if (std.mem.eql(u8, name, "sa_fmt_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .fmt_buffer_data }
    else if (std.mem.eql(u8, name, "sa_fmt_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .fmt_buffer_len }
    else if (std.mem.eql(u8, name, "sa_fmt_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .fmt_buffer_free }
    else if (std.mem.eql(u8, name, "sa_modstate_get_u64"))
        .{ .voids = all_void ^ 0b1, .tag = .modstate_get_u64 }
    else if (std.mem.eql(u8, name, "sa_modstate_set_u64"))
        .{ .voids = all_void ^ 0b11, .tag = .modstate_set_u64 }
    else if (std.mem.eql(u8, name, "sa_string_concat"))
        .{ .voids = all_void ^ 0b1111, .tag = .string_concat }
    else if (std.mem.eql(u8, name, "sa_string_index_of"))
        .{ .voids = all_void ^ 0b11111, .tag = .string_index_of }
    else if (std.mem.eql(u8, name, "sa_string_last_index_of"))
        .{ .voids = all_void ^ 0b11111, .tag = .string_last_index_of }
    else if (std.mem.eql(u8, name, "sa_string_starts_with"))
        .{ .voids = all_void ^ 0b1111, .tag = .string_starts_with }
    else if (std.mem.eql(u8, name, "sa_string_ends_with"))
        .{ .voids = all_void ^ 0b1111, .tag = .string_ends_with }
    else if (std.mem.eql(u8, name, "sa_string_to_lower_ascii"))
        .{ .voids = all_void ^ 0b11, .tag = .string_to_lower_ascii }
    else if (std.mem.eql(u8, name, "sa_string_to_upper_ascii"))
        .{ .voids = all_void ^ 0b11, .tag = .string_to_upper_ascii }
    else if (std.mem.eql(u8, name, "sa_string_repeat"))
        .{ .voids = all_void ^ 0b111, .tag = .string_repeat }
    else if (std.mem.eql(u8, name, "sa_string_pad_start"))
        .{ .voids = all_void ^ 0b11111, .tag = .string_pad_start }
    else if (std.mem.eql(u8, name, "sa_string_pad_end"))
        .{ .voids = all_void ^ 0b11111, .tag = .string_pad_end }
    else if (std.mem.eql(u8, name, "sa_string_from_char_code"))
        .{ .voids = all_void ^ 0b1, .tag = .string_from_char_code }
    else if (std.mem.eql(u8, name, "sa_string_from_code_point"))
        .{ .voids = all_void ^ 0b1, .tag = .string_from_code_point }
    else if (std.mem.eql(u8, name, "sa_string_code_point_at"))
        .{ .voids = all_void ^ 0b111, .tag = .string_code_point_at }
    else if (std.mem.eql(u8, name, "sa_string_replace"))
        .{ .voids = all_void ^ 0b1111111, .tag = .string_replace }
    else if (std.mem.eql(u8, name, "sa_parse_float"))
        .{ .voids = all_void ^ 0b11, .tag = .parse_float }
    else if (std.mem.eql(u8, name, "sa_regex_compile"))
        .{ .voids = all_void ^ 0b111, .tag = .regex_compile }
    else if (std.mem.eql(u8, name, "sa_regex_match"))
        .{ .voids = all_void ^ 0b111, .tag = .regex_match }
    else if (std.mem.eql(u8, name, "sa_regex_group_ptr"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_group_ptr }
    else if (std.mem.eql(u8, name, "sa_regex_group_len"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_group_len }
    else if (std.mem.eql(u8, name, "sa_regex_group_start"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_group_start }
    else if (std.mem.eql(u8, name, "sa_regex_group_count"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_group_count }
    else if (std.mem.eql(u8, name, "sa_regex_free"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_free }
    else if (std.mem.eql(u8, name, "sa_regex_match_free"))
        .{ .voids = all_void, .tag = .regex_match_free }
    else if (std.mem.eql(u8, name, "sa_http_client_new"))
        .{ .voids = all_void ^ 0b11, .tag = .http_client_new }
    else if (std.mem.eql(u8, name, "sa_http_client_req_new"))
        .{ .voids = all_void ^ 0b11101, .tag = .http_client_req_new }
    else if (std.mem.eql(u8, name, "sa_http_client_req_add_header"))
        .{ .voids = all_void ^ 0b11111, .tag = .http_client_req_add_header }
    else if (std.mem.eql(u8, name, "sa_http_client_req_set_body"))
        .{ .voids = all_void ^ 0b111, .tag = .http_client_req_set_body }
    else if (std.mem.eql(u8, name, "sa_http_client_req_send"))
        .{ .voids = all_void ^ 0b11, .tag = .http_client_req_send }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_status"))
        .{ .voids = all_void ^ 0b1, .tag = .http_client_resp_status }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_body_reader"))
        .{ .voids = all_void ^ 0b11, .tag = .http_client_resp_body_reader }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_read_chunk"))
        .{ .voids = all_void ^ 0b1111, .tag = .http_client_resp_read_chunk }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_client_resp_free }
    else if (std.mem.eql(u8, name, "sa_http_client_body_reader_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_client_body_reader_free }
    else if (std.mem.eql(u8, name, "sa_http_client_req_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_client_req_free }
    else if (std.mem.eql(u8, name, "sa_http_client_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_client_free }
    else if (std.mem.eql(u8, name, "sa_http_server_new"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_new }
    else if (std.mem.eql(u8, name, "sa_http_server_start"))
        .{ .voids = all_void ^ 0b111, .tag = .http_server_start }
    else if (std.mem.eql(u8, name, "sa_http_server_accept"))
        .{ .voids = all_void ^ 0b11, .tag = .http_server_accept }
    else if (std.mem.eql(u8, name, "sa_http_server_req_get_path"))
        .{ .voids = all_void ^ 0b111, .tag = .http_server_req_get_path }
    else if (std.mem.eql(u8, name, "sa_http_server_req_get_header"))
        .{ .voids = all_void ^ 0b11111, .tag = .http_server_req_get_header }
    else if (std.mem.eql(u8, name, "sa_http_server_req_get_body"))
        .{ .voids = all_void ^ 0b111, .tag = .http_server_req_get_body }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_new"))
        .{ .voids = all_void ^ 0b101, .tag = .http_server_resp_stream_new }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_write"))
        .{ .voids = all_void ^ 0b111, .tag = .http_server_resp_stream_write }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_flush"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_resp_stream_flush }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_end"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_resp_stream_end }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_resp_stream_free }
    else if (std.mem.eql(u8, name, "sa_http_server_req_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_req_free }
    else if (std.mem.eql(u8, name, "sa_http_server_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_free }
    else
        null;
    const binding = b orelse return false;
    // Uniform-arity signature (matches the fwd decl) + selective padding.
    try writer.writeAll("static sa_u64 ");
    try cFuncName(writer, raw_name);
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
        if (pi < 64 and (binding.voids >> @intCast(pi)) & 1 == 1) {
            try writer.print(" (void)a{d};", .{pi});
        }
    }
    if (gas) try writer.writeAll(" SA_GAS_CHECK(1);");
    switch (binding.tag) {
        .fd_open => {
            // Fake fd counter from 3 (mirrors JS next-fd); the path is
            // staged and unread, like the interpreter.
            try writer.writeAll(" { static sa_u64 next_fd = 3; return next_fd++; } }\n");
        },
        .fd_close => {
            try writer.writeAll(" return 0; }\n");
        },
        .fd_read => {
            try writer.writeAll(" return 3; }\n");
        },
        .mmap => {
            // Anonymous zero-filled mapping stands in for the host page
            // (a1 = len; a0 fd is staged). Negative lengths trap inside
            // sa_alloc via the OOM check.
            try writer.writeAll(" return sa_alloc(a1); }\n");
        },
        .munmap => {
            try writer.writeAll(" return 0; }\n");
        },
        .signal => {
            // Echo the signal number back (staged oracle semantics).
            try writer.writeAll(" return a0; }\n");
        },
        .npm_totalmem => {
            // Deterministic 8GiB stand-in (asserted only as > 0).
            try writer.writeAll(" return 8589934592ULL; }\n");
        },
        .npm_parallelism => {
            // Deterministic stand-in (asserted only as >= 1).
            try writer.writeAll(" return 4; }\n");
        },
        .npm_isabs => {
            // Byte-level absolute-path check on guest memory (a0 = ptr,
            // a1 = len); OOB traps via the checked address.
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a1 == 0) return 0;");
            try writer.writeAll(" return sa_mem[x] == (uint8_t)'/' ? 1 : 0; } }\n");
        },
        .npm_iseq => {
            // Byte-level deep-equal on guest memory (a0/a1, a2/a3);
            // OOB traps via the checked addresses.
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" if (a1 != a3) return 0;");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" if (sa_mem[x + i] != sa_mem[y + i]) return 0; }");
            try writer.writeAll(" return 1; } }\n");
        },
        .pthread_spawn => {
            // Run the entry synchronously via the dispatcher, then hand
            // out a joinable handle (single-threaded staged semantics,
            // mirrors JS). Trailing zeros pad to dispatcher arity.
            try writer.writeAll(" { sa_call_indirect(a0, a1");
            var zi: usize = 1;
            while (zi < uniform_arity) : (zi += 1) {
                try writer.writeAll(", 0");
            }
            try writer.writeAll(");");
            try writer.writeAll(" { static sa_u64 next_thr = 1; return next_thr++; } } }\n");
        },
        .pthread_join => {
            // Entry already ran inside spawn; nothing to wait for.
            try writer.writeAll(" return 0; }\n");
        },
        .pthread_drop => {
            try writer.writeAll(" return 0; }\n");
        },
        .dlopen => {
            // Real zeroed region stands in for the OS handle (mirrors
            // JS __sa_alloc(8)); nonzero is what the oracle checks.
            try writer.writeAll(" return sa_alloc(8); }\n");
        },
        .dlsym => {
            try writer.writeAll(" return sa_alloc(8); }\n");
        },
        .dlclose => {
            try writer.writeAll(" return 0; }\n");
        },
        .sqlite3_prepare => {
            try writer.writeAll(" return 0; }\n");
        },
        .sqlite3_step => {
            // SQLITE_ROW so the row-present branch is taken (mirrors JS).
            try writer.writeAll(" return 100; }\n");
        },
        .sqlite3_finalize => {
            try writer.writeAll(" return 0; }\n");
        },
        .fmt_i64_into => {
            // Signed decimal (or base 2/8/16/17) into the caller buffer;
            // out_len is always written, cap==0 short-circuits OK,
            // overflow reports truncated (mirrors writeFormattedInto).
            try writer.writeAll(" { char tmp[130];");
            try writer.writeAll(" int n = sa_fmt_int(tmp, a0, (unsigned)a1, 1, (a1 == 17));");
            try writer.writeAll(" if (n < 0) return 1;");
            try writer.writeAll(" sa_store_u64(a4, (sa_u64)n);");
            try writer.writeAll(" if (a3 == 0) return 0;");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" if ((sa_u64)n > a3) return 9;");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)n; i++)");
            try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; } } return 0; } }\n");
        },
        .fmt_u64_into => {
            try writer.writeAll(" { char tmp[130];");
            try writer.writeAll(" int n = sa_fmt_int(tmp, a0, (unsigned)a1, 0, (a1 == 17));");
            try writer.writeAll(" if (n < 0) return 1;");
            try writer.writeAll(" sa_store_u64(a4, (sa_u64)n);");
            try writer.writeAll(" if (a3 == 0) return 0;");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" if ((sa_u64)n > a3) return 9;");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)n; i++)");
            try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; } } return 0; } }\n");
        },
        .fmt_f64_into => {
            // Zig "{d:.precision}" == C "%.*f" for sane precisions;
            // NaN keeps Zig's "NaN" casing (printf says "nan").
            try writer.writeAll(" { if (a1 > 200) return 1;");
            try writer.writeAll(" union { sa_u64 u; double d; } t; t.u = a0;");
            try writer.writeAll(" char tmp[256];");
            try writer.writeAll(" if (t.d != t.d) {");
            try writer.writeAll(" sa_store_u64(a4, 3);");
            try writer.writeAll(" if (a3 == 0) return 0;");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" if (3 > a3) return 9;");
            try writer.writeAll(" sa_mem[d] = (uint8_t)'N'; sa_mem[d + 1] = (uint8_t)'a';");
            try writer.writeAll(" sa_mem[d + 2] = (uint8_t)'N'; } return 0; }");
            try writer.writeAll(" int n = snprintf(tmp, sizeof(tmp), \"%.*f\", (int)a1, t.d);");
            try writer.writeAll(" if (n < 0 || n >= 256) return 1;");
            try writer.writeAll(" sa_store_u64(a4, (sa_u64)n);");
            try writer.writeAll(" if (a3 == 0) return 0;");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" if ((sa_u64)n > a3) return 9;");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)n; i++)");
            try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; } } return 0; } }\n");
        },
        .fmt_bool_into => {
            try writer.writeAll(" { const char *s = a0 ? \"true\" : \"false\";");
            try writer.writeAll(" sa_u64 n = a0 ? 4 : 5;");
            try writer.writeAll(" sa_store_u64(a3, n);");
            try writer.writeAll(" if (a2 == 0) return 0;");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" if (n > a2) return 9;");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)n; i++)");
            try writer.writeAll(" sa_mem[d + i] = (uint8_t)s[i]; } } return 0; } }\n");
        },
        .fmt_bytes_into => {
            try writer.writeAll(" { uint32_t s = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" sa_store_u64(a4, a1);");
            try writer.writeAll(" if (a3 == 0) return 0;");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" if (a1 > a3) return 9;");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d + i] = sa_mem[s + i]; } } return 0; } }\n");
        },
        .fmt_i64 => {
            try writer.writeAll(" { char tmp[130];");
            try writer.writeAll(" int n = sa_fmt_int(tmp, a0, (unsigned)a1, 1, (a1 == 17));");
            try writer.writeAll(" if (n < 0) return 0;");
            try writer.writeAll(" sa_u64 p = sa_alloc((sa_u64)n);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, (sa_u64)n);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++)");
            try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; }");
            try writer.writeAll(" return sa_owned_new(p, (sa_u64)n, 1); } }\n");
        },
        .fmt_u64 => {
            try writer.writeAll(" { char tmp[130];");
            try writer.writeAll(" int n = sa_fmt_int(tmp, a0, (unsigned)a1, 0, (a1 == 17));");
            try writer.writeAll(" if (n < 0) return 0;");
            try writer.writeAll(" sa_u64 p = sa_alloc((sa_u64)n);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, (sa_u64)n);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++)");
            try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; }");
            try writer.writeAll(" return sa_owned_new(p, (sa_u64)n, 1); } }\n");
        },
        .fmt_f64 => {
            try writer.writeAll(" { if (a1 > 200) return 0;");
            try writer.writeAll(" union { sa_u64 u; double d; } t; t.u = a0;");
            try writer.writeAll(" char tmp[256];");
            try writer.writeAll(" int n = snprintf(tmp, sizeof(tmp), \"%.*f\", (int)a1, t.d);");
            try writer.writeAll(" if (n < 0 || n >= 256) return 0;");
            try writer.writeAll(" sa_u64 p = sa_alloc((sa_u64)n);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, (sa_u64)n);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++)");
            try writer.writeAll(" sa_mem[d + i] = (uint8_t)tmp[i]; }");
            try writer.writeAll(" return sa_owned_new(p, (sa_u64)n, 1); } }\n");
        },
        .fmt_bool => {
            try writer.writeAll(" { const char *s = a0 ? \"true\" : \"false\";");
            try writer.writeAll(" sa_u64 n = a0 ? 4 : 5;");
            try writer.writeAll(" sa_u64 p = sa_alloc(n);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, n);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++)");
            try writer.writeAll(" sa_mem[d + i] = (uint8_t)s[i]; }");
            try writer.writeAll(" return sa_owned_new(p, n, 1); } }\n");
        },
        .fmt_bytes => {
            try writer.writeAll(" { uint32_t s = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d + i] = sa_mem[s + i]; }");
            try writer.writeAll(" return sa_owned_new(p, a1, 1); } }\n");
        },
        .fmt_buffer_data => {
            try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 1) return 0;");
            try writer.writeAll(" return o->ptr; } }\n");
        },
        .fmt_buffer_len => {
            try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 1) return 0;");
            try writer.writeAll(" return o->len; } }\n");
        },
        .fmt_buffer_free => {
            try writer.writeAll(" { sa_owned_drop(a0); return 0; } }\n");
        },
        .modstate_get_u64 => {
            try writer.writeAll(" { sa_u64 i; for (i = 0; i < SA_MODSTATE_MAX; i++)");
            try writer.writeAll(" if (sa_modstate_used[i] && sa_modstate_keys[i] == a0)");
            try writer.writeAll(" return sa_modstate_vals[i]; return 0; } }\n");
        },
        .modstate_set_u64 => {
            try writer.writeAll(" { sa_u64 i; for (i = 0; i < SA_MODSTATE_MAX; i++)");
            try writer.writeAll(" if (sa_modstate_used[i] && sa_modstate_keys[i] == a0)");
            try writer.writeAll(" { sa_modstate_vals[i] = a1; return 0; }");
            try writer.writeAll(" for (i = 0; i < SA_MODSTATE_MAX; i++)");
            try writer.writeAll(" if (!sa_modstate_used[i])");
            try writer.writeAll(" { sa_modstate_used[i] = 1; sa_modstate_keys[i] = a0;");
            try writer.writeAll(" sa_modstate_vals[i] = a1; return 0; } return 5; } }\n");
        },
        .string_concat => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" sa_u64 n = a1 + a3;");
            try writer.writeAll(" sa_u64 p = sa_alloc(n);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, n);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
            try writer.writeAll(" for (i = 0; i < (size_t)a3; i++)");
            try writer.writeAll(" sa_mem[d + (size_t)a1 + i] = sa_mem[y + i]; }");
            try writer.writeAll(" return sa_owned_new(p, n, 1); } }\n");
        },
        .string_index_of => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" sa_u64 st = a4 < a1 ? a4 : a1;");
            try writer.writeAll(" if (a3 == 0) return st;");
            try writer.writeAll(" if (a3 > a1) return ~(sa_u64)0;");
            try writer.writeAll(" { sa_u64 i, j; for (i = st; i + a3 <= a1; i++) {");
            try writer.writeAll(" int eq = 1;");
            try writer.writeAll(" for (j = 0; j < a3; j++)");
            try writer.writeAll(" if (sa_mem[x + i + j] != sa_mem[y + j]) { eq = 0; break; }");
            try writer.writeAll(" if (eq) return i; } } return ~(sa_u64)0; } }\n");
        },
        .string_last_index_of => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" sa_u64 st = a4 < a1 ? a4 : a1;");
            try writer.writeAll(" if (a3 == 0) return st;");
            try writer.writeAll(" if (a3 > a1) return ~(sa_u64)0;");
            try writer.writeAll(" { sa_u64 i = st < a1 - a3 ? st : a1 - a3; sa_u64 j;");
            try writer.writeAll(" for (;;) { int eq = 1;");
            try writer.writeAll(" for (j = 0; j < a3; j++)");
            try writer.writeAll(" if (sa_mem[x + i + j] != sa_mem[y + j]) { eq = 0; break; }");
            try writer.writeAll(" if (eq) return i; if (i == 0) break; i--; } }");
            try writer.writeAll(" return ~(sa_u64)0; } }\n");
        },
        .string_starts_with => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" if (a3 > a1) return 0;");
            try writer.writeAll(" { sa_u64 j; for (j = 0; j < a3; j++)");
            try writer.writeAll(" if (sa_mem[x + j] != sa_mem[y + j]) return 0; }");
            try writer.writeAll(" return 1; } }\n");
        },
        .string_ends_with => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" if (a3 > a1) return 0;");
            try writer.writeAll(" { sa_u64 j; for (j = 0; j < a3; j++)");
            try writer.writeAll(" if (sa_mem[x + a1 - a3 + j] != sa_mem[y + j]) return 0; }");
            try writer.writeAll(" return 1; } }\n");
        },
        .string_to_lower_ascii => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++) {");
            try writer.writeAll(" uint8_t c = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[d + i] = (uint8_t)(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c); } }");
            try writer.writeAll(" return sa_owned_new(p, a1, 1); } }\n");
        },
        .string_to_upper_ascii => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++) {");
            try writer.writeAll(" uint8_t c = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[d + i] = (uint8_t)(c >= 'a' && c <= 'z' ? c - ('a' - 'A') : c); } }");
            try writer.writeAll(" return sa_owned_new(p, a1, 1); } }\n");
        },
        .string_repeat => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a2 == 0 || a1 == 0) {");
            try writer.writeAll(" sa_u64 p0 = sa_alloc(0);");
            try writer.writeAll(" return sa_owned_new(p0, 0, 1); }");
            try writer.writeAll(" if (a1 > ~(sa_u64)0 / a2) return 0;");
            try writer.writeAll(" { sa_u64 n = a1 * a2; sa_u64 p = sa_alloc(n);");
            try writer.writeAll(" uint32_t d = sa_checked_addr(p, n);");
            try writer.writeAll(" sa_u64 i, j; for (i = 0; i < a2; i++)");
            try writer.writeAll(" for (j = 0; j < a1; j++)");
            try writer.writeAll(" sa_mem[d + i * a1 + j] = sa_mem[x + j];");
            try writer.writeAll(" return sa_owned_new(p, n, 1); } } }\n");
        },
        .string_pad_start => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t v = sa_checked_addr(a3, (size_t)a4);");
            try writer.writeAll(" if (a2 <= a1 || a4 == 0) {");
            try writer.writeAll(" sa_u64 p0 = sa_alloc(a1);");
            try writer.writeAll(" { uint32_t d0 = sa_checked_addr(p0, a1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d0 + i] = sa_mem[x + i]; }");
            try writer.writeAll(" return sa_owned_new(p0, a1, 1); }");
            try writer.writeAll(" { sa_u64 fill = a2 - a1; sa_u64 p = sa_alloc(a2);");
            try writer.writeAll(" uint32_t d = sa_checked_addr(p, a2);");
            try writer.writeAll(" sa_u64 i, j; for (i = 0; i < fill; i++)");
            try writer.writeAll(" sa_mem[d + i] = sa_mem[v + i % a4];");
            try writer.writeAll(" for (j = 0; j < a1; j++)");
            try writer.writeAll(" sa_mem[d + fill + j] = sa_mem[x + j];");
            try writer.writeAll(" return sa_owned_new(p, a2, 1); } } }\n");
        },
        .string_pad_end => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t v = sa_checked_addr(a3, (size_t)a4);");
            try writer.writeAll(" if (a2 <= a1 || a4 == 0) {");
            try writer.writeAll(" sa_u64 p0 = sa_alloc(a1);");
            try writer.writeAll(" { uint32_t d0 = sa_checked_addr(p0, a1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d0 + i] = sa_mem[x + i]; }");
            try writer.writeAll(" return sa_owned_new(p0, a1, 1); }");
            try writer.writeAll(" { sa_u64 p = sa_alloc(a2);");
            try writer.writeAll(" uint32_t d = sa_checked_addr(p, a2);");
            try writer.writeAll(" sa_u64 j; for (j = 0; j < a1; j++)");
            try writer.writeAll(" sa_mem[d + j] = sa_mem[x + j];");
            try writer.writeAll(" for (; j < a2; j++)");
            try writer.writeAll(" sa_mem[d + j] = sa_mem[v + (j - a1) % a4];");
            try writer.writeAll(" return sa_owned_new(p, a2, 1); } } }\n");
        },
        .string_from_char_code => {
            try writer.writeAll(" { sa_u64 p = sa_alloc(1);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, 1);");
            try writer.writeAll(" sa_mem[d] = (uint8_t)(a0 & 0xFFu); }");
            try writer.writeAll(" return sa_owned_new(p, 1, 1); } }\n");
        },
        .string_from_code_point => {
            // UTF-8 encode with U+FFFD fallback for negative, >0x10FFFF
            // and surrogate halves (mirrors the interpreter exactly).
            try writer.writeAll(" { sa_i64 c = (sa_i64)(int32_t)(uint32_t)a0;");
            try writer.writeAll(" uint32_t cp = c < 0 ? 0xFFFDu : (uint32_t)c;");
            try writer.writeAll(" if (cp > 0x10FFFFu || (cp >= 0xD800u && cp <= 0xDFFFu)) cp = 0xFFFDu;");
            try writer.writeAll(" uint8_t t[4]; sa_u64 n;");
            try writer.writeAll(" if (cp < 0x80) { t[0] = (uint8_t)cp; n = 1; }");
            try writer.writeAll(" else if (cp < 0x800) {");
            try writer.writeAll(" t[0] = (uint8_t)(0xC0 | (cp >> 6));");
            try writer.writeAll(" t[1] = (uint8_t)(0x80 | (cp & 0x3F)); n = 2; }");
            try writer.writeAll(" else if (cp < 0x10000) {");
            try writer.writeAll(" t[0] = (uint8_t)(0xE0 | (cp >> 12));");
            try writer.writeAll(" t[1] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));");
            try writer.writeAll(" t[2] = (uint8_t)(0x80 | (cp & 0x3F)); n = 3; }");
            try writer.writeAll(" else {");
            try writer.writeAll(" t[0] = (uint8_t)(0xF0 | (cp >> 18));");
            try writer.writeAll(" t[1] = (uint8_t)(0x80 | ((cp >> 12) & 0x3F));");
            try writer.writeAll(" t[2] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F));");
            try writer.writeAll(" t[3] = (uint8_t)(0x80 | (cp & 0x3F)); n = 4; }");
            try writer.writeAll(" { sa_u64 p = sa_alloc(n);");
            try writer.writeAll(" uint32_t d = sa_checked_addr(p, n);");
            try writer.writeAll(" sa_u64 i; for (i = 0; i < n; i++) sa_mem[d + i] = t[i];");
            try writer.writeAll(" return sa_owned_new(p, n, 1); } } }\n");
        },
        .string_code_point_at => {
            // Byte at idx despite the name (mirrors the interpreter).
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a2 >= a1) return ~(sa_u64)0;");
            try writer.writeAll(" return (sa_u64)sa_mem[x + a2]; } }\n");
        },
        .string_replace => {
            // First or all non-overlapping matches swapped; empty needle
            // prepends (once) or interleaves (all); misses copy input.
            // Overflow bails to 0 (mirrors checked arithmetic). Flat
            // structure: each path returns inside its own block.
            try writer.writeAll(" uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" uint32_t z = sa_checked_addr(a4, (size_t)a5);");
            try writer.writeAll(" if (a3 == 0) {");
            try writer.writeAll(" if (!a6) {");
            try writer.writeAll(" sa_u64 n0 = a5 + a1; if (n0 < a5) return 0;");
            try writer.writeAll(" sa_u64 p0 = sa_alloc(n0);");
            try writer.writeAll(" { uint32_t d0 = sa_checked_addr(p0, n0);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a5; i++)");
            try writer.writeAll(" sa_mem[d0 + i] = sa_mem[z + i];");
            try writer.writeAll(" for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d0 + (size_t)a5 + i] = sa_mem[x + i]; }");
            try writer.writeAll(" return sa_owned_new(p0, n0, 1); }");
            try writer.writeAll(" if (a5 != 0 && a1 + 1 > ~(sa_u64)0 / a5) return 0;");
            try writer.writeAll(" { sa_u64 n1 = a1 + a5 * (a1 + 1);");
            try writer.writeAll(" if (n1 < a1) return 0;");
            try writer.writeAll(" sa_u64 p1 = sa_alloc(n1);");
            try writer.writeAll(" uint32_t d1 = sa_checked_addr(p1, n1);");
            try writer.writeAll(" sa_u64 o = 0; sa_u64 i;");
            try writer.writeAll(" for (i = 0; i < a1; i++) {");
            try writer.writeAll(" sa_u64 j; for (j = 0; j < a5; j++)");
            try writer.writeAll(" sa_mem[d1 + o + j] = sa_mem[z + j];");
            try writer.writeAll(" o += a5; sa_mem[d1 + o] = sa_mem[x + i]; o += 1; }");
            try writer.writeAll(" { sa_u64 j; for (j = 0; j < a5; j++)");
            try writer.writeAll(" sa_mem[d1 + o + j] = sa_mem[z + j]; }");
            try writer.writeAll(" return sa_owned_new(p1, n1, 1); } }");
            try writer.writeAll(" { sa_u64 cnt = 0; sa_u64 i = 0; sa_u64 first = 0;");
            try writer.writeAll(" while (i + a3 <= a1) { sa_u64 j; int eq = 1;");
            try writer.writeAll(" for (j = 0; j < a3; j++)");
            try writer.writeAll(" if (sa_mem[x + i + j] != sa_mem[y + j]) { eq = 0; break; }");
            try writer.writeAll(" if (eq) { if (cnt == 0) first = i; cnt++;");
            try writer.writeAll(" if (!a6) break; i += a3; continue; } i++; }");
            try writer.writeAll(" if (cnt == 0) {");
            try writer.writeAll(" sa_u64 p2 = sa_alloc(a1);");
            try writer.writeAll(" { uint32_t d2 = sa_checked_addr(p2, a1);");
            try writer.writeAll(" size_t k; for (k = 0; k < (size_t)a1; k++)");
            try writer.writeAll(" sa_mem[d2 + k] = sa_mem[x + k]; }");
            try writer.writeAll(" return sa_owned_new(p2, a1, 1); }");
            try writer.writeAll(" if (!a6) {");
            try writer.writeAll(" if (a1 - a3 > ~(sa_u64)0 - a5) return 0;");
            try writer.writeAll(" sa_u64 n3 = a1 - a3 + a5;");
            try writer.writeAll(" sa_u64 p3 = sa_alloc(n3);");
            try writer.writeAll(" uint32_t d3 = sa_checked_addr(p3, n3);");
            try writer.writeAll(" { size_t k; for (k = 0; k < (size_t)first; k++)");
            try writer.writeAll(" sa_mem[d3 + k] = sa_mem[x + k]; }");
            try writer.writeAll(" { size_t k; for (k = 0; k < (size_t)a5; k++)");
            try writer.writeAll(" sa_mem[d3 + (size_t)first + k] = sa_mem[z + k]; }");
            try writer.writeAll(" { size_t k; for (k = 0; k + first + a3 < a1 + 1; k++)");
            try writer.writeAll(" sa_mem[d3 + (size_t)first + (size_t)a5 + k] = sa_mem[x + first + a3 + k]; }");
            try writer.writeAll(" return sa_owned_new(p3, n3, 1); }");
            try writer.writeAll(" { sa_u64 total = a1; sa_u64 ii = 0;");
            try writer.writeAll(" while (ii + a3 <= a1) { sa_u64 jj; int eq2 = 1;");
            try writer.writeAll(" for (jj = 0; jj < a3; jj++)");
            try writer.writeAll(" if (sa_mem[x + ii + jj] != sa_mem[y + jj]) { eq2 = 0; break; }");
            try writer.writeAll(" if (eq2) {");
            try writer.writeAll(" if (total < a3 || total - a3 > ~(sa_u64)0 - a5) return 0;");
            try writer.writeAll(" total = total - a3 + a5; ii += a3; } else ii++; }");
            try writer.writeAll(" sa_u64 p4 = sa_alloc(total);");
            try writer.writeAll(" uint32_t d4 = sa_checked_addr(p4, total);");
            try writer.writeAll(" sa_u64 o4 = 0; ii = 0;");
            try writer.writeAll(" while (ii + a3 <= a1) { sa_u64 jj; int eq3 = 1;");
            try writer.writeAll(" for (jj = 0; jj < a3; jj++)");
            try writer.writeAll(" if (sa_mem[x + ii + jj] != sa_mem[y + jj]) { eq3 = 0; break; }");
            try writer.writeAll(" if (eq3) { sa_u64 jj;");
            try writer.writeAll(" for (jj = 0; jj < a5; jj++)");
            try writer.writeAll(" sa_mem[d4 + o4 + jj] = sa_mem[z + jj];");
            try writer.writeAll(" o4 += a5; ii += a3; } else {");
            try writer.writeAll(" sa_mem[d4 + o4] = sa_mem[x + ii]; o4 += 1; ii++; } }");
            try writer.writeAll(" while (o4 < total) {");
            try writer.writeAll(" sa_mem[d4 + o4] = sa_mem[x + ii]; o4 += 1; ii++; }");
            try writer.writeAll(" return sa_owned_new(p4, total, 1); } } }\n");
        },
        .parse_float => {
            // Manual scan (whitespace/sign/digits/dot/exponent) then
            // strtod on the scanned span; no digits -> quiet NaN,
            // overflow -> signed inf (mirrors the interpreter).
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" size_t i = 0; int neg = 0;");
            try writer.writeAll(" while (i < (size_t)a1) { uint8_t c = sa_mem[x + i];");
            try writer.writeAll(" if (c != ' ' && c != '\\t' && c != '\\n' && c != '\\r' && c != '\\f' && c != '\\v') break; i++; }");
            try writer.writeAll(" if (i < (size_t)a1 && (sa_mem[x + i] == '+' || sa_mem[x + i] == '-'))");
            try writer.writeAll(" { neg = sa_mem[x + i] == '-'; i++; }");
            try writer.writeAll(" { size_t j = i; while (j < (size_t)a1 && sa_mem[x + j] >= '0' && sa_mem[x + j] <= '9') j++;");
            try writer.writeAll(" size_t nd = j - i;");
            try writer.writeAll(" if (j < (size_t)a1 && sa_mem[x + j] == '.') { j++;");
            try writer.writeAll(" while (j < (size_t)a1 && sa_mem[x + j] >= '0' && sa_mem[x + j] <= '9') j++; }");
            try writer.writeAll(" size_t nf = j - nd - (j > nd && sa_mem[x + i + nd] == '.' ? 1 : 0);");
            try writer.writeAll(" if (nd == 0 && nf == 0)");
            try writer.writeAll(" return (sa_u64)0x7FF8000000000000ULL;");
            try writer.writeAll(" size_t k = j;");
            try writer.writeAll(" if (k < (size_t)a1 && (sa_mem[x + k] == 'e' || sa_mem[x + k] == 'E')) {");
            try writer.writeAll(" size_t m = k + 1;");
            try writer.writeAll(" if (m < (size_t)a1 && (sa_mem[x + m] == '+' || sa_mem[x + m] == '-')) m++;");
            try writer.writeAll(" size_t es = m;");
            try writer.writeAll(" while (m < (size_t)a1 && sa_mem[x + m] >= '0' && sa_mem[x + m] <= '9') m++;");
            try writer.writeAll(" if (m > es) k = m; }");
            try writer.writeAll(" { sa_u64 n = (sa_u64)(k - i); sa_u64 p = sa_alloc(n + 1);");
            try writer.writeAll(" uint32_t d = sa_checked_addr(p, n + 1);");
            try writer.writeAll(" size_t q; for (q = 0; q < (size_t)n; q++)");
            try writer.writeAll(" sa_mem[d + q] = sa_mem[x + i + q];");
            try writer.writeAll(" sa_mem[d + n] = 0; errno = 0;");
            try writer.writeAll(" union { sa_u64 u; double v; } t; t.v = strtod((const char *)&sa_mem[d], 0);");
            try writer.writeAll(" if (errno == ERANGE) {");
            try writer.writeAll(" if ((t.u & (sa_u64)0x7FF0000000000000ULL) == (sa_u64)0x7FF0000000000000ULL)");
            try writer.writeAll(" t.u = neg ? (sa_u64)0xFFF0000000000000ULL : (sa_u64)0x7FF0000000000000ULL; }");
            try writer.writeAll(" if (neg) t.v = -t.v; return t.u; } } } }\n");
        },
        .regex_compile => {
            // POSIX regcomp over a NUL-terminated guest copy; the
            // compiled form lives in a C-side table (host pointers).
            // Bad patterns yield 0, mirroring the interpreter.
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
            try writer.writeAll(" uint32_t d = sa_checked_addr(p, a1 + 1);");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i]; }");
            try writer.writeAll(" sa_mem[d + a1] = 0;");
            try writer.writeAll(" { unsigned k; sa_regex_t *o = 0;");
            try writer.writeAll(" for (k = 0; k < SA_REGEX_MAX_OBJS; k++)");
            try writer.writeAll(" if (sa_regexes[k].h == 0) { o = &sa_regexes[k]; break; }");
            try writer.writeAll(" if (o == 0) return 0;");
            try writer.writeAll(" if (regcomp(&o->rx, (const char *)&sa_mem[d], (int)a2) != 0) return 0;");
            try writer.writeAll(" sa_u64 h = sa_alloc(8); o->h = h; return h; } } }\n");
        },
        .regex_match => {
            // Match header lives in guest memory: [text_base][magic|n]
            // then n (start,end) pairs. Embedded NUL or no-match yields
            // 0, mirroring the interpreter.
            try writer.writeAll(" { sa_regex_t *r = sa_regex_find(a0);");
            try writer.writeAll(" if (r == 0) return 0;");
            try writer.writeAll(" uint32_t x = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" if (sa_mem[x + i] == 0) return 0; }");
            try writer.writeAll(" sa_u64 n = (sa_u64)r->rx.re_nsub + 1;");
            try writer.writeAll(" if (n > SA_REGEX_MAX_GROUPS) n = SA_REGEX_MAX_GROUPS;");
            try writer.writeAll(" sa_u64 tp = sa_alloc(a2 + 1);");
            try writer.writeAll(" { uint32_t td = sa_checked_addr(tp, a2 + 1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" sa_mem[td + i] = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[td + a2] = 0; }");
            try writer.writeAll(" regmatch_t pm[SA_REGEX_MAX_GROUPS];");
            try writer.writeAll(" if (regexec(&r->rx, (const char *)&sa_mem[sa_checked_addr(tp, a2 + 1)], (size_t)n, pm, 0) != 0) return 0;");
            try writer.writeAll(" { sa_u64 h = sa_alloc(16 + n * 16);");
            try writer.writeAll(" sa_store_u64(h, tp);");
            try writer.writeAll(" sa_store_u64(h + 8, (sa_u64)0x53414D5800000000ULL | n);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++) {");
            try writer.writeAll(" sa_store_u64(h + 16 + i * 16, (sa_u64)(sa_i64)pm[i].rm_so);");
            try writer.writeAll(" sa_store_u64(h + 16 + i * 16 + 8, (sa_u64)(sa_i64)pm[i].rm_eo); }");
            try writer.writeAll(" return h; } } }\n");
        },
        .regex_group_ptr => {
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
            try writer.writeAll(" (void)hh;");
            try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
            try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53414D58u) return 0;");
            try writer.writeAll(" sa_u64 n = hdr1 & (sa_u64)0xFFFFFFFFu;");
            try writer.writeAll(" if (a1 >= n) return 0;");
            try writer.writeAll(" sa_u64 so = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16);");
            try writer.writeAll(" sa_u64 eo = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16 + 8);");
            try writer.writeAll(" if ((sa_i64)so < 0 || (sa_i64)eo < 0) return 0;");
            try writer.writeAll(" return sa_load_u64(a0) + so; } }\n");
        },
        .regex_group_len => {
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
            try writer.writeAll(" (void)hh;");
            try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
            try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53414D58u) return 0;");
            try writer.writeAll(" sa_u64 n = hdr1 & (sa_u64)0xFFFFFFFFu;");
            try writer.writeAll(" if (a1 >= n) return 0;");
            try writer.writeAll(" sa_u64 so = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16);");
            try writer.writeAll(" sa_u64 eo = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16 + 8);");
            try writer.writeAll(" if ((sa_i64)so < 0 || (sa_i64)eo < 0) return 0;");
            try writer.writeAll(" return eo - so; } }\n");
        },
        .regex_group_start => {
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
            try writer.writeAll(" (void)hh;");
            try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
            try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53414D58u) return 0;");
            try writer.writeAll(" sa_u64 n = hdr1 & (sa_u64)0xFFFFFFFFu;");
            try writer.writeAll(" if (a1 >= n) return 0;");
            try writer.writeAll(" sa_u64 so = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16);");
            try writer.writeAll(" sa_u64 eo = (sa_u64)(sa_i64)sa_load_u64(a0 + 16 + a1 * 16 + 8);");
            try writer.writeAll(" if ((sa_i64)so < 0 || (sa_i64)eo < 0) return 0;");
            try writer.writeAll(" return so; } }\n");
        },
        .regex_group_count => {
            try writer.writeAll(" { sa_regex_t *r = sa_regex_find(a0);");
            try writer.writeAll(" if (r == 0) return 0;");
            try writer.writeAll(" return (sa_u64)r->rx.re_nsub + 1; } }\n");
        },
        .regex_free => {
            try writer.writeAll(" { sa_regex_t *r = sa_regex_find(a0);");
            try writer.writeAll(" if (r == 0) return 0;");
            try writer.writeAll(" regfree(&r->rx); r->h = 0; return 0; } }\n");
        },
        .regex_match_free => {
            // Guest-side match regions live in the bump arena (no free);
            // dropping is a no-op that still validates nothing and
            // returns OK, matching observable behavior.
            try writer.writeAll(" return 0; }\n");
        },
        .http_client_new => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8);");
            try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
            try writer.writeAll(" if (s == 0) return 1;");
            try writer.writeAll(" s->h = h; s->aux0 = a0;");
            try writer.writeAll(" sa_store_u64(a1, h); return 0; } }\n");
        },
        .http_client_req_new => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
            try writer.writeAll(" { uint32_t u = sa_checked_addr(a2, (size_t)a3); (void)u; }");
            try writer.writeAll(" sa_u64 h = sa_alloc(8);");
            try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
            try writer.writeAll(" if (s == 0) return 1;");
            try writer.writeAll(" s->h = h; s->aux0 = 0; s->aux1 = 0;");
            try writer.writeAll(" sa_store_u64(a4, h); return 0; } }\n");
        },
        .http_client_req_add_header => {
            try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0);");
            try writer.writeAll(" if (r == 0) return 1;");
            try writer.writeAll(" { uint32_t k = sa_checked_addr(a1, (size_t)a2); (void)k; }");
            try writer.writeAll(" { uint32_t v = sa_checked_addr(a3, (size_t)a4); (void)v; }");
            try writer.writeAll(" return 0; } }\n");
        },
        .http_client_req_set_body => {
            try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0);");
            try writer.writeAll(" if (r == 0) return 1;");
            try writer.writeAll(" { uint32_t b = sa_checked_addr(a1, (size_t)a2); (void)b; }");
            try writer.writeAll(" r->aux0 = a1; r->aux1 = a2; return 0; } }\n");
        },
        .http_client_req_send => {
            // Echo the recorded body with status 200 (mirrors JS).
            try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0);");
            try writer.writeAll(" if (r == 0) return 1;");
            try writer.writeAll(" sa_u64 h = sa_alloc(8);");
            try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
            try writer.writeAll(" if (s == 0) return 1;");
            try writer.writeAll(" s->h = h; s->aux0 = r->aux0; s->aux1 = r->aux1;");
            try writer.writeAll(" sa_store_u64(a1, h); return 0; } }\n");
        },
        .http_client_resp_status => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 0;");
            try writer.writeAll(" return 200; } }\n");
        },
        .http_client_resp_body_reader => {
            try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0);");
            try writer.writeAll(" if (r == 0) return 1;");
            try writer.writeAll(" sa_u64 h = sa_alloc(8);");
            try writer.writeAll(" sa_http_obj_t *d = sa_http_slot(sa_http_objs);");
            try writer.writeAll(" if (d == 0) return 1;");
            try writer.writeAll(" d->h = h; d->aux0 = r->aux0; d->aux1 = r->aux1; d->aux2 = 0;");
            try writer.writeAll(" sa_store_u64(a1, h); return 0; } }\n");
        },
        .http_client_resp_read_chunk => {
            try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0);");
            try writer.writeAll(" if (r == 0) return 1;");
            try writer.writeAll(" sa_u64 rem = r->aux1 - r->aux2;");
            try writer.writeAll(" sa_u64 n = a2 < rem ? a2 : rem;");
            try writer.writeAll(" { uint32_t b = sa_checked_addr(a1, (size_t)n);");
            try writer.writeAll(" uint32_t s = sa_checked_addr(r->aux0, (size_t)r->aux1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)n; i++)");
            try writer.writeAll(" sa_mem[b + i] = sa_mem[s + r->aux2 + i]; }");
            try writer.writeAll(" r->aux2 += n; sa_store_u64(a3, n); return 0; } }\n");
        },
        .http_client_resp_free => {
            try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
        .http_client_body_reader_free => {
            try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
        .http_client_req_free => {
            try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
        .http_client_free => {
            try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
        .http_server_new => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8);");
            try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
            try writer.writeAll(" if (s == 0) return 1;");
            try writer.writeAll(" s->h = h; sa_store_u64(a0, h); return 0; } }\n");
        },
        .http_server_start => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a1, (size_t)a2); (void)hh; }");
            try writer.writeAll(" return 0; } }\n");
        },
        .http_server_accept => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
            try writer.writeAll(" sa_u64 h = sa_alloc(8);");
            try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
            try writer.writeAll(" if (s == 0) return 1;");
            try writer.writeAll(" s->h = h; sa_store_u64(a1, h); return 0; } }\n");
        },
        .http_server_req_get_path => {
            // Canned "/stream" served from fresh guest memory (mirrors JS).
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
            try writer.writeAll(" static const uint8_t lit[] = {47, 115, 116, 114, 101, 97, 109};");
            try writer.writeAll(" sa_u64 p = sa_alloc(7);");
            try writer.writeAll(" { size_t i; for (i = 0; i < 7; i++)");
            try writer.writeAll(" sa_mem[sa_checked_addr(p, 7) + i] = lit[i]; }");
            try writer.writeAll(" sa_store_u64(a1, p); sa_store_u64(a2, 7); return 0; } }\n");
        },
        .http_server_req_get_header => {
            // Canned "text/plain" served from fresh guest memory.
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
            try writer.writeAll(" { uint32_t k = sa_checked_addr(a1, (size_t)a2); (void)k; }");
            try writer.writeAll(" static const uint8_t lit[] = {116, 101, 120, 116, 47, 112, 108, 97, 105, 110};");
            try writer.writeAll(" sa_u64 p = sa_alloc(10);");
            try writer.writeAll(" { size_t i; for (i = 0; i < 10; i++)");
            try writer.writeAll(" sa_mem[sa_checked_addr(p, 10) + i] = lit[i]; }");
            try writer.writeAll(" sa_store_u64(a3, p); sa_store_u64(a4, 10); return 0; } }\n");
        },
        .http_server_req_get_body => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
            try writer.writeAll(" sa_store_u64(a1, 0); sa_store_u64(a2, 0); return 0; } }\n");
        },
        .http_server_resp_stream_new => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
            try writer.writeAll(" sa_u64 h = sa_alloc(8);");
            try writer.writeAll(" sa_http_obj_t *s = sa_http_slot(sa_http_objs);");
            try writer.writeAll(" if (s == 0) return 1;");
            try writer.writeAll(" s->h = h; sa_store_u64(a2, h); return 0; } }\n");
        },
        .http_server_resp_stream_write => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
            try writer.writeAll(" { uint32_t b = sa_checked_addr(a1, (size_t)a2); (void)b; }");
            try writer.writeAll(" return 0; } }\n");
        },
        .http_server_resp_stream_flush => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .http_server_resp_stream_end => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .http_server_resp_stream_free => {
            try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
        .http_server_req_free => {
            try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
        .http_server_free => {
            try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
    }
    return true;
}

fn writePreamble(
    writer: anytype,
    c_opt: CEmitOptions,
    size_bits: u16,
    used: *const std.StringHashMap(void),
    need_mem: bool,
    need_brk: bool,
    need_http: bool,
    need_owned: bool,
    need_modstate: bool,
    need_regex: bool,
) !void {
    const mem_bytes: usize = @as(usize, c_opt.mem_pages) * 65536;
    try writer.print("/* Generated by `sa build-c` (c backend, MVP). DO NOT EDIT. */\n", .{});
    try writer.print("/* size_bits={d} mem_bytes={d} */\n", .{ size_bits, mem_bytes });
    try writer.writeAll(
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <stdlib.h>
        \\#include <errno.h>
        \\typedef uint64_t sa_u64;
        \\typedef int64_t sa_i64;
        \\typedef uint32_t sa_u32;
        \\typedef int32_t sa_i32;
        \\#ifndef SA_MEM_BYTES
        \\#define SA_MEM_BYTES 16777216UL
        \\#endif
        \\
    );
    if (need_mem) {
        try writer.writeAll("static uint8_t sa_mem[SA_MEM_BYTES];\n");
    }
    if (need_brk) {
        try writer.writeAll("static uint32_t sa_brk = 65536;\n");
    }
    try writer.writeAll(
        \\static __attribute__((noreturn, unused)) void sa_trap(const char *msg) { fputs("[sa-trap] ", stderr); fputs(msg, stderr); fputc('\n', stderr); exit(1); }
        \\
    );
    if (c_opt.gas) {
        try writer.writeAll(
            \\#ifndef SA_GAS_LIMIT
            \\#define SA_GAS_LIMIT 10000ULL
            \\#endif
            \\static sa_u64 sa_gas = SA_GAS_LIMIT;
            \\#define SA_GAS_CHECK(n) do { if (sa_gas < (sa_u64)(n)) sa_trap("out of gas"); sa_gas -= (sa_u64)(n); } while (0)
            \\
        );
    }
    // Staged http state: one bounded fixed table shared by all families
    // (handles are unique alloc offsets, so no cross-talk; no malloc).
    // Emitted only when an sa_http_* binding is rendered; every such
    // binding references the table via find/slot/drop, so it is never
    // unused. The helpers live in the runtime catalog (reference-gated).
    if (need_http) {
        try writer.writeAll(
            \\#ifndef SA_HTTP_MAX_OBJS
            \\#define SA_HTTP_MAX_OBJS 16
            \\#endif
            \\typedef struct { sa_u64 h, aux0, aux1, aux2; } sa_http_obj_t;
            \\static sa_http_obj_t sa_http_objs[SA_HTTP_MAX_OBJS];
            \\
        );
    }
    // Owned guest buffers shared by fmt/string/json producers (handles
    // read back via buffer_data/len). Kinds mirror the interpreter
    // registry: 1 = fmt/string, 2 = byte, 3 = env. The counter is gated
    // separately: read-only bindings (data/len/free) don't need it.
    if (need_owned) {
        try writer.writeAll(
            \\#ifndef SA_OWNED_MAX_OBJS
            \\#define SA_OWNED_MAX_OBJS 64
            \\#endif
            \\typedef struct { sa_u64 h, ptr, len; unsigned kind; } sa_owned_buf_t;
            \\static sa_owned_buf_t sa_owned_bufs[SA_OWNED_MAX_OBJS];
            \\
        );
        if (used.get("sa_owned_new") != null) {
            try writer.writeAll("static sa_u64 sa_owned_next = 1;\n");
        }
    }
    // Compiled POSIX regexes (regex_t holds host pointers: C-side table,
    // never guest memory). Match state lives in guest memory instead
    // (header + offset pairs), so only the compiled set needs a table.
    if (need_regex) {
        try writer.writeAll(
            \\#include <regex.h>
            \\#ifndef SA_REGEX_MAX_OBJS
            \\#define SA_REGEX_MAX_OBJS 16
            \\#endif
            \\#ifndef SA_REGEX_MAX_GROUPS
            \\#define SA_REGEX_MAX_GROUPS 32
            \\#endif
            \\typedef struct { sa_u64 h; regex_t rx; } sa_regex_t;
            \\static sa_regex_t sa_regexes[SA_REGEX_MAX_OBJS];
            \\
        );
    }
    // Module-state cells (satsgo top-level `let`): key/value slots,
    // zero default on miss.
    if (need_modstate) {
        try writer.writeAll(
            \\#ifndef SA_MODSTATE_MAX
            \\#define SA_MODSTATE_MAX 64
            \\#endif
            \\static sa_u64 sa_modstate_keys[SA_MODSTATE_MAX];
            \\static sa_u64 sa_modstate_used[SA_MODSTATE_MAX];
            \\static sa_u64 sa_modstate_vals[SA_MODSTATE_MAX];
            \\
        );
    }
    for (kRuntimeHelpers) |h| {
        if (used.get(h.name) != null) {
            try writer.writeAll(h.code);
            try writer.writeAll("\n");
        }
    }
}

/// Best-effort slot resolution for liveness: reg/symbol/text operands that
/// denote a local slot. Returns null for immediates, labels, funcs, consts.
///
/// Name-based operands (.symbol/.text) that resolve to a const decl are NOT
/// register reads: the emitter prefers the const immediate
/// (`resolveTextToC` checks `const_addrs` before registers), so counting
/// them as reads would keep dead `rN` declarations alive.
fn readSlotOf(fsig: sig.FunctionSig, use_global: bool, verified: anytype, op: inst.Operand) ?u32 {
    const symbols = verified.symbols;
    switch (op) {
        .reg => |r| return regSlot(fsig, use_global, r) catch null,
        .symbol => |id| {
            if (symbols.lookupName(id)) |name| {
                if (isConstName(verified, name)) return null;
            }
            return fsig.slotOf(id);
        },
        .text, .native_text => |t| {
            var text = std.mem.trim(u8, t, " \t");
            if (text.len == 0) return null;
            if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
            if (std.mem.lastIndexOf(u8, text, " as ")) |idx| text = std.mem.trim(u8, text[0..idx], " \t\r");
            if (text.len == 0) return null;
            if (isConstName(verified, text)) return null;
            if (symbols.findId(text)) |id| return fsig.slotOf(id);
            return null;
        },
        else => return null,
    }
}

fn isConstName(verified: anytype, name: []const u8) bool {
    for (verified.const_decls) |decl| {
        if (std.mem.eql(u8, decl.name, name)) return true;
    }
    return false;
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
            if (readSlotOf(fsig, use_global, verified, base.operands[0])) |sl| try uses.append(sl);
        },
        .try_, .early_return => {
            if (defSlotOf(fsig, use_global, base.operands[0])) |sl| try defs.append(sl);
            if (readSlotOf(fsig, use_global, verified, base.operands[1])) |sl| try uses.append(sl);
        },
        .op, .alloc, .stack_alloc, .ptr_add, .load, .take, .atomic_load => {
            if (defSlotOf(fsig, use_global, base.operands[0])) |sl| try defs.append(sl);
            for (base.operands[1..]) |opnd| {
                if (readSlotOf(fsig, use_global, verified, opnd)) |sl| try uses.append(sl);
            }
        },
        .store, .atomic_store, .release => {
            for (base.operands) |opnd| {
                if (readSlotOf(fsig, use_global, verified, opnd)) |sl| try uses.append(sl);
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
                    if (readSlotOf(fsig, use_global, verified, inst.Operand{ .text = arg.text })) |sl| try uses.append(sl);
                }
                if (parsed.is_indirect) {
                    if (readSlotOf(fsig, use_global, verified, inst.Operand{ .text = parsed.callee })) |sl| try uses.append(sl);
                }
            } else |_| {}
        },
        .cmpxchg => {
            if (defSlotOf(fsig, use_global, base.operands[0])) |sl| try defs.append(sl);
            if (defSlotOf(fsig, use_global, base.operands[1])) |sl| try defs.append(sl);
            for (base.operands[2..]) |opnd| {
                if (readSlotOf(fsig, use_global, verified, opnd)) |sl| try uses.append(sl);
            }
            if (base.atomic_expected_text) |t| {
                if (readSlotOf(fsig, use_global, verified, inst.Operand{ .text = t })) |sl| try uses.append(sl);
            }
            if (base.atomic_new_text) |t| {
                if (readSlotOf(fsig, use_global, verified, inst.Operand{ .text = t })) |sl| try uses.append(sl);
            }
        },
        .atomic_rmw => {
            if (defSlotOf(fsig, use_global, base.operands[0])) |sl| try defs.append(sl);
            for (base.operands[1..]) |opnd| {
                if (readSlotOf(fsig, use_global, verified, opnd)) |sl| try uses.append(sl);
            }
        },
        .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow => {
            if (defSlotOf(fsig, use_global, base.operands[0])) |sl| try defs.append(sl);
            if (readSlotOf(fsig, use_global, verified, base.operands[1])) |sl| try uses.append(sl);
        },
        .panic => {
            if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                var parsed = pc.*;
                defer parsed.deinit(allocator);
                for (parsed.args) |arg| {
                    if (readSlotOf(fsig, use_global, verified, inst.Operand{ .text = arg.text })) |sl| try uses.append(sl);
                }
            } else |_| {}
        },
        .br, .br_null => {
            if (readSlotOf(fsig, use_global, verified, base.operands[0])) |sl| try uses.append(sl);
        },
        else => {
            for (base.operands) |opnd| {
                if (readSlotOf(fsig, use_global, verified, opnd)) |sl| try uses.append(sl);
            }
        },
    }
}

fn computeDeadSlots(allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, use_global: bool, task: FuncTask, out_reads: ?*std.AutoHashMap(u32, void)) !std.AutoHashMap(u32, void) {
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
    if (out_reads) |out| {
        var rit = reads.iterator();
        while (rit.next()) |e| {
            try out.put(e.key_ptr.*, {});
        }
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

fn emitLinearInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, widths: *WidthMap, sigmap: anytype, uniform_arity: usize, indirect_ret_width: ?u32, dead: *const std.AutoHashMap(u32, void)) !void {
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
                } else if (indirect_ret_width) |w| {
                    if (parsed.dest) |dest| {
                        if (symbols.findId(dest)) |id| {
                            if (fsig.slotOf(id)) |slot| {
                                widths.put(slot, w) catch {};
                            }
                        }
                    }
                }
            } else |_| {}
        },
        .call_indirect => {
            if (indirect_ret_width) |w| {
                if (call.parseInstructionCall(allocator, base, symbols)) |*parsed_const| {
                    var parsed = parsed_const.*;
                    defer parsed.deinit(allocator);
                    if (parsed.dest) |dest| {
                        if (symbols.findId(dest)) |id| {
                            if (fsig.slotOf(id)) |slot| {
                                widths.put(slot, w) catch {};
                            }
                        }
                    }
                } else |_| {}
            }
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
            // Unread dest of a trapping op: bare call preserves the trap
            // with no dead store (and no declaration needed).
            if (dead.get(slot) != null) {
                try writer.writeAll("  ");
                try emitOpExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, base.operands[1], base.operands[2], widths);
                try writer.writeAll(";\n");
                return;
            }
            try writer.print("  r{d} = ", .{slot});
            try emitOpExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, base.operands[1], base.operands[2], widths);
            try writer.writeAll(";\n");
        },
        .alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Unread dest: bare call preserves bump/OOM with no dead store.
            if (dead.get(slot) != null) {
                try writer.writeAll("  sa_alloc(");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(");\n");
                return;
            }
            try writer.print("  r{d} = sa_alloc(", .{slot});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(");\n");
        },
        .stack_alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            if (dead.get(slot) != null) {
                try writer.writeAll("  sa_salloc(");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(");\n");
                return;
            }
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
            // Unread dest: bare call preserves the OOB trap with no dead
            // store (and no declaration needed).
            const dest_dead = dead.get(slot) != null;
            if (offIsZero(base.operands[2])) {
                if (dest_dead) {
                    try writer.print("  {s}(", .{load_fn});
                } else {
                    try writer.print("  r{d} = {s}(", .{ slot, load_fn });
                }
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(");\n");
            } else {
                if (dest_dead) {
                    try writer.print("  {s}(sa_ptr_add(", .{load_fn});
                } else {
                    try writer.print("  r{d} = {s}(sa_ptr_add(", .{ slot, load_fn });
                }
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

fn emitOneFunction(writer: anytype, allocator: std.mem.Allocator, verified: anytype, task: FuncTask, const_addrs: anytype, fn_idx: anytype, c_opt: CEmitOptions, sigmap: anytype, uniform_arity: usize, indirect_ret_width: ?u32) !void {
    const fsig = verified.function_sigs[task.fsig_index];
    const use_global = taskUsesGlobalRegIds(fsig, verified, task);
    last_c_func = fsig.name;
    var widths = WidthMap.init(allocator);
    defer widths.deinit();
    // Definitely-unread slots: pure redefinitions elided, effectful calls
    // kept in (void) form (silences clang-analyzer-deadcode.DeadStores).
    var live_reads = std.AutoHashMap(u32, void).init(allocator);
    defer live_reads.deinit();
    var reads_complete = true;
    var dead = computeDeadSlots(allocator, verified, fsig, use_global, task, &live_reads) catch blk: {
        reads_complete = false;
        break :blk std.AutoHashMap(u32, void).init(allocator);
    };
    defer dead.deinit();
    var elide = computeElideIdx(allocator, verified, fsig, use_global, task) catch std.AutoHashMap(usize, void).init(allocator);
    defer elide.deinit();
    // Labels targeted by a jump/branch. An untargeted label is pure
    // fallthrough: emitting it trips -Wunused-label, so only the gas
    // metering (which still executes on fallthrough) is kept.
    var label_refs = std.AutoHashMap(u32, void).init(allocator);
    defer label_refs.deinit();
    {
        var li: usize = task.start_idx + 1;
        while (li < task.end_idx) : (li += 1) {
            const lb = verified.annotated[li].base;
            switch (lb.kind) {
                .jmp => {
                    const id: u32 = switch (lb.operands[1]) {
                        .label => |v| v, .symbol => |v| v, else => continue,
                    };
                    label_refs.put(id, {}) catch {};
                },
                .br, .br_null => {
                    const t: u32 = switch (lb.operands[1]) {
                        .label => |v| v, .symbol => |v| v, else => continue,
                    };
                    const f: u32 = switch (lb.operands[3]) {
                        .label => |v| v, .symbol => |v| v, else => continue,
                    };
                    label_refs.put(t, {}) catch {};
                    label_refs.put(f, {}) catch {};
                },
                else => {},
            }
        }
    }
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
        // Slots never read in the body are not declared at all: a
        // set-but-unused `rN` trips -Wunused-but-set-variable (and reads
        // as dead code to auditors); nothing references them.
        var first_decl = true;
        var s: usize = 0;
        while (s < nregs) : (s += 1) {
            const slot32: u32 = @intCast(s);
            // Declare a slot iff it is read somewhere (when liveness is
            // known). Effectful instructions with unread dests are
            // emitted as bare calls (no assignment), so no declaration
            // is needed for them; pure unread ones are elided outright.
            // On any analysis failure declare everything (safe direction:
            // an unused declaration warns, a missing one errors).
            if (reads_complete and live_reads.get(slot32) == null) continue;
            if (first_decl) {
                try writer.writeAll("  sa_u64 ");
                first_decl = false;
            } else {
                try writer.writeAll(", ");
            }
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
        if (!first_decl) {
            try writer.writeAll(";\n");
        }
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
    // Gas metering: every function entry costs 1 unit. The SA selling
    // point is Gas+Capability; without this a guest infinite loop hangs
    // the host (e.g. a Shopify checkout rule).
    if (c_opt.gas) {
        try writer.writeAll("  SA_GAS_CHECK(1);\n");
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
                if (label_refs.get(id) == null) {
                    // Fallthrough-only block: no label (else -Wunused-label),
                    // but the block entry still pays gas on fallthrough.
                    if (c_opt.debug_comments) {
                        try writer.print("  /* fallthrough {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                    }
                    if (c_opt.gas) {
                        try writer.writeAll("  SA_GAS_CHECK(1);\n");
                    }
                    continue;
                }
                try writer.print("SA_L_{d}:\n", .{id});
                // Loop/back-edge headers pay gas per visit: bounded execution.
                if (c_opt.gas) {
                    try writer.writeAll("  SA_GAS_CHECK(1);\n");
                }
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
                try emitLinearInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, base, &widths, sigmap, uniform_arity, indirect_ret_width, &dead);
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
    // Indirect dispatch is needed iff the IR contains a dynamic call
    // site. Vtable consts alone don't need the ftable: without a call
    // site it would be dead data plus an unused dispatcher.
    var need_indirect = false;
    {
        var ti: usize = 0;
        while (ti < tasks.len and !need_indirect) : (ti += 1) {
            var i: usize = tasks[ti].start_idx + 1;
            while (i < tasks[ti].end_idx) : (i += 1) {
                const base = verified.annotated[i].base;
                if (base.kind != .call and base.kind != .call_indirect) continue;
                if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                    var parsed = pc.*;
                    defer parsed.deinit(allocator);
                    if (parsed.is_indirect) need_indirect = true;
                } else |_| {}
            }
        }
    }
    // Host-side dispatch: some staged bindings (pthread_spawn) invoke
    // guest code via sa_call_indirect, so a program that calls them needs
    // the dispatcher+ftable even without a call_indirect instruction.
    // (Corner: a call inside otherwise-dead code still forces it; no demo
    // hits that, and the sweep guards -Wall cleanliness.)
    if (!need_indirect) {
        var ti: usize = 0;
        while (ti < tasks.len and !need_indirect) : (ti += 1) {
            var i: usize = tasks[ti].start_idx + 1;
            while (i < tasks[ti].end_idx) : (i += 1) {
                const base = verified.annotated[i].base;
                if (base.kind != .call) continue;
                if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                    var parsed = pc.*;
                    defer parsed.deinit(allocator);
                    if (!parsed.is_indirect and bindingNeedsDispatcher(sigNormName(parsed.callee))) need_indirect = true;
                } else |_| {}
            }
        }
    }
    // Reachable defined functions: BFS from entry points over static direct
    // calls, keyed by fsig_index. Unreachable definitions are skipped
    // entirely (emitting them trips -Wunused-function and they are dead
    // code to auditors). The only roots are `main` and, with indirect
    // dispatch, the vtable entries referenced by the ftable initializer.
    // NOTE: exports/tests are deliberately NOT roots: this backend emits a
    // linked program (`int main`), not a library, so an uncalled export is
    // dead code here. (A unit with no main at all keeps everything.)
    // A dynamically called function must hold a vtable slot (`.func`
    // operands resolve via fn_idx), so static reachability + fn_names is
    // exact: nothing reachable is ever skipped.
    var reachable = std.AutoHashMap(usize, void).init(allocator);
    defer reachable.deinit();
    {
        var has_entry = false;
        for (tasks) |task| {
            if (task.kind == .extern_decl) continue;
            const norm = sigNormName(verified.function_sigs[task.fsig_index].name);
            if (std.mem.eql(u8, norm, "main")) {
                try reachable.put(task.fsig_index, {});
                has_entry = true;
            }
        }
        if (need_indirect) {
            for (fn_names.items) |fname| {
                if (taskIndexByName(tasks, verified, sigNormName(fname))) |ci| {
                    try reachable.put(ci, {});
                }
                has_entry = true;
            }
        }
        if (!has_entry) {
            // Pure library unit (no entry point): keep everything.
            for (tasks) |task| {
                if (task.kind == .extern_decl) continue;
                try reachable.put(task.fsig_index, {});
            }
        } else {
            var queue = std.array_list.Managed(usize).init(allocator);
            defer queue.deinit();
            var rit = reachable.iterator();
            while (rit.next()) |e| try queue.append(e.key_ptr.*);
            var qi: usize = 0;
            while (qi < queue.items.len) : (qi += 1) {
                const cur = queue.items[qi];
                for (tasks) |task| {
                    if (task.kind == .extern_decl) continue;
                    if (task.fsig_index != cur) continue;
                    var i: usize = task.start_idx + 1;
                    while (i < task.end_idx) : (i += 1) {
                        const base = verified.annotated[i].base;
                        if (base.kind != .call and base.kind != .call_indirect) continue;
                        if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                            var parsed = pc.*;
                            defer parsed.deinit(allocator);
                            if (parsed.is_indirect) continue;
                            if (taskIndexByName(tasks, verified, sigNormName(parsed.callee))) |ci| {
                                if (!reachable.contains(ci)) {
                                    try reachable.put(ci, {});
                                    try queue.append(ci);
                                }
                            }
                        } else |_| {}
                    }
                }
            }
        }
    }
    // Unanimous ftable return domain: every successful indirect call
    // lands on an ftable entry (bounds + null checked in the dispatcher),
    // so when all entries share one return domain the indirect result
    // domain is exact (e.g. single-callback tables returning f32).
    // Non-unanimous (or empty) tables keep the unknown default.
    var indirect_ret_width: ?u32 = null;
    if (need_indirect and fn_names.items.len > 0) {
        var acc: ?u32 = null;
        var unanimous = true;
        var first = true;
        for (fn_names.items) |fname| {
            const w = sigReturnWidth(sigmap, fname);
            if (first) {
                acc = w;
                first = false;
            } else if (!std.meta.eql(acc, w)) {
                unanimous = false;
                break;
            }
        }
        if (unanimous) indirect_ret_width = acc;
    }
    // Const address layout (pure; #defines are emitted in phase 2 after
    // the helper scan so the preamble comes first in the file).
    var const_addrs = std.StringHashMap(usize).init(allocator);
    defer const_addrs.deinit();
    var const_cursor: usize = 4096;
    const bump_start: usize = 65536;
    var has_const_bytes = false;
    for (verified.const_decls) |decl| {
        const len = constBytesLen(decl.value) catch 0;
        const aligned = std.mem.alignForward(usize, const_cursor, 8);
        if (decl.value == .vtable or len == 0) {
            const is_vt = decl.value == .vtable;
            const slots: usize = if (is_vt) decl.value.vtable.slots.len * 8 else 8;
            const a2 = std.mem.alignForward(usize, const_cursor, 8);
            if (a2 + slots > bump_start) return CEmitError.Failed;
            try const_addrs.put(decl.name, a2);
            const_cursor = a2 + slots;
            continue;
        }
        if (aligned + len > bump_start) return CEmitError.Failed;
        try const_addrs.put(decl.name, aligned);
        has_const_bytes = true;
        const_cursor = aligned + len;
    }
    var rest: std.Io.Writer.Allocating = .init(allocator);
    defer rest.deinit();
    const rw = &rest.writer;
    // Phase 1: const-init + function bodies go to a side buffer first so
    // phase 2 can scan the exact helper set referenced and emit only
    // those (no dead runtime helpers for Coverity/Semgrep to flag).
    // const init
    try rw.writeAll("static void sa_init_consts(void) {\n  static int done = 0; if (done) return; done = 1;\n");
    for (verified.const_decls) |decl| {
        const init_len = constBytesLen(decl.value) catch 0;
        if (decl.value == .vtable or init_len == 0) {
            if (decl.value == .vtable) {
                var sidx: usize = 0;
                for (decl.value.vtable.slots) |vslot| {
                    const fidx = fnIndexOf(fn_idx, vslot.func_name) orelse return CEmitError.UnknownFunction;
                    const addr = const_addrs.get(decl.name) orelse return CEmitError.InvalidOperand;
                    const le: u64 = 1000000 + @as(u64, @intCast(fidx));
                    try rw.print("  sa_store_u64({d}ULL, {d}ULL);\n", .{ addr + sidx * 8, le });
                    sidx += 1;
                }
            }
            continue;
        }
        const bytes = try allocator.alloc(u8, init_len);
        defer allocator.free(bytes);
        try fillConstBytes(bytes, decl.value);
        const addr = const_addrs.get(decl.name) orelse return CEmitError.InvalidOperand;
        try rw.print("  {{ static const uint8_t b[] = {{", .{});
        for (bytes, 0..) |b, idx| {
            if (idx != 0) try rw.writeAll(",");
            try rw.print("{d}", .{b});
        }
        try rw.print("}}; {{ size_t i; for (i = 0; i < {d}; i++) sa_mem[{d} + i] = b[i]; }} }}\n", .{ init_len, addr });
    }
    try rw.writeAll("}\n");
    var emitted = std.StringHashMap(void).init(allocator);
    defer emitted.deinit();
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        const efsig = verified.function_sigs[task.fsig_index];
        if (emitted.contains(efsig.name)) continue;
        // Unreachable definitions are dead code: skip (else
        // -Wunused-function). Reachability is exact (see above).
        if (reachable.get(task.fsig_index) == null) continue;
        try emitOneFunction(rw, allocator, verified, task, &const_addrs, &fn_idx, c_opt, &sigmap, uniform_arity, indirect_ret_width);
        try emitted.put(efsig.name, {});
    }
    // Phase 2: helper-use scan, then the file preamble (which must precede
    // any `sa_u64`-typed declaration in output order).
    const rest_text = try rest.toOwnedSlice();
    defer allocator.free(rest_text);
    var used = try collectUsedHelpers(allocator, rest_text);
    defer used.deinit();
    // Seed helper uses from extern binding bodies (emitted after the
    // preamble): render each called, known binding once and merge what
    // it references, so e.g. mmap pulls sa_alloc. Unknown externs keep
    // the trap stub, which needs only sa_trap (always present).
    // Rendering an sa_http_* binding also raises need_http for the
    // staged state tables.
    var need_http = false;
    var need_owned = false;
    var need_modstate = false;
    var need_regex = false;
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const efsig = verified.function_sigs[task.fsig_index];
        if (std.mem.eql(u8, sigNormName(efsig.name), "sa_print_bytes")) continue;
        if (!bodyCallsFunction(rest_text, efsig.name)) continue;
        var tmp: std.Io.Writer.Allocating = .init(allocator);
        defer tmp.deinit();
        if (!try writeExternBinding(&tmp.writer, efsig.name, uniform_arity, c_opt.gas)) continue;
        const rendered_norm = sigNormName(efsig.name);
        if (std.mem.startsWith(u8, rendered_norm, "sa_http_")) need_http = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_owned_") != null) need_owned = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_modstate_") != null) need_modstate = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_regex_") != null) need_regex = true;
        const t = try tmp.toOwnedSlice();
        defer allocator.free(t);
        // Self-check every rendered binding: unbalanced output fails the
        // build loudly instead of emitting broken C (covers all present
        // and future bindings with no list to keep in sync).
        if (!cBodyBalanced(t)) return CEmitError.Failed;
        var bu = try collectUsedHelpers(allocator, t);
        defer bu.deinit();
        var bit = bu.iterator();
        while (bit.next()) |e| try used.put(e.key_ptr.*, {});
    }
    // Linear memory is needed for const bytes or any mem-touching helper.
    // (sa_brk only travels with the allocator; sa_mem stays out entirely
    // for pure-compute programs.)
    var need_mem = has_const_bytes;
    if (!need_mem) {
        var uit = used.iterator();
        while (uit.next()) |e| {
            const n = e.key_ptr.*;
            if (std.mem.startsWith(u8, n, "sa_load_") or std.mem.startsWith(u8, n, "sa_store_") or std.mem.eql(u8, n, "sa_alloc") or std.mem.eql(u8, n, "sa_print_bytes")) {
                need_mem = true;
                break;
            }
        }
    }
    const need_brk = used.get("sa_alloc") != null;
    try writePreamble(writer, c_opt, size_bits, &used, need_mem, need_brk, need_http, need_owned, need_modstate, need_regex);
    try writer.print("/* source: {s} */\n", .{source_path});
    // const address defines
    for (verified.const_decls) |decl| {
        const addr = const_addrs.get(decl.name) orelse return CEmitError.InvalidOperand;
        try writer.writeAll("#define ");
        try writeConstSym(writer, decl.name);
        if (decl.value == .vtable) {
            try writer.print(" {d}UL /* vtable */\n", .{addr});
        } else {
            const def_len = constBytesLen(decl.value) catch 0;
            if (def_len == 0) {
                try writer.print(" {d}UL /* {s} */\n", .{ addr, @tagName(decl.value) });
            } else {
                try writer.print(" {d}UL\n", .{addr});
            }
        }
    }
    // forward decls (uniform arity); only for emitted functions, so no
    // decl is left without a definition (-Wunused-function).
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        if (reachable.get(task.fsig_index) == null) continue;
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
    // Forward declaration for the indirect dispatcher (defined after all
    // functions so the ftable can reference them). Only when a dynamic
    // call site exists; otherwise it would be dead code.
    if (need_indirect) {
        try writer.writeAll("// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform calling convention\nstatic sa_u64 sa_call_indirect(sa_u64 f");
        for (0..uniform_arity) |k| {
            try writer.print(", sa_u64 a{d}", .{k});
        }
        try writer.writeAll(");\n");
    }
    // forward declarations for extern trap stubs (defined at the end):
    // without these, calls to externs hit implicit-declaration errors.
    // Only for called externs (a static decl without a definition or use
    // trips -Wunused-function).
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (std.mem.eql(u8, sigNormName(fsig.name), "sa_print_bytes")) continue;
        if (!bodyCallsFunction(rest_text, fsig.name)) continue;
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
    // Fwd decls for vtable-referenced functions with no definition: only
    // needed alongside the ftable (dead otherwise).
    if (need_indirect) {
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
    }
    try writer.writeAll(rest_text);
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (emitted.contains(fsig.name)) continue;
        if (std.mem.eql(u8, sigNormName(fsig.name), "sa_print_bytes")) continue; // runtime provides it
        // Only emit a stub when the body actually calls it: an unreferenced
        // static definition trips -Wunused-function (and reads as dead
        // code to auditors). Externs are only reachable via direct calls,
        // which render as `sa_fn_<name>(`, so a text scan is exact.
        if (!bodyCallsFunction(rest_text, fsig.name)) continue;
        // Known externs get staged host bindings; anything else keeps the
        // trap stub (uniform arity).
        if (try writeExternBinding(writer, fsig.name, uniform_arity, c_opt.gas)) {
            try emitted.put(fsig.name, {});
            continue;
        }
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
    // Only with the ftable: every entry is referenced by its initializer,
    // so no stub is ever dead.
    if (need_indirect) {
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
    }
    // Indirect dispatch: uniform signature makes a plain function-pointer
    // table exact (indices match fn_idx / vtable const encoding). Skipped
    // entirely without a dynamic call site (dead otherwise).
    if (need_indirect) {
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
        // Lower-bound check first: `f - 1000000` wraps for f < 1000000, so
        // the old `uint64_t idx = f - 1000000; if (idx >= 0)` was always
        // true and trapped every indirect call.
        try writer.writeAll(") {\n  if (f < 1000000ULL) { sa_trap(\"bad indirect callee\"); }\n");
        try writer.writeAll("  { sa_u64 idx = f - 1000000ULL;\n");
        try writer.writeAll("    if (idx >= (sa_u64)(sizeof(sa_ftable) / sizeof(sa_ftable[0]))) { sa_trap(\"bad indirect callee\"); }\n");
        try writer.writeAll("    if (sa_ftable[idx] == 0) { sa_trap(\"null indirect callee\"); }\n");
        try writer.writeAll("    return sa_ftable[idx](");
        for (0..uniform_arity) |k| {
            if (k != 0) try writer.writeAll(", ");
            try writer.print("a{d}", .{k});
        }
        try writer.writeAll("); }\n}\n");
    }
    try writer.writeAll("int main(void) { sa_init_consts();\n");
    if (c_opt.gas) {
        // Keeps `sa_gas` referenced even for (degenerate) programs whose
        // functions were all elided; normally the SA_GAS_CHECKs do that.
        try writer.writeAll("  (void)sa_gas;\n");
    }
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

/// True iff t is a brace-balanced function body ending with "}\n",
/// ignoring braces inside strings/chars. Used to self-check every
/// rendered extern binding (an unclosed body would swallow following
/// definitions; fail the build loudly instead of emitting broken C).
/// NOTE: emit_c unit tests are not wired into any test binary, so this
/// runtime check (not a test block) is the enforced guard.
fn cBodyBalanced(t: []const u8) bool {
    if (!std.mem.endsWith(u8, t, "}\n")) return false;
    var depth: i32 = 0;
    var in_str = false;
    var in_chr = false;
    var esc = false;
    for (t) |c| {
        if (in_str) {
            if (esc) { esc = false; } else if (c == '\\') { esc = true; } else if (c == '"') { in_str = false; }
        } else if (in_chr) {
            if (esc) { esc = false; } else if (c == '\\') { esc = true; } else if (c == '\'') { in_chr = false; }
        } else if (c == '"') { in_str = true; } else if (c == '\'') { in_chr = true; } else if (c == '{') { depth += 1; } else if (c == '}') {
            depth -= 1;
            if (depth < 0) return false;
        }
    }
    return depth == 0;
}
