//! sa_std goroutine runtime (sala 13_goroutine_runtime, phase 1).
//!
//! Go-style goroutines as an sa_std runtime core: the SA spec itself
//! is unchanged (frozen base); everything here is a library surface
//! of externs declared in sa_std/task.sai. Scope ruled by Jev
//! (2026-10-29, goroutine_scope_ruling.json):
//!   S1 fixed virtual stacks + guard page + explicit trap on
//!      overflow; NO copying stack growth in this phase.
//!   S2 cooperative preemption only: yield points are the explicit
//!      sa_task_yield extern plus every blocking runtime call; a
//!      compute-bound goroutine that never reaches a yield point
//!      can starve its carrier thread — documented, not silent.
//!   S5 x86_64 Linux only. Other targets return
//!      SA_STD_ERR_UNSUPPORTED from every entry point. wasm note:
//!      goroutines are possible on wasm in principle (Go's own wasm
//!      port proves it, via Asyncify / compiler stack transforms /
//!      stack-switching proposals), but this phase's mechanism —
//!      native stack-pointer switching — does not lower to wasm;
//!      wasm needs its own lowering track and reports UNSUPPORTED
//!      here. That is a mechanism difference, not a principled
//!      impossibility.
//!
//! Contracts registered explicitly (no silent degradation):
//!   - A blocking file syscall or a blocking FFI/extern call made
//!     inside a goroutine blocks its carrier OS thread for the
//!     duration. The scheduler does not compensate in this phase;
//!     callers that need many blocked threads must size carriers
//!     accordingly (SA_TASK_CARRIERS).
//!   - Network waits go through sa_task_net_wait, which parks the
//!     goroutine and lets the scheduler poll via the existing
//!     sa_std_net_poll_wait face; network I/O never needs to block
//!     a carrier.
//!   - Stack overflow is a loud trap: a SIGSEGV handler registered
//!     by the runtime recognizes goroutine guard pages, prints
//!     "sa_task: goroutine <id> stack overflow" and aborts. It is
//!     NOT boundary-recoverable in this phase (the stack is gone);
//!     boundary recover (below) covers runtime-raised traps only.
//!   - Deadlock guard: OFF by default, armed explicitly with
//!     sa_task_deadlock_guard_arm. Reason: threads that are not
//!     goroutines (e.g. a host main thread between API calls) are
//!     invisible to the scheduler, so an always-on detector could
//!     fire while an external participant is about to make
//!     progress. Arming is the program's declaration that all
//!     participants are goroutines or blocked inside a runtime
//!     call. When armed and the whole system is quiescent (live
//!     goroutines all parked, no timers, no net waiters, no
//!     external blocked callers) past the grace window, the
//!     runtime prints a deadlock trap and aborts — Go parity.
//!   - Goroutine structs are pooled and recycled by the registry;
//!     stacks (the expensive part) are unmapped at exit. A handle
//!     is (generation, slot) encoded; using a handle after its
//!     goroutine was reaped and the slot recycled returns
//!     SA_STD_ERR_INVALID_HANDLE.
//!
//! Boundary trap catch point (reserved for the SLA syntax batch's
//! goroutine-boundary panic/recover supervision semantics): every
//! goroutine runs under trampoline(), which arms a rescue context
//! (rescue_sp) before invoking user entry. Runtime-raised traps
//! (send on closed channel, negative WaitGroup counter, ...)
//! call raiseTrap(), which records {code, message} in the
//! Goroutine and switches back to the rescue context instead of
//! unwinding: the boundary then invokes the goroutine's trap
//! sink if one is registered, or performs the default process
//! trap (stderr + abort) when none is. The sink is a per-goroutine
//! function pointer (Goroutine.trap_sink) — settable from Zig
//! today (setTrapSink below, exercised by unit tests); the extern
//! registration surface (spawn-supervised + sa_task_trap_info
//! read-back after join) is the reserved API shape for the syntax
//! batch and lands with it, so the runtime does not need rework.
//!
//! Monitor reservation (Erlang-style exit notification, adopted
//! per Jev erl_candidates 0.81; runtime half reserved into v1 at
//! 0.58): goroutineExit() is the single convergence point of the
//! goroutine lifecycle — normal return and boundary trap both end
//! there, after the trap record is final and before join waiters
//! fire. That is the production point for exit notifications: a
//! monitor subscription registered on a goroutine would have its
//! notification (handle, exit kind, trap code) enqueued to the
//! subscriber's channel at exactly that point, deliverable through
//! ordinary channel/select waits. The delivery point needs no
//! scheduler surgery, so v1 only reserves the shape: the SLA
//! syntax batch adds the subscription surface (spawn-monitored +
//! a monitor registration extern mirroring the trap-sink shape);
//! no monitor extern ships in this phase.
//!
//! Context-style cancellation convention (std idiom over this
//! surface, no extra mechanism): a cancellation signal is an
//! ordinary sa_chan channel with capacity 0 that is closed to
//! broadcast "done"; closing wakes every blocked receiver and
//! every select case waiting on it, so a Done channel can be
//! selected on alongside work channels and passed down a call
//! chain. Cancellation is cooperative: receivers observe it at
//! channel/select points only.
//!
//! Status codes mirror sa_std.zig (SA_STD_*): OK=0,
//! INVALID_ARGUMENT=1, INVALID_HANDLE=2, NOT_FOUND=3,
//! NO_MEMORY=5, UNSUPPORTED=8, UNKNOWN=127. One task-local code:
//! SA_TASK_TRAPPED=100 is returned by sa_task_join when the
//! goroutine exited through the boundary trap with a sink
//! registered (details live in the goroutine's trap record).

const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

pub const supported = builtin.cpu.arch == .x86_64 and builtin.os.tag == .linux;

pub const SA_TASK_OK: i32 = 0;
pub const SA_TASK_TRAPPED: i32 = 100;
const ERR_INVALID: i32 = 1;
const ERR_INVALID_HANDLE: i32 = 2;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;
const ERR_UNSUPPORTED: i32 = 8;
const ERR_UNKNOWN: i32 = 127;

// Trap codes recorded in Goroutine.trap_code (boundary recover).
pub const SA_TASK_TRAP_SEND_ON_CLOSED: i32 = 1;
pub const SA_TASK_TRAP_WAITGROUP_NEGATIVE: i32 = 2;
pub const SA_TASK_TRAP_INTERNAL: i32 = 3;

const alloc = std.heap.page_allocator;

// ---------------------------------------------------------------------
// Small futex-based primitives (self-contained: no Io, no libc deps
// beyond syscalls, so this module also tests standalone).

const Mutex = struct {
    state: std.atomic.Value(u32) = .init(0),

    fn lock(m: *Mutex) void {
        if (m.state.cmpxchgStrong(0, 1, .acquire, .monotonic) == null) return;
        while (true) {
            const s = m.state.swap(2, .acquire);
            if (s == 0) return;
            futexWait(&m.state, 2, null);
        }
    }

    fn tryLock(m: *Mutex) bool {
        return m.state.cmpxchgStrong(0, 1, .acquire, .monotonic) == null;
    }

    fn unlock(m: *Mutex) void {
        const prev = m.state.swap(0, .release);
        if (prev == 2) futexWake(&m.state, 1);
    }
};

fn futexWait(word: *std.atomic.Value(u32), expect: u32, timeout_ns: ?u64) void {
    if (!supported) return;
    var ts: linux.timespec = undefined;
    var ts_ptr: ?*const linux.timespec = null;
    if (timeout_ns) |ns| {
        ts = .{
            .sec = @intCast(@divTrunc(ns, std.time.ns_per_s)),
            .nsec = @intCast(@mod(ns, std.time.ns_per_s)),
        };
        ts_ptr = &ts;
    }
    _ = linux.futex_4arg(@ptrCast(&word.raw), .{ .cmd = .WAIT, .private = true }, expect, ts_ptr);
}

fn futexWake(word: *std.atomic.Value(u32), n: u32) void {
    if (!supported) return;
    _ = linux.futex_3arg(@ptrCast(&word.raw), .{ .cmd = .WAKE, .private = true }, @intCast(n));
}

/// A blocking wait slot for OS threads (non-goroutine callers).
const OsWaiter = struct {
    word: std.atomic.Value(u32) = .init(0),
    status: i32 = SA_TASK_OK,

    fn wait(os: *OsWaiter) void {
        _ = external_blocked.fetchAdd(1, .seq_cst);
        defer _ = external_blocked.fetchSub(1, .seq_cst);
        while (os.word.load(.acquire) == 0) futexWait(&os.word, 0, null);
    }

    fn fire(os: *OsWaiter) void {
        os.word.store(1, .release);
        futexWake(&os.word, 1);
    }
};

var external_blocked: std.atomic.Value(usize) = .init(0);
var last_progress_ns: std.atomic.Value(i64) = .init(0);

fn noteProgress() void {
    last_progress_ns.store(monotonicNs(), .release);
}

fn monotonicNs() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * std.time.ns_per_s + ts.nsec;
}

// ---------------------------------------------------------------------
// x86_64 context primitives. The assembly lives in
// src/runtime/sa_task_ctx.s (see that file for why it is not Zig
// naked functions: the Zig 0.17 self-hosted backend segfaults
// linking artifacts where a naked function is reachable from an
// exported symbol). Frame layout: 6 callee-saved registers are
// pushed/popped by the switch; the return-address slot is
// consumed by `ret`.

/// Boundary rescue frame: the snapshot DATA lives here, in the
/// Goroutine struct — never on the stack. (A stack-resident
/// snapshot is recycled by the trampoline's deeper calls before
/// any trap fires; this was found by frame dump: the saved return
/// slot read back as 0.) Only rsp/rip VALUES are captured.
/// Layout is fixed by sa_task_ctx.s: rsp, rip, then
/// r15,r14,r13,r12,rbx,rbp.
pub const RescueFrame = extern struct {
    rsp: u64 = 0, // rsp in the arming frame after the arm call returns
    rip: u64 = 0, // return address into the arming frame
    regs: [6]u64 = std.mem.zeroes([6]u64), // r15,r14,r13,r12,rbx,rbp
};

extern fn sa_task_ctx_switch(old_sp: *u64, new_sp: u64) void;
extern fn sa_task_ctx_arm(frame: *RescueFrame) u64;
extern fn sa_task_ctx_resume(frame: *const RescueFrame, val: u64) noreturn;

fn ctxSwitch(old: *u64, new: u64) void {
    sa_task_ctx_switch(old, new);
}

fn ctxResume(frame: *const RescueFrame, val: u64) noreturn {
    sa_task_ctx_resume(frame, val);
}

fn stackUnderflowTrap() callconv(.c) noreturn {
    processTrap("goroutine entry returned past its trampoline (stack underflow)");
}

// ---------------------------------------------------------------------
// Goroutine + registry.

pub const EntryFn = *const fn (?*anyopaque) callconv(.c) void;
pub const TrapSinkFn = *const fn (handle: u64, code: i32, msg_ptr: [*]const u8, msg_len: u64, ctx: ?*anyopaque) callconv(.c) void;

const State = enum(u8) { empty, runnable, running, parked, done };

const WaitKind = enum(u8) {
    none,
    join,
    sleep,
    chan_send,
    chan_recv,
    select,
    mutex,
    rwlock,
    waitgroup,
    once,
    net,
};

