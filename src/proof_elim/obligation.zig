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
//   * the header may be reached through a chain of bounds checks on
//     the condition's own indices (the condition's Vec indexing emits
//     its checks first); the real condition is found by following the
//     OK-chain past leading bounds-check `br`s, and
//   * the check's bound base may be a fresh register recomputing the
//     same address; two bases are the same location when their
//     defining chains compute the same value (see sameValue), and
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

/// Do two operands denote the same value? Immediates compare by value;
/// registers compare through `sameValue`. Used to compare the operands
/// of two defining instructions while checking base equivalence.
fn sameOperand(insts: []const Inst, func_start: usize, o1: Operand, pos1: usize, o2: Operand, pos2: usize, depth: u32, min_head: *usize) bool {
    if (immI64Of(o1)) |v1| {
        if (immI64Of(o2)) |v2| return v1 == v2;
        return false;
    }
    if (immI64Of(o2) != null) return false;
    const r1 = regOf(o1) orelse return false;
    const r2 = regOf(o2) orelse return false;
    return sameValue(insts, func_start, r1, pos1, r2, pos2, depth, min_head);
}

/// Do two registers hold the same value, where `r1` is used at `pos1`
/// and `r2` at `pos2`? The defining instruction chains must be
/// structurally identical over the pure kinds the plugin uses to
/// compute an address (load / ptr_add / add-mul / borrow / assign):
/// same kinds, same op kinds, same constants, same leaf registers.
/// A leaf is a register with no definition in [func_start, use) —
/// typically a function parameter; two leaves are the same value when
/// they are the same register and it is not redefined between the two
/// uses. `min_head` records the earliest head-side (first-argument)
/// definition visited, so the caller can extend its no-store scan over
/// the head chain. A load's value also depends on memory; the caller
/// must guarantee no store/call between the two chains (the mutation
/// scan in analyzeCheck does this over [head chain start, check bound
/// load)). Anything unrecognized returns false: the safe direction is
/// to lose a proof, never to claim a false equivalence.
fn sameValue(insts: []const Inst, func_start: usize, r1: u32, pos1: usize, r2: u32, pos2: usize, depth: u32, min_head: *usize) bool {
    if (depth > 16) return false;
    if (r1 == r2) {
        const lo = @min(pos1, pos2);
        const hi = @max(pos1, pos2);
        return versionAt(insts, lo, hi, r1) == 0;
    }
    const d1 = findDef(insts, func_start, pos1, r1) orelse return false;
    const d2 = findDef(insts, func_start, pos2, r2) orelse return false;
    if (d1 < min_head.*) min_head.* = d1;
    const x1 = insts[d1];
    const x2 = insts[d2];
    if (x1.kind != x2.kind) return false;
    switch (x1.kind) {
        .load => {
            if (!sameOperand(insts, func_start, x1.operands[2], d1, x2.operands[2], d2, depth + 1, min_head)) return false;
            const b1 = regOf(x1.operands[1]) orelse return false;
            const b2 = regOf(x2.operands[1]) orelse return false;
            return sameValue(insts, func_start, b1, d1, b2, d2, depth + 1, min_head);
        },
        .ptr_add => {
            return sameOperand(insts, func_start, x1.operands[1], d1, x2.operands[1], d2, depth + 1, min_head) and
                sameOperand(insts, func_start, x1.operands[2], d1, x2.operands[2], d2, depth + 1, min_head);
        },
        .op => {
            if (x1.op_kind != x2.op_kind) return false;
            const k = x1.op_kind orelse return false;
            if (k != .add and k != .mul) return false;
            // add/mul commute: try both operand orders.
            const fwd = sameOperand(insts, func_start, x1.operands[1], d1, x2.operands[1], d2, depth + 1, min_head) and
                sameOperand(insts, func_start, x1.operands[2], d1, x2.operands[2], d2, depth + 1, min_head);
            if (fwd) return true;
            return sameOperand(insts, func_start, x1.operands[1], d1, x2.operands[2], d2, depth + 1, min_head) and
                sameOperand(insts, func_start, x1.operands[2], d1, x2.operands[1], d2, depth + 1, min_head);
        },
        .borrow => {
            const a1 = regOf(x1.operands[1]) orelse return false;
            const a2 = regOf(x2.operands[1]) orelse return false;
            return sameValue(insts, func_start, a1, d1, a2, d2, depth + 1, min_head);
        },
        .assign => {
            return sameOperand(insts, func_start, x1.operands[1], d1, x2.operands[1], d2, depth + 1, min_head);
        },
        else => return false,
    }
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

/// Parse a loop header: the header block's OK-chain must reach a `br`
/// whose condition is defined by an unsigned comparison of an
/// induction-variable register against a register loaded from
/// (base, offset). The header block itself may end in a bounds-check
/// `br` (the loop condition's own Vec indexing emits its checks
/// first); `findLoopCondBr` follows the OK-chain past those to the
/// real condition. Returns null when the shape does not match.
fn parseLoopHead(insts: []const Inst, header_idx: usize, body_end: usize) ?LoopHead {
    const cond = findLoopCondBr(insts, header_idx, body_end) orelse return null;
    const br_idx = cond.br_idx;
    const cond_reg = regOf(insts[br_idx].operands[0]) orelse return null;
    const cmp_idx = findDef(insts, header_idx, br_idx, cond_reg) orelse return null;
    const cmp = insts[cmp_idx];
    if (cmp.kind != .op) return null;
    const cmp_kind = cmp.op_kind orelse return null;
    if (cmp_kind != .ult and cmp_kind != .ule and cmp_kind != .ugt and cmp_kind != .uge) return null;
    const lhs = regOf(cmp.operands[1]) orelse return null;
    const rhs = regOf(cmp.operands[2]) orelse return null;
    // One side is the IV, the other is the bound register (a load).
    // Try both assignments; the bound side must be a load.
    const candidates = [_]struct { iv: u32, bound: u32 }{
        .{ .iv = lhs, .bound = rhs },
        .{ .iv = rhs, .bound = lhs },
    };
    for (candidates) |c| {
        const load_idx = findDef(insts, header_idx, cmp_idx, c.bound) orelse continue;
        const load = loadOperands(insts[load_idx]) orelse continue;
        return .{
            .header_label_idx = header_idx,
            .header_end = blockEnd(insts, cond.block_start),
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

/// Walk the OK-chain from the header block to the real loop-condition
/// `br`. The header block may end in a bounds-check `br` when the loop
/// condition itself indexes a Vec (midx_eq_pos: the condition `i <
/// len(s[e][a])` is preceded by `e < len(s)` and `a < len(s[e])`
/// checks, each ending its block with a `br` to a lone-panic OOB
/// block). A bounds-check `br` is recognized exactly as the check
/// scanner recognizes one: its false target holds exactly one `panic`.
/// Following each such check's OK (true) target reaches the block
/// whose last `br` is the loop condition (true -> body, false ->
/// exit). Returns the condition block's start and `br` index, or null
/// when the chain leaves the loop, ends without a `br`, or runs too
/// long. The safe direction is null: the loop is skipped, no proof
/// is claimed.
fn findLoopCondBr(insts: []const Inst, header_idx: usize, body_end: usize) ?struct { block_start: usize, br_idx: usize } {
    var cur = header_idx;
    var steps: usize = 0;
    while (steps < 32) : (steps += 1) {
        const end = blockEnd(insts, cur);
        if (end == 0 or end > insts.len) return null;
        const br_idx = end - 1;
        if (insts[br_idx].kind != .br) return null;
        const false_label = labelOf(insts[br_idx].operands[3]) orelse return null;
        const false_def = findLabelDef(insts, false_label) orelse return null;
        if (lonePanicBlock(insts, false_def) == null) {
            return .{ .block_start = cur, .br_idx = br_idx };
        }
        const true_label = labelOf(insts[br_idx].operands[1]) orelse return null;
        const next = findLabelDef(insts, true_label) orelse return null;
        if (next <= cur or next > body_end) return null;
        cur = next;
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
    if (bound_offset != head.bound_offset) {
        return make_ob(.not_target_class, "check bound loads a different offset than the head bound", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }
    // The bound base is usually a fresh register per load: the plugin
    // recomputes the base address (e.g. s[e][a]) for every access. The
    // bases are the same location when their defining chains compute
    // the same value; the head chain's earliest instruction extends
    // the no-store scan below. When the registers are already the
    // same, the chain starts at the head bound load (as before).
    var head_chain_start = head.bound_load_idx;
    if (bound_base != head.bound_base) {
        if (!sameValue(insts, func_start, head.bound_base, head.bound_load_idx, bound_base, bound_load_idx, 0, &head_chain_start)) {
            return make_ob(.not_target_class, "check bound base holds a different value than the head bound base", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
        }
    }
    if (versionAt(insts, func_start, head.bound_load_idx, head.bound_base) != versionAt(insts, func_start, bound_load_idx, bound_base)) {
        return make_ob(.not_target_class, "bound base register redefined between head and check", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }
    if (findIVIncrement(insts, head.header_label_idx, head.body_end, head.iv_reg) == null) {
        return make_ob(.not_target_class, "no positive-constant increment of the induction variable in the loop body", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
    }
    // Strict mutation scan on [head base chain start, check bound load].
    // The head chain's loads must read the same memory the check chain's
    // loads read; with no store/call anywhere between the two chains,
    // and no leaf redefinition (checked in sameValue), the recomputed
    // base holds the same value. The base-redefinition and take checks
    // apply only from the head bound load onward; the head base chain
    // itself defines the base before that point.
    var s = head_chain_start;
    while (s < bound_load_idx and s < insts.len) : (s += 1) {
        const k = insts[s].kind;
        if (isMemoryWrite(k) or isCall(k)) {
            return make_ob(.not_target_class, "store or call on the path from head load to check load", head_fact, goal, null, br_idx, base, ok_label, oob_label, func_name, insts);
        }
        if (s >= head.bound_load_idx) {
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

// ---------------------------------------------------------------- midx-shape tests
//
// A loop whose condition indexes a Vec: the header block ends in a
// bounds check on the condition's own index, and the real condition
// (`ult i, len`) lives two OK-chain steps later. The body checks the
// same bound through a recomputed base address (fresh registers,
// structurally identical chain). Mirrors midx_eq_pos loop 1
// (L_WHILE_HEAD_1874), reduced to one index level.

const M_S: u32 = 30; // the Vec (parameter)
const M_E: u32 = 31; // index e (parameter)
const M_A: u32 = 32; // index a (parameter)
const M_I: u32 = 33; // induction variable
const M_TOTAL: u32 = 34;

const M_H_PTR: u32 = 40;
const M_H_MUL: u32 = 41;
const M_H_ADDR: u32 = 42;
const M_H_BASE: u32 = 43;
const M_H_LEN: u32 = 44;
const M_H_COND: u32 = 45;
const M_C_PTR: u32 = 46;
const M_C_MUL: u32 = 47;
const M_C_ADDR: u32 = 48;
const M_C_BASE: u32 = 49;
const M_C_LEN: u32 = 50;
const M_C_COND: u32 = 51;
const M_D_PTR: u32 = 52;
const M_D_MUL: u32 = 53;
const M_D_ADDR: u32 = 54;
const M_D_BASE: u32 = 55;
const M_D_LEN: u32 = 56;
const M_D_COND: u32 = 57;
const M_F_PTR: u32 = 58;
const M_F_MUL: u32 = 59;
const M_F_ADDR: u32 = 60;
const M_F_BASE: u32 = 61;
const M_F_LEN: u32 = 62;
const M_F_COND: u32 = 63;
const M_E_LEN: u32 = 64;
const M_E_COND: u32 = 65;
const M_A_LEN: u32 = 66;
const M_A_COND: u32 = 67;
const M_ONE: u32 = 68;
const M_INC: u32 = 69;

const M_L_ENTRY: u32 = 299;
const M_L_HEAD: u32 = 300;
const M_L_OKE: u32 = 301;
const M_L_CONDBLK: u32 = 302;
const M_L_BODY: u32 = 303;
const M_L_FALSE: u32 = 304;
const M_L_EXIT: u32 = 305;
const M_L_OOB_E: u32 = 306;
const M_L_OOB_A: u32 = 307;
const M_L_OK1: u32 = 308;
const M_L_OOB1: u32 = 309;
const M_L_OK2: u32 = 310;
const M_L_OOB2: u32 = 311;
const M_L_OK3: u32 = 312;
const M_L_OOB3: u32 = 313;

fn mkPtrAdd(dst: u32, base: u32, off: u32, line: u32) Inst {
    var inst = mk(.ptr_add, line);
    inst.operands[0] = .{ .reg = dst };
    inst.operands[1] = .{ .reg = base };
    inst.operands[2] = .{ .reg = off };
    return inst;
}

/// The midx-shaped loop: header ends in an `e` bounds check, the next
/// block in an `a` bounds check, the third block holds the real
/// condition `ult i, len(s[e])`. The body has three `i` checks against
/// len(s[e]): one through a recomputed base (must prove), one through
/// a base indexed by `a` instead of `e` (must refuse), one through a
/// base with a different stride (must refuse).
fn buildMidxLoop(allocator: std.mem.Allocator) ![]Inst {
    var list = std.array_list.Managed(Inst).init(allocator);
    var line: u32 = 1;
    try list.append(mk(.func_decl, line));
    line += 1;
    try list.append(mkLabel(M_L_ENTRY, line));
    line += 1;
    var a = mk(.assign, line);
    a.operands[0] = .{ .reg = M_TOTAL };
    a.operands[1] = .{ .imm_i64 = 0 };
    try list.append(a);
    line += 1;
    a = mk(.assign, line);
    a.operands[0] = .{ .reg = M_I };
    a.operands[1] = .{ .imm_i64 = 0 };
    try list.append(a);
    line += 1;
    try list.append(mkJmp(M_L_HEAD, line));
    line += 1;
    // Header: `e < len(s)` bounds check.
    try list.append(mkLabel(M_L_HEAD, line));
    line += 1;
    try list.append(mkLoad(M_E_LEN, M_S, 8, line));
    line += 1;
    try list.append(mkOp(M_E_COND, .ult, .{ .reg = M_E }, .{ .reg = M_E_LEN }, line));
    line += 1;
    try list.append(mkBr(M_E_COND, M_L_OKE, M_L_OOB_E, line));
    line += 1;
    try list.append(mkLabel(M_L_OOB_E, line));
    line += 1;
    var p = mk(.panic, line);
    p.operands[0] = .{ .text = "32" };
    try list.append(p);
    line += 1;
    // Next: `a < len(s)` bounds check.
    try list.append(mkLabel(M_L_OKE, line));
    line += 1;
    try list.append(mkLoad(M_A_LEN, M_S, 8, line));
    line += 1;
    try list.append(mkOp(M_A_COND, .ult, .{ .reg = M_A }, .{ .reg = M_A_LEN }, line));
    line += 1;
    try list.append(mkBr(M_A_COND, M_L_CONDBLK, M_L_OOB_A, line));
    line += 1;
    try list.append(mkLabel(M_L_OOB_A, line));
    line += 1;
    p = mk(.panic, line);
    p.operands[0] = .{ .text = "32" };
    try list.append(p);
    line += 1;
    // Real condition block: base = s[e], `ult i, len(s[e])`.
    try list.append(mkLabel(M_L_CONDBLK, line));
    line += 1;
    try list.append(mkLoad(M_H_PTR, M_S, 0, line));
    line += 1;
    try list.append(mkOp(M_H_MUL, .mul, .{ .reg = M_E }, .{ .imm_i64 = 8 }, line));
    line += 1;
    try list.append(mkPtrAdd(M_H_ADDR, M_H_PTR, M_H_MUL, line));
    line += 1;
    try list.append(mkLoad(M_H_BASE, M_H_ADDR, 0, line));
    line += 1;
    try list.append(mkLoad(M_H_LEN, M_H_BASE, 8, line));
    line += 1;
    try list.append(mkOp(M_H_COND, .ult, .{ .reg = M_I }, .{ .reg = M_H_LEN }, line));
    line += 1;
    try list.append(mkBr(M_H_COND, M_L_BODY, M_L_FALSE, line));
    line += 1;
    // Body check 1: same bound, recomputed base (must prove).
    try list.append(mkLabel(M_L_BODY, line));
    line += 1;
    try list.append(mkLoad(M_C_PTR, M_S, 0, line));
    line += 1;
    try list.append(mkOp(M_C_MUL, .mul, .{ .reg = M_E }, .{ .imm_i64 = 8 }, line));
    line += 1;
    try list.append(mkPtrAdd(M_C_ADDR, M_C_PTR, M_C_MUL, line));
    line += 1;
    try list.append(mkLoad(M_C_BASE, M_C_ADDR, 0, line));
    line += 1;
    try list.append(mkLoad(M_C_LEN, M_C_BASE, 8, line));
    line += 1;
    try list.append(mkOp(M_C_COND, .ult, .{ .reg = M_I }, .{ .reg = M_C_LEN }, line));
    line += 1;
    try list.append(mkBr(M_C_COND, M_L_OK1, M_L_OOB1, line));
    line += 1;
    try list.append(mkLabel(M_L_OOB1, line));
    line += 1;
    p = mk(.panic, line);
    p.operands[0] = .{ .text = "32" };
    try list.append(p);
    line += 1;
    // Body check 2: base indexed by `a` instead of `e` (must refuse).
    try list.append(mkLabel(M_L_OK1, line));
    line += 1;
    try list.append(mkLoad(M_D_PTR, M_S, 0, line));
    line += 1;
    try list.append(mkOp(M_D_MUL, .mul, .{ .reg = M_A }, .{ .imm_i64 = 8 }, line));
    line += 1;
    try list.append(mkPtrAdd(M_D_ADDR, M_D_PTR, M_D_MUL, line));
    line += 1;
    try list.append(mkLoad(M_D_BASE, M_D_ADDR, 0, line));
    line += 1;
    try list.append(mkLoad(M_D_LEN, M_D_BASE, 8, line));
    line += 1;
    try list.append(mkOp(M_D_COND, .ult, .{ .reg = M_I }, .{ .reg = M_D_LEN }, line));
    line += 1;
    try list.append(mkBr(M_D_COND, M_L_OK2, M_L_OOB2, line));
    line += 1;
    try list.append(mkLabel(M_L_OOB2, line));
    line += 1;
    p = mk(.panic, line);
    p.operands[0] = .{ .text = "32" };
    try list.append(p);
    line += 1;
    // Body check 3: base with a different stride, `e * 16` (must refuse).
    try list.append(mkLabel(M_L_OK2, line));
    line += 1;
    try list.append(mkLoad(M_F_PTR, M_S, 0, line));
    line += 1;
    try list.append(mkOp(M_F_MUL, .mul, .{ .reg = M_E }, .{ .imm_i64 = 16 }, line));
    line += 1;
    try list.append(mkPtrAdd(M_F_ADDR, M_F_PTR, M_F_MUL, line));
    line += 1;
    try list.append(mkLoad(M_F_BASE, M_F_ADDR, 0, line));
    line += 1;
    try list.append(mkLoad(M_F_LEN, M_F_BASE, 8, line));
    line += 1;
    try list.append(mkOp(M_F_COND, .ult, .{ .reg = M_I }, .{ .reg = M_F_LEN }, line));
    line += 1;
    try list.append(mkBr(M_F_COND, M_L_OK3, M_L_OOB3, line));
    line += 1;
    try list.append(mkLabel(M_L_OOB3, line));
    line += 1;
    p = mk(.panic, line);
    p.operands[0] = .{ .text = "32" };
    try list.append(p);
    line += 1;
    // Increment (copy form) and back edge.
    try list.append(mkLabel(M_L_OK3, line));
    line += 1;
    a = mk(.assign, line);
    a.operands[0] = .{ .reg = M_ONE };
    a.operands[1] = .{ .imm_i64 = 1 };
    try list.append(a);
    line += 1;
    try list.append(mkOp(M_INC, .add, .{ .reg = M_I }, .{ .reg = M_ONE }, line));
    line += 1;
    try list.append(mkOp(M_I, .add, .{ .reg = M_INC }, .{ .imm_i64 = 0 }, line));
    line += 1;
    try list.append(mkJmp(M_L_HEAD, line));
    line += 1;
    // Exit.
    try list.append(mkLabel(M_L_FALSE, line));
    line += 1;
    try list.append(mkJmp(M_L_EXIT, line));
    line += 1;
    try list.append(mkLabel(M_L_EXIT, line));
    line += 1;
    var ret = mk(.return_, line);
    ret.operands[0] = .{ .reg = M_TOTAL };
    try list.append(ret);
    return list.toOwnedSlice();
}

test "obligation follows the OK-chain and proves the recomputed-base check" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const insts = try buildMidxLoop(arena.allocator());
    const result = try analyzeFunction(arena.allocator(), insts, 0, "midx_eq_pos");
    // 5 checks: the `e` and `a` header checks plus the 3 body `i` checks.
    try std.testing.expectEqual(@as(u32, 1), result.stats.loops_found);
    try std.testing.expectEqual(@as(u32, 5), result.stats.checks_found);
    try std.testing.expectEqual(@as(u32, 1), result.stats.target_class);
    try std.testing.expectEqual(@as(u32, 1), result.stats.proven);
    try std.testing.expectEqual(@as(u32, 0), result.stats.unproven);
    try std.testing.expectEqual(@as(u32, 4), result.stats.not_target_class);
    try std.testing.expectEqual(@as(u32, 5), result.obligations.len);
    // Scan order: e-check, a-check, recomputed-base i-check, a-indexed
    // i-check, stride-16 i-check.
    try std.testing.expect(result.obligations[0].status == .not_target_class);
    try std.testing.expectEqualStrings("check index is not the loop induction variable", result.obligations[0].reason);
    try std.testing.expect(result.obligations[1].status == .not_target_class);
    try std.testing.expectEqualStrings("check index is not the loop induction variable", result.obligations[1].reason);
    try std.testing.expect(result.obligations[2].status == .proven);
    try std.testing.expect(result.obligations[3].status == .not_target_class);
    try std.testing.expectEqualStrings("check bound base holds a different value than the head bound base", result.obligations[3].reason);
    try std.testing.expect(result.obligations[4].status == .not_target_class);
    try std.testing.expectEqualStrings("check bound base holds a different value than the head bound base", result.obligations[4].reason);
}

test "obligation finds no loop head when the OK-chain ends without a br" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    // Canonical loop shape, but the header block ends in a bounds check
    // whose OK target jumps straight to the body: no block on the chain
    // ends in a loop-condition `br`, so parseLoopHead must return null
    // and the loop is skipped (not misparsed as iv = e).
    var list = std.array_list.Managed(Inst).init(arena.allocator());
    var line: u32 = 1;
    try list.append(mk(.func_decl, line));
    line += 1;
    try list.append(mkLabel(M_L_ENTRY, line));
    line += 1;
    var a = mk(.assign, line);
    a.operands[0] = .{ .reg = M_I };
    a.operands[1] = .{ .imm_i64 = 0 };
    try list.append(a);
    line += 1;
    try list.append(mkJmp(M_L_HEAD, line));
    line += 1;
    try list.append(mkLabel(M_L_HEAD, line));
    line += 1;
    try list.append(mkLoad(M_E_LEN, M_S, 8, line));
    line += 1;
    try list.append(mkOp(M_E_COND, .ult, .{ .reg = M_E }, .{ .reg = M_E_LEN }, line));
    line += 1;
    try list.append(mkBr(M_E_COND, M_L_OKE, M_L_OOB_E, line));
    line += 1;
    try list.append(mkLabel(M_L_OOB_E, line));
    line += 1;
    var p = mk(.panic, line);
    p.operands[0] = .{ .text = "32" };
    try list.append(p);
    line += 1;
    // OK target ends in an unconditional jump: the chain dies here.
    try list.append(mkLabel(M_L_OKE, line));
    line += 1;
    try list.append(mkJmp(M_L_BODY, line));
    line += 1;
    // Body: one `i` check, increment, back edge.
    try list.append(mkLabel(M_L_BODY, line));
    line += 1;
    try list.append(mkLoad(M_C_LEN, M_S, 8, line));
    line += 1;
    try list.append(mkOp(M_C_COND, .ult, .{ .reg = M_I }, .{ .reg = M_C_LEN }, line));
    line += 1;
    try list.append(mkBr(M_C_COND, M_L_OK1, M_L_OOB1, line));
    line += 1;
    try list.append(mkLabel(M_L_OOB1, line));
    line += 1;
    p = mk(.panic, line);
    p.operands[0] = .{ .text = "32" };
    try list.append(p);
    line += 1;
    try list.append(mkLabel(M_L_OK1, line));
    line += 1;
    a = mk(.assign, line);
    a.operands[0] = .{ .reg = M_ONE };
    a.operands[1] = .{ .imm_i64 = 1 };
    try list.append(a);
    line += 1;
    try list.append(mkOp(M_INC, .add, .{ .reg = M_I }, .{ .reg = M_ONE }, line));
    line += 1;
    try list.append(mkOp(M_I, .add, .{ .reg = M_INC }, .{ .imm_i64 = 0 }, line));
    line += 1;
    try list.append(mkJmp(M_L_HEAD, line));
    line += 1;
    try list.append(mkLabel(M_L_EXIT, line));
    line += 1;
    var ret = mk(.return_, line);
    ret.operands[0] = .{ .reg = M_TOTAL };
    try list.append(ret);
    const insts2 = try list.toOwnedSlice();
    const result = try analyzeFunction(arena.allocator(), insts2, 0, "dead_chain");
    try std.testing.expectEqual(@as(u32, 0), result.stats.loops_found);
    try std.testing.expectEqual(@as(u32, 0), result.stats.checks_found);
    try std.testing.expectEqual(@as(u32, 0), result.obligations.len);
}
