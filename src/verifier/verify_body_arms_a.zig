const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const classifier = @import("../flattener/line_classifier.zig");
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const allocDefaultMask = @import("reg_state_change.zig").allocDefaultMask;
const assignValue = @import("collect_metadata.zig").assignValue;
const attachInteriorChild = @import("snapshot_merge_state_in_scope.zig").attachInteriorChild;
const checkAtomicOrdering = @import("const_trap.zig").checkAtomicOrdering;
const checkStaticOffsetInBounds = @import("snapshot_merge_state_in_scope.zig").checkStaticOffsetInBounds;
const constTrap = @import("const_trap.zig").constTrap;
const consumeSourceValue = @import("collect_metadata.zig").consumeSourceValue;
const hasActiveBorrowRefs = @import("const_trap.zig").hasActiveBorrowRefs;
const hasInteriorTree = @import("const_trap.zig").hasInteriorTree;
const hasOverlappingInteriorBorrow = @import("snapshot_merge_state_in_scope.zig").hasOverlappingInteriorBorrow;
const isConstData = @import("reg_state_change.zig").isConstData;
const isIdentLike = @import("reg_state_change.zig").isIdentLike;
const isImmutableConst = @import("reg_state_change.zig").isImmutableConst;
const maskOf = @import("reg_state_change.zig").maskOf;
const parseAllocSizeOperand = @import("snapshot_merge_state_in_scope.zig").parseAllocSizeOperand;
const readCheck = @import("collect_metadata.zig").readCheck;
const recordAllocSize = @import("snapshot_merge_state_in_scope.zig").recordAllocSize;
const regFlagEphemeralScalar = @import("reg_state_change.zig").regFlagEphemeralScalar;
const regFlagRawPointer = @import("reg_state_change.zig").regFlagRawPointer;
const regFlagStackAlloc = @import("reg_state_change.zig").regFlagStackAlloc;
const resolveScopedRegId = @import("sax_trap_report.zig").resolveScopedRegId;
const saxReport = @import("sax_trap_report.zig").saxReport;
const setBorrowState = @import("collect_metadata.zig").setBorrowState;
const setInteriorOffsetFromBase = @import("snapshot_merge_state_in_scope.zig").setInteriorOffsetFromBase;
const staticByteOffset = @import("snapshot_merge_state_in_scope.zig").staticByteOffset;
const trapReport = @import("snapshot_merge_state_in_scope.zig").trapReport;
const writeCheck = @import("collect_metadata.zig").writeCheck;
const VerifyBodyCtx = @import("verify_body_ctx.zig").VerifyBodyCtx;

pub fn armAlloc(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, allocDefaultMask(vb.default_immutable), &vb.interior)) |tr| return tr;
    vb.flags[@intCast(item.operands[0].reg)] = 0;
    recordAllocSize(&vb.interior, item.operands[0].reg, parseAllocSizeOperand(item.operands[1]));
    vb.gas_alloc_bytes += switch (item.operands[1]) {
        .imm_u64 => |v| v,
        .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
        .text => |t| std.fmt.parseInt(u64, t, 10) catch 0,
        else => 0,
    };
}

pub fn armStackAlloc(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, allocDefaultMask(vb.default_immutable), &vb.interior)) |tr| return tr;
    vb.flags[@intCast(item.operands[0].reg)] = regFlagStackAlloc;
    recordAllocSize(&vb.interior, item.operands[0].reg, parseAllocSizeOperand(item.operands[1]));
    vb.gas_alloc_bytes += switch (item.operands[1]) {
        .imm_u64 => |v| v,
        .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
        .text => |t| std.fmt.parseInt(u64, t, 10) catch 0,
        else => 0,
    };
}

