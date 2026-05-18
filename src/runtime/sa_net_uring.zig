const std = @import("std");
const builtin = @import("builtin");
const sa_std = @import("sa_std.zig");

const net = std.net;
const posix = std.posix;
const linux = std.os.linux;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;

pub const SA_NETX_ABI_VERSION: u32 = 1;

pub const SA_NETX_OK: i32 = sa_std.SA_STD_OK;
pub const SA_NETX_ERR_INVALID_ARGUMENT: i32 = sa_std.SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_NETX_ERR_INVALID_HANDLE: i32 = sa_std.SA_STD_ERR_INVALID_HANDLE;
pub const SA_NETX_ERR_NOT_FOUND: i32 = sa_std.SA_STD_ERR_NOT_FOUND;
pub const SA_NETX_ERR_ACCESS: i32 = sa_std.SA_STD_ERR_ACCESS;
pub const SA_NETX_ERR_NO_MEMORY: i32 = sa_std.SA_STD_ERR_NO_MEMORY;
pub const SA_NETX_ERR_IO: i32 = sa_std.SA_STD_ERR_IO;
pub const SA_NETX_ERR_NET: i32 = sa_std.SA_STD_ERR_NET;
pub const SA_NETX_ERR_UNSUPPORTED: i32 = sa_std.SA_STD_ERR_UNSUPPORTED;
pub const SA_NETX_ERR_TRUNCATED: i32 = sa_std.SA_STD_ERR_TRUNCATED;

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
    pub const zc: u8 = 1 << 4;
};

const HANDSHAKE_TIMEOUT_NS: u64 = 5 * std.time.ns_per_s;
const IDLE_TIMEOUT_NS: u64 = 60 * std.time.ns_per_s;
const REACTOR_TIMEOUT_NS: u64 = 250 * std.time.ns_per_ms;

const ReactorUserTag = enum(u8) {
    none,
    accept,
    recv,
    send,
    timeout,
    wakeup,
};

const WorkerState = struct {
    mutex: Mutex = .{},
    cond: Condition = .{},
    running: bool = false,
    stop: bool = false,
    active_workers: usize = 0,
};

const ReactorCommandKind = enum(u8) {
    listen,
    send,
    broadcast,
    close,
};

const ReactorCommand = struct {
    kind: ReactorCommandKind,
    slot_id: u32,
    use_zc: bool = false,
    msg_ptr: ?[*]const u8 = null,
    msg_len: usize = 0,
    slot_ids_ptr: ?[*]const u32 = null,
    slot_ids_len: usize = 0,
    address: ?net.Address = null,
};

const ReactorCommandQueue = struct {
    storage: []ReactorCommand,
    head: u32 = 0,
    tail: u32 = 0,
    mask: u32 = 0,
    mmap_bytes: []align(std.heap.page_size_min) u8 = &.{},

    fn init(requested_capacity: usize) !ReactorCommandQueue {
        const cap = ceilPow2(@max(requested_capacity, 64));
        const bytes_len = cap * @sizeOf(ReactorCommand);
        const base_flags = std.posix.MAP{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
            .POPULATE = true,
        };
        const huge_flags = std.posix.MAP{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
            .POPULATE = true,
            .HUGETLB = true,
        };

        const mapped = std.posix.mmap(null, bytes_len, linux.PROT.READ | linux.PROT.WRITE, huge_flags, -1, 0) catch std.posix.mmap(null, bytes_len, linux.PROT.READ | linux.PROT.WRITE, base_flags, -1, 0) catch return error.OutOfMemory;
        @memset(mapped, 0);
        const ptr: [*]align(@alignOf(ReactorCommand)) ReactorCommand = @ptrCast(@alignCast(mapped.ptr));
        return .{
            .storage = ptr[0..cap],
            .mask = @as(u32, @intCast(cap - 1)),
            .mmap_bytes = mapped,
        };
    }

    fn deinit(self: *ReactorCommandQueue) void {
        if (self.mmap_bytes.len != 0) {
            const bytes: []align(std.heap.page_size_min) const u8 = self.mmap_bytes;
            std.posix.munmap(bytes);
        }
        self.* = undefined;
    }

    fn isEmpty(self: *const ReactorCommandQueue) bool {
        return self.head == self.tail;
    }

    fn isFull(self: *const ReactorCommandQueue) bool {
        return self.tail -% self.head == self.storage.len;
    }

    fn freeCount(self: *const ReactorCommandQueue) usize {
        return self.storage.len - @as(usize, @intCast(self.tail -% self.head));
    }

    fn push(self: *ReactorCommandQueue, command: ReactorCommand) bool {
        if (self.isFull()) return false;
        self.storage[self.tail & self.mask] = command;
        self.tail +%= 1;
        return true;
    }

    fn pop(self: *ReactorCommandQueue) ?ReactorCommand {
        if (self.isEmpty()) return null;
        const command = self.storage[self.head & self.mask];
        self.head +%= 1;
        return command;
    }
};

pub const Ticket = extern struct {
    slot_id: u32,
    op_code: u16,
    proto: u8,
    flags: u8,
    payload: *u8,
    payload_len: u32,
    pad: u32,
};

comptime {
    std.debug.assert(@sizeOf(Ticket) == 24);
    std.debug.assert(@offsetOf(Ticket, "slot_id") == 0);
    std.debug.assert(@offsetOf(Ticket, "op_code") == 4);
    std.debug.assert(@offsetOf(Ticket, "proto") == 6);
    std.debug.assert(@offsetOf(Ticket, "flags") == 7);
    std.debug.assert(@offsetOf(Ticket, "payload") == 8);
    std.debug.assert(@offsetOf(Ticket, "payload_len") == 16);
    std.debug.assert(@offsetOf(Ticket, "pad") == 20);
}

pub const SlotState = enum(u8) {
    Free,
    Accepting,
    Handshake,
    Reading,
    Http,
    WebSocket,
    RawBinary,
    HalfClosed,
    Closing,
};

pub const HttpRequest = struct {
    method: FieldSpan,
    path: FieldSpan,
    version: FieldSpan,
    content_length: usize,
    websocket_key: ?FieldSpan,
    websocket_upgrade: bool,
    request_end: usize,
};

pub const WsFrame = struct {
    fin: bool,
    opcode: u8,
    masked: bool,
    payload_start: usize,
    payload_len: usize,
    frame_len: usize,
    mask: [4]u8,
};

pub const FieldSpan = struct {
    offset: u32,
    len: u32,
};

const ConnectionSlot = struct {
    fd: posix.fd_t align(64) = -1,
    reactor_id: u32 = 0,
    slot_id: u32 = 0,
    state: SlotState = .Free,
    proto: u8 = NetxProto_HTTP,
    flags: u8 = 0,
    recv_paused: bool = false,
    recv_multishot_armed: bool = false,
    accept_multishot_armed: bool = false,
    outbound_inflight: bool = false,
    outbound_mode_zc: bool = false,
    outbound_len: usize = 0,
    scratch_used: usize = 0,
    message_start: usize = 0,
    scratch: [4096]u8 = undefined,
    outbound_scratch: [4096]u8 = undefined,
    last_active_ns: u64 = 0,
    handshake_deadline_ns: u64 = 0,

    fn initFree(self: *ConnectionSlot, slot_id: u32) void {
        self.fd = -1;
        self.reactor_id = 0;
        self.slot_id = slot_id;
        self.state = .Free;
        self.proto = NetxProto_HTTP;
        self.flags = 0;
        self.recv_paused = false;
        self.recv_multishot_armed = false;
        self.accept_multishot_armed = false;
        self.outbound_inflight = false;
        self.outbound_mode_zc = false;
        self.outbound_len = 0;
        self.scratch_used = 0;
        self.message_start = 0;
        self.last_active_ns = 0;
        self.handshake_deadline_ns = 0;
    }

    fn initAccepted(self: *ConnectionSlot, reactor_id: u32, fd: posix.fd_t, now_ns: u64) void {
        self.fd = fd;
        self.reactor_id = reactor_id;
        self.state = .Accepting;
        self.proto = NetxProto_HTTP;
        self.flags = 0;
        self.recv_paused = false;
        self.recv_multishot_armed = false;
        self.accept_multishot_armed = false;
        self.outbound_inflight = false;
        self.outbound_mode_zc = false;
        self.outbound_len = 0;
        self.scratch_used = 0;
        self.message_start = 0;
        self.last_active_ns = now_ns;
        self.handshake_deadline_ns = now_ns + HANDSHAKE_TIMEOUT_NS;
        @memset(self.scratch[0..], 0);
        @memset(self.outbound_scratch[0..], 0);
    }

    fn clear(self: *ConnectionSlot) void {
        if (self.fd >= 0) {
            posix.close(self.fd);
        }
        self.initFree(self.slot_id);
    }

    fn markActive(self: *ConnectionSlot, now_ns: u64) void {
        self.last_active_ns = now_ns;
        if (self.state == .Handshake or self.state == .Reading) {
            self.handshake_deadline_ns = now_ns + HANDSHAKE_TIMEOUT_NS;
        }
    }
};

