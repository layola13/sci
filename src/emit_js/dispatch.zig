const std = @import("std");
const types = @import("types.zig");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const tagToPrim = @import("ident.zig").tagToPrim;
const writeJsStrEscaped = @import("ident.zig").writeJsStrEscaped;
const memPrimType = @import("ident.zig").memPrimType;
const memLoadFn = @import("ident.zig").memLoadFn;
const memStoreFn = @import("ident.zig").memStoreFn;
const offIsZero = @import("ident.zig").offIsZero;
const WidthMap = @import("widths.zig").WidthMap;
const trackWidths = @import("widths.zig").trackWidths;
const JsEmitOptions = @import("types.zig").JsEmitOptions;
const JsEmitError = @import("types.zig").JsEmitError;
const CalleeRetTable = @import("types.zig").CalleeRetTable;
const RetBaseTable = @import("types.zig").RetBaseTable;
const BaseSet = @import("types.zig").BaseSet;
const dstSlot = @import("slots.zig").dstSlot;
const provSlotOf = @import("slots.zig").provSlotOf;
const provKill = @import("prov.zig").provKill;
const provKillStoreValue = @import("prov.zig").provKillStoreValue;
const provMark = @import("prov.zig").provMark;
const PromoMap = @import("prov.zig").PromoMap;
const provTransfer = @import("prov.zig").provTransfer;
const resolveTextToJs = @import("instr.zig").resolveTextToJs;
const resolveValueToJs = @import("instr.zig").resolveValueToJs;
const emitCvtExpr = @import("instr.zig").emitCvtExpr;
const emitOpExpr = @import("instr.zig").emitOpExpr;
const emitCallInstruction = @import("instr.zig").emitCallInstruction;
const emitCallIndirectInstruction = @import("instr.zig").emitCallIndirectInstruction;

pub fn labelPcOf(label_pc: *const std.AutoHashMap(u32, usize), op: inst.Operand) !usize {
    const id: u32 = switch (op) {
        .label => |v| v,
        .symbol => |v| v,
        else => return JsEmitError.InvalidOperand,
    };
    return label_pc.get(id) orelse return JsEmitError.UnknownFunction;
}

/// Shared return emission for straight-line and pc-machine bodies.
/// Fallible functions return {s, v} objects (mirrors SA_OP_RET
/// build_fallible_ok); plain functions return bare values.
pub fn emitReturnStmt(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, operand: inst.Operand, indent: []const u8) !void {
    if (fsig.return_fallible) {
        switch (operand) {
            .none => try writer.print("{s}return {{s: 0}};\n", .{indent}),
            else => {
                try writer.print("{s}return {{s: 0, v: (", .{indent});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, operand);
                try writer.writeAll(")};\n");
            },
        }
    } else switch (operand) {
        .none => try writer.print("{s}return 0;\n", .{indent}),
        else => {
            try writer.print("{s}return (", .{indent});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, operand);
            try writer.writeAll(");\n");
        },
    }
}

