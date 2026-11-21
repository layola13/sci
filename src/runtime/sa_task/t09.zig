const std = @import("std");
const builtin = @import("builtin");
const ERR_INVALID = @import("t01.zig").ERR_INVALID;
const ERR_INVALID_HANDLE = @import("t01.zig").ERR_INVALID_HANDLE;
const SA_TASK_NET_READ = @import("t07.zig").SA_TASK_NET_READ;
const SA_TASK_OK = @import("t01.zig").SA_TASK_OK;
const SA_TASK_TRAPPED = @import("t01.zig").SA_TASK_TRAPPED;
const SA_TASK_TRAP_CLOSE_OF_CLOSED = @import("t04.zig").SA_TASK_TRAP_CLOSE_OF_CLOSED;
const SA_TASK_TRAP_SEND_ON_CLOSED = @import("t01.zig").SA_TASK_TRAP_SEND_ON_CLOSED;
const SA_TASK_TRAP_WAITGROUP_NEGATIVE = @import("t01.zig").SA_TASK_TRAP_WAITGROUP_NEGATIVE;
const Slot = @import("t01.zig").Slot;
const c_readers_max = @import("t08.zig").c_readers_max;
const c_readers_now = @import("t08.zig").c_readers_now;
const c_rwlock_handle = @import("t08.zig").c_rwlock_handle;
const countingWorker = @import("t04.zig").countingWorker;
const monotonicNs = @import("t01.zig").monotonicNs;
const readerWorker = @import("t08.zig").readerWorker;
const recordingSink = @import("t04.zig").recordingSink;
const sa_chan_close = @import("t05.zig").sa_chan_close;
const sa_chan_destroy = @import("t05.zig").sa_chan_destroy;
const sa_chan_make = @import("t05.zig").sa_chan_make;
const sa_chan_recv = @import("t05.zig").sa_chan_recv;
const sa_chan_send = @import("t05.zig").sa_chan_send;
const sa_sync_destroy = @import("t08.zig").sa_sync_destroy;
const sa_sync_once_do = @import("t08.zig").sa_sync_once_do;
const sa_sync_once_new = @import("t08.zig").sa_sync_once_new;
const sa_sync_rwlock_lock = @import("t08.zig").sa_sync_rwlock_lock;
const sa_sync_rwlock_new = @import("t08.zig").sa_sync_rwlock_new;
const sa_sync_rwlock_rlock = @import("t08.zig").sa_sync_rwlock_rlock;
const sa_sync_rwlock_runlock = @import("t08.zig").sa_sync_rwlock_runlock;
const sa_sync_rwlock_unlock = @import("t08.zig").sa_sync_rwlock_unlock;
const sa_sync_waitgroup_add = @import("t08.zig").sa_sync_waitgroup_add;
const sa_sync_waitgroup_done = @import("t08.zig").sa_sync_waitgroup_done;
const sa_sync_waitgroup_new = @import("t08.zig").sa_sync_waitgroup_new;
const sa_sync_waitgroup_wait = @import("t08.zig").sa_sync_waitgroup_wait;
const sa_task_join = @import("t04.zig").sa_task_join;
const sa_task_live_count = @import("t04.zig").sa_task_live_count;
const sa_task_monitor = @import("t04.zig").sa_task_monitor;
const sa_task_net_wait = @import("t07.zig").sa_task_net_wait;
const sa_task_sleep_ms = @import("t04.zig").sa_task_sleep_ms;
const sa_task_spawn = @import("t03.zig").sa_task_spawn;
const sa_task_spawn_supervised = @import("t03.zig").sa_task_spawn_supervised;
const sa_task_trap_info = @import("t03.zig").sa_task_trap_info;
const sa_task_yield = @import("t04.zig").sa_task_yield;
const setPollHook = @import("t07.zig").setPollHook;
const setTrapSink = @import("t03.zig").setTrapSink;
const sink_seen_code = @import("t04.zig").sink_seen_code;
const supported = @import("t01.zig").supported;
const testing = @import("t04.zig").testing;

