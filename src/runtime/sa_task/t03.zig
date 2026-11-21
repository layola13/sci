const std = @import("std");
const builtin = @import("builtin");
const Carrier = @import("t02.zig").Carrier;
const ERR_INVALID = @import("t01.zig").ERR_INVALID;
const ERR_INVALID_HANDLE = @import("t01.zig").ERR_INVALID_HANDLE;
const ERR_NOMEM = @import("t01.zig").ERR_NOMEM;
const ERR_UNSUPPORTED = @import("t01.zig").ERR_UNSUPPORTED;
const EntryFn = @import("t01.zig").EntryFn;
const Goroutine = @import("t01.zig").Goroutine;
const MonitorSub = @import("t01.zig").MonitorSub;
const Mutex = @import("t01.zig").Mutex;
const OsWaiter = @import("t01.zig").OsWaiter;
const SA_TASK_OK = @import("t01.zig").SA_TASK_OK;
const SA_TASK_TRAPPED = @import("t01.zig").SA_TASK_TRAPPED;
const TrapSinkFn = @import("t01.zig").TrapSinkFn;
const alloc = @import("t01.zig").alloc;
const allocStack = @import("t01.zig").allocStack;
const carriers = @import("t02.zig").carriers;
const cfg_carriers = @import("t01.zig").cfg_carriers;
const cfg_idle_backoff_ns = @import("t01.zig").cfg_idle_backoff_ns;
const cfg_idle_backoff_passes = @import("t01.zig").cfg_idle_backoff_passes;
const cfg_stack_cap = @import("t01.zig").cfg_stack_cap;
const cfg_stack_initial = @import("t01.zig").cfg_stack_initial;
const chanLookup = @import("t04.zig").chanLookup;
const chanRelease = @import("t05.zig").chanRelease;
const chanTrySend = @import("t05.zig").chanTrySend;
const ctxResume = @import("t01.zig").ctxResume;
const ctxSwitch = @import("t01.zig").ctxSwitch;
const deadlock_armed = @import("t02.zig").deadlock_armed;
const enqueueRunnable = @import("t02.zig").enqueueRunnable;
const external_blocked = @import("t01.zig").external_blocked;
const fireNode = @import("t02.zig").fireNode;
const fireTimers = @import("t02.zig").fireTimers;
const freeStack = @import("t01.zig").freeStack;
const futexWait = @import("t01.zig").futexWait;
const globalPop = @import("t02.zig").globalPop;
const global_runq_head = @import("t02.zig").global_runq_head;
const idle_carriers = @import("t02.zig").idle_carriers;
const initStackFrame = @import("t01.zig").initStackFrame;
const installAltStack = @import("t02.zig").installAltStack;
const installSegvHandler = @import("t02.zig").installSegvHandler;
const last_progress_ns = @import("t01.zig").last_progress_ns;
const linux = @import("t01.zig").linux;
const live_count = @import("t02.zig").live_count;
const monotonicNs = @import("t01.zig").monotonicNs;
const netWaiterCount = @import("t07.zig").netWaiterCount;
const noteProgress = @import("t01.zig").noteProgress;
const pollNetOnce = @import("t07.zig").pollNetOnce;
const processTrap = @import("t01.zig").processTrap;
const reapIfReadyLocked = @import("t01.zig").reapIfReadyLocked;
const registryAlloc = @import("t01.zig").registryAlloc;
const registryLookup = @import("t01.zig").registryLookup;
const registryRecycle = @import("t01.zig").registryRecycle;
const registry_mu = @import("t01.zig").registry_mu;
const sa_task_ctx_arm = @import("t01.zig").sa_task_ctx_arm;
const sched_mu = @import("t02.zig").sched_mu;
const sleepNs = @import("t01.zig").sleepNs;
const supported = @import("t01.zig").supported;
const switchToCarrier = @import("t02.zig").switchToCarrier;
const timerMain = @import("t02.zig").timerMain;
const timerNextDeadline = @import("t02.zig").timerNextDeadline;
const wakeCarriers = @import("t02.zig").wakeCarriers;
const wake_word = @import("t02.zig").wake_word;

