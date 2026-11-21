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

const AnnotatedInstruction = @import("reg_state_change.zig").AnnotatedInstruction;
const CollectResult = @import("reg_state_change.zig").CollectResult;
const ConstVTable = @import("reg_state_change.zig").ConstVTable;
const FunctionRegScope = @import("reg_state_change.zig").FunctionRegScope;
const InteriorContext = @import("reg_state_change.zig").InteriorContext;
const LabelSnapshot = @import("reg_state_change.zig").LabelSnapshot;
const RegStateChange = @import("reg_state_change.zig").RegStateChange;
const RegStateDelta = @import("reg_state_change.zig").RegStateDelta;
const SaxValidationContext = @import("reg_state_change.zig").SaxValidationContext;
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const captureLabelSnapshot = @import("const_trap.zig").captureLabelSnapshot;
const consumeInteriorChildren = @import("snapshot_merge_state_in_scope.zig").consumeInteriorChildren;
const consumeInteriorValue = @import("snapshot_merge_state_in_scope.zig").consumeInteriorValue;
const emptyRegStateDelta = @import("reg_state_change.zig").emptyRegStateDelta;
const hasActiveBorrowRefs = @import("const_trap.zig").hasActiveBorrowRefs;
const hasInteriorPtr = @import("const_trap.zig").hasInteriorPtr;
const hasInteriorTree = @import("const_trap.zig").hasInteriorTree;
const isConstData = @import("reg_state_change.zig").isConstData;
const isDecl = @import("const_trap.zig").isDecl;
const isImmutableConst = @import("reg_state_change.zig").isImmutableConst;
const isStackAllocated = @import("collect_metadata.zig").isStackAllocated;
const maskOf = @import("reg_state_change.zig").maskOf;
const readCheck = @import("collect_metadata.zig").readCheck;
const regFlagBranchCondition = @import("reg_state_change.zig").regFlagBranchCondition;
const regFlagEphemeralScalar = @import("reg_state_change.zig").regFlagEphemeralScalar;
const regFlagImmutable = @import("reg_state_change.zig").regFlagImmutable;
const regFlagRawPointer = @import("reg_state_change.zig").regFlagRawPointer;
const restoreLabelSnapshot = @import("const_trap.zig").restoreLabelSnapshot;
const saxReport = @import("sax_trap_report.zig").saxReport;
const setBorrowState = @import("collect_metadata.zig").setBorrowState;
const trapReport = @import("snapshot_merge_state_in_scope.zig").trapReport;
const verifyBody = @import("verify_body.zig").verifyBody;
const verifyWorker = @import("free_annotated_slice.zig").verifyWorker;

pub fn clearBorrowCtx(
    state: []u16,
    flags: []u8,
    origins: []?u32,
    locks: []u16,
    id: u32,
    interior: *InteriorContext,
) void {
    const idx: usize = @intCast(id);
    if ((state[idx] & maskOf(.borrow_view)) == 0) return;

    if (hasInteriorPtr(state[idx])) {
        consumeInteriorValue(interior.state, interior.interior_parent, interior.interior_first_child, interior.interior_next_sibling, id);
    } else {
        consumeInteriorChildren(interior.state, interior.interior_parent, interior.interior_first_child, interior.interior_next_sibling, id);
    }

    if ((flags[idx] & regFlagRawPointer) != 0) {
        state[idx] = 0;
        flags[idx] = 0;
        origins[idx] = null;
        return;
    }
    const origin = origins[idx] orelse {
        state[idx] = 0;
        flags[idx] = 0;
        return;
    };
    const origin_idx: usize = @intCast(origin);
    if (origin_idx >= locks.len) {
        state[idx] = 0;
        flags[idx] = 0;
        origins[idx] = null;
        return;
    }
    if (locks[origin_idx] > 0) {
        locks[origin_idx] -= 1;
        if (locks[origin_idx] == 0) {
            // Restore the origin only when this borrow actually locked it.
            // setBorrowState locks the source (Locked_Read/Locked_Mut) only
            // when it was plain Active; when the source is itself a borrow
            // view (borrow-of-borrow, e.g. STRING_BUF_AS_STR over the
            // borrow produced for `&local`), its state was left untouched,
            // and resetting it to plain Active here would strip its
            // BorrowView bit. The outer view's later release would then
            // take the non-borrow path, the ultimate source's lock count
            // would never decrement, and releasing the owner would raise a
            // false BorrowConflict (expected Active, actual Locked_Read).
            const origin_state = state[origin_idx];
            if ((origin_state & maskOf(.borrow_view)) == 0 and
                (origin_state & (maskOf(.locked_read) | maskOf(.locked_mut))) != 0)
            {
                state[origin_idx] = if (isImmutableConst(state, flags, origin)) maskOf(.active) | maskOf(.immutable) else maskOf(.active);
            }
        }
    }
    state[idx] = 0;
    flags[idx] = 0;
    origins[idx] = null;
}

