//! Cooperative goroutine runtime for wasm targets — the
//! CPS/state-machine track that DESIGN (goroutine parity goal)
//! pairs with the SLA plugin's coop lowering.
//!
//! sa_std.zig selects this module in place of sa_task.zig on wasm:
//! the native mechanism (carrier OS threads + stack-pointer
//! switching) cannot lower to wasm, so here every goroutine is a
//! heap-frame state machine driven by a single-threaded
//! round-robin driver inside sa_coop_run_main. Scheduling is
//! cooperative only — no preemption — which matches the Go wasm
//! yardstick (its lock_js.go: "no support for threads yet. There
//! is no preemption").
//!
//! Blocking protocol (execute once, deliver results, never
//! retry): when a blocking extern cannot complete immediately it
//! registers the current task on the relevant wait queue, captures
//! the call's out-pointers (they point into the waiting task's heap
//! frame, so they stay valid across the suspension), marks the
//! task blocked and returns SA_COOP_BLOCKED. The call is never
//! re-executed: at wake time the runtime writes the data outputs
//! through the captured pointers and stores the final status in
//! the task's pending slot, which the resumed step function
//! collects through sa_coop_take_result. A step invocation
//! therefore returns to the driver exactly when its task blocks or
//! finishes.
//!
//! Status codes mirror sa_task.zig / sa_std.zig: OK=0,
//! INVALID_ARGUMENT=1, INVALID_HANDLE=2, NOT_FOUND=3, NO_MEMORY=5,
//! UNSUPPORTED=8, UNKNOWN=127, SA_TASK_TRAPPED=100 (join delivery
//! for a trapped task; this track traps at process level instead,
//! see "Differences" in the parity design note).
//!
//! v1 registered limits (loud, never silent): sa_task_net_wait and
//! sa_task_monitor return ERR_UNSUPPORTED; a panic inside any task
//! traps the whole module (no per-task trap isolation, so a
//! supervised spawn's sink never fires on this track yet); task
//! frames and select registrations are not freed (bounded by the
//! number of tasks/selects a program runs).

const std = @import("std");
const sio = @import("sio");

pub const SA_TASK_OK: i32 = 0;
pub const SA_TASK_TRAPPED: i32 = 100;
const ERR_INVALID: i32 = 1;
const ERR_INVALID_HANDLE: i32 = 2;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;
const ERR_UNSUPPORTED: i32 = 8;
const ERR_UNKNOWN: i32 = 127;

/// Reserved status returned by a blocking extern exactly when it
/// suspends the current task. Out of band of every real status
/// (0,1,2,3,5,8,100,127); the SLA coop lowering emits the same
/// literal, and sa_std/task.sai documents the pair.
pub const SA_COOP_BLOCKED: i32 = 0x4000_0000;

pub const EntryFn = *const fn (?*anyopaque) callconv(.c) void;
pub const TrapSinkFn = *const fn (handle: u64, code: i32, msg_ptr: [*]const u8, msg_len: u64, ctx: ?*anyopaque) callconv(.c) void;

/// Channel payload cell: the runtime's fixed 16-byte slot, layout
/// identical to sa_task.zig's Slot.
pub const Slot = extern struct { a: u64 = 0, b: u64 = 0 };

const alloc = std.heap.page_allocator;

fn coopTrap(comptime msg: []const u8) noreturn {
    @panic("sa_coop: " ++ msg);
}

fn nowNs() i64 {
    return @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
}

fn hostSleepNs(ns: u64) void {
    if (ns == 0) return;
    sio.io().sleep(.fromNanoseconds(@as(i96, @intCast(ns))), .awake) catch {};
}

// ---------------------------------------------------------------------
// Tasks and the driver

const Task = struct {
    gen: u32,
    entry: EntryFn,
    arg: ?*anyopaque,
    state: enum { ready, running, blocked, done } = .ready,
    exit_status: i32 = 0,
    detached: bool = false,
    join_delivered: bool = false,
    pending: ?i32 = null,
    joiners: ?*JoinWaiter = null,
    joiners_tail: ?*JoinWaiter = null,
    sink: ?TrapSinkFn = null,
    sink_ctx: ?*anyopaque = null,
};

const JoinWaiter = struct {
    task: *Task,
    next: ?*JoinWaiter = null,
};

const Timer = struct {
    deadline: i64,
    task: ?*Task = null,
    sel: ?*SelectReg = null,
    next: ?*Timer = null,
};

var tasks: std.ArrayList(?*Task) = .empty;
var task_gens: std.ArrayList(u32) = .empty;
var current: ?*Task = null;
var root_task: ?*Task = null;
var driver_active: bool = false;
/// Set while the driver synchronously runs a sa_sync_once_do
/// entry: blocking is impossible there (the entry is a plain call
/// frame), so a block attempt traps loudly instead of corrupting
/// the once.
var suspend_forbidden: u32 = 0;

var ready_head: ?*ReadyNode = null;
var ready_tail: ?*ReadyNode = null;
const ReadyNode = struct {
    task: *Task,
    next: ?*ReadyNode = null,
};

var timers_head: ?*Timer = null;

fn makeHandle(slot: usize, gen: u32) u64 {
    return (@as(u64, gen) << 32) | @as(u64, @intCast(slot + 1));
}

