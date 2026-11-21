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

const FunctionRegScope = @import("reg_state_change.zig").FunctionRegScope;
const markInstructionConsumedRegs = @import("snapshot_merge_state_in_scope.zig").markInstructionConsumedRegs;
const verify = @import("free_annotated_slice.zig").verify;
const verifyBody = @import("verify_body.zig").verifyBody;
const verifyWithOptions = @import("free_annotated_slice.zig").verifyWithOptions;

// Negative control for the assume_safe propagation: assume_safe of an
// owned alloc must NOT inherit any exemption (alloc never sets the
// raw-pointer flag). Releasing the owner while the safe alias lives must
// still trap — and the trap must name s itself, proving s stays tracked
// (a move-then-release shape would leave the moved-to owner live and
// trap on that instead, proving nothing about s).
test "assume_safe of owned alloc still traps at exit" {
    const source =
        \\@ffi_wrapper wrap(*slot: ptr) -> i32:
        \\    x = alloc 8
        \\    s = assume_safe x
        \\    !x
        \\    return 0
        \\@main() -> i32:
        \\    return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| {
            try std.testing.expectEqual(trap.Trap.memory_leak, report.trap);
            try std.testing.expectEqualStrings("s", std.mem.sliceTo(&report.register_buf, 0));
        },
        .ok => return error.TestUnexpectedResult,
    }
}

