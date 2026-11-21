const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const call = @import("../referee/call.zig");
const cap = @import("../common/capability.zig");
const atomic = @import("../common/atomic.zig");
const gas = @import("../common/gas.zig");
const const_decl = @import("../common/const_decl.zig");
const inst = @import("../common/instruction.zig");
const pkg_manifest = @import("../pkg/manifest.zig");
const sig = @import("../common/signature.zig");
const trap = @import("../common/trap.zig");
const upstream = @import("../common/upstream_loc.zig");
const classifier = @import("../flattener/line_classifier.zig");
const symbol = @import("../flattener/symbol.zig");

const CallProvenance = @import("reg_state_change.zig").CallProvenance;
const ConstVTable = @import("reg_state_change.zig").ConstVTable;
const ConstVTableSlot = @import("reg_state_change.zig").ConstVTableSlot;
const FunctionRegScope = @import("reg_state_change.zig").FunctionRegScope;
const LabelSnapshot = @import("reg_state_change.zig").LabelSnapshot;
const LabelStateChange = @import("reg_state_change.zig").LabelStateChange;
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const maskOf = @import("reg_state_change.zig").maskOf;
const regFlagImmutable = @import("reg_state_change.zig").regFlagImmutable;
const trapReport = @import("snapshot_merge_state_in_scope.zig").trapReport;

pub fn constTrap(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    register: []const u8,
    actual_mask: u16,
    message: []const u8,
) VerifyBodyResult {
    return trapReport(.const_mutation, item, function_text, is_ffi_wrapper, register, maskOf(.immutable), actual_mask, message, null);
}

/// Inverted seeding (OPTIMIZE-IMPL-1, step 2): the old loop visited EVERY
/// const for EVERY function (O(F x C) findId + slotOf), which became the
/// dominant residual quadratic once scopes went demand-driven. The scope
/// already contains exactly the consts the function references, and
/// reg_ids is slot-ordered, so iterate the scope and test membership.
pub fn seedConstSymbols(
    state: []u16,
    flags: []u8,
    scope: *const FunctionRegScope,
    const_ids: *const std.AutoHashMap(u32, void),
) void {
    for (scope.reg_ids, 0..) |id, idx| {
        if (!const_ids.contains(id)) continue;
        state[idx] = maskOf(.active) | maskOf(.immutable);
        flags[idx] |= regFlagImmutable;
    }
}

pub fn isDecl(kind: inst.InstKind) bool {
    return switch (kind) {
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => true,
        else => false,
    };
}

pub fn isTerminator(kind: inst.InstKind) bool {
    return switch (kind) {
        .jmp, .br, .br_null, .early_return, .return_, .panic, .panic_msg => true,
        else => false,
    };
}

pub fn isExecKind(kind: inst.InstKind) bool {
    return switch (kind) {
        .alloc, .stack_alloc, .load, .store, .atomic_load, .atomic_store, .cmpxchg, .atomic_rmw, .fence, .borrow, .move_, .release, .assign, .op, .ptr_add, .jmp, .br, .br_null, .call, .call_indirect, .try_, .early_return, .panic, .panic_msg, .return_, .take, .raw_cast, .assume_safe, .assume_borrow, .native, .va_start, .va_arg, .va_end, .transfer => true,
        else => false,
    };
}

pub fn isConstDeclText(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    return std.mem.startsWith(u8, trimmed, "@const ");
}

pub fn parseConstDeclName(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    if (!std.mem.startsWith(u8, trimmed, "@const ")) return null;
    const after = std.mem.trimStart(u8, trimmed["@const ".len..], " \t\r");
    const eq = std.mem.indexOfScalar(u8, after, '=') orelse return null;
    const name = std.mem.trim(u8, after[0..eq], " \t\r");
    if (name.len == 0) return null;
    return name;
}

pub fn parseVtableSlotName(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    if (!std.mem.startsWith(u8, trimmed, "vtable {")) return null;
    const open = std.mem.indexOfScalar(u8, trimmed, '{') orelse return null;
    const close = std.mem.lastIndexOfScalar(u8, trimmed, '}') orelse return null;
    if (close <= open) return null;
    const body = std.mem.trim(u8, trimmed[open + 1 .. close], " \t\r");
    const eq = std.mem.indexOfScalar(u8, body, '=') orelse return null;
    const slot = std.mem.trim(u8, body[0..eq], " \t\r");
    if (slot.len == 0) return null;
    return slot;
}

