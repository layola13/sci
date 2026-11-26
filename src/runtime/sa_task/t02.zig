const std = @import("std");
const builtin = @import("builtin");
const Goroutine = @import("t01.zig").Goroutine;
const Mutex = @import("t01.zig").Mutex;
const NetWaiter = @import("t03.zig").NetWaiter;
const SA_TASK_OK = @import("t01.zig").SA_TASK_OK;
const SelectWaiter = @import("t03.zig").SelectWaiter;
const WaitNode = @import("t01.zig").WaitNode;
const alloc = @import("t01.zig").alloc;
const ctxSwitch = @import("t01.zig").ctxSwitch;
const futexWait = @import("t01.zig").futexWait;
const futexWake = @import("t01.zig").futexWake;
const linux = @import("t01.zig").linux;
const monotonicNs = @import("t01.zig").monotonicNs;
const netTimeoutFire = @import("t07.zig").netTimeoutFire;
const noteProgress = @import("t01.zig").noteProgress;
const selectTimeoutFire = @import("t05.zig").selectTimeoutFire;
const stackEntryLookup = @import("t01.zig").stackEntryLookup;
const stackGrowForFault = @import("t01.zig").stackGrowForFault;

pub fn segvHandler(sig: linux.SIG, info: *const linux.siginfo_t, ctx: ?*anyopaque) callconv(.c) void {
    _ = sig;
    _ = ctx;
    const addr = @intFromPtr(info.fields.sigfault.addr);
    if (stackEntryLookup(addr)) |e| {
        if (addr < e.committed_lo.load(.monotonic)) {
            // DEF-R2: a fault in this task's own reserved-but-
            // uncommitted zone is a growth event, not an
            // overflow: commit the span and return — the
            // faulting instruction re-executes against the
            // now-RW pages.
            if (stackGrowForFault(e, addr)) return;
            // Growth refused (hard guard = cap exceeded, or the
            // commit syscall failed): the loud overflow trap.
            // Format "sa_task: goroutine <id> stack overflow
            // (task stack cap reached)\n" without any libc/alloc
            // calls.
            const id = e.id;
            var buf: [128]u8 = undefined;
            const prefix = "sa_task: goroutine ";
            const suffix = " stack overflow (task stack cap reached)\n";
            @memcpy(buf[0..prefix.len], prefix);
            var n = prefix.len;
            var v = id;
            var digits: [20]u8 = undefined;
            var dn: usize = 0;
            if (v == 0) {
                digits[0] = '0';
                dn = 1;
            } else {
                while (v > 0) : (v /= 10) {
                    digits[dn] = @intCast('0' + (v % 10));
                    dn += 1;
                }
            }
            var i: usize = 0;
            while (i < dn) : (i += 1) {
                buf[n] = digits[dn - 1 - i];
                n += 1;
            }
            @memcpy(buf[n .. n + suffix.len], suffix);
            n += suffix.len;
            _ = linux.write(2, &buf, n);
            std.process.abort();
        }
    }
    // Not one of ours: restore the default disposition and re-raise
    // by returning — the faulting instruction re-executes and the
    // process dies with the original signal.
    var act: linux.Sigaction = .{
        .handler = .{ .handler = null }, // null == SIG_DFL
        .mask = std.mem.zeroes(linux.sigset_t),
        .flags = 0,
    };
    _ = linux.sigaction(.SEGV, &act, null);
}

pub var segv_installed: bool = false;

pub fn installSegvHandler() void {
    if (segv_installed) return;
    segv_installed = true;
    var act: std.posix.Sigaction = .{
        .handler = .{ .sigaction = &segvHandler },
        .mask = std.mem.zeroes(std.posix.sigset_t),
        .flags = @as(c_ulong, std.posix.SA.SIGINFO | std.posix.SA.ONSTACK),
    };
    std.posix.sigaction(std.posix.SIG.SEGV, &act, null);
}

pub fn installAltStack() void {
    const size = 64 * 1024;
    const mem = alloc.alloc(u8, size) catch return;
    var ss: linux.stack_t = .{ .sp = mem.ptr, .flags = 0, .size = size };
    _ = linux.sigaltstack(&ss, null);
}

