//! mutex / once / rwlock / mpsc / async helpers -- split from tests/std_smoke.zig (shared helpers: helpers.zig).
const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const repoRoot = helpers.repoRoot;
const readFileAlloc = helpers.readFileAlloc;
const writeSource = helpers.writeSource;
const runCommand = helpers.runCommand;
const runCommandWithEnvMap = helpers.runCommandWithEnvMap;
const runCommandAnyExit = helpers.runCommandAnyExit;
const NormalizedInstruction = helpers.NormalizedInstruction;
const normalizeInstruction = helpers.normalizeInstruction;
const expectFlattenEquivalent = helpers.expectFlattenEquivalent;
const dumpInstructionTexts = helpers.dumpInstructionTexts;
const flattenFixture = helpers.flattenFixture;

test "sa_std mutex helpers are concrete and verifiable" {
    const mutex_layout = try readFileAlloc(std.testing.allocator, "sa_std/sync/mutex.sal");
    defer std.testing.allocator.free(mutex_layout);
    try std.testing.expectEqualStrings(
        "#def Mutex_SIZE = 8\n#def Mutex_lock = +0\n#def Mutex_data = +8\n",
        mutex_layout,
    );

    const mutex_src = try readFileAlloc(std.testing.allocator, "sa_std/sync/mutex.sa");
    defer std.testing.allocator.free(mutex_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "@import \"../time.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "[MACRO] MUTEX_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "[MACRO] MUTEX_LOCK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "[MACRO] MUTEX_UNLOCK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "atomic_rmw_xchg lock+Mutex_lock, 1 as u64 seq_cst"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "atomic_store %lock_ptr+Mutex_lock, 0 as u64 release"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "@__mutex_lock_spin"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "call @sa_time_sleep_ns(backoff_ns)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mutex_src, 1, "next_backoff = shl backoff_ns, 1"));

    var mutex_flat = try flattenFixture(std.testing.allocator, "sa_std/sync/mutex.sa", mutex_src);
    defer mutex_flat.deinit(std.testing.allocator);
    try std.testing.expect(mutex_flat.instructions.len > 0);
    try std.testing.expectEqual(@as(usize, 8), mutex_flat.function_sigs.len);
}

test "sa_std once helpers are concrete and verifiable" {
    const once_layout = try readFileAlloc(std.testing.allocator, "sa_std/sync/once.sal");
    defer std.testing.allocator.free(once_layout);
    try std.testing.expectEqualStrings(
        "#def Once_SIZE = 16\n#def Once_state = +0\n#def Once_value = +8\n#def Once_STATE_UNINIT = 0\n#def Once_STATE_RUNNING = 1\n#def Once_STATE_READY = 2\n",
        once_layout,
    );

    const once_src = try readFileAlloc(std.testing.allocator, "sa_std/sync/once.sa");
    defer std.testing.allocator.free(once_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "@import \"../time.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_IS_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_TRY_CLAIM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_WAIT_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_PUBLISH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] ONCE_GET_OR_INIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] LAZY_LOCK_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] LAZY_LOCK_FORCE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] LAZY_LOCK_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] LAZY_LOCK_IS_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "[MACRO] LAZY_LOCK_INTO_INNER"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "atomic_load once+Once_state as u32 acquire"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "cmpxchg once+Once_state, Once_STATE_UNINIT, Once_STATE_RUNNING as u32 acq_rel acquire"));
    try std.testing.expect(std.mem.containsAtLeast(u8, once_src, 1, "atomic_store %once_reg+Once_state, Once_STATE_READY as u32 release"));

    var once_flat = try flattenFixture(std.testing.allocator, "sa_std/sync/once.sa", once_src);
    defer once_flat.deinit(std.testing.allocator);
    try std.testing.expect(once_flat.instructions.len > 0);
    try std.testing.expectEqual(@as(usize, 9), once_flat.function_sigs.len);
}

test "sa_std rwlock helpers are concrete and verifiable" {
    const rwlock_layout = try readFileAlloc(std.testing.allocator, "sa_std/sync/rwlock.sal");
    defer std.testing.allocator.free(rwlock_layout);
    try std.testing.expectEqualStrings(
        "#def RwLock_SIZE = 8\n#def RwLock_readers = +0\n#def RwLock_writing = +4\n",
        rwlock_layout,
    );

    const rwlock_src = try readFileAlloc(std.testing.allocator, "sa_std/sync/rwlock.sa");
    defer std.testing.allocator.free(rwlock_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, rwlock_src, 1, "[MACRO] RWLOCK_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rwlock_src, 1, "[MACRO] RWLOCK_TRY_READ"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rwlock_src, 1, "[MACRO] RWLOCK_TRY_WRITE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rwlock_src, 1, "[MACRO] RWLOCK_RELEASE_READ"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rwlock_src, 1, "[MACRO] RWLOCK_RELEASE_WRITE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rwlock_src, 1, "cmpxchg %lock_reg+RwLock_writing, 0, 1 as i32 acq_rel acquire"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rwlock_src, 1, "atomic_rmw_add %lock_reg+RwLock_readers, 1 as i32 acq_rel"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rwlock_src, 1, "@__rwlock_release_read"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rwlock_src, 1, "panic(1601)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rwlock_src, 1, "atomic_store %lock_reg+RwLock_writing, 0 as i32 release"));

    var rwlock_flat = try flattenFixture(std.testing.allocator, "sa_std/sync/rwlock.sa", rwlock_src);
    defer rwlock_flat.deinit(std.testing.allocator);
    try std.testing.expect(rwlock_flat.instructions.len > 0);
    try std.testing.expectEqual(@as(usize, 6), rwlock_flat.function_sigs.len);
}

test "sa_std mpsc helpers are concrete and verifiable" {
    const mpsc_layout = try readFileAlloc(std.testing.allocator, "sa_std/sync/mpsc.sal");
    defer std.testing.allocator.free(mpsc_layout);
    try std.testing.expectEqualStrings(
        "#def Mpsc_SIZE = 32\n#def Mpsc_cap = +0\n#def Mpsc_head = +8\n#def Mpsc_tail = +16\n#def Mpsc_data = +32\n\n#def Mpsc_SLOT_SIZE = 16\n#def Mpsc_SLOT_value = +0\n#def Mpsc_SLOT_ready = +8\n#def Mpsc_SLOT_EMPTY = 0\n#def Mpsc_SLOT_READY = 1\n",
        mpsc_layout,
    );

    const mpsc_src = try readFileAlloc(std.testing.allocator, "sa_std/sync/mpsc.sa");
    defer std.testing.allocator.free(mpsc_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "@import \"../core/mem.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "@import \"../num.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "@import \"../time.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_TRY_SEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_SEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_TRY_RECV"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "[MACRO] MPSC_RECV"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "@__mpsc_try_send"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "@__mpsc_try_recv"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "EXPAND NUM_U64_CHECKED_MUL __mpsc_data_ok_%out_chan"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "EXPAND NUM_U64_CHECKED_ADD __mpsc_total_ok_%out_chan"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "__mpsc_len_order_ok_%out_len = uge __mpsc_len_tail_%out_len, __mpsc_len_head_%out_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "tail_ok = uge tail, head"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mpsc_src, 1, "L_MPSC_TRY_RECV_CORRUPT:"));

    var mpsc_flat = try flattenFixture(std.testing.allocator, "sa_std/sync/mpsc.sa", mpsc_src);
    defer mpsc_flat.deinit(std.testing.allocator);
    try std.testing.expect(mpsc_flat.instructions.len > 0);
    try std.testing.expectEqual(@as(usize, 11), mpsc_flat.function_sigs.len);
}

test "sa_std async helpers are concrete and verifiable" {
    const async_src = try readFileAlloc(std.testing.allocator, "sa_std/libsa_async.sa");
    defer std.testing.allocator.free(async_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_CTX_DEF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_POLL_PROLOGUE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_AWAIT_POINT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_AWAIT_POINT_FINAL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_RETURN_PENDING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_READY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, async_src, 1, "[MACRO] ASYNC_INVALID_STATE"));

    var async_flat = try flattenFixture(std.testing.allocator, "sa_std/libsa_async.sa", async_src);
    defer async_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), async_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), async_flat.function_sigs.len);
}

test "libsa_async macro expansion stays equivalent to the manual state machine" {
    const macro_source = try readFileAlloc(std.testing.allocator, "demos/rosetta/09_async_await/main.sa");
    defer std.testing.allocator.free(macro_source);

    const print_iface_path = try sio.cwd().realpathAlloc(std.testing.allocator, "sa_std/io/print.sai");
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
        var macro_flat = try flattenFixture(
            std.testing.allocator,
            "demos/rosetta/09_async_await/main.sa",
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