/// LINE-OPT-VERIFY-MERGE (metadata adjacency index): vtable slots used to
/// resolve their function by a LINEAR scan over all sigs -- O(V x F), and
/// the slot names share the "sla__f" prefix so each comparison walks most
/// of the name. The caller already owns sig_index_by_name (first index
/// per name, same first-match semantics as the scan), so resolve in O(1).
pub fn parseVtableSlots(allocator: std.mem.Allocator, literal: const_decl.VTableLiteral, sigs: []const sig.FunctionSig, sig_index_by_name: *const std.StringHashMap(usize)) ![]ConstVTableSlot {
    var slots = std.array_list.Managed(ConstVTableSlot).init(allocator);
    errdefer slots.deinit();
    for (literal.slots) |slot| {
        const sig_idx = sig_index_by_name.get(slot.func_name) orelse return error.UnknownRegister;
        const resolved = sigs[sig_idx];
        try slots.append(.{
            .slot_name = slot.name,
            .function_name = slot.func_name,
            .signature = resolved,
        });
    }
    return try slots.toOwnedSlice();
}

pub fn collectConstVtables(
    allocator: std.mem.Allocator,
    const_decls: []const const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
    sig_index_by_name: *const std.StringHashMap(usize),
) !std.array_list.Managed(ConstVTable) {
    var out = std.array_list.Managed(ConstVTable).init(allocator);
    errdefer {
        for (out.items) |*item| item.deinit(allocator);
        out.deinit();
    }

    for (const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                const name_copy = try allocator.dupe(u8, decl.name);
                errdefer allocator.free(name_copy);
                const slots = try parseVtableSlots(allocator, literal, sigs, sig_index_by_name);
                try out.append(.{
                    .name = name_copy,
                    .slots = slots,
                });
            },
            else => {},
        }
    }
    return out;
}

pub fn findConstVtableByName(const_vtables: []const ConstVTable, name: []const u8) ?ConstVTable {
    for (const_vtables) |item| {
        if (std.mem.eql(u8, item.name, name)) return item;
    }
    return null;
}

pub fn parseCallProvenance(
    item: inst.Instruction,
    parsed: call.ParsedCall,
    symbols: *const symbol.SymbolTable,
    state: []const u16,
    const_vtables: []const ConstVTable,
    origins: []?u32,
    const_reg_names: []const ?[]const u8,
) ?CallProvenance {
    _ = item;
    if (!parsed.is_indirect) return null;
    const callee_id = symbols.findId(parsed.callee) orelse return null;
    const callee_idx: usize = @intCast(callee_id);
    const callee_mask = state[callee_idx];
    if ((callee_mask & maskOf(.untracked)) != 0) return null;

    const candidate_const_name = if (const_reg_names[callee_idx]) |name| name else blk: {
        if (origins[callee_idx]) |origin_id| {
            const origin_idx: usize = @intCast(origin_id);
            break :blk const_reg_names[origin_idx] orelse return null;
        }
        break :blk null;
    } orelse return null;

    const vt = findConstVtableByName(const_vtables, candidate_const_name) orelse return null;
    const slot_name = parsed.callee;
    for (vt.slots) |slot| {
        if (std.mem.eql(u8, slot.function_name, slot_name) or std.mem.eql(u8, slot.slot_name, slot_name)) {
            return .{
                .callee_name = parsed.callee,
                .is_vtable_slot = true,
                .vtable_name = vt.name,
                .slot_name = slot.slot_name,
                .slot_signature = slot.signature,
                .const_name = candidate_const_name,
            };
        }
    }
    return .{
        .callee_name = parsed.callee,
        .is_vtable_slot = true,
        .vtable_name = vt.name,
        .slot_name = parsed.callee,
        .slot_signature = null,
        .const_name = candidate_const_name,
    };
}

pub fn atomicKey(inst_: inst.Instruction) ?u64 {
    return switch (inst_.kind) {
        .cmpxchg => (@as(u64, inst_.operands[2].reg) << 32) | @as(u64, inst_.operands[3].imm_u64),
        .atomic_rmw => (@as(u64, inst_.operands[1].reg) << 32) | @as(u64, inst_.operands[2].imm_u64),
        else => null,
    };
}

pub fn atomicOrderingOf(inst_: inst.Instruction) atomic.AtomicOrdering {
    return switch (inst_.kind) {
        .cmpxchg => inst_.atomic_ordering orelse .seq_cst,
        .atomic_rmw => inst_.atomic_ordering orelse .seq_cst,
        else => .seq_cst,
    };
}

