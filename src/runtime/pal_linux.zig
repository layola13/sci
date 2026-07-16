const std = @import("std");

pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = 1;
pub const SA_STD_ERR_NO_MEMORY: i32 = 5;
pub const SA_STD_ERR_IO: i32 = 6;
pub const supports_term_epoll = true;

pub const SaEvent = extern struct {
    user_data: u64,
    flags: u32,
    res: i32,
};

pub const SaTermEpollEvent = extern struct {
    events: u32,
    data: u64,
};

const EventLoop = struct {
    epoll_fd: std.posix.fd_t,
    event_fd: std.posix.fd_t,
    mutex: std.Thread.Mutex = .{},
    events: std.ArrayList(SaEvent),

    fn init(allocator: std.mem.Allocator, epoll_fd: std.posix.fd_t, event_fd: std.posix.fd_t) EventLoop {
        return .{
            .epoll_fd = epoll_fd,
            .event_fd = event_fd,
            .events = std.ArrayList(SaEvent).init(allocator),
        };
    }

    fn deinit(self: *EventLoop) void {
        std.posix.close(self.event_fd);
        std.posix.close(self.epoll_fd);
        self.events.deinit();
    }
};

pub fn get_executable_path(allocator: std.mem.Allocator) ![]u8 {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.posix.readlinkZ("/proc/self/exe", &buffer);
    return allocator.dupe(u8, path);
}

pub fn process_args_json_alloc(allocator: std.mem.Allocator) ![]u8 {
    const args = try process_args_alloc(allocator);
    defer process_args_free(allocator, args);
    return std.json.stringifyAlloc(allocator, args, .{});
}

pub fn process_args_alloc(allocator: std.mem.Allocator) ![][:0]u8 {
    return std.process.argsAlloc(allocator);
}

pub fn process_args_free(allocator: std.mem.Allocator, args: []const [:0]u8) void {
    std.process.argsFree(allocator, args);
}

pub fn term_epoll_create(flags: u32) !std.posix.fd_t {
    const cloexec_flag: u32 = @as(u32, @intCast(std.os.linux.EPOLL.CLOEXEC));
    if ((flags & ~cloexec_flag) != 0) return error.InvalidArgument;
    return std.posix.epoll_create1(flags);
}

pub fn term_epoll_ctl(epoll_fd: std.posix.fd_t, op: u32, target_fd: std.posix.fd_t, events: u32, data: u64) !void {
    if (op != std.os.linux.EPOLL.CTL_ADD and op != std.os.linux.EPOLL.CTL_MOD and op != std.os.linux.EPOLL.CTL_DEL) {
        return error.InvalidArgument;
    }
    if (op != std.os.linux.EPOLL.CTL_DEL and events == 0) return error.InvalidArgument;
    var event: std.os.linux.epoll_event = .{
        .events = events,
        .data = .{ .u64 = data },
    };
    const event_ptr = if (op == std.os.linux.EPOLL.CTL_DEL) null else &event;
    return std.posix.epoll_ctl(epoll_fd, op, target_fd, event_ptr);
}

pub fn term_epoll_wait(allocator: std.mem.Allocator, epoll_fd: std.posix.fd_t, out_events: [*]SaTermEpollEvent, event_count: usize, timeout_ms: i32) !usize {
    if (event_count == 0) return error.InvalidArgument;
    const kernel_events = try allocator.alloc(std.os.linux.epoll_event, event_count);
    defer allocator.free(kernel_events);

    const ready = std.posix.epoll_wait(epoll_fd, kernel_events, timeout_ms);
    for (kernel_events[0..ready], 0..) |event, i| {
        out_events[i] = .{
            .events = event.events,
            .data = event.data.u64,
        };
    }
    return ready;
}

pub fn event_loop_create(out_loop: ?*?*anyopaque) i32 {
    const slot = out_loop orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = null;

    const epoll_fd = std.posix.epoll_create1(std.os.linux.EPOLL.CLOEXEC) catch return SA_STD_ERR_IO;
    errdefer std.posix.close(epoll_fd);

    const event_fd = std.posix.eventfd(0, std.os.linux.EFD.CLOEXEC | std.os.linux.EFD.NONBLOCK) catch return SA_STD_ERR_IO;
    errdefer std.posix.close(event_fd);

    var wake_event: std.os.linux.epoll_event = .{
        .events = std.os.linux.EPOLL.IN,
        .data = .{ .u64 = 1 },
    };
    std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, event_fd, &wake_event) catch return SA_STD_ERR_IO;

    const loop = std.heap.page_allocator.create(EventLoop) catch return SA_STD_ERR_NO_MEMORY;
    loop.* = EventLoop.init(std.heap.page_allocator, epoll_fd, event_fd);
    slot.* = loop;
    return SA_STD_OK;
}

