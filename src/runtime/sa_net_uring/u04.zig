const std = @import("std");
const builtin = @import("builtin");
const sa_std = @import("../sa_std.zig");
const net_primitives = @import("sa_net_primitives");
const sio = @import("sio");
const Condition = @import("u01.zig").Condition;
const ConnectionSlot = @import("u01.zig").ConnectionSlot;
const Mutex = @import("u01.zig").Mutex;
const NetxProto_RAW = @import("u01.zig").NetxProto_RAW;
const Reactor = @import("u02.zig").Reactor;
const SA_NETX_ERR_INVALID_ARGUMENT = @import("u01.zig").SA_NETX_ERR_INVALID_ARGUMENT;
const SA_NETX_ERR_INVALID_HANDLE = @import("u01.zig").SA_NETX_ERR_INVALID_HANDLE;
const SA_NETX_ERR_IO = @import("u01.zig").SA_NETX_ERR_IO;
const SA_NETX_ERR_NET = @import("u01.zig").SA_NETX_ERR_NET;
const SA_NETX_ERR_NOT_FOUND = @import("u01.zig").SA_NETX_ERR_NOT_FOUND;
const SA_NETX_ERR_NO_MEMORY = @import("u01.zig").SA_NETX_ERR_NO_MEMORY;
const SA_NETX_ERR_UNSUPPORTED = @import("u01.zig").SA_NETX_ERR_UNSUPPORTED;
const SA_NETX_OK = @import("u01.zig").SA_NETX_OK;
const SlotPool = @import("u01.zig").SlotPool;
const Thread = @import("u01.zig").Thread;
const Ticket = @import("u01.zig").Ticket;
const TicketOp = @import("u01.zig").TicketOp;
const TicketQueue = @import("u01.zig").TicketQueue;
const ceilPow2 = @import("u03.zig").ceilPow2;
const computeTicketCapacity = @import("u03.zig").computeTicketCapacity;
const fieldSlice = @import("u03.zig").fieldSlice;
const findCrlfVector = @import("u03.zig").findCrlfVector;
const findHttpHeaderEndVector = @import("u03.zig").findHttpHeaderEndVector;
const linux = @import("u01.zig").linux;
const makeTicket = @import("u03.zig").makeTicket;
const maybeHttpPrefixVector = @import("u03.zig").maybeHttpPrefixVector;
const net = @import("u01.zig").net;
const parseHttpRequest = @import("u03.zig").parseHttpRequest;
const parseWsFrame = @import("u03.zig").parseWsFrame;
const posix = @import("u01.zig").posix;
const resumeSlot = @import("u03.zig").resumeSlot;
const ticket_payload_capacity = @import("u01.zig").ticket_payload_capacity;
const unmaskFrame = @import("u03.zig").unmaskFrame;
const websocketAccept = @import("u03.zig").websocketAccept;
const u03 = @import("u03.zig");

