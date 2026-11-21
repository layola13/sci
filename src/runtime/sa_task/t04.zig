const std = @import("std");
const builtin = @import("builtin");
const ERR_INVALID = @import("t01.zig").ERR_INVALID;
const ERR_INVALID_HANDLE = @import("t01.zig").ERR_INVALID_HANDLE;
const ERR_NOMEM = @import("t01.zig").ERR_NOMEM;
const ERR_UNSUPPORTED = @import("t01.zig").ERR_UNSUPPORTED;
const GUARD_KIB = @import("t01.zig").GUARD_KIB;
const Goroutine = @import("t01.zig").Goroutine;
const MonitorSub = @import("t01.zig").MonitorSub;
const Mutex = @import("t01.zig").Mutex;
const OsWaiter = @import("t01.zig").OsWaiter;
const SA_TASK_OK = @import("t01.zig").SA_TASK_OK;
const SA_TASK_TRAPPED = @import("t01.zig").SA_TASK_TRAPPED;
const SA_TASK_TRAP_INTERNAL = @import("t01.zig").SA_TASK_TRAP_INTERNAL;
const Slot = @import("t01.zig").Slot;
const WaitNode = @import("t01.zig").WaitNode;
const alloc = @import("t01.zig").alloc;
const cfg_stack_initial = @import("t01.zig").cfg_stack_initial;
const deliverMonitor = @import("t03.zig").deliverMonitor;
const ensureInit = @import("t03.zig").ensureInit;
const guardLookup = @import("t01.zig").guardLookup;
const guard_table = @import("t01.zig").guard_table;
const linux = @import("t01.zig").linux;
const monotonicNs = @import("t01.zig").monotonicNs;
const noteProgress = @import("t01.zig").noteProgress;
const parkBegin = @import("t02.zig").parkBegin;
const parkBeginLocked = @import("t02.zig").parkBeginLocked;
const parkCancel = @import("t02.zig").parkCancel;
const parkSwitch = @import("t02.zig").parkSwitch;
const raiseTrap = @import("t03.zig").raiseTrap;
const reapIfReadyLocked = @import("t01.zig").reapIfReadyLocked;
const registryLookup = @import("t01.zig").registryLookup;
const registryRecycle = @import("t01.zig").registryRecycle;
const sa_chan_destroy = @import("t05.zig").sa_chan_destroy;
const sa_chan_make = @import("t05.zig").sa_chan_make;
const sa_task_spawn = @import("t03.zig").sa_task_spawn;
const setTrapSink = @import("t03.zig").setTrapSink;
const stackEntryLookup = @import("t01.zig").stackEntryLookup;
const stack_grow_events = @import("t01.zig").stack_grow_events;
const supported = @import("t01.zig").supported;
const switchToCarrier = @import("t02.zig").switchToCarrier;
const systemQuiescent = @import("t03.zig").systemQuiescent;
const timerAdd = @import("t02.zig").timerAdd;
const t02 = @import("t02.zig");
const t01 = @import("t01.zig");

