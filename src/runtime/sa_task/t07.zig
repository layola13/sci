const std = @import("std");
const builtin = @import("builtin");
const ERR_INVALID = @import("t01.zig").ERR_INVALID;
const ERR_NOMEM = @import("t01.zig").ERR_NOMEM;
const ERR_UNSUPPORTED = @import("t01.zig").ERR_UNSUPPORTED;
const Mutex = @import("t01.zig").Mutex;
const NetWaiter = @import("t03.zig").NetWaiter;
const OsWaiter = @import("t01.zig").OsWaiter;
const SA_CHAN_OP_RECV = @import("t04.zig").SA_CHAN_OP_RECV;
const SA_TASK_OK = @import("t01.zig").SA_TASK_OK;
const SA_TASK_TRAPPED = @import("t01.zig").SA_TASK_TRAPPED;
const SA_TASK_TRAP_SEND_ON_CLOSED = @import("t01.zig").SA_TASK_TRAP_SEND_ON_CLOSED;
const Slot = @import("t01.zig").Slot;
const alloc = @import("t01.zig").alloc;
const ensureInit = @import("t03.zig").ensureInit;
const monotonicNs = @import("t01.zig").monotonicNs;
const parkBegin = @import("t02.zig").parkBegin;
const parkSwitch = @import("t02.zig").parkSwitch;
const sa_chan_close = @import("t05.zig").sa_chan_close;
const sa_chan_destroy = @import("t05.zig").sa_chan_destroy;
const sa_chan_make = @import("t05.zig").sa_chan_make;
const sa_chan_recv = @import("t05.zig").sa_chan_recv;
const sa_chan_select = @import("t06.zig").sa_chan_select;
const sa_chan_send = @import("t05.zig").sa_chan_send;
const sa_task_join = @import("t04.zig").sa_task_join;
const sa_task_sleep_ms = @import("t04.zig").sa_task_sleep_ms;
const sa_task_spawn = @import("t03.zig").sa_task_spawn;
const setTrapSink = @import("t03.zig").setTrapSink;
const supported = @import("t01.zig").supported;
const testing = @import("t04.zig").testing;
const timerAdd = @import("t02.zig").timerAdd;
const unpark = @import("t02.zig").unpark;
const unparkNoWake = @import("t02.zig").unparkNoWake;
const wakeDemand = @import("t02.zig").wakeDemand;
const t02 = @import("t02.zig");

test "sa_task.test.select: default takes precedence over zero timeout" {
    if (!supported) return error.SkipZigTest;
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &ch));
    var chans = [1]u64{ch};
    var ops = [1]u32{SA_CHAN_OP_RECV};
    var slots = [1]Slot{.{}};
    var idx: i64 = -99;
    try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans, &ops, &slots, 1, 1, 0, &idx, null));
    try testing.expectEqual(@as(i64, -1), idx);
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}

test "sa_task.test.select: ready arms drain in order, no arm starves" {
    if (!supported) return error.SkipZigTest;
    var ch1: u64 = 0;
    var ch2: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(4, &ch1));
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(4, &ch2));
    for (0..3) |i| {
        var v1: Slot = .{ .a = @intCast(100 + i), .b = 0 };
        try testing.expectEqual(SA_TASK_OK, sa_chan_send(ch1, &v1));
        var v2: Slot = .{ .a = @intCast(200 + i), .b = 0 };
        try testing.expectEqual(SA_TASK_OK, sa_chan_send(ch2, &v2));
    }
    var chans = [2]u64{ ch1, ch2 };
    var ops = [2]u32{ SA_CHAN_OP_RECV, SA_CHAN_OP_RECV };
    var slots = [2]Slot{ .{}, .{} };
    // In-order evaluation drains the earlier ready arm first;
    // across the full drain every arm's items are all served --
    // no item is starved while its channel holds values.
    var counts = [2]u64{ 0, 0 };
    var seen = [6]u64{ 0, 0, 0, 0, 0, 0 };
    var k: usize = 0;
    while (k < 6) : (k += 1) {
        var idx: i64 = -99;
        slots = [2]Slot{ .{}, .{} };
        try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans, &ops, &slots, 2, 0, 0, &idx, null));
        try testing.expect(idx == 0 or idx == 1);
        counts[@intCast(idx)] += 1;
        seen[k] = slots[@intCast(idx)].a;
    }
    try testing.expectEqual(@as(u64, 3), counts[0]);
    try testing.expectEqual(@as(u64, 3), counts[1]);
    for (0..3) |i| {
        try testing.expectEqual(@as(u64, @intCast(100 + i)), seen[i]);
        try testing.expectEqual(@as(u64, @intCast(200 + i)), seen[3 + i]);
    }
    // Both drained: a further zero-timeout poll reports timeout.
    var idx: i64 = -99;
    try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans, &ops, &slots, 2, 0, 0, &idx, null));
    try testing.expectEqual(@as(i64, -2), idx);
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch1));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch2));
}

