const std = @import("std");
const builtin = @import("builtin");
const sa_std = @import("../sa_std.zig");
const net_primitives = @import("sa_net_primitives");
const sio = @import("sio");
const Condition = @import("u01.zig").Condition;
const ConnectionSlot = @import("u01.zig").ConnectionSlot;
const IDLE_TIMEOUT_NS = @import("u01.zig").IDLE_TIMEOUT_NS;
const Mutex = @import("u01.zig").Mutex;
const NetxProto_HTTP = @import("u01.zig").NetxProto_HTTP;
const NetxProto_RAW = @import("u01.zig").NetxProto_RAW;
const NetxProto_WS = @import("u01.zig").NetxProto_WS;
const REACTOR_TIMEOUT_NS = @import("u01.zig").REACTOR_TIMEOUT_NS;
const ReactorCommand = @import("u01.zig").ReactorCommand;
const SA_NETX_ERR_INVALID_ARGUMENT = @import("u01.zig").SA_NETX_ERR_INVALID_ARGUMENT;
const SA_NETX_ERR_INVALID_HANDLE = @import("u01.zig").SA_NETX_ERR_INVALID_HANDLE;
const SA_NETX_ERR_IO = @import("u01.zig").SA_NETX_ERR_IO;
const SA_NETX_ERR_NET = @import("u01.zig").SA_NETX_ERR_NET;
const SA_NETX_ERR_NO_MEMORY = @import("u01.zig").SA_NETX_ERR_NO_MEMORY;
const SA_NETX_ERR_TRUNCATED = @import("u01.zig").SA_NETX_ERR_TRUNCATED;
const SA_NETX_OK = @import("u01.zig").SA_NETX_OK;
const Thread = @import("u01.zig").Thread;
const Ticket = @import("u01.zig").Ticket;
const TicketFlag = @import("u01.zig").TicketFlag;
const TicketQueue = @import("u01.zig").TicketQueue;
const decodeUserData = @import("u03.zig").decodeUserData;
const fieldSlice = @import("u03.zig").fieldSlice;
const frameFlags = @import("u03.zig").frameFlags;
const getState = @import("u03.zig").getState;
const linux = @import("u01.zig").linux;
const looksLikeHttpPrefix = @import("u03.zig").looksLikeHttpPrefix;
const makeTicket = @import("u03.zig").makeTicket;
const net = @import("u01.zig").net;
const packUserData = @import("u03.zig").packUserData;
const parseHttpRequest = @import("u03.zig").parseHttpRequest;
const parseWsFrame = @import("u03.zig").parseWsFrame;
const posix = @import("u01.zig").posix;
const reactorWorkerMain = @import("u03.zig").reactorWorkerMain;
const runtime_state = @import("u03.zig").runtime_state;
const setNonBlocking = @import("u03.zig").setNonBlocking;
const unmaskFrame = @import("u03.zig").unmaskFrame;
const websocketAccept = @import("u03.zig").websocketAccept;
const writeWebSocketFrame = @import("u03.zig").writeWebSocketFrame;
const ConnectionSlot = @import("u01.zig").ConnectionSlot;
const NetxProto_HTTP = @import("u01.zig").NetxProto_HTTP;
const NetxProto_RAW = @import("u01.zig").NetxProto_RAW;
const NetxProto_WS = @import("u01.zig").NetxProto_WS;
const Reactor = @import("u02.zig").Reactor;
const Ticket = @import("u01.zig").Ticket;
const TicketFlag = @import("u01.zig").TicketFlag;
const eof = @import("u01.zig").eof;
const fieldSlice = @import("u03.zig").fieldSlice;
const frameFlags = @import("u03.zig").frameFlags;
const looksLikeHttpPrefix = @import("u03.zig").looksLikeHttpPrefix;
const makeTicket = @import("u03.zig").makeTicket;
const masked = @import("u01.zig").masked;
const packUserData = @import("u03.zig").packUserData;
const parseHttpRequest = @import("u03.zig").parseHttpRequest;
const parseWsFrame = @import("u03.zig").parseWsFrame;
const unmaskFrame = @import("u03.zig").unmaskFrame;
const upgrade = @import("u01.zig").upgrade;
const websocketAccept = @import("u03.zig").websocketAccept;
const writeWebSocketFrame = @import("u03.zig").writeWebSocketFrame;

    pub fn queuePeerClose(self: *Reactor, slot: *ConnectionSlot, flags: u32) !void {
        const payload = slot.scratch[slot.message_start..slot.scratch_used];
        _ = payload;
        const ticket = makeTicket(slot, .peer_close, NetxProto_RAW, TicketFlag.eof, slot.scratch[slot.message_start..slot.message_start]);
        if (!self.queueTicket(ticket)) {
            slot.recv_paused = true;
        }
        _ = flags;
    }

    pub fn processSlotBytes(self: *Reactor, slot: *ConnectionSlot, start: usize, end: usize, cqe_flags: u32) !void {
        _ = cqe_flags;
        if (slot.state == .Closing or slot.state == .Free) return;
        if (start >= end) return;
        slot.markActive(@as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds())));

        while (slot.message_start < slot.scratch_used) {
            const pending = slot.scratch[slot.message_start..slot.scratch_used];
            switch (slot.state) {
                .Handshake, .Reading => {
                    if (parseHttpRequest(pending)) |req| {
                        if (slot.scratch_used < slot.message_start + req.request_end) break;
                        const req_slice = slot.scratch[slot.message_start .. slot.message_start + req.request_end];
                        const upgrade = req.websocket_upgrade and req.websocket_key != null;
                        if (upgrade) {
                            const accept_value = try websocketAccept(fieldSlice(req_slice, req.websocket_key.?));
                            try self.queueWebSocketUpgrade(slot, accept_value[0..]);
                            slot.state = .WebSocket;
                            const ticket = makeTicket(slot, .websocket_upgrade, NetxProto_HTTP, TicketFlag.upgrade, req_slice);
                            if (self.queueTicket(ticket)) {
                                slot.message_start += req.request_end;
                                continue;
                            } else {
                                slot.recv_paused = true;
                                break;
                            }
                        } else {
                            slot.state = .Http;
                            const ticket = makeTicket(slot, .http_request, NetxProto_HTTP, 0, req_slice);
                            if (self.queueTicket(ticket)) {
                                slot.message_start += req.request_end;
                                continue;
                            } else {
                                slot.recv_paused = true;
                                break;
                            }
                        }
                    } else |err| switch (err) {
                        error.Incomplete => {
                            if (looksLikeHttpPrefix(pending)) {
                                slot.state = .Reading;
                                break;
                            }
                            slot.state = .RawBinary;
                            continue;
                        },
                        error.Invalid => {
                            slot.state = .RawBinary;
                            continue;
                        },
                    }
                },
                .Http => {
                    if (parseHttpRequest(pending)) |req| {
                        if (slot.scratch_used < slot.message_start + req.request_end) break;
                        const req_slice = slot.scratch[slot.message_start .. slot.message_start + req.request_end];
                        if (req.websocket_upgrade and req.websocket_key != null) {
                            const accept_value = try websocketAccept(fieldSlice(req_slice, req.websocket_key.?));
                            try self.queueWebSocketUpgrade(slot, accept_value[0..]);
                            slot.state = .WebSocket;
                            const ticket = makeTicket(slot, .websocket_upgrade, NetxProto_HTTP, TicketFlag.upgrade, req_slice);
                            if (self.queueTicket(ticket)) {
                                slot.message_start += req.request_end;
                                continue;
                            }
                            slot.recv_paused = true;
                            break;
                        }
                        const ticket = makeTicket(slot, .http_request, NetxProto_HTTP, 0, req_slice);
                        if (self.queueTicket(ticket)) {
                            slot.message_start += req.request_end;
                            continue;
                        }
                        slot.recv_paused = true;
                        break;
                    } else |err| switch (err) {
                        error.Incomplete => break,
                        error.Invalid => {
                            slot.state = .RawBinary;
                            continue;
                        },
                    }
                },
                .RawBinary => {
                    const raw = pending;
                    const ticket = makeTicket(slot, .raw_bytes, NetxProto_RAW, 0, raw);
                    if (self.queueTicket(ticket)) {
                        slot.message_start = slot.scratch_used;
                    } else {
                        slot.recv_paused = true;
                    }
                    break;
                },
                .WebSocket => {
                    if (parseWsFrame(pending)) |frame| {
                        if (pending.len < frame.frame_len) break;
                        const payload_start = slot.message_start + frame.payload_start;
                        const payload_end = payload_start + frame.payload_len;
                        const payload = slot.scratch[payload_start..payload_end];
                        if (frame.masked) {
                            unmaskFrame(slot.scratch[payload_start..payload_end], frame.mask);
                        }
                        const ticket = makeTicket(slot, .ws_frame, NetxProto_WS, frameFlags(frame), payload);
                        if (self.queueTicket(ticket)) {
                            slot.message_start += frame.frame_len;
                            if (frame.opcode == 0x8) {
                                slot.state = .HalfClosed;
                                slot.clear();
                                return;
                            }
                            continue;
                        }
                        slot.recv_paused = true;
                        break;
                    } else |err| switch (err) {
                        error.Incomplete => break,
                        error.Invalid => {
                            slot.state = .Closing;
                            slot.clear();
                            return;
                        },
                    }
                },
                .HalfClosed, .Closing, .Free => break,
                .Accepting => {
                    slot.state = .Handshake;
                },
            }
        }
    }

    pub fn queueTicket(self: *Reactor, ticket: Ticket) bool {
        self.ticket_mutex.lockUncancelable(sio.io());
        defer self.ticket_mutex.unlock(sio.io());
        const pushed = self.tickets.push(ticket);
        if (pushed) {
            self.ticket_cond.broadcast(sio.io());
        }
        return pushed;
    }

    pub fn ticketPop(self: *Reactor) ?Ticket {
        self.ticket_mutex.lockUncancelable(sio.io());
        defer self.ticket_mutex.unlock(sio.io());
        return self.ticketPopLocked();
    }

    pub fn ticketPopLocked(self: *Reactor) ?Ticket {
        return self.tickets.pop();
    }

    pub fn ticketIsFull(self: *Reactor) bool {
        self.ticket_mutex.lockUncancelable(sio.io());
        defer self.ticket_mutex.unlock(sio.io());
        return self.tickets.isFull();
    }

    pub fn queueWebSocketUpgrade(self: *Reactor, slot: *ConnectionSlot, accept_value: []const u8) !void {
        var response_buf: [256]u8 = undefined;
        const response = try std.fmt.bufPrint(response_buf[0..], "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept_value});
        try self.sendBytes(slot, response, false, false);
    }

    pub fn sendBytes(self: *Reactor, slot: *ConnectionSlot, bytes: []const u8, use_zc: bool, websocket_frame: bool) !void {
        if (slot.outbound_inflight) return error.WouldBlock;
        const payload = if (websocket_frame and slot.state == .WebSocket) blk: {
            break :blk try writeWebSocketFrame(slot, bytes);
        } else blk: {
            if (bytes.len > slot.outbound_scratch.len) return error.NoSpaceLeft;
            @memcpy(slot.outbound_scratch[0..bytes.len], bytes);
            break :blk slot.outbound_scratch[0..bytes.len];
        };
        slot.outbound_len = payload.len;
        slot.outbound_inflight = true;
        slot.outbound_mode_zc = use_zc and self.send_zc_supported;

        const ud = packUserData(.send, self.id, slot.slot_id);
        if (slot.outbound_mode_zc) {
            _ = self.ring.send_zc(ud, slot.fd, payload, 0, 0) catch {
                self.send_zc_supported = false;
                slot.outbound_mode_zc = false;
                _ = try self.ring.send(ud, slot.fd, payload, 0);
            };
        } else {
            _ = try self.ring.send(ud, slot.fd, payload, 0);
        }
    }

    pub fn pump(self: *Reactor, wait_one: bool) !void {
        try self.armTimeout();
        try self.armWakeup();
        _ = try self.ring.submit();
        if (wait_one) {
            try self.drain(true);
        } else {
            try self.drain(false);
        }
    }

    pub fn serviceDeferredWork(self: *Reactor) void {
        self.command_mutex.lockUncancelable(sio.io());
        const should_resume = self.resume_requested;
        self.resume_requested = false;
        const has_command = self.command_pending;
        self.command_mutex.unlock(sio.io());
        if (has_command) self.processPendingCommand();
        if (should_resume) self.resumePausedSlots();
    }