test "sa_task.test.sync: rwlock readers overlap, writer excludes" {
    if (!supported) return error.SkipZigTest;
    try testing.expectEqual(SA_TASK_OK, sa_sync_rwlock_new(&c_rwlock_handle));
    c_readers_now.store(0, .seq_cst);
    c_readers_max.store(0, .seq_cst);
    // Main holds a read lock; goroutine readers must still enter.
    try testing.expectEqual(SA_TASK_OK, sa_sync_rwlock_rlock(c_rwlock_handle));
    var hs: [3]u64 = undefined;
    for (&hs) |*h| try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&readerWorker, null, h));
    for (hs) |h| try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(SA_TASK_OK, sa_sync_rwlock_runlock(c_rwlock_handle));
    try testing.expect(c_readers_max.load(.seq_cst) >= 2);
    // Writer excludes readers.
    var entered: std.atomic.Value(bool) = .init(false);
    const ReaderFlag = struct {
        fn run(arg: ?*anyopaque) callconv(.c) void {
            const flag: *std.atomic.Value(bool) = @ptrCast(@alignCast(arg.?));
            _ = sa_sync_rwlock_rlock(c_rwlock_handle);
            flag.store(true, .release);
            _ = sa_sync_rwlock_runlock(c_rwlock_handle);
        }
    };
    try testing.expectEqual(SA_TASK_OK, sa_sync_rwlock_lock(c_rwlock_handle));
    var rh: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&ReaderFlag.run, &entered, &rh));
    _ = sa_task_sleep_ms(60);
    try testing.expect(!entered.load(.acquire));
    try testing.expectEqual(SA_TASK_OK, sa_sync_rwlock_unlock(c_rwlock_handle));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(rh));
    try testing.expect(entered.load(.acquire));
    try testing.expectEqual(SA_TASK_OK, sa_sync_destroy(c_rwlock_handle));
}

pub var c_wg_handle: u64 = 0;

pub var c_wg_mask: std.atomic.Value(u32) = .init(0);

pub fn wgWorker(arg: ?*anyopaque) callconv(.c) void {
    const bit: *u32 = @ptrCast(@alignCast(arg.?));
    _ = sa_task_sleep_ms(10);
    _ = c_wg_mask.fetchOr(@as(u32, 1) << @as(u5, @intCast(bit.*)), .seq_cst);
    _ = sa_sync_waitgroup_done(c_wg_handle);
}

test "sa_task.test.sync: waitgroup reaches zero" {
    if (!supported) return error.SkipZigTest;
    try testing.expectEqual(SA_TASK_OK, sa_sync_waitgroup_new(&c_wg_handle));
    c_wg_mask.store(0, .seq_cst);
    try testing.expectEqual(SA_TASK_OK, sa_sync_waitgroup_add(c_wg_handle, 16));
    var bits: [16]u32 = undefined;
    var hs: [16]u64 = undefined;
    for (0..16) |i| {
        bits[i] = @intCast(i);
        try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&wgWorker, &bits[i], &hs[i]));
    }
    try testing.expectEqual(SA_TASK_OK, sa_sync_waitgroup_wait(c_wg_handle));
    try testing.expectEqual(@as(u32, 0xFFFF), c_wg_mask.load(.seq_cst));
    // Already zero: wait returns immediately.
    try testing.expectEqual(SA_TASK_OK, sa_sync_waitgroup_wait(c_wg_handle));
    for (hs) |h| try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(SA_TASK_OK, sa_sync_destroy(c_wg_handle));
}

pub var c_sink_code: std.atomic.Value(i32) = .init(0);

pub fn cRecordingSink(_: u64, code: i32, _: [*]const u8, _: u64, _: ?*anyopaque) callconv(.c) void {
    c_sink_code.store(code, .seq_cst);
}

pub fn wgNegativeWorker(arg: ?*anyopaque) callconv(.c) void {
    setTrapSink(&cRecordingSink, null);
    const wg: *u64 = @ptrCast(@alignCast(arg.?));
    _ = sa_sync_waitgroup_done(wg.*); // counter 0 -> -1: boundary trap
}

test "sa_task.test.sync: waitgroup negative counter traps" {
    if (!supported) return error.SkipZigTest;
    var wg: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_sync_waitgroup_new(&wg));
    c_sink_code.store(0, .seq_cst);
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&wgNegativeWorker, &wg, &h));
    try testing.expectEqual(SA_TASK_TRAPPED, sa_task_join(h));
    try testing.expectEqual(SA_TASK_TRAP_WAITGROUP_NEGATIVE, c_sink_code.load(.seq_cst));
    try testing.expectEqual(SA_TASK_OK, sa_sync_destroy(wg));
}

pub var c_once_handle: u64 = 0;

pub var c_once_runs: std.atomic.Value(u64) = .init(0);

pub fn onceFn(_: ?*anyopaque) callconv(.c) void {
    _ = sa_task_sleep_ms(20);
    _ = c_once_runs.fetchAdd(1, .seq_cst);
}

pub fn onceWorker(_: ?*anyopaque) callconv(.c) void {
    _ = sa_sync_once_do(c_once_handle, &onceFn, null);
}

