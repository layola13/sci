const std = @import("std");
const saasm = @import("saasm");

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 1 << 20);
}

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn runCommandAnyExit(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

const NormalizedInstruction = struct {
    kind: saasm.common.instruction.InstKind,
    op_kind: ?saasm.common.instruction.OpKind,
    operands: [4]saasm.common.instruction.Operand,
    raw_text: []const u8,
    atomic_value_ty: ?u32,
    atomic_ordering: ?saasm.common.instruction.AtomicOrdering,
    atomic_second_ordering: ?saasm.common.instruction.AtomicOrdering,
    atomic_rmw_op: ?saasm.common.instruction.AtomicRmwOp,
    atomic_expected_text: ?[]const u8,
    atomic_new_text: ?[]const u8,
    native_reg_names: []const []const u8,
};

fn normalizeInstruction(inst: saasm.flattener.Instruction) NormalizedInstruction {
    return .{
        .kind = inst.kind,
        .op_kind = inst.op_kind,
        .operands = inst.operands,
        .raw_text = inst.raw_text,
        .atomic_value_ty = inst.atomic_value_ty,
        .atomic_ordering = inst.atomic_ordering,
        .atomic_second_ordering = inst.atomic_second_ordering,
        .atomic_rmw_op = inst.atomic_rmw_op,
        .atomic_expected_text = inst.atomic_expected_text,
        .atomic_new_text = inst.atomic_new_text,
        .native_reg_names = inst.native_reg_names,
    };
}

fn expectFlattenEquivalent(lhs: saasm.flattener.FlattenResult, rhs: saasm.flattener.FlattenResult) !void {
    try std.testing.expectEqual(lhs.instructions.len, rhs.instructions.len);
    try std.testing.expectEqual(lhs.function_sigs.len, rhs.function_sigs.len);
    try std.testing.expectEqual(lhs.const_decls.len, rhs.const_decls.len);
    try std.testing.expectEqual(lhs.loc_table.len, rhs.loc_table.len);
    for (lhs.instructions, rhs.instructions, 0..) |l, r, idx| {
        const ln = normalizeInstruction(l);
        const rn = normalizeInstruction(r);
        try std.testing.expectEqual(ln.kind, rn.kind);
        try std.testing.expectEqual(ln.op_kind, rn.op_kind);
        try std.testing.expectEqualDeep(ln.operands, rn.operands);
        try std.testing.expectEqualStrings(ln.raw_text, rn.raw_text);
        try std.testing.expectEqual(ln.atomic_value_ty, rn.atomic_value_ty);
        try std.testing.expectEqual(ln.atomic_ordering, rn.atomic_ordering);
        try std.testing.expectEqual(ln.atomic_second_ordering, rn.atomic_second_ordering);
        try std.testing.expectEqual(ln.atomic_rmw_op, rn.atomic_rmw_op);
        try std.testing.expectEqual(ln.atomic_expected_text, rn.atomic_expected_text);
        try std.testing.expectEqual(ln.atomic_new_text, rn.atomic_new_text);
        try std.testing.expectEqualDeep(ln.native_reg_names, rn.native_reg_names);
        _ = idx;
    }
}

fn dumpInstructionTexts(prefix: []const u8, flat: saasm.flattener.FlattenResult) void {
    std.debug.print("{s} ({d} instructions)\n", .{ prefix, flat.instructions.len });
    for (flat.instructions, 0..) |item, idx| {
        std.debug.print("  [{d}] {s}\n", .{ idx, item.raw_text });
    }
}

test "sa_std core primitives are concrete and verifiable" {
    const slice_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/slice.saasm-layout");
    defer std.testing.allocator.free(slice_layout);
    try std.testing.expectEqualStrings(
        "#def Slice_SIZE = 16\n#def Slice_ptr  = +0\n#def Slice_len  = +8\n",
        slice_layout,
    );

    const slice_src = try readFileAlloc(std.testing.allocator, "sa_std/core/slice.saasm");
    defer std.testing.allocator.free(slice_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_LEN"));

    var slice_flat = try saasm.flattener.flatten(std.testing.allocator, slice_src);
    defer slice_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.function_sigs.len);

    const mem_src = try readFileAlloc(std.testing.allocator, "sa_std/core/mem.saasm");
    defer std.testing.allocator.free(mem_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_copy"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_set"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "ptr_add"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "br done -> L_END, L_BODY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "stack_alloc 8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "store offset_slot+0, 0 as u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "store remaining_slot+0, count as u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "next_remaining = sub remaining, one"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, mem_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, mem_src, 1, "i = 0"));

    var mem_flat = try saasm.flattener.flatten(std.testing.allocator, mem_src);
    defer mem_flat.deinit(std.testing.allocator);
    const verified = try saasm.referee.verify(std.testing.allocator, mem_flat.instructions, mem_flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 2), owned.function_sigs.len);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("std smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std alloc helpers are concrete and verifiable" {
    const vec_layout = try readFileAlloc(std.testing.allocator, "sa_std/alloc/vec.saasm-layout");
    defer std.testing.allocator.free(vec_layout);
    try std.testing.expectEqualStrings(
        "#def Vec_SIZE = 24\n#def Vec_ptr  = +0\n#def Vec_cap  = +8\n#def Vec_len  = +16",
        vec_layout,
    );

    const vec_src = try readFileAlloc(std.testing.allocator, "sa_std/alloc/vec.saasm");
    defer std.testing.allocator.free(vec_src);
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "add 0, 0"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "假定"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, vec_src, 1, "示例"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "@export sa_vec_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "@export sa_vec_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "store vec+Vec_ptr, 0 as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "store vec+Vec_cap, 0 as u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "store vec+Vec_len, 0 as u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "load vec+Vec_ptr as ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "!inner_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, vec_src, 1, "!vec"));

    var vec_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/alloc/vec.saasm", vec_src);
    defer vec_flat.deinit(std.testing.allocator);
    const vec_verified = try saasm.referee.verify(std.testing.allocator, vec_flat.instructions, vec_flat.const_decls);
    switch (vec_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 2), owned.function_sigs.len);
        },
        .trap => |report| {
            std.debug.print("vec smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const string_src = try readFileAlloc(std.testing.allocator, "sa_std/alloc/string.saasm");
    defer std.testing.allocator.free(string_src);
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "假定"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, string_src, 1, "示例"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_src, 1, "[MACRO] STR_FROM_CONST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, string_src, 1, "EXPAND SLICE_NEW"));

    const string_fixture =
        \\@import "../../../sa_std/core/slice.saasm-layout"
        \\@import "../../../sa_std/core/slice.saasm"
        \\@import "../../../sa_std/alloc/string.saasm"
        \\
        \\@const WORD = utf8:"rust"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    word = alloc Slice_SIZE
        \\    EXPAND STR_FROM_CONST word, WORD, 4
        \\    EXPAND SLICE_GET_LEN len, word
        \\    ok = eq len, 4
        \\    !len
        \\    !word
        \\    br ok -> L_OK, L_ERR
        \\
        \\L_OK:
        \\    !ok
        \\    return 0
        \\
        \\L_ERR:
        \\    !ok
        \\    return 1
    ;
    var string_flat = try saasm.flattener.flattenFile(std.testing.allocator, "demos/rosetta/15_string_bytes/main.saasm", string_fixture);
    defer string_flat.deinit(std.testing.allocator);
    const string_verified = try saasm.referee.verify(std.testing.allocator, string_flat.instructions, string_flat.const_decls);
    switch (string_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 1), owned.function_sigs.len);
        },
        .trap => |report| {
            std.debug.print("string smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std time helpers are concrete and verifiable" {
    const time_layout = try readFileAlloc(std.testing.allocator, "sa_std/time.saasm-layout");
    defer std.testing.allocator.free(time_layout);
    try std.testing.expectEqualStrings(
        "#def Time_NS_PER_US = 1000\n#def Time_NS_PER_MS = 1000000\n#def Time_NS_PER_S  = 1000000000\n#def Time_MS_PER_S  = 1000\n#def TimeDate_SIZE = 32\n#def TimeDate_unix_ms = +0\n#def TimeDate_unix_ns = +8\n#def TimeDate_year = +16\n#def TimeDate_month = +18\n#def TimeDate_day = +19\n#def TimeDate_hour = +20\n#def TimeDate_minute = +21\n#def TimeDate_second = +22\n#def TimeDate_millisecond = +24\n",
        time_layout,
    );

    const time_iface = try readFileAlloc(std.testing.allocator, "sa_std/time.saasm-iface");
    defer std.testing.allocator.free(time_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_instant_ns"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_unix_ms"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_utc_now"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_sleep_ms"));

    const time_src = try readFileAlloc(std.testing.allocator, "sa_std/time.saasm");
    defer std.testing.allocator.free(time_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_NOW_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_NOW_UNIX_MS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_UTC_NOW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_SLEEP_MS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_FROM_MS"));

    var time_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/time.saasm", time_src);
    defer time_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 7), time_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 7), time_flat.function_sigs.len);
}

