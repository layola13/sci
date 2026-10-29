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

fn goroutineExit() noreturn {
    const g = current_g orelse unreachable;
    // Fire join waiters.
    sched_mu.lock();
    const waiters = g.join_waiters;
    g.join_waiters = null;
    g.state.store(.done, .release);
    sched_mu.unlock();
    // Deposit the stack with our carrier for post-switch freeing
    // (the struct may be recycled only after that handoff).
    if (carrier_self) |c| c.exit_region = g.region;
    // Decrement BEFORE waking joiners: once a join returns, the
    // goroutine must already be out of the live count.
    _ = live_count.fetchSub(1, .seq_cst);
    noteProgress();
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
};

// Phase B/C hooks (real implementations land with their phases).
fn selectTimeoutFire(sel: *SelectWaiter, gen: u64) void {
    _ = sel;
    _ = gen;
}

fn netTimeoutFire(nw: *NetWaiter, gen: u64) void {
    _ = nw;
    _ = gen;
}

fn pollNetOnce() void {}

fn netWaiterCount() usize {
    return 0;
}

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

pub export fn sa_task_join(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    if (!ensureInit()) return ERR_UNSUPPORTED;
    const g = registryLookup(handle) orelse return ERR_INVALID_HANDLE;
    if (current_g == g) return ERR_INVALID;
    if (g.state.load(.acquire) == .done) {
        const status: i32 = if (g.trapped) SA_TASK_TRAPPED else SA_TASK_OK;
        registryRecycle(g, g.gen);
        return status;
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
        registryRecycle(g, target_gen);
        return status;
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
        registryRecycle(g, target_gen);
        return status;
    }
    os_waiter.wait();
    const status = os_waiter.status;
    registryRecycle(g, target_gen);
    return status;
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
