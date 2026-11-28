// obligation.zig — extract "loop induction variable vs len" obligations
// from flat SA instructions, prove them, and verify the proofs.
//
// Scope (prototype): ONLY the loop-induction-variable-vs-len class.
// A check is in the class when:
//   * it sits in a loop body (textual loop: a backward `jmp` to a header
//     label whose block ends in a conditional `br` on an unsigned
//     comparison), and
//   * the loop header compares an induction variable `iv` against a bound
//     loaded from (base, field-offset), and
//   * the check compares the same `iv` (same register, no redefinition
//     between head and check) against a load of the same (base, offset),
//     and
//   * the check's false target is a block holding exactly one `panic`
//     (this is what distinguishes a bounds check from e.g. a VPUSH
//     capacity check, whose false target is a call block), and
//   * `iv` is incremented by a positive constant in the loop body, and
//   * on the path from the head load to the check load there is no memory
//     write, no call, no redefinition of the base register, and no `take`
//     of the bound location (the strict rule closes the aliasing hole:
//     with no store at all on the path, no aliased store can change len).
//
// Soundness notes (read before extending):
//   * Loops are found textually: the plugin emits structured while loops
//     (header, body, exit in order, one backward `jmp`). A general
//     CFG/dominator analysis is extension work for unstructured .sa.
//   * Register "versions" are counted textually from the function start.
//     head-version == check-version means no redefinition of that register
//     occurs textually between head and check; since control flows forward
//     from head to check within one iteration, that is the no-change
//     property the proof needs.
//   * The mutation scan covers the textual range [head-load, check-load],
//     which contains every instruction on the head->check path (forward
//     flow) plus possibly extra ones; extra ones only lose proofs.
//   * Facts are exactly one inequality: the head condition. The goal is
//     the check condition, over the same two variables (iv, bound).
//     The prover (fm) is untrusted; every certificate is re-checked by
//     linear.checkCertificate before anything is marked proven.

const std = @import("std");
const common_instruction = @import("../common/instruction.zig");
const linear = @import("linear.zig");
const fm = @import("fm.zig");

pub const Inst = common_instruction.Instruction;
pub const InstKind = common_instruction.InstKind;
pub const OpKind = common_instruction.OpKind;
pub const Operand = common_instruction.Operand;

pub const CheckStatus = enum {
    /// Proved and verified: the check's branch may be removed.
    proven,
    /// In the target class but the prover could not prove it.
    unproven,
    /// A bounds-check-shaped site that is not the IV-vs-len class.
    not_target_class,
};

pub const Obligation = struct {
    br_idx: usize,
    ok_label: u32,
    oob_label: u32,
    func_name: []const u8,
    source_line: u32,
    upstream_file: ?[]const u8,
    upstream_line: ?u32,
    upstream_col: ?u32,
    head_fact: linear.Ineq,
    goal: linear.Ineq,
    status: CheckStatus,
    reason: []const u8,
    /// Verified certificate (weights owned by the caller's arena).
    cert: ?linear.Certificate,
};

pub const ProofStats = struct {
    functions_scanned: u32 = 0,
    loops_found: u32 = 0,
    checks_found: u32 = 0,
    target_class: u32 = 0,
    proven: u32 = 0,
    unproven: u32 = 0,
    not_target_class: u32 = 0,
};

// ---------------------------------------------------------------- helpers

fn regOf(op: Operand) ?u32 {
    return switch (op) {
        .reg => |r| r,
        else => null,
    };
}

fn labelOf(op: Operand) ?u32 {
    return switch (op) {
        .label => |l| l,
        else => null,
    };
}

fn immI64Of(op: Operand) ?i64 {
    return switch (op) {
        .imm_i64 => |v| v,
        .imm_u64 => |v| if (v <= std.math.maxInt(i64)) @as(i64, @intCast(v)) else null,
        .imm_int => |v| v,
        else => null,
    };
}

/// Kinds whose operands[0] (a .reg) is a value definition. Anything not
/// listed here is treated as NOT defining a register; the list must stay
/// complete for value-producing kinds (a missed def would make two
/// different values look like one version, which is unsound). The safe
/// direction for an uncertain kind is to list it (an extra version bump
/// only loses proofs).
const def_kinds = [_]InstKind{
    .alloc, .stack_alloc, .load, .take, .atomic_load, .cmpxchg, .atomic_rmw,
    .borrow, .move_, .assign, .op, .ptr_add, .call, .call_indirect, .try_,
    .raw_cast, .assume_safe, .assume_borrow, .va_start, .va_arg,
};