/// Register an exit monitor (companion): creates a dedicated
/// capacity-1 channel and subscribes it to the watched
/// goroutine's exit. Exactly one message is delivered, at the
/// exit convergence point after the trap record is final and
/// before join waiters fire: slot.a = watched handle, slot.b =
/// trap code (0 for a normal exit). Subscribing to an
/// already-exited (but not yet consumed) goroutine delivers
/// immediately. The subscriber owns the channel and destroys
/// it. Subscribing with an invalid or already-consumed handle
/// reports ERR_INVALID_HANDLE.
pub export fn sa_task_monitor(handle: u64, out_chan: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_chan orelse return ERR_INVALID;
    out.* = 0;
    if (!ensureInit()) return ERR_UNSUPPORTED;
    const g = registryLookup(handle) orelse return ERR_INVALID_HANDLE;
    var chan_h: u64 = 0;
    const rc = sa_chan_make(1, &chan_h);
    if (rc != SA_TASK_OK) return rc;
    const sub = alloc.create(MonitorSub) catch {
        _ = sa_chan_destroy(chan_h);
        return ERR_NOMEM;
    };
    sub.* = .{ .chan_handle = chan_h };
    t02.sched_mu.lock();
    // Re-validate the handle INSIDE the critical section
    // (DEF-TASK-MONITOR-REAP-RACE): registryLookup above only
    // proves the slot held this generation at lookup time. The
    // slot's two-phase reap can complete and the slot be
    // recycled for a new spawn between the lookup and this
    // lock; the new owner's registryAlloc resets the record
    // (state back to .runnable), so without re-validation the
    // .done branch below — or worse, the live-subscription
    // branch — acted on the WRONG goroutine: a consumed handle
    // was answered with a fresh channel and the successor's
    // exit was delivered (or armed to be delivered) to the
    // stale subscriber. The generation + state re-check under
    // sched_mu closes the window: a reap that already landed
    // shows .empty, a recycled slot shows the bumped gen.
    if (g.gen != @as(u32, @truncate(handle >> 32)) or g.state.load(.acquire) == .empty) {
        t02.sched_mu.unlock();
        _ = sa_chan_destroy(chan_h);
        alloc.destroy(sub);
        return ERR_INVALID_HANDLE;
    }
    if (g.state.load(.acquire) == .done) {
        // A trap record already consumed by sa_task_trap_info
        // leaves the handle invalid even while the two-phase
        // slot reap is still pending: subscribing must report
        // ERR_INVALID_HANDLE (the contract above), not resurrect
        // the exit as a fresh delivery. Roll back the channel
        // and subscription allocated for this call.
        if (g.trap_consumed) {
            t02.sched_mu.unlock();
            _ = sa_chan_destroy(chan_h);
            alloc.destroy(sub);
            return ERR_INVALID_HANDLE;
        }
        t02.sched_mu.unlock();
        deliverMonitor(sub, handle, g.trapped, g.trap_code);
        alloc.destroy(sub);
    } else {
        sub.next = g.monitors;
        g.monitors = sub;
        t02.sched_mu.unlock();
    }
    out.* = chan_h;
    return SA_TASK_OK;
}

pub export fn sa_task_yield() i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const g = t02.current_g orelse {
        std.Thread.yield() catch {};
        return SA_TASK_OK;
    };
    t02.sched_mu.lock();
    g.transition = true;
    g.yield_requeue = true;
    g.state.store(.runnable, .release);
    t02.sched_mu.unlock();
    switchToCarrier(g);
    return SA_TASK_OK;
}

pub export fn sa_task_sleep_ns(ns: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    if (ns == 0) return sa_task_yield();
    if (t02.current_g) |g| {
        g.park_gen += 1;
        g.wait_kind = .sleep;
        const deadline = monotonicNs() + @as(i64, @intCast(@min(ns, @as(u64, @intCast(std.math.maxInt(i64))))));
        parkBegin();
        if (!timerAdd(deadline, .{ .g = g }, g.park_gen)) {
            parkCancel();
            return ERR_NOMEM;
        }
        parkSwitch();
        g.wait_kind = .none;
        return g.wake_status;
    }
    var ts: linux.timespec = .{
        .sec = @intCast(@divTrunc(ns, std.time.ns_per_s)),
        .nsec = @intCast(@mod(ns, std.time.ns_per_s)),
    };
    var rem: linux.timespec = undefined;
    while (true) {
        const rc = linux.nanosleep(&ts, &rem);
        if (linux.errno(rc) != .INTR) break;
        ts = rem;
    }
    return SA_TASK_OK;
}

pub export fn sa_task_sleep_ms(ms: u64) i32 {
    return sa_task_sleep_ns(ms * std.time.ns_per_ms);
}