pub fn atomicSeenBit(ordering: atomic.AtomicOrdering) u8 {
    return switch (ordering) {
        .relaxed => 0x01,
        .acquire => 0x02,
        .release => 0x04,
        .acq_rel => 0x08,
        .seq_cst => 0x10,
    };
}

pub fn checkAtomicOrdering(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    seen: *std.AutoHashMap(u64, u8),
) ?VerifyBodyResult {
    const key = atomicKey(item) orelse return null;
    const ordering = atomicOrderingOf(item);
    const current = seen.get(key) orelse 0;
    for ([_]atomic.AtomicOrdering{ .relaxed, .acquire, .release, .acq_rel, .seq_cst }) |prev| {
        const bit = atomicSeenBit(prev);
        if ((current & bit) == 0) continue;
        if (!atomic.sameAddressRmwCompatible(prev, ordering)) {
            return trapReport(.atomic_ordering_mismatch, item, function_text, is_ffi_wrapper, null, null, null, "same-address RMW ordering combination is not allowed", null);
        }
    }
    seen.put(key, current | atomicSeenBit(ordering)) catch {
        return trapReport(.arena_oom, item, function_text, is_ffi_wrapper, null, null, null, "unable to record atomic ordering history", null);
    };
    return null;
}

pub fn hasInteriorPtr(mask: u16) bool {
    return (mask & maskOf(.interior_ptr)) != 0;
}

pub fn hasInteriorTree(state: []const u16, interior_first_child: []const ?u32, id: u32) bool {
    const idx: usize = @intCast(id);
    return hasInteriorPtr(state[idx]) or interior_first_child[idx] != null;
}

pub fn hasActiveBorrowRefs(locks: []const u16, id: u32) bool {
    const idx: usize = @intCast(id);
    if (locks[idx] != 0) return true;
    return false;
}

pub fn statesCompatibleForJoin(lhs: []const u16, rhs: []const u16) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |left, right| {
        if (left == right) continue;
        if ((left == 0 and right == maskOf(.consumed)) or (right == 0 and left == maskOf(.consumed))) continue;
        return false;
    }
    return true;
}

pub const StateMismatch = struct {
    name: []const u8,
    expected: u16,
    actual: u16,
};

pub fn firstStateMismatch(lhs: []const u16, rhs: []const u16, symbols: *const symbol.SymbolTable) ?StateMismatch {
    if (lhs.len != rhs.len) return null;
    for (lhs, rhs, 0..) |left, right, idx| {
        if (left == right) continue;
        if ((left == 0 and right == maskOf(.consumed)) or (right == 0 and left == maskOf(.consumed))) continue;
        const name = symbols.lookupName(@intCast(idx)) orelse continue;
        return .{
            .name = name,
            .expected = right,
            .actual = left,
        };
    }
    return null;
}

pub fn mergeJoinMask(left: u16, right: u16) ?u16 {
    if (left == right) return left;
    if ((left == 0 and right == maskOf(.consumed)) or (right == 0 and left == maskOf(.consumed))) {
        return maskOf(.consumed);
    }

    // PATCH: Allow Active ↔ Uninitialized merging (similar to Consumed ↔ Uninitialized)
    // This fixes SLA PhiStateConflict in while loops and if-without-else patterns
    const active_mask = maskOf(.active);
    if ((left == 0 and right == active_mask) or (right == 0 and left == active_mask)) {
        return 0; // Merge to Uninitialized (safe: uninit is the conservative state)
    }

    // PATCH 1b: Allow (Active|BorrowView) ↔ Uninitialized merging.
    // A borrow created on one if/else branch but not the other merges to
    // Uninitialized (the borrow is dead on the merged path). This mirrors
    // the Active ↔ Uninitialized patch above.
    const borrow_active_mask = maskOf(.active) | maskOf(.borrow_view);
    if ((left == 0 and right == borrow_active_mask) or (right == 0 and left == borrow_active_mask)) {
        return 0;
    }

    // PATCH 2: Allow Active ↔ Untracked merging for primitive types
    // Untracked is used for non-affine types (int, float, bool)
    const untracked_mask = maskOf(.untracked);
    if ((left == active_mask and right == untracked_mask) or (right == active_mask and left == untracked_mask)) {
        return untracked_mask;  // Merge to Untracked (safe: untracked types don't need tracking)
    }

    // PATCH 3: Allow Untracked ↔ Uninitialized merging for primitive types
    if ((left == 0 and right == untracked_mask) or (right == 0 and left == untracked_mask)) {
        return untracked_mask;
    }

    const merged = left & right;
    const core_mask = maskOf(.active) | maskOf(.locked_read) | maskOf(.locked_mut) | maskOf(.consumed) | maskOf(.untracked) | maskOf(.fallible) | maskOf(.immutable) | maskOf(.interior_ptr);
    if ((merged & core_mask) == 0) return null;
    return merged;
}