pub fn clearBorrow(
    state: []u16,
    flags: []u8,
    origins: []?u32,
    locks: []u16,
    id: u32,
    interior: *InteriorContext,
) void {
    clearBorrowCtx(state, flags, origins, locks, id, interior);
}

pub fn consumeAtContractBoundaryCtx(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
    origins: []?u32,
    locks: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    interior: *InteriorContext,
) ?VerifyBodyResult {
    if (readCheck(item, function_text, is_ffi_wrapper, name, id, state, flags)) |tr| return tr;

    const idx: usize = @intCast(id);
    if (hasActiveBorrowRefs(locks, id)) {
        return trapReport(.borrow_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), state[idx], "borrow rules reject this access", null);
    }
    if (isStackAllocated(flags, origins, state, id)) {
        return trapReport(.stack_escape, item, function_text, is_ffi_wrapper, name, maskOf(.active), state[idx], "stack allocation cannot cross a native escape boundary", null);
    }

    if ((state[idx] & maskOf(.borrow_view)) != 0) {
        clearBorrowCtx(state, flags, origins, locks, id, interior);
    } else if (hasInteriorTree(state, interior_first_child, id)) {
        consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, id);
    } else {
        state[idx] = maskOf(.consumed);
    }
    return null;
}

pub fn consumeAtContractBoundary(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
    origins: []?u32,
    locks: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    interior: *InteriorContext,
) ?VerifyBodyResult {
    return consumeAtContractBoundaryCtx(item, function_text, is_ffi_wrapper, name, id, state, flags, origins, locks, interior_parent, interior_first_child, interior_next_sibling, interior);
}

pub fn markBranchCondition(flags: []u8, id: u32) void {
    flags[@intCast(id)] |= regFlagBranchCondition;
}

pub fn updateLabel(
    item: inst.Instruction,
    labels: *std.AutoHashMap(u32, LabelSnapshot),
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
    allocator: std.mem.Allocator,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
) ?VerifyBodyResult {
    const label_id = item.operands[1].label;
    if (labels.getPtr(label_id)) |entry| {
        restoreLabelSnapshot(entry, state, origins, locks, flags, interior_parent, interior_first_child, interior_next_sibling, interior_root, interior_offset, interior_offset_known, alloc_size, alloc_size_known);
        return null;
    }
    var dup = captureLabelSnapshot(allocator, state, origins, locks, flags, interior_parent, interior_first_child, interior_next_sibling, interior_root, interior_offset, interior_offset_known, alloc_size, alloc_size_known) catch {
        return trapReport(.arena_oom, item, function_text, is_ffi_wrapper, null, null, null, "unable to record label state", null);
    };
    labels.put(label_id, dup) catch {
        dup.deinit(allocator);
        return trapReport(.arena_oom, item, function_text, is_ffi_wrapper, null, null, null, "unable to record label state", null);
    };
    return null;
}

pub fn freeSigs(allocator: std.mem.Allocator, sigs: *std.array_list.Managed(sig.FunctionSig)) void {
    for (sigs.items) |*item| item.deinit(allocator);
    sigs.deinit();
}

pub fn freeConstVtables(allocator: std.mem.Allocator, const_vtables: *std.array_list.Managed(ConstVTable)) void {
    for (const_vtables.items) |*item| item.deinit(allocator);
    const_vtables.deinit();
}

