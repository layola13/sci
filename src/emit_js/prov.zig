const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const memPrimType = @import("ident.zig").memPrimType;
const offIsZero = @import("ident.zig").offIsZero;
const memLoadFn = @import("ident.zig").memLoadFn;
const JsEmitError = @import("types.zig").JsEmitError;
const FuncTask = @import("types.zig").FuncTask;
const RetBaseTable = @import("types.zig").RetBaseTable;
const BaseSet = @import("types.zig").BaseSet;
const dstSlot = @import("slots.zig").dstSlot;
const provSlotOf = @import("slots.zig").provSlotOf;
const provArgSlot = @import("slots.zig").provArgSlot;
const provCallDestBase = @import("slots.zig").provCallDestBase;
const resolveTextToJs = @import("instr.zig").resolveTextToJs;
const callDestSlot = @import("instr.zig").callDestSlot;

pub fn provKill(bases: *BaseSet, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) void {
    if (provSlotOf(fsig, use_global, op)) |slot| _ = bases.remove(slot);
}

/// Slot of a textual value (`store` keeps its value operand as `.text`;
/// see flattener.zig). Mirrors resolveTextToJs name resolution exactly
/// (global id -> slotOf, ignoring use_global) so escape kills apply to
/// textual values too; immediates never name slots.
pub fn provTextSlot(symbols: anytype, fsig: sig.FunctionSig, use_global: bool, text: []const u8) ?u32 {
    _ = use_global;
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

/// Forget the stored value's slot on `.store` (any operand shape).
pub fn provKillStoreValue(bases: *BaseSet, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) void {
    switch (op) {
        .reg, .symbol => provKill(bases, fsig, use_global, op),
        .text, .native_text => |t| {
            if (provTextSlot(symbols, fsig, use_global, t)) |slot| _ = bases.remove(slot);
        },
        else => {},
    }
}

pub fn provMark(bases: *BaseSet, fsig: sig.FunctionSig, use_global: bool, dst_op: inst.Operand, src_op: inst.Operand) JsEmitError!void {
    const dst = try dstSlot(fsig, use_global, dst_op);
    const src_base = if (provSlotOf(fsig, use_global, src_op)) |src| bases.get(src) != null else false;
    if (src_base) {
        bases.put(dst, {}) catch return JsEmitError.OutOfMemory;
    } else {
        _ = bases.remove(dst);
    }
}

/// Slot-promotion (register) analysis for the JS backend: finds `stack_alloc`
/// slots whose every use is a zero-offset plain `.load`/`.store` base.
/// Promoted slots become function-scope JS locals (`__sa_sp{slot}`), which
/// lets V8/JSC keep counters/accumulators in registers instead of bouncing
/// them through linear memory on every iteration. Soundness rules
/// (conservative; anything unclear disqualifies):
/// - the def must be the single `stack_alloc` in this function (params and
///   heap allocs never qualify); any reassignment disqualifies;
/// - any mention outside load/store base position disqualifies (borrows via
///   `&`, ptr_add/call/return/br operands, nonzero offsets, take/atomics,
///   cmpxchg, release), textual operands included;
/// - all accesses must share one int type so the store-side conversion is
///   exact (<=32-bit via `__sa_narrow`; 64-bit via `BigInt.asIntN`, mirroring
///   `__sa_store_i64` which both i64 and u64 use); floats/pointers never
///   qualify; init is an in-place load at the alloc site, so
///   even never-stored slots observe identical stale bytes.
pub const PromoInfo = struct {
    load_fn: []const u8,
    narrow_bits: u8,
    narrow_signed: bool,
};

pub const PromoMap = std.AutoHashMap(u32, PromoInfo);

pub fn collectPromotableSlots(allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, task: FuncTask, use_global: bool) !PromoMap {
    var promo = PromoMap.init(allocator);
    errdefer promo.deinit();
    var defined = std.AutoHashMap(u32, void).init(allocator);
    defer defined.deinit();
    var bad = std.AutoHashMap(u32, void).init(allocator);
    defer bad.deinit();
    const UseInfo = struct { ty: sig.PrimType, loads: u32, stores: u32 };
    var uses = std.AutoHashMap(u32, UseInfo).init(allocator);
    defer uses.deinit();
    for (fsig.param_ids) |gid| {
        if (fsig.slotOf(gid)) |s| try bad.put(s, {});
    }
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        const ops = base.operands;
        switch (base.kind) {
            .stack_alloc => {
                if (ops.len < 1) continue;
                if (promoMentionSlot(verified.symbols, fsig, use_global, ops[0])) |ds| {
                    if (defined.get(ds) != null) try bad.put(ds, {});
                    try defined.put(ds, {});
                }
                var k: usize = 1;
                while (k < ops.len) : (k += 1) {
                    if (promoMentionSlot(verified.symbols, fsig, use_global, ops[k])) |s| try bad.put(s, {});
                }
            },
            .load => {
                if (ops.len < 3) continue;
                if (promoMentionSlot(verified.symbols, fsig, use_global, ops[0])) |ds| try bad.put(ds, {});
                if (promoMentionSlot(verified.symbols, fsig, use_global, ops[2])) |os| try bad.put(os, {});
                const b = promoMentionSlot(verified.symbols, fsig, use_global, ops[1]) orelse continue;
                if (!offIsZero(ops[2])) { try bad.put(b, {}); continue; }
                const ty = memPrimType(base);
                const gop = try uses.getOrPut(b);
                if (!gop.found_existing) gop.value_ptr.* = .{ .ty = ty, .loads = 0, .stores = 0 };
                if (gop.value_ptr.ty != ty) { try bad.put(b, {}); continue; }
                gop.value_ptr.loads += 1;
            },
            .store => {
                if (ops.len < 3) continue;
                if (promoMentionSlot(verified.symbols, fsig, use_global, ops[1])) |os| try bad.put(os, {});
                if (promoMentionSlot(verified.symbols, fsig, use_global, ops[2])) |vs| try bad.put(vs, {});
                const b = promoMentionSlot(verified.symbols, fsig, use_global, ops[0]) orelse continue;
                if (!offIsZero(ops[1])) { try bad.put(b, {}); continue; }
                const ty = memPrimType(base);
                const gop = try uses.getOrPut(b);
                if (!gop.found_existing) gop.value_ptr.* = .{ .ty = ty, .loads = 0, .stores = 0 };
                if (gop.value_ptr.ty != ty) { try bad.put(b, {}); continue; }
                gop.value_ptr.stores += 1;
            },
            else => {
                for (ops) |op| {
                    if (promoMentionSlot(verified.symbols, fsig, use_global, op)) |s| try bad.put(s, {});
                    // Composite text operands (a call's argument list
                    // rendered as one string) name several slots, but
                    // promoMentionSlot resolves only the first. Scan every
                    // token as well: in raw_text-less (SAB-form) bodies
                    // this operand is the ONLY place an escaped slot is
                    // mentioned — the raw_text scan below sees nothing —
                    // so a slot passed by address to a callee that writes
                    // through it (extern out-params, e.g. a task handle
                    // written by sa_task_spawn) would otherwise stay
                    // promotable and keep serving its stale init value.
                    switch (op) {
                        .text, .native_text => |t| {
                            var oit = std.mem.tokenizeAny(u8, t, " \t\r\n,()[]{}:;\"'`@=");
                            while (oit.next()) |tok| {
                                if (provTextSlot(verified.symbols, fsig, use_global, tok)) |s| try bad.put(s, {});
                            }
                        },
                        else => {},
                    }
                }
                // Call instructions carry their arguments in raw_text,
                // not in operands, so the operand scan above never sees
                // them. Scan the text as well: a slot passed to a callee
                // that writes through its address (extern out-params)
                // must not be promoted, or later loads would serve the
                // stale promoted init value instead of memory.
                var tit = std.mem.tokenizeAny(u8, base.raw_text, " \t\r\n,()[]{}:;\"'`@=");
                while (tit.next()) |tok| {
                    if (provTextSlot(verified.symbols, fsig, use_global, tok)) |s| try bad.put(s, {});
                }
            },
        }
    }
    var uit = uses.iterator();
    while (uit.next()) |e| {
        const s = e.key_ptr.*;
        if (defined.get(s) == null) continue;
        if (bad.get(s) != null) continue;
        if (e.value_ptr.loads == 0 or e.value_ptr.stores == 0) continue;
        const nb = promoNarrowBits(e.value_ptr.ty) orelse continue;
        try promo.put(s, .{ .load_fn = memLoadFn(e.value_ptr.ty), .narrow_bits = nb.bits, .narrow_signed = nb.signed });
    }
    return promo;
}