fn definesReg(inst: Inst) ?u32 {
    const r = regOf(inst.operands[0]) orelse return null;
    for (def_kinds) |k| {
        if (inst.kind == k) return r;
    }
    return null;
}

fn isTerminator(kind: InstKind) bool {
    return switch (kind) {
        .br, .br_null, .jmp, .return_, .early_return, .panic, .panic_msg => true,
        else => false,
    };
}

fn isMemoryWrite(kind: InstKind) bool {
    return switch (kind) {
        .store, .atomic_store, .atomic_rmw, .cmpxchg => true,
        else => false,
    };
}

fn isCall(kind: InstKind) bool {
    return switch (kind) {
        .call, .call_indirect => true,
        else => false,
    };
}

/// Number of definitions of `reg` in insts[lo..hi). The "version" of a
/// register at an instruction index.
fn versionAt(insts: []const Inst, lo: usize, hi: usize, reg: u32) u32 {
    var v: u32 = 0;
    var i = lo;
    while (i < hi and i < insts.len) : (i += 1) {
        if (definesReg(insts[i])) |d| {
            if (d == reg) v += 1;
        }
    }
    return v;
}

/// Index of the `label` instruction defining `label_id`, or null.
fn findLabelDef(insts: []const Inst, label_id: u32) ?usize {
    for (insts, 0..) |inst, i| {
        if (inst.kind != .label) continue;
        if (labelOf(inst.operands[1])) |l| {
            if (l == label_id) return i;
        }
    }
    return null;
}

/// Index just past the block starting at `start` (a label instruction, or
/// the function start). A block ends after its terminator, or before the
/// next label / function declaration.
fn blockEnd(insts: []const Inst, start: usize) usize {
    var i = start;
    while (i < insts.len) : (i += 1) {
        const k = insts[i].kind;
        if (i != start and (k == .label or k == .func_decl or k == .ffi_wrapper_decl or k == .extern_decl or k == .export_decl or k == .test_decl or k == .gpu_decl)) {
            return i;
        }
        if (isTerminator(k)) return i + 1;
    }
    return insts.len;
}

/// The block holding exactly one `panic` and nothing else (after its
/// label). Returns the panic's index.
fn lonePanicBlock(insts: []const Inst, label_idx: usize) ?usize {
    const end = blockEnd(insts, label_idx);
    // label + exactly one instruction, which is a panic.
    if (end - label_idx != 2) return null;
    if (insts[label_idx + 1].kind != .panic) return null;
    return label_idx + 1;
}

/// A comparison (op_kind, lhs, rhs) normalized to an (iv, bound)
/// inequality over variables (0 = iv, 1 = bound). Returns null when the
/// comparison is not an unsigned iv-vs-bound comparison. `iv_reg` and
/// `bound_reg` are the two registers involved (in either order).
fn normalizeCmp(op_kind: OpKind, lhs: u32, rhs: u32, iv_reg: u32, bound_reg: u32) ?linear.Ineq {
    // iv < bound
    if (lhs == iv_reg and rhs == bound_reg) {
        return switch (op_kind) {
            .ult => linear.ultIneq(0, 1, 2),
            .ule => linear.uleIneq(0, 1, 2),
            else => null,
        };
    }
    // bound > iv  (same relation, operands swapped)
    if (lhs == bound_reg and rhs == iv_reg) {
        return switch (op_kind) {
            .ugt => linear.ultIneq(0, 1, 2),
            .uge => linear.uleIneq(0, 1, 2),
            else => null,
        };
    }
    return null;
}

/// Find the instruction in insts[lo..hi) that defines `reg` (searching
/// backward from `hi`), or null.
fn findDef(insts: []const Inst, lo: usize, hi: usize, reg: u32) ?usize {
    var i = hi;
    while (i > lo) {
        i -= 1;
        if (definesReg(insts[i])) |d| {
            if (d == reg) return i;
        }
    }
    return null;
}

/// A bound load: `dst = load base+offset as ty`. Returns (base, offset).
fn loadOperands(inst: Inst) ?struct { base: u32, offset: u64 } {
    if (inst.kind != .load) return null;
    const base = regOf(inst.operands[1]) orelse return null;
    const offset = switch (inst.operands[2]) {
        .imm_u64 => |v| v,
        .imm_i64 => |v| if (v >= 0) @as(u64, @intCast(v)) else return null,
        .imm_int => |v| if (v >= 0) @as(u64, @intCast(v)) else return null,
        else => return null,
    };
    return .{ .base = base, .offset = offset };
}

