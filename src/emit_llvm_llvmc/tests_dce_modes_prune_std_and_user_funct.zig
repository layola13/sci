const std = @import("std");
const call = @import("../referee/call.zig");
const referee = @import("../referee.zig");
const emit_options = @import("../emit_options.zig");
const flattener = @import("../flattener.zig");
const inst = @import("../common/instruction.zig");
const atomic = @import("../common/atomic.zig");
const sig = @import("../common/signature.zig");
const const_decl = @import("../common/const_decl.zig");
const upstream = @import("../common/upstream_loc.zig");
const sio = @import("sio");

const BuildState = @import("sa_llvmc_free.zig").BuildState;
const COp = @import("sa_llvmc_free.zig").COp;
const COperandKind = @import("sa_llvmc_free.zig").COperandKind;
const IndirectSlotCandidate = @import("atomic_rmw_op.zig").IndirectSlotCandidate;
const SharedEmitTables = @import("atomic_rmw_op.zig").SharedEmitTables;
const assignOperand = @import("assign_operand.zig").assignOperand;
const chooseIndirectSigIndex = @import("atomic_rmw_op.zig").chooseIndirectSigIndex;
const conversionOp = @import("atomic_rmw_op.zig").conversionOp;
const lowerInstruction = @import("assign_operand.zig").lowerInstruction;
const sa_llvmc_free = @import("sa_llvmc_free.zig").sa_llvmc_free;
const sa_llvmc_make_minimal_module_bitcode = @import("sa_llvmc_free.zig").sa_llvmc_make_minimal_module_bitcode;
const shouldPruneUnreachableFunction = @import("atomic_rmw_op.zig").shouldPruneUnreachableFunction;

test "dce modes prune std and user functions at distinct levels" {
    const std_func = sig.FunctionSig{
        .id = 0,
        .name = "std_unused",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .void,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .upstream_file = "/tmp/app/sa_std/core/unused.sa",
    };
    const user_func = sig.FunctionSig{
        .id = 1,
        .name = "user_unused",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .void,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .upstream_file = "/tmp/app/src/user.sa",
    };

    const source_path = "/tmp/app/src/main.sa";
    try std.testing.expect(shouldPruneUnreachableFunction(.{ .dce = .std, .std_root = "/tmp/app/sa_std" }, std_func, source_path));
    try std.testing.expect(!shouldPruneUnreachableFunction(.{ .dce = .std, .std_root = "/tmp/app/sa_std" }, user_func, source_path));
    try std.testing.expect(shouldPruneUnreachableFunction(.{ .dce = .full, .std_root = "/tmp/app/sa_std" }, user_func, source_path));
    try std.testing.expect(!shouldPruneUnreachableFunction(.{ .dce = .no, .std_root = "/tmp/app/sa_std" }, std_func, source_path));
}

test "assignOperand resolves localized const vtable slots without raw text" {
    var symbols = flattener.SymbolTable.init(std.testing.allocator);
    defer symbols.deinit();
    const const_id = try symbols.intern("SLA_THREAD_VT_0");

    var anon_string_names = std.StringHashMap([*:0]const u8).init(std.testing.allocator);
    defer anon_string_names.deinit();
    var function_sig_index = std.StringHashMap(usize).init(std.testing.allocator);
    defer function_sig_index.deinit();

    const reg_ids = [_]u32{const_id};
    const fsig = sig.FunctionSig{
        .id = 0,
        .name = "wrap",
        .params = &.{},
        .kind = .ffi_wrapper,
        .return_cap = null,
        .return_ty = .void,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = true,
        .reg_ids = reg_ids[0..],
    };

    var shared_tables = SharedEmitTables{
        .const_names = std.StringHashMap(void).init(std.testing.allocator),
        .emitted_pos_by_sig = &.{},
        .indirect_by_slot = std.StringHashMap(?usize).init(std.testing.allocator),
        .indirect_slot_candidates = std.StringHashMap([]const IndirectSlotCandidate).init(std.testing.allocator),
        .indirect_by_offset = &.{},
    };
    defer shared_tables.const_names.deinit();
    defer shared_tables.indirect_by_slot.deinit();
    defer shared_tables.indirect_slot_candidates.deinit();
    try shared_tables.const_names.put("SLA_THREAD_VT_0", {});
    var state = BuildState{
        .allocator = std.testing.allocator,
        .symbols = &symbols,
        .fsig = fsig,
        .reg_operands_are_global_ids = false,
        .const_names = &shared_tables.const_names,
        .anon_string_names = &anon_string_names,
        .function_sigs = &.{},
        .function_sig_index = &function_sig_index,
        .shared = &shared_tables,
    };

    var item = inst.makeInstruction(.borrow, 1, 0, null, "");
    item.operands[0] = .{ .reg = 1 };
    item.operands[1] = .{ .reg = 0 };

    const got = try assignOperand(&state, item);
    defer if (got.name) |name| std.testing.allocator.free(std.mem.span(name));
    try std.testing.expectEqual(COperandKind.const_ptr, got.kind);
    try std.testing.expect(got.name != null);
    try std.testing.expectEqualStrings("SLA_THREAD_VT_0", std.mem.sliceTo(got.name.?, 0));
}