pub const SelWake = struct {
    a: u64 = 0,
    b: u64 = 0,
    timeout_ns: i64 = -1,
    idx: std.atomic.Value(i64) = .init(-99),
    val: std.atomic.Value(u64) = .init(0),
};

pub var selwake: SelWake = .{};

pub fn selWakeWaiter(_: ?*anyopaque) callconv(.c) void {
    var chans = [2]u64{ selwake.a, selwake.b };
    var ops = [2]u32{ SA_CHAN_OP_RECV, SA_CHAN_OP_RECV };
    var slots = [2]Slot{ .{}, .{} };
    var idx: i64 = -1;
    _ = sa_chan_select(&chans, &ops, &slots, 2, 0, selwake.timeout_ns, &idx, null);
    selwake.idx.store(idx, .seq_cst);
    if (idx >= 0) selwake.val.store(slots[@intCast(idx)].a, .seq_cst);
}

test "sa_task.test.select: blocked select is woken by the second arm" {
    if (!supported) return error.SkipZigTest;
    selwake = .{ .timeout_ns = -1 };
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &selwake.a));
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &selwake.b));
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&selWakeWaiter, null, &h));
    _ = sa_task_sleep_ms(60); // let the waiter park in select
    var v: Slot = .{ .a = 9001, .b = 0 };
    try testing.expectEqual(SA_TASK_OK, sa_chan_send(selwake.b, &v));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(@as(i64, 1), selwake.idx.load(.seq_cst));
    try testing.expectEqual(@as(u64, 9001), selwake.val.load(.seq_cst));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(selwake.a));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(selwake.b));
}

test "sa_task.test.select: long timeout still waits and is woken by data" {
    if (!supported) return error.SkipZigTest;
    selwake = .{ .timeout_ns = 5 * std.time.ns_per_s };
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &selwake.a));
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &selwake.b));
    const t0 = monotonicNs();
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&selWakeWaiter, null, &h));
    _ = sa_task_sleep_ms(60); // waiter is parked with ~5 s left
    var v: Slot = .{ .a = 31337, .b = 0 };
    try testing.expectEqual(SA_TASK_OK, sa_chan_send(selwake.a, &v));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    const elapsed = monotonicNs() - t0;
    try testing.expectEqual(@as(i64, 0), selwake.idx.load(.seq_cst));
    try testing.expectEqual(@as(u64, 31337), selwake.val.load(.seq_cst));
    // Woken by the data long before the 5 s timeout, and not
    // before the send (i.e. it genuinely waited).
    try testing.expect(elapsed < 2 * std.time.ns_per_s);
    try testing.expect(elapsed >= 40 * std.time.ns_per_ms);
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(selwake.a));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(selwake.b));
}

pub const SelMany = struct {
    chans: [40]u64 = undefined,
    idx: std.atomic.Value(i64) = .init(-99),
    val: std.atomic.Value(u64) = .init(0),
};

pub var selmany: SelMany = .{};

pub fn selManyWaiter(_: ?*anyopaque) callconv(.c) void {
    var ops: [40]u32 = undefined;
    var slots: [40]Slot = undefined;
    for (&ops) |*o| o.* = SA_CHAN_OP_RECV;
    for (&slots) |*s| s.* = .{};
    var idx: i64 = -1;
    _ = sa_chan_select(&selmany.chans, &ops, &slots, 40, 0, -1, &idx, null);
    selmany.idx.store(idx, .seq_cst);
    if (idx >= 0) selmany.val.store(slots[@intCast(idx)].a, .seq_cst);
}

test "sa_task.test.select: 40 cases (heap node path) woken by the last arm" {
    if (!supported) return error.SkipZigTest;
    selmany = .{};
    for (&selmany.chans) |*h| try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, h));
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&selManyWaiter, null, &h));
    _ = sa_task_sleep_ms(60); // let the waiter register all 40 arms
    var v: Slot = .{ .a = 4242, .b = 0 };
    try testing.expectEqual(SA_TASK_OK, sa_chan_send(selmany.chans[39], &v));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(@as(i64, 39), selmany.idx.load(.seq_cst));
    try testing.expectEqual(@as(u64, 4242), selmany.val.load(.seq_cst));
    for (selmany.chans) |ch| try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}