/// Finish a join that observed a status: recycle the record,
/// EXCEPT for a trapped supervised goroutine, whose record is
/// held for sa_task_trap_info (join keeps returning
/// SA_TASK_TRAPPED until the info call consumes it).
pub fn joinFinish(g: *Goroutine, gen: u32, status: i32) i32 {
    // The trap-record decision is taken under sched_mu, the same
    // critical section sa_task_trap_info consumes in and
    // goroutineExit publishes .done in
    // (DEF-TASK-MONITOR-REAP-RACE): a bare-field read here raced
    // a concurrent trap_info consume, and a bare-field write of
    // trap_held raced goroutineExit's monitor delivery.
    t02.sched_mu.lock();
    // A trap record already consumed by sa_task_trap_info leaves
    // the handle invalid: report that instead of replaying the
    // trap (or a clean status read from the not-yet-reaped
    // record). The consuming call already requested the reap.
    if (g.trap_consumed) {
        t02.sched_mu.unlock();
        return ERR_INVALID_HANDLE;
    }
    if (status == SA_TASK_TRAPPED and g.trap_sink != null) {
        g.trap_held = true;
        t02.sched_mu.unlock();
        return status;
    }
    t02.sched_mu.unlock();
    registryRecycle(g, gen);
    return status;
}

pub export fn sa_task_join(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    if (!ensureInit()) return ERR_UNSUPPORTED;
    const g = registryLookup(handle) orelse return ERR_INVALID_HANDLE;
    if (t02.current_g == g) return ERR_INVALID;
    // A detached handle is dead by declaration (DEF-R1): joining
    // it is an invalid-handle use, exactly like joining a handle
    // whose record a previous join already consumed.
    if (g.detached) return ERR_INVALID_HANDLE;
    // The exit-fact read (state + trapped) is taken under
    // sched_mu (DEF-TASK-MONITOR-REAP-RACE): goroutineExit
    // publishes .done and snapshots the monitor list in that
    // same critical section, so a status read outside it can
    // catch the window where .done is visible but the trap
    // record is not final yet and report a trapped exit as a
    // clean SA_TASK_OK. joinFinish re-checks the consumed flag
    // under the same lock before acting on the status.
    t02.sched_mu.lock();
    if (g.state.load(.acquire) == .done) {
        const status: i32 = if (g.trapped) SA_TASK_TRAPPED else SA_TASK_OK;
        t02.sched_mu.unlock();
        return joinFinish(g, g.gen, status);
    }
    t02.sched_mu.unlock();
    const node = alloc.create(WaitNode) catch return ERR_NOMEM;
    node.* = .{};
    var os_waiter: OsWaiter = .{};
    if (t02.current_g) |me| {
        node.g = me;
        me.wait_kind = .join;
    } else {
        node.os = &os_waiter;
    }
    const target_gen = g.gen;
    t02.sched_mu.lock();
    if (g.state.load(.acquire) == .done) {
        t02.sched_mu.unlock();
        alloc.destroy(node);
        const status: i32 = if (g.trapped) SA_TASK_TRAPPED else SA_TASK_OK;
        return joinFinish(g, target_gen, status);
    }
    node.next = g.join_waiters;
    g.join_waiters = node;
    // Mark parked while still holding sched_mu: goroutineExit
    // snapshots the waiter list under the same lock, so its fire
    // either precedes registration (impossible: it would have
    // seen the done state above) or observes state == parked.
    if (t02.current_g) |me| parkBeginLocked(me);
    t02.sched_mu.unlock();
    if (t02.current_g) |me| {
        parkSwitch();
        me.wait_kind = .none;
        const status = me.wake_status;
        return joinFinish(g, target_gen, status);
    }
    os_waiter.wait();
    const status = os_waiter.status;
    return joinFinish(g, target_gen, status);
}