pub fn event_loop_submit(loop_ptr: ?*anyopaque, event_ptr: ?*const SaEvent) i32 {
    const loop: *EventLoop = @ptrCast(@alignCast(loop_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT));
    const event = event_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    {
        loop.mutex.lock();
        defer loop.mutex.unlock();
        loop.events.append(event.*) catch return SA_STD_ERR_NO_MEMORY;
    }
    var wake: u64 = 1;
    _ = std.posix.write(loop.event_fd, std.mem.asBytes(&wake)) catch return SA_STD_ERR_IO;
    return SA_STD_OK;
}

fn drainSubmittedEvents(loop: *EventLoop, out: [*]SaEvent, max_events: u32) i32 {
    loop.mutex.lock();
    defer loop.mutex.unlock();
    if (loop.events.items.len == 0) return 0;
    const ready = @min(loop.events.items.len, @as(usize, @intCast(max_events)));
    @memcpy(out[0..ready], loop.events.items[0..ready]);
    std.mem.copyForwards(SaEvent, loop.events.items[0 .. loop.events.items.len - ready], loop.events.items[ready..]);
    loop.events.shrinkRetainingCapacity(loop.events.items.len - ready);
    return @as(i32, @intCast(ready));
}

pub fn event_loop_wait(loop_ptr: ?*anyopaque, out_events: ?[*]SaEvent, max_events: u32, timeout_ms: i32) i32 {
    const loop: *EventLoop = @ptrCast(@alignCast(loop_ptr orelse return -SA_STD_ERR_INVALID_ARGUMENT));
    const out = out_events orelse return -SA_STD_ERR_INVALID_ARGUMENT;
    if (max_events == 0) return -SA_STD_ERR_INVALID_ARGUMENT;

    const ready_before_wait = drainSubmittedEvents(loop, out, max_events);
    if (ready_before_wait != 0) return ready_before_wait;

    var kernel_events: [1]std.os.linux.epoll_event = undefined;
    const woke = std.posix.epoll_wait(loop.epoll_fd, &kernel_events, timeout_ms);
    if (woke == 0) return 0;

    var counter: u64 = 0;
    _ = std.posix.read(loop.event_fd, std.mem.asBytes(&counter)) catch {};
    return drainSubmittedEvents(loop, out, max_events);
}

pub fn event_loop_close(loop_ptr: ?*anyopaque) i32 {
    const loop: *EventLoop = @ptrCast(@alignCast(loop_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT));
    loop.deinit();
    std.heap.page_allocator.destroy(loop);
    return SA_STD_OK;
}

test "PAL event loop drains submitted events and closes platform handles" {
    var loop: ?*anyopaque = null;
    try std.testing.expectEqual(SA_STD_OK, event_loop_create(&loop));
    try std.testing.expect(loop != null);

    const event = SaEvent{ .user_data = 0x5a17, .flags = 3, .res = -9 };
    try std.testing.expectEqual(SA_STD_OK, event_loop_submit(loop, &event));

    var out = [_]SaEvent{.{ .user_data = 0, .flags = 0, .res = 0 }};
    try std.testing.expectEqual(@as(i32, 1), event_loop_wait(loop, &out, 1, 0));
    try std.testing.expectEqual(event.user_data, out[0].user_data);
    try std.testing.expectEqual(event.flags, out[0].flags);
    try std.testing.expectEqual(event.res, out[0].res);
    try std.testing.expectEqual(@as(i32, 0), event_loop_wait(loop, &out, 1, 0));
    try std.testing.expectEqual(SA_STD_OK, event_loop_close(loop));
}

const WaiterResult = struct {
    ready: i32 = -1,
    event: SaEvent = .{ .user_data = 0, .flags = 0, .res = 0 },
};

fn waitForSubmittedEvent(loop: ?*anyopaque, result: *WaiterResult) void {
    var out = [_]SaEvent{.{ .user_data = 0, .flags = 0, .res = 0 }};
    result.ready = event_loop_wait(loop, &out, 1, 2000);
    if (result.ready == 1) result.event = out[0];
}

test "PAL event loop wait blocks until submit wakes the platform backend" {
    var loop: ?*anyopaque = null;
    try std.testing.expectEqual(SA_STD_OK, event_loop_create(&loop));
    defer std.testing.expectEqual(SA_STD_OK, event_loop_close(loop)) catch unreachable;

    var result = WaiterResult{};
    const waiter = try std.Thread.spawn(.{}, waitForSubmittedEvent, .{ loop, &result });
    std.time.sleep(10 * std.time.ns_per_ms);

    const event = SaEvent{ .user_data = 0x7a11, .flags = 9, .res = 17 };
    try std.testing.expectEqual(SA_STD_OK, event_loop_submit(loop, &event));
    waiter.join();

    try std.testing.expectEqual(@as(i32, 1), result.ready);
    try std.testing.expectEqual(event.user_data, result.event.user_data);
    try std.testing.expectEqual(event.flags, result.event.flags);
    try std.testing.expectEqual(event.res, result.event.res);
}