pub fn mergeJoinStates(dst: []u16, src: []const u16) bool {
    if (dst.len != src.len) return false;
    for (dst, src) |*left, right| {
        left.* = mergeJoinMask(left.*, right) orelse return false;
    }
    return true;
}

pub fn captureLabelSnapshot(
    allocator: std.mem.Allocator,
    state: []const u16,
    origins: []const ?u32,
    locks: []const u16,
    flags: []const u8,
    interior_parent: []const ?u32,
    interior_first_child: []const ?u32,
    interior_next_sibling: []const ?u32,
    interior_root: []const ?u32,
    interior_offset: []const u64,
    interior_offset_known: []const bool,
    alloc_size: []const u64,
    alloc_size_known: []const bool,
) !LabelSnapshot {
    var changes = std.array_list.Managed(LabelStateChange).init(allocator);
    errdefer changes.deinit();

    for (state, 0..) |mask, idx| {
        const origin = origins[idx];
        const lock = locks[idx];
        const flag = flags[idx];
        const parent = interior_parent[idx];
        const first_child = interior_first_child[idx];
        const next_sibling = interior_next_sibling[idx];
        const root = interior_root[idx];
        const offset_known = interior_offset_known[idx];
        const size_known = alloc_size_known[idx];
        const changed = mask != 0 or origin != null or lock != 0 or flag != 0 or parent != null or first_child != null or next_sibling != null or root != null or offset_known or size_known;
        if (!changed) continue;
        try changes.append(.{
            .reg = @intCast(idx),
            .state = if (mask != 0) mask else null,
            .origins = origin,
            .locks = if (lock != 0) lock else null,
            .flags = if (flag != 0) flag else null,
            .interior_parent = parent,
            .interior_first_child = first_child,
            .interior_next_sibling = next_sibling,
            .interior_root = root,
            .interior_offset = if (offset_known) interior_offset[idx] else null,
            .interior_offset_known = if (offset_known) true else null,
            .alloc_size = if (size_known) alloc_size[idx] else null,
            .alloc_size_known = if (size_known) true else null,
        });
    }

    return .{ .changes = try changes.toOwnedSlice() };
}

pub fn restoreLabelSnapshot(
    snapshot: *const LabelSnapshot,
    state: []u16,
    origins: []?u32,
    locks: []u16,
    flags: []u8,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    interior_root: []?u32,
    interior_offset: []u64,
    interior_offset_known: []bool,
    alloc_size: []u64,
    alloc_size_known: []bool,
) void {
    @memset(state, 0);
    @memset(origins, null);
    @memset(locks, 0);
    @memset(flags, 0);
    @memset(interior_parent, null);
    @memset(interior_first_child, null);
    @memset(interior_next_sibling, null);
    @memset(interior_root, null);
    @memset(interior_offset, 0);
    @memset(interior_offset_known, false);
    @memset(alloc_size, 0);
    @memset(alloc_size_known, false);

    for (snapshot.changes) |change| {
        const idx: usize = @intCast(change.reg);
        if (change.state) |value| state[idx] = value;
        if (change.origins) |value| origins[idx] = value;
        if (change.locks) |value| locks[idx] = value;
        if (change.flags) |value| flags[idx] = value;
        if (change.interior_parent) |value| interior_parent[idx] = value;
        if (change.interior_first_child) |value| interior_first_child[idx] = value;
        if (change.interior_next_sibling) |value| interior_next_sibling[idx] = value;
        if (change.interior_root) |value| interior_root[idx] = value;
        if (change.interior_offset) |value| interior_offset[idx] = value;
        if (change.interior_offset_known) |value| interior_offset_known[idx] = value;
        if (change.alloc_size) |value| alloc_size[idx] = value;
        if (change.alloc_size_known) |value| alloc_size_known[idx] = value;
    }
}

pub fn snapshotChangeFor(snapshot: *const LabelSnapshot, reg: u32) ?LabelStateChange {
    for (snapshot.changes) |change| {
        if (change.reg == reg) return change;
    }
    return null;
}

