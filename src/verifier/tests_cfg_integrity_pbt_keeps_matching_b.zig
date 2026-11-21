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

const appendRandomLocBlock = @import("reg_state_change.zig").appendRandomLocBlock;
const expectOptionalUpstreamLoc = @import("reg_state_change.zig").expectOptionalUpstreamLoc;
const expectTrapReportUpstreamLoc = @import("reg_state_change.zig").expectTrapReportUpstreamLoc;
const regFlagRawPointer = @import("reg_state_change.zig").regFlagRawPointer;
const trapCode = @import("reg_state_change.zig").trapCode;
const verify = @import("free_annotated_slice.zig").verify;

test "cfg integrity PBT keeps matching branch states and traps on mismatched joins" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6252);
    const random = prng.random();

    for (0..48) |_| {
        const left_consume = random.boolean();
        const right_consume = random.boolean();
        const expect_conflict = left_consume != right_consume;
        const left_text = if (left_consume) "    !victim\n" else "";
        const right_text = if (right_consume) "    !victim\n" else "";
        const join_text = if (!left_consume and !right_consume) "    !victim\n" else "";
        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\@main() -> i32:
            \\victim = alloc 8
            \\cond = eq 1, 1
            \\br cond -> L_LEFT, L_RIGHT
            \\L_LEFT:
            \\{s}    jmp L_JOIN
            \\L_RIGHT:
            \\{s}    jmp L_JOIN
            \\L_JOIN:
            \\{s}    !cond
            \\    return 0
        , .{ left_text, right_text, join_text });
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
        if (expect_conflict) {
            switch (verified) {
                .trap => |report| {
                    try std.testing.expectEqual(trap.Trap.phi_state_conflict, report.trap);
                    try std.testing.expect(std.mem.containsAtLeast(u8, report.message, 1, "incoming control-flow states do not agree"));
                },
                .ok => return error.TestUnexpectedResult,
            }
        } else {
            switch (verified) {
                .ok => |ok| {
                    var owned = ok;
                    defer owned.deinit(std.testing.allocator);
                    try std.testing.expect(owned.annotated.len > 0);
                },
                .trap => |report| {
                    std.debug.print("unexpected trap {s}: {s}\n", .{ @tagName(report.trap), report.message });
                    return error.TestUnexpectedResult;
                },
            }
        }
    }
}

test "phi join AND PBT keeps borrow-view branches compatible and traps consumed mismatches" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6253);
    const random = prng.random();

    for (0..48) |_| {
        const case_id = random.intRangeLessThan(u8, 0, 3);
        const right_text = switch (case_id) {
            0 => "    view = alloc 8\n",
            1 => "    view = & MSG\n",
            else => "    view = alloc 8\n    !view\n",
        };
        const expect_conflict = case_id == 2;
        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\@const MSG = utf8:"ok\n"
            \\@main() -> i32:
            \\cond = eq 1, 1
            \\br cond -> L_LEFT, L_RIGHT
            \\L_LEFT:
            \\    view = alloc 8
            \\    jmp L_JOIN
            \\L_RIGHT:
            \\{s}    jmp L_JOIN
            \\L_JOIN:
            \\    !view
            \\    !cond
            \\    return 0
        , .{right_text});
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
        if (expect_conflict) {
            switch (verified) {
                .trap => |report| try std.testing.expectEqual(trap.Trap.phi_state_conflict, report.trap),
                .ok => return error.TestUnexpectedResult,
            }
        } else {
            switch (verified) {
                .ok => |ok| {
                    var owned = ok;
                    defer owned.deinit(std.testing.allocator);
                    try std.testing.expect(owned.annotated.len > 0);
                },
                .trap => |report| {
                    std.debug.print("unexpected trap {s}: {s}\n", .{ @tagName(report.trap), report.message });
                    return error.TestUnexpectedResult;
                },
            }
        }
    }
}

