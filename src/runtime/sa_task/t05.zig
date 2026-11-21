const std = @import("std");
const builtin = @import("builtin");
const Channel = @import("t04.zig").Channel;
const ERR_INVALID = @import("t01.zig").ERR_INVALID;
const ERR_INVALID_HANDLE = @import("t01.zig").ERR_INVALID_HANDLE;
const ERR_NOMEM = @import("t01.zig").ERR_NOMEM;
const ERR_UNSUPPORTED = @import("t01.zig").ERR_UNSUPPORTED;
const Mutex = @import("t01.zig").Mutex;
const OsWaiter = @import("t01.zig").OsWaiter;
const SA_TASK_OK = @import("t01.zig").SA_TASK_OK;
const SA_TASK_TRAP_CLOSE_OF_CLOSED = @import("t04.zig").SA_TASK_TRAP_CLOSE_OF_CLOSED;
const SA_TASK_TRAP_SEND_ON_CLOSED = @import("t01.zig").SA_TASK_TRAP_SEND_ON_CLOSED;
const SelectWaiter = @import("t03.zig").SelectWaiter;
const Slot = @import("t01.zig").Slot;
const WAKE_DESTROYED = @import("t04.zig").WAKE_DESTROYED;
const WAKE_RECHECK = @import("t04.zig").WAKE_RECHECK;
const WAKE_SEND_ON_CLOSED = @import("t04.zig").WAKE_SEND_ON_CLOSED;
const WaitNode = @import("t01.zig").WaitNode;
const alloc = @import("t01.zig").alloc;
const chanLookup = @import("t04.zig").chanLookup;
const ensureInit = @import("t03.zig").ensureInit;
const fireNode = @import("t02.zig").fireNode;
const parkBegin = @import("t02.zig").parkBegin;
const parkSwitch = @import("t02.zig").parkSwitch;
const raiseTrap = @import("t03.zig").raiseTrap;
const supported = @import("t01.zig").supported;
const unpark = @import("t02.zig").unpark;
const waitNodeAlloc = @import("t02.zig").waitNodeAlloc;
const t04 = @import("t04.zig");
const t02 = @import("t02.zig");

pub fn chanRelease(ch: *Channel) void {
    if (ch.refs.fetchSub(1, .seq_cst) == 1) {
        // Last pin dropped after destroy: free memory.
        if (ch.buf.len > 0) alloc.free(ch.buf);
        alloc.destroy(ch);
    }
}

pub fn queuePush(head: *?*WaitNode, tail: *?*WaitNode, node: *WaitNode) void {
    node.next = null;
    node.linked = true;
    if (tail.*) |t| {
        t.next = node;
    } else {
        head.* = node;
    }
    tail.* = node;
}