/// Recognize an induction-variable increment of `iv_reg` in
/// insts[lo..hi): `iv = add iv, k` (direct) or `tmp = add iv, k` followed
/// by `iv = add tmp, 0` (copy form), with k a positive constant (an
/// immediate, or a register assigned a positive immediate). Returns the
/// increment amount, or null.
fn findIVIncrement(insts: []const Inst, lo: usize, hi: usize, iv_reg: u32) ?i64 {
    var i = lo;
    while (i < hi and i < insts.len) : (i += 1) {
        const inst = insts[i];
        if (inst.kind != .op or inst.op_kind != .add) continue;
        const dst = regOf(inst.operands[0]) orelse continue;
        const lhs = inst.operands[1];
        const rhs = inst.operands[2];
        // One side must be iv_reg, the other a positive constant.
        const other: ?Operand = if (regOf(lhs)) |r| (if (r == iv_reg) rhs else null) else null;
        const other2: ?Operand = if (regOf(rhs)) |r| (if (r == iv_reg) lhs else null) else null;
        const const_op = other orelse other2 orelse continue;
        const k = constValue(insts, lo, i, const_op) orelse continue;
        if (k <= 0) continue;
        if (dst == iv_reg) return k; // direct form
        // Copy form: later `iv = add tmp, 0`.
        var j = i + 1;
        while (j < hi and j < insts.len) : (j += 1) {
            const c = insts[j];
            if (c.kind != .op or c.op_kind != .add) continue;
            if (regOf(c.operands[0]) orelse 0 != iv_reg) continue;
            const cl = c.operands[1];
            const cr = c.operands[2];
            const is_copy = (regOf(cl) == dst and immI64Of(cr) == 0) or
                (regOf(cr) == dst and immI64Of(cl) == 0);
            if (is_copy) return k;
        }
    }
    return null;
}

/// The constant value of an operand: an immediate, or a register defined
/// in insts[lo..hi) by `reg = <immediate>` (an assign).
fn constValue(insts: []const Inst, lo: usize, hi: usize, op: Operand) ?i64 {
    if (immI64Of(op)) |v| return v;
    const r = regOf(op) orelse return null;
    const def_idx = findDef(insts, lo, hi, r) orelse return null;
    const def = insts[def_idx];
    if (def.kind != .assign) return null;
    return immI64Of(def.operands[1]);
}

// ---------------------------------------------------------------- analysis

const LoopHead = struct {
    header_label_idx: usize,
    header_end: usize,
    br_idx: usize,
    cond_reg: u32,
    cmp_idx: usize,
    cmp_kind: OpKind,
    iv_reg: u32,
    bound_reg: u32,
    bound_base: u32,
    bound_offset: u64,
    bound_load_idx: usize,
    body_end: usize,
};

/// Analyze one function's instructions (a slice of the flat array).
/// `base` is the absolute index of insts[0] in the flat array (for
/// reporting absolute br indices). `func_name` is used in reports.
/// The caller provides an arena allocator; all obligations and
/// certificates are allocated from it.
pub fn analyzeFunction(
    allocator: std.mem.Allocator,
    insts: []const Inst,
    base: usize,
    func_name: []const u8,
) !struct { obligations: []Obligation, stats: ProofStats } {
    var stats = ProofStats{ .functions_scanned = 1 };
    var obligations = std.array_list.Managed(Obligation).init(allocator);

    // --- find loops: backward jmps to a header whose block ends in a br.
    var headers = std.array_list.Managed(u32).init(allocator);
    defer headers.deinit();
    var body_ends = std.array_list.Managed(usize).init(allocator);
    defer body_ends.deinit();
    for (insts, 0..) |inst, i| {
        if (inst.kind != .jmp) continue;
        const target = labelOf(inst.operands[1]) orelse continue;
        const h = findLabelDef(insts, target) orelse continue;
        if (h >= i) continue; // forward jump, not a back edge
        // Dedupe by header label; keep the latest back edge as body end.
        var found: ?usize = null;
        for (headers.items, 0..) |hh, k| {
            if (hh == target) {
                found = k;
                break;
            }
        }
        if (found) |k| {
            if (i > body_ends.items[k]) body_ends.items[k] = i;
        } else {
            try headers.append(target);
            try body_ends.append(i);
        }
    }

    for (headers.items, body_ends.items) |target, body_end| {
        const header_idx = findLabelDef(insts, target) orelse continue;
        const head = parseLoopHead(insts, header_idx, body_end) orelse continue;
        stats.loops_found += 1;

        // --- find checks in the body range [header_idx, body_end].
        var i = header_idx;
        while (i <= body_end and i < insts.len) : (i += 1) {
            const inst = insts[i];
            if (inst.kind != .br) continue;
            const cond_reg = regOf(inst.operands[0]) orelse continue;
            const ok_label = labelOf(inst.operands[1]) orelse continue;
            const oob_label = labelOf(inst.operands[3]) orelse continue;
            const oob_def = findLabelDef(insts, oob_label) orelse continue;
            _ = lonePanicBlock(insts, oob_def) orelse continue;
            // A bounds-check-shaped site.
            stats.checks_found += 1;
            const obligation = try analyzeCheck(
                allocator,
                insts,
                base,
                func_name,
                &head,
                i,
                cond_reg,
                ok_label,
                oob_label,
                header_idx,
            );
            if (obligation.status == .proven) stats.proven += 1;
            if (obligation.status == .unproven) stats.unproven += 1;
            if (obligation.status == .not_target_class) stats.not_target_class += 1;
            if (obligation.status != .not_target_class) stats.target_class += 1;
            try obligations.append(obligation);
        }
    }

    return .{ .obligations = try obligations.toOwnedSlice(), .stats = stats };
}