comptime {
    std.debug.assert(@alignOf(ConnectionSlot) == 64);
    std.debug.assert(@sizeOf(ConnectionSlot) % 64 == 0);
}

const TicketQueue = struct {
    storage: []Ticket,
    head: u32 = 0,
    tail: u32 = 0,
    mask: u32 = 0,
    mmap_bytes: []align(std.heap.page_size_min) u8 = &.{},

    fn init(requested_capacity: usize) !TicketQueue {
        const cap = ceilPow2(@max(requested_capacity, 64));
        const bytes_len = cap * @sizeOf(Ticket);
        const base_flags = std.posix.MAP{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
            .POPULATE = true,
        };
        const huge_flags = std.posix.MAP{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
            .POPULATE = true,
            .HUGETLB = true,
        };

        const mapped = std.posix.mmap(null, bytes_len, linux.PROT.READ | linux.PROT.WRITE, huge_flags, -1, 0) catch std.posix.mmap(null, bytes_len, linux.PROT.READ | linux.PROT.WRITE, base_flags, -1, 0) catch return error.OutOfMemory;
        @memset(mapped, 0);
        const ptr: [*]align(@alignOf(Ticket)) Ticket = @ptrCast(@alignCast(mapped.ptr));
        return .{
            .storage = ptr[0..cap],
            .mask = @as(u32, @intCast(cap - 1)),
            .mmap_bytes = mapped,
        };
    }

    fn deinit(self: *TicketQueue) void {
        if (self.mmap_bytes.len != 0) {
            const bytes: []align(std.heap.page_size_min) const u8 = self.mmap_bytes;
            std.posix.munmap(bytes);
        }
        self.* = undefined;
    }

    fn isEmpty(self: *const TicketQueue) bool {
        return self.head == self.tail;
    }

    fn isFull(self: *const TicketQueue) bool {
        return self.tail -% self.head == self.storage.len;
    }

    fn push(self: *TicketQueue, ticket: Ticket) bool {
        if (self.isFull()) return false;
        self.storage[self.tail & self.mask] = ticket;
        self.tail +%= 1;
        return true;
    }

    fn pop(self: *TicketQueue) ?Ticket {
        if (self.isEmpty()) return null;
        const ticket = self.storage[self.head & self.mask];
        self.head +%= 1;
        return ticket;
    }
};

const SlotPool = struct {
    bytes: []align(std.heap.page_size_min) u8,
    slots: []ConnectionSlot,
    capacity: usize,
    next_hint: usize = 0,

    fn init(capacity: usize) !SlotPool {
        if (capacity == 0) return error.InvalidArgument;
        const bytes_len = capacity * @sizeOf(ConnectionSlot);
        const base_flags = std.posix.MAP{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
            .POPULATE = true,
        };
        const huge_flags = std.posix.MAP{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
            .POPULATE = true,
            .HUGETLB = true,
        };

        const mapped = std.posix.mmap(null, bytes_len, linux.PROT.READ | linux.PROT.WRITE, huge_flags, -1, 0) catch std.posix.mmap(null, bytes_len, linux.PROT.READ | linux.PROT.WRITE, base_flags, -1, 0) catch return error.OutOfMemory;
        @memset(mapped, 0);
        const ptr: [*]align(@alignOf(ConnectionSlot)) ConnectionSlot = @ptrCast(@alignCast(mapped.ptr));
        const slots = ptr[0..capacity];
        for (slots, 0..) |*slot, idx| {
            slot.initFree(@as(u32, @intCast(idx + 1)));
        }
        return .{
            .bytes = mapped,
            .slots = slots,
            .capacity = capacity,
        };
    }

    fn deinit(self: *SlotPool) void {
        if (self.bytes.len != 0) {
            const bytes: []align(std.heap.page_size_min) const u8 = self.bytes;
            std.posix.munmap(bytes);
        }
        self.* = undefined;
    }

    fn slotFromId(self: *const SlotPool, slot_id: u32) ?*ConnectionSlot {
        if (slot_id == 0) return null;
        const idx = @as(usize, @intCast(slot_id - 1));
        if (idx >= self.capacity) return null;
        return &self.slots[idx];
    }

    fn slotIdFromIndex(index: usize) u32 {
        return @as(u32, @intCast(index + 1));
    }

    fn allocSlot(self: *SlotPool, reactor_id: u32, fd: posix.fd_t, now_ns: u64) ?*ConnectionSlot {
        var scanned: usize = 0;
        while (scanned < self.capacity) : (scanned += 1) {
            const idx = (self.next_hint + scanned) % self.capacity;
            const slot = &self.slots[idx];
            if (slot.state == .Free) {
                self.next_hint = (idx + 1) % self.capacity;
                slot.slot_id = slotIdFromIndex(idx);
                slot.initAccepted(reactor_id, fd, now_ns);
                return slot;
            }
        }
        return null;
    }
};

