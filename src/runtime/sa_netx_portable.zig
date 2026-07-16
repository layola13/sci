const std = @import("std");

const net_primitives = @import("sa_net_primitives.zig");
const pal = @import("pal.zig");
const pal_sys = pal.sys;

const net = std.net;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;

pub const SA_NETX_ABI_VERSION: u32 = 1;

pub const SA_NETX_OK: i32 = 0;
pub const SA_NETX_ERR_INVALID_ARGUMENT: i32 = 1;
pub const SA_NETX_ERR_INVALID_HANDLE: i32 = 2;
pub const SA_NETX_ERR_NOT_FOUND: i32 = 3;
pub const SA_NETX_ERR_NO_MEMORY: i32 = 5;
pub const SA_NETX_ERR_IO: i32 = 6;
pub const SA_NETX_ERR_NET: i32 = 7;
pub const SA_NETX_ERR_TRUNCATED: i32 = 9;

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

const ticket_payload_capacity: usize = 4096;
const reactor_wait_forever_ms: i32 = -1;

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

const Reactor = struct {
    tickets: TicketQueue,
    event_loop: ?*anyopaque = null,
    mutex: Mutex = .{},
    cond: Condition = .{},

    fn init(allocator: std.mem.Allocator, ticket_capacity: usize) !Reactor {
        var event_loop: ?*anyopaque = null;
        if (pal_sys.event_loop_create(&event_loop) != SA_NETX_OK) return error.EventLoopCreate;
        errdefer _ = pal_sys.event_loop_close(event_loop);
        return .{
            .tickets = try TicketQueue.init(allocator, ticket_capacity),
            .event_loop = event_loop,
        };
    }

    fn deinit(self: *Reactor, allocator: std.mem.Allocator) void {
        self.tickets.deinit(allocator);
        if (self.event_loop) |event_loop| _ = pal_sys.event_loop_close(event_loop);
        self.* = undefined;
    }

    fn submitWake(self: *Reactor, event: pal.SaEvent) void {
        if (self.event_loop) |event_loop| _ = pal_sys.event_loop_submit(event_loop, &event);
    }

    fn wake(self: *Reactor) void {
        self.submitWake(.{ .user_data = 0, .flags = 0, .res = 0 });
    }

    fn queueTicket(self: *Reactor, ticket: Ticket) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        const pushed = self.tickets.push(ticket);
        if (pushed) {
            self.cond.broadcast();
            const event = pal.SaEvent{
                .user_data = ticket.slot_id,
                .flags = ticket.op_code,
                .res = @intCast(ticket.payload_len),
            };
            self.submitWake(event);
        }
        return pushed;
    }
};

const ConnectionSlot = struct {
    id: u32 = 0,
    reactor_id: u32 = 0,
    active: bool = false,
    proto: u8 = NetxProto_HTTP,
    stream: ?net.Stream = null,
    thread: ?Thread = null,
    write_mutex: Mutex = .{},
    scratch: [4096]u8 = undefined,
    scratch_used: usize = 0,
    outbound: [4096]u8 = undefined,

    fn reset(self: *ConnectionSlot, id: u32) void {
        self.id = id;
        self.reactor_id = 0;
        self.active = false;
        self.proto = NetxProto_HTTP;
        self.stream = null;
        self.thread = null;
        self.scratch_used = 0;
        @memset(self.scratch[0..], 0);
        @memset(self.outbound[0..], 0);
    }
};

const RuntimeState = struct {
    mutex: Mutex = .{},
    initialized: bool = false,
    stop: bool = false,
    listened: bool = false,
    server: ?net.Server = null,
    listen_address: ?net.Address = null,
    accept_thread: ?Thread = null,
    reactors: []Reactor = &.{},
    slots: []ConnectionSlot = &.{},
    next_slot: usize = 0,
    next_reactor: usize = 0,
};

var runtime_state: RuntimeState = .{};

