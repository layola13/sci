const std = @import("std");
const builtin = @import("builtin");
const current_g = @import("t02.zig").current_g;
const Channel = @import("t04.zig").Channel;
const ERR_INVALID = @import("t01.zig").ERR_INVALID;
const ERR_INVALID_HANDLE = @import("t01.zig").ERR_INVALID_HANDLE;
const ERR_NOMEM = @import("t01.zig").ERR_NOMEM;
const ERR_UNSUPPORTED = @import("t01.zig").ERR_UNSUPPORTED;
const OsWaiter = @import("t01.zig").OsWaiter;
const SA_CHAN_OP_RECV = @import("t04.zig").SA_CHAN_OP_RECV;
const SA_CHAN_OP_SEND = @import("t04.zig").SA_CHAN_OP_SEND;
const SA_TASK_OK = @import("t01.zig").SA_TASK_OK;
const SA_TASK_TRAP_SEND_ON_CLOSED = @import("t01.zig").SA_TASK_TRAP_SEND_ON_CLOSED;
const SELECT_STACK_CASES = @import("t05.zig").SELECT_STACK_CASES;
const Slot = @import("t01.zig").Slot;
const WAKE_DESTROYED = @import("t04.zig").WAKE_DESTROYED;
const WAKE_SEND_ON_CLOSED = @import("t04.zig").WAKE_SEND_ON_CLOSED;
const WaitNode = @import("t01.zig").WaitNode;
const alloc = @import("t01.zig").alloc;
const chanLookup = @import("t04.zig").chanLookup;
const chanRelease = @import("t05.zig").chanRelease;
const chanTakeFromSender = @import("t05.zig").chanTakeFromSender;
const chanTrySend = @import("t05.zig").chanTrySend;
const ensureInit = @import("t03.zig").ensureInit;
const monotonicNs = @import("t01.zig").monotonicNs;
const parkBegin = @import("t02.zig").parkBegin;
const parkCancel = @import("t02.zig").parkCancel;
const parkSwitch = @import("t02.zig").parkSwitch;
const queuePush = @import("t05.zig").queuePush;
const queueRemove = @import("t05.zig").queueRemove;
const raiseTrap = @import("t03.zig").raiseTrap;
const sa_chan_close = @import("t05.zig").sa_chan_close;
const sa_chan_destroy = @import("t05.zig").sa_chan_destroy;
const sa_chan_len = @import("t05.zig").sa_chan_len;
const sa_chan_make = @import("t05.zig").sa_chan_make;
const sa_chan_recv = @import("t05.zig").sa_chan_recv;
const sa_chan_send = @import("t05.zig").sa_chan_send;
const sa_task_join = @import("t04.zig").sa_task_join;
const sa_task_sleep_ms = @import("t04.zig").sa_task_sleep_ms;
const sa_task_spawn = @import("t03.zig").sa_task_spawn;
const selectAlloc = @import("t05.zig").selectAlloc;
const selectRelease = @import("t05.zig").selectRelease;
const selectTryClaim = @import("t05.zig").selectTryClaim;
const selectUnclaim = @import("t05.zig").selectUnclaim;
const select_gen_counter = @import("t05.zig").select_gen_counter;
const supported = @import("t01.zig").supported;
const testing = @import("t04.zig").testing;
const timerAdd = @import("t02.zig").timerAdd;
const wait_node_pool_len = @import("t02.zig").wait_node_pool_len;

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
    // Small case counts resolve into a stack buffer: the ready
    // fast path below must not pay a page_allocator mmap/munmap
    // per call (that tax alone priced a ready-hit select well
    // above a bare recv). Larger counts fall back to the heap.
    var stack_chans: [SELECT_STACK_CASES]?*Channel = undefined;
    for (&stack_chans) |*c| c.* = null;
    const heap_chans: ?[]?*Channel = if (n > SELECT_STACK_CASES) (alloc.alloc(?*Channel, n) catch return ERR_NOMEM) else null;
    if (heap_chans) |hc| {
        for (hc) |*c| c.* = null;
    }
    const chans: []?*Channel = if (heap_chans) |hc| hc else stack_chans[0..n];
    defer {
        for (chans) |c| if (c) |ch| chanRelease(ch);
        if (heap_chans) |hc| alloc.free(hc);
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
    // Zero timeout: the deadline has already expired at entry.
    // Phase 1 found nothing ready, so the timeout outcome is
    // decided -- return it now instead of registering wait
    // nodes and parking for a timer cycle that can only confirm
    // what is already known. (Parking here priced every drain
    // poll of a saturated supervisor at a full park/wake cycle
    // per item, which was the measured completion ceiling.)
    if (timeout_ns == 0) {
        oi.* = -2;
        return SA_TASK_OK;
    }

    // Phase 2: register one node per case and park.
    const sel = selectAlloc() orelse return ERR_NOMEM;
    sel.gen = select_gen_counter.fetchAdd(1, .seq_cst) + 1;
    var os_waiter: OsWaiter = .{};
    if (current_g) |me| {
        sel.owner_g = me;
        me.wait_kind = .select;
    } else {
        sel.owner_os = &os_waiter;
    }
    // Wait nodes for small case counts live on this call's
    // stack. The frame outlives the park; peers touch a node
    // only while it is linked in a channel queue and only
    // under that channel's lock, and the cleanup below
    // detaches every node under the same lock before
    // returning, so no peer can reach a node after this call.
    // The heap path paid a page_allocator mmap + munmap for
    // the pointer array and one mmap + munmap per node on
    // every blocking select; at supervisor park rates that
    // syscall traffic (mmap_lock contention, TLB shootdowns)
    // priced tens of microseconds into the park/wake cycle
    // (the same per-call allocator tax the ready fast path
    // removed for case resolution).
    var stack_nodes: [SELECT_STACK_CASES]WaitNode = undefined;
    var stack_node_ptrs: [SELECT_STACK_CASES]?*WaitNode = undefined;
    const stack_nodes_on = n <= SELECT_STACK_CASES;
    const nodes: []?*WaitNode = if (stack_nodes_on) stack_node_ptrs[0..n] else (alloc.alloc(?*WaitNode, n) catch {
        selectRelease(sel);
        return ERR_NOMEM;
    });
    for (nodes) |*nd| nd.* = null;
    // Mark parked BEFORE registering any case: a peer completing
    // a case during registration fires the waiter, and that wake
    // must find state == parked (see parkBegin). If a claim lands
    // during registration we cancel the park instead of switching.
    if (current_g != null) parkBegin();
    var registered: usize = 0;
    var self_claimed = false;
    for (0..n) |i| {
        const node: *WaitNode = if (stack_nodes_on) &stack_nodes[i] else (alloc.create(WaitNode) catch break);
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
            // Claim BEFORE moving the value (DEF-R4): moving it
            // first and claiming second delivers the payload even
            // when a peer case claimed this select in between --
            // a phantom send the program never observes. The
            // readiness peek is exact under ch.mu except for
            // queues whose nodes are all stale select waiters;
            // that corner surfaces as a failed move after the
            // claim and is rolled back with selectUnclaim.
            if (!ch.closed and (ch.count < ch.cap or ch.recvq_head != null)) {
                if (selectTryClaim(sel, @intCast(i), false, SA_TASK_OK)) {
                    if (chanTrySend(ch, slot_ptrs[i])) {
                        // Detach our own node while still holding
                        // the lock: the value already moved via
                        // chanTrySend, and a queued node would
                        // deliver it a second time to a later
                        // receiver.
                        _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
                        self_claimed = true;
                    } else {
                        selectUnclaim(sel);
                    }
                } else {
                    // A peer case already claimed this select and
                    // carries its outcome; stop registering.
                    _ = queueRemove(&ch.sendq_head, &ch.sendq_tail, node);
                    self_claimed = true;
                }
            }
        } else {
            if (ch.count > 0 or ch.sendq_head != null) {
                // Claim BEFORE taking the value (DEF-R4): taking
                // first fires the sender, and if a peer case then
                // wins the claim the payload has nowhere to go --
                // it vanished between a completed send and a
                // receive that never happens (the slanginx
                // generation-drain wedge: workers exited, their
                // completions lost, in_flight never reached 0).
                if (selectTryClaim(sel, @intCast(i), false, SA_TASK_OK)) {
                    var v: Slot = undefined;
                    if (chanTakeFromSender(ch, &v) == .got) {
                        slot_ptrs[i] = v;
                        _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
                        self_claimed = true;
                    } else {
                        selectUnclaim(sel);
                    }
                } else {
                    _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
                    self_claimed = true;
                }
            } else if (ch.closed) {
                if (selectTryClaim(sel, @intCast(i), true, SA_TASK_OK)) {
                    slot_ptrs[i] = .{};
                    _ = queueRemove(&ch.recvq_head, &ch.recvq_tail, node);
                    self_claimed = true;
                } else {
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
            if (!stack_nodes_on) alloc.destroy(node);
        }
        if (!stack_nodes_on) alloc.free(nodes);
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
        if (!stack_nodes_on) alloc.destroy(node);
    }
    if (!stack_nodes_on) alloc.free(nodes);
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
pub fn pingPongProducer(arg: ?*anyopaque) callconv(.c) void {
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

pub var block_send_done: std.atomic.Value(bool) = .init(false);

pub fn blockedSender(arg: ?*anyopaque) callconv(.c) void {
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

pub const ProdCons = struct {
    ch: u64 = 0,
    total: std.atomic.Value(u64) = .init(0),
    count: std.atomic.Value(u64) = .init(0),
};

pub var prodcons: ProdCons = .{};

pub fn pcProducer(arg: ?*anyopaque) callconv(.c) void {
    const pid: u64 = @intFromPtr(arg.?) - 1;
    var i: u64 = 0;
    while (i < 250) : (i += 1) {
        var v: Slot = .{ .a = pid * 1000 + i, .b = 0 };
        _ = sa_chan_send(prodcons.ch, &v);
    }
}

pub fn pcConsumer(_: ?*anyopaque) callconv(.c) void {
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

pub fn poolCycleProducer(arg: ?*anyopaque) callconv(.c) void {
    const ch: u64 = @intFromPtr(arg.?);
    var i: u64 = 0;
    while (i < 5000) : (i += 1) {
        var v: Slot = .{ .a = i, .b = i * 3 };
        _ = sa_chan_send(ch, &v);
    }
    _ = sa_chan_close(ch);
}

test "sa_task.test.chan: pooled wait nodes keep delivery integrity across park cycles" {
    if (!supported) return error.SkipZigTest;
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &ch));
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&poolCycleProducer, @ptrFromInt(@as(usize, @intCast(ch))), &h));
    // Every producer send parks on the unbuffered channel; its
    // node is fired by the recv below and must come back through
    // the pool thousands of times without corrupting delivery.
    var i: u64 = 0;
    while (i < 5000) : (i += 1) {
        var out: Slot = undefined;
        var closed: u32 = 99;
        try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, &closed));
        try testing.expectEqual(@as(u32, 0), closed);
        try testing.expectEqual(i, out.a);
        try testing.expectEqual(i * 3, out.b);
    }
    var out: Slot = undefined;
    var closed: u32 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, &closed));
    try testing.expectEqual(@as(u32, 1), closed);
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    // The pool must actually be holding recycled nodes (if the
    // release path regresses to destroy, this stays 0).
    try testing.expect(wait_node_pool_len > 0);
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}

