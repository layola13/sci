const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const NetworkStatus = @import("v2_core.zig").NetworkStatus;
const PollEvent = @import("v2_core.zig").PollEvent;
const V2Error = @import("v2_core.zig").V2Error;
const WebSocketOpcodeV2 = @import("v2_websocket.zig").WebSocketOpcodeV2;
const WebSocketV2 = @import("v2_websocket.zig").WebSocketV2;
const buildWebSocketFrame = @import("core.zig").buildWebSocketFrame;
const max_v2_message_bytes = @import("v2_core.zig").max_v2_message_bytes;
const requiredSlice = @import("v2_core.zig").requiredSlice;
const statusCode = @import("v2_core.zig").statusCode;
const statusFromV2Error = @import("v2_core.zig").statusFromV2Error;
const websocketPoll = @import("v2_websocket.zig").websocketPoll;

const FrameMeta = struct {
    fin: bool,
    opcode: u8,
    payload_offset: usize,
    payload_len: usize,
    frame_len: usize,
};
const FrameParse = union(enum) {
    need_more,
    too_large,
    invalid,
    frame: FrameMeta,
};
fn parseServerFrame(bytes: []const u8, max_payload: u64) FrameParse {
    if (bytes.len < 2) return .need_more;
    const first = bytes[0];
    const second = bytes[1];
    if (first & 0x70 != 0) return .invalid;
    if (second & 0x80 != 0) return .invalid;

    var payload_len: u64 = second & 0x7f;
    var payload_offset: usize = 2;
    if (payload_len == 126) {
        if (bytes.len < 4) return .need_more;
        payload_len = std.mem.readInt(u16, bytes[2..4], .big);
        if (payload_len < 126) return .invalid;
        payload_offset = 4;
    } else if (payload_len == 127) {
        if (bytes.len < 10) return .need_more;
        payload_len = std.mem.readInt(u64, bytes[2..10], .big);
        if (payload_len < 65536 or payload_len & (@as(u64, 1) << 63) != 0) return .invalid;
        payload_offset = 10;
    }
    if (payload_len > max_payload or payload_len > std.math.maxInt(usize)) return .too_large;
    const payload_len_usize: usize = @intCast(payload_len);
    const frame_len = std.math.add(usize, payload_offset, payload_len_usize) catch return .too_large;
    if (bytes.len < frame_len) return .need_more;
    const opcode = first & 0x0f;
    const fin = first & 0x80 != 0;
    if (opcode >= 8 and (!fin or payload_len > 125)) return .invalid;
    return .{ .frame = .{
        .fin = fin,
        .opcode = opcode,
        .payload_offset = payload_offset,
        .payload_len = payload_len_usize,
        .frame_len = frame_len,
    } };
}
fn compactReceiveBuffer(handle: *WebSocketV2) void {
    if (handle.receive_start == 0) return;
    if (handle.receive_start == handle.receive_buffer.items.len) {
        handle.receive_buffer.clearRetainingCapacity();
        handle.receive_start = 0;
        return;
    }
    if (handle.receive_start < 4096 and handle.receive_start * 2 < handle.receive_buffer.items.len) return;
    const remaining = handle.receive_buffer.items.len - handle.receive_start;
    std.mem.copyForwards(u8, handle.receive_buffer.items[0..remaining], handle.receive_buffer.items[handle.receive_start..]);
    handle.receive_buffer.items.len = remaining;
    handle.receive_start = 0;
}
fn consumeFrame(handle: *WebSocketV2, frame_len: usize) void {
    handle.receive_start += frame_len;
    compactReceiveBuffer(handle);
}
fn errorFromNetworkStatus(status: NetworkStatus) V2Error {
    return switch (status) {
        .would_block => error.WouldBlock,
        .closed => error.Closed,
        .timeout => error.Timeout,
        .too_large => error.TooLarge,
        .invalid => error.Invalid,
        .io_error => error.Io,
        .ok => unreachable,
    };
}
fn fillWebSocketInput(handle: *WebSocketV2) V2Error!void {
    var events: u32 = 0;
    const poll_status = websocketPoll(handle, PollEvent.readable, 0, &events);
    if (poll_status != .ok) return errorFromNetworkStatus(poll_status);
    if (events & PollEvent.readable == 0) return if (events & PollEvent.closed != 0) error.Closed else error.WouldBlock;
    var buffer: [16 * 1024]u8 = undefined;
    const read_len = handle.rawRead(&buffer) catch |err| return err;
    if (read_len == 0) return error.Closed;
    handle.receive_buffer.appendSlice(buffer[0..read_len]) catch return error.Io;
}
fn websocketFrameBytes(handle: *WebSocketV2, opcode: u8, payload: []const u8) V2Error![]u8 {
    if (payload.len > max_v2_message_bytes) return error.TooLarge;
    const header_len: usize = if (payload.len < 126) 2 else if (payload.len <= std.math.maxInt(u16)) 4 else 10;
    const frame_capacity = std.math.add(usize, payload.len, header_len + 4) catch return error.TooLarge;
    const frame = handle.allocator.alloc(u8, frame_capacity) catch return error.Io;
    errdefer handle.allocator.free(frame);
    var mask_key: [4]u8 = undefined;
    sio.io().random(&mask_key);
    const frame_len = buildWebSocketFrame(frame, opcode, payload, &mask_key) catch return error.Invalid;
    std.debug.assert(frame_len == frame_capacity);
    return frame;
}
fn writeWebSocketFrame(handle: *WebSocketV2, opcode: u8, payload: []const u8) V2Error!void {
    if (handle.closed or handle.close_sent) return error.Closed;
    var events: u32 = 0;
    const poll_status = websocketPoll(handle, PollEvent.writable, 0, &events);
    if (poll_status != .ok) return errorFromNetworkStatus(poll_status);
    const frame = try websocketFrameBytes(handle, opcode, payload);
    defer handle.allocator.free(frame);
    handle.rawWrite(frame) catch |err| {
        handle.markClosed();
        return err;
    };
}
fn flushPendingPong(handle: *WebSocketV2) V2Error!void {
    const payload = handle.pending_pong orelse return;
    try writeWebSocketFrame(handle, @intFromEnum(WebSocketOpcodeV2.pong), payload);
    handle.allocator.free(payload);
    handle.pending_pong = null;
}
fn validCloseCode(code: u16) bool {
    if (code >= 3000 and code <= 4999) return true;
    return switch (code) {
        1000, 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014 => true,
        else => false,
    };
}
fn validateClosePayload(payload: []const u8) bool {
    if (payload.len == 0) return true;
    if (payload.len == 1) return false;
    const code = std.mem.readInt(u16, payload[0..2], .big);
    return validCloseCode(code) and std.unicode.utf8ValidateSlice(payload[2..]);
}
fn deliverMessage(handle: *WebSocketV2, opcode: u8, payload: []const u8, out_opcode: *u8, out_ptr: *?[*]const u8, out_len: *u64) V2Error!void {
    if (opcode == @intFromEnum(WebSocketOpcodeV2.text) and !std.unicode.utf8ValidateSlice(payload)) return error.Invalid;
    const copy = if (payload.len == 0) null else handle.allocator.dupe(u8, payload) catch return error.Io;
    handle.clearLastMessage();
    handle.last_message = copy;
    out_opcode.* = opcode;
    out_ptr.* = if (copy) |message| message.ptr else null;
    out_len.* = payload.len;
}
fn readWebSocketMessage(
    handle: *WebSocketV2,
    max_len: u64,
    out_opcode: *u8,
    out_ptr: *?[*]const u8,
    out_len: *u64,
) V2Error!void {
    const message_limit = if (max_len == 0) max_v2_message_bytes else @min(max_len, max_v2_message_bytes);
    try flushPendingPong(handle);
    while (true) {
        const available = handle.receive_buffer.items[handle.receive_start..];
        switch (parseServerFrame(available, message_limit)) {
            .need_more => {
                fillWebSocketInput(handle) catch |err| {
                    if (err == error.Closed) handle.markClosed();
                    return err;
                };
                continue;
            },
            .too_large => {
                handle.markClosed();
                return error.TooLarge;
            },
            .invalid => {
                handle.markClosed();
                return error.Invalid;
            },
            .frame => |frame| {
                const payload = available[frame.payload_offset .. frame.payload_offset + frame.payload_len];
                switch (frame.opcode) {
                    @intFromEnum(WebSocketOpcodeV2.ping) => {
                        if (handle.pending_pong) |old| handle.allocator.free(old);
                        handle.pending_pong = handle.allocator.dupe(u8, payload) catch return error.Io;
                        consumeFrame(handle, frame.frame_len);
                        try flushPendingPong(handle);
                    },
                    @intFromEnum(WebSocketOpcodeV2.pong) => consumeFrame(handle, frame.frame_len),
                    @intFromEnum(WebSocketOpcodeV2.close) => {
                        if (!validateClosePayload(payload)) {
                            handle.markClosed();
                            return error.Invalid;
                        }
                        if (!handle.close_sent) {
                            writeWebSocketFrame(handle, @intFromEnum(WebSocketOpcodeV2.close), payload) catch {};
                            handle.close_sent = true;
                        }
                        consumeFrame(handle, frame.frame_len);
                        handle.markClosed();
                        return error.Closed;
                    },
                    @intFromEnum(WebSocketOpcodeV2.text), @intFromEnum(WebSocketOpcodeV2.binary) => {
                        if (handle.fragment_opcode != null) {
                            handle.markClosed();
                            return error.Invalid;
                        }
                        if (frame.fin) {
                            try deliverMessage(handle, frame.opcode, payload, out_opcode, out_ptr, out_len);
                            consumeFrame(handle, frame.frame_len);
                            return;
                        }
                        handle.fragment_opcode = frame.opcode;
                        handle.fragment_buffer.clearRetainingCapacity();
                        handle.fragment_buffer.appendSlice(payload) catch return error.Io;
                        consumeFrame(handle, frame.frame_len);
                    },
                    @intFromEnum(WebSocketOpcodeV2.continuation) => {
                        const initial_opcode = handle.fragment_opcode orelse {
                            handle.markClosed();
                            return error.Invalid;
                        };
                        const next_len = std.math.add(usize, handle.fragment_buffer.items.len, payload.len) catch {
                            handle.markClosed();
                            return error.TooLarge;
                        };
                        if (next_len > message_limit) {
                            handle.markClosed();
                            return error.TooLarge;
                        }
                        handle.fragment_buffer.appendSlice(payload) catch return error.Io;
                        consumeFrame(handle, frame.frame_len);
                        if (frame.fin) {
                            try deliverMessage(handle, initial_opcode, handle.fragment_buffer.items, out_opcode, out_ptr, out_len);
                            handle.fragment_buffer.clearRetainingCapacity();
                            handle.fragment_opcode = null;
                            return;
                        }
                    },
                    else => {
                        handle.markClosed();
                        return error.Invalid;
                    },
                }
            },
        }
    }
}
pub export fn sa_http_websocket_poll_v2(ws: ?*anyopaque, interests: u32, timeout_ms: u32, out_events: ?*u32) u32 {
    const events = out_events orelse return statusCode(.invalid);
    events.* = 0;
    const ws_ptr = ws orelse return statusCode(.invalid);
    const handle: *WebSocketV2 = @ptrCast(@alignCast(ws_ptr));
    while (!handle.io_mutex.tryLock()) std.atomic.spinLoopHint();
    defer handle.io_mutex.unlock();
    return statusCode(websocketPoll(handle, interests, timeout_ms, events));
}
pub export fn sa_http_websocket_read_v2(
    ws: ?*anyopaque,
    max_len: u64,
    out_opcode: ?*u8,
    out_ptr: ?*?[*]const u8,
    out_len: ?*u64,
) u32 {
    const opcode_slot = out_opcode orelse return statusCode(.invalid);
    const ptr_slot = out_ptr orelse return statusCode(.invalid);
    const len_slot = out_len orelse return statusCode(.invalid);
    opcode_slot.* = 0;
    ptr_slot.* = null;
    len_slot.* = 0;
    const ws_ptr = ws orelse return statusCode(.invalid);
    const handle: *WebSocketV2 = @ptrCast(@alignCast(ws_ptr));
    while (!handle.io_mutex.tryLock()) std.atomic.spinLoopHint();
    defer handle.io_mutex.unlock();
    readWebSocketMessage(handle, max_len, opcode_slot, ptr_slot, len_slot) catch |err| return statusCode(statusFromV2Error(err));
    return statusCode(.ok);
}
pub export fn sa_http_websocket_write_v2(
    ws: ?*anyopaque,
    opcode: u8,
    data_ptr: ?[*]const u8,
    data_len: u64,
    out_written: ?*u64,
) u32 {
    const written = out_written orelse return statusCode(.invalid);
    written.* = 0;
    const ws_ptr = ws orelse return statusCode(.invalid);
    const payload = requiredSlice(data_ptr, data_len) catch return statusCode(.invalid);
    if (opcode != @intFromEnum(WebSocketOpcodeV2.text) and opcode != @intFromEnum(WebSocketOpcodeV2.binary) and
        opcode != @intFromEnum(WebSocketOpcodeV2.ping) and opcode != @intFromEnum(WebSocketOpcodeV2.pong))
    {
        return statusCode(.invalid);
    }
    if ((opcode == @intFromEnum(WebSocketOpcodeV2.ping) or opcode == @intFromEnum(WebSocketOpcodeV2.pong)) and payload.len > 125) return statusCode(.too_large);
    if (opcode == @intFromEnum(WebSocketOpcodeV2.text) and !std.unicode.utf8ValidateSlice(payload)) return statusCode(.invalid);
    const handle: *WebSocketV2 = @ptrCast(@alignCast(ws_ptr));
    while (!handle.io_mutex.tryLock()) std.atomic.spinLoopHint();
    defer handle.io_mutex.unlock();
    writeWebSocketFrame(handle, opcode, payload) catch |err| return statusCode(statusFromV2Error(err));
    written.* = payload.len;
    return statusCode(.ok);
}
pub export fn sa_http_websocket_close_v2(ws: ?*anyopaque, code: u16, reason_ptr: ?[*]const u8, reason_len: u64) u32 {
    const ws_ptr = ws orelse return statusCode(.invalid);
    const reason = requiredSlice(reason_ptr, reason_len) catch return statusCode(.invalid);
    if (!validCloseCode(code) or reason.len > 123) return statusCode(if (reason.len > 123) .too_large else .invalid);
    if (!std.unicode.utf8ValidateSlice(reason)) return statusCode(.invalid);
    const handle: *WebSocketV2 = @ptrCast(@alignCast(ws_ptr));
    while (!handle.io_mutex.tryLock()) std.atomic.spinLoopHint();
    defer handle.io_mutex.unlock();
    if (handle.closed or handle.close_sent) return statusCode(.closed);
    var payload: [125]u8 = undefined;
    std.mem.writeInt(u16, payload[0..2], code, .big);
    @memcpy(payload[2 .. 2 + reason.len], reason);
    writeWebSocketFrame(handle, @intFromEnum(WebSocketOpcodeV2.close), payload[0 .. 2 + reason.len]) catch |err| return statusCode(statusFromV2Error(err));
    handle.close_sent = true;
    return statusCode(.ok);
}
pub export fn sa_http_websocket_free_v2(ws: ?*anyopaque) u32 {
    const ws_ptr = ws orelse return statusCode(.invalid);
    const handle: *WebSocketV2 = @ptrCast(@alignCast(ws_ptr));
    handle.deinit();
    return statusCode(.ok);
}