/// Parse a loop header: the header block must end in a `br` whose
/// condition is defined in the header by an unsigned comparison of an
/// induction-variable register against a register loaded from
/// (base, offset). Returns null when the shape does not match.
fn parseLoopHead(insts: []const Inst, header_idx: usize, body_end: usize) ?LoopHead {
    const header_end = blockEnd(insts, header_idx);
    if (header_end == 0 or header_end > insts.len) return null;
    const br_idx = header_end - 1;
    if (insts[br_idx].kind != .br) return null;
    const cond_reg = regOf(insts[br_idx].operands[0]) orelse return null;
    const cmp_idx = findDef(insts, header_idx, br_idx, cond_reg) orelse return null;
    const cmp = insts[cmp_idx];
    if (cmp.kind != .op) return null;
    const cmp_kind = cmp.op_kind orelse return null;
    if (cmp_kind != .ult and cmp_kind != .ule and cmp_kind != .ugt and cmp_kind != .uge) return null;
    const lhs = regOf(cmp.operands[1]) orelse return null;
    const rhs = regOf(cmp.operands[2]) orelse return null;
    // One side is the IV, the other is the bound register (a load).
    // Try both assignments; the bound side must be a load in the header.
    const candidates = [_]struct { iv: u32, bound: u32 }{
        .{ .iv = lhs, .bound = rhs },
        .{ .iv = rhs, .bound = lhs },
    };
    for (candidates) |c| {
        const load_idx = findDef(insts, header_idx, cmp_idx, c.bound) orelse continue;
        const load = loadOperands(insts[load_idx]) orelse continue;
        return .{
            .header_label_idx = header_idx,
            .header_end = header_end,
            .br_idx = br_idx,
            .cond_reg = cond_reg,
            .cmp_idx = cmp_idx,
            .cmp_kind = cmp_kind,
            .iv_reg = c.iv,
            .bound_reg = c.bound,
            .bound_base = load.base,
            .bound_offset = load.offset,
            .bound_load_idx = load_idx,
            .body_end = body_end,
        };
    }
    return null;
}