pub var pool_blocked_got: std.atomic.Value(u64) = .init(0);

pub var pool_blocked_closed: std.atomic.Value(u32) = .init(99);

pub fn poolBlockedReceiver(arg: ?*anyopaque) callconv(.c) void {
    const ch: u64 = @intFromPtr(arg.?);
    var out: Slot = undefined;
    var closed: u32 = 0;
    _ = sa_chan_recv(ch, &out, &closed);
    pool_blocked_got.store(out.a, .release);
    pool_blocked_closed.store(closed, .release);
}

test "sa_task.test.chan: pooled nodes wake precisely (value, drain, close)" {
    if (!supported) return error.SkipZigTest;
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(1, &ch));
    // Rotate the pool first so the waits below run on recycled
    // nodes: a blocked receiver claimed by a send...
    pool_blocked_got.store(0, .release);
    pool_blocked_closed.store(99, .release);
    var h: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&poolBlockedReceiver, @ptrFromInt(@as(usize, @intCast(ch))), &h));
    _ = sa_task_sleep_ms(60);
    var v: Slot = .{ .a = 77, .b = 0 };
    try testing.expectEqual(SA_TASK_OK, sa_chan_send(ch, &v));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h));
    try testing.expectEqual(@as(u64, 77), pool_blocked_got.load(.acquire));
    try testing.expectEqual(@as(u32, 0), pool_blocked_closed.load(.acquire));
    // ...a blocked sender released by a drain...
    var v5: Slot = .{ .a = 5, .b = 0 };
    try testing.expectEqual(SA_TASK_OK, sa_chan_send(ch, &v5));
    block_send_done.store(false, .release);
    var h2: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&blockedSender, @ptrFromInt(@as(usize, @intCast(ch))), &h2));
    _ = sa_task_sleep_ms(60);
    try testing.expect(!block_send_done.load(.acquire));
    var out: Slot = undefined;
    try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, null));
    try testing.expectEqual(@as(u64, 5), out.a);
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h2));
    try testing.expect(block_send_done.load(.acquire));
    try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, null));
    try testing.expectEqual(@as(u64, 44), out.a);
    // ...and a blocked receiver woken by close (recheck path).
    pool_blocked_closed.store(99, .release);
    var h3: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_task_spawn(&poolBlockedReceiver, @ptrFromInt(@as(usize, @intCast(ch))), &h3));
    _ = sa_task_sleep_ms(60);
    try testing.expectEqual(SA_TASK_OK, sa_chan_close(ch));
    try testing.expectEqual(SA_TASK_OK, sa_task_join(h3));
    try testing.expectEqual(@as(u32, 1), pool_blocked_closed.load(.acquire));
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
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