const Goroutine = struct {
    slot: u32 = 0,
    gen: u32 = 0,
    entry: EntryFn = undefined,
    arg: ?*anyopaque = null,
    // stack bookkeeping
    region: []align(4096) u8 = undefined,
    sp: u64 = 0,
    state: std.atomic.Value(State) = .init(.empty),
    queued: bool = false, // guarded by sched_mu
    qnext: ?*Goroutine = null, // guarded by the owning queue's lock
    wait_kind: WaitKind = .none,
    wake_status: i32 = SA_TASK_OK,
    park_gen: u64 = 0,
    // Switch-out handshake (guarded by sched_mu): while a
    // goroutine is between "marked parked/runnable" and its
    // context actually being saved by the carrier, wakers must
    // not enqueue it — another carrier would resume it from a
    // stale sp. unpark() during the window sets unpark_pending;
    // the carrier completes the enqueue after the switch.
    transition: bool = false,
    unpark_pending: bool = false,
    yield_requeue: bool = false,
    // join
    join_waiters: ?*WaitNode = null, // guarded by sched_mu
    // boundary trap catch point (see module header)
    rescue: RescueFrame = .{},
    rescue_armed: bool = false,
    trap_sink: ?TrapSinkFn = null,
    trap_ctx: ?*anyopaque = null,
    trapped: bool = false,
    trap_code: i32 = 0,
    trap_msg: [160]u8 = std.mem.zeroes([160]u8),
    trap_msg_len: usize = 0,
    // SLA goroutine syntax batch (companion): set when a join has
    // reported SA_TASK_TRAPPED for a supervised goroutine; the
    // record then stays un-recycled until sa_task_trap_info
    // consumes it.
    trap_held: bool = false,
    // Set by sa_task_trap_info when it consumes the trap record.
    // The slot's own reap is two-phase and may lag the consume
    // (registryRecycle only requests the reap while the exit
    // handoff is pending), so consumption is recorded on the
    // record itself: later trap_info / join calls observe it and
    // report ERR_INVALID_HANDLE instead of replaying the record.
    trap_consumed: bool = false,
    // Monitor subscriptions (companion): channels to notify at
    // goroutineExit; list head guarded by sched_mu.
    monitors: ?*MonitorSub = null,
    // lifecycle: two-phase reap. A join that observes .done only
    // sets reap_requested; the slot is actually recycled by the
    // carrier AFTER the exit handoff completes (final switch done
    // + stack freed). Recycling earlier would let a respawn
    // overwrite this goroutine's sp/region while its own exit
    // sequence is still executing on its stack.
    exit_handed_off: bool = false,
    reap_requested: bool = false,
    reaped: bool = false, // completion record consumed by a join

    fn handle(g: *const Goroutine) u64 {
        return (@as(u64, g.gen) << 32) | @as(u64, g.slot);
    }
};

/// One monitor subscription (companion): a channel handle to
/// deliver the watched goroutine's exit message to. Allocated at
/// sa_task_monitor, freed at delivery (goroutineExit or the
/// immediate already-exited path).
const MonitorSub = struct {
    chan_handle: u64 = 0,
    next: ?*MonitorSub = null,
};

const WaitNode = struct {
    next: ?*WaitNode = null,
    g: ?*Goroutine = null,
    os: ?*OsWaiter = null,
    // channel payload slots (phase B): send reads from slot,
    // recv writes into slot.
    slot: ?*Slot = null,
    fired: bool = false,
    recv_closed: bool = false,
    // select registration (phase B)
    sel: ?*SelectWaiter = null,
    sel_index: u32 = 0,
    linked: bool = false, // currently in a channel wait queue
    // sync primitives (phase C): ownership key of the waiter
    // (mutex handoff transfers ownership to the head waiter) and
    // a kind-specific flag (rwlock: 1 = writer).
    owner_key: u64 = 0,
    flag: u32 = 0,
};

pub const Slot = extern struct { a: u64 = 0, b: u64 = 0 };

var registry_mu: Mutex = .{};
var registry_slots: std.ArrayList(?*Goroutine) = .empty;
var registry_free: std.ArrayList(u32) = .empty;

fn registryAlloc(entry: EntryFn, arg: ?*anyopaque) ?*Goroutine {
    registry_mu.lock();
    defer registry_mu.unlock();
    var g: *Goroutine = undefined;
    if (registry_free.pop()) |idx| {
        g = registry_slots.items[idx].?;
        g.gen +%= 1;
        if (g.gen == 0) g.gen = 1;
    } else {
        g = alloc.create(Goroutine) catch return null;
        g.* = .{};
        g.slot = @intCast(registry_slots.items.len);
        g.gen = 1;
        registry_slots.append(alloc, g) catch {
            alloc.destroy(g);
            return null;
        };
    }
    g.entry = entry;
    g.arg = arg;
    g.state.store(.runnable, .release);
    g.queued = false;
    g.qnext = null;
    g.wait_kind = .none;
    g.wake_status = SA_TASK_OK;
    g.join_waiters = null;
    g.rescue = .{};
    g.rescue_armed = false;
    g.trap_sink = null;
    g.trap_ctx = null;
    g.trapped = false;
    g.trap_code = 0;
    g.trap_msg_len = 0;
    g.trap_held = false;
    g.trap_consumed = false;
    g.monitors = null;
    g.exit_handed_off = false;
    g.reap_requested = false;
    g.reaped = false;
    g.transition = false;
    g.unpark_pending = false;
    g.yield_requeue = false;
    return g;
}

fn registryLookup(handle: u64) ?*Goroutine {
    const idx: u32 = @truncate(handle);
    const gen: u32 = @truncate(handle >> 32);
    registry_mu.lock();
    defer registry_mu.unlock();
    if (idx >= registry_slots.items.len) return null;
    const g = registry_slots.items[idx] orelse return null;
    if (g.gen != gen) return null;
    if (g.state.load(.acquire) == .empty) return null;
    return g;
}

/// Consume a finished goroutine's completion record: the slot
/// becomes reusable (generation bumps on the next alloc). Called
/// by sa_task_join once it has observed the done state — a join
/// therefore CONSUMES the handle; joining the same handle again
/// reports INVALID_HANDLE. Unjoined completions keep a small
/// record (the struct; the stack is freed at exit regardless),
/// exactly like zombie processes wait for wait().
fn registryRecycle(g: *Goroutine, gen: u32) void {
    registry_mu.lock();
    defer registry_mu.unlock();
    if (g.gen != gen) return; // slot already recycled and reused
    if (g.reaped) return;
    if (g.state.load(.acquire) != .done) return;
    if (!g.exit_handed_off) {
        // The exiting carrier has not finished the handoff; it
        // completes the reap after the final switch (see
        // runGoroutine). Registering the request is enough.
        g.reap_requested = true;
        return;
    }
    g.reaped = true;
    g.state.store(.empty, .release);
    registry_free.append(alloc, g.slot) catch {};
}

// ---------------------------------------------------------------------
// Stack allocation: [guard PROT_NONE][usable RW], grows down.

pub const DEFAULT_STACK_USABLE_KIB: u64 = 256;
pub const GUARD_KIB: u64 = 64;

var cfg_stack_usable: usize = DEFAULT_STACK_USABLE_KIB * 1024;
var cfg_carriers: usize = 0;