// ---------------------------------------------------------------------
// Scheduler.
pub const Carrier = struct {
    sched_sp: u64 = 0,
    runq: [256]*Goroutine = undefined,
    runq_head: usize = 0,
    // sched-wake batch: queue length as an atomic hint. All
    // array-slot updates still happen under runq_mu (push/pop/
    // steal); only the length read in the steal scan is
    // lock-free, and it is a heuristic re-checked under the
    // lock in stealHalf, so a stale read cannot misdirect a
    // steal. This removes one lock acquisition per victim per
    // idle scan (findWork used to lock every victim just to
    // read its length).
    runq_len: std.atomic.Value(usize) = .init(0),
    runq_mu: Mutex = .{},
    // sched-wake batch: single runnext hot slot. Only the
    // owning carrier writes/reads it (via runq_mu); it is
    // never stolen. A woken goroutine placed here runs next
    // on this carrier, giving back-to-back handoffs same-core
    // locality instead of queueing behind unrelated work.
    runnext: ?*Goroutine = null,
    current: ?*Goroutine = null,
    thread: ?std.Thread = null,
    /// Exit handoff: the exiting goroutine (running on this
    /// carrier) deposits its stack region here just before its
    /// final switch; the carrier frees it after regaining
    /// control. Carrier-local, so no recycling race can alias it.
    exit_region: ?[]align(4096) u8 = null,
    /// Task 118 (kernel 3): slot index of this carrier (set in
    /// initScheduler). The idle-backoff sleep is staggered by
    /// slot so carriers do not all re-enter the poll loop
    /// simultaneously.
    idx: usize = 0,
    /// Task 118 (kernel 3): consecutive carrierMain passes that
    /// found no work in any findWork call or the bounded spin.
    /// Reset when the carrier runs a goroutine (runGoroutine);
    /// reaching DEFAULT_IDLE_BACKOFF_PASSES triggers the bounded
    /// idle backoff instead of another futexWait.
    empty_passes: u32 = 0,

    fn push(c: *Carrier, g: *Goroutine) bool {
        c.runq_mu.lock();
        defer c.runq_mu.unlock();
        const len = c.runq_len.load(.acquire);
        if (len >= c.runq.len) return false;
        c.runq[(c.runq_head + len) % c.runq.len] = g;
        c.runq_len.store(len + 1, .release);
        return true;
    }

    pub fn pop(c: *Carrier) ?*Goroutine {
        c.runq_mu.lock();
        defer c.runq_mu.unlock();
        if (c.runq_len.load(.acquire) == 0) return null;
        const g = c.runq[c.runq_head];
        c.runq_head = (c.runq_head + 1) % c.runq.len;
        _ = c.runq_len.fetchSub(1, .acq_rel);
        return g;
    }

    /// Owner-only hot slot: the next goroutine this carrier
    /// runs, ahead of its queue. Never stolen by other
    /// carriers; consumed by findWork before the queue.
    pub fn popRunnext(c: *Carrier) ?*Goroutine {
        c.runq_mu.lock();
        defer c.runq_mu.unlock();
        const g = c.runnext orelse return null;
        c.runnext = null;
        return g;
    }

    pub fn runq_len_snapshot(c: *Carrier) usize {
        // Lock-free by design (see runq_len comment): a
        // heuristic for the steal scan only.
        return c.runq_len.load(.acquire);
    }

    pub fn stealHalf(c: *Carrier, victim: *Carrier) ?*Goroutine {
        // Caller guarantees c's own queue is empty (findWork only
        // steals after its own pop failed), so pushes cannot fill
        // it: at most 127 of 256 slots are taken from a victim.
        victim.runq_mu.lock();
        defer victim.runq_mu.unlock();
        const vlen = victim.runq_len.load(.acquire);
        if (vlen < 2) return null;
        const take = vlen / 2;
        var first: ?*Goroutine = null;
        var i: usize = 0;
        while (i < take) : (i += 1) {
            const g = victim.runq[victim.runq_head];
            victim.runq_head = (victim.runq_head + 1) % victim.runq.len;
            _ = victim.runq_len.fetchSub(1, .acq_rel);
            if (first == null) {
                first = g;
            } else {
                std.debug.assert(c.push(g));
            }
        }
        return first;
    }
};

