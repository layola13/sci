const std = @import("std");

const emit_options = @import("emit_options.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const call = @import("referee/call.zig");
const const_decl = @import("common/const_decl.zig");
const sio = @import("sio");

pub const EmitOptions = emit_options.EmitOptions;
pub const CEmitError = error{ Failed, InvalidOperand, UnknownFunction, UnsupportedInstruction, UnsupportedVariadic, OutOfMemory };

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
    // Atomic kinds carry their value type in atomic_value_ty (mirrors
    // emit_llvm_llvmc.atomicValueType and emit_js.memPrimType).
    if (base.kind == .atomic_load or base.kind == .atomic_store or
        base.kind == .atomic_rmw or base.kind == .cmpxchg)
    {
        if (base.atomic_value_ty) |tag| return tagToPrim(tag);
        return .i64;
    }
    // operands[3] for load/store is usually .ty tag. The untyped fallback
    // must match the reference widths (interp.zig): an untyped `take`
    // loads a pointer, an untyped load/store moves a full i64 word. The
    // previous u8 fallback truncated untyped pointer takes to the low
    // byte (e.g. `take vec+Vec_ptr` in sa_vec_push read back 8 instead
    // of the buffer address, corrupting every Vec grow copy).
    for (base.operands) |op| {
        if (op == .ty) return tagToPrim(op.ty);
    }
    return if (base.kind == .take) .ptr else .i64;
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
            // A typed assignment (`dst = src as T`, the form SLA's
            // casts take) leaves the register holding a T value.
            if (base.kind == .assign) {
                if (castTargetType(base)) |tgt| {
                    if (packWidth(tgt)) |w| {
                        widths.put(dst, w) catch return;
                        return;
                    }
                }
            }
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
        .raw_cast => {
            // After a cast the register holds a value of the TARGET
            // type (the cast converts at materialization in the
            // reference's typed-register model), so record the target
            // width; without a parseable target, propagate the source
            // width (bit-pattern-preserving domains) rather than
            // dropping it, so downstream typed consumers still see a
            // domain. Dropping it made every post-cast store a blind
            // bit copy of whatever the source held.
            if (slotOfOp(fsig, use_global, base.operands[0])) |dst| {
                if (castTargetType(base)) |tgt| {
                    if (packWidth(tgt)) |w| {
                        widths.put(dst, w) catch return;
                    } else {
                        widthRemoveSlot(widths, dst);
                    }
                } else if (widthOfOperand(widths, fsig, use_global, base.operands[1])) |w| {
                    widths.put(dst, w) catch return;
                } else {
                    widthRemoveSlot(widths, dst);
                }
            }
        },
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
        .i1 => "i1",
        .i8 => "i8",
        .i16 => "i16",
        .i32 => "i32",
        .i64 => "i64",
        .u8 => "u8",
        .u16 => "u16",
        .u32 => "u32",
        .u64 => "u64",
        .blob_handle => "u64",
        .ptr => "ptr",
        .f32 => "f32",
        .f64 => "f64",
        else => return CEmitError.InvalidOperand,
    };
    const opname: []const u8 = switch (opcode) {
        .trunc => "trunc",
        .zext => "zext",
        .sext => "sext",
        .fptosi => "fptosi",
        .sitofp => "sitofp",
        .uitofp => "uitofp",
        .fptrunc => "fptrunc",
        .fpext => "fpext",
        .bitcast => "bitcast",
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

/// The target type of a `dst = src as T` cast, recovered from the
/// instruction's raw text (the instruction itself carries only
/// dst/src; the type survives in the text form). Null when the text
/// has no parseable `as T` tail.
fn castTargetType(base: inst.Instruction) ?sig.PrimType {
    const text = std.mem.trim(u8, base.raw_text, " \t\r\n");
    const idx = std.mem.lastIndexOf(u8, text, " as ") orelse return null;
    var tail = std.mem.trim(u8, text[idx + 4 ..], " \t\r\n");
    if (tail.len == 0) return null;
    if (std.mem.indexOfAny(u8, tail, " \t\r\n")) |end| tail = tail[0..end];
    return sig.parsePrimType(tail) catch null;
}

/// Conversion opcode for a raw_cast from a source of width code
/// `src_code` to target type `tgt`, or null when the cast is a pure
/// bit copy in this backend's register model (same domain and width).
fn castOpcode(src_code: u32, tgt: sig.PrimType) ?inst.OpKind {
    const tgt_code = packWidth(tgt) orelse return null;
    const src_float = widthIsFloat(src_code);
    const tgt_float = widthIsFloat(tgt_code);
    const src_bits = widthBits(src_code);
    const tgt_bits = widthBits(tgt_code);
    if (src_float and tgt_float) {
        if (src_bits == tgt_bits) return null;
        return if (tgt_bits == 32) .fptrunc else .fpext;
    }
    if (src_float) return .fptosi;
    if (tgt_float) return if (widthIsSigned(src_code)) .sitofp else .uitofp;
    if (tgt_bits < src_bits) return .trunc;
    if (tgt_bits > src_bits) return if (widthIsSigned(src_code)) .sext else .zext;
    return null;
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
    // Float/int mixing (e.g. `eq(f64val, 10)` from TS `==`): exactly one
    // statically-known float side plus a statically-known int side
    // compares numerically in f64 (JS == parity, ints converted). All
    // other shapes keep the legacy bitwise compare.
    switch (opcode) {
        .eq, .ne => {
            const lk = cOperandKind(widths, fsig, use_global, lhs);
            const rk = cOperandKind(widths, fsig, use_global, rhs);
            const lf = lk == .float;
            const rf = rk == .float;
            const li = lk == .signed or lk == .unsigned;
            const ri = rk == .signed or rk == .unsigned;
            if ((lf and ri) or (li and rf)) {
                try writer.print("{s}(", .{if (opcode == .eq) "sa_fcmp_eq" else "sa_fcmp_ne"});
                try emitFNumOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, widths, lhs, lk, .f64);
                try writer.writeAll(", ");
                try emitFNumOperand(writer, symbols, fsig, use_global, const_addrs, fn_idx, widths, rhs, rk, .f64);
                try writer.writeAll(")");
                return;
            }
        },
        else => {},
    }
    // Float ALU: f32 iff both sides proven f32, else f64 (int sides
    // convert, unknowns go raw, f32 sides promote; mirrors JS).
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
        .add => "sa_add",
        .sub => "sa_sub",
        .mul => "sa_mul",
        .sdiv => "sa_sdiv",
        .udiv => "sa_udiv",
        .srem => "sa_srem",
        .urem => "sa_urem",
        .@"and" => "sa_band",
        .@"or" => "sa_bor",
        .xor => "sa_bxor",
        .shl => "sa_shl",
        .lshr => "sa_lshr",
        .ashr => "sa_ashr",
        .not => "sa_bnot",
        .neg => "sa_neg",
        .eq => "sa_eq",
        .ne => "sa_ne",
        .slt => "sa_slt",
        .sle => "sa_sle",
        .sgt => "sa_sgt",
        .sge => "sa_sge",
        .ult => "sa_ult",
        .ule => "sa_ule",
        .ugt => "sa_ugt",
        .uge => "sa_uge",
        .fadd => "sa_fadd",
        .fsub => "sa_fsub",
        .fmul => "sa_fmul",
        .fdiv => "sa_fdiv",
        .fneg => "sa_fneg",
        .fcmp_eq => "sa_fcmp_eq",
        .fcmp_ne => "sa_fcmp_ne",
        .fcmp_lt => "sa_fcmp_lt",
        .fcmp_le => "sa_fcmp_le",
        .fcmp_gt => "sa_fcmp_gt",
        .fcmp_ge => "sa_fcmp_ge",
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
    .{ .name = "sa_policy_check", .code =
    \\#include <string.h>
    \\#include <time.h>
    \\/* ---- sa policy (16_policy phase 1; C port of sa_policy.zig) ----
    \\   Same policy JSON, same SA_POLICY_* env vars, same audit JSONL shape
    \\   and decision semantics as the native runtime. Lazily initialized on
    \\   first gated call; with no policy configured the backend stays in
    \\   legacy mode (everything allowed), exactly like the native default.
    \\   Categories: 0 net, 1 fs, 2 env, 3 run, 4 time, 5 random.
    \\   Modes: 0 allow, 1 deny, 2 allow-list, 3 audit, 4 ask. */
    \\typedef struct { char **items; size_t len; } sa_pol_list;
    \\typedef struct { int mode; sa_pol_list allow, read, write; } sa_pol_cat;
    \\static sa_pol_cat sa_pol_cats[6];
    \\static int sa_pol_state = 0; /* 0 uninit, 1 legacy, 2 policy */
    \\static char *sa_pol_audit_path = 0;
    \\static const char *sa_pol_cat_names[6] = { "net", "fs", "env", "run", "time", "random" };
    \\static void sa_pol_invalid(void) { fputs("[sa-policy] InvalidPolicy\n", stderr); exit(2); }
    \\static char *sa_pol_strdup_n(const char *s, size_t n) { char *p = (char *)malloc(n + 1); if (!p) exit(2); memcpy(p, s, n); p[n] = 0; return p; }
    \\typedef struct { const char *s; size_t len; size_t pos; } sa_pol_js;
    \\static void sa_pol_ws(sa_pol_js *j) { while (j->pos < j->len) { char c = j->s[j->pos]; if (c == ' ' || c == '\t' || c == '\n' || c == '\r') j->pos++; else break; } }
    \\static void sa_pol_expect(sa_pol_js *j, char c) { sa_pol_ws(j); if (j->pos >= j->len || j->s[j->pos] != c) sa_pol_invalid(); j->pos++; }
    \\static int sa_pol_peek(sa_pol_js *j) { sa_pol_ws(j); return j->pos < j->len ? j->s[j->pos] : -1; }
    \\static unsigned sa_pol_hex4(sa_pol_js *j) { unsigned v = 0; int i; for (i = 0; i < 4; i++) { char c; unsigned d; if (j->pos >= j->len) sa_pol_invalid(); c = j->s[j->pos++]; if (c >= '0' && c <= '9') d = (unsigned)(c - '0'); else if (c >= 'a' && c <= 'f') d = (unsigned)(c - 'a' + 10); else if (c >= 'A' && c <= 'F') d = (unsigned)(c - 'A' + 10); else sa_pol_invalid(); v = v * 16 + d; } return v; }
    \\static char *sa_pol_json_string(sa_pol_js *j) {
    \\  size_t cap = 16, n = 0; char *out;
    \\  sa_pol_expect(j, '"');
    \\  out = (char *)malloc(cap); if (!out) exit(2);
    \\  for (;;) {
    \\    char c; if (j->pos >= j->len) sa_pol_invalid(); c = j->s[j->pos++];
    \\    if (c == '"') break;
    \\    if (c == '\\') {
    \\      char e; if (j->pos >= j->len) sa_pol_invalid(); e = j->s[j->pos++];
    \\      if (e == 'u') { unsigned cp = sa_pol_hex4(j); char tmp[4]; int tn = 0;
    \\        if (cp >= 0xD800 && cp <= 0xDBFF) { /* lone surrogate half: replace */ cp = 0xFFFD; }
    \\        if (cp < 0x80) tmp[tn++] = (char)cp;
    \\        else if (cp < 0x800) { tmp[tn++] = (char)(0xC0 | (cp >> 6)); tmp[tn++] = (char)(0x80 | (cp & 0x3F)); }
    \\        else { tmp[tn++] = (char)(0xE0 | (cp >> 12)); tmp[tn++] = (char)(0x80 | ((cp >> 6) & 0x3F)); tmp[tn++] = (char)(0x80 | (cp & 0x3F)); }
    \\        if (n + (size_t)tn + 1 > cap) { while (n + (size_t)tn + 1 > cap) cap *= 2; out = (char *)realloc(out, cap); if (!out) exit(2); }
    \\        memcpy(out + n, tmp, (size_t)tn); n += (size_t)tn; continue;
    \\      }
    \\      switch (e) { case '"': c = '"'; break; case '\\': c = '\\'; break; case '/': c = '/'; break; case 'b': c = '\b'; break; case 'f': c = '\f'; break; case 'n': c = '\n'; break; case 'r': c = '\r'; break; case 't': c = '\t'; break; default: sa_pol_invalid(); }
    \\    }
    \\    if (n + 2 > cap) { cap *= 2; out = (char *)realloc(out, cap); if (!out) exit(2); }
    \\    out[n++] = c;
    \\  }
    \\  out[n] = 0; return out;
    \\}
    \\static void sa_pol_json_skip(sa_pol_js *j) {
    \\  int c = sa_pol_peek(j);
    \\  if (c == '"') { char *t = sa_pol_json_string(j); free(t); return; }
    \\  if (c == '{') { j->pos++; if (sa_pol_peek(j) == '}') { j->pos++; return; } for (;;) { char *k = sa_pol_json_string(j); free(k); sa_pol_expect(j, ':'); sa_pol_json_skip(j); if (sa_pol_peek(j) == ',') { j->pos++; continue; } sa_pol_expect(j, '}'); return; } }
    \\  if (c == '[') { j->pos++; if (sa_pol_peek(j) == ']') { j->pos++; return; } for (;;) { sa_pol_json_skip(j); if (sa_pol_peek(j) == ',') { j->pos++; continue; } sa_pol_expect(j, ']'); return; } }
    \\  while (j->pos < j->len) { char ch = j->s[j->pos]; if ((ch >= '0' && ch <= '9') || ch == '-' || ch == '+' || ch == '.' || ch == 'e' || ch == 'E' || (ch >= 'a' && ch <= 'z')) j->pos++; else break; }
    \\}
    \\static sa_pol_list sa_pol_json_string_list(sa_pol_js *j) {
    \\  sa_pol_list out; out.items = 0; out.len = 0; size_t cap = 0;
    \\  sa_pol_expect(j, '[');
    \\  if (sa_pol_peek(j) == ']') { j->pos++; return out; }
    \\  for (;;) {
    \\    char *v = sa_pol_json_string(j);
    \\    if (out.len == cap) { cap = cap ? cap * 2 : 4; out.items = (char **)realloc(out.items, cap * sizeof(char *)); if (!out.items) exit(2); }
    \\    out.items[out.len++] = v;
    \\    if (sa_pol_peek(j) == ',') { j->pos++; continue; }
    \\    sa_pol_expect(j, ']'); return out;
    \\  }
    \\}
    \\static int sa_pol_cat_index(const char *name) { int i; for (i = 0; i < 6; i++) if (strcmp(name, sa_pol_cat_names[i]) == 0) return i; return -1; }
    \\static void sa_pol_parse_category(sa_pol_js *j, int cat) {
    \\  sa_pol_cat *cp = &sa_pol_cats[cat]; int has_lists = 0; int has_mode = 0;
    \\  cp->mode = 1;
    \\  sa_pol_expect(j, '{');
    \\  if (sa_pol_peek(j) == '}') { j->pos++; return; }
    \\  for (;;) {
    \\    char *key = sa_pol_json_string(j);
    \\    sa_pol_expect(j, ':');
    \\    if (strcmp(key, "mode") == 0) {
    \\      char *m = sa_pol_json_string(j); has_mode = 1;
    \\      if (strcmp(m, "allow") == 0) cp->mode = 0;
    \\      else if (strcmp(m, "deny") == 0) cp->mode = 1;
    \\      else if (strcmp(m, "allow-list") == 0) cp->mode = 2;
    \\      else if (strcmp(m, "audit") == 0) cp->mode = 3;
    \\      else if (strcmp(m, "ask") == 0) cp->mode = 4;
    \\      else sa_pol_invalid();
    \\      free(m);
    \\    } else if (strcmp(key, "allow") == 0) {
    \\      if (cat == 1 || cat == 4 || cat == 5) sa_pol_invalid();
    \\      cp->allow = sa_pol_json_string_list(j); has_lists = 1;
    \\    } else if (strcmp(key, "read") == 0) {
    \\      if (cat != 1) sa_pol_invalid();
    \\      cp->read = sa_pol_json_string_list(j); has_lists = 1;
    \\    } else if (strcmp(key, "write") == 0) {
    \\      if (cat != 1) sa_pol_invalid();
    \\      cp->write = sa_pol_json_string_list(j); has_lists = 1;
    \\    } else sa_pol_invalid();
    \\    free(key);
    \\    if (sa_pol_peek(j) == ',') { j->pos++; continue; }
    \\    sa_pol_expect(j, '}'); break;
    \\  }
    \\  if (has_lists && !has_mode) cp->mode = 2;
    \\}
    \\static char *sa_pol_sink = 0;
    \\static void sa_pol_parse(const char *text) {
    \\  sa_pol_js j; int i; j.s = text; j.len = strlen(text); j.pos = 0;
    \\  for (i = 0; i < 6; i++) { sa_pol_cats[i].mode = 1; sa_pol_cats[i].allow.items = 0; sa_pol_cats[i].allow.len = 0; sa_pol_cats[i].read.items = 0; sa_pol_cats[i].read.len = 0; sa_pol_cats[i].write.items = 0; sa_pol_cats[i].write.len = 0; }
    \\  sa_pol_expect(&j, '{');
    \\  if (sa_pol_peek(&j) == '}') { j.pos++; }
    \\  else for (;;) {
    \\    char *key = sa_pol_json_string(&j);
    \\    sa_pol_expect(&j, ':');
    \\    if (strcmp(key, "permissions") == 0) {
    \\      sa_pol_expect(&j, '{');
    \\      if (sa_pol_peek(&j) == '}') { j.pos++; }
    \\      else for (;;) {
    \\        char *name = sa_pol_json_string(&j); int cat;
    \\        sa_pol_expect(&j, ':');
    \\        cat = sa_pol_cat_index(name); if (cat < 0) sa_pol_invalid();
    \\        free(name);
    \\        sa_pol_parse_category(&j, cat);
    \\        if (sa_pol_peek(&j) == ',') { j.pos++; continue; }
    \\        sa_pol_expect(&j, '}'); break;
    \\      }
    \\    } else if (strcmp(key, "audit") == 0) {
    \\      sa_pol_expect(&j, '{');
    \\      if (sa_pol_peek(&j) == '}') { j.pos++; }
    \\      else for (;;) {
    \\        char *ak = sa_pol_json_string(&j);
    \\        sa_pol_expect(&j, ':');
    \\        if (strcmp(ak, "sink") == 0) { sa_pol_sink = sa_pol_json_string(&j); }
    \\        else if (strcmp(ak, "events") == 0) { sa_pol_list ev = sa_pol_json_string_list(&j); size_t k; for (k = 0; k < ev.len; k++) free(ev.items[k]); free(ev.items); }
    \\        else sa_pol_invalid();
    \\        free(ak);
    \\        if (sa_pol_peek(&j) == ',') { j.pos++; continue; }
    \\        sa_pol_expect(&j, '}'); break;
    \\      }
    \\    } else sa_pol_invalid();
    \\    free(key);
    \\    if (sa_pol_peek(&j) == ',') { j.pos++; continue; }
    \\    sa_pol_expect(&j, '}'); break;
    \\  }
    \\  sa_pol_ws(&j); if (j.pos != j.len) sa_pol_invalid();
    \\}
    \\static void sa_pol_audit(const char *catname, const char *resource, const char *decision, const char *source) {
    \\  FILE *f; struct timespec ts; unsigned long long ns; const char *p;
    \\  if (!sa_pol_audit_path) return;
    \\  f = fopen(sa_pol_audit_path, "a"); if (!f) return;
    \\  clock_gettime(CLOCK_REALTIME, &ts);
    \\  ns = (unsigned long long)ts.tv_sec * 1000000000ull + (unsigned long long)ts.tv_nsec;
    \\  fputs("{\"ts_ns\":", f); fprintf(f, "%llu", ns);
    \\  fputs(",\"context\":1,\"category\":\"", f); fputs(catname, f);
    \\  fputs("\",\"resource\":\"", f);
    \\  for (p = resource; *p; p++) { unsigned char c = (unsigned char)*p; if (c == '"' || c == '\\') { fputc('\\', f); fputc(c, f); } else if (c == '\n') fputs("\\n", f); else if (c == '\r') fputs("\\r", f); else if (c == '\t') fputs("\\t", f); else if (c < 0x20) fprintf(f, "\\u%04x", c); else fputc(c, f); }
    \\  fputs("\",\"decision\":\"", f); fputs(decision, f);
    \\  fputs("\",\"source\":\"", f); fputs(source, f);
    \\  fputs("\"}\n", f);
    \\  fclose(f);
    \\}
    \\static void sa_pol_init(void) {
    \\  const char *aa; const char *text; const char *file; int i;
    \\  if (sa_pol_state != 0) return;
    \\  sa_pol_state = 1;
    \\  aa = getenv("SA_POLICY_ALLOW_ALL");
    \\  if (aa && strcmp(aa, "1") == 0) {
    \\    const char *af;
    \\    for (i = 0; i < 6; i++) sa_pol_cats[i].mode = 0;
    \\    sa_pol_state = 2;
    \\    af = getenv("SA_AUDIT_FILE"); if (af) sa_pol_audit_path = sa_pol_strdup_n(af, strlen(af));
    \\    fputs("[sa-policy] allow-all policy engaged via SA_POLICY_ALLOW_ALL (audit trace)\n", stderr);
    \\    sa_pol_audit("run", "SA_POLICY_ALLOW_ALL", "allow-all", "env");
    \\    return;
    \\  }
    \\  text = getenv("SA_POLICY_JSON");
    \\  if (!text) {
    \\    file = getenv("SA_POLICY_FILE");
    \\    if (file) {
    \\      FILE *f = fopen(file, "rb"); long sz; char *buf;
    \\      if (!f) { fputs("[sa-policy] SA_POLICY_FILE is set but cannot be opened\n", stderr); exit(2); }
    \\      if (fseek(f, 0, SEEK_END) != 0) { fclose(f); fputs("[sa-policy] SA_POLICY_FILE cannot be read\n", stderr); exit(2); }
    \\      sz = ftell(f); if (sz < 0) { fclose(f); fputs("[sa-policy] SA_POLICY_FILE cannot be read\n", stderr); exit(2); }
    \\      if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); fputs("[sa-policy] SA_POLICY_FILE cannot be read\n", stderr); exit(2); }
    \\      buf = (char *)malloc((size_t)sz + 1); if (!buf) exit(2);
    \\      if (sz > 0 && fread(buf, 1, (size_t)sz, f) != (size_t)sz) { fclose(f); fputs("[sa-policy] SA_POLICY_FILE cannot be read\n", stderr); exit(2); }
    \\      fclose(f); buf[sz] = 0;
    \\      sa_pol_parse(buf);
    \\      sa_pol_state = 2;
    \\      { const char *af = getenv("SA_AUDIT_FILE"); if (af) sa_pol_audit_path = sa_pol_strdup_n(af, strlen(af)); else if (sa_pol_sink && strncmp(sa_pol_sink, "file://", 7) == 0) sa_pol_audit_path = sa_pol_strdup_n(sa_pol_sink + 7, strlen(sa_pol_sink + 7)); }
    \\      return;
    \\    }
    \\  }
    \\  if (text) {
    \\    sa_pol_parse(text);
    \\    sa_pol_state = 2;
    \\    { const char *af = getenv("SA_AUDIT_FILE"); if (af) sa_pol_audit_path = sa_pol_strdup_n(af, strlen(af)); else if (sa_pol_sink && strncmp(sa_pol_sink, "file://", 7) == 0) sa_pol_audit_path = sa_pol_strdup_n(sa_pol_sink + 7, strlen(sa_pol_sink + 7)); }
    \\    return;
    \\  }
    \\  { const char *req = getenv("SA_POLICY_REQUIRED"); if (req && strcmp(req, "1") == 0) { fputs("[sa-policy] SA_POLICY_REQUIRED is set but no policy was provided (set SA_POLICY_JSON, SA_POLICY_FILE, or SA_POLICY_ALLOW_ALL=1)\n", stderr); exit(1); } }
    \\}
    \\static int sa_pol_list_has(sa_pol_list *l, const char *v) { size_t i; for (i = 0; i < l->len; i++) if (strcmp(l->items[i], v) == 0) return 1; return 0; }
    \\static int sa_pol_fs_allows(sa_pol_list *l, const char *path) {
    \\  size_t i;
    \\  for (i = 0; i < l->len; i++) {
    \\    const char *entry = l->items[i]; size_t plen = strlen(entry);
    \\    while (plen > 0 && entry[plen - 1] == '/') plen--;
    \\    if (strlen(path) == plen && strncmp(path, entry, plen) == 0) return 1;
    \\    if (strlen(path) > plen && strncmp(path, entry, plen) == 0 && path[plen] == '/') return 1;
    \\  }
    \\  return 0;
    \\}
    \\static int sa_pol_ipv4(const char *t, unsigned *out) {
    \\  unsigned v = 0; int count = 0; const char *p = t;
    \\  for (;;) { unsigned oct = 0; int digits = 0; while (*p >= '0' && *p <= '9') { oct = oct * 10 + (unsigned)(*p - '0'); p++; digits++; if (digits > 3) return 0; } if (digits == 0 || oct > 255) return 0; v = v * 256 + oct; count++; if (count == 4) { if (*p != 0) return 0; *out = v; return 1; } if (*p != '.') return 0; p++; }
    \\}
    \\static int sa_pol_net_match(const char *entry, const char *host, unsigned port) {
    \\  const char *colon = strrchr(entry, ':'); const char *slash; size_t hlen; char hbuf[256];
    \\  if (!colon) return 0;
    \\  if (!(colon[1] == '*' && colon[2] == 0)) { unsigned ep = 0; const char *p; for (p = colon + 1; *p; p++) { if (*p < '0' || *p > '9') return 0; ep = ep * 10 + (unsigned)(*p - '0'); } if (ep != port) return 0; }
    \\  hlen = (size_t)(colon - entry); if (hlen >= sizeof(hbuf)) return 0; memcpy(hbuf, entry, hlen); hbuf[hlen] = 0;
    \\  slash = strchr(hbuf, '/');
    \\  if (slash) {
    \\    unsigned prefix_len = 0; const char *p; unsigned network, host_ip; char ipbuf[64]; size_t ilen = (size_t)(slash - hbuf);
    \\    if (ilen >= sizeof(ipbuf)) return 0; memcpy(ipbuf, hbuf, ilen); ipbuf[ilen] = 0;
    \\    for (p = slash + 1; *p; p++) { if (*p < '0' || *p > '9') return 0; prefix_len = prefix_len * 10 + (unsigned)(*p - '0'); }
    \\    if (prefix_len > 32) return 0;
    \\    if (!sa_pol_ipv4(ipbuf, &network)) return 0;
    \\    if (!sa_pol_ipv4(host, &host_ip)) return 0;
    \\    if (prefix_len == 0) return 1;
    \\    { unsigned div = 1u << (32 - prefix_len); return (network / div) == (host_ip / div); }
    \\  }
    \\  { size_t i; if (strlen(host) != hlen) return 0; for (i = 0; i < hlen; i++) { char a = hbuf[i], b = host[i]; if (a >= 'A' && a <= 'Z') a = (char)(a + 32); if (b >= 'A' && b <= 'Z') b = (char)(b + 32); if (a != b) return 0; } return 1; }
    \\}
    \\/* Returns nonzero when the acquisition is allowed. On audit-mode allows
    \\   and on every denial an audit event is written (best-effort). */
    \\static int sa_policy_check(int cat, const char *res, int write, unsigned port) {
    \\  sa_pol_cat *cp; int decision; /* 0 allow, 1 deny, 2 allow_audit, 3 deny_ask */
    \\  char keybuf[1024]; const char *key;
    \\  sa_pol_init();
    \\  if (sa_pol_state == 1) return 1;
    \\  cp = &sa_pol_cats[cat];
    \\  switch (cp->mode) {
    \\    case 0: decision = 0; break;
    \\    case 1: decision = 1; break;
    \\    case 3: decision = 2; break;
    \\    case 4: decision = 3; break;
    \\    default: /* allow-list */
    \\      if (cat == 0) { size_t i; decision = 1; for (i = 0; i < cp->allow.len; i++) if (sa_pol_net_match(cp->allow.items[i], res, port)) { decision = 0; break; } }
    \\      else if (cat == 1) decision = sa_pol_fs_allows(write ? &cp->write : &cp->read, res) ? 0 : 1;
    \\      else if (cat == 2 || cat == 3) decision = sa_pol_list_has(&cp->allow, res) ? 0 : 1;
    \\      else decision = 1;
    \\      break;
    \\  }
    \\  if (cat == 0) { snprintf(keybuf, sizeof(keybuf), "%s:%u", res, port); key = keybuf; }
    \\  else if (cat == 1) { snprintf(keybuf, sizeof(keybuf), "%s:%s", write ? "write" : "read", res); key = keybuf; }
    \\  else if (cat == 2 || cat == 3) key = res;
    \\  else key = sa_pol_cat_names[cat];
    \\  if (decision == 0) return 1;
    \\  if (decision == 2) { sa_pol_audit(sa_pol_cat_names[cat], key, "allow", "policy-audit"); return 1; }
    \\  sa_pol_audit(sa_pol_cat_names[cat], key, "deny", decision == 3 ? "ask-unhandled" : "policy");
    \\  return 0;
    \\}
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
    .{ .name = "sa_nb_buf_find", .code =
    \\typedef struct { sa_u64 h; uint32_t addr; sa_u64 len; } sa_nb_buf_t;
    \\static sa_nb_buf_t sa_nb_bufs[64];
    \\static sa_u64 sa_nb_next = 1;
    \\static sa_nb_buf_t *sa_nb_buf_find(sa_u64 h) { unsigned i; if (h == 0) return 0; for (i = 0; i < 64; i++) if (sa_nb_bufs[i].h == h) return &sa_nb_bufs[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_nb_buf_new", .code =
    \\static sa_u64 sa_nb_buf_new(uint32_t addr, sa_u64 len) { unsigned i; for (i = 0; i < 64; i++) if (sa_nb_bufs[i].h == 0) { sa_u64 h = sa_nb_next++; sa_nb_bufs[i].h = h; sa_nb_bufs[i].addr = addr; sa_nb_bufs[i].len = len; return h; } return 0; }
    , .deps = &.{"sa_nb_buf_find"} },
    .{ .name = "sa_nb_buf_drop", .code =
    \\static int sa_nb_buf_drop(sa_u64 h) { sa_nb_buf_t *b = sa_nb_buf_find(h); if (!b) return 0; b->h = 0; return 1; }
    , .deps = &.{"sa_nb_buf_find"} },
    .{ .name = "sa_nb_crc32", .code =
    \\static uint32_t sa_nb_crc_tab[256];
    \\static int sa_nb_crc_ready = 0;
    \\static uint32_t sa_nb_crc32(uint32_t addr, sa_u64 len) {
    \\  uint32_t c; sa_u64 i; unsigned k;
    \\  if (!sa_nb_crc_ready) { for (k = 0; k < 256; k++) { uint32_t x = k; int j; for (j = 0; j < 8; j++) x = (x & 1) ? (0xEDB88320u ^ (x >> 1)) : (x >> 1); sa_nb_crc_tab[k] = x; } sa_nb_crc_ready = 1; }
    \\  c = 0xFFFFFFFFu;
    \\  for (i = 0; i < len; i++) c = sa_nb_crc_tab[(c ^ sa_mem[addr + i]) & 0xFF] ^ (c >> 8);
    \\  return c ^ 0xFFFFFFFFu;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_nb_adler32", .code =
    \\static uint32_t sa_nb_adler32(uint32_t addr, sa_u64 len) {
    \\  uint32_t a = 1, b = 0; sa_u64 i;
    \\  for (i = 0; i < len; i++) { a += sa_mem[addr + i]; if (a >= 65521) a -= 65521; b += a; if (b >= 65521) b -= 65521; }
    \\  return (b << 16) | a;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_nb_deflate", .code =
    \\static int sa_nb_deflate(int fmt, uint32_t ia, sa_u64 ilen, sa_u64 out_slot) {
    \\  uint32_t oa; sa_u64 cap, pos = 0, off = 0;
    \\  if (fmt < 1 || fmt > 4) return 1;
    \\  if (fmt == 4) return 8;
    \\  cap = ilen + (ilen / 65535 + 1) * 5 + 32;
    \\  oa = (uint32_t)sa_alloc(cap);
    \\  if (fmt == 1) { int k; for (k = 0; k < 10; k++) sa_mem[oa + pos++] = (uint8_t)((k == 0) ? 0x1F : (k == 1) ? 0x8B : (k == 2) ? 8 : 0); }
    \\  else if (fmt == 2) { sa_mem[oa + pos++] = 0x78; sa_mem[oa + pos++] = 0x9C; }
    \\  while (1) {
    \\    sa_u64 chunk = ilen - off; sa_u64 j; int fin; uint16_t nc;
    \\    if (chunk > 65535) chunk = 65535;
    \\    fin = (off + chunk >= ilen);
    \\    sa_mem[oa + pos++] = (uint8_t)(fin ? 1 : 0);
    \\    sa_mem[oa + pos++] = (uint8_t)(chunk & 0xFF); sa_mem[oa + pos++] = (uint8_t)((chunk >> 8) & 0xFF);
    \\    nc = (uint16_t)~(uint16_t)chunk;
    \\    sa_mem[oa + pos++] = (uint8_t)(nc & 0xFF); sa_mem[oa + pos++] = (uint8_t)((nc >> 8) & 0xFF);
    \\    for (j = 0; j < chunk; j++) sa_mem[oa + pos + j] = sa_mem[ia + off + j];
    \\    pos += chunk; off += chunk;
    \\    if (fin) break;
    \\  }
    \\  if (fmt == 1) { uint32_t crc = sa_nb_crc32(ia, ilen); int k; for (k = 0; k < 4; k++) sa_mem[oa + pos++] = (uint8_t)(crc >> (8 * k)); for (k = 0; k < 4; k++) sa_mem[oa + pos++] = (uint8_t)((uint32_t)ilen >> (8 * k)); }
    \\  else if (fmt == 2) { uint32_t ad = sa_nb_adler32(ia, ilen); int k; for (k = 3; k >= 0; k--) sa_mem[oa + pos++] = (uint8_t)(ad >> (8 * k)); }
    \\  { sa_u64 h = sa_nb_buf_new(oa, pos); if (h == 0) return 5; sa_store_u64(out_slot, h); }
    \\  return 0;
    \\}
    , .deps = &.{ "sa_nb_buf_find", "sa_nb_buf_new", "sa_nb_crc32", "sa_nb_adler32", "sa_alloc", "sa_store_u64" } },
    .{ .name = "sa_nb_inflate_stream", .code =
    \\typedef struct { uint32_t addr; sa_u64 len; sa_u64 pos; uint32_t bitbuf; int bitcnt; } sa_nb_bits_t;
    \\static int sa_nb_getbit(sa_nb_bits_t *b) { if (b->bitcnt == 0) { if (b->pos >= b->len) return -1; b->bitbuf = sa_mem[b->addr + b->pos]; b->pos++; b->bitcnt = 8; } { int v = (int)(b->bitbuf & 1u); b->bitbuf >>= 1; b->bitcnt--; return v; } }
    \\static int sa_nb_getbits(sa_nb_bits_t *b, int n) { int v = 0, i; for (i = 0; i < n; i++) { int bit = sa_nb_getbit(b); if (bit < 0) return -1; v |= bit << i; } return v; }
    \\typedef struct { uint16_t counts[16]; uint16_t symbols[288]; } sa_nb_huff_t;
    \\static int sa_nb_huff_build(sa_nb_huff_t *h, const uint8_t *lengths, int n) {
    \\  int len, sym, left; uint16_t offs[16];
    \\  for (len = 0; len < 16; len++) h->counts[len] = 0;
    \\  for (sym = 0; sym < n; sym++) h->counts[lengths[sym]]++;
    \\  if (h->counts[0] == n) return 0;
    \\  left = 1;
    \\  for (len = 1; len < 16; len++) { left <<= 1; left -= h->counts[len]; if (left < 0) return -1; }
    \\  offs[1] = 0;
    \\  for (len = 1; len < 15; len++) offs[len + 1] = offs[len] + h->counts[len];
    \\  for (sym = 0; sym < n; sym++) if (lengths[sym] != 0) h->symbols[offs[lengths[sym]]++] = (uint16_t)sym;
    \\  return 0;
    \\}
    \\static int sa_nb_huff_decode(sa_nb_bits_t *b, const sa_nb_huff_t *h) {
    \\  int len, code = 0, first = 0, index = 0;
    \\  for (len = 1; len <= 15; len++) {
    \\    int bit = sa_nb_getbit(b); int count;
    \\    if (bit < 0) return -1;
    \\    code |= bit;
    \\    count = h->counts[len];
    \\    if (code - count < first) return h->symbols[index + (code - first)];
    \\    index += count; first += count; first <<= 1; code <<= 1;
    \\  }
    \\  return -1;
    \\}
    \\typedef struct { uint32_t addr; sa_u64 cap; sa_u64 len; } sa_nb_out_t;
    \\static int sa_nb_out_put(sa_nb_out_t *o, uint8_t v) {
    \\  if (o->len >= o->cap) { uint32_t na; sa_u64 nc = o->cap ? o->cap * 2 : 4096, j; na = (uint32_t)sa_alloc(nc); for (j = 0; j < o->len; j++) sa_mem[na + j] = sa_mem[o->addr + j]; o->addr = na; o->cap = nc; }
    \\  sa_mem[o->addr + o->len] = v; o->len++; return 0;
    \\}
    \\static int sa_nb_inflate_stream(uint32_t ia, sa_u64 ilen, uint32_t *out_a, sa_u64 *out_n) {
    \\  static const uint16_t lbase[29] = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
    \\  static const uint8_t lext[29] = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
    \\  static const uint16_t dbase[30] = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
    \\  static const uint8_t dext[30] = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};
    \\  sa_nb_bits_t b; sa_nb_out_t o; int fin = 0;
    \\  b.addr = ia; b.len = ilen; b.pos = 0; b.bitbuf = 0; b.bitcnt = 0;
    \\  o.addr = 0; o.cap = 0; o.len = 0;
    \\  while (!fin) {
    \\    int btype = sa_nb_getbits(&b, 3);
    \\    if (btype < 0) return -1;
    \\    fin = btype & 1; btype >>= 1;
    \\    if (btype == 0) {
    \\      uint32_t ln, nn; sa_u64 j;
    \\      b.bitcnt = 0;
    \\      if (b.pos + 4 > b.len) return -1;
    \\      ln = (uint32_t)(sa_mem[b.addr + b.pos] | (sa_mem[b.addr + b.pos + 1] << 8));
    \\      nn = (uint32_t)(sa_mem[b.addr + b.pos + 2] | (sa_mem[b.addr + b.pos + 3] << 8));
    \\      if (ln != (nn ^ 0xFFFFu)) return -1;
    \\      b.pos += 4;
    \\      if (b.pos + ln > b.len) return -1;
    \\      for (j = 0; j < ln; j++) if (sa_nb_out_put(&o, sa_mem[b.addr + b.pos + j])) return -1;
    \\      b.pos += ln;
    \\    } else {
    \\      sa_nb_huff_t lit, dist; uint8_t lengths[320]; int i;
    \\      if (btype == 2) {
    \\        int hlit, hdist, hclen; sa_nb_huff_t cl; uint8_t clens[19];
    \\        static const uint8_t order[19] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};
    \\        hlit = sa_nb_getbits(&b, 5); hdist = sa_nb_getbits(&b, 5); hclen = sa_nb_getbits(&b, 4);
    \\        if (hlit < 0 || hdist < 0 || hclen < 0) return -1;
    \\        hlit += 257; hdist += 1; hclen += 4;
    \\        for (i = 0; i < 19; i++) clens[i] = 0;
    \\        for (i = 0; i < hclen; i++) { int v = sa_nb_getbits(&b, 3); if (v < 0) return -1; clens[order[i]] = (uint8_t)v; }
    \\        if (sa_nb_huff_build(&cl, clens, 19)) return -1;
    \\        i = 0;
    \\        while (i < hlit + hdist) {
    \\          int sym = sa_nb_huff_decode(&b, &cl); if (sym < 0) return -1;
    \\          if (sym < 16) lengths[i++] = (uint8_t)sym;
    \\          else if (sym == 16) { int rep, v; if (i == 0) return -1; v = sa_nb_getbits(&b, 2); if (v < 0) return -1; rep = v + 3; while (rep-- > 0) { if (i >= hlit + hdist) return -1; lengths[i] = lengths[i - 1]; i++; } }
    \\          else if (sym == 17) { int v = sa_nb_getbits(&b, 3); if (v < 0) return -1; v += 3; while (v-- > 0) { if (i >= hlit + hdist) return -1; lengths[i++] = 0; } }
    \\          else { int v = sa_nb_getbits(&b, 7); if (v < 0) return -1; v += 11; while (v-- > 0) { if (i >= hlit + hdist) return -1; lengths[i++] = 0; } }
    \\        }
    \\        if (sa_nb_huff_build(&lit, lengths, hlit)) return -1;
    \\        if (sa_nb_huff_build(&dist, lengths + hlit, hdist)) return -1;
    \\      } else if (btype == 1) {
    \\        for (i = 0; i < 288; i++) lengths[i] = (uint8_t)((i < 144) ? 8 : (i < 256) ? 9 : (i < 280) ? 7 : 8);
    \\        if (sa_nb_huff_build(&lit, lengths, 288)) return -1;
    \\        for (i = 0; i < 30; i++) lengths[i] = 5;
    \\        if (sa_nb_huff_build(&dist, lengths, 30)) return -1;
    \\      } else return -1;
    \\      while (1) {
    \\        int sym = sa_nb_huff_decode(&b, &lit); if (sym < 0) return -1;
    \\        if (sym < 256) { if (sa_nb_out_put(&o, (uint8_t)sym)) return -1; }
    \\        else if (sym == 256) break;
    \\        else {
    \\          int len, dsym, distv, e, v; sa_u64 k, from;
    \\          if (sym > 285) return -1;
    \\          len = lbase[sym - 257]; e = lext[sym - 257];
    \\          if (e) { v = sa_nb_getbits(&b, e); if (v < 0) return -1; len += v; }
    \\          dsym = sa_nb_huff_decode(&b, &dist); if (dsym < 0 || dsym > 29) return -1;
    \\          distv = dbase[dsym]; e = dext[dsym];
    \\          if (e) { v = sa_nb_getbits(&b, e); if (v < 0) return -1; distv += v; }
    \\          if ((sa_u64)distv > o.len) return -1;
    \\          from = o.len - (sa_u64)distv;
    \\          for (k = 0; k < (sa_u64)len; k++) if (sa_nb_out_put(&o, sa_mem[o.addr + from + k])) return -1;
    \\        }
    \\      }
    \\    }
    \\  }
    \\  *out_a = o.addr; *out_n = o.len;
    \\  return 0;
    \\}
    , .deps = &.{"sa_alloc"} },
    .{ .name = "sa_nb_undeflate", .code =
    \\static int sa_nb_undeflate(int fmt, uint32_t ia, sa_u64 ilen, sa_u64 out_slot) {
    \\  uint32_t start = ia; sa_u64 avail = ilen; uint32_t crc_want = 0, ad_want = 0, oa = 0; sa_u64 on = 0, h; int have_crc = 0, have_ad = 0;
    \\  if (fmt < 1 || fmt > 4) return 1;
    \\  if (fmt == 4) return 8;
    \\  if (fmt == 1) {
    \\    uint8_t flg; uint32_t p = ia; sa_u64 rem = ilen; uint32_t isize;
    \\    if (rem < 18) return 6;
    \\    if (sa_mem[p] != 0x1F || sa_mem[p + 1] != 0x8B || sa_mem[p + 2] != 8) return 6;
    \\    flg = sa_mem[p + 3]; p += 10; rem -= 10;
    \\    if (flg & 4) { uint32_t xl; if (rem < 2) return 6; xl = (uint32_t)(sa_mem[p] | (sa_mem[p + 1] << 8)); p += 2; rem -= 2; if (rem < xl) return 6; p += xl; rem -= xl; }
    \\    if (flg & 8) { while (1) { if (rem == 0) return 6; if (sa_mem[p] == 0) { p++; rem--; break; } p++; rem--; } }
    \\    if (flg & 16) { while (1) { if (rem == 0) return 6; if (sa_mem[p] == 0) { p++; rem--; break; } p++; rem--; } }
    \\    if (flg & 2) { if (rem < 2) return 6; p += 2; rem -= 2; }
    \\    if (rem < 8) return 6;
    \\    { uint32_t ep = p + (uint32_t)(rem - 8);
    \\      crc_want = (uint32_t)(sa_mem[ep] | (sa_mem[ep + 1] << 8) | ((uint32_t)sa_mem[ep + 2] << 16) | ((uint32_t)sa_mem[ep + 3] << 24));
    \\      isize = (uint32_t)(sa_mem[ep + 4] | (sa_mem[ep + 5] << 8) | ((uint32_t)sa_mem[ep + 6] << 16) | ((uint32_t)sa_mem[ep + 7] << 24));
    \\      have_crc = 1;
    \\      if (sa_nb_inflate_stream(p, rem - 8, &oa, &on)) return 6;
    \\      if ((uint32_t)on != isize) return 6;
    \\    }
    \\    if (sa_nb_crc32(oa, on) != crc_want) return 6;
    \\    (void)have_ad;
    \\    h = sa_nb_buf_new(oa, on); if (h == 0) return 5;
    \\    sa_store_u64(out_slot, h);
    \\    return 0;
    \\  }
    \\  if (fmt == 2) {
    \\    uint32_t cmf, flg;
    \\    if (ilen < 6) return 6;
    \\    cmf = sa_mem[ia]; flg = sa_mem[ia + 1];
    \\    if (((cmf << 8) + flg) % 31 != 0 || (cmf & 0x0F) != 8) return 6;
    \\    if (flg & 0x20) return 6;
    \\    ad_want = ((uint32_t)sa_mem[ia + ilen - 4] << 24) | ((uint32_t)sa_mem[ia + ilen - 3] << 16) | ((uint32_t)sa_mem[ia + ilen - 2] << 8) | (uint32_t)sa_mem[ia + ilen - 1];
    \\    if (sa_nb_inflate_stream(ia + 2, ilen - 6, &oa, &on)) return 6;
    \\    if (sa_nb_adler32(oa, on) != ad_want) return 6;
    \\    h = sa_nb_buf_new(oa, on); if (h == 0) return 5;
    \\    sa_store_u64(out_slot, h);
    \\    return 0;
    \\  }
    \\  start = ia; avail = ilen;
    \\  if (sa_nb_inflate_stream(start, avail, &oa, &on)) return 6;
    \\  h = sa_nb_buf_new(oa, on); if (h == 0) return 5;
    \\  sa_store_u64(out_slot, h);
    \\  return 0;
    \\}
    , .deps = &.{ "sa_nb_buf_find", "sa_nb_buf_new", "sa_nb_inflate_stream", "sa_nb_crc32", "sa_nb_adler32", "sa_store_u64" } },
    .{ .name = "sa_mp_find", .code =
    \\typedef struct { sa_u64 h; int kind; uint32_t body_a; sa_u64 body_n; uint8_t bnd[96]; sa_u64 bnd_n; uint32_t acc_a; sa_u64 acc_n; sa_u64 acc_cap; } sa_mp_t;
    \\static sa_mp_t sa_mp_tab[32];
    \\static sa_u64 sa_mp_next = 1;
    \\static sa_mp_t *sa_mp_find(sa_u64 h) { unsigned i; if (h == 0) return 0; for (i = 0; i < 32; i++) if (sa_mp_tab[i].h == h) return &sa_mp_tab[i]; return 0; }
    \\static sa_mp_t *sa_mp_slot(void) { unsigned i; for (i = 0; i < 32; i++) if (sa_mp_tab[i].h == 0) { sa_mp_t *mp = &sa_mp_tab[i]; mp->h = sa_mp_next++; mp->kind = 0; mp->body_a = 0; mp->body_n = 0; mp->bnd_n = 0; mp->acc_a = 0; mp->acc_n = 0; mp->acc_cap = 0; return mp; } return 0; }
    \\static int sa_mp_bnd_eq(sa_mp_t *mp, uint32_t a) { sa_u64 i; for (i = 0; i < mp->bnd_n; i++) if (sa_mem[a + i] != mp->bnd[i]) return 0; return 1; }
    \\static int sa_mp_is_delim(sa_mp_t *mp, sa_u64 off) { if (off + 2 + mp->bnd_n > mp->body_n) return 0; if (sa_mem[mp->body_a + off] != '-' || sa_mem[mp->body_a + off + 1] != '-') return 0; return sa_mp_bnd_eq(mp, mp->body_a + (uint32_t)off + 2); }
    \\static int sa_mp_ci_at(uint32_t a, sa_u64 n, const char *s) { sa_u64 i, m = 0; while (s[m]) m++; if (n < m) return 0; for (i = 0; i < m; i++) { uint8_t x = sa_mem[a + i]; if (x >= 'A' && x <= 'Z') x = (uint8_t)(x + 32); if (x != (uint8_t)s[i]) return 0; } return 1; }
    , .deps = &.{} },
    .{ .name = "sa_mp_seek", .code =
    \\static int sa_mp_seek(sa_mp_t *mp, sa_u64 idx, sa_u64 *so, sa_u64 *sn) {
    \\  sa_u64 off = 0, cur = 0;
    \\  if (!sa_mp_is_delim(mp, 0)) return 0;
    \\  while (1) {
    \\    sa_u64 p = off + 2 + mp->bnd_n;
    \\    if (p + 2 <= mp->body_n && sa_mem[mp->body_a + p] == '-' && sa_mem[mp->body_a + p + 1] == '-') return 0;
    \\    if (p + 2 > mp->body_n || sa_mem[mp->body_a + p] != '\r' || sa_mem[mp->body_a + p + 1] != '\n') return 0;
    \\    { sa_u64 seg_start = p + 2, q = seg_start; int found = 0;
    \\      while (q + 4 + mp->bnd_n <= mp->body_n) {
    \\        if (sa_mem[mp->body_a + q] == '\r' && sa_mem[mp->body_a + q + 1] == '\n' && sa_mem[mp->body_a + q + 2] == '-' && sa_mem[mp->body_a + q + 3] == '-' && sa_mp_bnd_eq(mp, mp->body_a + (uint32_t)q + 4)) { found = 1; break; }
    \\        q++;
    \\      }
    \\      if (!found) return 0;
    \\      if (cur == idx) { *so = seg_start; *sn = q - seg_start; return 1; }
    \\      cur++; off = q + 2;
    \\    }
    \\  }
    \\}
    , .deps = &.{"sa_mp_find"} },
    .{ .name = "sa_mp_split", .code =
    \\static int sa_mp_split(sa_mp_t *mp, sa_u64 so, sa_u64 sn, sa_u64 *bo, sa_u64 *bn) {
    \\  sa_u64 i;
    \\  if (sn >= 4) for (i = 0; i + 4 <= sn; i++) { uint32_t a = mp->body_a + (uint32_t)(so + i); if (sa_mem[a] == '\r' && sa_mem[a + 1] == '\n' && sa_mem[a + 2] == '\r' && sa_mem[a + 3] == '\n') { *bo = so + i + 4; *bn = sn - (i + 4); return 1; } }
    \\  return 0;
    \\}
    , .deps = &.{"sa_mp_find"} },
    .{ .name = "sa_mp_hdr", .code =
    \\static int sa_mp_hdr(sa_mp_t *mp, sa_u64 so, sa_u64 hn, const char *name, sa_u64 *va, sa_u64 *vn) {
    \\  sa_u64 ls = so, end = so + hn, m = 0;
    \\  while (name[m]) m++;
    \\  while (ls < end) {
    \\    sa_u64 le = ls, i, colon = 0; int has = 0;
    \\    while (le < end && !(sa_mem[mp->body_a + le] == '\r' && le + 1 < end && sa_mem[mp->body_a + le + 1] == '\n')) le++;
    \\    for (i = ls; i < le; i++) if (sa_mem[mp->body_a + i] == ':') { colon = i; has = 1; break; }
    \\    if (has && colon - ls == m) {
    \\      int eq = 1;
    \\      for (i = 0; i < m; i++) { uint8_t x = sa_mem[mp->body_a + ls + i]; if (x >= 'A' && x <= 'Z') x = (uint8_t)(x + 32); if (x != (uint8_t)name[i]) { eq = 0; break; } }
    \\      if (eq) { sa_u64 vs = colon + 1; while (vs < le && (sa_mem[mp->body_a + vs] == ' ' || sa_mem[mp->body_a + vs] == '\t')) vs++; *va = mp->body_a + vs; *vn = le - vs; return 1; }
    \\    }
    \\    ls = le + 2;
    \\  }
    \\  return 0;
    \\}
    \\static int sa_mp_hdr_guest(sa_mp_t *mp, sa_u64 so, sa_u64 hn, uint32_t na, sa_u64 nn, sa_u64 *va, sa_u64 *vn) {
    \\  sa_u64 ls = so, end = so + hn;
    \\  while (ls < end) {
    \\    sa_u64 le = ls, i, colon = 0; int has = 0;
    \\    while (le < end && !(sa_mem[mp->body_a + le] == '\r' && le + 1 < end && sa_mem[mp->body_a + le + 1] == '\n')) le++;
    \\    for (i = ls; i < le; i++) if (sa_mem[mp->body_a + i] == ':') { colon = i; has = 1; break; }
    \\    if (has && colon - ls == nn) {
    \\      int eq = 1;
    \\      for (i = 0; i < nn; i++) { uint8_t x = sa_mem[mp->body_a + ls + i]; uint8_t y = sa_mem[na + i]; if (x >= 'A' && x <= 'Z') x = (uint8_t)(x + 32); if (y >= 'A' && y <= 'Z') y = (uint8_t)(y + 32); if (x != y) { eq = 0; break; } }
    \\      if (eq) { sa_u64 vs = colon + 1; while (vs < le && (sa_mem[mp->body_a + vs] == ' ' || sa_mem[mp->body_a + vs] == '\t')) vs++; *va = mp->body_a + vs; *vn = le - vs; return 1; }
    \\    }
    \\    ls = le + 2;
    \\  }
    \\  return 0;
    \\}
    , .deps = &.{"sa_mp_find"} },
    .{ .name = "sa_mp_param", .code =
    \\static int sa_mp_param(sa_u64 va, sa_u64 vn, const char *key, sa_u64 *pa, sa_u64 *pn) {
    \\  sa_u64 pos = 0, kl = 0; int first = 1;
    \\  while (key[kl]) kl++;
    \\  while (pos <= vn) {
    \\    sa_u64 te = pos, ts, tn;
    \\    while (te < vn && sa_mem[va + te] != ';') te++;
    \\    ts = pos; tn = te - pos;
    \\    while (tn > 0 && (sa_mem[va + ts] == ' ' || sa_mem[va + ts] == '\t')) { ts++; tn--; }
    \\    while (tn > 0 && (sa_mem[va + ts + tn - 1] == ' ' || sa_mem[va + ts + tn - 1] == '\t')) tn--;
    \\    if (!first && tn > kl && sa_mp_ci_at((uint32_t)(va + ts), kl, key) && sa_mem[va + ts + kl] == '=') {
    \\      sa_u64 vs = ts + kl + 1, vl = tn - kl - 1;
    \\      while (vl > 0 && sa_mem[va + vs] == ' ') { vs++; vl--; }
    \\      if (vl >= 2 && sa_mem[va + vs] == '"' && sa_mem[va + vs + vl - 1] == '"') { vs++; vl -= 2; }
    \\      *pa = va + vs; *pn = vl; return 1;
    \\    }
    \\    first = 0;
    \\    if (te >= vn) break;
    \\    pos = te + 1;
    \\  }
    \\  return 0;
    \\}
    , .deps = &.{"sa_mp_find"} },
    .{ .name = "sa_mp_writeout", .code =
    \\static int sa_mp_writeout(uint32_t va, sa_u64 vn, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_u64 i; sa_store_u64(ol, vn); if (cap < vn) return 9;
    \\  for (i = 0; i < vn; i++) sa_mem[(uint32_t)ov + i] = sa_mem[va + i];
    \\  return 0;
    \\}
    \\static int sa_mp_writeout_host(const uint8_t *v, sa_u64 vn, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_u64 i; sa_store_u64(ol, vn); if (cap < vn) return 9;
    \\  for (i = 0; i < vn; i++) sa_mem[(uint32_t)ov + i] = v[i];
    \\  return 0;
    \\}
    , .deps = &.{"sa_store_u64"} },
    .{ .name = "sa_mp_parse", .code =
    \\static int sa_mp_parse(sa_u64 body_a, sa_u64 body_n, sa_u64 ct_a, sa_u64 ct_n, sa_u64 out_slot) {
    \\  sa_u64 i, vs = 0, vn = 0; int found = 0;
    \\  for (i = 0; i + 9 <= ct_n; i++) if (sa_mp_ci_at((uint32_t)(ct_a + i), 9, "boundary=")) { vs = ct_a + i + 9; found = 1; break; }
    \\  if (!found) return 1;
    \\  { sa_u64 e = vs; sa_mp_t *mp;
    \\    while (e < ct_a + ct_n && sa_mem[e] != ';') e++;
    \\    vn = e - vs;
    \\    while (vn > 0 && (sa_mem[vs] == ' ' || sa_mem[vs] == '"')) { vs++; vn--; }
    \\    while (vn > 0 && (sa_mem[vs + vn - 1] == ' ' || sa_mem[vs + vn - 1] == '"')) vn--;
    \\    if (vn == 0 || vn > 95) return 1;
    \\    mp = sa_mp_slot(); if (!mp) return 5;
    \\    mp->kind = 1; mp->body_a = (uint32_t)body_a; mp->body_n = body_n;
    \\    for (i = 0; i < vn; i++) mp->bnd[i] = sa_mem[vs + i];
    \\    mp->bnd_n = vn;
    \\    if (!sa_mp_is_delim(mp, 0)) { mp->h = 0; return 1; }
    \\    sa_store_u64(out_slot, mp->h);
    \\    return 0;
    \\  }
    \\}
    , .deps = &.{ "sa_mp_find", "sa_store_u64" } },
    .{ .name = "sa_mp_field", .code =
    \\static int sa_mp_field(sa_u64 h, sa_u64 idx, int kind, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_mp_t *mp = sa_mp_find(h); sa_u64 so, sn, bo, bn, va, vn;
    \\  if (!mp) return 3;
    \\  if (!sa_mp_seek(mp, idx, &so, &sn)) return 3;
    \\  if (!sa_mp_split(mp, so, sn, &bo, &bn)) return 3;
    \\  if (kind == 2) { if (!sa_mp_hdr(mp, so, bo - so, "content-type", &va, &vn)) return 100; return sa_mp_writeout((uint32_t)va, vn, ov, ol, cap); }
    \\  { sa_u64 pa, pn;
    \\    if (!sa_mp_hdr(mp, so, bo - so, "content-disposition", &va, &vn)) return 100;
    \\    if (!sa_mp_param(va, vn, kind == 0 ? "name" : "filename", &pa, &pn)) return 100;
    \\    return sa_mp_writeout((uint32_t)pa, pn, ov, ol, cap); }
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_seek", "sa_mp_split", "sa_mp_hdr", "sa_mp_param", "sa_mp_writeout" } },
    .{ .name = "sa_mp_header", .code =
    \\static int sa_mp_header(sa_u64 h, sa_u64 idx, sa_u64 na, sa_u64 nn, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_mp_t *mp = sa_mp_find(h); sa_u64 so, sn, bo, bn, va, vn;
    \\  if (!mp) return 3;
    \\  if (!sa_mp_seek(mp, idx, &so, &sn)) return 3;
    \\  if (!sa_mp_split(mp, so, sn, &bo, &bn)) return 3;
    \\  if (!sa_mp_hdr_guest(mp, so, bo - so, (uint32_t)na, nn, &va, &vn)) return 100;
    \\  return sa_mp_writeout((uint32_t)va, vn, ov, ol, cap);
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_seek", "sa_mp_split", "sa_mp_hdr", "sa_mp_writeout" } },
    .{ .name = "sa_mp_part_body", .code =
    \\static int sa_mp_part_body(sa_u64 h, sa_u64 idx, sa_u64 op, sa_u64 ol) {
    \\  sa_mp_t *mp = sa_mp_find(h); sa_u64 so, sn, bo, bn;
    \\  if (!mp) return 3;
    \\  if (!sa_mp_seek(mp, idx, &so, &sn)) return 3;
    \\  if (!sa_mp_split(mp, so, sn, &bo, &bn)) return 3;
    \\  sa_store_u64(op, mp->body_a + bo); sa_store_u64(ol, bn);
    \\  return 0;
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_seek", "sa_mp_split", "sa_store_u64" } },
    .{ .name = "sa_mp_acc", .code =
    \\static int sa_mp_reserve(sa_mp_t *mp, sa_u64 extra) {
    \\  if (mp->acc_n + extra > mp->acc_cap) { uint32_t na; sa_u64 nc = mp->acc_cap ? mp->acc_cap : 1024, i; while (nc < mp->acc_n + extra) nc *= 2; na = (uint32_t)sa_alloc(nc); for (i = 0; i < mp->acc_n; i++) sa_mem[na + i] = sa_mem[mp->acc_a + i]; mp->acc_a = na; mp->acc_cap = nc; }
    \\  return 0;
    \\}
    \\static int sa_mp_acc(sa_mp_t *mp, uint32_t a, sa_u64 n) { sa_u64 i; sa_mp_reserve(mp, n); for (i = 0; i < n; i++) sa_mem[mp->acc_a + mp->acc_n + i] = sa_mem[a + i]; mp->acc_n += n; return 0; }
    \\static int sa_mp_accs(sa_mp_t *mp, const char *s) { sa_u64 i, n = 0; while (s[n]) n++; sa_mp_reserve(mp, n); for (i = 0; i < n; i++) sa_mem[mp->acc_a + mp->acc_n + i] = (uint8_t)s[i]; mp->acc_n += n; return 0; }
    \\static int sa_mp_accb(sa_mp_t *mp) { sa_u64 i; sa_mp_reserve(mp, mp->bnd_n); for (i = 0; i < mp->bnd_n; i++) sa_mem[mp->acc_a + mp->acc_n + i] = mp->bnd[i]; mp->acc_n += mp->bnd_n; return 0; }
    , .deps = &.{ "sa_mp_find", "sa_alloc" } },
    .{ .name = "sa_mp_builder_new", .code =
    \\static int sa_mp_builder_new(sa_u64 bnd_a, sa_u64 bnd_n, sa_u64 out_slot) {
    \\  sa_mp_t *mp = sa_mp_slot(); sa_u64 i;
    \\  if (!mp) return 5;
    \\  mp->kind = 2;
    \\  if (bnd_n == 0) {
    \\    const char *pfx = "----sa-std-multipart-c-"; sa_u64 hv = mp->h; char tmp[24]; int nd = 0;
    \\    mp->bnd_n = 0;
    \\    while (*pfx) mp->bnd[mp->bnd_n++] = (uint8_t)*pfx++;
    \\    if (hv == 0) tmp[nd++] = '0';
    \\    while (hv) { tmp[nd++] = (char)('0' + (hv % 10)); hv /= 10; }
    \\    while (nd > 0) mp->bnd[mp->bnd_n++] = (uint8_t)tmp[--nd];
    \\  } else {
    \\    if (bnd_n > 95) { mp->h = 0; return 1; }
    \\    for (i = 0; i < bnd_n; i++) mp->bnd[i] = sa_mem[bnd_a + i];
    \\    mp->bnd_n = bnd_n;
    \\  }
    \\  sa_store_u64(out_slot, mp->h);
    \\  return 0;
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_acc", "sa_store_u64" } },
    .{ .name = "sa_mp_add_field", .code =
    \\static int sa_mp_add_field(sa_u64 h, sa_u64 na, sa_u64 nn, sa_u64 va, sa_u64 vn, int is_file, sa_u64 fa, sa_u64 fnn, sa_u64 ca, sa_u64 cn, sa_u64 da, sa_u64 dn) {
    \\  sa_mp_t *mp = sa_mp_find(h);
    \\  if (!mp || mp->kind != 2) return 3;
    \\  if (mp->acc_n > 0) sa_mp_accs(mp, "\r\n"); sa_mp_accs(mp, "--"); sa_mp_accb(mp); sa_mp_accs(mp, "\r\nContent-Disposition: form-data; name=\"");
    \\  sa_mp_acc(mp, (uint32_t)na, nn);
    \\  sa_mp_accs(mp, "\"");
    \\  if (is_file) { sa_mp_accs(mp, "; filename=\""); sa_mp_acc(mp, (uint32_t)fa, fnn); sa_mp_accs(mp, "\""); }
    \\  sa_mp_accs(mp, "\r\n");
    \\  if (is_file) { sa_mp_accs(mp, "Content-Type: "); sa_mp_acc(mp, (uint32_t)ca, cn); sa_mp_accs(mp, "\r\n"); }
    \\  sa_mp_accs(mp, "\r\n");
    \\  sa_mp_acc(mp, is_file ? (uint32_t)da : (uint32_t)va, is_file ? dn : vn);
    \\  return 0;
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_acc" } },
    .{ .name = "sa_mp_builder_finish", .code =
    \\static int sa_mp_builder_finish(sa_u64 h, sa_u64 out_slot) {
    \\  sa_mp_t *mp = sa_mp_find(h); sa_u64 bh;
    \\  if (!mp || mp->kind != 2) return 3;
    \\  sa_mp_accs(mp, "\r\n--"); sa_mp_accb(mp); sa_mp_accs(mp, "--\r\n");
    \\  bh = sa_nb_buf_new(mp->acc_a, mp->acc_n);
    \\  if (bh == 0) return 5;
    \\  mp->h = 0;
    \\  sa_store_u64(out_slot, bh);
    \\  return 0;
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_acc", "sa_nb_buf_find", "sa_nb_buf_new", "sa_store_u64" } },
    .{ .name = "sa_mp_bnd_out", .code =
    \\static int sa_mp_bnd_out(sa_u64 h, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_mp_t *mp = sa_mp_find(h);
    \\  if (!mp) return 3;
    \\  return sa_mp_writeout_host(mp->bnd, mp->bnd_n, ov, ol, cap);
    \\}
    , .deps = &.{ "sa_mp_find", "sa_mp_writeout" } },
    .{ .name = "sa_mp_ctype_out", .code =
    \\static int sa_mp_ctype_out(sa_u64 h, sa_u64 ov, sa_u64 ol, sa_u64 cap) {
    \\  sa_mp_t *mp = sa_mp_find(h); const char *pfx = "multipart/form-data; boundary="; sa_u64 pn = 0, total, i; uint32_t t;
    \\  if (!mp) return 3;
    \\  while (pfx[pn]) pn++;
    \\  total = pn + mp->bnd_n;
    \\  sa_store_u64(ol, total);
    \\  if (cap < total) return 9;
    \\  t = (uint32_t)ov;
    \\  for (i = 0; i < pn; i++) sa_mem[t + i] = (uint8_t)pfx[i];
    \\  for (i = 0; i < mp->bnd_n; i++) sa_mem[t + pn + i] = mp->bnd[i];
    \\  return 0;
    \\}
    , .deps = &.{ "sa_mp_find", "sa_store_u64" } },
    .{ .name = "sa_nb_ws_opcode_get", .code =
    \\typedef struct { sa_u64 h; int opcode; int closed; } sa_nb_ws_t;
    \\static sa_nb_ws_t sa_nb_ws_tab[32];
    \\static sa_nb_ws_t *sa_nb_ws_rec(sa_u64 h) { unsigned i; for (i = 0; i < 32; i++) if (sa_nb_ws_tab[i].h == h) return &sa_nb_ws_tab[i]; return 0; }
    \\static int sa_nb_ws_opcode_get(sa_u64 h) { sa_nb_ws_t *r = sa_nb_ws_rec(h); return r ? r->opcode : 2; }
    , .deps = &.{} },
    .{ .name = "sa_nb_ws_closed_get", .code =
    \\static int sa_nb_ws_closed_get(sa_u64 h) { sa_nb_ws_t *r = sa_nb_ws_rec(h); return r ? r->closed : 0; }
    , .deps = &.{"sa_nb_ws_opcode_get"} },
    .{ .name = "sa_nb_ws_meta_set", .code =
    \\static void sa_nb_ws_meta_set(sa_u64 h, int opcode, int closed) {
    \\  sa_nb_ws_t *r = sa_nb_ws_rec(h); unsigned i;
    \\  if (!r) { for (i = 0; i < 32; i++) if (sa_nb_ws_tab[i].h == 0) { r = &sa_nb_ws_tab[i]; r->h = h; r->opcode = 2; r->closed = 0; break; } }
    \\  if (!r) return;
    \\  if (opcode >= 0) r->opcode = opcode;
    \\  if (closed >= 0) r->closed = closed;
    \\}
    , .deps = &.{"sa_nb_ws_opcode_get"} },
    .{ .name = "sa_nb_ws_meta_clear", .code =
    \\static void sa_nb_ws_meta_clear(sa_u64 h) { sa_nb_ws_t *r = sa_nb_ws_rec(h); if (r) r->h = 0; }
    , .deps = &.{"sa_nb_ws_opcode_get"} },
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
    .{ .name = "sa_mkdir_wrap", .code =
    \\static int sa_mkdir_wrap(const uint8_t *p) { return mkdir((const char *)p, 0777); }
    , .deps = &.{} },
    .{ .name = "SA_ROTR32", .code =
    \\#define SA_ROTR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
    , .deps = &.{} },
    .{ .name = "SA_ROTL32", .code =
    \\#define SA_ROTL32(x, n) (((x) << (n)) | ((x) >> (32 - (n))))
    , .deps = &.{} },
    .{ .name = "SA_ROTR64", .code =
    \\#define SA_ROTR64(x, n) (((x) >> (n)) | ((x) << (64 - (n))))
    , .deps = &.{} },
    .{ .name = "sa_access_wrap", .code =
    \\static int sa_access_wrap(const uint8_t *p) { return access((const char *)p, F_OK); }
    , .deps = &.{} },
    .{ .name = "sa_sha256_block", .code =
    \\static void sa_sha256_block(uint32_t st[8], const uint8_t *p) {
    \\  static const uint32_t sa_sha256_k[64] = {
    \\  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    \\  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    \\  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    \\  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    \\  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    \\  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    \\  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    \\  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
    \\  uint32_t w[64]; int i;
    \\  for (i = 0; i < 16; i++) w[i] = ((uint32_t)p[i*4] << 24) | ((uint32_t)p[i*4+1] << 16) | ((uint32_t)p[i*4+2] << 8) | p[i*4+3];
    \\  for (i = 16; i < 64; i++) { uint32_t s0 = SA_ROTR32(w[i-15], 7) ^ SA_ROTR32(w[i-15], 18) ^ (w[i-15] >> 3); uint32_t s1 = SA_ROTR32(w[i-2], 17) ^ SA_ROTR32(w[i-2], 19) ^ (w[i-2] >> 10); w[i] = w[i-16] + s0 + w[i-7] + s1; }
    \\  uint32_t a=st[0],b=st[1],c=st[2],d=st[3],e=st[4],f=st[5],g=st[6],h=st[7];
    \\  for (i = 0; i < 64; i++) { uint32_t S1 = SA_ROTR32(e,6)^SA_ROTR32(e,11)^SA_ROTR32(e,25); uint32_t ch = (e&f)^(~e&g); uint32_t t1 = h+S1+ch+sa_sha256_k[i]+w[i]; uint32_t S0 = SA_ROTR32(a,2)^SA_ROTR32(a,13)^SA_ROTR32(a,22); uint32_t mj = (a&b)^(a&c)^(b&c); uint32_t t2 = S0+mj; h=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2; }
    \\  st[0]+=a; st[1]+=b; st[2]+=c; st[3]+=d; st[4]+=e; st[5]+=f; st[6]+=g; st[7]+=h;
    \\}
    , .deps = &.{"SA_ROTR32"} },
    .{ .name = "sa_sha256", .code =
    \\static void sa_sha256(const uint8_t *msg, size_t len, uint8_t out[32]) {
    \\  uint32_t st[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    \\  uint8_t blk[64]; size_t i, off = 0;
    \\  uint64_t bitlen = (uint64_t)len * 8;
    \\  while (len - off >= 64) { sa_sha256_block(st, msg + off); off += 64; }
    \\  size_t rem = len - off;
    \\  for (i = 0; i < rem; i++) blk[i] = msg[off + i];
    \\  blk[rem] = 0x80;
    \\  if (rem + 1 + 8 > 64) { for (i = rem + 1; i < 64; i++) blk[i] = 0; sa_sha256_block(st, blk); for (i = 0; i < 56; i++) blk[i] = 0; }
    \\  else { for (i = rem + 1; i < 56; i++) blk[i] = 0; }
    \\  for (i = 0; i < 8; i++) blk[56 + i] = (uint8_t)(bitlen >> (56 - i * 8));
    \\  sa_sha256_block(st, blk);
    \\  for (i = 0; i < 8; i++) { out[i*4] = (uint8_t)(st[i] >> 24); out[i*4+1] = (uint8_t)(st[i] >> 16); out[i*4+2] = (uint8_t)(st[i] >> 8); out[i*4+3] = (uint8_t)st[i]; }
    \\}
    , .deps = &.{"sa_sha256_block"} },
    .{ .name = "sa_sha512_block", .code =
    \\static void sa_sha512_block(uint64_t st[8], const uint8_t *p) {
    \\  static const uint64_t sa_sha512_k[80] = {
    \\  0x428a2f98d728ae22ULL,0x7137449123ef65cdULL,0xb5c0fbcfec4d3b2fULL,0xe9b5dba58189dbbcULL,0x3956c25bf348b538ULL,0x59f111f1b605d019ULL,0x923f82a4af194f9bULL,0xab1c5ed5da6d8118ULL,
    \\  0xd807aa98a3030242ULL,0x12835b0145706fbeULL,0x243185be4ee4b28cULL,0x550c7dc3d5ffb4e2ULL,0x72be5d74f27b896fULL,0x80deb1fe3b1696b1ULL,0x9bdc06a725c71235ULL,0xc19bf174cf692694ULL,
    \\  0xe49b69c19ef14ad2ULL,0xefbe4786384f25e3ULL,0x0fc19dc68b8cd5b5ULL,0x240ca1cc77ac9c65ULL,0x2de92c6f592b0275ULL,0x4a7484aa6ea6e483ULL,0x5cb0a9dcbd41fbd4ULL,0x76f988da831153b5ULL,
    \\  0x983e5152ee66dfabULL,0xa831c66d2db43210ULL,0xb00327c898fb213fULL,0xbf597fc7beef0ee4ULL,0xc6e00bf33da88fc2ULL,0xd5a79147930aa725ULL,0x06ca6351e003826fULL,0x142929670a0e6e70ULL,
    \\  0x27b70a8546d22ffcULL,0x2e1b21385c26c926ULL,0x4d2c6dfc5ac42aedULL,0x53380d139d95b3dfULL,0x650a73548baf63deULL,0x766a0abb3c77b2a8ULL,0x81c2c92e47edaee6ULL,0x92722c851482353bULL,
    \\  0xa2bfe8a14cf10364ULL,0xa81a664bbc423001ULL,0xc24b8b70d0f89791ULL,0xc76c51a30654be30ULL,0xd192e819d6ef5218ULL,0xd69906245565a910ULL,0xf40e35855771202aULL,0x106aa07032bbd1b8ULL,
    \\  0x19a4c116b8d2d0c8ULL,0x1e376c085141ab53ULL,0x2748774cdf8eeb99ULL,0x34b0bcb5e19b48a8ULL,0x391c0cb3c5c95a63ULL,0x4ed8aa4ae3418acbULL,0x5b9cca4f7763e373ULL,0x682e6ff3d6b2b8a3ULL,
    \\  0x748f82ee5defb2fcULL,0x78a5636f43172f60ULL,0x84c87814a1f0ab72ULL,0x8cc702081a6439ecULL,0x90befffa23631e28ULL,0xa4506cebde82bde9ULL,0xbef9a3f7b2c67915ULL,0xc67178f2e372532bULL,
    \\  0xca273eceea26619cULL,0xd186b8c721c0c207ULL,0xeada7dd6cde0eb1eULL,0xf57d4f7fee6ed178ULL,0x06f067aa72176fbaULL,0x0a637dc5a2c898a6ULL,0x113f9804bef90daeULL,0x1b710b35131c471bULL,
    \\  0x28db77f523047d84ULL,0x32caab7b40c72493ULL,0x3c9ebe0a15c9bebcULL,0x431d67c49c100d4cULL,0x4cc5d4becb3e42b6ULL,0x597f299cfc657e2aULL,0x5fcb6fab3ad6faecULL,0x6c44198c4a475817ULL};
    \\  uint64_t w[80]; int i; int j;
    \\  for (i = 0; i < 16; i++) { w[i] = 0; for (j = 0; j < 8; j++) w[i] |= (uint64_t)p[i*8+j] << (56 - j * 8); }
    \\  for (i = 16; i < 80; i++) { uint64_t s0 = SA_ROTR64(w[i-15],1)^SA_ROTR64(w[i-15],8)^(w[i-15]>>7); uint64_t s1 = SA_ROTR64(w[i-2],19)^SA_ROTR64(w[i-2],61)^(w[i-2]>>6); w[i] = w[i-16]+s0+w[i-7]+s1; }
    \\  uint64_t a=st[0],b=st[1],c=st[2],d=st[3],e=st[4],f=st[5],g=st[6],h=st[7];
    \\  for (i = 0; i < 80; i++) { uint64_t S1 = SA_ROTR64(e,14)^SA_ROTR64(e,18)^SA_ROTR64(e,41); uint64_t ch = (e&f)^(~e&g); uint64_t t1 = h+S1+ch+sa_sha512_k[i]+w[i]; uint64_t S0 = SA_ROTR64(a,28)^SA_ROTR64(a,34)^SA_ROTR64(a,39); uint64_t mj = (a&b)^(a&c)^(b&c); uint64_t t2 = S0+mj; h=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2; }
    \\  st[0]+=a; st[1]+=b; st[2]+=c; st[3]+=d; st[4]+=e; st[5]+=f; st[6]+=g; st[7]+=h;
    \\}
    , .deps = &.{"SA_ROTR64"} },
    .{ .name = "sa_sha512", .code =
    \\static void sa_sha512(const uint8_t *msg, size_t len, uint8_t out[64]) {
    \\  uint64_t st[8] = {0x6a09e667f3bcc908ULL,0xbb67ae8584caa73bULL,0x3c6ef372fe94f82bULL,0xa54ff53a5f1d36f1ULL,0x510e527fade682d1ULL,0x9b05688c2b3e6c1fULL,0x1f83d9abfb41bd6bULL,0x5be0cd19137e2179ULL};
    \\  uint8_t blk[128]; size_t i, off = 0;
    \\  uint64_t bitlen = (uint64_t)len * 8;
    \\  while (len - off >= 128) { sa_sha512_block(st, msg + off); off += 128; }
    \\  size_t rem = len - off;
    \\  for (i = 0; i < rem; i++) blk[i] = msg[off + i];
    \\  blk[rem] = 0x80;
    \\  if (rem + 1 + 16 > 128) { for (i = rem + 1; i < 128; i++) blk[i] = 0; sa_sha512_block(st, blk); for (i = 0; i < 112; i++) blk[i] = 0; }
    \\  else { for (i = rem + 1; i < 112; i++) blk[i] = 0; }
    \\  for (i = 0; i < 8; i++) blk[112 + i] = 0;
    \\  for (i = 0; i < 8; i++) blk[120 + i] = (uint8_t)(bitlen >> (56 - i * 8));
    \\  sa_sha512_block(st, blk);
    \\  for (i = 0; i < 8; i++) { int j; for (j = 0; j < 8; j++) out[i*8+j] = (uint8_t)(st[i] >> (56 - j * 8)); }
    \\}
    , .deps = &.{"sa_sha512_block"} },
    .{ .name = "sa_sha1_block", .code =
    \\static void sa_sha1_block(uint32_t st[5], const uint8_t *p) {
    \\  uint32_t w[80]; int i;
    \\  for (i = 0; i < 16; i++) w[i] = ((uint32_t)p[i*4] << 24) | ((uint32_t)p[i*4+1] << 16) | ((uint32_t)p[i*4+2] << 8) | p[i*4+3];
    \\  for (i = 16; i < 80; i++) w[i] = SA_ROTL32(w[i-3]^w[i-8]^w[i-14]^w[i-16], 1);
    \\  uint32_t a=st[0],b=st[1],c=st[2],d=st[3],e=st[4];
    \\  for (i = 0; i < 80; i++) { uint32_t f, k; if (i < 20) { f = (b&c)|(~b&d); k = 0x5a827999; } else if (i < 40) { f = b^c^d; k = 0x6ed9eba1; } else if (i < 60) { f = (b&c)|(b&d)|(c&d); k = 0x8f1bbcdc; } else { f = b^c^d; k = 0xca62c1d6; } uint32_t t = SA_ROTL32(a,5)+f+e+k+w[i]; e=d; d=c; c=SA_ROTL32(b,30); b=a; a=t; }
    \\  st[0]+=a; st[1]+=b; st[2]+=c; st[3]+=d; st[4]+=e;
    \\}
    , .deps = &.{"SA_ROTL32"} },
    .{ .name = "sa_sha1", .code =
    \\static void sa_sha1(const uint8_t *msg, size_t len, uint8_t out[20]) {
    \\  uint32_t st[5] = {0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0};
    \\  uint8_t blk[64]; size_t i, off = 0;
    \\  uint64_t bitlen = (uint64_t)len * 8;
    \\  while (len - off >= 64) { sa_sha1_block(st, msg + off); off += 64; }
    \\  size_t rem = len - off;
    \\  for (i = 0; i < rem; i++) blk[i] = msg[off + i];
    \\  blk[rem] = 0x80;
    \\  if (rem + 1 + 8 > 64) { for (i = rem + 1; i < 64; i++) blk[i] = 0; sa_sha1_block(st, blk); for (i = 0; i < 56; i++) blk[i] = 0; }
    \\  else { for (i = rem + 1; i < 56; i++) blk[i] = 0; }
    \\  for (i = 0; i < 8; i++) blk[56 + i] = (uint8_t)(bitlen >> (56 - i * 8));
    \\  sa_sha1_block(st, blk);
    \\  for (i = 0; i < 5; i++) { out[i*4] = (uint8_t)(st[i] >> 24); out[i*4+1] = (uint8_t)(st[i] >> 16); out[i*4+2] = (uint8_t)(st[i] >> 8); out[i*4+3] = (uint8_t)st[i]; }
    \\}
    , .deps = &.{"sa_sha1_block"} },
    .{ .name = "sa_md5_block", .code =
    \\static void sa_md5_block(uint32_t st[4], const uint8_t *p) {
    \\  static const uint32_t s[64] = {7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21};
    \\  static const uint32_t K[64] = {0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391};
    \\  uint32_t M[16]; int i;
    \\  for (i = 0; i < 16; i++) M[i] = (uint32_t)p[i*4] | ((uint32_t)p[i*4+1] << 8) | ((uint32_t)p[i*4+2] << 16) | ((uint32_t)p[i*4+3] << 24);
    \\  uint32_t a=st[0],b=st[1],c=st[2],d=st[3];
    \\  for (i = 0; i < 64; i++) { uint32_t f; int g; if (i < 16) { f = (b&c)|(~b&d); g = i; } else if (i < 32) { f = (d&b)|(~d&c); g = (5*i+1)%16; } else if (i < 48) { f = b^c^d; g = (3*i+5)%16; } else { f = c^(b|~d); g = (7*i)%16; } f = f + a + K[i] + M[g]; a = d; d = c; c = b; b = b + SA_ROTL32(f, s[i]); }
    \\  st[0]+=a; st[1]+=b; st[2]+=c; st[3]+=d;
    \\}
    , .deps = &.{"SA_ROTL32"} },
    .{ .name = "sa_md5", .code =
    \\static void sa_md5(const uint8_t *msg, size_t len, uint8_t out[16]) {
    \\  uint32_t st[4] = {0x67452301,0xefcdab89,0x98badcfe,0x10325476};
    \\  uint8_t blk[64]; size_t i, off = 0;
    \\  uint64_t bitlen = (uint64_t)len * 8;
    \\  while (len - off >= 64) { sa_md5_block(st, msg + off); off += 64; }
    \\  size_t rem = len - off;
    \\  for (i = 0; i < rem; i++) blk[i] = msg[off + i];
    \\  blk[rem] = 0x80;
    \\  if (rem + 1 + 8 > 64) { for (i = rem + 1; i < 64; i++) blk[i] = 0; sa_md5_block(st, blk); for (i = 0; i < 56; i++) blk[i] = 0; }
    \\  else { for (i = rem + 1; i < 56; i++) blk[i] = 0; }
    \\  for (i = 0; i < 8; i++) blk[56 + i] = (uint8_t)(bitlen >> (i * 8));
    \\  sa_md5_block(st, blk);
    \\  for (i = 0; i < 4; i++) { out[i*4] = (uint8_t)st[i]; out[i*4+1] = (uint8_t)(st[i] >> 8); out[i*4+2] = (uint8_t)(st[i] >> 16); out[i*4+3] = (uint8_t)(st[i] >> 24); }
    \\}
    , .deps = &.{"sa_md5_block"} },
    .{ .name = "sa_owned_drop", .code =
    \\static void sa_owned_drop(sa_u64 h) { sa_owned_buf_t *o = sa_owned_find(h); if (o != 0) o->h = 0; }
    , .deps = &.{"sa_owned_find"} },
    .{ .name = "sa_regex_find", .code =
    \\static sa_regex_t *sa_regex_find(sa_u64 h) { unsigned i; for (i = 0; i < SA_REGEX_MAX_OBJS; i++) if (sa_regexes[i].h == h) return &sa_regexes[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_json_find", .code =
    \\static sa_json_node_t *sa_json_find(sa_u64 h) { unsigned i; for (i = 0; i < SA_JSON_MAX_NODES; i++) if (sa_json_nodes[i].h == h) return &sa_json_nodes[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_json_writer_find", .code =
    \\static sa_json_writer_t *sa_json_writer_find(sa_u64 h) { unsigned i; for (i = 0; i < SA_JSON_MAX_WRITERS; i++) if (sa_json_writers[i].h == h) return &sa_json_writers[i]; return 0; }
    , .deps = &.{} },
    .{ .name = "sa_json_new", .code =
    \\static sa_json_node_t *sa_json_new(void) { unsigned i; for (i = 0; i < SA_JSON_MAX_NODES; i++) if (sa_json_nodes[i].h == 0) { sa_u64 h = sa_alloc(8); sa_json_nodes[i].h = h; sa_json_nodes[i].kind = 0; sa_json_nodes[i].first = 0; sa_json_nodes[i].next = 0; sa_json_nodes[i].kptr = 0; sa_json_nodes[i].klen = 0; sa_json_nodes[i].vptr = 0; sa_json_nodes[i].vlen = 0; sa_json_nodes[i].ival = 0; sa_json_nodes[i].fbits = 0; sa_json_nodes[i].bval = 0; return &sa_json_nodes[i]; } return 0; }
    , .deps = &.{} },
    .{ .name = "sa_jw_grow", .code =
    \\static int sa_jw_grow(sa_json_writer_t *w, size_t extra) {
    \\  if (w->len + extra < w->len) return 1;
    \\  if (w->len + extra <= w->cap) return 0;
    \\  { size_t ncap = w->cap == 0 ? 256 : w->cap * 2;
    \\    while (ncap < w->len + extra) { if (ncap > ~(size_t)0 / 2) return 1; ncap *= 2; }
    \\    sa_u64 p = sa_alloc((sa_u64)ncap);
    \\    uint32_t d = sa_checked_addr(p, (sa_u64)ncap);
    \\    uint32_t s = sa_checked_addr(w->buf, w->len);
    \\    size_t i; for (i = 0; i < w->len; i++) sa_mem[d + i] = sa_mem[s + i];
    \\    w->buf = p; w->cap = ncap; }
    \\  return 0;
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr" } },
    .{ .name = "sa_jw_putc", .code =
    \\static int sa_jw_putc(sa_json_writer_t *w, uint8_t c) {
    \\  if (sa_jw_grow(w, 1)) return 1;
    \\  { uint32_t d = sa_checked_addr(w->buf, w->len + 1); sa_mem[d + w->len] = c; }
    \\  w->len++;
    \\  return 0;
    \\}
    , .deps = &.{"sa_jw_grow"} },
    .{ .name = "sa_jw_write", .code =
    \\static int sa_jw_write(sa_json_writer_t *w, const uint8_t *s, size_t n) {
    \\  size_t i; uint32_t d;
    \\  if (sa_jw_grow(w, n)) return 1;
    \\  d = sa_checked_addr(w->buf, w->len + n);
    \\  for (i = 0; i < n; i++) sa_mem[d + w->len + i] = s[i];
    \\  w->len += n;
    \\  return 0;
    \\}
    , .deps = &.{"sa_jw_grow"} },
    .{ .name = "sa_jw_comma", .code =
    \\static int sa_jw_comma(sa_json_writer_t *w) {
    \\  if (w->depth == 0 || w->first[w->depth - 1]) return 0;
    \\  return sa_jw_putc(w, ',');
    \\}
    , .deps = &.{"sa_jw_putc"} },
    .{ .name = "sa_jw_value_begin", .code =
    \\static int sa_jw_value_begin(sa_json_writer_t *w) {
    \\  if (w->done) return 1;
    \\  if (w->pending) { w->pending = 0; w->started = 1; return 0; }
    \\  if (w->depth == 0) {
    \\    if (w->complete) return 1;
    \\    w->started = 1; w->complete = 1; return 0;
    \\  }
    \\  if (w->kinds[w->depth - 1] != '{' && w->kinds[w->depth - 1] != '[') return 1;
    \\  if (sa_jw_comma(w)) return 1;
    \\  w->first[w->depth - 1] = 0; w->started = 1;
    \\  return 0;
    \\}
    , .deps = &.{"sa_jw_comma"} },
    .{ .name = "sa_jw_string", .code =
    \\static int sa_jw_string(sa_json_writer_t *w, const uint8_t *s, size_t n) {
    \\  size_t i;
    \\  if (sa_jw_putc(w, '"')) return 1;
    \\  for (i = 0; i < n; i++) {
    \\    uint8_t c = s[i];
    \\    if (c == '"' || c == '\\') { if (sa_jw_putc(w, '\\')) return 1; if (sa_jw_putc(w, c)) return 1; }
    \\    else if (c == '\b') { if (sa_jw_write(w, (const uint8_t *)"\\b", 2)) return 1; }
    \\    else if (c == '\f') { if (sa_jw_write(w, (const uint8_t *)"\\f", 2)) return 1; }
    \\    else if (c == '\n') { if (sa_jw_write(w, (const uint8_t *)"\\n", 2)) return 1; }
    \\    else if (c == '\r') { if (sa_jw_write(w, (const uint8_t *)"\\r", 2)) return 1; }
    \\    else if (c == '\t') { if (sa_jw_write(w, (const uint8_t *)"\\t", 2)) return 1; }
    \\    else if (c < 0x20) {
    \\      char eb[6]; eb[0] = '\\'; eb[1] = 'u'; eb[2] = '0'; eb[3] = '0';
    \\      eb[4] = (char)"0123456789abcdef"[(c >> 4) & 15]; eb[5] = (char)"0123456789abcdef"[c & 15];
    \\      if (sa_jw_write(w, (const uint8_t *)eb, 6)) return 1;
    \\    } else if (sa_jw_putc(w, c)) return 1;
    \\  }
    \\  if (sa_jw_putc(w, '"')) return 1;
    \\  return 0;
    \\}
    , .deps = &.{ "sa_jw_putc", "sa_jw_write" } },
    .{ .name = "sa_utf8_next", .code =
    \\static uint32_t sa_utf8_next(const uint8_t *s, size_t n, size_t *i) {
    \\  size_t k = *i; uint8_t b0;
    \\  if (k >= n) return ~(uint32_t)0;
    \\  b0 = s[k];
    \\  if (b0 < 0x80) { *i = k + 1; return b0; }
    \\  if (b0 >= 0xC2 && b0 <= 0xDF && k + 1 < n && (s[k + 1] & 0xC0) == 0x80) {
    \\    *i = k + 2; return ((uint32_t)(b0 & 0x1F) << 6) | (s[k + 1] & 0x3F); }
    \\  if (b0 >= 0xE0 && b0 <= 0xEF && k + 2 < n && (s[k + 1] & 0xC0) == 0x80 && (s[k + 2] & 0xC0) == 0x80) {
    \\    uint32_t cp = ((uint32_t)(b0 & 0x0F) << 12) | ((uint32_t)(s[k + 1] & 0x3F) << 6) | (s[k + 2] & 0x3F);
    \\    if (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF)) return ~(uint32_t)0;
    \\    *i = k + 3; return cp; }
    \\  if (b0 >= 0xF0 && b0 <= 0xF4 && k + 3 < n && (s[k + 1] & 0xC0) == 0x80 && (s[k + 2] & 0xC0) == 0x80 && (s[k + 3] & 0xC0) == 0x80) {
    \\    uint32_t cp = ((uint32_t)(b0 & 0x07) << 18) | ((uint32_t)(s[k + 1] & 0x3F) << 12) | ((uint32_t)(s[k + 2] & 0x3F) << 6) | (s[k + 3] & 0x3F);
    \\    if (cp < 0x10000 || cp > 0x10FFFF) return ~(uint32_t)0;
    \\    *i = k + 4; return cp; }
    \\  return ~(uint32_t)0;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_utf8_enc", .code =
    \\static unsigned sa_utf8_enc(uint32_t cp, uint8_t *o) {
    \\  if (cp < 0x80) { o[0] = (uint8_t)cp; return 1; }
    \\  if (cp < 0x800) { o[0] = (uint8_t)(0xC0 | (cp >> 6)); o[1] = (uint8_t)(0x80 | (cp & 0x3F)); return 2; }
    \\  if (cp < 0x10000) { o[0] = (uint8_t)(0xE0 | (cp >> 12)); o[1] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F)); o[2] = (uint8_t)(0x80 | (cp & 0x3F)); return 3; }
    \\  o[0] = (uint8_t)(0xF0 | (cp >> 18)); o[1] = (uint8_t)(0x80 | ((cp >> 12) & 0x3F)); o[2] = (uint8_t)(0x80 | ((cp >> 6) & 0x3F)); o[3] = (uint8_t)(0x80 | (cp & 0x3F)); return 4;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_json_string", .code =
    \\static int sa_json_string(const uint8_t *s, size_t n, size_t *pos, sa_u64 *out_ptr, sa_u64 *out_len) {
    \\  size_t i = *pos; size_t w; sa_u64 p; uint32_t d;
    \\  if (i >= n || s[i] != '"') return 0;
    \\  i++;
    \\  p = sa_alloc(n - i + 1);
    \\  d = sa_checked_addr(p, n - i + 1);
    \\  w = 0;
    \\  while (i < n && s[i] != '"') {
    \\    uint8_t c = s[i];
    \\    if (c == '\\') {
    \\      uint8_t e;
    \\      i++; if (i >= n) return 0; e = s[i];
    \\      if (e == '"' || e == '\\' || e == '/') sa_mem[d + w++] = e;
    \\      else if (e == 'b') sa_mem[d + w++] = 8;
    \\      else if (e == 'f') sa_mem[d + w++] = 12;
    \\      else if (e == 'n') sa_mem[d + w++] = 10;
    \\      else if (e == 'r') sa_mem[d + w++] = 13;
    \\      else if (e == 't') sa_mem[d + w++] = 9;
    \\      else if (e == 'u') {
    \\        uint32_t cp = 0; int k;
    \\        for (k = 0; k < 4; k++) {
    \\          i++; if (i >= n) return 0;
    \\          uint8_t h = s[i]; uint32_t v;
    \\          if (h >= '0' && h <= '9') v = (uint32_t)(h - '0');
    \\          else if (h >= 'a' && h <= 'f') v = (uint32_t)(h - 'a' + 10);
    \\          else if (h >= 'A' && h <= 'F') v = (uint32_t)(h - 'A' + 10);
    \\          else return 0;
    \\          cp = cp * 16 + v;
    \\        }
    \\        if (cp >= 0xD800 && cp <= 0xDBFF) {
    \\          uint32_t lo;
    \\          if (i + 2 >= n || s[i + 1] != '\\' || s[i + 2] != 'u') return 0;
    \\          lo = 0; i += 2;
    \\          for (k = 0; k < 4; k++) {
    \\            i++; if (i >= n) return 0;
    \\            uint8_t h = s[i]; uint32_t v;
    \\            if (h >= '0' && h <= '9') v = (uint32_t)(h - '0');
    \\            else if (h >= 'a' && h <= 'f') v = (uint32_t)(h - 'a' + 10);
    \\            else if (h >= 'A' && h <= 'F') v = (uint32_t)(h - 'A' + 10);
    \\            else return 0;
    \\            lo = lo * 16 + v;
    \\          }
    \\          if (lo < 0xDC00 || lo > 0xDFFF) return 0;
    \\          cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
    \\        } else if (cp >= 0xDC00 && cp <= 0xDFFF) return 0;
    \\        w += sa_utf8_enc(cp, &sa_mem[d + w]);
    \\      } else return 0;
    \\      i++;
    \\    } else if ((uint8_t)c < 0x20) return 0;
    \\    else { sa_mem[d + w++] = c; i++; }
    \\  }
    \\  if (i >= n) return 0;
    \\  *pos = i + 1;
    \\  *out_ptr = p;
    \\  *out_len = w;
    \\  return 1;
    \\}
    , .deps = &.{"sa_utf8_enc"} },
    .{ .name = "sa_json_guest_dup", .code =
    \\static sa_u64 sa_json_guest_dup(sa_u64 src, sa_u64 len) {
    \\  sa_u64 p = sa_alloc(len);
    \\  uint32_t d = sa_checked_addr(p, len);
    \\  uint32_t s = sa_checked_addr(src, len);
    \\  size_t i;
    \\  for (i = 0; i < (size_t)len; i++) sa_mem[d + i] = sa_mem[s + i];
    \\  return p;
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr" } },
    .{ .name = "sa_json_append_child", .code =
    \\static void sa_json_append_child(sa_json_node_t *parent, sa_json_node_t *child) {
    \\  child->next = 0;
    \\  if (parent->first == 0) {
    \\    parent->first = (sa_u64)(child - sa_json_nodes) + 1;
    \\    return;
    \\  }
    \\  { sa_json_node_t *m = &sa_json_nodes[parent->first - 1];
    \\    while (m->next != 0) m = &sa_json_nodes[m->next - 1];
    \\    m->next = (sa_u64)(child - sa_json_nodes) + 1; }
    \\}
    , .deps = &.{} },
    .{ .name = "sa_json_child_named", .code =
    \\static sa_json_node_t *sa_json_child_named(sa_json_node_t *obj, uint32_t k, sa_u64 klen) {
    \\  sa_u64 ci = obj->first;
    \\  while (ci != 0) {
    \\    sa_json_node_t *m = &sa_json_nodes[ci - 1];
    \\    if (m->klen == klen) {
    \\      uint32_t mk = sa_checked_addr(m->kptr, m->klen);
    \\      size_t i; int eq = 1;
    \\      for (i = 0; i < (size_t)klen; i++) {
    \\        if (sa_mem[mk + i] != sa_mem[k + i]) { eq = 0; break; }
    \\      }
    \\      if (eq) return m;
    \\    }
    \\    ci = m->next;
    \\  }
    \\  return 0;
    \\}
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_json_unlink_child", .code =
    \\static void sa_json_unlink_child(sa_json_node_t *parent, sa_json_node_t *child) {
    \\  sa_u64 want = (sa_u64)(child - sa_json_nodes) + 1;
    \\  if (parent->first == want) {
    \\    parent->first = child->next;
    \\    child->next = 0;
    \\    return;
    \\  }
    \\  { sa_u64 ci = parent->first;
    \\    while (ci != 0) {
    \\      sa_json_node_t *m = &sa_json_nodes[ci - 1];
    \\      if (m->next == want) {
    \\        m->next = child->next;
    \\        child->next = 0;
    \\        return;
    \\      }
    \\      ci = m->next;
    \\    } }
    \\}
    , .deps = &.{} },
    .{ .name = "sa_json_retire_subtree", .code =
    \\static void sa_json_retire_subtree(sa_json_node_t *nd) {
    \\  sa_u64 ci = nd->first;
    \\  while (ci != 0) {
    \\    sa_json_node_t *m = &sa_json_nodes[ci - 1];
    \\    sa_u64 nx = m->next;
    \\    sa_json_retire_subtree(m);
    \\    ci = nx;
    \\  }
    \\  nd->h = 0;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_json_clone_node", .code =
    \\static sa_json_node_t *sa_json_clone_node(sa_json_node_t *src) {
    \\  sa_json_node_t *nd = sa_json_new();
    \\  if (nd == 0) return 0;
    \\  nd->kind = src->kind;
    \\  nd->ival = src->ival;
    \\  nd->fbits = src->fbits;
    \\  nd->bval = src->bval;
    \\  nd->vlen = src->vlen;
    \\  if (src->vlen > 0) nd->vptr = sa_json_guest_dup(src->vptr, src->vlen);
    \\  { sa_u64 ci = src->first;
    \\    sa_json_node_t *last = 0;
    \\    while (ci != 0) {
    \\      sa_json_node_t *cm = &sa_json_nodes[ci - 1];
    \\      sa_u64 nx = cm->next;
    \\      sa_json_node_t *cc = sa_json_clone_node(cm);
    \\      if (cc == 0) return 0;
    \\      cc->klen = cm->klen;
    \\      if (cm->klen > 0) cc->kptr = sa_json_guest_dup(cm->kptr, cm->klen);
    \\      cc->next = 0;
    \\      if (last == 0) nd->first = (sa_u64)(cc - sa_json_nodes) + 1;
    \\      else last->next = (sa_u64)(cc - sa_json_nodes) + 1;
    \\      last = cc;
    \\      ci = nx;
    \\    } }
    \\  return nd;
    \\}
    , .deps = &.{ "sa_json_new", "sa_json_guest_dup" } },
    .{ .name = "sa_regex_exec_range", .code =
    \\static int sa_regex_exec_range(sa_regex_t *r, sa_u64 tp, sa_u64 tl, sa_u64 pos, regmatch_t *pm, sa_u64 n) {
    \\  uint32_t td = sa_checked_addr(tp, tl + 1);
    \\  pm[0].rm_so = (regoff_t)pos;
    \\  pm[0].rm_eo = (regoff_t)tl;
    \\  return regexec(&r->rx, (const char *)&sa_mem[td], (size_t)n, pm, REG_STARTEND);
    \\}
    , .deps = &.{"sa_checked_addr"} },
    .{ .name = "sa_rb_put", .code =
    \\static void sa_rb_put(sa_u64 *base, sa_u64 *len, sa_u64 *cap, const uint8_t *sp, sa_u64 n) {
    \\  if (n == 0) return;
    \\  if (*len + n > *cap) {
    \\    sa_u64 ncap = *cap == 0 ? 64 : *cap;
    \\    while (ncap < *len + n) ncap *= 2;
    \\    { sa_u64 nb = sa_alloc(ncap);
    \\      uint32_t d = sa_checked_addr(nb, ncap);
    \\      if (*len > 0) {
    \\        uint32_t s = sa_checked_addr(*base, *len);
    \\        size_t i;
    \\        for (i = 0; i < (size_t)*len; i++) sa_mem[d + i] = sa_mem[s + i];
    \\      }
    \\      *base = nb;
    \\      *cap = ncap; }
    \\  }
    \\  { uint32_t d = sa_checked_addr(*base, *len + n);
    \\    size_t i;
    \\    for (i = 0; i < (size_t)n; i++) sa_mem[d + *len + i] = sp[i]; }
    \\  *len += n;
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr" } },
    .{ .name = "sa_regex_put_group", .code =
    \\static void sa_regex_put_group(sa_u64 *base, sa_u64 *len, sa_u64 *cap, uint32_t td, regmatch_t *pm, sa_u64 idx) {
    \\  if (pm[idx].rm_so < 0 || pm[idx].rm_eo < pm[idx].rm_so) return;
    \\  sa_rb_put(base, len, cap, &sa_mem[td + (sa_u64)pm[idx].rm_so],
    \\    (sa_u64)(pm[idx].rm_eo - pm[idx].rm_so));
    \\}
    , .deps = &.{"sa_rb_put"} },
    .{ .name = "sa_regex_expand_into", .code =
    \\/* Template expansion mirroring sa_std regexExpandInto. Byte codes:
    \\   36='$' 38='&' 96=backtick 39=quote 48..57 digits. */
    \\static void sa_regex_expand_into(sa_u64 *base, sa_u64 *len, sa_u64 *cap,
    \\    sa_u64 tp, sa_u64 tl, regmatch_t *pm, sa_u64 n, sa_u64 rp, sa_u64 rl) {
    \\  uint32_t td = sa_checked_addr(tp, tl);
    \\  uint32_t rd = sa_checked_addr(rp, rl);
    \\  sa_u64 total = n - 1;
    \\  sa_u64 i = 0;
    \\  while (i < rl) {
    \\    uint8_t c = sa_mem[rd + i];
    \\    if (c != 36 || i + 1 >= rl) {
    \\      sa_rb_put(base, len, cap, &sa_mem[rd + i], 1);
    \\      i += 1;
    \\      continue;
    \\    }
    \\    { uint8_t nx = sa_mem[rd + i + 1];
    \\      if (nx == 36) {
    \\        sa_rb_put(base, len, cap, &sa_mem[rd + i], 1);
    \\        i += 2;
    \\      } else if (nx == 38) {
    \\        sa_regex_put_group(base, len, cap, td, pm, 0);
    \\        i += 2;
    \\      } else if (nx == 96) {
    \\        if (pm[0].rm_so > 0)
    \\          sa_rb_put(base, len, cap, &sa_mem[td], (sa_u64)pm[0].rm_so);
    \\        i += 2;
    \\      } else if (nx == 39) {
    \\        if (pm[0].rm_eo >= 0 && (sa_u64)pm[0].rm_eo < tl)
    \\          sa_rb_put(base, len, cap, &sa_mem[td + (sa_u64)pm[0].rm_eo],
    \\            tl - (sa_u64)pm[0].rm_eo);
    \\        i += 2;
    \\      } else if (nx >= 49 && nx <= 57) {
    \\        sa_u64 d1 = (sa_u64)(nx - 49) + 1;
    \\        sa_u64 consumed = 0;
    \\        if (i + 2 < rl && sa_mem[rd + i + 2] >= 48 && sa_mem[rd + i + 2] <= 57) {
    \\          sa_u64 nn = d1 * 10 + (sa_u64)(sa_mem[rd + i + 2] - 48);
    \\          if (nn >= 1 && nn <= total) {
    \\            sa_regex_put_group(base, len, cap, td, pm, nn);
    \\            consumed = 3;
    \\          }
    \\        }
    \\        if (consumed == 0 && d1 <= total) {
    \\          sa_regex_put_group(base, len, cap, td, pm, d1);
    \\          consumed = 2;
    \\        }
    \\        if (consumed == 0) {
    \\          sa_rb_put(base, len, cap, &sa_mem[rd + i], 1);
    \\          i += 1;
    \\        } else {
    \\          i += consumed;
    \\        }
    \\      } else {
    \\        sa_rb_put(base, len, cap, &sa_mem[rd + i], 1);
    \\        i += 1;
    \\      } }
    \\  }
    \\}
    , .deps = &.{ "sa_checked_addr", "sa_rb_put", "sa_regex_put_group" } },
    .{ .name = "sa_regex_collect_block", .code =
    \\/* Match list block (guest): [0]=text base [8]=0x53414C58<<32 | count
    \\   [16]=group count, then per match n (start,end) pairs. */
    \\static sa_u64 sa_regex_collect_block(sa_regex_t *r, sa_u64 tp, sa_u64 tl) {
    \\  sa_u64 n = (sa_u64)r->rx.re_nsub + 1;
    \\  if (n > SA_REGEX_MAX_GROUPS) n = SA_REGEX_MAX_GROUPS;
    \\  { sa_u64 cap = 16;
    \\    sa_u64 cnt = 0;
    \\    sa_u64 blk = sa_alloc(24 + cap * n * 16);
    \\    regmatch_t pm[SA_REGEX_MAX_GROUPS];
    \\    sa_u64 pos = 0;
    \\    while (pos <= tl) {
    \\      if (sa_regex_exec_range(r, tp, tl, pos, pm, n) != 0) break;
    \\      if (cnt == cap) {
    \\        sa_u64 nblk = sa_alloc(24 + cap * 2 * n * 16);
    \\        uint32_t d = sa_checked_addr(nblk, 24 + cap * n * 16);
    \\        uint32_t s = sa_checked_addr(blk, 24 + cap * n * 16);
    \\        size_t i;
    \\        for (i = 0; i < (size_t)(24 + cap * n * 16); i++)
    \\          sa_mem[d + i] = sa_mem[s + i];
    \\        blk = nblk;
    \\        cap *= 2;
    \\      }
    \\      { sa_u64 g;
    \\        for (g = 0; g < n; g++) {
    \\          sa_store_u64(blk + 24 + (cnt * n + g) * 16,
    \\            (sa_u64)(sa_i64)pm[g].rm_so);
    \\          sa_store_u64(blk + 24 + (cnt * n + g) * 16 + 8,
    \\            (sa_u64)(sa_i64)pm[g].rm_eo);
    \\        } }
    \\      cnt++;
    \\      { sa_u64 ms = (sa_u64)(sa_i64)pm[0].rm_so;
    \\        sa_u64 me = (sa_u64)(sa_i64)pm[0].rm_eo;
    \\        pos = (me == ms) ? me + 1 : me; }
    \\    }
    \\    sa_store_u64(blk, tp);
    \\    sa_store_u64(blk + 8, (sa_u64)0x53414C5800000000ULL | cnt);
    \\    sa_store_u64(blk + 16, n);
    \\    return blk; }
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr", "sa_store_u64", "sa_regex_exec_range" } },
    .{ .name = "sa_regex_build_replace", .code =
    \\/* Replace result buffer block (guest): [0]=0x53414258<<32 [8]=len,
    \\   bytes at +16. Mirrors sa_std regexBuildReplace. */
    \\static sa_u64 sa_regex_build_replace(sa_regex_t *r, sa_u64 tp, sa_u64 tl,
    \\    sa_u64 rp, sa_u64 rl, int global) {
    \\  sa_u64 n = (sa_u64)r->rx.re_nsub + 1;
    \\  if (n > SA_REGEX_MAX_GROUPS) n = SA_REGEX_MAX_GROUPS;
    \\  { sa_u64 base = 0;
    \\    sa_u64 len = 0;
    \\    sa_u64 cap = 0;
    \\    regmatch_t pm[SA_REGEX_MAX_GROUPS];
    \\    uint32_t td = sa_checked_addr(tp, tl);
    \\    if (!global) {
    \\      if (sa_regex_exec_range(r, tp, tl, 0, pm, n) != 0) {
    \\        sa_rb_put(&base, &len, &cap, &sa_mem[td], tl);
    \\      } else {
    \\        sa_u64 ms = (sa_u64)(sa_i64)pm[0].rm_so;
    \\        sa_u64 me = (sa_u64)(sa_i64)pm[0].rm_eo;
    \\        if (ms > 0) sa_rb_put(&base, &len, &cap, &sa_mem[td], ms);
    \\        sa_regex_expand_into(&base, &len, &cap, tp, tl, pm, n, rp, rl);
    \\        if (me < tl)
    \\          sa_rb_put(&base, &len, &cap, &sa_mem[td + me], tl - me);
    \\      }
    \\    } else {
    \\      sa_u64 last = 0;
    \\      sa_u64 pos = 0;
    \\      while (pos <= tl) {
    \\        if (sa_regex_exec_range(r, tp, tl, pos, pm, n) != 0) break;
    \\        { sa_u64 ms = (sa_u64)(sa_i64)pm[0].rm_so;
    \\          sa_u64 me = (sa_u64)(sa_i64)pm[0].rm_eo;
    \\          if (ms > last)
    \\            sa_rb_put(&base, &len, &cap, &sa_mem[td + last], ms - last);
    \\          sa_regex_expand_into(&base, &len, &cap, tp, tl, pm, n, rp, rl);
    \\          last = me;
    \\          pos = (me == ms) ? me + 1 : me; }
    \\      }
    \\      if (last < tl)
    \\        sa_rb_put(&base, &len, &cap, &sa_mem[td + last], tl - last);
    \\    }
    \\    { sa_u64 blk = sa_alloc(16 + len);
    \\      sa_store_u64(blk, (sa_u64)0x5341425800000000ULL);
    \\      sa_store_u64(blk + 8, len);
    \\      if (len > 0) {
    \\        uint32_t d = sa_checked_addr(blk + 16, len);
    \\        uint32_t s = sa_checked_addr(base, len);
    \\        size_t i;
    \\        for (i = 0; i < (size_t)len; i++) sa_mem[d + i] = sa_mem[s + i];
    \\      }
    \\      return blk; } }
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr", "sa_store_u64", "sa_rb_put", "sa_regex_exec_range", "sa_regex_expand_into" } },
    .{ .name = "sa_regex_piece_put", .code =
    \\static void sa_regex_piece_put(sa_u64 *blk, sa_u64 *cap, sa_u64 *cnt,
    \\    sa_i64 so, sa_i64 eo) {
    \\  if (*cnt == *cap) {
    \\    sa_u64 nblk = sa_alloc(16 + *cap * 2 * 16);
    \\    uint32_t d = sa_checked_addr(nblk, 16 + *cap * 16);
    \\    uint32_t s = sa_checked_addr(*blk, 16 + *cap * 16);
    \\    size_t i;
    \\    for (i = 0; i < (size_t)(16 + *cap * 16); i++)
    \\      sa_mem[d + i] = sa_mem[s + i];
    \\    *blk = nblk;
    \\    *cap *= 2;
    \\  }
    \\  sa_store_u64(*blk + 16 + *cnt * 16, (sa_u64)so);
    \\  sa_store_u64(*blk + 16 + *cnt * 16 + 8, (sa_u64)eo);
    \\  *cnt += 1;
    \\}
    , .deps = &.{ "sa_alloc", "sa_checked_addr", "sa_store_u64" } },
    .{ .name = "sa_regex_split_block", .code =
    \\/* Split list block (guest): [0]=text base [8]=0x53415058<<32 | count,
    \\   then count (start,end) pairs; start -1 marks non-participating
    \\   groups. Ports sa_std regexSplitList (JS String.split semantics). */
    \\static sa_u64 sa_regex_split_block(sa_regex_t *r, sa_u64 tp, sa_u64 tl,
    \\    sa_u64 limit) {
    \\  sa_u64 n = (sa_u64)r->rx.re_nsub + 1;
    \\  if (n > SA_REGEX_MAX_GROUPS) n = SA_REGEX_MAX_GROUPS;
    \\  { sa_u64 lim = limit == 0 ? ~(sa_u64)0 : limit;
    \\    sa_u64 cap = 16;
    \\    sa_u64 cnt = 0;
    \\    sa_u64 blk = sa_alloc(16 + cap * 16);
    \\    regmatch_t pm[SA_REGEX_MAX_GROUPS];
    \\    if (tl == 0) {
    \\      if (sa_regex_exec_range(r, tp, tl, 0, pm, n) != 0)
    \\        sa_regex_piece_put(&blk, &cap, &cnt, 0, 0);
    \\    } else {
    \\      sa_u64 p = 0;
    \\      sa_u64 q = 0;
    \\      int done = 0;
    \\      while (!done && q < tl) {
    \\        if (cnt >= lim) break;
    \\        if (sa_regex_exec_range(r, tp, tl, q, pm, n) != 0) break;
    \\        { sa_u64 ms = (sa_u64)(sa_i64)pm[0].rm_so;
    \\          sa_u64 me = (sa_u64)(sa_i64)pm[0].rm_eo;
    \\          if (me == p) { q = me + 1; continue; }
    \\          sa_regex_piece_put(&blk, &cap, &cnt, (sa_i64)p, (sa_i64)ms);
    \\          { sa_u64 g;
    \\            for (g = 1; g < n; g++) {
    \\              if (cnt >= lim) break;
    \\              sa_regex_piece_put(&blk, &cap, &cnt,
    \\                (sa_i64)pm[g].rm_so, (sa_i64)pm[g].rm_eo);
    \\            } }
    \\          if (cnt >= lim) done = 1;
    \\          else { p = me; q = me; } }
    \\      }
    \\      if (!done && cnt < lim)
    \\        sa_regex_piece_put(&blk, &cap, &cnt, (sa_i64)p, (sa_i64)tl);
    \\    }
    \\    sa_store_u64(blk, tp);
    \\    sa_store_u64(blk + 8, (sa_u64)0x5341505800000000ULL | cnt);
    \\    return blk; }
    \\}
    , .deps = &.{ "sa_alloc", "sa_store_u64", "sa_regex_exec_range", "sa_regex_piece_put" } },
    .{ .name = "sa_json_parse_value", .code =
    \\static sa_json_node_t *sa_json_parse_value(const uint8_t *s, size_t n, size_t *pos, int depth) {
    \\  sa_json_node_t *nd; uint8_t c;
    \\  if (depth > SA_JSON_MAX_DEPTH) return 0;
    \\  while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\  if (*pos >= n) return 0;
    \\  c = s[*pos];
    \\  if (c == '{') {
    \\    sa_json_node_t *last = 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0; nd->kind = 7;
    \\    (*pos)++;
    \\    while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\    if (*pos < n && s[*pos] == '}') { (*pos)++; return nd; }
    \\    for (;;) {
    \\      sa_u64 kp = 0, kl = 0; sa_json_node_t *v;
    \\      while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\      if (!sa_json_string(s, n, pos, &kp, &kl)) return 0;
    \\      while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\      if (*pos >= n || s[*pos] != ':') return 0;
    \\      (*pos)++;
    \\      v = sa_json_parse_value(s, n, pos, depth + 1);
    \\      if (v == 0) return 0;
    \\      v->kptr = kp; v->klen = kl;
    \\      if (last == 0) nd->first = (sa_u64)(v - sa_json_nodes) + 1; else last->next = (sa_u64)(v - sa_json_nodes) + 1;
    \\      last = v;
    \\      while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\      if (*pos < n && s[*pos] == ',') { (*pos)++; continue; }
    \\      if (*pos < n && s[*pos] == '}') { (*pos)++; return nd; }
    \\      return 0;
    \\    }
    \\  }
    \\  if (c == '[') {
    \\    sa_json_node_t *last = 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0; nd->kind = 6;
    \\    (*pos)++;
    \\    while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\    if (*pos < n && s[*pos] == ']') { (*pos)++; return nd; }
    \\    for (;;) {
    \\      sa_json_node_t *v = sa_json_parse_value(s, n, pos, depth + 1);
    \\      if (v == 0) return 0;
    \\      if (last == 0) nd->first = (sa_u64)(v - sa_json_nodes) + 1; else last->next = (sa_u64)(v - sa_json_nodes) + 1;
    \\      last = v;
    \\      while (*pos < n && (s[*pos] == ' ' || s[*pos] == '\t' || s[*pos] == '\n' || s[*pos] == '\r')) (*pos)++;
    \\      if (*pos < n && s[*pos] == ',') { (*pos)++; continue; }
    \\      if (*pos < n && s[*pos] == ']') { (*pos)++; return nd; }
    \\      return 0;
    \\    }
    \\  }
    \\  if (c == '"') {
    \\    sa_u64 p = 0, l = 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0;
    \\    if (!sa_json_string(s, n, pos, &p, &l)) return 0;
    \\    nd->kind = 5; nd->vptr = p; nd->vlen = l;
    \\    return nd;
    \\  }
    \\  if (c == 't') {
    \\    if (*pos + 4 > n || s[*pos+1] != 'r' || s[*pos+2] != 'u' || s[*pos+3] != 'e') return 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0;
    \\    *pos += 4; nd->kind = 1; nd->bval = 1;
    \\    return nd;
    \\  }
    \\  if (c == 'f') {
    \\    if (*pos + 5 > n || s[*pos+1] != 'a' || s[*pos+2] != 'l' || s[*pos+3] != 's' || s[*pos+4] != 'e') return 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0;
    \\    *pos += 5; nd->kind = 1; nd->bval = 0;
    \\    return nd;
    \\  }
    \\  if (c == 'n') {
    \\    if (*pos + 4 > n || s[*pos+1] != 'u' || s[*pos+2] != 'l' || s[*pos+3] != 'l') return 0;
    \\    nd = sa_json_new(); if (nd == 0) return 0;
    \\    *pos += 4; nd->kind = 0;
    \\    return nd;
    \\  }
    \\  if (c == '-' || (c >= '0' && c <= '9')) {
    \\    size_t st = *pos; size_t j = *pos; int is_float = 0;
    \\    if (s[j] == '-') j++;
    \\    if (j >= n) return 0;
    \\    if (s[j] == '0') j++;
    \\    else if (s[j] >= '1' && s[j] <= '9') { while (j < n && s[j] >= '0' && s[j] <= '9') j++; }
    \\    else return 0;
    \\    if (j < n && s[j] == '.') {
    \\      is_float = 1; j++;
    \\      if (j >= n || s[j] < '0' || s[j] > '9') return 0;
    \\      while (j < n && s[j] >= '0' && s[j] <= '9') j++;
    \\    }
    \\    if (j < n && (s[j] == 'e' || s[j] == 'E')) {
    \\      size_t m;
    \\      is_float = 1; j++;
    \\      if (j < n && (s[j] == '+' || s[j] == '-')) j++;
    \\      m = j;
    \\      while (j < n && s[j] >= '0' && s[j] <= '9') j++;
    \\      if (m == j) return 0;
    \\    }
    \\    nd = sa_json_new(); if (nd == 0) return 0;
    \\    if (!is_float) {
    \\      sa_u64 mag = 0; size_t k = st; int neg = 0;
    \\      if (s[k] == '-') { neg = 1; k++; }
    \\      for (; k < j; k++) {
    \\        unsigned dg = (unsigned)(s[k] - '0');
    \\        if (mag > (~(sa_u64)0 - dg) / 10) break;
    \\        mag = mag * 10 + dg;
    \\      }
    \\      if (k == j && !neg && mag <= (sa_u64)9223372036854775807ULL) { nd->kind = 2; nd->ival = (sa_i64)mag; }
    \\      else if (k == j && neg && mag <= (sa_u64)9223372036854775808ULL) { nd->kind = 2; nd->ival = (sa_i64)(~(sa_u64)0 - mag + 1); }
    \\      else is_float = 1;
    \\    }
    \\    if (is_float) {
    \\      sa_u64 span = j - st;
    \\      sa_u64 tp = sa_alloc(span + 1);
    \\      uint32_t td = sa_checked_addr(tp, span + 1);
    \\      size_t q; for (q = 0; q < (size_t)span; q++) sa_mem[td + q] = s[st + q];
    \\      sa_mem[td + span] = 0; errno = 0;
    \\      union { sa_u64 u; double v; } t; t.v = strtod((const char *)&sa_mem[td], 0);
    \\      nd->kind = 3; nd->fbits = t.u;
    \\    }
    \\    *pos = j;
    \\    return nd;
    \\  }
    \\  return 0;
    \\}
    , .deps = &.{ "sa_json_new", "sa_json_string", "sa_utf8_enc" } },
    .{ .name = "sa_path_norm", .code =
    \\static sa_u64 sa_path_norm(const uint8_t *s, size_t n, uint8_t *o, size_t cap) {
    \\  size_t w = 0; size_t i = 0; int abs = (n > 0 && s[0] == '/');
    \\  int trail = (n > 1 && s[n - 1] == '/');
    \\  size_t base = abs ? 1 : 0;
    \\  if (abs) { if (w >= cap) return ~(sa_u64)0; o[w++] = '/'; }
    \\  while (i < n) {
    \\    while (i < n && s[i] == '/') i++;
    \\    if (i >= n) break;
    \\    size_t j = i; while (j < n && s[j] != '/') j++;
    \\    size_t sl = j - i;
    \\    if (sl == 1 && s[i] == '.') { }
    \\    else if (sl == 2 && s[i] == '.' && s[i + 1] == '.') {
    \\      size_t e = w;
    \\      if (w > base && o[w - 1] == '/') e--;
    \\      size_t ss = e;
    \\      while (ss > base && o[ss - 1] != '/') ss--;
    \\      if (w > base && !(e - ss == 2 && o[ss] == '.' && o[ss + 1] == '.')) { w = ss; if (w > base && o[w - 1] == '/') w--; }
    \\      else if (w == base && !abs) {
    \\        if (w + 2 > cap) return ~(sa_u64)0;
    \\        o[w++] = '.'; o[w++] = '.';
    \\      }
    \\      else if (w > base) {
    \\        if (w + 3 > cap) return ~(sa_u64)0;
    \\        o[w++] = '/'; o[w++] = '.'; o[w++] = '.';
    \\      }
    \\    } else {
    \\      if (w > base) { if (w + 1 > cap) return ~(sa_u64)0; o[w++] = '/'; }
    \\      if (w + sl > cap) return ~(sa_u64)0;
    \\      { size_t k; for (k = 0; k < sl; k++) o[w + k] = s[i + k]; }
    \\      w += sl;
    \\    }
    \\    i = j;
    \\  }
    \\  if (w == 0) { if (w + 1 > cap) return ~(sa_u64)0; o[w++] = abs ? '/' : '.'; }
    \\  else if (trail && o[w - 1] != '/') { if (w + 1 > cap) return ~(sa_u64)0; o[w++] = '/'; }
    \\  return (sa_u64)w;
    \\}
    , .deps = &.{} },
    .{ .name = "sa_div_floor", .code =
    \\static sa_i64 sa_div_floor(sa_i64 a, sa_i64 b) { sa_i64 q = a / b; sa_i64 r = a % b; if (r != 0 && ((r < 0) != (b < 0))) q -= 1; return q; }
    , .deps = &.{} },
    .{ .name = "sa_mod_floor", .code =
    \\static sa_i64 sa_mod_floor(sa_i64 a, sa_i64 b) { sa_i64 r = a % b; if ((r != 0) && ((r < 0) != (b < 0))) r += b; return r; }
    , .deps = &.{} },
    .{ .name = "sa_civil_ymd", .code =
    \\static void sa_civil_ymd(sa_i64 ms, sa_i64 *y, sa_i64 *mo, sa_i64 *d) {
    \\  sa_i64 days = sa_div_floor(ms, 86400000);
    \\  sa_i64 z = days + 719468;
    \\  sa_i64 era = (z >= 0) ? sa_div_floor(z, 146097) : sa_div_floor(z - 146096, 146097);
    \\  sa_i64 doe = z - era * 146097;
    \\  sa_i64 yoe = sa_div_floor(doe - sa_div_floor(doe, 1460) + sa_div_floor(doe, 36524) - sa_div_floor(doe, 146096), 365);
    \\  sa_i64 yy = yoe + era * 400;
    \\  sa_i64 doy = doe - (365 * yoe + sa_div_floor(yoe, 4) - sa_div_floor(yoe, 100));
    \\  sa_i64 mp = sa_div_floor(5 * doy + 2, 153);
    \\  sa_i64 month = (mp < 10) ? mp + 3 : mp - 9;
    \\  *y = (month <= 2) ? yy + 1 : yy;
    \\  *mo = month;
    \\  *d = doy - sa_div_floor(153 * mp + 2, 5) + 1;
    \\}
    , .deps = &.{"sa_div_floor"} },
    .{ .name = "sa_puny_adapt", .code =
    \\static sa_u64 sa_puny_adapt(sa_u64 delta, sa_u64 numpoints, int first) {
    \\  sa_u64 k = 0;
    \\  delta = first ? delta / 700 : delta >> 1;
    \\  delta += delta / numpoints;
    \\  while (delta > ((36 - 1) * 26) / 2) { delta /= 36 - 1; k += 36; }
    \\  return k + (36 - 1 + 1) * delta / (delta + 38);
    \\}
    , .deps = &.{} },
};

/// Emission order for the catalog, topologically sorted by deps at
/// comptime (Kahn's algorithm, stable by table order). Callees always
/// precede callers no matter where entries sit in the table, so adding
/// helpers can never reintroduce use-before-definition. Unknown deps
/// (sa_trap, always emitted) are treated as ready; any residual cycle
/// falls back to table order.
const kHelpersSorted: [kRuntimeHelpers.len]HelperDef = blk: {
    @setEvalBranchQuota(100000);
    var order: [kRuntimeHelpers.len]usize = undefined;
    var done: [kRuntimeHelpers.len]bool = std.mem.zeroes([kRuntimeHelpers.len]bool);
    var n: usize = 0;
    var progress = true;
    while (progress) {
        progress = false;
        for (kRuntimeHelpers, 0..) |h, i| {
            if (done[i]) continue;
            var ready = true;
            for (h.deps) |dep| {
                for (kRuntimeHelpers, 0..) |h2, j| {
                    if (std.mem.eql(u8, h2.name, dep)) {
                        if (!done[j]) ready = false;
                        break;
                    }
                }
                if (!ready) break;
            }
            if (ready) {
                order[n] = i;
                n += 1;
                done[i] = true;
                progress = true;
            }
        }
    }
    for (0..kRuntimeHelpers.len) |i| {
        if (!done[i]) {
            order[n] = i;
            n += 1;
            done[i] = true;
        }
    }
    var out: [kRuntimeHelpers.len]HelperDef = undefined;
    for (order, 0..) |idx, k| out[k] = kRuntimeHelpers[idx];
    break :blk out;
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
    return std.mem.eql(u8, norm_name, "pthread_spawn") or bindingNeedsTaskEntry(norm_name);
}

/// True for the goroutine bindings whose host side runs guest code
/// (spawn / supervised spawn / once_do): their C1 glue trampolines
/// call sa_call_indirect, so programs calling them force
/// need_indirect exactly like pthread_spawn, and the emit pass adds
/// the trampoline block (see the need_task_entry emission).
fn bindingNeedsTaskEntry(norm_name: []const u8) bool {
    return std.mem.eql(u8, norm_name, "sa_task_spawn") or
        std.mem.eql(u8, norm_name, "sa_task_spawn_supervised") or
        std.mem.eql(u8, norm_name, "sa_sync_once_do");
}

/// Staged host bindings for well-known externs (fd/mmap/signal/npm).
/// These mirror the interpreter/JS staged semantics the demos assert on
/// (fake fds, echo signal, byte-level npm checks) — NOT real syscalls,
/// so output stays deterministic with no host dependencies. Emits the
/// definition with the uniform-arity signature and returns true; unknown
/// names return false and the caller falls back to the trap stub.
/// True for externs bound directly to libsa_std.a entry points (the
/// cookie, TLS client-config and sockopt passthrough families). Their
/// rendered bindings call the real sa_std functions through the
/// sa_glue_* adapters, so a program using any of them needs the
/// preamble's prototype block and the catalog helpers the adapters
/// call (both keyed off this predicate), and its final link must
/// include libsa_std.a.
fn isStdlinkExtern(norm_name: []const u8) bool {
    if (std.mem.startsWith(u8, norm_name, "sa_cookie_")) return true;
    // Goroutine family (C1): the whole task.sai surface — sa_task_*,
    // sa_chan_*, sa_sync_* — is real in libsa_std.a, so these bind
    // for real instead of trap-stubbing. Delimitation: the binding
    // renderer below covers exactly the 36 names declared in
    // sa_std/task.sai (locked by the C1 unit test); the archive's
    // task runtime itself only supports x86_64 Linux hosts, so on
    // other hosts the calls surface the runtime's ERR_UNSUPPORTED.
    if (std.mem.startsWith(u8, norm_name, "sa_task_")) return true;
    if (std.mem.startsWith(u8, norm_name, "sa_chan_")) return true;
    if (std.mem.startsWith(u8, norm_name, "sa_sync_")) return true;
    const names = [_][]const u8{
        "sa_std_tls_client_config_new",
        "sa_std_tls_client_config_free",
        "sa_std_tls_client_config_set_server_name",
        "sa_std_tls_client_config_add_ca_file",
        "sa_std_tls_client_config_add_ca_memory",
        "sa_std_tls_client_config_set_insecure_no_verification",
        "sa_std_tls_client_config_set_verify_self_signed",
        "sa_std_tls_client_peer_cert_json",
        "sa_std_tls_shaped_supported",
        "sa_std_tls_shaped_connect",
        "sa_std_tls_client_buffer_data",
        "sa_std_tls_client_buffer_len",
        "sa_std_tls_client_buffer_free",
        "sa_net_addr_family",
        "sa_net_addr_free",
        "sa_net_addr_port",
        "sa_std_net_addr_format",
        "sa_std_net_socket_getsockopt",
        "sa_std_net_socket_getsockopt_int",
        "sa_std_net_socket_setsockopt",
        "sa_std_net_socket_setsockopt_int",
        "sa_std_net_to_socket_addr_first",
        "sa_std_net_udp_bind",
        "sa_std_net_udp_broadcast",
        "sa_std_net_udp_connect_addr",
        "sa_std_net_udp_local_addr",
        "sa_std_net_udp_recv_msg",
        "sa_std_net_udp_recv_multi",
        "sa_std_net_udp_send",
        "sa_std_net_udp_set_read_timeout",
        "sa_std_net_udp_ttl",
        "sa_std_net_unix_datagram_pair",
        "sa_std_net_unix_datagram_peer_cred",
        "sa_std_net_unix_datagram_unbound",
        "sa_std_process_id",
        "sa_std_process_user_id",
    };
    for (names) |n| {
        if (std.mem.eql(u8, norm_name, n)) return true;
    }
    return false;
}

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
        str_is_ascii,
        str_eq_ignore_ascii_case,
        str_trim_ascii_start_index,
        str_trim_ascii_end_len,
        parse_float,
        math_floor,
        math_ceil,
        math_sqrt,
        math_sin,
        math_cos,
        math_pow,
        math_random,
        env_get,
        env_has,
        env_set_var,
        env_remove_var,
        env_buffer_data,
        env_buffer_len,
        env_buffer_free,
        deno_btoa_handle,
        regex_compile,
        regex_match,
        regex_group_ptr,
        regex_group_len,
        regex_group_start,
        regex_group_count,
        regex_free,
        regex_match_free,
        regex_match_all,
        regex_match_list_count,
        regex_match_list_at,
        regex_match_list_free,
        regex_replace,
        regex_replace_all,
        regex_buffer_data,
        regex_buffer_len,
        regex_buffer_free,
        regex_split,
        regex_split_count,
        regex_split_ptr,
        regex_split_len,
        regex_split_free,
        node_path_normalize,
        node_path_dirname,
        node_path_extname,
        node_path_is_absolute,
        node_path_join,
        node_qs_escape,
        node_qs_unescape,
        node_puny_encode,
        node_puny_decode,
        json_writer_new,
        json_writer_begin_object,
        json_writer_end_object,
        json_writer_begin_array,
        json_writer_end_array,
        json_writer_field_bool,
        json_writer_field_i64,
        json_writer_field_f64,
        json_writer_field_string,
        json_writer_object_field,
        json_writer_write_bool,
        json_writer_write_i64,
        json_writer_write_f64,
        json_writer_write_string,
        json_writer_write_null,
        json_writer_finish,
        json_writer_free,
        json_buffer_data,
        json_buffer_len,
        json_buffer_free,
        json_parse,
        json_free,
        json_object_get,
        json_object_get_i64,
        json_object_get_string,
        json_object_get_bool,
        json_array_get,
        json_value_count,
        json_as_i64,
        json_object_set_string,
        json_object_set_i64,
        json_object_set_f64,
        json_object_set_bool,
        json_object_set_null,
        json_object_set_node,
        json_object_remove,
        json_array_push_string,
        json_array_push_i64,
        json_array_push_f64,
        json_array_push_bool,
        json_array_push_null,
        json_array_push_node,
        node_buf_concat,
        node_rand_bytes,
        node_crypto_hash,
        deno_btoa,
        deno_atob,
        deno_read_file,
        deno_write_file,
        deno_remove,
        deno_mkdir,
        std_fs_exists,
        time_unix_ms,
        time_get_full_year,
        time_get_month,
        time_get_date,
        time_parse_iso,
        time_set_field,
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
        hc_req_new_joined,
        hc_req_openai_auth,
        hc_send_async,
        hc_op_poll,
        hc_op_take,
        hc_op_free,
        hc_resp_get_header,
        hc_resp_body_slice,
        hc_resp_body_ptr,
        hc_resp_body_len,
        hc_ws_connect,
        hc_ws_read,
        hc_ws_write,
        hc_ws_free,
        hc2_client_new,
        hc2_req_new,
        hc2_add_header,
        hc2_set_body,
        hc2_set_timeout,
        hc2_set_max,
        hc2_send,
        hc2_send_async,
        hc2_poll,
        hc2_take,
        hc2_cancel,
        hc2_free_obj,
        hc2_ws_connect4,
        hc2_ws_connect6,
        hc2_ws_connect2,
        hc2_ws_poll,
        hc2_ws_read,
        hc2_ws_write,
        hc2_ws_close,
        hc_sse_post,
        hc_sse_read,
        hc_sse_poll,
        hc_sse_status,
        hc_sse_turn,
        hc_sse_turn_free,
        hs_req_get_method,
        hs_resp_new,
        hs_check0,
        hs_resp_send,
        hs_free,
        hs_ws_upgrade,
        hs_serve_threaded,
        hs2_new,
        hs2_accept,
        hs2_ws_poll,
        hs2_ws_read,
        hs2_ws_write,
        hs2_ws_close,
        nb_compress_supported,
        nb_compress_encode,
        nb_compress_decode,
        nb_buf_data,
        nb_buf_len,
        nb_buf_free,
        mp_parse,
        mp_free,
        mp_count,
        mp_part_name,
        mp_part_filename,
        mp_part_content_type,
        mp_part_header,
        mp_part_body,
        mp_builder_new,
        mp_builder_free,
        mp_builder_add_field,
        mp_builder_add_file,
        mp_builder_boundary,
        mp_builder_content_type,
        mp_builder_finish,
        ssh_supported,
        ssh_buf_data,
        ssh_buf_len,
        ssh_buf_free,
        cookie_parse,
        cookie_last_error,
        cookie_free,
        cookie_new,
        cookie_name,
        cookie_value,
        cookie_domain,
        cookie_path,
        cookie_expires,
        cookie_max_age,
        cookie_flags,
        cookie_same_site,
        cookie_is_host_only,
        cookie_set_domain,
        cookie_set_path,
        cookie_set_expires,
        cookie_set_max_age,
        cookie_clear_expiry,
        cookie_set_secure,
        cookie_set_http_only,
        cookie_set_partitioned,
        cookie_set_same_site,
        cookie_serialize,
        cookie_serialize_pair,
        cookie_is_expired,
        cookie_domain_match,
        cookie_path_match,
        cookie_header_pair_count,
        cookie_header_pair_at,
        cookie_jar_new,
        cookie_jar_free,
        cookie_jar_set_policy,
        cookie_jar_policy,
        cookie_jar_store,
        cookie_jar_header,
        cookie_jar_count,
        cookie_jar_at,
        cookie_jar_clear,
        cookie_jar_evict_expired,
        cookie_jar_save,
        cookie_jar_load,
        cookie_jar_request_header,
        cookie_jar_store_response,
        tlscfg_new,
        tlscfg_free,
        tlscfg_set_server_name,
        tlscfg_add_ca_file,
        tlscfg_add_ca_memory,
        tlscfg_set_insecure,
        tlscfg_set_verify_self_signed,
        tls_peer_cert_json,
        tls_shaped_supported,
        tls_shaped_connect,
        tls_cbuf_data,
        tls_cbuf_len,
        tls_cbuf_free,
        na_family,
        na_free,
        na_port,
        na_format,
        sk_get,
        sk_get_int,
        sk_set,
        sk_set_int,
        na_to_first,
        udp_bind_h,
        udp_broadcast_h,
        udp_connect_addr_h,
        udp_local_addr_h,
        udp_recv_msg_h,
        udp_recv_multi_h,
        udp_send_h,
        udp_set_read_timeout_h,
        udp_ttl_h,
        unix_pair_h,
        unix_peer_cred_h,
        unix_unbound_h,
        proc_id,
        proc_user_id,
        net_unsupported8,
        task_out0,
        task_handle_ret,
        task_noargs_ret,
        task_handle_out1,
        task_chan_make,
        task_chan_send,
        task_chan_recv,
        task_spawn,
        task_spawn_supervised,
        task_trap_info,
        task_net_wait,
        task_try_lock,
        task_wg_add,
        task_once_do,
        task_select,
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
    else if (std.mem.eql(u8, name, "sa_str_is_ascii"))
        .{ .voids = all_void ^ 0b11, .tag = .str_is_ascii }
    else if (std.mem.eql(u8, name, "sa_str_eq_ignore_ascii_case"))
        .{ .voids = all_void ^ 0b1111, .tag = .str_eq_ignore_ascii_case }
    else if (std.mem.eql(u8, name, "sa_str_trim_ascii_start_index"))
        .{ .voids = all_void ^ 0b11, .tag = .str_trim_ascii_start_index }
    else if (std.mem.eql(u8, name, "sa_str_trim_ascii_end_len"))
        .{ .voids = all_void ^ 0b11, .tag = .str_trim_ascii_end_len }
    else if (std.mem.eql(u8, name, "sa_parse_float"))
        .{ .voids = all_void ^ 0b11, .tag = .parse_float }
    else if (std.mem.eql(u8, name, "sa_math_floor"))
        .{ .voids = all_void ^ 0b1, .tag = .math_floor }
    else if (std.mem.eql(u8, name, "sa_math_ceil"))
        .{ .voids = all_void ^ 0b1, .tag = .math_ceil }
    else if (std.mem.eql(u8, name, "sa_math_sqrt"))
        .{ .voids = all_void ^ 0b1, .tag = .math_sqrt }
    else if (std.mem.eql(u8, name, "sa_math_sin"))
        .{ .voids = all_void ^ 0b1, .tag = .math_sin }
    else if (std.mem.eql(u8, name, "sa_math_cos"))
        .{ .voids = all_void ^ 0b1, .tag = .math_cos }
    else if (std.mem.eql(u8, name, "sa_math_pow"))
        .{ .voids = all_void ^ 0b11, .tag = .math_pow }
    else if (std.mem.eql(u8, name, "sa_math_random"))
        .{ .voids = all_void, .tag = .math_random }
    else if (std.mem.eql(u8, name, "sa_env_get"))
        .{ .voids = all_void ^ 0b11, .tag = .env_get }
    else if (std.mem.eql(u8, name, "sa_env_has"))
        .{ .voids = all_void ^ 0b11, .tag = .env_has }
    else if (std.mem.eql(u8, name, "sa_env_set_var"))
        .{ .voids = all_void ^ 0b1111, .tag = .env_set_var }
    else if (std.mem.eql(u8, name, "sa_env_remove_var"))
        .{ .voids = all_void ^ 0b11, .tag = .env_remove_var }
    else if (std.mem.eql(u8, name, "sa_env_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .env_buffer_data }
    else if (std.mem.eql(u8, name, "sa_env_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .env_buffer_len }
    else if (std.mem.eql(u8, name, "sa_env_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .env_buffer_free }
    else if (std.mem.eql(u8, name, "sa_deno_btoa"))
        .{ .voids = all_void ^ 0b11, .tag = .deno_btoa_handle }
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
    else if (std.mem.eql(u8, name, "sa_regex_match_all"))
        .{ .voids = all_void ^ 0b111, .tag = .regex_match_all }
    else if (std.mem.eql(u8, name, "sa_regex_match_list_count"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_match_list_count }
    else if (std.mem.eql(u8, name, "sa_regex_match_list_at"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_match_list_at }
    else if (std.mem.eql(u8, name, "sa_regex_match_list_free"))
        .{ .voids = all_void, .tag = .regex_match_list_free }
    else if (std.mem.eql(u8, name, "sa_regex_replace"))
        .{ .voids = all_void ^ 0b11111, .tag = .regex_replace }
    else if (std.mem.eql(u8, name, "sa_regex_replace_all"))
        .{ .voids = all_void ^ 0b11111, .tag = .regex_replace_all }
    else if (std.mem.eql(u8, name, "sa_regex_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_buffer_data }
    else if (std.mem.eql(u8, name, "sa_regex_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_buffer_len }
    else if (std.mem.eql(u8, name, "sa_regex_buffer_free"))
        .{ .voids = all_void, .tag = .regex_buffer_free }
    else if (std.mem.eql(u8, name, "sa_regex_split"))
        .{ .voids = all_void ^ 0b1111, .tag = .regex_split }
    else if (std.mem.eql(u8, name, "sa_regex_split_count"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_split_count }
    else if (std.mem.eql(u8, name, "sa_regex_split_ptr"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_split_ptr }
    else if (std.mem.eql(u8, name, "sa_regex_split_len"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_split_len }
    else if (std.mem.eql(u8, name, "sa_regex_split_free"))
        .{ .voids = all_void, .tag = .regex_split_free }
    else if (std.mem.eql(u8, name, "sa_time_unix_ms"))
        .{ .voids = all_void, .tag = .time_unix_ms }
    else if (std.mem.eql(u8, name, "sa_time_get_full_year"))
        .{ .voids = all_void ^ 0b1, .tag = .time_get_full_year }
    else if (std.mem.eql(u8, name, "sa_time_get_month"))
        .{ .voids = all_void ^ 0b1, .tag = .time_get_month }
    else if (std.mem.eql(u8, name, "sa_time_get_date"))
        .{ .voids = all_void ^ 0b1, .tag = .time_get_date }
    else if (std.mem.eql(u8, name, "sa_time_parse_iso"))
        .{ .voids = all_void ^ 0b111, .tag = .time_parse_iso }
    else if (std.mem.eql(u8, name, "sa_time_set_field"))
        .{ .voids = all_void ^ 0b111, .tag = .time_set_field }
    else if (std.mem.eql(u8, name, "sa_node_plugin_path_normalize"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_path_normalize }
    else if (std.mem.eql(u8, name, "sa_node_plugin_path_dirname"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_path_dirname }
    else if (std.mem.eql(u8, name, "sa_node_plugin_path_extname"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_path_extname }
    else if (std.mem.eql(u8, name, "sa_node_plugin_path_is_absolute"))
        .{ .voids = all_void ^ 0b111, .tag = .node_path_is_absolute }
    else if (std.mem.eql(u8, name, "sa_node_plugin_path_join"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_path_join }
    else if (std.mem.eql(u8, name, "sa_node_plugin_querystring_escape"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_qs_escape }
    else if (std.mem.eql(u8, name, "sa_node_plugin_querystring_unescape"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_qs_unescape }
    else if (std.mem.eql(u8, name, "sa_node_plugin_punycode_encode"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_puny_encode }
    else if (std.mem.eql(u8, name, "sa_node_plugin_punycode_decode"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_puny_decode }
    else if (std.mem.eql(u8, name, "sa_json_writer_new"))
        .{ .voids = all_void ^ 0b100000, .tag = .json_writer_new }
    else if (std.mem.eql(u8, name, "sa_json_writer_begin_object"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_begin_object }
    else if (std.mem.eql(u8, name, "sa_json_writer_end_object"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_end_object }
    else if (std.mem.eql(u8, name, "sa_json_writer_begin_array"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_begin_array }
    else if (std.mem.eql(u8, name, "sa_json_writer_end_array"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_end_array }
    else if (std.mem.eql(u8, name, "sa_json_writer_field_bool"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_writer_field_bool }
    else if (std.mem.eql(u8, name, "sa_json_writer_field_i64"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_writer_field_i64 }
    else if (std.mem.eql(u8, name, "sa_json_writer_field_f64"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_writer_field_f64 }
    else if (std.mem.eql(u8, name, "sa_json_writer_field_string"))
        .{ .voids = all_void ^ 0b11111, .tag = .json_writer_field_string }
    else if (std.mem.eql(u8, name, "sa_json_writer_object_field"))
        .{ .voids = all_void ^ 0b111, .tag = .json_writer_object_field }
    else if (std.mem.eql(u8, name, "sa_json_writer_write_bool"))
        .{ .voids = all_void ^ 0b11, .tag = .json_writer_write_bool }
    else if (std.mem.eql(u8, name, "sa_json_writer_write_i64"))
        .{ .voids = all_void ^ 0b11, .tag = .json_writer_write_i64 }
    else if (std.mem.eql(u8, name, "sa_json_writer_write_f64"))
        .{ .voids = all_void ^ 0b11, .tag = .json_writer_write_f64 }
    else if (std.mem.eql(u8, name, "sa_json_writer_write_string"))
        .{ .voids = all_void ^ 0b111, .tag = .json_writer_write_string }
    else if (std.mem.eql(u8, name, "sa_json_writer_write_null"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_write_null }
    else if (std.mem.eql(u8, name, "sa_json_writer_finish"))
        .{ .voids = all_void ^ 0b11, .tag = .json_writer_finish }
    else if (std.mem.eql(u8, name, "sa_json_writer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_free }
    else if (std.mem.eql(u8, name, "sa_json_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .json_buffer_data }
    else if (std.mem.eql(u8, name, "sa_json_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .json_buffer_len }
    else if (std.mem.eql(u8, name, "sa_json_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .json_buffer_free }
    else if (std.mem.eql(u8, name, "sa_json_parse"))
        .{ .voids = all_void ^ 0b11, .tag = .json_parse }
    else if (std.mem.eql(u8, name, "sa_json_free"))
        .{ .voids = all_void ^ 0b1, .tag = .json_free }
    else if (std.mem.eql(u8, name, "sa_json_object_get"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_get }
    else if (std.mem.eql(u8, name, "sa_json_object_get_i64"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_get_i64 }
    else if (std.mem.eql(u8, name, "sa_json_object_get_string"))
        .{ .voids = all_void ^ 0b11111, .tag = .json_object_get_string }
    else if (std.mem.eql(u8, name, "sa_json_object_get_bool"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_get_bool }
    else if (std.mem.eql(u8, name, "sa_json_array_get"))
        .{ .voids = all_void ^ 0b111, .tag = .json_array_get }
    else if (std.mem.eql(u8, name, "sa_json_value_count"))
        .{ .voids = all_void ^ 0b11, .tag = .json_value_count }
    else if (std.mem.eql(u8, name, "sa_json_object_set_string"))
        .{ .voids = all_void ^ 0b11111, .tag = .json_object_set_string }
    else if (std.mem.eql(u8, name, "sa_json_object_set_i64"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_set_i64 }
    else if (std.mem.eql(u8, name, "sa_json_object_set_f64"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_set_f64 }
    else if (std.mem.eql(u8, name, "sa_json_object_set_bool"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_set_bool }
    else if (std.mem.eql(u8, name, "sa_json_object_set_null"))
        .{ .voids = all_void ^ 0b111, .tag = .json_object_set_null }
    else if (std.mem.eql(u8, name, "sa_json_object_set_node"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_set_node }
    else if (std.mem.eql(u8, name, "sa_json_object_remove"))
        .{ .voids = all_void ^ 0b111, .tag = .json_object_remove }
    else if (std.mem.eql(u8, name, "sa_json_array_push_string"))
        .{ .voids = all_void ^ 0b111, .tag = .json_array_push_string }
    else if (std.mem.eql(u8, name, "sa_json_array_push_i64"))
        .{ .voids = all_void ^ 0b11, .tag = .json_array_push_i64 }
    else if (std.mem.eql(u8, name, "sa_json_array_push_f64"))
        .{ .voids = all_void ^ 0b11, .tag = .json_array_push_f64 }
    else if (std.mem.eql(u8, name, "sa_json_array_push_bool"))
        .{ .voids = all_void ^ 0b11, .tag = .json_array_push_bool }
    else if (std.mem.eql(u8, name, "sa_json_array_push_null"))
        .{ .voids = all_void ^ 0b1, .tag = .json_array_push_null }
    else if (std.mem.eql(u8, name, "sa_json_array_push_node"))
        .{ .voids = all_void ^ 0b11, .tag = .json_array_push_node }
    else if (std.mem.eql(u8, name, "sa_json_as_i64"))
        .{ .voids = all_void ^ 0b11, .tag = .json_as_i64 }
    else if (std.mem.eql(u8, name, "sa_node_plugin_buffer_concat"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_buf_concat }
    else if (std.mem.eql(u8, name, "sa_node_plugin_crypto_random_bytes"))
        .{ .voids = all_void ^ 0b11, .tag = .node_rand_bytes }
    else if (std.mem.eql(u8, name, "sa_node_plugin_crypto_hash"))
        .{ .voids = all_void ^ 0b111111, .tag = .node_crypto_hash }
    else if (std.mem.eql(u8, name, "sa_std_fs_exists"))
        .{ .voids = all_void ^ 0b11, .tag = .std_fs_exists }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_btoa"))
        .{ .voids = all_void ^ 0b1111, .tag = .deno_btoa }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_atob"))
        .{ .voids = all_void ^ 0b1111, .tag = .deno_atob }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_read_text_file"))
        .{ .voids = all_void ^ 0b1111, .tag = .deno_read_file }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_write_text_file"))
        .{ .voids = all_void ^ 0b1111, .tag = .deno_write_file }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_remove"))
        .{ .voids = all_void, .tag = .deno_remove }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_mkdir"))
        .{ .voids = all_void ^ 0b111, .tag = .deno_mkdir }
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
    else if (std.mem.eql(u8, name, "sa_http_client_req_new_joined"))
        .{ .voids = all_void ^ 0b11111111, .tag = .hc_req_new_joined }
    else if (std.mem.eql(u8, name, "sa_http_client_req_add_openai_auth"))
        .{ .voids = all_void ^ 0b111, .tag = .hc_req_openai_auth }
    else if (std.mem.eql(u8, name, "sa_http_client_req_send_async"))
        .{ .voids = all_void ^ 0b11, .tag = .hc_send_async }
    else if (std.mem.eql(u8, name, "sa_http_client_async_poll"))
        .{ .voids = all_void ^ 0b11, .tag = .hc_op_poll }
    else if (std.mem.eql(u8, name, "sa_http_client_async_take_response"))
        .{ .voids = all_void ^ 0b11, .tag = .hc_op_take }
    else if (std.mem.eql(u8, name, "sa_http_client_async_free"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_op_free }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_get_header"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc_resp_get_header }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_body_slice"))
        .{ .voids = all_void ^ 0b111, .tag = .hc_resp_body_slice }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_body_ptr"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_resp_body_ptr }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_body_len"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_resp_body_len }
    else if (std.mem.eql(u8, name, "sa_http_client_websocket_connect"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc_ws_connect }
    else if (std.mem.eql(u8, name, "sa_http_websocket_read"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc_ws_read }
    else if (std.mem.eql(u8, name, "sa_http_websocket_write"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc_ws_write }
    else if (std.mem.eql(u8, name, "sa_http_websocket_free"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_ws_free }
    else if (std.mem.eql(u8, name, "sa_http_client_new_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc2_client_new }
    else if (std.mem.eql(u8, name, "sa_http_client_req_new_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_req_new }
    else if (std.mem.eql(u8, name, "sa_http_client_req_add_header_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_add_header }
    else if (std.mem.eql(u8, name, "sa_http_client_req_set_body_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hc2_set_body }
    else if (std.mem.eql(u8, name, "sa_http_client_req_set_timeout_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hc2_set_timeout }
    else if (std.mem.eql(u8, name, "sa_http_client_req_set_max_response_bytes_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hc2_set_max }
    else if (std.mem.eql(u8, name, "sa_http_client_req_send_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hc2_send }
    else if (std.mem.eql(u8, name, "sa_http_client_req_send_async_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hc2_send_async }
    else if (std.mem.eql(u8, name, "sa_http_client_async_poll_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hc2_poll }
    else if (std.mem.eql(u8, name, "sa_http_client_async_take_response_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hc2_take }
    else if (std.mem.eql(u8, name, "sa_http_client_async_cancel_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hc2_cancel }
    else if (std.mem.eql(u8, name, "sa_http_client_async_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hc2_free_obj }
    else if (std.mem.eql(u8, name, "sa_http_client_websocket_connect_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_ws_connect4 }
    else if (std.mem.eql(u8, name, "sa_http_client_websocket_connect_unix_v2"))
        .{ .voids = all_void ^ 0b1111111, .tag = .hc2_ws_connect6 }
    else if (std.mem.eql(u8, name, "sa_http_client_req_websocket_connect_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hc2_ws_connect2 }
    else if (std.mem.eql(u8, name, "sa_http_client_req_websocket_connect_unix_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_ws_connect4 }
    else if (std.mem.eql(u8, name, "sa_http_websocket_poll_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc2_ws_poll }
    else if (std.mem.eql(u8, name, "sa_http_websocket_read_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_ws_read }
    else if (std.mem.eql(u8, name, "sa_http_websocket_write_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_ws_write }
    else if (std.mem.eql(u8, name, "sa_http_websocket_close_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc2_ws_close }
    else if (std.mem.eql(u8, name, "sa_http_websocket_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_ws_free }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_post"))
        .{ .voids = all_void ^ 0b1111111, .tag = .hc_sse_post }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_read"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc_sse_read }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_poll"))
        .{ .voids = all_void ^ 0b11, .tag = .hc_sse_poll }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_status"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_sse_status }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_free"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_op_free }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_turn"))
        .{ .voids = all_void ^ 0b11111111111, .tag = .hc_sse_turn }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_turn_free"))
        .{ .voids = all_void ^ 0b11, .tag = .hc_sse_turn_free }
    else if (std.mem.eql(u8, name, "sa_http_server_req_get_method"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_req_get_method }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_new"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_resp_new }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_set_content_type"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_send"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_resp_send }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_free"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_free }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_upgrade"))
        .{ .voids = all_void ^ 0b11, .tag = .hs_ws_upgrade }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_read"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc_ws_read }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_write"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc_ws_write }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_free"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_ws_free }
    else if (std.mem.eql(u8, name, "sa_http_server_serve_threaded"))
        .{ .voids = all_void ^ 0b11111, .tag = .hs_serve_threaded }
    else if (std.mem.eql(u8, name, "sa_http_server_stop_serving"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_set_max_body_bytes"))
        .{ .voids = all_void ^ 0b11, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_new_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs2_new }
    else if (std.mem.eql(u8, name, "sa_http_server_start_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_accept_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hs2_accept }
    else if (std.mem.eql(u8, name, "sa_http_server_req_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_free }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_new_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_resp_new }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_add_header_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_send_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hs_resp_send }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_free }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_new_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_resp_new }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_add_header_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_write_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hs_resp_send }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_flush_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_end_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_free }
    else if (std.mem.eql(u8, name, "sa_http_server_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_free }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_upgrade_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hs_ws_upgrade }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_poll_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hs2_ws_poll }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_read_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hs2_ws_read }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_write_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hs2_ws_write }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_close_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hs2_ws_close }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_ws_free }
    else if (std.mem.eql(u8, name, "sa_std_compress_supported"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_compress_supported }
    else if (std.mem.eql(u8, name, "sa_std_compress_encode"))
        .{ .voids = all_void ^ 0b1111, .tag = .nb_compress_encode }
    else if (std.mem.eql(u8, name, "sa_std_compress_decode"))
        .{ .voids = all_void ^ 0b1111, .tag = .nb_compress_decode }
    else if (std.mem.eql(u8, name, "sa_std_compress_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_data }
    else if (std.mem.eql(u8, name, "sa_std_compress_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_len }
    else if (std.mem.eql(u8, name, "sa_std_compress_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_free }
    else if (std.mem.eql(u8, name, "sa_std_multipart_parse"))
        .{ .voids = all_void ^ 0b11111, .tag = .mp_parse }
    else if (std.mem.eql(u8, name, "sa_std_multipart_free"))
        .{ .voids = all_void ^ 0b1, .tag = .mp_free }
    else if (std.mem.eql(u8, name, "sa_std_multipart_count"))
        .{ .voids = all_void ^ 0b1, .tag = .mp_count }
    else if (std.mem.eql(u8, name, "sa_std_multipart_part_name"))
        .{ .voids = all_void ^ 0b11111, .tag = .mp_part_name }
    else if (std.mem.eql(u8, name, "sa_std_multipart_part_filename"))
        .{ .voids = all_void ^ 0b11111, .tag = .mp_part_filename }
    else if (std.mem.eql(u8, name, "sa_std_multipart_part_content_type"))
        .{ .voids = all_void ^ 0b11111, .tag = .mp_part_content_type }
    else if (std.mem.eql(u8, name, "sa_std_multipart_part_header"))
        .{ .voids = all_void ^ 0b1111111, .tag = .mp_part_header }
    else if (std.mem.eql(u8, name, "sa_std_multipart_part_body"))
        .{ .voids = all_void ^ 0b1111, .tag = .mp_part_body }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_new"))
        .{ .voids = all_void ^ 0b1, .tag = .mp_builder_new }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_free"))
        .{ .voids = all_void ^ 0b1, .tag = .mp_builder_free }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_add_field"))
        .{ .voids = all_void ^ 0b11111, .tag = .mp_builder_add_field }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_add_file"))
        .{ .voids = all_void ^ 0b111111111, .tag = .mp_builder_add_file }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_boundary"))
        .{ .voids = all_void ^ 0b1111, .tag = .mp_builder_boundary }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_content_type"))
        .{ .voids = all_void ^ 0b1111, .tag = .mp_builder_content_type }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_finish"))
        .{ .voids = all_void ^ 0b11, .tag = .mp_builder_finish }
    else if (std.mem.eql(u8, name, "sa_std_multipart_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_data }
    else if (std.mem.eql(u8, name, "sa_std_multipart_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_len }
    else if (std.mem.eql(u8, name, "sa_std_multipart_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_free }
    else if (std.mem.eql(u8, name, "sa_std_ssh_supported"))
        .{ .voids = all_void ^ 0b1, .tag = .ssh_supported }
    else if (std.mem.eql(u8, name, "sa_std_ssh_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .ssh_buf_data }
    else if (std.mem.eql(u8, name, "sa_std_ssh_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .ssh_buf_len }
    else if (std.mem.eql(u8, name, "sa_std_ssh_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .ssh_buf_free }
    else if (std.mem.eql(u8, name, "sa_std_ssh_client_connect"))
        .{ .voids = all_void ^ 0b1111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_hostkey_fingerprint"))
        .{ .voids = all_void ^ 0b1111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_auth_password"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_auth_keyfile"))
        .{ .voids = all_void ^ 0b111111111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_exec"))
        .{ .voids = all_void ^ 0b111111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_sftp_read"))
        .{ .voids = all_void ^ 0b1111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_sftp_write"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_sftp_stat"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_session_close"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_listen"))
        .{ .voids = all_void ^ 0b111111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_bind_close"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_accept"))
        .{ .voids = all_void ^ 0b11, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_next"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_accept"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_deny"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_channel_accept"))
        .{ .voids = all_void ^ 0b11, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_channel_exec"))
        .{ .voids = all_void ^ 0b111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_channel_write"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_channel_read"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_channel_send_exit"))
        .{ .voids = all_void ^ 0b11, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_channel_close"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_session_close"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
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
    else if (std.mem.eql(u8, name, "sa_cookie_parse_set_cookie"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_parse }
    else if (std.mem.eql(u8, name, "sa_cookie_last_error"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_last_error }
    else if (std.mem.eql(u8, name, "sa_cookie_free"))
        .{ .voids = all_void ^ 0b1, .tag = .cookie_free }
    else if (std.mem.eql(u8, name, "sa_cookie_new"))
        .{ .voids = all_void ^ 0b1111, .tag = .cookie_new }
    else if (std.mem.eql(u8, name, "sa_cookie_name"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_name }
    else if (std.mem.eql(u8, name, "sa_cookie_value"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_value }
    else if (std.mem.eql(u8, name, "sa_cookie_domain"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_domain }
    else if (std.mem.eql(u8, name, "sa_cookie_path"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_path }
    else if (std.mem.eql(u8, name, "sa_cookie_expires"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_expires }
    else if (std.mem.eql(u8, name, "sa_cookie_max_age"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_max_age }
    else if (std.mem.eql(u8, name, "sa_cookie_flags"))
        .{ .voids = all_void ^ 0b1111, .tag = .cookie_flags }
    else if (std.mem.eql(u8, name, "sa_cookie_same_site"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_same_site }
    else if (std.mem.eql(u8, name, "sa_cookie_is_host_only"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_is_host_only }
    else if (std.mem.eql(u8, name, "sa_cookie_set_domain"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_set_domain }
    else if (std.mem.eql(u8, name, "sa_cookie_set_path"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_set_path }
    else if (std.mem.eql(u8, name, "sa_cookie_set_expires"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_expires }
    else if (std.mem.eql(u8, name, "sa_cookie_set_max_age"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_max_age }
    else if (std.mem.eql(u8, name, "sa_cookie_clear_expiry"))
        .{ .voids = all_void ^ 0b1, .tag = .cookie_clear_expiry }
    else if (std.mem.eql(u8, name, "sa_cookie_set_secure"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_secure }
    else if (std.mem.eql(u8, name, "sa_cookie_set_http_only"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_http_only }
    else if (std.mem.eql(u8, name, "sa_cookie_set_partitioned"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_partitioned }
    else if (std.mem.eql(u8, name, "sa_cookie_set_same_site"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_same_site }
    else if (std.mem.eql(u8, name, "sa_cookie_serialize"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_serialize }
    else if (std.mem.eql(u8, name, "sa_cookie_serialize_pair"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_serialize_pair }
    else if (std.mem.eql(u8, name, "sa_cookie_is_expired"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_is_expired }
    else if (std.mem.eql(u8, name, "sa_cookie_domain_match"))
        .{ .voids = all_void ^ 0b11111, .tag = .cookie_domain_match }
    else if (std.mem.eql(u8, name, "sa_cookie_path_match"))
        .{ .voids = all_void ^ 0b11111, .tag = .cookie_path_match }
    else if (std.mem.eql(u8, name, "sa_cookie_header_pair_count"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_header_pair_count }
    else if (std.mem.eql(u8, name, "sa_cookie_header_pair_at"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_header_pair_at }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_new"))
        .{ .voids = all_void, .tag = .cookie_jar_new }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_free"))
        .{ .voids = all_void ^ 0b1, .tag = .cookie_jar_free }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_set_policy"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_jar_set_policy }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_policy"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_jar_policy }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_store"))
        .{ .voids = all_void ^ 0b1111111, .tag = .cookie_jar_store }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_header"))
        .{ .voids = all_void ^ 0b111111, .tag = .cookie_jar_header }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_count"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_jar_count }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_at"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_jar_at }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_clear"))
        .{ .voids = all_void ^ 0b1, .tag = .cookie_jar_clear }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_evict_expired"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_jar_evict_expired }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_save"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_jar_save }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_load"))
        .{ .voids = all_void ^ 0b1111, .tag = .cookie_jar_load }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_request_header"))
        .{ .voids = all_void ^ 0b11111, .tag = .cookie_jar_request_header }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_store_response"))
        .{ .voids = all_void ^ 0b11111, .tag = .cookie_jar_store_response }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_new"))
        .{ .voids = all_void ^ 0b1, .tag = .tlscfg_new }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_free"))
        .{ .voids = all_void ^ 0b1, .tag = .tlscfg_free }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_server_name"))
        .{ .voids = all_void ^ 0b111, .tag = .tlscfg_set_server_name }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_add_ca_file"))
        .{ .voids = all_void ^ 0b111, .tag = .tlscfg_add_ca_file }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_add_ca_memory"))
        .{ .voids = all_void ^ 0b111, .tag = .tlscfg_add_ca_memory }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_insecure_no_verification"))
        .{ .voids = all_void ^ 0b11, .tag = .tlscfg_set_insecure }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_verify_self_signed"))
        .{ .voids = all_void ^ 0b11, .tag = .tlscfg_set_verify_self_signed }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_peer_cert_json"))
        .{ .voids = all_void ^ 0b11, .tag = .tls_peer_cert_json }
    else if (std.mem.eql(u8, name, "sa_std_tls_shaped_supported"))
        .{ .voids = all_void ^ 0b1, .tag = .tls_shaped_supported }
    else if (std.mem.eql(u8, name, "sa_std_tls_shaped_connect"))
        .{ .voids = all_void ^ 0b111111, .tag = .tls_shaped_connect }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .tls_cbuf_data }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .tls_cbuf_len }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .tls_cbuf_free }
    else if (std.mem.eql(u8, name, "sa_net_addr_family"))
        .{ .voids = all_void ^ 0b1, .tag = .na_family }
    else if (std.mem.eql(u8, name, "sa_net_addr_free"))
        .{ .voids = all_void ^ 0b1, .tag = .na_free }
    else if (std.mem.eql(u8, name, "sa_net_addr_port"))
        .{ .voids = all_void ^ 0b1, .tag = .na_port }
    else if (std.mem.eql(u8, name, "sa_std_net_addr_format"))
        .{ .voids = all_void ^ 0b1111, .tag = .na_format }
    else if (std.mem.eql(u8, name, "sa_std_net_socket_getsockopt"))
        .{ .voids = all_void ^ 0b111111, .tag = .sk_get }
    else if (std.mem.eql(u8, name, "sa_std_net_socket_getsockopt_int"))
        .{ .voids = all_void ^ 0b1111, .tag = .sk_get_int }
    else if (std.mem.eql(u8, name, "sa_std_net_socket_setsockopt"))
        .{ .voids = all_void ^ 0b11111, .tag = .sk_set }
    else if (std.mem.eql(u8, name, "sa_std_net_socket_setsockopt_int"))
        .{ .voids = all_void ^ 0b1111, .tag = .sk_set_int }
    else if (std.mem.eql(u8, name, "sa_std_net_to_socket_addr_first"))
        .{ .voids = all_void ^ 0b1111, .tag = .na_to_first }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_bind"))
        .{ .voids = all_void ^ 0b1111, .tag = .udp_bind_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_broadcast"))
        .{ .voids = all_void ^ 0b11, .tag = .udp_broadcast_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_connect_addr"))
        .{ .voids = all_void ^ 0b11, .tag = .udp_connect_addr_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_local_addr"))
        .{ .voids = all_void ^ 0b11, .tag = .udp_local_addr_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_recv_msg"))
        .{ .voids = all_void ^ 0b111111111, .tag = .udp_recv_msg_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_recv_multi"))
        .{ .voids = all_void ^ 0b11111111, .tag = .udp_recv_multi_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_send"))
        .{ .voids = all_void ^ 0b1111, .tag = .udp_send_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_set_read_timeout"))
        .{ .voids = all_void ^ 0b11, .tag = .udp_set_read_timeout_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_ttl"))
        .{ .voids = all_void ^ 0b11, .tag = .udp_ttl_h }
    else if (std.mem.eql(u8, name, "sa_std_net_unix_datagram_pair"))
        .{ .voids = all_void ^ 0b11, .tag = .unix_pair_h }
    else if (std.mem.eql(u8, name, "sa_std_net_unix_datagram_peer_cred"))
        .{ .voids = all_void ^ 0b1111, .tag = .unix_peer_cred_h }
    else if (std.mem.eql(u8, name, "sa_std_net_unix_datagram_unbound"))
        .{ .voids = all_void ^ 0b1, .tag = .unix_unbound_h }
    else if (std.mem.eql(u8, name, "sa_std_process_id"))
        .{ .voids = all_void, .tag = .proc_id }
    else if (std.mem.eql(u8, name, "sa_std_process_user_id"))
        .{ .voids = all_void, .tag = .proc_user_id }
        // Goroutine family (C1): exactly the 36 externs of sa_std/task.sai.
    else if (std.mem.eql(u8, name, "sa_task_spawn"))
        .{ .voids = all_void ^ 0b111, .tag = .task_spawn }
    else if (std.mem.eql(u8, name, "sa_task_spawn_supervised"))
        .{ .voids = all_void ^ 0b11111, .tag = .task_spawn_supervised }
    else if (std.mem.eql(u8, name, "sa_task_trap_info"))
        .{ .voids = all_void ^ 0b1111, .tag = .task_trap_info }
    else if (std.mem.eql(u8, name, "sa_task_monitor"))
        .{ .voids = all_void ^ 0b11, .tag = .task_handle_out1 }
    else if (std.mem.eql(u8, name, "sa_task_yield"))
        .{ .voids = all_void, .tag = .task_noargs_ret }
    else if (std.mem.eql(u8, name, "sa_task_sleep_ns"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_task_sleep_ms"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_task_join"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_task_detach"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_task_current"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_task_live_count"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_task_deadlock_guard_arm"))
        .{ .voids = all_void, .tag = .task_noargs_ret }
    else if (std.mem.eql(u8, name, "sa_task_net_wait"))
        .{ .voids = all_void ^ 0b1111, .tag = .task_net_wait }
    else if (std.mem.eql(u8, name, "sa_chan_make"))
        .{ .voids = all_void ^ 0b11, .tag = .task_chan_make }
    else if (std.mem.eql(u8, name, "sa_chan_destroy"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_chan_close"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_chan_send"))
        .{ .voids = all_void ^ 0b11, .tag = .task_chan_send }
    else if (std.mem.eql(u8, name, "sa_chan_recv"))
        .{ .voids = all_void ^ 0b111, .tag = .task_chan_recv }
    else if (std.mem.eql(u8, name, "sa_chan_len"))
        .{ .voids = all_void ^ 0b11, .tag = .task_handle_out1 }
    else if (std.mem.eql(u8, name, "sa_chan_cap"))
        .{ .voids = all_void ^ 0b11, .tag = .task_handle_out1 }
    else if (std.mem.eql(u8, name, "sa_chan_select"))
        .{ .voids = all_void ^ 0b11111111, .tag = .task_select }
    else if (std.mem.eql(u8, name, "sa_sync_mutex_new"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_sync_rwlock_new"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_sync_waitgroup_new"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_sync_once_new"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_sync_destroy"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_mutex_lock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_mutex_try_lock"))
        .{ .voids = all_void ^ 0b11, .tag = .task_try_lock }
    else if (std.mem.eql(u8, name, "sa_sync_mutex_unlock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_rwlock_rlock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_rwlock_runlock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_rwlock_lock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_rwlock_unlock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_waitgroup_add"))
        .{ .voids = all_void ^ 0b11, .tag = .task_wg_add }
    else if (std.mem.eql(u8, name, "sa_sync_waitgroup_done"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_waitgroup_wait"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_once_do"))
        .{ .voids = all_void ^ 0b111, .tag = .task_once_do }
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
        .str_is_ascii => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" if (sa_mem[x + i] > 0x7F) return 0;");
            try writer.writeAll(" return 1; } }\n");
        },
        .str_eq_ignore_ascii_case => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" if (a1 != a3) return 0;");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a1; i++) {");
            try writer.writeAll(" uint8_t l = sa_mem[x + i]; uint8_t r = sa_mem[y + i];");
            try writer.writeAll(" if (l >= 'A' && l <= 'Z') l += (uint8_t)('a' - 'A');");
            try writer.writeAll(" if (r >= 'A' && r <= 'Z') r += (uint8_t)('a' - 'A');");
            try writer.writeAll(" if (l != r) return 0; } }");
            try writer.writeAll(" return 1; } }\n");
        },
        .str_trim_ascii_start_index => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" size_t i = 0;");
            try writer.writeAll(" while (i < (size_t)a1) { uint8_t c = sa_mem[x + i];");
            try writer.writeAll(" if (c != ' ' && c != '\\t' && c != '\\n' && c != '\\r' && c != 0x0B && c != 0x0C) break; i++; }");
            try writer.writeAll(" return (sa_u64)i; } }\n");
        },
        .str_trim_ascii_end_len => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" size_t e = (size_t)a1;");
            try writer.writeAll(" while (e > 0) { uint8_t c = sa_mem[x + e - 1];");
            try writer.writeAll(" if (c != ' ' && c != '\\t' && c != '\\n' && c != '\\r' && c != 0x0B && c != 0x0C) break; e--; }");
            try writer.writeAll(" return (sa_u64)e; } }\n");
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
        .math_floor => {
            // libm floor over the f64 bit pattern (mirrors sa_math_floor).
            try writer.writeAll(" { union { sa_u64 u; double v; } t; t.u = a0; t.v = floor(t.v); return t.u; } }\n");
        },
        .math_ceil => {
            try writer.writeAll(" { union { sa_u64 u; double v; } t; t.u = a0; t.v = ceil(t.v); return t.u; } }\n");
        },
        .math_sqrt => {
            // C sqrt of a negative is NaN, matching Zig @sqrt.
            try writer.writeAll(" { union { sa_u64 u; double v; } t; t.u = a0; t.v = sqrt(t.v); return t.u; } }\n");
        },
        .math_sin => {
            try writer.writeAll(" { union { sa_u64 u; double v; } t; t.u = a0; t.v = sin(t.v); return t.u; } }\n");
        },
        .math_cos => {
            try writer.writeAll(" { union { sa_u64 u; double v; } t; t.u = a0; t.v = cos(t.v); return t.u; } }\n");
        },
        .math_pow => {
            try writer.writeAll(" { union { sa_u64 u; double v; } x; union { sa_u64 u; double v; } y; x.u = a0; y.u = a1; x.v = pow(x.v, y.v); return x.u; } }\n");
        },
        .math_random => {
            // Native sa_math_random is crypto-random in [0, 1), so exact
            // values can never match across backends; the binding keeps
            // the same 53-bit draw shape with a deterministic LCG state,
            // per this backend's determinism rule for staged bindings.
            try writer.writeAll(" { static sa_u64 st = (sa_u64)0x9E3779B97F4A7C15ULL; st = st * (sa_u64)6364136223846793005ULL + (sa_u64)1442695040888963407ULL; union { sa_u64 u; double v; } t; t.v = (double)(st >> 11) * (1.0 / 9007199254740992.0); return t.u; } }\n");
        },
        .env_get => {
            // Real host environment via libc (the native binding reads
            // the same process env); the value is copied into an owned
            // buffer of kind 4, the env-buffer registry kind.
            try writer.writeAll(" { if (a1 > 4096) return 0; char kb[4097]; uint32_t s = sa_checked_addr(a0, (size_t)a1); sa_u64 i; for (i = 0; i < a1; i++) kb[i] = (char)sa_mem[s + i]; kb[a1] = 0; const char *v = getenv(kb); if (v == 0) return 0; size_t n = strlen(v); sa_u64 p = sa_alloc(n == 0 ? 1 : (sa_u64)n); uint32_t d = sa_checked_addr(p, n == 0 ? 1 : n); size_t j; for (j = 0; j < n; j++) sa_mem[d + j] = (uint8_t)v[j]; return sa_owned_new(p, (sa_u64)n, 4); } }\n");
        },
        .env_has => {
            // Status semantics mirror the native binding: 0 = present,
            // 3 = SA_STD_ERR_NOT_FOUND.
            try writer.writeAll(" { if (a1 > 4096) return 1; char kb[4097]; uint32_t s = sa_checked_addr(a0, (size_t)a1); sa_u64 i; for (i = 0; i < a1; i++) kb[i] = (char)sa_mem[s + i]; kb[a1] = 0; return getenv(kb) != 0 ? 0 : 3; } }\n");
        },
        .env_set_var => {
            try writer.writeAll(" { if (a1 > 4096 || a3 > 1048576) return 1; char kb[4097]; char *vb = (char *)malloc(a3 + 1); if (vb == 0) return 6; uint32_t s = sa_checked_addr(a0, (size_t)a1); uint32_t t = sa_checked_addr(a2, (size_t)a3); sa_u64 i; for (i = 0; i < a1; i++) kb[i] = (char)sa_mem[s + i]; kb[a1] = 0; for (i = 0; i < a3; i++) { if (sa_mem[t + i] == 0) { free(vb); return 1; } vb[i] = (char)sa_mem[t + i]; } vb[a3] = 0; int rc = setenv(kb, vb, 1); free(vb); return rc == 0 ? 0 : 6; } }\n");
        },
        .env_remove_var => {
            try writer.writeAll(" { if (a1 > 4096) return 1; char kb[4097]; uint32_t s = sa_checked_addr(a0, (size_t)a1); sa_u64 i; for (i = 0; i < a1; i++) kb[i] = (char)sa_mem[s + i]; kb[a1] = 0; return unsetenv(kb) == 0 ? 0 : 6; } }\n");
        },
        .env_buffer_data => {
            try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0); if (o == 0 || o->kind != 4) return 0; return o->ptr; } }\n");
        },
        .env_buffer_len => {
            try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0); if (o == 0 || o->kind != 4) return 0; return o->len; } }\n");
        },
        .env_buffer_free => {
            try writer.writeAll(" { sa_owned_drop(a0); return 0; } }\n");
        },
        .deno_btoa_handle => {
            // Standard-alphabet base64 with padding, matching the
            // native encoder; the result is an fmt buffer (kind 1),
            // consumed via sa_fmt_buffer_data/len/free as natively.
            // (The .deno_btoa tag below is the unrelated out-param
            // shape used by sa_deno_plugin_btoa.)
            try writer.writeAll(" { static const char T[65] = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"; uint32_t s = sa_checked_addr(a0, (size_t)a1); sa_u64 out_len = 4 * ((a1 + 2) / 3); sa_u64 p = sa_alloc(out_len == 0 ? 1 : out_len); uint32_t d = sa_checked_addr(p, out_len == 0 ? 1 : (size_t)out_len); sa_u64 i = 0, j = 0; while (i + 3 <= a1) { uint32_t v = ((uint32_t)sa_mem[s + i] << 16) | ((uint32_t)sa_mem[s + i + 1] << 8) | (uint32_t)sa_mem[s + i + 2]; sa_mem[d + j++] = (uint8_t)T[(v >> 18) & 63]; sa_mem[d + j++] = (uint8_t)T[(v >> 12) & 63]; sa_mem[d + j++] = (uint8_t)T[(v >> 6) & 63]; sa_mem[d + j++] = (uint8_t)T[v & 63]; i += 3; } if (a1 - i == 1) { uint32_t v = ((uint32_t)sa_mem[s + i] << 16); sa_mem[d + j++] = (uint8_t)T[(v >> 18) & 63]; sa_mem[d + j++] = (uint8_t)T[(v >> 12) & 63]; sa_mem[d + j++] = 61; sa_mem[d + j++] = 61; } else if (a1 - i == 2) { uint32_t v = ((uint32_t)sa_mem[s + i] << 16) | ((uint32_t)sa_mem[s + i + 1] << 8); sa_mem[d + j++] = (uint8_t)T[(v >> 18) & 63]; sa_mem[d + j++] = (uint8_t)T[(v >> 12) & 63]; sa_mem[d + j++] = (uint8_t)T[(v >> 6) & 63]; sa_mem[d + j++] = 61; } return sa_owned_new(p, out_len, 1); } }\n");
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
        .regex_match_all => {
            try writer.writeAll(" {");
            try writer.writeAll(" sa_regex_t *r = sa_regex_find(a0);");
            try writer.writeAll(" if (r == 0) return 0;");
            try writer.writeAll(" uint32_t x = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" if (sa_mem[x + i] == 0) return 0; }");
            try writer.writeAll(" sa_u64 tp = sa_alloc(a2 + 1);");
            try writer.writeAll(" { uint32_t td = sa_checked_addr(tp, a2 + 1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" sa_mem[td + i] = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[td + a2] = 0; }");
            try writer.writeAll(" return sa_regex_collect_block(r, tp, a2); } }\n");
        },
        .regex_match_list_count => {
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 24);");
            try writer.writeAll(" (void)hh;");
            try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
            try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53414C58u) return 0;");
            try writer.writeAll(" return hdr1 & (sa_u64)0xFFFFFFFFu; } }\n");
        },
        .regex_match_list_at => {
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 24);");
            try writer.writeAll(" (void)hh;");
            try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
            try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53414C58u) return 0;");
            try writer.writeAll(" sa_u64 cnt = hdr1 & (sa_u64)0xFFFFFFFFu;");
            try writer.writeAll(" if (a1 >= cnt) return 0;");
            try writer.writeAll(" sa_u64 n = sa_load_u64(a0 + 16);");
            try writer.writeAll(" sa_u64 h = sa_alloc(16 + n * 16);");
            try writer.writeAll(" sa_store_u64(h, sa_load_u64(a0));");
            try writer.writeAll(" sa_store_u64(h + 8, (sa_u64)0x53414D5800000000ULL | n);");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)n; i++) {");
            try writer.writeAll(" sa_store_u64(h + 16 + i * 16,");
            try writer.writeAll(" sa_load_u64(a0 + 24 + (a1 * n + i) * 16));");
            try writer.writeAll(" sa_store_u64(h + 16 + i * 16 + 8,");
            try writer.writeAll(" sa_load_u64(a0 + 24 + (a1 * n + i) * 16 + 8)); } }");
            try writer.writeAll(" return h; } }\n");
        },
        .regex_match_list_free => {
            try writer.writeAll(" return 0; }\n");
        },
        .regex_replace => {
            try writer.writeAll(" {");
            try writer.writeAll(" sa_regex_t *r = sa_regex_find(a0);");
            try writer.writeAll(" if (r == 0) return 0;");
            try writer.writeAll(" uint32_t x = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" if (sa_mem[x + i] == 0) return 0; }");
            try writer.writeAll(" sa_u64 tp = sa_alloc(a2 + 1);");
            try writer.writeAll(" { uint32_t td = sa_checked_addr(tp, a2 + 1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" sa_mem[td + i] = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[td + a2] = 0; }");
            try writer.writeAll(" return sa_regex_build_replace(r, tp, a2, a3, a4, 0); } }\n");
        },
        .regex_replace_all => {
            try writer.writeAll(" {");
            try writer.writeAll(" sa_regex_t *r = sa_regex_find(a0);");
            try writer.writeAll(" if (r == 0) return 0;");
            try writer.writeAll(" uint32_t x = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" if (sa_mem[x + i] == 0) return 0; }");
            try writer.writeAll(" sa_u64 tp = sa_alloc(a2 + 1);");
            try writer.writeAll(" { uint32_t td = sa_checked_addr(tp, a2 + 1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" sa_mem[td + i] = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[td + a2] = 0; }");
            try writer.writeAll(" return sa_regex_build_replace(r, tp, a2, a3, a4, 1); } }\n");
        },
        .regex_buffer_data => {
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
            try writer.writeAll(" (void)hh;");
            try writer.writeAll(" sa_u64 hdr = sa_load_u64(a0);");
            try writer.writeAll(" if ((hdr >> 32) != (sa_u64)0x53414258u) return 0;");
            try writer.writeAll(" return a0 + 16; } }\n");
        },
        .regex_buffer_len => {
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
            try writer.writeAll(" (void)hh;");
            try writer.writeAll(" sa_u64 hdr = sa_load_u64(a0);");
            try writer.writeAll(" if ((hdr >> 32) != (sa_u64)0x53414258u) return 0;");
            try writer.writeAll(" return sa_load_u64(a0 + 8); } }\n");
        },
        .regex_buffer_free => {
            try writer.writeAll(" return 0; }\n");
        },
        .regex_split => {
            try writer.writeAll(" {");
            try writer.writeAll(" sa_regex_t *r = sa_regex_find(a0);");
            try writer.writeAll(" if (r == 0) return 0;");
            try writer.writeAll(" uint32_t x = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" { size_t i; for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" if (sa_mem[x + i] == 0) return 0; }");
            try writer.writeAll(" sa_u64 tp = sa_alloc(a2 + 1);");
            try writer.writeAll(" { uint32_t td = sa_checked_addr(tp, a2 + 1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" sa_mem[td + i] = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[td + a2] = 0; }");
            try writer.writeAll(" return sa_regex_split_block(r, tp, a2, a3); } }\n");
        },
        .regex_split_count => {
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
            try writer.writeAll(" (void)hh;");
            try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
            try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53415058u) return 0;");
            try writer.writeAll(" return hdr1 & (sa_u64)0xFFFFFFFFu; } }\n");
        },
        .regex_split_ptr => {
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
            try writer.writeAll(" (void)hh;");
            try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
            try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53415058u) return 0;");
            try writer.writeAll(" sa_u64 cnt = hdr1 & (sa_u64)0xFFFFFFFFu;");
            try writer.writeAll(" if (a1 >= cnt) return 0;");
            try writer.writeAll(" sa_i64 so = (sa_i64)sa_load_u64(a0 + 16 + a1 * 16);");
            try writer.writeAll(" if (so < 0) return 0;");
            try writer.writeAll(" return sa_load_u64(a0) + (sa_u64)so; } }\n");
        },
        .regex_split_len => {
            try writer.writeAll(" { uint32_t hh = sa_checked_addr(a0, 16);");
            try writer.writeAll(" (void)hh;");
            try writer.writeAll(" sa_u64 hdr1 = sa_load_u64(a0 + 8);");
            try writer.writeAll(" if ((hdr1 >> 32) != (sa_u64)0x53415058u) return 0;");
            try writer.writeAll(" sa_u64 cnt = hdr1 & (sa_u64)0xFFFFFFFFu;");
            try writer.writeAll(" if (a1 >= cnt) return 0;");
            try writer.writeAll(" sa_i64 so = (sa_i64)sa_load_u64(a0 + 16 + a1 * 16);");
            try writer.writeAll(" sa_i64 eo = (sa_i64)sa_load_u64(a0 + 16 + a1 * 16 + 8);");
            try writer.writeAll(" if (so < 0 || eo < so) return 0;");
            try writer.writeAll(" return (sa_u64)(eo - so); } }\n");
        },
        .regex_split_free => {
            try writer.writeAll(" return 0; }\n");
        },
        .node_path_normalize => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" sa_u64 cap = a1 + 2;");
            try writer.writeAll(" sa_u64 p = sa_alloc(cap);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, cap);");
            try writer.writeAll(" sa_u64 n = sa_path_norm(&sa_mem[x], (size_t)a1, &sa_mem[d], (size_t)cap);");
            try writer.writeAll(" if (n == ~(sa_u64)0) return 1;");
            try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, n); return 0; } } }\n");
        },
        .node_path_dirname => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" size_t e = (size_t)a1;");
            try writer.writeAll(" while (e > 1 && sa_mem[x + e - 1] == '/') e--;");
            try writer.writeAll(" size_t i = e;");
            try writer.writeAll(" while (i > 0 && sa_mem[x + i - 1] != '/') i--;");
            try writer.writeAll(" sa_u64 n; sa_u64 src;");
            try writer.writeAll(" if (e == 0 || i == 0) { n = 1; src = 0; }");
            try writer.writeAll(" else if (i == 1) { n = 1; src = 1; }");
            try writer.writeAll(" else { n = (sa_u64)(i - 1); src = 2; }");
            try writer.writeAll(" { sa_u64 p = sa_alloc(n);");
            try writer.writeAll(" uint32_t d = sa_checked_addr(p, n);");
            try writer.writeAll(" if (src == 0) sa_mem[d] = (uint8_t)'.';");
            try writer.writeAll(" else if (src == 1) sa_mem[d] = (uint8_t)'/';");
            try writer.writeAll(" else { size_t k; for (k = 0; k < (size_t)n; k++)");
            try writer.writeAll(" sa_mem[d + k] = sa_mem[x + k]; }");
            try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, n);");
            try writer.writeAll(" return 0; } } }\n");
        },
        .node_path_extname => {
            // Zero-copy view into the input (no allocation needed).
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" size_t i = (size_t)a1;");
            try writer.writeAll(" while (i > 0 && sa_mem[x + i - 1] != '/') i--;");
            try writer.writeAll(" size_t j = (size_t)a1;");
            try writer.writeAll(" while (j > i && sa_mem[x + j - 1] != '.') j--;");
            try writer.writeAll(" if (j <= i || j == i + 1 || j == (size_t)a1) {");
            try writer.writeAll(" sa_store_u64(a2, 0); sa_store_u64(a3, 0); return 0; }");
            try writer.writeAll(" sa_store_u64(a2, (sa_u64)x + (j - 1));");
            try writer.writeAll(" sa_store_u64(a3, (sa_u64)a1 - (j - 1));");
            try writer.writeAll(" return 0; } }\n");
        },
        .node_path_is_absolute => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" sa_u64 r = (a1 > 0 && sa_mem[x] == '/') ? 1 : 0;");
            try writer.writeAll(" sa_store_u32(a2, r); return 0; } }\n");
        },
        .node_path_join => {
            // argv of (ptr,len) pairs; joined with '/' then normalized
            // in place (output never exceeds input + 1).
            try writer.writeAll(" { if (a1 > (sa_u64)0x100000u) return 1;");
            try writer.writeAll(" uint32_t ab = sa_checked_addr(a0, (size_t)(a1 * 16));");
            try writer.writeAll(" (void)ab;");
            try writer.writeAll(" sa_u64 total = 0; sa_u64 k;");
            try writer.writeAll(" for (k = 0; k < a1; k++) {");
            try writer.writeAll(" sa_u64 l = sa_load_u64(a0 + k * 16 + 8);");
            try writer.writeAll(" if (l > 0 && total > ~(sa_u64)0 - l - 1) return 1;");
            try writer.writeAll(" total += l + (k + 1 < a1 && l > 0 ? 1 : 0); }");
            try writer.writeAll(" sa_u64 p = sa_alloc(total + 2);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, total + 2);");
            try writer.writeAll(" sa_u64 w = 0;");
            try writer.writeAll(" for (k = 0; k < a1; k++) {");
            try writer.writeAll(" sa_u64 pp = sa_load_u64(a0 + k * 16);");
            try writer.writeAll(" sa_u64 l = sa_load_u64(a0 + k * 16 + 8);");
            try writer.writeAll(" uint32_t s = sa_checked_addr(pp, (size_t)l);");
            try writer.writeAll(" if (l > 0 && w > 0) sa_mem[d + w++] = (uint8_t)'/';");
            try writer.writeAll(" { size_t q; for (q = 0; q < (size_t)l; q++)");
            try writer.writeAll(" sa_mem[d + w + q] = sa_mem[s + q]; }");
            try writer.writeAll(" w += l; }");
            try writer.writeAll(" sa_u64 n = sa_path_norm(&sa_mem[d], (size_t)w, &sa_mem[d], (size_t)(total + 2));");
            try writer.writeAll(" if (n == ~(sa_u64)0) return 1;");
            try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, n); return 0; } } }\n");
        },
        .node_qs_escape => {
            // Node querystring.escape: alnum + ~!*()-'_. pass through,
            // everything else becomes %XX uppercase hex.
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a1 > ~(sa_u64)0 / 3) return 1;");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1 * 3);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 * 3);");
            try writer.writeAll(" sa_u64 w = 0; size_t i;");
            try writer.writeAll(" for (i = 0; i < (size_t)a1; i++) {");
            try writer.writeAll(" uint8_t c = sa_mem[x + i];");
            try writer.writeAll(" int ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');");
            try writer.writeAll(" if (!ok) { const char *u = \"~!*()-'_.\"; size_t k; ok = 0;");
            try writer.writeAll(" for (k = 0; k < 8; k++) if (c == (uint8_t)u[k]) { ok = 1; break; } }");
            try writer.writeAll(" if (ok) sa_mem[d + w++] = c;");
            try writer.writeAll(" else {");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)'%';");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"0123456789ABCDEF\"[c >> 4];");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"0123456789ABCDEF\"[c & 15]; } }");
            try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
        },
        .node_qs_unescape => {
            // %XX (either case) decodes; malformed % and '+' pass through
            // literally (mirrors Node).
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1 == 0 ? 1 : a1);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 == 0 ? 1 : a1);");
            try writer.writeAll(" sa_u64 w = 0; size_t i = 0;");
            try writer.writeAll(" while (i < (size_t)a1) {");
            try writer.writeAll(" uint8_t c = sa_mem[x + i];");
            try writer.writeAll(" if (c == '%' && i + 2 < (size_t)a1) {");
            try writer.writeAll(" uint8_t h1 = sa_mem[x + i + 1]; uint8_t h2 = sa_mem[x + i + 2];");
            try writer.writeAll(" int v1 = h1 >= '0' && h1 <= '9' ? h1 - '0' : (h1 >= 'a' && h1 <= 'f' ? h1 - 'a' + 10 : (h1 >= 'A' && h1 <= 'F' ? h1 - 'A' + 10 : -1));");
            try writer.writeAll(" int v2 = h2 >= '0' && h2 <= '9' ? h2 - '0' : (h2 >= 'a' && h2 <= 'f' ? h2 - 'a' + 10 : (h2 >= 'A' && h2 <= 'F' ? h2 - 'A' + 10 : -1));");
            try writer.writeAll(" if (v1 >= 0 && v2 >= 0) { sa_mem[d + w++] = (uint8_t)(v1 * 16 + v2); i += 3; continue; } }");
            try writer.writeAll(" sa_mem[d + w++] = c; i++; }");
            try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
        },
        .node_puny_encode => {
            // RFC 3492 encode (UTF-8 in, ASCII out); invalid UTF-8 or
            // overflow yields 1. Output capped at 12x+16 (DoS bound).
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a1 > (~(sa_u64)0 - 16) / 12) return 1;");
            try writer.writeAll(" sa_u64 cap = a1 * 12 + 16;");
            try writer.writeAll(" sa_u64 p = sa_alloc(cap);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, cap);");
            try writer.writeAll(" sa_u64 cp = sa_alloc((a1 + 1) * 4);");
            try writer.writeAll(" uint32_t cd = sa_checked_addr(cp, (a1 + 1) * 4);");
            try writer.writeAll(" sa_u64 h = 0; size_t i = 0;");
            try writer.writeAll(" while (i < (size_t)a1) {");
            try writer.writeAll(" uint32_t c = sa_utf8_next(&sa_mem[x], (size_t)a1, &i);");
            try writer.writeAll(" if (c == ~(uint32_t)0) return 1;");
            try writer.writeAll(" sa_mem[cd + h * 4] = (uint8_t)(c & 0xFF);");
            try writer.writeAll(" sa_mem[cd + h * 4 + 1] = (uint8_t)((c >> 8) & 0xFF);");
            try writer.writeAll(" sa_mem[cd + h * 4 + 2] = (uint8_t)((c >> 16) & 0xFF);");
            try writer.writeAll(" sa_mem[cd + h * 4 + 3] = (uint8_t)((c >> 24) & 0xFF);");
            try writer.writeAll(" h++; }");
            try writer.writeAll(" sa_u64 w = 0; sa_u64 b;");
            try writer.writeAll(" for (b = 0; b < h; b++) {");
            try writer.writeAll(" uint32_t c = (uint32_t)sa_mem[cd + b * 4] | ((uint32_t)sa_mem[cd + b * 4 + 1] << 8) | ((uint32_t)sa_mem[cd + b * 4 + 2] << 16) | ((uint32_t)sa_mem[cd + b * 4 + 3] << 24);");
            try writer.writeAll(" if (c < 0x80) { if (w >= cap) return 1; sa_mem[d + w++] = (uint8_t)c; } }");
            try writer.writeAll(" sa_u64 nb = w;");
            try writer.writeAll(" if (nb > 0) { if (w >= cap) return 1; sa_mem[d + w++] = (uint8_t)'-'; }");
            try writer.writeAll(" sa_u64 n = 0x80; sa_u64 delta = 0; sa_u64 bias = 72;");
            try writer.writeAll(" int first = 1;");
            try writer.writeAll(" while (h > nb) {");
            try writer.writeAll(" sa_u64 m = ~(sa_u64)0; sa_u64 k;");
            try writer.writeAll(" for (k = 0; k < h; k++) {");
            try writer.writeAll(" uint32_t c = (uint32_t)sa_mem[cd + k * 4] | ((uint32_t)sa_mem[cd + k * 4 + 1] << 8) | ((uint32_t)sa_mem[cd + k * 4 + 2] << 16) | ((uint32_t)sa_mem[cd + k * 4 + 3] << 24);");
            try writer.writeAll(" if (c >= n && (sa_u64)c < m) m = c; }");
            try writer.writeAll(" if (m - n > (~(sa_u64)0 - delta) / (h > 0 ? h : 1)) return 1;");
            try writer.writeAll(" delta += (m - n) * h;");
            try writer.writeAll(" n = m;");
            try writer.writeAll(" for (k = 0; k < h; k++) {");
            try writer.writeAll(" uint32_t c = (uint32_t)sa_mem[cd + k * 4] | ((uint32_t)sa_mem[cd + k * 4 + 1] << 8) | ((uint32_t)sa_mem[cd + k * 4 + 2] << 16) | ((uint32_t)sa_mem[cd + k * 4 + 3] << 24);");
            try writer.writeAll(" if ((sa_u64)c < n) { delta++; if (delta == 0) return 1; continue; }");
            try writer.writeAll(" if ((sa_u64)c == n) {");
            try writer.writeAll(" sa_u64 q = delta; sa_u64 kk = 36;");
            try writer.writeAll(" for (;;) {");
            try writer.writeAll(" sa_u64 t = kk <= bias ? 1 : (kk >= bias + 26 ? 26 : kk - bias);");
            try writer.writeAll(" if (q < t) break;");
            try writer.writeAll(" { sa_u64 bt = 36 - t; sa_u64 dg = t + (q - t) % bt;");
            try writer.writeAll(" if (w >= cap) return 1;");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)(dg < 26 ? 'a' + dg : '0' + dg - 26); }");
            try writer.writeAll(" q = (q - t) / (36 - t); kk += 36; }");
            try writer.writeAll(" if (w >= cap) return 1;");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)(q < 26 ? 'a' + q : '0' + q - 26);");
            try writer.writeAll(" bias = sa_puny_adapt(delta, h + 1, first);");
            try writer.writeAll(" first = 0;");
            try writer.writeAll(" delta = 0; nb++; } }");
            try writer.writeAll(" n++; }");
            try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
        },
        .node_puny_decode => {
            // RFC 3492 decode (ASCII in, UTF-8 out); malformed input or
            // overflow yields 1.
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" size_t dl = (size_t)a1; size_t q;");
            try writer.writeAll(" for (q = 0; q < (size_t)a1; q++) {");
            try writer.writeAll(" uint8_t c = sa_mem[x + q];");
            try writer.writeAll(" if (c == '-') dl = q; }");
            try writer.writeAll(" sa_u64 cp = sa_alloc(((sa_u64)a1 + 1) * 4);");
            try writer.writeAll(" uint32_t cd = sa_checked_addr(cp, ((sa_u64)a1 + 1) * 4);");
            try writer.writeAll(" sa_u64 out = 0; size_t i;");
            try writer.writeAll(" for (i = 0; i < dl; i++) {");
            try writer.writeAll(" uint8_t c = sa_mem[x + i];");
            try writer.writeAll(" if (c >= 0x80) return 1;");
            try writer.writeAll(" sa_mem[cd + out * 4] = c;");
            try writer.writeAll(" sa_mem[cd + out * 4 + 1] = 0;");
            try writer.writeAll(" sa_mem[cd + out * 4 + 2] = 0;");
            try writer.writeAll(" sa_mem[cd + out * 4 + 3] = 0; out++; }");
            try writer.writeAll(" size_t pos = dl < (size_t)a1 ? dl + 1 : (size_t)a1;");
            try writer.writeAll(" sa_u64 n = 0x80; sa_u64 bias = 72;");
            try writer.writeAll(" sa_u64 idx = 0; int first = 1;");
            try writer.writeAll(" while (pos < (size_t)a1) {");
            try writer.writeAll(" sa_u64 oldi = idx; sa_u64 w = 1; sa_u64 kk = 36;");
            try writer.writeAll(" for (;;) {");
            try writer.writeAll(" if (pos >= (size_t)a1) return 1;");
            try writer.writeAll(" uint8_t c = sa_mem[x + pos++];");
            try writer.writeAll(" sa_u64 dg = c >= '0' && c <= '9' ? (sa_u64)(c - '0' + 26)");
            try writer.writeAll(" : (c >= 'a' && c <= 'z' ? (sa_u64)(c - 'a')");
            try writer.writeAll(" : (c >= 'A' && c <= 'Z' ? (sa_u64)(c - 'A') : ~(sa_u64)0));");
            try writer.writeAll(" if (dg == ~(sa_u64)0) return 1;");
            try writer.writeAll(" if (dg > (~(sa_u64)0 - idx) / w) return 1;");
            try writer.writeAll(" idx += dg * w;");
            try writer.writeAll(" sa_u64 t = kk <= bias ? 1 : (kk >= bias + 26 ? 26 : kk - bias);");
            try writer.writeAll(" if (dg < t) break;");
            try writer.writeAll(" if (w > ~(sa_u64)0 / (36 - t)) return 1;");
            try writer.writeAll(" w *= 36 - t; kk += 36; }");
            try writer.writeAll(" bias = sa_puny_adapt(idx - oldi, out + 1, first);");
            try writer.writeAll(" first = 0;");
            try writer.writeAll(" if (idx - oldi > (~(sa_u64)0 - n) / (out + 1)) return 1;");
            try writer.writeAll(" n += (idx - oldi) / (out + 1);");
            try writer.writeAll(" idx %= out + 1;");
            try writer.writeAll(" if (n > 0x10FFFF) return 1;");
            try writer.writeAll(" { sa_u64 z; for (z = out; z > idx; z--) {");
            try writer.writeAll(" sa_mem[cd + z * 4] = sa_mem[cd + (z - 1) * 4];");
            try writer.writeAll(" sa_mem[cd + z * 4 + 1] = sa_mem[cd + (z - 1) * 4 + 1];");
            try writer.writeAll(" sa_mem[cd + z * 4 + 2] = sa_mem[cd + (z - 1) * 4 + 2];");
            try writer.writeAll(" sa_mem[cd + z * 4 + 3] = sa_mem[cd + (z - 1) * 4 + 3]; } }");
            try writer.writeAll(" sa_mem[cd + idx * 4] = (uint8_t)(n & 0xFF);");
            try writer.writeAll(" sa_mem[cd + idx * 4 + 1] = (uint8_t)((n >> 8) & 0xFF);");
            try writer.writeAll(" sa_mem[cd + idx * 4 + 2] = (uint8_t)((n >> 16) & 0xFF);");
            try writer.writeAll(" sa_mem[cd + idx * 4 + 3] = (uint8_t)((n >> 24) & 0xFF);");
            try writer.writeAll(" out++; idx++; }");
            try writer.writeAll(" sa_u64 p = sa_alloc(out * 4);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, out * 4);");
            try writer.writeAll(" sa_u64 w = 0; sa_u64 z;");
            try writer.writeAll(" for (z = 0; z < out; z++) {");
            try writer.writeAll(" uint32_t c = (uint32_t)sa_mem[cd + z * 4] | ((uint32_t)sa_mem[cd + z * 4 + 1] << 8) | ((uint32_t)sa_mem[cd + z * 4 + 2] << 16) | ((uint32_t)sa_mem[cd + z * 4 + 3] << 24);");
            try writer.writeAll(" unsigned el = sa_utf8_enc(c, &sa_mem[d + w]);");
            try writer.writeAll(" if (el == 0 || c > 0x10FFFF) return 1; w += el; }");
            try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
        },
        .node_buf_concat => {
            // argv of (ptr,len) pairs concatenated in order.
            try writer.writeAll(" { if (a1 > (sa_u64)0x100000u) return 1;");
            try writer.writeAll(" uint32_t ab = sa_checked_addr(a0, (size_t)(a1 * 16));");
            try writer.writeAll(" (void)ab;");
            try writer.writeAll(" sa_u64 total = 0; sa_u64 k;");
            try writer.writeAll(" for (k = 0; k < a1; k++) {");
            try writer.writeAll(" sa_u64 l = sa_load_u64(a0 + k * 16 + 8);");
            try writer.writeAll(" if (total > ~(sa_u64)0 - l) return 1;");
            try writer.writeAll(" total += l; }");
            try writer.writeAll(" sa_u64 p = sa_alloc(total == 0 ? 1 : total);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, total == 0 ? 1 : total);");
            try writer.writeAll(" sa_u64 w = 0;");
            try writer.writeAll(" for (k = 0; k < a1; k++) {");
            try writer.writeAll(" sa_u64 pp = sa_load_u64(a0 + k * 16);");
            try writer.writeAll(" sa_u64 l = sa_load_u64(a0 + k * 16 + 8);");
            try writer.writeAll(" uint32_t s = sa_checked_addr(pp, (size_t)l);");
            try writer.writeAll(" { size_t q; for (q = 0; q < (size_t)l; q++)");
            try writer.writeAll(" sa_mem[d + w + q] = sa_mem[s + q]; }");
            try writer.writeAll(" w += l; }");
            try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, total); return 0; } } }\n");
        },
        .node_rand_bytes => {
            // Staged zero region (only the length is asserted).
            try writer.writeAll(" if (!sa_policy_check(5, 0, 0, 0)) return 10;");
            try writer.writeAll(" sa_u64 p = sa_alloc(a0 == 0 ? 1 : a0);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a0 == 0 ? 1 : a0);");
            try writer.writeAll(" (void)d;");
            try writer.writeAll(" sa_store_u64(a1, p); return 0; } }\n");
        },
        .node_crypto_hash => {
            // Byte-exact algo dispatch (mirror native: sha256, sha512,
            // sha1, md5 in either case, status 2 otherwise); lowercase
            // hex digest materializes into fresh guest memory.
            try writer.writeAll(" { uint32_t ax = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t dx = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" unsigned hlen = 0; unsigned hk = 0; unsigned e0; unsigned e1; size_t i;");
            try writer.writeAll(" if (a1 == 6) { e0 = 1; e1 = 1;");
            try writer.writeAll(" for (i = 0; i < 6; i++) {");
            try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"sha256\"[i]) e0 = 0;");
            try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"SHA256\"[i]) e1 = 0; }");
            try writer.writeAll(" if (e0 != 0 || e1 != 0) { hk = 1; hlen = 32; }");
            try writer.writeAll(" else { e0 = 1; e1 = 1;");
            try writer.writeAll(" for (i = 0; i < 6; i++) {");
            try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"sha512\"[i]) e0 = 0;");
            try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"SHA512\"[i]) e1 = 0; }");
            try writer.writeAll(" if (e0 != 0 || e1 != 0) { hk = 2; hlen = 64; } } }");
            try writer.writeAll(" if (hk == 0 && a1 == 4) { e0 = 1; e1 = 1;");
            try writer.writeAll(" for (i = 0; i < 4; i++) {");
            try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"sha1\"[i]) e0 = 0;");
            try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"SHA1\"[i]) e1 = 0; }");
            try writer.writeAll(" if (e0 != 0 || e1 != 0) { hk = 3; hlen = 20; } }");
            try writer.writeAll(" if (hk == 0 && a1 == 3) { e0 = 1; e1 = 1;");
            try writer.writeAll(" for (i = 0; i < 3; i++) {");
            try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"md5\"[i]) e0 = 0;");
            try writer.writeAll(" if (sa_mem[ax + i] != (uint8_t)\"MD5\"[i]) e1 = 0; }");
            try writer.writeAll(" if (e0 != 0 || e1 != 0) { hk = 4; hlen = 16; } }");
            try writer.writeAll(" if (hk == 0) return 2;");
            try writer.writeAll(" { uint8_t dig[64];");
            try writer.writeAll(" if (hk == 1) sa_sha256(&sa_mem[dx], (size_t)a3, dig);");
            try writer.writeAll(" else if (hk == 2) sa_sha512(&sa_mem[dx], (size_t)a3, dig);");
            try writer.writeAll(" else if (hk == 3) sa_sha1(&sa_mem[dx], (size_t)a3, dig);");
            try writer.writeAll(" else sa_md5(&sa_mem[dx], (size_t)a3, dig);");
            try writer.writeAll(" sa_u64 p = sa_alloc((sa_u64)hlen * 2);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, (sa_u64)hlen * 2);");
            try writer.writeAll(" unsigned k; for (k = 0; k < hlen; k++) {");
            try writer.writeAll(" sa_mem[d + k * 2] = (uint8_t)\"0123456789abcdef\"[dig[k] >> 4];");
            try writer.writeAll(" sa_mem[d + k * 2 + 1] = (uint8_t)\"0123456789abcdef\"[dig[k] & 15]; }");
            try writer.writeAll(" sa_store_u64(a4, p); sa_store_u64(a5, (sa_u64)hlen * 2); return 0; } } } }\n");
        },
        .deno_btoa => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a1 > (~(sa_u64)0 - 2) / 4 * 3) return 1;");
            try writer.writeAll(" sa_u64 n = (a1 + 2) / 3 * 4;");
            try writer.writeAll(" sa_u64 p = sa_alloc(n == 0 ? 1 : n);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, n == 0 ? 1 : n);");
            try writer.writeAll(" size_t i = 0; sa_u64 w = 0;");
            try writer.writeAll(" while (i + 3 <= (size_t)a1) {");
            try writer.writeAll(" uint32_t v = ((uint32_t)sa_mem[x + i] << 16) | ((uint32_t)sa_mem[x + i + 1] << 8) | sa_mem[x + i + 2];");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 18) & 63];");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 12) & 63];");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 6) & 63];");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[v & 63];");
            try writer.writeAll(" i += 3; }");
            try writer.writeAll(" if (i < (size_t)a1) {");
            try writer.writeAll(" uint32_t v = (uint32_t)sa_mem[x + i] << 16;");
            try writer.writeAll(" size_t rem = (size_t)a1 - i;");
            try writer.writeAll(" if (rem == 2) v |= (uint32_t)sa_mem[x + i + 1] << 8;");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 18) & 63];");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 12) & 63];");
            try writer.writeAll(" if (rem == 2) sa_mem[d + w++] = (uint8_t)\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"[(v >> 6) & 63]; else sa_mem[d + w++] = (uint8_t)'=';");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)'='; }");
            try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
        },
        .deno_atob => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a1 % 4 != 0) return 1;");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1 == 0 ? 1 : a1 / 4 * 3);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 == 0 ? 1 : a1 / 4 * 3);");
            try writer.writeAll(" sa_u64 w = 0; size_t i = 0;");
            try writer.writeAll(" while (i < (size_t)a1) {");
            try writer.writeAll(" int v[4]; size_t k; int pad = 0;");
            try writer.writeAll(" for (k = 0; k < 4; k++) {");
            try writer.writeAll(" uint8_t c = sa_mem[x + i + k];");
            try writer.writeAll(" if (c >= 'A' && c <= 'Z') v[k] = c - 'A';");
            try writer.writeAll(" else if (c >= 'a' && c <= 'z') v[k] = c - 'a' + 26;");
            try writer.writeAll(" else if (c >= '0' && c <= '9') v[k] = c - '0' + 52;");
            try writer.writeAll(" else if (c == '+') v[k] = 62;");
            try writer.writeAll(" else if (c == '/') v[k] = 63;");
            try writer.writeAll(" else if (c == '=' && k >= 2) { v[k] = 0; pad++; }");
            try writer.writeAll(" else return 1; }");
            try writer.writeAll(" if (pad > 2 || (pad > 0 && i + 4 < (size_t)a1)) return 1;");
            try writer.writeAll(" uint32_t t = ((uint32_t)v[0] << 18) | ((uint32_t)v[1] << 12) | ((uint32_t)v[2] << 6) | (uint32_t)v[3];");
            try writer.writeAll(" sa_mem[d + w++] = (uint8_t)(t >> 16);");
            try writer.writeAll(" if (pad < 2) sa_mem[d + w++] = (uint8_t)(t >> 8);");
            try writer.writeAll(" if (pad < 1) sa_mem[d + w++] = (uint8_t)t; i += 4; }");
            try writer.writeAll(" sa_store_u64(a2, p); sa_store_u64(a3, w); return 0; } } }\n");
        },
        .deno_read_file => {
            // Real host read into fresh guest memory (mirrors the deno
            // plugin); 0 ok, 2 on any failure.
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a1 == 0) return 2;");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 + 1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[d + a1] = 0; }");
            try writer.writeAll(" if (!sa_policy_check(1, (const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], 0, 0)) return 10;");
            try writer.writeAll(" FILE *f = fopen((const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], \"rb\");");
            try writer.writeAll(" if (f == 0) return 2;");
            try writer.writeAll(" if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return 2; }");
            try writer.writeAll(" long sz = ftell(f);");
            try writer.writeAll(" if (sz < 0) { fclose(f); return 2; }");
            try writer.writeAll(" if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return 2; }");
            try writer.writeAll(" sa_u64 q = sa_alloc((sa_u64)sz == 0 ? 1 : (sa_u64)sz);");
            try writer.writeAll(" { uint32_t dd = sa_checked_addr(q, (sa_u64)sz == 0 ? 1 : (sa_u64)sz);");
            try writer.writeAll(" size_t got = fread(&sa_mem[dd], 1, (size_t)sz, f);");
            try writer.writeAll(" fclose(f);");
            try writer.writeAll(" if (got != (size_t)sz) return 2;");
            try writer.writeAll(" sa_store_u64(a2, q); sa_store_u64(a3, (sa_u64)sz); return 0; } } }\n");
        },
        .deno_write_file => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" uint32_t y = sa_checked_addr(a2, (size_t)a3);");
            try writer.writeAll(" if (a1 == 0) return 2;");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 + 1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[d + a1] = 0; }");
            try writer.writeAll(" if (!sa_policy_check(1, (const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], 1, 0)) return 10;");
            try writer.writeAll(" FILE *f = fopen((const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], \"wb\");");
            try writer.writeAll(" if (f == 0) return 2;");
            try writer.writeAll(" { size_t w = 0; while (w < (size_t)a3) {");
            try writer.writeAll(" size_t n = fwrite(&sa_mem[y + w], 1, (size_t)a3 - w, f);");
            try writer.writeAll(" if (n == 0) { fclose(f); return 2; } w += n; } }");
            try writer.writeAll(" if (fclose(f) != 0) return 2;");
            try writer.writeAll(" return 0; } }\n");
        },
        .deno_remove => {
            // Non-recursive remove (files + empty dirs via libc
            // remove); recursive trees are out of scope for now.
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a1 == 0) return 2;");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 + 1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[d + a1] = 0; }");
            try writer.writeAll(" if (!sa_policy_check(1, (const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], 1, 0)) return 10;");
            try writer.writeAll(" if (remove((const char *)&sa_mem[sa_checked_addr(p, a1 + 1)]) != 0) return 2;");
            try writer.writeAll(" return 0; } }\n");
        },
        .deno_mkdir => {
            // Recursive prefix walk (mkdir -p shape); EEXIST tolerated.
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a1 == 0) return 2;");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 + 1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[d + a1] = 0; }");
            try writer.writeAll(" if (!sa_policy_check(1, (const char *)&sa_mem[sa_checked_addr(p, a1 + 1)], 1, 0)) return 10;");
            try writer.writeAll(" { size_t i = (a2 != 0);");
            try writer.writeAll(" if (i == 0) {");
            try writer.writeAll(" if (sa_mkdir_wrap(&sa_mem[sa_checked_addr(p, a1 + 1)]) != 0) return 2;");
            try writer.writeAll(" } else {");
            try writer.writeAll(" size_t j; for (j = 1; j <= (size_t)a1; j++) {");
            try writer.writeAll(" if (j == (size_t)a1 || sa_mem[sa_checked_addr(p, a1 + 1) + j] == '/') {");
            try writer.writeAll(" uint8_t sv = sa_mem[sa_checked_addr(p, a1 + 1) + j];");
            try writer.writeAll(" sa_mem[sa_checked_addr(p, a1 + 1) + j] = 0;");
            try writer.writeAll(" if (sa_mkdir_wrap(&sa_mem[sa_checked_addr(p, a1 + 1)]) != 0 && errno != EEXIST) return 2;");
            try writer.writeAll(" sa_mem[sa_checked_addr(p, a1 + 1) + j] = sv; } } }");
            try writer.writeAll(" return 0; } } }\n");
        },
        .std_fs_exists => {
            // Status-code shape (mirror native): 0 exists, NOT_FOUND 3
            // missing, INVALID_ARGUMENT 1 on bad input, ACCESS 4 on
            // permission errors, IO 6 otherwise.
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" if (a1 == 0) return 1;");
            try writer.writeAll(" sa_u64 p = sa_alloc(a1 + 1);");
            try writer.writeAll(" { uint32_t d = sa_checked_addr(p, a1 + 1);");
            try writer.writeAll(" size_t i; for (i = 0; i < (size_t)a1; i++)");
            try writer.writeAll(" sa_mem[d + i] = sa_mem[x + i];");
            try writer.writeAll(" sa_mem[d + a1] = 0; }");
            try writer.writeAll(" if (sa_access_wrap(&sa_mem[sa_checked_addr(p, a1 + 1)]) == 0) return 0;");
            try writer.writeAll(" if (errno == ENOENT || errno == ENOTDIR) return 3;");
            try writer.writeAll(" if (errno == EACCES) return 4;");
            try writer.writeAll(" return 6; } }\n");
        },
        .time_unix_ms => {
            // Real wall clock (mirrors the interpreter, not staged).
            try writer.writeAll(" { struct timespec ts;");
            try writer.writeAll(" if (!sa_policy_check(4, 0, 0, 0)) return 0;");
            try writer.writeAll(" if (clock_gettime(CLOCK_REALTIME, &ts) != 0) return 0;");
            try writer.writeAll(" return (sa_u64)((sa_i64)ts.tv_sec * 1000 + ts.tv_nsec / 1000000); } }\n");
        },
        .json_parse => {
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" size_t pos = 0;");
            try writer.writeAll(" sa_json_node_t *nd = sa_json_parse_value(&sa_mem[x], (size_t)a1, &pos, 0);");
            try writer.writeAll(" if (nd == 0) return 0;");
            try writer.writeAll(" while (pos < (size_t)a1 && (sa_mem[x + pos] == ' ' || sa_mem[x + pos] == '\\t' || sa_mem[x + pos] == '\\n' || sa_mem[x + pos] == '\\r')) pos++;");
            try writer.writeAll(" if (pos != (size_t)a1) return 0;");
            try writer.writeAll(" return nd->h; } }\n");
        },
        .json_free => {
            try writer.writeAll(" { sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0) return 0;");
            try writer.writeAll(" o->h = 0; return 0; } }\n");
        },
        .json_object_get => {
            try writer.writeAll(" { sa_store_u64(a3, 0);");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 1;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" if (a2 == 0) return 1;");
            try writer.writeAll(" sa_u64 ci = o->first;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" if (m->klen == a2) {");
            try writer.writeAll(" uint32_t mk = sa_checked_addr(m->kptr, m->klen);");
            try writer.writeAll(" size_t i; int eq = 1;");
            try writer.writeAll(" for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" if (sa_mem[mk + i] != sa_mem[k + i]) { eq = 0; break; }");
            try writer.writeAll(" if (eq) {");
            try writer.writeAll(" if (m->h == 0) m->h = sa_alloc(8);");
            try writer.writeAll(" sa_store_u64(a3, m->h); return 0; } }");
            try writer.writeAll(" ci = m->next; }");
            try writer.writeAll(" return 1; } }\n");
        },
        .json_object_get_i64 => {
            try writer.writeAll(" { sa_store_u64(a3, 0);");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 1;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" if (a2 == 0) return 1;");
            try writer.writeAll(" sa_u64 ci = o->first;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" if (m->klen == a2) {");
            try writer.writeAll(" uint32_t mk = sa_checked_addr(m->kptr, m->klen);");
            try writer.writeAll(" size_t i; int eq = 1;");
            try writer.writeAll(" for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" if (sa_mem[mk + i] != sa_mem[k + i]) { eq = 0; break; }");
            try writer.writeAll(" if (eq) {");
            try writer.writeAll(" if (m->kind == 2) { sa_store_u64(a3, (sa_u64)m->ival); return 0; }");
            try writer.writeAll(" if (m->kind == 3) {");
            try writer.writeAll(" union { sa_u64 u; double v; } t; t.u = m->fbits;");
            try writer.writeAll(" if (t.v != t.v) return 1;");
            try writer.writeAll(" if (t.v >= 9223372036854775808.0 || t.v < -9223372036854775808.0) return 1;");
            try writer.writeAll(" sa_i64 vv = (sa_i64)t.v;");
            try writer.writeAll(" union { sa_u64 u; double v; } u2; u2.v = (double)vv;");
            try writer.writeAll(" if (u2.u != m->fbits) return 1;");
            try writer.writeAll(" sa_store_u64(a3, (sa_u64)vv); return 0; }");
            try writer.writeAll(" return 1; } }");
            try writer.writeAll(" ci = m->next; }");
            try writer.writeAll(" return 1; } }\n");
        },
        .json_object_get_string => {
            try writer.writeAll(" { sa_store_u64(a3, 0); sa_store_u64(a4, 0);");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 1;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" if (a2 == 0) return 1;");
            try writer.writeAll(" sa_u64 ci = o->first;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" if (m->klen == a2) {");
            try writer.writeAll(" uint32_t mk = sa_checked_addr(m->kptr, m->klen);");
            try writer.writeAll(" size_t i; int eq = 1;");
            try writer.writeAll(" for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" if (sa_mem[mk + i] != sa_mem[k + i]) { eq = 0; break; }");
            try writer.writeAll(" if (eq) {");
            try writer.writeAll(" if (m->kind != 5) return 1;");
            try writer.writeAll(" sa_store_u64(a3, m->vptr); sa_store_u64(a4, m->vlen); return 0; } }");
            try writer.writeAll(" ci = m->next; }");
            try writer.writeAll(" return 1; } }\n");
        },
        .json_object_get_bool => {
            try writer.writeAll(" { sa_store_u8(a3, 0);");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 1;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" if (a2 == 0) return 1;");
            try writer.writeAll(" sa_u64 ci = o->first;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" if (m->klen == a2) {");
            try writer.writeAll(" uint32_t mk = sa_checked_addr(m->kptr, m->klen);");
            try writer.writeAll(" size_t i; int eq = 1;");
            try writer.writeAll(" for (i = 0; i < (size_t)a2; i++)");
            try writer.writeAll(" if (sa_mem[mk + i] != sa_mem[k + i]) { eq = 0; break; }");
            try writer.writeAll(" if (eq) {");
            try writer.writeAll(" if (m->kind != 1) return 1;");
            try writer.writeAll(" sa_store_u8(a3, m->bval ? 1 : 0); return 0; } }");
            try writer.writeAll(" ci = m->next; }");
            try writer.writeAll(" return 1; } }\n");
        },
        .json_array_get => {
            try writer.writeAll(" { sa_store_u64(a2, 0);");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 6) return 1;");
            try writer.writeAll(" sa_u64 ci = o->first; sa_u64 i = 0;");
            try writer.writeAll(" while (ci != 0 && i < a1) {");
            try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" ci = m->next; i++; }");
            try writer.writeAll(" if (ci == 0) return 1;");
            try writer.writeAll(" { sa_json_node_t *m = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" if (m->h == 0) m->h = sa_alloc(8);");
            try writer.writeAll(" sa_store_u64(a2, m->h); return 0; } } }\n");
        },
        .json_value_count => {
            try writer.writeAll(" { sa_store_u64(a1, 0);");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || (o->kind != 6 && o->kind != 7)) return 1;");
            try writer.writeAll(" sa_u64 ci = o->first; sa_u64 n = 0;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *m = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" ci = m->next; n++; }");
            try writer.writeAll(" sa_store_u64(a1, n); return 0; } }\n");
        },
        .json_as_i64 => {
            try writer.writeAll(" { sa_store_u64(a1, 0);");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0) return 1;");
            try writer.writeAll(" if (o->kind == 2) { sa_store_u64(a1, (sa_u64)o->ival); return 0; }");
            try writer.writeAll(" if (o->kind == 3) {");
            try writer.writeAll(" union { sa_u64 u; double v; } t; t.u = o->fbits;");
            try writer.writeAll(" if (t.v != t.v) return 1;");
            try writer.writeAll(" if (t.v >= 9223372036854775808.0 || t.v < -9223372036854775808.0) return 1;");
            try writer.writeAll(" sa_i64 vv = (sa_i64)t.v;");
            try writer.writeAll(" union { sa_u64 u; double v; } u2; u2.v = (double)vv;");
            try writer.writeAll(" if (u2.u != o->fbits) return 1;");
            try writer.writeAll(" sa_store_u64(a1, (sa_u64)vv); return 0; }");
            try writer.writeAll(" return 1; } }\n");
        },
        .json_object_set_string => {
            try writer.writeAll(" { if (a2 == 0) return 1;");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
            try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" sa_u64 nx = cm->next;");
            try writer.writeAll(" sa_json_retire_subtree(cm);");
            try writer.writeAll(" ci = nx; }");
            try writer.writeAll(" m->first = 0; }");
            try writer.writeAll(" else { m = sa_json_new();");
            try writer.writeAll(" if (m == 0) return 2;");
            try writer.writeAll(" m->kptr = sa_json_guest_dup(a1, a2);");
            try writer.writeAll(" m->klen = a2;");
            try writer.writeAll(" sa_json_append_child(o, m); }");
            try writer.writeAll(" m->kind = 5;");
            try writer.writeAll(" m->vptr = sa_json_guest_dup(a3, a4);");
            try writer.writeAll(" m->vlen = a4;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_object_set_i64 => {
            try writer.writeAll(" { if (a2 == 0) return 1;");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
            try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" sa_u64 nx = cm->next;");
            try writer.writeAll(" sa_json_retire_subtree(cm);");
            try writer.writeAll(" ci = nx; }");
            try writer.writeAll(" m->first = 0; }");
            try writer.writeAll(" else { m = sa_json_new();");
            try writer.writeAll(" if (m == 0) return 2;");
            try writer.writeAll(" m->kptr = sa_json_guest_dup(a1, a2);");
            try writer.writeAll(" m->klen = a2;");
            try writer.writeAll(" sa_json_append_child(o, m); }");
            try writer.writeAll(" m->kind = 2;");
            try writer.writeAll(" m->ival = (sa_i64)a3;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_object_set_f64 => {
            try writer.writeAll(" { if (a2 == 0) return 1;");
            try writer.writeAll(" union { sa_u64 u; double v; } t; t.u = a3;");
            try writer.writeAll(" if (!(t.v <= 1.7976931348623157e308 &&");
            try writer.writeAll(" t.v >= -1.7976931348623157e308)) return 1;");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
            try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" sa_u64 nx = cm->next;");
            try writer.writeAll(" sa_json_retire_subtree(cm);");
            try writer.writeAll(" ci = nx; }");
            try writer.writeAll(" m->first = 0; }");
            try writer.writeAll(" else { m = sa_json_new();");
            try writer.writeAll(" if (m == 0) return 2;");
            try writer.writeAll(" m->kptr = sa_json_guest_dup(a1, a2);");
            try writer.writeAll(" m->klen = a2;");
            try writer.writeAll(" sa_json_append_child(o, m); }");
            try writer.writeAll(" m->kind = 3;");
            try writer.writeAll(" m->fbits = a3;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_object_set_bool => {
            try writer.writeAll(" { if (a2 == 0) return 1;");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
            try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" sa_u64 nx = cm->next;");
            try writer.writeAll(" sa_json_retire_subtree(cm);");
            try writer.writeAll(" ci = nx; }");
            try writer.writeAll(" m->first = 0; }");
            try writer.writeAll(" else { m = sa_json_new();");
            try writer.writeAll(" if (m == 0) return 2;");
            try writer.writeAll(" m->kptr = sa_json_guest_dup(a1, a2);");
            try writer.writeAll(" m->klen = a2;");
            try writer.writeAll(" sa_json_append_child(o, m); }");
            try writer.writeAll(" m->kind = 1;");
            try writer.writeAll(" m->bval = a3 != 0;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_object_set_null => {
            try writer.writeAll(" { if (a2 == 0) return 1;");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
            try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" sa_u64 nx = cm->next;");
            try writer.writeAll(" sa_json_retire_subtree(cm);");
            try writer.writeAll(" ci = nx; }");
            try writer.writeAll(" m->first = 0; }");
            try writer.writeAll(" else { m = sa_json_new();");
            try writer.writeAll(" if (m == 0) return 2;");
            try writer.writeAll(" m->kptr = sa_json_guest_dup(a1, a2);");
            try writer.writeAll(" m->klen = a2;");
            try writer.writeAll(" sa_json_append_child(o, m); }");
            try writer.writeAll(" m->kind = 0;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_object_set_node => {
            try writer.writeAll(" { if (a2 == 0) return 1;");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
            try writer.writeAll(" sa_json_node_t *ch = sa_json_find(a3);");
            try writer.writeAll(" if (ch == 0) return 2;");
            try writer.writeAll(" sa_json_node_t *cl = sa_json_clone_node(ch);");
            try writer.writeAll(" if (cl == 0) return 2;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
            try writer.writeAll(" if (m != 0) { sa_u64 ci = m->first;");
            try writer.writeAll(" while (ci != 0) {");
            try writer.writeAll(" sa_json_node_t *cm = &sa_json_nodes[ci - 1];");
            try writer.writeAll(" sa_u64 nx = cm->next;");
            try writer.writeAll(" sa_json_retire_subtree(cm);");
            try writer.writeAll(" ci = nx; }");
            try writer.writeAll(" m->kind = cl->kind;");
            try writer.writeAll(" m->vptr = cl->vptr;");
            try writer.writeAll(" m->vlen = cl->vlen;");
            try writer.writeAll(" m->ival = cl->ival;");
            try writer.writeAll(" m->fbits = cl->fbits;");
            try writer.writeAll(" m->bval = cl->bval;");
            try writer.writeAll(" m->first = cl->first;");
            try writer.writeAll(" cl->first = 0;");
            try writer.writeAll(" cl->h = 0; }");
            try writer.writeAll(" else { cl->kptr = sa_json_guest_dup(a1, a2);");
            try writer.writeAll(" cl->klen = a2;");
            try writer.writeAll(" sa_json_append_child(o, cl); }");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_object_remove => {
            try writer.writeAll(" { if (a2 == 0) return 1;");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 7) return 2;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" sa_json_node_t *m = sa_json_child_named(o, k, a2);");
            try writer.writeAll(" if (m == 0) return 3;");
            try writer.writeAll(" sa_json_unlink_child(o, m);");
            try writer.writeAll(" sa_json_retire_subtree(m);");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_array_push_string => {
            try writer.writeAll(" {");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
            try writer.writeAll(" sa_json_node_t *nd = sa_json_new();");
            try writer.writeAll(" if (nd == 0) return 2;");
            try writer.writeAll(" nd->kind = 5;");
            try writer.writeAll(" nd->vptr = sa_json_guest_dup(a1, a2);");
            try writer.writeAll(" nd->vlen = a2;");
            try writer.writeAll(" sa_json_append_child(o, nd);");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_array_push_i64 => {
            try writer.writeAll(" {");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
            try writer.writeAll(" sa_json_node_t *nd = sa_json_new();");
            try writer.writeAll(" if (nd == 0) return 2;");
            try writer.writeAll(" nd->kind = 2;");
            try writer.writeAll(" nd->ival = (sa_i64)a1;");
            try writer.writeAll(" sa_json_append_child(o, nd);");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_array_push_f64 => {
            try writer.writeAll(" {");
            try writer.writeAll(" union { sa_u64 u; double v; } t; t.u = a1;");
            try writer.writeAll(" if (!(t.v <= 1.7976931348623157e308 &&");
            try writer.writeAll(" t.v >= -1.7976931348623157e308)) return 1;");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
            try writer.writeAll(" sa_json_node_t *nd = sa_json_new();");
            try writer.writeAll(" if (nd == 0) return 2;");
            try writer.writeAll(" nd->kind = 3;");
            try writer.writeAll(" nd->fbits = a1;");
            try writer.writeAll(" sa_json_append_child(o, nd);");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_array_push_bool => {
            try writer.writeAll(" {");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
            try writer.writeAll(" sa_json_node_t *nd = sa_json_new();");
            try writer.writeAll(" if (nd == 0) return 2;");
            try writer.writeAll(" nd->kind = 1;");
            try writer.writeAll(" nd->bval = a1 != 0;");
            try writer.writeAll(" sa_json_append_child(o, nd);");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_array_push_null => {
            try writer.writeAll(" {");
            try writer.writeAll(" sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
            try writer.writeAll(" sa_json_node_t *nd = sa_json_new();");
            try writer.writeAll(" if (nd == 0) return 2;");
            try writer.writeAll(" nd->kind = 0;");
            try writer.writeAll(" sa_json_append_child(o, nd);");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_array_push_node => {
            try writer.writeAll(" { sa_json_node_t *o = sa_json_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 6) return 2;");
            try writer.writeAll(" sa_json_node_t *ch = sa_json_find(a1);");
            try writer.writeAll(" if (ch == 0) return 2;");
            try writer.writeAll(" sa_json_node_t *cl = sa_json_clone_node(ch);");
            try writer.writeAll(" if (cl == 0) return 2;");
            try writer.writeAll(" sa_json_append_child(o, cl);");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_new => {
            // Minified-only writers in the corpus; other whitespace modes
            // or flags fail loudly rather than emitting wrong JSON.
            try writer.writeAll(" { sa_store_u64(a5, 0);");
            try writer.writeAll(" if (a0 != 0 || a1 != 0 || a2 != 0 || a3 != 0 || a4 != 0) return 1;");
            try writer.writeAll(" unsigned i; sa_json_writer_t *w = 0;");
            try writer.writeAll(" for (i = 0; i < SA_JSON_MAX_WRITERS; i++)");
            try writer.writeAll(" if (sa_json_writers[i].h == 0) { w = &sa_json_writers[i]; break; }");
            try writer.writeAll(" if (w == 0) return 1;");
            try writer.writeAll(" { sa_u64 h = sa_alloc(8);");
            try writer.writeAll(" w->h = h; w->buf = 0; w->len = 0; w->cap = 0;");
            try writer.writeAll(" w->depth = 0; w->done = 0; w->started = 0;");
            try writer.writeAll(" w->complete = 0; w->pending = 0;");
            try writer.writeAll(" sa_store_u64(a5, h); return 0; } } }\n");
        },
        .json_writer_begin_object => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0) return 1;");
            try writer.writeAll(" if (w->pending) w->pending = 0;");
            try writer.writeAll(" else {");
            try writer.writeAll(" if (w->depth == 0) {");
            try writer.writeAll(" if (w->complete) return 1;");
            try writer.writeAll(" w->started = 1; w->complete = 1; }");
            try writer.writeAll(" else {");
            try writer.writeAll(" if (w->first[w->depth - 1]) w->first[w->depth - 1] = 0;");
            try writer.writeAll(" else if (sa_jw_putc(w, ',')) return 1;");
            try writer.writeAll(" w->started = 1; } }");
            try writer.writeAll(" if (w->depth >= 32) return 1;");
            try writer.writeAll(" w->kinds[w->depth] = '{'; w->first[w->depth] = 1; w->depth++;");
            try writer.writeAll(" if (sa_jw_putc(w, '{')) return 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_end_object => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0 || w->depth == 0 || w->pending) return 1;");
            try writer.writeAll(" if (w->kinds[w->depth - 1] != '{') return 1;");
            try writer.writeAll(" w->depth--;");
            try writer.writeAll(" if (sa_jw_putc(w, '}')) return 1;");
            try writer.writeAll(" if (w->depth == 0) w->complete = 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_begin_array => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0) return 1;");
            try writer.writeAll(" if (w->pending) w->pending = 0;");
            try writer.writeAll(" else {");
            try writer.writeAll(" if (w->depth == 0) {");
            try writer.writeAll(" if (w->complete) return 1;");
            try writer.writeAll(" w->started = 1; w->complete = 1; }");
            try writer.writeAll(" else {");
            try writer.writeAll(" if (w->first[w->depth - 1]) w->first[w->depth - 1] = 0;");
            try writer.writeAll(" else if (sa_jw_putc(w, ',')) return 1;");
            try writer.writeAll(" w->started = 1; } }");
            try writer.writeAll(" if (w->depth >= 32) return 1;");
            try writer.writeAll(" w->kinds[w->depth] = '['; w->first[w->depth] = 1; w->depth++;");
            try writer.writeAll(" if (sa_jw_putc(w, '[')) return 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_end_array => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0 || w->depth == 0 || w->pending) return 1;");
            try writer.writeAll(" if (w->kinds[w->depth - 1] != '[') return 1;");
            try writer.writeAll(" w->depth--;");
            try writer.writeAll(" if (sa_jw_putc(w, ']')) return 1;");
            try writer.writeAll(" if (w->depth == 0) w->complete = 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_field_bool => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0 || w->pending || w->depth == 0 || w->kinds[w->depth - 1] != '{') return 1;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
            try writer.writeAll(" if (sa_jw_string(w, &sa_mem[k], (size_t)a2)) return 1;");
            try writer.writeAll(" if (sa_jw_putc(w, ':')) return 1;");
            try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)(a3 ? \"true\" : \"false\"), a3 ? 4 : 5)) return 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_field_i64 => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0 || w->pending || w->depth == 0 || w->kinds[w->depth - 1] != '{') return 1;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
            try writer.writeAll(" if (sa_jw_string(w, &sa_mem[k], (size_t)a2)) return 1;");
            try writer.writeAll(" if (sa_jw_putc(w, ':')) return 1;");
            try writer.writeAll(" { char tmp[130];");
            try writer.writeAll(" int n = sa_fmt_int(tmp, a3, 10, 1, 0);");
            try writer.writeAll(" if (n < 0) return 1;");
            try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)tmp, (size_t)n)) return 1; }");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_field_f64 => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0 || w->pending || w->depth == 0 || w->kinds[w->depth - 1] != '{') return 1;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
            try writer.writeAll(" if (sa_jw_string(w, &sa_mem[k], (size_t)a2)) return 1;");
            try writer.writeAll(" if (sa_jw_putc(w, ':')) return 1;");
            try writer.writeAll(" { union { sa_u64 u; double d; } t; t.u = a3;");
            try writer.writeAll(" if (t.d != t.d) return 1;");
            try writer.writeAll(" if ((t.u & (sa_u64)0x7FF0000000000000ULL) == (sa_u64)0x7FF0000000000000ULL) return 1;");
            try writer.writeAll(" char tmp[256];");
            try writer.writeAll(" int n = snprintf(tmp, sizeof(tmp), \"%.17g\", t.d);");
            try writer.writeAll(" if (n < 0 || n >= 256) return 1;");
            try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)tmp, (size_t)n)) return 1; }");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_field_string => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0 || w->pending || w->depth == 0 || w->kinds[w->depth - 1] != '{') return 1;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" uint32_t v = sa_checked_addr(a3, (size_t)a4);");
            try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
            try writer.writeAll(" if (sa_jw_string(w, &sa_mem[k], (size_t)a2)) return 1;");
            try writer.writeAll(" if (sa_jw_putc(w, ':')) return 1;");
            try writer.writeAll(" if (sa_jw_string(w, &sa_mem[v], (size_t)a4)) return 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_object_field => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0 || w->pending || w->depth == 0 || w->kinds[w->depth - 1] != '{') return 1;");
            try writer.writeAll(" uint32_t k = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
            try writer.writeAll(" if (sa_jw_string(w, &sa_mem[k], (size_t)a2)) return 1;");
            try writer.writeAll(" if (sa_jw_putc(w, ':')) return 1;");
            try writer.writeAll(" w->pending = 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_write_bool => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0) return 1;");
            try writer.writeAll(" if (!w->pending && w->depth > 0 && w->kinds[w->depth - 1] == '{') return 1;");
            try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
            try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)(a1 ? \"true\" : \"false\"), a1 ? 4 : 5)) return 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_write_i64 => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0) return 1;");
            try writer.writeAll(" if (!w->pending && w->depth > 0 && w->kinds[w->depth - 1] == '{') return 1;");
            try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
            try writer.writeAll(" { char tmp[130];");
            try writer.writeAll(" int n = sa_fmt_int(tmp, a1, 10, 1, 0);");
            try writer.writeAll(" if (n < 0) return 1;");
            try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)tmp, (size_t)n)) return 1; }");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_write_f64 => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0) return 1;");
            try writer.writeAll(" if (!w->pending && w->depth > 0 && w->kinds[w->depth - 1] == '{') return 1;");
            try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
            try writer.writeAll(" { union { sa_u64 u; double d; } t; t.u = a1;");
            try writer.writeAll(" if (t.d != t.d) return 1;");
            try writer.writeAll(" if ((t.u & (sa_u64)0x7FF0000000000000ULL) == (sa_u64)0x7FF0000000000000ULL) return 1;");
            try writer.writeAll(" char tmp[256];");
            try writer.writeAll(" int n = snprintf(tmp, sizeof(tmp), \"%.17g\", t.d);");
            try writer.writeAll(" if (n < 0 || n >= 256) return 1;");
            try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)tmp, (size_t)n)) return 1; }");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_write_string => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0) return 1;");
            try writer.writeAll(" if (!w->pending && w->depth > 0 && w->kinds[w->depth - 1] == '{') return 1;");
            try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
            try writer.writeAll(" { uint32_t v = sa_checked_addr(a1, (size_t)a2);");
            try writer.writeAll(" if (sa_jw_string(w, &sa_mem[v], (size_t)a2)) return 1; }");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_write_null => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0) return 1;");
            try writer.writeAll(" if (!w->pending && w->depth > 0 && w->kinds[w->depth - 1] == '{') return 1;");
            try writer.writeAll(" if (sa_jw_value_begin(w)) return 1;");
            try writer.writeAll(" if (sa_jw_write(w, (const uint8_t *)\"null\", 4)) return 1;");
            try writer.writeAll(" return 0; } }\n");
        },
        .json_writer_finish => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" sa_store_u64(a1, 0);");
            try writer.writeAll(" if (w == 0 || !w->started || w->pending || w->depth != 0 || w->done) return 1;");
            try writer.writeAll(" { sa_u64 h = sa_owned_new(w->buf, w->len, 2);");
            try writer.writeAll(" if (h == 0) return 1;");
            try writer.writeAll(" w->done = 1;");
            try writer.writeAll(" sa_store_u64(a1, h); return 0; } } }\n");
        },
        .json_writer_free => {
            try writer.writeAll(" { sa_json_writer_t *w = sa_json_writer_find(a0);");
            try writer.writeAll(" if (w == 0) return 0;");
            try writer.writeAll(" w->h = 0; return 0; } }\n");
        },
        .json_buffer_data => {
            try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 2) return 0;");
            try writer.writeAll(" return o->ptr; } }\n");
        },
        .json_buffer_len => {
            try writer.writeAll(" { sa_owned_buf_t *o = sa_owned_find(a0);");
            try writer.writeAll(" if (o == 0 || o->kind != 2) return 0;");
            try writer.writeAll(" return o->len; } }\n");
        },
        .json_buffer_free => {
            try writer.writeAll(" { sa_owned_drop(a0); return 0; } }\n");
        },
        .time_get_full_year => {
            try writer.writeAll(" { sa_i64 y, mo, d;");
            try writer.writeAll(" sa_civil_ymd((sa_i64)a0, &y, &mo, &d);");
            try writer.writeAll(" return (sa_u64)y; } }\n");
        },
        .time_get_month => {
            // 0-based like JS getMonth (mirrors the interpreter).
            try writer.writeAll(" { sa_i64 y, mo, d;");
            try writer.writeAll(" sa_civil_ymd((sa_i64)a0, &y, &mo, &d);");
            try writer.writeAll(" return (sa_u64)(mo - 1); } }\n");
        },
        .time_get_date => {
            try writer.writeAll(" { sa_i64 y, mo, d;");
            try writer.writeAll(" sa_civil_ymd((sa_i64)a0, &y, &mo, &d);");
            try writer.writeAll(" return (sa_u64)d; } }\n");
        },
        .time_parse_iso => {
            // Strict ISO YYYY-MM-DD[THH:MM:SS[.sss]][Z|+-HH:MM] to unix
            // millis; 0 ok (writes *out_ms, pre-zeroed), 1 invalid.
            try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a1);");
            try writer.writeAll(" sa_store_u64(a2, 0);");
            try writer.writeAll(" size_t p = 0;");
            try writer.writeAll(" sa_i64 v = 0; size_t k; size_t q;");
            try writer.writeAll(" if ((size_t)a1 < 10) return 1;");
            try writer.writeAll(" for (k = 0; k < 4; k++) {");
            try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
            try writer.writeAll(" if (c < '0' || c > '9') return 1;");
            try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
            try writer.writeAll(" sa_i64 year = v; p = 4;");
            try writer.writeAll(" if (sa_mem[x + p] != '-') return 1; p++;");
            try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
            try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
            try writer.writeAll(" if (c < '0' || c > '9') return 1;");
            try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
            try writer.writeAll(" sa_i64 month = v; p += 2;");
            try writer.writeAll(" if (sa_mem[x + p] != '-') return 1; p++;");
            try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
            try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
            try writer.writeAll(" if (c < '0' || c > '9') return 1;");
            try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
            try writer.writeAll(" sa_i64 day = v; p += 2;");
            try writer.writeAll(" sa_i64 hour = 0; sa_i64 minute = 0;");
            try writer.writeAll(" sa_i64 second = 0; sa_i64 milli = 0;");
            try writer.writeAll(" if (p < (size_t)a1) {");
            try writer.writeAll(" uint8_t t = sa_mem[x + p];");
            try writer.writeAll(" if (t != 'T' && t != 't' && t != ' ') return 1; p++;");
            try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
            try writer.writeAll(" if (p + k >= (size_t)a1) return 1;");
            try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
            try writer.writeAll(" if (c < '0' || c > '9') return 1;");
            try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
            try writer.writeAll(" hour = v; p += 2;");
            try writer.writeAll(" if (p >= (size_t)a1 || sa_mem[x + p] != ':') return 1; p++;");
            try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
            try writer.writeAll(" if (p + k >= (size_t)a1) return 1;");
            try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
            try writer.writeAll(" if (c < '0' || c > '9') return 1;");
            try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
            try writer.writeAll(" minute = v; p += 2;");
            try writer.writeAll(" if (p >= (size_t)a1 || sa_mem[x + p] != ':') return 1; p++;");
            try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
            try writer.writeAll(" if (p + k >= (size_t)a1) return 1;");
            try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
            try writer.writeAll(" if (c < '0' || c > '9') return 1;");
            try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
            try writer.writeAll(" second = v; p += 2;");
            try writer.writeAll(" if (p < (size_t)a1 && sa_mem[x + p] == '.') { p++;");
            try writer.writeAll(" size_t fs = p;");
            try writer.writeAll(" while (p < (size_t)a1 && sa_mem[x + p] >= '0' && sa_mem[x + p] <= '9') p++;");
            try writer.writeAll(" size_t fl = p - fs;");
            try writer.writeAll(" if (fl == 0 || fl > 3) return 1;");
            try writer.writeAll(" v = 0; for (q = fs; q < p; q++)");
            try writer.writeAll(" v = v * 10 + (sa_i64)(sa_mem[x + q] - '0');");
            try writer.writeAll(" milli = fl == 1 ? v * 100 : (fl == 2 ? v * 10 : v); } }");
            try writer.writeAll(" sa_i64 offm = 0;");
            try writer.writeAll(" if (p < (size_t)a1) {");
            try writer.writeAll(" uint8_t z = sa_mem[x + p];");
            try writer.writeAll(" if (z == 'Z' || z == 'z') { p++; }");
            try writer.writeAll(" else if (z == '+' || z == '-') {");
            try writer.writeAll(" int neg = z == '-'; p++;");
            try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
            try writer.writeAll(" if (p + k >= (size_t)a1) return 1;");
            try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
            try writer.writeAll(" if (c < '0' || c > '9') return 1;");
            try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
            try writer.writeAll(" sa_i64 oh = v; p += 2;");
            try writer.writeAll(" if (p >= (size_t)a1 || sa_mem[x + p] != ':') return 1; p++;");
            try writer.writeAll(" v = 0; for (k = 0; k < 2; k++) {");
            try writer.writeAll(" if (p + k >= (size_t)a1) return 1;");
            try writer.writeAll(" uint8_t c = sa_mem[x + p + k];");
            try writer.writeAll(" if (c < '0' || c > '9') return 1;");
            try writer.writeAll(" v = v * 10 + (sa_i64)(c - '0'); }");
            try writer.writeAll(" sa_i64 om = v; p += 2;");
            try writer.writeAll(" if (oh > 23 || om > 59) return 1;");
            try writer.writeAll(" offm = oh * 60 + om; if (neg) offm = -offm;");
            try writer.writeAll(" } else return 1; }");
            try writer.writeAll(" if (p != (size_t)a1) return 1;");
            try writer.writeAll(" if (month < 1 || month > 12) return 1;");
            try writer.writeAll(" { int leap = (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0));");
            try writer.writeAll(" sa_i64 dim = 31;");
            try writer.writeAll(" if (month == 2) dim = leap ? 29 : 28;");
            try writer.writeAll(" else if (month == 4 || month == 6 || month == 9 || month == 11) dim = 30;");
            try writer.writeAll(" if (day < 1 || day > dim) return 1; }");
            try writer.writeAll(" if (hour > 23 || minute > 59 || second > 59) return 1;");
            try writer.writeAll(" { sa_i64 yy = month <= 2 ? year - 1 : year;");
            try writer.writeAll(" sa_i64 era = yy >= 0 ? sa_div_floor(yy, 400) : sa_div_floor(yy - 399, 400);");
            try writer.writeAll(" sa_i64 yoe = yy - era * 400;");
            try writer.writeAll(" sa_i64 mp = sa_mod_floor(month - 3, 12);");
            try writer.writeAll(" sa_i64 doy = sa_div_floor(153 * mp + 2, 5) + day - 1;");
            try writer.writeAll(" sa_i64 doe = yoe * 365 + sa_div_floor(yoe, 4) - sa_div_floor(yoe, 100) + doy;");
            try writer.writeAll(" sa_i64 days = era * 146097 + doe - 719468;");
            try writer.writeAll(" sa_store_u64(a2, (sa_u64)(((days * 86400 + hour * 3600 + minute * 60 + second) * 1000 + milli) - offm * 60000));");
            try writer.writeAll(" return 0; } } }\n");
        },
        .time_set_field => {
            try writer.writeAll(" { sa_i64 ms = (sa_i64)a0; sa_u64 f = a1; sa_i64 v = (sa_i64)a2;");
            try writer.writeAll(" sa_i64 day_ms = sa_mod_floor(ms, 86400000);");
            try writer.writeAll(" sa_i64 y, mo, d;");
            try writer.writeAll(" sa_civil_ymd(ms, &y, &mo, &d);");
            try writer.writeAll(" sa_i64 tod = day_ms / 3600000 * 3600000 + sa_mod_floor(day_ms, 3600000);");
            try writer.writeAll(" tod = tod / 60000 * 60000 + sa_mod_floor(day_ms, 60000);");
            try writer.writeAll(" tod = tod / 1000 * 1000 + sa_mod_floor(day_ms, 1000);");
            try writer.writeAll(" if (f == 0) y = v;");
            try writer.writeAll(" else if (f == 1) {");
            try writer.writeAll(" sa_i64 tm = y * 12 + v;");
            try writer.writeAll(" y = sa_div_floor(tm, 12); mo = sa_mod_floor(tm, 12) + 1; }");
            try writer.writeAll(" else if (f == 2) d = v;");
            try writer.writeAll(" else if (f == 3) tod = v * 3600000 + sa_mod_floor(tod, 3600000);");
            try writer.writeAll(" else if (f == 4) tod = (tod - sa_mod_floor(tod, 3600000)) + v * 60000 + sa_mod_floor(tod, 60000);");
            try writer.writeAll(" else if (f == 5) tod = (tod - sa_mod_floor(tod, 60000)) + v * 1000 + sa_mod_floor(tod, 1000);");
            try writer.writeAll(" else if (f == 6) tod = tod - sa_mod_floor(tod, 1000) + v;");
            try writer.writeAll(" else return ms;");
            try writer.writeAll(" { sa_i64 tm = y * 12 + (mo - 1);");
            try writer.writeAll(" sa_i64 y2 = sa_div_floor(tm, 12);");
            try writer.writeAll(" sa_i64 m2 = sa_mod_floor(tm, 12) + 1;");
            try writer.writeAll(" sa_i64 yy = m2 <= 2 ? y2 - 1 : y2;");
            try writer.writeAll(" sa_i64 era = yy >= 0 ? sa_div_floor(yy, 400) : sa_div_floor(yy - 399, 400);");
            try writer.writeAll(" sa_i64 yoe = yy - era * 400;");
            try writer.writeAll(" sa_i64 mp = sa_mod_floor(m2 - 3, 12);");
            try writer.writeAll(" sa_i64 doy = sa_div_floor(153 * mp + 2, 5) + d - 1;");
            try writer.writeAll(" sa_i64 doe = yoe * 365 + sa_div_floor(yoe, 4) - sa_div_floor(yoe, 100) + doy;");
            try writer.writeAll(" sa_i64 dys = era * 146097 + doe - 719468;");
            try writer.writeAll(" sa_i64 tdys = dys + sa_div_floor(tod, 86400000);");
            try writer.writeAll(" sa_i64 tnorm = tod - sa_div_floor(tod, 86400000) * 86400000;");
            try writer.writeAll(" return (sa_u64)((tdys * 86400) * 1000 + tnorm); } } }\n");
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
        .hc_req_new_joined => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); sa_u64 n = a3 + a5; sa_u64 buf; sa_u64 i; if (s == 0) return 1; buf = sa_alloc(n); for (i = 0; i < a3; i++) sa_mem[buf + i] = sa_mem[a2 + i]; for (i = 0; i < a5; i++) sa_mem[buf + a3 + i] = sa_mem[a4 + i]; s->h = h; s->aux0 = buf; s->aux1 = n; s->aux2 = 0; sa_store_u64(a7, h); return 0; } }\n");
        },
        .hc_req_openai_auth => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1; return 0; } }\n");
        },
        .hc_send_async => {
            try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = q->aux0; s->aux1 = q->aux1; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
        },
        .hc_op_poll => {
            try writer.writeAll(" { sa_http_obj_t *o = sa_http_find(sa_http_objs, a0); if (o == 0) return 1; sa_store_u64(a1, o->aux2 ? 0 : 1); return 0; } }\n");
        },
        .hc_op_take => {
            try writer.writeAll(" { sa_http_obj_t *o = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (o == 0) return 1; if (o->aux2) return 1; o->aux2 = 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = o->aux0; s->aux1 = o->aux1; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
        },
        .hc_op_free => {
            try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
        .hc_resp_get_header => {
            try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0); if (r == 0) return 1; sa_store_u64(a4, 0); return 2; } }\n");
        },
        .hc_resp_body_slice => {
            try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0); if (r == 0) return 1; sa_store_u64(a1, r->aux0); sa_store_u64(a2, r->aux1); return 0; } }\n");
        },
        .hc_resp_body_ptr => {
            try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0); return r ? r->aux0 : 0; } }\n");
        },
        .hc_resp_body_len => {
            try writer.writeAll(" { sa_http_obj_t *r = sa_http_find(sa_http_objs, a0); return r ? r->aux1 : 0; } }\n");
        },
        .hc_ws_connect => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a3, h); return 0; } }\n");
        },
        .hc_ws_read => {
            try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; if (!w->aux2) { sa_store_u64(a2, 0); sa_store_u64(a3, 0); sa_store_u64(a4, 0); return 2; } sa_store_u64(a2, w->aux2 - 1); sa_store_u64(a3, w->aux0); sa_store_u64(a4, w->aux1); w->aux2 = 0; return 0; } }\n");
        },
        .hc_ws_write => {
            try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; if (sa_nb_ws_closed_get(a0)) return 2; if (w->aux2) return 1; w->aux0 = a2; w->aux1 = a3; w->aux2 = a1 + 1; return 0; } }\n");
        },
        .hc_ws_free => {
            try writer.writeAll(" { sa_nb_ws_meta_clear(a0); sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
        .hc2_client_new => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a3, h); return 0; } }\n");
        },
        .hc2_req_new => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = a2; s->aux1 = a3; s->aux2 = 0; sa_store_u64(a4, h); return 0; } }\n");
        },
        .hc2_add_header => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 5; return 0; } }\n");
        },
        .hc2_set_body => {
            try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); if (q == 0) return 5; q->aux0 = a1; q->aux1 = a2; return 0; } }\n");
        },
        .hc2_set_timeout => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 5; return 0; } }\n");
        },
        .hc2_set_max => {
            try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); if (q == 0) return 5; q->aux2 = a1; return 0; } }\n");
        },
        .hc2_send => {
            try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 5; if (q->aux2 && q->aux1 > q->aux2) return 4; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = q->aux0; s->aux1 = q->aux1; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
        },
        .hc2_send_async => {
            try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 5; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = q->aux0; s->aux1 = q->aux1; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
        },
        .hc2_poll => {
            try writer.writeAll(" { sa_http_obj_t *o = sa_http_find(sa_http_objs, a0); if (o == 0) return 5; sa_store_u64(a2, o->aux2 ? 0 : 1); return 0; } }\n");
        },
        .hc2_take => {
            try writer.writeAll(" { sa_http_obj_t *o = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (o == 0) return 5; if (o->aux2) return 5; o->aux2 = 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = o->aux0; s->aux1 = o->aux1; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
        },
        .hc2_cancel => {
            try writer.writeAll(" { sa_http_obj_t *o = sa_http_find(sa_http_objs, a0); if (o == 0) return 5; o->aux2 = 1; return 0; } }\n");
        },
        .hc2_free_obj => {
            try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
        .hc2_ws_connect4 => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a4, h); return 0; } }\n");
        },
        .hc2_ws_connect6 => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a6, h); return 0; } }\n");
        },
        .hc2_ws_connect2 => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 5; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a2, h); return 0; } }\n");
        },
        .hc2_ws_poll => {
            try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 5; sa_store_u64(a3, 2 | (w->aux2 < w->aux1 ? 1 : 0) | (sa_nb_ws_closed_get(a0) ? 4 : 0)); return 0; } }\n");
        },
        .hc2_ws_read => {
            try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 5; if (w->aux2 >= w->aux1) { if (sa_nb_ws_closed_get(a0)) { sa_store_u64(a3, 0); sa_store_u64(a4, 0); return 2; } return 1; } sa_store_u64(a2, (sa_u64)sa_nb_ws_opcode_get(a0)); sa_store_u64(a3, w->aux0 + w->aux2); sa_store_u64(a4, w->aux1 - w->aux2); w->aux2 = w->aux1; return 0; } }\n");
        },
        .hc2_ws_write => {
            try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 5; if (sa_nb_ws_closed_get(a0)) return 2; if (w->aux1 > w->aux2) return 1; w->aux0 = a2; w->aux1 = a3; w->aux2 = 0; sa_nb_ws_meta_set(a0, (int)a1, -1); sa_store_u64(a4, a3); return 0; } }\n");
        },
        .hc2_ws_close => {
            try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 5; sa_nb_ws_meta_set(a0, -1, 1); return 0; } }\n");
        },
        .hc_sse_post => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = a2; s->aux1 = a3; s->aux2 = 0; sa_store_u64(a6, h); return 0; } }\n");
        },
        .hc_sse_read => {
            try writer.writeAll(" { sa_http_obj_t *s = sa_http_find(sa_http_objs, a0); sa_u64 rem, n, i; if (s == 0) return 1; rem = s->aux1 - s->aux2; n = rem < a2 ? rem : a2; for (i = 0; i < n; i++) sa_mem[a1 + i] = sa_mem[s->aux0 + s->aux2 + i]; s->aux2 += n; sa_store_u64(a3, n); return n == 0 ? 2 : 0; } }\n");
        },
        .hc_sse_poll => {
            try writer.writeAll(" { sa_http_obj_t *s = sa_http_find(sa_http_objs, a0); if (s == 0) return 1; sa_store_u64(a1, s->aux2 >= s->aux1 ? 1 : 0); return 0; } }\n");
        },
        .hc_sse_status => {
            try writer.writeAll(" { sa_http_obj_t *s = sa_http_find(sa_http_objs, a0); return s ? 200 : 0; } }\n");
        },
        .hc_sse_turn => {
            try writer.writeAll(" { sa_store_u64(a7, a2); sa_store_u64(a8, a3); sa_store_u64(a9, 0); sa_store_u64(a10, 0); return 0; } }\n");
        },
        .hc_sse_turn_free => {
            try writer.writeAll(" { (void)a0; (void)a1; } }\n");
        },
        .hs_req_get_method => {
            try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 p; if (q == 0) return 1; p = sa_alloc(3); sa_mem[p] = 71; sa_mem[p + 1] = 69; sa_mem[p + 2] = 84; sa_store_u64(a1, p); sa_store_u64(a2, 3); return 0; } }\n");
        },
        .hs_resp_new => {
            try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a2, h); return 0; } }\n");
        },
        .hs_check0 => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1; return 0; } }\n");
        },
        .hs_resp_send => {
            try writer.writeAll(" { if (sa_http_find(sa_http_objs, a0) == 0) return 1; return 0; } }\n");
        },
        .hs_free => {
            try writer.writeAll(" { sa_http_drop(sa_http_objs, a0); return 0; } }\n");
        },
        .hs_ws_upgrade => {
            try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a1, h); return 0; } }\n");
        },
        .hs_serve_threaded => {
            try writer.writeAll(" { (void)a0; return 0; } }\n");
        },
        .hs2_new => {
            try writer.writeAll(" { sa_u64 h = sa_alloc(8); sa_http_obj_t *s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a0, h); return 0; } }\n");
        },
        .hs2_accept => {
            try writer.writeAll(" { sa_http_obj_t *q = sa_http_find(sa_http_objs, a0); sa_u64 h; sa_http_obj_t *s; if (q == 0) return 1; h = sa_alloc(8); s = sa_http_slot(sa_http_objs); if (s == 0) return 1; s->h = h; s->aux0 = 0; s->aux1 = 0; s->aux2 = 0; sa_store_u64(a2, h); return 0; } }\n");
        },
        .hs2_ws_poll => {
            try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; sa_store_u64(a3, 2 | (w->aux2 < w->aux1 ? 1 : 0) | (sa_nb_ws_closed_get(a0) ? 4 : 0)); return 0; } }\n");
        },
        .hs2_ws_read => {
            try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; if (w->aux2 >= w->aux1) { if (sa_nb_ws_closed_get(a0)) { sa_store_u64(a3, 0); sa_store_u64(a4, 0); return 2; } return 1; } sa_store_u64(a2, (sa_u64)sa_nb_ws_opcode_get(a0)); sa_store_u64(a3, w->aux0 + w->aux2); sa_store_u64(a4, w->aux1 - w->aux2); w->aux2 = w->aux1; return 0; } }\n");
        },
        .hs2_ws_write => {
            try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; if (sa_nb_ws_closed_get(a0)) return 2; if (w->aux1 > w->aux2) return 1; w->aux0 = a2; w->aux1 = a3; w->aux2 = 0; sa_nb_ws_meta_set(a0, (int)a1, -1); sa_store_u64(a4, a3); return 0; } }\n");
        },
        .hs2_ws_close => {
            try writer.writeAll(" { sa_http_obj_t *w = sa_http_find(sa_http_objs, a0); if (w == 0) return 1; sa_nb_ws_meta_set(a0, -1, 1); return 0; } }\n");
        },
        .nb_compress_supported => {
            try writer.writeAll(" { sa_store_u64(a0, 1); return 0; } }\n");
        },
        .nb_compress_encode => {
            try writer.writeAll(" { return sa_nb_deflate((int)a0, (uint32_t)a1, a2, a3); } }\n");
        },
        .nb_compress_decode => {
            try writer.writeAll(" { return sa_nb_undeflate((int)a0, (uint32_t)a1, a2, a3); } }\n");
        },
        .nb_buf_data => {
            try writer.writeAll(" { sa_nb_buf_t *b = sa_nb_buf_find(a0); return b ? (sa_u64)b->addr : 0; } }\n");
        },
        .nb_buf_len => {
            try writer.writeAll(" { sa_nb_buf_t *b = sa_nb_buf_find(a0); return b ? b->len : 0; } }\n");
        },
        .nb_buf_free => {
            try writer.writeAll(" { return sa_nb_buf_drop(a0) ? 0 : 2; } }\n");
        },
        .mp_parse => {
            try writer.writeAll(" { return sa_mp_parse(a0, a1, a2, a3, a4); } }\n");
        },
        .mp_free => {
            try writer.writeAll(" { sa_mp_t *mp = sa_mp_find(a0); if (!mp) return 3; mp->h = 0; return 0; } }\n");
        },
        .mp_count => {
            try writer.writeAll(" { sa_mp_t *mp = sa_mp_find(a0); sa_u64 c = 0, so, sn; if (!mp) return 0; while (sa_mp_seek(mp, c, &so, &sn)) c++; return c; } }\n");
        },
        .mp_part_name => {
            try writer.writeAll(" { return sa_mp_field(a0, a1, 0, a2, a4, a3); } }\n");
        },
        .mp_part_filename => {
            try writer.writeAll(" { return sa_mp_field(a0, a1, 1, a2, a4, a3); } }\n");
        },
        .mp_part_content_type => {
            try writer.writeAll(" { return sa_mp_field(a0, a1, 2, a2, a4, a3); } }\n");
        },
        .mp_part_header => {
            try writer.writeAll(" { return sa_mp_header(a0, a1, a2, a3, a4, a6, a5); } }\n");
        },
        .mp_part_body => {
            try writer.writeAll(" { return sa_mp_part_body(a0, a1, a2, a3); } }\n");
        },
        .mp_builder_new => {
            try writer.writeAll(" { return sa_mp_builder_new(0, 0, a0); } }\n");
        },
        .mp_builder_free => {
            try writer.writeAll(" { sa_mp_t *mp = sa_mp_find(a0); if (!mp) return 3; mp->h = 0; return 0; } }\n");
        },
        .mp_builder_add_field => {
            try writer.writeAll(" { return sa_mp_add_field(a0, a1, a2, a3, a4, 0, 0, 0, 0, 0, 0, 0); } }\n");
        },
        .mp_builder_add_file => {
            try writer.writeAll(" { return sa_mp_add_field(a0, a1, a2, 0, 0, 1, a3, a4, a5, a6, a7, a8); } }\n");
        },
        .mp_builder_boundary => {
            try writer.writeAll(" { return sa_mp_bnd_out(a0, a1, a3, a2); } }\n");
        },
        .mp_builder_content_type => {
            try writer.writeAll(" { return sa_mp_ctype_out(a0, a1, a3, a2); } }\n");
        },
        .mp_builder_finish => {
            try writer.writeAll(" { return sa_mp_builder_finish(a0, a1); } }\n");
        },
        .ssh_supported => {
            try writer.writeAll(" { sa_store_u64(a0, 0); return 0; } }\n");
        },
        .ssh_buf_data => {
            try writer.writeAll(" { return 0; } }\n");
        },
        .ssh_buf_len => {
            try writer.writeAll(" { return 0; } }\n");
        },
        .ssh_buf_free => {
            try writer.writeAll(" { return 0; } }\n");
        },
        .cookie_parse => {
            // Direct link: the real RFC 6265 parser in libsa_std.a;
            // the guest byte span is handed over as a host pointer
            // into linear memory, the returned handle passes through.
            try writer.writeAll(" return sa_cookie_parse_set_cookie(sa_glue_cptr(a0, a1), a1); }\n");
        },
        .cookie_last_error => {
            try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_last_error(&hp, &hn); sa_glue_out_str(a0, a1, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_free => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_free(a0); }\n");
        },
        .cookie_new => {
            try writer.writeAll(" return sa_cookie_new(sa_glue_cptr(a0, a1), a1, sa_glue_cptr(a2, a3), a3); }\n");
        },
        .cookie_name => {
            try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_name(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_value => {
            try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_value(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_domain => {
            try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_domain(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_path => {
            try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_path(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_expires => {
            try writer.writeAll(" { int64_t v = 0; int32_t st = sa_cookie_expires(a0, &v); sa_store_u64(a1, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_max_age => {
            try writer.writeAll(" { int64_t v = 0; int32_t st = sa_cookie_max_age(a0, &v); sa_store_u64(a1, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_flags => {
            try writer.writeAll(" { int32_t x = 0, y = 0, z = 0; int32_t st = sa_cookie_flags(a0, &x, &y, &z); sa_store_u32(a1, (sa_u64)(uint32_t)x); sa_store_u32(a2, (sa_u64)(uint32_t)y); sa_store_u32(a3, (sa_u64)(uint32_t)z); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_same_site => {
            try writer.writeAll(" { uint32_t v = 0; int32_t st = sa_cookie_same_site(a0, &v); sa_store_u32(a1, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_is_host_only => {
            try writer.writeAll(" { int32_t v = 0; int32_t st = sa_cookie_is_host_only(a0, &v); sa_store_u32(a1, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_set_domain => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_domain(a0, sa_glue_cptr(a1, a2), a2); }\n");
        },
        .cookie_set_path => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_path(a0, sa_glue_cptr(a1, a2), a2); }\n");
        },
        .cookie_set_expires => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_expires(a0, (sa_i64)a1); }\n");
        },
        .cookie_set_max_age => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_max_age(a0, (sa_i64)a1); }\n");
        },
        .cookie_clear_expiry => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_clear_expiry(a0); }\n");
        },
        .cookie_set_secure => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_secure(a0, (int32_t)a1); }\n");
        },
        .cookie_set_http_only => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_http_only(a0, (int32_t)a1); }\n");
        },
        .cookie_set_partitioned => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_partitioned(a0, (int32_t)a1); }\n");
        },
        .cookie_set_same_site => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_set_same_site(a0, (uint32_t)a1); }\n");
        },
        .cookie_serialize => {
            try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_serialize(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_serialize_pair => {
            try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_serialize_pair(a0, &hp, &hn); sa_glue_out_str(a1, a2, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_is_expired => {
            try writer.writeAll(" { int32_t v = 0; int32_t st = sa_cookie_is_expired(a0, (sa_i64)a1, &v); sa_store_u32(a2, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_domain_match => {
            try writer.writeAll(" { int32_t v = 0; int32_t st = sa_cookie_domain_match(sa_glue_cptr(a0, a1), a1, sa_glue_cptr(a2, a3), a3, &v); sa_store_u32(a4, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_path_match => {
            try writer.writeAll(" { int32_t v = 0; int32_t st = sa_cookie_path_match(sa_glue_cptr(a0, a1), a1, sa_glue_cptr(a2, a3), a3, &v); sa_store_u32(a4, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_header_pair_count => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_cookie_header_pair_count(sa_glue_cptr(a0, a1), a1, &v); sa_store_u64(a2, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_header_pair_at => {
            try writer.writeAll(" return sa_cookie_header_pair_at(sa_glue_cptr(a0, a1), a1, a2); }\n");
        },
        .cookie_jar_new => {
            try writer.writeAll(" return sa_cookie_jar_new(); }\n");
        },
        .cookie_jar_free => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_jar_free(a0); }\n");
        },
        .cookie_jar_set_policy => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_jar_set_policy(a0, (uint32_t)a1); }\n");
        },
        .cookie_jar_policy => {
            try writer.writeAll(" { uint32_t v = 0; int32_t st = sa_cookie_jar_policy(a0, &v); sa_store_u32(a1, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_jar_store => {
            try writer.writeAll(" { uint32_t r = 0; int32_t st = sa_cookie_jar_store(a0, sa_glue_cptr(a1, a2), a2, sa_glue_cptr(a3, a4), a4, (sa_i64)a5, &r); sa_store_u32(a6, (sa_u64)r); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_jar_header => {
            try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_jar_header(a0, sa_glue_cptr(a1, a2), a2, (sa_i64)a3, &hp, &hn); sa_glue_out_str(a4, a5, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_jar_count => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_cookie_jar_count(a0, &v); sa_store_u64(a1, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_jar_at => {
            try writer.writeAll(" return sa_cookie_jar_at(a0, a1); }\n");
        },
        .cookie_jar_clear => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_jar_clear(a0); }\n");
        },
        .cookie_jar_evict_expired => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_cookie_jar_evict_expired(a0, (sa_i64)a1, &v); sa_store_u64(a2, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_jar_save => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_jar_save(a0, sa_glue_cptr(a1, a2), a2); }\n");
        },
        .cookie_jar_load => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_cookie_jar_load(a0, sa_glue_cptr(a1, a2), a2, &v); sa_store_u64(a3, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_jar_request_header => {
            try writer.writeAll(" { const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_cookie_jar_request_header(a0, sa_glue_cptr(a1, a2), a2, &hp, &hn); sa_glue_out_str(a3, a4, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
        },
        .cookie_jar_store_response => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_cookie_jar_store_response(a0, sa_glue_cptr(a1, a2), a2, sa_glue_cptr(a3, a4), a4); }\n");
        },
        .tlscfg_new => {
            // Direct link: the real config registry in libsa_std.a;
            // the handle value passes through, only the out slot is
            // translated into guest memory.
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_tls_client_config_new(&v); sa_store_u64(a0, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .tlscfg_free => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_free(a0); }\n");
        },
        .tlscfg_set_server_name => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_set_server_name(a0, sa_glue_cptr(a1, a2), a2); }\n");
        },
        .tlscfg_add_ca_file => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_add_ca_file(a0, sa_glue_cptr(a1, a2), a2); }\n");
        },
        .tlscfg_add_ca_memory => {
            // The PEM validation is OpenSSL's, inside libsa_std.a:
            // malformed PEM fails with -22 exactly as natively.
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_add_ca_memory(a0, sa_glue_cptr(a1, a2), a2); }\n");
        },
        .tlscfg_set_insecure => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_set_insecure_no_verification(a0, (uint32_t)a1); }\n");
        },
        .tlscfg_set_verify_self_signed => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_config_set_verify_self_signed(a0, (uint32_t)a1); }\n");
        },
        .tls_peer_cert_json => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_tls_client_peer_cert_json(a0, &v); sa_store_u64(a1, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .tls_shaped_supported => {
            try writer.writeAll(" { uint32_t v = 0; int32_t st = sa_std_tls_shaped_supported(&v); sa_store_u32(a0, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .tls_shaped_connect => {
            // Pre-dial profile validation happens inside libsa_std.a
            // (a malformed profile is -22 before any socket is opened),
            // so forwarding preserves the no-network test contract.
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_tls_shaped_connect(sa_glue_cptr(a0, a1), a1, (uint32_t)a2, sa_glue_cptr(a3, a4), a4, &v); sa_store_u64(a5, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .tls_cbuf_data => {
            // The native accessor returns a host pointer into the
            // buffer's bytes; the guest form copies the bytes into a
            // fresh guest allocation and returns its address (the
            // copy is never invalidated, unlike the native borrow).
            try writer.writeAll(" { uint64_t n = sa_std_tls_client_buffer_len(a0); const uint8_t *hp = sa_std_tls_client_buffer_data(a0); if (hp == 0) return 0; { sa_u64 g = sa_alloc(n == 0 ? 1 : n); uint32_t d = sa_checked_addr(g, (size_t)(n == 0 ? 1 : n)); if (n != 0) memcpy(&sa_mem[d], hp, (size_t)n); return g; } } }\n");
        },
        .tls_cbuf_len => {
            try writer.writeAll(" return sa_std_tls_client_buffer_len(a0); }\n");
        },
        .tls_cbuf_free => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_tls_client_buffer_free(a0); }\n");
        },
        .na_family => {
            try writer.writeAll(" return (sa_u64)sa_net_addr_family(a0); }\n");
        },
        .na_free => {
            // Fallible extern: the SA-level value is the status half
            // of the fallible pair (0 = SA_STD_OK on success).
            try writer.writeAll(" { sa_std_fallible_i32 r = sa_net_addr_free(a0); return (sa_u64)(sa_i64)r.status; } }\n");
        },
        .na_port => {
            try writer.writeAll(" return (sa_u64)sa_net_addr_port(a0); }\n");
        },
        .na_format => {
            try writer.writeAll(" { uint64_t n = 0; int32_t st = sa_std_net_addr_format(a0, sa_glue_mptr(a1, a2), a2, &n); sa_store_u64(a3, n); return (sa_u64)(sa_i64)st; } }\n");
        },
        .sk_get => {
            // Direct link: the real getsockopt syscall wrapper in
            // libsa_std.a runs against the real socket behind the
            // handle; only the out span is guest memory.
            try writer.writeAll(" { uint64_t n = 0; int32_t st = sa_std_net_socket_getsockopt(a0, (int32_t)a1, (uint32_t)a2, sa_glue_mptr(a3, a4), a4, &n); sa_store_u64(a5, n); return (sa_u64)(sa_i64)st; } }\n");
        },
        .sk_get_int => {
            try writer.writeAll(" { int32_t v = 0; int32_t st = sa_std_net_socket_getsockopt_int(a0, (int32_t)a1, (uint32_t)a2, &v); sa_store_u32(a3, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .sk_set => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_net_socket_setsockopt(a0, (int32_t)a1, (uint32_t)a2, sa_glue_cptr(a3, a4), a4); }\n");
        },
        .sk_set_int => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_net_socket_setsockopt_int(a0, (int32_t)a1, (uint32_t)a2, (int32_t)a3); }\n");
        },
        .na_to_first => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_net_to_socket_addr_first(sa_glue_cptr(a0, a1), a1, (uint32_t)a2, &v); sa_store_u64(a3, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .udp_bind_h => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_net_udp_bind(sa_glue_cptr(a0, a1), a1, (uint32_t)a2, &v); sa_store_u64(a3, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .udp_broadcast_h => {
            try writer.writeAll(" { int32_t v = 0; int32_t st = sa_std_net_udp_broadcast(a0, &v); sa_store_u32(a1, (sa_u64)(uint32_t)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .udp_connect_addr_h => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_net_udp_connect_addr(a0, a1); }\n");
        },
        .udp_local_addr_h => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_net_udp_local_addr(a0, &v); sa_store_u64(a1, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .udp_recv_msg_h => {
            try writer.writeAll(" { uint64_t rd = 0, saddr = 0, daddr = 0, ts = 0; uint32_t ix = 0, fl = 0; int32_t st = sa_std_net_udp_recv_msg(a0, sa_glue_mptr(a1, a2), a2, &rd, &saddr, &daddr, &ix, &ts, &fl); sa_store_u64(a3, rd); sa_store_u64(a4, saddr); sa_store_u64(a5, daddr); sa_store_u32(a6, (sa_u64)ix); sa_store_u64(a7, ts); sa_store_u32(a8, (sa_u64)fl); return (sa_u64)(sa_i64)st; } }\n");
        },
        .udp_recv_multi_h => {
            // The lens/addrs out arrays are staged in host scratch
            // and stored back element-wise (guest slots are byte
            // addressed; a direct uint64_t* cast would assume guest
            // alignment the SA allocator does not guarantee).
            try writer.writeAll(" { uint64_t cnt = 0; uint64_t *lens = (uint64_t *)malloc((a4 == 0 ? 1 : a4) * 8); uint64_t *addrs = (uint64_t *)malloc((a4 == 0 ? 1 : a4) * 8); if (lens == 0 || addrs == 0) { free(lens); free(addrs); return 5; } { int32_t st = sa_std_net_udp_recv_multi(a0, sa_glue_mptr(a1, a2), a2, a3, a4, &cnt, lens, addrs); sa_u64 i; for (i = 0; i < cnt; i++) { sa_store_u64(a6 + i * 8, lens[i]); sa_store_u64(a7 + i * 8, addrs[i]); } free(lens); free(addrs); sa_store_u64(a5, cnt); return (sa_u64)(sa_i64)st; } } }\n");
        },
        .udp_send_h => {
            try writer.writeAll(" { uint64_t w = 0; int32_t st = sa_std_net_udp_send(a0, sa_glue_cptr(a1, a2), a2, &w); sa_store_u64(a3, w); return (sa_u64)(sa_i64)st; } }\n");
        },
        .udp_set_read_timeout_h => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_std_net_udp_set_read_timeout(a0, a1); }\n");
        },
        .udp_ttl_h => {
            try writer.writeAll(" { uint32_t v = 0; int32_t st = sa_std_net_udp_ttl(a0, &v); sa_store_u32(a1, (sa_u64)v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .unix_pair_h => {
            try writer.writeAll(" { uint64_t l = 0, r = 0; int32_t st = sa_std_net_unix_datagram_pair(&l, &r); sa_store_u64(a0, l); sa_store_u64(a1, r); return (sa_u64)(sa_i64)st; } }\n");
        },
        .unix_peer_cred_h => {
            try writer.writeAll(" { int32_t pid = 0; uint32_t uid = 0, gid = 0; int32_t st = sa_std_net_unix_datagram_peer_cred(a0, &pid, &uid, &gid); sa_store_u32(a1, (sa_u64)(uint32_t)pid); sa_store_u32(a2, (sa_u64)uid); sa_store_u32(a3, (sa_u64)gid); return (sa_u64)(sa_i64)st; } }\n");
        },
        .unix_unbound_h => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_std_net_unix_datagram_unbound(&v); sa_store_u64(a0, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .proc_id => {
            try writer.writeAll(" return (sa_u64)sa_std_process_id(); }\n");
        },
        .proc_user_id => {
            try writer.writeAll(" return (sa_u64)sa_std_process_user_id(); }\n");
        },
        .net_unsupported8 => {
            try writer.writeAll(" { return 8; } }\n");
        },
        // Goroutine family (C1): real forwards into libsa_std.a.
        // Handles and scalars pass through as values; guest pointers
        // convert through the sa_glue adapters (payloads are the
        // runtime's opaque 16-byte slots). Spawn-shaped calls go
        // through the sa_glue_task_* trampolines emitted by the
        // need_task_entry block, because the archive runtime calls
        // host function pointers while guest functions are ftable
        // indices in this backend's uniform convention.
        .task_out0 => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = ");
            try writer.writeAll(name);
            try writer.writeAll("(&v); sa_store_u64(a0, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .task_handle_ret => {
            try writer.writeAll(" return (sa_u64)(sa_i64)");
            try writer.writeAll(name);
            try writer.writeAll("(a0); }\n");
        },
        .task_noargs_ret => {
            try writer.writeAll(" return (sa_u64)(sa_i64)");
            try writer.writeAll(name);
            try writer.writeAll("(); }\n");
        },
        .task_handle_out1 => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = ");
            try writer.writeAll(name);
            try writer.writeAll("(a0, &v); sa_store_u64(a1, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .task_chan_make => {
            try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_chan_make((uint32_t)a0, &v); sa_store_u64(a1, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .task_chan_send => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_chan_send(a0, sa_glue_mptr(a1, 16)); }\n");
        },
        .task_chan_recv => {
            try writer.writeAll(" { uint32_t cl = 0; int32_t st = sa_chan_recv(a0, sa_glue_mptr(a1, 16), &cl); sa_store_u32(a2, (sa_u64)cl); return (sa_u64)(sa_i64)st; } }\n");
        },
        .task_spawn => {
            try writer.writeAll(" { sa_glue_task_ctx *c = (sa_glue_task_ctx *)malloc(sizeof(sa_glue_task_ctx)); uint64_t v = 0; int32_t st; c->entry = a0; c->arg = a1; st = sa_task_spawn(sa_glue_task_entry, c, &v); if (st != 0) { free(c); } sa_store_u64(a2, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .task_spawn_supervised => {
            try writer.writeAll(" { sa_glue_task_ctx *c = (sa_glue_task_ctx *)malloc(sizeof(sa_glue_task_ctx)); uint64_t v = 0; int32_t st; c->entry = a0; c->arg = a1; c->sink = a2; c->sink_ctx = a3; st = sa_task_spawn_supervised(sa_glue_task_entry_keep, c, sa_glue_trap_sink, c, &v); if (st != 0) { free(c); } sa_store_u64(a4, v); return (sa_u64)(sa_i64)st; } }\n");
        },
        .task_trap_info => {
            try writer.writeAll(" { int32_t code = 0; const uint8_t *hp = 0; uint64_t hn = 0; int32_t st = sa_task_trap_info(a0, &code, &hp, &hn); sa_store_u32(a1, (sa_u64)(uint32_t)code); sa_glue_out_str(a2, a3, hp, hn); return (sa_u64)(sa_i64)st; } }\n");
        },
        .task_net_wait => {
            try writer.writeAll(" { uint32_t r = 0; int32_t st = sa_task_net_wait(a0, (uint32_t)a1, (sa_i64)a2, &r); sa_store_u32(a3, (sa_u64)r); return (sa_u64)(sa_i64)st; } }\n");
        },
        .task_try_lock => {
            try writer.writeAll(" { uint32_t r = 0; int32_t st = sa_sync_mutex_try_lock(a0, &r); sa_store_u32(a1, (sa_u64)r); return (sa_u64)(sa_i64)st; } }\n");
        },
        .task_wg_add => {
            try writer.writeAll(" return (sa_u64)(sa_i64)sa_sync_waitgroup_add(a0, (sa_i64)a1); }\n");
        },
        .task_once_do => {
            // The entry trampoline frees the context record when the
            // once actually runs; if the once was already done, the
            // entry never runs and the tiny record leaks (host glue).
            try writer.writeAll(" { sa_glue_task_ctx *c = (sa_glue_task_ctx *)malloc(sizeof(sa_glue_task_ctx)); int32_t st; c->entry = a1; c->arg = a2; st = sa_sync_once_do(a0, sa_glue_task_entry, c); return (sa_u64)(sa_i64)st; } }\n");
        },
        .task_select => {
            // Guest case/op/slot arrays are copied into host scratch;
            // the slot array is copied back (recv cases write into
            // it). Slot contents stay guest values end to end.
            try writer.writeAll(" { uint64_t n = a3; size_t cb = (size_t)n * 8; size_t ob = (size_t)n * 4; size_t sb = (size_t)n * 16; uint8_t *buf = (uint8_t *)malloc(cb + ob + sb == 0 ? 1 : cb + ob + sb); uint64_t *cases_h = (uint64_t *)(void *)buf; uint32_t *ops_h = (uint32_t *)(void *)(buf + cb); uint8_t *slots_h = buf + cb + ob; int64_t idx = -1; uint32_t cl = 0; int32_t st;");
            try writer.writeAll(" if (n != 0) { memcpy(cases_h, sa_glue_mptr(a0, cb), cb); memcpy(ops_h, sa_glue_mptr(a1, ob), ob); memcpy(slots_h, sa_glue_mptr(a2, sb), sb); }");
            try writer.writeAll(" st = sa_chan_select(cases_h, ops_h, slots_h, n, (uint32_t)a4, (sa_i64)a5, &idx, &cl);");
            try writer.writeAll(" if (n != 0) { memcpy(sa_glue_mptr(a2, sb), slots_h, sb); }");
            try writer.writeAll(" sa_store_u64(a6, (sa_u64)idx); sa_store_u32(a7, (sa_u64)cl); free(buf); return (sa_u64)(sa_i64)st; } }\n");
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
    need_time_clock: bool,
    need_sys_stat: bool,
    need_json: bool,
    need_stdlink: bool,
) !void {
    const mem_bytes: usize = @as(usize, c_opt.mem_pages) * 65536;
    try writer.print("/* Generated by `sa build-c` (c backend, MVP). DO NOT EDIT. */\n", .{});
    try writer.print("/* size_bits={d} mem_bytes={d} */\n", .{ size_bits, mem_bytes });
    // Feature-test macro must precede ALL system headers (glibc locks
    // strict-ANSI mode on first include otherwise, hiding clock_gettime).
    if (need_time_clock) {
        try writer.writeAll("#ifndef _POSIX_C_SOURCE\n#define _POSIX_C_SOURCE 200809L\n#endif\n");
    }
    try writer.writeAll(
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <stdlib.h>
        \\#include <errno.h>
        \\#include <math.h>
        \\#include <string.h>
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
    // Wall-clock needs <time.h> (the _POSIX_C_SOURCE define above
    // already precedes all headers); pure civil arithmetic needs nothing.
    if (need_time_clock) {
        try writer.writeAll(
            \\#include <time.h>
            \\
        );
    }
    if (need_sys_stat) {
        try writer.writeAll(
            \\#include <sys/stat.h>
            \\#include <unistd.h>
            \\
        );
    }
    // JSON DOM nodes (C-side fixed table; string payloads live in guest
    // memory). Kinds mirror SA_JSON_KIND_*: 0 null, 1 bool, 2 int,
    // 3 float, 5 string, 6 array, 7 object. Children link via
    // first/next; object members carry key in kptr/klen.
    if (need_json) {
        try writer.writeAll(
            \\#ifndef SA_JSON_MAX_NODES
            \\#define SA_JSON_MAX_NODES 256
            \\#endif
            \\#ifndef SA_JSON_MAX_DEPTH
            \\#define SA_JSON_MAX_DEPTH 64
            \\#endif
            \\typedef struct { sa_u64 h; unsigned kind; sa_u64 first, next; sa_u64 kptr, klen, vptr, vlen; sa_i64 ival; sa_u64 fbits; unsigned bval; } sa_json_node_t;
            \\static sa_json_node_t sa_json_nodes[SA_JSON_MAX_NODES];
            \\#ifndef SA_JSON_MAX_WRITERS
            \\#define SA_JSON_MAX_WRITERS 16
            \\#endif
            \\typedef struct { sa_u64 h, buf, len, cap; unsigned depth, done, started, complete, pending; unsigned char first[32], kinds[32]; } sa_json_writer_t;
            \\static sa_json_writer_t sa_json_writers[SA_JSON_MAX_WRITERS];
            \\
        );
    }
    if (need_time_clock) {
        try writer.writeAll(
            \\#include <time.h>
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
    for (kHelpersSorted) |h| {
        if (used.get(h.name) != null) {
            // Catalog bodies are hand-written C strings: fail loudly on
            // imbalance rather than emitting broken output.
            if (!cBracesBalanced(h.code)) return CEmitError.Failed;
            try writer.writeAll(h.code);
            try writer.writeAll("\n");
        }
    }
    // stdlink families (cookie / TLS client config / sockopt
    // passthrough): the bindings forward to the real libsa_std.a
    // entry points, so the preamble carries their prototypes
    // (mirroring src/runtime/sa_std.h) plus the guest<->host
    // adapters the wrappers use. A program that renders any of
    // these bindings must link libsa_std.a (the probe harness and
    // the c-matrix harness both do); programs that use none of
    // them never see this block.
    if (need_stdlink) {
        try writer.writeAll(
            \\typedef struct { int32_t status; int32_t value; } sa_std_fallible_i32;
            \\uint64_t sa_cookie_parse_set_cookie(const uint8_t *, uint64_t);
            \\int32_t sa_cookie_last_error(const uint8_t **, uint64_t *);
            \\int32_t sa_cookie_free(uint64_t);
            \\uint64_t sa_cookie_new(const uint8_t *, uint64_t, const uint8_t *, uint64_t);
            \\int32_t sa_cookie_name(uint64_t, const uint8_t **, uint64_t *);
            \\int32_t sa_cookie_value(uint64_t, const uint8_t **, uint64_t *);
            \\int32_t sa_cookie_domain(uint64_t, const uint8_t **, uint64_t *);
            \\int32_t sa_cookie_path(uint64_t, const uint8_t **, uint64_t *);
            \\int32_t sa_cookie_expires(uint64_t, int64_t *);
            \\int32_t sa_cookie_max_age(uint64_t, int64_t *);
            \\int32_t sa_cookie_flags(uint64_t, int32_t *, int32_t *, int32_t *);
            \\int32_t sa_cookie_same_site(uint64_t, uint32_t *);
            \\int32_t sa_cookie_is_host_only(uint64_t, int32_t *);
            \\int32_t sa_cookie_set_domain(uint64_t, const uint8_t *, uint64_t);
            \\int32_t sa_cookie_set_path(uint64_t, const uint8_t *, uint64_t);
            \\int32_t sa_cookie_set_expires(uint64_t, int64_t);
            \\int32_t sa_cookie_set_max_age(uint64_t, int64_t);
            \\int32_t sa_cookie_clear_expiry(uint64_t);
            \\int32_t sa_cookie_set_secure(uint64_t, int32_t);
            \\int32_t sa_cookie_set_http_only(uint64_t, int32_t);
            \\int32_t sa_cookie_set_partitioned(uint64_t, int32_t);
            \\int32_t sa_cookie_set_same_site(uint64_t, uint32_t);
            \\int32_t sa_cookie_serialize(uint64_t, const uint8_t **, uint64_t *);
            \\int32_t sa_cookie_serialize_pair(uint64_t, const uint8_t **, uint64_t *);
            \\int32_t sa_cookie_is_expired(uint64_t, int64_t, int32_t *);
            \\int32_t sa_cookie_domain_match(const uint8_t *, uint64_t, const uint8_t *, uint64_t, int32_t *);
            \\int32_t sa_cookie_path_match(const uint8_t *, uint64_t, const uint8_t *, uint64_t, int32_t *);
            \\int32_t sa_cookie_header_pair_count(const uint8_t *, uint64_t, uint64_t *);
            \\uint64_t sa_cookie_header_pair_at(const uint8_t *, uint64_t, uint64_t);
            \\uint64_t sa_cookie_jar_new(void);
            \\int32_t sa_cookie_jar_free(uint64_t);
            \\int32_t sa_cookie_jar_set_policy(uint64_t, uint32_t);
            \\int32_t sa_cookie_jar_policy(uint64_t, uint32_t *);
            \\int32_t sa_cookie_jar_store(uint64_t, const uint8_t *, uint64_t, const uint8_t *, uint64_t, int64_t, uint32_t *);
            \\int32_t sa_cookie_jar_header(uint64_t, const uint8_t *, uint64_t, int64_t, const uint8_t **, uint64_t *);
            \\int32_t sa_cookie_jar_count(uint64_t, uint64_t *);
            \\uint64_t sa_cookie_jar_at(uint64_t, uint64_t);
            \\int32_t sa_cookie_jar_clear(uint64_t);
            \\int32_t sa_cookie_jar_evict_expired(uint64_t, int64_t, uint64_t *);
            \\int32_t sa_cookie_jar_save(uint64_t, const uint8_t *, uint64_t);
            \\int32_t sa_cookie_jar_load(uint64_t, const uint8_t *, uint64_t, uint64_t *);
            \\int32_t sa_cookie_jar_request_header(uint64_t, const uint8_t *, uint64_t, const uint8_t **, uint64_t *);
            \\int32_t sa_cookie_jar_store_response(uint64_t, const uint8_t *, uint64_t, const uint8_t *, uint64_t);
            \\int32_t sa_std_tls_client_config_new(uint64_t *);
            \\int32_t sa_std_tls_client_config_free(uint64_t);
            \\int32_t sa_std_tls_client_config_set_server_name(uint64_t, const uint8_t *, uint64_t);
            \\int32_t sa_std_tls_client_config_add_ca_file(uint64_t, const uint8_t *, uint64_t);
            \\int32_t sa_std_tls_client_config_add_ca_memory(uint64_t, const uint8_t *, uint64_t);
            \\int32_t sa_std_tls_client_config_set_insecure_no_verification(uint64_t, uint32_t);
            \\int32_t sa_std_tls_client_config_set_verify_self_signed(uint64_t, uint32_t);
            \\int32_t sa_std_tls_client_peer_cert_json(uint64_t, uint64_t *);
            \\int32_t sa_std_tls_shaped_supported(uint32_t *);
            \\int32_t sa_std_tls_shaped_connect(const uint8_t *, uint64_t, uint32_t, const uint8_t *, uint64_t, uint64_t *);
            \\const uint8_t *sa_std_tls_client_buffer_data(uint64_t);
            \\uint64_t sa_std_tls_client_buffer_len(uint64_t);
            \\int32_t sa_std_tls_client_buffer_free(uint64_t);
            \\uint32_t sa_net_addr_family(uint64_t);
            \\sa_std_fallible_i32 sa_net_addr_free(uint64_t);
            \\uint32_t sa_net_addr_port(uint64_t);
            \\int32_t sa_std_net_addr_format(uint64_t, uint8_t *, uint64_t, uint64_t *);
            \\int32_t sa_std_net_socket_getsockopt(uint64_t, int32_t, uint32_t, uint8_t *, uint64_t, uint64_t *);
            \\int32_t sa_std_net_socket_getsockopt_int(uint64_t, int32_t, uint32_t, int32_t *);
            \\int32_t sa_std_net_socket_setsockopt(uint64_t, int32_t, uint32_t, const uint8_t *, uint64_t);
            \\int32_t sa_std_net_socket_setsockopt_int(uint64_t, int32_t, uint32_t, int32_t);
            \\int32_t sa_std_net_to_socket_addr_first(const uint8_t *, uint64_t, uint32_t, uint64_t *);
            \\int32_t sa_std_net_udp_bind(const uint8_t *, uint64_t, uint32_t, uint64_t *);
            \\int32_t sa_std_net_udp_broadcast(uint64_t, int32_t *);
            \\int32_t sa_std_net_udp_connect_addr(uint64_t, uint64_t);
            \\int32_t sa_std_net_udp_local_addr(uint64_t, uint64_t *);
            \\int32_t sa_std_net_udp_recv_msg(uint64_t, uint8_t *, uint64_t, uint64_t *, uint64_t *, uint64_t *, uint32_t *, uint64_t *, uint32_t *);
            \\int32_t sa_std_net_udp_recv_multi(uint64_t, uint8_t *, uint64_t, uint64_t, uint64_t, uint64_t *, uint64_t *, uint64_t *);
            \\int32_t sa_std_net_udp_send(uint64_t, const uint8_t *, uint64_t, uint64_t *);
            \\int32_t sa_std_net_udp_set_read_timeout(uint64_t, uint64_t);
            \\int32_t sa_std_net_udp_ttl(uint64_t, uint32_t *);
            \\int32_t sa_std_net_unix_datagram_pair(uint64_t *, uint64_t *);
            \\int32_t sa_std_net_unix_datagram_peer_cred(uint64_t, int32_t *, uint32_t *, uint32_t *);
            \\int32_t sa_std_net_unix_datagram_unbound(uint64_t *);
            \\uint32_t sa_std_process_id(void);
            \\uint32_t sa_std_process_user_id(void);
            \\int32_t sa_task_spawn(void (*)(void *), void *, uint64_t *);
            \\int32_t sa_task_spawn_supervised(void (*)(void *), void *, void (*)(uint64_t, int32_t, const uint8_t *, uint64_t, void *), void *, uint64_t *);
            \\int32_t sa_task_trap_info(uint64_t, int32_t *, const uint8_t **, uint64_t *);
            \\int32_t sa_task_monitor(uint64_t, uint64_t *);
            \\int32_t sa_task_yield(void);
            \\int32_t sa_task_sleep_ns(uint64_t);
            \\int32_t sa_task_sleep_ms(uint64_t);
            \\int32_t sa_task_join(uint64_t);
            \\int32_t sa_task_detach(uint64_t);
            \\int32_t sa_task_current(uint64_t *);
            \\int32_t sa_task_live_count(uint64_t *);
            \\int32_t sa_task_deadlock_guard_arm(void);
            \\int32_t sa_task_net_wait(uint64_t, uint32_t, int64_t, uint32_t *);
            \\int32_t sa_chan_make(uint32_t, uint64_t *);
            \\int32_t sa_chan_destroy(uint64_t);
            \\int32_t sa_chan_close(uint64_t);
            \\int32_t sa_chan_send(uint64_t, const void *);
            \\int32_t sa_chan_recv(uint64_t, void *, uint32_t *);
            \\int32_t sa_chan_len(uint64_t, uint64_t *);
            \\int32_t sa_chan_cap(uint64_t, uint64_t *);
            \\int32_t sa_chan_select(const uint64_t *, const uint32_t *, void *, uint64_t, uint32_t, int64_t, int64_t *, uint32_t *);
            \\int32_t sa_sync_mutex_new(uint64_t *);
            \\int32_t sa_sync_rwlock_new(uint64_t *);
            \\int32_t sa_sync_waitgroup_new(uint64_t *);
            \\int32_t sa_sync_once_new(uint64_t *);
            \\int32_t sa_sync_destroy(uint64_t);
            \\int32_t sa_sync_mutex_lock(uint64_t);
            \\int32_t sa_sync_mutex_try_lock(uint64_t, uint32_t *);
            \\int32_t sa_sync_mutex_unlock(uint64_t);
            \\int32_t sa_sync_rwlock_rlock(uint64_t);
            \\int32_t sa_sync_rwlock_runlock(uint64_t);
            \\int32_t sa_sync_rwlock_lock(uint64_t);
            \\int32_t sa_sync_rwlock_unlock(uint64_t);
            \\int32_t sa_sync_waitgroup_add(uint64_t, int64_t);
            \\int32_t sa_sync_waitgroup_done(uint64_t);
            \\int32_t sa_sync_waitgroup_wait(uint64_t);
            \\int32_t sa_sync_once_do(uint64_t, void (*)(void *), void *);
            \\static __attribute__((unused)) const uint8_t *sa_glue_cptr(sa_u64 p, sa_u64 n) { return (const uint8_t *)&sa_mem[sa_checked_addr(p, (size_t)n)]; }
            \\static __attribute__((unused)) uint8_t *sa_glue_mptr(sa_u64 p, sa_u64 n) { return (uint8_t *)&sa_mem[sa_checked_addr(p, (size_t)n)]; }
            \\static __attribute__((unused)) void sa_glue_out_str(sa_u64 op, sa_u64 ol, const uint8_t *hp, uint64_t n) { sa_u64 g = sa_alloc(n == 0 ? 1 : n); uint32_t d = sa_checked_addr(g, (size_t)(n == 0 ? 1 : n)); if (n != 0 && hp != 0) memcpy(&sa_mem[d], hp, (size_t)n); sa_store_u64(op, g); sa_store_u64(ol, n); }
            \\
        );
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
/// Pure, side-effect-free definitions eligible for dead-store elision.
/// Must stay in sync with emitLinearInstruction's elision arms: anything
/// here elides (comment only) when its dest is dead, so killing it never
/// drops traps or observable effects.
fn pureElidable(base: inst.Instruction) bool {
    switch (base.kind) {
        .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow, .ptr_add, .try_, .early_return => return true,
        .op => {
            const opcode = base.op_kind orelse return false;
            return !opCanTrap(opcode);
        },
        else => return false,
    }
}

/// True iff every instruction reading `slot` is already elided (i.e. the
/// slot is effectively unread). Used by the cascade-kill worklist.
fn allReadersElided(
    allocator: std.mem.Allocator,
    verified: anytype,
    fsig: sig.FunctionSig,
    use_global: bool,
    task: FuncTask,
    elide: *const std.AutoHashMap(usize, void),
    slot: u32,
) bool {
    var tmp_defs = std.array_list.Managed(u32).init(allocator);
    defer tmp_defs.deinit();
    var tmp_uses = std.array_list.Managed(u32).init(allocator);
    defer tmp_uses.deinit();
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        if (elide.get(i) != null) continue;
        tmp_defs.clearRetainingCapacity();
        tmp_uses.clearRetainingCapacity();
        collectDefUse(allocator, verified, fsig, use_global, verified.annotated[i].base, &tmp_defs, &tmp_uses) catch return false;
        for (tmp_uses.items) |sl| {
            if (sl == slot) return false;
        }
    }
    return true;
}

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
        if (!pureElidable(base)) continue;
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

/// Store-value coercion, mirroring interp.zig's store coercion: the
/// stored value is converted to the store's declared type at the
/// consumption point. SLA lowers `r as i64` to a raw_cast bit copy in
/// every backend and relies on this coercion — without it an f64
/// payload stored into an i64 slot lands as raw float bits (bitpack
/// quantize stored the f64 bits of 6.0 into a Result<i64> payload and
/// the value read back as a huge integer, not 6). Only float<->int
/// and f32<->f64 conversions are observable; same-domain stores and
/// pointer stores stay bit copies, as in the reference.
fn emitStoreValue(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, widths: *const WidthMap, op: inst.Operand, ty: sig.PrimType) !void {
    const code = widthOfOperand(widths, fsig, use_global, op);
    const src_float = if (code) |c| widthIsFloat(c) else false;
    const src_bits: u8 = if (code) |c| widthBits(c) else 64;
    const src_signed = if (code) |c| widthIsSigned(c) else false;
    const tgt_float = ty == .f32 or ty == .f64;
    if (src_float and !tgt_float and ty != .ptr and ty != .blob_handle and ty != .void) {
        // float -> int: convert at 64-bit width; narrower stores
        // truncate the converted value, matching the reference
        // (coerce to the target type, then store its low bytes).
        const sfx: []const u8 = switch (ty) {
            .i1, .i8, .i16, .i32, .i64 => "i64",
            else => "u64",
        };
        try writer.print("sa_cvt_fptosi_{s}(", .{sfx});
        if (src_bits == 32) try writer.writeAll("sa_f32_to_f64(");
        try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, op);
        if (src_bits == 32) try writer.writeAll(")");
        try writer.writeAll(")");
        return;
    }
    if (!src_float and tgt_float and code != null) {
        const opname: []const u8 = if (src_signed) "sitofp" else "uitofp";
        const sfx: []const u8 = if (ty == .f32) "f32" else "f64";
        try writer.print("sa_cvt_{s}_{s}(", .{ opname, sfx });
        try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, op);
        try writer.writeAll(")");
        return;
    }
    if (src_float and tgt_float and code != null and ((src_bits == 32) != (ty == .f32))) {
        try writer.writeAll(if (ty == .f32) "sa_cvt_fptrunc_f32(" else "sa_cvt_fpext_f64(");
        try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, op);
        try writer.writeAll(")");
        return;
    }
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, op);
}

/// Copy-or-cast emission for assign/raw_cast: a typed assignment
/// (`dst = src as T`, the form SLA's casts take after the flattener
/// drops the type annotation into the raw text) is a real conversion
/// in the reference's typed-register model — the value is converted
/// when materialized into the target-typed register (SLA's
/// `r as i64` over an f64 lowers to this form, and typed consumers
/// downstream read the converted integer; bitpack's quantize stored
/// the result into a Result payload and read back raw f64 bits
/// instead of 6 when this was a blind copy). This backend's
/// registers are untyped u64 slots, so the conversion is emitted
/// here; only same-domain casts stay bit copies.
fn emitCopyOrCast(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, widths: *WidthMap, dead: *const std.AutoHashMap(u32, void)) !void {
    const slot = try dstSlot(fsig, use_global, base.operands[0]);
    if (dead.get(slot) != null) {
        try writer.print("  /* dead store elided: {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
        return;
    }
    var cvt_op: ?inst.OpKind = null;
    var cvt_tgt: ?sig.PrimType = null;
    if (castTargetType(base)) |tgt| {
        if (widthOfOperand(widths, fsig, use_global, base.operands[1])) |code| {
            cvt_op = castOpcode(code, tgt);
            cvt_tgt = tgt;
        }
    }
    if (cvt_op) |opcode| {
        try writer.print("  r{d} = ", .{slot});
        try emitCvtExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, cvt_tgt.?, base.operands[1], widths);
        try writer.writeAll(";\n");
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
                try emitStoreValue(writer, symbols, fsig, use_global, const_addrs, fn_idx, widths, base.operands[2], ty);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  {s}(sa_ptr_add(", .{store_fn});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll("), ");
                try emitStoreValue(writer, symbols, fsig, use_global, const_addrs, fn_idx, widths, base.operands[2], ty);
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
        .assign, .raw_cast => {
            try emitCopyOrCast(writer, symbols, fsig, use_global, const_addrs, fn_idx, base, widths, dead);
        },
        .borrow, .assume_safe, .assume_borrow => {
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
    var reads_complete = true;
    var dead = computeDeadSlots(allocator, verified, fsig, use_global, task) catch blk: {
        reads_complete = false;
        break :blk std.AutoHashMap(u32, void).init(allocator);
    };
    defer dead.deinit();
    var elide = computeElideIdx(allocator, verified, fsig, use_global, task) catch std.AutoHashMap(usize, void).init(allocator);
    defer elide.deinit();
    var wdefs = std.array_list.Managed(u32).init(allocator);
    defer wdefs.deinit();
    var wuses = std.array_list.Managed(u32).init(allocator);
    defer wuses.deinit();
    // Cascade kills fixpoint: pure defs whose dests are dead AND pure
    // defs read only by skippable insts must both go. Two sets grow
    // monotonically (bounded by task size):
    //   dead  += slots with no reader outside `skipped`
    //   elide += pure insts whose defs are all dead (`skipped` = elide
    //            plus pure all-dead-def insts, mirroring emission which
    //            elides pure-dead via dead-checks independently)
    // Emission (elide pre-check, dead-based void/bare/elision) stays
    // consistent by construction. Zero additions = historical behavior.
    {
        var round: usize = 0;
        while (round < 1024) : (round += 1) {
            var progressed = false;
            // Phase A: slots with no reader outside skipped insts are dead.
            // (Skipped = elide map, which Phase B below also extends with
            // pure all-dead-def insts, so later rounds see them.)
            var si: usize = task.start_idx + 1;
            while (si < task.end_idx) : (si += 1) {
                wdefs.clearRetainingCapacity();
                wuses.clearRetainingCapacity();
                collectDefUse(allocator, verified, fsig, use_global, verified.annotated[si].base, &wdefs, &wuses) catch break;
                for (wdefs.items) |sl| {
                    if (dead.get(sl) != null) continue;
                    if (!allReadersElided(allocator, verified, fsig, use_global, task, &elide, sl)) continue;
                    dead.put(sl, {}) catch continue;
                    progressed = true;
                }
            }
            // Phase B: pure insts whose defs are all dead are skippable.
            var gi: usize = task.start_idx + 1;
            while (gi < task.end_idx) : (gi += 1) {
                if (elide.get(gi) != null) continue;
                const gbase = verified.annotated[gi].base;
                if (!pureElidable(gbase)) continue;
                wdefs.clearRetainingCapacity();
                wuses.clearRetainingCapacity();
                collectDefUse(allocator, verified, fsig, use_global, gbase, &wdefs, &wuses) catch break;
                if (wdefs.items.len == 0) continue;
                var all_dead = true;
                for (wdefs.items) |sl| {
                    if (dead.get(sl) == null) {
                        all_dead = false;
                        break;
                    }
                }
                if (!all_dead) continue;
                elide.put(gi, {}) catch continue;
                progressed = true;
            }
            if (!progressed) break;
        }
    }
    // Live-for-declaration set: slots read by a non-elided instruction.
    // (Effectful unread defs emit bare calls needing no declaration;
    // pure unread defs are elided above.) On any analysis failure the
    // flag drops and everything is declared (safe direction).
    var liveK = std.AutoHashMap(u32, void).init(allocator);
    defer liveK.deinit();
    {
        var gi: usize = task.start_idx + 1;
        while (gi < task.end_idx) : (gi += 1) {
            if (elide.get(gi) != null) continue;
            wdefs.clearRetainingCapacity();
            wuses.clearRetainingCapacity();
            collectDefUse(allocator, verified, fsig, use_global, verified.annotated[gi].base, &wdefs, &wuses) catch {
                reads_complete = false;
                break;
            };
            for (wuses.items) |sl| liveK.put(sl, {}) catch {
                reads_complete = false;
                break;
            };
        }
    }
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
                        .label => |v| v,
                        .symbol => |v| v,
                        else => continue,
                    };
                    label_refs.put(id, {}) catch {};
                },
                .br, .br_null => {
                    const t: u32 = switch (lb.operands[1]) {
                        .label => |v| v,
                        .symbol => |v| v,
                        else => continue,
                    };
                    const f: u32 = switch (lb.operands[3]) {
                        .label => |v| v,
                        .symbol => |v| v,
                        else => continue,
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
            // Declare a slot iff it is read by a non-elided instruction
            // (when liveness is known). Effectful unread defs emit bare
            // calls, pure unread defs are elided above: neither assigns,
            // so neither needs a declaration. On any analysis failure
            // declare everything (safe direction).
            if (reads_complete and liveK.get(slot32) == null) continue;
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
                    .label => |v| v,
                    .symbol => |v| v,
                    else => 0,
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
                    .label => |v| v,
                    .symbol => |v| v,
                    else => return CEmitError.InvalidOperand,
                };
                try writer.print("  goto SA_L_{d};\n", .{id});
            },
            .br => {
                const t: u32 = switch (base.operands[1]) {
                    .label => |v| v,
                    .symbol => |v| v,
                    else => return CEmitError.InvalidOperand,
                };
                const f: u32 = switch (base.operands[3]) {
                    .label => |v| v,
                    .symbol => |v| v,
                    else => return CEmitError.InvalidOperand,
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
                    .label => |v| v,
                    .symbol => |v| v,
                    else => return CEmitError.InvalidOperand,
                };
                const f: u32 = switch (base.operands[3]) {
                    .label => |v| v,
                    .symbol => |v| v,
                    else => return CEmitError.InvalidOperand,
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
    // Extern variadic batch: the C emitter's uniform-arity model has no
    // C-ABI variadic call/define mechanism (externs resolve through a
    // hand-written binding catalogue). Reject loudly instead of falling
    // back to a trap stub.
    for (verified.function_sigs) |fs| {
        if (fs.is_variadic) return error.UnsupportedVariadic;
    }
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
    var need_time_clock = false;
    var need_json = false;
    var need_stdlink = false;
    var need_task_entry = false;
    var need_sys_stat = false;
    var need_mem_direct = false;
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const efsig = verified.function_sigs[task.fsig_index];
        if (std.mem.eql(u8, sigNormName(efsig.name), "sa_print_bytes")) continue;
        if (!bodyCallsFunction(rest_text, efsig.name)) continue;
        var tmp: std.Io.Writer.Allocating = .init(allocator);
        defer tmp.deinit();
        if (!try writeExternBinding(&tmp.writer, efsig.name, uniform_arity, c_opt.gas)) continue;
        const rendered_norm = sigNormName(efsig.name);
        if (isStdlinkExtern(rendered_norm)) need_stdlink = true;
        if (bindingNeedsTaskEntry(rendered_norm)) need_task_entry = true;
        if (std.mem.startsWith(u8, rendered_norm, "sa_http_")) need_http = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_owned_") != null) need_owned = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_modstate_") != null) need_modstate = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_regex_") != null) need_regex = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "clock_gettime") != null) need_time_clock = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_json_") != null) need_json = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_mkdir_wrap") != null or std.mem.indexOf(u8, tmp.writer.buffered(), "sa_access_wrap") != null) need_sys_stat = true;
        // Bindings touching sa_mem directly (not via helpers) still need
        // the memory itself (e.g. the JSON parser's hot loops).
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_mem[") != null) need_mem_direct = true;
        const t = try tmp.toOwnedSlice();
        defer allocator.free(t);
        // Self-check every rendered binding: unbalanced output fails the
        // build loudly instead of emitting broken C (covers all present
        // and future bindings with no list to keep in sync).
        if (!cBodyBalanced(t)) return CEmitError.Failed;
        // Same for unused params (voids-mask precision).
        if (!cParamsCovered(t, uniform_arity)) return CEmitError.Failed;
        var bu = try collectUsedHelpers(allocator, t);
        defer bu.deinit();
        var bit = bu.iterator();
        while (bit.next()) |e| try used.put(e.key_ptr.*, {});
    }
    if (need_stdlink) {
        // The sa_glue_* adapters emitted by the preamble call
        // these catalog helpers directly; pull them and
        // their dependency closure into the used set.
        try used.put("sa_addr", {});
        try used.put("sa_checked_addr", {});
        try used.put("sa_align", {});
        try used.put("sa_alloc", {});
        try used.put("sa_store_u32", {});
        try used.put("sa_store_u64", {});
    }
    // Linear memory is needed for const bytes or any mem-touching helper.
    // (sa_brk only travels with the allocator; sa_mem stays out entirely
    // for pure-compute programs.)
    var need_mem = has_const_bytes or need_mem_direct;
    if (!need_mem) {
        // Helpers touching sa_mem directly (not just via other helpers).
        for (kRuntimeHelpers) |h| {
            if (used.get(h.name) != null and std.mem.indexOf(u8, h.code, "sa_mem") != null) {
                need_mem = true;
                break;
            }
        }
    }
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
    try writePreamble(writer, c_opt, size_bits, &used, need_mem, need_brk, need_http, need_owned, need_modstate, need_regex, need_time_clock, need_sys_stat, need_json, need_stdlink);
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
    // Goroutine glue trampolines (C1): the archive task runtime calls
    // host function pointers, while guest functions are ftable indices
    // here. The spawn / once_do bindings hand the runtime these
    // trampolines plus a small host-side record carrying the guest
    // entry index and the guest argument value. The plain entry
    // trampoline frees the record; the supervised path keeps it (the
    // trap sink may fire later and frees it there; a supervised task
    // that never traps leaks its one small record — host glue only).
    if (need_task_entry) {
        try writer.writeAll("typedef struct { sa_u64 entry; sa_u64 arg; sa_u64 sink; sa_u64 sink_ctx; } sa_glue_task_ctx;\n");
        try writer.writeAll("static void sa_glue_task_entry(void *p) { sa_glue_task_ctx *c = (sa_glue_task_ctx *)p; sa_u64 e = c->entry; sa_u64 a = c->arg; free(c); (void)sa_call_indirect(e, a");
        for (1..uniform_arity) |_| {
            try writer.writeAll(", 0");
        }
        try writer.writeAll("); }\n");
        try writer.writeAll("static void sa_glue_task_entry_keep(void *p) { sa_glue_task_ctx *c = (sa_glue_task_ctx *)p; (void)sa_call_indirect(c->entry, c->arg");
        for (1..uniform_arity) |_| {
            try writer.writeAll(", 0");
        }
        try writer.writeAll("); }\n");
        try writer.writeAll("static void sa_glue_trap_sink(sa_u64 h, int32_t code, const uint8_t *mp, sa_u64 ml, void *p) { sa_glue_task_ctx *c = (sa_glue_task_ctx *)p; sa_u64 g = 0; if (ml != 0 && mp != 0) { g = sa_alloc(ml); { uint32_t d = sa_checked_addr(g, (size_t)ml); memcpy(&sa_mem[d], mp, (size_t)ml); } } (void)sa_call_indirect(c->sink, h, (sa_u64)(sa_i64)code, g, ml, c->sink_ctx");
        if (uniform_arity > 5) {
            for (5..uniform_arity) |_| {
                try writer.writeAll(", 0");
            }
        }
        try writer.writeAll("); free(c); }\n");
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
    try writer.writeAll("int main(void) { extern void sa_install_sigpipe_ignore(void); sa_install_sigpipe_ignore(); sa_init_consts();\n");
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

test "c memPrimType untyped fallbacks match reference widths" {
    // Regression lock: the untyped fallback used to be u8, which
    // truncated untyped pointer takes (sa_vec_push's `take vec+Vec_ptr`)
    // to the pointer's low byte and corrupted every Vec grow copy on
    // the C backend. Reference widths are interp.zig's: take -> ptr,
    // load/store -> i64, atomics -> atomic_value_ty else i64.
    const take = inst.makeInstruction(.take, 0, 0, null, "");
    try std.testing.expectEqual(sig.PrimType.ptr, memPrimType(take));
    const load = inst.makeInstruction(.load, 0, 0, null, "");
    try std.testing.expectEqual(sig.PrimType.i64, memPrimType(load));
    const store = inst.makeInstruction(.store, 0, 0, null, "");
    try std.testing.expectEqual(sig.PrimType.i64, memPrimType(store));
    var atomic = inst.makeInstruction(.atomic_load, 0, 0, null, "");
    try std.testing.expectEqual(sig.PrimType.i64, memPrimType(atomic));
    atomic.atomic_value_ty = @backingInt(sig.PrimType.u8);
    try std.testing.expectEqual(sig.PrimType.u8, memPrimType(atomic));
    var typed = inst.makeInstruction(.load, 0, 0, null, "");
    typed.operands[3] = .{ .ty = @backingInt(sig.PrimType.u16) };
    try std.testing.expectEqual(sig.PrimType.u16, memPrimType(typed));
}

test "c stdlink bindings cover the cookie/tls/sockopt gap lists" {
    // Regression lock for the BQ-registered sa2c binding gaps: the
    // cookie family (the 17 names BQ hit plus the rest of the
    // http_cookie.sai surface), the TLS config face (10 names plus
    // the client-buffer accessors peer_cert_json is consumed
    // through) and the sockopt passthrough family (23 names). Every
    // name must render a real direct-link binding instead of falling
    // through to the trap stub.
    const names = [_][]const u8{
        "sa_cookie_parse_set_cookie",
        "sa_cookie_last_error",
        "sa_cookie_free",
        "sa_cookie_new",
        "sa_cookie_name",
        "sa_cookie_value",
        "sa_cookie_domain",
        "sa_cookie_path",
        "sa_cookie_expires",
        "sa_cookie_max_age",
        "sa_cookie_flags",
        "sa_cookie_same_site",
        "sa_cookie_is_host_only",
        "sa_cookie_set_domain",
        "sa_cookie_set_path",
        "sa_cookie_set_expires",
        "sa_cookie_set_max_age",
        "sa_cookie_clear_expiry",
        "sa_cookie_set_secure",
        "sa_cookie_set_http_only",
        "sa_cookie_set_partitioned",
        "sa_cookie_set_same_site",
        "sa_cookie_serialize",
        "sa_cookie_serialize_pair",
        "sa_cookie_is_expired",
        "sa_cookie_domain_match",
        "sa_cookie_path_match",
        "sa_cookie_header_pair_count",
        "sa_cookie_header_pair_at",
        "sa_cookie_jar_new",
        "sa_cookie_jar_free",
        "sa_cookie_jar_set_policy",
        "sa_cookie_jar_policy",
        "sa_cookie_jar_store",
        "sa_cookie_jar_header",
        "sa_cookie_jar_count",
        "sa_cookie_jar_at",
        "sa_cookie_jar_clear",
        "sa_cookie_jar_evict_expired",
        "sa_cookie_jar_save",
        "sa_cookie_jar_load",
        "sa_cookie_jar_request_header",
        "sa_cookie_jar_store_response",
        "sa_std_tls_client_config_new",
        "sa_std_tls_client_config_free",
        "sa_std_tls_client_config_set_server_name",
        "sa_std_tls_client_config_add_ca_file",
        "sa_std_tls_client_config_add_ca_memory",
        "sa_std_tls_client_config_set_insecure_no_verification",
        "sa_std_tls_client_config_set_verify_self_signed",
        "sa_std_tls_client_peer_cert_json",
        "sa_std_tls_shaped_supported",
        "sa_std_tls_shaped_connect",
        "sa_std_tls_client_buffer_data",
        "sa_std_tls_client_buffer_len",
        "sa_std_tls_client_buffer_free",
        "sa_net_addr_family",
        "sa_net_addr_free",
        "sa_net_addr_port",
        "sa_std_net_addr_format",
        "sa_std_net_socket_getsockopt",
        "sa_std_net_socket_getsockopt_int",
        "sa_std_net_socket_setsockopt",
        "sa_std_net_socket_setsockopt_int",
        "sa_std_net_to_socket_addr_first",
        "sa_std_net_udp_bind",
        "sa_std_net_udp_broadcast",
        "sa_std_net_udp_connect_addr",
        "sa_std_net_udp_local_addr",
        "sa_std_net_udp_recv_msg",
        "sa_std_net_udp_recv_multi",
        "sa_std_net_udp_send",
        "sa_std_net_udp_set_read_timeout",
        "sa_std_net_udp_ttl",
        "sa_std_net_unix_datagram_pair",
        "sa_std_net_unix_datagram_peer_cred",
        "sa_std_net_unix_datagram_unbound",
        "sa_std_process_id",
        "sa_std_process_user_id",
    };
    for (names) |n| {
        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try std.testing.expect(try writeExternBinding(&aw.writer, n, 12, false));
        try std.testing.expect(isStdlinkExtern(n));
    }
}

test "c stdlink bindings cover the goroutine task family (C1)" {
    // The whole sa_std/task.sai surface (36 names) must render a real
    // direct-link binding into libsa_std.a instead of falling through
    // to the trap stub, and every rendered body must stay balanced
    // with all uniform-arity parameters covered.
    const names = [_][]const u8{
        "sa_task_spawn",
        "sa_task_spawn_supervised",
        "sa_task_trap_info",
        "sa_task_monitor",
        "sa_task_yield",
        "sa_task_sleep_ns",
        "sa_task_sleep_ms",
        "sa_task_join",
        "sa_task_detach",
        "sa_task_current",
        "sa_task_live_count",
        "sa_task_deadlock_guard_arm",
        "sa_task_net_wait",
        "sa_chan_make",
        "sa_chan_destroy",
        "sa_chan_close",
        "sa_chan_send",
        "sa_chan_recv",
        "sa_chan_len",
        "sa_chan_cap",
        "sa_chan_select",
        "sa_sync_mutex_new",
        "sa_sync_rwlock_new",
        "sa_sync_waitgroup_new",
        "sa_sync_once_new",
        "sa_sync_destroy",
        "sa_sync_mutex_lock",
        "sa_sync_mutex_try_lock",
        "sa_sync_mutex_unlock",
        "sa_sync_rwlock_rlock",
        "sa_sync_rwlock_runlock",
        "sa_sync_rwlock_lock",
        "sa_sync_rwlock_unlock",
        "sa_sync_waitgroup_add",
        "sa_sync_waitgroup_done",
        "sa_sync_waitgroup_wait",
        "sa_sync_once_do",
    };
    for (names) |n| {
        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try std.testing.expect(try writeExternBinding(&aw.writer, n, 12, false));
        try std.testing.expect(isStdlinkExtern(n));
        try std.testing.expect(cBodyBalanced(aw.writer.buffered()));
        try std.testing.expect(cParamsCovered(aw.writer.buffered(), 12));
    }
}

/// True iff every param a0..aN in a rendered binding body occurs at
/// least twice (declaration plus a (void) cast or real use), so no
/// -Wunused-parameter can fire. Enforces voids-mask precision forever.
fn cParamsCovered(t: []const u8, uniform_arity: usize) bool {
    if (uniform_arity == 0) return true;
    var i: usize = 0;
    while (i < uniform_arity) : (i += 1) {
        var nbuf: [32]u8 = undefined;
        const needle = std.fmt.bufPrint(&nbuf, "a{d}", .{i}) catch return false;
        var count: usize = 0;
        var pos: usize = 0;
        while (pos + needle.len <= t.len) {
            if (std.mem.startsWith(u8, t[pos..], needle)) {
                const before_ok = pos == 0 or !(std.ascii.isAlphanumeric(t[pos - 1]) or t[pos - 1] == '_');
                const after = pos + needle.len;
                const after_ok = after >= t.len or !(std.ascii.isAlphanumeric(t[after]) or t[after] == '_');
                if (before_ok and after_ok) count += 1;
            }
            pos += 1;
        }
        if (count < 2) return false;
    }
    return true;
}

/// True iff t is a brace-balanced function body ending with "}\n",
/// ignoring braces inside strings/chars. Used to self-check every
/// rendered extern binding (an unclosed body would swallow following
/// definitions; fail the build loudly instead of emitting broken C).
/// NOTE: emit_c unit tests are not wired into any test binary, so this
/// runtime check (not a test block) is the enforced guard.
fn cBodyBalanced(t: []const u8) bool {
    if (!std.mem.endsWith(u8, t, "}\n")) return false;
    return cBracesBalanced(t);
}

/// Brace balance ignoring string/char literals. Used for catalog helper
/// bodies (which the preamble writes with its own trailing newline).
fn cBracesBalanced(t: []const u8) bool {
    var depth: i32 = 0;
    var in_str = false;
    var in_chr = false;
    var esc = false;
    for (t) |c| {
        if (in_str) {
            if (esc) {
                esc = false;
            } else if (c == '\\') {
                esc = true;
            } else if (c == '"') {
                in_str = false;
            }
        } else if (in_chr) {
            if (esc) {
                esc = false;
            } else if (c == '\\') {
                esc = true;
            } else if (c == '\'') {
                in_chr = false;
            }
        } else if (c == '"') {
            in_str = true;
        } else if (c == '\'') {
            in_chr = true;
        } else if (c == '{') {
            depth += 1;
        } else if (c == '}') {
            depth -= 1;
            if (depth < 0) return false;
        }
    }
    return depth == 0;
}