test "unknown register PBT traps on random undeclared op operands" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6251);
    const random = prng.random();

    for (0..48) |iter| {
        var name_buf: [32]u8 = undefined;
        const ghost_name = try std.fmt.bufPrint(&name_buf, "ghost_{d}", .{random.int(u32)});
        const unknown_first = (iter & 1) == 0;

        const source = if (unknown_first) blk: {
            break :blk try std.fmt.allocPrint(std.testing.allocator,
                \\@main() -> i32:
                \\value = add {s}, 1
                \\return value
            , .{ghost_name});
        } else blk: {
            break :blk try std.fmt.allocPrint(std.testing.allocator,
                \\@main() -> i32:
                \\value = add 1, {s}
                \\return value
            , .{ghost_name});
        };
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
        switch (verified) {
            .trap => |report| {
                try std.testing.expectEqual(trap.Trap.unknown_register, report.trap);
                try std.testing.expectEqual(trap.trapCode(.unknown_register), report.trap_code orelse return error.TestUnexpectedResult);
                try std.testing.expect(report.register == null);
                try std.testing.expect(std.mem.startsWith(u8, report.register_buf[0..], ghost_name));
            },
            .ok => return error.TestUnexpectedResult,
        }
    }
}

test "#loc PBT keeps trap upstream locations aligned with loc table entries" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6254);
    const random = prng.random();

    for (0..48) |iter| {
        const ghost_name = try std.fmt.allocPrint(std.testing.allocator, "ghost_{d}", .{iter});
        defer std.testing.allocator.free(ghost_name);

        var source: std.Io.Writer.Allocating = .init(std.testing.allocator);
        errdefer source.deinit();
        const writer = &source.writer;

        var expected_main_loc: ?upstream.UpstreamLoc = null;
        var expected_alloc_loc: ?upstream.UpstreamLoc = null;
        var expected_error_loc: ?upstream.UpstreamLoc = null;
        var expected_return_loc: ?upstream.UpstreamLoc = null;

        try appendRandomLocBlock(writer, random, &expected_main_loc, 0);
        try writer.writeAll("@main() -> i32:\n");
        try appendRandomLocBlock(writer, random, &expected_alloc_loc, 0);
        try writer.writeAll("value = alloc 8\n");
        try appendRandomLocBlock(writer, random, &expected_error_loc, 1);
        if ((iter & 1) == 0) {
            try writer.print("result = add {s}, 1\n", .{ghost_name});
        } else {
            try writer.print("result = add 1, {s}\n", .{ghost_name});
        }
        try appendRandomLocBlock(writer, random, &expected_return_loc, 0);
        try writer.writeAll("return result\n");

        const source_text = try source.toOwnedSlice();
        defer std.testing.allocator.free(source_text);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source_text);
        defer flat.deinit(std.testing.allocator);

        const expected_alloc_effective_loc = expected_alloc_loc orelse expected_main_loc;

        try std.testing.expectEqual(@as(usize, 4), flat.instructions.len);
        try std.testing.expectEqual(flat.instructions.len, flat.loc_table.len);
        try expectOptionalUpstreamLoc(flat.instructions[0].upstream_loc, expected_main_loc);
        try expectOptionalUpstreamLoc(flat.loc_table[0], null);
        try expectOptionalUpstreamLoc(flat.instructions[1].upstream_loc, expected_alloc_effective_loc);
        try expectOptionalUpstreamLoc(flat.loc_table[1], expected_alloc_effective_loc);
        try expectOptionalUpstreamLoc(flat.loc_table[2], expected_error_loc);
        try expectOptionalUpstreamLoc(flat.instructions[3].upstream_loc, expected_return_loc);
        try expectOptionalUpstreamLoc(flat.loc_table[3], expected_return_loc);

        const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
        switch (verified) {
            .trap => |report| {
                try std.testing.expectEqual(trap.Trap.unknown_register, report.trap);
                try std.testing.expectEqual(trap.trapCode(.unknown_register), report.trap_code orelse return error.TestUnexpectedResult);
                try expectTrapReportUpstreamLoc(report, expected_error_loc);
                try std.testing.expect(std.mem.startsWith(u8, report.register_buf[0..], ghost_name));
            },
            .ok => return error.TestUnexpectedResult,
        }
    }
}

test "interior ptr PBT traps on use after releasing parent borrow" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6260);
    const random = prng.random();

    for (0..32) |_| {
        const offset: u64 = random.intRangeAtMost(u64, 0, 32);
        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\@main() -> i32:
            \\base = alloc 64
            \\view = & base
            \\ip = take view+{d}
            \\!view
            \\value = load ip+0 as u8
            \\return value
        , .{offset});
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.use_after_move, report.trap),
            .ok => return error.TestUnexpectedResult,
        }
    }
}

