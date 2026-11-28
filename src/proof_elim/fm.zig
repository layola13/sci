// fm.zig — Fourier-Motzkin prover (UNTRUSTED).
//
// Given facts and a goal, tries to find a Farkas certificate. The prover
// may be wrong (buggy, incomplete, slow) — that only loses proofs, never
// weakens a check, because linear.checkCertificate verifies every
// certificate before anything is deleted. The prover must therefore never
// be trusted: it returns null when it cannot prove, and its output is
// always re-checked.
//
// Method: Fourier-Motzkin elimination over the system {facts} ∪ {¬goal},
// tracking for every derived inequality its non-negative combination
// weights over the original rows. ¬goal of (c.x <= d) is (-c.x <= -d-1)
// (integer strictness). If elimination derives 0 <= -1, the weights on
// the fact rows (lambda) and the weight on the negated goal row (mu) form
// the scaled Farkas certificate {weights: lambda, scale: mu}; mu == 0
// means the facts alone are contradictory, which proves nothing about the
// goal, so null is returned. Row/derivation caps and i128 overflow both
// fail closed to null (the check is kept).

const std = @import("std");
const linear = @import("linear.zig");

const max_rows: usize = 512;
const max_orig: usize = 32;

const Row = struct {
    ineq: linear.Ineq,
    /// Combination weights over the original rows (facts, then the
    /// negated goal as the last row). Always non-negative.
    weights: []i128,
};

fn mulI128(a: i128, b: i128) ?i128 {
    const r = @mulWithOverflow(a, b);
    if (r[1] != 0) return null;
    return r[0];
}

fn addI128(a: i128, b: i128) ?i128 {
    const r = @addWithOverflow(a, b);
    if (r[1] != 0) return null;
    return r[0];
}

const ProverError = error{OutOfMemory};

/// Try to prove `goal` from `facts`. Returns a certificate (caller owns
/// the weights slice; free with the same allocator) or null if the goal
/// is not provable by this prover (including caps and overflow).
/// The caller MUST verify the result with linear.checkCertificate.
pub fn prove(
    allocator: std.mem.Allocator,
    facts: []const linear.Ineq,
    goal: linear.Ineq,
) ProverError!?linear.Certificate {
    const n_facts = facts.len;
    if (n_facts > max_orig - 1) return null;
    const n_orig = n_facts + 1;
    const nvars = goal.nvars;
    for (facts) |f| {
        if (f.nvars != nvars) return null;
    }

    var rows = std.array_list.Managed(Row).init(allocator);
    defer {
        for (rows.items) |r| allocator.free(r.weights);
        rows.deinit();
    }

    // Original rows: facts with unit weights, then the negated goal.
    for (facts, 0..) |f, i| {
        const w = try allocator.alloc(i128, n_orig);
        @memset(w, 0);
        w[i] = 1;
        try rows.append(.{ .ineq = f, .weights = w });
    }
    {
        var neg = linear.Ineq{ .nvars = nvars, .constant = -goal.constant - 1 };
        for (0..nvars) |v| neg.coeff[v] = -goal.coeff[v];
        const w = try allocator.alloc(i128, n_orig);
        @memset(w, 0);
        w[n_facts] = 1;
        try rows.append(.{ .ineq = neg, .weights = w });
    }

    // A contradiction already present among the original rows?
    if (findContradiction(rows.items, n_facts)) |cert| {
        return finishCertificate(allocator, cert, n_facts);
    }

    var v: usize = 0;
    while (v < nvars) : (v += 1) {
        var next = std.array_list.Managed(Row).init(allocator);
        defer {
            for (next.items) |r| allocator.free(r.weights);
            next.deinit();
        }
        var pos = std.array_list.Managed(usize).init(allocator);
        defer pos.deinit();
        var neg_rows = std.array_list.Managed(usize).init(allocator);
        defer neg_rows.deinit();
        for (rows.items, 0..) |r, i| {
            const c = r.ineq.coeff[v];
            if (c > 0) {
                try pos.append(i);
            } else if (c < 0) {
                try neg_rows.append(i);
            } else {
                // Zero-coefficient rows carry forward unchanged.
                const w = try allocator.dupe(i128, r.weights);
                try next.append(.{ .ineq = r.ineq, .weights = w });
            }
        }
        for (pos.items) |pi| {
            for (neg_rows.items) |ni| {
                const p = rows.items[pi];
                const q = rows.items[ni];
                const a = p.ineq.coeff[v]; // > 0
                const b = -q.ineq.coeff[v]; // > 0
                const combined = combineRows(allocator, p, q, b, a, n_orig) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Overflow => return null,
                };
                if (isContradiction(combined.ineq)) {
                    const cert = combined.weights;
                    defer allocator.free(combined.weights);
                    return finishCertificate(allocator, cert, n_facts);
                }
                if (combined.ineq.isZero() and combined.ineq.constant >= 0) {
                    // Trivially true; drop it.
                    allocator.free(combined.weights);
                    continue;
                }
                try next.append(combined);
                if (next.items.len > max_rows) return null;
            }
        }
        // Swap next into rows (freeing the old rows' weights).
        for (rows.items) |r| allocator.free(r.weights);
        rows.clearRetainingCapacity();
        for (next.items) |r| try rows.append(r);
        // next's weights are now owned by rows; prevent double-free.
        next.clearRetainingCapacity();
        if (findContradiction(rows.items, n_facts)) |cert| {
            return finishCertificate(allocator, cert, n_facts);
        }
        if (rows.items.len == 0) return null;
    }
    return null;
}

