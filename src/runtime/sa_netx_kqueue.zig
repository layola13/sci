const std = @import("std");
const builtin = @import("builtin");
const sa_std = @import("sa_std.zig");
const net_primitives = @import("sa_net_primitives.zig");

const net = std.net;
const posix = std.posix;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;

pub const SA_NETX_ABI_VERSION: u32 = 1;
pub const backend_name = "kqueue";
pub const platform_reactor = "kqueue";
pub const supports_native_reactor = true;

pub const SA_NETX_OK: i32 = sa_std.SA_STD_OK;
pub const SA_NETX_ERR_INVALID_ARGUMENT: i32 = sa_std.SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_NETX_ERR_INVALID_HANDLE: i32 = sa_std.SA_STD_ERR_INVALID_HANDLE;
pub const SA_NETX_ERR_NOT_FOUND: i32 = sa_std.SA_STD_ERR_NOT_FOUND;
pub const SA_NETX_ERR_NO_MEMORY: i32 = sa_std.SA_STD_ERR_NO_MEMORY;
pub const SA_NETX_ERR_IO: i32 = sa_std.SA_STD_ERR_IO;
pub const SA_NETX_ERR_NET: i32 = sa_std.SA_STD_ERR_NET;
pub const SA_NETX_ERR_TRUNCATED: i32 = sa_std.SA_STD_ERR_TRUNCATED;
pub const SA_NETX_ERR_UNSUPPORTED: i32 = sa_std.SA_STD_ERR_UNSUPPORTED;

pub const NetxProto_HTTP: u8 = 1;
pub const NetxProto_WS: u8 = 2;
pub const NetxProto_RAW: u8 = 3;

const TicketOp = enum(u16) {
    accept = 1,
    http_request = 2,
    websocket_upgrade = 3,
    ws_frame = 4,
    raw_bytes = 5,
    peer_close = 6,
    send_done = 7,
    err = 8,
};

const TicketFlag = struct {
    pub const truncated: u8 = 1 << 0;
    pub const upgrade: u8 = 1 << 1;
    pub const eof: u8 = 1 << 2;
    pub const masked: u8 = 1 << 3;
};

const SlotState = enum(u8) {
    free,
    handshake,
    http,
    websocket,
    raw,
    closing,
};

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

const ticket_payload_capacity: usize = 4096;
const wake_ident: usize = 1;

const ReactorEvent = enum(u8) {
    none = 0,
    accept = 1,
    read = 2,
    write = 3,
    wake = 4,
};

const CommandKind = enum(u8) {
    listen,
    send,
    broadcast,
    close,
    stop,
};

const ReactorCommand = struct {
    kind: CommandKind,
    address: ?net.Address = null,
    slot_id: u32 = 0,
    msg_ptr: ?[*]const u8 = null,
    msg_len: usize = 0,
    slot_ids_ptr: ?[*]const u32 = null,
    slot_ids_len: usize = 0,
};

const TicketQueue = struct {
    storage: []Ticket,
    payload_storage: []u8,
    head: usize = 0,
    tail: usize = 0,
    count: usize = 0,

    fn init(allocator: std.mem.Allocator, requested_capacity: usize) !TicketQueue {
        const cap = @max(requested_capacity, 64);
        const payload_bytes = std.math.mul(usize, cap, ticket_payload_capacity) catch return error.OutOfMemory;
        const storage = try allocator.alloc(Ticket, cap);
        errdefer allocator.free(storage);
        const payload_storage = try allocator.alloc(u8, payload_bytes);
        @memset(payload_storage, 0);
        return .{
            .storage = storage,
            .payload_storage = payload_storage,
        };
    }

    fn deinit(self: *TicketQueue, allocator: std.mem.Allocator) void {
        if (self.storage.len != 0) allocator.free(self.storage);
        if (self.payload_storage.len != 0) allocator.free(self.payload_storage);
        self.* = undefined;
    }

    fn isEmpty(self: *const TicketQueue) bool {
        return self.count == 0;
    }

    fn isFull(self: *const TicketQueue) bool {
        return self.count == self.storage.len;
    }

    fn push(self: *TicketQueue, ticket: Ticket) bool {
        if (self.isFull()) return false;
        const payload_len = @as(usize, @intCast(ticket.payload_len));
        if (payload_len > ticket_payload_capacity) return false;
        const slot_start = self.tail * ticket_payload_capacity;
        const payload_dst = self.payload_storage[slot_start .. slot_start + ticket_payload_capacity];
        if (payload_len != 0) {
            const payload_ptr = ticket.payload orelse return false;
            const payload_src = @as([*]const u8, @ptrCast(payload_ptr))[0..payload_len];
            @memcpy(payload_dst[0..payload_len], payload_src);
        }
        var queued = ticket;
        queued.payload = if (payload_len == 0) null else &payload_dst[0];
        self.storage[self.tail] = queued;
        self.tail = (self.tail + 1) % self.storage.len;
        self.count += 1;
        return true;
    }

    fn pop(self: *TicketQueue) ?Ticket {
        if (self.isEmpty()) return null;
        const ticket = self.storage[self.head];
        self.head = (self.head + 1) % self.storage.len;
        self.count -= 1;
        return ticket;
    }
};