fn allocStack(id: u64) ?[]align(4096) u8 {
    const total = cfg_stack_usable + GUARD_KIB * 1024;
    const rc = linux.mmap(null, total, linux.PROT{ .READ = true, .WRITE = true }, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    if (@as(isize, @bitCast(rc)) < 0) return null;
    const base: [*]align(4096) u8 = @ptrFromInt(rc);
    // Guard: lowest GUARD_KIB becomes PROT_NONE.
    const grc = linux.mprotect(base, GUARD_KIB * 1024, linux.PROT{});
    if (@as(isize, @bitCast(grc)) < 0) {
        _ = linux.munmap(base, total);
        return null;
    }
    guardRegister(@intFromPtr(base), @intFromPtr(base) + GUARD_KIB * 1024, id);
    return base[0..total];
}

fn freeStack(region: []align(4096) u8) void {
    guardUnregister(@intFromPtr(region.ptr));
    _ = linux.munmap(region.ptr, region.len);
}

fn initStackFrame(g: *Goroutine) void {
    const top = (@intFromPtr(g.region.ptr) + g.region.len) & ~@as(usize, 15);
    const frame: [*]u64 = @ptrFromInt(top - 8 * 8);
    frame[0] = 0; // r15
    frame[1] = 0; // r14
    frame[2] = 0; // r13
    frame[3] = 0; // r12
    frame[4] = 0; // rbx
    frame[5] = 0; // rbp
    frame[6] = @intFromPtr(&trampoline); // ret target on first switch
    frame[7] = @intFromPtr(&stackUnderflowTrap); // trampoline's own return slot
    g.sp = @intFromPtr(frame);
}

// Guard registry for the SIGSEGV overflow trap: fixed table,
// lock-free reads from the signal handler.
const GUARD_SLOTS = 16384;
const GuardEntry = struct {
    live: std.atomic.Value(bool) = .init(false),
    lo: usize = 0,
    hi: usize = 0,
    id: u64 = 0,
};
var guard_table: [GUARD_SLOTS]GuardEntry = std.mem.zeroes([GUARD_SLOTS]GuardEntry);
var guard_hint: std.atomic.Value(usize) = .init(0);

fn guardRegister(lo: usize, hi: usize, id: u64) void {
    var i: usize = 0;
    while (i < GUARD_SLOTS) : (i += 1) {
        const idx = (guard_hint.load(.monotonic) + i) % GUARD_SLOTS;
        if (guard_table[idx].live.cmpxchgStrong(false, true, .acq_rel, .monotonic) == null) {
            guard_table[idx].lo = lo;
            guard_table[idx].hi = hi;
            guard_table[idx].id = id;
            guard_hint.store(idx + 1, .monotonic);
            return;
        }
    }
}

fn guardUnregister(lo: usize) void {
    for (&guard_table) |*e| {
        if (e.live.load(.acquire) and e.lo == lo) {
            e.live.store(false, .release);
            return;
        }
    }
}

fn guardLookup(addr: usize) ?u64 {
    for (&guard_table) |*e| {
        if (e.live.load(.acquire) and addr >= e.lo and addr < e.hi) return e.id;
    }
    return null;
}

// ---------------------------------------------------------------------
// Process-level trap (default boundary) + SIGSEGV overflow trap.

fn writeStderr(text: []const u8) void {
    _ = linux.write(2, text.ptr, text.len);
}

fn processTrap(msg: []const u8) noreturn {
    writeStderr("sa_task: fatal: ");
    writeStderr(msg);
    writeStderr("\n");
    std.process.abort();
}

fn segvHandler(sig: linux.SIG, info: *const linux.siginfo_t, ctx: ?*anyopaque) callconv(.c) void {
    _ = sig;
    _ = ctx;
    const addr = @intFromPtr(info.fields.sigfault.addr);
    if (guardLookup(addr)) |id| {
        // Format "sa_task: goroutine <id> stack overflow (fixed stack,
        // no growth in this phase)\n" without any libc/alloc calls.
        var buf: [128]u8 = undefined;
        const prefix = "sa_task: goroutine ";
        const suffix = " stack overflow (fixed stack, no growth in this phase)\n";
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

var segv_installed: bool = false;

fn installSegvHandler() void {
    if (segv_installed) return;
    segv_installed = true;
    var act: std.posix.Sigaction = .{
        .handler = .{ .sigaction = &segvHandler },
        .mask = std.mem.zeroes(std.posix.sigset_t),
        .flags = @as(c_ulong, std.posix.SA.SIGINFO | std.posix.SA.ONSTACK),
    };
    std.posix.sigaction(std.posix.SIG.SEGV, &act, null);
}

fn installAltStack() void {
    const size = 64 * 1024;
    const mem = alloc.alloc(u8, size) catch return;
    var ss: linux.stack_t = .{ .sp = mem.ptr, .flags = 0, .size = size };
    _ = linux.sigaltstack(&ss, null);
}

// ---------------------------------------------------------------------
// Scheduler.

const Carrier = struct {
    sched_sp: u64 = 0,
    runq: [256]*Goroutine = undefined,
    runq_head: usize = 0,
    runq_len: usize = 0,
    runq_mu: Mutex = .{},
    current: ?*Goroutine = null,
    thread: ?std.Thread = null,
    /// Exit handoff: the exiting goroutine (running on this
    /// carrier) deposits its stack region here just before its
    /// final switch; the carrier frees it after regaining
    /// control. Carrier-local, so no recycling race can alias it.
    exit_region: ?[]align(4096) u8 = null,

    fn push(c: *Carrier, g: *Goroutine) bool {
        c.runq_mu.lock();
        defer c.runq_mu.unlock();
        if (c.runq_len >= c.runq.len) return false;
        c.runq[(c.runq_head + c.runq_len) % c.runq.len] = g;
        c.runq_len += 1;
        return true;
    }

    fn pop(c: *Carrier) ?*Goroutine {
        c.runq_mu.lock();
        defer c.runq_mu.unlock();
        if (c.runq_len == 0) return null;
        const g = c.runq[c.runq_head];
        c.runq_head = (c.runq_head + 1) % c.runq.len;
        c.runq_len -= 1;
        return g;
    }

    fn runq_len_snapshot(c: *Carrier) usize {
        c.runq_mu.lock();
        defer c.runq_mu.unlock();
        return c.runq_len;
    }

    fn stealHalf(c: *Carrier, victim: *Carrier) ?*Goroutine {
        // Caller guarantees c's own queue is empty (findWork only
        // steals after its own pop failed), so pushes cannot fill
        // it: at most 127 of 256 slots are taken from a victim.
        victim.runq_mu.lock();
        defer victim.runq_mu.unlock();
        if (victim.runq_len < 2) return null;
        const take = victim.runq_len / 2;
        var first: ?*Goroutine = null;
        var i: usize = 0;
        while (i < take) : (i += 1) {
            const g = victim.runq[victim.runq_head];
            victim.runq_head = (victim.runq_head + 1) % victim.runq.len;
            victim.runq_len -= 1;
            if (first == null) {
                first = g;
            } else {
                std.debug.assert(c.push(g));
            }
        }
        return first;
    }
};

var sched_mu: Mutex = .{};
var carriers: []Carrier = &.{};
var global_runq_head: ?*Goroutine = null;
var global_runq_tail: ?*Goroutine = null;
var live_count: std.atomic.Value(usize) = .init(0);
var wake_word: std.atomic.Value(u32) = .init(0);
var deadlock_armed: std.atomic.Value(bool) = .init(false);

threadlocal var current_g: ?*Goroutine = null;
threadlocal var carrier_self: ?*Carrier = null;

fn wakeCarriers() void {
    _ = wake_word.fetchAdd(1, .release);
    futexWake(&wake_word, 0x7fffffff);
}

fn globalPush(g: *Goroutine) void {
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

fn globalPop() ?*Goroutine {
    sched_mu.lock();
    defer sched_mu.unlock();
    const g = global_runq_head orelse return null;
    global_runq_head = g.qnext;
    if (global_runq_head == null) global_runq_tail = null;
    g.qnext = null;
    return g;
}

fn enqueueRunnable(g: *Goroutine) void {
    noteProgress();
    if (carrier_self) |c| {
        if (c.push(g)) {
            wakeCarriers();
            return;
        }
    }
    globalPush(g);
    wakeCarriers();
}

/// Transition a parked goroutine back to runnable. Only the first
/// waker wins; later ones observe state != parked and do nothing.
/// If the goroutine is still switching out (transition), the wake
/// is recorded and the carrier completes it after the switch.
fn unpark(g: *Goroutine) void {
    sched_mu.lock();
    if (g.state.load(.acquire) != .parked) {
        sched_mu.unlock();
        return;
    }
    if (g.transition) {
        g.unpark_pending = true;
        sched_mu.unlock();
        return;
    }
    g.state.store(.runnable, .release);
    sched_mu.unlock();
    enqueueRunnable(g);
}

fn fireNode(node: *WaitNode, status: i32) void {
    if (node.g) |g| {
        g.wake_status = status;
        unpark(g);
    }
    if (node.os) |os| {
        os.status = status;
        os.fire();
    }
    alloc.destroy(node);
}

// ---------------------------------------------------------------------
// Timers (sleep + select/net timeouts). Binary heap by deadline.

const TimerTarget = union(enum) {
    g: *Goroutine,
    sel: *SelectWaiter,
    net: *NetWaiter,
};

const TimerEntry = struct {
    deadline: i64,
    seq: u64,
    target: TimerTarget,
    gen: u64,

    fn lessThan(_: void, a: TimerEntry, b: TimerEntry) std.math.Order {
        if (a.deadline != b.deadline) return std.math.order(a.deadline, b.deadline);
        return std.math.order(a.seq, b.seq);
    }
};

var timer_mu: Mutex = .{};
var timer_heap: std.PriorityQueue(TimerEntry, void, TimerEntry.lessThan) = .initContext({});
var timer_seq: u64 = 0;

fn timerAdd(deadline: i64, target: TimerTarget, gen: u64) bool {
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
    // intermittently. Waking all carriers is coarse but rare
    // (once per armed timer) and always correct: each carrier
    // recomputes its deadline on the next loop pass.
    wakeCarriers();
    return true;
}

fn timerNextDeadline() ?i64 {
    timer_mu.lock();
    defer timer_mu.unlock();
    if (timer_heap.peek()) |e| return e.deadline;
    return null;
}

fn fireTimers() void {
    const now = monotonicNs();
    var expired: std.ArrayList(TimerEntry) = .empty;
    defer expired.deinit(alloc);
    timer_mu.lock();
    while (timer_heap.peek()) |e| {
        if (e.deadline > now) break;
        expired.append(alloc, timer_heap.pop().?) catch break;
    }
    timer_mu.unlock();
    for (expired.items) |e| {
        switch (e.target) {
            .g => |g| {
                if (g.state.load(.acquire) == .parked and g.wait_kind == .sleep and g.park_gen == e.gen) {
                    g.wake_status = SA_TASK_OK;
                    unpark(g);
                }
            },
            .sel => |sel| selectTimeoutFire(sel, e.gen),
            .net => |nw| netTimeoutFire(nw, e.gen),
        }
    }
}

// ---------------------------------------------------------------------
// Core goroutine context operations (called on a goroutine stack).

fn switchToCarrier(g: *Goroutine) void {
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
fn parkBeginLocked(g: *Goroutine) void {
    g.transition = true;
    g.state.store(.parked, .release);
}

fn parkBegin() void {
    const g = current_g orelse unreachable;
    sched_mu.lock();
    parkBeginLocked(g);
    sched_mu.unlock();
}

fn parkSwitch() void {
    const g = current_g orelse unreachable;
    noteProgress();
    switchToCarrier(g);
    // Resumed by unpark + carrier dispatch.
}

fn parkCurrent() void {
    parkBegin();
    parkSwitch();
}

/// Undo a parkBegin when the wait completed before the switch
/// (e.g. a select case claimed during registration).
fn parkCancel() void {
    const g = current_g orelse unreachable;
    sched_mu.lock();
    g.transition = false;
    g.unpark_pending = false;
    g.state.store(.running, .release);
    sched_mu.unlock();
}

fn deliverMonitor(sub: *MonitorSub, watched: u64, trapped: bool, trap_code: i32) void {
    const ch = chanLookup(sub.chan_handle) orelse return;
    defer chanRelease(ch);
    const code: u64 = if (trapped) @bitCast(@as(i64, trap_code)) else 0;
    ch.mu.lock();
    _ = chanTrySend(ch, .{ .a = watched, .b = code });
    ch.mu.unlock();
}

fn goroutineExit() noreturn {
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

fn trampoline() callconv(.c) void {
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

fn findWork(c: *Carrier) ?*Goroutine {
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

fn runGoroutine(c: *Carrier, g: *Goroutine) void {
    g.state.store(.running, .release);
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
        if (g.reap_requested and !g.reaped and g.state.load(.acquire) == .done) {
            g.reaped = true;
            g.state.store(.empty, .release);
            registry_free.append(alloc, g.slot) catch {};
        }
        registry_mu.unlock();
    }
}

fn runnableTotal() usize {
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
fn systemQuiescent() bool {
    if (live_count.load(.acquire) == 0) return false;
    if (runnableTotal() != 0) return false;
    if (timerNextDeadline() != null) return false;
    if (netWaiterCount() != 0) return false;
    if (external_blocked.load(.acquire) != 0) return false;
    const since = monotonicNs() - last_progress_ns.load(.acquire);
    return since >= 250 * std.time.ns_per_ms;
}

fn deadlockCheck() void {
    if (!deadlock_armed.load(.acquire)) return;
    if (!systemQuiescent()) return;
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "deadlock: all {d} goroutines are parked (guard armed)", .{live_count.load(.acquire)}) catch "deadlock";
    processTrap(msg);
}

fn carrierMain(c: *Carrier) void {
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
        if (findWork(c)) |g| {
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
        futexWait(&wake_word, w, timeout_ns);
    }
}

// ---------------------------------------------------------------------
// Lazy scheduler init.

var init_state: std.atomic.Value(u32) = .init(0);

fn ensureInit() bool {
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

fn envUsize(name: []const u8) ?usize {
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

fn initScheduler() void {
    if (envUsize("SA_TASK_STACK_KIB")) |kib| {
        const clamped = std.math.clamp(kib, 64, 8192);
        cfg_stack_usable = clamped * 1024;
    }
    const cpu = std.Thread.getCpuCount() catch 1;
    var want = envUsize("SA_TASK_CARRIERS") orelse cpu;
    want = std.math.clamp(want, 1, 128);
    cfg_carriers = want;
    carriers = alloc.alloc(Carrier, want) catch processTrap("sa_task: out of memory starting scheduler");
    for (carriers) |*c| c.* = .{};
    installSegvHandler();
    noteProgress();
    for (carriers) |*c| {
        c.thread = std.Thread.spawn(.{}, carrierMain, .{c}) catch processTrap("sa_task: cannot spawn carrier thread");
        if (c.thread) |t| t.detach();
    }
}

// ---------------------------------------------------------------------
// Phase B/C shared wait objects (defined here; their fire/poll
// implementations land in the channel and sync/net sections).

const SelectWaiter = struct {
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
};

const NetWaiter = struct {
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
// Phase A externs: spawn / yield / sleep / join / current.

pub export fn sa_task_spawn(entry: ?*const anyopaque, arg: ?*anyopaque, out_handle: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    const e: EntryFn = @ptrCast(@alignCast(entry orelse return ERR_INVALID));
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
fn recordOnlySink(_: u64, _: i32, _: [*]const u8, _: u64, _: ?*anyopaque) callconv(.c) void {}

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
    if (g.state.load(.acquire) != .done) return ERR_INVALID;
    // Done but no held trap record (clean exit, already consumed,
    // or never held by a TRAPPED join): for this API the handle
    // has no record to give, which the handle-validity family
    // reports as ERR_INVALID_HANDLE — the same answer a fully
    // reaped handle gets from registryLookup above.
    if (g.trap_consumed or !g.trapped or !g.trap_held) return ERR_INVALID_HANDLE;
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
    registryRecycle(g, g.gen);
    return SA_TASK_OK;
}

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
    sched_mu.lock();
    if (g.state.load(.acquire) == .done) {
        // A trap record already consumed by sa_task_trap_info
        // leaves the handle invalid even while the two-phase
        // slot reap is still pending: subscribing must report
        // ERR_INVALID_HANDLE (the contract above), not resurrect
        // the exit as a fresh delivery. Roll back the channel
        // and subscription allocated for this call.
        if (g.trap_consumed) {
            sched_mu.unlock();
            _ = sa_chan_destroy(chan_h);
            alloc.destroy(sub);
            return ERR_INVALID_HANDLE;
        }
        sched_mu.unlock();
        deliverMonitor(sub, handle, g.trapped, g.trap_code);
        alloc.destroy(sub);
    } else {
        sub.next = g.monitors;
        g.monitors = sub;
        sched_mu.unlock();
    }
    out.* = chan_h;
    return SA_TASK_OK;
}

pub export fn sa_task_yield() i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const g = current_g orelse {
        std.Thread.yield() catch {};
        return SA_TASK_OK;
    };
    sched_mu.lock();
    g.transition = true;
    g.yield_requeue = true;
    g.state.store(.runnable, .release);
    sched_mu.unlock();
    switchToCarrier(g);
    return SA_TASK_OK;
}

pub export fn sa_task_sleep_ns(ns: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    if (ns == 0) return sa_task_yield();
    if (current_g) |g| {
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
fn joinFinish(g: *Goroutine, gen: u32, status: i32) i32 {
    // A trap record already consumed by sa_task_trap_info leaves
    // the handle invalid: report that instead of replaying the
    // trap (or a clean status read from the not-yet-reaped
    // record). The consuming call already requested the reap.
    if (g.trap_consumed) return ERR_INVALID_HANDLE;
    if (status == SA_TASK_TRAPPED and g.trap_sink != null) {
        g.trap_held = true;
        return status;
    }
    registryRecycle(g, gen);
    return status;
}

pub export fn sa_task_join(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    if (!ensureInit()) return ERR_UNSUPPORTED;
    const g = registryLookup(handle) orelse return ERR_INVALID_HANDLE;
    if (current_g == g) return ERR_INVALID;
    if (g.state.load(.acquire) == .done) {
        const status: i32 = if (g.trapped) SA_TASK_TRAPPED else SA_TASK_OK;
        return joinFinish(g, g.gen, status);
    }
    const node = alloc.create(WaitNode) catch return ERR_NOMEM;
    node.* = .{};
    var os_waiter: OsWaiter = .{};
    if (current_g) |me| {
        node.g = me;
        me.wait_kind = .join;
    } else {
        node.os = &os_waiter;
    }
    const target_gen = g.gen;
    sched_mu.lock();
    if (g.state.load(.acquire) == .done) {
        sched_mu.unlock();
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
    if (current_g) |me| parkBeginLocked(me);
    sched_mu.unlock();
    if (current_g) |me| {
        parkSwitch();
        me.wait_kind = .none;
        const status = me.wake_status;
        return joinFinish(g, target_gen, status);
    }
    os_waiter.wait();
    const status = os_waiter.status;
    return joinFinish(g, target_gen, status);
}

pub export fn sa_task_current(out_handle: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_handle orelse return ERR_INVALID;
    out.* = if (current_g) |g| g.handle() else 0;
    return SA_TASK_OK;
}

pub export fn sa_task_live_count(out_count: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_count orelse return ERR_INVALID;
    out.* = @intCast(live_count.load(.acquire));
    return SA_TASK_OK;
}

pub export fn sa_task_deadlock_guard_arm() i32 {
    if (!supported) return ERR_UNSUPPORTED;
    deadlock_armed.store(true, .release);
    noteProgress();
    return SA_TASK_OK;
}

// ---------------------------------------------------------------------
// Phase A tests.

const testing = std.testing;

var test_counter: std.atomic.Value(u64) = .init(0);

fn countingWorker(_: ?*anyopaque) callconv(.c) void {
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

fn sleepyWorker(arg: ?*anyopaque) callconv(.c) void {
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

fn yieldWorker(arg: ?*anyopaque) callconv(.c) void {
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

var sink_seen_code: std.atomic.Value(i32) = .init(0);
var sink_seen_len: std.atomic.Value(u64) = .init(0);

fn recordingSink(_: u64, code: i32, _: [*]const u8, msg_len: u64, _: ?*anyopaque) callconv(.c) void {
    sink_seen_code.store(code, .release);
    sink_seen_len.store(msg_len, .release);
}

fn trappingWorker(_: ?*anyopaque) callconv(.c) void {
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

var probe_region_lo: std.atomic.Value(usize) = .init(0);
var probe_stack_addr: std.atomic.Value(usize) = .init(0);
var probe_release: std.atomic.Value(bool) = .init(false);

fn probeWorker(_: ?*anyopaque) callconv(.c) void {
    const g = current_g.?;
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

var cycle_handles: [2]u64 = .{ 0, 0 };
var cycle_ready: std.atomic.Value(bool) = .init(false);

fn cycleWorker(arg: ?*anyopaque) callconv(.c) void {
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

const WAKE_SEND_ON_CLOSED: i32 = -7;
const WAKE_RECHECK: i32 = -8;
const WAKE_DESTROYED: i32 = -9;

const Channel = struct {
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

var chan_registry_mu: Mutex = .{};
var chan_slots: std.ArrayList(?*Channel) = .empty;
// Generations live OUTSIDE the Channel struct: the struct is
// freed when its last pin drops, which can happen before the
// slot is reused, so make must never read gen from a dead struct.
var chan_gens: std.ArrayList(u32) = .empty;
var chan_free: std.ArrayList(u32) = .empty;

fn chanLookup(handle: u64) ?*Channel {
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

fn chanRelease(ch: *Channel) void {
    if (ch.refs.fetchSub(1, .seq_cst) == 1) {
        // Last pin dropped after destroy: free memory.
        if (ch.buf.len > 0) alloc.free(ch.buf);
        alloc.destroy(ch);
    }
}

fn queuePush(head: *?*WaitNode, tail: *?*WaitNode, node: *WaitNode) void {
    node.next = null;
    node.linked = true;
    if (tail.*) |t| {
        t.next = node;
    } else {
        head.* = node;
    }
    tail.* = node;
}

fn queueRemove(head: *?*WaitNode, tail: *?*WaitNode, node: *WaitNode) bool {
    var prev: ?*WaitNode = null;
    var cur = head.*;
    while (cur) |n| {
        if (n == node) {
            if (prev) |p| {
                p.next = n.next;
            } else {
                head.* = n.next;
            }
            if (tail.* == n) tail.* = prev;
            n.next = null;
            n.linked = false;
            return true;
        }
        prev = n;
        cur = n.next;
    }
    return false;
}

fn wakeSelectOwner(sel: *SelectWaiter) void {
    if (sel.owner_g) |g| {
        g.wake_status = sel.wake_status;
        unpark(g);
    }
    if (sel.owner_os) |os| {
        os.status = sel.wake_status;
        os.fire();
    }
}

fn selectRelease(sel: *SelectWaiter) void {
    if (sel.refs.fetchSub(1, .seq_cst) == 1) alloc.destroy(sel);
}

/// Attempt to claim a select waiter for case `index`. On success
/// the caller (holding the channel lock) completes the payload
/// move, detaches the node, then calls wakeSelectOwner.
fn selectTryClaim(sel: *SelectWaiter, index: u32, closed_result: bool, wake_status: i32) bool {
    sel.mu.lock();
    defer sel.mu.unlock();
    if (sel.claimed) return false;
    sel.claimed = true;
    sel.chosen = @intCast(index);
    sel.closed_result = closed_result;
    sel.wake_status = wake_status;
    return true;
}

fn selectTimeoutFire(sel: *SelectWaiter, gen: u64) void {
    sel.mu.lock();
    if (!sel.claimed and sel.gen == gen) {
        sel.claimed = true;
        sel.chosen = -2;
        sel.wake_status = SA_TASK_OK;
        sel.mu.unlock();
        wakeSelectOwner(sel);
    } else {
        sel.mu.unlock();
    }
    selectRelease(sel);
}

/// Deliver `val` to the head receive waiter, if any. Channel lock
/// held. Stale select nodes (already claimed via another case)
/// are detached and skipped; their owner frees them.
fn chanDeliverToReceiver(ch: *Channel, val: Slot) bool {
    while (ch.recvq_head) |node| {
        if (node.sel) |sel| {
            if (!selectTryClaim(sel, node.sel_index, false, SA_TASK_OK)) {
                _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
                continue;
            }
            node.slot.?.* = val;
            _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
            wakeSelectOwner(sel);
            return true;
        }
        node.slot.?.* = val;
        _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
        fireNode(node, SA_TASK_OK);
        return true;
    }
    return false;
}

/// Take a value from the buffer, or directly from a head send
/// waiter. Channel lock held.
fn chanTakeFromSender(ch: *Channel, out: *Slot) enum { got, empty } {
    if (ch.count > 0) {
        out.* = ch.buf[ch.head];
        ch.head = (ch.head + 1) % ch.buf.len;
        ch.count -= 1;
        // A blocked sender may now refill the buffer slot.
        if (ch.sendq_head) |node| {
            if (node.sel) |sel| {
                if (selectTryClaim(sel, node.sel_index, false, SA_TASK_OK)) {
                    const v = node.slot.?.*;
                    _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
                    ch.buf[(ch.head + ch.count) % ch.buf.len] = v;
                    ch.count += 1;
                    wakeSelectOwner(sel);
                }
            } else {
                const v = node.slot.?.*;
                _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
                ch.buf[(ch.head + ch.count) % ch.buf.len] = v;
                ch.count += 1;
                fireNode(node, SA_TASK_OK);
            }
        }
        return .got;
    }
    while (ch.sendq_head) |node| {
        if (node.sel) |sel| {
            if (!selectTryClaim(sel, node.sel_index, false, SA_TASK_OK)) {
                _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
                continue;
            }
            out.* = node.slot.?.*;
            _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
            wakeSelectOwner(sel);
            return .got;
        }
        out.* = node.slot.?.*;
        _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
        fireNode(node, SA_TASK_OK);
        return .got;
    }
    return .empty;
}

/// Send attempt without blocking. Channel lock held; caller has
/// already handled the closed trap. Returns true if the value was
/// accepted (receiver handoff or buffered).
fn chanTrySend(ch: *Channel, val: Slot) bool {
    if (chanDeliverToReceiver(ch, val)) return true;
    if (ch.count < ch.cap) {
        ch.buf[(ch.head + ch.count) % ch.buf.len] = val;
        ch.count += 1;
        return true;
    }
    return false;
}

/// Close-time firing of every waiter. Channel lock held; queues
/// are emptied. Send waiters observe the send-on-closed trap on
/// wake (Go parity); plain receive waiters re-check state (drain
/// or closed), select receive cases are claimed immediately.
fn chanFireAllOnClose(ch: *Channel) void {
    while (ch.sendq_head) |node| {
        _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
        if (node.sel) |sel| {
            if (selectTryClaim(sel, node.sel_index, false, WAKE_SEND_ON_CLOSED)) {
                wakeSelectOwner(sel);
            }
        } else {
            fireNode(node, WAKE_SEND_ON_CLOSED);
        }
    }
    while (ch.recvq_head) |node| {
        _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
        if (node.sel) |sel| {
            // Claim BEFORE touching channel state: a lost claim
            // must not consume a buffered value.
            if (ch.count > 0) {
                if (selectTryClaim(sel, node.sel_index, false, SA_TASK_OK)) {
                    var v: Slot = undefined;
                    _ = chanTakeFromSender(ch, &v);
                    node.slot.?.* = v;
                    wakeSelectOwner(sel);
                }
            } else {
                if (selectTryClaim(sel, node.sel_index, true, SA_TASK_OK)) {
                    wakeSelectOwner(sel);
                }
            }
        } else {
            fireNode(node, WAKE_RECHECK);
        }
    }
}

fn chanFireAllOnDestroy(ch: *Channel) void {
    while (ch.sendq_head) |node| {
        _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
        if (node.sel) |sel| {
            if (selectTryClaim(sel, node.sel_index, false, WAKE_DESTROYED)) wakeSelectOwner(sel);
        } else {
            fireNode(node, WAKE_DESTROYED);
        }
    }
    while (ch.recvq_head) |node| {
        _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
        if (node.sel) |sel| {
            if (selectTryClaim(sel, node.sel_index, false, WAKE_DESTROYED)) wakeSelectOwner(sel);
        } else {
            fireNode(node, WAKE_DESTROYED);
        }
    }
}

pub export fn sa_chan_make(capacity: u32, out_handle: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    if (!ensureInit()) return ERR_UNSUPPORTED;
    if (capacity > (1 << 22)) return ERR_INVALID; // 64 MiB payload cap
    const ch = alloc.create(Channel) catch return ERR_NOMEM;
    ch.* = .{ .cap = capacity };
    if (capacity > 0) {
        ch.buf = alloc.alloc(Slot, capacity) catch {
            alloc.destroy(ch);
            return ERR_NOMEM;
        };
    }
    chan_registry_mu.lock();
    if (chan_free.pop()) |idx| {
        ch.slot_idx = idx;
        ch.gen = chan_gens.items[idx] +% 1;
        if (ch.gen == 0) ch.gen = 1;
        chan_gens.items[idx] = ch.gen;
        chan_slots.items[idx] = ch;
    } else {
        ch.slot_idx = @intCast(chan_slots.items.len);
        ch.gen = 1;
        chan_slots.append(alloc, ch) catch {
            chan_registry_mu.unlock();
            if (ch.buf.len > 0) alloc.free(ch.buf);
            alloc.destroy(ch);
            return ERR_NOMEM;
        };
        chan_gens.append(alloc, 1) catch {
            _ = chan_slots.pop();
            chan_registry_mu.unlock();
            if (ch.buf.len > 0) alloc.free(ch.buf);
            alloc.destroy(ch);
            return ERR_NOMEM;
        };
    }
    chan_registry_mu.unlock();
    out.* = ch.handle();
    return SA_TASK_OK;
}

pub export fn sa_chan_destroy(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const idx: u32 = @truncate(handle);
    const gen: u32 = @truncate(handle >> 32);
    chan_registry_mu.lock();
    if (idx >= chan_slots.items.len) {
        chan_registry_mu.unlock();
        return ERR_INVALID_HANDLE;
    }
    const ch = chan_slots.items[idx] orelse {
        chan_registry_mu.unlock();
        return ERR_INVALID_HANDLE;
    };
    if (ch.gen != gen or ch.dead) {
        chan_registry_mu.unlock();
        return ERR_INVALID_HANDLE;
    }
    ch.dead = true;
    chan_registry_mu.unlock();
    ch.mu.lock();
    chanFireAllOnDestroy(ch);
    ch.mu.unlock();
    chan_registry_mu.lock();
    chan_slots.items[idx] = null;
    chan_free.append(alloc, idx) catch {};
    chan_registry_mu.unlock();
    chanRelease(ch); // drop the handle's base reference
    return SA_TASK_OK;
}

pub export fn sa_chan_close(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const ch = chanLookup(handle) orelse return ERR_INVALID_HANDLE;
    defer chanRelease(ch);
    ch.mu.lock();
    if (ch.closed) {
        ch.mu.unlock();
        raiseTrap(SA_TASK_TRAP_CLOSE_OF_CLOSED, "close of closed channel");
    }
    ch.closed = true;
    chanFireAllOnClose(ch);
    ch.mu.unlock();
    return SA_TASK_OK;
}

pub export fn sa_chan_send(handle: u64, value_ptr: ?*const Slot) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const val_ptr = value_ptr orelse return ERR_INVALID;
    const ch = chanLookup(handle) orelse return ERR_INVALID_HANDLE;
    defer chanRelease(ch);
    ch.mu.lock();
    if (ch.closed) {
        ch.mu.unlock();
        raiseTrap(SA_TASK_TRAP_SEND_ON_CLOSED, "send on closed channel");
    }
    if (chanTrySend(ch, val_ptr.*)) {
        ch.mu.unlock();
        return SA_TASK_OK;
    }
    // Block: register a wait node and park.
    const node = alloc.create(WaitNode) catch {
        ch.mu.unlock();
        return ERR_NOMEM;
    };
    node.* = .{ .slot = @constCast(val_ptr) };
    var os_waiter: OsWaiter = .{};
    if (current_g) |me| {
        node.g = me;
        me.wait_kind = .chan_send;
    } else {
        node.os = &os_waiter;
    }
    queuePush(&ch.sendq_head, &ch.sendq_tail, node);
    if (current_g) |_| parkBegin();
    ch.mu.unlock();
    if (current_g) |me| {
        parkSwitch();
        me.wait_kind = .none;
        return chanSendWakeStatus(me.wake_status);
    }
    os_waiter.wait();
    return chanSendWakeStatus(os_waiter.status);
}

fn chanSendWakeStatus(status: i32) i32 {
    if (status == WAKE_SEND_ON_CLOSED) {
        raiseTrap(SA_TASK_TRAP_SEND_ON_CLOSED, "send on closed channel");
    }
    if (status == WAKE_DESTROYED) return ERR_INVALID_HANDLE;
    return status;
}

pub export fn sa_chan_recv(handle: u64, out_value: ?*Slot, out_closed: ?*u32) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_value orelse return ERR_INVALID;
    if (out_closed) |oc| oc.* = 0;
    const ch = chanLookup(handle) orelse return ERR_INVALID_HANDLE;
    defer chanRelease(ch);
    while (true) {
        ch.mu.lock();
        var v: Slot = undefined;
        if (chanTakeFromSender(ch, &v) == .got) {
            ch.mu.unlock();
            out.* = v;
            return SA_TASK_OK;
        }
        if (ch.closed) {
            ch.mu.unlock();
            if (out_closed) |oc| oc.* = 1;
            out.* = .{};
            return SA_TASK_OK;
        }
        const node = alloc.create(WaitNode) catch {
            ch.mu.unlock();
            return ERR_NOMEM;
        };
        node.* = .{ .slot = out };
        var os_waiter: OsWaiter = .{};
        if (current_g) |me| {
            node.g = me;
            me.wait_kind = .chan_recv;
        } else {
            node.os = &os_waiter;
        }
        queuePush(&ch.recvq_head, &ch.recvq_tail, node);
        if (current_g) |_| parkBegin();
        ch.mu.unlock();
        var status: i32 = undefined;
        if (current_g) |me| {
            parkSwitch();
            me.wait_kind = .none;
            status = me.wake_status;
        } else {
            os_waiter.wait();
            status = os_waiter.status;
        }
        if (status == WAKE_DESTROYED) return ERR_INVALID_HANDLE;
        if (status == WAKE_RECHECK) continue; // closed while parked: re-evaluate
        // Value already delivered into `out` by the sender side.
        return SA_TASK_OK;
    }
}

pub export fn sa_chan_len(handle: u64, out_len: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_len orelse return ERR_INVALID;
    const ch = chanLookup(handle) orelse return ERR_INVALID_HANDLE;
    defer chanRelease(ch);
    ch.mu.lock();
    out.* = ch.count;
    ch.mu.unlock();
    return SA_TASK_OK;
}

pub export fn sa_chan_cap(handle: u64, out_cap: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_cap orelse return ERR_INVALID;
    const ch = chanLookup(handle) orelse return ERR_INVALID_HANDLE;
    defer chanRelease(ch);
    out.* = ch.cap;
    return SA_TASK_OK;
}

var select_gen_counter: std.atomic.Value(u64) = .init(0);

pub export fn sa_chan_select(cases: ?[*]const u64, ops: ?[*]const u32, slots: ?[*]Slot, count: u64, has_default: u32, timeout_ns: i64, out_index: ?*i64, out_closed: ?*u32) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const oi = out_index orelse return ERR_INVALID;
    oi.* = -1;
    if (out_closed) |oc| oc.* = 0;
    if (count > 0) {
        if (cases == null or ops == null or slots == null) return ERR_INVALID;
        if (count > 4096) return ERR_INVALID;
    }
    if (!ensureInit()) return ERR_UNSUPPORTED;
    const n: usize = @intCast(count);
    const case_ptrs = if (n > 0) cases.?[0..n] else &.{};
    const op_ptrs = if (n > 0) ops.?[0..n] else &.{};
    var empty_slots = [_]Slot{};
    const slot_ptrs: []Slot = if (n > 0) slots.?[0..n] else &empty_slots;

    // Resolve all channels first (pins them for the whole call).
    const chans = alloc.alloc(?*Channel, n) catch return ERR_NOMEM;
    defer {
        for (chans) |c| if (c) |ch| chanRelease(ch);
        alloc.free(chans);
    }
    for (case_ptrs, 0..) |h, i| {
        chans[i] = chanLookup(h);
        if (chans[i] == null) return ERR_INVALID_HANDLE;
        if (op_ptrs[i] != SA_CHAN_OP_RECV and op_ptrs[i] != SA_CHAN_OP_SEND) return ERR_INVALID;
    }

    // Phase 1: in-order immediate evaluation.
    for (0..n) |i| {
        const ch = chans[i].?;
        ch.mu.lock();
        if (op_ptrs[i] == SA_CHAN_OP_SEND) {
            if (ch.closed) {
                ch.mu.unlock();
                raiseTrap(SA_TASK_TRAP_SEND_ON_CLOSED, "send on closed channel");
            }
            if (chanTrySend(ch, slot_ptrs[i])) {
                ch.mu.unlock();
                oi.* = @intCast(i);
                return SA_TASK_OK;
            }
        } else {
            var v: Slot = undefined;
            if (chanTakeFromSender(ch, &v) == .got) {
                ch.mu.unlock();
                slot_ptrs[i] = v;
                oi.* = @intCast(i);
                return SA_TASK_OK;
            }
            if (ch.closed) {
                ch.mu.unlock();
                slot_ptrs[i] = .{};
                if (out_closed) |oc| oc.* = 1;
                oi.* = @intCast(i);
                return SA_TASK_OK;
            }
        }
        ch.mu.unlock();
    }
    if (has_default != 0) {
        oi.* = -1;
        return SA_TASK_OK;
    }

    // Phase 2: register one node per case and park.
    const sel = alloc.create(SelectWaiter) catch return ERR_NOMEM;
    sel.* = .{};
    sel.gen = select_gen_counter.fetchAdd(1, .seq_cst) + 1;
    var os_waiter: OsWaiter = .{};
    if (current_g) |me| {
        sel.owner_g = me;
        me.wait_kind = .select;
    } else {
        sel.owner_os = &os_waiter;
    }
    const nodes = alloc.alloc(?*WaitNode, n) catch {
        selectRelease(sel);
        return ERR_NOMEM;
    };
    for (nodes) |*nd| nd.* = null;
    // Mark parked BEFORE registering any case: a peer completing
    // a case during registration fires the waiter, and that wake
    // must find state == parked (see parkBegin). If a claim lands
    // during registration we cancel the park instead of switching.
    if (current_g != null) parkBegin();
    var registered: usize = 0;
    var self_claimed = false;
    for (0..n) |i| {
        const node = alloc.create(WaitNode) catch break;
        node.* = .{ .slot = &slot_ptrs[i], .sel = sel, .sel_index = @intCast(i) };
        nodes[i] = node;
        const ch = chans[i].?;
        ch.mu.lock();
        if (op_ptrs[i] == SA_CHAN_OP_SEND) {
            queuePush(&ch.sendq_head, &ch.sendq_tail, node);
        } else {
            queuePush(&ch.recvq_head, &ch.recvq_tail, node);
        }
        registered += 1;
        // Re-check readiness under the same lock hold: a case
        // that became ready between phase 1 and registration
        // must claim us now, or the wakeup would be lost (the
        // peer already came and went).
        if (op_ptrs[i] == SA_CHAN_OP_SEND) {
            if (!ch.closed and chanTrySend(ch, slot_ptrs[i])) {
                _ = selectTryClaim(sel, @intCast(i), false, SA_TASK_OK);
                // Detach our own node while still holding the
                // lock: the value already moved via chanTrySend,
                // and a queued node would deliver it a second
                // time to a later receiver.
                _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
                self_claimed = true;
            }
        } else {
            var v: Slot = undefined;
            if (chanTakeFromSender(ch, &v) == .got) {
                if (selectTryClaim(sel, @intCast(i), false, SA_TASK_OK)) {
                    slot_ptrs[i] = v;
                    _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
                    self_claimed = true;
                }
            } else if (ch.closed) {
                if (selectTryClaim(sel, @intCast(i), true, SA_TASK_OK)) {
                    slot_ptrs[i] = .{};
                    _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
                    self_claimed = true;
                }
            }
        }
        ch.mu.unlock();
        if (self_claimed) break;
    }
    if (registered < n and !self_claimed) {
        // Node allocation failed mid-registration: unwind.
        for (0..n) |i| {
            const node = nodes[i] orelse continue;
            const ch = chans[i].?;
            ch.mu.lock();
            if (node.linked) {
                if (op_ptrs[i] == SA_CHAN_OP_SEND) {
                    _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
                } else {
                    _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
                }
            }
            ch.mu.unlock();
            alloc.destroy(node);
        }
        alloc.free(nodes);
        selectRelease(sel);
        if (current_g) |me| {
            parkCancel();
            me.wait_kind = .none;
        }
        return ERR_NOMEM;
    }
    sel.mu.lock();
    const claimed_now = self_claimed or sel.claimed;
    sel.mu.unlock();
    if (timeout_ns >= 0 and !claimed_now) {
        _ = sel.refs.fetchAdd(1, .seq_cst);
        const deadline = monotonicNs() + timeout_ns;
        if (!timerAdd(deadline, .{ .sel = sel }, sel.gen)) {
            _ = sel.refs.fetchSub(1, .seq_cst);
        }
    }
    if (claimed_now) {
        if (current_g) |me| {
            parkCancel();
            me.wait_kind = .none;
        }
    } else {
        if (current_g) |me| {
            parkSwitch();
            me.wait_kind = .none;
        } else {
            os_waiter.wait();
        }
    }
    // Read the outcome.
    sel.mu.lock();
    const chosen = sel.chosen;
    const closed_result = sel.closed_result;
    const wake_status = sel.wake_status;
    sel.mu.unlock();
    // Cleanup: detach any nodes still queued and free them.
    for (0..n) |i| {
        const node = nodes[i] orelse continue;
        const ch = chans[i].?;
        ch.mu.lock();
        if (node.linked) {
            if (op_ptrs[i] == SA_CHAN_OP_SEND) {
                _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
            } else {
                _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
            }
        }
        ch.mu.unlock();
        alloc.destroy(node);
    }
    alloc.free(nodes);
    selectRelease(sel);
    if (wake_status == WAKE_SEND_ON_CLOSED) {
        raiseTrap(SA_TASK_TRAP_SEND_ON_CLOSED, "send on closed channel");
    }
    if (wake_status == WAKE_DESTROYED) return ERR_INVALID_HANDLE;
    oi.* = chosen;
    if (closed_result and out_closed != null) out_closed.?.* = 1;
    return SA_TASK_OK;
}

// ---------------------------------------------------------------------
// Phase B tests.

fn pingPongProducer(arg: ?*anyopaque) callconv(.c) void {
    const ch: u64 = @intFromPtr(arg.?);
    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        var v: Slot = .{ .a = i, .b = i * 7 };
        _ = sa_chan_send(ch, &v);
    }
    _ = sa_chan_close(ch);
}

test "sa_task.test.chan: unbuffered ping-pong ordering and close" {
    if (!supported) return error.SkipZigTest;
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &ch));
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&pingPongProducer, @ptrFromInt(@as(usize, @intCast(ch))), &h));
    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        var out: Slot = undefined;
        var closed: u32 = 99;
        try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, &closed));
        try testing.expectEqual(@as(u32, 0), closed);
        try testing.expectEqual(i, out.a);
        try testing.expectEqual(i * 7, out.b);
    }
    var out: Slot = undefined;
    var closed: u32 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, &closed));
    try testing.expectEqual(@as(u32, 1), closed);
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}

var block_send_done: std.atomic.Value(bool) = .init(false);

fn blockedSender(arg: ?*anyopaque) callconv(.c) void {
    const ch: u64 = @intFromPtr(arg.?);
    var v: Slot = .{ .a = 44, .b = 0 };
    _ = sa_chan_send(ch, &v);
    block_send_done.store(true, .release);
}

test "sa_task.test.chan: buffered full and empty edges" {
    if (!supported) return error.SkipZigTest;
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(3, &ch));
    for (0..3) |i| {
        var v: Slot = .{ .a = @intCast(i + 1), .b = 0 };
        try testing.expectEqual(SA_TASK_OK, sa_chan_send(ch, &v));
    }
    var ln: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_len(ch, &ln));
    try testing.expectEqual(@as(u64, 3), ln);
    // Fourth send blocks (buffer full).
    block_send_done.store(false, .release);
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&blockedSender, @ptrFromInt(@as(usize, @intCast(ch))), &h));
    _ = sa_task_sleep_ms(60);
    try testing.expect(!block_send_done.load(.acquire));
    // Freeing one slot lets it through; FIFO order preserved.
    var out: Slot = undefined;
    try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, null));
    try testing.expectEqual(@as(u64, 1), out.a);
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expect(block_send_done.load(.acquire));
    for (0..3) |i| {
        try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, null));
        const expected: u64 = if (i == 2) 44 else @intCast(i + 2);
        try testing.expectEqual(expected, out.a);
    }
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}