test "sa_task.test.sync: once runs exactly once" {
    if (!supported) return error.SkipZigTest;
    try testing.expectEqual(SA_TASK_OK, sa_sync_once_new(&c_once_handle));
    c_once_runs.store(0, .seq_cst);
    var hs: [16]u64 = undefined;
    for (&hs) |*h| try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&onceWorker, null, h));
    for (hs) |h| try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(@as(u64, 1), c_once_runs.load(.seq_cst));
    // After completion, calls return without running the fn.
    try testing.expectEqual(SA_TASK_OK, sa_sync_once_do(c_once_handle, &onceFn, null));
    try testing.expectEqual(@as(u64, 1), c_once_runs.load(.seq_cst));
    try testing.expectEqual(SA_TASK_OK, sa_sync_destroy(c_once_handle));
}

// Fake poller for the net tests: handle 4242 becomes readable
// 30 ms after installation; 9999 never becomes ready; anything
// else is an invalid handle (status 1), mirroring the real
// poller's rejection of unknown handles.
pub var c_fake_poll_start: i64 = 0;

pub fn fakePoll(handles: ?[*]const u64, interests: ?[*]const u32, count: u64, timeout_ms: i32, ready: ?[*]u32, out_ready_count: ?*u64) callconv(.c) i32 {
    _ = timeout_ms;
    const hs = handles orelse return ERR_INVALID;
    const ins = interests orelse return ERR_INVALID;
    const rd = ready orelse return ERR_INVALID;
    const oc = out_ready_count orelse return ERR_INVALID;
    oc.* = 0;
    const elapsed = monotonicNs() - c_fake_poll_start;
    for (0..@intCast(count)) |i| {
        rd[i] = 0;
        if (hs[i] == 4242) {
            if (elapsed >= 30 * std.time.ns_per_ms) {
                rd[i] = ins[i] & SA_TASK_NET_READ;
                if (rd[i] != 0) oc.* += 1;
            }
        } else if (hs[i] == 9999) {
            // never ready
        } else {
            return ERR_INVALID;
        }
    }
    return SA_TASK_OK;
}

pub const NetResult = struct {
    rc: i32 = -1,
    bits: u32 = 0,
    elapsed: i64 = 0,
};

pub fn netWaitWorker(arg: ?*anyopaque) callconv(.c) void {
    const res: *NetResult = @ptrCast(@alignCast(arg.?));
    var bits: u32 = 0;
    const t0 = monotonicNs();
    res.rc = sa_task_net_wait(4242, SA_TASK_NET_READ, 5 * std.time.ns_per_s, &bits);
    res.elapsed = monotonicNs() - t0;
    res.bits = bits;
}

pub fn netTimeoutWorker(arg: ?*anyopaque) callconv(.c) void {
    const res: *NetResult = @ptrCast(@alignCast(arg.?));
    var bits: u32 = 0;
    const t0 = monotonicNs();
    res.rc = sa_task_net_wait(9999, SA_TASK_NET_READ, 60 * std.time.ns_per_ms, &bits);
    res.elapsed = monotonicNs() - t0;
    res.bits = bits;
}

test "sa_task.test.net: park on poll readiness and timeout" {
    if (!supported) return error.SkipZigTest;
    setPollHook(&fakePoll);
    c_fake_poll_start = monotonicNs();
    var r1: NetResult = .{};
    var r2: NetResult = .{};
    var h1: u64 = 0;
    var h2: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&netWaitWorker, &r1, &h1));
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&netTimeoutWorker, &r2, &h2));
    // Invalid handles are rejected eagerly by the validation
    // poll, before any parking.
    var bits: u32 = 0;
    try testing.expectEqual(ERR_INVALID, sa_task_net_wait(13, SA_TASK_NET_READ, std.time.ns_per_s, &bits));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h1));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h2));
    try testing.expectEqual(SA_TASK_OK, r1.rc);
    try testing.expectEqual(SA_TASK_NET_READ, r1.bits);
    try testing.expectEqual(SA_TASK_OK, r2.rc);
    try testing.expectEqual(@as(u32, 0), r2.bits);
    try testing.expect(r2.elapsed >= 45 * std.time.ns_per_ms);
}

// ---------------------------------------------------------------------
// SLA goroutine syntax batch companion: supervised spawn, trap
// record readback, and exit monitors.
pub fn supervisedTrapWorker(_: ?*anyopaque) callconv(.c) void {
    var ch: u64 = 0;
    _ = sa_chan_make(0, &ch);
    _ = sa_chan_close(ch);
    _ = sa_chan_close(ch); // boundary trap: close of closed channel
}

