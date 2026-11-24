const std = @import("std");
const trap = @import("../common/trap.zig");
const verify = @import("free_annotated_slice.zig").verify;

fn expectOk(source: []const u8) !void {
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
        },
        .trap => |report| {
            std.debug.print("unexpected trap {s}: {s}\n", .{ @tagName(report.trap), report.message });
            return error.TestUnexpectedResult;
        },
    }
}

fn expectTrap(source: []const u8, expected: trap.Trap) !void {
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(expected, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

// VERIFIER-BFULL (G1): a scalar parameter in a NON-LAST function that is
// never released must not trap 1012. Minimal shape of
// demos/rosetta/18_option_map (@double(x: u64)).
test "bfull: scalar param in non-last function is not a leak" {
    try expectOk(
        \\@double(x: u64) -> u64:
        \\    y = add x, x
        \\    return y
        \\
        \\@main() -> i32:
        \\    v = call @double(3)
        \\    !v
        \\    return 0
    );
}

// VERIFIER-BFULL (G1): same shape as demos/rosetta/52_queue_rotate
// (@rotate_three(a: i32, b: i32, c: i32)).
test "bfull: three scalar params in non-last function are not a leak" {
    try expectOk(
        \\@rotate_three(a: i32, b: i32, c: i32) -> i32:
        \\    first = add b, 0
        \\    second = add c, 0
        \\    third = add a, 0
        \\    total = add first, second
        \\    total2 = add total, third
        \\    !first
        \\    !second
        \\    !third
        \\    !total
        \\    !total2
        \\    return 0
        \\
        \\@main() -> i32:
        \\    value = call @rotate_three(1, 2, 3)
        \\    !value
        \\    return 0
    );
}

// VERIFIER-BFULL (G2): a call returning a scalar type yields a freely
// droppable value — no explicit `!` needed at the call site.
test "bfull: scalar call result needs no explicit release" {
    try expectOk(
        \\@seven() -> i64:
        \\    return 7
        \\
        \\@main() -> i32:
        \\    v = call @seven()
        \\    w = add v, 1
        \\    !w
        \\    return 0
    );
}

// VERIFIER-BFULL (G3): unwrapping a fallible scalar yields a scalar.
test "bfull: fallible scalar unwrap needs no explicit release" {
    try expectOk(
        \\@maybe() -> i64!:
        \\    return 7
        \\
        \\@main() -> i32:
        \\    v = call @maybe()
        \\    w = ? v
        \\    !w
        \\    return 0
    );
}

// VERIFIER-BFULL (G4): scalars are freely copyable — `y = x; z = x`
// must not use-after-move the source, for parameters and for op-result
// temporaries alike.
test "bfull: scalar param can be copied twice by assign" {
    try expectOk(
        \\@f(x: i64) -> i64:
        \\    y = x
        \\    z = x
        \\    return z
        \\
        \\@main() -> i32:
        \\    v = call @f(7)
        \\    !v
        \\    return 0
    );
}

test "bfull: op-result temporary can be copied twice by assign" {
    try expectOk(
        \\@main() -> i32:
        \\    a = add 1, 2
        \\    b = a
        \\    c = a
        \\    !b
        \\    !c
        \\    return 0
    );
}

// VERIFIER-BFULL (G5): passing a scalar does not count as a move —
// `f(x); g(x)` is legal with the default by-value prefix; the same
// scalar stays usable across several by-value calls.
// NOTE: an explicit `^` move prefix on a scalar arg is NOT covered
// here — the call-site prefix must match the callee contract
// (callPrefixMatchesParam), so `^v` against a by-value param traps
// capability_mismatch. That is pre-existing intentional strictness,
// not a 1012 question.
test "bfull: scalar passed to two callees stays usable" {
    try expectOk(
        \\@f(x: i64) -> i64:
        \\    return x
        \\
        \\@g(x: i64) -> i64:
        \\    return x
        \\
        \\@main() -> i32:
        \\    v = call @f(7)
        \\    a = call @g(v)
        \\    b = call @f(v)
        \\    d = call @f(v)
        \\    !a
        \\    !b
        \\    !d
        \\    return 0
    );
}

// VERIFIER-BFULL (rule 5): explicit `!x` on a scalar stays a legal
// no-op and the scalar remains usable afterwards.
test "bfull: explicit release of a scalar is a no-op" {
    try expectOk(
        \\@f(x: i64) -> i64:
        \\    !x
        \\    y = add x, 1
        \\    return y
        \\
        \\@main() -> i32:
        \\    v = call @f(7)
        \\    !v
        \\    return 0
    );
}

// VERIFIER-BFULL (G6): a borrow view of a scalar origin owes nothing —
// it needs no explicit end at function exit.
test "bfull: borrow view of a scalar origin is not a leak" {
    try expectOk(
        \\@f(x: i64) -> i64:
        \\    v = &x
        \\    return 0
        \\
        \\@main() -> i32:
        \\    return 0
    );
}

// Negative control for G6: a borrow view of an OWNED value is still
// scanned — the exit scan on the view is the move-while-borrowed
// backstop and must never be silenced by the scalar exemption.
test "bfull: borrow view of an owned value still traps" {
    try expectTrap(
        \\@main() -> i32:
        \\    x = alloc 8
        \\    b = &x
        \\    return 0
    , trap.Trap.memory_leak);
}

// REQUIRED REGRESSION (task): a heap-owning parameter in a NON-LAST
// function that is never released must still trap 1012.
test "bfull: unreleased heap-owning param in non-last function still traps 1012" {
    try expectTrap(
        \\@take(h: blob_handle) -> i32:
        \\    return 0
        \\
        \\@main() -> i32:
        \\    return 0
    , trap.Trap.memory_leak);
}

test "bfull: released heap-owning param does not trap" {
    try expectOk(
        \\@take(h: blob_handle) -> i32:
        \\    !h
        \\    return 0
        \\
        \\@main() -> i32:
        \\    return 0
    );
}

// VERIFIER-BFULL (G7): a nominal wrapper type opts OUT of scalar status
// — an unreleased `Fd(i32)` parameter still traps 1012, in a param and
// in a return position alike.
test "bfull: unreleased nominal-wrapper param still traps 1012" {
    try expectTrap(
        \\@close_fd(fd: Fd(i32)) -> i32:
        \\    return 0
        \\
        \\@main() -> i32:
        \\    return 0
    , trap.Trap.memory_leak);
}

test "bfull: released nominal-wrapper param does not trap" {
    try expectOk(
        \\@close_fd(fd: Fd(i32)) -> i32:
        \\    !fd
        \\    return 0
        \\
        \\@main() -> i32:
        \\    return 0
    );
}

test "bfull: unreleased nominal-wrapper call result still traps 1012" {
    try expectTrap(
        \\@make_fd() -> Fd(i32):
        \\    return 3
        \\
        \\@main() -> i32:
        \\    v = call @make_fd()
        \\    return 0
    , trap.Trap.memory_leak);
}

// VERIFIER-BFULL (G8, locked-in current behaviour): a bare `ptr`
// parameter passed by value stays owning — its obligation is decided
// by its cap, not by the scalar rule.
test "bfull: unreleased by-value ptr param still traps 1012" {
    try expectTrap(
        \\@take_ptr(p: ptr) -> i32:
        \\    return 0
        \\
        \\@main() -> i32:
        \\    return 0
    , trap.Trap.memory_leak);
}

// VERIFIER-BFULL (scalar-move): a `take` of a scalar field yields a
// freely droppable value — the move-ownership read of a scalar carries
// no obligation, so no explicit `!` is needed (contrast 361_take_basic,
// which still releases its taken i64 explicitly).
test "bfull: take of a scalar field needs no explicit release" {
    try expectOk(
        \\@main() -> i32:
        \\    buf = alloc 8
        \\    v = take buf+0 as i64
        \\    !buf
        \\    return 0
    );
}

// VERIFIER-BFULL (scalar-move, no-regression): a `take` of a
// blob_handle stays owning — the scalar exemption must not swallow it.
test "bfull: take of a blob_handle still traps 1012" {
    try expectTrap(
        \\@main() -> i32:
        \\    buf = alloc 8
        \\    v = take buf+0 as blob_handle
        \\    !buf
        \\    return 0
    , trap.Trap.memory_leak);
}

// VERIFIER-BFULL (suggestion 3): a `load` of a blob_handle is owning —
// the load must not mark it an ephemeral scalar (7452 residual: armLoad
// used to set EphemeralScalar for every non-ptr load).
test "bfull: load of a blob_handle still traps 1012" {
    try expectTrap(
        \\@main() -> i32:
        \\    buf = alloc 8
        \\    v = load buf+0 as blob_handle
        \\    !buf
        \\    return 0
    , trap.Trap.memory_leak);
}

// VERIFIER-BFULL (suggestion 3, no-regression): an atomic_load of a
// scalar stays ephemeral — the type-driven flag must not make scalar
// atomics owning.
test "bfull: atomic_load of i32 needs no explicit release" {
    try expectOk(
        \\@main() -> i32:
        \\    lock = alloc 8
        \\    state = atomic_load lock+0 as i32 acquire
        \\    !lock
        \\    return 0
    );
}

// VERIFIER-BFULL (suggestion 5, 7452(e)): a compliant call into @sink
// still leaves the callee's exit obligation intact — @sink's borrow
// parameter p (origin is an owned value, so G6 does not exempt it)
// and its owning parameter q are both live at @sink's exit, so the
// exit scan must still trap 1012. The scalar/G6 exemptions must never
// silence this.
test "bfull: compliant sink call still leaves callee exit obligation (1012)" {
    try expectTrap(
        \\@sink(&p: ptr, ^q: ptr) -> i32:
        \\    return 0
        \\
        \\@main() -> i32:
        \\    value = alloc 8
        \\    result = call @sink(&value, ^value)
        \\    !result
        \\    return 0
    , trap.Trap.memory_leak);
}