test "sa_task.test.select: 40 cases (heap node path) still time out precisely" {
    if (!supported) return error.SkipZigTest;
    selmany = .{};
    for (&selmany.chans) |*h| try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, h));
    var ops: [40]u32 = undefined;
    var slots: [40]Slot = undefined;
    for (&ops) |*o| o.* = SA_CHAN_OP_RECV;
    for (&slots) |*s| s.* = .{};
    var idx: i64 = -1;
    const t0 = monotonicNs();
    try testing.expectEqual(SA_TASK_OK, sa_chan_select(&selmany.chans, &ops, &slots, 40, 0, 30 * std.time.ns_per_ms, &idx, null));
    const elapsed = monotonicNs() - t0;
    try testing.expectEqual(@as(i64, -2), idx);
    try testing.expect(elapsed >= 20 * std.time.ns_per_ms);
    try testing.expect(elapsed < 2 * std.time.ns_per_s);
    for (selmany.chans) |ch| try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}

test "sa_task.test.select: recycled waiters keep timeout precision across cycles" {
    if (!supported) return error.SkipZigTest;
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &ch));
    // Alternate timed-out cycles (the waiter is released by
    // its own timer fire and recycled) with data-claimed
    // cycles (released by the owner). Every cycle must observe
    // its own outcome and its own deadline: a stale claim or a
    // stale gen leaking across pool reuse would show up as a
    // wrong index, a wrong value, or an early return.
    var iter: usize = 0;
    while (iter < 6) : (iter += 1) {
        var chans = [1]u64{ch};
        var ops = [1]u32{SA_CHAN_OP_RECV};
        var slots = [1]Slot{.{}};
        var idx: i64 = -1;
        if (iter % 2 == 0) {
            const t0 = monotonicNs();
            try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans, &ops, &slots, 1, 0, 25 * std.time.ns_per_ms, &idx, null));
            const elapsed = monotonicNs() - t0;
            try testing.expectEqual(@as(i64, -2), idx);
            try testing.expect(elapsed >= 18 * std.time.ns_per_ms);
            try testing.expect(elapsed < 1 * std.time.ns_per_s);
        } else {
            selwake = .{ .timeout_ns = 500 * std.time.ns_per_ms };
            selwake.a = ch;
            try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &selwake.b));
            var h: u64 = 0;
            const t0 = monotonicNs();
            try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&selWakeWaiter, null, &h));
            _ = sa_task_sleep_ms(10);
            var v: Slot = .{ .a = 1000 + @as(u64, @intCast(iter)), .b = 0 };
            try testing.expectEqual(SA_TASK_OK, sa_chan_send(ch, &v));
            try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
            const elapsed = monotonicNs() - t0;
            try testing.expectEqual(@as(i64, 0), selwake.idx.load(.seq_cst));
            try testing.expectEqual(@as(u64, 1000 + @as(u64, @intCast(iter))), selwake.val.load(.seq_cst));
            try testing.expect(elapsed < 300 * std.time.ns_per_ms);
            try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(selwake.b));
        }
    }
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}

pub const SelFair = struct {
    ch: u64 = 0,
    got_a: std.atomic.Value(u64) = .init(0),
    got_b: std.atomic.Value(u64) = .init(0),
};

pub var selfair: SelFair = .{};

pub fn selFairWaiter(arg: ?*anyopaque) callconv(.c) void {
    const mine: *std.atomic.Value(u64) = @ptrCast(@alignCast(arg.?));
    var n: usize = 0;
    while (n < 20) : (n += 1) {
        var chans = [1]u64{selfair.ch};
        var ops = [1]u32{SA_CHAN_OP_RECV};
        var slots = [1]Slot{.{}};
        var idx: i64 = -1;
        _ = sa_chan_select(&chans, &ops, &slots, 1, 0, -1, &idx, null);
        if (idx == 0) _ = mine.fetchAdd(1, .seq_cst);
    }
}