pub export fn sa_netx_init(slot_capacity: u64, reactor_count: u32) i32 {
    if (builtin.os.tag != .linux) return SA_NETX_ERR_UNSUPPORTED;
    if (slot_capacity == 0 or reactor_count == 0) return SA_NETX_ERR_INVALID_ARGUMENT;
    if (u03.runtime_state.initialized) return SA_NETX_ERR_INVALID_ARGUMENT;

    const slot_capacity_usize = std.math.cast(usize, slot_capacity) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    if (slot_capacity_usize > std.math.maxInt(u32)) return SA_NETX_ERR_INVALID_ARGUMENT;
    const reactor_count_usize = @as(usize, @intCast(reactor_count));
    const ticket_capacity = computeTicketCapacity(slot_capacity_usize) catch return SA_NETX_ERR_INVALID_ARGUMENT;

    const pool = SlotPool.init(slot_capacity_usize) catch return SA_NETX_ERR_NO_MEMORY;
    var reactors = std.heap.page_allocator.alloc(Reactor, reactor_count_usize) catch {
        var pool_owned = pool;
        pool_owned.deinit();
        return SA_NETX_ERR_NO_MEMORY;
    };

    var i: usize = 0;
    while (i < reactors.len) : (i += 1) {
        reactors[i] = Reactor.init(@as(u32, @intCast(i)), ticket_capacity) catch |err| {
            var j: usize = 0;
            while (j < i) : (j += 1) reactors[j].deinit();
            std.heap.page_allocator.free(reactors);
            var pool_owned = pool;
            pool_owned.deinit();
            return if (err == error.IoUringUnavailable) SA_NETX_ERR_UNSUPPORTED else SA_NETX_ERR_IO;
        };
    }

    u03.runtime_state = .{
        .initialized = true,
        .slot_pool = pool,
        .reactors = reactors,
        .reactor_count = reactors.len,
        .listened = false,
        .listen_address = null,
        .ticket_capacity = ticket_capacity,
    };

    for (reactors) |*reactor| {
        reactor.startWorker() catch {
            u03.runtime_state.worker_state.mutex.lockUncancelable(sio.io());
            u03.runtime_state.worker_state.stop = true;
            u03.runtime_state.worker_state.cond.broadcast(sio.io());
            u03.runtime_state.worker_state.mutex.unlock(sio.io());
            var j: usize = 0;
            while (j < reactors.len) : (j += 1) reactors[j].deinit();
            std.heap.page_allocator.free(reactors);
            var pool_owned = pool;
            pool_owned.deinit();
            u03.runtime_state = .{};
            return SA_NETX_ERR_IO;
        };
    }

    return SA_NETX_OK;
}

pub export fn sa_netx_listen(host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    if (!u03.runtime_state.initialized) return SA_NETX_ERR_INVALID_HANDLE;
    if (u03.runtime_state.listened) return SA_NETX_ERR_INVALID_ARGUMENT;
    const host = if (host_len == 0) "0.0.0.0" else blk: {
        const ptr = host_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        const n = std.math.cast(usize, host_len) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        const host_slice = ptr[0..n];
        if (std.mem.indexOfScalar(u8, host_slice, 0) != null) return SA_NETX_ERR_INVALID_ARGUMENT;
        break :blk host_slice;
    };
    const address = net.IpAddress.resolve(sio.io(), host, port) catch return SA_NETX_ERR_NET;
    if (u03.runtime_state.reactors.len == 0) return SA_NETX_ERR_INVALID_HANDLE;

    const first_result = u03.runtime_state.reactors[0].beginCommand(.{
        .kind = .listen,
        .slot_id = 0,
        .address = address,
    });
    if (first_result != SA_NETX_OK) return first_result;

    const listen_address = u03.runtime_state.reactors[0].server orelse return SA_NETX_ERR_IO;
    u03.runtime_state.listen_address = listen_address.socket.address;

    var idx: usize = 1;
    while (idx < u03.runtime_state.reactors.len) : (idx += 1) {
        const result = u03.runtime_state.reactors[idx].beginCommand(.{
            .kind = .listen,
            .slot_id = 0,
            .address = u03.runtime_state.listen_address.?,
        });
        if (result != SA_NETX_OK) {
            var rollback_idx: usize = 0;
            while (rollback_idx < idx) : (rollback_idx += 1) {
                _ = u03.runtime_state.reactors[rollback_idx].beginCommand(.{
                    .kind = .listen,
                    .slot_id = 0,
                    .address = null,
                });
            }
            u03.runtime_state.listen_address = null;
            return result;
        }
    }
    u03.runtime_state.listened = true;
    return SA_NETX_OK;
}