/// Analyze one bounds-check-shaped `br` against a loop head.
fn analyzeCheck(
    allocator: std.mem.Allocator,
    insts: []const Inst,
    base: usize,
    func_name: []const u8,
    head: *const LoopHead,
    br_idx: usize,
    cond_reg: u32,
    ok_label: u32,
    oob_label: u32,
    func_start: usize,
) !Obligation {
    const make_ob = struct {
        fn make(
            status: CheckStatus,
            reason: []const u8,
            head_fact: linear.Ineq,
            goal: linear.Ineq,
            cert: ?linear.Certificate,
            br_rel: usize,
            abs_base: usize,
            ok: u32,
            oob: u32,
            fname: []const u8,
            insts_ref: []const Inst,
        ) Obligation {
            const inst = insts_ref[br_rel];
            var ob = Obligation{
                .br_idx = abs_base + br_rel,
                .ok_label = ok,
                .oob_label = oob,
                .func_name = fname,
                .source_line = inst.source_line,
                .upstream_file = null,
                .upstream_line = null,
                .upstream_col = null,
                .head_fact = head_fact,
                .goal = goal,
                .status = status,
                .reason = reason,
                .cert = cert,
            };
            if (inst.upstream_loc) |loc| {
                ob.upstream_file = loc.file;
                ob.upstream_line = loc.line;
                ob.upstream_col = loc.col;
            }
            return ob;
        }
    }.make;

    const zero = linear.Ineq{ .nvars = 2 };
    // Find the comparison defining the check condition (search backward
    // within the enclosing block).
    const block_start = blk: {
        var s = br_idx;
        while (s > 0) {
            s -= 1;
            if (insts[s].kind == .label) break :blk s;
            if (insts[s].kind == .func_decl) break :blk s;
        }
        break :blk 0;
    };
    const cmp_idx = findDef(insts, block_start, br_idx, cond_reg) orelse {
        return make_ob(.not_target_class, "check condition has no defining op in its block", zero, zero, null, br_idx, base, ok_label, oob_label, func_name, insts);
    };
    const cmp = insts[cmp_idx];
    if (cmp.kind != .op) {
        return make_ob(.not_target_class, "check condition is not defined by an op", zero, zero, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }
    const lhs = regOf(cmp.operands[1]) orelse {
        return make_ob(.not_target_class, "check comparison lhs is not a register", zero, zero, null, br_idx, base, ok_label, oob_label, func_name, insts);
    };
    const rhs = regOf(cmp.operands[2]) orelse {
        return make_ob(.not_target_class, "check comparison rhs is not a register", zero, zero, null, br_idx, base, ok_label, oob_label, func_name, insts);
    };
    // The bound side must be a load in the same block.
    var bound_base: u32 = 0;
    var bound_offset: u64 = 0;
    var bound_load_idx: usize = 0;
    var idx_reg: u32 = 0;
    var found_bound = false;
    for ([_]struct { idx: u32, bnd: u32 }{ .{ .idx = lhs, .bnd = rhs }, .{ .idx = rhs, .bnd = lhs } }) |c| {
        const li = findDef(insts, block_start, cmp_idx, c.bnd) orelse continue;
        const ld = loadOperands(insts[li]) orelse continue;
        bound_base = ld.base;
        bound_offset = ld.offset;
        bound_load_idx = li;
        idx_reg = c.idx;
        found_bound = true;
        break;
    }
    if (!found_bound) {
        return make_ob(.not_target_class, "check bound is not a load in its block", zero, zero, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }

    // Normalize head and check comparisons to (iv, bound) inequalities.
    const head_fact = normalizeCmp(head.cmp_kind, regOf(insts[head.cmp_idx].operands[1]).?, regOf(insts[head.cmp_idx].operands[2]).?, head.iv_reg, head.bound_reg) orelse {
        return make_ob(.not_target_class, "head comparison is not an unsigned iv-vs-bound comparison", zero, zero, null, br_idx, base, ok_label, oob_label, func_name, insts);
    };
    const cmp_kind2 = cmp.op_kind orelse {
        return make_ob(.not_target_class, "check comparison has no op kind", zero, zero, null, br_idx, base, ok_label, oob_label, func_name, insts);
    };
    const goal = normalizeCmp(cmp_kind2, lhs, rhs, idx_reg, if (idx_reg == lhs) rhs else lhs) orelse {
        return make_ob(.not_target_class, "check comparison is not an unsigned comparison", zero, zero, null, br_idx, base, ok_label, oob_label, func_name, insts);
    };

    // Target-class gates (each refusal is a classification, not a failure).
    if (idx_reg != head.iv_reg) {
        return make_ob(.not_target_class, "check index is not the loop induction variable", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }
    if (versionAt(insts, func_start, head.cmp_idx, head.iv_reg) != versionAt(insts, func_start, cmp_idx, idx_reg)) {
        return make_ob(.not_target_class, "induction variable redefined between head and check", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }
    if (bound_base != head.bound_base or bound_offset != head.bound_offset) {
        return make_ob(.not_target_class, "check bound loads a different location than the head bound", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }
    if (versionAt(insts, func_start, head.bound_load_idx, head.bound_base) != versionAt(insts, func_start, bound_load_idx, bound_base)) {
        return make_ob(.not_target_class, "bound base register redefined between head and check", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }
    if (findIVIncrement(insts, head.header_label_idx, head.body_end, head.iv_reg) == null) {
        return make_ob(.not_target_class, "no positive-constant increment of the induction variable in the loop body", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }
    // Strict mutation scan on [head bound load, check bound load].
    var s = head.bound_load_idx;
    while (s < bound_load_idx and s < insts.len) : (s += 1) {
        const k = insts[s].kind;
        if (isMemoryWrite(k) or isCall(k)) {
            return make_ob(.not_target_class, "store or call on the path from head load to check load", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
        }
        if (definesReg(insts[s])) |d| {
            if (d == head.bound_base) {
                return make_ob(.not_target_class, "bound base register redefined on the path from head load to check load", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
            }
        }
        if (k == .take) {
            if (loadOperands(insts[s])) |ld| {
                if (ld.base == head.bound_base and ld.offset == head.bound_offset) {
                    return make_ob(.not_target_class, "bound location taken on the path from head load to check load", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
                }
            }
        }
    }

    // In the target class: prove the goal from the head fact.
    const facts = [_]linear.Ineq{head_fact};
    const cert = (try fm.prove(allocator, &facts, goal)) orelse {
        return make_ob(.unproven, "prover could not prove the goal from the head fact", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
    };
    if (!linear.checkCertificate(&facts, goal, cert)) {
        allocator.free(cert.weights);
        return make_ob(.unproven, "prover certificate failed the trusted checker (prover bug)", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }
    return make_ob(.proven, "proved from the head condition and verified by the Farkas checker", head_fact, goal, cert, br_idx, base, ok_label, oob_label, func_name, insts);
}

// ---------------------------------------------------------------- tests
//
// The synthetic function below mirrors the real .sa the plugin emits for
// a Vec while loop (see /tmp/loop-probe/vec_loop.sa, @sla__vec_loop_sum):
// a header that loads v+Vec_len and branches on `ult i, len`, a body
// whose first check reloads v+Vec_len and branches to a lone-panic OOB
// block, and an increment `i = add (i + 1), 0` at the body end.
// Symbol ids are arbitrary but distinct: registers 1..19, labels 100...

const R_V: u32 = 1;
const R_I: u32 = 2;
const R_TOTAL: u32 = 3;
const R_LEN_H: u32 = 10;
const R_COND_H: u32 = 11;
const R_LEN_C: u32 = 12;
const R_COND_C: u32 = 13;
const R_PTR: u32 = 14;
const R_MUL: u32 = 15;
const R_ADDR: u32 = 16;
const R_ELEM: u32 = 17;
const R_SUM: u32 = 18;
const R_ONE: u32 = 19;
const R_INC: u32 = 20;

const L_ENTRY: u32 = 100;
const L_HEAD: u32 = 101;
const L_BODY: u32 = 102;
const L_FALSE: u32 = 103;
const L_EXIT: u32 = 104;
const L_OK: u32 = 105;
const L_OOB: u32 = 106;
const L_CALL: u32 = 107;

fn mk(kind: InstKind, line: u32) Inst {
    return common_instruction.makeInstruction(kind, line, line, null, "");
}

fn mkOp(dst: u32, op_kind: OpKind, lhs: Operand, rhs: Operand, line: u32) Inst {
    var inst = mk(.op, line);
    inst.op_kind = op_kind;
    inst.operands[0] = .{ .reg = dst };
    inst.operands[1] = lhs;
    inst.operands[2] = rhs;
    return inst;
}

fn mkLoad(dst: u32, base: u32, offset: u64, line: u32) Inst {
    var inst = mk(.load, line);
    inst.operands[0] = .{ .reg = dst };
    inst.operands[1] = .{ .reg = base };
    inst.operands[2] = .{ .imm_u64 = offset };
    inst.operands[3] = .{ .ty = 0 };
    return inst;
}

fn mkLabel(label: u32, line: u32) Inst {
    var inst = mk(.label, line);
    inst.operands[0] = .{ .symbol = label };
    inst.operands[1] = .{ .label = label };
    return inst;
}

fn mkBr(cond: u32, true_label: u32, false_label: u32, line: u32) Inst {
    var inst = mk(.br, line);
    inst.operands[0] = .{ .reg = cond };
    inst.operands[1] = .{ .label = true_label };
    inst.operands[2] = .{ .label = true_label };
    inst.operands[3] = .{ .label = false_label };
    return inst;
}

fn mkJmp(target: u32, line: u32) Inst {
    var inst = mk(.jmp, line);
    inst.operands[0] = .{ .symbol = target };
    inst.operands[1] = .{ .label = target };
    return inst;
}

fn mkRelease(reg: u32, line: u32) Inst {
    var inst = mk(.release, line);
    inst.operands[0] = .{ .reg = reg };
    return inst;
}

/// The canonical Vec while loop, as a flat instruction list. Variants
/// are selected by flags for the negative tests.
fn buildVecLoop(
    allocator: std.mem.Allocator,
    head_ule: bool,
    store_between: bool,
    wrong_bound_offset: bool,
    redefine_iv_between: bool,
) ![]Inst {
    var list = std.array_list.Managed(Inst).init(allocator);
    const off: u64 = if (wrong_bound_offset) 16 else 8;
    var line: u32 = 1;
    // func_decl + entry
    try list.append(mk(.func_decl, line));
    line += 1;
    try list.append(mkLabel(L_ENTRY, line));
    line += 1;
    var a = mk(.assign, line);
    a.operands[0] = .{ .reg = R_TOTAL };
    a.operands[1] = .{ .imm_i64 = 0 };
    try list.append(a);
    line += 1;
    a = mk(.assign, line);
    a.operands[0] = .{ .reg = R_I };
    a.operands[1] = .{ .imm_i64 = 0 };
    try list.append(a);
    line += 1;
    try list.append(mkJmp(L_HEAD, line));
    line += 1;
    // header
    try list.append(mkLabel(L_HEAD, line));
    line += 1;
    try list.append(mkLoad(R_LEN_H, R_V, 8, line));
    line += 1;
    try list.append(mkOp(R_COND_H, if (head_ule) .ule else .ult, .{ .reg = R_I }, .{ .reg = R_LEN_H }, line));
    line += 1;
    try list.append(mkRelease(R_LEN_H, line));
    line += 1;
    try list.append(mkBr(R_COND_H, L_BODY, L_FALSE, line));
    line += 1;
    // body: the bounds check
    try list.append(mkLabel(L_BODY, line));
    line += 1;
    try list.append(mkRelease(R_COND_H, line));
    line += 1;
    if (store_between) {
        var st = mk(.store, line);
        st.operands[0] = .{ .reg = R_V };
        st.operands[1] = .{ .imm_u64 = 8 };
        st.operands[2] = .{ .text = "x" };
        st.operands[3] = .{ .ty = 0 };
        try list.append(st);
        line += 1;
    }
    if (redefine_iv_between) {
        try list.append(mkOp(R_I, .add, .{ .reg = R_I }, .{ .imm_i64 = 0 }, line));
        line += 1;
    }
    try list.append(mkLoad(R_LEN_C, R_V, off, line));
    line += 1;
    try list.append(mkOp(R_COND_C, .ult, .{ .reg = R_I }, .{ .reg = R_LEN_C }, line));
    line += 1;
    try list.append(mkBr(R_COND_C, L_OK, L_OOB, line));
    line += 1;
    // OOB block: lone panic
    try list.append(mkLabel(L_OOB, line));
    line += 1;
    var p = mk(.panic, line);
    p.operands[0] = .{ .text = "32" };
    try list.append(p);
    line += 1;
    // OK block: element load, sum, increment, back edge
    try list.append(mkLabel(L_OK, line));
    line += 1;
    try list.append(mkRelease(R_COND_C, line));
    line += 1;
    try list.append(mkLoad(R_PTR, R_V, 0, line));
    line += 1;
    try list.append(mkOp(R_MUL, .mul, .{ .reg = R_I }, .{ .imm_i64 = 8 }, line));
    line += 1;
    var pa = mk(.ptr_add, line);
    pa.operands[0] = .{ .reg = R_ADDR };
    pa.operands[1] = .{ .reg = R_PTR };
    pa.operands[2] = .{ .reg = R_MUL };
    try list.append(pa);
    line += 1;
    try list.append(mkLoad(R_ELEM, R_ADDR, 0, line));
    line += 1;
    try list.append(mkOp(R_SUM, .add, .{ .reg = R_TOTAL }, .{ .reg = R_ELEM }, line));
    line += 1;
    try list.append(mkOp(R_TOTAL, .add, .{ .reg = R_SUM }, .{ .imm_i64 = 0 }, line));
    line += 1;
    a = mk(.assign, line);
    a.operands[0] = .{ .reg = R_ONE };
    a.operands[1] = .{ .imm_i64 = 1 };
    try list.append(a);
    line += 1;
    try list.append(mkOp(R_INC, .add, .{ .reg = R_I }, .{ .reg = R_ONE }, line));
    line += 1;
    try list.append(mkRelease(R_I, line));
    line += 1;
    try list.append(mkOp(R_I, .add, .{ .reg = R_INC }, .{ .imm_i64 = 0 }, line));
    line += 1;
    try list.append(mkJmp(L_HEAD, line));
    line += 1;
    // exit
    try list.append(mkLabel(L_FALSE, line));
    line += 1;
    try list.append(mkRelease(R_COND_H, line));
    line += 1;
    try list.append(mkJmp(L_EXIT, line));
    line += 1;
    try list.append(mkLabel(L_EXIT, line));
    line += 1;
    try list.append(mkRelease(R_I, line));
    line += 1;
    var ret = mk(.return_, line);
    ret.operands[0] = .{ .reg = R_TOTAL };
    try list.append(ret);
    return list.toOwnedSlice();
}

test "obligation proves the canonical vec while loop check" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const insts = try buildVecLoop(arena.allocator(), false, false, false, false);
    const result = try analyzeFunction(arena.allocator(), insts, 0, "vec_loop_sum");
    try std.testing.expectEqual(@as(u32, 1), result.stats.loops_found);
    try std.testing.expectEqual(@as(u32, 1), result.stats.checks_found);
    try std.testing.expectEqual(@as(u32, 1), result.stats.target_class);
    try std.testing.expectEqual(@as(u32, 1), result.stats.proven);
    try std.testing.expectEqual(@as(u32, 0), result.stats.unproven);
    try std.testing.expectEqual(@as(u32, 1), result.obligations.len);
    try std.testing.expect(result.obligations[0].status == .proven);
}

test "obligation does not prove ule head vs ult check" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const insts = try buildVecLoop(arena.allocator(), true, false, false, false);
    const result = try analyzeFunction(arena.allocator(), insts, 0, "vec_loop_sum");
    try std.testing.expectEqual(@as(u32, 1), result.stats.checks_found);
    try std.testing.expectEqual(@as(u32, 1), result.stats.target_class);
    try std.testing.expectEqual(@as(u32, 0), result.stats.proven);
    try std.testing.expectEqual(@as(u32, 1), result.stats.unproven);
    try std.testing.expect(result.obligations[0].status == .unproven);
}

test "obligation refuses when a store sits between head and check" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const insts = try buildVecLoop(arena.allocator(), false, true, false, false);
    const result = try analyzeFunction(arena.allocator(), insts, 0, "vec_loop_sum");
    try std.testing.expectEqual(@as(u32, 1), result.stats.checks_found);
    try std.testing.expectEqual(@as(u32, 0), result.stats.target_class);
    try std.testing.expectEqual(@as(u32, 1), result.stats.not_target_class);
    try std.testing.expectEqual(@as(u32, 0), result.stats.proven);
}

test "obligation refuses when the check loads a different bound" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const insts = try buildVecLoop(arena.allocator(), false, false, true, false);
    const result = try analyzeFunction(arena.allocator(), insts, 0, "vec_loop_sum");
    try std.testing.expectEqual(@as(u32, 1), result.stats.checks_found);
    try std.testing.expectEqual(@as(u32, 0), result.stats.target_class);
    try std.testing.expectEqual(@as(u32, 0), result.stats.proven);
}

test "obligation refuses when the iv is redefined between head and check" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const insts = try buildVecLoop(arena.allocator(), false, false, false, true);
    const result = try analyzeFunction(arena.allocator(), insts, 0, "vec_loop_sum");
    try std.testing.expectEqual(@as(u32, 1), result.stats.checks_found);
    try std.testing.expectEqual(@as(u32, 0), result.stats.target_class);
    try std.testing.expectEqual(@as(u32, 0), result.stats.proven);
}

test "obligation ignores a vpush-shaped branch (false target is a call block)" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    // Canonical loop, with a VPUSH-shaped branch spliced into the body
    // just before the increment's `assign R_ONE`: `br c -> FAST, CALL`
    // where CALL holds a call, not a lone panic. It must not be counted
    // as a bounds check.
    const insts = try buildVecLoop(arena.allocator(), false, false, false, false);
    var ins_idx: usize = 0;
    for (insts, 0..) |inst, i| {
        if (inst.kind == .assign and regOf(inst.operands[0]) == R_ONE) {
            ins_idx = i;
            break;
        }
    }
    const L_FAST: u32 = 200;
    const L_VCALL: u32 = 201;
    var list2 = std.array_list.Managed(Inst).init(arena.allocator());
    for (insts, 0..) |inst, i| {
        if (i == ins_idx) {
            try list2.append(mkOp(R_COND_C, .ult, .{ .reg = R_LEN_C }, .{ .reg = R_LEN_H }, 999));
            try list2.append(mkBr(R_COND_C, L_FAST, L_VCALL, 999));
            try list2.append(mkLabel(L_VCALL, 999));
            var c = mk(.call, 999);
            c.operands[0] = .{ .text = "push" };
            try list2.append(c);
            try list2.append(mkLabel(L_FAST, 999));
        }
        try list2.append(inst);
    }
    const insts2 = try list2.toOwnedSlice();
    const result = try analyzeFunction(arena.allocator(), insts2, 0, "vec_loop_sum");
    // Only the real VEC_INDEX check is counted; the VPUSH branch is not.
    try std.testing.expectEqual(@as(u32, 1), result.stats.checks_found);
    try std.testing.expectEqual(@as(u32, 1), result.stats.proven);
}
