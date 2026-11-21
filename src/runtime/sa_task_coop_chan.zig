const std = @import("std");
const sa_std = @import("sa_task_coop.zig");
const ERR_INVALID = @import("sa_task_coop.zig").ERR_INVALID;
const ERR_INVALID_HANDLE = @import("sa_task_coop.zig").ERR_INVALID_HANDLE;
const ERR_NOMEM = @import("sa_task_coop.zig").ERR_NOMEM;
const SA_TASK_OK = @import("sa_task_coop.zig").SA_TASK_OK;
const Slot = @import("sa_task_coop.zig").Slot;
const Task = @import("sa_task_coop.zig").Task;
const addTimer = @import("sa_task_coop.zig").addTimer;
const alloc = @import("sa_task_coop.zig").alloc;
const blockCurrent = @import("sa_task_coop.zig").blockCurrent;
const coopTrap = @import("sa_task_coop.zig").coopTrap;
const makeHandle = @import("sa_task_coop.zig").makeHandle;
const nowNs = @import("sa_task_coop.zig").nowNs;
const wakeWith = @import("sa_task_coop.zig").wakeWith;

pub const Chan = struct {
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

pub const ChanWaiter = struct {
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

pub const SelectReg = struct {
    task: *Task,
    out_index: *i64,
    out_closed: *u32,
    fired: bool = false,
};

pub var chans: std.ArrayList(?*Chan) = .empty;

pub var chan_gens: std.ArrayList(u32) = .empty;

pub fn chanFromHandle(handle: u64) ?*Chan {
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

pub fn chanHandle(ch: *Chan) u64 {
    for (chans.items, 0..) |slot_chan, i| {
        if (slot_chan == ch) return makeHandle(i, ch.gen);
    }
    return 0;
}

pub fn waiterLive(w: *ChanWaiter) bool {
    if (w.sel) |sel| return !sel.fired;
    return true;
}

pub fn queuePush(head: *?*ChanWaiter, tail: *?*ChanWaiter, w: *ChanWaiter) void {
    w.next = null;
    if (tail.*) |t| {
        t.next = w;
        tail.* = w;
    } else {
        head.* = w;
        tail.* = w;
    }
}

pub fn queuePopLive(head: *?*ChanWaiter, tail: *?*ChanWaiter) ?*ChanWaiter {
    while (head.*) |w| {
        head.* = w.next;
        if (head.* == null) tail.* = null;
        if (waiterLive(w)) return w;
        alloc.destroy(w);
    }
    return null;
}

pub fn queueHasLive(head: ?*ChanWaiter) bool {
    var it = head;
    while (it) |w| {
        if (waiterLive(w)) return true;
        it = w.next;
    }
    return false;
}

pub fn completeSendWaiter(w: *ChanWaiter) void {
    if (w.sel) |sel| {
        fireSelect(sel, @intCast(w.sel_index), 0);
    } else {
        wakeWith(w.task, SA_TASK_OK);
    }
    alloc.destroy(w);
}

pub fn completeRecvWaiter(w: *ChanWaiter, value: Slot, closed_flag: u32) void {
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

pub fn fireSelect(sel: *SelectReg, index: i64, closed_flag: u32) void {
    if (sel.fired) return;
    sel.fired = true;
    sel.out_index.* = index;
    sel.out_closed.* = closed_flag;
    wakeWith(sel.task, SA_TASK_OK);
}

pub fn bufPush(ch: *Chan, value: Slot) void {
    ch.buf[(ch.head + ch.count) % ch.buf.len] = value;
    ch.count += 1;
}

pub fn bufPop(ch: *Chan) Slot {
    const v = ch.buf[ch.head];
    ch.head = (ch.head + 1) % ch.buf.len;
    ch.count -= 1;
    return v;
}

pub fn recvReady(ch: *Chan) bool {
    return ch.count > 0 or queueHasLive(ch.send_q) or ch.closed;
}

pub fn sendReady(ch: *Chan) bool {
    return queueHasLive(ch.recv_q) or ch.count < ch.cap or ch.closed;
}

pub fn doRecv(ch: *Chan, out_value: *Slot, out_closed: *u32) bool {
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

pub fn doSend(ch: *Chan, value: Slot) bool {
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
    const me = sa_std.current orelse return ERR_INVALID;
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
    const me = sa_std.current orelse return ERR_INVALID;
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
    const me = sa_std.current orelse return ERR_INVALID;
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