pub export fn sa_netx_recv_ticket(reactor_id: u32, out_ticket: ?*Ticket) i32 {
    const ticket_ptr = out_ticket orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const reactor = getReactor(reactor_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    reactor.ticket_mutex.lockUncancelable(sio.io());
    defer reactor.ticket_mutex.unlock(sio.io());
    while (reactor.tickets.isEmpty()) {
        if (u03.runtime_state.worker_state.stop) return SA_NETX_ERR_NOT_FOUND;
        reactor.ticket_cond.waitUncancelable(sio.io(), &reactor.ticket_mutex);
    }
    const ticket = reactor.tickets.pop().?;
    ticket_ptr.* = ticket;
    if (u03.runtime_state.slot_pool) |*pool| {
        if (pool.slotFromId(ticket.slot_id)) |slot| {
            resumeSlot(reactor, slot) catch |err| {
                // Resume requests are retried through the reactor queue; this call only nudges current progress.
                _ = @errorName(err);
            };
        }
    }
    reactor.requestResume();
    return SA_NETX_OK;
}

pub export fn sa_netx_push_outbound(reactor_id: u32, slot_id: u32, msg_ptr: ?[*]const u8, len: u32) i32 {
    const reactor = getReactor(reactor_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    const msg = if (len == 0) &[_]u8{} else blk: {
        const ptr = msg_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        break :blk ptr[0..@as(usize, @intCast(len))];
    };
    return reactor.beginCommand(.{
        .kind = .send,
        .slot_id = slot_id,
        .use_zc = msg.len >= 1536,
        .msg_ptr = msg.ptr,
        .msg_len = msg.len,
    });
}

pub export fn sa_netx_broadcast(reactor_id: u32, slot_ids_ptr: ?[*]const u32, n: u32, msg_ptr: ?[*]const u8, len: u32) i32 {
    const reactor = getReactor(reactor_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    const slots = if (n == 0) &[_]u32{} else blk: {
        const ptr = slot_ids_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        break :blk ptr[0..@as(usize, @intCast(n))];
    };
    const msg = if (len == 0) &[_]u8{} else blk: {
        const ptr = msg_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        break :blk ptr[0..@as(usize, @intCast(len))];
    };
    return reactor.beginCommand(.{
        .kind = .broadcast,
        .slot_id = 0,
        .use_zc = slots.len >= 8 or msg.len >= 1536,
        .msg_ptr = msg.ptr,
        .msg_len = msg.len,
        .slot_ids_ptr = slots.ptr,
        .slot_ids_len = slots.len,
    });
}

pub export fn sa_netx_close_slot(slot_id: u32) i32 {
    if (!u03.runtime_state.initialized) return SA_NETX_ERR_INVALID_HANDLE;
    const pool = u03.runtime_state.slot_pool orelse return SA_NETX_ERR_INVALID_HANDLE;
    const slot = pool.slotFromId(slot_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    const reactor = getReactor(slot.reactor_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    return reactor.beginCommand(.{
        .kind = .close,
        .slot_id = slot_id,
    });
}

pub export fn sa_netx_shutdown() i32 {
    if (!u03.runtime_state.initialized) return SA_NETX_OK;
    u03.runtime_state.worker_state.mutex.lockUncancelable(sio.io());
    u03.runtime_state.worker_state.stop = true;
    u03.runtime_state.worker_state.cond.broadcast(sio.io());
    u03.runtime_state.worker_state.mutex.unlock(sio.io());
    if (u03.runtime_state.reactors.len != 0) {
        for (u03.runtime_state.reactors) |*reactor| {
            reactor.ticket_cond.broadcast(sio.io());
            reactor.deinit();
        }
        std.heap.page_allocator.free(u03.runtime_state.reactors);
    }
    if (u03.runtime_state.slot_pool) |*pool| {
        pool.deinit();
    }
    u03.runtime_state = .{};
    return SA_NETX_OK;
}

pub fn getReactor(reactor_id: u32) ?*Reactor {
    if (!u03.runtime_state.initialized) return null;
    const idx = @as(usize, @intCast(reactor_id));
    if (idx >= u03.runtime_state.reactors.len) return null;
    return &u03.runtime_state.reactors[idx];
}

pub const LoopbackClient = struct {
    address: net.IpAddress,
    request: []const u8,
    received: [256]u8 = undefined,
    received_len: usize = 0,
};

pub const WsLoopbackClient = struct {
    address: net.IpAddress,
    request: []const u8,
    expected_payload: []const u8,
    expected_frame_len: usize,
    received: [256]u8 = undefined,
    received_len: usize = 0,
    upgrade_response: [256]u8 = undefined,
    upgrade_len: usize = 0,
    frame_buf: [256]u8 = undefined,
    frame_len: usize = 0,
};

pub const TicketCollector = struct {
    reactor_id: u32,
    tickets: []Ticket,
    mutex: Mutex = .init,
    cond: Condition = .init,
    count: usize = 0,
    result: i32 = SA_NETX_OK,
};

pub const TestTimeval = std.posix.timeval;

pub const TestTimevalSec = @TypeOf(@as(TestTimeval, .{ .sec = 0, .usec = 0 }).sec);

pub const TestTimevalUsec = @TypeOf(@as(TestTimeval, .{ .sec = 0, .usec = 0 }).usec);

pub fn setLoopbackReadTimeout(stream: net.Stream) void {
    const timeout_ns: u64 = 2 * std.time.ns_per_s;
    const tv = TestTimeval{
        .sec = std.math.cast(TestTimevalSec, timeout_ns / std.time.ns_per_s) orelse 2,
        .usec = std.math.cast(TestTimevalUsec, (timeout_ns % std.time.ns_per_s) / std.time.ns_per_us) orelse 0,
    };
    std.posix.setsockopt(stream.socket.handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&tv)) catch {};
}

pub fn ticketPayload(ticket: Ticket) []const u8 {
    return @as([*]const u8, @ptrCast(ticket.payload))[0..@as(usize, @intCast(ticket.payload_len))];
}

pub fn loopbackClientMain(client: *LoopbackClient) void {
    const stream = client.address.connect(sio.io(), .{ .mode = .stream }) catch return;
    defer stream.close(sio.io());
    setLoopbackReadTimeout(stream);

    var wbuf_lb: [4096]u8 = undefined;
    var w_lb = stream.writer(sio.io(), &wbuf_lb);
    w_lb.interface.writeAll(client.request) catch return;
    w_lb.interface.flush() catch return;

    var total: usize = 0;
    var buf: [64]u8 = undefined;
    while (total < client.received.len) {
        const read_len = std.posix.read(stream.socket.handle, buf[0..]) catch return;
        if (read_len == 0) break;
        const copy_len = @min(client.received.len - total, read_len);
        if (copy_len != 0) {
            @memcpy(client.received[total .. total + copy_len], buf[0..copy_len]);
            total += copy_len;
        }
    }
    client.received_len = total;
}

pub fn wsLoopbackClientMain(client: *WsLoopbackClient) void {
    const stream = client.address.connect(sio.io(), .{ .mode = .stream }) catch return;
    defer stream.close(sio.io());
    setLoopbackReadTimeout(stream);

    var wbuf_ws: [4096]u8 = undefined;
    var w_ws = stream.writer(sio.io(), &wbuf_ws);
    w_ws.interface.writeAll(client.request) catch return;
    w_ws.interface.flush() catch return;

    var frame_start: usize = 0;
    var upgrade_total: usize = 0;
    while (upgrade_total < client.upgrade_response.len) {
        const read_len = std.posix.read(stream.socket.handle, client.upgrade_response[upgrade_total..]) catch return;
        if (read_len == 0) break;
        upgrade_total += read_len;
        if (std.mem.indexOf(u8, client.upgrade_response[0..upgrade_total], "\r\n\r\n")) |idx| {
            const end = idx + 4;
            const tail = upgrade_total - end;
            if (tail != 0) {
                @memcpy(client.frame_buf[0..tail], client.upgrade_response[end..upgrade_total]);
                frame_start = tail;
            }
            upgrade_total = end;
            break;
        }
    }
    client.upgrade_len = upgrade_total;

    var total: usize = frame_start;
    if (frame_start != 0) {
        @memcpy(client.received[0..frame_start], client.frame_buf[0..frame_start]);
    }
    while (total < client.expected_frame_len) {
        const read_len = std.posix.read(stream.socket.handle, client.frame_buf[0..]) catch return;
        if (read_len == 0) break;
        const copy_len = @min(client.received.len - total, read_len);
        if (copy_len != 0) {
            @memcpy(client.received[total .. total + copy_len], client.frame_buf[0..copy_len]);
            total += copy_len;
        }
    }
    client.frame_len = total;
    client.received_len = total;
}

pub fn collectTicketsMain(state: *TicketCollector) void {
    var index: usize = 0;
    while (index < state.tickets.len) : (index += 1) {
        var ticket: Ticket = undefined;
        const result = sa_netx_recv_ticket(state.reactor_id, &ticket);
        state.mutex.lockUncancelable(sio.io());
        if (result != SA_NETX_OK) {
            state.result = result;
            state.cond.broadcast(sio.io());
            state.mutex.unlock(sio.io());
            return;
        }
        state.tickets[index] = ticket;
        state.count = index + 1;
        state.cond.broadcast(sio.io());
        state.mutex.unlock(sio.io());
    }
}

test "ticket layout is stable" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(Ticket));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Ticket, "slot_id"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(Ticket, "op_code"));
    try std.testing.expectEqual(@as(usize, 6), @offsetOf(Ticket, "proto"));
    try std.testing.expectEqual(@as(usize, 7), @offsetOf(Ticket, "flags"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Ticket, "payload"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Ticket, "payload_len"));
    try std.testing.expectEqual(@as(usize, 20), @offsetOf(Ticket, "pad"));
}

test "ticket queue owns payload bytes after slot scratch changes" {
    var queue = try TicketQueue.init(2);
    defer queue.deinit();

    var slot: ConnectionSlot = .{};
    slot.initFree(1);
    slot.slot_id = 1;
    @memcpy(slot.scratch[0..5], "hello");

    const ticket = makeTicket(&slot, .raw_bytes, NetxProto_RAW, 0, slot.scratch[0..5]);
    try std.testing.expect(queue.push(ticket));
    @memset(slot.scratch[0..5], 'x');

    const popped = queue.pop() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("hello", ticketPayload(popped));
}

test "ticket queue rejects oversized payload copies" {
    var queue = try TicketQueue.init(2);
    defer queue.deinit();

    var byte: u8 = 0;
    const ticket = Ticket{
        .slot_id = 1,
        .op_code = @intFromEnum(TicketOp.raw_bytes),
        .proto = NetxProto_RAW,
        .flags = 0,
        .payload = &byte,
        .payload_len = @as(u32, @intCast(ticket_payload_capacity + 1)),
        .pad = 0,
    };
    try std.testing.expect(!queue.push(ticket));
}

test "netx capacity math rejects overflow" {
    try std.testing.expectEqual(@as(usize, 64), try ceilPow2(33));
    try std.testing.expectError(error.Overflow, ceilPow2(std.math.maxInt(usize)));
    try std.testing.expectError(error.Overflow, computeTicketCapacity((std.math.maxInt(usize) / 4) + 1));
}

test "websocket accept matches the RFC example" {
    const accept = try websocketAccept("dGhlIHNhbXBsZSBub25jZQ==");
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &accept);
}