pub const BlockRange = struct { start: usize, end: usize, label: ?u32 };

/// Forward must-analysis transfer for owned-base provenance: computes the set
/// of slots that hold `alloc` bases on EVERY path reaching each point.
/// Mirrors the interpreter (alloc marks; alias preserves; loads, arithmetic,
/// ptr_add, calls, cmpxchg results and stack_allocs kill).
pub fn provTransfer(
    allocator: std.mem.Allocator,
    symbols: anytype,
    fsig: sig.FunctionSig,
    use_global: bool,
    annotated: anytype,
    start: usize,
    end: usize,
    in_set: *const BaseSet,
    out_set: *BaseSet,
    retbase: *const RetBaseTable,
) JsEmitError!void {
    out_set.clearRetainingCapacity();
    var it = in_set.iterator();
    while (it.next()) |e| out_set.put(e.key_ptr.*, {}) catch return JsEmitError.OutOfMemory;
    var k: usize = start;
    while (k < end) : (k += 1) {
        const base = annotated[k].base;
        switch (base.kind) {
            .alloc => {
                if (provSlotOf(fsig, use_global, base.operands[0])) |slot| {
                    out_set.put(slot, {}) catch return JsEmitError.OutOfMemory;
                }
            },
            .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow => {
                const dst = provSlotOf(fsig, use_global, base.operands[0]);
                const src_base = if (provSlotOf(fsig, use_global, base.operands[1])) |s| out_set.get(s) != null else false;
                if (dst) |d| {
                    if (src_base) {
                        out_set.put(d, {}) catch return JsEmitError.OutOfMemory;
                    } else {
                        _ = out_set.remove(d);
                    }
                }
            },
            .op, .ptr_add, .load, .take, .atomic_load, .atomic_rmw, .try_, .early_return => {
                provKill(out_set, fsig, use_global, base.operands[0]);
            },
            .cmpxchg => {
                provKill(out_set, fsig, use_global, base.operands[0]);
                provKill(out_set, fsig, use_global, base.operands[1]);
            },
            .move_ => {
                // Ownership transfer: forget both sides (sound over-approximation).
                provKill(out_set, fsig, use_global, base.operands[0]);
                provKill(out_set, fsig, use_global, base.operands[1]);
            },
            .store, .atomic_store => {
                // Storing an owned base into memory escapes it (struct
                // fields, array slots, spills): the source register no
                // longer solely owns the block, so a later `release` of
                // the source must stay a no-op. Tsgosa emits this for
                // every array literal (`store s+0, p as ptr` ... `!p`);
                // freeing there corrupts the stored copy on free-list
                // reuse (native malloc survives by luck: LIFO + no
                // zeroing). Leaking instead is always observably safe.
                // The value operand is `.text`-shaped (see flattener),
                // so resolve it through the symbol table.
                provKillStoreValue(out_set, symbols, fsig, use_global, base.operands[2]);
            },
            .release, .stack_alloc => {
                provKill(out_set, fsig, use_global, base.operands[0]);
            },
            .call, .call_indirect => {
                var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                    out_set.clearRetainingCapacity();
                    continue;
                };
                defer parsed.deinit(allocator);
                if (parsed.dest) |_| {
                    if (callDestSlot(symbols, fsig, use_global, base, parsed) catch null) |slot| {
                        if (!parsed.is_indirect and provCallDestBase(out_set, symbols, fsig, parsed.callee, parsed.args, retbase)) {
                            out_set.put(slot, {}) catch return JsEmitError.OutOfMemory;
                        } else {
                            _ = out_set.remove(slot);
                        }
                    }
                }
                // Move-prefix arguments are consumed by the call. Bare
                // (by_value) arguments may be retained (mirrors emission).
                for (parsed.args) |arg| {
                    if (arg.prefix == .move or arg.prefix == .by_value) {
                        if (provArgSlot(symbols, fsig, arg.text)) |aslot| _ = out_set.remove(aslot);
                    }
                }
            },
            else => {},
        }
    }
}