/// Declare a spawn handle dead: the spawner will never join,
/// read trap info, or otherwise use it (DEF-R1; the SLA bare
/// `go` statement form). The completion record is then reaped
/// by the runtime itself once the goroutine exits and its exit
/// handoff completes, instead of being retained as an unjoined
/// zombie record forever. Monitor subscriptions registered
/// before the detach still fire at exit. Joining or reading
/// trap info through a detached handle reports
/// ERR_INVALID_HANDLE; detaching an unknown or consumed handle
/// does the same. Detach is idempotent while the record lives.
pub export fn sa_task_detach(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const g = registryLookup(handle) orelse return ERR_INVALID_HANDLE;
    t01.registry_mu.lock();
    defer t01.registry_mu.unlock();
    if (g.gen != @as(u32, @truncate(handle >> 32))) return ERR_INVALID_HANDLE;
    if (g.state.load(.acquire) == .empty) return ERR_INVALID_HANDLE;
    g.detached = true;
    reapIfReadyLocked(g);
    return SA_TASK_OK;
}

pub export fn sa_task_current(out_handle: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_handle orelse return ERR_INVALID;
    out.* = if (t02.current_g) |g| g.handle() else 0;
    return SA_TASK_OK;
}

pub export fn sa_task_live_count(out_count: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_count orelse return ERR_INVALID;
    out.* = @intCast(t02.live_count.load(.acquire));
    return SA_TASK_OK;
}

pub export fn sa_task_deadlock_guard_arm() i32 {
    if (!supported) return ERR_UNSUPPORTED;
    t02.deadlock_armed.store(true, .release);
    noteProgress();
    return SA_TASK_OK;
}

// ---------------------------------------------------------------------
// Phase A tests.
pub const testing = std.testing;

pub var test_counter: std.atomic.Value(u64) = .init(0);

pub fn countingWorker(_: ?*anyopaque) callconv(.c) void {
    _ = test_counter.fetchAdd(1, .seq_cst);
}

test "sa_task.test.sched: spawn and join counting" {
    if (!supported) return error.SkipZigTest;
    var handles: [64]u64 = undefined;
    for (&handles) |*h| {
        try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&countingWorker, null, h));
    }
    for (handles) |h| {
        try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    }
    try testing.expectEqual(@as(u64, 64), test_counter.load(.seq_cst));
}

pub fn sleepyWorker(arg: ?*anyopaque) callconv(.c) void {
    const done_flag: *std.atomic.Value(bool) = @ptrCast(@alignCast(arg.?));
    _ = sa_task_sleep_ms(40);
    done_flag.store(true, .release);
}

test "sa_task.test.sched: sleep parks and wakes" {
    if (!supported) return error.SkipZigTest;
    var flag: std.atomic.Value(bool) = .init(false);
    var h: u64 = 0;
    const t0 = monotonicNs();
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&sleepyWorker, &flag, &h));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    const elapsed = monotonicNs() - t0;
    try testing.expect(flag.load(.acquire));
    try testing.expect(elapsed >= 35 * std.time.ns_per_ms);
}

pub fn yieldWorker(arg: ?*anyopaque) callconv(.c) void {
    const counter: *std.atomic.Value(u64) = @ptrCast(@alignCast(arg.?));
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        _ = counter.fetchAdd(1, .seq_cst);
        _ = sa_task_yield();
    }
}

test "sa_task.test.sched: cooperative yield progress" {
    if (!supported) return error.SkipZigTest;
    var counter: std.atomic.Value(u64) = .init(0);
    var hs: [8]u64 = undefined;
    for (&hs) |*h| try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&yieldWorker, &counter, h));
    for (hs) |h| try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(@as(u64, 8 * 200), counter.load(.seq_cst));
}

pub var sink_seen_code: std.atomic.Value(i32) = .init(0);

pub var sink_seen_len: std.atomic.Value(u64) = .init(0);

pub fn recordingSink(_: u64, code: i32, _: [*]const u8, msg_len: u64, _: ?*anyopaque) callconv(.c) void {
    sink_seen_code.store(code, .release);
    sink_seen_len.store(msg_len, .release);
}