pub fn deliverMonitor(sub: *MonitorSub, watched: u64, trapped: bool, trap_code: i32) void {
    const ch = chanLookup(sub.chan_handle) orelse return;
    defer chanRelease(ch);
    const code: u64 = if (trapped) @bitCast(@as(i64, trap_code)) else 0;
    ch.mu.lock();
    _ = chanTrySend(ch, .{ .a = watched, .b = code });
    ch.mu.unlock();
}

pub fn goroutineExit() noreturn {
    const g = current_g orelse unreachable;
    // Fire join waiters.
    sched_mu.lock();
    const waiters = g.join_waiters;
    g.join_waiters = null;
    // Monitor subscriptions snapshot under the same lock that
    // publishes .done: a registration that misses this snapshot
    // observes .done and delivers immediately, so every
    // subscription is delivered exactly once.
    const subs = g.monitors;
    g.monitors = null;
    g.state.store(.done, .release);
    sched_mu.unlock();
    // Deposit the stack with our carrier for post-switch freeing
    // (the struct may be recycled only after that handoff).
    if (carrier_self) |c| c.exit_region = g.region;
    // Decrement BEFORE waking joiners: once a join returns, the
    // goroutine must already be out of the live count.
    _ = live_count.fetchSub(1, .seq_cst);
    noteProgress();
    // Monitor delivery: after the trap record is final, before
    // join waiters fire (DESIGN/monitor contract).
    var sub = subs;
    while (sub) |s| {
        const next_sub = s.next;
        deliverMonitor(s, g.handle(), g.trapped, g.trap_code);
        alloc.destroy(s);
        sub = next_sub;
    }
    var n = waiters;
    while (n) |node| {
        const next = node.next;
        fireNode(node, if (g.trapped) SA_TASK_TRAPPED else SA_TASK_OK);
        n = next;
    }
    switchToCarrier(g);
    unreachable;
}

pub fn trampoline() callconv(.c) void {
    const g = current_g orelse processTrap("trampoline without a current goroutine");
    // Arm the boundary rescue frame BEFORE running user code: a
    // runtime trap inside the goroutine resumes this frame (the
    // arm call re-emerges returning 1) instead of unwinding. The
    // arm call is made directly from this frame on purpose: the
    // captured rsp/rip are this frame's.
    g.rescue_armed = true;
    if (sa_task_ctx_arm(&g.rescue) == 0) {
        g.entry(g.arg);
        goroutineExit();
    }
    g.rescue_armed = false;
    // Boundary catch segment (reached via raiseTrap).
    if (g.trap_sink) |sink| {
        sink(g.handle(), g.trap_code, g.trap_msg[0..].ptr, @intCast(g.trap_msg_len), g.trap_ctx);
    } else {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "goroutine {d} trap {d}: {s}", .{ g.handle(), g.trap_code, g.trap_msg[0..g.trap_msg_len] }) catch "goroutine trap";
        processTrap(msg);
    }
    goroutineExit();
}

/// Raise a runtime trap in the current goroutine: record it and
/// switch to the boundary rescue context. Outside a goroutine
/// this is the plain process trap.
pub fn raiseTrap(code: i32, msg: []const u8) noreturn {
    if (current_g) |g| {
        if (g.rescue_armed) {
            g.trap_code = code;
            const n = @min(msg.len, g.trap_msg.len);
            @memcpy(g.trap_msg[0..n], msg[0..n]);
            g.trap_msg_len = n;
            g.trapped = true;
            ctxResume(&g.rescue, 1);
        }
    }
    processTrap(msg);
}

/// Zig-level registration of a boundary trap sink for the current
/// goroutine (the extern registration surface is reserved for the
/// SLA syntax batch; see module header).
pub fn setTrapSink(sink: ?TrapSinkFn, ctx: ?*anyopaque) void {
    if (current_g) |g| {
        g.trap_sink = sink;
        g.trap_ctx = ctx;
    }
}

// ---------------------------------------------------------------------
// Carrier main loop.
pub fn findWork(c: *Carrier) ?*Goroutine {
    if (c.popRunnext()) |g| return g;
    if (c.pop()) |g| return g;
    if (globalPop()) |g| return g;
    // Steal: start from a rotating victim to spread load.
    const start = @as(usize, @intCast(monotonicNs())) % @max(carriers.len, 1);
    var i: usize = 0;
    while (i < carriers.len) : (i += 1) {
        const v = &carriers[(start + i) % carriers.len];
        if (v == c) continue;
        if (v.runq_len_snapshot() > 1) {
            if (c.stealHalf(v)) |g| return g;
        }
    }
    return null;
}

