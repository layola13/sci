const std = @import("std");
const builtin = @import("builtin");
const sa_std = @import("../sa_std.zig");
const net_primitives = @import("sa_net_primitives");
const sio = @import("sio");
const ceilPow2 = @import("u03.zig").ceilPow2;

pub const net = std.Io.net;

pub const posix = std.posix;

pub const linux = std.os.linux;

pub const Thread = std.Thread;

pub const Mutex = std.Io.Mutex;

pub const Condition = std.Io.Condition;

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

pub const TicketOp = enum(u16) {
    accept = 1,
    http_request = 2,
    websocket_upgrade = 3,
    ws_frame = 4,
    raw_bytes = 5,
    peer_close = 6,
    send_done = 7,
    err = 8,
};

pub const TicketFlag = struct {
    pub const truncated: u8 = 1 << 0;
    pub const upgrade: u8 = 1 << 1;
    pub const eof: u8 = 1 << 2;
    pub const masked: u8 = 1 << 3;
    pub const zc: u8 = 1 << 4;
};

pub const HANDSHAKE_TIMEOUT_NS: u64 = 5 * std.time.ns_per_s;

pub const IDLE_TIMEOUT_NS: u64 = 60 * std.time.ns_per_s;

pub const REACTOR_TIMEOUT_NS: u64 = 250 * std.time.ns_per_ms;

pub const ticket_payload_capacity: usize = 4096;

pub const ReactorUserTag = enum(u8) {
    none,
    accept,
    recv,
    send,
    timeout,
    wakeup,
};

pub const WorkerState = struct {
    mutex: Mutex = .init,
    cond: Condition = .init,
    running: bool = false,
    stop: bool = false,
    active_workers: usize = 0,
};

pub const ReactorCommandKind = enum(u8) {
    listen,
    send,
    broadcast,
    close,
};

pub const ReactorCommand = struct {
    kind: ReactorCommandKind,
    slot_id: u32,
    use_zc: bool = false,
    msg_ptr: ?[*]const u8 = null,
    msg_len: usize = 0,
    slot_ids_ptr: ?[*]const u32 = null,
    slot_ids_len: usize = 0,
    address: ?net.IpAddress = null,
};

pub const ReactorCommandQueue = struct {
    storage: []ReactorCommand,
    head: u32 = 0,
    tail: u32 = 0,
    mask: u32 = 0,
    mmap_bytes: []align(std.heap.page_size_min) u8 = &.{},

    fn init(requested_capacity: usize) !ReactorCommandQueue {
        const cap = try ceilPow2(@max(requested_capacity, 64));
        if (cap - 1 > std.math.maxInt(u32)) return error.OutOfMemory;
        const bytes_len = std.math.mul(usize, cap, @sizeOf(ReactorCommand)) catch return error.OutOfMemory;
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

        const mapped = std.posix.mmap(null, bytes_len, .{ .READ = true, .WRITE = true }, huge_flags, -1, 0) catch std.posix.mmap(null, bytes_len, .{ .READ = true, .WRITE = true }, base_flags, -1, 0) catch return error.OutOfMemory;
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

pub const ConnectionSlot = struct {
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
            _ = linux.close(self.fd);
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

pub const TicketQueue = struct {
    storage: []Ticket,
    payload_storage: []u8,
    head: u32 = 0,
    tail: u32 = 0,
    mask: u32 = 0,
    mmap_bytes: []align(std.heap.page_size_min) u8 = &.{},

    fn init(requested_capacity: usize) !TicketQueue {
        const cap = try ceilPow2(@max(requested_capacity, 64));
        if (cap - 1 > std.math.maxInt(u32)) return error.OutOfMemory;
        const bytes_len = std.math.mul(usize, cap, @sizeOf(Ticket)) catch return error.OutOfMemory;
        const payload_bytes_len = std.math.mul(usize, cap, ticket_payload_capacity) catch return error.OutOfMemory;
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

        const mapped = std.posix.mmap(null, bytes_len, .{ .READ = true, .WRITE = true }, huge_flags, -1, 0) catch std.posix.mmap(null, bytes_len, .{ .READ = true, .WRITE = true }, base_flags, -1, 0) catch return error.OutOfMemory;
        errdefer {
            const bytes: []align(std.heap.page_size_min) const u8 = mapped;
            std.posix.munmap(bytes);
        }
        const payload_storage = std.heap.page_allocator.alloc(u8, payload_bytes_len) catch return error.OutOfMemory;
        errdefer std.heap.page_allocator.free(payload_storage);
        @memset(mapped, 0);
        @memset(payload_storage, 0);
        const ptr: [*]align(@alignOf(Ticket)) Ticket = @ptrCast(@alignCast(mapped.ptr));
        return .{
            .storage = ptr[0..cap],
            .payload_storage = payload_storage,
            .mask = @as(u32, @intCast(cap - 1)),
            .mmap_bytes = mapped,
        };
    }

    fn deinit(self: *TicketQueue) void {
        if (self.mmap_bytes.len != 0) {
            const bytes: []align(std.heap.page_size_min) const u8 = self.mmap_bytes;
            std.posix.munmap(bytes);
        }
        if (self.payload_storage.len != 0) {
            std.heap.page_allocator.free(self.payload_storage);
        }
        self.* = undefined;
    }

    pub fn isEmpty(self: *const TicketQueue) bool {
        return self.head == self.tail;
    }

    fn isFull(self: *const TicketQueue) bool {
        return self.tail -% self.head == self.storage.len;
    }

    fn push(self: *TicketQueue, ticket: Ticket) bool {
        if (self.isFull()) return false;
        const payload_len = @as(usize, @intCast(ticket.payload_len));
        if (payload_len > ticket_payload_capacity) return false;
        const slot_idx = self.tail & self.mask;
        const slot_start = @as(usize, @intCast(slot_idx)) * ticket_payload_capacity;
        const payload_dst = self.payload_storage[slot_start .. slot_start + ticket_payload_capacity];
        if (payload_len != 0) {
            const payload_src = @as([*]const u8, @ptrCast(ticket.payload))[0..payload_len];
            @memcpy(payload_dst[0..payload_len], payload_src);
        }
        var queued = ticket;
        queued.payload = &payload_dst[0];
        self.storage[slot_idx] = queued;
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

pub const SlotPool = struct {
    bytes: []align(std.heap.page_size_min) u8,
    slots: []ConnectionSlot,
    capacity: usize,
    next_hint: usize = 0,

    fn init(capacity: usize) !SlotPool {
        if (capacity == 0) return error.InvalidArgument;
        if (capacity > std.math.maxInt(u32)) return error.InvalidArgument;
        const bytes_len = std.math.mul(usize, capacity, @sizeOf(ConnectionSlot)) catch return error.OutOfMemory;
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

        const mapped = std.posix.mmap(null, bytes_len, .{ .READ = true, .WRITE = true }, huge_flags, -1, 0) catch std.posix.mmap(null, bytes_len, .{ .READ = true, .WRITE = true }, base_flags, -1, 0) catch return error.OutOfMemory;
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
