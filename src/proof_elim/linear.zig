// linear.zig — trusted Farkas checker for linear integer inequalities.
//
// Trust boundary (jihoo 02): the obligation generator defines integer
// semantics and is trusted; the prover is untrusted; THIS checker is small
// and trusted. It does pure multiply-add over i128 and verifies a Farkas
// certificate. A wrong certificate is rejected; a certificate the checker
// accepts is a sound proof of the goal from the given facts.
//
// Inequality form: sum(coeff[i] * x[i]) <= constant, over mathematical
// integers (variables are u64/i64 values, so i128 cannot overflow for
// real program values; the checker still fails closed on i128 overflow).
//
// Certificate form (scaled Farkas): weights w[i] >= 0 (one per fact) and a
// positive scale s. The checker verifies:
//   (1) for every variable v: sum_i w[i]*facts[i].coeff[v] == s * goal.coeff[v]
//   (2) sum_i w[i]*facts[i].constant <= s * goal.constant + (s - 1)
// Soundness: (1) gives s*(goal_lhs) = sum_i w[i]*(fact_lhs) <=
// sum_i w[i]*fact_const <= s*goal_const + (s-1), so goal_lhs <=
// goal_const + (s-1)/s < goal_const + 1; goal_lhs is an integer, hence
// goal_lhs <= goal_const. The (s-1) slack is exact for integer arithmetic
// and is what Fourier-Motzkin derivations produce (see fm.zig).
// A scale of 0 is rejected: a derivation that does not use the negated
// goal proves only that the facts are contradictory, never a goal.

const std = @import("std");

/// Maximum variables per inequality. The prototype's facts use at most a
/// handful (induction variable, bound, a constant offset). More than this
/// is a generator bug, not a case to support.
pub const max_vars: usize = 16;

pub const Ineq = struct {
    /// coeff[v] is the coefficient of variable v. Unused slots are 0.
    coeff: [max_vars]i128 = std.mem.zeroes([max_vars]i128),
    /// Number of variables in scope (all facts and the goal of one proof
    /// share the same variable numbering).
    nvars: u8 = 0,
    /// Right-hand side: sum(coeff[i]*x[i]) <= constant.
    constant: i128 = 0,

    pub fn isZero(self: Ineq) bool {
        for (self.coeff) |c| {
            if (c != 0) return false;
        }
        return true;
    }
};

