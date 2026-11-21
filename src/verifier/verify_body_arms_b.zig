const std = @import("std");
const inst = @import("../common/instruction.zig");
const classifier = @import("../flattener/line_classifier.zig");
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const assignValue = @import("collect_metadata.zig").assignValue;
const captureLabelSnapshot = @import("const_trap.zig").captureLabelSnapshot;
const clearBorrow = @import("clear_borrow_ctx.zig").clearBorrow;
const constTrap = @import("const_trap.zig").constTrap;
const consumeAtContractBoundary = @import("clear_borrow_ctx.zig").consumeAtContractBoundary;
const consumeInteriorValue = @import("snapshot_merge_state_in_scope.zig").consumeInteriorValue;
const consumeSourceValue = @import("collect_metadata.zig").consumeSourceValue;
const hasActiveBorrowRefs = @import("const_trap.zig").hasActiveBorrowRefs;
const hasInteriorTree = @import("const_trap.zig").hasInteriorTree;
const isConstData = @import("reg_state_change.zig").isConstData;
const isIdentLike = @import("reg_state_change.zig").isIdentLike;
const isStackAllocated = @import("collect_metadata.zig").isStackAllocated;
const markBranchCondition = @import("clear_borrow_ctx.zig").markBranchCondition;
const maskOf = @import("reg_state_change.zig").maskOf;
const phiStateConflictReport = @import("snapshot_merge_state_in_scope.zig").phiStateConflictReport;
const readCheck = @import("collect_metadata.zig").readCheck;
const regFlagEphemeralScalar = @import("reg_state_change.zig").regFlagEphemeralScalar;
const regFlagRawPointer = @import("reg_state_change.zig").regFlagRawPointer;
const resolveScopedRegId = @import("sax_trap_report.zig").resolveScopedRegId;
const setBorrowState = @import("collect_metadata.zig").setBorrowState;
const snapshotFirstMismatch = @import("const_trap.zig").snapshotFirstMismatch;
const snapshotFirstMismatchInScope = @import("const_trap.zig").snapshotFirstMismatchInScope;
const snapshotMergeCompatible = @import("const_trap.zig").snapshotMergeCompatible;
const snapshotMergeState = @import("const_trap.zig").snapshotMergeState;
const snapshotMergeStateInScope = @import("snapshot_merge_state_in_scope.zig").snapshotMergeStateInScope;
const snapshotStatesCompatible = @import("const_trap.zig").snapshotStatesCompatible;
const trapReport = @import("snapshot_merge_state_in_scope.zig").trapReport;
const VerifyBodyCtx = @import("verify_body_ctx.zig").VerifyBodyCtx;

pub fn armAssign(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    const dst_id = item.operands[0].reg;
    const source_is_ephemeral = switch (item.operands[1]) {
        .imm_i64, .imm_u64, .imm_int, .imm_float => true,
        .reg => |src| (vb.flags[@intCast(src)] & regFlagEphemeralScalar) != 0,
        else => false,
    };
    if (item.operands[1] == .reg and item.operands[1].reg != dst_id) {
        if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags)) |tr| return tr;
    }
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], dst_id, vb.state, vb.flags, maskOf(.active), &vb.interior)) |tr| return tr;
    if (item.operands[1] == .reg) {
        const src_flags = vb.flags[@intCast(item.operands[1].reg)];
        if ((src_flags & regFlagRawPointer) != 0) {
            vb.flags[@intCast(dst_id)] |= regFlagRawPointer;
        }
    }
    if (source_is_ephemeral) {
        vb.flags[@intCast(dst_id)] = regFlagEphemeralScalar;
    }
    if (item.operands[1] == .reg and item.operands[1].reg != dst_id) {
        if (consumeSourceValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags, vb.origins, vb.locks, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, true, &vb.interior)) |tr| return tr;
    }
}