test "http parser recognizes websocket upgrade" {
    const request =
        "GET /chat HTTP/1.1\r\n" ++ "Host: example.com\r\n" ++ "Upgrade: websocket\r\n" ++ "Connection: Upgrade\r\n" ++ "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++ "Sec-WebSocket-Version: 13\r\n" ++ "\r\n";
    const parsed = try parseHttpRequest(request);
    try std.testing.expectEqualStrings("GET", fieldSlice(request, parsed.method));
    try std.testing.expectEqualStrings("/chat", fieldSlice(request, parsed.path));
    try std.testing.expectEqualStrings("HTTP/1.1", fieldSlice(request, parsed.version));
    try std.testing.expect(parsed.websocket_upgrade);
    try std.testing.expectEqual(@as(usize, 0), parsed.content_length);
    try std.testing.expectEqual(@as(usize, request.len), parsed.request_end);
    try std.testing.expect(parsed.websocket_key != null);
    try std.testing.expectEqualStrings("dGhlIHNhbXBsZSBub25jZQ==", fieldSlice(request, parsed.websocket_key.?));
}

test "maybeHttpPrefixVector recognizes request prefixes" {
    try std.testing.expect(maybeHttpPrefixVector("GET /"));
    try std.testing.expect(maybeHttpPrefixVector("POST /api"));
    try std.testing.expect(maybeHttpPrefixVector("PRI * HTTP/2.0"));
    try std.testing.expect(maybeHttpPrefixVector("PATCH /resource"));
    try std.testing.expect(!maybeHttpPrefixVector("HELLO"));
}