test "exit leak in a non-last function still traps memory leak" {
    // HOST-VERIFIER-SCOPE: the exit-leak check used to examine only the
    // last function in the stream (end-of-verifyBody state, plus a
    // last-chunk-only gate on the parallel path), so a leak in an
    // earlier function was silently dropped. A leak in the FIRST of
    // two functions must trap even though the second exits clean.
    const source =
        \\@leaker() -> i32:
        \\leak_0 = alloc 8
        \\return 0
        \\@main() -> i32:
        \\box = alloc 4
        \\!box
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

test "exit leak in a middle function still traps memory leak" {
    // HOST-VERIFIER-SCOPE: same scope defect as the test above, with
    // the leak in the MIDDLE function — this pins the per-boundary
    // check rather than any first/last-only variant.
    const source =
        \\@first() -> i32:
        \\box = alloc 4
        \\!box
        \\return 0
        \\@leaker() -> i32:
        \\leak_0 = alloc 8
        \\return 0
        \\@main() -> i32:
        \\box2 = alloc 4
        \\!box2
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

test "call-site trap in caller beats exit leak in earlier-declared callee (serial)" {
    // TRAP-PRECEDENCE (regression for the trap_baseline golden
    // case demos/support/capability_mismatch.sa): @sink exits with
    // its borrow parameter p still live, but @sink's exit is only
    // reached through @main's call, and that call traps
    // CapabilityMismatch at the call site -- earlier in execution
    // order. Declaration order (@sink first) must not let the exit
    // leak pre-empt the call-site trap.
    const source =
        \\@sink(&p: ptr, ^q: ptr) -> i32:
        \\return 0
        \\@main() -> i32:
        \\value = alloc 8
        \\result = call @sink(^value, ^value)
        \\return result
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .jobs = 1 });
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.capability_mismatch, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "call-site trap in caller beats exit leak in earlier-declared callee (parallel)" {
    // TRAP-PRECEDENCE (regression for the trap_baseline golden
    // case demos/support/capability_mismatch.sa): @sink exits with
    // its borrow parameter p still live, but @sink's exit is only
    // reached through @main's call, and that call traps
    // CapabilityMismatch at the call site -- earlier in execution
    // order. Declaration order (@sink first) must not let the exit
    // leak pre-empt the call-site trap.
    const source =
        \\@sink(&p: ptr, ^q: ptr) -> i32:
        \\return 0
        \\@main() -> i32:
        \\value = alloc 8
        \\result = call @sink(^value, ^value)
        \\return result
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .jobs = 4 });
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.capability_mismatch, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "redefining live owned register still traps register redefinition" {
    // Negative control for the raw-pointer redefinition exemption: an owned
    // (non-raw-pointer, non-ephemeral) live register must still trap
    // .register_redefinition when reassigned.
    const source =
        \\@main() -> i32:
        \\leak_0 = alloc 8
        \\leak_0 = alloc 16
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.register_redefinition, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "predecoded metadata verifies basic instructions without raw text" {
    const symbol_names = [_][]const u8{ "main", "value" };
    const reg_ids = [_]u32{1};
    const fsig = sig.FunctionSig{
        .id = 0,
        .name = "main",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .i32,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .reg_ids = reg_ids[0..],
    };

    var decl = inst.makeInstruction(.func_decl, 1, 0, null, "");
    decl.operands[0] = .{ .symbol = 0 };
    decl.operands[1] = .{ .func = 0 };
    var assign = inst.makeInstruction(.assign, 2, 1, null, "");
    assign.operands[0] = .{ .reg = 1 };
    assign.operands[1] = .{ .imm_i64 = 7 };
    var ret = inst.makeInstruction(.return_, 3, 2, null, "");
    ret.operands[0] = .{ .reg = 1 };
    const instructions = [_]inst.Instruction{ decl, assign, ret };

    const verified = try verifyWithOptions(std.testing.allocator, instructions[0..], &.{}, .{
        .predecoded_symbol_names = symbol_names[0..],
        .predecoded_function_sigs = &.{fsig},
    });
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "predecoded structured call move args mark function consumed regs" {
    var symbols = symbol.SymbolTable.init(std.testing.allocator);
    defer symbols.deinit();

    _ = try symbols.intern("sa_vec_extend_from_slice");
    _ = try symbols.intern("padding");
    const dst_vec = try symbols.intern("dst_vec");

    const reg_ids = [_]u32{dst_vec};
    var scope = try FunctionRegScope.initBorrowed(std.testing.allocator, reg_ids[0..]);
    defer scope.deinit();

    var call_item = inst.makeInstruction(.call, 42, 1, null, "");
    call_item.operands[0] = .{ .reg = dst_vec };
    call_item.operands[1] = .{ .text = "@sa_vec_extend_from_slice(^dst_vec)" };

    var consumed = [_]bool{false};
    markInstructionConsumedRegs(std.testing.allocator, call_item, &symbols, &scope, consumed[0..]);

    try std.testing.expect(consumed[0]);
}

test "predecoded structured call supports move arg rebound to same destination" {
    const symbol_names = [_][]const u8{
        "sa_vec_extend_from_slice",
        "sa_vec_append",
        "dst_vec",
        "src_slice",
        "elem_size",
    };
    const params = [_]sig.ParamSpec{
        .{ .name = "dst_vec", .ty = .ptr, .cap = .move },
        .{ .name = "src_slice", .ty = .ptr, .cap = .borrow },
        .{ .name = "elem_size", .ty = .u64, .cap = .by_value },
    };
    const param_ids = [_]u32{ 2, 3, 4 };
    const reg_ids = [_]u32{ 2, 3, 4 };
    const callee_sig = sig.FunctionSig{
        .id = 0,
        .name = "sa_vec_extend_from_slice",
        .params = params[0..],
        .kind = .external,
        .return_cap = .move,
        .return_ty = .ptr,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .param_ids = param_ids[0..],
        .reg_ids = reg_ids[0..],
    };
    const caller_sig = sig.FunctionSig{
        .id = 1,
        .name = "sa_vec_append",
        .params = params[0..],
        .kind = .exported,
        .return_cap = .move,
        .return_ty = .ptr,
        .entry_inst_idx = 1,
        .is_ffi_wrapper = false,
        .param_ids = param_ids[0..],
        .reg_ids = reg_ids[0..],
    };

    var callee_decl = inst.makeInstruction(.extern_decl, 1, 0, null, "");
    callee_decl.operands[0] = .{ .symbol = 0 };
    callee_decl.operands[1] = .{ .func = 0 };
    var caller_decl = inst.makeInstruction(.export_decl, 2, 1, null, "");
    caller_decl.operands[0] = .{ .symbol = 1 };
    caller_decl.operands[1] = .{ .func = 1 };
    var call_item = inst.makeInstruction(.call, 3, 2, null, "");
    call_item.operands[0] = .{ .reg = 2 };
    call_item.operands[1] = .{ .text = "@sa_vec_extend_from_slice(^dst_vec, &src_slice, elem_size)" };
    var release_slice = inst.makeInstruction(.release, 4, 3, null, "");
    release_slice.operands[0] = .{ .reg = 3 };
    var release_elem_size = inst.makeInstruction(.release, 5, 4, null, "");
    release_elem_size.operands[0] = .{ .reg = 4 };
    var ret = inst.makeInstruction(.return_, 6, 5, null, "");
    ret.operands[0] = .{ .reg = 2 };

    const instructions = [_]inst.Instruction{ callee_decl, caller_decl, call_item, release_slice, release_elem_size, ret };
    const verified = try verifyWithOptions(std.testing.allocator, instructions[0..], &.{}, .{
        .jobs = 1,
        .predecoded_symbol_names = symbol_names[0..],
        .predecoded_function_sigs = &.{ callee_sig, caller_sig },
    });
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 6), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}