fn taskFromHandle(handle: u64) ?*Task {
    if (handle == 0) return null;
    const slot_plus = handle & 0xFFFF_FFFF;
    if (slot_plus == 0) return null;
    const slot: usize = @intCast(slot_plus - 1);
    if (slot >= tasks.items.len) return null;
    const t = tasks.items[slot] orelse return null;
    if (t.gen != @as(u32, @truncate(handle >> 32))) return null;
    return t;
}

fn allocTask(entry: EntryFn, arg: ?*anyopaque) error{OutOfMemory}!*Task {
    // Reuse a reaped slot when one exists.
    for (tasks.items, 0..) |slot_task, i| {
        if (slot_task == null) {
            const t = try alloc.create(Task);
            task_gens.items[i] += 1;
            t.* = .{ .gen = task_gens.items[i], .entry = entry, .arg = arg };
            tasks.items[i] = t;
            return t;
        }
    }
    const t = try alloc.create(Task);
    try tasks.append(alloc, t);
    try task_gens.append(alloc, 1);
    t.* = .{ .gen = 1, .entry = entry, .arg = arg };
    return t;
}

fn taskHandle(t: *Task) u64 {
    for (tasks.items, 0..) |slot_task, i| {
        if (slot_task == t) return makeHandle(i, t.gen);
    }
    return 0;
}

fn readyPush(t: *Task) void {
    const node = alloc.create(ReadyNode) catch coopTrap("out of memory in scheduler");
    node.* = .{ .task = t };
    if (ready_tail) |tail| {
        tail.next = node;
        ready_tail = node;
    } else {
        ready_head = node;
        ready_tail = node;
    }
}

fn readyPop() ?*Task {
    const node = ready_head orelse return null;
    ready_head = node.next;
    if (ready_head == null) ready_tail = null;
    const t = node.task;
    alloc.destroy(node);
    return t;
}

fn makeReady(t: *Task) void {
    if (t.state != .blocked and t.state != .ready) return;
    if (t.state == .ready) return;
    t.state = .ready;
    readyPush(t);
}

/// Deliver a final status to a blocked task and make it runnable.
/// The data outputs of its blocked call were already written
/// through the captured pointers by the waker.
fn wakeWith(t: *Task, status: i32) void {
    t.pending = status;
    makeReady(t);
}

/// Suspend the current task: the caller (a blocking extern) has
/// already registered it on a wait queue or timer.
fn blockCurrent() i32 {
    const me = current orelse return ERR_INVALID;
    if (suspend_forbidden > 0) coopTrap("blocking call inside a once_do entry or host context that cannot suspend");
    me.state = .blocked;
    return SA_COOP_BLOCKED;
}

fn reapIfReady(t: *Task) void {
    if (t.state != .done) return;
    if (!t.detached and !t.join_delivered) return;
    if (t.joiners != null) return;
    for (tasks.items, 0..) |slot_task, i| {
        if (slot_task == t) {
            tasks.items[i] = null;
            alloc.destroy(t);
            return;
        }
    }
}

fn addTimer(deadline: i64, task: ?*Task, sel: ?*SelectReg) error{OutOfMemory}!*Timer {
    const timer = try alloc.create(Timer);
    timer.* = .{ .deadline = deadline, .task = task, .sel = sel, .next = null };
    // Keep the list sorted by deadline (FIFO among equals):
    // promoteTimers wakes due timers in list order, and when the
    // host sleep overshoots several deadlines the wake order must
    // still be deadline order, not registration order.
    var prev: ?*Timer = null;
    var it = timers_head;
    while (it) |t| {
        if (t.deadline > deadline) break;
        prev = t;
        it = t.next;
    }
    timer.next = it;
    if (prev) |p| {
        p.next = timer;
    } else {
        timers_head = timer;
    }
    return timer;
}

/// Fire every expired timer. Sleep wakes deliver OK; select
/// timeouts fire the registration with index -2.
fn promoteTimers() void {
    const now = nowNs();
    var prev: ?*Timer = null;
    var it = timers_head;
    while (it) |timer| {
        if (timer.deadline <= now) {
            const next = timer.next;
            if (prev) |p| {
                p.next = next;
            } else {
                timers_head = next;
            }
            if (timer.sel) |sel| {
                fireSelect(sel, -2, 0);
            } else if (timer.task) |t| {
                if (t.state == .blocked) wakeWith(t, SA_TASK_OK);
            }
            alloc.destroy(timer);
            it = next;
        } else {
            prev = timer;
            it = timer.next;
        }
    }
}

fn earliestDeadline() ?i64 {
    var best: ?i64 = null;
    var it = timers_head;
    while (it) |timer| {
        if (best == null or timer.deadline < best.?) best = timer.deadline;
        it = timer.next;
    }
    return best;
}