const Reactor = struct {
    id: u32,
    ring: linux.IoUring,
    tickets: TicketQueue,
    ticket_mutex: Mutex = .{},
    ticket_cond: Condition = .{},
    command_mutex: Mutex = .{},
    command_cond: Condition = .{},
    server: ?net.Server = null,
    buffers: []align(std.heap.page_size_min) u8 = &.{},
    buffer_group: ?linux.IoUring.BufferGroup = null,
    timeout_armed: bool = false,
    wake_armed: bool = false,
    worker_started: bool = false,
    worker: ?Thread = null,
    command_eventfd: posix.fd_t = -1,
    command_pending: bool = false,
    command_result: i32 = SA_NETX_OK,
    command: ReactorCommand = .{ .kind = .send, .slot_id = 0 },
    resume_requested: bool = false,
    accept_multishot_supported: bool = true,
    recv_multishot_supported: bool = true,
    send_zc_supported: bool = true,
    accept_armed: bool = false,
    accept_addr: posix.sockaddr = undefined,
    accept_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr),

    fn init(id: u32, ticket_capacity: usize) !Reactor {
        var ring = try linux.IoUring.init(256, 0);
        errdefer ring.deinit();
        const tickets = try TicketQueue.init(ticket_capacity);
        errdefer {
            var tickets_owned = tickets;
            tickets_owned.deinit();
        }
        const command_eventfd = posix.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK) catch {
            var tickets_owned = tickets;
            tickets_owned.deinit();
            ring.deinit();
            return error.OutOfMemory;
        };
        return .{
            .id = id,
            .ring = ring,
            .tickets = tickets,
            .command_eventfd = command_eventfd,
        };
    }

    fn deinit(self: *Reactor) void {
        self.stopWorker();
        if (self.command_eventfd >= 0) {
            posix.close(self.command_eventfd);
            self.command_eventfd = -1;
        }
        self.tickets.deinit();
        if (self.buffer_group) |*group| {
            group.deinit();
            self.buffer_group = null;
        }
        if (self.buffers.len != 0) {
            const bytes: []align(std.heap.page_size_min) const u8 = self.buffers;
            std.posix.munmap(bytes);
            self.buffers = &.{};
        }
        if (self.server) |*server| {
            server.deinit();
            self.server = null;
        }
        self.ring.deinit();
    }

    fn startWorker(self: *Reactor) !void {
        if (self.worker_started) return;
        const worker = try Thread.spawn(.{}, reactorWorkerMain, .{self});
        self.worker = worker;
        self.worker_started = true;
    }

    fn stopWorker(self: *Reactor) void {
        if (!self.worker_started) return;
        self.command_mutex.lock();
        self.command_pending = false;
        self.command_result = SA_NETX_ERR_IO;
        self.command_cond.broadcast();
        self.command_mutex.unlock();
        self.ticket_cond.broadcast();
        getState().worker_state.mutex.lock();
        getState().worker_state.stop = true;
        getState().worker_state.cond.broadcast();
        getState().worker_state.mutex.unlock();
        self.signalWake();
        if (self.worker) |worker| {
            worker.join();
            self.worker = null;
        }
        self.worker_started = false;
    }

    fn ensureBuffers(self: *Reactor) !void {
        if (self.buffer_group != null or self.buffers.len != 0) return;
        const buffer_count = 64;
        const buffer_size = 4096;
        const total = buffer_count * buffer_size;
        const base_flags = std.posix.MAP{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
            .POPULATE = true,
        };
        const mapped = std.posix.mmap(null, total, linux.PROT.READ | linux.PROT.WRITE, base_flags, -1, 0) catch return error.OutOfMemory;
        @memset(mapped, 0);
        self.buffers = mapped;
        self.buffer_group = linux.IoUring.BufferGroup.init(&self.ring, @as(u16, @intCast(self.id + 1)), self.buffers[0..total], buffer_size, buffer_count) catch {
            self.buffer_group = null;
            return;
        };
    }

    fn signalWake(self: *Reactor) void {
        if (self.command_eventfd < 0) return;
        const value: u64 = 1;
        _ = posix.write(self.command_eventfd, std.mem.asBytes(&value)) catch {};
    }

    fn drainWakeEvent(self: *Reactor) void {
        if (self.command_eventfd < 0) return;
        var buf: [8]u8 = undefined;
        _ = posix.read(self.command_eventfd, buf[0..]) catch {};
    }

    fn armWakeup(self: *Reactor) !void {
        if (self.command_eventfd < 0) return;
        if (self.wake_armed) return;
        _ = try self.ring.poll_add(packUserData(.wakeup, self.id, 0), self.command_eventfd, posix.POLL.IN | posix.POLL.ERR | posix.POLL.HUP);
        self.wake_armed = true;
    }

    fn armAccept(self: *Reactor) !void {
        if (self.server == null) return;
        if (self.accept_armed and self.accept_multishot_supported) return;
        const ud = packUserData(.accept, self.id, 0);
        if (self.accept_multishot_supported) {
            self.accept_addr_len = @sizeOf(posix.sockaddr);
            const sqe = self.ring.accept_multishot(ud, self.server.?.stream.handle, &self.accept_addr, &self.accept_addr_len, 0) catch |err| switch (err) {
                else => blk: {
                    self.accept_multishot_supported = false;
                    self.accept_addr_len = @sizeOf(posix.sockaddr);
                    break :blk try self.ring.accept(ud, self.server.?.stream.handle, &self.accept_addr, &self.accept_addr_len, 0);
                },
            };
            _ = sqe;
            self.accept_armed = true;
        } else {
            self.accept_addr_len = @sizeOf(posix.sockaddr);
            _ = try self.ring.accept(ud, self.server.?.stream.handle, &self.accept_addr, &self.accept_addr_len, 0);
            self.accept_armed = true;
        }
    }

    fn armRecv(self: *Reactor, slot: *ConnectionSlot) !void {
        if (slot.state == .Free or slot.state == .Closing) return;
        if (slot.fd < 0) return;
        if (slot.recv_multishot_armed and self.recv_multishot_supported) return;
        if (slot.recv_paused) return;
        const ud = packUserData(.recv, self.id, slot.slot_id);
        if (self.buffer_group) |*group| {
            if (self.recv_multishot_supported) {
                _ = group.recv_multishot(ud, slot.fd, 0) catch {
                    self.recv_multishot_supported = false;
                    _ = try group.recv(ud, slot.fd, 0);
                };
                slot.recv_multishot_armed = true;
            } else {
                _ = try group.recv(ud, slot.fd, 0);
                slot.recv_multishot_armed = false;
            }
        } else {
            if (self.recv_multishot_supported) {
                _ = self.ring.recv(ud, slot.fd, .{ .buffer = slot.scratch[0..] }, 0) catch {
                    self.recv_multishot_supported = false;
                    _ = try self.ring.recv(ud, slot.fd, .{ .buffer = slot.scratch[0..] }, 0);
                };
                slot.recv_multishot_armed = true;
            } else {
                _ = try self.ring.recv(ud, slot.fd, .{ .buffer = slot.scratch[0..] }, 0);
                slot.recv_multishot_armed = false;
            }
        }
    }

    fn drain(self: *Reactor, wait_one: bool) !void {
        if (wait_one) {
            const cqe = try self.ring.copy_cqe();
            try self.handleCqe(cqe);
            while (self.ring.cq_ready() > 0) {
                const extra = try self.ring.copy_cqe();
                try self.handleCqe(extra);
            }
            return;
        }
        while (self.ring.cq_ready() > 0) {
            const cqe = try self.ring.copy_cqe();
            try self.handleCqe(cqe);
        }
    }

    fn handleCqe(self: *Reactor, cqe: linux.io_uring_cqe) !void {
        const ud = decodeUserData(cqe.user_data);
        switch (ud.tag) {
            .accept => try self.handleAcceptCqe(cqe),
            .recv => try self.handleRecvCqe(ud.slot_id, cqe),
            .send => try self.handleSendCqe(ud.slot_id, cqe),
            .timeout => try self.handleTimeoutCqe(cqe),
            .wakeup => try self.handleWakeupCqe(cqe),
            .none => {},
        }
    }

    fn handleWakeupCqe(self: *Reactor, cqe: linux.io_uring_cqe) !void {
        _ = cqe;
        self.wake_armed = false;
        self.drainWakeEvent();
    }

    fn armTimeout(self: *Reactor) !void {
        if (self.timeout_armed) return;
        const ts = linux.kernel_timespec{
            .sec = @as(i64, @intCast(REACTOR_TIMEOUT_NS / std.time.ns_per_s)),
            .nsec = @as(i64, @intCast(REACTOR_TIMEOUT_NS % std.time.ns_per_s)),
        };
        _ = try self.ring.timeout(packUserData(.timeout, self.id, 0), &ts, 0, 0);
        self.timeout_armed = true;
    }

    fn handleTimeoutCqe(self: *Reactor, cqe: linux.io_uring_cqe) !void {
        self.timeout_armed = false;
        _ = cqe;
        self.scanExpiredSlots();
        self.resumePausedSlots();
        try self.armTimeout();
        _ = try self.ring.submit();
    }

    fn scanExpiredSlots(self: *Reactor) void {
        const now_ns = std.time.nanoTimestamp();
        if (runtime_state.slot_pool) |*pool| {
            for (pool.slots) |*slot| {
                if (slot.reactor_id != self.id) continue;
                if (slot.state == .Free or slot.state == .Closing or slot.fd < 0) continue;
                if ((slot.state == .Handshake or slot.state == .Reading) and now_ns >= slot.handshake_deadline_ns) {
                    _ = self.queueCloseTicket(slot, TicketFlag.eof);
                    slot.state = .Closing;
                    slot.clear();
                    continue;
                }
                if (now_ns >= slot.last_active_ns + IDLE_TIMEOUT_NS) {
                    _ = self.queueCloseTicket(slot, TicketFlag.eof);
                    slot.state = .Closing;
                    slot.clear();
                }
            }
        }
    }

    fn resumePausedSlots(self: *Reactor) void {
        if (self.ticketIsFull()) return;
        if (runtime_state.slot_pool) |*pool| {
            for (pool.slots) |*slot| {
                if (slot.reactor_id != self.id) continue;
                if (!slot.recv_paused) continue;
                if (slot.state == .Free or slot.state == .Closing or slot.fd < 0) continue;
                slot.recv_paused = false;
                switch (slot.state) {
                    .Accepting => {
                        if (self.queueAcceptTicket(slot)) {
                            slot.state = .Handshake;
                            slot.markActive(@as(u64, @intCast(std.time.nanoTimestamp())));
                            self.armRecv(slot) catch {
                                slot.recv_paused = true;
                            };
                        } else {
                            slot.recv_paused = true;
                        }
                    },
                    else => {
                        self.armRecv(slot) catch {
                            slot.recv_paused = true;
                        };
                    },
                }
                if (self.ticketIsFull()) return;
            }
        }
    }

    fn requestResume(self: *Reactor) void {
        self.command_mutex.lock();
        self.resume_requested = true;
        self.command_mutex.unlock();
        self.signalWake();
    }

    fn processPendingCommand(self: *Reactor) void {
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
                    if (self.server != null) {
                        self.stopListening();
                    }
                    self.server = address.listen(.{
                        .kernel_backlog = 256,
                        .reuse_address = true,
                        .reuse_port = true,
                        .force_nonblocking = true,
                    }) catch {
                        result = SA_NETX_ERR_NET;
                        self.finishCommand(result);
                        return;
                    };
                    self.ensureBuffers() catch {
                        self.stopListening();
                        self.finishCommand(SA_NETX_ERR_NO_MEMORY);
                        return;
                    };
                    self.armAccept() catch {
                        self.stopListening();
                        self.finishCommand(SA_NETX_ERR_IO);
                        return;
                    };
                    self.armWakeup() catch {};
                    _ = self.ring.submit() catch {
                        self.stopListening();
                        result = SA_NETX_ERR_IO;
                    };
                } else {
                    self.stopListening();
                }
            },
            .send => {
                var pool = runtime_state.slot_pool orelse {
                    result = SA_NETX_ERR_INVALID_HANDLE;
                    self.finishCommand(result);
                    return;
                };
                const slot = pool.slotFromId(command.slot_id) orelse {
                    result = SA_NETX_ERR_INVALID_HANDLE;
                    self.finishCommand(result);
                    return;
                };
                if (slot.state == .Free or slot.state == .Closing or slot.fd < 0) {
                    result = SA_NETX_ERR_INVALID_HANDLE;
                } else if (command.msg_len > slot.outbound_scratch.len) {
                    result = SA_NETX_ERR_TRUNCATED;
                } else {
                    const msg = if (command.msg_len == 0) &[_]u8{} else command.msg_ptr orelse {
                        result = SA_NETX_ERR_INVALID_ARGUMENT;
                        self.finishCommand(result);
                        return;
                    };
                    self.sendBytes(slot, msg[0..command.msg_len], command.use_zc, slot.state == .WebSocket) catch |err| switch (err) {
                        error.NoSpaceLeft => result = SA_NETX_ERR_TRUNCATED,
                        error.WouldBlock => result = SA_NETX_ERR_IO,
                        else => result = SA_NETX_ERR_IO,
                    };
                    if (result == SA_NETX_OK) {
                        _ = self.ring.submit() catch {
                            slot.outbound_inflight = false;
                            slot.outbound_mode_zc = false;
                            slot.outbound_len = 0;
                            result = SA_NETX_ERR_IO;
                        };
                    }
                }
            },
            .broadcast => {
                var pool = runtime_state.slot_pool orelse {
                    result = SA_NETX_ERR_INVALID_HANDLE;
                    self.finishCommand(result);
                    return;
                };
                if (command.slot_ids_len == 0) {
                    result = SA_NETX_OK;
                } else {
                    const msg = if (command.msg_len == 0) &[_]u8{} else command.msg_ptr orelse {
                        result = SA_NETX_ERR_INVALID_ARGUMENT;
                        self.finishCommand(result);
                        return;
                    };
                    const slots = command.slot_ids_ptr orelse {
                        result = SA_NETX_ERR_INVALID_ARGUMENT;
                        self.finishCommand(result);
                        return;
                    };
                    const use_zc = command.use_zc or command.slot_ids_len >= 8 or command.msg_len >= 1536;
                    var idx: usize = 0;
                    while (idx < command.slot_ids_len) : (idx += 1) {
                        const slot = pool.slotFromId(slots[idx]) orelse {
                            result = SA_NETX_ERR_INVALID_HANDLE;
                            break;
                        };
                        if (slot.state == .Free or slot.state == .Closing or slot.fd < 0) {
                            result = SA_NETX_ERR_INVALID_HANDLE;
                            break;
                        }
                        if (slot.outbound_inflight) {
                            result = SA_NETX_ERR_IO;
                            break;
                        }
                        self.sendBytes(slot, msg[0..command.msg_len], use_zc, slot.state == .WebSocket) catch |err| switch (err) {
                            error.NoSpaceLeft => {
                                result = SA_NETX_ERR_TRUNCATED;
                                break;
                            },
                            error.WouldBlock => {
                                result = SA_NETX_ERR_IO;
                                break;
                            },
                            else => {
                                result = SA_NETX_ERR_IO;
                                break;
                            },
                        };
                    }
                    if (result == SA_NETX_OK) {
                        _ = self.ring.submit() catch {
                            result = SA_NETX_ERR_IO;
                        };
                    }
                }
            },
            .close => {
                var pool = runtime_state.slot_pool orelse {
                    result = SA_NETX_ERR_INVALID_HANDLE;
                    self.finishCommand(result);
                    return;
                };
                const slot = pool.slotFromId(command.slot_id) orelse {
                    result = SA_NETX_ERR_INVALID_HANDLE;
                    self.finishCommand(result);
                    return;
                };
                if (slot.state == .Free or slot.state == .Closing or slot.fd < 0) {
                    result = SA_NETX_ERR_INVALID_HANDLE;
                } else {
                    slot.state = .Closing;
                    slot.clear();
                }
            },
        }

        self.finishCommand(result);
    }

    fn queueAcceptTicket(self: *Reactor, slot: *ConnectionSlot) bool {
        const ticket = makeTicket(slot, .accept, slot.proto, 0, slot.scratch[slot.message_start..slot.message_start]);
        return self.queueTicket(ticket);
    }

    fn queueSendDoneTicket(self: *Reactor, slot: *ConnectionSlot, flags: u8) bool {
        const ticket = makeTicket(slot, .send_done, slot.proto, flags, slot.scratch[slot.message_start..slot.message_start]);
        return self.queueTicket(ticket);
    }

    fn finishCommand(self: *Reactor, result: i32) void {
        self.command_mutex.lock();
        self.command_result = result;
        self.command_pending = false;
        self.command_cond.broadcast();
        self.command_mutex.unlock();
    }

    fn stopListening(self: *Reactor) void {
        if (self.server) |*server| {
            server.deinit();
            self.server = null;
        }
        self.accept_armed = false;
        self.timeout_armed = false;
    }

    fn beginCommand(self: *Reactor, command: ReactorCommand) i32 {
        if (!self.worker_started) return SA_NETX_ERR_INVALID_HANDLE;
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

    fn queueCloseTicket(self: *Reactor, slot: *ConnectionSlot, flags: u8) bool {
        const ticket = makeTicket(slot, .peer_close, NetxProto_RAW, flags, slot.scratch[slot.message_start..slot.message_start]);
        return self.queueTicket(ticket);
    }

    fn handleAcceptCqe(self: *Reactor, cqe: linux.io_uring_cqe) !void {
        if (cqe.res < 0) {
            self.accept_armed = false;
            self.accept_multishot_supported = false;
            try self.armAccept();
            return;
        }

        const fd = @as(posix.fd_t, @intCast(cqe.res));
        setNonBlocking(fd);
        var state = getState();
        const now_ns = @as(u64, @intCast(std.time.nanoTimestamp()));
        if (state.slot_pool) |*pool| {
            const slot = pool.allocSlot(self.id, fd, now_ns) orelse {
                posix.close(fd);
                return;
            };
            if (!self.queueAcceptTicket(slot)) {
                slot.recv_paused = true;
                return;
            }
            slot.state = .Handshake;
            slot.markActive(now_ns);
            self.armRecv(slot) catch {
                slot.recv_paused = true;
            };
        } else {
            posix.close(fd);
            return;
        }
        if (!self.accept_multishot_supported) {
            self.accept_armed = false;
            try self.armAccept();
        }
    }

    fn handleRecvCqe(self: *Reactor, slot_id: u32, cqe: linux.io_uring_cqe) !void {
        if (runtime_state.slot_pool) |*pool| {
            const slot = pool.slotFromId(slot_id) orelse return;
            slot.recv_multishot_armed = self.recv_multishot_supported;

            if (cqe.res == 0) {
                try self.queuePeerClose(slot, cqe.flags);
                slot.state = .HalfClosed;
                slot.clear();
                return;
            }
            if (cqe.res < 0) {
                try self.queuePeerClose(slot, cqe.flags);
                slot.state = .Closing;
                slot.clear();
                return;
            }

            const received = @as(usize, @intCast(cqe.res));
            slot.markActive(@as(u64, @intCast(std.time.nanoTimestamp())));
            const incoming = if (self.buffer_group) |*group| blk: {
                break :blk group.get_cqe(cqe) catch return;
            } else blk: {
                break :blk slot.scratch[0..received];
            };

            if (slot.scratch_used >= slot.scratch.len) {
                slot.recv_paused = true;
                return;
            }
            const copy_len = @min(slot.scratch.len - slot.scratch_used, incoming.len);
            const write_start = slot.scratch_used;
            if (copy_len != 0) {
                std.mem.copyForwards(u8, slot.scratch[write_start .. write_start + copy_len], incoming[0..copy_len]);
            }
            slot.scratch_used += copy_len;
            if (copy_len < incoming.len) slot.flags |= TicketFlag.truncated;

            try self.processSlotBytes(slot, write_start, slot.scratch_used, cqe.flags);

            if (!self.recv_multishot_supported and !slot.recv_paused and slot.state != .Free and slot.state != .Closing) {
                try self.armRecv(slot);
            }
            if (self.buffer_group) |*group| {
                group.put_cqe(cqe) catch {};
            }
        } else return;
    }

    fn handleSendCqe(self: *Reactor, slot_id: u32, cqe: linux.io_uring_cqe) !void {
        if (runtime_state.slot_pool) |*pool| {
            const slot = pool.slotFromId(slot_id) orelse return;
            if (cqe.flags & linux.IORING_CQE_F_NOTIF != 0) {
                slot.outbound_inflight = false;
                slot.outbound_mode_zc = false;
                _ = self.queueSendDoneTicket(slot, TicketFlag.zc);
                return;
            }
            if (!slot.outbound_mode_zc) {
                slot.outbound_inflight = false;
                slot.outbound_len = 0;
                _ = self.queueSendDoneTicket(slot, 0);
            }
        } else return;
    }

    fn queuePeerClose(self: *Reactor, slot: *ConnectionSlot, flags: u32) !void {
        const payload = slot.scratch[slot.message_start..slot.scratch_used];
        _ = payload;
        const ticket = makeTicket(slot, .peer_close, NetxProto_RAW, TicketFlag.eof, slot.scratch[slot.message_start..slot.message_start]);
        if (!self.queueTicket(ticket)) {
            slot.recv_paused = true;
        }
        _ = flags;
    }

    fn processSlotBytes(self: *Reactor, slot: *ConnectionSlot, start: usize, end: usize, cqe_flags: u32) !void {
        _ = cqe_flags;
        if (slot.state == .Closing or slot.state == .Free) return;
        if (start >= end) return;
        slot.markActive(@as(u64, @intCast(std.time.nanoTimestamp())));

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

    fn queueTicket(self: *Reactor, ticket: Ticket) bool {
        self.ticket_mutex.lock();
        defer self.ticket_mutex.unlock();
        const pushed = self.tickets.push(ticket);
        if (pushed) {
            self.ticket_cond.broadcast();
        }
        return pushed;
    }

    fn ticketPop(self: *Reactor) ?Ticket {
        self.ticket_mutex.lock();
        defer self.ticket_mutex.unlock();
        return self.ticketPopLocked();
    }

    fn ticketPopLocked(self: *Reactor) ?Ticket {
        return self.tickets.pop();
    }

    fn ticketIsFull(self: *Reactor) bool {
        self.ticket_mutex.lock();
        defer self.ticket_mutex.unlock();
        return self.tickets.isFull();
    }

    fn queueWebSocketUpgrade(self: *Reactor, slot: *ConnectionSlot, accept_value: []const u8) !void {
        var response_buf: [256]u8 = undefined;
        const response = try std.fmt.bufPrint(response_buf[0..], "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept_value});
        try self.sendBytes(slot, response, false, false);
    }

    fn sendBytes(self: *Reactor, slot: *ConnectionSlot, bytes: []const u8, use_zc: bool, websocket_frame: bool) !void {
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

    fn pump(self: *Reactor, wait_one: bool) !void {
        try self.armTimeout();
        try self.armWakeup();
        _ = try self.ring.submit();
        if (wait_one) {
            try self.drain(true);
        } else {
            try self.drain(false);
        }
    }

    fn serviceDeferredWork(self: *Reactor) void {
        self.command_mutex.lock();
        const should_resume = self.resume_requested;
        self.resume_requested = false;
        const has_command = self.command_pending;
        self.command_mutex.unlock();
        if (has_command) self.processPendingCommand();
        if (should_resume) self.resumePausedSlots();
    }
};

fn setThreadAffinity(core_id: usize) void {
    if (builtin.os.tag != .linux) return;
    var set: linux.cpu_set_t = .{0} ** (linux.CPU_SETSIZE / @sizeOf(usize));
    const idx = core_id / (@sizeOf(usize) * 8);
    const bit = core_id % (@sizeOf(usize) * 8);
    if (idx < set.len) {
        set[idx] |= (@as(usize, 1) << @intCast(bit));
        linux.sched_setaffinity(0, &set) catch {};
    }
}

fn setNonBlocking(fd: posix.fd_t) void {
    const flags = posix.fcntl(fd, posix.F.GETFL, 0) catch return;
    _ = posix.fcntl(fd, posix.F.SETFL, flags | (@as(usize, 1) << @bitOffsetOf(posix.O, "NONBLOCK"))) catch {};
}

fn reactorWorkerMain(reactor: *Reactor) void {
    setThreadAffinity(reactor.id);
    const state = &getState().worker_state;
    state.mutex.lock();
    state.active_workers += 1;
    state.running = true;
    state.cond.broadcast();
    state.mutex.unlock();

    defer {
        state.mutex.lock();
        if (state.active_workers > 0) state.active_workers -= 1;
        if (state.active_workers == 0) {
            state.running = false;
            state.cond.broadcast();
        }
        state.mutex.unlock();
    }

    while (true) {
        state.mutex.lock();
        const stop = state.stop;
        state.mutex.unlock();
        if (stop) break;
        reactor.pump(true) catch {};
        reactor.serviceDeferredWork();
    }
}

const PackedUserData = packed struct {
    tag: ReactorUserTag,
    slot_id: u32,
    reactor_id: u24 = 0,
};

fn packUserData(tag: ReactorUserTag, reactor_id: u32, slot_id: u32) u64 {
    return @bitCast(PackedUserData{
        .tag = tag,
        .slot_id = slot_id,
        .reactor_id = @as(u24, @intCast(reactor_id)),
    });
}

fn decodeUserData(user_data: u64) PackedUserData {
    return @bitCast(user_data);
}

const RuntimeState = struct {
    initialized: bool = false,
    slot_pool: ?SlotPool = null,
    reactors: []Reactor = &.{},
    reactor_count: usize = 0,
    listened: bool = false,
    listen_address: ?net.Address = null,
    ticket_capacity: usize = 0,
    worker_state: WorkerState = .{},
};

var runtime_state: RuntimeState = .{};

fn getState() *RuntimeState {
    return &runtime_state;
}

fn ceilPow2(value: usize) usize {
    if (value <= 1) return 1;
    var v = value - 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    if (@sizeOf(usize) >= 8) v |= v >> 32;
    return v + 1;
}

fn makeTicket(slot: *ConnectionSlot, op: TicketOp, proto: u8, flags: u8, payload: []const u8) Ticket {
    return .{
        .slot_id = slot.slot_id,
        .op_code = @intFromEnum(op),
        .proto = proto,
        .flags = flags,
        .payload = @as(*u8, @ptrCast(@constCast(payload.ptr))),
        .payload_len = @as(u32, @intCast(payload.len)),
        .pad = 0,
    };
}

fn frameFlags(frame: WsFrame) u8 {
    var flags: u8 = 0;
    if (frame.masked) flags |= TicketFlag.masked;
    if (!frame.fin) flags |= 1 << 5;
    return flags;
}

fn trimAscii(bytes: []const u8) []const u8 {
    return std.mem.trim(u8, bytes, " \t");
}

fn readVector16(bytes: []const u8) @Vector(16, u8) {
    var tmp: [16]u8 = undefined;
    @memcpy(tmp[0..], bytes[0..16]);
    return tmp;
}

fn readVector32(bytes: []const u8) @Vector(32, u8) {
    var tmp: [32]u8 = undefined;
    @memcpy(tmp[0..], bytes[0..32]);
    return tmp;
}

fn writeVector16(bytes: []u8, vec: @Vector(16, u8)) void {
    const arr: [16]u8 = vec;
    @memcpy(bytes[0..16], arr[0..]);
}

fn writeVector32(bytes: []u8, vec: @Vector(32, u8)) void {
    const arr: [32]u8 = vec;
    @memcpy(bytes[0..32], arr[0..]);
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ac, bc| {
        if (std.ascii.toLower(ac) != std.ascii.toLower(bc)) return false;
    }
    return true;
}

fn containsTokenIgnoreCase(value: []const u8, needle: []const u8) bool {
    var it = std.mem.splitScalar(u8, value, ',');
    while (it.next()) |token| {
        const trimmed = trimAscii(token);
        if (eqlIgnoreCase(trimmed, needle)) return true;
    }
    return false;
}

fn parsePositiveInt(text: []const u8) !usize {
    return std.fmt.parseInt(usize, trimAscii(text), 10);
}

fn isHttpMethodPrefix(bytes: []const u8, prefix: []const u8) bool {
    if (bytes.len < prefix.len) {
        return std.mem.eql(u8, bytes, prefix[0..bytes.len]);
    }
    if (!std.mem.startsWith(u8, bytes, prefix)) return false;
    return bytes.len == prefix.len or bytes[prefix.len] == ' ';
}

fn fieldSpan(start: usize, end: usize) FieldSpan {
    return .{
        .offset = @as(u32, @intCast(start)),
        .len = @as(u32, @intCast(end - start)),
    };
}

fn fieldSlice(bytes: []const u8, span: FieldSpan) []const u8 {
    const start = @as(usize, @intCast(span.offset));
    const len = @as(usize, @intCast(span.len));
    return bytes[start .. start + len];
}

pub fn parseHttpRequest(bytes: []const u8) error{Incomplete, Invalid}!HttpRequest {
    const header_end = findHttpHeaderEndVector(bytes) orelse return error.Incomplete;
    const header_block = bytes[0..header_end];
    const request_line_end = findCrlfVector(header_block, 0) orelse return error.Invalid;
    const request_line = header_block[0..request_line_end];
    const method_end = std.mem.indexOfScalar(u8, request_line, ' ') orelse return error.Invalid;
    if (method_end == 0) return error.Invalid;
    const path_space_rel = std.mem.indexOfScalar(u8, request_line[method_end + 1 ..], ' ') orelse return error.Invalid;
    if (path_space_rel == 0) return error.Invalid;
    const path_end = method_end + 1 + path_space_rel;
    if (path_end + 1 >= request_line.len) return error.Invalid;
    const method_start = 0;
    const path_start = method_end + 1;
    const version_start = path_end + 1;
    const method_len = method_end - method_start;
    const path_len = path_end - path_start;
    const version_len = request_line.len - version_start;
    const version = request_line[version_start..];
    if (!eqlIgnoreCase(version, "HTTP/1.1")) return error.Invalid;

    var content_length: usize = 0;
    var websocket_key: ?FieldSpan = null;
    var websocket_upgrade = false;
    var line_start: usize = request_line_end + 2;

    while (line_start < header_end) {
        const line_end = findCrlfVector(header_block, line_start) orelse header_end;
        const line = header_block[line_start..line_end];
        const colon = findColonVector(line) orelse return error.Invalid;
        const name = trimAscii(line[0..colon]);
        const value_text = line[colon + 1 ..];
        const value = trimAscii(value_text);
        const value_start = line_start + colon + 1 + (value_text.len - value.len);
        if (eqlIgnoreCase(name, "Content-Length")) {
            content_length = parsePositiveInt(value) catch return error.Invalid;
        } else if (eqlIgnoreCase(name, "Connection")) {
            if (containsTokenIgnoreCase(value, "Upgrade")) websocket_upgrade = true;
        } else if (eqlIgnoreCase(name, "Upgrade")) {
            if (eqlIgnoreCase(value, "websocket")) websocket_upgrade = true;
        } else if (eqlIgnoreCase(name, "Sec-WebSocket-Key")) {
            websocket_key = fieldSpan(value_start, value_start + value.len);
        } else if (eqlIgnoreCase(name, "Sec-WebSocket-Version")) {
            if (!eqlIgnoreCase(value, "13")) return error.Invalid;
        }
        line_start = line_end + 2;
    }

    const request_end = header_end + 4 + content_length;
    if (bytes.len < request_end) return error.Incomplete;
    return .{
        .method = fieldSpan(method_start, method_start + method_len),
        .path = fieldSpan(path_start, path_start + path_len),
        .version = fieldSpan(version_start, version_start + version_len),
        .content_length = content_length,
        .websocket_key = websocket_key,
        .websocket_upgrade = websocket_upgrade,
        .request_end = request_end,
    };
}

pub fn looksLikeHttpPrefix(bytes: []const u8) bool {
    const methods = [_][]const u8{ "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "CONNECT", "TRACE", "PRI" };
    for (methods) |method| {
        if (isHttpMethodPrefix(bytes, method)) return true;
    }
    return false;
}

pub fn maybeHttpPrefixVector(bytes: []const u8) bool {
    if (bytes.len < 3) return true;
    const prefixes = [_][]const u8{
        "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "CONNECT", "TRACE", "PRI",
    };
    if (bytes.len >= 32) {
        inline for (prefixes) |prefix| {
            if (prefixMatchesVector32(bytes, prefix)) return true;
        }
    } else {
        for (prefixes) |prefix| {
            if (isHttpMethodPrefix(bytes, prefix)) return true;
        }
    }
    return looksLikeHttpPrefix(bytes);
}

fn prefixMatchesVector32(bytes: []const u8, prefix: []const u8) bool {
    if (prefix.len == 0 or prefix.len > 32 or bytes.len < prefix.len) return false;
    const chunk = readVector32(bytes);
    const expected = prefixPaddedVector32(prefix);
    const diff = chunk ^ expected;
    const mask = prefixMaskVector32(prefix.len);
    const masked = diff & mask;
    const zero: @Vector(32, u8) = @splat(@as(u8, 0));
    if (@reduce(.Or, masked != zero)) return false;
    return isHttpMethodPrefix(bytes, prefix);
}

fn prefixPaddedVector32(prefix: []const u8) @Vector(32, u8) {
    var padded: [32]u8 = [_]u8{0} ** 32;
    @memcpy(padded[0..prefix.len], prefix);
    return padded;
}

fn prefixMaskVector32(prefix_len: usize) @Vector(32, u8) {
    var mask: [32]u8 = [_]u8{0} ** 32;
    const len = @min(prefix_len, mask.len);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        mask[i] = 0xff;
    }
    return mask;
}

fn writeWebSocketFrame(slot: *ConnectionSlot, payload: []const u8) ![]u8 {
    const header_len: usize = if (payload.len < 126) 2 else if (payload.len <= 0xffff) 4 else 10;
    const total_len = header_len + payload.len;
    if (total_len > slot.outbound_scratch.len) return error.NoSpaceLeft;
    var idx: usize = 0;
    slot.outbound_scratch[idx] = 0x82;
    idx += 1;
    if (payload.len < 126) {
        slot.outbound_scratch[idx] = @as(u8, @intCast(payload.len));
        idx += 1;
    } else if (payload.len <= 0xffff) {
        slot.outbound_scratch[idx] = 126;
        idx += 1;
        const len16: u16 = @as(u16, @intCast(payload.len));
        slot.outbound_scratch[idx] = @as(u8, @intCast(len16 >> 8));
        slot.outbound_scratch[idx + 1] = @as(u8, @intCast(len16 & 0xff));
        idx += 2;
    } else {
        slot.outbound_scratch[idx] = 127;
        idx += 1;
        const len64: u64 = @as(u64, @intCast(payload.len));
        const shifts = [_]u6{ 56, 48, 40, 32, 24, 16, 8, 0 };
        for (shifts, 0..) |shift, b| {
            slot.outbound_scratch[idx + b] = @as(u8, @intCast((len64 >> shift) & 0xff));
        }
        idx += 8;
    }
    @memcpy(slot.outbound_scratch[idx .. idx + payload.len], payload);
    return slot.outbound_scratch[0..total_len];
}

fn findHttpHeaderEndVector(bytes: []const u8) ?usize {
    if (bytes.len < 4) return null;
    if (bytes.len < 32) {
        return std.mem.indexOf(u8, bytes, "\r\n\r\n");
    }
    const cr: @Vector(32, u8) = @splat(@as(u8, '\r'));
    var i: usize = 0;
    while (i + 32 <= bytes.len) : (i += 32) {
        const chunk = readVector32(bytes[i..]);
        if (!@reduce(.Or, chunk == cr)) continue;
        var j: usize = 0;
        while (j < 32 and i + j + 4 <= bytes.len) : (j += 1) {
            if (bytes[i + j] == '\r' and bytes[i + j + 1] == '\n' and bytes[i + j + 2] == '\r' and bytes[i + j + 3] == '\n') {
                return i + j;
            }
        }
    }
    while (i + 4 <= bytes.len) : (i += 1) {
        if (bytes[i] == '\r' and bytes[i + 1] == '\n' and bytes[i + 2] == '\r' and bytes[i + 3] == '\n') return i;
    }
    return null;
}

fn findCrlfVector(bytes: []const u8, start: usize) ?usize {
    if (start + 2 > bytes.len) return null;
    if (bytes.len - start < 32) {
        return if (std.mem.indexOf(u8, bytes[start..], "\r\n")) |idx| start + idx else null;
    }
    const cr: @Vector(32, u8) = @splat(@as(u8, '\r'));
    var i: usize = start;
    while (i + 32 <= bytes.len) : (i += 32) {
        const chunk = readVector32(bytes[i..]);
        if (!@reduce(.Or, chunk == cr)) continue;
        var j: usize = 0;
        while (j < 32 and i + j + 1 < bytes.len) : (j += 1) {
            if (bytes[i + j] == '\r' and bytes[i + j + 1] == '\n') return i + j;
        }
    }
    while (i + 1 < bytes.len) : (i += 1) {
        if (bytes[i] == '\r' and bytes[i + 1] == '\n') return i;
    }
    return null;
}

fn findColonVector(bytes: []const u8) ?usize {
    if (bytes.len == 0) return null;
    if (bytes.len < 32) {
        return std.mem.indexOfScalar(u8, bytes, ':');
    }
    const colon: @Vector(32, u8) = @splat(@as(u8, ':'));
    var i: usize = 0;
    while (i + 32 <= bytes.len) : (i += 32) {
        const chunk = readVector32(bytes[i..]);
        if (!@reduce(.Or, chunk == colon)) continue;
        var j: usize = 0;
        while (j < 32) : (j += 1) {
            if (bytes[i + j] == ':') return i + j;
        }
    }
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] == ':') return i;
    }
    return null;
}

