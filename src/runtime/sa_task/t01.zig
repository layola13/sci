const std = @import("std");
const builtin = @import("builtin");
const SelectWaiter = @import("t03.zig").SelectWaiter;
const trampoline = @import("t03.zig").trampoline;

pub const linux = std.os.linux;

pub const supported = builtin.cpu.arch == .x86_64 and builtin.os.tag == .linux;

pub const SA_TASK_OK: i32 = 0;

pub const SA_TASK_TRAPPED: i32 = 100;

pub const ERR_INVALID: i32 = 1;

pub const ERR_INVALID_HANDLE: i32 = 2;

pub const ERR_NOT_FOUND: i32 = 3;

pub const ERR_NOMEM: i32 = 5;

pub const ERR_UNSUPPORTED: i32 = 8;

pub const ERR_UNKNOWN: i32 = 127;

// Trap codes recorded in Goroutine.trap_code (boundary recover).
pub const SA_TASK_TRAP_SEND_ON_CLOSED: i32 = 1;

pub const SA_TASK_TRAP_WAITGROUP_NEGATIVE: i32 = 2;

pub const SA_TASK_TRAP_INTERNAL: i32 = 3;

pub const alloc = std.heap.page_allocator;

// ---------------------------------------------------------------------
// Small futex-based primitives (self-contained: no Io, no libc deps
// beyond syscalls, so this module also tests standalone).
pub const Mutex = struct {
    state: std.atomic.Value(u32) = .init(0),

    pub fn lock(m: *Mutex) void {
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

pub fn futexWait(word: *std.atomic.Value(u32), expect: u32, timeout_ns: ?u64) void {
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

pub fn futexWake(word: *std.atomic.Value(u32), n: u32) void {
    if (!supported) return;
    _ = linux.futex_3arg(@ptrCast(&word.raw), .{ .cmd = .WAKE, .private = true }, @intCast(n));
}

/// A blocking wait slot for OS threads (non-goroutine callers).
pub const OsWaiter = struct {
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

pub var external_blocked: std.atomic.Value(usize) = .init(0);

pub var last_progress_ns: std.atomic.Value(i64) = .init(0);

pub fn noteProgress() void {
    last_progress_ns.store(monotonicNs(), .release);
}

pub fn monotonicNs() i64 {
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

pub extern fn sa_task_ctx_switch(old_sp: *u64, new_sp: u64) void;

pub extern fn sa_task_ctx_arm(frame: *RescueFrame) u64;

pub extern fn sa_task_ctx_resume(frame: *const RescueFrame, val: u64) noreturn;

pub fn ctxSwitch(old: *u64, new: u64) void {
    sa_task_ctx_switch(old, new);
}

pub fn ctxResume(frame: *const RescueFrame, val: u64) noreturn {
    sa_task_ctx_resume(frame, val);
}

pub fn stackUnderflowTrap() callconv(.c) noreturn {
    processTrap("goroutine entry returned past its trampoline (stack underflow)");
}

// ---------------------------------------------------------------------
// Goroutine + registry.
pub const EntryFn = *const fn (?*anyopaque) callconv(.c) void;

pub const TrapSinkFn = *const fn (handle: u64, code: i32, msg_ptr: [*]const u8, msg_len: u64, ctx: ?*anyopaque) callconv(.c) void;

pub const State = enum(u8) { empty, runnable, running, parked, done };

pub const WaitKind = enum(u8) {
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

pub const Goroutine = struct {
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
    // DEF-R1: set by sa_task_detach when the spawner declares the
    // handle will never be used (SLA bare `go` statements). A
    // detached record is reaped by the runtime itself once the
    // exit handoff completes — without it, every detached spawn
    // retained its completion record (one page_allocator page per
    // Goroutine struct) forever, ~4,231 B/spawn of unbounded RSS.
    detached: bool = false,

    pub fn handle(g: *const Goroutine) u64 {
        return (@as(u64, g.gen) << 32) | @as(u64, g.slot);
    }
};

/// One monitor subscription (companion): a channel handle to
/// deliver the watched goroutine's exit message to. Allocated at
/// sa_task_monitor, freed at delivery (goroutineExit or the
/// immediate already-exited path).
pub const MonitorSub = struct {
    chan_handle: u64 = 0,
    next: ?*MonitorSub = null,
};

pub const WaitNode = struct {
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
    pool_next: ?*WaitNode = null, // wait-node pool free list
};

pub const Slot = extern struct { a: u64 = 0, b: u64 = 0 };

pub var registry_mu: Mutex = .{};

pub var registry_slots: std.ArrayList(?*Goroutine) = .empty;

pub var registry_free: std.ArrayList(u32) = .empty;

pub fn registryAlloc(entry: EntryFn, arg: ?*anyopaque) ?*Goroutine {
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
    g.detached = false;
    g.transition = false;
    g.unpark_pending = false;
    g.yield_requeue = false;
    return g;
}

pub fn registryLookup(handle: u64) ?*Goroutine {
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
/// Reap a finished record if the exit handoff has completed.
/// Caller must hold registry_mu. When the handoff is still
/// pending, registering the request is enough — runGoroutine
/// completes the reap after the final switch.
pub fn reapIfReadyLocked(g: *Goroutine) void {
    if (g.reaped) return;
    if (g.state.load(.acquire) != .done) return;
    if (!g.exit_handed_off) {
        g.reap_requested = true;
        return;
    }
    g.reaped = true;
    g.state.store(.empty, .release);
    registry_free.append(alloc, g.slot) catch {};
}

pub fn registryRecycle(g: *Goroutine, gen: u32) void {
    registry_mu.lock();
    defer registry_mu.unlock();
    if (g.gen != gen) return; // slot already recycled and reused
    reapIfReadyLocked(g);
}

// ---------------------------------------------------------------------
// Stack allocation (DEF-R2 reserve/commit): one mapping per task,
//   [hard guard PROT_NONE][reserve PROT_NONE][committed RW]
// growing down. At spawn only the top cfg_stack_initial bytes are
// committed (mprotect RW); the rest of the per-task cap is a
// PROT_NONE reservation (MAP_NORESERVE: virtual only, no commit
// charge, no RSS until touched). When execution descends past
// the committed edge, the SIGSEGV handler commits the next span
// in place — addresses never move, so pointers to stack locals
// (out-params, borrowed views) stay valid across growth.
// Descending past the reserve bottom lands in the hard guard
// and aborts (cap exceeded): the same loud path as the old
// fixed-stack overflow.
//
// Why fault-driven commit instead of scheduler-checkpoint
// watermarks: between two checkpoints (yield / chan / select /
// poll / task switch) a goroutine can descend an UNBOUNDED
// amount — giant frames live inside a single call chain between
// chan ops (the validate_kb worker shape) and pure recursion
// has no checkpoints at all. A watermark scheme would need the
// initial commit to cover the worst inter-checkpoint depth,
// which is unknowable; in practice it degenerates into a bigger
// guessed constant. The protection boundary is a per-page check
// that fires on every descent path at zero cost on
// non-faulting paths; it plays exactly the role the DEF-R2
// ruling reserved for compiler stack checks at large-frame
// entries, with no new extern and no codegen change on either
// SLA backend. A single frame larger than the committed span
// faults at its first touch below the edge and the handler
// commits down to the faulting page, so frames of any size up
// to the cap work.
//
// Env semantics (explicit, DEF-R2 — a deliberate redefinition,
// not a silent one):
//   SA_TASK_STACK_KIB — was: total usable stack per task.
//     Now: the INITIAL COMMIT per task, and the guaranteed
//     floor (at least this much is always mapped RW at spawn).
//     Programs that raised it to make deep workloads pass keep
//     working (they pre-commit more; the cap still sits above);
//     it no longer caps total growth — that is the cap env's
//     job. Clamp [64, 8192] KiB, as before.
//   SA_TASK_STACK_CAP_KIB — NEW: the per-task reserve cap, the
//     hard ceiling whose crossing aborts. Default 64 MiB:
//     16x the largest measured natural need ((2MiB, 4MiB] for
//     validate_kb), while the VA cost is negligible (10k tasks
//     x 64 MiB = 640 GiB of the 128 TiB user space) and
//     uncommitted pages cost no RSS. Clamp [1024, 1048576] KiB;
//     raised to the initial commit when configured smaller.
pub const DEFAULT_STACK_USABLE_KIB: u64 = 256;

pub const DEFAULT_STACK_CAP_KIB: u64 = 64 * 1024;

pub const GUARD_KIB: u64 = 64;

/// Growth granularity: a reserve fault commits at least this
/// much beyond the faulting page (bounded by the reserve).
pub const STACK_GROW_QUANTUM: usize = 256 * 1024;

pub var cfg_stack_initial: usize = DEFAULT_STACK_USABLE_KIB * 1024;

pub var cfg_stack_cap: usize = DEFAULT_STACK_CAP_KIB * 1024;

pub var cfg_carriers: usize = 0;

/// Reserve-fault growth events so far (telemetry; the unit
/// tests use it to prove growth happened in place rather than
/// passing via a larger constant).
pub var stack_grow_events: std.atomic.Value(u64) = .init(0);

pub fn allocStack(id: u64) ?[]align(4096) u8 {
    const total = GUARD_KIB * 1024 + cfg_stack_cap;
    const rc = linux.mmap(null, total, linux.PROT{}, .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .NORESERVE = true }, -1, 0);
    if (@as(isize, @bitCast(rc)) < 0) return null;
    const base: [*]align(4096) u8 = @ptrFromInt(rc);
    const top = @intFromPtr(base) + total;
    // Initial commit: the top cfg_stack_initial bytes become RW;
    // guard and reserve stay PROT_NONE.
    const committed_lo = top - cfg_stack_initial;
    const crc = linux.mprotect(@ptrFromInt(committed_lo), cfg_stack_initial, linux.PROT{ .READ = true, .WRITE = true });
    if (@as(isize, @bitCast(crc)) < 0) {
        _ = linux.munmap(base, total);
        return null;
    }
    guardRegister(@intFromPtr(base), top, committed_lo, id);
    return base[0..total];
}

pub fn freeStack(region: []align(4096) u8) void {
    guardUnregister(@intFromPtr(region.ptr));
    _ = linux.munmap(region.ptr, region.len);
}

pub fn initStackFrame(g: *Goroutine) void {
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

// Stack registry for the SIGSEGV handler (overflow trap +
// DEF-R2 growth): fixed table, lock-free reads from the signal
// handler. Each live entry describes one task mapping:
// [lo, lo+GUARD) hard guard, [lo+GUARD, committed_lo) reserve,
// [committed_lo, top) committed RW. committed_lo only ever
// decreases (growth is monotonic; pages are never uncommitted).
pub const GUARD_SLOTS = 16384;

pub const GuardEntry = struct {
    live: std.atomic.Value(bool) = .init(false),
    lo: usize = 0,
    hi: usize = 0, // guard zone end: lo + GUARD_KIB
    top: usize = 0, // mapping end (stack top)
    committed_lo: std.atomic.Value(usize) = .init(0),
    id: u64 = 0,
};

pub var guard_table: [GUARD_SLOTS]GuardEntry = std.mem.zeroes([GUARD_SLOTS]GuardEntry);

pub var guard_hint: std.atomic.Value(usize) = .init(0);

pub fn guardRegister(lo: usize, top: usize, committed_lo: usize, id: u64) void {
    var i: usize = 0;
    while (i < GUARD_SLOTS) : (i += 1) {
        const idx = (guard_hint.load(.monotonic) + i) % GUARD_SLOTS;
        if (guard_table[idx].live.cmpxchgStrong(false, true, .acq_rel, .monotonic) == null) {
            guard_table[idx].lo = lo;
            guard_table[idx].hi = lo + GUARD_KIB * 1024;
            guard_table[idx].top = top;
            guard_table[idx].committed_lo.store(committed_lo, .monotonic);
            guard_table[idx].id = id;
            guard_hint.store(idx + 1, .monotonic);
            return;
        }
    }
}

pub fn guardUnregister(lo: usize) void {
    for (&guard_table) |*e| {
        if (e.live.load(.acquire) and e.lo == lo) {
            e.live.store(false, .release);
            return;
        }
    }
}

/// Guard-zone lookup (the overflow trap's range; also what the
/// unit tests pin): only the hard guard resolves here.
pub fn guardLookup(addr: usize) ?u64 {
    for (&guard_table) |*e| {
        if (e.live.load(.acquire) and addr >= e.lo and addr < e.hi) return e.id;
    }
    return null;
}

/// Full-mapping lookup for the fault handler: any address
/// inside a live task mapping (guard, reserve or committed).
pub fn stackEntryLookup(addr: usize) ?*GuardEntry {
    for (&guard_table) |*e| {
        if (e.live.load(.acquire) and addr >= e.lo and addr < e.top) return e;
    }
    return null;
}

/// DEF-R2 growth: commit the reserved span covering a fault at
/// `addr` in entry `e`. Signal-handler context: raw syscalls
/// and atomics only, no allocation, no locks. Returns true when
/// the fault is covered now (the handler returns and the
/// faulting instruction re-executes); false when the fault is
/// not a growable reserve fault (hard guard = cap exceeded, or
/// already-committed memory).
pub fn stackGrowForFault(e: *GuardEntry, addr: usize) bool {
    const reserve_lo = e.lo + GUARD_KIB * 1024;
    if (addr < reserve_lo) return false; // hard guard: cap exceeded
    const committed = e.committed_lo.load(.monotonic);
    if (addr >= committed) return false; // already RW
    // Commit at least STACK_GROW_QUANTUM past the committed
    // edge, or down to the faulting page when a single frame
    // jumps further than that; never below the reserve bottom.
    var target = addr & ~@as(usize, 4095);
    const quantum_edge = committed -| STACK_GROW_QUANTUM;
    if (target > quantum_edge) target = quantum_edge;
    if (target < reserve_lo) target = reserve_lo;
    if (target >= committed) return true; // a racing grow covered it
    const rc = linux.mprotect(@ptrFromInt(target), committed - target, linux.PROT{ .READ = true, .WRITE = true });
    if (@as(isize, @bitCast(rc)) < 0) return false;
    // Publish monotonically: committed_lo only ever decreases.
    var cur = e.committed_lo.load(.monotonic);
    while (target < cur) {
        if (e.committed_lo.cmpxchgWeak(cur, target, .monotonic, .monotonic)) |prev| {
            cur = prev;
        } else break;
    }
    _ = stack_grow_events.fetchAdd(1, .monotonic);
    return true;
}

// ---------------------------------------------------------------------
// Process-level trap (default boundary) + SIGSEGV overflow trap.
pub fn writeStderr(text: []const u8) void {
    _ = linux.write(2, text.ptr, text.len);
}

pub fn processTrap(msg: []const u8) noreturn {
    writeStderr("sa_task: fatal: ");
    writeStderr(msg);
    writeStderr("\n");
    std.process.abort();
}
