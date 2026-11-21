const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const jsFuncName = @import("ident.zig").jsFuncName;
const writeConstSlot = @import("ident.zig").writeConstSlot;
const WidthMap = @import("widths.zig").WidthMap;
const widthIsFloat = @import("widths.zig").widthIsFloat;
const widthBits = @import("widths.zig").widthBits;
const OpndKind = @import("widths.zig").OpndKind;
const operandKind = @import("widths.zig").operandKind;
const combinedKind = @import("widths.zig").combinedKind;
const useFastU32 = @import("widths.zig").useFastU32;
const JsEmitError = @import("types.zig").JsEmitError;
const RetBaseTable = @import("types.zig").RetBaseTable;
const BaseSet = @import("types.zig").BaseSet;
const regSlot = @import("slots.zig").regSlot;
const dstSlot = @import("slots.zig").dstSlot;
const provSlotOf = @import("slots.zig").provSlotOf;
const provCallDestBase = @import("slots.zig").provCallDestBase;
const provArgSlot = @import("slots.zig").provArgSlot;

/// Resolve raw call-arg text (`&name`, `10`, `3.5`, `"str"`) to a JS expr.
/// Mirrors emit_llvm_llvmc.textOperand: int/float literal, else symbol slot.
pub fn resolveTextToJs(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, const_addrs: anytype, raw: []const u8) !void {
    var text = std.mem.trim(u8, raw, " \t");
    if (text.len == 0) return JsEmitError.InvalidOperand;
    if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
    if (std.mem.lastIndexOf(u8, text, " as ")) |idx| {
        text = std.mem.trim(u8, text[0..idx], " \t\r");
    }
    if (text.len == 0) return JsEmitError.InvalidOperand;
    if (std.fmt.parseInt(i64, text, 10)) |v| {
        try writer.print("{d}", .{v});
        return;
    } else |_| {}
    // u64-range literals that overflow i64 still materialize exactly as
    // BigInt (plain float formatting would lose precision above 2^53).
    if (std.fmt.parseInt(u64, text, 10)) |v| {
        try writer.print("{d}n", .{v});
        return;
    } else |_| {}
    if (std.fmt.parseFloat(f64, text)) |v| {
        try writer.print("{d}", .{v});
        return;
    } else |_| {}
    // Static consts live at fixed linear-memory addresses (mirrors
    // emit_llvm_llvmc.textOperand checking const_names before symbols).
    if (const_addrs.get(text)) |_| {
        try writeConstSlot(writer, text);
        return;
    }
    if (symbols.findId(text)) |id| {
        if (fsig.slotOf(id)) |slot| {
            try writer.print("r{d}", .{slot});
            return;
        }
    }
    return JsEmitError.InvalidOperand;
}

