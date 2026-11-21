const std = @import("std");
const shims_std_a = @import("shims_std_a.zig");
const shims_std_b = @import("shims_std_b.zig");
const shims_std_c = @import("shims_std_c.zig");
const shims_std_d = @import("shims_std_d.zig");
const shims_http_a = @import("shims_http_a.zig");
const shims_http_b = @import("shims_http_b.zig");
const shims_json_a = @import("shims_json_a.zig");
const shims_json_b = @import("shims_json_b.zig");
const shims_cookie_a = @import("shims_cookie_a.zig");
const shims_cookie_b = @import("shims_cookie_b.zig");
const shims_misc_a = @import("shims_misc_a.zig");
const shims_misc_b = @import("shims_misc_b.zig");
const shims_misc_c = @import("shims_misc_c.zig");
const shims_misc_d = @import("shims_misc_d.zig");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const jsIdent = @import("ident.zig").jsIdent;
const jsFuncName = @import("ident.zig").jsFuncName;
const writeConstSlot = @import("ident.zig").writeConstSlot;
const WidthMap = @import("widths.zig").WidthMap;
const packWidth = @import("widths.zig").packWidth;
const trackWidths = @import("widths.zig").trackWidths;
const JsEmitOptions = @import("types.zig").JsEmitOptions;
const FuncTask = @import("types.zig").FuncTask;
const CalleeRetTable = @import("types.zig").CalleeRetTable;
const RetBaseTable = @import("types.zig").RetBaseTable;
const BaseSet = @import("types.zig").BaseSet;
const collectPromotableSlots = @import("prov.zig").collectPromotableSlots;
const provSolveBody = @import("prov.zig").provSolveBody;
const emitLinearInstruction = @import("dispatch.zig").emitLinearInstruction;
const emitPcInstruction = @import("dispatch.zig").emitPcInstruction;

/// Mirror emit_llvm_llvmc.functionUsesGlobalRegIds: .reg operands may hold
/// per-function slot indexes or global symbol ids, depending on the body.
pub fn taskUsesGlobalRegIds(fsig: sig.FunctionSig, verified: anytype, task: FuncTask) bool {
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        for (verified.annotated[i].base.operands) |operand| {
            if (operand == .reg) {
                const raw = operand.reg;
                if (raw >= fsig.reg_ids.len and fsig.slotOf(raw) != null) return true;
            }
        }
    }
    return false;
}

pub fn emitBodyAsPcMachine(writer: anytype, allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, task: FuncTask, const_addrs: anytype, fn_idx: anytype, js_opt: JsEmitOptions, retbase: *const RetBaseTable) !void {    const use_global = taskUsesGlobalRegIds(fsig, verified, task);
    // Map label symbol id -> pc number. Entry (before first label) is pc 0.
    var label_pc = std.AutoHashMap(u32, usize).init(allocator);
    defer label_pc.deinit();
    var pcs: usize = 1; // next free pc
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        if (base.kind == .label) {
            const lid: u32 = switch (base.operands[1]) {
                .label => |v| v,
                .symbol => |v| v,
                else => continue,
            };
            if (label_pc.get(lid) == null) {
                try label_pc.put(lid, pcs);
                pcs += 1;
            }
        }
    }
    // Owned-base provenance for `release` lowering (see provSolveBody).
    var bases = BaseSet.init(allocator);
    defer bases.deinit();
    // Statically tracked source widths for conversions (see trackWidths);
    // cleared at every label since merges are untracked (sound fallback).
    var widths = WidthMap.init(allocator);
    defer widths.deinit();
    // Declared callee return types, for width tracking of call results
    // (see trackWidths' call case). Variadic callees are excluded: JS
    // rejects their signatures at entry, so no call to one can emit.
    var rettype = CalleeRetTable.init(allocator);
    defer rettype.deinit();
    for (verified.function_sigs) |csig| {
        if (csig.is_variadic) continue;
        if (packWidth(csig.return_ty) != null) {
            rettype.put(csig.name, csig.return_ty) catch {};
        }
    }
    var prov = try provSolveBody(allocator, verified, fsig, use_global, task, retbase, null);
    defer prov.deinit();
    // Slot promotion: unescaped stack slots become function-scope locals.
    var promo = try collectPromotableSlots(allocator, verified, fsig, task, use_global);
    defer promo.deinit();
    if (promo.count() != 0) {
        var pkeys = std.array_list.Managed(u32).init(allocator);
        defer pkeys.deinit();
        var pkit = promo.keyIterator();
        while (pkit.next()) |k| try pkeys.append(k.*);
        std.mem.sort(u32, pkeys.items, {}, std.sort.asc(u32));
        for (pkeys.items) |s| {
            const is64 = if (promo.get(s)) |info| info.narrow_bits == 64 else false;
            if (is64) try writer.print("  let __sa_sp{d} = 0n;\n", .{s}) else try writer.print("  let __sa_sp{d} = 0;\n", .{s});
        }
    }
    // If no labels at all, emit straight-line body without pc machine.
    if (pcs == 1) {
        i = task.start_idx + 1;
        while (i < task.end_idx) : (i += 1) {
            try emitLinearInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, verified.annotated[i].base, js_opt, &bases, retbase, &rettype, &widths, &promo);
        }
        return;
    }

    try writer.writeAll("  let __pc = 0;\n  while (true) {\n    switch (__pc) {\n      case 0: {\n");
    i = task.start_idx + 1;
    var prev_terminates = false;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        if (base.kind == .label) {
            const lid: u32 = switch (base.operands[1]) {
                .label => |v| v,
                .symbol => |v| v,
                else => continue,
            };
            const npc = label_pc.get(lid) orelse continue;
            // Join point: load the fixpoint IN set for this block (sound on
            // every path); unknown labels fall back to empty (safe).
            bases.clearRetainingCapacity();
            widths.clearRetainingCapacity();
            if (prov.lid_to_blk.get(lid)) |tbi| {
                var iit = prov.in_sets.items[tbi].iterator();
                while (iit.next()) |e| try bases.put(e.key_ptr.*, {});
            }
            // A preceding jmp/br/return already leaves the case; skip the
            // redundant `__pc = N; break;` instead of emitting dead code.
            if (prev_terminates) {
                try writer.print("      }}\n      case {d}: {{\n", .{npc});
            } else {
                try writer.print("        __pc = {d}; break;\n      }}\n      case {d}: {{\n", .{ npc, npc });
            }
            prev_terminates = false;
            continue;
        }
        try emitPcInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, base, &label_pc, js_opt, &bases, retbase, &rettype, &widths, &promo);
        prev_terminates = base.kind == .jmp or base.kind == .br or base.kind == .br_null or base.kind == .return_;
    }
    try writer.writeAll("        return __sa_trap(\"fallthrough end of function\");\n      }\n      default: return __sa_trap(\"bad pc \" + __pc);\n    }\n  }\n");
}