pub fn trappingWorker(_: ?*anyopaque) callconv(.c) void {
    setTrapSink(&recordingSink, null);
    raiseTrap(SA_TASK_TRAP_INTERNAL, "boom from test");
}

test "sa_task.test.sched: boundary trap sink catches runtime trap" {
    if (!supported) return error.SkipZigTest;
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&trappingWorker, null, &h));
    try testing.expectEqual(SA_TASK_TRAPPED, sa_task_join(h));
    try testing.expectEqual(SA_TASK_TRAP_INTERNAL, sink_seen_code.load(.acquire));
    try testing.expectEqual(@as(u64, 14), sink_seen_len.load(.acquire));
}

test "sa_task.test.sched: mass spawn exit 10000" {
    if (!supported) return error.SkipZigTest;
    const N = 10_000;
    const handles = try alloc.alloc(u64, N);
    defer alloc.free(handles);
    var before: u64 = 0;
    _ = sa_task_live_count(&before);
    for (handles) |*h| {
        try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&countingWorker, null, h));
    }
    for (handles) |h| {
        try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    }
    var after: u64 = 0;
    _ = sa_task_live_count(&after);
    try testing.expectEqual(before, after);
}

// The two process-fatal behaviors — the stack-overflow trap and
// the armed deadlock guard — end in abort() by design, so they
// are verified as subprocess scenarios by the acceptance harness
// (acceptance programs that must die with SIGABRT and the trap
// message on stderr). The Zig tests here cover the mechanisms
// in-process: guard registration, and the quiescence predicate
// the guard fires on.
pub var probe_region_lo: std.atomic.Value(usize) = .init(0);

pub var probe_stack_addr: std.atomic.Value(usize) = .init(0);

pub var probe_release: std.atomic.Value(bool) = .init(false);

pub fn probeWorker(_: ?*anyopaque) callconv(.c) void {
    const g = t02.current_g.?;
    var marker: u8 = 0;
    probe_region_lo.store(@intFromPtr(g.region.ptr), .release);
    probe_stack_addr.store(@intFromPtr(&marker), .release);
    while (!probe_release.load(.acquire)) _ = sa_task_sleep_ms(5);
}

test "sa_task.test.sched: guard range registered while goroutine lives" {
    if (!supported) return error.SkipZigTest;
    probe_release.store(false, .release);
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&probeWorker, null, &h));
    while (probe_region_lo.load(.acquire) == 0) std.Thread.yield() catch {};
    const lo = probe_region_lo.load(.acquire);
    // An address inside the guard zone resolves to this goroutine.
    try testing.expectEqual(h, guardLookup(lo + 1).?);
    try testing.expectEqual(h, guardLookup(lo + GUARD_KIB * 1024 - 1).?);
    // The usable stack (where the worker's locals live) is NOT a
    // guard zone.
    try testing.expect(guardLookup(probe_stack_addr.load(.acquire)) == null);
    probe_release.store(true, .release);
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    // Stack reclaim (and with it guard unregistration) is done
    // by the carrier after the exit switch, asynchronously to
    // the join return: poll for it with a bounded deadline.
    const deadline = monotonicNs() + 2 * std.time.ns_per_s;
    while (guardLookup(lo + 1) != null) {
        if (monotonicNs() > deadline) break;
        std.Thread.yield() catch {};
    }
    try testing.expect(guardLookup(lo + 1) == null);
}

// ---------------------------------------------------------------------
// DEF-R2 reserve/commit tests.
pub var r2_sum: std.atomic.Value(u64) = .init(0);

pub var r2_deepest_committed: std.atomic.Value(usize) = .init(0);

pub var r2_deepest_top: std.atomic.Value(usize) = .init(0);

