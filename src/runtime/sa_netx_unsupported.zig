const std = @import("std");

const net_primitives = @import("sa_net_primitives.zig");

const SA_NETX_OK: i32 = 0;
const SA_NETX_ERR_INVALID_ARGUMENT: i32 = 1;
const SA_NETX_ERR_UNSUPPORTED: i32 = 8;
const SA_NETX_ERR_TRUNCATED: i32 = 9;

pub const Ticket = extern struct {
    slot_id: u32,
    op_code: u16,
    proto: u8,
    flags: u8,
    payload: ?*u8,
    payload_len: u32,
    pad: u32,
};

comptime {
    std.debug.assert(@sizeOf(Ticket) == 24);
    std.debug.assert(@alignOf(Ticket) == 8);
    std.debug.assert(@offsetOf(Ticket, "slot_id") == 0);
    std.debug.assert(@offsetOf(Ticket, "op_code") == 4);
    std.debug.assert(@offsetOf(Ticket, "proto") == 6);
    std.debug.assert(@offsetOf(Ticket, "flags") == 7);
    std.debug.assert(@offsetOf(Ticket, "payload") == 8);
    std.debug.assert(@offsetOf(Ticket, "payload_len") == 16);
    std.debug.assert(@offsetOf(Ticket, "pad") == 20);
}

fn validateCopyOut(src: []const u8, out: ?[*]u8, cap: u64) i32 {
    if (out != null) {
        const capacity = std.math.cast(usize, cap) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        if (src.len > capacity) return SA_NETX_ERR_TRUNCATED;
    }
    return SA_NETX_OK;
}

fn commitCopyOut(src: []const u8, out: ?[*]u8, out_len: ?*u64) void {
    if (out) |dst| @memcpy(dst[0..src.len], src);
    if (out_len) |len| len.* = @intCast(src.len);
}

fn zeroWsFrameOutputs(
    out_fin: ?*u8,
    out_opcode: ?*u8,
    out_masked: ?*u8,
    out_payload_offset: ?*u64,
    out_payload_len: ?*u64,
    out_frame_len: ?*u64,
    out_mask: ?[*]u8,
) void {
    if (out_fin) |value| value.* = 0;
    if (out_opcode) |value| value.* = 0;
    if (out_masked) |value| value.* = 0;
    if (out_payload_offset) |value| value.* = 0;
    if (out_payload_len) |value| value.* = 0;
    if (out_frame_len) |value| value.* = 0;
    if (out_mask) |value| @memset(value[0..4], 0);
}

fn zeroTicket(out_ticket: ?*Ticket) void {
    if (out_ticket) |ticket| {
        ticket.* = .{
            .slot_id = 0,
            .op_code = 0,
            .proto = 0,
            .flags = 0,
            .payload = null,
            .payload_len = 0,
            .pad = 0,
        };
    }
}

pub export fn sa_std_ws_accept_key(key_ptr: ?[*]const u8, key_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_out = out_len orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    len_out.* = 0;
    const key_size = std.math.cast(usize, key_len) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const key = if (key_size == 0) &[_]u8{} else (key_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT)[0..key_size];
    const out = out_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    if (out_cap < 28) return SA_NETX_ERR_TRUNCATED;
    const accept = net_primitives.websocketAccept(key) catch return SA_NETX_ERR_INVALID_ARGUMENT;
    @memcpy(out[0..accept.len], &accept);
    len_out.* = accept.len;
    return SA_NETX_OK;
}

pub export fn sa_std_ws_frame_parse(
    data_ptr: ?[*]const u8,
    data_len: u64,
    out_fin: ?*u8,
    out_opcode: ?*u8,
    out_masked: ?*u8,
    out_payload_offset: ?*u64,
    out_payload_len: ?*u64,
    out_frame_len: ?*u64,
    out_mask: ?[*]u8,
) i32 {
    zeroWsFrameOutputs(out_fin, out_opcode, out_masked, out_payload_offset, out_payload_len, out_frame_len, out_mask);
    const len = std.math.cast(usize, data_len) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const data = if (len == 0) &[_]u8{} else (data_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT)[0..len];
    const frame = net_primitives.parseWsFrame(data) catch |err| switch (err) {
        error.Incomplete => return SA_NETX_ERR_TRUNCATED,
        error.Invalid => return SA_NETX_ERR_INVALID_ARGUMENT,
    };
    if (out_fin) |value| value.* = @intFromBool(frame.fin);
    if (out_opcode) |value| value.* = frame.opcode;
    if (out_masked) |value| value.* = @intFromBool(frame.masked);
    if (out_payload_offset) |value| value.* = @intCast(frame.payload_start);
    if (out_payload_len) |value| value.* = @intCast(frame.payload_len);
    if (out_frame_len) |value| value.* = @intCast(frame.frame_len);
    if (out_mask) |value| @memcpy(value[0..4], &frame.mask);
    return SA_NETX_OK;
}