pub fn parseWsFrame(bytes: []const u8) error{Incomplete, Invalid}!WsFrame {
    if (bytes.len < 2) return error.Incomplete;
    const b0 = bytes[0];
    const b1 = bytes[1];
    const fin = (b0 & 0x80) != 0;
    const opcode = b0 & 0x0f;
    const masked = (b1 & 0x80) != 0;
    var payload_len: usize = b1 & 0x7f;
    var idx: usize = 2;
    if (payload_len == 126) {
        if (bytes.len < 4) return error.Incomplete;
        payload_len = std.mem.readInt(u16, bytes[2..4], .big);
        idx = 4;
    } else if (payload_len == 127) {
        if (bytes.len < 10) return error.Incomplete;
        const raw = std.mem.readInt(u64, bytes[2..10], .big);
        payload_len = std.math.cast(usize, raw) orelse return error.Invalid;
        idx = 10;
    }

    var mask: [4]u8 = .{ 0, 0, 0, 0 };
    if (masked) {
        if (bytes.len < idx + 4) return error.Incomplete;
        @memcpy(mask[0..], bytes[idx .. idx + 4]);
        idx += 4;
    }

    if (bytes.len < idx + payload_len) return error.Incomplete;
    return .{
        .fin = fin,
        .opcode = opcode,
        .masked = masked,
        .payload_start = idx,
        .payload_len = payload_len,
        .frame_len = idx + payload_len,
        .mask = mask,
    };
}