const ProdCons = struct {
    ch: u64 = 0,
    total: std.atomic.Value(u64) = .init(0),
    count: std.atomic.Value(u64) = .init(0),
};
var prodcons: ProdCons = .{};

fn pcProducer(arg: ?*anyopaque) callconv(.c) void {
    const pid: u64 = @intFromPtr(arg.?) - 1;
    var i: u64 = 0;
    while (i < 250) : (i += 1) {
        var v: Slot = .{ .a = pid * 1000 + i, .b = 0 };
        _ = sa_chan_send(prodcons.ch, &v);
    }
}

fn pcConsumer(_: ?*anyopaque) callconv(.c) void {
    while (true) {
        var out: Slot = undefined;
        var closed: u32 = 0;
        _ = sa_chan_recv(prodcons.ch, &out, &closed);
        if (closed != 0) return;
        _ = prodcons.total.fetchAdd(out.a, .seq_cst);
        _ = prodcons.count.fetchAdd(1, .seq_cst);
    }
}

test "sa_task.test.chan: producer-consumer sum oracle" {
    if (!supported) return error.SkipZigTest;
    prodcons = .{};
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(16, &prodcons.ch));
    var cons: [3]u64 = undefined;
    for (&cons) |*h| try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&pcConsumer, null, h));
    var prods: [4]u64 = undefined;
    for (&prods, 0..) |*h, i| {
        try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&pcProducer, @ptrFromInt(@as(usize, i + 1)), h));
    }
    for (prods) |h| try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(SA_TASK_OK, sa_chan_close(prodcons.ch));
    for (cons) |h| try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    var expected: u64 = 0;
    for (0..4) |p| {
        for (0..250) |i| expected += @as(u64, p * 1000 + i);
    }
    try testing.expectEqual(expected, prodcons.total.load(.seq_cst));
    try testing.expectEqual(@as(u64, 1000), prodcons.count.load(.seq_cst));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(prodcons.ch));
}