pub export fn sa_std_ws_unmask(payload_ptr: ?[*]u8, payload_len: u64, mask_ptr: ?[*]const u8) i32 {
    const len = std.math.cast(usize, payload_len) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    if (len == 0) return SA_NETX_OK;
    const payload = (payload_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT)[0..len];
    const mask_source = mask_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    var mask: [4]u8 = undefined;
    @memcpy(&mask, mask_source[0..4]);
    net_primitives.unmaskFrame(payload, mask);
    return SA_NETX_OK;
}

pub export fn sa_std_ws_frame_build(
    opcode: u32,
    fin: u32,
    payload_ptr: ?[*]const u8,
    payload_len: u64,
    mask_ptr: ?[*]const u8,
    out_ptr: ?[*]u8,
    out_cap: u64,
    out_len: ?*u64,
) i32 {
    const len_out = out_len orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    len_out.* = 0;
    const payload_size = std.math.cast(usize, payload_len) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const payload = if (payload_size == 0) &[_]u8{} else (payload_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT)[0..payload_size];
    const capacity = std.math.cast(usize, out_cap) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const out = (out_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT)[0..capacity];

    var mask: [4]u8 = undefined;
    const optional_mask: ?*const [4]u8 = if (mask_ptr) |source| blk: {
        @memcpy(&mask, source[0..4]);
        break :blk &mask;
    } else null;
    const written = net_primitives.buildWsFrame(@intCast(opcode & 0x0f), fin != 0, payload, optional_mask, out) catch |err| switch (err) {
        error.NoSpaceLeft => return SA_NETX_ERR_TRUNCATED,
        else => return SA_NETX_ERR_INVALID_ARGUMENT,
    };
    len_out.* = @intCast(written);
    return SA_NETX_OK;
}

pub export fn sa_std_ws_frame_build_unmasked(
    opcode: u32,
    fin: u32,
    payload_ptr: ?[*]const u8,
    payload_len: u64,
    out_ptr: ?[*]u8,
    out_cap: u64,
    out_len: ?*u64,
) i32 {
    return sa_std_ws_frame_build(opcode, fin, payload_ptr, payload_len, null, out_ptr, out_cap, out_len);
}

pub export fn sa_std_url_parse(
    url_ptr: ?[*]const u8,
    url_len: u64,
    scheme_out: ?[*]u8,
    scheme_cap: u64,
    scheme_len: ?*u64,
    host_out: ?[*]u8,
    host_cap: u64,
    host_len: ?*u64,
    path_out: ?[*]u8,
    path_cap: u64,
    path_len: ?*u64,
    out_port: ?*u32,
) i32 {
    if (scheme_len) |value| value.* = 0;
    if (host_len) |value| value.* = 0;
    if (path_len) |value| value.* = 0;
    if (out_port) |value| value.* = 0;

    const len = std.math.cast(usize, url_len) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const url = if (len == 0) &[_]u8{} else (url_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT)[0..len];
    const parts = net_primitives.parseUrlParts(url) catch return SA_NETX_ERR_INVALID_ARGUMENT;

    const scheme_status = validateCopyOut(parts.scheme, scheme_out, scheme_cap);
    if (scheme_status != SA_NETX_OK) return scheme_status;
    const host_status = validateCopyOut(parts.host, host_out, host_cap);
    if (host_status != SA_NETX_OK) return host_status;
    const path_status = validateCopyOut(parts.path, path_out, path_cap);
    if (path_status != SA_NETX_OK) return path_status;

    commitCopyOut(parts.scheme, scheme_out, scheme_len);
    commitCopyOut(parts.host, host_out, host_len);
    commitCopyOut(parts.path, path_out, path_len);
    if (out_port) |port| port.* = parts.port;
    return SA_NETX_OK;
}

pub export fn sa_netx_init(slot_capacity: u64, reactor_count: u32) i32 {
    _ = slot_capacity;
    _ = reactor_count;
    return SA_NETX_ERR_UNSUPPORTED;
}

pub export fn sa_netx_listen(host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    _ = host_ptr;
    _ = host_len;
    _ = port;
    return SA_NETX_ERR_UNSUPPORTED;
}

pub export fn sa_netx_recv_ticket(reactor_id: u32, out_ticket: ?*Ticket) i32 {
    _ = reactor_id;
    zeroTicket(out_ticket);
    return SA_NETX_ERR_UNSUPPORTED;
}

pub export fn sa_netx_push_outbound(reactor_id: u32, slot_id: u32, msg_ptr: ?[*]const u8, len: u32) i32 {
    _ = reactor_id;
    _ = slot_id;
    _ = msg_ptr;
    _ = len;
    return SA_NETX_ERR_UNSUPPORTED;
}

pub export fn sa_netx_broadcast(reactor_id: u32, slot_ids_ptr: ?[*]const u32, n: u32, msg_ptr: ?[*]const u8, len: u32) i32 {
    _ = reactor_id;
    _ = slot_ids_ptr;
    _ = n;
    _ = msg_ptr;
    _ = len;
    return SA_NETX_ERR_UNSUPPORTED;
}