test "vector line scanners find crlf and header end" {
    const request =
        "GET /chat HTTP/1.1\r\n" ++ "Host: example.com\r\n" ++ "Upgrade: websocket\r\n" ++ "Connection: Upgrade\r\n" ++ "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++ "Sec-WebSocket-Version: 13\r\n" ++ "\r\n";
    const header_end = findHttpHeaderEndVector(request) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, request.len - 4), header_end);
    const request_line_end = findCrlfVector(request, 0) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 18), request_line_end);
    const host_line_start = request_line_end + 2;
    const host_line_end = findCrlfVector(request, host_line_start) orelse return error.TestUnexpectedResult;
    try std.testing.expect(host_line_end > host_line_start);
}

test "websocket upgrade and binary frame work end to end" {
    if (builtin.os.tag != .linux) return;

    const ws_init_rc = sa_netx_init(8, 1);
    if (ws_init_rc == SA_NETX_ERR_UNSUPPORTED) return; // io_uring unavailable in this environment
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), ws_init_rc);
    defer _ = sa_netx_shutdown();

    const listen_host = "127.0.0.1";
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_listen(listen_host.ptr, listen_host.len, 0));
    const listen_address = u03.runtime_state.listen_address orelse return error.TestUnexpectedResult;

    var collector_state = TicketCollector{
        .reactor_id = 0,
        .tickets = try std.testing.allocator.alloc(Ticket, 4),
    };
    defer std.testing.allocator.free(collector_state.tickets);

    var ws_client = WsLoopbackClient{
        .address = listen_address,
        .request = "GET /ws HTTP/1.1\r\n" ++ "Host: example.test\r\n" ++ "Upgrade: websocket\r\n" ++ "Connection: Upgrade\r\n" ++ "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++ "Sec-WebSocket-Version: 13\r\n" ++ "\r\n",
        .expected_payload = "WS_OK\n",
        .expected_frame_len = 2 + "WS_OK\n".len,
    };

    const collector_thread = try Thread.spawn(.{}, collectTicketsMain, .{&collector_state});
    const ws_thread = try Thread.spawn(.{}, wsLoopbackClientMain, .{&ws_client});

    collector_state.mutex.lockUncancelable(sio.io());
    const deadline = @as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds())) + 10 * std.time.ns_per_s;
    while (collector_state.count < 3 and collector_state.result == SA_NETX_OK) {
        const now = @as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds()));
        if (now >= deadline) break;
        const remaining = deadline - now;
        collector_state.cond.waitTimeout(sio.io(), &collector_state.mutex, .{ .duration = .{ .raw = .fromNanoseconds(@as(i96, @intCast(remaining))), .clock = .awake } }) catch |err| {
            // Test wait loops re-check the deadline/result predicates after spurious timeout errors.
            _ = @errorName(err);
        };
    }
    const collected = collector_state.count;
    const result = collector_state.result;
    collector_state.mutex.unlock(sio.io());
    if (collected != 3 or result != SA_NETX_OK) return error.TestUnexpectedResult;

    var ws_slot: u32 = 0;
    var saw_upgrade = false;
    var saw_send_done = false;
    for (collector_state.tickets[0..collected]) |ticket| {
        switch (ticket.op_code) {
            @intFromEnum(TicketOp.accept) => ws_slot = ticket.slot_id,
            @intFromEnum(TicketOp.websocket_upgrade) => {
                saw_upgrade = true;
                try std.testing.expectEqual(ws_slot, ticket.slot_id);
            },
            @intFromEnum(TicketOp.send_done) => saw_send_done = true,
            else => return error.TestUnexpectedResult,
        }
    }
    try std.testing.expect(ws_slot != 0);
    try std.testing.expect(saw_upgrade);
    try std.testing.expect(saw_send_done);

    const ws_payload = "WS_OK\n";
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_push_outbound(0, ws_slot, ws_payload.ptr, @as(u32, @intCast(ws_payload.len))));

    collector_state.mutex.lockUncancelable(sio.io());
    const send_deadline = @as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds())) + 10 * std.time.ns_per_s;
    while (collector_state.count < 4 and collector_state.result == SA_NETX_OK) {
        const now = @as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds()));
        if (now >= send_deadline) break;
        const remaining = send_deadline - now;
        collector_state.cond.waitTimeout(sio.io(), &collector_state.mutex, .{ .duration = .{ .raw = .fromNanoseconds(@as(i96, @intCast(remaining))), .clock = .awake } }) catch |err| {
            // Test wait loops re-check the deadline/result predicates after spurious timeout errors.
            _ = @errorName(err);
        };
    }
    const total_collected = collector_state.count;
    const total_result = collector_state.result;
    collector_state.mutex.unlock(sio.io());
    if (total_collected != 4 or total_result != SA_NETX_OK) return error.TestUnexpectedResult;

    _ = sa_netx_close_slot(ws_slot);
    collector_thread.join();
    ws_thread.join();
    _ = sa_netx_shutdown();

    try std.testing.expect(std.mem.indexOf(u8, ws_client.upgrade_response[0..ws_client.upgrade_len], "101 Switching Protocols") != null);
    try std.testing.expectEqual(ws_client.expected_frame_len, ws_client.frame_len);
    const frame = ws_client.received[0..ws_client.frame_len];
    try std.testing.expectEqual(@as(u8, 0x82), frame[0]);
    try std.testing.expectEqual(@as(u8, @intCast(ws_client.expected_payload.len)), frame[1]);
    try std.testing.expectEqualStrings(ws_client.expected_payload, frame[2 .. 2 + ws_client.expected_payload.len]);
}

test "websocket frame parser handles masked payloads" {
    var frame = [_]u8{
        0x81,
        0x85,
        0x37,
        0xfa,
        0x21,
        0x3d,
        'f' ^ 0x37,
        'o' ^ 0xfa,
        'o' ^ 0x21,
        '!' ^ 0x3d,
        '?' ^ 0x37,
    };
    const parsed = try parseWsFrame(frame[0..]);
    try std.testing.expectEqual(@as(u8, 1), parsed.opcode);
    try std.testing.expect(parsed.masked);
    unmaskFrame(frame[parsed.payload_start .. parsed.payload_start + parsed.payload_len], parsed.mask);
    try std.testing.expectEqualStrings("foo!?", frame[parsed.payload_start .. parsed.payload_start + parsed.payload_len]);
}

test "init and shutdown round-trip on linux" {
    if (builtin.os.tag != .linux) return;
    const rt_init_rc = sa_netx_init(8, 1);
    if (rt_init_rc == SA_NETX_ERR_UNSUPPORTED) return; // io_uring unavailable in this environment
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), rt_init_rc);
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_shutdown());
}