pub fn queueRemove(head: *?*WaitNode, tail: *?*WaitNode, node: *WaitNode) bool {
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

pub fn wakeSelectOwner(sel: *SelectWaiter) void {
    if (sel.owner_g) |g| {
        g.wake_status = sel.wake_status;
        unpark(g);
    }
    if (sel.owner_os) |os| {
        os.status = sel.wake_status;
        os.fire();
    }
}

/// SelectWaiter recycling. A blocking select otherwise pays a
/// page_allocator mmap/munmap pair for its waiter on every
/// call. The refs/gen discipline already guarantees that a
/// waiter whose refs reach zero is unreachable: a live timer
/// entry holds a ref until it fires, stale entries are
/// rejected by the gen check before they can touch the
/// waiter, and the owner detaches every wait node (the only
/// path by which a peer can reach the waiter) before dropping
/// its own ref. A zero-ref waiter can therefore be reset and
/// reused safely -- the same envelope that makes destroying
/// it safe today.
pub const SEL_POOL_MAX: usize = 64;

pub var sel_pool_mu: Mutex = .{};

pub var sel_pool_head: ?*SelectWaiter = null;

pub var sel_pool_len: usize = 0;

pub fn selectAlloc() ?*SelectWaiter {
    sel_pool_mu.lock();
    if (sel_pool_head) |sel| {
        sel_pool_head = sel.pool_next;
        sel_pool_len -= 1;
        sel_pool_mu.unlock();
        sel.* = .{};
        return sel;
    }
    sel_pool_mu.unlock();
    const sel = alloc.create(SelectWaiter) catch return null;
    sel.* = .{};
    return sel;
}

pub fn selectRelease(sel: *SelectWaiter) void {
    if (sel.refs.fetchSub(1, .seq_cst) == 1) {
        sel_pool_mu.lock();
        if (sel_pool_len < SEL_POOL_MAX) {
            sel.pool_next = sel_pool_head;
            sel_pool_head = sel;
            sel_pool_len += 1;
            sel_pool_mu.unlock();
            return;
        }
        sel_pool_mu.unlock();
        alloc.destroy(sel);
    }
}

/// Attempt to claim a select waiter for case `index`. On success
/// the caller (holding the channel lock) completes the payload
/// move, detaches the node, then calls wakeSelectOwner.
pub fn selectTryClaim(sel: *SelectWaiter, index: u32, closed_result: bool, wake_status: i32) bool {
    sel.mu.lock();
    defer sel.mu.unlock();
    if (sel.claimed) return false;
    sel.claimed = true;
    sel.chosen = @intCast(index);
    sel.closed_result = closed_result;
    sel.wake_status = wake_status;
    return true;
}

/// Release a claim taken by selectTryClaim during phase-2
/// registration when the readiness re-check that motivated it
/// turns out empty after all (every queued peer was a stale
/// select node). Only the registering owner calls this, while
/// holding the case channel's lock and before the timeout
/// timer is armed: peers that met the claimed flag in the
/// meantime only skipped and detached this select's nodes
/// (never consumed a value for it, never woke the owner), so
/// restoring the unclaimed state is invisible to them.
pub fn selectUnclaim(sel: *SelectWaiter) void {
    sel.mu.lock();
    defer sel.mu.unlock();
    sel.claimed = false;
    sel.chosen = -1;
    sel.closed_result = false;
    sel.wake_status = SA_TASK_OK;
}

pub fn selectTimeoutFire(sel: *SelectWaiter, gen: u64) void {
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
pub fn chanDeliverToReceiver(ch: *Channel, val: Slot) bool {
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
pub fn chanTakeFromSender(ch: *Channel, out: *Slot) enum { got, empty } {
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
pub fn chanTrySend(ch: *Channel, val: Slot) bool {
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
pub fn chanFireAllOnClose(ch: *Channel) void {
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

pub fn chanFireAllOnDestroy(ch: *Channel) void {
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
    t04.chan_registry_mu.lock();
    if (t04.chan_free.pop()) |idx| {
        ch.slot_idx = idx;
        ch.gen = t04.chan_gens.items[idx] +% 1;
        if (ch.gen == 0) ch.gen = 1;
        t04.chan_gens.items[idx] = ch.gen;
        t04.chan_slots.items[idx] = ch;
    } else {
        ch.slot_idx = @intCast(t04.chan_slots.items.len);
        ch.gen = 1;
        t04.chan_slots.append(alloc, ch) catch {
            t04.chan_registry_mu.unlock();
            if (ch.buf.len > 0) alloc.free(ch.buf);
            alloc.destroy(ch);
            return ERR_NOMEM;
        };
        t04.chan_gens.append(alloc, 1) catch {
            _ = t04.chan_slots.pop();
            t04.chan_registry_mu.unlock();
            if (ch.buf.len > 0) alloc.free(ch.buf);
            alloc.destroy(ch);
            return ERR_NOMEM;
        };
    }
    t04.chan_registry_mu.unlock();
    out.* = ch.handle();
    return SA_TASK_OK;
}

pub export fn sa_chan_destroy(handle: u64) i32 {
    if (!supported) return ERR_UNSUPPORTED;
    const idx: u32 = @truncate(handle);
    const gen: u32 = @truncate(handle >> 32);
    t04.chan_registry_mu.lock();
    if (idx >= t04.chan_slots.items.len) {
        t04.chan_registry_mu.unlock();
        return ERR_INVALID_HANDLE;
    }
    const ch = t04.chan_slots.items[idx] orelse {
        t04.chan_registry_mu.unlock();
        return ERR_INVALID_HANDLE;
    };
    if (ch.gen != gen or ch.dead) {
        t04.chan_registry_mu.unlock();
        return ERR_INVALID_HANDLE;
    }
    ch.dead = true;
    t04.chan_registry_mu.unlock();
    ch.mu.lock();
    chanFireAllOnDestroy(ch);
    ch.mu.unlock();
    t04.chan_registry_mu.lock();
    t04.chan_slots.items[idx] = null;
    t04.chan_free.append(alloc, idx) catch {};
    t04.chan_registry_mu.unlock();
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
    const node = waitNodeAlloc() orelse {
        ch.mu.unlock();
        return ERR_NOMEM;
    };
    node.* = .{ .slot = @constCast(val_ptr) };
    var os_waiter: OsWaiter = .{};
    if (t02.current_g) |me| {
        node.g = me;
        me.wait_kind = .chan_send;
    } else {
        node.os = &os_waiter;
    }
    queuePush(&ch.sendq_head, &ch.sendq_tail, node);
    if (t02.current_g) |_| parkBegin();
    ch.mu.unlock();
    if (t02.current_g) |me| {
        parkSwitch();
        me.wait_kind = .none;
        return chanSendWakeStatus(me.wake_status);
    }
    os_waiter.wait();
    return chanSendWakeStatus(os_waiter.status);
}

pub fn chanSendWakeStatus(status: i32) i32 {
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
        const node = waitNodeAlloc() orelse {
            ch.mu.unlock();
            return ERR_NOMEM;
        };
        node.* = .{ .slot = out };
        var os_waiter: OsWaiter = .{};
        if (t02.current_g) |me| {
            node.g = me;
            me.wait_kind = .chan_recv;
        } else {
            node.os = &os_waiter;
        }
        queuePush(&ch.recvq_head, &ch.recvq_tail, node);
        if (t02.current_g) |_| parkBegin();
        ch.mu.unlock();
        var status: i32 = undefined;
        if (t02.current_g) |me| {
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

pub var select_gen_counter: std.atomic.Value(u64) = .init(0);

/// Case-count ceiling for stack-resident channel resolution in
/// sa_chan_select; above this the call falls back to the heap.
pub const SELECT_STACK_CASES: usize = 32;