fn computeTicketCapacity(slot_capacity: usize) !usize {
    return std.math.mul(usize, @max(slot_capacity, 1), 4) catch error.Overflow;
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

fn queueTicket(slot: *ConnectionSlot, ticket: Ticket) bool {
    const reactor_id = @as(usize, @intCast(slot.reactor_id));
    if (reactor_id >= runtime_state.reactors.len) return false;
    return runtime_state.reactors[reactor_id].queueTicket(ticket);
}

fn closeSlotStream(slot: *ConnectionSlot) void {
    slot.write_mutex.lock();
    defer slot.write_mutex.unlock();
    if (slot.stream) |stream| {
        stream.close();
        slot.stream = null;
    }
    slot.active = false;
}

fn allocSlot(stream: net.Stream) ?*ConnectionSlot {
    runtime_state.mutex.lock();
    defer runtime_state.mutex.unlock();
    if (!runtime_state.initialized or runtime_state.stop or runtime_state.reactors.len == 0) return null;
    var scanned: usize = 0;
    while (scanned < runtime_state.slots.len) : (scanned += 1) {
        const idx = (runtime_state.next_slot + scanned) % runtime_state.slots.len;
        const slot = &runtime_state.slots[idx];
        if (!slot.active and slot.thread == null) {
            runtime_state.next_slot = (idx + 1) % runtime_state.slots.len;
            slot.reset(@as(u32, @intCast(idx + 1)));
            slot.active = true;
            slot.stream = stream;
            slot.reactor_id = @as(u32, @intCast(runtime_state.next_reactor % runtime_state.reactors.len));
            runtime_state.next_reactor = (runtime_state.next_reactor + 1) % runtime_state.reactors.len;
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
    if (!slot.active) return null;
    return slot;
}

fn acceptLoop() void {
    while (true) {
        runtime_state.mutex.lock();
        const should_stop = runtime_state.stop or runtime_state.server == null;
        runtime_state.mutex.unlock();
        if (should_stop) break;

        const conn = if (runtime_state.server) |*server| server.accept() catch {
            runtime_state.mutex.lock();
            const stop = runtime_state.stop;
            runtime_state.mutex.unlock();
            if (stop) break;
            std.time.sleep(std.time.ns_per_ms);
            continue;
        } else break;

        const slot = allocSlot(conn.stream) orelse {
            conn.stream.close();
            continue;
        };
        const thread = Thread.spawn(.{}, connectionLoop, .{slot}) catch {
            closeSlotStream(slot);
            continue;
        };
        slot.thread = thread;
        _ = queueTicket(slot, makeTicket(slot, .accept, slot.proto, 0, &.{}));
    }
}

fn connectionLoop(slot: *ConnectionSlot) void {
    defer {
        closeSlotStream(slot);
    }

    while (slot.active) {
        var buffer: [1024]u8 = undefined;
        const read_len = blk: {
            slot.write_mutex.lock();
            const stream = slot.stream;
            slot.write_mutex.unlock();
            if (stream) |s| {
                break :blk s.read(buffer[0..]) catch 0;
            }
            break :blk 0;
        };
        if (read_len == 0) {
            _ = queueTicket(slot, makeTicket(slot, .peer_close, NetxProto_RAW, TicketFlag.eof, &.{}));
            return;
        }
        appendAndProcess(slot, buffer[0..read_len]);
    }
}

fn appendAndProcess(slot: *ConnectionSlot, bytes: []const u8) void {
    const copy_len = @min(slot.scratch.len - slot.scratch_used, bytes.len);
    if (copy_len != 0) {
        @memcpy(slot.scratch[slot.scratch_used .. slot.scratch_used + copy_len], bytes[0..copy_len]);
        slot.scratch_used += copy_len;
    }
    var flags: u8 = 0;
    if (copy_len < bytes.len) flags |= TicketFlag.truncated;

    while (slot.scratch_used != 0) {
        const pending = slot.scratch[0..slot.scratch_used];
        switch (slot.proto) {
            NetxProto_HTTP => {
                if (findHttpRequestEnd(pending)) |request_end| {
                    const request = pending[0..request_end];
                    if (isWebSocketUpgrade(request)) |key| {
                        if (sendWebSocketUpgrade(slot, key) == SA_NETX_OK) {
                            slot.proto = NetxProto_WS;
                            _ = queueTicket(slot, makeTicket(slot, .websocket_upgrade, NetxProto_HTTP, flags | TicketFlag.upgrade, request));
                        }
                    } else {
                        _ = queueTicket(slot, makeTicket(slot, .http_request, NetxProto_HTTP, flags, request));
                    }
                    consumeScratch(slot, request_end);
                    continue;
                }
                if (!looksLikeHttpPrefix(pending)) {
                    _ = queueTicket(slot, makeTicket(slot, .raw_bytes, NetxProto_RAW, flags, pending));
                    slot.scratch_used = 0;
                }
                return;
            },
            NetxProto_WS => {
                const frame = net_primitives.parseWsFrame(pending) catch |err| switch (err) {
                    error.Incomplete => return,
                    error.Invalid => {
                        closeSlotStream(slot);
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
                _ = queueTicket(slot, makeTicket(slot, .ws_frame, NetxProto_WS, frame_flags, payload));
                consumeScratch(slot, frame.frame_len);
                if (frame.opcode == 0x8) {
                    closeSlotStream(slot);
                    return;
                }
                continue;
            },
            else => {
                _ = queueTicket(slot, makeTicket(slot, .raw_bytes, NetxProto_RAW, flags, pending));
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

fn sendWebSocketUpgrade(slot: *ConnectionSlot, key: []const u8) i32 {
    const accept = net_primitives.websocketAccept(key) catch return SA_NETX_ERR_INVALID_ARGUMENT;
    var response_buf: [256]u8 = undefined;
    const response = std.fmt.bufPrint(
        response_buf[0..],
        "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: {s}\r\n\r\n",
        .{accept},
    ) catch return SA_NETX_ERR_IO;
    return writeSlot(slot, response, false);
}

fn writeSlot(slot: *ConnectionSlot, bytes: []const u8, websocket_frame: bool) i32 {
    slot.write_mutex.lock();
    defer slot.write_mutex.unlock();
    var stream = slot.stream orelse return SA_NETX_ERR_INVALID_HANDLE;
    const payload = if (websocket_frame) blk: {
        const written = net_primitives.buildWsFrame(0x2, true, bytes, null, slot.outbound[0..]) catch |err| switch (err) {
            error.NoSpaceLeft => return SA_NETX_ERR_TRUNCATED,
            else => return SA_NETX_ERR_INVALID_ARGUMENT,
        };
        break :blk slot.outbound[0..written];
    } else bytes;
    stream.writeAll(payload) catch return SA_NETX_ERR_IO;
    return SA_NETX_OK;
}

pub export fn sa_netx_init(slot_capacity: u64, reactor_count: u32) i32 {
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
        reactors[initialized_reactors] = Reactor.init(allocator, ticket_capacity) catch |err| {
            var idx: usize = 0;
            while (idx < initialized_reactors) : (idx += 1) reactors[idx].deinit(allocator);
            return if (err == error.EventLoopCreate) SA_NETX_ERR_IO else SA_NETX_ERR_NO_MEMORY;
        };
    }

    const slots = allocator.alloc(ConnectionSlot, slot_capacity_usize) catch {
        for (reactors) |*reactor| reactor.deinit(allocator);
        allocator.free(reactors);
        return SA_NETX_ERR_NO_MEMORY;
    };
    for (slots, 0..) |*slot, idx| slot.reset(@as(u32, @intCast(idx + 1)));

    runtime_state.initialized = true;
    runtime_state.stop = false;
    runtime_state.listened = false;
    runtime_state.server = null;
    runtime_state.listen_address = null;
    runtime_state.accept_thread = null;
    runtime_state.reactors = reactors;
    runtime_state.slots = slots;
    runtime_state.next_slot = 0;
    runtime_state.next_reactor = 0;
    return SA_NETX_OK;
}

pub export fn sa_netx_listen(host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    runtime_state.mutex.lock();
    if (!runtime_state.initialized) {
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
    var server = address.listen(.{
        .kernel_backlog = 256,
        .reuse_address = true,
        .force_nonblocking = true,
    }) catch return SA_NETX_ERR_NET;

    runtime_state.mutex.lock();
    if (runtime_state.stop or runtime_state.listened) {
        runtime_state.mutex.unlock();
        server.deinit();
        return SA_NETX_ERR_INVALID_ARGUMENT;
    }
    runtime_state.listen_address = server.listen_address;
    runtime_state.server = server;
    runtime_state.listened = true;
    runtime_state.mutex.unlock();

    const thread = Thread.spawn(.{}, acceptLoop, .{}) catch {
        runtime_state.mutex.lock();
        if (runtime_state.server) |*owned| owned.deinit();
        runtime_state.server = null;
        runtime_state.listen_address = null;
        runtime_state.listened = false;
        runtime_state.mutex.unlock();
        return SA_NETX_ERR_NO_MEMORY;
    };
    runtime_state.mutex.lock();
    runtime_state.accept_thread = thread;
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

    reactor.mutex.lock();
    defer reactor.mutex.unlock();
    while (reactor.tickets.isEmpty()) {
        runtime_state.mutex.lock();
        const stop = runtime_state.stop or !runtime_state.initialized;
        runtime_state.mutex.unlock();
        if (stop) {
            zeroTicket(out_ticket);
            return SA_NETX_ERR_NOT_FOUND;
        }
        const event_loop = reactor.event_loop;
        reactor.mutex.unlock();
        var wake_event = [_]pal.SaEvent{.{ .user_data = 0, .flags = 0, .res = 0 }};
        const ready = if (event_loop) |loop|
            pal_sys.event_loop_wait(loop, &wake_event, 1, reactor_wait_forever_ms)
        else
            0;
        reactor.mutex.lock();
        if (ready < 0) {
            zeroTicket(out_ticket);
            return SA_NETX_ERR_IO;
        }
    }
    ticket_ptr.* = reactor.tickets.pop().?;
    return SA_NETX_OK;
}

pub export fn sa_netx_push_outbound(reactor_id: u32, slot_id: u32, msg_ptr: ?[*]const u8, len: u32) i32 {
    _ = reactor_id;
    const slot = slotFromId(slot_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    const msg = if (len == 0) &[_]u8{} else blk: {
        const ptr = msg_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        break :blk ptr[0..@as(usize, @intCast(len))];
    };
    const result = writeSlot(slot, msg, slot.proto == NetxProto_WS);
    if (result == SA_NETX_OK) {
        _ = queueTicket(slot, makeTicket(slot, .send_done, slot.proto, 0, &.{}));
    }
    return result;
}

pub export fn sa_netx_broadcast(reactor_id: u32, slot_ids_ptr: ?[*]const u32, n: u32, msg_ptr: ?[*]const u8, len: u32) i32 {
    _ = reactor_id;
    const slots = if (n == 0) &[_]u32{} else blk: {
        const ptr = slot_ids_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        break :blk ptr[0..@as(usize, @intCast(n))];
    };
    const msg = if (len == 0) &[_]u8{} else blk: {
        const ptr = msg_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        break :blk ptr[0..@as(usize, @intCast(len))];
    };
    for (slots) |slot_id| {
        const slot = slotFromId(slot_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
        const result = writeSlot(slot, msg, slot.proto == NetxProto_WS);
        if (result != SA_NETX_OK) return result;
        _ = queueTicket(slot, makeTicket(slot, .send_done, slot.proto, 0, &.{}));
    }
    return SA_NETX_OK;
}

pub export fn sa_netx_close_slot(slot_id: u32) i32 {
    const slot = slotFromId(slot_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    closeSlotStream(slot);
    return SA_NETX_OK;
}

pub export fn sa_netx_shutdown() i32 {
    runtime_state.mutex.lock();
    if (!runtime_state.initialized) {
        runtime_state.mutex.unlock();
        return SA_NETX_OK;
    }
    runtime_state.stop = true;
    for (runtime_state.reactors) |*reactor| {
        reactor.mutex.lock();
        reactor.cond.broadcast();
        reactor.mutex.unlock();
        reactor.wake();
    }
    if (runtime_state.server) |*server| {
        server.deinit();
        runtime_state.server = null;
    }
    const accept_thread = runtime_state.accept_thread;
    runtime_state.accept_thread = null;
    for (runtime_state.slots) |*slot| closeSlotStream(slot);
    runtime_state.mutex.unlock();

    if (accept_thread) |thread| thread.join();
    for (runtime_state.slots) |*slot| {
        if (slot.thread) |thread| {
            thread.join();
            slot.thread = null;
        }
    }

    runtime_state.mutex.lock();
    const allocator = std.heap.page_allocator;
    for (runtime_state.reactors) |*reactor| {
        reactor.mutex.lock();
        reactor.cond.broadcast();
        reactor.mutex.unlock();
        reactor.wake();
        reactor.deinit(allocator);
    }
    if (runtime_state.reactors.len != 0) allocator.free(runtime_state.reactors);
    if (runtime_state.slots.len != 0) allocator.free(runtime_state.slots);
    runtime_state.initialized = false;
    runtime_state.stop = false;
    runtime_state.listened = false;
    runtime_state.server = null;
    runtime_state.listen_address = null;
    runtime_state.accept_thread = null;
    runtime_state.reactors = &.{};
    runtime_state.slots = &.{};
    runtime_state.next_slot = 0;
    runtime_state.next_reactor = 0;
    runtime_state.mutex.unlock();
    return SA_NETX_OK;
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

test "portable netx init and shutdown round-trip" {
    try std.testing.expectEqual(SA_NETX_OK, sa_netx_init(8, 1));
    try std.testing.expect(runtime_state.initialized);
    try std.testing.expectEqual(SA_NETX_OK, sa_netx_shutdown());
    try std.testing.expect(!runtime_state.initialized);
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
            try std.testing.expect(std.mem.startsWith(u8, payload, "GET /portable"));
        }
    }
    try std.testing.expect(slot_id != 0);
    try std.testing.expect(saw_http);
    return slot_id;
}

test "portable netx accepts an HTTP request and queues tickets" {
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
    try stream.writeAll("GET /portable HTTP/1.1\r\nHost: example.test\r\n\r\n");

    _ = try expectHttpExchangeTickets(try recvTicketForTest(), try recvTicketForTest());

    stream.close();
    stream_closed = true;
    try std.testing.expectEqual(SA_NETX_OK, sa_netx_shutdown());
    shutdown_done = true;
}

test "portable netx sends outbound bytes and queues send_done" {
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
    try stream.writeAll("GET /portable HTTP/1.1\r\nHost: example.test\r\n\r\n");

    const slot_id = try expectHttpExchangeTickets(try recvTicketForTest(), try recvTicketForTest());
    const response = "portable response";
    try std.testing.expectEqual(
        SA_NETX_OK,
        sa_netx_push_outbound(0, slot_id, response.ptr, @as(u32, @intCast(response.len))),
    );

    var read_buf: [64]u8 = undefined;
    const read_len = try stream.read(read_buf[0..]);
    try std.testing.expectEqualStrings(response, read_buf[0..read_len]);

    const send_ticket = try recvTicketForTest();
    try std.testing.expectEqual(slot_id, send_ticket.slot_id);
    try std.testing.expectEqual(@as(u16, @intFromEnum(TicketOp.send_done)), send_ticket.op_code);

    stream.close();
    stream_closed = true;
    try std.testing.expectEqual(SA_NETX_OK, sa_netx_shutdown());
    shutdown_done = true;
}