pub fn supervisedSendClosedWorker(_: ?*anyopaque) callconv(.c) void {
    var ch: u64 = 0;
    _ = sa_chan_make(1, &ch);
    _ = sa_chan_close(ch);
    var v: Slot = .{ .a = 1 };
    _ = sa_chan_send(ch, &v); // boundary trap: send on closed channel
}

pub fn supervisedCleanWorker(arg: ?*anyopaque) callconv(.c) void {
    const p: *std.atomic.Value(u64) = @ptrCast(@alignCast(arg.?));
    _ = p.fetchAdd(1, .seq_cst);
}

test "sa_task.companion: supervised trap held until trap_info consumes" {
    if (!supported) return error.SkipZigTest;
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn_supervised(&supervisedTrapWorker, null, null, null, &h));
    try testing.expect(h != 0);
    try testing.expectEqual(SA_TASK_TRAPPED, sa_task_join(h));
    // Held: a repeated join reports the trap again.
    try testing.expectEqual(SA_TASK_TRAPPED, sa_task_join(h));
    var code: i32 = 0;
    var msg_ptr: ?*const u8 = null;
    var msg_len: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_trap_info(h, &code, &msg_ptr, &msg_len));
    try testing.expectEqual(SA_TASK_TRAP_CLOSE_OF_CLOSED, code);
    const msg: [*]const u8 = @ptrCast(msg_ptr.?);
    try testing.expectEqualStrings("close of closed channel", msg[0..@intCast(msg_len)]);
    // Consumed: the handle is invalid now.
    try testing.expectEqual(ERR_INVALID_HANDLE, sa_task_trap_info(h, &code, &msg_ptr, &msg_len));
    try testing.expectEqual(ERR_INVALID_HANDLE, sa_task_join(h));
}

test "sa_task.companion: supervised clean exit leaves no record" {
    if (!supported) return error.SkipZigTest;
    var counter: std.atomic.Value(u64) = .init(0);
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn_supervised(&supervisedCleanWorker, &counter, null, null, &h));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(@as(u64, 1), counter.load(.seq_cst));
    var code: i32 = 0;
    var msg_ptr: ?*const u8 = null;
    var msg_len: u64 = 0;
    try testing.expectEqual(ERR_INVALID_HANDLE, sa_task_trap_info(h, &code, &msg_ptr, &msg_len));
}

test "sa_task.companion: custom sink invoked at the boundary" {
    if (!supported) return error.SkipZigTest;
    sink_seen_code.store(0, .release);
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn_supervised(&supervisedTrapWorker, null, &recordingSink, null, &h));
    try testing.expectEqual(SA_TASK_TRAPPED, sa_task_join(h));
    try testing.expectEqual(SA_TASK_TRAP_CLOSE_OF_CLOSED, sink_seen_code.load(.acquire));
    var code: i32 = 0;
    var msg_ptr: ?*const u8 = null;
    var msg_len: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_trap_info(h, &code, &msg_ptr, &msg_len));
}

test "sa_task.companion: monitor delivers normal exit" {
    if (!supported) return error.SkipZigTest;
    var counter: std.atomic.Value(u64) = .init(0);
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&supervisedCleanWorker, &counter, &h));
    var mch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_monitor(h, &mch));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    var slot: Slot = .{};
    var closed: u32 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_recv(mch, &slot, &closed));
    try testing.expectEqual(h, slot.a);
    try testing.expectEqual(@as(u64, 0), slot.b);
    try testing.expectEqual(@as(u32, 0), closed);
    _ = sa_chan_destroy(mch);
}

test "sa_task.companion: monitor delivers trapped exit code" {
    if (!supported) return error.SkipZigTest;
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn_supervised(&supervisedSendClosedWorker, null, null, null, &h));
    var mch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_monitor(h, &mch));
    try testing.expectEqual(SA_TASK_TRAPPED, sa_task_join(h));
    var slot: Slot = .{};
    var closed: u32 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_recv(mch, &slot, &closed));
    try testing.expectEqual(h, slot.a);
    try testing.expectEqual(@as(u64, @intCast(SA_TASK_TRAP_SEND_ON_CLOSED)), slot.b);
    _ = sa_chan_destroy(mch);
    var code: i32 = 0;
    var msg_ptr: ?*const u8 = null;
    var msg_len: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_trap_info(h, &code, &msg_ptr, &msg_len));
    try testing.expectEqual(SA_TASK_TRAP_SEND_ON_CLOSED, code);
}