pub fn runGoroutine(c: *Carrier, g: *Goroutine) void {
    g.state.store(.running, .release);
    c.empty_passes = 0;
    c.current = g;
    current_g = g;
    ctxSwitch(&c.sched_sp, g.sp);
    current_g = null;
    c.current = null;
    // The goroutine has fully switched out; complete any deferred
    // wake/requeue recorded during its switch-out window.
    var requeue = false;
    sched_mu.lock();
    if (g.transition) {
        g.transition = false;
        if (g.state.load(.acquire) == .parked and g.unpark_pending) {
            g.unpark_pending = false;
            g.state.store(.runnable, .release);
            requeue = true;
        } else if (g.yield_requeue) {
            g.yield_requeue = false;
            requeue = true;
        }
    }
    sched_mu.unlock();
    if (requeue) enqueueRunnable(g);
    if (c.exit_region) |region| {
        c.exit_region = null;
        // The stack (the expensive part) is freed at exit; the
        // completion record stays in the registry until a join
        // consumes it. Marking the handoff complete may release
        // a reap that a join already requested.
        freeStack(region);
        registry_mu.lock();
        g.exit_handed_off = true;
        // A reap a join already requested completes here; a
        // detached record (DEF-R1) is reaped here unconditionally
        // — no join will ever consume it.
        if (g.reap_requested or g.detached) reapIfReadyLocked(g);
        registry_mu.unlock();
    }
}

pub fn runnableTotal() usize {
    var total: usize = 0;
    for (carriers) |*c| total += c.runq_len_snapshot();
    sched_mu.lock();
    var n = global_runq_head;
    while (n) |g| {
        total += 1;
        n = g.qnext;
    }
    sched_mu.unlock();
    return total;
}

/// Quiescence predicate behind the deadlock guard: live
/// goroutines exist, none is runnable, no timer is pending, no
/// network waiter is parked, no external (non-goroutine) caller
/// is blocked inside a runtime call, and no progress has been
/// made for the grace window.
pub fn systemQuiescent() bool {
    if (live_count.load(.acquire) == 0) return false;
    if (runnableTotal() != 0) return false;
    if (timerNextDeadline() != null) return false;
    if (netWaiterCount() != 0) return false;
    if (external_blocked.load(.acquire) != 0) return false;
    const since = monotonicNs() - last_progress_ns.load(.acquire);
    return since >= 250 * std.time.ns_per_ms;
}

pub fn deadlockCheck() void {
    if (!deadlock_armed.load(.acquire)) return;
    if (!systemQuiescent()) return;
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "deadlock: all {d} goroutines are parked (guard armed)", .{live_count.load(.acquire)}) catch "deadlock";
    processTrap(msg);
}