test "sa_std mutex helpers are concrete and verifiable" {
    const mutex_layout = try readFileAlloc(std.testing.allocator, "sa_std/sync/mutex.saasm-layout");
    defer std.testing.allocator.free(mutex_layout);
    try std.testing.expectEqualStrings(
        "#def Mutex_SIZE = 8\n#def Mutex_lock = +0\n#def Mutex_data = +8\n",
        mutex_layout,
    );

    const mutex_src = try readFileAlloc(std.testing.allocator, "sa_std/sync/mutex.saasm");
    defer std.testing.allocator.free(mutex_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "@import \"../time.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "[MACRO] MUTEX_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "[MACRO] MUTEX_LOCK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "[MACRO] MUTEX_UNLOCK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "atomic_rmw_xchg lock+Mutex_lock, 1 as u64 seq_cst"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "atomic_store %lock_ptr+Mutex_lock, 0 as u64 release"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "@__mutex_lock_spin"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "call @sa_time_sleep_ns(1)"));

    var mutex_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/sync/mutex.saasm", mutex_src);
    defer mutex_flat.deinit(std.testing.allocator);
    try std.testing.expect(mutex_flat.instructions.len > 0);
    try std.testing.expectEqual(@as(usize, 8), mutex_flat.function_sigs.len);
}

