const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const types = @import("types.zig");
const shim_names = @import("shim_names.zig");

const BaseSet = types.BaseSet;
const RetBaseTable = types.RetBaseTable;
const JsEmitError = types.JsEmitError;
const isAllocatorShim = shim_names.isAllocatorShim;

pub fn regSlot(fsig: sig.FunctionSig, use_global: bool, slot_or_id: u32) !u32 {
    if (use_global) return fsig.slotOf(slot_or_id) orelse return JsEmitError.InvalidOperand;
    if (@as(usize, slot_or_id) < fsig.reg_ids.len) return slot_or_id;
    return fsig.slotOf(slot_or_id) orelse return JsEmitError.InvalidOperand;
}

pub fn dstSlot(fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) !u32 {
    return switch (op) {
        .reg => |r| try regSlot(fsig, use_global, r),
        .symbol => |id| try regSlot(fsig, use_global, id),
        else => return JsEmitError.InvalidOperand,
    };
}

pub fn provSlotOf(fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) ?u32 {
    return switch (op) {
        .reg => |r| regSlot(fsig, use_global, r) catch null,
        .symbol => |id| regSlot(fsig, use_global, id) catch null,
        else => null,
    };
}

/// Whether a call result slot is proven to hold a SOLELY-owned base:
/// allocator shims and alloc-class callees always qualify. Param-class
/// (pass-through) callees NEVER qualify: the result aliases the caller's
/// argument block, so freeing through the result would corrupt the still
/// live source (e.g. `t_8 = call @greet(t)` ... `!t_8` must stay a no-op
/// while `t` is used again; native preserves the block). Leaking instead
/// is always observably safe.
pub fn provCallDestBase(
    set: *const BaseSet,
    symbols: anytype,
    fsig: sig.FunctionSig,
    parsed_callee: []const u8,
    parsed_args: anytype,
    retbase: *const RetBaseTable,
) bool {
    _ = set;
    _ = symbols;
    _ = fsig;
    _ = parsed_args;
    if (isAllocatorShim(parsed_callee)) return true;
    const info = retbase.get(parsed_callee) orelse return false;
    return info == .alloc;
}

pub fn provArgSlot(symbols: anytype, fsig: sig.FunctionSig, arg_text: []const u8) ?u32 {
    const id = symbols.findId(arg_text) orelse return null;
    return fsig.slotOf(id);
}