const ConnectionSlot = struct {
    id: u32 = 0,
    reactor_id: u32 = 0,
    fd: posix.fd_t = -1,
    state: SlotState = .free,
    proto: u8 = NetxProto_HTTP,
    recv_paused: bool = false,
    write_registered: bool = false,
    outbound_len: usize = 0,
    outbound_sent: usize = 0,
    scratch: [4096]u8 = undefined,
    scratch_used: usize = 0,
    outbound: [4096]u8 = undefined,

    fn reset(self: *ConnectionSlot, id: u32) void {
        self.id = id;
        self.reactor_id = 0;
        self.fd = -1;
        self.state = .free;
        self.proto = NetxProto_HTTP;
        self.recv_paused = false;
        self.write_registered = false;
        self.outbound_len = 0;
        self.outbound_sent = 0;
        self.scratch_used = 0;
        @memset(self.scratch[0..], 0);
        @memset(self.outbound[0..], 0);
    }

    fn initAccepted(self: *ConnectionSlot, id: u32, reactor_id: u32, fd: posix.fd_t) void {
        self.reset(id);
        self.reactor_id = reactor_id;
        self.fd = fd;
        self.state = .handshake;
        self.proto = NetxProto_HTTP;
    }

    fn active(self: *const ConnectionSlot) bool {
        return self.state != .free and self.state != .closing and self.fd >= 0;
    }
};