fn unmaskFrame(payload: []u8, mask: [4]u8) void {
    if (payload.len == 0) return;
    const vec_len = 16;
    if (payload.len >= 32) {
        const mask16: @Vector(16, u8) = .{
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
        };
        const mask32: @Vector(32, u8) = .{
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
        };
        var offset32: usize = 0;
        while (offset32 + 32 <= payload.len) : (offset32 += 32) {
            const block = readVector32(payload[offset32..]);
            const decoded = block ^ mask32;
            writeVector32(payload[offset32..], decoded);
        }
        while (offset32 + 16 <= payload.len) : (offset32 += 16) {
            const block = readVector16(payload[offset32..]);
            const decoded = block ^ mask16;
            writeVector16(payload[offset32..], decoded);
        }
        while (offset32 < payload.len) : (offset32 += 1) {
            payload[offset32] ^= mask[offset32 & 3];
        }
        return;
    }
    var i: usize = 0;
    while (i + vec_len <= payload.len) : (i += vec_len) {
        const block = readVector16(payload[i..]);
        const key: @Vector(16, u8) = .{
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
        };
        const decoded = block ^ key;
        writeVector16(payload[i..], decoded);
    }
    while (i < payload.len) : (i += 1) {
        payload[i] ^= mask[i & 3];
    }
}