test "sa_task.test.select: zero timeout returns immediately on empty channel" {
    if (!supported) return error.SkipZigTest;
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(0, &ch));
    var chans = [1]u64{ch};
    var ops = [1]u32{SA_CHAN_OP_RECV};
    var slots = [1]Slot{.{}};
    var idx: i64 = -99;
    // One call: timeout outcome (-2), no value.
    try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans, &ops, &slots, 1, 0, 0, &idx, null));
    try testing.expectEqual(@as(i64, -2), idx);
    // A drain loop of zero-timeout polls must not pay a park /
    // timer cycle per call: 2000 polls complete in a small
    // fraction of the ~100us-per-poll the parking path charged.
    const t0 = monotonicNs();
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        idx = -99;
        try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans, &ops, &slots, 1, 0, 0, &idx, null));
        try testing.expectEqual(@as(i64, -2), idx);
    }
    try testing.expect(monotonicNs() - t0 < 20 * std.time.ns_per_ms);
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}

test "sa_task.test.select: ready arm beats zero timeout" {
    if (!supported) return error.SkipZigTest;
    var ch: u64 = 0;
    try testing.expectEqual(SA_TASK_OK, sa_chan_make(1, &ch));
    var v: Slot = .{ .a = 4242, .b = 0 };
    try testing.expectEqual(SA_TASK_OK, sa_chan_send(ch, &v));
    var chans = [1]u64{ch};
    var ops = [1]u32{SA_CHAN_OP_RECV};
    var slots = [1]Slot{.{}};
    var idx: i64 = -99;
    try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans, &ops, &slots, 1, 0, 0, &idx, null));
    try testing.expectEqual(@as(i64, 0), idx);
    try testing.expectEqual(@as(u64, 4242), slots[0].a);
    // Send arm with buffer space also resolves immediately.
    var chans2 = [1]u64{ch};
    var ops2 = [1]u32{SA_CHAN_OP_SEND};
    var slots2 = [1]Slot{.{ .a = 5150, .b = 0 }};
    idx = -99;
    try testing.expectEqual(SA_TASK_OK, sa_chan_select(&chans2, &ops2, &slots2, 1, 0, 0, &idx, null));
    try testing.expectEqual(@as(i64, 0), idx);
    var out: Slot = undefined;
    try testing.expectEqual(SA_TASK_OK, sa_chan_recv(ch, &out, null));
    try testing.expectEqual(@as(u64, 5150), out.a);
    try testing.expectEqual(SA_TASK_OK, sa_chan_destroy(ch));
}
