const std = @import("std");
const sa_std = @import("sa_task_coop.zig");
const ERR_INVALID = @import("sa_task_coop.zig").ERR_INVALID;
const ERR_INVALID_HANDLE = @import("sa_task_coop.zig").ERR_INVALID_HANDLE;
const ERR_NOMEM = @import("sa_task_coop.zig").ERR_NOMEM;
const EntryFn = @import("sa_task_coop.zig").EntryFn;
const SA_TASK_OK = @import("sa_task_coop.zig").SA_TASK_OK;
const Task = @import("sa_task_coop.zig").Task;
const alloc = @import("sa_task_coop.zig").alloc;
const blockCurrent = @import("sa_task_coop.zig").blockCurrent;
const coopTrap = @import("sa_task_coop.zig").coopTrap;
const makeHandle = @import("sa_task_coop.zig").makeHandle;
const wakeWith = @import("sa_task_coop.zig").wakeWith;

pub const SyncKind = enum { mutex, rwlock, waitgroup, once };

pub const SyncObj = struct {
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

pub const WaitNode = struct {
    task: *Task,
    next: ?*WaitNode = null,
};

pub const TaskQueue = struct {
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

pub var syncs: std.ArrayList(?*SyncObj) = .empty;

pub var sync_gens: std.ArrayList(u32) = .empty;

pub fn syncFromHandle(handle: u64, kind: ?SyncKind) ?*SyncObj {
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

pub fn syncNew(kind: SyncKind, out_handle: ?*u64) i32 {
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
    const me = sa_std.current orelse return ERR_INVALID;
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
    const me = sa_std.current orelse return ERR_INVALID;
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
    const me = sa_std.current orelse return ERR_INVALID;
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
    const me = sa_std.current orelse return ERR_INVALID;
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
    const me = sa_std.current orelse return ERR_INVALID;
    if (o.rw_writer == null and o.rw_readers == 0 and o.rw_wqueue.head == null) {
        o.rw_writer = me;
        return SA_TASK_OK;
    }
    o.rw_wqueue.push(me) catch return ERR_NOMEM;
    return blockCurrent();
}

pub export fn sa_sync_rwlock_unlock(handle: u64) i32 {
    const o = syncFromHandle(handle, .rwlock) orelse return ERR_INVALID_HANDLE;
    const me = sa_std.current orelse return ERR_INVALID;
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
    const me = sa_std.current orelse return ERR_INVALID;
    o.wg_queue.push(me) catch return ERR_NOMEM;
    return blockCurrent();
}

pub export fn sa_sync_once_do(handle: u64, entry: ?*const anyopaque, arg: ?*anyopaque) i32 {
    const o = syncFromHandle(handle, .once) orelse return ERR_INVALID_HANDLE;
    if (o.once_done) return SA_TASK_OK;
    const me = sa_std.current orelse return ERR_INVALID;
    if (o.once_running) {
        o.once_queue.push(me) catch return ERR_NOMEM;
        return blockCurrent();
    }
    const e = entry orelse return ERR_INVALID;
    const entry_fn: EntryFn = @ptrCast(@alignCast(e));
    o.once_running = true;
    sa_std.suspend_forbidden += 1;
    entry_fn(arg);
    sa_std.suspend_forbidden -= 1;
    o.once_running = false;
    o.once_done = true;
    o.once_queue.wakeAll(SA_TASK_OK);
    return SA_TASK_OK;
}
