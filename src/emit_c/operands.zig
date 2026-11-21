const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const COpndKind = @import("types.zig").COpndKind;
const FDom = @import("types.zig").FDom;
const WidthMap = @import("types.zig").WidthMap;
const floatWidthIs32 = @import("widths.zig").floatWidthIs32;
const packWidth = @import("widths.zig").packWidth;
const regSlot = @import("ident.zig").regSlot;
const resolveValueToC = @import("values.zig").resolveValueToC;
const widthBits = @import("widths.zig").widthBits;
const widthIsFloat = @import("widths.zig").widthIsFloat;
const widthIsSigned = @import("widths.zig").widthIsSigned;
const widthOfOperand = @import("widths.zig").widthOfOperand;

pub fn cOperandKind(widths: *const WidthMap, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) COpndKind {
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

pub fn cCombinedKind(a: COpndKind, b: COpndKind) COpndKind {
    if (a == .float or b == .float) return .float;
    if (a == .signed or b == .signed) return .signed;
    if (a == .unsigned and b == .unsigned) return .unsigned;
    return .unknown;
}


/// C helper for kind-driven compat aliases (div/rem/gt/lt/shr), mirroring
/// JS aliasCallee. Unknown keeps forced-signed lowering (except shr, where
/// JS lowers unknown to lshr).
pub fn cAliasCallee(opcode: inst.OpKind, k: COpndKind) []const u8 {
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
pub fn emitNarrowLshr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, lhs: inst.Operand, rhs: inst.Operand, widths: *const WidthMap) !bool {
    const w = widthOfOperand(widths, fsig, use_global, lhs) orelse return false;
    if (widthIsFloat(w) or widthBits(w) >= 64) return false;
    try writer.print("sa_lshr(sa_srcmask(", .{});
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
    try writer.print(", {d}, 0), sa_band(", .{widthBits(w)});
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
    try writer.writeAll(", 31))");
    return true;
}

pub fn emitCvtExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, opcode: inst.OpKind, tgt: sig.PrimType, src_op: inst.Operand, widths: *const WidthMap) !void {
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
pub fn castTargetType(base: inst.Instruction) ?sig.PrimType {
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
pub fn castOpcode(src_code: u32, tgt: sig.PrimType) ?inst.OpKind {
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


pub fn floatOpDomain(widths: *const WidthMap, fsig: sig.FunctionSig, use_global: bool, lhs: inst.Operand, rhs: inst.Operand) FDom {
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
pub fn emitFNumOperand(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, widths: *const WidthMap, op: inst.Operand, kind: COpndKind, want: FDom) !void {
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

pub fn emitFloatOperand(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, op: inst.Operand, is32: bool, want32: bool) !void {
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

pub fn emitOpExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, opcode: inst.OpKind, lhs: inst.Operand, rhs: inst.Operand, widths: *const WidthMap) !void {
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

pub fn dstSlot(fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) !u32 {
    switch (op) {
        .reg => |r| return regSlot(fsig, use_global, r),
        .symbol => |id| return fsig.slotOf(id) orelse return CEmitError.InvalidOperand,
        .text, .native_text => return CEmitError.InvalidOperand,
        else => return CEmitError.InvalidOperand,
    }
}


/// Destination slot of a call instruction; mirrors emit_js.callDestSlot.
/// The destination register lives in operands[0], in the per-function
/// operand id space (slot indexes, or global symbol ids in global-reg
/// bodies — see regSlot). The parsed dest text resolves through the
/// program-global symbol table, a different id space: for raw_text-less
/// (SAB-form) calls it names an unrelated symbol, so resolving it either
/// fails (InvalidOperand) or silently assigns the wrong slot. Only fall
/// back to the parsed name when the instruction carries no dest operand.
pub fn callDestSlot(symbols: anytype, fsig: sig.FunctionSig, use_global: bool, base: inst.Instruction, parsed: call.ParsedCall) !?u32 {
    if (base.operands[0] == .reg) {
        return try dstSlot(fsig, use_global, base.operands[0]);
    }
    if (parsed.dest) |dest| {
        const id = symbols.findId(dest) orelse return null;
        return fsig.slotOf(id);
    }
    return null;
}

pub fn emitReturnStmt(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, operand: inst.Operand, indent: []const u8) !void {
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