pub fn armLoad(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags)) |tr| return tr;
    if (checkStaticOffsetInBounds(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], &vb.interior, vb.origins, vb.state, item.operands[1].reg, staticByteOffset(item.operands[2]))) |tr| return tr;
    const loaded_ty: sig.PrimType = if (item.operands[3] == .ty) blk: {
        break :blk sig.primTypeFromTag(item.operands[3].ty) orelse if (item.kind == .take) .ptr else .i64;
    } else if (item.kind == .take) .ptr else .i64;
    const source_idx: usize = @intCast(item.operands[1].reg);
    const source_mask = vb.state[source_idx];
    const load_is_borrowed_ptr =
        loaded_ty == .ptr and
        ((source_mask & (maskOf(.borrow_view) | maskOf(.ffi_borrow))) != 0);
    const new_mask = maskOf(.active) | if (load_is_borrowed_ptr) maskOf(.interior_ptr) else 0;
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, new_mask, &vb.interior)) |tr| return tr;
    vb.flags[@intCast(item.operands[0].reg)] = if (item.kind == .load) (if (loaded_ty == .ptr) regFlagRawPointer else regFlagEphemeralScalar) else 0;
    if (item.kind == .take and ((source_mask & (maskOf(.borrow_view) | maskOf(.ffi_borrow) | maskOf(.interior_ptr))) != 0 or hasInteriorTree(vb.state, vb.interior_first_child, item.operands[1].reg))) {
        attachInteriorChild(vb.state, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, item.operands[1].reg, item.operands[0].reg);
        setInteriorOffsetFromBase(&vb.interior, item.operands[1].reg, item.operands[0].reg, staticByteOffset(item.operands[2]));
    }
}

pub fn armStore(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (vb.sax_context) |ctx| {
        const trimmed = std.mem.trim(u8, item.raw_text, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "store state+") and !vb.current_is_ffi_wrapper) {
            return saxReport(ctx, .sax_state_write_from_outside, item, classified.parts[0], null, null, "state slot written from outside component", null);
        }
    }
    if (writeCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, vb.origins, vb.locks)) |tr| return tr;
    if (checkStaticOffsetInBounds(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], &vb.interior, vb.origins, vb.state, item.operands[0].reg, staticByteOffset(item.operands[1]))) |tr| return tr;
    const dst_idx: usize = @intCast(item.operands[0].reg);
    if ((vb.state[dst_idx] & maskOf(.borrow_view)) != 0) {
        const origin_id = vb.origins[dst_idx] orelse unreachable;
        const origin_idx: usize = @intCast(origin_id);
        if (origin_idx < vb.state.len and vb.state[origin_idx] == maskOf(.locked_read)) {
            vb.state[origin_idx] = maskOf(.locked_mut);
        }
    }
    if (item.operands[2] == .text and isIdentLike(item.operands[2].text)) {
        if (vb.current_scope) |scope| {
            if (resolveScopedRegId(&scope, &vb.metadata.symbols, item.operands[2].text)) |value_id| {
                if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, item.operands[2].text, value_id, vb.state, vb.flags)) |tr| return tr;
            }
        }
    }
}

pub fn armAtomicLoad(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags)) |tr| return tr;
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, maskOf(.untracked), &vb.interior)) |tr| return tr;
    vb.flags[@intCast(item.operands[0].reg)] = regFlagEphemeralScalar;
}

pub fn armAtomicStore(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[0].reg, vb.state, vb.flags)) |tr| return tr;
    if (item.operands[2] == .text and isIdentLike(item.operands[2].text)) {
        if (vb.current_scope) |scope| {
            if (resolveScopedRegId(&scope, &vb.metadata.symbols, item.operands[2].text)) |value_id| {
                if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, item.operands[2].text, value_id, vb.state, vb.flags)) |tr| return tr;
            }
        }
    }
}

pub fn armCmpxchg(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (checkAtomicOrdering(item, vb.current_function_text, vb.current_is_ffi_wrapper, &vb.atomic_history)) |tr| return tr;
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[2].reg, vb.state, vb.flags)) |tr| return tr;
    if (item.operands[3] == .imm_u64) {
        _ = item.operands[3].imm_u64;
    }
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, maskOf(.active), &vb.interior)) |tr| return tr;
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags, maskOf(.active), &vb.interior)) |tr| return tr;
    vb.flags[@intCast(item.operands[0].reg)] = 0;
    vb.flags[@intCast(item.operands[1].reg)] = 0;
}

pub fn armAtomicRmw(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (checkAtomicOrdering(item, vb.current_function_text, vb.current_is_ffi_wrapper, &vb.atomic_history)) |tr| return tr;
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags)) |tr| return tr;
    if (item.operands[3] == .text and isIdentLike(item.operands[3].text)) {
        if (vb.current_scope) |scope| {
            if (resolveScopedRegId(&scope, &vb.metadata.symbols, item.operands[3].text)) |value_id| {
                if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, item.operands[3].text, value_id, vb.state, vb.flags)) |tr| return tr;
            }
        }
    }
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, maskOf(.active), &vb.interior)) |tr| return tr;
    vb.flags[@intCast(item.operands[0].reg)] = regFlagEphemeralScalar;
}

