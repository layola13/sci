const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const CBaseSet = @import("types.zig").CBaseSet;
const WidthMap = @import("types.zig").WidthMap;
const cFuncName = @import("ident.zig").cFuncName;
const callDestSlot = @import("operands.zig").callDestSlot;
const dstSlot = @import("operands.zig").dstSlot;
const emitCopyOrCast = @import("dead_slots.zig").emitCopyOrCast;
const emitCvtExpr = @import("operands.zig").emitCvtExpr;
const emitOpExpr = @import("operands.zig").emitOpExpr;
const emitReturnStmt = @import("operands.zig").emitReturnStmt;
const emitStoreValue = @import("dead_slots.zig").emitStoreValue;
const memLoadFn = @import("values.zig").memLoadFn;
const memPrimType = @import("values.zig").memPrimType;
const memStoreFn = @import("values.zig").memStoreFn;
const offIsZero = @import("ident.zig").offIsZero;
const opCanTrap = @import("dead_slots.zig").opCanTrap;
const packWidth = @import("widths.zig").packWidth;
const provCSlotOf = @import("prov.zig").provCSlotOf;
const provCUpdate = @import("prov.zig").provCUpdate;
const regSlot = @import("ident.zig").regSlot;
const resolveTextToC = @import("values.zig").resolveTextToC;
const resolveValueToC = @import("values.zig").resolveValueToC;
const sigReturnWidth = @import("dead_slots.zig").sigReturnWidth;
const tagToPrim = @import("ident.zig").tagToPrim;
const trackWidths = @import("widths.zig").trackWidths;
const widthOfOperand = @import("widths.zig").widthOfOperand;
const writeCStrEscaped = @import("ident.zig").writeCStrEscaped;
const last_c_inst = @import("../emit_c.zig").last_c_inst;
const last_c_func = @import("../emit_c.zig").last_c_func;

pub fn emitLinearInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, widths: *WidthMap, sigmap: anytype, uniform_arity: usize, indirect_ret_width: ?u32, dead: *const std.AutoHashMap(u32, void), bases: *CBaseSet) !void {
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
            if (parsed.dest) |_| {
                const slot = (try callDestSlot(symbols, fsig, use_global, base, parsed)) orelse return CEmitError.InvalidOperand;
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
            if (parsed.dest) |_| {
                const slot = (try callDestSlot(symbols, fsig, use_global, base, parsed)) orelse return CEmitError.InvalidOperand;
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
        .transfer => {
            // Verifier-visible ownership annotation: the preceding `store`
            // already moved the bytes; the Referee consumed the semantic
            // fact. No machine code (explicit, never an `unsupported` trap).
            try writer.print("  /* no-op {s}: {s} */\n", .{ @tagName(base.kind), std.mem.trim(u8, base.raw_text, " \t\r\n") });
        },
        .release => {
            // Ownership release: emit a real `sa_free` only for slots
            // proven to hold owned heap bases (see provCUpdate).
            // Anything else (interior pointers, borrows, scalars,
            // consts) stays a no-op comment, mirroring interp release
            // semantics; freeing those corrupts live allocations.
            const freeable = if (provCSlotOf(fsig, use_global, base.operands[0])) |slot| bases.get(slot) != null else false;
            if (freeable) {
                if (provCSlotOf(fsig, use_global, base.operands[0])) |slot| _ = bases.remove(slot);
                try writer.writeAll("  sa_free(");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  /* no-op {s}: {s} */\n", .{ @tagName(base.kind), std.mem.trim(u8, base.raw_text, " \t\r\n") });
            }
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

// ------------------------------------------------------------------
// @gpu task-form (fork-parallel) emission — TASKFORM_DESIGN.md.
// Only @gpu functions in the task-formed set T (the downward closure
// of the recursive @gpu SCCs) are emitted as a step function plus a
// wrapper over the sa_tf_* machinery; every other function keeps the
// historical emission byte-for-byte. The machinery text is emitted
// only when T is non-empty, so programs without recursive @gpu call
// graphs are completely unaffected.