pub fn armRelease(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    const idx: usize = @intCast(item.operands[0].reg);
    if ((vb.state[idx] & maskOf(.borrow_view)) != 0) {
        clearBorrow(vb.state, vb.flags, vb.origins, vb.locks, item.operands[0].reg, &vb.interior);
    } else if ((vb.flags[idx] & (regFlagRawPointer | regFlagEphemeralScalar)) != 0 and
        vb.state[idx] == maskOf(.active))
    {
        // Plain raw pointers and ephemeral scalars carry no
        // ownership: release is a no-op and must not mark the
        // register Consumed. Otherwise a `!tp`/`!tn` (e.g. at a
        // loop back-edge) poisons the phi snapshot for later
        // redefinitions of the same register name, producing a
        // false PhiStateConflict (Active vs Consumed).
        // NOTE: check borrow_view first above: setBorrowState
        // reuses bit 0x01 for FFI borrows, which collides with
        // regFlagRawPointer; FFI borrows must still go through
        // clearBorrow.
        // NOTE: only apply to PLAIN Active values. A raw ptr
        // loaded from a borrow view carries InteriorPtr state
        // (Active|InteriorPtr composite); it is borrow-tracked
        // and must go through the normal release path so macro
        // temps (e.g. VEC_AS_SLICE's __vec_ptr_...) are properly
        // cleared for loop-head phi merges.
        if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags)) |tr| return tr;
    } else {
        if (isConstData(vb.flags, item.operands[0].reg)) {
            return constTrap(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], vb.state[idx], "immutable registers cannot be released");
        }
        if (hasActiveBorrowRefs(vb.locks, item.operands[0].reg)) {
            return trapReport(.borrow_conflict, item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], maskOf(.active), vb.state[idx], "borrow rules reject this access", null);
        }
        if (isStackAllocated(vb.flags, vb.origins, vb.state, item.operands[0].reg)) {
            return trapReport(.stack_escape, item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], maskOf(.active), vb.state[idx], "stack allocation cannot be released explicitly", null);
        }
        if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags)) |tr| return tr;
        if (hasInteriorTree(vb.state, vb.interior_first_child, item.operands[0].reg)) {
            consumeInteriorValue(vb.state, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, item.operands[0].reg);
        } else {
            vb.state[idx] = maskOf(.consumed);
        }
    }
}

pub fn armRawCast(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (!vb.current_is_ffi_wrapper) return trapReport(.illegal_unsafe_context, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags)) |tr| return tr;
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, maskOf(.untracked), &vb.interior)) |tr| return tr;
}

pub fn armAssumeSafe(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (!vb.current_is_ffi_wrapper) return trapReport(.illegal_unsafe_context, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags)) |tr| return tr;
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, maskOf(.active), &vb.interior)) |tr| return tr;
    // A safe pointer carries no more ownership than the raw
    // pointer it reinterprets: propagate the raw-pointer flag
    // from the input, like .assign does. A load of .ptr is
    // flagged regFlagRawPointer, so the db bench shape (f =
    // load vt+0 as ptr; s = assume_safe f) leaves s exempt
    // from the exit scan; assume_safe of an owned value stays
    // tracked (alloc never sets the flag), so the
    // move-while-aliased backstop is preserved.
    if ((vb.flags[@intCast(item.operands[1].reg)] & regFlagRawPointer) != 0) {
        vb.flags[@intCast(item.operands[0].reg)] |= regFlagRawPointer;
    }
}

pub fn armAssumeBorrow(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (!vb.current_is_ffi_wrapper) return trapReport(.illegal_unsafe_context, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags)) |tr| return tr;
    const is_mut = item.operands[2] == .text and std.mem.eql(u8, item.operands[2].text, "mut");
    if (is_mut and isConstData(vb.flags, item.operands[1].reg)) {
        return constTrap(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], vb.state[@intCast(item.operands[1].reg)], "immutable registers cannot be exclusively borrowed");
    }
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, maskOf(.active) | maskOf(.borrow_view), &vb.interior)) |tr| return tr;
    setBorrowState(vb.state, vb.flags, vb.origins, vb.locks, item.operands[0].reg, item.operands[1].reg, is_mut, true);
}

pub fn armNative(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    _ = classified;
    for (item.native_reg_names) |name| {
        if (!isIdentLike(name)) continue;
        if (vb.current_scope) |scope| {
            if (resolveScopedRegId(&scope, &vb.metadata.symbols, name)) |id| {
                if (consumeAtContractBoundary(item, vb.current_function_text, vb.current_is_ffi_wrapper, name, id, vb.state, vb.flags, vb.origins, vb.locks, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, &vb.interior)) |tr| return tr;
            }
        }
    }
}