pub fn armOp(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    inline for ([_]usize{ 1, 2, 3 }) |op_idx| {
        if (op_idx >= item.operands.len) break;
        const part_idx = op_idx + 1;
        if (part_idx >= classified.part_count) break;
        switch (item.operands[op_idx]) {
            .reg => |id| if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[part_idx], id, vb.state, vb.flags)) |tr| return tr,
            .text => |text| if (isIdentLike(text)) {
                if (vb.current_scope) |scope| {
                    if (resolveScopedRegId(&scope, &vb.metadata.symbols, text)) |id| {
                        if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, text, id, vb.state, vb.flags)) |tr| return tr;
                    } else {
                        return trapReport(.unknown_register, item, vb.current_function_text, vb.current_is_ffi_wrapper, text, null, null, "register is not declared in the current scope", null);
                    }
                } else {
                    return trapReport(.unknown_register, item, vb.current_function_text, vb.current_is_ffi_wrapper, text, null, null, "register is not declared in the current scope", null);
                }
            },
            else => {},
        }
    }
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, maskOf(.untracked), &vb.interior)) |tr| return tr;
    vb.flags[@intCast(item.operands[0].reg)] = 0;
}

pub fn armPtrAdd(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags)) |tr| return tr;
    if (item.operands[2] == .reg) {
        if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[2], item.operands[2].reg, vb.state, vb.flags)) |tr| return tr;
    } else if (item.operands[2] == .text and isIdentLike(item.operands[2].text)) {
        if (vb.current_scope) |scope| {
            if (resolveScopedRegId(&scope, &vb.metadata.symbols, item.operands[2].text)) |value_id| {
                if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, item.operands[2].text, value_id, vb.state, vb.flags)) |tr| return tr;
            }
        }
    }
    const src_idx: usize = @intCast(item.operands[1].reg);
    const has_field_identity = (vb.state[src_idx] & (maskOf(.active) | maskOf(.borrow_view) | maskOf(.locked_read) | maskOf(.locked_mut) | maskOf(.interior_ptr))) != 0;
    const has_borrow_lifetime = (vb.state[src_idx] & (maskOf(.borrow_view) | maskOf(.ffi_borrow) | maskOf(.interior_ptr))) != 0 or hasInteriorTree(vb.state, vb.interior_first_child, item.operands[1].reg);
    // Static OOB check before linking the child: forming an
    // out-of-bounds derived pointer is rejected even if it is
    // never dereferenced.
    if (checkStaticOffsetInBounds(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], &vb.interior, vb.origins, vb.state, item.operands[1].reg, staticByteOffset(item.operands[2]))) |tr| return tr;
    const dst_mask: u16 = if (has_borrow_lifetime) maskOf(.active) | maskOf(.interior_ptr) else maskOf(.active);
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, dst_mask, &vb.interior)) |tr| return tr;
    if (has_borrow_lifetime) {
        attachInteriorChild(vb.state, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, item.operands[1].reg, item.operands[0].reg);
    }
    if (has_field_identity) {
        setInteriorOffsetFromBase(&vb.interior, item.operands[1].reg, item.operands[0].reg, staticByteOffset(item.operands[2]));
    }
    vb.flags[@intCast(item.operands[0].reg)] = 0;
}