pub fn websocketAccept(key: []const u8) ![28]u8 {
    var sha1 = std.crypto.hash.Sha1.init(.{});
    sha1.update(key);
    sha1.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    var digest: [20]u8 = undefined;
    sha1.final(&digest);

    var out: [28]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(out[0..], digest[0..]);
    return out;
}

fn resumeSlot(receptor: *Reactor, slot: *ConnectionSlot) !void {
    if (slot.state == .Free or slot.state == .Closing or slot.fd < 0) return;
    if (slot.recv_paused) {
        slot.recv_paused = false;
    }
    if (!receptor.recv_multishot_supported and !slot.recv_multishot_armed) {
        try receptor.armRecv(slot);
    }
}

pub fn sa_netx_init(slot_capacity: u64, reactor_count: u32) i32 {
    if (builtin.os.tag != .linux) return SA_NETX_ERR_UNSUPPORTED;
    if (slot_capacity == 0 or reactor_count == 0) return SA_NETX_ERR_INVALID_ARGUMENT;
    if (runtime_state.initialized) return SA_NETX_ERR_INVALID_ARGUMENT;

    const slot_capacity_usize = @as(usize, @intCast(slot_capacity));
    const reactor_count_usize = @as(usize, @intCast(reactor_count));
    const ticket_capacity = slot_capacity_usize * 4;

    const pool = SlotPool.init(slot_capacity_usize) catch return SA_NETX_ERR_NO_MEMORY;
    var reactors = std.heap.page_allocator.alloc(Reactor, reactor_count_usize) catch {
        var pool_owned = pool;
        pool_owned.deinit();
        return SA_NETX_ERR_NO_MEMORY;
    };

    var i: usize = 0;
    while (i < reactors.len) : (i += 1) {
        reactors[i] = Reactor.init(@as(u32, @intCast(i)), ticket_capacity) catch {
            var j: usize = 0;
            while (j < i) : (j += 1) reactors[j].deinit();
            std.heap.page_allocator.free(reactors);
            var pool_owned = pool;
            pool_owned.deinit();
            return SA_NETX_ERR_IO;
        };
    }

    for (reactors) |*reactor| {
        reactor.startWorker() catch {
            var j: usize = 0;
            while (j < reactors.len) : (j += 1) reactors[j].deinit();
            std.heap.page_allocator.free(reactors);
            var pool_owned = pool;
            pool_owned.deinit();
            return SA_NETX_ERR_IO;
        };
    }

    runtime_state = .{
        .initialized = true,
        .slot_pool = pool,
        .reactors = reactors,
        .reactor_count = reactors.len,
        .listened = false,
        .listen_address = null,
        .ticket_capacity = ticket_capacity,
    };
    return SA_NETX_OK;
}

