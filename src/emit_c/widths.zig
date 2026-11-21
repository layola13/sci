const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const WidthFloatBit = @import("types.zig").WidthFloatBit;
const WidthMap = @import("types.zig").WidthMap;
const WidthSignBit = @import("types.zig").WidthSignBit;
const cAliasCallee = @import("operands.zig").cAliasCallee;
const cCombinedKind = @import("operands.zig").cCombinedKind;
const cOperandKind = @import("operands.zig").cOperandKind;
const castTargetType = @import("operands.zig").castTargetType;
const emitOpExpr = @import("operands.zig").emitOpExpr;
const floatOpDomain = @import("operands.zig").floatOpDomain;
const memPrimType = @import("values.zig").memPrimType;
const regSlot = @import("ident.zig").regSlot;
const tagToPrim = @import("ident.zig").tagToPrim;

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

pub fn widthRemoveSlot(widths: *WidthMap, slot: ?u32) void {
    if (slot) |s| _ = widths.remove(s);
}

pub fn widthOfOperand(widths: *const WidthMap, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) ?u32 {
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

pub fn trackWidths(widths: *WidthMap, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, base: inst.Instruction) void {
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
pub fn floatWidthIs32(widths: *const WidthMap, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) bool {
    const w = widthOfOperand(widths, fsig, use_global, op) orelse return false;
    return widthIsFloat(w) and widthBits(w) == 32;
}

