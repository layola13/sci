const std = @import("std");
const network_interfaces = @import("pal_network_interfaces_windows_support.zig");
const ws = std.os.windows.ws2_32;

extern "kernel32" fn GetCommandLineW() callconv(.winapi) ?[*:0]const u16;
extern "kernel32" fn GetComputerNameW(lpBuffer: [*]u16, nSize: *std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn GetTickCount64() callconv(.winapi) std.os.windows.ULONGLONG;
extern "kernel32" fn GlobalMemoryStatusEx(lpBuffer: *MemoryStatusEx) callconv(.winapi) std.os.windows.BOOL;
extern "iphlpapi" fn GetAdaptersAddresses(
    family: std.os.windows.ULONG,
    flags: std.os.windows.ULONG,
    reserved: ?*anyopaque,
    addresses: ?*IpAdapterAddresses,
    size: *std.os.windows.ULONG,
) callconv(.winapi) std.os.windows.ULONG;
extern "ws2_32" fn InetNtopW(
    family: c_int,
    address: *const anyopaque,
    buffer: [*]u16,
    buffer_size: usize,
) callconv(.winapi) ?[*:0]const u16;

const IpAdapterUnicastAddress = extern struct {
    alignment: u64,
    next: ?*IpAdapterUnicastAddress,
    address: ws.SOCKET_ADDRESS,
    prefix_origin: c_int,
    suffix_origin: c_int,
    dad_state: c_int,
    valid_lifetime: std.os.windows.ULONG,
    preferred_lifetime: std.os.windows.ULONG,
    lease_lifetime: std.os.windows.ULONG,
    on_link_prefix_length: u8,
};

const IpAdapterAddresses = extern struct {
    alignment: u64,
    next: ?*IpAdapterAddresses,
    adapter_name: ?[*:0]const u8,
    first_unicast_address: ?*IpAdapterUnicastAddress,
    first_anycast_address: ?*anyopaque,
    first_multicast_address: ?*anyopaque,
    first_dns_server_address: ?*anyopaque,
    dns_suffix: ?[*:0]const u16,
    description: ?[*:0]const u16,
    friendly_name: ?[*:0]const u16,
    physical_address: [8]u8,
    physical_address_length: std.os.windows.ULONG,
};

comptime {
    std.debug.assert(@sizeOf(IpAdapterUnicastAddress) == 64);
    std.debug.assert(@offsetOf(IpAdapterUnicastAddress, "on_link_prefix_length") == 56);
    std.debug.assert(@offsetOf(IpAdapterAddresses, "physical_address") == 80);
    std.debug.assert(@offsetOf(IpAdapterAddresses, "physical_address_length") == 88);
}

const MemoryStatusEx = extern struct {
    dwLength: std.os.windows.DWORD,
    dwMemoryLoad: std.os.windows.DWORD,
    ullTotalPhys: std.os.windows.ULONGLONG,
    ullAvailPhys: std.os.windows.ULONGLONG,
    ullTotalPageFile: std.os.windows.ULONGLONG,
    ullAvailPageFile: std.os.windows.ULONGLONG,
    ullTotalVirtual: std.os.windows.ULONGLONG,
    ullAvailVirtual: std.os.windows.ULONGLONG,
    ullAvailExtendedVirtual: std.os.windows.ULONGLONG,
};

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
    iocp: std.os.windows.HANDLE,
    mutex: std.Thread.Mutex = .{},
    events: std.ArrayList(SaEvent),

    fn init(allocator: std.mem.Allocator, iocp: std.os.windows.HANDLE) EventLoop {
        return .{
            .iocp = iocp,
            .events = std.ArrayList(SaEvent).init(allocator),
        };
    }

    fn deinit(self: *EventLoop) void {
        std.os.windows.CloseHandle(self.iocp);
        self.events.deinit();
    }
};

pub fn get_executable_path(allocator: std.mem.Allocator) ![]u8 {
    var capacity: usize = std.os.windows.MAX_PATH;
    while (true) {
        const buffer = try allocator.allocSentinel(u16, capacity, 0);
        errdefer allocator.free(buffer);
        const path_w = try std.os.windows.GetModuleFileNameW(null, buffer.ptr, @intCast(capacity));
        if (path_w.len < capacity) {
            const path = try std.unicode.wtf16LeToWtf8Alloc(allocator, path_w);
            allocator.free(buffer);
            return path;
        }
        allocator.free(buffer);
        capacity = std.math.mul(usize, capacity, 2) catch return error.NameTooLong;
    }
}

