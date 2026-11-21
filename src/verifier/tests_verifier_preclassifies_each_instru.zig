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

const isDecl = @import("const_trap.zig").isDecl;
const metadataTrapKind = @import("collect_metadata.zig").metadataTrapKind;
const readTestClassifyLineCount = @import("reg_state_change.zig").readTestClassifyLineCount;
const readTestConsumedScanCount = @import("reg_state_change.zig").readTestConsumedScanCount;
const resetTestClassifyLineCount = @import("reg_state_change.zig").resetTestClassifyLineCount;
const resetTestConsumedScanCount = @import("reg_state_change.zig").resetTestConsumedScanCount;
const trapCode = @import("reg_state_change.zig").trapCode;
const verify = @import("free_annotated_slice.zig").verify;
const verifyWithOptions = @import("free_annotated_slice.zig").verifyWithOptions;

test "verifier preclassifies each instruction once" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .assign,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 0 },
                .{ .imm_i64 = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "x = 1",
        },
        .{
            .kind = .return_,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .reg = 0 },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "return x",
        },
    };

    resetTestClassifyLineCount();
    const verified = try verifyWithOptions(std.testing.allocator, program[0..], &.{}, .{ .jobs = 1 });
    defer switch (verified) {
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
        },
        .trap => {},
    };
    try std.testing.expect(verified == .ok);
    try std.testing.expectEqual(program.len, readTestClassifyLineCount());
}

test "metadata errors map to explicit trap kinds" {
    try std.testing.expectEqual(trap.Trap.unsupported_type, metadataTrapKind(error.UnsupportedType));
    try std.testing.expectEqual(trap.Trap.arena_oom, metadataTrapKind(error.OutOfMemory));
    try std.testing.expectEqual(trap.Trap.test_func_signature_mismatch, metadataTrapKind(error.TestFuncSignatureMismatch));
    try std.testing.expectEqual(trap.Trap.invalid_atomic_ordering, metadataTrapKind(error.InvalidAtomicOrdering));
    try std.testing.expectEqual(trap.Trap.forbidden_syntax, metadataTrapKind(error.InvalidFunctionSig));
    try std.testing.expectEqual(trap.Trap.forbidden_syntax, metadataTrapKind(error.InvalidAtomicSyntax));
    try std.testing.expectEqual(trap.Trap.import_resolution_failed, metadataTrapKind(error.InvalidJoinState));
}

test "metadata atomic ordering failure keeps atomic trap code" {
    const program = [_]inst.Instruction{
        inst.makeInstruction(.func_decl, 1, 0, null, "@main() -> i32:"),
        inst.makeInstruction(.alloc, 2, 1, null, "node = alloc 8"),
        inst.makeInstruction(.cmpxchg, 3, 2, null, "old, ok = cmpxchg node+0, 0, 1 acquire seq_cst"),
        inst.makeInstruction(.return_, 4, 3, null, "return 0"),
    };

    const verified = try verify(std.testing.allocator, &program, &.{});
    switch (verified) {
        .trap => |report| {
            try std.testing.expectEqual(trap.Trap.invalid_atomic_ordering, report.trap);
            try std.testing.expectEqual(trap.trapCode(.invalid_atomic_ordering), report.trap_code orelse return error.TestUnexpectedResult);
            try std.testing.expect(std.mem.containsAtLeast(u8, report.message, 1, "invalid atomic ordering"));
        },
        .ok => return error.TestUnexpectedResult,
    }
}

test "verifier precomputes consumed registers once per function body" {
    const source =
        \\@fail() -> i32!:
        \\return 1
        \\@main() -> i32!:
        \\res = call @fail()
        \\leak_a = alloc 8
        \\leak_b = alloc 16
        \\leak_c = alloc 24
        \\ok = ? res
        \\return ok
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    resetTestConsumedScanCount();
    const verified = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .jobs = 1 });
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.early_return_leak, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }

    var expected_scanned: usize = 0;
    for (flat.instructions) |item| {
        if (!isDecl(item.kind)) expected_scanned += 1;
    }
    try std.testing.expectEqual(expected_scanned, readTestConsumedScanCount());
}