pub fn carrierMain(c: *Carrier) void {
    carrier_self = c;
    installAltStack();
    while (true) {
        if (findWork(c)) |g| {
            runGoroutine(c, g);
            continue;
        }
        fireTimers();
        pollNetOnce();
        if (findWork(c)) |g| {
            runGoroutine(c, g);
            continue;
        }
        deadlockCheck();
        const w = wake_word.load(.acquire);
        // Mark idle BEFORE the last pre-sleep findWork check:
        // an enqueuer that observes idle>0 wakes one sleeper,
        // and an enqueuer that observes idle==0 still cannot
        // strand us — either its item predates our findWork
        // check (we pick it up) or its wake_word bump postdates
        // our snapshot w (futexWait returns immediately).
        _ = idle_carriers.fetchAdd(1, .acq_rel);
        if (findWork(c)) |g| {
            _ = idle_carriers.fetchSub(1, .acq_rel);
            runGoroutine(c, g);
            continue;
        }
        var timeout_ns: ?u64 = null;
        if (timerNextDeadline()) |d| {
            const delta = d - monotonicNs();
            timeout_ns = if (delta <= 0) 0 else @intCast(delta);
        }
        if (netWaiterCount() != 0) {
            const cap: u64 = 10 * std.time.ns_per_ms;
            timeout_ns = if (timeout_ns) |t| @min(t, cap) else cap;
        }
        if (deadlock_armed.load(.acquire)) {
            // The quiescence predicate includes a 250 ms
            // no-progress grace window, but an idle carrier
            // with no timers and no net waiters would otherwise
            // sleep indefinitely and never re-evaluate it after
            // the window lapses — the armed guard could never
            // fire in a real process (a subprocess scenario
            // caught this; the unit tests poll the predicate
            // from the test thread, which masked it). Bound the
            // wait while armed so carriers re-check.
            const cap: u64 = 50 * std.time.ns_per_ms;
            timeout_ns = if (timeout_ns) |t| @min(t, cap) else cap;
        }
        if (cfg_idle_backoff_ns > 0 and c.empty_passes >= cfg_idle_backoff_passes) {
            // Bounded idle backoff (task 118, kernel 3): this
            // carrier has been woken N times in a row and found
            // nothing — the work went to another carrier. Sleep
            // for a bounded, bump-insensitive interval instead of
            // going back to futexWait, which returns immediately
            // on the next wake_word bump and re-polls findWork
            // (3 sched_mu takes) without doing useful work. The
            // sleep is capped by any pending timer/net/deadlock
            // deadline so timers are not delayed. A genuine
            // enqueue is still picked up promptly: the carrier
            // that just ran work spins for it, and any carrier
            // in futexWait wakes on the bump; this carrier
            // re-polls at the loop top when its sleep ends.
            // Durations are staggered by carrier slot so the
            // carriers do not all re-enter the poll loop
            // simultaneously.
            const base_ns = cfg_idle_backoff_ns;
            const stagger_ns = base_ns / 2 * @as(u64, @intCast(c.idx % 3));
            var sleep_ns: u64 = base_ns + stagger_ns;
            if (timeout_ns) |t| sleep_ns = @min(sleep_ns, t);
            sleepNs(sleep_ns);
            c.empty_passes = 0;
            _ = idle_carriers.fetchSub(1, .acq_rel);
            continue;
        }
        c.empty_passes += 1;
        futexWait(&wake_word, w, timeout_ns);
        _ = idle_carriers.fetchSub(1, .acq_rel);
    }
}

// ---------------------------------------------------------------------
// Lazy scheduler init.
pub var init_state: std.atomic.Value(u32) = .init(0);

pub fn ensureInit() bool {
    if (!supported) return false;
    const s = init_state.load(.acquire);
    if (s == 2) return true;
    if (init_state.cmpxchgStrong(0, 1, .acq_rel, .acquire) == null) {
        initScheduler();
        init_state.store(2, .release);
        wakeCarriers();
        return true;
    }
    while (init_state.load(.acquire) != 2) std.Thread.yield() catch {};
    return true;
}

pub fn envUsize(name: []const u8) ?usize {
    // Read /proc/self/environ directly: this module deliberately
    // avoids libc std.process helpers so it stays linkable in any
    // consumer of the archive and testable standalone.
    const fd_rc = linux.openat(linux.AT.FDCWD, "/proc/self/environ", .{ .ACCMODE = .RDONLY }, 0);
    if (@as(isize, @bitCast(fd_rc)) < 0) return null;
    const fd: linux.fd_t = @intCast(fd_rc);
    defer _ = linux.close(fd);
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alloc);
    var chunk: [4096]u8 = undefined;
    while (true) {
        const rc = linux.read(fd, &chunk, chunk.len);
        if (@as(isize, @bitCast(rc)) < 0) return null;
        if (rc == 0) break;
        buf.appendSlice(alloc, chunk[0..rc]) catch return null;
        if (buf.items.len > (1 << 20)) break;
    }
    const data = buf.items;
    var it = std.mem.splitScalar(u8, data, 0);
    while (it.next()) |entry| {
        const eq = std.mem.indexOfScalar(u8, entry, '=') orelse continue;
        if (std.mem.eql(u8, entry[0..eq], name)) {
            return std.fmt.parseInt(usize, entry[eq + 1 ..], 10) catch null;
        }
    }
    return null;
}