pub fn process_args_json_alloc(allocator: std.mem.Allocator) ![]u8 {
    const args = try process_args_alloc(allocator);
    defer process_args_free(allocator, args);
    for (args) |arg| {
        if (!std.unicode.utf8ValidateSlice(arg)) return error.NativeStringNotUnicode;
    }
    return std.json.stringifyAlloc(allocator, args, .{});
}

fn process_args_alloc_from_windows_command_line(allocator: std.mem.Allocator, command_line_w: []const u16) ![][:0]u8 {
    var it = try std.process.ArgIteratorWindows.init(allocator, command_line_w);
    defer it.deinit();

    var args = std.ArrayList([:0]u8).init(allocator);
    errdefer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit();
    }

    while (it.next()) |arg| {
        try args.append(try allocator.dupeZ(u8, arg));
    }
    return try args.toOwnedSlice();
}

pub fn process_args_alloc(allocator: std.mem.Allocator) ![][:0]u8 {
    const command_line_ptr = GetCommandLineW() orelse return error.Unexpected;
    return process_args_alloc_from_windows_command_line(allocator, std.mem.sliceTo(command_line_ptr, 0));
}

pub fn process_args_free(allocator: std.mem.Allocator, args: []const [:0]u8) void {
    for (args) |arg| allocator.free(arg);
    allocator.free(args);
}

pub fn hostname_alloc(allocator: std.mem.Allocator) ![]u8 {
    var buffer: [256]u16 = undefined;
    var len: std.os.windows.DWORD = buffer.len;
    if (GetComputerNameW(&buffer, &len) == 0) return error.Unexpected;
    return std.unicode.wtf16LeToWtf8Alloc(allocator, buffer[0..len]);
}

pub fn os_release_alloc(allocator: std.mem.Allocator) ![]u8 {
    var version = std.mem.zeroes(std.os.windows.RTL_OSVERSIONINFOW);
    version.dwOSVersionInfoSize = @sizeOf(std.os.windows.RTL_OSVERSIONINFOW);
    const status = std.os.windows.ntdll.RtlGetVersion(&version);
    if (status != .SUCCESS) return std.os.windows.unexpectedStatus(status);
    return std.fmt.allocPrint(
        allocator,
        "{d}.{d}.{d}",
        .{ version.dwMajorVersion, version.dwMinorVersion, version.dwBuildNumber },
    );
}

pub fn process_id() !u32 {
    return std.os.windows.GetCurrentProcessId();
}

pub fn parent_process_id() !u32 {
    var info: std.os.windows.PROCESS_BASIC_INFORMATION = undefined;
    var returned: std.os.windows.ULONG = 0;
    const status = std.os.windows.ntdll.NtQueryInformationProcess(
        std.os.windows.GetCurrentProcess(),
        .ProcessBasicInformation,
        &info,
        @sizeOf(std.os.windows.PROCESS_BASIC_INFORMATION),
        &returned,
    );
    if (status != .SUCCESS) return std.os.windows.unexpectedStatus(status);
    return std.math.cast(u32, info.InheritedFromUniqueProcessId) orelse error.Overflow;
}

pub fn user_id() !u32 {
    return error.Unsupported;
}

pub fn group_id() !u32 {
    return error.Unsupported;
}

fn formatMemoryUsageJson(allocator: std.mem.Allocator, rss: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"rss\":{d},\"heapTotal\":{d},\"heapUsed\":{d},\"external\":0}}", .{ rss, rss, rss });
}

pub fn memory_usage_json_alloc(allocator: std.mem.Allocator) ![]u8 {
    const counters = try std.os.windows.GetProcessMemoryInfo(std.os.windows.GetCurrentProcess());
    return formatMemoryUsageJson(allocator, @intCast(counters.WorkingSetSize));
}

fn formatSystemMemoryInfoJson(allocator: std.mem.Allocator, total: u64, free: u64, available: u64, buffers: u64, cached: u64, swapTotal: u64, swapFree: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"total\":{d},\"free\":{d},\"available\":{d},\"buffers\":{d},\"cached\":{d},\"swapTotal\":{d},\"swapFree\":{d}}}", .{ total, free, available, buffers, cached, swapTotal, swapFree });
}

pub fn system_memory_info_json_alloc(allocator: std.mem.Allocator) ![]u8 {
    var status: MemoryStatusEx = undefined;
    status.dwLength = @sizeOf(MemoryStatusEx);
    if (GlobalMemoryStatusEx(&status) == 0) return error.Unexpected;
    return formatSystemMemoryInfoJson(
        allocator,
        @intCast(status.ullTotalPhys),
        @intCast(status.ullAvailPhys),
        @intCast(status.ullAvailPhys),
        0,
        0,
        @intCast(status.ullTotalPageFile),
        @intCast(status.ullAvailPageFile),
    );
}

