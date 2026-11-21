const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const FuncTask = @import("types.zig").FuncTask;
const WidthMap = @import("types.zig").WidthMap;
const castOpcode = @import("operands.zig").castOpcode;
const castTargetType = @import("operands.zig").castTargetType;
const dstSlot = @import("operands.zig").dstSlot;
const emitCvtExpr = @import("operands.zig").emitCvtExpr;
const emitLinearInstruction = @import("linear.zig").emitLinearInstruction;
const packWidth = @import("widths.zig").packWidth;
const regSlot = @import("ident.zig").regSlot;
const resolveTextToC = @import("values.zig").resolveTextToC;
const resolveValueToC = @import("values.zig").resolveValueToC;
const sigNormName = @import("ident.zig").sigNormName;
const widthBits = @import("widths.zig").widthBits;
const widthIsFloat = @import("widths.zig").widthIsFloat;
const widthIsSigned = @import("widths.zig").widthIsSigned;
const widthOfOperand = @import("widths.zig").widthOfOperand;
const CEmitError = @import("../emit_c.zig").CEmitError;

/// Best-effort slot resolution for liveness: reg/symbol/text operands that
/// denote a local slot. Returns null for immediates, labels, funcs, consts.
///
/// Name-based operands (.symbol/.text) that resolve to a const decl are NOT
/// register reads: the emitter prefers the const immediate
/// (`resolveTextToC` checks `const_addrs` before registers), so counting
/// them as reads would keep dead `rN` declarations alive.
pub fn readSlotOf(fsig: sig.FunctionSig, use_global: bool, verified: anytype, op: inst.Operand) ?u32 {
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

pub fn isConstName(verified: anytype, name: []const u8) bool {
    for (verified.const_decls) |decl| {
        if (std.mem.eql(u8, decl.name, name)) return true;
    }
    return false;
}

pub fn defSlotOf(fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) ?u32 {
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
pub fn collectDefUse(allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, use_global: bool, base: inst.Instruction, defs: *std.array_list.Managed(u32), uses: *std.array_list.Managed(u32)) !void {
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

pub fn computeDeadSlots(allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, use_global: bool, task: FuncTask) !std.AutoHashMap(u32, void) {
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
pub fn pureElidable(base: inst.Instruction) bool {
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
pub fn allReadersElided(
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

pub fn computeElideIdx(allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, use_global: bool, task: FuncTask) !std.AutoHashMap(usize, void) {
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

pub fn sigReturnWidth(sigmap: anytype, callee: []const u8) ?u32 {
    const key = sigNormName(callee);
    if (sigmap.get(key)) |ty| {
        if (ty == .void) return null;
        return packWidth(ty);
    }
    return null;
}

pub fn opCanTrap(opcode: inst.OpKind) bool {
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
pub fn emitStoreValue(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, widths: *const WidthMap, op: inst.Operand, ty: sig.PrimType) !void {
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
pub fn emitCopyOrCast(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, widths: *WidthMap, dead: *const std.AutoHashMap(u32, void)) !void {
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

