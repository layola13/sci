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
pub const ERR_INVALID: i32 = 1;
pub const ERR_INVALID_HANDLE: i32 = 2;
const ERR_NOT_FOUND: i32 = 3;
pub const ERR_NOMEM: i32 = 5;
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

pub const alloc = std.heap.page_allocator;

pub fn coopTrap(comptime msg: []const u8) noreturn {
    @panic("sa_coop: " ++ msg);
}

pub fn nowNs() i64 {
    return @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
}

fn hostSleepNs(ns: u64) void {
    if (ns == 0) return;
    sio.io().sleep(.fromNanoseconds(@as(i96, @intCast(ns))), .awake) catch {};
}

// ---------------------------------------------------------------------
// Tasks and the driver

pub const Task = struct {
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
pub var current: ?*Task = null;
var root_task: ?*Task = null;
var driver_active: bool = false;
/// Set while the driver synchronously runs a sa_sync_once_do
/// entry: blocking is impossible there (the entry is a plain call
/// frame), so a block attempt traps loudly instead of corrupting
/// the once.
pub var suspend_forbidden: u32 = 0;

var ready_head: ?*ReadyNode = null;
var ready_tail: ?*ReadyNode = null;
const ReadyNode = struct {
    task: *Task,
    next: ?*ReadyNode = null,
};

var timers_head: ?*Timer = null;

pub fn makeHandle(slot: usize, gen: u32) u64 {
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
pub fn wakeWith(t: *Task, status: i32) void {
    t.pending = status;
    makeReady(t);
}

/// Suspend the current task: the caller (a blocking extern) has
/// already registered it on a wait queue or timer.
pub fn blockCurrent() i32 {
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

pub fn addTimer(deadline: i64, task: ?*Task, sel: ?*SelectReg) error{OutOfMemory}!*Timer {
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

pub const Chan = @import("sa_task_coop_chan.zig").Chan;

pub const ChanWaiter = @import("sa_task_coop_chan.zig").ChanWaiter;

pub const SelectReg = @import("sa_task_coop_chan.zig").SelectReg;


pub const chanFromHandle = @import("sa_task_coop_chan.zig").chanFromHandle;

pub const chanHandle = @import("sa_task_coop_chan.zig").chanHandle;

pub const waiterLive = @import("sa_task_coop_chan.zig").waiterLive;

pub const queuePush = @import("sa_task_coop_chan.zig").queuePush;

/// Pop the first live waiter, discarding stale select arms.
pub const queuePopLive = @import("sa_task_coop_chan.zig").queuePopLive;

pub const queueHasLive = @import("sa_task_coop_chan.zig").queueHasLive;

/// Complete a send waiter whose payload has been consumed: plain
/// waiters wake with OK; a select arm fires its registration.
pub const completeSendWaiter = @import("sa_task_coop_chan.zig").completeSendWaiter;

/// Deliver a payload to a recv waiter (plain or select arm).
pub const completeRecvWaiter = @import("sa_task_coop_chan.zig").completeRecvWaiter;

/// Fire a select registration exactly once: write the chosen
/// index/closed flag through the waiter's frame pointers and
/// deliver OK. The data movement of the chosen arm has already
/// happened (or, for a recv arm, completeRecvWaiter wrote the
/// slot before calling here).
pub const fireSelect = @import("sa_task_coop_chan.zig").fireSelect;

pub const bufPush = @import("sa_task_coop_chan.zig").bufPush;

pub const bufPop = @import("sa_task_coop_chan.zig").bufPop;

/// A receive can complete now if the buffer is non-empty, a sender
/// is waiting (rendezvous), or the channel is closed.
pub const recvReady = @import("sa_task_coop_chan.zig").recvReady;

/// A send can complete now if a receiver is waiting, the buffer
/// has room, or the channel is closed (send-on-closed traps).
pub const sendReady = @import("sa_task_coop_chan.zig").sendReady;

/// Perform a receive that is known ready. Delivery goes to
/// out_value/out_closed. Returns false only when not ready.
pub const doRecv = @import("sa_task_coop_chan.zig").doRecv;

/// Perform a send that is known ready. Returns false only when
/// not ready.
pub const doSend = @import("sa_task_coop_chan.zig").doSend;

pub const sa_chan_make = @import("sa_task_coop_chan.zig").sa_chan_make;

pub const sa_chan_destroy = @import("sa_task_coop_chan.zig").sa_chan_destroy;

pub const sa_chan_close = @import("sa_task_coop_chan.zig").sa_chan_close;

pub const sa_chan_send = @import("sa_task_coop_chan.zig").sa_chan_send;

pub const sa_chan_recv = @import("sa_task_coop_chan.zig").sa_chan_recv;

pub const sa_chan_len = @import("sa_task_coop_chan.zig").sa_chan_len;

pub const sa_chan_cap = @import("sa_task_coop_chan.zig").sa_chan_cap;

pub const sa_chan_select = @import("sa_task_coop_chan.zig").sa_chan_select;

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

pub const SyncKind = @import("sa_task_coop_sync.zig").SyncKind;

pub const SyncObj = @import("sa_task_coop_sync.zig").SyncObj;

pub const WaitNode = @import("sa_task_coop_sync.zig").WaitNode;

pub const TaskQueue = @import("sa_task_coop_sync.zig").TaskQueue;


pub const syncFromHandle = @import("sa_task_coop_sync.zig").syncFromHandle;

pub const syncNew = @import("sa_task_coop_sync.zig").syncNew;

pub const sa_sync_mutex_new = @import("sa_task_coop_sync.zig").sa_sync_mutex_new;

pub const sa_sync_rwlock_new = @import("sa_task_coop_sync.zig").sa_sync_rwlock_new;

pub const sa_sync_waitgroup_new = @import("sa_task_coop_sync.zig").sa_sync_waitgroup_new;

pub const sa_sync_once_new = @import("sa_task_coop_sync.zig").sa_sync_once_new;

pub const sa_sync_destroy = @import("sa_task_coop_sync.zig").sa_sync_destroy;

pub const sa_sync_mutex_lock = @import("sa_task_coop_sync.zig").sa_sync_mutex_lock;

pub const sa_sync_mutex_try_lock = @import("sa_task_coop_sync.zig").sa_sync_mutex_try_lock;

pub const sa_sync_mutex_unlock = @import("sa_task_coop_sync.zig").sa_sync_mutex_unlock;

pub const sa_sync_rwlock_rlock = @import("sa_task_coop_sync.zig").sa_sync_rwlock_rlock;

pub const sa_sync_rwlock_runlock = @import("sa_task_coop_sync.zig").sa_sync_rwlock_runlock;

pub const sa_sync_rwlock_lock = @import("sa_task_coop_sync.zig").sa_sync_rwlock_lock;

pub const sa_sync_rwlock_unlock = @import("sa_task_coop_sync.zig").sa_sync_rwlock_unlock;

pub const sa_sync_waitgroup_add = @import("sa_task_coop_sync.zig").sa_sync_waitgroup_add;

pub const sa_sync_waitgroup_done = @import("sa_task_coop_sync.zig").sa_sync_waitgroup_done;

pub const sa_sync_waitgroup_wait = @import("sa_task_coop_sync.zig").sa_sync_waitgroup_wait;

pub const sa_sync_once_do = @import("sa_task_coop_sync.zig").sa_sync_once_do;

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
