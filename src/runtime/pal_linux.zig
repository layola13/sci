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

fn process_args_alloc_from_cmdline_bytes(allocator: std.mem.Allocator, bytes: []const u8) ![][:0]u8 {
    var args = std.ArrayList([:0]u8).init(allocator);
    errdefer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit();
    }

    var start: usize = 0;
    while (start < bytes.len) {
        const end = std.mem.indexOfScalarPos(u8, bytes, start, 0) orelse bytes.len;
        try args.append(try allocator.dupeZ(u8, bytes[start..end]));
        start = if (end == bytes.len) bytes.len else end + 1;
    }

    return try args.toOwnedSlice();
}

pub fn process_args_alloc(allocator: std.mem.Allocator) ![][:0]u8 {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, "/proc/self/cmdline", 16 * 1024 * 1024);
    defer allocator.free(bytes);
    return process_args_alloc_from_cmdline_bytes(allocator, bytes);
}

pub fn process_args_free(allocator: std.mem.Allocator, args: []const [:0]u8) void {
    for (args) |arg| allocator.free(arg);
    allocator.free(args);
}

fn memory_usage_json_from_statm_bytes(allocator: std.mem.Allocator, bytes: []const u8, page_size: u64) ![]u8 {
    var it = std.mem.tokenizeAny(u8, bytes, " \t\r\n");
    _ = it.next() orelse return error.InvalidMemoryUsage;
    const rss_pages_text = it.next() orelse return error.InvalidMemoryUsage;
    const rss_pages = try std.fmt.parseInt(u64, rss_pages_text, 10);
    const rss = rss_pages * page_size;
    return std.fmt.allocPrint(allocator, "{{\"rss\":{d},\"heapTotal\":{d},\"heapUsed\":{d},\"external\":0}}", .{ rss, rss, rss });
}

pub fn memory_usage_json_alloc(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, "/proc/self/statm", 4096);
    defer allocator.free(bytes);
    const page_size: u64 = @intCast(std.heap.pageSize());
    return memory_usage_json_from_statm_bytes(allocator, bytes, page_size);
}

fn formatSystemMemoryInfoJson(allocator: std.mem.Allocator, total: u64, free: u64, available: u64, buffers: u64, cached: u64, swapTotal: u64, swapFree: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"total\":{d},\"free\":{d},\"available\":{d},\"buffers\":{d},\"cached\":{d},\"swapTotal\":{d},\"swapFree\":{d}}}", .{ total, free, available, buffers, cached, swapTotal, swapFree });
}

fn system_memory_info_json_from_meminfo_bytes(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var total: u64 = 0;
    var free: u64 = 0;
    var available: u64 = 0;
    var buffers: u64 = 0;
    var cached: u64 = 0;
    var swapTotal: u64 = 0;
    var swapFree: u64 = 0;

    var it = std.mem.tokenizeScalar(u8, bytes, '\n');
    while (it.next()) |line| {
        var line_it = std.mem.tokenizeAny(u8, line, " \t:");
        const key = line_it.next() orelse continue;
        const val_str = line_it.next() orelse continue;
        const val = std.fmt.parseInt(u64, val_str, 10) catch continue;
        const value_bytes = val * 1024;
        if (std.mem.eql(u8, key, "MemTotal")) {
            total = value_bytes;
        } else if (std.mem.eql(u8, key, "MemFree")) {
            free = value_bytes;
        } else if (std.mem.eql(u8, key, "MemAvailable")) {
            available = value_bytes;
        } else if (std.mem.eql(u8, key, "Buffers")) {
            buffers = value_bytes;
        } else if (std.mem.eql(u8, key, "Cached")) {
            cached = value_bytes;
        } else if (std.mem.eql(u8, key, "SwapTotal")) {
            swapTotal = value_bytes;
        } else if (std.mem.eql(u8, key, "SwapFree")) {
            swapFree = value_bytes;
        }
    }

    return formatSystemMemoryInfoJson(allocator, total, free, available, buffers, cached, swapTotal, swapFree);
}

pub fn system_memory_info_json_alloc(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, "/proc/meminfo", 64 * 1024);
    defer allocator.free(bytes);
    return system_memory_info_json_from_meminfo_bytes(allocator, bytes);
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

test "Linux PAL parses proc cmdline bytes without Zig startup argv" {
    const bytes = "demo\x00two words\x00\x00";
    const args = try process_args_alloc_from_cmdline_bytes(std.testing.allocator, bytes);
    defer process_args_free(std.testing.allocator, args);

    try std.testing.expectEqual(@as(usize, 3), args.len);
    try std.testing.expectEqualStrings("demo", args[0]);
    try std.testing.expectEqualStrings("two words", args[1]);
    try std.testing.expectEqualStrings("", args[2]);
}

test "Linux PAL formats memory usage from proc statm bytes" {
    const json = try memory_usage_json_from_statm_bytes(std.testing.allocator, "12 3 0 0 0 0 0\n", 4096);
    defer std.testing.allocator.free(json);
    try std.testing.expectEqualStrings("{\"rss\":12288,\"heapTotal\":12288,\"heapUsed\":12288,\"external\":0}", json);
}

test "Linux PAL formats system memory info from proc meminfo bytes" {
    const meminfo =
        \\MemTotal:       10 kB
        \\MemFree:         2 kB
        \\MemAvailable:    4 kB
        \\Buffers:         1 kB
        \\Cached:          3 kB
        \\SwapTotal:       8 kB
        \\SwapFree:        6 kB
        \\
    ;
    const json = try system_memory_info_json_from_meminfo_bytes(std.testing.allocator, meminfo);
    defer std.testing.allocator.free(json);
    try std.testing.expectEqualStrings("{\"total\":10240,\"free\":2048,\"available\":4096,\"buffers\":1024,\"cached\":3072,\"swapTotal\":8192,\"swapFree\":6144}", json);
}