test "interior ptr PBT traps on ffi escape" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6261);
    const random = prng.random();

    for (0..32) |_| {
        const offset: u64 = random.intRangeAtMost(u64, 0, 32);
        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\@extern sink(*p: ptr) -> i32
            \\@ffi_wrapper wrap(*raw: ptr) -> i32:
            \\safe = assume_safe raw
            \\view = & safe
            \\ip = take view+{d}
            \\value = call @sink(*ip)
            \\return value
            \\@main() -> i32:
            \\base = alloc 64
            \\return 0
        , .{offset});
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.interior_ptr_escape, report.trap),
            .ok => return error.TestUnexpectedResult,
        }
    }
}

test "ffi airlock isolation PBT rejects unsafe ops outside ffi wrapper" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6262);
    const random = prng.random();

    for (0..48) |_| {
        const case_id = random.intRangeLessThan(u8, 0, 3);
        const source = switch (case_id) {
            0 => try std.fmt.allocPrint(std.testing.allocator,
                \\@main() -> i32:
                \\node = alloc 8
                \\raw = *node
                \\return 0
            , .{}),
            1 => try std.fmt.allocPrint(std.testing.allocator,
                \\@extern grab() -> *ptr
                \\@main() -> i32:
                \\raw = call @grab()
                \\safe = assume_safe raw
                \\return 0
            , .{}),
            else => try std.fmt.allocPrint(std.testing.allocator,
                \\@extern grab() -> *ptr
                \\@main() -> i32:
                \\raw = call @grab()
                \\view = assume_borrow raw
                \\return 0
            , .{}),
        };
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.illegal_unsafe_context, report.trap),
            .ok => return error.TestUnexpectedResult,
        }
    }
}

test "ffi wrapper allows raw params in branch control flow" {
    const source =
        \\@ffi_wrapper branch(*flag: i32) -> i32:
        \\br flag -> L_TRUE, L_FALSE
        \\L_TRUE:
        \\return 1
        \\L_FALSE:
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 6), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "raw pointer load temp live at exit is not a memory leak" {
    // A `load` whose type is .ptr is flagged regFlagRawPointer. Raw pointers
    // carry no ownership (release is a no-op for them), so a live raw-pointer
    // temp at function exit must not trap -- same as an ephemeral scalar.
    // This is the verifier side of the SAB/SA-text parity fix for
    // PhiStateConflict on ptr phi joins: the flag must be assignable without
    // forcing the compiler to emit a release for every compiler-generated
    // ptr temp.
    const source =
        \\@main() -> i32:
        \\data = stack_alloc 8
        \\tmp = load data+0 as ptr
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
        },
        .trap => |report| {
            std.debug.print("unexpected trap: {s}\n", .{@tagName(report.trap)});
            return error.TestUnexpectedResult;
        },
    }
}

test "raw pointer release is a no-op: no false PhiStateConflict at diamond merge" {
    // Releasing a plain raw pointer (`!tp` where tp was loaded `as ptr`)
    // must not mark the register Consumed: raw pointers carry no ownership.
    // Pre-fix, `!tp` marked tp Consumed, so at L_M the path via L_B
    // (tp=Consumed) clashed with the path via L_A (tp=Active after
    // redefinition), producing a false PhiStateConflict. Post-fix both
    // paths carry tp=Active and the join succeeds.
    // This test FAILS on the pre-fix verifier (trap PhiStateConflict).
    const source =
        \\@main() -> i32:
        \\data = stack_alloc 8
        \\i = stack_alloc 8
        \\n = 2
        \\tmp0 = 0
        \\store i+0, tmp0 as u64
        \\!tmp0
        \\tp = load data+0 as ptr
        \\!tp
        \\tmp1 = load i+0 as u64
        \\tmp2 = ult tmp1, n
        \\!tmp1
        \\br tmp2 -> L_A, L_B
        \\L_A:
        \\!tmp2
        \\tp = load data+0 as ptr
        \\jmp L_M
        \\L_B:
        \\!tmp2
        \\jmp L_M
        \\L_M:
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
        },
        .trap => |report| {
            std.debug.print("unexpected trap: {s}\n", .{@tagName(report.trap)});
            return error.TestUnexpectedResult;
        },
    }
}