pub fn emitOneFunction(writer: anytype, allocator: std.mem.Allocator, verified: anytype, task: FuncTask, const_addrs: anytype, fn_idx: anytype, js_opt: JsEmitOptions, retbase: *const RetBaseTable) !void {
    const fsig = verified.function_sigs[task.fsig_index];
    if (task.kind == .extern_decl) {
        // Known sa_std IO shims live in the emitter (NOT in sa_std): they only
        // read already-emitted linear memory. Unknown externs still trap.
        if (try shims_std_a.emitShim(writer, fsig.name)) return;
        if (try shims_std_b.emitShim(writer, fsig.name)) return;
        if (try shims_std_c.emitShim(writer, fsig.name)) return;
        if (try shims_std_d.emitShim(writer, fsig.name)) return;
        if (try shims_http_a.emitShim(writer, fsig.name)) return;
        if (try shims_http_b.emitShim(writer, fsig.name)) return;
        if (try shims_json_a.emitShim(writer, fsig.name)) return;
        if (try shims_json_b.emitShim(writer, fsig.name)) return;
        if (try shims_cookie_a.emitShim(writer, fsig.name)) return;
        if (try shims_cookie_b.emitShim(writer, fsig.name)) return;
        if (try shims_misc_a.emitShim(writer, fsig.name)) return;
        if (try shims_misc_b.emitShim(writer, fsig.name)) return;
        if (try shims_misc_c.emitShim(writer, fsig.name)) return;
        if (try shims_misc_d.emitShim(writer, fsig.name)) return;
        try writer.writeAll("function ");
        try jsFuncName(writer, fsig.name);
        try writer.writeAll("() { __sa_trap(\"extern not linked: ");
        try jsFuncName(writer, fsig.name);
        try writer.writeAll("\"); }\n");
        return;
    }
    if (js_opt.format == .esm) try writer.writeAll("export function ") else try writer.writeAll("function ");
    try jsFuncName(writer, fsig.name);
    try writer.writeAll("(");
    for (fsig.params, 0..) |p, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try jsIdent(writer, p.name);
    }
    try writer.writeAll(") {\n");
    // Frame scope for stack slots: push on entry, recycle on exit via
    // finally (covers early returns and panics). Indentation of the wrapped
    // body is irrelevant to JS semantics.
    try writer.writeAll("  __sa_fstack.push([]);\n  try {\n");
    if (js_opt.debug_comments) {
        try writer.print("  // sa-sig: {s} -> {s} regs={d}\n", .{ fsig.name, sig.primTypeName(fsig.return_ty), fsig.reg_ids.len });
    }
    // Declare registers as locals. Slots aliasing static consts are
    // initialized to the const address (mirrors LLVM const reg init);
    // all other slots start at 0. Params bind into their slots after.
    if (fsig.reg_ids.len > 0) {
        try writer.writeAll("  let ");
        var first = true;
        for (fsig.reg_ids, 0..) |gid, slot| {
            if (!first) try writer.writeAll(", ");
            try writer.print("r{d} = ", .{slot});
            if (verified.symbols.lookupName(gid)) |gname| {
                if (const_addrs.get(gname)) |_| {
                    try writeConstSlot(writer, gname);
                } else {
                    try writer.writeAll("0");
                }
            } else {
                try writer.writeAll("0");
            }
            first = false;
        }
        try writer.writeAll(";\n");
        // bind params into their slots
        for (fsig.params, 0..) |p, pidx| {
            if (pidx < fsig.param_ids.len) {
                const gid = fsig.param_ids[pidx];
                if (fsig.slotOf(gid)) |slot| {
                    try writer.print("  r{d} = ", .{slot});
                    try jsIdent(writer, p.name);
                    try writer.writeAll(";\n");
                }
            }
        }
    }
    try emitBodyAsPcMachine(writer, allocator, verified, fsig, task, const_addrs, fn_idx, js_opt, retbase);
    try writer.writeAll("  } finally { const __f = __sa_fstack.pop(); for (let __k = 0; __k < __f.length; __k++) __sa_sfree(__f[__k]); }\n}\n");
}
