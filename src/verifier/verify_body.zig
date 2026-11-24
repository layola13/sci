const std = @import("std");
const const_decl = @import("../common/const_decl.zig");
const inst = @import("../common/instruction.zig");
const pkg_manifest = @import("../pkg/manifest.zig");
const sig = @import("../common/signature.zig");
const classifier = @import("../flattener/line_classifier.zig");
const AnnotatedInstruction = @import("reg_state_change.zig").AnnotatedInstruction;
const CollectResult = @import("reg_state_change.zig").CollectResult;
const FunctionRegScope = @import("reg_state_change.zig").FunctionRegScope;
const InteriorContext = @import("reg_state_change.zig").InteriorContext;
const LabelSnapshot = @import("reg_state_change.zig").LabelSnapshot;
const SaxValidationContext = @import("reg_state_change.zig").SaxValidationContext;
const VerifierBufferPool = @import("clear_borrow_ctx.zig").VerifierBufferPool;
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const checkExitLeaks = @import("clear_borrow_ctx.zig").checkExitLeaks;
const computeFunctionConsumedRegs = @import("snapshot_merge_state_in_scope.zig").computeFunctionConsumedRegs;
const diffState = @import("clear_borrow_ctx.zig").diffState;
const freeAnnotated = @import("clear_borrow_ctx.zig").freeAnnotated;
const isDecl = @import("const_trap.zig").isDecl;
const isExecKind = @import("const_trap.zig").isExecKind;
const localizeInstructionRegs = @import("sax_trap_report.zig").localizeInstructionRegs;
const maskOf = @import("reg_state_change.zig").maskOf;
const regFlagEphemeralScalar = @import("reg_state_change.zig").regFlagEphemeralScalar;
const regFlagRawPointer = @import("reg_state_change.zig").regFlagRawPointer;
const resetLabels = @import("clear_borrow_ctx.zig").resetLabels;
const seedConstSymbols = @import("const_trap.zig").seedConstSymbols;
const trapReport = @import("snapshot_merge_state_in_scope.zig").trapReport;
const trapReportFromText = @import("sax_trap_report.zig").trapReportFromText;
const updateLabel = @import("clear_borrow_ctx.zig").updateLabel;
const VerifyBodyCtx = @import("verify_body_ctx.zig").VerifyBodyCtx;
const armAlloc = @import("verify_body_arms_alloc_borrow.zig").armAlloc;
const armStackAlloc = @import("verify_body_arms_alloc_borrow.zig").armStackAlloc;
const armLoad = @import("verify_body_arms_alloc_borrow.zig").armLoad;
const armStore = @import("verify_body_arms_alloc_borrow.zig").armStore;
const armAtomicLoad = @import("verify_body_arms_alloc_borrow.zig").armAtomicLoad;
const armAtomicStore = @import("verify_body_arms_alloc_borrow.zig").armAtomicStore;
const armCmpxchg = @import("verify_body_arms_alloc_borrow.zig").armCmpxchg;
const armAtomicRmw = @import("verify_body_arms_alloc_borrow.zig").armAtomicRmw;
const armOp = @import("verify_body_arms_alloc_borrow.zig").armOp;
const armPtrAdd = @import("verify_body_arms_alloc_borrow.zig").armPtrAdd;
const armBorrow = @import("verify_body_arms_alloc_borrow.zig").armBorrow;
const armMove = @import("verify_body_arms_alloc_borrow.zig").armMove;
const armTransfer = @import("verify_body_arms_alloc_borrow.zig").armTransfer;
const armAssign = @import("verify_body_arms_assign_branch.zig").armAssign;
const armRelease = @import("verify_body_arms_assign_branch.zig").armRelease;
const armRawCast = @import("verify_body_arms_assign_branch.zig").armRawCast;
const armAssumeSafe = @import("verify_body_arms_assign_branch.zig").armAssumeSafe;
const armAssumeBorrow = @import("verify_body_arms_assign_branch.zig").armAssumeBorrow;
const armNative = @import("verify_body_arms_assign_branch.zig").armNative;
const armJmp = @import("verify_body_arms_assign_branch.zig").armJmp;
const armBr = @import("verify_body_arms_assign_branch.zig").armBr;
const armBrNull = @import("verify_body_arms_assign_branch.zig").armBrNull;
const armCall = @import("verify_body_arms_call_return.zig").armCall;
const armTry = @import("verify_body_arms_call_return.zig").armTry;
const armReturn = @import("verify_body_arms_call_return.zig").armReturn;
const armVaStart = @import("verify_body_arms_call_return.zig").armVaStart;
const armVaArg = @import("verify_body_arms_call_return.zig").armVaArg;
const armVaEnd = @import("verify_body_arms_call_return.zig").armVaEnd;

