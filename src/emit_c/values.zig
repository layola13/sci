const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const fnIndexOf = @import("ident.zig").fnIndexOf;
const regSlot = @import("ident.zig").regSlot;
const tagToPrim = @import("ident.zig").tagToPrim;
const writeConstSym = @import("ident.zig").writeConstSym;

pub fn resolveTextToC(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, const_addrs: anytype, raw: []const u8) !void {
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

pub fn resolveValueToC(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, op: inst.Operand) !void {
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

pub fn memPrimType(base: inst.Instruction) sig.PrimType {
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

pub fn memLoadFn(ty: sig.PrimType) []const u8 {
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

pub fn memStoreFn(ty: sig.PrimType) []const u8 {
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