/// Resolve any value operand to a JS expression.
pub fn resolveValueToJs(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, op: inst.Operand) !void {
    switch (op) {
        .reg => |r| {
            const slot = try regSlot(fsig, use_global, r);
            try writer.print("r{d}", .{slot});
        },
        .symbol, .label => |id| {
            // Mirror assignOperand: resolve id -> name -> text operand.
            const name = symbols.lookupName(id) orelse return JsEmitError.InvalidOperand;
            try resolveTextToJs(writer, symbols, fsig, const_addrs, name);
        },
        .func => |id| {
            // Function addresses box into the indirect-call table.
            const name = symbols.lookupName(id) orelse return JsEmitError.InvalidOperand;
            const fidx = fnIndexOf(fn_idx, name) orelse return JsEmitError.InvalidOperand;
            try writer.print("__sa_fnptr({d})", .{fidx});
        },
        .imm_int => |v| try writer.print("{d}", .{v}),
        // 64-bit immediates materialize as BigInt literals so the runtime
        // typeof-dispatch (number = 32-bit/float, bigint = 64-bit) stays
        // exact across the full u64 range. Plain digits would silently lose
        // precision above 2^53 and wrap 64-bit arithmetic at 32 bits.
        //
        // Exception: immediates whose magnitude already fits the 32-bit
        // Number domain are emitted as plain digits. SOUNDNESS INVARIANT
        // (interpreter computes all int ALU at 64 bits): every runtime int
        // helper carries full 64-bit precision — add/sub are double-exact to
        // 2^53 (no |0 truncation); mul/div/rem/shifts/bitwise/comparisons
        // dynamically promote out-of-32-bit-range Number operands to the
        // BigInt path; only provably-32-bit pairs take the fast path.
        // Narrowing happens solely at explicit narrow points (stores, loads,
        // cvt, comparisons coerce their inputs). 64-bit literals, extern
        // BigInt returns, and u64 loads stay BigInt end to end.
        // Negative i64 literals stay BigInt (their unsigned reading is
        // mod-2^64); unsigned-forcing ops (udiv/urem/ult/ule/ugt/uge/lshr)
        // select the neg-checking GENERAL helper unless every relevant
        // operand is statically <=32-bit (demos 337 vs 347), in which case
        // the pure->>>0 FAST helper is bit-identical to legacy behavior.
        .imm_i64 => |v| if (v >= 0 and v <= std.math.maxInt(i32))
            try writer.print("{d}", .{v})
        else
            try writer.print("{d}n", .{v}),
        .imm_u64 => |v| if (v <= std.math.maxInt(u32))
            try writer.print("{d}", .{v})
        else
            try writer.print("{d}n", .{v}),
        .imm_float => |v| try writer.print("{d}", .{v}),
        .text, .native_text => |t| try resolveTextToJs(writer, symbols, fsig, const_addrs, t),
        else => return JsEmitError.InvalidOperand,
    }
}

/// Runtime helper suffix for a conversion target type. blob_handle shares
/// the u64 helpers (both are 64-bit); v128/void targets are rejected loudly
/// (the verifier never produces them, so reaching here is a compiler bug).
pub fn cvtTargetSuffix(tgt: sig.PrimType) ?[]const u8 {
    return switch (tgt) {
        .i1 => "i1",
        .i8 => "i8",
        .i16 => "i16",
        .i32 => "i32",
        .i64 => "i64",
        .u8 => "u8",
        .u16 => "u16",
        .u32 => "u32",
        .u64, .blob_handle => "u64",
        .f32 => "f32",
        .f64 => "f64",
        .ptr => "ptr",
        else => null,
    };
}

/// Whether (opcode, target) is a verifier-accepted conversion shape.
/// Anything else fails the build loudly instead of emitting wrong code.
pub fn cvtShapeValid(opcode: inst.OpKind, tgt: sig.PrimType) bool {
    return switch (opcode) {
        // Mirror interp isIntLike: int<->int only (float targets are
        // verifier-rejected, so reaching them here is a compiler bug).
        .trunc, .zext, .sext => switch (tgt) {
            .i1, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .ptr, .blob_handle => true,
            else => false,
        },
        // bitcast allows any equal-width pair (verifier-enforced), so float
        // targets are legal here.
        .bitcast => switch (tgt) {
            .i1, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .ptr, .blob_handle, .f32, .f64 => true,
            else => false,
        },
        .sitofp, .uitofp => switch (tgt) {
            .f32, .f64 => true,
            else => false,
        },
        .fptosi => switch (tgt) {
            .i1, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .ptr, .blob_handle => true,
            else => false,
        },
        .fptrunc => tgt == .f32,
        .fpext => tgt == .f64,
        else => false,
    };
}

pub fn opNameForCvt(opcode: inst.OpKind) []const u8 {
    return switch (opcode) {
        .trunc => "trunc",
        .zext => "zext",
        .sext => "sext",
        .fptosi => "fptosi",
        .sitofp => "sitofp",
        .uitofp => "uitofp",
        .fptrunc => "fptrunc",
        .fpext => "fpext",
        .bitcast => "bitcast",
        else => "unknown",
    };
}

