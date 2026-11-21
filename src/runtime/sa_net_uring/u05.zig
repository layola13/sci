const std = @import("std");
const builtin = @import("builtin");
const sa_std = @import("../sa_std.zig");
const net_primitives = @import("sa_net_primitives");
const sio = @import("sio");
const LoopbackClient = @import("u04.zig").LoopbackClient;
const SA_NETX_ERR_UNSUPPORTED = @import("u01.zig").SA_NETX_ERR_UNSUPPORTED;
const SA_NETX_OK = @import("u01.zig").SA_NETX_OK;
const Thread = @import("u01.zig").Thread;
const Ticket = @import("u01.zig").Ticket;
const TicketCollector = @import("u04.zig").TicketCollector;
const TicketOp = @import("u01.zig").TicketOp;
const collectTicketsMain = @import("u04.zig").collectTicketsMain;
const linux = @import("u01.zig").linux;
const loopbackClientMain = @import("u04.zig").loopbackClientMain;
const runtime_state = @import("u03.zig").runtime_state;
const sa_netx_broadcast = @import("u04.zig").sa_netx_broadcast;
const sa_netx_close_slot = @import("u04.zig").sa_netx_close_slot;
const sa_netx_init = @import("u04.zig").sa_netx_init;
const sa_netx_listen = @import("u04.zig").sa_netx_listen;
const sa_netx_push_outbound = @import("u04.zig").sa_netx_push_outbound;
const sa_netx_shutdown = @import("u04.zig").sa_netx_shutdown;
const ticketPayload = @import("u04.zig").ticketPayload;

