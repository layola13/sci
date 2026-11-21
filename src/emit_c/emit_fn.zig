const std = @import("std");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const CBaseSet = @import("types.zig").CBaseSet;
const CEmitOptions = @import("types.zig").CEmitOptions;
const FuncTask = @import("types.zig").FuncTask;
const TfFnCtx = @import("types.zig").TfFnCtx;
const TfSyncInfo = @import("types.zig").TfSyncInfo;
const WidthMap = @import("types.zig").WidthMap;
const allReadersElided = @import("dead_slots.zig").allReadersElided;
const cFuncName = @import("ident.zig").cFuncName;
const cIdent = @import("ident.zig").cIdent;
const collectDefUse = @import("dead_slots.zig").collectDefUse;
const computeDeadSlots = @import("dead_slots.zig").computeDeadSlots;
const computeElideIdx = @import("dead_slots.zig").computeElideIdx;
const emitLinearInstruction = @import("linear.zig").emitLinearInstruction;
const emitTfCall = @import("tf_emit.zig").emitTfCall;
const emitTfReturn = @import("tf_emit.zig").emitTfReturn;
const emitTfSyncBlock = @import("tf_emit.zig").emitTfSyncBlock;
const emitTfWrapper = @import("tf_emit.zig").emitTfWrapper;
const packWidth = @import("widths.zig").packWidth;
const provCUpdate = @import("prov.zig").provCUpdate;
const pureElidable = @import("dead_slots.zig").pureElidable;
const resolveValueToC = @import("values.zig").resolveValueToC;
const sigNormName = @import("ident.zig").sigNormName;
const taskUsesGlobalRegIds = @import("ident.zig").taskUsesGlobalRegIds;
const tfArgIdentity = @import("tf_emit.zig").tfArgIdentity;
const tfListHas = @import("tf_emit.zig").tfListHas;
const tfListHasU64 = @import("tf_emit.zig").tfListHasU64;
const writeConstSym = @import("ident.zig").writeConstSym;
const CEmitError = @import("../emit_c.zig").CEmitError;
const emit_c = @import("../emit_c.zig");