test "sa_std once helpers are concrete and verifiable" {
    const once_layout = try readFileAlloc(std.testing.allocator, "sa_std/sync/once.saasm-layout");
    defer std.testing.allocator.free(once_layout);
    try std.testing.expectEqualStrings(
        "#def Once_SIZE = 16\n#def Once_state = +0\n#def Once_value = +8\n#def Once_STATE_UNINIT = 0\n#def Once_STATE_RUNNING = 1\n#def Once_STATE_READY = 2\n",
        once_layout,
    );

    const once_src = try readFileAlloc(std.testing.allocator, "sa_std/sync/once.saasm");
    defer std.testing.allocator.free(once_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "@import \"../time.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_IS_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_TRY_CLAIM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_WAIT_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_PUBLISH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_GET_OR_INIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "atomic_load once+Once_state as u32 acquire"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "cmpxchg once+Once_state, Once_STATE_UNINIT, Once_STATE_RUNNING as u32 acq_rel acquire"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "atomic_store %once_reg+Once_state, Once_STATE_READY as u32 release"));

    var once_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/sync/once.saasm", once_src);
    defer once_flat.deinit(std.testing.allocator);
    try std.testing.expect(once_flat.instructions.len > 0);
    try std.testing.expectEqual(@as(usize, 9), once_flat.function_sigs.len);
}

test "sa_std async helpers are concrete and verifiable" {
    const async_src = try readFileAlloc(std.testing.allocator, "sa_std/libsa_async.saasm");
    defer std.testing.allocator.free(async_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_CTX_DEF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_POLL_PROLOGUE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_AWAIT_POINT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_AWAIT_POINT_FINAL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_RETURN_PENDING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_INVALID_STATE"));

    var async_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/libsa_async.saasm", async_src);
    defer async_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), async_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), async_flat.function_sigs.len);
}

