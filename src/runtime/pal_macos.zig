const std = @import("std");

pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = 1;
pub const SA_STD_ERR_NO_MEMORY: i32 = 5;
pub const SA_STD_ERR_IO: i32 = 6;
pub const supports_term_epoll = false;

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
    kq_fd: std.posix.fd_t,
    mutex: std.Thread.Mutex = .{},
    events: std.ArrayList(SaEvent),

    fn init(allocator: std.mem.Allocator, kq_fd: std.posix.fd_t) EventLoop {
        return .{
            .kq_fd = kq_fd,
            .events = std.ArrayList(SaEvent).init(allocator),
        };
    }

    fn deinit(self: *EventLoop) void {
        std.posix.close(self.kq_fd);
        self.events.deinit();
    }
};

const wake_ident: usize = 1;

pub fn get_executable_path(allocator: std.mem.Allocator) ![]u8 {
    var symlink_path_buffer: [std.fs.max_path_bytes:0]u8 = undefined;
    var symlink_path_len: u32 = std.fs.max_path_bytes + 1;
    if (std.c._NSGetExecutablePath(&symlink_path_buffer, &symlink_path_len) != 0) return error.NameTooLong;

    var real_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const real_path = try std.posix.realpathZ(&symlink_path_buffer, &real_path_buffer);
    return allocator.dupe(u8, real_path);
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

pub fn term_epoll_create(_: u32) !std.posix.fd_t {
    return error.Unsupported;
}

pub fn term_epoll_ctl(_: std.posix.fd_t, _: u32, _: std.posix.fd_t, _: u32, _: u64) !void {
    return error.Unsupported;
}

pub fn term_epoll_wait(_: std.mem.Allocator, _: std.posix.fd_t, _: [*]SaTermEpollEvent, _: usize, _: i32) !usize {
    return error.Unsupported;
}

pub fn event_loop_create(out_loop: ?*?*anyopaque) i32 {
    const slot = out_loop orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = null;

    const kq_fd = std.posix.kqueue() catch return SA_STD_ERR_IO;
    errdefer std.posix.close(kq_fd);

    const add_wake = std.posix.Kevent{
        .ident = wake_ident,
        .filter = std.c.EVFILT.USER,
        .flags = std.c.EV.ADD | std.c.EV.CLEAR,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    };
    _ = std.posix.kevent(kq_fd, &.{add_wake}, &.{}, null) catch return SA_STD_ERR_IO;

    const loop = std.heap.page_allocator.create(EventLoop) catch return SA_STD_ERR_NO_MEMORY;
    loop.* = EventLoop.init(std.heap.page_allocator, kq_fd);
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
    const trigger_wake = std.posix.Kevent{
        .ident = wake_ident,
        .filter = std.c.EVFILT.USER,
        .flags = 0,
        .fflags = std.c.NOTE.TRIGGER,
        .data = 0,
        .udata = 0,
    };
    _ = std.posix.kevent(loop.kq_fd, &.{trigger_wake}, &.{}, null) catch return SA_STD_ERR_IO;
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

    var timespec_buffer: std.posix.timespec = undefined;
    const timeout = if (timeout_ms < 0)
        null
    else blk: {
        timespec_buffer = .{
            .sec = @intCast(@divTrunc(timeout_ms, 1000)),
            .nsec = @intCast(@mod(timeout_ms, 1000) * std.time.ns_per_ms),
        };
        break :blk &timespec_buffer;
    };
    var kernel_events: [1]std.posix.Kevent = undefined;
    const woke = std.posix.kevent(loop.kq_fd, &.{}, &kernel_events, timeout) catch return -SA_STD_ERR_IO;
    if (woke == 0) return 0;
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

test "PAL event loop wait blocks until submit wakes the kqueue backend" {
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