pub fn verifyBody(
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    classified_lines: []const classifier.ClassifiedLine,
    const_decls: []const const_decl.ConstDecl,
    metadata: *const CollectResult,
    sig_index_start: usize,
    check_exit_leaks: bool,
    package_grants: []const pkg_manifest.RequireEntry,
    sax_context: ?SaxValidationContext,
    default_immutable: bool,
) !VerifyBodyResult {
    // const_decls no longer used here: const ids now ride metadata.const_ids
    // (OPTIMIZE-IMPL-1 step 2). Kept in the signature to avoid churning the
    // three verifyBody call sites and the parallel context.
    _ = const_decls;
    // OPTIMIZE-VERIFY-FIX: one reusable snapshot scratch instead of
    // allocator.dupe() per exec instruction (timer probe: dupe was ~94%
    // of snapshot_diff, ~5.9us per 40B alloc @100k serial). Grown on
    // demand; the delta diffState computes is unchanged, so the
    // annotated stream and all output bytes are identical.
    var vb: VerifyBodyCtx = .{
        .snapshot_scratch = &.{},
        .sig_index = sig_index_start,
        .state = &.{},
        .flags = &.{},
        .origins = &.{},
        .locks = &.{},
        .consumed_in_function = &.{},
        .interior_parent = &.{},
        .interior_first_child = &.{},
        .interior_next_sibling = &.{},
        .interior_root = &.{},
        .interior_offset = &.{},
        .interior_offset_known = &.{},
        .alloc_size = &.{},
        .alloc_size_known = &.{},
        .buffers = VerifierBufferPool.init(allocator),
        .current_scope = null,
        .interior = InteriorContext{
            .state = &.{},
            .interior_parent = &.{},
            .interior_first_child = &.{},
            .interior_next_sibling = &.{},
            .interior_root = &.{},
            .interior_offset = &.{},
            .interior_offset_known = &.{},
            .alloc_size = &.{},
            .alloc_size_known = &.{},
        },
        .atomic_history = std.AutoHashMap(u64, u8).init(allocator),
        .labels = std.AutoHashMap(u32, LabelSnapshot).init(allocator),
        .defined_labels = std.AutoHashMap(u32, void).init(allocator),
        .annotated = std.array_list.Managed(AnnotatedInstruction).init(allocator),
        .current_function_text = null,
        .current_is_ffi_wrapper = false,
        .current_sig = null,
        .body_seen = false,
        .terminated = false,
        .fatal_terminated = false,
        .gas_alloc_bytes = 0,
        .gas_steps = 0,
        .has_unbounded_loop = false,
        .last_seen_label = null,
        // TRAP-PRECEDENCE: an exit leak is the LAST event of its function
        // in execution order (its return). A trap raised anywhere the
        // program reaches before that return must win over it, even when
        // the leaking function is declared (and therefore verified)
        // earlier in the stream. So a boundary exit leak is recorded
        // here and only reported once the whole stream has been verified
        // with no other trap.
        .deferred_exit_leak = null,
        .allocator = allocator,
        .instructions = instructions,
        .classified_lines = classified_lines,
        .metadata = metadata,
        .check_exit_leaks = check_exit_leaks,
        .package_grants = package_grants,
        .sax_context = sax_context,
        .default_immutable = default_immutable,
    };
    defer vb.allocator.free(vb.snapshot_scratch);
    std.debug.assert(vb.classified_lines.len == vb.instructions.len);
    defer vb.buffers.deinit();
    defer {
        if (vb.current_scope) |*scope| scope.deinit();
    }
    defer vb.atomic_history.deinit();
    defer {
        var it = vb.labels.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(allocator);
        vb.labels.deinit();
    }
    defer vb.defined_labels.deinit();
    var completed = false;
    defer {
        if (!completed) {
            freeAnnotated(allocator, &vb.annotated);
        }
    }
    const call_depth: u16 = 0;
    for (vb.instructions, 0..) |raw_item, inst_idx| {
        if (try verifyBodyStep(&vb, raw_item, inst_idx)) |r| return r;
    }

    if (vb.body_seen and !vb.terminated) {
        return trapReport(.fallthrough_forbidden, instructions[instructions.len - 1], vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "function body ended without a terminator", "end the last block with jmp, br, br_null, or return");
    }

    const current_is_bodyless_extern = vb.current_sig != null and vb.current_sig.?.kind == .external and !vb.body_seen;
    if (check_exit_leaks and !vb.fatal_terminated and !current_is_bodyless_extern) {
        if (checkExitLeaks(vb.state, vb.flags, vb.origins, vb.consumed_in_function, if (vb.current_scope) |*s| s else null, metadata, sax_context, instructions[instructions.len - 1], vb.current_function_text, vb.current_is_ffi_wrapper)) |trap_result| {
            if (vb.deferred_exit_leak == null) {
                vb.deferred_exit_leak = switch (trap_result) {
                    .trap => |report| report,
                    .ok => null,
                };
            }
        }
    }

    // TRAP-PRECEDENCE: no other trap fired anywhere in the stream, so
    // the deferred exit leak (if any) is the verdict.
    if (vb.deferred_exit_leak) |report| {
        return .{ .trap = report };
    }

    if (vb.current_scope) |*scope| {
        scope.deinit();
        vb.current_scope = null;
    }

    const annotated_slice = vb.annotated.toOwnedSlice() catch {
        return .{ .trap = trapReportFromText(.arena_oom, 1, 1, instructions[instructions.len - 1].raw_text, "unable to finalize annotations", null) };
    };
    completed = true;

    return .{ .ok = .{
        .annotated = annotated_slice,
        .gas = .{
            .max_alloc_bytes = vb.gas_alloc_bytes,
            .max_instruction_steps = if (vb.has_unbounded_loop) .{ .unbounded = .{ .bounded_prefix = vb.gas_steps } } else .{ .bounded = vb.gas_steps },
            .call_depth = call_depth,
            .has_unbounded_loop = vb.has_unbounded_loop,
        },
        .has_unbounded_loop = vb.has_unbounded_loop,
    } };
}