pub fn emitCvtExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, opcode: inst.OpKind, tgt: sig.PrimType, src_op: inst.Operand, widths: *const WidthMap) !void {
    if (!cvtShapeValid(opcode, tgt)) return JsEmitError.InvalidOperand;
    const sfx = cvtTargetSuffix(tgt) orelse return JsEmitError.InvalidOperand;
    // Load-typed source widths sharpen conversions whose runtime
    // value-inference default (32-bit for Numbers) would misread
    // sub-word sources (e.g. zext of an i8-loaded 0xFF).
    const src_w: ?u32 = if (src_op == .reg) widths.get(src_op.reg) else null;
    if ((opcode == .zext or opcode == .sext) and src_w != null and !widthIsFloat(src_w.?) and widthBits(src_w.?) < 64) {
        const w = widthBits(src_w.?);
        try writer.print("__sa_cvt_{s}_{s}(__sa_srcmask(", .{ opNameForCvt(opcode), sfx });
        try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.print(", {d}, {s}))", .{ w, if (opcode == .sext) "true" else "false" });
        return;
    }
    if (opcode == .bitcast and tgt == .f32 and src_w != null and widthIsFloat(src_w.?)) {
        try writer.writeAll("(+");
        try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.writeAll(")");
        return;
    }
    if (opcode == .bitcast and tgt == .f64 and src_w != null and !widthIsFloat(src_w.?)) {
        try writer.writeAll("__sa_cvt_bitcast_f64i(");
        try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.writeAll(")");
        return;
    }
    if (opcode == .bitcast and (tgt == .i32 or tgt == .u32) and src_w != null and widthIsFloat(src_w.?)) {
        if (tgt == .i32) {
            try writer.writeAll("__sa_cvt_bitcast_i32f(");
        } else {
            try writer.writeAll("__sa_cvt_bitcast_u32f(");
        }
        try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.writeAll(")");
        return;
    }
    if (opcode == .bitcast and (tgt == .i64 or tgt == .u64) and src_w != null and widthIsFloat(src_w.?)) {
        if (tgt == .i64) {
            try writer.writeAll("__sa_cvt_bitcast_i64b(");
        } else {
            try writer.writeAll("__sa_cvt_bitcast_u64b(");
        }
        try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.writeAll(")");
        return;
    }
    try writer.print("__sa_cvt_{s}_{s}(", .{ opNameForCvt(opcode), sfx });
    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
    try writer.writeAll(")");
}

/// Runtime callee for kind-driven compat aliases (div/rem/gt/lt/shr),
/// mirroring interp numKind. Unknown keeps today's forced-signed
/// lowering exactly, so only statically-known shapes change.
pub fn aliasCallee(opcode: inst.OpKind, k: OpndKind) []const u8 {
    return switch (opcode) {
        .div => switch (k) {
            .float => "__sa_fdiv",
            .unsigned => "__sa_udiv",
            else => "__sa_sdiv",
        },
        .rem => switch (k) {
            .unsigned => "__sa_urem",
            else => "__sa_srem",
        },
        .shr => switch (k) {
            .signed => "__sa_ashr",
            else => "__sa_lshr",
        },
        .gt => switch (k) {
            .float => "__sa_fgt",
            .unsigned => "__sa_ugt",
            else => "__sa_sgt",
        },
        .lt => switch (k) {
            .float => "__sa_flt",
            .unsigned => "__sa_ult",
            else => "__sa_slt",
        },
        else => unreachable,
    };
}

pub fn emitAliasOperands(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, lhs: inst.Operand, rhs: inst.Operand) !void {
    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
    try writer.writeAll(", ");
    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
    try writer.writeAll(")");
}