test "sa_task.test.select: timeout, default, and ready case" {
    if (!supported) return error.SkipZigTest;
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &ch));
    var chans = [1]u64{ch};
    var ops = [1]u32{SA_CHAN_OP_RECV};
    var slots = [1]Slot{.{}};
    var idx: i64 = -99;
    // Default: returns immediately with -1.
    var t0 = monotonicNs();
    try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans, &ops, &slots, 1, 1, -1, &idx, null));
    try testing.expectEqual(@as(i64, -1), idx);
    try testing.expect(monotonicNs() - t0 < 20 * std.time.ns_per_ms);
    // Timeout: returns -2 after roughly the timeout.
    idx = -99;
    t0 = monotonicNs();
    try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans, &ops, &slots, 1, 0, 60 * std.time.ns_per_ms, &idx, null));
    try testing.expectEqual(@as(i64, -2), idx);
    try testing.expect(monotonicNs() - t0 >= 50 * std.time.ns_per_ms);
    // Ready case beats the timeout.
    var ch2: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(1, &ch2));
    var v: Slot = .{ .a = 777, .b = 0 };
    try testing.expectEqual(SA_TASK_OK, sa_chan_send(ch2, &v));
    var chans2 = [2]u64{ ch, ch2 };
    var ops2 = [2]u32{ SA_CHAN_OP_RECV, SA_CHAN_OP_RECV };
    var slots2 = [2]Slot{ .{}, .{} };
    idx = -99;
    t0 = monotonicNs();
    try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans2, &ops2, &slots2, 2, 0, 5 * std.time.ns_per_s, &idx, null));
    try testing.expectEqual(@as(i64, 1), idx);
    try testing.expectEqual(@as(u64, 777), slots2[1].a);
    try testing.expect(monotonicNs() - t0 < 1000 * std.time.ns_per_ms);
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch2));
}

