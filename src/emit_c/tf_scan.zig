const std = @import("std");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const FuncTask = @import("types.zig").FuncTask;
const TF_PROV_ANY = @import("types.zig").TF_PROV_ANY;
const TfProgram = @import("types.zig").TfProgram;
const collectDefUse = @import("dead_slots.zig").collectDefUse;
const readSlotOf = @import("dead_slots.zig").readSlotOf;
const sigNormName = @import("ident.zig").sigNormName;
const taskIndexByName = @import("ident.zig").taskIndexByName;
const taskUsesGlobalRegIds = @import("ident.zig").taskUsesGlobalRegIds;

pub fn tfTaskOf(tasks: []FuncTask, fsig_index: usize) ?FuncTask {
    for (tasks) |t| {
        if (t.fsig_index == fsig_index) return t;
    }
    return null;
}


pub fn tfMarkStore(prog: *TfProgram, fid: usize, p: u32) bool {
    if (p == TF_PROV_ANY) {
        var flipped = false;
        for (prog.may_store[fid]) |*b| {
            if (!b.*) {
                b.* = true;
                flipped = true;
            }
        }
        return flipped;
    }
    if (!prog.may_store[fid][p]) {
        prog.may_store[fid][p] = true;
        return true;
    }
    return false;
}


// One may-store summary pass over a single task-formed function.
// Returns true when any summary bit flipped (fixpoint driver).
pub fn tfScanMayStore(allocator: std.mem.Allocator, verified: anytype, tasks: []FuncTask, fidx: usize, prog: *TfProgram) !bool {
    const fsig = verified.function_sigs[fidx];
    const task = tfTaskOf(tasks, fidx) orelse return false;
    const use_global = taskUsesGlobalRegIds(fsig, verified, task);
    const my_fid = prog.fnid_of_fsig.get(fidx).?;
    // Pointer provenance: slot -> param index (or TF_PROV_ANY). Over-
    // approximates the set of parameters a pointer value may alias.
    var prov = std.AutoHashMap(u32, u32).init(allocator);
    defer prov.deinit();
    for (fsig.param_ids, 0..) |pid, pi| {
        if (pi >= fsig.params.len) break;
        if (fsig.slotOf(pid)) |slot| try prov.put(slot, @intCast(pi));
    }
    var defs = std.array_list.Managed(u32).init(allocator);
    defer defs.deinit();
    var uses = std.array_list.Managed(u32).init(allocator);
    defer uses.deinit();
    var flipped = false;
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        defs.clearRetainingCapacity();
        uses.clearRetainingCapacity();
        collectDefUse(allocator, verified, fsig, use_global, base, &defs, &uses) catch continue;
        switch (base.kind) {
            .store, .atomic_store, .atomic_rmw, .cmpxchg => {
                // Write-through: the address base is operands[0].
                if (base.operands.len > 0) {
                    if (readSlotOf(fsig, use_global, verified, base.operands[0])) |bs| {
                        if (prov.get(bs)) |p| {
                            if (tfMarkStore(prog, my_fid, p)) flipped = true;
                        }
                    }
                }
            },
            .call => {
                if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                    var parsed = pc.*;
                    defer parsed.deinit(allocator);
                    if (!parsed.is_indirect) {
                        if (prog.fnid_by_name.get(sigNormName(parsed.callee))) |cfid| {
                            const cfsig = verified.function_sigs[prog.fsig_of_fnid[cfid]];
                            const lim = @min(parsed.args.len, cfsig.params.len);
                            for (parsed.args[0..lim], 0..) |arg, j| {
                                if (!prog.may_store[cfid][j]) continue;
                                const aname = std.mem.trim(u8, arg.text, " \t");
                                if (verified.symbols.findId(aname)) |aid| {
                                    if (fsig.slotOf(aid)) |aslot| {
                                        if (prov.get(aslot)) |p| {
                                            if (tfMarkStore(prog, my_fid, p)) flipped = true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else |_| {}
            },
            else => {},
        }
        // Provenance flow into the defined slot(s).
        if (defs.items.len == 1) {
            const dest = defs.items[0];
            var newp: ?u32 = null;
            switch (base.kind) {
                // A loaded value may itself be a chased pointer.
                .load, .take, .atomic_load => newp = TF_PROV_ANY,
                else => {
                    var seen_p: ?u32 = null;
                    var multi = false;
                    for (uses.items) |us| {
                        if (prov.get(us)) |p| {
                            if (seen_p == null) {
                                seen_p = p;
                            } else if (seen_p.? != p) {
                                multi = true;
                            }
                        }
                    }
                    if (multi) {
                        newp = TF_PROV_ANY;
                    } else if (seen_p) |p| {
                        newp = p;
                    }
                },
            }
            if (newp) |p| {
                try prov.put(dest, p);
            } else {
                _ = prov.remove(dest);
            }
        } else {
            for (defs.items) |d| _ = prov.remove(d);
        }
    }
    return flipped;
}

pub fn buildTfProgram(allocator: std.mem.Allocator, verified: anytype, tasks: []FuncTask, reachable: *const std.AutoHashMap(usize, void)) !TfProgram {
    var prog = TfProgram{
        .fnid_of_fsig = std.AutoHashMap(usize, u32).init(allocator),
        .fnid_by_name = std.StringHashMap(u32).init(allocator),
    };
    // Candidate set G: reachable @gpu definitions with a body.
    var gset = std.AutoHashMap(usize, void).init(allocator);
    defer gset.deinit();
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        if (reachable.get(task.fsig_index) == null) continue;
        const fs = verified.function_sigs[task.fsig_index];
        if (fs.kind != .gpu) continue;
        if (task.end_idx <= task.start_idx + 1) continue;
        try gset.put(task.fsig_index, {});
    }
    if (gset.count() == 0) return prog;
    // Direct-call edges within G.
    var edges = std.AutoHashMap(usize, std.array_list.Managed(usize)).init(allocator);
    defer {
        var eit = edges.iterator();
        while (eit.next()) |e| e.value_ptr.deinit();
        edges.deinit();
    }
    {
        var git = gset.iterator();
        while (git.next()) |e| {
            const src = e.key_ptr.*;
            const task = tfTaskOf(tasks, src).?;
            var list = std.array_list.Managed(usize).init(allocator);
            var i: usize = task.start_idx + 1;
            while (i < task.end_idx) : (i += 1) {
                const base = verified.annotated[i].base;
                if (base.kind != .call) continue;
                if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                    var parsed = pc.*;
                    defer parsed.deinit(allocator);
                    if (parsed.is_indirect) continue;
                    if (taskIndexByName(tasks, verified, sigNormName(parsed.callee))) |ci| {
                        if (gset.get(ci) != null) try list.append(ci);
                    }
                } else |_| {}
            }
            try edges.put(src, list);
        }
    }
    // Cyclic nodes: v with a path v ->+ v.
    var cyclic = std.AutoHashMap(usize, void).init(allocator);
    defer cyclic.deinit();
    {
        var git = gset.iterator();
        while (git.next()) |e| {
            const v = e.key_ptr.*;
            var seen = std.AutoHashMap(usize, void).init(allocator);
            defer seen.deinit();
            var stack = std.array_list.Managed(usize).init(allocator);
            defer stack.deinit();
            if (edges.get(v)) |lst| {
                for (lst.items) |w| try stack.append(w);
            }
            while (stack.items.len > 0) {
                const x = stack.pop() orelse break;
                if (x == v) {
                    try cyclic.put(v, {});
                    break;
                }
                if (seen.get(x) != null) continue;
                try seen.put(x, {});
                if (edges.get(x)) |lst| {
                    for (lst.items) |w| try stack.append(w);
                }
            }
        }
    }
    if (cyclic.count() == 0) return prog;
    // T = downward closure of the cyclic nodes over call edges.
    var tset = std.AutoHashMap(usize, void).init(allocator);
    defer tset.deinit();
    {
        var stack = std.array_list.Managed(usize).init(allocator);
        defer stack.deinit();
        var cit = cyclic.iterator();
        while (cit.next()) |e| try stack.append(e.key_ptr.*);
        while (stack.items.len > 0) {
            const x = stack.pop() orelse break;
            if (tset.get(x) != null) continue;
            try tset.put(x, {});
            if (edges.get(x)) |lst| {
                for (lst.items) |w| try stack.append(w);
            }
        }
    }
    // fnids in task order: deterministic emission.
    var fsigs = std.array_list.Managed(usize).init(allocator);
    defer fsigs.deinit();
    for (tasks) |task| {
        if (tset.get(task.fsig_index) == null) continue;
        if (prog.fnid_of_fsig.get(task.fsig_index) != null) continue;
        const fid: u32 = @intCast(fsigs.items.len);
        try prog.fnid_of_fsig.put(task.fsig_index, fid);
        try fsigs.append(task.fsig_index);
        try prog.fnid_by_name.put(sigNormName(verified.function_sigs[task.fsig_index].name), fid);
    }
    prog.fsig_of_fnid = try fsigs.toOwnedSlice();
    // May-store-through-parameter summaries over T (fixpoint).
    const n = prog.fsig_of_fnid.len;
    prog.may_store = try allocator.alloc([]bool, n);
    prog.may_store_any = try allocator.alloc(bool, n);
    for (prog.fsig_of_fnid, 0..) |fidx, fid| {
        const np = verified.function_sigs[fidx].params.len;
        prog.may_store[fid] = try allocator.alloc(bool, np);
        @memset(prog.may_store[fid], false);
        prog.may_store_any[fid] = false;
    }
    var changed = true;
    var rounds: usize = 0;
    while (changed and rounds < 4096) : (rounds += 1) {
        changed = false;
        for (prog.fsig_of_fnid, 0..) |fidx, fid| {
            _ = fid;
            if (try tfScanMayStore(allocator, verified, tasks, fidx, &prog)) changed = true;
        }
    }
    if (changed) {
        // Fixpoint cap exhausted (not expected: every round flips at
        // least one bit of a finite lattice). Degrade to the sound
        // over-approximation: everything may store.
        for (prog.may_store) |row| @memset(row, true);
    }
    for (prog.may_store, 0..) |row, fid| {
        for (row) |b| {
            if (b) {
                prog.may_store_any[fid] = true;
                break;
            }
        }
    }
    return prog;
}
