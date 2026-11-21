const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const CBaseSet = @import("types.zig").CBaseSet;
const emitOneFunction = @import("emit_fn.zig").emitOneFunction;
const regSlot = @import("ident.zig").regSlot;
const trackWidths = @import("widths.zig").trackWidths;

pub fn provCSlotOf(fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) ?u32 {
    return switch (op) {
        .reg => |r| regSlot(fsig, use_global, r) catch null,
        .symbol => |id| fsig.slotOf(id),
        else => null,
    };
}


/// Slot of a textual value (call args and `.store` keep values as
/// `.text`); mirrors emit_js's provTextSlot name resolution.
pub fn provCTextSlot(symbols: anytype, fsig: sig.FunctionSig, text: []const u8) ?u32 {
    var t = std.mem.trim(u8, text, " \t");
    if (t.len == 0) return null;
    if (t[0] == '&' or t[0] == '*' or t[0] == '^') t = std.mem.trim(u8, t[1..], " \t");
    if (std.mem.lastIndexOf(u8, t, " as ")) |idx| t = std.mem.trim(u8, t[0..idx], " \t\r");
    if (t.len == 0) return null;
    if (std.fmt.parseInt(i64, t, 10)) |_| return null else |_| {}
    if (std.fmt.parseFloat(f64, t)) |_| return null else |_| {}
    const id = symbols.findId(t) orelse return null;
    return fsig.slotOf(id);
}

pub fn provCKillOp(bases: *CBaseSet, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) void {
    if (provCSlotOf(fsig, use_global, op)) |slot| _ = bases.remove(slot);
}

pub fn provCKillText(bases: *CBaseSet, symbols: anytype, fsig: sig.FunctionSig, text: []const u8) void {
    if (provCTextSlot(symbols, fsig, text)) |slot| _ = bases.remove(slot);
}


/// Advance the owned-base provenance set across one instruction.
/// Applied once per instruction in emitOneFunction's emission loop
/// (before dispatch), so the task-form path is covered identically.
pub fn provCUpdate(bases: *CBaseSet, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, base: inst.Instruction) !void {
    switch (base.kind) {
        .label => bases.clearRetainingCapacity(),
        .alloc, .stack_alloc => {
            if (provCSlotOf(fsig, use_global, base.operands[0])) |slot| try bases.put(slot, {});
        },
        .assign => {
            const dst = provCSlotOf(fsig, use_global, base.operands[0]) orelse return;
            const src_base = if (provCSlotOf(fsig, use_global, base.operands[1])) |src| bases.get(src) != null else false;
            if (src_base) {
                try bases.put(dst, {});
            } else {
                _ = bases.remove(dst);
            }
        },
        .move_ => provCKillOp(bases, fsig, use_global, base.operands[0]),
        .release => {}, // the emission case consumes the set itself
        .store, .atomic_store => {
            switch (base.operands[2]) {
                .reg, .symbol => provCKillOp(bases, fsig, use_global, base.operands[2]),
                .text, .native_text => |t| provCKillText(bases, symbols, fsig, t),
                else => {},
            }
        },
        .return_ => provCKillOp(bases, fsig, use_global, base.operands[0]),
        .call, .call_indirect => {
            if (call.parseInstructionCall(allocator, base, symbols)) |*parsed_const| {
                var parsed = parsed_const.*;
                defer parsed.deinit(allocator);
                if (parsed.dest) |dest| {
                    if (symbols.findId(dest)) |id| {
                        if (fsig.slotOf(id)) |slot| _ = bases.remove(slot);
                    }
                }
                for (parsed.args) |arg| {
                    if (arg.prefix == .move or arg.prefix == .by_value) {
                        provCKillText(bases, symbols, fsig, arg.text);
                    }
                }
            } else |_| {
                // Conservatively drop ALL owned-base knowledge on a call we
                // cannot parse: the call may have overwritten or released
                // any live base. Keeping a stale base would let a later
                // `!reg` emit sa_free on an already-freed/rebound slot
                // (double free). Mirrors trackWidths' clear-on-parse-failure.
                // The Referee rejects invalid call syntax before emission, so
                // this is a defence-in-depth path, not a normal occurrence.
                bases.clearRetainingCapacity();
            }
        },
        .load, .take, .ptr_add, .op, .borrow, .raw_cast, .assume_safe, .assume_borrow, .atomic_load, .atomic_rmw, .cmpxchg, .try_, .early_return, .va_start, .va_arg => {
            provCKillOp(bases, fsig, use_global, base.operands[0]);
        },
        else => {},
    }
}
