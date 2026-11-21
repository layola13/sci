const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const CalleeRetTable = @import("types.zig").CalleeRetTable;
const tagToPrim = @import("ident.zig").tagToPrim;
const memPrimType = @import("ident.zig").memPrimType;

/// Statically tracked source widths for int/float-domain slots, keyed by
/// raw register id. Populated by a single forward pass over each function
/// body (see trackWidths); cleared at every label since merges are
/// untracked. Absent entries fall back to runtime value inference
/// (BigInt = 64-bit, Number = 32-bit), which is today's behavior, so the
/// map can only sharpen conversions, never change covered paths.
/// Packing: low 31 bits = width, high bit = float domain.
pub const WidthMap = std.AutoHashMap(u32, u32);

/// Packing: low 31 bits = width, bit 30 = signed integer domain,
/// bit 31 = float domain.
pub const WidthSignBit: u32 = 0x40000000;
pub const WidthFloatBit: u32 = 0x80000000;

pub fn packWidth(prim: sig.PrimType) ?u32 {
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

pub fn widthIsFloat(code: u32) bool {
    return (code & WidthFloatBit) != 0;
}

pub fn widthIsSigned(code: u32) bool {
    return (code & WidthSignBit) != 0;
}

pub fn widthBits(code: u32) u8 {
    return @intCast(code & 0xff);
}

pub fn widthRemoveSlot(widths: *WidthMap, op: inst.Operand) void {
    if (op == .reg) _ = widths.remove(op.reg);
}

pub fn widthCopySlot(widths: *WidthMap, dst_op: inst.Operand, src_op: inst.Operand) void {
    if (dst_op != .reg) return;
    if (src_op == .reg) {
        if (widths.get(src_op.reg)) |w| {
            widths.put(dst_op.reg, w) catch return;
        } else {
            _ = widths.remove(dst_op.reg);
        }
        return;
    }
    switch (src_op) {
        .imm_int, .imm_i64 => widths.put(dst_op.reg, 64 | WidthSignBit) catch return,
        .imm_u64 => widths.put(dst_op.reg, 64) catch return,
        .imm_float => widths.put(dst_op.reg, WidthFloatBit | 64) catch return,
        else => _ = widths.remove(dst_op.reg),
    }
}

/// Operand domain for kind-driven compat aliases (div/rem/gt/lt/shr),
/// mirroring interp numKind: float wins, then signed, else unsigned.
/// Unknown preserves today's forced-signed lowering exactly.
pub const OpndKind = enum { float, signed, unsigned, unknown };

pub fn operandKind(op: inst.Operand, widths: *const WidthMap) OpndKind {
    switch (op) {
        .reg => |id| {
            const w = widths.get(id) orelse return .unknown;
            if (widthIsFloat(w)) return .float;
            return if (widthIsSigned(w)) .signed else .unsigned;
        },
        .imm_float => return .float,
        .imm_int, .imm_i64 => return .signed,
        .imm_u64 => return .unsigned,
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

pub fn combinedKind(a: OpndKind, b: OpndKind) OpndKind {
    if (a == .float or b == .float) return .float;
    if (a == .signed or b == .signed) return .signed;
    if (a == .unsigned and b == .unsigned) return .unsigned;
    return .unknown;
}

/// Width-directed unsigned-op selection (demos 337 vs 347): a negative
/// Number means mod-2^32 for <=32-bit regs but mod-2^64 for 64-bit regs,
/// and the runtime cannot tell them apart. So unsigned-forcing ops
/// (udiv/urem/ult/ule/ugt/uge/lshr) use the neg-checking GENERAL helper
/// unless every relevant operand is provably 32-bit-or-safe, in which
/// case the pure->>>0 FAST helper is bit-identical to the old behavior.
/// A 64-bit reg holding a small Number still takes the >>>0 path inside
/// GENERAL (values coincide); only actually-negative/big inputs pay BigInt.
pub fn u32SafeOperand(op: inst.Operand, widths: *const WidthMap) bool {
    switch (op) {
        .reg => |id| {
            const w = widths.get(id) orelse return false;
            if (widthIsFloat(w)) return false;
            return widthBits(w) <= 32;
        },
        .imm_int => |v| return v >= 0,
        .imm_i64 => |v| return v >= 0,
        .imm_u64 => return true,
        .imm_float => return false,
        .text, .native_text => |t| {
            var text = std.mem.trim(u8, t, " \t");
            if (text.len == 0) return false;
            if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
            if (std.mem.lastIndexOf(u8, text, " as ")) |idx| text = std.mem.trim(u8, text[0..idx], " \t\r");
            if (std.fmt.parseInt(u64, text, 10)) |_| return true else |_| {}
            return false;
        },
        else => return false,
    }
}

pub fn useFastU32(lhs: inst.Operand, rhs: inst.Operand, widths: *const WidthMap, checkBoth: bool) bool {
    if (!u32SafeOperand(lhs, widths)) return false;
    if (checkBoth and !u32SafeOperand(rhs, widths)) return false;
    return true;
}

/// Forward type-width transfer for one instruction. Mirrors native typing:
/// int-op results are 64-bit (interp always builds i64/u64), int compares
/// are i1, float ops are f64. Anything unrecognized drops knowledge so a
/// stale entry can never feed a wrong mask.
pub fn trackWidths(widths: *WidthMap, allocator: std.mem.Allocator, symbols: anytype, rettype: *const CalleeRetTable, base: inst.Instruction) void {
    switch (base.kind) {
        // Extern variadic batch: JS rejects variadic signatures at
        // entry; should a hand-written va instruction still arrive,
        // drop width knowledge for its destination (never guess).
        .va_start, .va_arg => {
            if (base.operands[0] != .reg) return;
            _ = widths.remove(base.operands[0].reg);
        },
        .va_end => {},
        .load, .take, .atomic_load => {
            if (base.operands[0] != .reg) return;
            if (packWidth(memPrimType(base))) |w| {
                widths.put(base.operands[0].reg, w) catch return;
            } else {
                _ = widths.remove(base.operands[0].reg);
            }
        },
        .op => {
            if (base.operands[0] != .reg) return;
            const dst = base.operands[0].reg;
            const opcode = base.op_kind orelse {
                _ = widths.remove(dst);
                return;
            };
            if (inst.isTypeConversionOpKind(opcode)) {
                // Self-referential conversion keeps no reliable width.
                if (base.operands[1] == .reg and base.operands[1].reg == dst) {
                    _ = widths.remove(dst);
                    return;
                }
                if (base.operands[2] != .ty) {
                    _ = widths.remove(dst);
                    return;
                }
                // Mirrors the emitter: bare sitofp/uitofp default to f64.
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
                .neg, .not, .fneg => widthCopySlot(widths, base.operands[0], base.operands[1]),
                .eq, .ne, .gt, .lt, .sgt, .slt, .sge, .sle, .ugt, .ult, .uge, .ule, .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => widths.put(dst, 1) catch return,
                .fadd, .fsub, .fmul, .fdiv => widths.put(dst, WidthFloatBit | 64) catch return,
                .sdiv, .srem, .ashr => widths.put(dst, 64 | WidthSignBit) catch return,
                .udiv, .urem, .lshr => widths.put(dst, 64) catch return,
                .add_v128, .sub_v128, .mul_v128, .shuffle_v128, .extract_lane, .insert_lane => _ = widths.remove(dst),
                .add, .sub, .mul, .div, .rem, .@"and", .@"or", .xor, .shl, .shr => {
                    // Kind-driven like interp numKind; unknown keeps today's
                    // forced-signed lowering exactly (no behavior change).
                    switch (combinedKind(operandKind(base.operands[1], widths), operandKind(base.operands[2], widths))) {
                        .float => _ = widths.remove(dst),
                        .signed => widths.put(dst, 64 | WidthSignBit) catch return,
                        .unsigned => widths.put(dst, 64) catch return,
                        .unknown => widths.put(dst, 64 | WidthSignBit) catch return,
                    }
                },
                else => widths.put(dst, 64 | WidthSignBit) catch return,
            }
        },
        .assign, .assume_safe, .assume_borrow => widthCopySlot(widths, base.operands[0], base.operands[1]),
        .borrow => {
            if (base.operands[0] == .reg) widths.put(base.operands[0].reg, 64) catch return;
        },
        .raw_cast => widthRemoveSlot(widths, base.operands[0]),
        .ptr_add, .alloc, .stack_alloc => {
            if (base.operands[0] == .reg) widths.put(base.operands[0].reg, 64) catch return;
        },
        .call, .call_indirect => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                widths.clearRetainingCapacity();
                return;
            };
            defer parsed.deinit(allocator);
            // Width keys live in the per-function operand id space:
            // the destination is operands[0] (parseInstructionCall's
            // has_dest). The parsed dest text resolves through the
            // program-global symbol table, a different id space — only
            // use it when the instruction carries no dest operand.
            const dest_id: ?u32 = if (base.operands[0] == .reg)
                base.operands[0].reg
            else if (parsed.dest) |dest|
                symbols.findId(dest)
            else
                null;
            if (dest_id) |id| {
                // A direct call to a declared callee produces its
                // declared return type: record that domain (this is
                // what keeps a direct bitcast of an extern f64 result
                // exact). Indirect calls and unresolved callees keep
                // the conservative removal (never guess a domain the
                // declaration does not give).
                var recorded = false;
                if (!parsed.is_indirect) {
                    if (rettype.get(parsed.callee)) |ret_ty| {
                        if (packWidth(ret_ty)) |w| {
                            widths.put(id, w) catch return;
                            recorded = true;
                        }
                    }
                }
                if (!recorded) _ = widths.remove(id);
            }
        },
        .try_, .early_return => widthRemoveSlot(widths, base.operands[0]),
        .cmpxchg => {
            widthRemoveSlot(widths, base.operands[0]);
            widthRemoveSlot(widths, base.operands[1]);
        },
        .atomic_rmw => widthRemoveSlot(widths, base.operands[0]),
        .move_ => {
            widthRemoveSlot(widths, base.operands[0]);
            widthRemoveSlot(widths, base.operands[1]);
        },
        .store, .atomic_store, .fence, .release, .jmp, .br, .br_null, .panic, .panic_msg, .return_, .native, .label, .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl, .transfer => {},
    }
}

