const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const classifier = @import("../flattener/line_classifier.zig");
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const assignValue = @import("collect_metadata.zig").assignValue;
const builtinArgSpec = @import("sax_trap_report.zig").builtinArgSpec;
const builtinGrantRequirement = @import("sax_trap_report.zig").builtinGrantRequirement;
const builtinReturnCap = @import("sax_trap_report.zig").builtinReturnCap;
const callPrefixMatchesParam = @import("sax_trap_report.zig").callPrefixMatchesParam;
const clearBorrow = @import("clear_borrow_ctx.zig").clearBorrow;
const constTrap = @import("const_trap.zig").constTrap;
const consumeInteriorValue = @import("snapshot_merge_state_in_scope.zig").consumeInteriorValue;
const hasActiveBorrowRefs = @import("const_trap.zig").hasActiveBorrowRefs;
const hasInteriorTree = @import("const_trap.zig").hasInteriorTree;
const isConstData = @import("reg_state_change.zig").isConstData;
const isIdentLike = @import("reg_state_change.zig").isIdentLike;
const isImmutableConst = @import("reg_state_change.zig").isImmutableConst;
const isStackAllocated = @import("collect_metadata.zig").isStackAllocated;
const maskOf = @import("reg_state_change.zig").maskOf;
const packageGrantAllowsEntry = @import("sax_trap_report.zig").packageGrantAllowsEntry;
const packageGrantEntry = @import("sax_trap_report.zig").packageGrantEntry;
const panicMsgAllowsRawArg = @import("sax_trap_report.zig").panicMsgAllowsRawArg;
const parseInstructionCallForLocalizedVerifier = @import("sax_trap_report.zig").parseInstructionCallForLocalizedVerifier;
const readCheck = @import("collect_metadata.zig").readCheck;
const readCheckAllowRaw = @import("sax_trap_report.zig").readCheckAllowRaw;
const regFlagEphemeralScalar = @import("reg_state_change.zig").regFlagEphemeralScalar;
const regFlagImmutable = @import("reg_state_change.zig").regFlagImmutable;
const regFlagRawPointer = @import("reg_state_change.zig").regFlagRawPointer;
const resolveScopedRegId = @import("sax_trap_report.zig").resolveScopedRegId;
const saxReport = @import("sax_trap_report.zig").saxReport;
const trapReport = @import("snapshot_merge_state_in_scope.zig").trapReport;
const VerifyBodyCtx = @import("verify_body_ctx.zig").VerifyBodyCtx;