test "libsa_async macro expansion stays equivalent to the manual state machine" {
    const macro_source = try readFileAlloc(std.testing.allocator, "demos/rosetta/09_async_await/main.saasm");
    defer std.testing.allocator.free(macro_source);

    const print_iface_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "sa_std/io/print.saasm-iface");
    defer std.testing.allocator.free(print_iface_path);

    const manual_source = try std.fmt.allocPrint(std.testing.allocator,
        \\@import "{s}"
        \\
        \\@const RESULT_OK = utf8:"2\n"
        \\@const RESULT_ERR = utf8:"error\n"
        \\
        \\#def Run_SIZE = 32
        \\#def Run_state = +0
        \\#def Run_stage = +4
        \\#def Run_status = +8
        \\#def Run_value = +16
        \\#def Run_resume = +24
        \\#def Run_PENDING = 0
        \\#def Run_READY = 1
        \\#def Run_INVALID = 102
        \\
        \\@poll_step(state: ptr) -> i32:
        \\L_ENTRY:
        \\    stage = load state+Run_stage as u32
        \\    ready = eq stage, 1
        \\    !stage
        \\    return ready
        \\
        \\@take_step(state: ptr) -> void:
        \\L_ENTRY:
        \\    store state+Run_value, 1 as i32
        \\    return
        \\
        \\@poll_run(state: ptr) -> i32:
        \\L_ENTRY:
        \\    state_id = load state+Run_state as u32
        \\    is_state0 = eq state_id, 0
        \\    br is_state0 -> L_STATE_0, L_STATE_1
        \\
        \\L_STATE_0:
        \\    store state+Run_stage, 1 as u32
        \\    store state+Run_state, 1 as u32
        \\    !state_id
        \\    !is_state0
        \\    return 0
        \\
        \\L_STATE_1:
        \\    !state_id
        \\    !is_state0
        \\    async_poll_status_1_Run_state = call @poll_step(state)
        \\    async_is_ready_1_Run_state = eq async_poll_status_1_Run_state, 1
        \\    br async_is_ready_1_Run_state -> L_ASYNC_AWAIT_READY_1_Run_state, L_ASYNC_AWAIT_PENDING_1_Run_state
        \\L_ASYNC_AWAIT_PENDING_1_Run_state:
        \\    store state+Run_state, 1 as u32
        \\    !async_poll_status_1_Run_state
        \\    !async_is_ready_1_Run_state
        \\    return 0
        \\L_ASYNC_AWAIT_READY_1_Run_state:
        \\    call @take_step(state)
        \\    async_result_1_Run_state = load state+Run_value as i32
        \\    async_next_state_1_Run_state = add 1, 1
        \\    store state+Run_state, async_next_state_1_Run_state as u32
        \\    !async_poll_status_1_Run_state
        \\    !async_is_ready_1_Run_state
        \\    !async_next_state_1_Run_state
        \\    next = add async_result_1_Run_state, 1
        \\    store state+Run_value, next as i32
        \\    store state+Run_stage, 2 as u32
        \\    !async_result_1_Run_state
        \\    !next
        \\    return 1
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    state = alloc Run_SIZE
        \\    store state+Run_state, 0 as u32
        \\    store state+Run_stage, 0 as u32
        \\    store state+Run_status, 0 as u32
        \\    store state+Run_value, 0 as i32
        \\    store state+Run_resume, 0 as u32
        \\
        \\    ready0 = call @poll_run(state)
        \\    ready1 = call @poll_run(state)
        \\    value = load state+Run_value as i32
        \\    ok_ready0 = eq ready0, 0
        \\    ok_ready1 = eq ready1, 1
        \\    ok_value = eq value, 2
        \\    ok0 = and ok_ready0, ok_ready1
        \\    ok = and ok0, ok_value
        \\
        \\    !ready0
        \\    !ready1
        \\    !value
        \\    !ok_ready0
        \\    !ok_ready1
        \\    !ok_value
        \\    !ok0
        \\    !state
        \\
        \\    br ok -> L_OK, L_ERR
        \\
        \\L_OK:
        \\    !ok
        \\    call @sa_print_bytes(&RESULT_OK, 2)
        \\    return 0
        \\
        \\L_ERR:
        \\    !ok
        \\    call @sa_print_bytes(&RESULT_ERR, 6)
        \\    return 1
    , .{print_iface_path});
    defer std.testing.allocator.free(manual_source);

    for (0..100) |_| {
        var macro_flat = try saasm.flattener.flattenFile(
            std.testing.allocator,
            "demos/rosetta/09_async_await/main.saasm",
            macro_source,
        );
        defer macro_flat.deinit(std.testing.allocator);
        var manual_flat = try saasm.flattener.flatten(std.testing.allocator, manual_source);
        defer manual_flat.deinit(std.testing.allocator);

        if (macro_flat.instructions.len != manual_flat.instructions.len) {
            dumpInstructionTexts("macro", macro_flat);
            dumpInstructionTexts("manual", manual_flat);
        }
        try expectFlattenEquivalent(macro_flat, manual_flat);

        const macro_verified = try saasm.referee.verify(std.testing.allocator, macro_flat.instructions, macro_flat.const_decls);
        switch (macro_verified) {
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(std.testing.allocator);
            },
            .trap => |report| {
                std.debug.print("macro async verifier trap: {s}\n", .{report.message});
                return error.TestUnexpectedResult;
            },
        }
        const manual_verified = try saasm.referee.verify(std.testing.allocator, manual_flat.instructions, manual_flat.const_decls);
        switch (manual_verified) {
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(std.testing.allocator);
            },
            .trap => |report| {
                std.debug.print("manual async verifier trap: {s}\n", .{report.message});
                return error.TestUnexpectedResult;
            },
        }
    }
}