pub fn initScheduler() void {
    if (envUsize("SA_TASK_STACK_KIB")) |kib| {
        // DEF-R2: initial commit per task (see the stack
        // allocation section for the redefinition note).
        const clamped = std.math.clamp(kib, 64, 8192);
        cfg_stack_initial = clamped * 1024;
    }
    if (envUsize("SA_TASK_STACK_CAP_KIB")) |kib| {
        const clamped = std.math.clamp(kib, 1024, 1024 * 1024);
        cfg_stack_cap = clamped * 1024;
    }
    if (cfg_stack_cap < cfg_stack_initial) cfg_stack_cap = cfg_stack_initial;
    const cpu = std.Thread.getCpuCount() catch 1;
    var want = envUsize("SA_TASK_CARRIERS") orelse cpu;
    want = std.math.clamp(want, 1, 128);
    cfg_carriers = want;
    if (envUsize("SA_TASK_IDLE_BACKOFF_NS")) |ns| {
        cfg_idle_backoff_ns = ns;
    }
    if (envUsize("SA_TASK_IDLE_BACKOFF_PASSES")) |n| {
        cfg_idle_backoff_passes = @intCast(@min(n, 1_000_000));
    }
    carriers = alloc.alloc(Carrier, want) catch processTrap("sa_task: out of memory starting scheduler");
    for (carriers) |*c| c.* = .{};
    installSegvHandler();
    noteProgress();
    for (carriers, 0..) |*c, i| {
        c.idx = i;
        c.thread = std.Thread.spawn(.{}, carrierMain, .{c}) catch processTrap("sa_task: cannot spawn carrier thread");
        if (c.thread) |t| t.detach();
    }
    // Timer service must not depend on carrier progress (see
    // timerMain): one dedicated thread for the process lifetime.
    const timer_thread = std.Thread.spawn(.{}, timerMain, .{}) catch processTrap("sa_task: cannot spawn timer thread");
    timer_thread.detach();
}

// ---------------------------------------------------------------------
// Phase B/C shared wait objects (defined here; their fire/poll
// implementations land in the channel and sync/net sections).
pub const SelectWaiter = struct {
    mu: Mutex = .{},
    claimed: bool = false,
    chosen: i64 = -1, // case index, -1 default taken, -2 timeout
    closed_result: bool = false,
    owner_g: ?*Goroutine = null,
    owner_os: ?*OsWaiter = null,
    wake_status: i32 = SA_TASK_OK,
    gen: u64 = 0,
    // Refcounted because a timeout timer may still hold the
    // pointer after the owner has woken and cleaned up.
    refs: std.atomic.Value(u32) = .init(1),
    pool_next: ?*SelectWaiter = null, // selectAlloc free list
};

pub const NetWaiter = struct {
    next: ?*NetWaiter = null,
    g: ?*Goroutine = null,
    os: ?*OsWaiter = null,
    handle: u64 = 0,
    interest: u32 = 0,
    ready_out: ?*u32 = null,
    status: i32 = SA_TASK_OK,
    gen: u64 = 0,
    linked: bool = false,
    done: bool = false,
    // Refcounted because a timeout timer may hold the pointer
    // after the owner has woken and returned.
    refs: std.atomic.Value(u32) = .init(1),
};

// netTimeoutFire / pollNetOnce / netWaiterCount are implemented
// in the Phase C section at the end of this file.
// ---------------------------------------------------------------------
// Entry validation (DEF-SCI-HOST-JOIN-COMPLETED-SEGFAULT,
// re-adjudicated 2026-11-17): a task entry must be a callable
// machine address. An SA fn value's bits are the address of its
// vtable record (data); the callable address lives in vtable
// slot 0, and correct callers pass the loaded slot (the SLA
// extern-argument plan does exactly that load + cast). A caller
// that passes the vtable address itself -- e.g. hand-written SA
// `entry = &VT; call @sa_task_spawn(*entry, ...)` -- used to start
// the goroutine on a data address: the trampoline jumped into a
// non-executable page and the whole process died with SIGSEGV at
// whatever synchronization point came next (join, sleep, recv),
// which made the crash look like a defect in that point. Reject
// a non-executable entry at the entry-taking calls with
// ERR_INVALID instead -- the same loud channel as a null entry.
// The executable-range set comes from /proc/self/maps, is cached
// after the first read, and is re-read once on a miss (a mapping
// created after the snapshot -- a JIT buffer, a late dlopen -- is
// then honored). If the maps file cannot be read at all, the
// cached set stays empty and entries are accepted: the check
// guards against a known-invalid shape, it must not make spawn
// unusable in restricted environments.
pub const ExecRange = struct { lo: usize, hi: usize };