pub var sched_mu: Mutex = .{};

pub var carriers: []Carrier = &.{};

pub var global_runq_head: ?*Goroutine = null;

pub var global_runq_tail: ?*Goroutine = null;

pub var live_count: std.atomic.Value(usize) = .init(0);

pub var wake_word: std.atomic.Value(u32) = .init(0);

// DEF-SLA-RUNTIME-TIMER-THREAD-WAKE-STEAL: the dedicated timer
// thread sleeps on its OWN futex word, never on wake_word. It
// used to share wake_word with the carriers, but wakeDemand's
// nudge is quota-sized (min(n, idle_carriers) — carriers only),
// so the timer thread could consume the single nudge an enqueue
// aimed at the one idle carrier; a carrier whose futexWait has
// no deadline from its own view (no timer armed, no net waiter,
// deadlock guard unarmed) then slept forever with runnable work
// queued (cap-0 rendezvous loops wedged with every thread parked
// in futex_wait and zero CPU). Only timerAdd bumps this word:
// the timer thread's waits are already bounded by the next
// deadline and a 10 ms cap, so no other path needs to reach it.
pub var timer_wake_word: std.atomic.Value(u32) = .init(0);

// sched-wake batch: carriers currently parked in futexWait
// in carrierMain. Maintained only around the sleep section:
// incremented before the last pre-sleep findWork check,
// decremented when the carrier wakes or finds work instead.
// Enqueuers read it to size the futex nudge; it is a hint,
// not a gate — the wake_word bump below is the real signal
// (a carrier that computed its wait value before the bump
// returns from futexWait immediately), so a stale read
// cannot strand work.
pub var idle_carriers: std.atomic.Value(usize) = .init(0);

pub var deadlock_armed: std.atomic.Value(bool) = .init(false);

pub threadlocal var current_g: ?*Goroutine = null;

pub threadlocal var carrier_self: ?*Carrier = null;

/// Wake discipline (sched-wake batch, replaces wake-all).
/// Every enqueue bumps wake_word first (release): that bump is
/// what a sleeping carrier's futexWait compares against, so no
/// enqueue can be missed. The futex nudge itself goes only to
/// idle carriers, one per demand unit: the old code woke ALL
/// sleeping carriers per enqueue (measured enqueue segment
/// 26-29 us, worse at zero contention when carriers are
/// genuinely asleep). Busy carriers need no nudge — they drain
/// queues in their own loop before sleeping.
pub fn wakeDemand(n: usize) void {
    _ = wake_word.fetchAdd(1, .release);
    const idle = idle_carriers.load(.acquire);
    if (idle == 0) return;
    futexWake(&wake_word, @intCast(@min(n, idle)));
}

pub fn wakeCarriers() void {
    // Timer-arm and init paths: waking one idle carrier
    // suffices — the woken carrier re-evaluates deadlines on
    // its next loop pass (timer case) or enters its loop
    // (init case). The old "wake all, coarse but rare" comment
    // on timerAdd stays true in the weaker form: at least one
    // carrier is guaranteed to re-evaluate, which is what the
    // stranded-timer race required.
    wakeDemand(1);
}

pub fn wakeTimerThread() void {
    // The timer thread is the only waiter on timer_wake_word, so
    // a quota of one is exact — no carrier can steal this nudge
    // and it cannot steal a carrier nudge in return.
    _ = timer_wake_word.fetchAdd(1, .release);
    futexWake(&timer_wake_word, 1);
}

pub fn globalPush(g: *Goroutine) void {
    sched_mu.lock();
    g.qnext = null;
    if (global_runq_tail) |t| {
        t.qnext = g;
    } else {
        global_runq_head = g;
    }
    global_runq_tail = g;
    sched_mu.unlock();
}

pub fn globalPop() ?*Goroutine {
    sched_mu.lock();
    defer sched_mu.unlock();
    const g = global_runq_head orelse return null;
    global_runq_head = g.qnext;
    if (global_runq_head == null) global_runq_tail = null;
    g.qnext = null;
    return g;
}

pub fn enqueueRunnable(g: *Goroutine) void {
    enqueueWake(g, true);
}