pub fn snapshotStateAt(snapshot: *const LabelSnapshot, reg: u32) u16 {
    return snapshotChangeFor(snapshot, reg) orelse .{ .reg = reg };
}

pub fn snapshotMaskAt(snapshot: *const LabelSnapshot, reg: u32) u16 {
    const change = snapshotChangeFor(snapshot, reg) orelse return 0;
    return change.state orelse 0;
}

pub fn snapshotStatesCompatible(snapshot: *const LabelSnapshot, state: []const u16) bool {
    const active_mask: u16 = 0x01;      // maskOf(.active)
    const untracked_mask: u16 = 0x40;   // maskOf(.untracked)
    const consumed_mask: u16 = 0x08;    // maskOf(.consumed)

    for (state, 0..) |mask, idx| {
        const snap_mask = snapshotMaskAt(snapshot, @intCast(idx));
        if (snap_mask == mask) continue;

        // Allow Uninitialized ↔ Consumed
        if ((snap_mask == 0 and mask == consumed_mask) or (mask == 0 and snap_mask == consumed_mask)) continue;
        if ((snap_mask == consumed_mask and mask == 0) or (mask == consumed_mask and snap_mask == 0)) continue;

        // PATCH: Allow Active ↔ Uninitialized
        if ((snap_mask == 0 and mask == active_mask) or (mask == 0 and snap_mask == active_mask)) continue;

        // PATCH: Allow (Active|BorrowView) ↔ Uninitialized (while-loop back-edge
        // with a borrow created inside the loop but not at entry).
        const borrow_active_mask: u16 = 0x01 | 0x10; // active | borrow_view
        if ((snap_mask == 0 and mask == borrow_active_mask) or (mask == 0 and snap_mask == borrow_active_mask)) continue;

        // PATCH: Allow Active (0x01) ↔ Untracked (0x40)
        if (snap_mask == active_mask and mask == untracked_mask) continue;
        if (mask == active_mask and snap_mask == untracked_mask) continue;

        // PATCH: Allow Untracked (0x40) ↔ Uninitialized (0)
        if ((snap_mask == 0 and mask == untracked_mask) or (mask == 0 and snap_mask == untracked_mask)) continue;

        return false;
    }
    return true;
}

pub fn snapshotMergeCompatible(snapshot: *const LabelSnapshot, state: []const u16) bool {
    if (snapshot.changes.len == 0) return state.len == 0;
    for (snapshot.changes) |change| {
        const idx: usize = @intCast(change.reg);
        if (idx >= state.len) return false;
        if (mergeJoinMask(change.state orelse 0, state[idx]) == null) return false;
    }
    return true;
}

pub fn snapshotFirstMismatch(snapshot: *const LabelSnapshot, state: []const u16, symbols: *const symbol.SymbolTable) ?StateMismatch {
    for (state, 0..) |mask, idx| {
        const snap_mask = snapshotMaskAt(snapshot, @intCast(idx));
        if (snap_mask == mask) continue;
        if ((snap_mask == 0 and mask == maskOf(.consumed)) or (mask == 0 and snap_mask == maskOf(.consumed))) continue;
        if ((snap_mask == maskOf(.consumed) and mask == 0) or (mask == maskOf(.consumed) and snap_mask == 0)) continue;

        // PATCH: Allow Active ↔ Uninitialized
        const active_mask = maskOf(.active);
        if ((snap_mask == 0 and mask == active_mask) or (mask == 0 and snap_mask == active_mask)) continue;

        // PATCH: Allow (Active|BorrowView) ↔ Uninitialized (while-loop back-edge
        // with a borrow created inside the loop but not at entry).
        const borrow_active_mask = maskOf(.active) | maskOf(.borrow_view);
        if ((snap_mask == 0 and mask == borrow_active_mask) or (mask == 0 and snap_mask == borrow_active_mask)) continue;

        // PATCH: Allow Active ↔ Untracked
        const untracked_mask = maskOf(.untracked);
        if ((snap_mask == active_mask and mask == untracked_mask) or (mask == active_mask and snap_mask == untracked_mask)) continue;

        // PATCH: Allow Untracked ↔ Uninitialized
        if ((snap_mask == 0 and mask == untracked_mask) or (mask == 0 and snap_mask == untracked_mask)) continue;

        // PATCH: Allow Untracked ↔ Uninitialized
        if ((snap_mask == 0 and mask == untracked_mask) or (mask == 0 and snap_mask == untracked_mask)) continue;

        const name = symbols.lookupName(@intCast(idx)) orelse continue;
        return .{ .name = name, .expected = mask, .actual = snap_mask };
    }
    return null;
}