pub fn freeFunctionStarts(starts: *std.array_list.Managed(usize)) void {
    starts.deinit();
}

pub fn freeAnnotated(allocator: std.mem.Allocator, annotated: *std.array_list.Managed(AnnotatedInstruction)) void {
    for (annotated.items) |item| {
        var owned = item;
        owned.deinit(allocator);
    }
    annotated.deinit();
}

pub fn diffState(allocator: std.mem.Allocator, before: []const u16, after: []const u16) !RegStateDelta {
    if (before.len != after.len) return error.InvalidOperand;

    var change_count: usize = 0;
    for (before, after) |prev, next| {
        if (next != prev) change_count += 1;
    }
    if (change_count == 0) return emptyRegStateDelta();

    var changes = try allocator.alloc(RegStateChange, change_count);
    var out_idx: usize = 0;
    errdefer allocator.free(changes);
    for (before, after, 0..) |prev, next, idx| {
        if (next == prev) continue;
        changes[out_idx] = .{ .reg = @intCast(idx), .before = prev, .after = next };
        out_idx += 1;
    }
    return .{ .changes = changes };
}

pub fn applyStateDelta(state: []u16, delta: []const RegStateChange) void {
    for (delta) |change| {
        state[change.reg] = change.after;
    }
}

pub fn resetLabels(allocator: std.mem.Allocator, labels: *std.AutoHashMap(u32, LabelSnapshot)) void {
    var it = labels.iterator();
    while (it.next()) |entry| entry.value_ptr.deinit(allocator);
    labels.clearRetainingCapacity();
}

pub const VerifierBufferPool = struct {
    allocator: std.mem.Allocator,
    state: []u16 = &.{},
    flags: []u8 = &.{},
    origins: []?u32 = &.{},
    locks: []u16 = &.{},
    consumed_in_function: []bool = &.{},
    interior_parent: []?u32 = &.{},
    interior_first_child: []?u32 = &.{},
    interior_next_sibling: []?u32 = &.{},
    interior_root: []?u32 = &.{},
    interior_offset: []u64 = &.{},
    interior_offset_known: []bool = &.{},
    alloc_size: []u64 = &.{},
    alloc_size_known: []bool = &.{},

    pub fn init(allocator: std.mem.Allocator) VerifierBufferPool {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *VerifierBufferPool) void {
        const allocator = self.allocator;
        if (self.state.len != 0) self.allocator.free(self.state);
        if (self.flags.len != 0) self.allocator.free(self.flags);
        if (self.origins.len != 0) self.allocator.free(self.origins);
        if (self.locks.len != 0) self.allocator.free(self.locks);
        if (self.consumed_in_function.len != 0) self.allocator.free(self.consumed_in_function);
        if (self.interior_parent.len != 0) self.allocator.free(self.interior_parent);
        if (self.interior_first_child.len != 0) self.allocator.free(self.interior_first_child);
        if (self.interior_next_sibling.len != 0) self.allocator.free(self.interior_next_sibling);
        if (self.interior_root.len != 0) self.allocator.free(self.interior_root);
        if (self.interior_offset.len != 0) self.allocator.free(self.interior_offset);
        if (self.interior_offset_known.len != 0) self.allocator.free(self.interior_offset_known);
        if (self.alloc_size.len != 0) self.allocator.free(self.alloc_size);
        if (self.alloc_size_known.len != 0) self.allocator.free(self.alloc_size_known);
        self.* = .{ .allocator = allocator };
    }

    pub fn ensureCapacity(self: *VerifierBufferPool, reg_count: usize) !void {
        if (self.state.len >= reg_count) return;

        var next = VerifierBufferPool.init(self.allocator);
        errdefer next.deinit();
        next.state = try self.allocator.alloc(u16, reg_count);
        next.flags = try self.allocator.alloc(u8, reg_count);
        next.origins = try self.allocator.alloc(?u32, reg_count);
        next.locks = try self.allocator.alloc(u16, reg_count);
        next.consumed_in_function = try self.allocator.alloc(bool, reg_count);
        next.interior_parent = try self.allocator.alloc(?u32, reg_count);
        next.interior_first_child = try self.allocator.alloc(?u32, reg_count);
        next.interior_next_sibling = try self.allocator.alloc(?u32, reg_count);
        next.interior_root = try self.allocator.alloc(?u32, reg_count);
        next.interior_offset = try self.allocator.alloc(u64, reg_count);
        next.interior_offset_known = try self.allocator.alloc(bool, reg_count);
        next.alloc_size = try self.allocator.alloc(u64, reg_count);
        next.alloc_size_known = try self.allocator.alloc(bool, reg_count);

        self.deinit();
        self.* = next;
    }
};