fn isContradiction(ineq: linear.Ineq) bool {
    return ineq.isZero() and ineq.constant < 0;
}

/// If any row is a contradiction, return its weight vector (borrowed).
fn findContradiction(rows: []const Row, n_facts: usize) ?[]const i128 {
    _ = n_facts;
    for (rows) |r| {
        if (isContradiction(r.ineq)) return r.weights;
    }
    return null;
}

/// Build the returned certificate from a contradiction's weight vector.
/// weights[0..n_facts] are the fact weights, weights[n_facts] is mu.
/// mu == 0 means the facts alone contradict: proves nothing -> null.
fn finishCertificate(
    allocator: std.mem.Allocator,
    weights: []const i128,
    n_facts: usize,
) ProverError!?linear.Certificate {
    const mu = weights[n_facts];
    if (mu <= 0) return null;
    const out = try allocator.alloc(i128, n_facts);
    @memcpy(out, weights[0..n_facts]);
    return .{ .weights = out, .scale = mu };
}

const CombineError = error{ OutOfMemory, Overflow };

/// new = bp * p + ap * q (both multipliers non-negative), combining the
/// inequality coefficients, constant, and weight vectors.
fn combineRows(
    allocator: std.mem.Allocator,
    p: Row,
    q: Row,
    bp: i128,
    ap: i128,
    n_orig: usize,
) CombineError!Row {
    var ineq = linear.Ineq{ .nvars = p.ineq.nvars, .constant = 0 };
    for (0..p.ineq.nvars) |i| {
        const t1 = mulI128(bp, p.ineq.coeff[i]) orelse return error.Overflow;
        const t2 = mulI128(ap, q.ineq.coeff[i]) orelse return error.Overflow;
        ineq.coeff[i] = addI128(t1, t2) orelse return error.Overflow;
    }
    const c1 = mulI128(bp, p.ineq.constant) orelse return error.Overflow;
    const c2 = mulI128(ap, q.ineq.constant) orelse return error.Overflow;
    ineq.constant = addI128(c1, c2) orelse return error.Overflow;
    const w = try allocator.alloc(i128, n_orig);
    for (0..n_orig) |i| {
        const t1 = mulI128(bp, p.weights[i]) orelse {
            allocator.free(w);
            return error.Overflow;
        };
        const t2 = mulI128(ap, q.weights[i]) orelse {
            allocator.free(w);
            return error.Overflow;
        };
        w[i] = addI128(t1, t2) orelse {
            allocator.free(w);
            return error.Overflow;
        };
    }
    return .{ .ineq = ineq, .weights = w };
}

test "fm proves identical goal from one fact" {
    const alloc = std.testing.allocator;
    const facts = [_]linear.Ineq{linear.ultIneq(0, 1, 2)};
    const goal = linear.ultIneq(0, 1, 2);
    const cert = (try prove(alloc, &facts, goal)) orelse return error.TestUnexpectedResult;
    defer alloc.free(cert.weights);
    try std.testing.expect(linear.checkCertificate(&facts, goal, cert));
}

test "fm fails on ule head vs ult goal" {
    const alloc = std.testing.allocator;
    const facts = [_]linear.Ineq{linear.uleIneq(0, 1, 2)};
    const goal = linear.ultIneq(0, 1, 2);
    try std.testing.expect((try prove(alloc, &facts, goal)) == null);
}

test "fm proves transitive chain" {
    const alloc = std.testing.allocator;
    const facts = [_]linear.Ineq{ linear.ultIneq(0, 1, 3), linear.ultIneq(1, 2, 3) };
    var goal = linear.Ineq{ .nvars = 3, .constant = -2 };
    goal.coeff[0] = 1;
    goal.coeff[2] = -1;
    const cert = (try prove(alloc, &facts, goal)) orelse return error.TestUnexpectedResult;
    defer alloc.free(cert.weights);
    try std.testing.expect(linear.checkCertificate(&facts, goal, cert));
}

test "fm fails on false goal" {
    const alloc = std.testing.allocator;
    const facts = [_]linear.Ineq{linear.ultIneq(0, 1, 2)};
    var goal = linear.ultIneq(0, 1, 2);
    goal.constant = -2;
    try std.testing.expect((try prove(alloc, &facts, goal)) == null);
}

test "fm proves with a range fact" {
    const alloc = std.testing.allocator;
    // Facts: x < y and 0 <= x (u64 range). Goal: x - y <= -1 (same as fact 0).
    const facts = [_]linear.Ineq{ linear.ultIneq(0, 1, 2), linear.u64NonnegIneq(0, 2) };
    const goal = linear.ultIneq(0, 1, 2);
    const cert = (try prove(alloc, &facts, goal)) orelse return error.TestUnexpectedResult;
    defer alloc.free(cert.weights);
    try std.testing.expect(linear.checkCertificate(&facts, goal, cert));
}

test "fm returns null when facts alone contradict" {
    const alloc = std.testing.allocator;
    // Facts: x - y <= -1 and y - x <= -1 (x < y and y < x). Contradictory.
    // Goal x - y <= -1 must NOT be "proved" from contradictory facts.
    const facts = [_]linear.Ineq{ linear.ultIneq(0, 1, 2), linear.ultIneq(1, 0, 2) };
    const goal = linear.ultIneq(0, 1, 2);
    try std.testing.expect((try prove(alloc, &facts, goal)) == null);
}