pub fn enqueueWake(g: *Goroutine, wake: bool) void {
    noteProgress();
    if (carrier_self) |c| {
        if (c.push(g)) {
            if (wake) wakeDemand(1);
            return;
        }
    }
    globalPush(g);
    if (wake) wakeDemand(1);
}

/// Wake enqueue with runnext preference. When the waker runs
/// on a carrier, the woken goroutine is offered that carrier's
/// single runnext slot first, so a back-to-back handoff runs
/// next on the same core instead of queueing behind unrelated
/// work. A runnext placement needs no futex nudge at all: the
/// owning carrier consumes it at its next findWork before it
/// can sleep. Falls back to the normal queue when the slot is
/// busy or the waker is not on a carrier. The deferred requeue
/// path in runGoroutine deliberately does NOT use this: a
/// just-run goroutine must not cut back in front of the queue.
pub fn enqueueWakeNext(g: *Goroutine, wake: bool) void {
    noteProgress();
    if (carrier_self) |c| {
        c.runq_mu.lock();
        if (c.runnext == null) {
            c.runnext = g;
            c.runq_mu.unlock();
            return;
        }
        c.runq_mu.unlock();
    }
    enqueueWake(g, wake);
}

/// Transition a parked goroutine back to runnable. Only the first
/// waker wins; later ones observe state != parked and do nothing.
/// If the goroutine is still switching out (transition), the wake
/// is recorded and the carrier completes it after the switch.
/// Returns true iff the goroutine was actually enqueued (batch
/// callers use this to size the single trailing wake).
pub fn unpark(g: *Goroutine) void {
    _ = unparkWake(g, true);
}

pub fn unparkNoWake(g: *Goroutine) bool {
    return unparkWake(g, false);
}

pub fn unparkWake(g: *Goroutine, wake: bool) bool {
    sched_mu.lock();
    if (g.state.load(.acquire) != .parked) {
        sched_mu.unlock();
        return false;
    }
    if (g.transition) {
        g.unpark_pending = true;
        sched_mu.unlock();
        return false;
    }
    g.state.store(.runnable, .release);
    sched_mu.unlock();
    enqueueWakeNext(g, wake);
    return true;
}

/// WaitNode recycling. A blocking plain chan send/recv allocates
/// its wait node from the page allocator and the peer that fires
/// it releases it in fireNode: one mmap/munmap pair per park, on
/// the goroutine handoff path every request walks (slaredis's
/// per-command floor family; same tax the select path stopped
/// paying in the wake batch). The lifetime discipline already
/// guarantees exactly-once release: a node sits in exactly one
/// wait queue, the claimer unlinks it under the owning lock
/// before firing, and the fire-all paths unlink as they go --
/// the same envelope that makes destroying it safe today makes
/// pooling it safe. Select nodes never pass through fireNode
/// (claimed via selectTryClaim, freed by their owner), so the
/// pool only ever holds plain chan / join / sync nodes; join and
/// sync nodes are still created raw and are simply donated into
/// the pool when fireNode releases them. Every allocation site
/// fully reinitializes the node (`node.* = .{...}`) before
/// linking it anywhere, and waitNodeAlloc zeroes on top, so no
/// stale field can survive a cycle. Stack residence (the select
/// nodes' treatment) is NOT sound here: the peer fires and
/// releases the node, potentially while the owner resumes on
/// another carrier and reuses its stack frame -- the heap node's
/// lifetime is exactly what makes the peer-side release sound.
pub const WAIT_NODE_POOL_MAX: usize = 256;

pub var wait_node_pool_mu: Mutex = .{};

pub var wait_node_pool_head: ?*WaitNode = null;

pub var wait_node_pool_len: usize = 0;

pub fn waitNodeAlloc() ?*WaitNode {
    wait_node_pool_mu.lock();
    if (wait_node_pool_head) |node| {
        wait_node_pool_head = node.pool_next;
        wait_node_pool_len -= 1;
        wait_node_pool_mu.unlock();
        node.* = .{};
        return node;
    }
    wait_node_pool_mu.unlock();
    const node = alloc.create(WaitNode) catch return null;
    node.* = .{};
    return node;
}