pub fn provSetEq(a: *const BaseSet, b: *const BaseSet) bool {
    if (a.count() != b.count()) return false;
    var it = a.iterator();
    while (it.next()) |e| {
        if (b.get(e.key_ptr.*) == null) return false;
    }
    return true;
}

pub fn provLabelId(op: inst.Operand) ?u32 {
    return switch (op) {
        .label => |v| v,
        .symbol => |v| v,
        else => null,
    };
}

pub const ProvBody = struct {
    blocks: std.array_list.Managed(BlockRange),
    lid_to_blk: std.AutoHashMap(u32, usize),
    succs: std.array_list.Managed(std.array_list.Managed(usize)),
    in_sets: std.array_list.Managed(BaseSet),
    out_sets: std.array_list.Managed(BaseSet),

    pub fn deinit(self: *ProvBody) void {
        for (self.in_sets.items) |*s| s.deinit();
        for (self.out_sets.items) |*s| s.deinit();
        for (self.succs.items) |*s| s.deinit();
        self.blocks.deinit();
        self.lid_to_blk.deinit();
        self.succs.deinit();
        self.in_sets.deinit();
        self.out_sets.deinit();
    }
};

/// Build blocks/CFG and run the owned-base must-analysis fixpoint for one
/// function body. Shared by emission and return-base summary computation.
pub fn provSolveBody(
    allocator: std.mem.Allocator,
    verified: anytype,
    fsig: sig.FunctionSig,
    use_global: bool,
    task: FuncTask,
    retbase: *const RetBaseTable,
    seed: ?u32,
) JsEmitError!ProvBody {
    var prov = ProvBody{
        .blocks = std.array_list.Managed(BlockRange).init(allocator),
        .lid_to_blk = std.AutoHashMap(u32, usize).init(allocator),
        .succs = std.array_list.Managed(std.array_list.Managed(usize)).init(allocator),
        .in_sets = std.array_list.Managed(BaseSet).init(allocator),
        .out_sets = std.array_list.Managed(BaseSet).init(allocator),
    };
    errdefer prov.deinit();
    {
        var bs: usize = task.start_idx + 1;
        var blabel: ?u32 = null;
        var j: usize = bs;
        while (j < task.end_idx) : (j += 1) {
            const bk = verified.annotated[j].base;
            if (bk.kind == .label) {
                if (j > bs) {
                    prov.blocks.append(.{ .start = bs, .end = j, .label = blabel }) catch return JsEmitError.OutOfMemory;
                    blabel = provLabelId(bk.operands[1]);
                    bs = j + 1;
                } else if (blabel == null) {
                    blabel = provLabelId(bk.operands[1]);
                }
            } else if (bk.kind == .jmp or bk.kind == .br or bk.kind == .br_null or bk.kind == .return_) {
                prov.blocks.append(.{ .start = bs, .end = j + 1, .label = blabel }) catch return JsEmitError.OutOfMemory;
                blabel = null;
                bs = j + 1;
            }
        }
        if (bs < task.end_idx) prov.blocks.append(.{ .start = bs, .end = task.end_idx, .label = blabel }) catch return JsEmitError.OutOfMemory;
    }
    for (prov.blocks.items, 0..) |blk, bi| {
        if (blk.label) |lid| {
            if (prov.lid_to_blk.get(lid) == null) prov.lid_to_blk.put(lid, bi) catch return JsEmitError.OutOfMemory;
        }
    }
    for (prov.blocks.items, 0..) |blk, bi| {
        var s = std.array_list.Managed(usize).init(allocator);
        errdefer s.deinit();
        if (blk.end > blk.start) {
            const last = verified.annotated[blk.end - 1].base;
            switch (last.kind) {
                .jmp => {
                    if (provLabelId(last.operands[1])) |lid| {
                        if (prov.lid_to_blk.get(lid)) |t| s.append(t) catch return JsEmitError.OutOfMemory;
                    }
                },
                .br => {
                    if (provLabelId(last.operands[1])) |lid| {
                        if (prov.lid_to_blk.get(lid)) |t| s.append(t) catch return JsEmitError.OutOfMemory;
                    }
                    if (provLabelId(last.operands[3])) |lid| {
                        if (prov.lid_to_blk.get(lid)) |t| s.append(t) catch return JsEmitError.OutOfMemory;
                    }
                },
                .return_ => {},
                else => {
                    if (bi + 1 < prov.blocks.items.len) s.append(bi + 1) catch return JsEmitError.OutOfMemory;
                },
            }
        } else if (bi + 1 < prov.blocks.items.len) {
            s.append(bi + 1) catch return JsEmitError.OutOfMemory;
        }
        prov.succs.append(s) catch return JsEmitError.OutOfMemory;
    }
    for (prov.blocks.items) |_| {
        prov.in_sets.append(BaseSet.init(allocator)) catch return JsEmitError.OutOfMemory;
        prov.out_sets.append(BaseSet.init(allocator)) catch return JsEmitError.OutOfMemory;
    }
    var universe = BaseSet.init(allocator);
    defer universe.deinit();
    for (prov.blocks.items) |blk| {
        var k: usize = blk.start;
        while (k < blk.end) : (k += 1) {
            const base = verified.annotated[k].base;
            switch (base.kind) {
                .alloc, .stack_alloc, .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow, .op, .ptr_add, .load, .take, .atomic_load, .atomic_rmw, .try_, .early_return, .move_, .release => {
                    if (provSlotOf(fsig, use_global, base.operands[0])) |slot| {
                        universe.put(slot, {}) catch return JsEmitError.OutOfMemory;
                    }
                },
                .cmpxchg => {
                    if (provSlotOf(fsig, use_global, base.operands[0])) |slot| {
                        universe.put(slot, {}) catch return JsEmitError.OutOfMemory;
                    }
                    if (provSlotOf(fsig, use_global, base.operands[1])) |slot| {
                        universe.put(slot, {}) catch return JsEmitError.OutOfMemory;
                    }
                },
                .call, .call_indirect => {
                    var parsed = call.parseInstructionCall(allocator, base, verified.symbols) catch continue;
                    defer parsed.deinit(allocator);
                    if (parsed.dest) |_| {
                        if (callDestSlot(verified.symbols, fsig, use_global, base, parsed) catch null) |slot| {
                            universe.put(slot, {}) catch return JsEmitError.OutOfMemory;
                        }
                    }
                },
                else => {},
            }
        }
    }
    for (prov.in_sets.items, 0..) |*st, bi| {
        if (bi == 0) continue;
        var uit = universe.iterator();
        while (uit.next()) |e| st.put(e.key_ptr.*, {}) catch return JsEmitError.OutOfMemory;
    }
    var rounds: usize = 0;
    while (rounds < 100) : (rounds += 1) {
        var changed = false;
        for (prov.blocks.items, 0..) |blk, bi| {
            var tmp = BaseSet.init(allocator);
            defer tmp.deinit();
            var first_pred = true;
            for (prov.blocks.items, 0..) |_, pi| {
                var is_pred = false;
                for (prov.succs.items[pi].items) |t| {
                    if (t == bi) {
                        is_pred = true;
                        break;
                    }
                }
                if (!is_pred) continue;
                if (first_pred) {
                    var oit = prov.out_sets.items[pi].iterator();
                    while (oit.next()) |e| tmp.put(e.key_ptr.*, {}) catch return JsEmitError.OutOfMemory;
                    first_pred = false;
                } else {
                    var rm = std.array_list.Managed(u32).init(allocator);
                    defer rm.deinit();
                    var tit = tmp.iterator();
                    while (tit.next()) |e| {
                        if (prov.out_sets.items[pi].get(e.key_ptr.*) == null) rm.append(e.key_ptr.*) catch return JsEmitError.OutOfMemory;
                    }
                    for (rm.items) |slot| _ = tmp.remove(slot);
                }
            }
            if (first_pred) tmp.clearRetainingCapacity();
            if (bi == 0) {
                // Entry seed (for param-passthrough queries): a parameter
                // assumed to be a base on entry.
                if (seed) |s| tmp.put(s, {}) catch return JsEmitError.OutOfMemory;
            }
            if (!provSetEq(&prov.in_sets.items[bi], &tmp)) {
                prov.in_sets.items[bi].clearRetainingCapacity();
                var tit = tmp.iterator();
                while (tit.next()) |e| prov.in_sets.items[bi].put(e.key_ptr.*, {}) catch return JsEmitError.OutOfMemory;
                changed = true;
            }
            try provTransfer(allocator, verified.symbols, fsig, use_global, verified.annotated, blk.start, blk.end, &prov.in_sets.items[bi], &prov.out_sets.items[bi], retbase);
        }
        if (!changed) break;
    }
    return prov;
}