pub fn os_uptime_seconds() !f64 {
    return @as(f64, @floatFromInt(GetTickCount64())) / @as(f64, std.time.ms_per_s);
}

pub fn loadavg(_: *[3]f64) !void {
    return error.Unsupported;
}

fn adapterNameAlloc(allocator: std.mem.Allocator, adapter: *const IpAdapterAddresses) ![]u8 {
    if (adapter.friendly_name) |friendly_name| {
        return std.unicode.wtf16LeToWtf8Alloc(allocator, std.mem.sliceTo(friendly_name, 0));
    }
    if (adapter.adapter_name) |adapter_name| {
        return allocator.dupe(u8, std.mem.sliceTo(adapter_name, 0));
    }
    return allocator.dupe(u8, "");
}

fn internetAddressText(
    family: c_int,
    address: *const anyopaque,
    utf8_buffer: []u8,
) ![]const u8 {
    var utf16_buffer: [ws.INET6_ADDRSTRLEN]u16 = undefined;
    const text_w = InetNtopW(family, address, &utf16_buffer, utf16_buffer.len) orelse return error.Unexpected;
    const text_w_slice = std.mem.sliceTo(text_w, 0);
    const text_len = std.unicode.wtf16LeToWtf8(utf8_buffer, text_w_slice);
    return utf8_buffer[0..text_len];
}

fn socketAddressSource(address: *const ws.sockaddr, is_ipv4: bool) *const anyopaque {
    if (is_ipv4) {
        const inet: *align(1) const ws.sockaddr.in = @ptrCast(address);
        return @ptrCast(&inet.addr);
    }
    const inet6: *align(1) const ws.sockaddr.in6 = @ptrCast(address);
    return @ptrCast(&inet6.addr);
}

fn networkInterfacesJsonFromAdapters(
    allocator: std.mem.Allocator,
    first_adapter: ?*IpAdapterAddresses,
) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try list.append('[');

    var first = true;
    var current_adapter = first_adapter;
    while (current_adapter) |adapter| : (current_adapter = adapter.next) {
        const name = try adapterNameAlloc(allocator, adapter);
        defer allocator.free(name);

        const physical_address_length = @min(
            adapter.physical_address.len,
            @as(usize, @intCast(adapter.physical_address_length)),
        );
        var mac_buffer: [32]u8 = undefined;
        const mac = network_interfaces.formatMac(adapter.physical_address[0..physical_address_length], &mac_buffer);

        var current_unicast = adapter.first_unicast_address;
        while (current_unicast) |unicast| : (current_unicast = unicast.next) {
            const sockaddr = unicast.address.lpSockaddr;
            const family: c_int = @intCast(sockaddr.family);
            const is_ipv4 = family == ws.AF.INET;
            if (!is_ipv4 and family != ws.AF.INET6) continue;

            const required_size: i32 = if (is_ipv4) @sizeOf(ws.sockaddr.in) else @sizeOf(ws.sockaddr.in6);
            if (unicast.address.iSockaddrLength < required_size) continue;

            var address_buffer: [ws.INET6_ADDRSTRLEN * 3]u8 = undefined;
            const address = internetAddressText(
                family,
                socketAddressSource(sockaddr, is_ipv4),
                &address_buffer,
            ) catch continue;

            var mask_bytes: [16]u8 = undefined;
            const mask_slice = mask_bytes[0..if (is_ipv4) 4 else 16];
            network_interfaces.prefixMask(mask_slice, unicast.on_link_prefix_length);
            var mask_buffer: [ws.INET6_ADDRSTRLEN * 3]u8 = undefined;
            const netmask = internetAddressText(family, mask_slice.ptr, &mask_buffer) catch continue;

            var cidr_buffer: [ws.INET6_ADDRSTRLEN * 3 + 4]u8 = undefined;
            const cidr = try std.fmt.bufPrint(
                &cidr_buffer,
                "{s}/{d}",
                .{ address, unicast.on_link_prefix_length },
            );
            try network_interfaces.appendJson(&list, &first, .{
                .name = name,
                .family = if (is_ipv4) "IPv4" else "IPv6",
                .address = address,
                .netmask = netmask,
                .scopeid = null,
                .cidr = cidr,
                .mac = mac,
            });
        }
    }

    try list.append(']');
    return list.toOwnedSlice();
}

