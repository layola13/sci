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
const FunctionRegScope = @import("reg_state_change.zig").FunctionRegScope;
const InteriorContext = @import("reg_state_change.zig").InteriorContext;
const LabelSnapshot = @import("reg_state_change.zig").LabelSnapshot;
const SaxValidationContext = @import("reg_state_change.zig").SaxValidationContext;
const VerifierBufferPool = @import("clear_borrow_ctx.zig").VerifierBufferPool;
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const allocDefaultMask = @import("reg_state_change.zig").allocDefaultMask;
const assignValue = @import("collect_metadata.zig").assignValue;
const attachInteriorChild = @import("snapshot_merge_state_in_scope.zig").attachInteriorChild;
const builtinArgSpec = @import("sax_trap_report.zig").builtinArgSpec;
const builtinGrantRequirement = @import("sax_trap_report.zig").builtinGrantRequirement;
const builtinReturnCap = @import("sax_trap_report.zig").builtinReturnCap;
const callPrefixMatchesParam = @import("sax_trap_report.zig").callPrefixMatchesParam;
const captureLabelSnapshot = @import("const_trap.zig").captureLabelSnapshot;
const checkAtomicOrdering = @import("const_trap.zig").checkAtomicOrdering;
const checkExitLeaks = @import("clear_borrow_ctx.zig").checkExitLeaks;
const checkStaticOffsetInBounds = @import("snapshot_merge_state_in_scope.zig").checkStaticOffsetInBounds;
const clearBorrow = @import("clear_borrow_ctx.zig").clearBorrow;
const computeFunctionConsumedRegs = @import("snapshot_merge_state_in_scope.zig").computeFunctionConsumedRegs;
const constTrap = @import("const_trap.zig").constTrap;
const consumeAtContractBoundary = @import("clear_borrow_ctx.zig").consumeAtContractBoundary;
const consumeInteriorValue = @import("snapshot_merge_state_in_scope.zig").consumeInteriorValue;
const consumeSourceValue = @import("collect_metadata.zig").consumeSourceValue;
const diffState = @import("clear_borrow_ctx.zig").diffState;
const freeAnnotated = @import("clear_borrow_ctx.zig").freeAnnotated;
const hasActiveBorrowRefs = @import("const_trap.zig").hasActiveBorrowRefs;
const hasInteriorTree = @import("const_trap.zig").hasInteriorTree;
const hasOverlappingInteriorBorrow = @import("snapshot_merge_state_in_scope.zig").hasOverlappingInteriorBorrow;
const isConstData = @import("reg_state_change.zig").isConstData;
const isDecl = @import("const_trap.zig").isDecl;
const isExecKind = @import("const_trap.zig").isExecKind;
const isIdentLike = @import("reg_state_change.zig").isIdentLike;
const isImmutableConst = @import("reg_state_change.zig").isImmutableConst;
const isStackAllocated = @import("collect_metadata.zig").isStackAllocated;
const localizeInstructionRegs = @import("sax_trap_report.zig").localizeInstructionRegs;
const markBranchCondition = @import("clear_borrow_ctx.zig").markBranchCondition;
const maskOf = @import("reg_state_change.zig").maskOf;
const packageGrantAllowsEntry = @import("sax_trap_report.zig").packageGrantAllowsEntry;
const packageGrantEntry = @import("sax_trap_report.zig").packageGrantEntry;
const panicMsgAllowsRawArg = @import("sax_trap_report.zig").panicMsgAllowsRawArg;
const parseAllocSizeOperand = @import("snapshot_merge_state_in_scope.zig").parseAllocSizeOperand;
const parseInstructionCallForLocalizedVerifier = @import("sax_trap_report.zig").parseInstructionCallForLocalizedVerifier;
const phiStateConflictReport = @import("snapshot_merge_state_in_scope.zig").phiStateConflictReport;
const readCheck = @import("collect_metadata.zig").readCheck;
const readCheckAllowRaw = @import("sax_trap_report.zig").readCheckAllowRaw;
const recordAllocSize = @import("snapshot_merge_state_in_scope.zig").recordAllocSize;
const regFlagEphemeralScalar = @import("reg_state_change.zig").regFlagEphemeralScalar;
const regFlagImmutable = @import("reg_state_change.zig").regFlagImmutable;
const regFlagRawPointer = @import("reg_state_change.zig").regFlagRawPointer;
const regFlagStackAlloc = @import("reg_state_change.zig").regFlagStackAlloc;
const resetLabels = @import("clear_borrow_ctx.zig").resetLabels;
const resolveScopedRegId = @import("sax_trap_report.zig").resolveScopedRegId;
const saxReport = @import("sax_trap_report.zig").saxReport;
const seedConstSymbols = @import("const_trap.zig").seedConstSymbols;
const setBorrowState = @import("collect_metadata.zig").setBorrowState;
const setInteriorOffsetFromBase = @import("snapshot_merge_state_in_scope.zig").setInteriorOffsetFromBase;
const snapshotFirstMismatch = @import("const_trap.zig").snapshotFirstMismatch;
const snapshotFirstMismatchInScope = @import("const_trap.zig").snapshotFirstMismatchInScope;
const snapshotMergeCompatible = @import("const_trap.zig").snapshotMergeCompatible;
const snapshotMergeState = @import("const_trap.zig").snapshotMergeState;
const snapshotMergeStateInScope = @import("snapshot_merge_state_in_scope.zig").snapshotMergeStateInScope;
const snapshotStatesCompatible = @import("const_trap.zig").snapshotStatesCompatible;
const staticByteOffset = @import("snapshot_merge_state_in_scope.zig").staticByteOffset;
const trapReport = @import("snapshot_merge_state_in_scope.zig").trapReport;
const trapReportFromText = @import("sax_trap_report.zig").trapReportFromText;
const updateLabel = @import("clear_borrow_ctx.zig").updateLabel;
const writeCheck = @import("collect_metadata.zig").writeCheck;

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
    var snapshot_scratch: []u16 = &.{};
    defer allocator.free(snapshot_scratch);
    std.debug.assert(classified_lines.len == instructions.len);
    var sig_index = sig_index_start;
    var state: []u16 = &.{};
    var flags: []u8 = &.{};
    var origins: []?u32 = &.{};
    var locks: []u16 = &.{};
    var consumed_in_function: []bool = &.{};
    var interior_parent: []?u32 = &.{};
    var interior_first_child: []?u32 = &.{};
    var interior_next_sibling: []?u32 = &.{};
    var interior_root: []?u32 = &.{};
    var interior_offset: []u64 = &.{};
    var interior_offset_known: []bool = &.{};
    var alloc_size: []u64 = &.{};
    var alloc_size_known: []bool = &.{};
    var buffers = VerifierBufferPool.init(allocator);
    defer buffers.deinit();
    var current_scope: ?FunctionRegScope = null;
    defer {
        if (current_scope) |*scope| scope.deinit();
    }
    var interior = InteriorContext{
        .state = state,
        .interior_parent = interior_parent,
        .interior_first_child = interior_first_child,
        .interior_next_sibling = interior_next_sibling,
        .interior_root = interior_root,
        .interior_offset = interior_offset,
        .interior_offset_known = interior_offset_known,
        .alloc_size = alloc_size,
        .alloc_size_known = alloc_size_known,
    };
    var atomic_history = std.AutoHashMap(u64, u8).init(allocator);
    defer atomic_history.deinit();

    var labels = std.AutoHashMap(u32, LabelSnapshot).init(allocator);
    defer {
        var it = labels.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(allocator);
        labels.deinit();
    }
    var defined_labels = std.AutoHashMap(u32, void).init(allocator);
    defer defined_labels.deinit();

    var annotated = std.array_list.Managed(AnnotatedInstruction).init(allocator);
    var completed = false;
    defer {
        if (!completed) {
            freeAnnotated(allocator, &annotated);
        }
    }

    var current_function_text: ?[]const u8 = null;
    var current_is_ffi_wrapper = false;
    var current_sig: ?sig.FunctionSig = null;
    var body_seen = false;
    var terminated = false;
    var fatal_terminated = false;
    var gas_alloc_bytes: u64 = 0;
    var gas_steps: u64 = 0;
    const call_depth: u16 = 0;
    var has_unbounded_loop = false;
    var last_seen_label: ?u32 = null;
    // TRAP-PRECEDENCE: an exit leak is the LAST event of its function
    // in execution order (its return). A trap raised anywhere the
    // program reaches before that return -- in particular a call-site
    // trap in a caller, which fires before the callee body runs at
    // all -- must win over it, even when the leaking function is
    // declared (and therefore verified) earlier in the stream. So a
    // boundary exit leak is recorded here and only reported once the
    // whole stream has been verified with no other trap.
    var deferred_exit_leak: ?trap.TrapReport = null;

    for (instructions, 0..) |raw_item, inst_idx| {
        var item = raw_item;
        const classified = classified_lines[inst_idx];

        if (isDecl(item.kind)) {
            if (body_seen and !terminated and current_function_text != null) {
                return trapReport(.fallthrough_forbidden, item, current_function_text, current_is_ffi_wrapper, null, null, null, "basic blocks must end with jmp, br, br_null, or return", "insert an explicit terminator before the next declaration");
            }

            // HOST-VERIFIER-SCOPE: check the just-finished function's
            // exit state here, before its registers are reset for the
            // next function. The end-of-stream check below only ever
            // sees the last function; without this, a leak in any
            // earlier function is silently dropped. The trap location
            // is the previous function's terminator (the instruction
            // just before this declaration).
            if (check_exit_leaks and body_seen and terminated and !fatal_terminated) {
                if (checkExitLeaks(state, flags, origins, consumed_in_function, if (current_scope) |*s| s else null, metadata, sax_context, instructions[inst_idx - 1], current_function_text, current_is_ffi_wrapper)) |trap_result| {
                    // TRAP-PRECEDENCE: defer, do not return yet (see
                    // deferred_exit_leak above). The first exit leak in
                    // stream order is kept; any trap raised by a later
                    // instruction returns immediately and wins.
                    if (deferred_exit_leak == null) {
                        deferred_exit_leak = switch (trap_result) {
                            .trap => |report| report,
                            .ok => null,
                        };
                    }
                }
            }

            current_function_text = item.raw_text;
            current_is_ffi_wrapper = item.kind == .ffi_wrapper_decl;
            last_seen_label = null;
            terminated = false;
            fatal_terminated = false;
            body_seen = false;
            resetLabels(allocator, &labels);

            if (sig_index < metadata.sigs.items.len) {
                current_sig = metadata.sigs.items[sig_index];
                sig_index += 1;
            } else {
                current_sig = null;
            }

            if (current_scope) |*scope| scope.deinit();
            current_scope = null;
            state = &.{};
            flags = &.{};
            origins = &.{};
            locks = &.{};
            consumed_in_function = &.{};
            interior_parent = &.{};
            interior_first_child = &.{};
            interior_next_sibling = &.{};
            interior_root = &.{};
            interior_offset = &.{};
            interior_offset_known = &.{};
            alloc_size = &.{};
            alloc_size_known = &.{};

            if (current_sig) |decl_sig| {
                var next_scope = try FunctionRegScope.initBorrowed(allocator, decl_sig.reg_ids);
                errdefer next_scope.deinit();
                const reg_count = next_scope.reg_ids.len;
                buffers.ensureCapacity(reg_count) catch {
                    current_scope = null;
                    return .{ .trap = trapReportFromText(.arena_oom, 1, 1, item.raw_text, "unable to allocate verifier state", null) };
                };
                state = buffers.state[0..reg_count];
                @memset(state, 0);
                flags = buffers.flags[0..reg_count];
                @memset(flags, 0);
                origins = buffers.origins[0..reg_count];
                @memset(origins, null);
                locks = buffers.locks[0..reg_count];
                @memset(locks, 0);
                consumed_in_function = buffers.consumed_in_function[0..reg_count];
                @memset(consumed_in_function, false);
                interior_parent = buffers.interior_parent[0..reg_count];
                @memset(interior_parent, null);
                interior_first_child = buffers.interior_first_child[0..reg_count];
                @memset(interior_first_child, null);
                interior_next_sibling = buffers.interior_next_sibling[0..reg_count];
                @memset(interior_next_sibling, null);
                interior_root = buffers.interior_root[0..reg_count];
                @memset(interior_root, null);
                interior_offset = buffers.interior_offset[0..reg_count];
                @memset(interior_offset, 0);
                interior_offset_known = buffers.interior_offset_known[0..reg_count];
                @memset(interior_offset_known, false);
                alloc_size = buffers.alloc_size[0..reg_count];
                @memset(alloc_size, 0);
                alloc_size_known = buffers.alloc_size_known[0..reg_count];
                @memset(alloc_size_known, false);
                interior = .{
                    .state = state,
                    .interior_parent = interior_parent,
                    .interior_first_child = interior_first_child,
                    .interior_next_sibling = interior_next_sibling,
                    .interior_root = interior_root,
                    .interior_offset = interior_offset,
                    .interior_offset_known = interior_offset_known,
                    .alloc_size = alloc_size,
                    .alloc_size_known = alloc_size_known,
                };
                current_scope = next_scope;
                computeFunctionConsumedRegs(allocator, instructions, inst_idx, &metadata.symbols, &current_scope.?, consumed_in_function);
                errdefer {
                    if (current_scope) |*scope| scope.deinit();
                    current_scope = null;
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
                        current_function_text,
                        current_is_ffi_wrapper,
                        null,
                        null,
                        null,
                        "corrupted function signature: parameter count exceeds param_ids count",
                        "rebuild the module from source; the artifact's signature metadata is inconsistent",
                    );
                }
                for (decl_sig.params, 0..) |param, pidx| {
                    const reg_id = decl_sig.param_ids[pidx];
                    const reg_slot = current_scope.?.slotOf(reg_id) orelse {
                        return trapReport(
                            .corrupted_signature,
                            item,
                            current_function_text,
                            current_is_ffi_wrapper,
                            param.name,
                            null,
                            null,
                            "corrupted function signature: parameter references a register id that is not declared in this function scope",
                            "rebuild the module from source; the artifact's param_ids are inconsistent with its register scope",
                        );
                    };
                    const reg_idx: usize = @intCast(reg_slot);
                    state[reg_idx] = switch (param.cap) {
                        .by_value, .move => maskOf(.active),
                        .borrow => maskOf(.active) | maskOf(.borrow_view) | maskOf(.locked_read),
                        .raw => maskOf(.untracked),
                    };
                    flags[reg_idx] = if (param.cap == .raw) regFlagRawPointer else 0;
                    if (param.cap == .borrow) {
                        origins[reg_idx] = reg_slot;
                        locks[reg_idx] = 1;
                    }
                }
            } else {
                current_scope = null;
            }

            atomic_history.clearRetainingCapacity();
            defined_labels.clearRetainingCapacity();
            if (current_scope) |scope| {
                seedConstSymbols(state, flags, &scope, &metadata.const_ids);
            }

            try annotated.append(.{
                .base = item,
                .delta = .{ .changes = &.{} },
                .gas_step_cost = 0,
            });
            continue;
        }

        if (fatal_terminated and item.kind != .label) {
            continue;
        }

        if (terminated) {
            if (!isDecl(item.kind) and item.kind != .label) {
                return trapReport(.fallthrough_forbidden, item, current_function_text, current_is_ffi_wrapper, null, null, null, "basic blocks must end with jmp, br, br_null, or return", "insert an explicit terminator before the next declaration");
            }
            terminated = false;
            fatal_terminated = false;
        }

        if (current_scope) |*scope| {
            if (localizeInstructionRegs(&item, scope, &metadata.symbols, current_function_text, current_is_ffi_wrapper)) |tr| {
                return tr;
            }
        }

        if (item.kind == .label) {
            last_seen_label = item.operands[1].label;
            if (defined_labels.contains(item.operands[1].label)) {
                return trapReport(.duplicate_label, item, current_function_text, current_is_ffi_wrapper, null, null, null, "label is already defined", "rename the label or merge the blocks");
            }
            if (updateLabel(item, &labels, state, origins, locks, flags, interior_parent, interior_first_child, interior_next_sibling, interior_root, interior_offset, interior_offset_known, alloc_size, alloc_size_known, allocator, current_function_text, current_is_ffi_wrapper)) |tr| {
                return tr;
            }
            defined_labels.put(item.operands[1].label, {}) catch {
                return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label definition", null);
            };
            try annotated.append(.{
                .base = item,
                .delta = .{ .changes = &.{} },
                .gas_step_cost = 0,
            });
            continue;
        }

        if (!isExecKind(item.kind)) {
            try annotated.append(.{
                .base = item,
                .delta = .{ .changes = &.{} },
                .gas_step_cost = 0,
            });
            continue;
        }

        body_seen = true;
        gas_steps += 1;
        if (snapshot_scratch.len < state.len) {
            const grown = try allocator.alloc(u16, state.len);
            allocator.free(snapshot_scratch);
            snapshot_scratch = grown;
        }
        const snapshot_before = snapshot_scratch[0..state.len];
        @memcpy(snapshot_before, state);

        switch (item.kind) {
            .alloc => {
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, allocDefaultMask(default_immutable), &interior)) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = 0;
                recordAllocSize(&interior, item.operands[0].reg, parseAllocSizeOperand(item.operands[1]));
                gas_alloc_bytes += switch (item.operands[1]) {
                    .imm_u64 => |v| v,
                    .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .text => |t| std.fmt.parseInt(u64, t, 10) catch 0,
                    else => 0,
                };
            },
            .stack_alloc => {
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, allocDefaultMask(default_immutable), &interior)) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = regFlagStackAlloc;
                recordAllocSize(&interior, item.operands[0].reg, parseAllocSizeOperand(item.operands[1]));
                gas_alloc_bytes += switch (item.operands[1]) {
                    .imm_u64 => |v| v,
                    .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .text => |t| std.fmt.parseInt(u64, t, 10) catch 0,
                    else => 0,
                };
            },
            .load, .take => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (checkStaticOffsetInBounds(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], &interior, origins, state, item.operands[1].reg, staticByteOffset(item.operands[2]))) |tr| return tr;
                const loaded_ty: sig.PrimType = if (item.operands[3] == .ty) blk: {
                    break :blk sig.primTypeFromTag(item.operands[3].ty) orelse if (item.kind == .take) .ptr else .i64;
                } else if (item.kind == .take) .ptr else .i64;
                const source_idx: usize = @intCast(item.operands[1].reg);
                const source_mask = state[source_idx];
                const load_is_borrowed_ptr =
                    loaded_ty == .ptr and
                    ((source_mask & (maskOf(.borrow_view) | maskOf(.ffi_borrow))) != 0);
                const new_mask = maskOf(.active) | if (load_is_borrowed_ptr) maskOf(.interior_ptr) else 0;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, new_mask, &interior)) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = if (item.kind == .load) (if (loaded_ty == .ptr) regFlagRawPointer else regFlagEphemeralScalar) else 0;
                if (item.kind == .take and ((source_mask & (maskOf(.borrow_view) | maskOf(.ffi_borrow) | maskOf(.interior_ptr))) != 0 or hasInteriorTree(state, interior_first_child, item.operands[1].reg))) {
                    attachInteriorChild(state, interior_parent, interior_first_child, interior_next_sibling, item.operands[1].reg, item.operands[0].reg);
                    setInteriorOffsetFromBase(&interior, item.operands[1].reg, item.operands[0].reg, staticByteOffset(item.operands[2]));
                }
            },
            .store => {
                if (sax_context) |ctx| {
                    const trimmed = std.mem.trim(u8, item.raw_text, " \t\r");
                    if (std.mem.startsWith(u8, trimmed, "store state+") and !current_is_ffi_wrapper) {
                        return saxReport(ctx, .sax_state_write_from_outside, item, classified.parts[0], null, null, "state slot written from outside component", null);
                    }
                }
                if (writeCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, origins, locks)) |tr| return tr;
                if (checkStaticOffsetInBounds(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], &interior, origins, state, item.operands[0].reg, staticByteOffset(item.operands[1]))) |tr| return tr;
                const dst_idx: usize = @intCast(item.operands[0].reg);
                if ((state[dst_idx] & maskOf(.borrow_view)) != 0) {
                    const origin_id = origins[dst_idx] orelse unreachable;
                    const origin_idx: usize = @intCast(origin_id);
                    if (origin_idx < state.len and state[origin_idx] == maskOf(.locked_read)) {
                        state[origin_idx] = maskOf(.locked_mut);
                    }
                }
                if (item.operands[2] == .text and isIdentLike(item.operands[2].text)) {
                    if (current_scope) |scope| {
                        if (resolveScopedRegId(&scope, &metadata.symbols, item.operands[2].text)) |value_id| {
                            if (readCheck(item, current_function_text, current_is_ffi_wrapper, item.operands[2].text, value_id, state, flags)) |tr| return tr;
                        }
                    }
                }
            },
            .atomic_load => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, maskOf(.untracked), &interior)) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = regFlagEphemeralScalar;
            },
            .atomic_store => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[0].reg, state, flags)) |tr| return tr;
                if (item.operands[2] == .text and isIdentLike(item.operands[2].text)) {
                    if (current_scope) |scope| {
                        if (resolveScopedRegId(&scope, &metadata.symbols, item.operands[2].text)) |value_id| {
                            if (readCheck(item, current_function_text, current_is_ffi_wrapper, item.operands[2].text, value_id, state, flags)) |tr| return tr;
                        }
                    }
                }
            },
            .cmpxchg => {
                if (checkAtomicOrdering(item, current_function_text, current_is_ffi_wrapper, &atomic_history)) |tr| return tr;
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[2].reg, state, flags)) |tr| return tr;
                if (item.operands[3] == .imm_u64) {
                    _ = item.operands[3].imm_u64;
                }
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, maskOf(.active), &interior)) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags, maskOf(.active), &interior)) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = 0;
                flags[@intCast(item.operands[1].reg)] = 0;
            },
            .atomic_rmw => {
                if (checkAtomicOrdering(item, current_function_text, current_is_ffi_wrapper, &atomic_history)) |tr| return tr;
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (item.operands[3] == .text and isIdentLike(item.operands[3].text)) {
                    if (current_scope) |scope| {
                        if (resolveScopedRegId(&scope, &metadata.symbols, item.operands[3].text)) |value_id| {
                            if (readCheck(item, current_function_text, current_is_ffi_wrapper, item.operands[3].text, value_id, state, flags)) |tr| return tr;
                        }
                    }
                }
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, maskOf(.active), &interior)) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = regFlagEphemeralScalar;
            },
            .fence => {},
            .op => {
                inline for ([_]usize{ 1, 2, 3 }) |op_idx| {
                    if (op_idx >= item.operands.len) break;
                    const part_idx = op_idx + 1;
                    if (part_idx >= classified.part_count) break;
                    switch (item.operands[op_idx]) {
                        .reg => |id| if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[part_idx], id, state, flags)) |tr| return tr,
                        .text => |text| if (isIdentLike(text)) {
                            if (current_scope) |scope| {
                                if (resolveScopedRegId(&scope, &metadata.symbols, text)) |id| {
                                    if (readCheck(item, current_function_text, current_is_ffi_wrapper, text, id, state, flags)) |tr| return tr;
                                } else {
                                    return trapReport(.unknown_register, item, current_function_text, current_is_ffi_wrapper, text, null, null, "register is not declared in the current scope", null);
                                }
                            } else {
                                return trapReport(.unknown_register, item, current_function_text, current_is_ffi_wrapper, text, null, null, "register is not declared in the current scope", null);
                            }
                        },
                        else => {},
                    }
                }
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, maskOf(.untracked), &interior)) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = 0;
            },
            .ptr_add => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (item.operands[2] == .reg) {
                    if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[2], item.operands[2].reg, state, flags)) |tr| return tr;
                } else if (item.operands[2] == .text and isIdentLike(item.operands[2].text)) {
                    if (current_scope) |scope| {
                        if (resolveScopedRegId(&scope, &metadata.symbols, item.operands[2].text)) |value_id| {
                            if (readCheck(item, current_function_text, current_is_ffi_wrapper, item.operands[2].text, value_id, state, flags)) |tr| return tr;
                        }
                    }
                }
                const src_idx: usize = @intCast(item.operands[1].reg);
                const has_field_identity = (state[src_idx] & (maskOf(.active) | maskOf(.borrow_view) | maskOf(.locked_read) | maskOf(.locked_mut) | maskOf(.interior_ptr))) != 0;
                const has_borrow_lifetime = (state[src_idx] & (maskOf(.borrow_view) | maskOf(.ffi_borrow) | maskOf(.interior_ptr))) != 0 or hasInteriorTree(state, interior_first_child, item.operands[1].reg);
                // Static OOB check before linking the child: forming an
                // out-of-bounds derived pointer is rejected even if it is
                // never dereferenced.
                if (checkStaticOffsetInBounds(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], &interior, origins, state, item.operands[1].reg, staticByteOffset(item.operands[2]))) |tr| return tr;
                const dst_mask: u16 = if (has_borrow_lifetime) maskOf(.active) | maskOf(.interior_ptr) else maskOf(.active);
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, dst_mask, &interior)) |tr| return tr;
                if (has_borrow_lifetime) {
                    attachInteriorChild(state, interior_parent, interior_first_child, interior_next_sibling, item.operands[1].reg, item.operands[0].reg);
                }
                if (has_field_identity) {
                    setInteriorOffsetFromBase(&interior, item.operands[1].reg, item.operands[0].reg, staticByteOffset(item.operands[2]));
                }
                flags[@intCast(item.operands[0].reg)] = 0;
            },
            .borrow => {
                const source_reg: u32 = blk: {
                    if (item.operands[1] == .reg) break :blk item.operands[1].reg;
                    if (item.operands[2] == .reg) break :blk item.operands[2].reg;
                    return trapReport(.forbidden_syntax, item, current_function_text, current_is_ffi_wrapper, null, null, null, "invalid borrow syntax", null);
                };
                const mode_text: []const u8 = blk: {
                    if (item.operands[1] == .text) break :blk item.operands[1].text;
                    if (item.operands[2] == .text) break :blk item.operands[2].text;
                    return trapReport(.forbidden_syntax, item, current_function_text, current_is_ffi_wrapper, null, null, null, "invalid borrow syntax", null);
                };
                const is_mut = std.mem.eql(u8, mode_text, "mut");
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[2], source_reg, state, flags)) |tr| return tr;
                if (is_mut) {
                    const source_idx: usize = @intCast(source_reg);
                    if (isConstData(flags, source_reg)) {
                        return constTrap(item, current_function_text, current_is_ffi_wrapper, classified.parts[2], state[source_idx], "immutable registers cannot be exclusively borrowed");
                    }
                    if ((state[source_idx] & maskOf(.borrow_view)) != 0 or locks[source_idx] != 0) {
                        return trapReport(.read_write_conflict, item, current_function_text, current_is_ffi_wrapper, classified.parts[2], maskOf(.active), state[source_idx], "cannot borrow mut while shared borrows are active", null);
                    }
                    if (hasOverlappingInteriorBorrow(&interior, locks, source_reg)) {
                        return trapReport(.read_write_conflict, item, current_function_text, current_is_ffi_wrapper, classified.parts[2], maskOf(.active), state[source_idx], "cannot borrow mut while overlapping field borrows are active", null);
                    }
                    if ((state[source_idx] & maskOf(.locked_mut)) != 0) {
                        return trapReport(.double_mutable_borrow, item, current_function_text, current_is_ffi_wrapper, classified.parts[2], maskOf(.active), state[source_idx], "cannot borrow mut more than once", null);
                    }
                }
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, maskOf(.active) | maskOf(.borrow_view), &interior)) |tr| return tr;
                setBorrowState(state, flags, origins, locks, item.operands[0].reg, source_reg, is_mut, false);
            },
            .move_ => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
                if (consumeSourceValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, origins, locks, interior_parent, interior_first_child, interior_next_sibling, false, &interior)) |tr| return tr;
            },
            .transfer => {
                // `transfer <container>, <value>`: ownership of `value` moves
                // into `container`. Verifier-visible annotation (runtime
                // no-op); the preceding `store` already did the data move.
                if (item.operands[0] != .reg or item.operands[1] != .reg) {
                    return trapReport(.transfer_into_borrow, item, current_function_text, current_is_ffi_wrapper, null, null, null, "transfer requires register operands", null);
                }
                const ci: usize = @intCast(item.operands[0].reg);
                // Destination must be a live OWNED root. Transferring into a
                // borrow view / interior pointer would leak the value when the
                // borrow ends -- this is the check the old bare `^` marker
                // (emitForgetMovedValue) could never perform.
                const cmask = state[ci];
                if ((cmask & (maskOf(.borrow_view) | maskOf(.ffi_borrow) | maskOf(.interior_ptr))) != 0 or
                    hasInteriorTree(state, interior_first_child, item.operands[0].reg))
                {
                    return trapReport(.transfer_into_borrow, item, current_function_text, current_is_ffi_wrapper, classified.parts[0], maskOf(.active), cmask, "cannot transfer ownership into a borrowed container", null);
                }
                // Use the combined predicate: an @const hard constant (flag)
                // OR a Rust-style immutable binding (capability bit 0x0100).
                // A transfer writes ownership into the container, so an
                // immutable binding must reject it just as const data does.
                if (isImmutableConst(state, flags, item.operands[0].reg)) {
                    return trapReport(.transfer_into_immutable, item, current_function_text, current_is_ffi_wrapper, classified.parts[0], maskOf(.active), cmask, "cannot transfer ownership into an immutable container", null);
                }
                if ((cmask & maskOf(.active)) == 0) {
                    return trapReport(.use_after_move, item, current_function_text, current_is_ffi_wrapper, classified.parts[0], maskOf(.active), cmask, "cannot transfer into a consumed container", null);
                }
                if (hasActiveBorrowRefs(locks, item.operands[0].reg)) {
                    return trapReport(.borrow_conflict, item, current_function_text, current_is_ffi_wrapper, classified.parts[0], maskOf(.active), cmask, "container has active borrows", null);
                }
                // Value retires exactly like a `^` move-out -> Consumed, so
                // the function-exit leak check is satisfied without an
                // opaque emitter-side marker.
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (consumeSourceValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags, origins, locks, interior_parent, interior_first_child, interior_next_sibling, false, &interior)) |tr| return tr;
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
                state[ci] |= maskOf(.owns_children);
            },
            .assign => {
                const dst_id = item.operands[0].reg;
                const source_is_ephemeral = switch (item.operands[1]) {
                    .imm_i64, .imm_u64, .imm_int, .imm_float => true,
                    .reg => |src| (flags[@intCast(src)] & regFlagEphemeralScalar) != 0,
                    else => false,
                };
                if (item.operands[1] == .reg and item.operands[1].reg != dst_id) {
                    if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                }
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], dst_id, state, flags, maskOf(.active), &interior)) |tr| return tr;
                if (item.operands[1] == .reg) {
                    const src_flags = flags[@intCast(item.operands[1].reg)];
                    if ((src_flags & regFlagRawPointer) != 0) {
                        flags[@intCast(dst_id)] |= regFlagRawPointer;
                    }
                }
                if (source_is_ephemeral) {
                    flags[@intCast(dst_id)] = regFlagEphemeralScalar;
                }
                if (item.operands[1] == .reg and item.operands[1].reg != dst_id) {
                    if (consumeSourceValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags, origins, locks, interior_parent, interior_first_child, interior_next_sibling, true, &interior)) |tr| return tr;
                }
            },
            .release => {
                const idx: usize = @intCast(item.operands[0].reg);
                if ((state[idx] & maskOf(.borrow_view)) != 0) {
                    clearBorrow(state, flags, origins, locks, item.operands[0].reg, &interior);
                } else if ((flags[idx] & (regFlagRawPointer | regFlagEphemeralScalar)) != 0 and
                    state[idx] == maskOf(.active))
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
                    if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
                } else {
                    if (isConstData(flags, item.operands[0].reg)) {
                        return constTrap(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], state[idx], "immutable registers cannot be released");
                    }
                    if (hasActiveBorrowRefs(locks, item.operands[0].reg)) {
                        return trapReport(.borrow_conflict, item, current_function_text, current_is_ffi_wrapper, classified.parts[0], maskOf(.active), state[idx], "borrow rules reject this access", null);
                    }
                    if (isStackAllocated(flags, origins, state, item.operands[0].reg)) {
                        return trapReport(.stack_escape, item, current_function_text, current_is_ffi_wrapper, classified.parts[0], maskOf(.active), state[idx], "stack allocation cannot be released explicitly", null);
                    }
                    if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
                    if (hasInteriorTree(state, interior_first_child, item.operands[0].reg)) {
                        consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, item.operands[0].reg);
                    } else {
                        state[idx] = maskOf(.consumed);
                    }
                }
            },
            .raw_cast => {
                if (!current_is_ffi_wrapper) return trapReport(.illegal_unsafe_context, item, current_function_text, current_is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, maskOf(.untracked), &interior)) |tr| return tr;
            },
            .assume_safe => {
                if (!current_is_ffi_wrapper) return trapReport(.illegal_unsafe_context, item, current_function_text, current_is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, maskOf(.active), &interior)) |tr| return tr;
                // A safe pointer carries no more ownership than the raw
                // pointer it reinterprets: propagate the raw-pointer flag
                // from the input, like .assign does. A load of .ptr is
                // flagged regFlagRawPointer, so the db bench shape (f =
                // load vt+0 as ptr; s = assume_safe f) leaves s exempt
                // from the exit scan; assume_safe of an owned value stays
                // tracked (alloc never sets the flag), so the
                // move-while-aliased backstop is preserved.
                if ((flags[@intCast(item.operands[1].reg)] & regFlagRawPointer) != 0) {
                    flags[@intCast(item.operands[0].reg)] |= regFlagRawPointer;
                }
            },
            .assume_borrow => {
                if (!current_is_ffi_wrapper) return trapReport(.illegal_unsafe_context, item, current_function_text, current_is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                const is_mut = item.operands[2] == .text and std.mem.eql(u8, item.operands[2].text, "mut");
                if (is_mut and isConstData(flags, item.operands[1].reg)) {
                    return constTrap(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], state[@intCast(item.operands[1].reg)], "immutable registers cannot be exclusively borrowed");
                }
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, maskOf(.active) | maskOf(.borrow_view), &interior)) |tr| return tr;
                setBorrowState(state, flags, origins, locks, item.operands[0].reg, item.operands[1].reg, is_mut, true);
            },
            .native => {
                for (item.native_reg_names) |name| {
                    if (!isIdentLike(name)) continue;
                    if (current_scope) |scope| {
                        if (resolveScopedRegId(&scope, &metadata.symbols, name)) |id| {
                            if (consumeAtContractBoundary(item, current_function_text, current_is_ffi_wrapper, name, id, state, flags, origins, locks, interior_parent, interior_first_child, interior_next_sibling, &interior)) |tr| return tr;
                        }
                    }
                }
            },
            .jmp => {
                const target = item.operands[1].label;
                if (defined_labels.contains(target)) has_unbounded_loop = true;
                if (labels.getPtr(target)) |entry| {
                    if (defined_labels.contains(target)) {
                        if (!snapshotStatesCompatible(entry, state)) {
                            const mismatch = if (current_scope) |scope|
                                snapshotFirstMismatchInScope(entry, state, &scope, &metadata.symbols)
                            else
                                snapshotFirstMismatch(entry, state, &metadata.symbols);
                            return phiStateConflictReport(item, current_function_text, current_is_ffi_wrapper, target, last_seen_label, mismatch, &metadata.symbols);
                        }
                    } else {
                        if (!snapshotMergeCompatible(entry, state)) {
                            const mismatch = if (current_scope) |scope|
                                snapshotMergeStateInScope(entry, state, &scope, &metadata.symbols)
                            else
                                snapshotMergeState(entry, state, &metadata.symbols);
                            return phiStateConflictReport(item, current_function_text, current_is_ffi_wrapper, target, last_seen_label, mismatch, &metadata.symbols);
                        }
                    }
                } else {
                    var snapshot = captureLabelSnapshot(allocator, state, origins, locks, flags, interior_parent, interior_first_child, interior_next_sibling, interior_root, interior_offset, interior_offset_known, alloc_size, alloc_size_known) catch {
                        return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
                    };
                    labels.put(target, snapshot) catch {
                        snapshot.deinit(allocator);
                        return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
                    };
                }
                terminated = true;
            },
            .br => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
                markBranchCondition(flags, item.operands[0].reg);
                for ([_]u32{ item.operands[1].label, item.operands[3].label }) |target| {
                    if (labels.getPtr(target)) |entry| {
                        if (defined_labels.contains(target)) {
                            if (!snapshotStatesCompatible(entry, state)) {
                                const mismatch = if (current_scope) |scope|
                                    snapshotFirstMismatchInScope(entry, state, &scope, &metadata.symbols)
                                else
                                    snapshotFirstMismatch(entry, state, &metadata.symbols);
                                return phiStateConflictReport(item, current_function_text, current_is_ffi_wrapper, target, last_seen_label, mismatch, &metadata.symbols);
                            }
                        } else {
                            if (!snapshotMergeCompatible(entry, state)) {
                                const mismatch = if (current_scope) |scope|
                                    snapshotMergeStateInScope(entry, state, &scope, &metadata.symbols)
                                else
                                    snapshotMergeState(entry, state, &metadata.symbols);
                                return phiStateConflictReport(item, current_function_text, current_is_ffi_wrapper, target, last_seen_label, mismatch, &metadata.symbols);
                            }
                        }
                    } else {
                        var snapshot = captureLabelSnapshot(allocator, state, origins, locks, flags, interior_parent, interior_first_child, interior_next_sibling, interior_root, interior_offset, interior_offset_known, alloc_size, alloc_size_known) catch {
                            return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
                        };
                        labels.put(target, snapshot) catch {
                            snapshot.deinit(allocator);
                            return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
                        };
                    }
                    if (defined_labels.contains(target)) has_unbounded_loop = true;
                }
                terminated = true;
            },
            .br_null => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
                markBranchCondition(flags, item.operands[0].reg);
                for ([_]u32{ item.operands[1].label, item.operands[3].label }) |target| {
                    if (labels.getPtr(target)) |entry| {
                        if (defined_labels.contains(target)) {
                            if (!snapshotStatesCompatible(entry, state)) {
                                const mismatch = if (current_scope) |scope|
                                    snapshotFirstMismatchInScope(entry, state, &scope, &metadata.symbols)
                                else
                                    snapshotFirstMismatch(entry, state, &metadata.symbols);
                                return phiStateConflictReport(item, current_function_text, current_is_ffi_wrapper, target, last_seen_label, mismatch, &metadata.symbols);
                            }
                        } else {
                            if (!snapshotMergeCompatible(entry, state)) {
                                const mismatch = if (current_scope) |scope|
                                    snapshotMergeStateInScope(entry, state, &scope, &metadata.symbols)
                                else
                                    snapshotMergeState(entry, state, &metadata.symbols);
                                return phiStateConflictReport(item, current_function_text, current_is_ffi_wrapper, target, last_seen_label, mismatch, &metadata.symbols);
                            }
                        }
                    } else {
                        var snapshot = captureLabelSnapshot(allocator, state, origins, locks, flags, interior_parent, interior_first_child, interior_next_sibling, interior_root, interior_offset, interior_offset_known, alloc_size, alloc_size_known) catch {
                            return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
                        };
                        labels.put(target, snapshot) catch {
                            snapshot.deinit(allocator);
                            return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
                        };
                    }
                    if (defined_labels.contains(target)) has_unbounded_loop = true;
                }
                terminated = true;
            },
            .call, .call_indirect, .panic, .panic_msg => {
                var parsed = parseInstructionCallForLocalizedVerifier(allocator, &metadata.symbols, if (current_scope) |*scope| scope else null, item) catch {
                    return trapReport(.forbidden_syntax, item, current_function_text, current_is_ffi_wrapper, null, null, null, "invalid call syntax", null);
                };
                defer parsed.deinit(allocator);

                if (sax_context) |ctx| {
                    if (std.mem.eql(u8, parsed.callee, "render") and !current_is_ffi_wrapper) {
                        return saxReport(ctx, .sax_render_outside_handler, item, parsed.dest, null, null, "call @render() is only legal inside @handler", null);
                    }
                }

                const sig_match: ?*const sig.FunctionSig = if (metadata.sig_index_by_name.get(parsed.callee)) |sig_idx| &metadata.sigs.items[sig_idx] else null;
                const builtin_spec = builtinArgSpec(parsed.callee);

                if (!parsed.is_indirect and sig_match == null and builtin_spec == null and !std.mem.startsWith(u8, parsed.callee, "sys_")) {
                    return trapReport(.unknown_register, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "callee is not declared", null);
                }

                if (!parsed.is_indirect and builtin_spec == null and std.mem.startsWith(u8, parsed.callee, "sys_")) {
                    return trapReport(.unsupported_sys_intrinsic, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "target runtime does not support this @sys_* intrinsic", null);
                }

                if (!parsed.is_indirect) {
                    if (builtinGrantRequirement(parsed.callee)) |required_grant| {
                        if (item.package_identity) |identity| {
                            const grant_entry = packageGrantEntry(identity, package_grants) orelse {
                                return trapReport(.unauthorized_primitive, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "package grants do not allow this @sys_* intrinsic", null);
                            };
                            if (!packageGrantAllowsEntry(grant_entry, required_grant)) {
                                return trapReport(.unauthorized_primitive, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "package grants do not allow this @sys_* intrinsic", null);
                            }
                            const package_hash = item.package_source_sha256 orelse {
                                return trapReport(.upstream_sha_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "package source hash does not match the granted requirement", null);
                            };
                            if (!std.mem.eql(u8, grant_entry.source_sha256[0..], package_hash[0..])) {
                                return trapReport(.upstream_sha_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "package source hash does not match the granted requirement", null);
                            }
                        }
                    }
                }

                if (!parsed.is_indirect) {
                    if (sig_match) |resolved| {
                        // Extern variadic batch: a variadic callee takes
                        // at least its fixed parameters; trailing
                        // arguments carry no ParamSpec contract and are
                        // not prefix-checked (their discipline is the
                        // language checker's promotion rules).
                        if (resolved.is_variadic) {
                            if (parsed.args.len < resolved.params.len) {
                                return trapReport(.capability_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                            }
                        } else if (resolved.params.len != parsed.args.len) {
                            return trapReport(.capability_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                        }
                        for (parsed.args[0..resolved.params.len], resolved.params) |arg, param| {
                            if (!callPrefixMatchesParam(param, arg.prefix)) {
                                return trapReport(.capability_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                            }
                        }
                    } else if (builtin_spec) |spec| {
                        if (spec.len != parsed.args.len) {
                            return trapReport(.capability_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                        }
                        for (parsed.args, spec) |arg, expected| {
                            if (arg.prefix != expected) {
                                return trapReport(.capability_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                            }
                        }
                    }
                }

                for (parsed.args, 0..) |arg, arg_idx| {
                    if (isIdentLike(arg.text)) {
                        if (current_scope) |scope| {
                            if (resolveScopedRegId(&scope, &metadata.symbols, arg.text)) |arg_id| {
                                const arg_reg_idx: usize = @intCast(arg_id);
                                if (metadata.sig_index_by_name.contains(arg.text)) {
                                    if (sig_match) |resolved| {
                                        if (arg_idx < resolved.params.len and resolved.params[arg_idx].ty == .ptr) {
                                            continue;
                                        }
                                    }
                                }
                                if (sig_match) |resolved| {
                                    if (arg.prefix != .borrow and (resolved.kind == .external or resolved.kind == .ffi_wrapper) and hasInteriorTree(state, interior_first_child, arg_id)) {
                                        return trapReport(.interior_ptr_escape, item, current_function_text, current_is_ffi_wrapper, arg.text, maskOf(.interior_ptr), state[arg_reg_idx], "interior pointers cannot cross FFI boundaries", null);
                                    }
                                }
                                switch (arg.prefix) {
                                    .borrow => if (readCheck(item, current_function_text, current_is_ffi_wrapper, arg.text, arg_id, state, flags)) |tr| return tr,
                                    .by_value => if (readCheck(item, current_function_text, current_is_ffi_wrapper, arg.text, arg_id, state, flags)) |tr| return tr,
                                    .raw => if (panicMsgAllowsRawArg(parsed.callee, parsed.args.len, arg_idx)) {
                                        if (readCheckAllowRaw(item, current_function_text, current_is_ffi_wrapper, arg.text, arg_id, state, flags)) |tr| return tr;
                                    } else {
                                        if (readCheck(item, current_function_text, current_is_ffi_wrapper, arg.text, arg_id, state, flags)) |tr| return tr;
                                    },
                                    .move => {
                                        if (isConstData(flags, arg_id)) {
                                            return constTrap(item, current_function_text, current_is_ffi_wrapper, arg.text, state[arg_reg_idx], "immutable registers cannot be moved");
                                        }
                                        if (readCheck(item, current_function_text, current_is_ffi_wrapper, arg.text, arg_id, state, flags)) |tr| return tr;
                                        if (isStackAllocated(flags, origins, state, arg_id)) {
                                            return trapReport(.stack_escape, item, current_function_text, current_is_ffi_wrapper, arg.text, maskOf(.active), state[@intCast(arg_id)], "stack allocation cannot be passed by move", null);
                                        }
                                        const move_arg_reg_idx: usize = @intCast(arg_id);
                                        if ((flags[move_arg_reg_idx] & regFlagRawPointer) != 0) {
                                            continue;
                                        }
                                        if ((state[move_arg_reg_idx] & maskOf(.borrow_view)) != 0) {
                                            clearBorrow(state, flags, origins, locks, arg_id, &interior);
                                        } else {
                                            if (hasInteriorTree(state, interior_first_child, arg_id)) {
                                                consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, arg_id);
                                            } else {
                                                state[move_arg_reg_idx] = maskOf(.consumed);
                                            }
                                        }
                                    },
                                }
                            } else if (sig_match) |resolved| {
                                if (arg_idx < resolved.params.len and resolved.params[arg_idx].ty == .ptr) {
                                    continue;
                                }
                                return trapReport(.unknown_register, item, current_function_text, current_is_ffi_wrapper, arg.text, null, null, "register is not declared in the current scope", null);
                            } else {
                                return trapReport(.unknown_register, item, current_function_text, current_is_ffi_wrapper, arg.text, null, null, "register is not declared in the current scope", null);
                            }
                        } else if (sig_match) |resolved| {
                            if (arg_idx < resolved.params.len and resolved.params[arg_idx].ty == .ptr) {
                                continue;
                            }
                            return trapReport(.unknown_register, item, current_function_text, current_is_ffi_wrapper, arg.text, null, null, "register is not declared in the current scope", null);
                        }
                    }
                }

                if (parsed.dest) |dest| {
                    if (isIdentLike(dest)) {
                        if (current_scope) |scope| {
                            if (resolveScopedRegId(&scope, &metadata.symbols, dest)) |dest_id| {
                                const idx: usize = @intCast(dest_id);
                                // The stdlib VEC_PUSH macro expands to:
                                //   %vec_reg = call @sa_vec_push(^%vec_reg, %value, %elem_size)
                                // In SA IR, `^` is the .move prefix (not .borrow; `&` is .borrow).
                                // This "update via move" pattern is legal SA: the dest is moved
                                // into the call via ^, then reassigned with the (mutated) result.
                                // SA-text verifies the EXPAND directive and never sees the expanded
                                // form; SAB contains the expanded instructions, so the SAB verifier
                                // must allow the pattern here to maintain SAB/SA-text parity.
                                // Note: if the moved arg has regFlagRawPointer, the .move handler
                                // above does `continue` without marking it consumed, so the dest
                                // check below would falsely report redefinition without this allowance.
                                var dest_is_moved_arg = false;
                                for (parsed.args) |arg| {
                                    if (arg.prefix != .move) continue;
                                    if (!isIdentLike(arg.text)) continue;
                                    if (resolveScopedRegId(&scope, &metadata.symbols, arg.text)) |arg_id| {
                                        if (arg_id == dest_id) {
                                            dest_is_moved_arg = true;
                                            break;
                                        }
                                    }
                                }
                                if (!dest_is_moved_arg and state[idx] != 0 and (state[idx] & maskOf(.consumed)) == 0 and (state[idx] & maskOf(.untracked)) == 0 and (flags[idx] & regFlagEphemeralScalar) == 0) {
                                    return trapReport(.register_redefinition, item, current_function_text, current_is_ffi_wrapper, dest, null, null, "register is already live", null);
                                }
                                if (isImmutableConst(state, flags, dest_id)) {
                                    return constTrap(item, current_function_text, current_is_ffi_wrapper, dest, state[idx], "immutable registers cannot be overwritten");
                                }
                                const ret_cap = if (parsed.is_indirect) null else if (sig_match) |resolved| resolved.return_cap else builtinReturnCap(parsed.callee);
                                const ret_state = if (!parsed.is_indirect) blk: {
                                    if (sig_match) |resolved| {
                                        if (resolved.return_fallible) break :blk maskOf(.fallible);
                                    }
                                    break :blk switch (ret_cap orelse .move) {
                                        .raw => maskOf(.untracked),
                                        .borrow => maskOf(.active) | maskOf(.borrow_view),
                                        .move, .by_value => maskOf(.active),
                                    };
                                } else blk: {
                                    break :blk switch (ret_cap orelse .move) {
                                        .raw => maskOf(.untracked),
                                        .borrow => maskOf(.active) | maskOf(.borrow_view),
                                        .move, .by_value => maskOf(.active),
                                    };
                                };
                                state[idx] = ret_state;
                                flags[idx] = 0;
                            }
                        }
                    }
                }

                if (item.kind == .panic or item.kind == .panic_msg) {
                    terminated = true;
                    fatal_terminated = true;
                }
            },
            .try_, .early_return => {
                const src_id = item.operands[1].reg;
                const dst_id = item.operands[0].reg;
                const src_idx: usize = @intCast(src_id);
                const src_mask = state[src_idx];
                if ((src_mask & maskOf(.fallible)) == 0) {
                    const src_name = current_scope.?.nameOf(&metadata.symbols, src_id) orelse metadata.symbols.lookupName(current_scope.?.globalId(src_id)) orelse "";
                    return trapReport(.fallible_contract_mismatch, item, current_function_text, current_is_ffi_wrapper, src_name, maskOf(.fallible), src_mask, "? can only be applied to fallible return values", null);
                }

                for (state, 0..) |mask, idx| {
                    if (idx == src_idx) continue;
                    if (mask == 0 or mask == maskOf(.consumed) or mask == maskOf(.untracked)) continue;
                    if ((mask & maskOf(.active)) == 0 and (mask & maskOf(.locked_read)) == 0 and (mask & maskOf(.locked_mut)) == 0) continue;
                    // Only const data is exempt from the leak check; an
                    // immutable binding still owns its allocation and must be
                    // released.
                    if ((flags[idx] & regFlagImmutable) != 0) continue;
                    if ((flags[idx] & regFlagEphemeralScalar) != 0) continue;
                    // Raw pointers carry no ownership (release is a no-op for
                    // them); a live raw-pointer temp is never a leak, same as
                    // an ephemeral scalar temp.
                    if ((flags[idx] & regFlagRawPointer) != 0) continue;
                    // Same const-borrow exemption as the function-exit scan
                    // (checkExitLeaks): a live borrow view of @const data is
                    // never a leak; a borrow view of an owned value is not
                    // exempted, so the scan stays the backstop for
                    // move-while-borrowed.
                    if ((mask & maskOf(.borrow_view)) != 0) {
                        const origin = origins[idx];
                        if (origin != null and isConstData(flags, origin.?)) continue;
                    }
                    if (isStackAllocated(flags, origins, state, @intCast(idx))) continue;
                    if (idx < consumed_in_function.len and consumed_in_function[idx]) continue;
                    const src_name = current_scope.?.nameOf(&metadata.symbols, src_id) orelse metadata.symbols.lookupName(current_scope.?.globalId(src_id)) orelse "";
                    return trapReport(.early_return_leak, item, current_function_text, current_is_ffi_wrapper, src_name, maskOf(.fallible), src_mask, "early return would leak live registers", null);
                }

                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], dst_id, state, flags, maskOf(.active), &interior)) |tr| return tr;
                flags[@intCast(dst_id)] = 0;
            },
            .return_ => {
                if (item.operands[0] == .reg) {
                    const ret_id = item.operands[0].reg;
                    const ret_name = current_scope.?.nameOf(&metadata.symbols, ret_id) orelse metadata.symbols.lookupName(current_scope.?.globalId(ret_id)) orelse item.operands[0].text;
                    const idx: usize = @intCast(ret_id);
                    if (readCheck(item, current_function_text, current_is_ffi_wrapper, ret_name, ret_id, state, flags)) |tr| {
                        return tr;
                    }
                    if ((state[idx] & maskOf(.fallible)) != 0) {
                        if (current_sig == null or current_sig.?.return_fallible == false) {
                            return trapReport(.fallible_contract_mismatch, item, current_function_text, current_is_ffi_wrapper, ret_name, maskOf(.fallible), state[idx], "fallible values must be propagated with ? or returned from a fallible function", null);
                        }
                        if (hasInteriorTree(state, interior_first_child, ret_id)) {
                            consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, ret_id);
                        } else {
                            state[idx] = maskOf(.consumed);
                        }
                    } else {
                        if ((state[idx] & maskOf(.borrow_view)) == 0 and hasActiveBorrowRefs(locks, ret_id)) {
                            return trapReport(.borrow_conflict, item, current_function_text, current_is_ffi_wrapper, ret_name, maskOf(.active), state[idx], "borrow rules reject this access", null);
                        }
                        if (isStackAllocated(flags, origins, state, ret_id)) {
                            return trapReport(.stack_escape, item, current_function_text, current_is_ffi_wrapper, ret_name, maskOf(.active), state[idx], "stack allocation cannot be returned", null);
                        }
                        if ((flags[idx] & regFlagRawPointer) == 0) {
                            if ((state[idx] & maskOf(.borrow_view)) != 0) {
                                clearBorrow(state, flags, origins, locks, ret_id, &interior);
                            } else if (hasInteriorTree(state, interior_first_child, ret_id)) {
                                consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, ret_id);
                            } else if ((state[idx] & maskOf(.untracked)) == 0) {
                                state[idx] = maskOf(.consumed);
                            }
                        }
                    }
                } else if (item.operands[0] == .text and isIdentLike(item.operands[0].text)) {
                    if (current_scope) |scope| {
                        if (resolveScopedRegId(&scope, &metadata.symbols, item.operands[0].text)) |ret_id| {
                            const idx: usize = @intCast(ret_id);
                            const ret_name = scope.nameOf(&metadata.symbols, ret_id) orelse item.operands[0].text;
                            if (readCheck(item, current_function_text, current_is_ffi_wrapper, item.operands[0].text, ret_id, state, flags)) |tr| {
                                return tr;
                            }
                            if (isConstData(flags, ret_id)) {
                                return constTrap(item, current_function_text, current_is_ffi_wrapper, ret_name, state[idx], "immutable registers cannot be returned by move");
                            }
                            if ((state[idx] & maskOf(.fallible)) != 0) {
                                if (current_sig == null or current_sig.?.return_fallible == false) {
                                    return trapReport(.fallible_contract_mismatch, item, current_function_text, current_is_ffi_wrapper, ret_name, maskOf(.fallible), state[idx], "fallible values must be propagated with ? or returned from a fallible function", null);
                                }
                                if (hasInteriorTree(state, interior_first_child, ret_id)) {
                                    consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, ret_id);
                                } else {
                                    state[idx] = maskOf(.consumed);
                                }
                            } else {
                                if ((state[idx] & maskOf(.borrow_view)) == 0 and hasActiveBorrowRefs(locks, ret_id)) {
                                    return trapReport(.borrow_conflict, item, current_function_text, current_is_ffi_wrapper, ret_name, maskOf(.active), state[idx], "borrow rules reject this access", null);
                                }
                                if (isStackAllocated(flags, origins, state, ret_id)) {
                                    return trapReport(.stack_escape, item, current_function_text, current_is_ffi_wrapper, ret_name, maskOf(.active), state[idx], "stack allocation cannot be returned", null);
                                }
                                if ((flags[idx] & regFlagRawPointer) == 0) {
                                    if ((state[idx] & maskOf(.borrow_view)) != 0) {
                                        clearBorrow(state, flags, origins, locks, ret_id, &interior);
                                    } else if (hasInteriorTree(state, interior_first_child, ret_id)) {
                                        consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, ret_id);
                                    } else if ((state[idx] & maskOf(.untracked)) == 0) {
                                        state[idx] = maskOf(.consumed);
                                    }
                                }
                            }
                        } else {
                            return trapReport(.unknown_register, item, current_function_text, current_is_ffi_wrapper, item.operands[0].text, null, null, "register is not declared in the current scope", null);
                        }
                    } else {
                        return trapReport(.unknown_register, item, current_function_text, current_is_ffi_wrapper, item.operands[0].text, null, null, "register is not declared in the current scope", null);
                    }
                }
                terminated = true;
            },
            .va_start => {
                // Extern variadic batch: the destination receives a
                // fresh raw pointer to this function's va_list object
                // (host-managed storage, no ownership payload), mirroring
                // the load-of-pointer state shape.
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, maskOf(.active), &interior)) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = regFlagRawPointer;
            },
            .va_arg => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags, maskOf(.active), &interior)) |tr| return tr;
                const read_ty: sig.PrimType = if (item.operands[2] == .ty) (sig.primTypeFromTag(item.operands[2].ty) orelse .i64) else .i64;
                flags[@intCast(item.operands[0].reg)] = if (read_ty == .ptr) regFlagRawPointer else regFlagEphemeralScalar;
            },
            .va_end => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
            },
            else => {},
        }

        const delta = try diffState(allocator, snapshot_before, state);
        errdefer {
            var owned = delta;
            owned.deinit(allocator);
        }
        try annotated.append(.{
            .base = item,
            .delta = delta,
            .gas_step_cost = if (isExecKind(item.kind)) 1 else 0,
        });
    }

    if (body_seen and !terminated) {
        return trapReport(.fallthrough_forbidden, instructions[instructions.len - 1], current_function_text, current_is_ffi_wrapper, null, null, null, "function body ended without a terminator", "end the last block with jmp, br, br_null, or return");
    }

    const current_is_bodyless_extern = current_sig != null and current_sig.?.kind == .external and !body_seen;
    if (check_exit_leaks and !fatal_terminated and !current_is_bodyless_extern) {
        if (checkExitLeaks(state, flags, origins, consumed_in_function, if (current_scope) |*s| s else null, metadata, sax_context, instructions[instructions.len - 1], current_function_text, current_is_ffi_wrapper)) |trap_result| {
            if (deferred_exit_leak == null) {
                deferred_exit_leak = switch (trap_result) {
                    .trap => |report| report,
                    .ok => null,
                };
            }
        }
    }

    // TRAP-PRECEDENCE: no other trap fired anywhere in the stream, so
    // the deferred exit leak (if any) is the verdict.
    if (deferred_exit_leak) |report| {
        return .{ .trap = report };
    }

    if (current_scope) |*scope| {
        scope.deinit();
        current_scope = null;
    }

    const annotated_slice = annotated.toOwnedSlice() catch {
        return .{ .trap = trapReportFromText(.arena_oom, 1, 1, instructions[instructions.len - 1].raw_text, "unable to finalize annotations", null) };
    };
    completed = true;

    return .{ .ok = .{
        .annotated = annotated_slice,
        .gas = .{
            .max_alloc_bytes = gas_alloc_bytes,
            .max_instruction_steps = if (has_unbounded_loop) .{ .unbounded = .{ .bounded_prefix = gas_steps } } else .{ .bounded = gas_steps },
            .call_depth = call_depth,
            .has_unbounded_loop = has_unbounded_loop,
        },
        .has_unbounded_loop = has_unbounded_loop,
    } };
}