pub fn armBorrow(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    const source_reg: u32 = blk: {
        if (item.operands[1] == .reg) break :blk item.operands[1].reg;
        if (item.operands[2] == .reg) break :blk item.operands[2].reg;
        return trapReport(.forbidden_syntax, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "invalid borrow syntax", null);
    };
    const mode_text: []const u8 = blk: {
        if (item.operands[1] == .text) break :blk item.operands[1].text;
        if (item.operands[2] == .text) break :blk item.operands[2].text;
        return trapReport(.forbidden_syntax, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "invalid borrow syntax", null);
    };
    const is_mut = std.mem.eql(u8, mode_text, "mut");
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[2], source_reg, vb.state, vb.flags)) |tr| return tr;
    if (is_mut) {
        const source_idx: usize = @intCast(source_reg);
        if (isConstData(vb.flags, source_reg)) {
            return constTrap(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[2], vb.state[source_idx], "immutable registers cannot be exclusively borrowed");
        }
        if ((vb.state[source_idx] & maskOf(.borrow_view)) != 0 or vb.locks[source_idx] != 0) {
            return trapReport(.read_write_conflict, item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[2], maskOf(.active), vb.state[source_idx], "cannot borrow mut while shared borrows are active", null);
        }
        if (hasOverlappingInteriorBorrow(&vb.interior, vb.locks, source_reg)) {
            return trapReport(.read_write_conflict, item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[2], maskOf(.active), vb.state[source_idx], "cannot borrow mut while overlapping field borrows are active", null);
        }
        if ((vb.state[source_idx] & maskOf(.locked_mut)) != 0) {
            return trapReport(.double_mutable_borrow, item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[2], maskOf(.active), vb.state[source_idx], "cannot borrow mut more than once", null);
        }
    }
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, maskOf(.active) | maskOf(.borrow_view), &vb.interior)) |tr| return tr;
    setBorrowState(vb.state, vb.flags, vb.origins, vb.locks, item.operands[0].reg, source_reg, is_mut, false);
}

pub fn armMove(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags)) |tr| return tr;
    if (consumeSourceValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, vb.origins, vb.locks, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, false, &vb.interior)) |tr| return tr;
}

pub fn armTransfer(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    // `transfer <container>, <value>`: ownership of `value` moves
    // into `container`. Verifier-visible annotation (runtime
    // no-op); the preceding `store` already did the data move.
    if (item.operands[0] != .reg or item.operands[1] != .reg) {
        return trapReport(.transfer_into_borrow, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "transfer requires register operands", null);
    }
    const ci: usize = @intCast(item.operands[0].reg);
    // Destination must be a live OWNED root. Transferring into a
    // borrow view / interior pointer would leak the value when the
    // borrow ends -- this is the check the old bare `^` marker
    // (emitForgetMovedValue) could never perform.
    const cmask = vb.state[ci];
    if ((cmask & (maskOf(.borrow_view) | maskOf(.ffi_borrow) | maskOf(.interior_ptr))) != 0 or
        hasInteriorTree(vb.state, vb.interior_first_child, item.operands[0].reg))
    {
        return trapReport(.transfer_into_borrow, item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], maskOf(.active), cmask, "cannot transfer ownership into a borrowed container", null);
    }
    // Use the combined predicate: an @const hard constant (flag)
    // OR a Rust-style immutable binding (capability bit 0x0100).
    // A transfer writes ownership into the container, so an
    // immutable binding must reject it just as const data does.
    if (isImmutableConst(vb.state, vb.flags, item.operands[0].reg)) {
        return trapReport(.transfer_into_immutable, item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], maskOf(.active), cmask, "cannot transfer ownership into an immutable container", null);
    }
    if ((cmask & maskOf(.active)) == 0) {
        return trapReport(.use_after_move, item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], maskOf(.active), cmask, "cannot transfer into a consumed container", null);
    }
    if (hasActiveBorrowRefs(vb.locks, item.operands[0].reg)) {
        return trapReport(.borrow_conflict, item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], maskOf(.active), cmask, "container has active borrows", null);
    }
    // Value retires exactly like a `^` move-out -> Consumed, so
    // the function-exit leak check is satisfied without an
    // opaque emitter-side marker.
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags)) |tr| return tr;
    if (consumeSourceValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags, vb.origins, vb.locks, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, false, &vb.interior)) |tr| return tr;
    // Record the obligation on the container with a single
    // `owns_children` bit. This is deliberately a boolean, not a
    // count: deep-drop pairing is NOT implemented and is not
    // planned for the verifier. The deep-drop sequence lives in
    // sa_std macros whose register-level effects the Referee
    // cannot observe (see sala SAB whitepaper §4.1 / DESIGN §4.5),
    // so a child counter would be a value with no consumer. A
    // count would also have to be threaded through label
    // snapshots, join merges and parallel workers -- a wide,
    // regression-prone change for data nothing reads. The bit is
    // sufficient for v1 diagnostics ("this container received an
    // ownership transfer"); pairing belongs to the SLA/codegen
    // layer, which owns the DropPlan and can see the drops.
    vb.state[ci] |= maskOf(.owns_children);
}