var sink_send_closed_code: std.atomic.Value(i32) = .init(0);

fn sendClosedSink(_: u64, code: i32, _: [*]const u8, _: u64, _: ?*anyopaque) callconv(.c) void {
    sink_send_closed_code.store(code, .release);
}

fn sendOnClosedWorker(arg: ?*anyopaque) callconv(.c) void {
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

const DoneFan = struct {
    done: u64 = 0,
    work: u64 = 0,
    woke: std.atomic.Value(u64) = .init(0),
    done_case: std.atomic.Value(u64) = .init(0),
};
var donefan: DoneFan = .{};

fn doneWaiter(_: ?*anyopaque) callconv(.c) void {
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

extern fn sa_std_net_poll_wait(handles: ?[*]const u64, interests: ?[*]const u32, count: u64, timeout_ms: i32, ready: ?[*]u32, out_ready_count: ?*u64) i32;

var poll_hook: ?PollFn = null;

pub fn setPollHook(f: PollFn) void {
    poll_hook = f;
}

fn pollWait(handles: ?[*]const u64, interests: ?[*]const u32, count: u64, timeout_ms: i32, ready: ?[*]u32, out_count: ?*u64) i32 {
    if (poll_hook) |hook| return hook(handles, interests, count, timeout_ms, ready, out_count);
    return sa_std_net_poll_wait(handles, interests, count, timeout_ms, ready, out_count);
}

var net_mu: Mutex = .{};
var net_list: ?*NetWaiter = null;
var net_count: usize = 0;
var net_gen_counter: std.atomic.Value(u64) = .init(0);

fn netRelease(nw: *NetWaiter) void {
    if (nw.refs.fetchSub(1, .seq_cst) == 1) alloc.destroy(nw);
}

fn netUnlinkLocked(nw: *NetWaiter) void {
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

fn netFireLocked(nw: *NetWaiter, bits: u32, status: i32) void {
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

fn netTimeoutFire(nw: *NetWaiter, gen: u64) void {
    net_mu.lock();
    if (nw.linked and nw.gen == gen and !nw.done) {
        netUnlinkLocked(nw);
        netFireLocked(nw, 0, SA_TASK_OK); // timeout: zero ready bits
    }
    net_mu.unlock();
    netRelease(nw);
}

fn netWaiterCount() usize {
    net_mu.lock();
    defer net_mu.unlock();
    return net_count;
}

fn pollNetOnce() void {
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
    for (0..n) |k| {
        if (ready[k] != 0) {
            const nw = waiters[k];
            if (nw.linked and !nw.done) {
                netUnlinkLocked(nw);
                netFireLocked(nw, ready[k], SA_TASK_OK);
            }
        }
    }
    net_mu.unlock();
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
    if (current_g) |me| {
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
    if (current_g) |me| {
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

// ---------------------------------------------------------------------
// Phase C: sync primitives on the park queues (Mutex / RwLock /
// WaitGroup / Once). One registry, kind-tagged objects; every
// operation validates the kind — a mismatched handle is an
// explicit error, never a silent reinterpretation.
//
// Mutexes are non-reentrant: a lock attempt by the current owner
// returns INVALID_ARGUMENT immediately (Go's sync.Mutex would
// deadlock; the explicit error is the documented deviation, in
// line with this runtime's no-silent-failure rule). Unlock by a
// non-owner is likewise INVALID_ARGUMENT. Handoff is direct:
// unlock transfers ownership to the head waiter, so wake order
// is FIFO and a woken waiter never re-competes.
//
// RwLock prefers writers once one is queued (later readers queue
// behind it) so writers cannot starve; reader batches at the
// queue head wake together.
//
// WaitGroup: a negative counter traps at the goroutine boundary
// (Go panic parity).
//
// Once: the function runs on the first caller's goroutine;
// concurrent callers park until it completes. If the function
// traps at the goroutine boundary, the Once stays in the running
// state — the component is considered failed and supervision
// restarts it wholesale; that is registered here rather than
// papered over.

const SyncKind = enum(u8) { mutex, rwlock, waitgroup, once };

const SyncObj = struct {
    kind: SyncKind,
    mu: Mutex = .{},
    slot_idx: u32 = 0,
    gen: u32 = 0,
    dead: bool = false,
    refs: std.atomic.Value(u32) = .init(1),
    // mutex + rwlock writer ownership
    locked: bool = false,
    owner_key: u64 = 0,
    waitq_head: ?*WaitNode = null,
    waitq_tail: ?*WaitNode = null,
    // rwlock
    readers: u32 = 0,
    // waitgroup
    counter: i64 = 0,
    // once
    once_done: bool = false,
    once_running: bool = false,

    fn handle(o: *const SyncObj) u64 {
        return (@as(u64, o.gen) << 32) | @as(u64, o.slot_idx);
    }
};

var sync_registry_mu: Mutex = .{};
var sync_slots: std.ArrayList(?*SyncObj) = .empty;
// Generations live outside the struct (same UAF lesson as
// channels): the struct is freed at the last pin drop.
var sync_gens: std.ArrayList(u32) = .empty;
var sync_free: std.ArrayList(u32) = .empty;

fn syncPin(handle: u64) ?*SyncObj {
    const idx: u32 = @truncate(handle);
    const gen: u32 = @truncate(handle >> 32);
    sync_registry_mu.lock();
    defer sync_registry_mu.unlock();
    if (idx >= sync_slots.items.len) return null;
    const o = sync_slots.items[idx] orelse return null;
    if (o.gen != gen or o.dead) return null;
    _ = o.refs.fetchAdd(1, .seq_cst);
    return o;
}

fn syncRelease(o: *SyncObj) void {
    if (o.refs.fetchSub(1, .seq_cst) == 1) alloc.destroy(o);
}

fn syncNew(kind: SyncKind, out_handle: ?*u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    if (!ensureInit()) return ERR_UNSUPPORTED;
    const o = alloc.create(SyncObj) catch return ERR_NOMEM;
    o.* = .{ .kind = kind };
    sync_registry_mu.lock();
    if (sync_free.pop()) |idx| {
        o.slot_idx = idx;
        o.gen = sync_gens.items[idx] +% 1;
        if (o.gen == 0) o.gen = 1;
        sync_gens.items[idx] = o.gen;
        sync_slots.items[idx] = o;
    } else {
        o.slot_idx = @intCast(sync_slots.items.len);
        o.gen = 1;
        sync_slots.append(alloc, o) catch {
            sync_registry_mu.unlock();
            alloc.destroy(o);
            return ERR_NOMEM;
        };
        sync_gens.append(alloc, 1) catch {
            _ = sync_slots.pop();
            sync_registry_mu.unlock();
            alloc.destroy(o);
            return ERR_NOMEM;
        };
    }
    sync_registry_mu.unlock();
    out.* = o.handle();
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
    if (!supported) return ERR_UNSUPPORTED;
    const idx: u32 = @truncate(handle);
    const gen: u32 = @truncate(handle >> 32);
    sync_registry_mu.lock();
    if (idx >= sync_slots.items.len) {
        sync_registry_mu.unlock();
        return ERR_INVALID_HANDLE;
    }
    const o = sync_slots.items[idx] orelse {
        sync_registry_mu.unlock();
        return ERR_INVALID_HANDLE;
    };
    if (o.gen != gen or o.dead) {
        sync_registry_mu.unlock();
        return ERR_INVALID_HANDLE;
    }
    o.dead = true;
    sync_slots.items[idx] = null;
    sync_free.append(alloc, idx) catch {};
    sync_registry_mu.unlock();
    o.mu.lock();
    while (o.waitq_head) |node| {
        _ = queueRemove(&o.waitq_head, &o.waitq_tail, node);
        fireNode(node, WAKE_DESTROYED);
    }
    o.mu.unlock();
    syncRelease(o);
    return SA_TASK_OK;
}

threadlocal var os_owner_seq: u64 = 0;
var os_owner_counter: std.atomic.Value(u64) = .init(0);

/// Identity of the calling execution context for lock ownership:
/// goroutines use their handle; OS threads use a stable
/// per-thread key in a reserved high range.
fn ownerKey() u64 {
    if (current_g) |g| return g.handle();
    if (os_owner_seq == 0) {
        os_owner_seq = os_owner_counter.fetchAdd(1, .seq_cst) + 1;
    }
    return (@as(u64, 1) << 63) | os_owner_seq;
}

/// Append a waiter for the caller. Caller holds o.mu; the node's
/// owner slot is filled BEFORE the node becomes visible, so a
/// fire can never observe a half-initialized node.
fn syncEnqueue(o: *SyncObj, os_waiter: ?*OsWaiter, is_writer: bool) ?*WaitNode {
    const node = alloc.create(WaitNode) catch return null;
    node.* = .{ .owner_key = ownerKey(), .flag = if (is_writer) 1 else 0 };
    if (current_g) |me| {
        node.g = me;
    } else {
        node.os = os_waiter;
    }
    queuePush(&o.waitq_head, &o.waitq_tail, node);
    return node;
}

/// Complete a park started under o.mu (parkBegin was called by
/// the caller before releasing o.mu on the goroutine path).
fn syncPark(kind: WaitKind, os_waiter: *OsWaiter) i32 {
    if (current_g) |me| {
        me.wait_kind = kind;
        parkSwitch();
        me.wait_kind = .none;
        const s = me.wake_status;
        return if (s == WAKE_DESTROYED) ERR_INVALID_HANDLE else s;
    }
    os_waiter.wait();
    const s = os_waiter.status;
    return if (s == WAKE_DESTROYED) ERR_INVALID_HANDLE else s;
}

// --- Mutex -----------------------------------------------------------

pub export fn sa_sync_mutex_lock(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const o = syncPin(handle) orelse return ERR_INVALID_HANDLE;
    defer syncRelease(o);
    if (o.kind != .mutex) return ERR_INVALID;
    const key = ownerKey();
    o.mu.lock();
    if (!o.locked) {
        o.locked = true;
        o.owner_key = key;
        o.mu.unlock();
        return SA_TASK_OK;
    }
    if (o.owner_key == key) {
        o.mu.unlock();
        return ERR_INVALID; // non-reentrant (documented above)
    }
    var os_waiter: OsWaiter = .{};
    const node = syncEnqueue(o, &os_waiter, false) orelse {
        o.mu.unlock();
        return ERR_NOMEM;
    };
    _ = node;
    if (current_g != null) parkBegin();
    o.mu.unlock();
    return syncPark(.mutex, &os_waiter);
}

pub export fn sa_sync_mutex_try_lock(handle: u64, out_acquired: ?*u32) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const out = out_acquired orelse return ERR_INVALID;
    out.* = 0;
    const o = syncPin(handle) orelse return ERR_INVALID_HANDLE;
    defer syncRelease(o);
    if (o.kind != .mutex) return ERR_INVALID;
    o.mu.lock();
    if (!o.locked) {
        o.locked = true;
        o.owner_key = ownerKey();
        out.* = 1;
    }
    o.mu.unlock();
    return SA_TASK_OK;
}

pub export fn sa_sync_mutex_unlock(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const o = syncPin(handle) orelse return ERR_INVALID_HANDLE;
    defer syncRelease(o);
    if (o.kind != .mutex) return ERR_INVALID;
    const key = ownerKey();
    o.mu.lock();
    if (!o.locked or o.owner_key != key) {
        o.mu.unlock();
        return ERR_INVALID;
    }
    if (o.waitq_head) |node| {
        _ = queueRemove(&o.waitq_head, &o.waitq_tail, node);
        o.owner_key = node.owner_key; // direct handoff, stays locked
        o.mu.unlock();
        fireNode(node, SA_TASK_OK);
        return SA_TASK_OK;
    }
    o.locked = false;
    o.owner_key = 0;
    o.mu.unlock();
    return SA_TASK_OK;
}

// --- RwLock ----------------------------------------------------------

fn rwWakeLocked(o: *SyncObj) void {
    // Caller holds o.mu. Wake the head waiter if admissible:
    // a writer needs exclusivity; readers go as a batch.
    const head = o.waitq_head orelse return;
    if (head.flag == 1) {
        if (o.locked or o.readers != 0) return;
        _ = queueRemove(&o.waitq_head, &o.waitq_tail, head);
        o.locked = true;
        o.owner_key = head.owner_key;
        fireNode(head, SA_TASK_OK);
        return;
    }
    if (o.locked) return;
    var n = o.waitq_head;
    while (n) |node| {
        if (node.flag == 1) break;
        const next = node.next;
        _ = queueRemove(&o.waitq_head, &o.waitq_tail, node);
        o.readers += 1;
        fireNode(node, SA_TASK_OK);
        n = next;
    }
}

pub export fn sa_sync_rwlock_rlock(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const o = syncPin(handle) orelse return ERR_INVALID_HANDLE;
    defer syncRelease(o);
    if (o.kind != .rwlock) return ERR_INVALID;
    o.mu.lock();
    // Writer preference: any queued writer blocks new readers.
    var writer_queued = false;
    var scan = o.waitq_head;
    while (scan) |sn| {
        if (sn.flag == 1) {
            writer_queued = true;
            break;
        }
        scan = sn.next;
    }
    if (!o.locked and !writer_queued) {
        o.readers += 1;
        o.mu.unlock();
        return SA_TASK_OK;
    }
    var os_waiter: OsWaiter = .{};
    _ = syncEnqueue(o, &os_waiter, false) orelse {
        o.mu.unlock();
        return ERR_NOMEM;
    };
    if (current_g != null) parkBegin();
    o.mu.unlock();
    return syncPark(.rwlock, &os_waiter);
}

pub export fn sa_sync_rwlock_runlock(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const o = syncPin(handle) orelse return ERR_INVALID_HANDLE;
    defer syncRelease(o);
    if (o.kind != .rwlock) return ERR_INVALID;
    o.mu.lock();
    if (o.readers == 0) {
        o.mu.unlock();
        return ERR_INVALID;
    }
    o.readers -= 1;
    if (o.readers == 0) rwWakeLocked(o);
    o.mu.unlock();
    return SA_TASK_OK;
}

pub export fn sa_sync_rwlock_lock(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const o = syncPin(handle) orelse return ERR_INVALID_HANDLE;
    defer syncRelease(o);
    if (o.kind != .rwlock) return ERR_INVALID;
    const key = ownerKey();
    o.mu.lock();
    if (!o.locked and o.readers == 0 and o.waitq_head == null) {
        o.locked = true;
        o.owner_key = key;
        o.mu.unlock();
        return SA_TASK_OK;
    }
    if (o.locked and o.owner_key == key) {
        o.mu.unlock();
        return ERR_INVALID; // non-reentrant, incl. read-to-write upgrade
    }
    var os_waiter: OsWaiter = .{};
    _ = syncEnqueue(o, &os_waiter, true) orelse {
        o.mu.unlock();
        return ERR_NOMEM;
    };
    if (current_g != null) parkBegin();
    o.mu.unlock();
    return syncPark(.rwlock, &os_waiter);
}

pub export fn sa_sync_rwlock_unlock(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const o = syncPin(handle) orelse return ERR_INVALID_HANDLE;
    defer syncRelease(o);
    if (o.kind != .rwlock) return ERR_INVALID;
    const key = ownerKey();
    o.mu.lock();
    if (!o.locked or o.owner_key != key) {
        o.mu.unlock();
        return ERR_INVALID;
    }
    o.locked = false;
    o.owner_key = 0;
    rwWakeLocked(o);
    o.mu.unlock();
    return SA_TASK_OK;
}

// --- WaitGroup -------------------------------------------------------

pub export fn sa_sync_waitgroup_add(handle: u64, delta: i64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const o = syncPin(handle) orelse return ERR_INVALID_HANDLE;
    defer syncRelease(o);
    if (o.kind != .waitgroup) return ERR_INVALID;
    o.mu.lock();
    const next = o.counter + delta;
    if (next < 0) {
        o.mu.unlock();
        // Go panics on a negative WaitGroup counter; here it is a
        // boundary trap (process trap when raised on an OS thread).
        raiseTrap(SA_TASK_TRAP_WAITGROUP_NEGATIVE, "sync: negative WaitGroup counter");
    }
    o.counter = next;
    if (next == 0) {
        const waiters = o.waitq_head;
        o.waitq_head = null;
        o.waitq_tail = null;
        o.mu.unlock();
        var n = waiters;
        while (n) |node| {
            const nx = node.next;
            node.linked = false;
            fireNode(node, SA_TASK_OK);
            n = nx;
        }
        return SA_TASK_OK;
    }
    o.mu.unlock();
    return SA_TASK_OK;
}

pub export fn sa_sync_waitgroup_done(handle: u64) i32 {
    return sa_sync_waitgroup_add(handle, -1);
}

pub export fn sa_sync_waitgroup_wait(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const o = syncPin(handle) orelse return ERR_INVALID_HANDLE;
    defer syncRelease(o);
    if (o.kind != .waitgroup) return ERR_INVALID;
    o.mu.lock();
    if (o.counter == 0) {
        o.mu.unlock();
        return SA_TASK_OK;
    }
    var os_waiter: OsWaiter = .{};
    _ = syncEnqueue(o, &os_waiter, false) orelse {
        o.mu.unlock();
        return ERR_NOMEM;
    };
    if (current_g != null) parkBegin();
    o.mu.unlock();
    return syncPark(.waitgroup, &os_waiter);
}

// --- Once ------------------------------------------------------------

pub export fn sa_sync_once_do(handle: u64, entry: ?*const anyopaque, arg: ?*anyopaque) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const o = syncPin(handle) orelse return ERR_INVALID_HANDLE;
    defer syncRelease(o);
    if (o.kind != .once) return ERR_INVALID;
    const f: EntryFn = @ptrCast(@alignCast(entry orelse return ERR_INVALID));
    o.mu.lock();
    if (o.once_done) {
        o.mu.unlock();
        return SA_TASK_OK;
    }
    if (o.once_running) {
        var os_waiter: OsWaiter = .{};
        _ = syncEnqueue(o, &os_waiter, false) orelse {
            o.mu.unlock();
            return ERR_NOMEM;
        };
        if (current_g != null) parkBegin();
        o.mu.unlock();
        return syncPark(.once, &os_waiter);
    }
    o.once_running = true;
    o.mu.unlock();
    f(arg);
    o.mu.lock();
    o.once_done = true;
    o.once_running = false;
    const waiters = o.waitq_head;
    o.waitq_head = null;
    o.waitq_tail = null;
    o.mu.unlock();
    var n = waiters;
    while (n) |node| {
        const nx = node.next;
        node.linked = false;
        fireNode(node, SA_TASK_OK);
        n = nx;
    }
    return SA_TASK_OK;
}

// ---------------------------------------------------------------------
// Phase C tests.

var c_mutex_handle: u64 = 0;
var c_counter: u64 = 0; // guarded by c_mutex_handle; deliberately non-atomic

fn mutexWorker(_: ?*anyopaque) callconv(.c) void {
    var i: usize = 0;
    while (i < 5000) : (i += 1) {
        _ = sa_sync_mutex_lock(c_mutex_handle);
        const p: *u64 = &c_counter;
        p.* += 1;
        _ = sa_sync_mutex_unlock(c_mutex_handle);
    }
}

test "sa_task.test.sync: mutex count race oracle" {
    if (!supported) return error.SkipZigTest;
    try testing.expectEqual(SA_TASK_OK, sa_sync_mutex_new(&c_mutex_handle));
    c_counter = 0;
    var hs: [8]u64 = undefined;
    for (&hs) |*h| try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&mutexWorker, null, h));
    for (hs) |h| try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(@as(u64, 8 * 5000), c_counter);
    try testing.expectEqual(SA_TASK_OK, sa_sync_destroy(c_mutex_handle));
}

test "sa_task.test.sync: mutex ownership rules are explicit" {
    if (!supported) return error.SkipZigTest;
    var m: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_sync_mutex_new(&m));
    try testing.expectEqual(SA_TASK_OK, sa_sync_mutex_lock(m));
    // Non-reentrant: the owner re-locking is an explicit error,
    // not a silent deadlock.
    try testing.expectEqual(ERR_INVALID, sa_sync_mutex_lock(m));
    var acq: u32 = 99;
    try testing.expectEqual(SA_TASK_OK, sa_sync_mutex_try_lock(m, &acq));
    try testing.expectEqual(@as(u32, 0), acq);
    try testing.expectEqual(SA_TASK_OK, sa_sync_mutex_unlock(m));
    try testing.expectEqual(ERR_INVALID, sa_sync_mutex_unlock(m));
    try testing.expectEqual(SA_TASK_OK, sa_sync_mutex_try_lock(m, &acq));
    try testing.expectEqual(@as(u32, 1), acq);
    try testing.expectEqual(SA_TASK_OK, sa_sync_mutex_unlock(m));
    // Wrong-kind handles are rejected, not reinterpreted.
    var rw: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_sync_rwlock_new(&rw));
    try testing.expectEqual(ERR_INVALID, sa_sync_mutex_lock(rw));
    try testing.expectEqual(SA_TASK_OK, sa_sync_destroy(rw));
    try testing.expectEqual(SA_TASK_OK, sa_sync_destroy(m));
    try testing.expectEqual(ERR_INVALID_HANDLE, sa_sync_mutex_lock(m));
}

var c_readers_now: std.atomic.Value(i32) = .init(0);
var c_readers_max: std.atomic.Value(i32) = .init(0);
var c_rwlock_handle: u64 = 0;

fn readerWorker(_: ?*anyopaque) callconv(.c) void {
    _ = sa_sync_rwlock_rlock(c_rwlock_handle);
    const now = c_readers_now.fetchAdd(1, .seq_cst) + 1;
    var cur_max = c_readers_max.load(.seq_cst);
    while (now > cur_max) {
        if (c_readers_max.cmpxchgWeak(cur_max, now, .seq_cst, .seq_cst)) |old| {
            cur_max = old;
        } else break;
    }
    _ = sa_task_sleep_ms(40);
    _ = c_readers_now.fetchSub(1, .seq_cst);
    _ = sa_sync_rwlock_runlock(c_rwlock_handle);
}

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

var c_wg_handle: u64 = 0;
var c_wg_mask: std.atomic.Value(u32) = .init(0);

fn wgWorker(arg: ?*anyopaque) callconv(.c) void {
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

var c_sink_code: std.atomic.Value(i32) = .init(0);

fn cRecordingSink(_: u64, code: i32, _: [*]const u8, _: u64, _: ?*anyopaque) callconv(.c) void {
    c_sink_code.store(code, .seq_cst);
}

fn wgNegativeWorker(arg: ?*anyopaque) callconv(.c) void {
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

var c_once_handle: u64 = 0;
var c_once_runs: std.atomic.Value(u64) = .init(0);

fn onceFn(_: ?*anyopaque) callconv(.c) void {
    _ = sa_task_sleep_ms(20);
    _ = c_once_runs.fetchAdd(1, .seq_cst);
}

fn onceWorker(_: ?*anyopaque) callconv(.c) void {
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
var c_fake_poll_start: i64 = 0;

fn fakePoll(handles: ?[*]const u64, interests: ?[*]const u32, count: u64, timeout_ms: i32, ready: ?[*]u32, out_ready_count: ?*u64) callconv(.c) i32 {
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

const NetResult = struct {
    rc: i32 = -1,
    bits: u32 = 0,
    elapsed: i64 = 0,
};

fn netWaitWorker(arg: ?*anyopaque) callconv(.c) void {
    const res: *NetResult = @ptrCast(@alignCast(arg.?));
    var bits: u32 = 0;
    const t0 = monotonicNs();
    res.rc = sa_task_net_wait(4242, SA_TASK_NET_READ, 5 * std.time.ns_per_s, &bits);
    res.elapsed = monotonicNs() - t0;
    res.bits = bits;
}

fn netTimeoutWorker(arg: ?*anyopaque) callconv(.c) void {
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

fn supervisedTrapWorker(_: ?*anyopaque) callconv(.c) void {
    var ch: u64 = 0;
    _ = sa_chan_make(0, &ch);
    _ = sa_chan_close(ch);
    _ = sa_chan_close(ch); // boundary trap: close of closed channel
}

fn supervisedSendClosedWorker(_: ?*anyopaque) callconv(.c) void {
    var ch: u64 = 0;
    _ = sa_chan_make(1, &ch);
    _ = sa_chan_close(ch);
    var v: Slot = .{ .a = 1 };
    _ = sa_chan_send(ch, &v); // boundary trap: send on closed channel
}

fn supervisedCleanWorker(arg: ?*anyopaque) callconv(.c) void {
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