test "chooseIndirectSigIndex merges by sig index after DCE pruning" {
    // Regression for the latent index bug fixed in 737a27f: indirect-call
    // merging used to receive EMITTED positions (from buildEmittedSigIndex)
    // and index function_sigs with them. Emitted position == sig index only
    // while nothing is pruned; once DCE drops a function the positions shift
    // and the merge compares the wrong pair of signatures.
    //
    // Layout: sig 0 is pruned by DCE, so sig 1 (callee_a) lands at emitted
    // position 0 and sig 2 (callee_b) at emitted position 1. A vtable slot
    // merging callee_a (void) with callee_b (i32) must come back ambiguous
    // (null): the two shapes differ. The old code compared function_sigs[0]
    // (the pruned void fn) with function_sigs[1] (callee_a, also void) and
    // wrongly merged them to 0.
    const sigs = [_]sig.FunctionSig{
        .{ .id = 0, .name = "pruned_fn", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
        .{ .id = 1, .name = "callee_a", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
        .{ .id = 2, .name = "callee_b", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .i32, .entry_inst_idx = 0, .is_ffi_wrapper = false },
        .{ .id = 3, .name = "callee_c", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
    };

    // Regression: void vs i32 shapes must not merge.
    try std.testing.expectEqual(@as(?usize, null), chooseIndirectSigIndex(sigs[0..], 1, 2));
    // Same-shape control: callee_a and callee_c are both void() -- merge keeps the first.
    try std.testing.expectEqual(@as(?usize, 1), chooseIndirectSigIndex(sigs[0..], 1, 3));
    // Identity control.
    try std.testing.expectEqual(@as(?usize, 2), chooseIndirectSigIndex(sigs[0..], 2, 2));
}

test "llvmc backend can construct and write bitcode in memory" {
    var out_bytes: ?[*]u8 = null;
    var out_len: usize = 0;
    var err_msg: ?[*:0]u8 = null;
    try std.testing.expectEqual(@as(i32, 0), sa_llvmc_make_minimal_module_bitcode(&out_bytes, &out_len, &err_msg));
    defer if (err_msg) |msg| sa_llvmc_free(msg);
    defer if (out_bytes) |ptr| sa_llvmc_free(ptr);
    try std.testing.expect(out_bytes != null);
    try std.testing.expect(out_len > 0);
}

test "DEF-12: bitcast lowers to the bitcast op, true conversions stay assign" {
    // Regression for the float<->int bitcast defect: the conversion
    // branch of lowerInstruction used to send EVERY conversion op
    // (bitcast included) to `.assign`, whose shim-side numeric
    // `coerce` then numerically converted float<->int bitcasts
    // (bitcast 1.5 as u64 compiled to 1). conversionOp is the exact
    // predicate lowerInstruction uses; the end-to-end behavior is
    // pinned by demos/rosetta/410_bitcast_f64_u64_roundtrip and the
    // DEF-12 SA probe set.
    try std.testing.expectEqual(COp.bitcast, conversionOp(.bitcast));
    try std.testing.expectEqual(COp.assign, conversionOp(.fptosi));
    try std.testing.expectEqual(COp.assign, conversionOp(.sitofp));
    try std.testing.expectEqual(COp.assign, conversionOp(.uitofp));
    try std.testing.expectEqual(COp.assign, conversionOp(.fpext));
    try std.testing.expectEqual(COp.assign, conversionOp(.fptrunc));
    try std.testing.expectEqual(COp.assign, conversionOp(.trunc));
    try std.testing.expectEqual(COp.assign, conversionOp(.zext));
    try std.testing.expectEqual(COp.assign, conversionOp(.sext));
}