test "sa_std io helpers are concrete and verifiable" {
    const io_iface = try readFileAlloc(std.testing.allocator, "sa_std/io.saasm-iface");
    defer std.testing.allocator.free(io_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_std_println"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_io_read_line"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_io_buffer_data"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "sa_io_buffer_free"));

    const io_src = try readFileAlloc(std.testing.allocator, "sa_std/io.saasm");
    defer std.testing.allocator.free(io_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "@import \"fmt.saasm-iface\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] PRINTLN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] READ_LINE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] FORMAT_INT"));

    var io_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/io.saasm", io_src);
    defer io_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 24), io_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 24), io_flat.function_sigs.len);
}

test "sa_std hashmap helpers are concrete and verifiable" {
    const hashmap_layout = try readFileAlloc(std.testing.allocator, "sa_std/hashmap.saasm-layout");
    defer std.testing.allocator.free(hashmap_layout);
    try std.testing.expectEqualStrings(
        "#def HashMap_SIZE = 32\n#def HashMap_slots = +0\n#def HashMap_cap = +8\n#def HashMap_len = +16\n#def HashMap_tombs = +24\n\n#def HashMapSlot_SIZE = 32\n#def HashMapSlot_hash = +0\n#def HashMapSlot_key = +8\n#def HashMapSlot_value = +16\n#def HashMapSlot_state = +24\n\n#def HashMap_INITIAL_CAP = 8\n#def HashMap_STATE_EMPTY = 0\n#def HashMap_STATE_FILLED = 1\n#def HashMap_STATE_TOMB = 2\n\n#def HashMap_FNV_OFFSET = -3750763034362895579\n#def HashMap_FNV_PRIME = 1099511628211\n",
        hashmap_layout,
    );

    const collections_hashmap = try readFileAlloc(std.testing.allocator, "sa_std/collections/hashmap.saasm");
    defer std.testing.allocator.free(collections_hashmap);
    try std.testing.expect(std.mem.containsAtLeast(u8, collections_hashmap, 1, "@import \"../hashmap.saasm\""));

    const hashmap_src = try readFileAlloc(std.testing.allocator, "sa_std/hashmap.saasm");
    defer std.testing.allocator.free(hashmap_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"core/mem.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@import \"hashmap.saasm-layout\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_put"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "@export sa_map_del"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_PUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_DEL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hashmap_src, 1, "[MACRO] MAP_FREE"));

    var hashmap_error_ctx = saasm.flattener.ErrorContext{};
    var hashmap_flat = saasm.flattener.flattenFileWithContext(std.testing.allocator, "sa_std/hashmap.saasm", hashmap_src, &hashmap_error_ctx) catch |err| {
        const source_line = saasm.flattener.takeErrorSourceLine(&hashmap_error_ctx) orelse 0;
        std.debug.print("hashmap flatten failed on line {d}: {s}\n", .{ source_line, @errorName(err) });
        return err;
    };
    defer hashmap_flat.deinit(std.testing.allocator);
    try std.testing.expect(hashmap_flat.instructions.len > 0);
    try std.testing.expect(hashmap_flat.function_sigs.len >= 9);

    const hashmap_verified = try saasm.referee.verify(std.testing.allocator, hashmap_flat.instructions, hashmap_flat.const_decls);
    switch (hashmap_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.function_sigs.len >= 9);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print(
                "hashmap smoke verifier trap: {s} (line={d}, source_line={d}, function={s}, text={s}, register={s}, expected={s}, actual={s})\n",
                .{
                    report.message,
                    report.line,
                    report.source_line,
                    std.mem.sliceTo(&report.function_buf, 0),
                    std.mem.sliceTo(&report.source_text_buf, 0),
                    if (report.register) |r| r else std.mem.sliceTo(&report.register_buf, 0),
                    if (report.expected_mask_name) |r| r else "",
                    if (report.actual_mask_name) |r| r else "",
                },
            );
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std sort helpers are concrete and verifiable" {
    const sort_src = try readFileAlloc(std.testing.allocator, "sa_std/sort.saasm");
    defer std.testing.allocator.free(sort_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@import \"core/mem.saasm\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "[MACRO] QSORT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_swap_bytes"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_partition_bounds"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_qsort_bounds"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sort_src, 1, "@sort_qsort_len"));

    var sort_flat = try saasm.flattener.flattenFile(std.testing.allocator, "sa_std/sort.saasm", sort_src);
    defer sort_flat.deinit(std.testing.allocator);
    try std.testing.expect(sort_flat.instructions.len > 0);
    try std.testing.expect(sort_flat.function_sigs.len >= 4);
}

test "std smoke fixture runs through the current compiler surface" {
    const fixture = try readFileAlloc(std.testing.allocator, "tests/std_smoke.saasm");
    defer std.testing.allocator.free(fixture);
    try std.testing.expect(std.mem.containsAtLeast(u8, fixture, 1, "ptr_add"));

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "std_smoke.saasm", fixture);

    const run_argv = [_][]const u8{ "saasm", "run", "std_smoke.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 209), run_code);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "std_smoke.saasm", "-o", "std_smoke.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("std_smoke.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "call ptr @malloc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "call void @free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "load i8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "store i8"));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{ "./std_smoke.out" });
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 209), code),
        else => return error.TestUnexpectedResult,
    }
}