pub fn waitNodeRelease(node: *WaitNode) void {
    wait_node_pool_mu.lock();
    if (wait_node_pool_len < WAIT_NODE_POOL_MAX) {
        node.pool_next = wait_node_pool_head;
        wait_node_pool_head = node;
        wait_node_pool_len += 1;
        wait_node_pool_mu.unlock();
        return;
    }
    wait_node_pool_mu.unlock();
    alloc.destroy(node);
}

pub fn fireNode(node: *WaitNode, status: i32) void {
    if (node.g) |g| {
        g.wake_status = status;
        unpark(g);
    }
    if (node.os) |os| {
        os.status = status;
        os.fire();
    }
    waitNodeRelease(node);
}

// ---------------------------------------------------------------------
// Timers (sleep + select/net timeouts). Binary heap by deadline.
pub const TimerTarget = union(enum) {
    g: *Goroutine,
    sel: *SelectWaiter,
    net: *NetWaiter,
};

pub const TimerEntry = struct {
    deadline: i64,
    seq: u64,
    target: TimerTarget,
    gen: u64,

    fn lessThan(_: void, a: TimerEntry, b: TimerEntry) std.math.Order {
        if (a.deadline != b.deadline) return std.math.order(a.deadline, b.deadline);
        return std.math.order(a.seq, b.seq);
    }
};

pub var timer_mu: Mutex = .{};

pub var timer_heap: std.PriorityQueue(TimerEntry, void, TimerEntry.lessThan) = .initContext({});

pub var timer_seq: u64 = 0;

pub fn timerAdd(deadline: i64, target: TimerTarget, gen: u64) bool {
    timer_mu.lock();
    timer_seq += 1;
    timer_heap.push(alloc, .{ .deadline = deadline, .seq = timer_seq, .target = target, .gen = gen }) catch {
        timer_mu.unlock();
        return false;
    };
    timer_mu.unlock();
    // An idle carrier may already have computed its futex wait
    // from the previous heap state — including "no timers, wait
    // indefinitely". Without this wake, a freshly armed timer
    // (a select timeout on an otherwise idle system) could be
    // stranded forever; this race hung the select timeout test
    // intermittently. Sched-wake note: wakeCarriers() now wakes
    // one idle carrier (plus the wake_word bump, which covers
    // carriers that computed their wait value early). One woken
    // carrier suffices: it recomputes its deadline and fires
    // timers on its next loop pass, which is exactly what the
    // stranded-timer race required — waking all was coarse
    // but never load-bearing.
    wakeCarriers();
    // The dedicated timer thread no longer shares wake_word
    // (DEF-SLA-RUNTIME-TIMER-THREAD-WAKE-STEAL): nudge it on its
    // private word so it re-evaluates the heap now instead of at
    // its 10 ms wait cap — above all when the new entry is the
    // earliest deadline.
    wakeTimerThread();
    return true;
}

pub fn timerNextDeadline() ?i64 {
    timer_mu.lock();
    defer timer_mu.unlock();
    if (timer_heap.peek()) |e| return e.deadline;
    return null;
}

pub fn fireTimers() void {
    const now = monotonicNs();
    var expired: std.ArrayList(TimerEntry) = .empty;
    defer expired.deinit(alloc);
    timer_mu.lock();
    while (timer_heap.peek()) |e| {
        if (e.deadline > now) break;
        expired.append(alloc, timer_heap.pop().?) catch break;
    }
    timer_mu.unlock();
    // Batch wake: fire all expired timers without a futex
    // nudge each, then one demand-sized wake at the end.
    var fired: usize = 0;
    for (expired.items) |e| {
        switch (e.target) {
            .g => |g| {
                if (g.state.load(.acquire) == .parked and g.wait_kind == .sleep and g.park_gen == e.gen) {
                    g.wake_status = SA_TASK_OK;
                    if (unparkNoWake(g)) fired += 1;
                }
            },
            .sel => |sel| selectTimeoutFire(sel, e.gen),
            .net => |nw| netTimeoutFire(nw, e.gen),
        }
    }
    if (fired > 0) wakeDemand(fired);
}