test "listen accept recv_ticket and outbound commands work end to end" {
    if (builtin.os.tag != .linux) return;

    const la_init_rc = sa_netx_init(16, 1);
    if (la_init_rc == SA_NETX_ERR_UNSUPPORTED) return; // io_uring unavailable in this environment
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), la_init_rc);
    defer _ = sa_netx_shutdown();

    const listen_host = "127.0.0.1";
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_listen(listen_host.ptr, listen_host.len, 0));
    const listen_address = runtime_state.listen_address orelse return error.TestUnexpectedResult;

    var collector_state = TicketCollector{
        .reactor_id = 0,
        .tickets = try std.testing.allocator.alloc(Ticket, 7),
    };
    defer std.testing.allocator.free(collector_state.tickets);

    var client1 = LoopbackClient{
        .address = listen_address,
        .request = "GET /one HTTP/1.1\r\n" ++ "Host: example.test\r\n" ++ "Connection: keep-alive\r\n" ++ "\r\n",
    };
    var client2 = LoopbackClient{
        .address = listen_address,
        .request = "GET /two HTTP/1.1\r\n" ++ "Host: example.test\r\n" ++ "Connection: keep-alive\r\n" ++ "\r\n",
    };

    const collector_thread = try Thread.spawn(.{}, collectTicketsMain, .{&collector_state});
    const client1_thread = try Thread.spawn(.{}, loopbackClientMain, .{&client1});
    const client2_thread = try Thread.spawn(.{}, loopbackClientMain, .{&client2});

    collector_state.mutex.lockUncancelable(sio.io());
    const first_deadline = @as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds())) + 10 * std.time.ns_per_s;
    while (collector_state.count < 4 and collector_state.result == SA_NETX_OK) {
        const now = @as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds()));
        if (now >= first_deadline) break;
        const remaining = first_deadline - now;
        collector_state.cond.waitTimeout(sio.io(), &collector_state.mutex, .{ .duration = .{ .raw = .fromNanoseconds(@as(i96, @intCast(remaining))), .clock = .awake } }) catch |err| {
            // Test wait loops re-check the deadline/result predicates after spurious timeout errors.
            _ = @errorName(err);
        };
    }
    const first_collected = collector_state.count;
    const collection_result = collector_state.result;
    collector_state.mutex.unlock(sio.io());

    if (first_collected != 4 or collection_result != SA_NETX_OK) {
        return error.TestUnexpectedResult;
    }

    var accept_slots = [_]u32{ 0, 0 };
    var http_requests: usize = 0;
    var saw_client1 = false;
    var saw_client2 = false;
    var request_slots = [_]u32{ 0, 0 };
    for (collector_state.tickets[0..first_collected]) |ticket| {
        switch (ticket.op_code) {
            @intFromEnum(TicketOp.accept) => {
                if (accept_slots[0] == 0) {
                    accept_slots[0] = ticket.slot_id;
                } else if (accept_slots[1] == 0 and ticket.slot_id != accept_slots[0]) {
                    accept_slots[1] = ticket.slot_id;
                }
            },
            @intFromEnum(TicketOp.http_request) => {
                const payload = ticketPayload(ticket);
                if (std.mem.eql(u8, payload, client1.request)) {
                    saw_client1 = true;
                    request_slots[0] = ticket.slot_id;
                } else if (std.mem.eql(u8, payload, client2.request)) {
                    saw_client2 = true;
                    request_slots[1] = ticket.slot_id;
                } else {
                    return error.TestUnexpectedResult;
                }
                http_requests += 1;
            },
            @intFromEnum(TicketOp.send_done) => {},
            else => return error.TestUnexpectedResult,
        }
    }

    try std.testing.expectEqual(@as(usize, 2), http_requests);
    try std.testing.expect(saw_client1);
    try std.testing.expect(saw_client2);
    try std.testing.expect(accept_slots[0] != 0);
    try std.testing.expect(accept_slots[1] != 0);

    const push_msg = "ONE\n";
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_push_outbound(0, accept_slots[0], push_msg.ptr, @as(u32, @intCast(push_msg.len))));

    const broadcast_slots = [_]u32{ accept_slots[0], accept_slots[1] };
    const broadcast_msg = "BROAD\n";
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_broadcast(0, broadcast_slots[0..].ptr, @as(u32, @intCast(broadcast_slots.len)), broadcast_msg.ptr, @as(u32, @intCast(broadcast_msg.len))));

    collector_state.mutex.lockUncancelable(sio.io());
    const second_deadline = @as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds())) + 10 * std.time.ns_per_s;
    while (collector_state.count < 7 and collector_state.result == SA_NETX_OK) {
        const now = @as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds()));
        if (now >= second_deadline) break;
        const remaining = second_deadline - now;
        collector_state.cond.waitTimeout(sio.io(), &collector_state.mutex, .{ .duration = .{ .raw = .fromNanoseconds(@as(i96, @intCast(remaining))), .clock = .awake } }) catch |err| {
            // Test wait loops re-check the deadline/result predicates after spurious timeout errors.
            _ = @errorName(err);
        };
    }
    const total_collected = collector_state.count;
    const total_result = collector_state.result;
    collector_state.mutex.unlock(sio.io());

    if (total_collected != 7 or total_result != SA_NETX_OK) {
        return error.TestUnexpectedResult;
    }

    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_close_slot(accept_slots[0]));
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_close_slot(accept_slots[1]));

    _ = sa_netx_shutdown();
    collector_thread.join();
    client1_thread.join();
    client2_thread.join();

    const client1_received = client1.received[0..client1.received_len];
    const client2_received = client2.received[0..client2.received_len];
    if (request_slots[0] == accept_slots[0]) {
        try std.testing.expect(std.mem.indexOf(u8, client1_received, push_msg) != null);
        try std.testing.expect(std.mem.indexOf(u8, client2_received, push_msg) == null);
    } else if (request_slots[1] == accept_slots[0]) {
        try std.testing.expect(std.mem.indexOf(u8, client2_received, push_msg) != null);
        try std.testing.expect(std.mem.indexOf(u8, client1_received, push_msg) == null);
    } else {
        return error.TestUnexpectedResult;
    }
    try std.testing.expect(std.mem.indexOf(u8, client1_received, broadcast_msg) != null);
    try std.testing.expect(std.mem.indexOf(u8, client2_received, broadcast_msg) != null);

    var send_done_count: usize = 0;
    for (collector_state.tickets[0..total_collected]) |ticket| {
        if (ticket.op_code == @intFromEnum(TicketOp.send_done)) send_done_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), send_done_count);
}