pub fn emitOpExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, opcode: inst.OpKind, lhs: inst.Operand, rhs: inst.Operand, widths: *const WidthMap) !void {
    switch (opcode) {
        .add => {
            try writer.writeAll("__sa_add(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .sub => {
            try writer.writeAll("__sa_sub(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .mul => {
            try writer.writeAll("__sa_mul(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .sdiv => {
            try writer.writeAll("__sa_sdiv(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .div => {
            try writer.writeAll(aliasCallee(.div, combinedKind(operandKind(lhs, widths), operandKind(rhs, widths))));
            try writer.writeAll("(");
            try emitAliasOperands(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs);
        },
        .udiv => {
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_udiv32(" else "__sa_udiv(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .srem => {
            try writer.writeAll("__sa_srem(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .rem => {
            try writer.writeAll(aliasCallee(.rem, combinedKind(operandKind(lhs, widths), operandKind(rhs, widths))));
            try writer.writeAll("(");
            try emitAliasOperands(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs);
        },
        .urem => {
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_urem32(" else "__sa_urem(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .@"and" => {
            try writer.writeAll("__sa_band(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .@"or" => {
            try writer.writeAll("__sa_bor(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .xor => {
            try writer.writeAll("__sa_bxor(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .shl => {
            try writer.writeAll("__sa_shl(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .lshr => {
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, false)) "__sa_lshr32(" else "__sa_lshr(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .shr => {
            try writer.writeAll(aliasCallee(.shr, combinedKind(operandKind(lhs, widths), operandKind(rhs, widths))));
            try writer.writeAll("(");
            try emitAliasOperands(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs);
        },
        .ashr => {
            try writer.writeAll("__sa_ashr(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .eq => {
            try writer.writeAll("__sa_eq(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .ne => {
            try writer.writeAll("__sa_ne(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .slt => {
            try writer.writeAll("__sa_slt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .lt => {
            try writer.writeAll(aliasCallee(.lt, combinedKind(operandKind(lhs, widths), operandKind(rhs, widths))));
            try writer.writeAll("(");
            try emitAliasOperands(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs);
        },
        .sle => {
            try writer.writeAll("__sa_sle(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .sgt => {
            try writer.writeAll("__sa_sgt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .gt => {
            try writer.writeAll(aliasCallee(.gt, combinedKind(operandKind(lhs, widths), operandKind(rhs, widths))));
            try writer.writeAll("(");
            try emitAliasOperands(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs);
        },
        .sge => {
            try writer.writeAll("__sa_sge(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .ult => {
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_ult32(" else "__sa_ult(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .ule => {
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_ule32(" else "__sa_ule(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .ugt => {
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_ugt32(" else "__sa_ugt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .uge => {
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_uge32(" else "__sa_uge(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fadd => {
            try writer.writeAll("__sa_fadd(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fsub => {
            try writer.writeAll("__sa_fsub(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fmul => {
            try writer.writeAll("__sa_fmul(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fdiv => {
            try writer.writeAll("__sa_fdiv(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_eq => {
            try writer.writeAll("__sa_feq(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_ne => {
            try writer.writeAll("__sa_fne(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_lt => {
            try writer.writeAll("__sa_flt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_le => {
            try writer.writeAll("__sa_fle(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_gt => {
            try writer.writeAll("__sa_fgt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_ge => {
            try writer.writeAll("__sa_fge(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .neg => {
            try writer.writeAll("__sa_neg(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(")");
        },
        .not => {
            try writer.writeAll("__sa_bnot(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(")");
        },
        .fneg => {
            try writer.writeAll("__sa_fneg(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(")");
        },
        else => {
            try writer.writeAll("__sa_trap(\"unsupported op\")");
        },
    }
}

pub fn emitCallInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, bases: *BaseSet, retbase: *const RetBaseTable) !void {
    _ = fn_idx;
    var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
        try writer.print("  __sa_trap(\"unsupported call: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
        return;
    };
    defer parsed.deinit(allocator);
    if (parsed.is_indirect) {
        try writer.print("  __sa_trap(\"unsupported call_indirect: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
        return;
    }
    if (parsed.dest) |_| {
        const slot = (try callDestSlot(symbols, fsig, use_global, base, parsed)) orelse return JsEmitError.InvalidOperand;
        // Fresh blocks from allocator shims and proven callees keep base
        // provenance; everything else is killed (unknown). Move-prefix
        // arguments are consumed.
        if (!parsed.is_indirect and provCallDestBase(bases, symbols, fsig, parsed.callee, parsed.args, retbase)) {
            bases.put(slot, {}) catch return JsEmitError.OutOfMemory;
        } else {
            _ = bases.remove(slot);
        }
        try writer.print("  r{d} = ", .{slot});
    } else {
        try writer.writeAll("  ");
    }
    // Move-prefix arguments are consumed. Bare (by_value) arguments
    // may be retained by the callee: forget those slots too (leak
    // beats use-after-free; mirrors the store-escape rule).
    // Borrow (&) / raw (*) args are only read through: kept.
    // Runs for dest-less calls too (push_word has no dest).
    for (parsed.args) |arg| {
        if (arg.prefix == .move or arg.prefix == .by_value) {
            if (provArgSlot(symbols, fsig, arg.text)) |aslot| _ = bases.remove(aslot);
        }
    }
    try jsFuncName(writer, parsed.callee);
    try writer.writeAll("(");
    for (parsed.args, 0..) |arg, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try resolveTextToJs(writer, symbols, fsig, const_addrs, arg.text);
    }
    try writer.writeAll(");\n");
}

/// Indirect calls resolve through the runtime function table.
/// Boxed callee values come from vtable loads or `&func` expressions;
/// results (including fallible {s,v} objects) pass through untouched.
pub fn emitCallIndirectInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, bases: *BaseSet, retbase: *const RetBaseTable) !void {
    _ = fn_idx;
    var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
        try writer.print("  __sa_trap(\"unsupported call_indirect: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
        return;
    };
    defer parsed.deinit(allocator);
    if (parsed.dest) |_| {
        const slot = (try callDestSlot(symbols, fsig, use_global, base, parsed)) orelse return JsEmitError.InvalidOperand;
        // Fresh blocks from allocator shims and proven callees keep base
        // provenance; everything else is killed (unknown). Move-prefix
        // arguments are consumed.
        if (!parsed.is_indirect and provCallDestBase(bases, symbols, fsig, parsed.callee, parsed.args, retbase)) {
            bases.put(slot, {}) catch return JsEmitError.OutOfMemory;
        } else {
            _ = bases.remove(slot);
        }
        try writer.print("  r{d} = ", .{slot});
    } else {
        try writer.writeAll("  ");
    }
    // Move-prefix arguments are consumed. Bare (by_value) arguments
    // may be retained by the callee: forget those slots too (leak
    // beats use-after-free; mirrors the store-escape rule).
    // Borrow (&) / raw (*) args are only read through: kept.
    // Runs for dest-less calls too.
    for (parsed.args) |arg| {
        if (arg.prefix == .move or arg.prefix == .by_value) {
            if (provArgSlot(symbols, fsig, arg.text)) |aslot| _ = bases.remove(aslot);
        }
    }
    try writer.writeAll("__sa_call_indirect(");
    try resolveTextToJs(writer, symbols, fsig, const_addrs, parsed.callee);
    for (parsed.args) |arg| {
        try writer.writeAll(", ");
        try resolveTextToJs(writer, symbols, fsig, const_addrs, arg.text);
    }
    try writer.writeAll(");\n");
}


/// Look up a function name in the indirect-call table, tolerating the
/// `@` prefix variance between symbol names and vtable slot spellings.
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

/// Destination slot of a call instruction. The destination register lives
/// in operands[0], in the per-function operand id space (slot indexes, or
/// global symbol ids in global-reg bodies — see regSlot). The parsed dest
/// text instead resolves through the program-global symbol table, a
/// different id space: for raw_text-less (SAB-form) calls
/// parseInstructionCall derives that text by looking the slot up as a
/// global id, which names an unrelated symbol — resolving it either fails
/// (InvalidOperand) or, worse, lands on a namesake local of the current
/// function and silently assigns the result to the wrong slot. Only fall
/// back to the parsed name when the instruction carries no dest operand
/// (the same rule trackWidths already follows).
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