pub fn r2Descend(n: usize) u64 {
    var frame: [16 * 1024]u8 = undefined;
    for (&frame, 0..) |*b, i| b.* = @truncate(n + i);
    var sum: u64 = 0;
    if (n == 0) {
        var marker: u8 = 0;
        if (stackEntryLookup(@intFromPtr(&marker))) |e| {
            r2_deepest_committed.store(e.committed_lo.load(.monotonic), .release);
            r2_deepest_top.store(e.top, .release);
        }
    } else {
        sum +%= r2Descend(n - 1);
    }
    for (frame) |b| sum +%= b;
    return sum;
}

pub fn r2GrowWorker(arg: ?*anyopaque) callconv(.c) void {
    const depth: usize = @intCast(@intFromPtr(arg.?));
    r2_sum.store(r2Descend(depth), .release);
}

test "sa_task.test.sched: reserve/commit grows in place for a deep descent (DEF-R2)" {
    if (!supported) return error.SkipZigTest;
    // 192 levels x ~16 KiB frames ~= 3 MiB of descent: far past
    // the 256 KiB initial commit, far below the 64 MiB cap.
    const depth: usize = 192;
    const events0 = stack_grow_events.load(.monotonic);
    r2_deepest_committed.store(0, .release);
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&r2GrowWorker, @ptrFromInt(depth), &h));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    var expect: u64 = 0;
    var k: usize = 0;
    while (k <= depth) : (k += 1) {
        var i: usize = 0;
        while (i < 16 * 1024) : (i += 1) expect +%= @as(u8, @truncate(k + i));
    }
    try testing.expectEqual(expect, r2_sum.load(.acquire));
    // Growth actually happened (in place — not a silently
    // larger fixed stack):
    try testing.expect(stack_grow_events.load(.monotonic) > events0);
    // And by the deepest point the committed span had grown
    // well past the initial commit.
    try testing.expect(r2_deepest_top.load(.acquire) - r2_deepest_committed.load(.acquire) > 2 * 1024 * 1024);
}

pub var r2_release: std.atomic.Value(bool) = .init(false);

pub fn r2ParkWorker(_: ?*anyopaque) callconv(.c) void {
    while (!r2_release.load(.acquire)) _ = sa_task_sleep_ms(5);
}

test "sa_task.test.sched: parked shallow tasks keep commit at the initial quantum (DEF-R2)" {
    if (!supported) return error.SkipZigTest;
    r2_release.store(false, .release);
    const N = 256;
    var handles: [N]u64 = undefined;
    for (&handles) |*h| try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&r2ParkWorker, null, h));
    // Let the workers start and park.
    var ts: linux.timespec = .{ .sec = 0, .nsec = 50 * std.time.ns_per_ms };
    _ = linux.nanosleep(&ts, null);
    var total_committed: usize = 0;
    var found: usize = 0;
    for (&guard_table) |*e| {
        if (!e.live.load(.acquire)) continue;
        for (handles) |h| {
            if (e.id == h) {
                total_committed += e.top - e.committed_lo.load(.monotonic);
                found += 1;
            }
        }
    }
    try testing.expectEqual(@as(usize, N), found);
    // Committed stays at the initial quantum per task (plus a
    // small slack) — NOT the 64 MiB reserve: idle tasks do not
    // commit their reservation.
    try testing.expect(total_committed <= N * (cfg_stack_initial + 64 * 1024));
    r2_release.store(true, .release);
    for (handles) |h| try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
}

pub var cycle_handles: [2]u64 = .{ 0, 0 };

pub var cycle_ready: std.atomic.Value(bool) = .init(false);

pub fn cycleWorker(arg: ?*anyopaque) callconv(.c) void {
    // Index is passed as (idx + 1) so index 0 is not a null pointer.
    const idx: usize = @intCast(@intFromPtr(arg.?) - 1);
    while (!cycle_ready.load(.acquire)) _ = sa_task_yield();
    _ = sa_task_join(cycle_handles[1 - idx]);
}