pub fn sa_netx_listen(host_ptr: ?[*]const u8, host_len: u64, port: u16) i32 {
    if (!runtime_state.initialized) return SA_NETX_ERR_INVALID_HANDLE;
    if (runtime_state.listened) return SA_NETX_ERR_INVALID_ARGUMENT;
    const host = if (host_len == 0) "0.0.0.0" else blk: {
        const ptr = host_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
        break :blk ptr[0..@as(usize, @intCast(host_len))];
    };
    const address = net.Address.resolveIp(host, port) catch return SA_NETX_ERR_NET;
    if (runtime_state.reactors.len == 0) return SA_NETX_ERR_INVALID_HANDLE;

    const first_result = runtime_state.reactors[0].beginCommand(.{
        .kind = .listen,
        .slot_id = 0,
        .address = address,
    });
    if (first_result != SA_NETX_OK) return first_result;

    const listen_address = runtime_state.reactors[0].server orelse return SA_NETX_ERR_IO;
    runtime_state.listen_address = listen_address.listen_address;

    var idx: usize = 1;
    while (idx < runtime_state.reactors.len) : (idx += 1) {
        const result = runtime_state.reactors[idx].beginCommand(.{
            .kind = .listen,
            .slot_id = 0,
            .address = runtime_state.listen_address.?,
        });
        if (result != SA_NETX_OK) {
            var rollback_idx: usize = 0;
            while (rollback_idx < idx) : (rollback_idx += 1) {
                _ = runtime_state.reactors[rollback_idx].beginCommand(.{
                    .kind = .listen,
                    .slot_id = 0,
                    .address = null,
                });
            }
            runtime_state.listen_address = null;
            return result;
        }
    }
    runtime_state.listened = true;
    return SA_NETX_OK;
}