/// True iff every `return` in the body returns a slot proven to hold an
/// owned heap base (replaying the block transfer up to each return).
pub fn provAllReturnsProven(
    allocator: std.mem.Allocator,
    verified: anytype,
    fsig: sig.FunctionSig,
    use_global: bool,
    prov: *const ProvBody,
    retbase: *const RetBaseTable,
) JsEmitError!bool {
    var found = false;
    for (prov.blocks.items, 0..) |blk, bi| {
        var k: usize = blk.start;
        while (k < blk.end) : (k += 1) {
            const base = verified.annotated[k].base;
            if (base.kind != .return_) continue;
            found = true;
            var tmp = BaseSet.init(allocator);
            defer tmp.deinit();
            try provTransfer(allocator, verified.symbols, fsig, use_global, verified.annotated, blk.start, k, &prov.in_sets.items[bi], &tmp, retbase);
            const ok = if (provSlotOf(fsig, use_global, base.operands[0])) |slot| tmp.get(slot) != null else false;
            if (!ok) return false;
        }
    }
    return found;
}

/// Slot named by any operand shape (mirrors provKillStoreValue: textual
/// values resolve exactly like regs; immediates never name slots).
pub fn promoMentionSlot(symbols: anytype, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) ?u32 {
    switch (op) {
        .reg, .symbol => return provSlotOf(fsig, use_global, op),
        .text, .native_text => |t| {
            if (provTextSlot(symbols, fsig, use_global, t)) |s| return s;
            // Composite text operands (a call's argument list rendered
            // as one string) hide slot mentions from the whole-text
            // lookup. Scan identifier tokens so an escaped slot still
            // disqualifies promotion: a callee may write through the
            // slot's address (extern out-params do exactly that), and a
            // promoted slot would keep serving the stale init value.
            // Conservative: a false hit only loses the optimization.
            var it = std.mem.tokenizeAny(u8, t, " \t\r\n,()[]{}:;\"'`");
            while (it.next()) |tok| {
                if (provTextSlot(symbols, fsig, use_global, tok)) |s| return s;
            }
            return null;
        },
        else => return null,
    }
}

pub fn promoNarrowBits(ty: sig.PrimType) ?struct { bits: u8, signed: bool } {
    return switch (ty) {
        .u8 => .{ .bits = 8, .signed = false },
        .i8, .i1 => .{ .bits = 8, .signed = true },
        .u16 => .{ .bits = 16, .signed = false },
        .i16 => .{ .bits = 16, .signed = true },
        .u32 => .{ .bits = 32, .signed = false },
        .i32 => .{ .bits = 32, .signed = true },
        // 64-bit mirror __sa_store_i64 exactly (asIntN for both i64/u64).
        .i64, .u64 => .{ .bits = 64, .signed = true },
        else => null,
    };
}
