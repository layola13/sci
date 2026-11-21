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
const IDLE_TIMEOUT_NS = @import("u01.zig").IDLE_TIMEOUT_NS;
const NetxProto_RAW = @import("u01.zig").NetxProto_RAW;
const REACTOR_TIMEOUT_NS = @import("u01.zig").REACTOR_TIMEOUT_NS;
const Reactor = @import("u02.zig").Reactor;
const ReactorCommand = @import("u01.zig").ReactorCommand;
const SA_NETX_ERR_INVALID_ARGUMENT = @import("u01.zig").SA_NETX_ERR_INVALID_ARGUMENT;
const SA_NETX_ERR_INVALID_HANDLE = @import("u01.zig").SA_NETX_ERR_INVALID_HANDLE;
const SA_NETX_ERR_IO = @import("u01.zig").SA_NETX_ERR_IO;
const SA_NETX_ERR_NET = @import("u01.zig").SA_NETX_ERR_NET;
const SA_NETX_ERR_NO_MEMORY = @import("u01.zig").SA_NETX_ERR_NO_MEMORY;
const SA_NETX_ERR_TRUNCATED = @import("u01.zig").SA_NETX_ERR_TRUNCATED;
const SA_NETX_OK = @import("u01.zig").SA_NETX_OK;
const Thread = @import("u01.zig").Thread;
const TicketFlag = @import("u01.zig").TicketFlag;
const TicketQueue = @import("u01.zig").TicketQueue;
const decodeUserData = @import("u03.zig").decodeUserData;
const eof = @import("u01.zig").eof;
const getState = @import("u03.zig").getState;
const linux = @import("u01.zig").linux;
const makeTicket = @import("u03.zig").makeTicket;
const packUserData = @import("u03.zig").packUserData;
const posix = @import("u01.zig").posix;
const reactorWorkerMain = @import("u03.zig").reactorWorkerMain;
const runtime_state = @import("u03.zig").runtime_state;
const setNonBlocking = @import("u03.zig").setNonBlocking;
const truncated = @import("u01.zig").truncated;
const zc = @import("u01.zig").zc;

    pub fn init(id: u32, ticket_capacity: usize) !Reactor {
        var ring = linux.IoUring.init(256, 0) catch |err| switch (err) {
            // Container seccomp policies or old kernels prohibit io_uring outright.
            // Surface this distinctly so callers can report UNSUPPORTED instead of IO.
            error.PermissionDenied, error.SystemOutdated => return error.IoUringUnavailable,
            else => return err,
        };
        errdefer ring.deinit();
        const tickets = try TicketQueue.init(ticket_capacity);
        errdefer {
            var tickets_owned = tickets;
            tickets_owned.deinit();
        }
        const command_eventfd: posix.fd_t = blk: {
            const rc = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);
            if (@as(isize, @bitCast(rc)) < 0) {
                var tickets_owned = tickets;
                tickets_owned.deinit();
                ring.deinit();
                return error.OutOfMemory;
            }
            break :blk @intCast(rc);
        };
        return .{
            .id = id,
            .ring = ring,
            .tickets = tickets,
            .command_eventfd = command_eventfd,
        };
    }

    pub fn deinit(self: *Reactor) void {
        self.stopWorker();
        if (self.command_eventfd >= 0) {
            _ = linux.close(self.command_eventfd);
            self.command_eventfd = -1;
        }
        self.tickets.deinit();
        if (self.buffer_group) |*group| {
            group.deinit(std.heap.page_allocator);
            self.buffer_group = null;
        }
        if (self.server) |*server| {
            server.deinit(sio.io());
            self.server = null;
        }
        self.ring.deinit();
    }

    pub fn startWorker(self: *Reactor) !void {
        if (self.worker_started) return;
        const worker = try Thread.spawn(.{}, reactorWorkerMain, .{self});
        self.worker = worker;
        self.worker_started = true;
    }

    pub fn stopWorker(self: *Reactor) void {
        if (!self.worker_started) return;
        self.command_mutex.lockUncancelable(sio.io());
        self.command_pending = false;
        self.command_result = SA_NETX_ERR_IO;
        self.command_cond.broadcast(sio.io());
        self.command_mutex.unlock(sio.io());
        self.ticket_cond.broadcast(sio.io());
        getState().worker_state.mutex.lockUncancelable(sio.io());
        getState().worker_state.stop = true;
        getState().worker_state.cond.broadcast(sio.io());
        while (getState().worker_state.active_workers != 0) {
            getState().worker_state.cond.waitUncancelable(sio.io(), &getState().worker_state.mutex);
        }
        getState().worker_state.mutex.unlock(sio.io());
        self.signalWake();
        if (self.worker) |worker| {
            worker.join();
            self.worker = null;
        }
        self.worker_started = false;
    }

    pub fn ensureBuffers(self: *Reactor) !void {
        // NOTE(Zig 0.17): BufferGroup.init now allocates its own buffers via
        // the given allocator (no caller mmap slice anymore).
        if (self.buffer_group != null) return;
        const buffer_count = 64;
        const buffer_size = 4096;
        self.buffer_group = linux.IoUring.BufferGroup.init(&self.ring, std.heap.page_allocator, @as(u16, @intCast(self.id + 1)), buffer_size, buffer_count) catch {
            self.buffer_group = null;
            return;
        };
    }

    pub fn signalWake(self: *Reactor) void {
        if (self.command_eventfd < 0) return;
        const value: u64 = 1;
        // Wake signals are best-effort; the reactor also polls command state on its next pump.
        _ = linux.write(self.command_eventfd, std.mem.asBytes(&value).ptr, @sizeOf(u64));
    }

    pub fn drainWakeEvent(self: *Reactor) void {
        if (self.command_eventfd < 0) return;
        var buf: [8]u8 = undefined;
        // Draining a wake event is best-effort; a stale event only causes an extra wake.
        _ = linux.read(self.command_eventfd, &buf, buf.len);
    }

    pub fn armWakeup(self: *Reactor) !void {
        if (self.command_eventfd < 0) return;
        if (self.wake_armed) return;
        _ = try self.ring.poll_add(packUserData(.wakeup, self.id, 0), self.command_eventfd, posix.POLL.IN | posix.POLL.ERR | posix.POLL.HUP);
        self.wake_armed = true;
    }

    pub fn armAccept(self: *Reactor) !void {
        if (self.server == null) return;
        if (self.accept_armed and self.accept_multishot_supported) return;
        const ud = packUserData(.accept, self.id, 0);
        if (self.accept_multishot_supported) {
            self.accept_addr_len = @sizeOf(posix.sockaddr);
            const sqe = self.ring.accept_multishot(ud, self.server.?.socket.handle, &self.accept_addr, &self.accept_addr_len, 0) catch |err| switch (err) {
                else => blk: {
                    self.accept_multishot_supported = false;
                    self.accept_addr_len = @sizeOf(posix.sockaddr);
                    break :blk try self.ring.accept(ud, self.server.?.socket.handle, &self.accept_addr, &self.accept_addr_len, 0);
                },
            };
            _ = sqe;
            self.accept_armed = true;
        } else {
            self.accept_addr_len = @sizeOf(posix.sockaddr);
            _ = try self.ring.accept(ud, self.server.?.socket.handle, &self.accept_addr, &self.accept_addr_len, 0);
            self.accept_armed = true;
        }
    }

    pub fn armRecv(self: *Reactor, slot: *ConnectionSlot) !void {
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

    pub fn drain(self: *Reactor, wait_one: bool) !void {
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

    pub fn handleCqe(self: *Reactor, cqe: linux.io_uring_cqe) !void {
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

    pub fn handleWakeupCqe(self: *Reactor, cqe: linux.io_uring_cqe) !void {
        _ = cqe;
        self.wake_armed = false;
        self.drainWakeEvent();
    }

    pub fn armTimeout(self: *Reactor) !void {
        if (self.timeout_armed) return;
        const ts = linux.kernel_timespec{
            .sec = @as(i64, @intCast(REACTOR_TIMEOUT_NS / std.time.ns_per_s)),
            .nsec = @as(i64, @intCast(REACTOR_TIMEOUT_NS % std.time.ns_per_s)),
        };
        _ = try self.ring.timeout(packUserData(.timeout, self.id, 0), &ts, 0, 0);
        self.timeout_armed = true;
    }

    pub fn handleTimeoutCqe(self: *Reactor, cqe: linux.io_uring_cqe) !void {
        self.timeout_armed = false;
        _ = cqe;
        self.scanExpiredSlots();
        self.resumePausedSlots();
        try self.armTimeout();
        _ = try self.ring.submit();
    }

    pub fn scanExpiredSlots(self: *Reactor) void {
        const now_ns = std.Io.Clock.awake.now(sio.io()).toNanoseconds();
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

    pub fn resumePausedSlots(self: *Reactor) void {
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
                            slot.markActive(@as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds())));
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

    pub fn requestResume(self: *Reactor) void {
        self.command_mutex.lockUncancelable(sio.io());
        self.resume_requested = true;
        self.command_mutex.unlock(sio.io());
        self.signalWake();
    }

    pub fn processPendingCommand(self: *Reactor) void {
        self.command_mutex.lockUncancelable(sio.io());
        if (!self.command_pending) {
            self.command_mutex.unlock(sio.io());
            return;
        }
        const command = self.command;
        self.command_mutex.unlock(sio.io());

        var result: i32 = SA_NETX_OK;
        switch (command.kind) {
            .listen => {
                if (command.address) |address| {
                    if (self.server != null) {
                        self.stopListening();
                    }
                    self.server = address.listen(sio.io(), .{
                        .kernel_backlog = 256,
                        .reuse_address = true,
                        .mode = .stream,
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
                    self.armWakeup() catch |err| {
                        // The accept path still submits work below; wake re-arming is opportunistic.
                        _ = @errorName(err);
                    };
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

    pub fn queueAcceptTicket(self: *Reactor, slot: *ConnectionSlot) bool {
        const ticket = makeTicket(slot, .accept, slot.proto, 0, slot.scratch[slot.message_start..slot.message_start]);
        return self.queueTicket(ticket);
    }

    pub fn queueSendDoneTicket(self: *Reactor, slot: *ConnectionSlot, flags: u8) bool {
        const ticket = makeTicket(slot, .send_done, slot.proto, flags, slot.scratch[slot.message_start..slot.message_start]);
        return self.queueTicket(ticket);
    }

    pub fn finishCommand(self: *Reactor, result: i32) void {
        self.command_mutex.lockUncancelable(sio.io());
        self.command_result = result;
        self.command_pending = false;
        self.command_cond.broadcast(sio.io());
        self.command_mutex.unlock(sio.io());
    }

    pub fn stopListening(self: *Reactor) void {
        if (self.server) |*server| {
            server.deinit(sio.io());
            self.server = null;
        }
        self.accept_armed = false;
        self.timeout_armed = false;
    }

    pub fn beginCommand(self: *Reactor, command: ReactorCommand) i32 {
        if (!self.worker_started) return SA_NETX_ERR_INVALID_HANDLE;
        self.command_mutex.lockUncancelable(sio.io());
        while (self.command_pending) {
            self.command_cond.waitUncancelable(sio.io(), &self.command_mutex);
        }
        self.command = command;
        self.command_result = SA_NETX_OK;
        self.command_pending = true;
        self.command_mutex.unlock(sio.io());

        self.signalWake();

        self.command_mutex.lockUncancelable(sio.io());
        while (self.command_pending) {
            self.command_cond.waitUncancelable(sio.io(), &self.command_mutex);
        }
        const result = self.command_result;
        self.command_mutex.unlock(sio.io());
        return result;
    }

    pub fn queueCloseTicket(self: *Reactor, slot: *ConnectionSlot, flags: u8) bool {
        const ticket = makeTicket(slot, .peer_close, NetxProto_RAW, flags, slot.scratch[slot.message_start..slot.message_start]);
        return self.queueTicket(ticket);
    }

    pub fn handleAcceptCqe(self: *Reactor, cqe: linux.io_uring_cqe) !void {
        if (cqe.res < 0) {
            self.accept_armed = false;
            self.accept_multishot_supported = false;
            try self.armAccept();
            return;
        }

        const fd = @as(posix.fd_t, @intCast(cqe.res));
        setNonBlocking(fd);
        var state = getState();
        const now_ns = @as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds()));
        if (state.slot_pool) |*pool| {
            const slot = pool.allocSlot(self.id, fd, now_ns) orelse {
                _ = linux.close(fd);
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
            _ = linux.close(fd);
            return;
        }
        if (!self.accept_multishot_supported) {
            self.accept_armed = false;
            try self.armAccept();
        }
    }

    pub fn handleRecvCqe(self: *Reactor, slot_id: u32, cqe: linux.io_uring_cqe) !void {
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
            slot.markActive(@as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds())));
            const incoming = if (self.buffer_group) |*group| blk: {
                break :blk group.get(cqe) catch return;
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
                group.put(cqe) catch |err| {
                    // Buffer recycling failure is tolerated for this CQE; later receives can allocate fallback buffers.
                    _ = @errorName(err);
                };
            }
        } else return;
    }

    pub fn handleSendCqe(self: *Reactor, slot_id: u32, cqe: linux.io_uring_cqe) !void {
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