test "sa_task.companion: monitor after exit delivers immediately" {
    if (!supported) return error.SkipZigTest;
    var counter: std.atomic.Value(u64) = .init(0);
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&supervisedCleanWorker, &counter, &h));
    var spins: usize = 0;
    while (spins < 100000) : (spins += 1) {
        var n: u64 = 0;
        _ = sa_task_live_count(&n);
        if (n == 0) break;
        _ = sa_task_yield();
    }
    var mch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_monitor(h, &mch));
    var slot: Slot = .{};
    var closed: u32 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_recv(mch, &slot, &closed));
    try testing.expectEqual(h, slot.a);
    try testing.expectEqual(@as(u64, 0), slot.b);
    _ = sa_chan_destroy(mch);
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
}

test "sa_task.companion: monitor rejects invalid handle" {
    if (!supported) return error.SkipZigTest;
    var mch: u64 = 0;
    try testing.expectEqual(ERR_INVALID_HANDLE, sa_task_monitor(0xdeadbeef, &mch));
}

test "sa_task.companion: monitor on consumed trap handle is rejected" {
    if (!supported) return error.SkipZigTest;
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn_supervised(&supervisedTrapWorker, null, null, null, &h));
    try testing.expectEqual(SA_TASK_TRAPPED, sa_task_join(h));
    var code: i32 = 0;
    var msg_ptr: ?*const u8 = null;
    var msg_len: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_trap_info(h, &code, &msg_ptr, &msg_len));
    // The trap record is consumed: the handle is invalid even
    // while the two-phase slot reap is still pending. A monitor
    // subscription must be rejected with ERR_INVALID_HANDLE and
    // must not hand out a channel, so no exit message can be
    // delivered for the consumed record.
    var mch: u64 = 0;
    try testing.expectEqual(ERR_INVALID_HANDLE, sa_task_monitor(h, &mch));
    try testing.expectEqual(@as(u64, 0), mch);
}

test "sa_task.companion: monitor rejects consumed handle under recycle churn (DEF-TASK-MONITOR-REAP-RACE)" {
    if (!supported) return error.SkipZigTest;
    // Stress regression for DEF-TASK-MONITOR-REAP-RACE. The
    // single-shot test above only races when the suite's
    // ambient load happens to land the consumed slot's reap
    // inside monitor's lookup-to-lock window (it flipped in
    // roughly 1 of 5-9 full-suite runs). Here the same
    // spawn -> TRAPPED join -> trap_info consume -> monitor
    // sequence runs back-to-back: every iteration's reap
    // completes asynchronously on a carrier while the next
    // iterations recycle the same registry slots at high
    // generation counts, which is exactly the regime the race
    // needs (measured on the pre-fix tree: first anomaly within
    // a few hundred iterations, ~1-6% of iterations once slot
    // generations pass a few hundred). Every monitor call on a
    // consumed handle must return ERR_INVALID_HANDLE and hand
    // out no channel.
    var it: usize = 0;
    while (it < 3000) : (it += 1) {
        var h: u64 = 0;
        try testing.expectEqual(SA_TASK_OK, sa_task_spawn_supervised(&supervisedTrapWorker, null, null, null, &h));
        try testing.expectEqual(SA_TASK_TRAPPED, sa_task_join(h));
        var code: i32 = 0;
        var msg_ptr: ?*const u8 = null;
        var msg_len: u64 = 0;
        try testing.expectEqual(SA_TASK_OK, sa_task_trap_info(h, &code, &msg_ptr, &msg_len));
        var mch: u64 = 0;
        try testing.expectEqual(ERR_INVALID_HANDLE, sa_task_monitor(h, &mch));
        try testing.expectEqual(@as(u64, 0), mch);
    }
}

// ---------------------------------------------------------------------
// Entry validation test (DEF-SCI-HOST-JOIN-COMPLETED-SEGFAULT,
// re-adjudicated): a data address passed as a task entry must be
// rejected with ERR_INVALID at spawn time, never dispatched.
pub var data_entry_cell: u64 = 0;

test "sa_task.test.sched: spawn rejects a data address as entry" {
    if (!supported) return error.SkipZigTest;
    const data_entry: ?*const anyopaque = @ptrCast(&data_entry_cell);
    var h: u64 = 999;
    try testing.expectEqual(ERR_INVALID, sa_task_spawn(data_entry, null, &h));
    try testing.expectEqual(@as(u64, 0), h);
    try testing.expectEqual(ERR_INVALID, sa_task_spawn_supervised(data_entry, null, null, null, &h));
    try testing.expectEqual(@as(u64, 0), h);
    // Positive control: a real function entry is still accepted
    // and joins cleanly.
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&countingWorker, null, &h));
    try testing.expect(h != 0);
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
}