test "sa_task.test.select: two waiters on one channel neither starves" {
    if (!supported) return error.SkipZigTest;
    selfair = .{};
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &selfair.ch));
    var ha: u64 = 0;
    var hb: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&selFairWaiter, @ptrCast(&selfair.got_a), &ha));
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&selFairWaiter, @ptrCast(&selfair.got_b), &hb));
    _ = sa_task_sleep_ms(30); // both parked
    var i: usize = 0;
    while (i < 40) : (i += 1) {
        var v: Slot = .{ .a = @intCast(i), .b = 0 };
        try testing.expectEqual(SA_TASK_OK, sa_chan_send(selfair.ch, &v));
        _ = sa_task_sleep_ms(5);
    }
    try testing.expectEqual(SA_TASK_OK, sa_task_join(ha));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(hb));
    try testing.expectEqual(@as(u64, 40), selfair.got_a.load(.seq_cst) + selfair.got_b.load(.seq_cst));
    try testing.expect(selfair.got_a.load(.seq_cst) >= 5);
    try testing.expect(selfair.got_b.load(.seq_cst) >= 5);
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(selfair.ch));
}

pub var sink_send_closed_code: std.atomic.Value(i32) = .init(0);

pub fn sendClosedSink(_: u64, code: i32, _: [*]const u8, _: u64, _: ?*anyopaque) callconv(.c) void {
    sink_send_closed_code.store(code, .release);
}

pub fn sendOnClosedWorker(arg: ?*anyopaque) callconv(.c) void {
    const ch: u64 = @intFromPtr(arg.?);
    setTrapSink(&sendClosedSink, null);
    var v: Slot = .{ .a = 1, .b = 0 };
    _ = sa_chan_send(ch, &v);
}

test "sa_task.test.chan: send on closed channel traps at the boundary" {
    if (!supported) return error.SkipZigTest;
    sink_send_closed_code.store(0, .release);
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(1, &ch));
    try testing.expectEqual(SA_TASK_OK, sa_chan_close(ch));
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&sendOnClosedWorker, @ptrFromInt(@as(usize, @intCast(ch))), &h));
    try testing.expectEqual(SA_TASK_TRAPPED, sa_task_join(h));
    try testing.expectEqual(SA_TASK_TRAP_SEND_ON_CLOSED, sink_send_closed_code.load(.acquire));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}

pub const DoneFan = struct {
    done: u64 = 0,
    work: u64 = 0,
    woke: std.atomic.Value(u64) = .init(0),
    done_case: std.atomic.Value(u64) = .init(0),
};

pub var donefan: DoneFan = .{};

pub fn doneWaiter(_: ?*anyopaque) callconv(.c) void {
    var chans = [2]u64{ donefan.work, donefan.done };
    var ops = [2]u32{ SA_CHAN_OP_RECV, SA_CHAN_OP_RECV };
    var slots = [2]Slot{ .{}, .{} };
    var idx: i64 = -1;
    var closed: u32 = 0;
    _ = sa_chan_select(&chans, &ops, &slots, 2, 0, -1, &idx, &closed);
    if (idx == 1) _ = donefan.done_case.fetchAdd(1, .seq_cst);
    _ = donefan.woke.fetchAdd(1, .seq_cst);
}

test "sa_task.test.select: closing a Done channel broadcasts to all waiters" {
    if (!supported) return error.SkipZigTest;
    donefan = .{};
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &donefan.done));
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &donefan.work));
    var hs: [8]u64 = undefined;
    for (&hs) |*h| try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&doneWaiter, null, h));
    _ = sa_task_sleep_ms(80); // let all waiters park in select
    try testing.expectEqual(SA_TASK_OK, sa_chan_close(donefan.done));
    for (hs) |h| try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(@as(u64, 8), donefan.woke.load(.seq_cst));
    try testing.expectEqual(@as(u64, 8), donefan.done_case.load(.seq_cst));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(donefan.done));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(donefan.work));
}

test "sa_task.test.chan: receivers drain buffered values after close" {
    if (!supported) return error.SkipZigTest;
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(3, &ch));
    for (0..3) |i| {
        var v: Slot = .{ .a = @intCast(10 + i), .b = 0 };
        try testing.expectEqual(SA_TASK_OK, sa_chan_send(ch, &v));
    }
    try testing.expectEqual(SA_TASK_OK, sa_chan_close(ch));
    for (0..3) |i| {
        var out: Slot = undefined;
        var closed: u32 = 99;
        try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, &closed));
        try testing.expectEqual(@as(u32, 0), closed);
        try testing.expectEqual(@as(u64, 10 + i), out.a);
    }
    var out: Slot = undefined;
    var closed: u32 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, &closed));
    try testing.expectEqual(@as(u32, 1), closed);
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}