pub fn sa_netx_recv_ticket(reactor_id: u32, out_ticket: ?*Ticket) i32 {
    const ticket_ptr = out_ticket orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const reactor = getReactor(reactor_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    reactor.ticket_mutex.lock();
    defer reactor.ticket_mutex.unlock();
    while (reactor.tickets.isEmpty()) {
        if (runtime_state.worker_state.stop) return SA_NETX_ERR_NOT_FOUND;
        reactor.ticket_cond.wait(&reactor.ticket_mutex);
    }
    const ticket = reactor.tickets.pop().?;
    ticket_ptr.* = ticket;
    if (runtime_state.slot_pool) |*pool| {
        if (pool.slotFromId(ticket.slot_id)) |slot| {
            resumeSlot(reactor, slot) catch {};
        }
    }
    reactor.requestResume();
    return SA_NETX_OK;
}

pub fn sa_netx_push_outbound(reactor_id: u32, slot_id: u32, msg_ptr: ?[*]const u8, len: u32) i32 {
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

pub fn sa_netx_broadcast(reactor_id: u32, slot_ids_ptr: ?[*]const u32, n: u32, msg_ptr: ?[*]const u8, len: u32) i32 {
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

pub fn sa_netx_close_slot(slot_id: u32) i32 {
    if (!runtime_state.initialized) return SA_NETX_ERR_INVALID_HANDLE;
    const pool = runtime_state.slot_pool orelse return SA_NETX_ERR_INVALID_HANDLE;
    const slot = pool.slotFromId(slot_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    const reactor = getReactor(slot.reactor_id) orelse return SA_NETX_ERR_INVALID_HANDLE;
    return reactor.beginCommand(.{
        .kind = .close,
        .slot_id = slot_id,
    });
}

pub fn sa_netx_shutdown() i32 {
    if (!runtime_state.initialized) return SA_NETX_OK;
    runtime_state.worker_state.mutex.lock();
    runtime_state.worker_state.stop = true;
    runtime_state.worker_state.cond.broadcast();
    runtime_state.worker_state.mutex.unlock();
    if (runtime_state.reactors.len != 0) {
        for (runtime_state.reactors) |*reactor| {
            reactor.ticket_cond.broadcast();
            reactor.deinit();
        }
        std.heap.page_allocator.free(runtime_state.reactors);
    }
    if (runtime_state.slot_pool) |*pool| {
        pool.deinit();
    }
    runtime_state = .{};
    return SA_NETX_OK;
}

fn getReactor(reactor_id: u32) ?*Reactor {
    if (!runtime_state.initialized) return null;
    const idx = @as(usize, @intCast(reactor_id));
    if (idx >= runtime_state.reactors.len) return null;
    return &runtime_state.reactors[idx];
}

const LoopbackClient = struct {
    address: net.Address,
    request: []const u8,
    received: [256]u8 = undefined,
    received_len: usize = 0,
};

const WsLoopbackClient = struct {
    address: net.Address,
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

const TicketCollector = struct {
    reactor_id: u32,
    tickets: []Ticket,
    mutex: Mutex = .{},
    cond: Condition = .{},
    count: usize = 0,
    result: i32 = SA_NETX_OK,
};

fn ticketPayload(ticket: Ticket) []const u8 {
    return @as([*]const u8, @ptrCast(ticket.payload))[0..@as(usize, @intCast(ticket.payload_len))];
}

fn loopbackClientMain(client: *LoopbackClient) void {
    const stream = net.tcpConnectToAddress(client.address) catch return;
    defer stream.close();

    _ = stream.writeAll(client.request) catch return;

    var total: usize = 0;
    var buf: [64]u8 = undefined;
    while (total < client.received.len) {
        const read_len = stream.read(buf[0..]) catch return;
        if (read_len == 0) break;
        const copy_len = @min(client.received.len - total, read_len);
        if (copy_len != 0) {
            @memcpy(client.received[total .. total + copy_len], buf[0..copy_len]);
            total += copy_len;
        }
    }
    client.received_len = total;
}

fn wsLoopbackClientMain(client: *WsLoopbackClient) void {
    const stream = net.tcpConnectToAddress(client.address) catch return;
    defer stream.close();

    _ = stream.writeAll(client.request) catch return;

    var frame_start: usize = 0;
    var upgrade_total: usize = 0;
    while (upgrade_total < client.upgrade_response.len) {
        const read_len = stream.read(client.upgrade_response[upgrade_total..]) catch return;
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
        const read_len = stream.read(client.frame_buf[0..]) catch return;
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

fn collectTicketsMain(state: *TicketCollector) void {
    var index: usize = 0;
    while (index < state.tickets.len) : (index += 1) {
        var ticket: Ticket = undefined;
        const result = sa_netx_recv_ticket(state.reactor_id, &ticket);
        state.mutex.lock();
        if (result != SA_NETX_OK) {
            state.result = result;
            state.cond.broadcast();
            state.mutex.unlock();
            return;
        }
        state.tickets[index] = ticket;
        state.count = index + 1;
        state.cond.broadcast();
        state.mutex.unlock();
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

test "websocket accept matches the RFC example" {
    const accept = try websocketAccept("dGhlIHNhbXBsZSBub25jZQ==");
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &accept);
}

test "http parser recognizes websocket upgrade" {
    const request =
        "GET /chat HTTP/1.1\r\n"
        ++ "Host: example.com\r\n"
        ++ "Upgrade: websocket\r\n"
        ++ "Connection: Upgrade\r\n"
        ++ "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        ++ "Sec-WebSocket-Version: 13\r\n"
        ++ "\r\n";
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
        "GET /chat HTTP/1.1\r\n"
        ++ "Host: example.com\r\n"
        ++ "Upgrade: websocket\r\n"
        ++ "Connection: Upgrade\r\n"
        ++ "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        ++ "Sec-WebSocket-Version: 13\r\n"
        ++ "\r\n";
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

    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_init(8, 1));
    defer _ = sa_netx_shutdown();

    const listen_host = "127.0.0.1";
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_listen(listen_host.ptr, listen_host.len, 0));
    const listen_address = runtime_state.listen_address orelse return error.TestUnexpectedResult;

    var collector_state = TicketCollector{
        .reactor_id = 0,
        .tickets = try std.testing.allocator.alloc(Ticket, 4),
    };
    defer std.testing.allocator.free(collector_state.tickets);

    var ws_client = WsLoopbackClient{
        .address = listen_address,
        .request =
            "GET /ws HTTP/1.1\r\n"
            ++ "Host: example.test\r\n"
            ++ "Upgrade: websocket\r\n"
            ++ "Connection: Upgrade\r\n"
            ++ "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
            ++ "Sec-WebSocket-Version: 13\r\n"
            ++ "\r\n",
        .expected_payload = "WS_OK\n",
        .expected_frame_len = 2 + "WS_OK\n".len,
    };

    const collector_thread = try Thread.spawn(.{}, collectTicketsMain, .{&collector_state});
    const ws_thread = try Thread.spawn(.{}, wsLoopbackClientMain, .{&ws_client});

    collector_state.mutex.lock();
    const deadline = @as(u64, @intCast(std.time.nanoTimestamp())) + 10 * std.time.ns_per_s;
    while (collector_state.count < 3 and collector_state.result == SA_NETX_OK) {
        const now = @as(u64, @intCast(std.time.nanoTimestamp()));
        if (now >= deadline) break;
        const remaining = deadline - now;
        collector_state.cond.timedWait(&collector_state.mutex, remaining) catch {};
    }
    const collected = collector_state.count;
    const result = collector_state.result;
    collector_state.mutex.unlock();
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

    collector_state.mutex.lock();
    const send_deadline = @as(u64, @intCast(std.time.nanoTimestamp())) + 10 * std.time.ns_per_s;
    while (collector_state.count < 4 and collector_state.result == SA_NETX_OK) {
        const now = @as(u64, @intCast(std.time.nanoTimestamp()));
        if (now >= send_deadline) break;
        const remaining = send_deadline - now;
        collector_state.cond.timedWait(&collector_state.mutex, remaining) catch {};
    }
    const total_collected = collector_state.count;
    const total_result = collector_state.result;
    collector_state.mutex.unlock();
    if (total_collected != 4 or total_result != SA_NETX_OK) return error.TestUnexpectedResult;

    _ = sa_netx_close_slot(ws_slot);
    _ = sa_netx_shutdown();
    collector_thread.join();
    ws_thread.join();

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
        0x37, 0xfa, 0x21, 0x3d,
        'f' ^ 0x37, 'o' ^ 0xfa, 'o' ^ 0x21, '!' ^ 0x3d, '?' ^ 0x37,
    };
    const parsed = try parseWsFrame(frame[0..]);
    try std.testing.expectEqual(@as(u8, 1), parsed.opcode);
    try std.testing.expect(parsed.masked);
    unmaskFrame(frame[parsed.payload_start .. parsed.payload_start + parsed.payload_len], parsed.mask);
    try std.testing.expectEqualStrings("foo!?", frame[parsed.payload_start .. parsed.payload_start + parsed.payload_len]);
}

test "init and shutdown round-trip on linux" {
    if (builtin.os.tag != .linux) return;
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_init(8, 1));
    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_shutdown());
}

test "listen accept recv_ticket and outbound commands work end to end" {
    if (builtin.os.tag != .linux) return;

    try std.testing.expectEqual(@as(i32, SA_NETX_OK), sa_netx_init(16, 1));
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
        .request =
            "GET /one HTTP/1.1\r\n"
            ++ "Host: example.test\r\n"
            ++ "Connection: keep-alive\r\n"
            ++ "\r\n",
    };
    var client2 = LoopbackClient{
        .address = listen_address,
        .request =
            "GET /two HTTP/1.1\r\n"
            ++ "Host: example.test\r\n"
            ++ "Connection: keep-alive\r\n"
            ++ "\r\n",
    };

    const collector_thread = try Thread.spawn(.{}, collectTicketsMain, .{&collector_state});
    const client1_thread = try Thread.spawn(.{}, loopbackClientMain, .{&client1});
    const client2_thread = try Thread.spawn(.{}, loopbackClientMain, .{&client2});

    collector_state.mutex.lock();
    const first_deadline = @as(u64, @intCast(std.time.nanoTimestamp())) + 10 * std.time.ns_per_s;
    while (collector_state.count < 4 and collector_state.result == SA_NETX_OK) {
        const now = @as(u64, @intCast(std.time.nanoTimestamp()));
        if (now >= first_deadline) break;
        const remaining = first_deadline - now;
        collector_state.cond.timedWait(&collector_state.mutex, remaining) catch {};
    }
    const first_collected = collector_state.count;
    const collection_result = collector_state.result;
    collector_state.mutex.unlock();

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

    collector_state.mutex.lock();
    const second_deadline = @as(u64, @intCast(std.time.nanoTimestamp())) + 10 * std.time.ns_per_s;
    while (collector_state.count < 7 and collector_state.result == SA_NETX_OK) {
        const now = @as(u64, @intCast(std.time.nanoTimestamp()));
        if (now >= second_deadline) break;
        const remaining = second_deadline - now;
        collector_state.cond.timedWait(&collector_state.mutex, remaining) catch {};
    }
    const total_collected = collector_state.count;
    const total_result = collector_state.result;
    collector_state.mutex.unlock();

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