pub fn snapshotFirstMismatchInScope(snapshot: *const LabelSnapshot, state: []const u16, scope: *const FunctionRegScope, symbols: *const symbol.SymbolTable) ?StateMismatch {
    for (state, 0..) |mask, idx| {
        const snap_mask = snapshotMaskAt(snapshot, @intCast(idx));
        if (snap_mask == mask) continue;
        if ((snap_mask == 0 and mask == maskOf(.consumed)) or (mask == 0 and snap_mask == maskOf(.consumed))) continue;
        if ((snap_mask == maskOf(.consumed) and mask == 0) or (mask == maskOf(.consumed) and snap_mask == 0)) continue;

        // PATCH: Allow Active ↔ Uninitialized
        const active_mask = maskOf(.active);
        if ((snap_mask == 0 and mask == active_mask) or (mask == 0 and snap_mask == active_mask)) continue;

        // PATCH: Allow (Active|BorrowView) ↔ Uninitialized (while-loop back-edge
        // with a borrow created inside the loop but not at entry).
        const borrow_active_mask = maskOf(.active) | maskOf(.borrow_view);
        if ((snap_mask == 0 and mask == borrow_active_mask) or (mask == 0 and snap_mask == borrow_active_mask)) continue;

        // PATCH: Allow Active ↔ Untracked
        const untracked_mask = maskOf(.untracked);
        if ((snap_mask == active_mask and mask == untracked_mask) or (mask == active_mask and snap_mask == untracked_mask)) continue;

        // PATCH: Allow Untracked ↔ Uninitialized
        if ((snap_mask == 0 and mask == untracked_mask) or (mask == 0 and snap_mask == untracked_mask)) continue;

        // PATCH: Allow Untracked ↔ Uninitialized
        if ((snap_mask == 0 and mask == untracked_mask) or (mask == 0 and snap_mask == untracked_mask)) continue;

        const name = scope.nameOf(symbols, @intCast(idx)) orelse symbols.lookupName(@intCast(idx)) orelse continue;
        return .{ .name = name, .expected = mask, .actual = snap_mask };
    }
    return null;
}

pub fn replaceLabelStateSnapshot(
    allocator: std.mem.Allocator,
    snapshot: *LabelSnapshot,
    state: []const u16,
    origins: []const ?u32,
    locks: []const u16,
    flags: []const u8,
    interior_parent: []const ?u32,
    interior_first_child: []const ?u32,
    interior_next_sibling: []const ?u32,
) !void {
    _ = origins;
    _ = locks;
    _ = flags;
    _ = interior_parent;
    _ = interior_first_child;
    _ = interior_next_sibling;
    var changes = std.array_list.Managed(LabelStateChange).init(allocator);
    errdefer changes.deinit();

    for (state, 0..) |mask, idx| {
        const existing = snapshotChangeFor(snapshot, @intCast(idx));
        const prev = existing.?.state orelse 0;
        const merged = mergeJoinMask(prev, mask) orelse return error.InvalidJoinState;
        const meta = existing orelse .{ .reg = @as(u32, @intCast(idx)) };
        const have_meta = meta.origins != null or meta.locks != null or meta.flags != null or meta.interior_parent != null or meta.interior_first_child != null or meta.interior_next_sibling != null;
        if (merged == 0 and !have_meta) continue;
        try changes.append(.{
            .reg = @intCast(idx),
            .state = if (merged != 0) merged else null,
            .origins = meta.origins,
            .locks = meta.locks,
            .flags = meta.flags,
            .interior_parent = meta.interior_parent,
            .interior_first_child = meta.interior_first_child,
            .interior_next_sibling = meta.interior_next_sibling,
        });
    }

    snapshot.deinit(allocator);
    snapshot.* = .{ .changes = try changes.toOwnedSlice() };
}

pub fn snapshotMergeState(snapshot: *const LabelSnapshot, state: []const u16, symbols: *const symbol.SymbolTable) ?StateMismatch {
    for (state, 0..) |mask, idx| {
        const snap_mask = snapshotMaskAt(snapshot, @intCast(idx));
        if (snap_mask == mask) continue;
        if (mergeJoinMask(snap_mask, mask) != null) continue;
        const name = symbols.lookupName(@intCast(idx)) orelse continue;
        return .{ .name = name, .expected = mask, .actual = snap_mask };
    }
    return null;
}