pub fn network_interfaces_json_alloc(allocator: std.mem.Allocator) ![]u8 {
    const gaa_flag_include_prefix: std.os.windows.ULONG = 0x0010;
    const error_buffer_overflow: std.os.windows.ULONG = 111;
    const error_no_data: std.os.windows.ULONG = 232;
    var size: std.os.windows.ULONG = 0;
    const probe = GetAdaptersAddresses(ws.AF.UNSPEC, gaa_flag_include_prefix, null, null, &size);
    if ((probe == 0 and size == 0) or probe == error_no_data) return allocator.dupe(u8, "[]");
    if (probe != error_buffer_overflow or size == 0) return error.Unexpected;

    var attempts: usize = 0;
    while (attempts < 3) : (attempts += 1) {
        const buffer = try allocator.alignedAlloc(u8, @alignOf(IpAdapterAddresses), size);
        const adapters: *IpAdapterAddresses = @ptrCast(buffer.ptr);
        const result = GetAdaptersAddresses(ws.AF.UNSPEC, gaa_flag_include_prefix, null, adapters, &size);
        if (result == 0) {
            defer allocator.free(buffer);
            return networkInterfacesJsonFromAdapters(allocator, adapters);
        }
        allocator.free(buffer);
        if (result == error_no_data) return allocator.dupe(u8, "[]");
        if (result != error_buffer_overflow or size == 0) return error.Unexpected;
    }
    return error.Unexpected;
}

pub fn term_epoll_create(_: u32) !std.os.windows.HANDLE {
    return error.Unsupported;
}

pub fn term_epoll_ctl(_: std.os.windows.HANDLE, _: u32, _: std.os.windows.HANDLE, _: u32, _: u64) !void {
    return error.Unsupported;
}

pub fn term_epoll_wait(_: std.mem.Allocator, _: std.os.windows.HANDLE, _: [*]SaTermEpollEvent, _: usize, _: i32) !usize {
    return error.Unsupported;
}

pub fn event_loop_create(out_loop: ?*?*anyopaque) i32 {
    const slot = out_loop orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = null;
    const iocp = std.os.windows.CreateIoCompletionPort(std.os.windows.INVALID_HANDLE_VALUE, null, 0, 0) catch return SA_STD_ERR_IO;
    errdefer std.os.windows.CloseHandle(iocp);

    const loop = std.heap.page_allocator.create(EventLoop) catch return SA_STD_ERR_NO_MEMORY;
    loop.* = EventLoop.init(std.heap.page_allocator, iocp);
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
    std.os.windows.PostQueuedCompletionStatus(loop.iocp, 0, 1, null) catch return SA_STD_ERR_IO;
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

    var transferred: std.os.windows.DWORD = 0;
    var completion_key: usize = 0;
    var overlapped: ?*std.os.windows.OVERLAPPED = null;
    const timeout: std.os.windows.DWORD = if (timeout_ms < 0) std.os.windows.INFINITE else @intCast(timeout_ms);
    switch (std.os.windows.GetQueuedCompletionStatus(loop.iocp, &transferred, &completion_key, &overlapped, timeout)) {
        .Normal => return drainSubmittedEvents(loop, out, max_events),
        .Timeout => return 0,
        .Aborted, .Cancelled, .EOF => return -SA_STD_ERR_IO,
    }
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

test "PAL event loop wait blocks until submit wakes the IOCP backend" {
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

test "Windows PAL parses process args from GetCommandLineW-compatible input" {
    const command_line = std.unicode.utf8ToUtf16LeStringLiteral("sa.exe \"two words\" slash\\\\\\\"quote");
    const args = try process_args_alloc_from_windows_command_line(std.testing.allocator, command_line);
    defer process_args_free(std.testing.allocator, args);

    try std.testing.expectEqual(@as(usize, 3), args.len);
    try std.testing.expectEqualStrings("sa.exe", args[0]);
    try std.testing.expectEqualStrings("two words", args[1]);
    try std.testing.expectEqualStrings("slash\\\"quote", args[2]);
}

test "Windows PAL formats process memory usage JSON" {
    const json = try formatMemoryUsageJson(std.testing.allocator, 12288);
    defer std.testing.allocator.free(json);
    try std.testing.expectEqualStrings("{\"rss\":12288,\"heapTotal\":12288,\"heapUsed\":12288,\"external\":0}", json);
}

test "Windows PAL formats system memory info JSON" {
    const json = try formatSystemMemoryInfoJson(std.testing.allocator, 12288, 4096, 4096, 0, 0, 8192, 2048);
    defer std.testing.allocator.free(json);
    try std.testing.expectEqualStrings("{\"total\":12288,\"free\":4096,\"available\":4096,\"buffers\":0,\"cached\":0,\"swapTotal\":8192,\"swapFree\":2048}", json);
}