// ---------------------------------------------------------------------
// Phase C: netpoller glue + sync primitives.
//
// Net: sa_task_net_wait parks the caller until a socket handle
// (an sa_std socket-resource handle) signals readiness, without
// occupying a carrier thread: registration is validated eagerly
// with a zero-timeout poll (an invalid handle fails the call
// immediately, never silently parks), then idle carriers poll the
// parked set and wake the waiters whose masks came back nonzero.
// Timeouts ride the phase-A timer heap.
//
// The poll face is the existing sa_std_net_poll_wait, declared
// here as a plain extern: in every sa_std-rooted build (unit,
// static, shared) sa_std.zig's own export satisfies it in the
// same compilation, and SA-built binaries link both objects
// from the archive. An .init_array constructor registration
// was tried first and is deliberately NOT used: SA-built test
// binaries segfault at startup when the archive carries an
// .init_array entry (verified by bisection: import-only test,
// zero calls, still signal 11; ctor removed -> all pass).
// Standalone module tests link through sa_task_test_root.zig,
// which provides a loud UNSUPPORTED stub for the symbol; the
// poll hook below remains as a test override so unit tests can
// drive the machinery with a deterministic fake poller.
pub const SA_TASK_NET_READ: u32 = 1;

pub const SA_TASK_NET_WRITE: u32 = 2;

pub const SA_TASK_NET_ERROR: u32 = 4;

pub const PollFn = *const fn (handles: ?[*]const u64, interests: ?[*]const u32, count: u64, timeout_ms: i32, ready: ?[*]u32, out_ready_count: ?*u64) callconv(.c) i32;

pub extern fn sa_std_net_poll_wait(handles: ?[*]const u64, interests: ?[*]const u32, count: u64, timeout_ms: i32, ready: ?[*]u32, out_ready_count: ?*u64) i32;

pub var poll_hook: ?PollFn = null;

pub fn setPollHook(f: PollFn) void {
    poll_hook = f;
}

pub fn pollWait(handles: ?[*]const u64, interests: ?[*]const u32, count: u64, timeout_ms: i32, ready: ?[*]u32, out_count: ?*u64) i32 {
    if (poll_hook) |hook| return hook(handles, interests, count, timeout_ms, ready, out_count);
    return sa_std_net_poll_wait(handles, interests, count, timeout_ms, ready, out_count);
}

pub var net_mu: Mutex = .{};

pub var net_list: ?*NetWaiter = null;

pub var net_count: usize = 0;

pub var net_gen_counter: std.atomic.Value(u64) = .init(0);

pub fn netRelease(nw: *NetWaiter) void {
    if (nw.refs.fetchSub(1, .seq_cst) == 1) alloc.destroy(nw);
}

pub fn netUnlinkLocked(nw: *NetWaiter) void {
    var prev: ?*NetWaiter = null;
    var cur = net_list;
    while (cur) |n| {
        if (n == nw) {
            if (prev) |p| {
                p.next = n.next;
            } else {
                net_list = n.next;
            }
            n.next = null;
            n.linked = false;
            net_count -= 1;
            return;
        }
        prev = n;
        cur = n.next;
    }
}

pub fn netFireLocked(nw: *NetWaiter, bits: u32, status: i32) void {
    // Caller holds net_mu and has already unlinked nw.
    nw.done = true;
    nw.status = status;
    if (nw.ready_out) |ro| ro.* = bits;
    if (nw.g) |g| {
        g.wake_status = status;
        unpark(g);
    }
    if (nw.os) |os| {
        os.status = status;
        os.fire();
    }
}

pub fn netTimeoutFire(nw: *NetWaiter, gen: u64) void {
    net_mu.lock();
    if (nw.linked and nw.gen == gen and !nw.done) {
        netUnlinkLocked(nw);
        netFireLocked(nw, 0, SA_TASK_OK); // timeout: zero ready bits
    }
    net_mu.unlock();
    netRelease(nw);
}

pub fn netWaiterCount() usize {
    net_mu.lock();
    defer net_mu.unlock();
    return net_count;
}

