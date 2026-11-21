const std = @import("std");
const builtin = @import("builtin");
const ERR_INVALID = @import("t01.zig").ERR_INVALID;
const ERR_INVALID_HANDLE = @import("t01.zig").ERR_INVALID_HANDLE;
const ERR_NOMEM = @import("t01.zig").ERR_NOMEM;
const ERR_UNSUPPORTED = @import("t01.zig").ERR_UNSUPPORTED;
const EntryFn = @import("t01.zig").EntryFn;
const Mutex = @import("t01.zig").Mutex;
const OsWaiter = @import("t01.zig").OsWaiter;
const SA_TASK_OK = @import("t01.zig").SA_TASK_OK;
const SA_TASK_TRAP_WAITGROUP_NEGATIVE = @import("t01.zig").SA_TASK_TRAP_WAITGROUP_NEGATIVE;
const WAKE_DESTROYED = @import("t04.zig").WAKE_DESTROYED;
const WaitKind = @import("t01.zig").WaitKind;
const WaitNode = @import("t01.zig").WaitNode;
const alloc = @import("t01.zig").alloc;
const ensureInit = @import("t03.zig").ensureInit;
const entryIsExecutable = @import("t03.zig").entryIsExecutable;
const fireNode = @import("t02.zig").fireNode;
const parkBegin = @import("t02.zig").parkBegin;
const parkSwitch = @import("t02.zig").parkSwitch;
const queuePush = @import("t05.zig").queuePush;
const queueRemove = @import("t05.zig").queueRemove;
const raiseTrap = @import("t03.zig").raiseTrap;
const sa_task_join = @import("t04.zig").sa_task_join;
const sa_task_sleep_ms = @import("t04.zig").sa_task_sleep_ms;
const sa_task_spawn = @import("t03.zig").sa_task_spawn;
const supported = @import("t01.zig").supported;
const testing = @import("t04.zig").testing;

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
pub const SyncKind = enum(u8) { mutex, rwlock, waitgroup, once };

pub const SyncObj = struct {
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

pub var sync_registry_mu: Mutex = .{};

pub var sync_slots: std.ArrayList(?*SyncObj) = .empty;

// Generations live outside the struct (same UAF lesson as
// channels): the struct is freed at the last pin drop.
pub var sync_gens: std.ArrayList(u32) = .empty;

pub var sync_free: std.ArrayList(u32) = .empty;

pub fn syncPin(handle: u64) ?*SyncObj {
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

pub fn syncRelease(o: *SyncObj) void {
    if (o.refs.fetchSub(1, .seq_cst) == 1) alloc.destroy(o);
}

pub fn syncNew(kind: SyncKind, out_handle: ?*u64) i32 {
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

pub var os_owner_counter: std.atomic.Value(u64) = .init(0);

/// Identity of the calling execution context for lock ownership:
/// goroutines use their handle; OS threads use a stable
/// per-thread key in a reserved high range.
pub fn ownerKey() u64 {
    if (current_g) |g| return g.handle();
    if (os_owner_seq == 0) {
        os_owner_seq = os_owner_counter.fetchAdd(1, .seq_cst) + 1;
    }
    return (@as(u64, 1) << 63) | os_owner_seq;
}

/// Append a waiter for the caller. Caller holds o.mu; the node's
/// owner slot is filled BEFORE the node becomes visible, so a
/// fire can never observe a half-initialized node.
pub fn syncEnqueue(o: *SyncObj, os_waiter: ?*OsWaiter, is_writer: bool) ?*WaitNode {
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
pub fn syncPark(kind: WaitKind, os_waiter: *OsWaiter) i32 {
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
pub fn rwWakeLocked(o: *SyncObj) void {
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
    if (!entryIsExecutable(f)) {
        o.mu.lock();
        o.once_running = false;
        o.mu.unlock();
        return ERR_INVALID;
    }
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
pub var c_mutex_handle: u64 = 0;

pub var c_counter: u64 = 0; // guarded by c_mutex_handle; deliberately non-atomic

pub fn mutexWorker(_: ?*anyopaque) callconv(.c) void {
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

pub var c_readers_now: std.atomic.Value(i32) = .init(0);

pub var c_readers_max: std.atomic.Value(i32) = .init(0);

pub var c_rwlock_handle: u64 = 0;

pub fn readerWorker(_: ?*anyopaque) callconv(.c) void {
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