test "panic terminates without forcing a leak trap" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .alloc,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 0 },
                .{ .imm_u64 = 8 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "x = alloc 8",
        },
        .{
            .kind = .panic,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .text = "7" },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "panic(7)",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "panic_msg is treated as a terminator" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .alloc,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 1 },
                .{ .imm_u64 = 3 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "buf = alloc 3",
        },
        .{
            .kind = .panic_msg,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .text = "7" },
                .{ .text = "buf" },
                .{ .text = "2" },
                .{ .none = {} },
            },
            .raw_text = "panic_msg(7, *buf, 2)",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "panic does not leak termination state into the next function" {
    const source =
        \\@first() -> i32:
        \\L_ENTRY:
        \\panic(7)
        \\@second() -> i32:
        \\L_ENTRY:
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
        .trap => |report| {
            std.debug.print("trap={s} msg={s} line={} source_line={} source={s}\n", .{
                @tagName(report.trap),
                report.message,
                report.line,
                report.source_line,
                report.source_text orelse "",
            });
            return error.TestUnexpectedResult;
        },
    }
}

test "function scope rebuilds correctly with consts across declarations" {
    const source =
        \\@const MSG = utf8:"ok\\n"
        \\@first() -> i32:
        \\L_ENTRY:
        \\return 1
        \\@second() -> i32:
        \\L_ENTRY:
        \\return 0
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("trap={s} msg={s} line={} source_line={} source={s}\n", .{
                @tagName(report.trap),
                report.message,
                report.line,
                report.source_line,
                report.source_text orelse "",
            });
            return error.TestUnexpectedResult;
        },
    }
}

test "branch conditions are consumed by control flow" {
    const source =
        \\@main() -> i32:
        \\L_ENTRY:
        \\cond = eq 1, 1
        \\br cond -> L_OK, L_ERR
        \\L_OK:
        \\return 0
        \\L_ERR:
        \\return 1
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("trap={s} msg={s} line={} source_line={} source={s}\n", .{
                @tagName(report.trap),
                report.message,
                report.line,
                report.source_line,
                report.source_text orelse "",
            });
            return error.TestUnexpectedResult;
        },
    }
}

test "default immutable mode rejects writing through an allocation without a borrow" {
    const source =
        \\@main() -> i32:
        \\box = alloc 4
        \\store box+0, 1 as i32
        \\!box
        \\return 0
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .default_immutable = true });
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.const_mutation, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "default immutable mode accepts the same program in the mutable mode" {
    const source =
        \\@main() -> i32:
        \\box = alloc 4
        \\store box+0, 1 as i32
        \\!box
        \\return 0
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("trap={s} msg={s}\n", .{ @tagName(report.trap), report.message });
            return error.TestUnexpectedResult;
        },
    }
}

test "default immutable mode grants write access through an exclusive borrow" {
    const source =
        \\@main() -> i32:
        \\box = alloc 4
        \\view = &mut box
        \\store view+0, 1 as i32
        \\value = load view+0 as i32
        \\!view
        \\!box
        \\!value
        \\return 0
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .default_immutable = true });
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("trap={s} msg={s} line={}\n", .{ @tagName(report.trap), report.message, report.source_line });
            return error.TestUnexpectedResult;
        },
    }
}

test "default immutable mode keeps the exclusive borrow exclusive" {
    const source =
        \\@main() -> i32:
        \\box = alloc 4
        \\view = &mut box
        \\store box+0, 1 as i32
        \\!view
        \\!box
        \\return 0
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .default_immutable = true });
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.borrow_conflict, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "default immutable mode still requires the allocation to be released" {
    const source =
        \\@main() -> i32:
        \\box = alloc 4
        \\return 0
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .default_immutable = true });
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.memory_leak, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "early return ignores immutable const data while checking for leaks" {
    const source =
        \\@const MSG = utf8:"ok\n"
        \\@fail() -> i32!:
        \\return 7
        \\@main() -> i32!:
        \\res = call @fail()
        \\value = ? res
        \\return value
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("trap={s} msg={s} line={} source_line={} source={s}\n", .{
                @tagName(report.trap),
                report.message,
                report.line,
                report.source_line,
                report.source_text orelse "",
            });
            return error.TestUnexpectedResult;
        },
    }
}

test "stack_alloc is exempt from memory leak and rejects escape" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .stack_alloc,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 1 },
                .{ .imm_u64 = 8 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "tmp = stack_alloc 8",
        },
        .{
            .kind = .return_,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .text = "0" },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "return 0",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}