pub fn armJmp(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    _ = classified;
    const target = item.operands[1].label;
    if (vb.defined_labels.contains(target)) vb.has_unbounded_loop = true;
    if (vb.labels.getPtr(target)) |entry| {
        if (vb.defined_labels.contains(target)) {
            if (!snapshotStatesCompatible(entry, vb.state)) {
                const mismatch = if (vb.current_scope) |scope|
                    snapshotFirstMismatchInScope(entry, vb.state, &scope, &vb.metadata.symbols)
                else
                    snapshotFirstMismatch(entry, vb.state, &vb.metadata.symbols);
                return phiStateConflictReport(item, vb.current_function_text, vb.current_is_ffi_wrapper, target, vb.last_seen_label, mismatch, &vb.metadata.symbols);
            }
        } else {
            if (!snapshotMergeCompatible(entry, vb.state)) {
                const mismatch = if (vb.current_scope) |scope|
                    snapshotMergeStateInScope(entry, vb.state, &scope, &vb.metadata.symbols)
                else
                    snapshotMergeState(entry, vb.state, &vb.metadata.symbols);
                return phiStateConflictReport(item, vb.current_function_text, vb.current_is_ffi_wrapper, target, vb.last_seen_label, mismatch, &vb.metadata.symbols);
            }
        }
    } else {
        var snapshot = captureLabelSnapshot(vb.allocator, vb.state, vb.origins, vb.locks, vb.flags, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, vb.interior_root, vb.interior_offset, vb.interior_offset_known, vb.alloc_size, vb.alloc_size_known) catch {
            return trapReport(.arena_oom, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
        };
        vb.labels.put(target, snapshot) catch {
            snapshot.deinit(vb.allocator);
            return trapReport(.arena_oom, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
        };
    }
    vb.terminated = true;
}

pub fn armBr(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags)) |tr| return tr;
    markBranchCondition(vb.flags, item.operands[0].reg);
    for ([_]u32{ item.operands[1].label, item.operands[3].label }) |target| {
        if (vb.labels.getPtr(target)) |entry| {
            if (vb.defined_labels.contains(target)) {
                if (!snapshotStatesCompatible(entry, vb.state)) {
                    const mismatch = if (vb.current_scope) |scope|
                        snapshotFirstMismatchInScope(entry, vb.state, &scope, &vb.metadata.symbols)
                    else
                        snapshotFirstMismatch(entry, vb.state, &vb.metadata.symbols);
                    return phiStateConflictReport(item, vb.current_function_text, vb.current_is_ffi_wrapper, target, vb.last_seen_label, mismatch, &vb.metadata.symbols);
                }
            } else {
                if (!snapshotMergeCompatible(entry, vb.state)) {
                    const mismatch = if (vb.current_scope) |scope|
                        snapshotMergeStateInScope(entry, vb.state, &scope, &vb.metadata.symbols)
                    else
                        snapshotMergeState(entry, vb.state, &vb.metadata.symbols);
                    return phiStateConflictReport(item, vb.current_function_text, vb.current_is_ffi_wrapper, target, vb.last_seen_label, mismatch, &vb.metadata.symbols);
                }
            }
        } else {
            var snapshot = captureLabelSnapshot(vb.allocator, vb.state, vb.origins, vb.locks, vb.flags, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, vb.interior_root, vb.interior_offset, vb.interior_offset_known, vb.alloc_size, vb.alloc_size_known) catch {
                return trapReport(.arena_oom, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
            };
            vb.labels.put(target, snapshot) catch {
                snapshot.deinit(vb.allocator);
                return trapReport(.arena_oom, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
            };
        }
        if (vb.defined_labels.contains(target)) vb.has_unbounded_loop = true;
    }
    vb.terminated = true;
}

pub fn armBrNull(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags)) |tr| return tr;
    markBranchCondition(vb.flags, item.operands[0].reg);
    for ([_]u32{ item.operands[1].label, item.operands[3].label }) |target| {
        if (vb.labels.getPtr(target)) |entry| {
            if (vb.defined_labels.contains(target)) {
                if (!snapshotStatesCompatible(entry, vb.state)) {
                    const mismatch = if (vb.current_scope) |scope|
                        snapshotFirstMismatchInScope(entry, vb.state, &scope, &vb.metadata.symbols)
                    else
                        snapshotFirstMismatch(entry, vb.state, &vb.metadata.symbols);
                    return phiStateConflictReport(item, vb.current_function_text, vb.current_is_ffi_wrapper, target, vb.last_seen_label, mismatch, &vb.metadata.symbols);
                }
            } else {
                if (!snapshotMergeCompatible(entry, vb.state)) {
                    const mismatch = if (vb.current_scope) |scope|
                        snapshotMergeStateInScope(entry, vb.state, &scope, &vb.metadata.symbols)
                    else
                        snapshotMergeState(entry, vb.state, &vb.metadata.symbols);
                    return phiStateConflictReport(item, vb.current_function_text, vb.current_is_ffi_wrapper, target, vb.last_seen_label, mismatch, &vb.metadata.symbols);
                }
            }
        } else {
            var snapshot = captureLabelSnapshot(vb.allocator, vb.state, vb.origins, vb.locks, vb.flags, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, vb.interior_root, vb.interior_offset, vb.interior_offset_known, vb.alloc_size, vb.alloc_size_known) catch {
                return trapReport(.arena_oom, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
            };
            vb.labels.put(target, snapshot) catch {
                snapshot.deinit(vb.allocator);
                return trapReport(.arena_oom, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
            };
        }
        if (vb.defined_labels.contains(target)) vb.has_unbounded_loop = true;
    }
    vb.terminated = true;
}
