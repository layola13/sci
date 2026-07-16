const std = @import("std");
const network_interfaces = @import("pal_network_interfaces_posix.zig");

extern "c" fn _NSGetArgc() *c_int;
extern "c" fn _NSGetArgv() *[*:null]?[*:0]u8;
extern "c" fn getloadavg(loadavg: [*]f64, nelem: c_int) c_int;
extern "c" fn getuid() c_uint;
extern "c" fn getgid() c_uint;

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

fn process_args_alloc_from_native_argv(allocator: std.mem.Allocator, argc: usize, argv: [*]const ?[*:0]const u8) ![][:0]u8 {
    var args = std.ArrayList([:0]u8).init(allocator);
    errdefer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit();
    }

    for (0..argc) |i| {
        const arg_ptr = argv[i] orelse return error.Unexpected;
        try args.append(try allocator.dupeZ(u8, std.mem.sliceTo(arg_ptr, 0)));
    }

    return try args.toOwnedSlice();
}

pub fn process_args_alloc(allocator: std.mem.Allocator) ![][:0]u8 {
    const argc = _NSGetArgc().*;
    if (argc < 0) return error.Unexpected;
    return process_args_alloc_from_native_argv(allocator, @intCast(argc), _NSGetArgv().*);
}

pub fn process_args_free(allocator: std.mem.Allocator, args: []const [:0]u8) void {
    for (args) |arg| allocator.free(arg);
    allocator.free(args);
}

pub fn hostname_alloc(allocator: std.mem.Allocator) ![]u8 {
    const uname = std.posix.uname();
    return allocator.dupe(u8, std.mem.sliceTo(&uname.nodename, 0));
}

pub fn os_release_alloc(allocator: std.mem.Allocator) ![]u8 {
    const uname = std.posix.uname();
    return allocator.dupe(u8, std.mem.sliceTo(&uname.release, 0));
}

pub fn process_id() !u32 {
    return @intCast(std.c.getpid());
}

pub fn parent_process_id() !u32 {
    return @intCast(std.c.getppid());
}

pub fn user_id() !u32 {
    return @intCast(getuid());
}

pub fn group_id() !u32 {
    return @intCast(getgid());
}

fn formatMemoryUsageJson(allocator: std.mem.Allocator, rss: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"rss\":{d},\"heapTotal\":{d},\"heapUsed\":{d},\"external\":0}}", .{ rss, rss, rss });
}

pub fn memory_usage_json_alloc(allocator: std.mem.Allocator) ![]u8 {
    const task_port = std.c.mach_task_self();
    if (task_port == std.c.TASK_NULL) return error.Unexpected;

    var info: std.c.mach_task_basic_info = undefined;
    var info_count: std.c.mach_msg_type_number_t = std.c.MACH_TASK_BASIC_INFO_COUNT;
    const rc = std.c.task_info(
        task_port,
        std.c.MACH_TASK_BASIC_INFO,
        @as(std.c.task_info_t, @ptrCast(&info)),
        &info_count,
    );
    if (rc != 0) return error.Unexpected;
    return formatMemoryUsageJson(allocator, @intCast(info.resident_size));
}

fn formatSystemMemoryInfoJson(allocator: std.mem.Allocator, total: u64, free: u64, available: u64, buffers: u64, cached: u64, swapTotal: u64, swapFree: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"total\":{d},\"free\":{d},\"available\":{d},\"buffers\":{d},\"cached\":{d},\"swapTotal\":{d},\"swapFree\":{d}}}", .{ total, free, available, buffers, cached, swapTotal, swapFree });
}

pub fn system_memory_info_json_alloc(allocator: std.mem.Allocator) ![]u8 {
    var total: u64 = 0;
    var len: usize = @sizeOf(u64);
    try std.posix.sysctlbynameZ("hw.memsize", &total, &len, null, 0);
    return formatSystemMemoryInfoJson(allocator, total, 0, 0, 0, 0, 0, 0);
}

pub fn os_uptime_seconds() !f64 {
    const uptime = try std.posix.clock_gettime(.UPTIME_RAW);
    return @as(f64, @floatFromInt(uptime.sec)) + (@as(f64, @floatFromInt(uptime.nsec)) / @as(f64, std.time.ns_per_s));
}

pub fn loadavg(out: *[3]f64) !void {
    const count: c_int = @intCast(out.len);
    if (getloadavg(out, count) != count) return error.Unsupported;
}

const SockaddrDl = extern struct {
    len: u8,
    family: u8,
    index: u16,
    interface_type: u8,
    name_len: u8,
    address_len: u8,
    selector_len: u8,
    data: [0]u8,
};

comptime {
    std.debug.assert(@offsetOf(std.c.sockaddr.in, "addr") == 4);
    std.debug.assert(@offsetOf(std.c.sockaddr.in6, "addr") == 8);
    std.debug.assert(@offsetOf(SockaddrDl, "data") == 8);
}

fn macosMacAddress(ifap: ?*network_interfaces.IfAddrs, name: []const u8, buffer: *[32]u8) []const u8 {
    var current = ifap;
    while (current) |ifa| : (current = ifa.ifa_next) {
        const addr = ifa.ifa_addr orelse continue;
        if (addr.family != std.c.AF.LINK) continue;
        if (!std.mem.eql(u8, name, std.mem.sliceTo(ifa.ifa_name, 0))) continue;

        const link: *align(1) const SockaddrDl = @ptrCast(addr);
        const data_offset = @offsetOf(SockaddrDl, "data");
        const address_offset = data_offset + @as(usize, link.name_len);
        const address_len: usize = link.address_len;
        if (address_len != 6 or address_offset + address_len > link.len) continue;

        const bytes: [*]const u8 = @ptrFromInt(@intFromPtr(addr) + address_offset);
        return std.fmt.bufPrint(
            buffer,
            "{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}",
            .{ bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5] },
        ) catch return "00:00:00:00:00:00";
    }
    return "00:00:00:00:00:00";
}

pub fn network_interfaces_json_alloc(allocator: std.mem.Allocator) ![]u8 {
    return network_interfaces.network_interfaces_json_alloc(allocator, macosMacAddress);
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

test "macOS PAL parses native argv without Zig startup argv" {
    const raw = [_]?[*:0]const u8{ "demo".ptr, "two words".ptr, "".ptr };
    const args = try process_args_alloc_from_native_argv(std.testing.allocator, raw.len, raw[0..].ptr);
    defer process_args_free(std.testing.allocator, args);

    try std.testing.expectEqual(@as(usize, 3), args.len);
    try std.testing.expectEqualStrings("demo", args[0]);
    try std.testing.expectEqualStrings("two words", args[1]);
    try std.testing.expectEqualStrings("", args[2]);
}

test "macOS PAL formats process memory usage JSON" {
    const json = try formatMemoryUsageJson(std.testing.allocator, 12288);
    defer std.testing.allocator.free(json);
    try std.testing.expectEqualStrings("{\"rss\":12288,\"heapTotal\":12288,\"heapUsed\":12288,\"external\":0}", json);
}

test "macOS PAL formats system memory info JSON" {
    const json = try formatSystemMemoryInfoJson(std.testing.allocator, 12288, 0, 0, 0, 0, 0, 0);
    defer std.testing.allocator.free(json);
    try std.testing.expectEqualStrings("{\"total\":12288,\"free\":0,\"available\":0,\"buffers\":0,\"cached\":0,\"swapTotal\":0,\"swapFree\":0}", json);
}