const Reactor = struct {
    id: u32,
    kq_fd: posix.fd_t,
    tickets: TicketQueue,
    ticket_mutex: Mutex = .{},
    ticket_cond: Condition = .{},
    command_mutex: Mutex = .{},
    command_cond: Condition = .{},
    command_pending: bool = false,
    command_result: i32 = SA_NETX_OK,
    command: ReactorCommand = .{ .kind = .stop },
    worker_started: bool = false,
    worker: ?Thread = null,
    stop: bool = false,
    server: ?net.Server = null,

    fn init(allocator: std.mem.Allocator, id: u32, ticket_capacity: usize) !Reactor {
        const kq_fd = try posix.kqueue();
        errdefer posix.close(kq_fd);
        const tickets = try TicketQueue.init(allocator, ticket_capacity);
        errdefer {
            var owned = tickets;
            owned.deinit(allocator);
        }
        var reactor = Reactor{
            .id = id,
            .kq_fd = kq_fd,
            .tickets = tickets,
        };
        try reactor.registerWake();
        return reactor;
    }

    fn deinit(self: *Reactor, allocator: std.mem.Allocator) void {
        self.stopWorker();
        if (self.server) |*server| {
            server.deinit();
            self.server = null;
        }
        self.tickets.deinit(allocator);
        if (self.kq_fd >= 0) {
            posix.close(self.kq_fd);
            self.kq_fd = -1;
        }
        self.* = undefined;
    }

    fn startWorker(self: *Reactor) !void {
        if (self.worker_started) return;
        self.stop = false;
        const thread = try Thread.spawn(.{}, reactorWorkerMain, .{self});
        self.worker = thread;
        self.worker_started = true;
    }

    fn stopWorker(self: *Reactor) void {
        if (!self.worker_started) return;
        _ = self.beginCommand(.{ .kind = .stop });
        self.signalWake();
        if (self.worker) |thread| {
            thread.join();
            self.worker = null;
        }
        self.worker_started = false;
    }

    fn registerWake(self: *Reactor) !void {
        const event = posix.Kevent{
            .ident = wake_ident,
            .filter = std.c.EVFILT.USER,
            .flags = std.c.EV.ADD | std.c.EV.CLEAR,
            .fflags = 0,
            .data = 0,
            .udata = packUserData(.wake, 0),
        };
        _ = try posix.kevent(self.kq_fd, &.{event}, &.{}, null);
    }

    fn signalWake(self: *Reactor) void {
        const event = posix.Kevent{
            .ident = wake_ident,
            .filter = std.c.EVFILT.USER,
            .flags = 0,
            .fflags = std.c.NOTE.TRIGGER,
            .data = 0,
            .udata = packUserData(.wake, 0),
        };
        _ = posix.kevent(self.kq_fd, &.{event}, &.{}, null) catch {};
    }

    fn registerAccept(self: *Reactor) !void {
        const server = &(self.server orelse return);
        const event = posix.Kevent{
            .ident = @intCast(server.stream.handle),
            .filter = std.c.EVFILT.READ,
            .flags = std.c.EV.ADD | std.c.EV.CLEAR,
            .fflags = 0,
            .data = 0,
            .udata = packUserData(.accept, 0),
        };
        _ = try posix.kevent(self.kq_fd, &.{event}, &.{}, null);
    }

    fn registerRead(self: *Reactor, slot: *ConnectionSlot) !void {
        if (!slot.active()) return;
        const event = posix.Kevent{
            .ident = @intCast(slot.fd),
            .filter = std.c.EVFILT.READ,
            .flags = std.c.EV.ADD | std.c.EV.CLEAR,
            .fflags = 0,
            .data = 0,
            .udata = packUserData(.read, slot.id),
        };
        _ = try posix.kevent(self.kq_fd, &.{event}, &.{}, null);
        slot.recv_paused = false;
    }

    fn unregisterRead(self: *Reactor, slot: *ConnectionSlot) void {
        if (slot.fd < 0) return;
        const event = posix.Kevent{
            .ident = @intCast(slot.fd),
            .filter = std.c.EVFILT.READ,
            .flags = std.c.EV.DELETE,
            .fflags = 0,
            .data = 0,
            .udata = packUserData(.read, slot.id),
        };
        _ = posix.kevent(self.kq_fd, &.{event}, &.{}, null) catch {};
    }

    fn registerWrite(self: *Reactor, slot: *ConnectionSlot) !void {
        if (!slot.active()) return;
        const event = posix.Kevent{
            .ident = @intCast(slot.fd),
            .filter = std.c.EVFILT.WRITE,
            .flags = std.c.EV.ADD | std.c.EV.CLEAR,
            .fflags = 0,
            .data = 0,
            .udata = packUserData(.write, slot.id),
        };
        _ = try posix.kevent(self.kq_fd, &.{event}, &.{}, null);
        slot.write_registered = true;
    }

    fn unregisterWrite(self: *Reactor, slot: *ConnectionSlot) void {
        if (slot.fd < 0 or !slot.write_registered) return;
        const event = posix.Kevent{
            .ident = @intCast(slot.fd),
            .filter = std.c.EVFILT.WRITE,
            .flags = std.c.EV.DELETE,
            .fflags = 0,
            .data = 0,
            .udata = packUserData(.write, slot.id),
        };
        _ = posix.kevent(self.kq_fd, &.{event}, &.{}, null) catch {};
        slot.write_registered = false;
    }

    fn beginCommand(self: *Reactor, command: ReactorCommand) i32 {
        if (!self.worker_started and command.kind != .stop) return SA_NETX_ERR_INVALID_HANDLE;
        self.command_mutex.lock();
        while (self.command_pending) {
            self.command_cond.wait(&self.command_mutex);
        }
        self.command = command;
        self.command_result = SA_NETX_OK;
        self.command_pending = true;
        self.command_mutex.unlock();

        self.signalWake();

        self.command_mutex.lock();
        while (self.command_pending) {
            self.command_cond.wait(&self.command_mutex);
        }
        const result = self.command_result;
        self.command_mutex.unlock();
        return result;
    }

    fn finishCommand(self: *Reactor, result: i32) void {
        self.command_mutex.lock();
        self.command_result = result;
        self.command_pending = false;
        self.command_cond.broadcast();
        self.command_mutex.unlock();
    }

    fn processCommand(self: *Reactor) void {
        self.command_mutex.lock();
        if (!self.command_pending) {
            self.command_mutex.unlock();
            return;
        }
        const command = self.command;
        self.command_mutex.unlock();

        var result: i32 = SA_NETX_OK;
        switch (command.kind) {
            .listen => {
                if (command.address) |address| {
                    if (self.server) |*server| server.deinit();
                    self.server = address.listen(.{
                        .kernel_backlog = 256,
                        .reuse_address = true,
                        .reuse_port = true,
                        .force_nonblocking = true,
                    }) catch {
                        self.server = null;
                        self.finishCommand(SA_NETX_ERR_NET);
                        return;
                    };
                    self.registerAccept() catch {
                        if (self.server) |*server| server.deinit();
                        self.server = null;
                        result = SA_NETX_ERR_IO;
                    };
                } else if (self.server) |*server| {
                    server.deinit();
                    self.server = null;
                }
            },
            .send => result = self.commandSend(command),
            .broadcast => result = self.commandBroadcast(command),
            .close => result = self.commandClose(command.slot_id),
            .stop => {
                self.stop = true;
                result = SA_NETX_OK;
            },
        }
        self.finishCommand(result);
    }

    fn commandSend(self: *Reactor, command: ReactorCommand) i32 {
        const slot = slotFromId(command.slot_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
        if (slot.reactor_id != self.id or !slot.active()) return SA_NETX_ERR_INVALID_HANDLE;
        const msg = if (command.msg_len == 0) &[_]u8{} else blk: {
            const ptr = command.msg_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
            break :blk ptr[0..command.msg_len];
        };
        self.prepareOutbound(slot, msg, slot.proto == NetxProto_WS) catch |err| switch (err) {
            error.NoSpaceLeft => return SA_NETX_ERR_TRUNCATED,
            error.WouldBlock => return SA_NETX_ERR_IO,
            else => return SA_NETX_ERR_IO,
        };
        self.flushWrite(slot) catch |err| switch (err) {
            error.WouldBlock => return SA_NETX_OK,
            else => return SA_NETX_ERR_IO,
        };
        return SA_NETX_OK;
    }

    fn commandBroadcast(self: *Reactor, command: ReactorCommand) i32 {
        const slots = if (command.slot_ids_len == 0) &[_]u32{} else blk: {
            const ptr = command.slot_ids_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
            break :blk ptr[0..command.slot_ids_len];
        };
        const msg = if (command.msg_len == 0) &[_]u8{} else blk: {
            const ptr = command.msg_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
            break :blk ptr[0..command.msg_len];
        };
        for (slots) |slot_id| {
            const slot = slotFromId(slot_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
            if (slot.reactor_id != self.id or !slot.active()) return SA_NETX_ERR_INVALID_HANDLE;
            self.prepareOutbound(slot, msg, slot.proto == NetxProto_WS) catch |err| switch (err) {
                error.NoSpaceLeft => return SA_NETX_ERR_TRUNCATED,
                error.WouldBlock => return SA_NETX_ERR_IO,
                else => return SA_NETX_ERR_IO,
            };
            self.flushWrite(slot) catch |err| switch (err) {
                error.WouldBlock => {},
                else => return SA_NETX_ERR_IO,
            };
        }
        return SA_NETX_OK;
    }

    fn commandClose(self: *Reactor, slot_id: u32) i32 {
        const slot = slotFromId(slot_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
        if (slot.reactor_id != self.id or !slot.active()) return SA_NETX_ERR_INVALID_HANDLE;
        self.closeSlot(slot, false);
        return SA_NETX_OK;
    }

    fn prepareOutbound(self: *Reactor, slot: *ConnectionSlot, bytes: []const u8, websocket_frame: bool) !void {
        if (slot.outbound_len != slot.outbound_sent) return error.WouldBlock;
        self.unregisterWrite(slot);
        const payload = if (websocket_frame) blk: {
            const written = net_primitives.buildWsFrame(0x2, true, bytes, null, slot.outbound[0..]) catch |err| switch (err) {
                error.NoSpaceLeft => return error.NoSpaceLeft,
                else => return error.Invalid,
            };
            break :blk slot.outbound[0..written];
        } else blk: {
            if (bytes.len > slot.outbound.len) return error.NoSpaceLeft;
            if (bytes.len != 0) @memcpy(slot.outbound[0..bytes.len], bytes);
            break :blk slot.outbound[0..bytes.len];
        };
        slot.outbound_len = payload.len;
        slot.outbound_sent = 0;
    }

    fn flushWrite(self: *Reactor, slot: *ConnectionSlot) !void {
        while (slot.outbound_sent < slot.outbound_len) {
            const pending = slot.outbound[slot.outbound_sent..slot.outbound_len];
            const written = posix.send(slot.fd, pending, 0) catch |err| switch (err) {
                error.WouldBlock => {
                    try self.registerWrite(slot);
                    return error.WouldBlock;
                },
                else => return err,
            };
            if (written == 0) {
                try self.registerWrite(slot);
                return error.WouldBlock;
            }
            slot.outbound_sent += written;
        }
        if (slot.outbound_len != 0) {
            slot.outbound_len = 0;
            slot.outbound_sent = 0;
            self.unregisterWrite(slot);
            _ = self.queueTicket(makeTicket(slot, .send_done, slot.proto, 0, &.{}));
        }
    }

    fn handleAccept(self: *Reactor) void {
        const server = &(self.server orelse return);
        while (true) {
            var addr: posix.sockaddr = undefined;
            var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
            const fd = posix.accept(server.stream.handle, &addr, &addr_len, posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC) catch |err| switch (err) {
                error.WouldBlock => return,
                else => return,
            };
            const slot = allocSlot(self.id, fd) orelse {
                posix.close(fd);
                continue;
            };
            if (!self.queueTicket(makeTicket(slot, .accept, slot.proto, 0, &.{}))) {
                slot.recv_paused = true;
                self.unregisterRead(slot);
                continue;
            }
            self.registerRead(slot) catch {
                self.closeSlot(slot, true);
            };
        }
    }

    fn handleRead(self: *Reactor, slot_id: u32) void {
        const slot = slotFromId(slot_id) orelse return;
        if (slot.reactor_id != self.id or !slot.active()) return;
        while (slot.active()) {
            if (slot.scratch_used >= slot.scratch.len) {
                slot.recv_paused = true;
                self.unregisterRead(slot);
                return;
            }
            var buffer: [1024]u8 = undefined;
            const read_len = posix.recv(slot.fd, buffer[0..], 0) catch |err| switch (err) {
                error.WouldBlock => return,
                else => {
                    self.closeSlot(slot, true);
                    return;
                },
            };
            if (read_len == 0) {
                self.closeSlot(slot, true);
                return;
            }
            appendAndProcess(self, slot, buffer[0..read_len]);
            if (slot.recv_paused) {
                self.unregisterRead(slot);
                return;
            }
        }
    }

    fn handleWrite(self: *Reactor, slot_id: u32) void {
        const slot = slotFromId(slot_id) orelse return;
        if (slot.reactor_id != self.id or !slot.active()) return;
        self.flushWrite(slot) catch |err| switch (err) {
            error.WouldBlock => {},
            else => self.closeSlot(slot, true),
        };
    }

    fn closeSlot(self: *Reactor, slot: *ConnectionSlot, queue_close: bool) void {
        if (slot.fd >= 0) {
            self.unregisterWrite(slot);
            self.unregisterRead(slot);
            posix.close(slot.fd);
        }
        if (queue_close) _ = self.queueTicket(makeTicket(slot, .peer_close, NetxProto_RAW, TicketFlag.eof, &.{}));
        slot.reset(slot.id);
    }

    fn resumePaused(self: *Reactor) void {
        for (runtime_state.slots) |*slot| {
            if (slot.reactor_id != self.id or !slot.recv_paused or !slot.active()) continue;
            if (self.ticketIsFull()) return;
            self.registerRead(slot) catch return;
        }
    }

    fn queueTicket(self: *Reactor, ticket: Ticket) bool {
        self.ticket_mutex.lock();
        defer self.ticket_mutex.unlock();
        const pushed = self.tickets.push(ticket);
        if (pushed) self.ticket_cond.broadcast();
        return pushed;
    }

    fn ticketIsFull(self: *Reactor) bool {
        self.ticket_mutex.lock();
        defer self.ticket_mutex.unlock();
        return self.tickets.isFull();
    }
};

const RuntimeState = struct {
    mutex: Mutex = .{},
    initialized: bool = false,
    listened: bool = false,
    listen_address: ?net.Address = null,
    reactors: []Reactor = &.{},
    slots: []ConnectionSlot = &.{},
    next_slot: usize = 0,
};

var runtime_state: RuntimeState = .{};

fn packUserData(tag: ReactorEvent, slot_id: u32) usize {
    return (@as(usize, @intFromEnum(tag)) << 32) | @as(usize, slot_id);
}

fn decodeUserData(value: usize) struct { tag: ReactorEvent, slot_id: u32 } {
    const tag_raw: u8 = @intCast((value >> 32) & 0xff);
    return .{
        .tag = std.meta.intToEnum(ReactorEvent, tag_raw) catch .none,
        .slot_id = @as(u32, @intCast(value & 0xffff_ffff)),
    };
}

fn computeTicketCapacity(slot_capacity: usize) !usize {
    return std.math.mul(usize, @max(slot_capacity, 1), 4) catch error.Overflow;
}

fn makeTicket(slot: *ConnectionSlot, op: TicketOp, proto: u8, flags: u8, payload: []const u8) Ticket {
    return .{
        .slot_id = slot.id,
        .op_code = @intFromEnum(op),
        .proto = proto,
        .flags = flags,
        .payload = if (payload.len == 0) null else @as(*u8, @ptrCast(@constCast(payload.ptr))),
        .payload_len = @as(u32, @intCast(payload.len)),
        .pad = 0,
    };
}

fn allocSlot(reactor_id: u32, fd: posix.fd_t) ?*ConnectionSlot {
    runtime_state.mutex.lock();
    defer runtime_state.mutex.unlock();
    var scanned: usize = 0;
    while (scanned < runtime_state.slots.len) : (scanned += 1) {
        const idx = (runtime_state.next_slot + scanned) % runtime_state.slots.len;
        const slot = &runtime_state.slots[idx];
        if (slot.state == .free) {
            runtime_state.next_slot = (idx + 1) % runtime_state.slots.len;
            slot.initAccepted(@as(u32, @intCast(idx + 1)), reactor_id, fd);
            return slot;
        }
    }
    return null;
}

fn slotFromId(slot_id: u32) ?*ConnectionSlot {
    if (slot_id == 0) return null;
    const idx = @as(usize, @intCast(slot_id - 1));
    if (idx >= runtime_state.slots.len) return null;
    const slot = &runtime_state.slots[idx];
    if (slot.state == .free) return null;
    return slot;
}

fn reactorWorkerMain(reactor: *Reactor) void {
    var events: [64]posix.Kevent = undefined;
    while (!reactor.stop) {
        reactor.processCommand();
        reactor.resumePaused();
        const ready = posix.kevent(reactor.kq_fd, &.{}, events[0..], null) catch continue;
        var idx: usize = 0;
        while (idx < ready) : (idx += 1) {
            const decoded = decodeUserData(events[idx].udata);
            switch (decoded.tag) {
                .accept => reactor.handleAccept(),
                .read => reactor.handleRead(decoded.slot_id),
                .write => reactor.handleWrite(decoded.slot_id),
                .wake => reactor.processCommand(),
                .none => {},
            }
        }
    }
    reactor.processCommand();
}

fn appendAndProcess(reactor: *Reactor, slot: *ConnectionSlot, bytes: []const u8) void {
    const copy_len = @min(slot.scratch.len - slot.scratch_used, bytes.len);
    if (copy_len != 0) {
        @memcpy(slot.scratch[slot.scratch_used .. slot.scratch_used + copy_len], bytes[0..copy_len]);
        slot.scratch_used += copy_len;
    }
    var flags: u8 = 0;
    if (copy_len < bytes.len) flags |= TicketFlag.truncated;

    while (slot.scratch_used != 0 and slot.active()) {
        const pending = slot.scratch[0..slot.scratch_used];
        switch (slot.proto) {
            NetxProto_HTTP => {
                if (findHttpRequestEnd(pending)) |request_end| {
                    const request = pending[0..request_end];
                    if (isWebSocketUpgrade(request)) |key| {
                        if (queueWebSocketUpgrade(reactor, slot, key) == SA_NETX_OK) {
                            slot.proto = NetxProto_WS;
                            slot.state = .websocket;
                            if (!reactor.queueTicket(makeTicket(slot, .websocket_upgrade, NetxProto_HTTP, flags | TicketFlag.upgrade, request))) {
                                slot.recv_paused = true;
                                return;
                            }
                        }
                    } else {
                        slot.state = .http;
                        if (!reactor.queueTicket(makeTicket(slot, .http_request, NetxProto_HTTP, flags, request))) {
                            slot.recv_paused = true;
                            return;
                        }
                    }
                    consumeScratch(slot, request_end);
                    continue;
                }
                if (!looksLikeHttpPrefix(pending)) {
                    slot.proto = NetxProto_RAW;
                    slot.state = .raw;
                    if (!reactor.queueTicket(makeTicket(slot, .raw_bytes, NetxProto_RAW, flags, pending))) {
                        slot.recv_paused = true;
                        return;
                    }
                    slot.scratch_used = 0;
                }
                return;
            },
            NetxProto_WS => {
                const frame = net_primitives.parseWsFrame(pending) catch |err| switch (err) {
                    error.Incomplete => return,
                    error.Invalid => {
                        reactor.closeSlot(slot, true);
                        return;
                    },
                };
                const payload_start = frame.payload_start;
                const payload_end = payload_start + frame.payload_len;
                if (frame.masked) {
                    net_primitives.unmaskFrame(slot.scratch[payload_start..payload_end], frame.mask);
                }
                var frame_flags = flags;
                if (frame.masked) frame_flags |= TicketFlag.masked;
                const payload = slot.scratch[payload_start..payload_end];
                if (!reactor.queueTicket(makeTicket(slot, .ws_frame, NetxProto_WS, frame_flags, payload))) {
                    slot.recv_paused = true;
                    return;
                }
                consumeScratch(slot, frame.frame_len);
                if (frame.opcode == 0x8) {
                    reactor.closeSlot(slot, true);
                    return;
                }
                continue;
            },
            else => {
                if (!reactor.queueTicket(makeTicket(slot, .raw_bytes, NetxProto_RAW, flags, pending))) {
                    slot.recv_paused = true;
                    return;
                }
                slot.scratch_used = 0;
                return;
            },
        }
    }
}

fn consumeScratch(slot: *ConnectionSlot, amount: usize) void {
    if (amount >= slot.scratch_used) {
        slot.scratch_used = 0;
        return;
    }
    const remaining = slot.scratch_used - amount;
    std.mem.copyForwards(u8, slot.scratch[0..remaining], slot.scratch[amount..slot.scratch_used]);
    slot.scratch_used = remaining;
}

fn findHttpRequestEnd(bytes: []const u8) ?usize {
    const header_end = std.mem.indexOf(u8, bytes, "\r\n\r\n") orelse return null;
    return header_end + 4;
}

fn looksLikeHttpPrefix(bytes: []const u8) bool {
    if (bytes.len < 3) return true;
    const methods = [_][]const u8{ "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "CONNECT", "TRACE" };
    for (methods) |method| {
        if (bytes.len <= method.len) {
            if (std.mem.eql(u8, bytes, method[0..bytes.len])) return true;
        } else if (std.mem.startsWith(u8, bytes, method) and bytes[method.len] == ' ') return true;
    }
    return false;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ac, bc| {
        if (std.ascii.toLower(ac) != std.ascii.toLower(bc)) return false;
    }
    return true;
}

fn trimAscii(bytes: []const u8) []const u8 {
    return std.mem.trim(u8, bytes, " \t");
}

fn containsTokenIgnoreCase(value: []const u8, needle: []const u8) bool {
    var it = std.mem.splitScalar(u8, value, ',');
    while (it.next()) |token| {
        if (eqlIgnoreCase(trimAscii(token), needle)) return true;
    }
    return false;
}

fn isWebSocketUpgrade(request: []const u8) ?[]const u8 {
    var saw_upgrade = false;
    var key: ?[]const u8 = null;
    var lines = std.mem.splitSequence(u8, request, "\r\n");
    _ = lines.next();
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = trimAscii(line[0..colon]);
        const value = trimAscii(line[colon + 1 ..]);
        if (eqlIgnoreCase(name, "Connection") and containsTokenIgnoreCase(value, "Upgrade")) saw_upgrade = true;
        if (eqlIgnoreCase(name, "Upgrade") and eqlIgnoreCase(value, "websocket")) saw_upgrade = true;
        if (eqlIgnoreCase(name, "Sec-WebSocket-Key")) key = value;
    }
    return if (saw_upgrade) key else null;
}

fn queueWebSocketUpgrade(reactor: *Reactor, slot: *ConnectionSlot, key: []const u8) i32 {
    const accept = net_primitives.websocketAccept(key) catch return SA_NETX_ERR_INVALID_ARGUMENT;
    var response_buf: [256]u8 = undefined;
    const response = std.fmt.bufPrint(
        response_buf[0..],
        "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: {s}\r\n\r\n",
        .{accept},
    ) catch return SA_NETX_ERR_IO;
    reactor.prepareOutbound(slot, response, false) catch return SA_NETX_ERR_IO;
    reactor.flushWrite(slot) catch |err| switch (err) {
        error.WouldBlock => return SA_NETX_OK,
        else => return SA_NETX_ERR_IO,
    };
    return SA_NETX_OK;
}

pub export fn sa_netx_init(slot_capacity: u64, reactor_count: u32) i32 {
    if (!builtin.target.os.tag.isDarwin()) return SA_NETX_ERR_UNSUPPORTED;
    if (slot_capacity == 0 or reactor_count == 0) return SA_NETX_ERR_INVALID_ARGUMENT;
    runtime_state.mutex.lock();
    defer runtime_state.mutex.unlock();
    if (runtime_state.initialized) return SA_NETX_ERR_INVALID_ARGUMENT;
    const slot_capacity_usize = std.math.cast(usize, slot_capacity) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    if (slot_capacity_usize > std.math.maxInt(u32)) return SA_NETX_ERR_INVALID_ARGUMENT;
    const reactor_count_usize = @as(usize, @intCast(reactor_count));
    const ticket_capacity = computeTicketCapacity(slot_capacity_usize) catch return SA_NETX_ERR_INVALID_ARGUMENT;

    const allocator = std.heap.page_allocator;
    const reactors = allocator.alloc(Reactor, reactor_count_usize) catch return SA_NETX_ERR_NO_MEMORY;
    errdefer allocator.free(reactors);
    var initialized_reactors: usize = 0;
    while (initialized_reactors < reactors.len) : (initialized_reactors += 1) {
        reactors[initialized_reactors] = Reactor.init(allocator, @as(u32, @intCast(initialized_reactors)), ticket_capacity) catch {
            var idx: usize = 0;
            while (idx < initialized_reactors) : (idx += 1) reactors[idx].deinit(allocator);
            return SA_NETX_ERR_IO;
        };
    }

    const slots = allocator.alloc(ConnectionSlot, slot_capacity_usize) catch {
        for (reactors) |*reactor| reactor.deinit(allocator);
        allocator.free(reactors);
        return SA_NETX_ERR_NO_MEMORY;
    };
    for (slots, 0..) |*slot, idx| slot.reset(@as(u32, @intCast(idx + 1)));

    var started: usize = 0;
    while (started < reactors.len) : (started += 1) {
        reactors[started].startWorker() catch {
            var idx: usize = 0;
            while (idx < started) : (idx += 1) reactors[idx].stopWorker();
            for (reactors) |*reactor| reactor.deinit(allocator);
            allocator.free(reactors);
            allocator.free(slots);
            return SA_NETX_ERR_NO_MEMORY;
        };
    }

    runtime_state.initialized = true;
    runtime_state.listened = false;
    runtime_state.listen_address = null;
    runtime_state.reactors = reactors;
    runtime_state.slots = slots;
    runtime_state.next_slot = 0;
    return SA_NETX_OK;
}

pub export fn sa_netx_listen(host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    runtime_state.mutex.lock();
    if (!runtime_state.initialized or runtime_state.reactors.len == 0) {
        runtime_state.mutex.unlock();
        return SA_NETX_ERR_INVALID_HANDLE;
    }
    if (runtime_state.listened) {
        runtime_state.mutex.unlock();
        return SA_NETX_ERR_INVALID_ARGUMENT;
    }
    runtime_state.mutex.unlock();

    const host = if (host_len == 0) "0.0.0.0" else blk: {
        const ptr = host_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        const len = std.math.cast(usize, host_len) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        const slice = ptr[0..len];
        if (std.mem.indexOfScalar(u8, slice, 0) != null) return SA_NETX_ERR_INVALID_ARGUMENT;
        break :blk slice;
    };
    const address = net.Address.resolveIp(host, port) catch return SA_NETX_ERR_NET;

    const result = runtime_state.reactors[0].beginCommand(.{ .kind = .listen, .address = address });
    if (result != SA_NETX_OK) return result;

    runtime_state.mutex.lock();
    runtime_state.listened = true;
    runtime_state.listen_address = runtime_state.reactors[0].server.?.listen_address;
    runtime_state.mutex.unlock();
    return SA_NETX_OK;
}

pub export fn sa_netx_recv_ticket(reactor_id: u32, out_ticket: ?*Ticket) i32 {
    const ticket_ptr = out_ticket orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const idx = @as(usize, @intCast(reactor_id));
    runtime_state.mutex.lock();
    if (!runtime_state.initialized or idx >= runtime_state.reactors.len) {
        runtime_state.mutex.unlock();
        return SA_NETX_ERR_INVALID_HANDLE;
    }
    const reactor = &runtime_state.reactors[idx];
    runtime_state.mutex.unlock();

    reactor.ticket_mutex.lock();
    defer reactor.ticket_mutex.unlock();
    while (reactor.tickets.isEmpty()) {
        runtime_state.mutex.lock();
        const initialized = runtime_state.initialized;
        runtime_state.mutex.unlock();
        if (!initialized) {
            ticket_ptr.* = .{ .slot_id = 0, .op_code = 0, .proto = 0, .flags = 0, .payload = null, .payload_len = 0, .pad = 0 };
            return SA_NETX_ERR_NOT_FOUND;
        }
        reactor.ticket_cond.wait(&reactor.ticket_mutex);
    }
    ticket_ptr.* = reactor.tickets.pop().?;
    reactor.signalWake();
    return SA_NETX_OK;
}

pub export fn sa_netx_push_outbound(reactor_id: u32, slot_id: u32, msg_ptr: ?[*]const u8, len: u32) i32 {
    _ = reactor_id;
    const slot = slotFromId(slot_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    const reactor_idx = @as(usize, @intCast(slot.reactor_id));
    if (reactor_idx >= runtime_state.reactors.len) return SA_NETX_ERR_INVALID_HANDLE;
    const msg = if (len == 0) null else msg_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    return runtime_state.reactors[reactor_idx].beginCommand(.{
        .kind = .send,
        .slot_id = slot_id,
        .msg_ptr = msg,
        .msg_len = @as(usize, @intCast(len)),
    });
}

pub export fn sa_netx_broadcast(reactor_id: u32, slot_ids_ptr: ?[*]const u32, n: u32, msg_ptr: ?[*]const u8, len: u32) i32 {
    const idx = @as(usize, @intCast(reactor_id));
    if (idx >= runtime_state.reactors.len) return SA_NETX_ERR_INVALID_HANDLE;
    const slots = if (n == 0) null else slot_ids_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const msg = if (len == 0) null else msg_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    return runtime_state.reactors[idx].beginCommand(.{
        .kind = .broadcast,
        .slot_ids_ptr = slots,
        .slot_ids_len = @as(usize, @intCast(n)),
        .msg_ptr = msg,
        .msg_len = @as(usize, @intCast(len)),
    });
}

pub export fn sa_netx_close_slot(slot_id: u32) i32 {
    const slot = slotFromId(slot_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    const reactor_idx = @as(usize, @intCast(slot.reactor_id));
    if (reactor_idx >= runtime_state.reactors.len) return SA_NETX_ERR_INVALID_HANDLE;
    return runtime_state.reactors[reactor_idx].beginCommand(.{ .kind = .close, .slot_id = slot_id });
}

pub export fn sa_netx_shutdown() i32 {
    runtime_state.mutex.lock();
    if (!runtime_state.initialized) {
        runtime_state.mutex.unlock();
        return SA_NETX_OK;
    }
    const reactors = runtime_state.reactors;
    const slots = runtime_state.slots;
    runtime_state.initialized = false;
    runtime_state.listened = false;
    runtime_state.listen_address = null;
    runtime_state.reactors = &.{};
    runtime_state.slots = &.{};
    runtime_state.next_slot = 0;
    runtime_state.mutex.unlock();

    const allocator = std.heap.page_allocator;
    for (reactors) |*reactor| {
        reactor.ticket_mutex.lock();
        reactor.ticket_cond.broadcast();
        reactor.ticket_mutex.unlock();
        reactor.deinit(allocator);
    }
    for (slots) |*slot| {
        if (slot.fd >= 0) {
            posix.close(slot.fd);
            slot.fd = -1;
        }
    }
    if (reactors.len != 0) allocator.free(reactors);
    if (slots.len != 0) allocator.free(slots);
    return SA_NETX_OK;
}

pub usingnamespace WsAndUrlAbi;

const WsAndUrlAbi = struct {
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
        if (out_fin) |value| value.* = 0;
        if (out_opcode) |value| value.* = 0;
        if (out_masked) |value| value.* = 0;
        if (out_payload_offset) |value| value.* = 0;
        if (out_payload_len) |value| value.* = 0;
        if (out_frame_len) |value| value.* = 0;
        if (out_mask) |value| @memset(value[0..4], 0);
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
        if (copyOut(parts.scheme, scheme_out, scheme_cap, scheme_len) != SA_NETX_OK) return SA_NETX_ERR_TRUNCATED;
        if (copyOut(parts.host, host_out, host_cap, host_len) != SA_NETX_OK) return SA_NETX_ERR_TRUNCATED;
        if (copyOut(parts.path, path_out, path_cap, path_len) != SA_NETX_OK) return SA_NETX_ERR_TRUNCATED;
        if (out_port) |port| port.* = parts.port;
        return SA_NETX_OK;
    }

    fn copyOut(src: []const u8, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
        if (out) |dst| {
            const capacity = std.math.cast(usize, cap) orelse return SA_NETX_ERR_INVALID_ARGUMENT;
            if (src.len > capacity) return SA_NETX_ERR_TRUNCATED;
            if (src.len != 0) @memcpy(dst[0..src.len], src);
        }
        if (out_len) |len| len.* = @intCast(src.len);
        return SA_NETX_OK;
    }
};

test "kqueue backend exposes the stable NetX ABI surface" {
    _ = backend_name;
    _ = platform_reactor;
    _ = supports_native_reactor;
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(Ticket));
}

const RecvTicketState = struct {
    ticket: Ticket = undefined,
    result: i32 = SA_NETX_OK,
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

fn recvTicketWorker(state: *RecvTicketState) void {
    state.result = sa_netx_recv_ticket(0, &state.ticket);
    state.done.store(true, .seq_cst);
}

fn recvTicketForTest() !Ticket {
    var state = RecvTicketState{};
    const thread = try Thread.spawn(.{}, recvTicketWorker, .{&state});
    const deadline = std.time.nanoTimestamp() + 5 * std.time.ns_per_s;
    while (!state.done.load(.seq_cst) and std.time.nanoTimestamp() < deadline) {
        std.time.sleep(10 * std.time.ns_per_ms);
    }
    if (!state.done.load(.seq_cst)) {
        _ = sa_netx_shutdown();
        thread.join();
        return error.TestTimedOut;
    }
    thread.join();
    try std.testing.expectEqual(SA_NETX_OK, state.result);
    return state.ticket;
}

fn expectHttpExchangeTickets(first: Ticket, second: Ticket) !u32 {
    var slot_id: u32 = 0;
    var saw_http = false;
    const tickets = [_]Ticket{ first, second };
    for (tickets) |ticket| {
        if (ticket.op_code == @intFromEnum(TicketOp.accept)) slot_id = ticket.slot_id;
        if (ticket.op_code == @intFromEnum(TicketOp.http_request)) {
            saw_http = true;
            const payload = (@as([*]const u8, @ptrCast(ticket.payload.?)))[0..ticket.payload_len];
            try std.testing.expect(std.mem.startsWith(u8, payload, "GET /native-netx"));
        }
    }
    try std.testing.expect(slot_id != 0);
    try std.testing.expect(saw_http);
    return slot_id;
}

test "kqueue netx accepts an HTTP request through native socket events" {
    if (!builtin.target.os.tag.isDarwin()) return error.SkipZigTest;
    try std.testing.expectEqual(SA_NETX_OK, sa_netx_init(8, 1));
    var shutdown_done = false;
    errdefer {
        if (!shutdown_done) _ = sa_netx_shutdown();
    }
    const host = "127.0.0.1";
    try std.testing.expectEqual(SA_NETX_OK, sa_netx_listen(host.ptr, host.len, 0));
    const address = runtime_state.listen_address orelse return error.TestUnexpectedResult;

    const stream = try net.tcpConnectToAddress(address);
    var stream_closed = false;
    errdefer if (!stream_closed) stream.close();
    try stream.writeAll("GET /native-netx HTTP/1.1\r\nHost: example.test\r\n\r\n");

    _ = try expectHttpExchangeTickets(try recvTicketForTest(), try recvTicketForTest());

    stream.close();
    stream_closed = true;
    try std.testing.expectEqual(SA_NETX_OK, sa_netx_shutdown());
    shutdown_done = true;
}