test "ephemeral scalar release is a no-op: no false PhiStateConflict at diamond merge" {
    // Same shape as the raw-pointer test, but for an ephemeral scalar
    // (`tmp0 = 0`, an immediate assignment). Pre-fix, `!tmp0` marked it
    // Consumed and the L_M join of Active (L_A, redefined) vs Consumed
    // (L_B) trapped with a false PhiStateConflict. Post-fix both paths
    // stay Active.
    // This test FAILS on the pre-fix verifier (trap PhiStateConflict).
    const source =
        \\@main() -> i32:
        \\data = stack_alloc 8
        \\i = stack_alloc 8
        \\n = 2
        \\tmp0 = 0
        \\store i+0, tmp0 as u64
        \\!tmp0
        \\tmp1 = load i+0 as u64
        \\tmp2 = ult tmp1, n
        \\!tmp1
        \\br tmp2 -> L_A, L_B
        \\L_A:
        \\!tmp2
        \\tmp0 = 5
        \\jmp L_M
        \\L_B:
        \\!tmp2
        \\jmp L_M
        \\L_M:
        \\!tmp0
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
        },
        .trap => |report| {
            std.debug.print("unexpected trap: {s}\n", .{@tagName(report.trap)});
            return error.TestUnexpectedResult;
        },
    }
}

test "owned alloc live at exit still traps memory leak" {
    // Negative control for the raw-pointer leak exemption: a genuinely owned
    // value (heap alloc, not a raw pointer) left live at function exit must
    // still trap .memory_leak.
    const source =
        \\@main() -> i32:
        \\leak_0 = alloc 8
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.memory_leak, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

// Regression (LINE-DB-VERIFIER-EXITLIVE): a borrow view of @const data
// left live at function exit is not a leak — the db concurrent-bench
// shape (worker_vt = &QUERY_WORKER_VT in @ffi_wrapper spawn_query_worker)
// was rejected with error[MemoryLeak] by the exit scan, although a
// borrow of a const global owns nothing and its referent can never be
// retired while borrowed.
test "borrow of const data left live at exit is not a leak" {
    const source =
        \\@const VT = vtable { call = @worker }
        \\@worker(*slot: ptr) -> i32:
        \\    return 0
        \\@main() -> i32:
        \\    vt = &VT
        \\    f = load vt+0 as ptr
        \\    return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| {
            std.debug.print("unexpected trap: {s}\n", .{@tagName(report.trap)});
            return error.TestUnexpectedResult;
        },
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
        },
    }
}

// Negative control for the const-borrow exit exemption: moving an owned
// value while a borrow of it is live must still trap — the move path does
// not check borrow locks, so the exit scan on the borrow view is the
// backstop that catches move-while-borrowed, and the exemption must never
// silence it (the view's origin here is an owned alloc, not const data).
test "move-while-borrowed still traps at exit" {
    const source =
        \\@main() -> i32:
        \\    x = alloc 8
        \\    b = &x
        \\    y = x
        \\    return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.memory_leak, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

// Negative control for the const-borrow exit exemption: an owned alloc
// with a live borrow of it must still trap .memory_leak — the exemption
// applies to the borrow view only when its origin is const data, never
// to the owned referent itself.
test "owned alloc with live borrow still traps memory leak" {
    const source =
        \\@main() -> i32:
        \\    x = alloc 8
        \\    b = &x
        \\    return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.memory_leak, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

// Regression (LINE-DB-VERIFIER-EXITLIVE): assume_safe must propagate the
// raw-pointer flag from its input, like .assign does. The db bench shape
// loads a function pointer from a @const vtable (f = load vt+0 as ptr,
// flagged regFlagRawPointer) and reinterprets it (s = assume_safe f);
// without propagation s is a plain Active register and the exit scan
// rejects it, even though it owns nothing.
test "assume_safe of const-loaded raw pointer is not a leak" {
    const source =
        \\@const VT = vtable { call = @worker }
        \\@extern pthread_spawn(*entry: ptr, *arg: ptr) -> i32
        \\@worker(*slot: ptr) -> i32:
        \\    return 0
        \\@ffi_wrapper spawn(*slot: ptr) -> i32:
        \\    vt = &VT
        \\    f = load vt+0 as ptr
        \\    s = assume_safe f
        \\    h = call @pthread_spawn(*s, *slot)
        \\    !slot
        \\    return h
        \\@main() -> i32:
        \\    return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| {
            std.debug.print("unexpected trap: {s} on {s}\n", .{ @tagName(report.trap), report.register_buf[0..] });
            return error.TestUnexpectedResult;
        },
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
        },
    }
}