test "sa_task.test.sched: join cycle reaches guard quiescence" {
    if (!supported) return error.SkipZigTest;
    // Two goroutines join each other: both park forever with no
    // timers and no runnable work — exactly the state the armed
    // deadlock guard traps on (the trap itself is an abort, so it
    // is exercised by the acceptance harness as a subprocess).
    // The pair intentionally stays parked for the rest of this
    // test process; later tests use live-count deltas.
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&cycleWorker, @ptrFromInt(@as(usize, 1)), &cycle_handles[0]));
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&cycleWorker, @ptrFromInt(@as(usize, 2)), &cycle_handles[1]));
    cycle_ready.store(true, .release);
    // Let both park and the 250 ms progress grace window lapse:
    // poll against a wall-clock deadline (2 s), not a spin count.
    const deadline = monotonicNs() + 2 * std.time.ns_per_s;
    while (!systemQuiescent()) {
        if (monotonicNs() > deadline) break;
        var ts: linux.timespec = .{ .sec = 0, .nsec = 5 * std.time.ns_per_ms };
        _ = linux.nanosleep(&ts, null);
    }
    try testing.expect(systemQuiescent());
}

// ---------------------------------------------------------------------
// Phase B: channels (Go semantics) + select.
//
// Payload is one fixed 16-byte Slot {a, b} at this layer; typed
// surfaces belong to later layers. Channel close semantics follow
// Go: send on a closed channel is a trap (including a blocked
// send woken by close, and a select send case claimed by close),
// close of a closed channel is a trap, receivers drain remaining
// buffered values and then observe closed. Closing is also the
// broadcast primitive behind the context-cancellation idiom (a
// shared cap-0 Done channel closed once wakes every receiver and
// every select case waiting on it).
//
// Select cases are evaluated in order (a documented refinement:
// Go chooses pseudo-randomly among ready cases; in-order is a
// legal single choice and is deterministic). A blocked select
// registers one wait node per case in the channels' own queues —
// multi-way wait is native to the park queues, not a poll loop.
pub const SA_CHAN_CLOSED: i32 = 101;

pub const SA_TASK_TRAP_CLOSE_OF_CLOSED: i32 = 4;

pub const SA_CHAN_OP_RECV: u32 = 0;

pub const SA_CHAN_OP_SEND: u32 = 1;

pub const WAKE_SEND_ON_CLOSED: i32 = -7;

pub const WAKE_RECHECK: i32 = -8;

pub const WAKE_DESTROYED: i32 = -9;

pub const Channel = struct {
    mu: Mutex = .{},
    cap: u32 = 0,
    buf: []Slot = &.{},
    head: usize = 0,
    count: usize = 0,
    closed: bool = false,
    sendq_head: ?*WaitNode = null,
    sendq_tail: ?*WaitNode = null,
    recvq_head: ?*WaitNode = null,
    recvq_tail: ?*WaitNode = null,
    slot_idx: u32 = 0,
    gen: u32 = 0,
    dead: bool = false,
    refs: std.atomic.Value(u32) = .init(1),

    fn handle(ch: *const Channel) u64 {
        return (@as(u64, ch.gen) << 32) | @as(u64, ch.slot_idx);
    }
};

pub var chan_registry_mu: Mutex = .{};

pub var chan_slots: std.ArrayList(?*Channel) = .empty;

// Generations live OUTSIDE the Channel struct: the struct is
// freed when its last pin drops, which can happen before the
// slot is reused, so make must never read gen from a dead struct.
pub var chan_gens: std.ArrayList(u32) = .empty;

pub var chan_free: std.ArrayList(u32) = .empty;

pub fn chanLookup(handle: u64) ?*Channel {
    const idx: u32 = @truncate(handle);
    const gen: u32 = @truncate(handle >> 32);
    chan_registry_mu.lock();
    defer chan_registry_mu.unlock();
    if (idx >= chan_slots.items.len) return null;
    const ch = chan_slots.items[idx] orelse return null;
    if (ch.gen != gen or ch.dead) return null;
    _ = ch.refs.fetchAdd(1, .seq_cst);
    return ch;
}