pub fn emitLinearInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, js_opt: JsEmitOptions, bases: *BaseSet, retbase: *const RetBaseTable, rettype: *const CalleeRetTable, widths: *WidthMap, promo: *const PromoMap) !void {
    _ = js_opt;
    types.last_js_inst = base.raw_text;
    types.last_js_func = fsig.name;
    trackWidths(widths, allocator, symbols, rettype, base);
    switch (base.kind) {
        .return_ => try emitReturnStmt(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0], "  "),
        .try_, .early_return => {
            // Unpack {s, v}; on error early-return like SA_OP_TRY.
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            provKill(bases, fsig, use_global, base.operands[0]);
            try writer.writeAll("  { const __t = (");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll("); if (!__sa_fok(__t)) ");
            if (fsig.return_fallible) {
                try writer.writeAll("return __t;");
            } else if (fsig.return_ty == .void) {
                try writer.writeAll("return;");
            } else {
                try writer.writeAll("return 0;");
            }
            try writer.print(" r{d} = __sa_fv(__t); }}\n", .{slot});
        },
        .op => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            provKill(bases, fsig, use_global, base.operands[0]);
            const opcode = base.op_kind orelse return JsEmitError.InvalidOperand;
            if (inst.isTypeConversionOpKind(opcode)) {
                if (base.operands[2] != .ty) return JsEmitError.InvalidOperand;
                // Tsgosa emits bare `sitofp X` / `uitofp X` (Number()
                // conversions) without `as f64`; the flattener defaults the
                // target to i32, which no float conversion accepts. Native
                // coerces to f64 at the consuming call site, so default the
                // target to f64 here for identical observable behavior.
                var tgt = tagToPrim(base.operands[2].ty);
                if ((opcode == .sitofp or opcode == .uitofp) and tgt != .f32 and tgt != .f64) {
                    tgt = .f64;
                }
                try writer.print("  r{d} = ", .{slot});
                try emitCvtExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, tgt, base.operands[1], widths);
                try writer.writeAll(";\n");
                return;
            }
            try writer.print("  r{d} = ", .{slot});
            if (opcode == .fneg) {
                try writer.writeAll("(-(");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll("));\n");
                return;
            }
            try emitOpExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, base.operands[1], base.operands[2], widths);
            try writer.writeAll(";\n");
        },
        .alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Fresh owned heap base: eligible for `__sa_free` on release.
            bases.put(slot, {}) catch return JsEmitError.OutOfMemory;
            try writer.print("  r{d} = __sa_alloc(", .{slot});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(");\n");
        },
        .stack_alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Mirrors the interpreter: stack slots are never freed mid-frame;
            // they are recycled when the owning frame returns (finally pop).
            _ = bases.remove(slot);
            try writer.print("  r{d} = __sa_salloc(", .{slot});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(");\n");
            // Promoted slot: snapshot the cell into its local (identical
            // stale bytes to what the program would observe; re-executes
            // correctly if the alloc itself is inside a loop).
            if (promo.get(slot)) |info| {
                try writer.print("  __sa_sp{d} = {s}(r{d});\n", .{ slot, info.load_fn, slot });
            }
        },
        .ptr_add => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Interior pointer (even at offset 0): never an owned base.
            _ = bases.remove(slot);
            // Peephole: ptr_add(x, 0) is the identity; skipping the helper
            // also skips BigInt materialization for 64-bit zero offsets on
            // the hot path (correct: x+0 == x in both domains).
            if (offIsZero(base.operands[2])) {
                try writer.print("  r{d} = ", .{slot});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(";\n");
            } else {
                try writer.print("  r{d} = __sa_ptr_add(", .{slot});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(", ");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            }
        },
        .load, .take, .atomic_load => {
            // NOTE: atomic ordering is ignored (single-threaded JS runtime).
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Loaded data is never an owned base.
            _ = bases.remove(slot);
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            if (promoBaseSlot(fsig, use_global, base, promo)) |bs| {
                try writer.print("  r{d} = __sa_sp{d};\n", .{ slot, bs });
            } else if (offIsZero(base.operands[2])) {
                try writer.print("  r{d} = {s}(", .{ slot, load_fn });
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  r{d} = {s}(__sa_ptr_add(", .{ slot, load_fn });
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(", ");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll("));\n");
            }
        },
        .store, .atomic_store => {
            // NOTE: atomic ordering is ignored (single-threaded JS runtime).
            // Escape: the stored value may be an owned base aliased into
            // memory; forget the source slot so a later `release` stays a
            // no-op (mirrors provTransfer; see the array-literal pattern).
            provKillStoreValue(bases, symbols, fsig, use_global, base.operands[2]);
            const ty = memPrimType(base);
            const store_fn = memStoreFn(ty);
            if (promoBaseSlot(fsig, use_global, base, promo)) |bs| {
                const info = promo.get(bs).?;
                // Narrow inline for 32-bit (bit-identical to __sa_narrow;
                // value operands are pure refs so triple emission is safe,
                // mirroring the br_null duplicate-operand precedent).
                if (info.narrow_bits == 32) {
                    try writer.print("  __sa_sp{d} = ((typeof (", .{bs});
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                    if (info.narrow_signed) {
                        try writer.writeAll(") === \"bigint\") ? Number(BigInt.asIntN(32, (");
                    } else {
                        try writer.writeAll(") === \"bigint\") ? Number(BigInt.asUintN(32, (");
                    }
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                    if (info.narrow_signed) {
                        try writer.writeAll("))) : ((");
                    } else {
                        try writer.writeAll("))) : ((");
                    }
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                    if (info.narrow_signed) {
                        try writer.writeAll(") | 0));\n");
                    } else {
                        try writer.writeAll(") >>> 0));\n");
                    }
                } else if (info.narrow_bits == 64) {
                    // Mirrors __sa_store_i64 exactly (asIntN for both i64/u64).
                    try writer.print("  __sa_sp{d} = BigInt.asIntN(64, BigInt((", .{bs});
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                    try writer.writeAll(")));\n");
                } else {
                    try writer.print("  __sa_sp{d} = __sa_narrow(", .{bs});
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                    try writer.print(", {d}, {s});\n", .{ info.narrow_bits, if (info.narrow_signed) "true" else "false" });
                }
            } else if (offIsZero(base.operands[1])) {
                try writer.print("  {s}(", .{store_fn});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(", ");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  {s}(__sa_ptr_add(", .{store_fn});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(", ");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll("), ");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            }
        },
        .call => try emitCallInstruction(writer, allocator, symbols, fsig, use_global, const_addrs, fn_idx, base, bases, retbase),
        .call_indirect => try emitCallIndirectInstruction(writer, allocator, symbols, fsig, use_global, const_addrs, fn_idx, base, bases, retbase),
        .cmpxchg => {
            // Single-threaded降级: old = load; ok = (old == expected);
            // if (ok) store(new). Mirrors SA_OP_CMPXCHG (dst=old, 2nd target=ok).
            const dst_old = try dstSlot(fsig, use_global, base.operands[0]);
            const dst_ok = try dstSlot(fsig, use_global, base.operands[1]);
            _ = bases.remove(dst_old);
            _ = bases.remove(dst_ok);
            const expected = base.atomic_expected_text orelse return JsEmitError.InvalidOperand;
            const new_text = base.atomic_new_text orelse return JsEmitError.InvalidOperand;
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            const store_fn = memStoreFn(ty);
            try writer.writeAll("  { const __addr = __sa_ptr_add(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[3]);
            try writer.print("); const __old = {s}(__addr); const __exp = (", .{load_fn});
            try resolveTextToJs(writer, symbols, fsig, const_addrs, expected);
            try writer.writeAll("); const __ok = ((__old == __exp) ? 1 : 0); if (__ok) ");
            try writer.print("{s}(__addr, (", .{store_fn});
            try resolveTextToJs(writer, symbols, fsig, const_addrs, new_text);
            try writer.print(")); r{d} = __old; r{d} = __ok; }}\n", .{ dst_old, dst_ok });
        },
        .atomic_rmw => {
            // Single-threaded降级: dst = old = load(addr); store(addr, op(old, value)).
            // Mirrors LLVM atomicrmw (returns the previous memory contents).
            const op = base.atomic_rmw_op orelse return JsEmitError.InvalidOperand;
            const dst = try dstSlot(fsig, use_global, base.operands[0]);
            _ = bases.remove(dst);
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            const store_fn = memStoreFn(ty);
            try writer.writeAll("  { const __addr = __sa_ptr_add(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.print("); const __old = {s}(__addr); const __val = (", .{load_fn});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[3]);
            try writer.writeAll("); const __new = ");
            switch (op) {
                .add => try writer.writeAll("__sa_add(__old, __val)"),
                .sub => try writer.writeAll("__sa_sub(__old, __val)"),
                .@"and" => try writer.writeAll("__sa_band(__old, __val)"),
                .@"or" => try writer.writeAll("__sa_bor(__old, __val)"),
                .xor => try writer.writeAll("__sa_bxor(__old, __val)"),
                .xchg => try writer.writeAll("__val"),
                .min => try writer.writeAll("((__sa_sle(__old, __val)) ? __old : __val)"),
                .max => try writer.writeAll("((__sa_sge(__old, __val)) ? __old : __val)"),
                .umin => try writer.writeAll("((__sa_ule(__old, __val)) ? __old : __val)"),
                .umax => try writer.writeAll("((__sa_uge(__old, __val)) ? __old : __val)"),
            }
            try writer.print("; {s}(__addr, __new); r{d} = __old; }}\n", .{ store_fn, dst });
        },
        .fence => {
            try writer.writeAll("  /* no-op fence (single-threaded JS runtime) */\n");
        },
        .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow => {
            // Mirror emit_llvm_llvmc assignOperand (and the interpreter):
            // dst aliases the value. assume_* are NOT no-ops: dropping the
            // copy leaves the dst slot at its zero init (broke pthread_spawn
            // entry delivery in 184_pthread_spawn_join).
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Alias preserves base provenance (borrow checking guarantees no
            // live use after any release of an alias).
            try provMark(bases, fsig, use_global, base.operands[0], base.operands[1]);
            try writer.print("  r{d} = (", .{slot});
            switch (base.operands[1]) {
                .reg, .symbol, .func, .label, .imm_i64, .imm_int, .imm_u64, .imm_float, .text, .native_text => {
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                },
                else => return JsEmitError.InvalidOperand,
            }
            try writer.writeAll(");\n");
        },
        .panic => {
            // `panic(code)` uses call syntax; parse args like the LLVM backend.
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                try writer.print("  __sa_trap(\"panic: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            };
            defer parsed.deinit(allocator);
            if (parsed.args.len != 1) {
                try writer.print("  __sa_trap(\"panic: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            }
            try writer.writeAll("  __sa_panic(");
            try resolveTextToJs(writer, symbols, fsig, const_addrs, parsed.args[0].text);
            try writer.writeAll(");\n");
        },
        .panic_msg => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                try writer.writeAll("  __sa_trap(\"panic_msg\");\n");
                return;
            };
            defer parsed.deinit(allocator);
            if (parsed.args.len >= 1) {
                try writer.writeAll("  __sa_trap(\"panic_msg: \" + (");
                try resolveTextToJs(writer, symbols, fsig, const_addrs, parsed.args[0].text);
                try writer.writeAll("));\n");
            } else {
                try writer.writeAll("  __sa_trap(\"panic_msg\");\n");
            }
        },
        .move_ => {
            try writer.print("  /* no-op {s}: {s} */\n", .{ @tagName(base.kind), std.mem.trim(u8, base.raw_text, " \t\r\n") });
        },
        .release => {
            // Ownership release: emit a real `__sa_free` only for slots
            // proven to hold owned heap bases. Anything else (interior
            // pointers, borrows, scalars, consts) stays a no-op comment,
            // mirroring interp release semantics.
            const freeable = if (provSlotOf(fsig, use_global, base.operands[0])) |slot| bases.get(slot) != null else false;
            if (freeable) {
                if (provSlotOf(fsig, use_global, base.operands[0])) |slot| _ = bases.remove(slot);
                try writer.writeAll("  __sa_free(");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  /* no-op {s}: {s} */\n", .{ @tagName(base.kind), std.mem.trim(u8, base.raw_text, " \t\r\n") });
            }
        },
        .native => {
            // Empty-template `asm sideeffect ""` carries no observable effect;
            // downgrade to a no-op (value passes through, matching demo intent).
            // Non-empty native escapes stay a loud trap, escaped so quotes in
            // the raw text cannot break the generated JS module.
            const raw = std.mem.trim(u8, base.raw_text, " \t\r\n");
            if (std.mem.indexOf(u8, raw, "asm sideeffect \"\"") != null) {
                try writer.writeAll("  /* no-op empty inline asm (single-threaded JS runtime) */\n");
            } else {
                try writer.writeAll("  __sa_trap(\"unsupported native: ");
                try writeJsStrEscaped(writer, raw);
                try writer.writeAll("\");\n");
            }
        },
        else => {
            try writer.print("  __sa_trap(\"unsupported {s}: ", .{@tagName(base.kind)});
            try writeJsStrEscaped(writer, std.mem.trim(u8, base.raw_text, " \t\r\n"));
            try writer.writeAll("\");\n");
        },
    }
}

pub fn emitPcInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, label_pc: *std.AutoHashMap(u32, usize), js_opt: JsEmitOptions, bases: *BaseSet, retbase: *const RetBaseTable, rettype: *const CalleeRetTable, widths: *WidthMap, promo: *const PromoMap) !void {
    switch (base.kind) {
        .jmp => {
            const npc = try labelPcOf(label_pc, base.operands[1]);
            try writer.print("        __pc = {d}; break;\n", .{npc});
        },
        .br => {
            const tpc = try labelPcOf(label_pc, base.operands[1]);
            const fpc = try labelPcOf(label_pc, base.operands[3]);
            try writer.writeAll("        __pc = (__sa_truthy(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
            try writer.print(") ? {d} : {d}); break;\n", .{ tpc, fpc });
        },
        .br_null => {
            // Null test on raw bits (mirrors interp `cond.bits == 0`):
            // only 0 / 0n count as null. NaN is *not* null (bits != 0),
            // so this intentionally differs from `!v` / `__sa_truthy`.
            const tpc = try labelPcOf(label_pc, base.operands[1]);
            const fpc = try labelPcOf(label_pc, base.operands[3]);
            try writer.writeAll("        __pc = ((((");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
            try writer.writeAll(") === 0) || ((");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
            try writer.writeAll(") === 0n))");
            try writer.print(" ? {d} : {d}); break;\n", .{ tpc, fpc });
        },
        .return_ => try emitReturnStmt(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0], "        "),
        else => {
            try writer.writeAll("        ");
            // Reuse the linear emitter, then re-indent (it emits with 2-space indent).
            var buf: [32768]u8 = undefined;
            var fbs = std.Io.Writer.fixed(&buf);
            try emitLinearInstruction(&fbs, allocator, symbols, fsig, use_global, const_addrs, fn_idx, base, js_opt, bases, retbase, rettype, widths, promo);
            const s = std.mem.trim(u8, fbs.buffered(), " \t\r\n");
            // Linear emitter may produce multiple lines; indent each by 8 spaces.
            var it = std.mem.splitScalar(u8, s, '\n');
            var first_line = true;
            while (it.next()) |line| {
                const t = std.mem.trim(u8, line, " \t\r");
                if (t.len == 0) continue;
                if (!first_line) try writer.writeAll("        ");
                try writer.print("{s}\n", .{t});
                first_line = false;
            }
        },
    }
}

/// Promoted base slot for a zero-offset plain load/store, else null.
pub fn promoBaseSlot(fsig: sig.FunctionSig, use_global: bool, base: inst.Instruction, promo: *const PromoMap) ?u32 {
    const is_load = base.kind == .load;
    const is_store = base.kind == .store;
    if (!is_load and !is_store) return null;
    const base_op = if (is_load) base.operands[1] else base.operands[0];
    const off_op = if (is_load) base.operands[2] else base.operands[1];
    if (!offIsZero(off_op)) return null;
    const bs = provSlotOf(fsig, use_global, base_op) orelse return null;
    if (promo.get(bs) == null) return null;
    return bs;
}