pub fn armCall(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    _ = classified;
    var parsed = parseInstructionCallForLocalizedVerifier(vb.allocator, &vb.metadata.symbols, if (vb.current_scope) |*scope| scope else null, item) catch {
        return trapReport(.forbidden_syntax, item, vb.current_function_text, vb.current_is_ffi_wrapper, null, null, null, "invalid call syntax", null);
    };
    defer parsed.deinit(vb.allocator);

    if (vb.sax_context) |ctx| {
        if (std.mem.eql(u8, parsed.callee, "render") and !vb.current_is_ffi_wrapper) {
            return saxReport(ctx, .sax_render_outside_handler, item, parsed.dest, null, null, "call @render() is only legal inside @handler", null);
        }
    }

    const sig_match: ?*const sig.FunctionSig = if (vb.metadata.sig_index_by_name.get(parsed.callee)) |sig_idx| &vb.metadata.sigs.items[sig_idx] else null;
    const builtin_spec = builtinArgSpec(parsed.callee);

    if (!parsed.is_indirect and sig_match == null and builtin_spec == null and !std.mem.startsWith(u8, parsed.callee, "sys_")) {
        return trapReport(.unknown_register, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "callee is not declared", null);
    }

    if (!parsed.is_indirect and builtin_spec == null and std.mem.startsWith(u8, parsed.callee, "sys_")) {
        return trapReport(.unsupported_sys_intrinsic, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "target runtime does not support this @sys_* intrinsic", null);
    }

    if (!parsed.is_indirect) {
        if (builtinGrantRequirement(parsed.callee)) |required_grant| {
            if (item.package_identity) |identity| {
                const grant_entry = packageGrantEntry(identity, vb.package_grants) orelse {
                    return trapReport(.unauthorized_primitive, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "package grants do not allow this @sys_* intrinsic", null);
                };
                if (!packageGrantAllowsEntry(grant_entry, required_grant)) {
                    return trapReport(.unauthorized_primitive, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "package grants do not allow this @sys_* intrinsic", null);
                }
                const package_hash = item.package_source_sha256 orelse {
                    return trapReport(.upstream_sha_mismatch, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "package source hash does not match the granted requirement", null);
                };
                if (!std.mem.eql(u8, grant_entry.source_sha256[0..], package_hash[0..])) {
                    return trapReport(.upstream_sha_mismatch, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "package source hash does not match the granted requirement", null);
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
                    return trapReport(.capability_mismatch, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                }
            } else if (resolved.params.len != parsed.args.len) {
                return trapReport(.capability_mismatch, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
            }
            for (parsed.args[0..resolved.params.len], resolved.params) |arg, param| {
                if (!callPrefixMatchesParam(param, arg.prefix)) {
                    return trapReport(.capability_mismatch, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                }
            }
        } else if (builtin_spec) |spec| {
            if (spec.len != parsed.args.len) {
                return trapReport(.capability_mismatch, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
            }
            for (parsed.args, spec) |arg, expected| {
                if (arg.prefix != expected) {
                    return trapReport(.capability_mismatch, item, vb.current_function_text, vb.current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                }
            }
        }
    }

    for (parsed.args, 0..) |arg, arg_idx| {
        if (isIdentLike(arg.text)) {
            if (vb.current_scope) |scope| {
                if (resolveScopedRegId(&scope, &vb.metadata.symbols, arg.text)) |arg_id| {
                    const arg_reg_idx: usize = @intCast(arg_id);
                    if (vb.metadata.sig_index_by_name.contains(arg.text)) {
                        if (sig_match) |resolved| {
                            if (arg_idx < resolved.params.len and resolved.params[arg_idx].ty == .ptr) {
                                continue;
                            }
                        }
                    }
                    if (sig_match) |resolved| {
                        if (arg.prefix != .borrow and (resolved.kind == .external or resolved.kind == .ffi_wrapper) and hasInteriorTree(vb.state, vb.interior_first_child, arg_id)) {
                            return trapReport(.interior_ptr_escape, item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, maskOf(.interior_ptr), vb.state[arg_reg_idx], "interior pointers cannot cross FFI boundaries", null);
                        }
                    }
                    switch (arg.prefix) {
                        .borrow => if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, arg_id, vb.state, vb.flags)) |tr| return tr,
                        .by_value => if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, arg_id, vb.state, vb.flags)) |tr| return tr,
                        .raw => if (panicMsgAllowsRawArg(parsed.callee, parsed.args.len, arg_idx)) {
                            if (readCheckAllowRaw(item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, arg_id, vb.state, vb.flags)) |tr| return tr;
                        } else {
                            if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, arg_id, vb.state, vb.flags)) |tr| return tr;
                        },
                        .move => {
                            if (isConstData(vb.flags, arg_id)) {
                                return constTrap(item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, vb.state[arg_reg_idx], "immutable registers cannot be moved");
                            }
                            if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, arg_id, vb.state, vb.flags)) |tr| return tr;
                            if (isStackAllocated(vb.flags, vb.origins, vb.state, arg_id)) {
                                return trapReport(.stack_escape, item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, maskOf(.active), vb.state[@intCast(arg_id)], "stack allocation cannot be passed by move", null);
                            }
                            const move_arg_reg_idx: usize = @intCast(arg_id);
                            if ((vb.flags[move_arg_reg_idx] & regFlagRawPointer) != 0) {
                                continue;
                            }
                            if ((vb.state[move_arg_reg_idx] & maskOf(.borrow_view)) != 0) {
                                clearBorrow(vb.state, vb.flags, vb.origins, vb.locks, arg_id, &vb.interior);
                            } else {
                                if (hasInteriorTree(vb.state, vb.interior_first_child, arg_id)) {
                                    consumeInteriorValue(vb.state, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, arg_id);
                                } else {
                                    vb.state[move_arg_reg_idx] = maskOf(.consumed);
                                }
                            }
                        },
                    }
                } else if (sig_match) |resolved| {
                    if (arg_idx < resolved.params.len and resolved.params[arg_idx].ty == .ptr) {
                        continue;
                    }
                    return trapReport(.unknown_register, item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, null, null, "register is not declared in the current scope", null);
                } else {
                    return trapReport(.unknown_register, item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, null, null, "register is not declared in the current scope", null);
                }
            } else if (sig_match) |resolved| {
                if (arg_idx < resolved.params.len and resolved.params[arg_idx].ty == .ptr) {
                    continue;
                }
                return trapReport(.unknown_register, item, vb.current_function_text, vb.current_is_ffi_wrapper, arg.text, null, null, "register is not declared in the current scope", null);
            }
        }
    }

    if (parsed.dest) |dest| {
        if (isIdentLike(dest)) {
            if (vb.current_scope) |scope| {
                if (resolveScopedRegId(&scope, &vb.metadata.symbols, dest)) |dest_id| {
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
                        if (resolveScopedRegId(&scope, &vb.metadata.symbols, arg.text)) |arg_id| {
                            if (arg_id == dest_id) {
                                dest_is_moved_arg = true;
                                break;
                            }
                        }
                    }
                    if (!dest_is_moved_arg and vb.state[idx] != 0 and (vb.state[idx] & maskOf(.consumed)) == 0 and (vb.state[idx] & maskOf(.untracked)) == 0 and (vb.flags[idx] & regFlagEphemeralScalar) == 0) {
                        return trapReport(.register_redefinition, item, vb.current_function_text, vb.current_is_ffi_wrapper, dest, null, null, "register is already live", null);
                    }
                    if (isImmutableConst(vb.state, vb.flags, dest_id)) {
                        return constTrap(item, vb.current_function_text, vb.current_is_ffi_wrapper, dest, vb.state[idx], "immutable registers cannot be overwritten");
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
                    vb.state[idx] = ret_state;
                    vb.flags[idx] = 0;
                }
            }
        }
    }

    if (item.kind == .panic or item.kind == .panic_msg) {
        vb.terminated = true;
        vb.fatal_terminated = true;
    }
    return null;
}