pub const Certificate = struct {
    /// One non-negative weight per fact, in fact order.
    weights: []const i128,
    /// Positive scale (the coefficient on the negated goal in the
    /// Fourier-Motzkin derivation). Must be >= 1.
    scale: i128,
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

/// Verify a Farkas certificate. Returns false on any malformed input
/// (wrong lengths, negative weights, scale < 1) and on any i128 overflow
/// (fail closed: an overflowing certificate is rejected, the check stays).
pub fn checkCertificate(facts: []const Ineq, goal: Ineq, cert: Certificate) bool {
    if (cert.scale < 1) return false;
    if (cert.weights.len != facts.len) return false;
    for (cert.weights) |w| {
        if (w < 0) return false;
    }
    // Variable counts must agree across facts and goal.
    for (facts) |f| {
        if (f.nvars != goal.nvars) return false;
    }
    // (1) coefficient equality, per variable.
    var v: usize = 0;
    while (v < goal.nvars) : (v += 1) {
        var sum: i128 = 0;
        for (facts, cert.weights) |f, w| {
            const term = mulI128(w, f.coeff[v]) orelse return false;
            sum = addI128(sum, term) orelse return false;
        }
        const want = mulI128(cert.scale, goal.coeff[v]) orelse return false;
        if (sum != want) return false;
    }
    // (2) constant bound with the exact integer slack (scale - 1).
    var csum: i128 = 0;
    for (facts, cert.weights) |f, w| {
        const term = mulI128(w, f.constant) orelse return false;
        csum = addI128(csum, term) orelse return false;
    }
    const rhs = addI128(mulI128(cert.scale, goal.constant) orelse return false, cert.scale - 1) orelse return false;
    if (csum > rhs) return false;
    return true;
}

/// Build the inequality for `a < b` (unsigned): a - b <= -1.
pub fn ultIneq(a_var: u8, b_var: u8, nvars: u8) Ineq {
    var ineq = Ineq{ .nvars = nvars, .constant = -1 };
    ineq.coeff[a_var] = 1;
    ineq.coeff[b_var] = -1;
    return ineq;
}

/// Build the inequality for `a <= b` (unsigned): a - b <= 0.
pub fn uleIneq(a_var: u8, b_var: u8, nvars: u8) Ineq {
    var ineq = Ineq{ .nvars = nvars, .constant = 0 };
    ineq.coeff[a_var] = 1;
    ineq.coeff[b_var] = -1;
    return ineq;
}

/// Build the inequality for `a > b` (unsigned): b - a <= -1.
pub fn ugtIneq(a_var: u8, b_var: u8, nvars: u8) Ineq {
    return ultIneq(b_var, a_var, nvars);
}

/// Build the inequality for `a >= b` (unsigned): b - a <= 0.
pub fn ugeIneq(a_var: u8, b_var: u8, nvars: u8) Ineq {
    return uleIneq(b_var, a_var, nvars);
}

/// Type-range fact for a u64 variable: 0 <= x, i.e. -x <= 0.
pub fn u64NonnegIneq(x_var: u8, nvars: u8) Ineq {
    var ineq = Ineq{ .nvars = nvars, .constant = 0 };
    ineq.coeff[x_var] = -1;
    return ineq;
}

test "farkas checker accepts weight-1 proof of identical goal" {
    const facts = [_]Ineq{ultIneq(0, 1, 2)};
    const goal = ultIneq(0, 1, 2);
    const weights = [_]i128{1};
    try std.testing.expect(checkCertificate(&facts, goal, .{ .weights = &weights, .scale = 1 }));
}

test "farkas checker rejects wrong weights" {
    const facts = [_]Ineq{ultIneq(0, 1, 2)};
    const goal = ultIneq(0, 1, 2);
    const weights = [_]i128{2};
    // 2*(x-y) == 1*(x-y) fails on coefficients.
    try std.testing.expect(!checkCertificate(&facts, goal, .{ .weights = &weights, .scale = 1 }));
    const weights0 = [_]i128{0};
    try std.testing.expect(!checkCertificate(&facts, goal, .{ .weights = &weights0, .scale = 1 }));
}

test "farkas checker rejects a false goal" {
    // Fact: x - y <= -1 (x < y). Goal: x - y <= -2 (x < y - 1). Not implied.
    const facts = [_]Ineq{ultIneq(0, 1, 2)};
    var goal = ultIneq(0, 1, 2);
    goal.constant = -2;
    const weights = [_]i128{1};
    try std.testing.expect(!checkCertificate(&facts, goal, .{ .weights = &weights, .scale = 1 }));
    const weights2 = [_]i128{2};
    try std.testing.expect(!checkCertificate(&facts, goal, .{ .weights = &weights2, .scale = 2 }));
}

test "farkas checker rejects ule head proving ult goal" {
    // Fact: x - y <= 0 (x <= y). Goal: x - y <= -1 (x < y). Not implied.
    const facts = [_]Ineq{uleIneq(0, 1, 2)};
    const goal = ultIneq(0, 1, 2);
    const weights = [_]i128{1};
    try std.testing.expect(!checkCertificate(&facts, goal, .{ .weights = &weights, .scale = 1 }));
}

test "farkas checker rejects negative weights and bad scale" {
    const facts = [_]Ineq{ultIneq(0, 1, 2)};
    const goal = ultIneq(0, 1, 2);
    const neg = [_]i128{-1};
    try std.testing.expect(!checkCertificate(&facts, goal, .{ .weights = &neg, .scale = 1 }));
    const w = [_]i128{1};
    try std.testing.expect(!checkCertificate(&facts, goal, .{ .weights = &w, .scale = 0 }));
    const wrong_len = [_]i128{ 1, 1 };
    try std.testing.expect(!checkCertificate(&facts, goal, .{ .weights = &wrong_len, .scale = 1 }));
}

test "farkas checker accepts scaled proof" {
    // Facts: x - y <= -1, and again x - y <= -1. Goal x - y <= -1.
    // Weights (1,1), scale 2: coeff 2*(x-y) == 2*(x-y); const -2 <= 2*(-1)+1 = -1.
    const facts = [_]Ineq{ ultIneq(0, 1, 2), ultIneq(0, 1, 2) };
    const goal = ultIneq(0, 1, 2);
    const weights = [_]i128{ 1, 1 };
    try std.testing.expect(checkCertificate(&facts, goal, .{ .weights = &weights, .scale = 2 }));
}

test "farkas checker fails closed on i128 overflow" {
    var big = Ineq{ .nvars = 1, .constant = std.math.maxInt(i128) };
    big.coeff[0] = std.math.maxInt(i128);
    const facts = [_]Ineq{big};
    var goal = Ineq{ .nvars = 1, .constant = 0 };
    goal.coeff[0] = 1;
    const weights = [_]i128{2};
    try std.testing.expect(!checkCertificate(&facts, goal, .{ .weights = &weights, .scale = 1 }));
}

test "farkas checker proves via combination of two facts" {
    // Facts: x - y <= -1 (x < y) and y - z <= -1 (y < z).
    // Goal: x - z <= -2 (x < z - 1). Weights (1,1), scale 1:
    // coeff (x-z) == (x-z); const -2 <= -2. Proved.
    const facts = [_]Ineq{ ultIneq(0, 1, 3), ultIneq(1, 2, 3) };
    var goal = Ineq{ .nvars = 3, .constant = -2 };
    goal.coeff[0] = 1;
    goal.coeff[2] = -1;
    const weights = [_]i128{ 1, 1 };
    try std.testing.expect(checkCertificate(&facts, goal, .{ .weights = &weights, .scale = 1 }));
}