fn verifyBodyStep(vb: *VerifyBodyCtx, raw_item: inst.Instruction, inst_idx: usize) !?VerifyBodyResult {
    var item = raw_item;
    const classified = vb.classified_lines[inst_idx];

    if (isDecl(item.kind)) {
        if (vb.body_seen and !vb.terminated and vb.current_function_text != null) {
            return trapReport(.fallthrough_forbidden, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "basic blocks must end with jmp, br, br_null, or return", "insert an explicit terminator before the next declaration");
        }

        // HOST-VERIFIER-SCOPE: check the just-finished function's
        // exit state here, before its registers are reset for the
        // next function. The end-of-stream check below only ever
        // sees the last function; without this, a leak in any
        // earlier function is silently dropped. The trap location
        // is the previous function's terminator (the instruction
        // just before this declaration).
        if (vb.check_exit_leaks and vb.body_seen and vb.terminated and !vb.fatal_terminated) {
            if (checkExitLeaks(vb.state, vb.flags, vb.origins, vb.consumed_in_function, if (vb.current_scope) |*s| s else null, vb.metadata, vb.sax_context, vb.instructions[inst_idx - 1], vb.current_function_text, vb.current_is_ffi_wrapper)) |trap_result| {
                // TRAP-PRECEDENCE: defer, do not return yet (see
                // deferred_exit_leak above). The first exit leak in
                // stream order is kept; any trap raised by a later
                // instruction returns immediately and wins.
                if (vb.deferred_exit_leak == null) {
                    vb.deferred_exit_leak = switch (trap_result) {
                        .trap => |report| report,
                        .ok => null,
                    };
                }
            }
        }

        vb.current_function_text = item.raw_text;
        vb.current_is_ffi_wrapper = item.kind == .ffi_wrapper_decl;
        vb.last_seen_label = null;
        vb.terminated = false;
        vb.fatal_terminated = false;
        vb.body_seen = false;
        resetLabels(vb.allocator, &vb.labels);

        if (vb.sig_index < vb.metadata.sigs.items.len) {
            vb.current_sig = vb.metadata.sigs.items[vb.sig_index];
            vb.sig_index += 1;
        } else {
            vb.current_sig = null;
        }

        if (vb.current_scope) |*scope| scope.deinit();
        vb.current_scope = null;
        vb.state = &.{};
        vb.flags = &.{};
        vb.origins = &.{};
        vb.locks = &.{};
        vb.consumed_in_function = &.{};
        vb.interior_parent = &.{};
        vb.interior_first_child = &.{};
        vb.interior_next_sibling = &.{};
        vb.interior_root = &.{};
        vb.interior_offset = &.{};
        vb.interior_offset_known = &.{};
        vb.alloc_size = &.{};
        vb.alloc_size_known = &.{};

        if (vb.current_sig) |decl_sig| {
            var next_scope = try FunctionRegScope.initBorrowed(vb.allocator, decl_sig.reg_ids);
            errdefer next_scope.deinit();
            const reg_count = next_scope.reg_ids.len;
            vb.buffers.ensureCapacity(reg_count) catch {
                vb.current_scope = null;
                return .{ .trap = trapReportFromText(.arena_oom, 1, 1, item.raw_text, "unable to allocate verifier state", null) };
            };
            vb.state = vb.buffers.state[0..reg_count];
            @memset(vb.state, 0);
            vb.flags = vb.buffers.flags[0..reg_count];
            @memset(vb.flags, 0);
            vb.origins = vb.buffers.origins[0..reg_count];
            @memset(vb.origins, null);
            vb.locks = vb.buffers.locks[0..reg_count];
            @memset(vb.locks, 0);
            vb.consumed_in_function = vb.buffers.consumed_in_function[0..reg_count];
            @memset(vb.consumed_in_function, false);
            vb.interior_parent = vb.buffers.interior_parent[0..reg_count];
            @memset(vb.interior_parent, null);
            vb.interior_first_child = vb.buffers.interior_first_child[0..reg_count];
            @memset(vb.interior_first_child, null);
            vb.interior_next_sibling = vb.buffers.interior_next_sibling[0..reg_count];
            @memset(vb.interior_next_sibling, null);
            vb.interior_root = vb.buffers.interior_root[0..reg_count];
            @memset(vb.interior_root, null);
            vb.interior_offset = vb.buffers.interior_offset[0..reg_count];
            @memset(vb.interior_offset, 0);
            vb.interior_offset_known = vb.buffers.interior_offset_known[0..reg_count];
            @memset(vb.interior_offset_known, false);
            vb.alloc_size = vb.buffers.alloc_size[0..reg_count];
            @memset(vb.alloc_size, 0);
            vb.alloc_size_known = vb.buffers.alloc_size_known[0..reg_count];
            @memset(vb.alloc_size_known, false);
            vb.interior = .{
                .state = vb.state,
                .interior_parent = vb.interior_parent,
                .interior_first_child = vb.interior_first_child,
                .interior_next_sibling = vb.interior_next_sibling,
                .interior_root = vb.interior_root,
                .interior_offset = vb.interior_offset,
                .interior_offset_known = vb.interior_offset_known,
                .alloc_size = vb.alloc_size,
                .alloc_size_known = vb.alloc_size_known,
            };
            vb.current_scope = next_scope;
            computeFunctionConsumedRegs(vb.allocator, vb.instructions, inst_idx, &vb.metadata.symbols, &vb.current_scope.?, vb.consumed_in_function);
            errdefer {
                if (vb.current_scope) |*scope| scope.deinit();
                vb.current_scope = null;
            }

            // A corrupted artifact (e.g. a hand-edited or truncated .sab) may carry
            // a signature whose param_ids do not line up with its params or whose
            // param register ids are not declared in the function scope. Both
            // are reported as structured traps; the old `orelse unreachable`
            // panicked and the bare `param_ids[pidx]` indexing could read out
            // of bounds.
            if (decl_sig.param_ids.len < decl_sig.params.len) {
                return trapReport(
                    .corrupted_signature,
                    item,
                    vb.current_function_text,
                    vb.current_is_ffi_wrapper,
                    null,
                    null,
                    null,
                    "corrupted function signature: parameter count exceeds param_ids count",
                    "rebuild the module from source; the artifact's signature metadata is inconsistent",
                );
            }
            for (decl_sig.params, 0..) |param, pidx| {
                const reg_id = decl_sig.param_ids[pidx];
                const reg_slot = vb.current_scope.?.slotOf(reg_id) orelse {
                    return trapReport(
                        .corrupted_signature,
                        item,
                        vb.current_function_text,
                        vb.current_is_ffi_wrapper,
                        param.name,
                        null,
                        null,
                        "corrupted function signature: parameter references a register id that is not declared in this function scope",
                        "rebuild the module from source; the artifact's param_ids are inconsistent with its register scope",
                    );
                };
                const reg_idx: usize = @intCast(reg_slot);
                vb.state[reg_idx] = switch (param.cap) {
                    .by_value, .move => maskOf(.active),
                    .borrow => maskOf(.active) | maskOf(.borrow_view) | maskOf(.locked_read),
                    .raw => maskOf(.untracked),
                };
                // VERIFIER-BFULL (G1): owning-ness is decided by the SA
                // signature TYPE, not by the parameter role. A scalar
                // parameter (int/float/v128, no nominal wrapper) carries
                // no obligation: flag it ephemeral so the exit scan, the
                // early-return scan, copy-consume and `!` release all
                // treat it as freely copyable/droppable. A nominal
                // wrapper (`Fd(i32)`) or a non-scalar type
                // (`blob_handle`, `ptr` by value/move) stays owning.
                vb.flags[reg_idx] = if (param.cap == .raw)
                    regFlagRawPointer
                else if (param.nominal == null and sig.isScalarPrimType(param.ty))
                    regFlagEphemeralScalar
                else
                    0;
                if (param.cap == .borrow) {
                    vb.origins[reg_idx] = reg_slot;
                    vb.locks[reg_idx] = 1;
                }
            }
        } else {
            vb.current_scope = null;
        }

        vb.atomic_history.clearRetainingCapacity();
        vb.defined_labels.clearRetainingCapacity();
        if (vb.current_scope) |scope| {
            seedConstSymbols(vb.state, vb.flags, &scope, &vb.metadata.const_ids);
        }

        try vb.annotated.append(.{
            .base = item,
            .delta = .{ .changes = &.{} },
            .gas_step_cost = 0,
        });
        return null;
    }

    if (vb.fatal_terminated and item.kind != .label) {
        return null;
    }

    if (vb.terminated) {
        if (!isDecl(item.kind) and item.kind != .label) {
            return trapReport(.fallthrough_forbidden, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "basic blocks must end with jmp, br, br_null, or return", "insert an explicit terminator before the next declaration");
        }
        vb.terminated = false;
        vb.fatal_terminated = false;
    }

    if (vb.current_scope) |*scope| {
        if (localizeInstructionRegs(&item, scope, &vb.metadata.symbols, vb.current_function_text, vb.current_is_ffi_wrapper)) |tr| {
            return tr;
        }
    }

    if (item.kind == .label) {
        vb.last_seen_label = item.operands[1].label;
        if (vb.defined_labels.contains(item.operands[1].label)) {
            return trapReport(.duplicate_label, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "label is already defined", "rename the label or merge the blocks");
        }
        if (updateLabel(item, &vb.labels, vb.state, vb.origins, vb.locks, vb.flags, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, vb.interior_root, vb.interior_offset, vb.interior_offset_known, vb.alloc_size, vb.alloc_size_known, vb.allocator, vb.current_function_text, vb.current_is_ffi_wrapper)) |tr| {
            return tr;
        }
        vb.defined_labels.put(item.operands[1].label, {}) catch {
            return trapReport(.arena_oom, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "unable to record label definition", null);
        };
        try vb.annotated.append(.{
            .base = item,
            .delta = .{ .changes = &.{} },
            .gas_step_cost = 0,
        });
        return null;
    }

    if (!isExecKind(item.kind)) {
        try vb.annotated.append(.{
            .base = item,
            .delta = .{ .changes = &.{} },
            .gas_step_cost = 0,
        });
        return null;
    }

    vb.body_seen = true;
    vb.gas_steps += 1;
    if (vb.snapshot_scratch.len < vb.state.len) {
        const grown = try vb.allocator.alloc(u16, vb.state.len);
        vb.allocator.free(vb.snapshot_scratch);
        vb.snapshot_scratch = grown;
    }
    const snapshot_before = vb.snapshot_scratch[0..vb.state.len];
    @memcpy(snapshot_before, vb.state);

    switch (item.kind) {
        .alloc => {
            if (try armAlloc(vb, item, classified)) |r| return r;
        },
        .stack_alloc => {
            if (try armStackAlloc(vb, item, classified)) |r| return r;
        },
        .load, .take => {
            if (try armLoad(vb, item, classified)) |r| return r;
        },
        .store => {
            if (try armStore(vb, item, classified)) |r| return r;
        },
        .atomic_load => {
            if (try armAtomicLoad(vb, item, classified)) |r| return r;
        },
        .atomic_store => {
            if (try armAtomicStore(vb, item, classified)) |r| return r;
        },
        .cmpxchg => {
            if (try armCmpxchg(vb, item, classified)) |r| return r;
        },
        .atomic_rmw => {
            if (try armAtomicRmw(vb, item, classified)) |r| return r;
        },
        .op => {
            if (try armOp(vb, item, classified)) |r| return r;
        },
        .ptr_add => {
            if (try armPtrAdd(vb, item, classified)) |r| return r;
        },
        .borrow => {
            if (try armBorrow(vb, item, classified)) |r| return r;
        },
        .move_ => {
            if (try armMove(vb, item, classified)) |r| return r;
        },
        .transfer => {
            if (try armTransfer(vb, item, classified)) |r| return r;
        },
        .assign => {
            if (try armAssign(vb, item, classified)) |r| return r;
        },
        .release => {
            if (try armRelease(vb, item, classified)) |r| return r;
        },
        .raw_cast => {
            if (try armRawCast(vb, item, classified)) |r| return r;
        },
        .assume_safe => {
            if (try armAssumeSafe(vb, item, classified)) |r| return r;
        },
        .assume_borrow => {
            if (try armAssumeBorrow(vb, item, classified)) |r| return r;
        },
        .native => {
            if (try armNative(vb, item, classified)) |r| return r;
        },
        .jmp => {
            if (try armJmp(vb, item, classified)) |r| return r;
        },
        .br => {
            if (try armBr(vb, item, classified)) |r| return r;
        },
        .br_null => {
            if (try armBrNull(vb, item, classified)) |r| return r;
        },
        .call, .call_indirect, .panic, .panic_msg => {
            if (try armCall(vb, item, classified)) |r| return r;
        },
        .try_, .early_return => {
            if (try armTry(vb, item, classified)) |r| return r;
        },
        .return_ => {
            if (try armReturn(vb, item, classified)) |r| return r;
        },
        .va_start => {
            if (try armVaStart(vb, item, classified)) |r| return r;
        },
        .va_arg => {
            if (try armVaArg(vb, item, classified)) |r| return r;
        },
        .va_end => {
            if (try armVaEnd(vb, item, classified)) |r| return r;
        },
        .fence => {},
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {},
        .label => {},
    }

    const delta = try diffState(vb.allocator, snapshot_before, vb.state);
    errdefer {
        var owned = delta;
        owned.deinit(vb.allocator);
    }
    try vb.annotated.append(.{
        .base = item,
        .delta = delta,
        .gas_step_cost = if (isExecKind(item.kind)) 1 else 0,
    });
    return null;
}