pub var exec_ranges_mu: Mutex = .{};

pub var exec_ranges: []ExecRange = &.{};

pub var exec_ranges_loaded: bool = false;

pub fn loadExecRangesLocked() void {
    // Caller holds exec_ranges_mu. Rebuilds the cached set from
    // /proc/self/maps; on any failure the previous set is kept.
    const fd_rc = linux.openat(linux.AT.FDCWD, "/proc/self/maps", .{ .ACCMODE = .RDONLY }, 0);
    if (@as(isize, @bitCast(fd_rc)) < 0) return;
    const fd: linux.fd_t = @intCast(fd_rc);
    defer _ = linux.close(fd);
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alloc);
    var chunk: [8192]u8 = undefined;
    while (true) {
        const rc = linux.read(fd, &chunk, chunk.len);
        if (@as(isize, @bitCast(rc)) < 0) return;
        if (rc == 0) break;
        buf.appendSlice(alloc, chunk[0..rc]) catch return;
        if (buf.items.len > (1 << 22)) break;
    }
    var ranges: std.ArrayList(ExecRange) = .empty;
    var lines = std.mem.splitScalar(u8, buf.items, '\n');
    while (lines.next()) |line| {
        // Format: "<lo>-<hi> <perms> <off> <dev> <inode> [path]";
        // perms is the second field and its third char is 'x'.
        const dash = std.mem.indexOfScalar(u8, line, '-') orelse continue;
        const lo = std.fmt.parseInt(usize, line[0..dash], 16) catch continue;
        const sp1 = std.mem.indexOfScalarPos(u8, line, dash, ' ') orelse continue;
        const hi = std.fmt.parseInt(usize, line[dash + 1 .. sp1], 16) catch continue;
        const sp2 = std.mem.indexOfScalarPos(u8, line, sp1 + 1, ' ') orelse continue;
        const perms = line[sp1 + 1 .. sp2];
        if (perms.len < 3 or perms[2] != 'x') continue;
        ranges.append(alloc, .{ .lo = lo, .hi = hi }) catch {
            ranges.deinit(alloc);
            return;
        };
    }
    if (exec_ranges.len > 0) alloc.free(exec_ranges);
    exec_ranges = ranges.toOwnedSlice(alloc) catch {
        ranges.deinit(alloc);
        return;
    };
}

pub fn entryInExecRanges(addr: usize) bool {
    for (exec_ranges) |r| {
        if (addr >= r.lo and addr < r.hi) return true;
    }
    return false;
}

pub fn entryIsExecutable(entry: EntryFn) bool {
    const addr = @intFromPtr(entry);
    exec_ranges_mu.lock();
    defer exec_ranges_mu.unlock();
    if (!exec_ranges_loaded) {
        loadExecRangesLocked();
        exec_ranges_loaded = true;
    }
    if (entryInExecRanges(addr)) return true;
    loadExecRangesLocked();
    if (entryInExecRanges(addr)) return true;
    return exec_ranges.len == 0;
}

// ---------------------------------------------------------------------
// Phase A externs: spawn / yield / sleep / join / current.
pub export fn sa_task_spawn(entry: ?*const anyopaque, arg: ?*anyopaque, out_handle: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    const e: EntryFn = @ptrCast(@alignCast(entry orelse return ERR_INVALID));
    if (!entryIsExecutable(e)) return ERR_INVALID;
    if (!ensureInit()) return ERR_UNSUPPORTED;
    const g = registryAlloc(e, arg) orelse return ERR_NOMEM;
    const region = allocStack(g.handle()) orelse {
        g.state.store(.done, .release);
        registryRecycle(g, g.gen);
        return ERR_NOMEM;
    };
    g.region = region;
    initStackFrame(g);
    _ = live_count.fetchAdd(1, .seq_cst);
    noteProgress();
    out.* = g.handle();
    enqueueRunnable(g);
    return SA_TASK_OK;
}

/// Builtin record-only trap sink selected when a supervised
/// spawn passes a null sink: the trap stays in the goroutine's
/// record for join + sa_task_trap_info; the process lives.
pub fn recordOnlySink(_: u64, _: i32, _: [*]const u8, _: u64, _: ?*anyopaque) callconv(.c) void {}