/// DEF-SLA-RUNTIME-CARRIER-LIVELOCK (timer starvation): the
/// dedicated timer thread. Carrier-side timer service is gated
/// on a null findWork() in carrierMain, and moving the call to
/// the carrier loop top does not fix it either (tested: the
/// wedge persists at the baseline signature): when carriers are
/// trapped inside runGoroutine behind goroutines that neither
/// park through the scheduler nor exit (futex churn in channel
/// ops), no carrier ever reaches any fireTimers() call site, and
/// a goroutine parked in a timed select starves with its
/// deadline long past (minim8-256 writer: 100 ms select timer
/// expired ~28 s, never fired). This thread's only job is
/// fireTimers(); its service is independent of carrier progress.
/// It sleeps on timer_wake_word — its private futex word —
/// until the next deadline: timerAdd bumps that word via
/// wakeTimerThread(), so a timer armed after the sleep begins
/// either changes the word before the futex wait (which then
/// returns immediately) or is picked up within the wait cap
/// (10 ms, the same cap carrierMain applies to net waiters).
/// Sharing the carriers' wake_word instead let this thread eat
/// quota-sized carrier nudges (DEF-SLA-RUNTIME-TIMER-THREAD-
/// WAKE-STEAL). All fire paths are already safe from a
/// non-carrier thread: enqueueWake/enqueueWakeNext fall back to
/// the global queue when carrier_self is null, and the timer
/// heap is mutex-guarded against carrier-side fireTimers()
/// calls.
pub fn timerMain() void {
    var observed = timer_wake_word.load(.acquire);
    while (true) {
        fireTimers();
        var timeout_ns: u64 = 10 * std.time.ns_per_ms;
        if (timerNextDeadline()) |d| {
            const delta = d - monotonicNs();
            if (delta <= 0) {
                timeout_ns = 0;
            } else if (delta < timeout_ns) {
                timeout_ns = @intCast(delta);
            }
        }
        // DEF-134-FUTEX: same re-check as carrierMain. A timerAdd
        // bump in the fireTimers/deadline window would make this
        // wait return EAGAIN at once, and a zero timeout (deadline
        // already past) can only return at once. Skip the syscall
        // and re-poll; when the word moved, adopt the fresh value
        // so the next wait compares correctly (fireTimers at the
        // loop top services any newly armed timer).
        if (timeout_ns == 0) continue;
        const cur = timer_wake_word.load(.acquire);
        if (cur != observed) {
            observed = cur;
            continue;
        }
        futexWait(&timer_wake_word, observed, timeout_ns);
        observed = timer_wake_word.load(.acquire);
    }
}

// ---------------------------------------------------------------------
// Core goroutine context operations (called on a goroutine stack).
pub fn switchToCarrier(g: *Goroutine) void {
    const c = carrier_self orelse unreachable;
    ctxSwitch(&g.sp, c.sched_sp);
}

/// Two-phase park, required for wakeup safety: a blocking
/// primitive registers its wait node under its own lock, then —
/// STILL holding that lock — calls parkBegin, which marks the
/// goroutine parked. Only then may the lock be released and
/// parkSwitch called. Any waker needs the primitive's lock to
/// fire the node, so it either fires before registration (and
/// the primitive's state check catches it) or after parkBegin
/// (and sees state == parked, so the wake is recorded even if
/// the actual switch has not happened yet). A one-phase park
/// has a lost-wakeup window between registration and the state
/// store; that window deadlocked channel sends under load.
pub fn parkBeginLocked(g: *Goroutine) void {
    g.transition = true;
    g.state.store(.parked, .release);
}

pub fn parkBegin() void {
    const g = current_g orelse unreachable;
    sched_mu.lock();
    parkBeginLocked(g);
    sched_mu.unlock();
}

pub fn parkSwitch() void {
    const g = current_g orelse unreachable;
    noteProgress();
    switchToCarrier(g);
    // Resumed by unpark + carrier dispatch.
}

pub fn parkCurrent() void {
    parkBegin();
    parkSwitch();
}

/// Undo a parkBegin when the wait completed before the switch
/// (e.g. a select case claimed during registration).
pub fn parkCancel() void {
    const g = current_g orelse unreachable;
    sched_mu.lock();
    g.transition = false;
    g.unpark_pending = false;
    g.state.store(.running, .release);
    sched_mu.unlock();
}