pub fn armTry(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    const src_id = item.operands[1].reg;
    const dst_id = item.operands[0].reg;
    const src_idx: usize = @intCast(src_id);
    const src_mask = vb.state[src_idx];
    if ((src_mask & maskOf(.fallible)) == 0) {
        const src_name = vb.current_scope.?.nameOf(&vb.metadata.symbols, src_id) orelse vb.metadata.symbols.lookupName(vb.current_scope.?.globalId(src_id)) orelse "";
        return trapReport(.fallible_contract_mismatch, item, vb.current_function_text, vb.current_is_ffi_wrapper, src_name, maskOf(.fallible), src_mask, "? can only be applied to fallible return values", null);
    }

    for (vb.state, 0..) |mask, idx| {
        if (idx == src_idx) continue;
        if (mask == 0 or mask == maskOf(.consumed) or mask == maskOf(.untracked)) continue;
        if ((mask & maskOf(.active)) == 0 and (mask & maskOf(.locked_read)) == 0 and (mask & maskOf(.locked_mut)) == 0) continue;
        // Only const data is exempt from the leak check; an
        // immutable binding still owns its allocation and must be
        // released.
        if ((vb.flags[idx] & regFlagImmutable) != 0) continue;
        if ((vb.flags[idx] & regFlagEphemeralScalar) != 0) continue;
        // Raw pointers carry no ownership (release is a no-op for
        // them); a live raw-pointer temp is never a leak, same as
        // an ephemeral scalar temp.
        if ((vb.flags[idx] & regFlagRawPointer) != 0) continue;
        // Same const-borrow exemption as the function-exit scan
        // (checkExitLeaks): a live borrow view of @const data is
        // never a leak; a borrow view of an owned value is not
        // exempted, so the scan stays the backstop for
        // move-while-borrowed.
        if ((mask & maskOf(.borrow_view)) != 0) {
            const origin = vb.origins[idx];
            if (origin != null and isConstData(vb.flags, origin.?)) continue;
        }
        if (isStackAllocated(vb.flags, vb.origins, vb.state, @intCast(idx))) continue;
        if (idx < vb.consumed_in_function.len and vb.consumed_in_function[idx]) continue;
        const src_name = vb.current_scope.?.nameOf(&vb.metadata.symbols, src_id) orelse vb.metadata.symbols.lookupName(vb.current_scope.?.globalId(src_id)) orelse "";
        return trapReport(.early_return_leak, item, vb.current_function_text, vb.current_is_ffi_wrapper, src_name, maskOf(.fallible), src_mask, "early return would leak live registers", null);
    }

    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], dst_id, vb.state, vb.flags, maskOf(.active), &vb.interior)) |tr| return tr;
    vb.flags[@intCast(dst_id)] = 0;
    return null;
}