fn anyBlocked() bool {
    for (tasks.items) |slot_task| {
        if (slot_task) |t| {
            if (t.state == .blocked) return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------
// Channels

const Chan = struct {
    gen: u32,
    cap: u32,
    buf: []Slot,
    head: usize = 0,
    count: usize = 0,
    closed: bool = false,
    destroyed: bool = false,
    recv_q: ?*ChanWaiter = null,
    recv_tail: ?*ChanWaiter = null,
    send_q: ?*ChanWaiter = null,
    send_tail: ?*ChanWaiter = null,
};

const ChanWaiter = struct {
    task: *Task,
    // recv waiter delivery targets (point into the waiter's frame)
    out_value: ?*Slot = null,
    out_closed: ?*u32 = null,
    // send waiter payload source (points into the sender's frame)
    value_ptr: ?*const Slot = null,
    // select registration, when this waiter is one arm of a select
    sel: ?*SelectReg = null,
    sel_index: u32 = 0,
    next: ?*ChanWaiter = null,
};

const SelectReg = struct {
    task: *Task,
    out_index: *i64,
    out_closed: *u32,
    fired: bool = false,
};

var chans: std.ArrayList(?*Chan) = .empty;
var chan_gens: std.ArrayList(u32) = .empty;

fn chanFromHandle(handle: u64) ?*Chan {
    if (handle == 0) return null;
    const slot_plus = handle & 0xFFFF_FFFF;
    if (slot_plus == 0) return null;
    const slot: usize = @intCast(slot_plus - 1);
    if (slot >= chans.items.len) return null;
    const ch = chans.items[slot] orelse return null;
    if (ch.gen != @as(u32, @truncate(handle >> 32))) return null;
    if (ch.destroyed) return null;
    return ch;
}

fn chanHandle(ch: *Chan) u64 {
    for (chans.items, 0..) |slot_chan, i| {
        if (slot_chan == ch) return makeHandle(i, ch.gen);
    }
    return 0;
}

fn waiterLive(w: *ChanWaiter) bool {
    if (w.sel) |sel| return !sel.fired;
    return true;
}

fn queuePush(head: *?*ChanWaiter, tail: *?*ChanWaiter, w: *ChanWaiter) void {
    w.next = null;
    if (tail.*) |t| {
        t.next = w;
        tail.* = w;
    } else {
        head.* = w;
        tail.* = w;
    }
}

/// Pop the first live waiter, discarding stale select arms.
fn queuePopLive(head: *?*ChanWaiter, tail: *?*ChanWaiter) ?*ChanWaiter {
    while (head.*) |w| {
        head.* = w.next;
        if (head.* == null) tail.* = null;
        if (waiterLive(w)) return w;
        alloc.destroy(w);
    }
    return null;
}

fn queueHasLive(head: ?*ChanWaiter) bool {
    var it = head;
    while (it) |w| {
        if (waiterLive(w)) return true;
        it = w.next;
    }
    return false;
}

/// Complete a send waiter whose payload has been consumed: plain
/// waiters wake with OK; a select arm fires its registration.
fn completeSendWaiter(w: *ChanWaiter) void {
    if (w.sel) |sel| {
        fireSelect(sel, @intCast(w.sel_index), 0);
    } else {
        wakeWith(w.task, SA_TASK_OK);
    }
    alloc.destroy(w);
}

/// Deliver a payload to a recv waiter (plain or select arm).
fn completeRecvWaiter(w: *ChanWaiter, value: Slot, closed_flag: u32) void {
    if (w.sel) |sel| {
        // The arm's slot is the waiter's out_value for select arms.
        if (w.out_value) |ov| ov.* = value;
        fireSelect(sel, @intCast(w.sel_index), closed_flag);
    } else {
        if (w.out_value) |ov| ov.* = value;
        if (w.out_closed) |oc| oc.* = closed_flag;
        wakeWith(w.task, SA_TASK_OK);
    }
    alloc.destroy(w);
}

/// Fire a select registration exactly once: write the chosen
/// index/closed flag through the waiter's frame pointers and
/// deliver OK. The data movement of the chosen arm has already
/// happened (or, for a recv arm, completeRecvWaiter wrote the
/// slot before calling here).
fn fireSelect(sel: *SelectReg, index: i64, closed_flag: u32) void {
    if (sel.fired) return;
    sel.fired = true;
    sel.out_index.* = index;
    sel.out_closed.* = closed_flag;
    wakeWith(sel.task, SA_TASK_OK);
}

fn bufPush(ch: *Chan, value: Slot) void {
    ch.buf[(ch.head + ch.count) % ch.buf.len] = value;
    ch.count += 1;
}

fn bufPop(ch: *Chan) Slot {
    const v = ch.buf[ch.head];
    ch.head = (ch.head + 1) % ch.buf.len;
    ch.count -= 1;
    return v;
}

/// A receive can complete now if the buffer is non-empty, a sender
/// is waiting (rendezvous), or the channel is closed.
fn recvReady(ch: *Chan) bool {
    return ch.count > 0 or queueHasLive(ch.send_q) or ch.closed;
}

/// A send can complete now if a receiver is waiting, the buffer
/// has room, or the channel is closed (send-on-closed traps).
fn sendReady(ch: *Chan) bool {
    return queueHasLive(ch.recv_q) or ch.count < ch.cap or ch.closed;
}

/// Perform a receive that is known ready. Delivery goes to
/// out_value/out_closed. Returns false only when not ready.
fn doRecv(ch: *Chan, out_value: *Slot, out_closed: *u32) bool {
    if (ch.count > 0) {
        const v = bufPop(ch);
        // Refill from a blocked sender (buffer was full).
        if (queuePopLive(&ch.send_q, &ch.send_tail)) |w| {
            bufPush(ch, w.value_ptr.?.*);
            completeSendWaiter(w);
        }
        out_value.* = v;
        out_closed.* = 0;
        return true;
    }
    if (queuePopLive(&ch.send_q, &ch.send_tail)) |w| {
        const v = w.value_ptr.?.*;
        completeSendWaiter(w);
        out_value.* = v;
        out_closed.* = 0;
        return true;
    }
    if (ch.closed) {
        out_value.* = .{};
        out_closed.* = 1;
        return true;
    }
    return false;
}

/// Perform a send that is known ready. Returns false only when
/// not ready.
fn doSend(ch: *Chan, value: Slot) bool {
    if (ch.closed) coopTrap("send on closed channel");
    if (queuePopLive(&ch.recv_q, &ch.recv_tail)) |w| {
        completeRecvWaiter(w, value, 0);
        return true;
    }
    if (ch.count < ch.cap) {
        bufPush(ch, value);
        return true;
    }
    return false;
}

pub export fn sa_chan_make(capacity: u32, out_handle: ?*u64) i32 {
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    const ch = alloc.create(Chan) catch return ERR_NOMEM;
    const buf = alloc.alloc(Slot, capacity) catch {
        alloc.destroy(ch);
        return ERR_NOMEM;
    };
    // Reuse a destroyed slot when one exists.
    for (chans.items, 0..) |slot_chan, i| {
        if (slot_chan == null) {
            chan_gens.items[i] += 1;
            ch.* = .{ .gen = chan_gens.items[i], .cap = capacity, .buf = buf };
            chans.items[i] = ch;
            out.* = makeHandle(i, ch.gen);
            return SA_TASK_OK;
        }
    }
    ch.* = .{ .gen = 1, .cap = capacity, .buf = buf };
    chans.append(alloc, ch) catch {
        alloc.free(buf);
        alloc.destroy(ch);
        return ERR_NOMEM;
    };
    chan_gens.append(alloc, 1) catch return ERR_NOMEM;
    out.* = makeHandle(chans.items.len - 1, 1);
    return SA_TASK_OK;
}

pub export fn sa_chan_destroy(handle: u64) i32 {
    const ch = chanFromHandle(handle) orelse return ERR_INVALID_HANDLE;
    ch.destroyed = true;
    for (chans.items, 0..) |slot_chan, i| {
        if (slot_chan == ch) {
            chans.items[i] = null;
            break;
        }
    }
    alloc.free(ch.buf);
    alloc.destroy(ch);
    return SA_TASK_OK;
}

pub export fn sa_chan_close(handle: u64) i32 {
    const ch = chanFromHandle(handle) orelse return ERR_INVALID_HANDLE;
    if (ch.closed) return SA_TASK_OK;
    ch.closed = true;
    // Blocked receivers drain: each wakes with the closed flag.
    while (queuePopLive(&ch.recv_q, &ch.recv_tail)) |w| {
        completeRecvWaiter(w, .{}, 1);
    }
    // A blocked sender can never complete now: that is a send on
    // a closed channel, which traps on the native track too.
    if (queueHasLive(ch.send_q)) coopTrap("send on closed channel");
    return SA_TASK_OK;
}

pub export fn sa_chan_send(handle: u64, value_ptr: ?*const Slot) i32 {
    const ch = chanFromHandle(handle) orelse return ERR_INVALID_HANDLE;
    const vp = value_ptr orelse return ERR_INVALID;
    if (ch.closed) coopTrap("send on closed channel");
    if (doSend(ch, vp.*)) return SA_TASK_OK;
    const me = current orelse return ERR_INVALID;
    const w = alloc.create(ChanWaiter) catch return ERR_NOMEM;
    w.* = .{ .task = me, .value_ptr = vp };
    queuePush(&ch.send_q, &ch.send_tail, w);
    return blockCurrent();
}

pub export fn sa_chan_recv(handle: u64, out_value: ?*Slot, out_closed: ?*u32) i32 {
    const ch = chanFromHandle(handle) orelse return ERR_INVALID_HANDLE;
    const ov = out_value orelse return ERR_INVALID;
    const oc = out_closed orelse return ERR_INVALID;
    oc.* = 0;
    if (doRecv(ch, ov, oc)) return SA_TASK_OK;
    const me = current orelse return ERR_INVALID;
    const w = alloc.create(ChanWaiter) catch return ERR_NOMEM;
    w.* = .{ .task = me, .out_value = ov, .out_closed = oc };
    queuePush(&ch.recv_q, &ch.recv_tail, w);
    return blockCurrent();
}

pub export fn sa_chan_len(handle: u64, out_len: ?*u64) i32 {
    const ch = chanFromHandle(handle) orelse return ERR_INVALID_HANDLE;
    const out = out_len orelse return ERR_INVALID;
    out.* = ch.count;
    return SA_TASK_OK;
}

pub export fn sa_chan_cap(handle: u64, out_cap: ?*u64) i32 {
    const ch = chanFromHandle(handle) orelse return ERR_INVALID_HANDLE;
    const out = out_cap orelse return ERR_INVALID;
    out.* = ch.cap;
    return SA_TASK_OK;
}

pub export fn sa_chan_select(cases: ?[*]const u64, ops: ?[*]const u32, slots: ?[*]Slot, count: u64, has_default: u32, timeout_ns: i64, out_index: ?*i64, out_closed: ?*u32) i32 {
    const oi = out_index orelse return ERR_INVALID;
    const oc = out_closed orelse return ERR_INVALID;
    oc.* = 0;
    oi.* = -3;
    if (count > 0 and (cases == null or ops == null or slots == null)) return ERR_INVALID;
    const n: usize = @intCast(count);
    // Resolve handles up front: an invalid arm fails the whole
    // select before any arm is performed.
    const case_chans = alloc.alloc(?*Chan, n) catch return ERR_NOMEM;
    defer alloc.free(case_chans);
    for (0..n) |i| {
        case_chans[i] = chanFromHandle(cases.?[i]);
        if (case_chans[i] == null) return ERR_INVALID_HANDLE;
    }
    // Phase 1: first ready arm in declaration order completes.
    for (0..n) |i| {
        const ch = case_chans[i].?;
        if (ops.?[i] == 0) {
            if (recvReady(ch)) {
                var v: Slot = undefined;
                var cl: u32 = 0;
                _ = doRecv(ch, &v, &cl);
                slots.?[i] = v;
                oi.* = @intCast(i);
                oc.* = cl;
                return SA_TASK_OK;
            }
        } else {
            if (sendReady(ch)) {
                if (ch.closed) coopTrap("send on closed channel");
                _ = doSend(ch, slots.?[i]);
                oi.* = @intCast(i);
                return SA_TASK_OK;
            }
        }
    }
    if (has_default != 0) {
        oi.* = -1;
        return SA_TASK_OK;
    }
    if (timeout_ns == 0) {
        oi.* = -2;
        return SA_TASK_OK;
    }
    // Phase 2: register on every arm and suspend.
    const me = current orelse return ERR_INVALID;
    const sel = alloc.create(SelectReg) catch return ERR_NOMEM;
    sel.* = .{ .task = me, .out_index = oi, .out_closed = oc };
    for (0..n) |i| {
        const ch = case_chans[i].?;
        const w = alloc.create(ChanWaiter) catch return ERR_NOMEM;
        if (ops.?[i] == 0) {
            w.* = .{ .task = me, .out_value = &slots.?[i], .sel = sel, .sel_index = @intCast(i) };
            queuePush(&ch.recv_q, &ch.recv_tail, w);
        } else {
            w.* = .{ .task = me, .value_ptr = &slots.?[i], .sel = sel, .sel_index = @intCast(i) };
            queuePush(&ch.send_q, &ch.send_tail, w);
        }
    }
    if (timeout_ns > 0) {
        _ = addTimer(nowNs() + timeout_ns, null, sel) catch return ERR_NOMEM;
    }
    return blockCurrent();
}

// ---------------------------------------------------------------------
// Task lifecycle

fn spawnImpl(entry: ?*const anyopaque, arg: ?*anyopaque, sink: ?TrapSinkFn, sink_ctx: ?*anyopaque, out_handle: ?*u64) i32 {
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    const e = entry orelse return ERR_INVALID;
    const entry_fn: EntryFn = @ptrCast(@alignCast(e));
    const t = allocTask(entry_fn, arg) catch return ERR_NOMEM;
    t.sink = sink;
    t.sink_ctx = sink_ctx;
    t.state = .ready;
    readyPush(t);
    out.* = taskHandle(t);
    return SA_TASK_OK;
}

pub export fn sa_task_spawn(entry: ?*const anyopaque, arg: ?*anyopaque, out_handle: ?*u64) i32 {
    return spawnImpl(entry, arg, null, null, out_handle);
}

pub export fn sa_task_spawn_supervised(entry: ?*const anyopaque, arg: ?*anyopaque, sink: ?*const anyopaque, sink_ctx: ?*anyopaque, out_handle: ?*u64) i32 {
    const sink_fn: ?TrapSinkFn = if (sink) |s| @ptrCast(@alignCast(s)) else null;
    return spawnImpl(entry, arg, sink_fn, sink_ctx, out_handle);
}

pub export fn sa_task_trap_info(handle: u64, out_code: ?*i32, out_msg_ptr: ?*?*const u8, out_msg_len: ?*u64) i32 {
    _ = out_code;
    _ = out_msg_ptr;
    _ = out_msg_len;
    const t = taskFromHandle(handle) orelse return ERR_INVALID_HANDLE;
    if (t.detached) return ERR_INVALID_HANDLE;
    // This track traps at process level: no per-task trap record
    // ever exists, so a live record always reports NOT_FOUND.
    return ERR_NOT_FOUND;
}

pub export fn sa_task_monitor(handle: u64, out_chan: ?*u64) i32 {
    _ = handle;
    _ = out_chan;
    return ERR_UNSUPPORTED;
}

pub export fn sa_task_yield() i32 {
    const me = current orelse return SA_TASK_OK;
    if (suspend_forbidden > 0) coopTrap("yield inside a once_do entry");
    me.pending = SA_TASK_OK;
    me.state = .blocked;
    // Requeue immediately: the driver picks the next ready task,
    // and this one resumes after them with the delivered OK.
    readyPush(me);
    me.state = .ready;
    return SA_COOP_BLOCKED;
}

pub export fn sa_task_sleep_ns(ns: u64) i32 {
    if (ns == 0) return sa_task_yield();
    const me = current orelse {
        hostSleepNs(ns);
        return SA_TASK_OK;
    };
    _ = addTimer(nowNs() + @as(i64, @intCast(ns)), me, null) catch return ERR_NOMEM;
    return blockCurrent();
}

pub export fn sa_task_sleep_ms(ms: u64) i32 {
    const ns = std.math.mul(u64, ms, std.time.ns_per_ms) catch return ERR_INVALID;
    return sa_task_sleep_ns(ns);
}

pub export fn sa_task_join(handle: u64) i32 {
    const t = taskFromHandle(handle) orelse return ERR_INVALID_HANDLE;
    if (t.detached) return ERR_INVALID_HANDLE;
    if (t.join_delivered) return ERR_INVALID_HANDLE;
    const me = current orelse return ERR_INVALID;
    if (me == t) return ERR_INVALID;
    if (t.state == .done) {
        const status = t.exit_status;
        t.join_delivered = true;
        reapIfReady(t);
        return status;
    }
    const w = alloc.create(JoinWaiter) catch return ERR_NOMEM;
    w.* = .{ .task = me };
    if (t.joiners_tail) |tail| {
        tail.next = w;
        t.joiners_tail = w;
    } else {
        t.joiners = w;
        t.joiners_tail = w;
    }
    return blockCurrent();
}

pub export fn sa_task_detach(handle: u64) i32 {
    const t = taskFromHandle(handle) orelse return ERR_INVALID_HANDLE;
    if (t.state == .done and t.join_delivered) return ERR_INVALID_HANDLE;
    t.detached = true;
    reapIfReady(t);
    return SA_TASK_OK;
}

pub export fn sa_task_current(out_handle: ?*u64) i32 {
    const out = out_handle orelse return ERR_INVALID;
    const me = current orelse return ERR_INVALID;
    out.* = taskHandle(me);
    return SA_TASK_OK;
}

pub export fn sa_task_live_count(out_count: ?*u64) i32 {
    const out = out_count orelse return ERR_INVALID;
    var n: u64 = 0;
    for (tasks.items) |slot_task| {
        if (slot_task) |t| {
            if (t.state != .done) n += 1;
        }
    }
    out.* = n;
    return SA_TASK_OK;
}

pub export fn sa_task_deadlock_guard_arm() i32 {
    // Deadlock detection is always on in this driver (no ready
    // task + no pending timer + blocked tasks = loud trap), so
    // arming is satisfied by construction.
    return SA_TASK_OK;
}

pub export fn sa_task_net_wait(handle: u64, interest: u32, timeout_ns: i64, ready_out: ?*u32) i32 {
    _ = handle;
    _ = interest;
    _ = timeout_ns;
    _ = ready_out;
    return ERR_UNSUPPORTED;
}

// ---------------------------------------------------------------------
// Sync family (mutex / rwlock / waitgroup / once)

const SyncKind = enum { mutex, rwlock, waitgroup, once };

const SyncObj = struct {
    gen: u32,
    kind: SyncKind,
    destroyed: bool = false,
    // mutex
    m_owner: ?*Task = null,
    m_queue: TaskQueue = .{},
    // rwlock
    rw_readers: u32 = 0,
    rw_writer: ?*Task = null,
    rw_rqueue: TaskQueue = .{},
    rw_wqueue: TaskQueue = .{},
    // waitgroup
    wg_count: i64 = 0,
    wg_queue: TaskQueue = .{},
    // once
    once_done: bool = false,
    once_running: bool = false,
    once_queue: TaskQueue = .{},
};

const WaitNode = struct {
    task: *Task,
    next: ?*WaitNode = null,
};

const TaskQueue = struct {
    head: ?*WaitNode = null,
    tail: ?*WaitNode = null,

    fn push(q: *TaskQueue, t: *Task) error{OutOfMemory}!void {
        const node = try alloc.create(WaitNode);
        node.* = .{ .task = t };
        if (q.tail) |tail| {
            tail.next = node;
            q.tail = node;
        } else {
            q.head = node;
            q.tail = node;
        }
    }

    fn pop(q: *TaskQueue) ?*Task {
        const node = q.head orelse return null;
        q.head = node.next;
        if (q.head == null) q.tail = null;
        const t = node.task;
        alloc.destroy(node);
        return t;
    }

    fn wakeAll(q: *TaskQueue, status: i32) void {
        while (q.pop()) |t| wakeWith(t, status);
    }
};

var syncs: std.ArrayList(?*SyncObj) = .empty;
var sync_gens: std.ArrayList(u32) = .empty;

fn syncFromHandle(handle: u64, kind: ?SyncKind) ?*SyncObj {
    if (handle == 0) return null;
    const slot_plus = handle & 0xFFFF_FFFF;
    if (slot_plus == 0) return null;
    const slot: usize = @intCast(slot_plus - 1);
    if (slot >= syncs.items.len) return null;
    const o = syncs.items[slot] orelse return null;
    if (o.gen != @as(u32, @truncate(handle >> 32))) return null;
    if (o.destroyed) return null;
    if (kind) |k| {
        if (o.kind != k) return null;
    }
    return o;
}

fn syncNew(kind: SyncKind, out_handle: ?*u64) i32 {
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    const o = alloc.create(SyncObj) catch return ERR_NOMEM;
    for (syncs.items, 0..) |slot_obj, i| {
        if (slot_obj == null) {
            sync_gens.items[i] += 1;
            o.* = .{ .gen = sync_gens.items[i], .kind = kind };
            syncs.items[i] = o;
            out.* = makeHandle(i, o.gen);
            return SA_TASK_OK;
        }
    }
    o.* = .{ .gen = 1, .kind = kind };
    syncs.append(alloc, o) catch {
        alloc.destroy(o);
        return ERR_NOMEM;
    };
    sync_gens.append(alloc, 1) catch return ERR_NOMEM;
    out.* = makeHandle(syncs.items.len - 1, 1);
    return SA_TASK_OK;
}

pub export fn sa_sync_mutex_new(out_handle: ?*u64) i32 {
    return syncNew(.mutex, out_handle);
}

pub export fn sa_sync_rwlock_new(out_handle: ?*u64) i32 {
    return syncNew(.rwlock, out_handle);
}

pub export fn sa_sync_waitgroup_new(out_handle: ?*u64) i32 {
    return syncNew(.waitgroup, out_handle);
}

pub export fn sa_sync_once_new(out_handle: ?*u64) i32 {
    return syncNew(.once, out_handle);
}

pub export fn sa_sync_destroy(handle: u64) i32 {
    const o = syncFromHandle(handle, null) orelse return ERR_INVALID_HANDLE;
    o.destroyed = true;
    for (syncs.items, 0..) |slot_obj, i| {
        if (slot_obj == o) {
            syncs.items[i] = null;
            break;
        }
    }
    alloc.destroy(o);
    return SA_TASK_OK;
}

pub export fn sa_sync_mutex_lock(handle: u64) i32 {
    const o = syncFromHandle(handle, .mutex) orelse return ERR_INVALID_HANDLE;
    const me = current orelse return ERR_INVALID;
    if (o.m_owner == null) {
        o.m_owner = me;
        return SA_TASK_OK;
    }
    if (o.m_owner == me) {
        // Non-reentrant: blocking on oneself deadlocks, which the
        // driver's always-on detection reports loudly.
        o.m_queue.push(me) catch return ERR_NOMEM;
        return blockCurrent();
    }
    o.m_queue.push(me) catch return ERR_NOMEM;
    return blockCurrent();
}

pub export fn sa_sync_mutex_try_lock(handle: u64, out_acquired: ?*u32) i32 {
    const o = syncFromHandle(handle, .mutex) orelse return ERR_INVALID_HANDLE;
    const out = out_acquired orelse return ERR_INVALID;
    const me = current orelse return ERR_INVALID;
    if (o.m_owner == null) {
        o.m_owner = me;
        out.* = 1;
    } else {
        out.* = 0;
    }
    return SA_TASK_OK;
}

pub export fn sa_sync_mutex_unlock(handle: u64) i32 {
    const o = syncFromHandle(handle, .mutex) orelse return ERR_INVALID_HANDLE;
    const me = current orelse return ERR_INVALID;
    if (o.m_owner == null or o.m_owner != me) return ERR_INVALID;
    // Direct handoff: the head waiter becomes the owner before it
    // wakes, so the lock is never unowned in between (mirrors the
    // native runtime).
    if (o.m_queue.pop()) |next| {
        o.m_owner = next;
        wakeWith(next, SA_TASK_OK);
    } else {
        o.m_owner = null;
    }
    return SA_TASK_OK;
}

pub export fn sa_sync_rwlock_rlock(handle: u64) i32 {
    const o = syncFromHandle(handle, .rwlock) orelse return ERR_INVALID_HANDLE;
    const me = current orelse return ERR_INVALID;
    if (o.rw_writer == null and o.rw_wqueue.head == null) {
        o.rw_readers += 1;
        return SA_TASK_OK;
    }
    o.rw_rqueue.push(me) catch return ERR_NOMEM;
    return blockCurrent();
}

pub export fn sa_sync_rwlock_runlock(handle: u64) i32 {
    const o = syncFromHandle(handle, .rwlock) orelse return ERR_INVALID_HANDLE;
    if (o.rw_readers == 0) return ERR_INVALID;
    o.rw_readers -= 1;
    if (o.rw_readers == 0) {
        if (o.rw_wqueue.pop()) |w| {
            o.rw_writer = w;
            wakeWith(w, SA_TASK_OK);
        }
    }
    return SA_TASK_OK;
}

pub export fn sa_sync_rwlock_lock(handle: u64) i32 {
    const o = syncFromHandle(handle, .rwlock) orelse return ERR_INVALID_HANDLE;
    const me = current orelse return ERR_INVALID;
    if (o.rw_writer == null and o.rw_readers == 0 and o.rw_wqueue.head == null) {
        o.rw_writer = me;
        return SA_TASK_OK;
    }
    o.rw_wqueue.push(me) catch return ERR_NOMEM;
    return blockCurrent();
}

pub export fn sa_sync_rwlock_unlock(handle: u64) i32 {
    const o = syncFromHandle(handle, .rwlock) orelse return ERR_INVALID_HANDLE;
    const me = current orelse return ERR_INVALID;
    if (o.rw_writer == null or o.rw_writer != me) return ERR_INVALID;
    o.rw_writer = null;
    if (o.rw_wqueue.pop()) |w| {
        o.rw_writer = w;
        wakeWith(w, SA_TASK_OK);
    } else {
        // Admit every queued reader at once.
        var admitted: u32 = 0;
        while (o.rw_rqueue.pop()) |r| {
            admitted += 1;
            wakeWith(r, SA_TASK_OK);
        }
        o.rw_readers += admitted;
    }
    return SA_TASK_OK;
}

pub export fn sa_sync_waitgroup_add(handle: u64, delta: i64) i32 {
    const o = syncFromHandle(handle, .waitgroup) orelse return ERR_INVALID_HANDLE;
    o.wg_count += delta;
    if (o.wg_count < 0) coopTrap("waitgroup counter went negative");
    if (o.wg_count == 0) o.wg_queue.wakeAll(SA_TASK_OK);
    return SA_TASK_OK;
}

pub export fn sa_sync_waitgroup_done(handle: u64) i32 {
    return sa_sync_waitgroup_add(handle, -1);
}

pub export fn sa_sync_waitgroup_wait(handle: u64) i32 {
    const o = syncFromHandle(handle, .waitgroup) orelse return ERR_INVALID_HANDLE;
    if (o.wg_count == 0) return SA_TASK_OK;
    const me = current orelse return ERR_INVALID;
    o.wg_queue.push(me) catch return ERR_NOMEM;
    return blockCurrent();
}

pub export fn sa_sync_once_do(handle: u64, entry: ?*const anyopaque, arg: ?*anyopaque) i32 {
    const o = syncFromHandle(handle, .once) orelse return ERR_INVALID_HANDLE;
    if (o.once_done) return SA_TASK_OK;
    const me = current orelse return ERR_INVALID;
    if (o.once_running) {
        o.once_queue.push(me) catch return ERR_NOMEM;
        return blockCurrent();
    }
    const e = entry orelse return ERR_INVALID;
    const entry_fn: EntryFn = @ptrCast(@alignCast(e));
    o.once_running = true;
    suspend_forbidden += 1;
    entry_fn(arg);
    suspend_forbidden -= 1;
    o.once_running = false;
    o.once_done = true;
    o.once_queue.wakeAll(SA_TASK_OK);
    return SA_TASK_OK;
}

// ---------------------------------------------------------------------
// Coop protocol surface (declared in sa_std/task.sai's coop
// section; only this runtime provides these symbols).

pub export fn sa_coop_take_result(out_status: ?*i32) i32 {
    const out = out_status orelse return 0;
    const me = current orelse return 0;
    if (me.pending) |p| {
        out.* = p;
        me.pending = null;
        return 1;
    }
    return 0;
}

pub export fn sa_coop_finish() void {
    const me = current orelse coopTrap("sa_coop_finish outside a task step");
    if (me.state == .done) return;
    me.state = .done;
    me.exit_status = SA_TASK_OK;
    var woke_joiner = false;
    var it = me.joiners;
    me.joiners = null;
    me.joiners_tail = null;
    while (it) |w| {
        const next = w.next;
        wakeWith(w.task, me.exit_status);
        alloc.destroy(w);
        woke_joiner = true;
        it = next;
    }
    if (woke_joiner) me.join_delivered = true;
    reapIfReady(me);
}

pub export fn sa_coop_run_main(entry: ?*const anyopaque, arg: ?*anyopaque) i32 {
    if (driver_active) return ERR_INVALID;
    const e = entry orelse return ERR_INVALID;
    const entry_fn: EntryFn = @ptrCast(@alignCast(e));
    const root = allocTask(entry_fn, arg) catch return ERR_NOMEM;
    root.state = .ready;
    readyPush(root);
    root_task = root;
    driver_active = true;
    defer driver_active = false;
    while (true) {
        promoteTimers();
        if (root.state == .done) return SA_TASK_OK;
        const next = readyPop();
        if (next == null) {
            if (earliestDeadline()) |deadline| {
                const delta = deadline - nowNs();
                if (delta > 0) hostSleepNs(@intCast(delta));
                continue;
            }
            if (anyBlocked()) {
                std.debug.print("sa_coop: deadlock: no ready task and no pending timer, but tasks remain blocked\n", .{});
                return ERR_UNKNOWN;
            }
            // Nothing ready, nothing blocked, nothing timed, and
            // the root is not done: the root completed its last
            // step without finishing, which the step protocol
            // forbids; treat as a driver-level failure, loudly.
            std.debug.print("sa_coop: driver stalled with the root task unfinished\n", .{});
            return ERR_UNKNOWN;
        }
        const t = next.?;
        t.state = .running;
        current = t;
        t.entry(t.arg);
        current = null;
        if (t.state == .running) {
            coopTrap("coop step returned without blocking or finishing");
        }
    }
}