pub export fn sa_netx_close_slot(slot_id: u32) i32 {
    _ = slot_id;
    return SA_NETX_ERR_UNSUPPORTED;
}

pub export fn sa_netx_shutdown() i32 {
    return SA_NETX_ERR_UNSUPPORTED;
}

test "unsupported netx ABI matches the Linux ticket layout" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(Ticket));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Ticket));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Ticket, "payload"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Ticket, "payload_len"));
}

test "unsupported netx operations consistently return unsupported" {
    var payload_byte: u8 = 1;
    var ticket = Ticket{
        .slot_id = 1,
        .op_code = 2,
        .proto = 3,
        .flags = 4,
        .payload = &payload_byte,
        .payload_len = 5,
        .pad = 6,
    };

    try std.testing.expectEqual(SA_NETX_ERR_UNSUPPORTED, sa_netx_init(0, 0));
    try std.testing.expectEqual(SA_NETX_ERR_UNSUPPORTED, sa_netx_listen(null, std.math.maxInt(u64), 0));
    try std.testing.expectEqual(SA_NETX_ERR_UNSUPPORTED, sa_netx_recv_ticket(0, &ticket));
    try std.testing.expectEqual(@as(u32, 0), ticket.slot_id);
    try std.testing.expectEqual(@as(u16, 0), ticket.op_code);
    try std.testing.expectEqual(@as(u8, 0), ticket.proto);
    try std.testing.expectEqual(@as(u8, 0), ticket.flags);
    try std.testing.expectEqual(@as(?*u8, null), ticket.payload);
    try std.testing.expectEqual(@as(u32, 0), ticket.payload_len);
    try std.testing.expectEqual(@as(u32, 0), ticket.pad);
    try std.testing.expectEqual(SA_NETX_ERR_UNSUPPORTED, sa_netx_recv_ticket(0, null));
    try std.testing.expectEqual(SA_NETX_ERR_UNSUPPORTED, sa_netx_push_outbound(0, 0, null, std.math.maxInt(u32)));
    try std.testing.expectEqual(SA_NETX_ERR_UNSUPPORTED, sa_netx_broadcast(0, null, std.math.maxInt(u32), null, std.math.maxInt(u32)));
    try std.testing.expectEqual(SA_NETX_ERR_UNSUPPORTED, sa_netx_close_slot(0));
    try std.testing.expectEqual(SA_NETX_ERR_UNSUPPORTED, sa_netx_shutdown());
}

test "websocket parse failures clear every output" {
    var fin: u8 = 1;
    var opcode: u8 = 2;
    var masked: u8 = 3;
    var payload_offset: u64 = 4;
    var payload_len: u64 = 5;
    var frame_len: u64 = 6;
    var mask = [_]u8{ 7, 8, 9, 10 };

    try std.testing.expectEqual(
        SA_NETX_ERR_TRUNCATED,
        sa_std_ws_frame_parse(null, 0, &fin, &opcode, &masked, &payload_offset, &payload_len, &frame_len, &mask),
    );
    try std.testing.expectEqual(@as(u8, 0), fin);
    try std.testing.expectEqual(@as(u8, 0), opcode);
    try std.testing.expectEqual(@as(u8, 0), masked);
    try std.testing.expectEqual(@as(u64, 0), payload_offset);
    try std.testing.expectEqual(@as(u64, 0), payload_len);
    try std.testing.expectEqual(@as(u64, 0), frame_len);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0 }, &mask);
}

test "URL parse failures leave scalar outputs at safe zero values" {
    const url = "https://example.test/path";
    var scheme: [8]u8 = undefined;
    var host: [4]u8 = undefined;
    var path: [16]u8 = undefined;
    var scheme_len: u64 = 1;
    var host_len: u64 = 2;
    var path_len: u64 = 3;
    var port: u32 = 4;

    try std.testing.expectEqual(
        SA_NETX_ERR_TRUNCATED,
        sa_std_url_parse(
            url.ptr,
            url.len,
            &scheme,
            scheme.len,
            &scheme_len,
            &host,
            host.len,
            &host_len,
            &path,
            path.len,
            &path_len,
            &port,
        ),
    );
    try std.testing.expectEqual(@as(u64, 0), scheme_len);
    try std.testing.expectEqual(@as(u64, 0), host_len);
    try std.testing.expectEqual(@as(u64, 0), path_len);
    try std.testing.expectEqual(@as(u32, 0), port);
}

test "buffer writers clear their output length before validation" {
    var output: [32]u8 = undefined;
    var output_len: u64 = 99;

    try std.testing.expectEqual(
        SA_NETX_ERR_INVALID_ARGUMENT,
        sa_std_ws_accept_key(null, 1, &output, output.len, &output_len),
    );
    try std.testing.expectEqual(@as(u64, 0), output_len);

    output_len = 99;
    try std.testing.expectEqual(
        SA_NETX_ERR_INVALID_ARGUMENT,
        sa_std_ws_frame_build(1, 1, null, 1, null, &output, output.len, &output_len),
    );
    try std.testing.expectEqual(@as(u64, 0), output_len);
}