pub fn pollNetOnce() void {
    net_mu.lock();
    const n = net_count;
    if (n == 0) {
        net_mu.unlock();
        return;
    }
    const waiters = alloc.alloc(*NetWaiter, n) catch {
        net_mu.unlock();
        return;
    };
    defer alloc.free(waiters);
    const handles = alloc.alloc(u64, n) catch {
        net_mu.unlock();
        return;
    };
    defer alloc.free(handles);
    const interests = alloc.alloc(u32, n) catch {
        net_mu.unlock();
        return;
    };
    defer alloc.free(interests);
    const ready = alloc.alloc(u32, n) catch {
        net_mu.unlock();
        return;
    };
    defer alloc.free(ready);
    var i: usize = 0;
    var cur = net_list;
    while (cur) |nw| {
        // Pin while polling unlocked: a timeout may fire (and the
        // owner may return and drop its own pin) mid-poll.
        _ = nw.refs.fetchAdd(1, .seq_cst);
        waiters[i] = nw;
        handles[i] = nw.handle;
        interests[i] = nw.interest;
        ready[i] = 0;
        i += 1;
        cur = nw.next;
    }
    net_mu.unlock();
    defer {
        for (waiters) |nw| netRelease(nw);
    }
    var out_count: u64 = 0;
    const rc = pollWait(handles.ptr, interests.ptr, @intCast(n), 0, ready.ptr, &out_count);
    if (rc != SA_TASK_OK or out_count == 0) return;
    net_mu.lock();
    // Batch wake: unlink + fire all ready waiters without a
    // futex nudge each (netFireLocked's per-waiter wake-all was
    // the N-way storm on a busy poll round), then one
    // demand-sized wake for the actually-enqueued count. Lock
    // order is unchanged from before (net_mu -> sched_mu via
    // unparkNoWake); os waiters still fire immediately.
    var fired: usize = 0;
    for (0..n) |k| {
        if (ready[k] != 0) {
            const nw = waiters[k];
            if (nw.linked and !nw.done) {
                netUnlinkLocked(nw);
                nw.done = true;
                nw.status = SA_TASK_OK;
                if (nw.ready_out) |ro| ro.* = ready[k];
                if (nw.g) |g| {
                    g.wake_status = SA_TASK_OK;
                    if (unparkNoWake(g)) fired += 1;
                }
                if (nw.os) |os| {
                    os.status = SA_TASK_OK;
                    os.fire();
                }
            }
        }
    }
    net_mu.unlock();
    if (fired > 0) wakeDemand(fired);
}

/// Park until `handle` is ready for `interest` (SA_TASK_NET_*
/// bits) or the timeout elapses. timeout_ns < 0 waits forever.
/// On return, ready_out receives the readiness mask (0 on
/// timeout). An invalid handle is rejected by the validation
/// poll before any parking happens.
pub export fn sa_task_net_wait(handle: u64, interest: u32, timeout_ns: i64, ready_out: ?*u32) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const ro = ready_out orelse return ERR_INVALID;
    ro.* = 0;
    if (interest == 0 or (interest & ~@as(u32, 7)) != 0) return ERR_INVALID;
    if (!ensureInit()) return ERR_UNSUPPORTED;
    // Eager validation + already-ready fast path.
    var h_arr = [1]u64{handle};
    var i_arr = [1]u32{interest};
    var r_arr = [1]u32{0};
    var oc: u64 = 0;
    const vrc = pollWait(&h_arr, &i_arr, 1, 0, &r_arr, &oc);
    if (vrc != SA_TASK_OK) return vrc;
    if (oc > 0) {
        ro.* = r_arr[0];
        return SA_TASK_OK;
    }
    if (timeout_ns == 0) return SA_TASK_OK;
    const nw = alloc.create(NetWaiter) catch return ERR_NOMEM;
    nw.* = .{
        .handle = handle,
        .interest = interest,
        .ready_out = ro,
        .gen = net_gen_counter.fetchAdd(1, .seq_cst) + 1,
    };
    var os_waiter: OsWaiter = .{};
    if (t02.current_g) |me| {
        nw.g = me;
        me.wait_kind = .net;
        parkBegin();
    } else {
        nw.os = &os_waiter;
    }
    net_mu.lock();
    nw.next = net_list;
    net_list = nw;
    nw.linked = true;
    net_count += 1;
    net_mu.unlock();
    if (timeout_ns > 0) {
        _ = nw.refs.fetchAdd(1, .seq_cst);
        const deadline = monotonicNs() + timeout_ns;
        if (!timerAdd(deadline, .{ .net = nw }, nw.gen)) {
            _ = nw.refs.fetchSub(1, .seq_cst);
        }
    }
    var status: i32 = SA_TASK_OK;
    if (t02.current_g) |me| {
        parkSwitch();
        me.wait_kind = .none;
        status = me.wake_status;
    } else {
        os_waiter.wait();
        status = os_waiter.status;
    }
    netRelease(nw);
    return status;
}