/// Supervised spawn (companion for the SLA goroutine syntax
/// batch): like sa_task_spawn, but the goroutine's boundary trap
/// sink is registered at creation. A trapped supervised
/// goroutine records {code, message} and exits; sa_task_join
/// returns SA_TASK_TRAPPED and HOLDS the record (repeated joins
/// keep returning SA_TASK_TRAPPED) until sa_task_trap_info
/// consumes it.
pub export fn sa_task_spawn_supervised(entry: ?*const anyopaque, arg: ?*anyopaque, sink: ?*const anyopaque, sink_ctx: ?*anyopaque, out_handle: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    const e: EntryFn = @ptrCast(@alignCast(entry orelse return ERR_INVALID));
    if (!entryIsExecutable(e)) return ERR_INVALID;
    if (!ensureInit()) return ERR_UNSUPPORTED;
    const g = registryAlloc(e, arg) orelse return ERR_NOMEM;
    if (sink) |s| {
        g.trap_sink = @ptrCast(@alignCast(s));
    } else {
        g.trap_sink = &recordOnlySink;
    }
    g.trap_ctx = sink_ctx;
    const region = allocStack(g.handle()) orelse {
        g.state.store(.done, .release);
        registryRecycle(g, g.gen);
        return ERR_NOMEM;
    };
    g.region = region;
    initStackFrame(g);
    _ = live_count.fetchAdd(1, .seq_cst);
    noteProgress();
    out.* = g.handle();
    enqueueRunnable(g);
    return SA_TASK_OK;
}

/// Read back a supervised goroutine's trap record after a join
/// returned SA_TASK_TRAPPED: fills the trap code and a pointer
/// to the recorded message (the pointer borrows the record;
/// copy the bytes before any further spawn or join), then
/// CONSUMES the record — the handle becomes invalid.
pub export fn sa_task_trap_info(handle: u64, out_code: ?*i32, out_msg_ptr: ?*?*const u8, out_msg_len: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const oc = out_code orelse return ERR_INVALID;
    const omp = out_msg_ptr orelse return ERR_INVALID;
    const oml = out_msg_len orelse return ERR_INVALID;
    const g = registryLookup(handle) orelse return ERR_INVALID_HANDLE;
    if (g.detached) return ERR_INVALID_HANDLE;
    // The consume decision and the consume itself are one
    // critical section (DEF-TASK-MONITOR-REAP-RACE): a bare-field
    // read of trap_consumed outside sched_mu races goroutineExit,
    // whose monitor delivery passes through this window on a
    // freshly exited record (trap_held still false, consume not
    // yet visible) — a monitor subscribing under sched_mu in
    // that gap read trap_consumed == false and resurrected the
    // exit as a fresh delivery instead of reporting
    // ERR_INVALID_HANDLE. sched_mu is the scheduler lock every
    // consumer of the exit fact already takes (goroutineExit's
    // .done publication and monitor list snapshot, join's parked
    // registration); the trap-record fields are only ever
    // written under it or by the goroutine itself before the
    // .done store, so reading them under it is race-free.
    sched_mu.lock();
    if (g.state.load(.acquire) != .done) {
        sched_mu.unlock();
        return ERR_INVALID;
    }
    // Done but no held trap record (clean exit, already consumed,
    // or never held by a TRAPPED join): for this API the handle
    // has no record to give, which the handle-validity family
    // reports as ERR_INVALID_HANDLE — the same answer a fully
    // reaped handle gets from registryLookup above.
    if (g.trap_consumed or !g.trapped or !g.trap_held) {
        sched_mu.unlock();
        return ERR_INVALID_HANDLE;
    }
    oc.* = g.trap_code;
    omp.* = @as(*const u8, @ptrCast(g.trap_msg[0..].ptr));
    oml.* = @intCast(g.trap_msg_len);
    // Consume the record NOW, on the record itself. The slot reap
    // inside registryRecycle is two-phase: while the exit
    // handoff is still pending it only requests the reap and the
    // slot stays lookup-able with `trapped` set (a later join
    // still reads the exit fact from it). trap_consumed is what
    // makes the handle invalid from this point on.
    g.trap_consumed = true;
    g.trap_held = false;
    sched_mu.unlock();
    registryRecycle(g, g.gen);
    return SA_TASK_OK;
}