/// Scan one finished function's exit state for live owned registers.
///
/// HOST-VERIFIER-SCOPE: this used to run only once, at the end of
/// `verifyBody`, over the LAST function's state — so a leak in any
/// earlier function was silently dropped (the `chunk_index + 1 ==
/// chunks.len` gate in `verifyWorker` had the same effect on the
/// parallel path). It is now called at every function boundary (see
/// the `isDecl` arm) and at end of stream, so every function is
/// checked. Returns the trap result on the first live register, or
/// null when the function exits clean. `scope` is optional only so
/// the check stays a no-op on streams without a scope; callers pass
/// the finished function's scope.
pub fn checkExitLeaks(
    state: []const u16,
    flags: []const u8,
    origins: []const ?u32,
    consumed_in_function: []const bool,
    scope: ?*const FunctionRegScope,
    metadata: *const CollectResult,
    sax_context: ?SaxValidationContext,
    location: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
) ?VerifyBodyResult {
    for (state, 0..) |mask, idx| {
        if (mask == 0 or mask == maskOf(.consumed) or mask == maskOf(.untracked)) continue;
        // Only const data is exempt from the leak check; an immutable
        // binding still owns its allocation and must be released.
        if ((flags[idx] & regFlagImmutable) != 0) continue;
        if ((flags[idx] & regFlagEphemeralScalar) != 0) continue;
        // Raw pointers carry no ownership (release is a no-op for them);
        // a live raw-pointer temp is never a leak, same as an ephemeral
        // scalar temp.
        if ((flags[idx] & regFlagRawPointer) != 0) continue;
        // A borrow view of hard const data (@const) carries no ownership
        // and its referent can never be retired while borrowed (const
        // data is never locked, moved, or released); a live borrow of
        // const data at function exit is never a leak, same as a live
        // raw-pointer temp. A borrow view of an owned value is NOT
        // exempted: the move path does not check borrow locks, so the
        // exit scan on the view is the backstop that catches
        // move-while-borrowed.
        if ((mask & maskOf(.borrow_view)) != 0) {
            const origin = origins[idx];
            if (origin != null and isConstData(flags, origin.?)) continue;
        }
        if ((flags[idx] & regFlagBranchCondition) != 0) continue;
        if (isStackAllocated(flags, origins, state, @intCast(idx))) continue;
        if (idx < consumed_in_function.len and consumed_in_function[idx]) continue;
        const leak_name = scope.?.nameOf(&metadata.symbols, @intCast(idx)) orelse metadata.symbols.lookupName(scope.?.globalId(@intCast(idx)));
        if (sax_context) |ctx| {
            if (is_ffi_wrapper and function_text != null and std.mem.containsAtLeast(u8, function_text.?, 1, "destroy")) {
                return saxReport(ctx, .sax_state_leak, location, leak_name, null, mask, "live state remains at component teardown", null);
            }
        }
        return trapReport(.memory_leak, location, function_text, is_ffi_wrapper, leak_name, null, mask, "live registers remain at function exit", null);
    }
    return null;
}

/// TRAP-PRECEDENCE: true when a trap report came from the
/// function-exit leak scan (checkExitLeaks). Within this file that
/// scan is the only producer of .memory_leak and .sax_state_leak
/// reports, so the trap kind alone classifies it.
pub fn isExitLeakReport(report: trap.TrapReport) bool {
    return report.trap == .memory_leak or report.trap == .sax_state_leak;
}