pub fn armReturn(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    _ = classified;
    if (item.operands[0] == .reg) {
        const ret_id = item.operands[0].reg;
        const ret_name = vb.current_scope.?.nameOf(&vb.metadata.symbols, ret_id) orelse vb.metadata.symbols.lookupName(vb.current_scope.?.globalId(ret_id)) orelse item.operands[0].text;
        const idx: usize = @intCast(ret_id);
        if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, ret_name, ret_id, vb.state, vb.flags)) |tr| {
            return tr;
        }
        if ((vb.state[idx] & maskOf(.fallible)) != 0) {
            if (vb.current_sig == null or vb.current_sig.?.return_fallible == false) {
                return trapReport(.fallible_contract_mismatch, item, vb.current_function_text, vb.current_is_ffi_wrapper, ret_name, maskOf(.fallible), vb.state[idx], "fallible values must be propagated with ? or returned from a fallible function", null);
            }
            if (hasInteriorTree(vb.state, vb.interior_first_child, ret_id)) {
                consumeInteriorValue(vb.state, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, ret_id);
            } else {
                vb.state[idx] = maskOf(.consumed);
            }
        } else {
            if ((vb.state[idx] & maskOf(.borrow_view)) == 0 and hasActiveBorrowRefs(vb.locks, ret_id)) {
                return trapReport(.borrow_conflict, item, vb.current_function_text, vb.current_is_ffi_wrapper, ret_name, maskOf(.active), vb.state[idx], "borrow rules reject this access", null);
            }
            if (isStackAllocated(vb.flags, vb.origins, vb.state, ret_id)) {
                return trapReport(.stack_escape, item, vb.current_function_text, vb.current_is_ffi_wrapper, ret_name, maskOf(.active), vb.state[idx], "stack allocation cannot be returned", null);
            }
            if ((vb.flags[idx] & regFlagRawPointer) == 0) {
                if ((vb.state[idx] & maskOf(.borrow_view)) != 0) {
                    clearBorrow(vb.state, vb.flags, vb.origins, vb.locks, ret_id, &vb.interior);
                } else if (hasInteriorTree(vb.state, vb.interior_first_child, ret_id)) {
                    consumeInteriorValue(vb.state, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, ret_id);
                } else if ((vb.state[idx] & maskOf(.untracked)) == 0) {
                    vb.state[idx] = maskOf(.consumed);
                }
            }
        }
    } else if (item.operands[0] == .text and isIdentLike(item.operands[0].text)) {
        if (vb.current_scope) |scope| {
            if (resolveScopedRegId(&scope, &vb.metadata.symbols, item.operands[0].text)) |ret_id| {
                const idx: usize = @intCast(ret_id);
                const ret_name = scope.nameOf(&vb.metadata.symbols, ret_id) orelse item.operands[0].text;
                if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, item.operands[0].text, ret_id, vb.state, vb.flags)) |tr| {
                    return tr;
                }
                if (isConstData(vb.flags, ret_id)) {
                    return constTrap(item, vb.current_function_text, vb.current_is_ffi_wrapper, ret_name, vb.state[idx], "immutable registers cannot be returned by move");
                }
                if ((vb.state[idx] & maskOf(.fallible)) != 0) {
                    if (vb.current_sig == null or vb.current_sig.?.return_fallible == false) {
                        return trapReport(.fallible_contract_mismatch, item, vb.current_function_text, vb.current_is_ffi_wrapper, ret_name, maskOf(.fallible), vb.state[idx], "fallible values must be propagated with ? or returned from a fallible function", null);
                    }
                    if (hasInteriorTree(vb.state, vb.interior_first_child, ret_id)) {
                        consumeInteriorValue(vb.state, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, ret_id);
                    } else {
                        vb.state[idx] = maskOf(.consumed);
                    }
                } else {
                    if ((vb.state[idx] & maskOf(.borrow_view)) == 0 and hasActiveBorrowRefs(vb.locks, ret_id)) {
                        return trapReport(.borrow_conflict, item, vb.current_function_text, vb.current_is_ffi_wrapper, ret_name, maskOf(.active), vb.state[idx], "borrow rules reject this access", null);
                    }
                    if (isStackAllocated(vb.flags, vb.origins, vb.state, ret_id)) {
                        return trapReport(.stack_escape, item, vb.current_function_text, vb.current_is_ffi_wrapper, ret_name, maskOf(.active), vb.state[idx], "stack allocation cannot be returned", null);
                    }
                    if ((vb.flags[idx] & regFlagRawPointer) == 0) {
                        if ((vb.state[idx] & maskOf(.borrow_view)) != 0) {
                            clearBorrow(vb.state, vb.flags, vb.origins, vb.locks, ret_id, &vb.interior);
                        } else if (hasInteriorTree(vb.state, vb.interior_first_child, ret_id)) {
                            consumeInteriorValue(vb.state, vb.interior_parent, vb.interior_first_child, vb.interior_next_sibling, ret_id);
                        } else if ((vb.state[idx] & maskOf(.untracked)) == 0) {
                            vb.state[idx] = maskOf(.consumed);
                        }
                    }
                }
            } else {
                return trapReport(.unknown_register, item, vb.current_function_text, vb.current_is_ffi_wrapper, item.operands[0].text, null, null, "register is not declared in the current scope", null);
            }
        } else {
            return trapReport(.unknown_register, item, vb.current_function_text, vb.current_is_ffi_wrapper, item.operands[0].text, null, null, "register is not declared in the current scope", null);
        }
    }
    vb.terminated = true;
    return null;
}

pub fn armVaStart(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    // Extern variadic batch: the destination receives a
    // fresh raw pointer to this function's va_list object
    // (host-managed storage, no ownership payload), mirroring
    // the load-of-pointer state shape.
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, maskOf(.active), &vb.interior)) |tr| return tr;
    vb.flags[@intCast(item.operands[0].reg)] = regFlagRawPointer;
    return null;
}

pub fn armVaArg(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, vb.state, vb.flags)) |tr| return tr;
    if (assignValue(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags, maskOf(.active), &vb.interior)) |tr| return tr;
    const read_ty: sig.PrimType = if (item.operands[2] == .ty) (sig.primTypeFromTag(item.operands[2].ty) orelse .i64) else .i64;
    vb.flags[@intCast(item.operands[0].reg)] = if (read_ty == .ptr) regFlagRawPointer else regFlagEphemeralScalar;
    return null;
}

pub fn armVaEnd(vb: *VerifyBodyCtx, item: inst.Instruction, classified: classifier.ClassifiedLine) !?VerifyBodyResult {
    if (readCheck(item, vb.current_function_text, vb.current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, vb.state, vb.flags)) |tr| return tr;
    return null;
}