pub fn emitOneFunction(writer: anytype, allocator: std.mem.Allocator, verified: anytype, task: FuncTask, const_addrs: anytype, fn_idx: anytype, c_opt: CEmitOptions, sigmap: anytype, uniform_arity: usize, indirect_ret_width: ?u32, tf: ?TfFnCtx) !void {
    const fsig = verified.function_sigs[task.fsig_index];
    const use_global = taskUsesGlobalRegIds(fsig, verified, task);
    emit_c.last_c_func = fsig.name;
    var widths = WidthMap.init(allocator);
    defer widths.deinit();
    // Definitely-unread slots: pure redefinitions elided, effectful calls
    // kept in (void) form (silences clang-analyzer-deadcode.DeadStores).
    var reads_complete = true;
    var dead = computeDeadSlots(allocator, verified, fsig, use_global, task) catch blk: {
        reads_complete = false;
        break :blk std.AutoHashMap(u32, void).init(allocator);
    };
    defer dead.deinit();
    var elide = computeElideIdx(allocator, verified, fsig, use_global, task) catch std.AutoHashMap(usize, void).init(allocator);
    defer elide.deinit();
    var wdefs = std.array_list.Managed(u32).init(allocator);
    defer wdefs.deinit();
    var wuses = std.array_list.Managed(u32).init(allocator);
    defer wuses.deinit();
    // Cascade kills fixpoint: pure defs whose dests are dead AND pure
    // defs read only by skippable insts must both go. Two sets grow
    // monotonically (bounded by task size):
    //   dead  += slots with no reader outside `skipped`
    //   elide += pure insts whose defs are all dead (`skipped` = elide
    //            plus pure all-dead-def insts, mirroring emission which
    //            elides pure-dead via dead-checks independently)
    // Emission (elide pre-check, dead-based void/bare/elision) stays
    // consistent by construction. Zero additions = historical behavior.
    {
        var round: usize = 0;
        while (round < 1024) : (round += 1) {
            var progressed = false;
            // Phase A: slots with no reader outside skipped insts are dead.
            // (Skipped = elide map, which Phase B below also extends with
            // pure all-dead-def insts, so later rounds see them.)
            var si: usize = task.start_idx + 1;
            while (si < task.end_idx) : (si += 1) {
                wdefs.clearRetainingCapacity();
                wuses.clearRetainingCapacity();
                collectDefUse(allocator, verified, fsig, use_global, verified.annotated[si].base, &wdefs, &wuses) catch break;
                for (wdefs.items) |sl| {
                    if (dead.get(sl) != null) continue;
                    if (!allReadersElided(allocator, verified, fsig, use_global, task, &elide, sl)) continue;
                    dead.put(sl, {}) catch continue;
                    progressed = true;
                }
            }
            // Phase B: pure insts whose defs are all dead are skippable.
            var gi: usize = task.start_idx + 1;
            while (gi < task.end_idx) : (gi += 1) {
                if (elide.get(gi) != null) continue;
                const gbase = verified.annotated[gi].base;
                if (!pureElidable(gbase)) continue;
                wdefs.clearRetainingCapacity();
                wuses.clearRetainingCapacity();
                collectDefUse(allocator, verified, fsig, use_global, gbase, &wdefs, &wuses) catch break;
                if (wdefs.items.len == 0) continue;
                var all_dead = true;
                for (wdefs.items) |sl| {
                    if (dead.get(sl) == null) {
                        all_dead = false;
                        break;
                    }
                }
                if (!all_dead) continue;
                elide.put(gi, {}) catch continue;
                progressed = true;
            }
            if (!progressed) break;
        }
    }
    // Live-for-declaration set: slots read by a non-elided instruction.
    // (Effectful unread defs emit bare calls needing no declaration;
    // pure unread defs are elided above.) On any analysis failure the
    // flag drops and everything is declared (safe direction).
    var liveK = std.AutoHashMap(u32, void).init(allocator);
    defer liveK.deinit();
    {
        var gi: usize = task.start_idx + 1;
        while (gi < task.end_idx) : (gi += 1) {
            if (elide.get(gi) != null) continue;
            wdefs.clearRetainingCapacity();
            wuses.clearRetainingCapacity();
            collectDefUse(allocator, verified, fsig, use_global, verified.annotated[gi].base, &wdefs, &wuses) catch {
                reads_complete = false;
                break;
            };
            for (wuses.items) |sl| liveK.put(sl, {}) catch {
                reads_complete = false;
                break;
            };
        }
    }
    // Labels targeted by a jump/branch. An untargeted label is pure
    // fallthrough: emitting it trips -Wunused-label, so only the gas
    // metering (which still executes on fallthrough) is kept.
    var label_refs = std.AutoHashMap(u32, void).init(allocator);
    defer label_refs.deinit();
    {
        var li: usize = task.start_idx + 1;
        while (li < task.end_idx) : (li += 1) {
            const lb = verified.annotated[li].base;
            switch (lb.kind) {
                .jmp => {
                    const id: u32 = switch (lb.operands[1]) {
                        .label => |v| v,
                        .symbol => |v| v,
                        else => continue,
                    };
                    label_refs.put(id, {}) catch {};
                },
                .br, .br_null => {
                    const t: u32 = switch (lb.operands[1]) {
                        .label => |v| v,
                        .symbol => |v| v,
                        else => continue,
                    };
                    const f: u32 = switch (lb.operands[3]) {
                        .label => |v| v,
                        .symbol => |v| v,
                        else => continue,
                    };
                    label_refs.put(t, {}) catch {};
                    label_refs.put(f, {}) catch {};
                },
                else => {},
            }
        }
    }
    // Task-form pre-pass (only for functions in the task-formed set):
    // compute the declared-slot list (frame load/save set) and assign
    // suspension points by a dry walk over the body. A suspension is
    // required before any instruction that may observe or overwrite
    // an outstanding spawn result, before any control transfer while
    // spawns are outstanding, before a parent memory write while
    // spawns are outstanding, before a parent memory read while a
    // possibly-writing child is outstanding, and before a spawn that
    // shares a may-store argument with a live spawn (TASKFORM_DESIGN
    // sections 6-7). The dry walk mirrors the emission walk exactly
    // (same elide set), so every assigned point exists in the output.
    var tf_declared = std.array_list.Managed(u32).init(allocator);
    defer tf_declared.deinit();
    var tf_const_slots = std.array_list.Managed(u32).init(allocator);
    defer tf_const_slots.deinit();
    var tf_const_names = std.array_list.Managed([]const u8).init(allocator);
    defer tf_const_names.deinit();
    var tf_syncs = std.AutoHashMap(usize, TfSyncInfo).init(allocator);
    defer tf_syncs.deinit();
    var tf_sync_list = std.array_list.Managed(TfSyncInfo).init(allocator);
    defer tf_sync_list.deinit();
    var tf_tail: ?TfSyncInfo = null;
    if (tf) |tc| {
        {
            var s: usize = 0;
            while (s < fsig.reg_ids.len) : (s += 1) {
                const slot32: u32 = @intCast(s);
                // Same predicate as the declaration block below.
                if (reads_complete and liveK.get(slot32) == null) continue;
                try tf_declared.append(slot32);
                const gid = fsig.reg_ids[s];
                if (verified.symbols.lookupName(gid)) |gname| {
                    if (const_addrs.get(gname) != null) {
                        try tf_const_slots.append(slot32);
                        try tf_const_names.append(gname);
                    }
                }
            }
        }
        var out_slots = std.array_list.Managed(u32).init(allocator);
        defer out_slots.deinit();
        var out_count: u32 = 0;
        var out_writer = false;
        var group_args = std.array_list.Managed(std.array_list.Managed(u64)).init(allocator);
        defer {
            for (group_args.items) |*g| g.deinit();
            group_args.deinit();
        }
        var next_id: u32 = 1;
        var wi: usize = task.start_idx + 1;
        while (wi < task.end_idx) : (wi += 1) {
            if (elide.get(wi) != null) continue;
            const wb = verified.annotated[wi].base;
            wdefs.clearRetainingCapacity();
            wuses.clearRetainingCapacity();
            // Unlike the liveness analyses above, sync placement must
            // not degrade silently on an analysis failure: a missed
            // use is a missed suspension. Fail the emission loudly.
            collectDefUse(allocator, verified, fsig, use_global, wb, &wdefs, &wuses) catch return CEmitError.Failed;
            // Call analysis first (spawn transition data + whether the
            // call is a barrier), in plain locals.
            var is_spawn = false;
            var spawn_dest: ?u32 = null;
            var spawn_writer = false;
            var spawn_args = std.array_list.Managed(u64).init(allocator);
            defer spawn_args.deinit();
            var is_barrier_call = wb.kind == .call_indirect;
            if (wb.kind == .call) {
                is_barrier_call = true;
                if (call.parseInstructionCall(allocator, wb, verified.symbols)) |*pc| {
                    var parsed = pc.*;
                    defer parsed.deinit(allocator);
                    if (!parsed.is_indirect) {
                        if (tc.prog.fnid_by_name.get(sigNormName(parsed.callee))) |cfid| {
                            is_spawn = true;
                            is_barrier_call = false;
                            const cfsig = verified.function_sigs[tc.prog.fsig_of_fnid[cfid]];
                            spawn_writer = tc.prog.may_store_any[cfid];
                            if (parsed.dest) |dname| {
                                if (verified.symbols.findId(dname)) |did| {
                                    if (fsig.slotOf(did)) |slot| {
                                        if (dead.get(slot) == null) spawn_dest = slot;
                                    }
                                }
                            }
                            const lim = @min(@min(parsed.args.len, cfsig.params.len), cfsig.param_ids.len);
                            for (parsed.args[0..lim], 0..) |arg, j| {
                                if (!tc.prog.may_store[cfid][j]) continue;
                                try spawn_args.append(tfArgIdentity(verified.symbols, fsig, arg.text));
                            }
                        }
                    }
                } else |_| {}
            }
            var need = false;
            if (out_count > 0) {
                const is_control = switch (wb.kind) {
                    .label, .jmp, .br, .br_null, .return_, .early_return => true,
                    else => false,
                };
                const is_mem_write = switch (wb.kind) {
                    .store, .atomic_store, .atomic_rmw, .cmpxchg => true,
                    else => false,
                };
                const is_mem_read = switch (wb.kind) {
                    .load, .take, .atomic_load, .atomic_rmw, .cmpxchg => true,
                    else => false,
                };
                if (is_control or is_barrier_call or is_mem_write) {
                    need = true;
                } else if (is_mem_read and out_writer) {
                    need = true;
                } else if (is_spawn) {
                    // R4: the new spawn shares a may-store argument
                    // with a live group member.
                    for (group_args.items) |g| {
                        for (spawn_args.items) |a| {
                            if (tfListHasU64(g.items, a)) {
                                need = true;
                                break;
                            }
                        }
                        if (need) break;
                    }
                }
                if (!need) {
                    for (wuses.items) |s| {
                        if (tfListHas(out_slots.items, s)) {
                            need = true;
                            break;
                        }
                    }
                }
                if (!need) {
                    for (wdefs.items) |s| {
                        if (tfListHas(out_slots.items, s)) {
                            need = true;
                            break;
                        }
                    }
                }
            }
            if (need) {
                const info = TfSyncInfo{ .id = next_id, .reload = try allocator.dupe(u32, out_slots.items) };
                next_id += 1;
                try tf_syncs.put(wi, info);
                try tf_sync_list.append(info);
                out_slots.clearRetainingCapacity();
                out_count = 0;
                out_writer = false;
                for (group_args.items) |*g| g.deinit();
                group_args.clearRetainingCapacity();
            }
            if (is_spawn) {
                if (spawn_dest) |slot| {
                    if (!tfListHas(out_slots.items, slot)) try out_slots.append(slot);
                }
                out_count += 1;
                if (spawn_writer) out_writer = true;
                var g = std.array_list.Managed(u64).init(allocator);
                try g.appendSlice(spawn_args.items);
                try group_args.append(g);
            }
        }
        if (out_count > 0) {
            tf_tail = TfSyncInfo{ .id = next_id, .reload = try allocator.dupe(u32, out_slots.items) };
        }
    }
    // Seed parameter slots with their declared types: caller and callee
    // share the u64-bits invariant, so this is exact (unlike JS, which
    // must infer argument domains at runtime).
    for (fsig.param_ids, 0..) |pid, pi| {
        if (pi >= fsig.params.len) break;
        if (fsig.slotOf(pid)) |slot| {
            if (packWidth(fsig.params[pi].ty)) |w| {
                widths.put(slot, w) catch {};
            }
        }
    }
    // Task-formed functions are emitted as a step function over a
    // frame (plus, at the end, a wrapper with the uniform signature).
    if (tf) |_| {
        try writer.writeAll("static void sa_tf_step_");
        try cIdent(writer, sigNormName(fsig.name));
        try writer.writeAll("(sa_u64 fr) {\n");
    } else {
    // Uniform-arity prototype: every function takes exactly uniform_arity
    // u64 params (extras ignored, missing padded with 0 at call sites).
    // This makes direct calls, the ftable, and indirect dispatch share
    // one C signature shape.
    try writer.writeAll("static sa_u64 ");
    try cFuncName(writer, fsig.name);
    try writer.writeAll("(");
    if (uniform_arity == 0) {
        try writer.writeAll("void");
    } else {
        for (0..uniform_arity) |pi| {
            if (pi != 0) try writer.writeAll(", ");
            try writer.print("sa_u64 a{d}", .{pi});
        }
    }
    try writer.writeAll(") {\n");
    }
    const nregs = fsig.reg_ids.len;
    if (nregs > 0) {
        // Declare registers. Slots aliasing static consts are
        // initialized to the const address (mirrors the JS backend);
        // all other slots start at 0. Params bind into their slots after.
        // Slots never read in the body are not declared at all: a
        // set-but-unused `rN` trips -Wunused-but-set-variable (and reads
        // as dead code to auditors); nothing references them.
        var first_decl = true;
        var s: usize = 0;
        while (s < nregs) : (s += 1) {
            const slot32: u32 = @intCast(s);
            // Declare a slot iff it is read by a non-elided instruction
            // (when liveness is known). Effectful unread defs emit bare
            // calls, pure unread defs are elided above: neither assigns,
            // so neither needs a declaration. On any analysis failure
            // declare everything (safe direction).
            if (reads_complete and liveK.get(slot32) == null) continue;
            if (first_decl) {
                try writer.writeAll("  sa_u64 ");
                first_decl = false;
            } else {
                try writer.writeAll(", ");
            }
            try writer.print("r{d} = ", .{s});
            const gid = fsig.reg_ids[s];
            if (verified.symbols.lookupName(gid)) |gname| {
                if (const_addrs.get(gname) != null) {
                    try writeConstSym(writer, gname);
                } else {
                    try writer.writeAll("0");
                }
            } else {
                try writer.writeAll("0");
            }
        }
        if (!first_decl) {
            try writer.writeAll(";\n");
        }
    }
    if (tf) |_| {
        // Step prologue: load the register file from the frame (the
        // frame was zero-initialized at frame_new and the spawner
        // stored the arguments into the parameter slots, so on first
        // entry this reproduces declaration init + parameter binding;
        // const-alias slots are then re-seeded with their constant
        // address, exactly like the declaration initializers do).
        for (tf_declared.items) |s| {
            try writer.print("  r{d} = sa_tf_ld64(fr + SA_TF_REGOFF({d}));\n", .{ s, s });
        }
        if (tf_const_slots.items.len > 0) {
            try writer.writeAll("  if (sa_tf_ld32(fr + SA_TF_OFF_RESUME) == 0) {\n");
            for (tf_const_slots.items, tf_const_names.items) |s, gname| {
                try writer.print("    r{d} = ", .{s});
                try writeConstSym(writer, gname);
                try writer.writeAll(";\n");
            }
            try writer.writeAll("  }\n");
        }
        // Gas is charged per step segment on the C path (entry of each
        // step); the LLVM build-exe path is untouched.
        if (c_opt.gas) {
            try writer.writeAll("  SA_GAS_CHECK(1);\n");
        }
        // Resume dispatch: jump to the suspension point whose wait
        // has completed (join == 0 is re-checked there).
        try writer.writeAll("  { uint32_t sa_tf_res = (uint32_t)sa_tf_ld32(fr + SA_TF_OFF_RESUME);\n    switch (sa_tf_res) {\n      case 0: break;\n");
        for (tf_sync_list.items) |info| {
            try writer.print("      case {d}: goto SA_TF_SYNC_{d};\n", .{ info.id, info.id });
        }
        if (tf_tail) |info| {
            try writer.print("      case {d}: goto SA_TF_SYNC_{d};\n", .{ info.id, info.id });
        }
        try writer.writeAll("      default: sa_trap(\"sa_tf: bad resume id\");\n    } }\n");
    } else {
    // map params to slots (skip slots never read in the body)
    for (fsig.param_ids, 0..) |pid, pi| {
        if (fsig.slotOf(pid)) |slot| {
            if (dead.get(slot) != null) {
                try writer.print("  /* dead param elided: r{d} = a{d}; */\n", .{ slot, pi });
                continue;
            }
            try writer.print("  r{d} = a{d};\n", .{ slot, pi });
        }
    }
    // Silence misc-unused-parameters for padded uniform-arity params.
    for (0..uniform_arity) |pi| {
        try writer.print("  (void)a{d};\n", .{pi});
    }
    // Gas metering: every function entry costs 1 unit. The SA selling
    // point is Gas+Capability; without this a guest infinite loop hangs
    // the host (e.g. a Shopify checkout rule).
    if (c_opt.gas) {
        try writer.writeAll("  SA_GAS_CHECK(1);\n");
    }
    }
    if (c_opt.debug_comments) {
        try writer.print("  /* fn {s} regs={d} */\n", .{ fsig.name, nregs });
    }
    // Owned-heap-base provenance for gated `.release` freeing
    // (provCUpdate); per function, advanced once per instruction.
    var bases = CBaseSet.init(allocator);
    defer bases.deinit();
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        if (elide.get(i) != null) {
            try writer.print("  /* dead store elided: {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
            continue;
        }
        if (tf) |_| {
            if (tf_syncs.get(i)) |sinfo| try emitTfSyncBlock(writer, tf_declared.items, sinfo);
        }
        switch (base.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                try writer.writeAll("  sa_trap(\"nested decl\");\n");
            },
            .label => {
                const id: u32 = switch (base.operands[0]) {
                    .label => |v| v,
                    .symbol => |v| v,
                    else => 0,
                };
                // Join point: merges are untracked, drop widths (sound
                // fallback; mirrors the JS backend clearing at labels).
                widths.clearRetainingCapacity();
                if (label_refs.get(id) == null) {
                    // Fallthrough-only block: no label (else -Wunused-label),
                    // but the block entry still pays gas on fallthrough.
                    if (c_opt.debug_comments) {
                        try writer.print("  /* fallthrough {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                    }
                    if (c_opt.gas) {
                        try writer.writeAll("  SA_GAS_CHECK(1);\n");
                    }
                    continue;
                }
                try writer.print("SA_L_{d}:\n", .{id});
                // Control-flow join: owned-base provenance is unknown
                // past a label (conservative, leak-only).
                bases.clearRetainingCapacity();
                // Loop/back-edge headers pay gas per visit: bounded execution.
                if (c_opt.gas) {
                    try writer.writeAll("  SA_GAS_CHECK(1);\n");
                }
                if (c_opt.debug_comments) {
                    try writer.print("  /* {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                }
            },
            .jmp => {
                const id: u32 = switch (base.operands[1]) {
                    .label => |v| v,
                    .symbol => |v| v,
                    else => return CEmitError.InvalidOperand,
                };
                try writer.print("  goto SA_L_{d};\n", .{id});
            },
            .br => {
                const t: u32 = switch (base.operands[1]) {
                    .label => |v| v,
                    .symbol => |v| v,
                    else => return CEmitError.InvalidOperand,
                };
                const f: u32 = switch (base.operands[3]) {
                    .label => |v| v,
                    .symbol => |v| v,
                    else => return CEmitError.InvalidOperand,
                };
                if (t == f) {
                    try writer.print("  goto SA_L_{d};\n", .{t});
                    continue;
                }
                try writer.writeAll("  if (sa_truthy(");
                try resolveValueToC(writer, verified.symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.print(")) goto SA_L_{d}; else goto SA_L_{d};\n", .{ t, f });
            },
            .br_null => {
                const t: u32 = switch (base.operands[1]) {
                    .label => |v| v,
                    .symbol => |v| v,
                    else => return CEmitError.InvalidOperand,
                };
                const f: u32 = switch (base.operands[3]) {
                    .label => |v| v,
                    .symbol => |v| v,
                    else => return CEmitError.InvalidOperand,
                };
                if (t == f) {
                    try writer.print("  goto SA_L_{d};\n", .{t});
                    continue;
                }
                try writer.writeAll("  if ((");
                try resolveValueToC(writer, verified.symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.print(") == 0) goto SA_L_{d}; else goto SA_L_{d};\n", .{ t, f });
            },
            else => {
                if (c_opt.debug_comments) {
                    try writer.print("  /* {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                }
                try provCUpdate(&bases, allocator, verified.symbols, fsig, use_global, base);
                if (tf) |tc| {
                    if (base.kind == .call or base.kind == .call_indirect) {
                        try emitTfCall(writer, allocator, verified, fsig, use_global, const_addrs, fn_idx, base, &widths, sigmap, uniform_arity, indirect_ret_width, &dead, &bases, tc);
                    } else if (base.kind == .return_) {
                        try emitTfReturn(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, base, &widths);
                    } else {
                        try emitLinearInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, base, &widths, sigmap, uniform_arity, indirect_ret_width, &dead, &bases);
                    }
                } else {
                    try emitLinearInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, base, &widths, sigmap, uniform_arity, indirect_ret_width, &dead, &bases);
                }
            },
        }
    }
    if (tf) |tc| {
        // Fallthrough completion: wait for any outstanding spawns
        // (tail suspension point), then complete with the zero value.
        if (tf_tail) |ts| try emitTfSyncBlock(writer, tf_declared.items, ts);
        try writer.writeAll("  sa_tf_complete(fr, 0);\n  return;\n}\n");
        try emitTfWrapper(writer, fsig, tc, uniform_arity);
    } else if (fsig.return_ty == .void and !fsig.return_fallible) {
        // default return for fallthrough
        try writer.writeAll("  return 0;\n}\n");
    } else {
        try writer.writeAll("  return 0;\n}\n");
    }
}
