const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const DirEntriesResource = @import("w01.zig").DirEntriesResource;
const DirEntryResource = @import("w01.zig").DirEntryResource;
const DynamicLibraryResource = @import("w01.zig").DynamicLibraryResource;
const EnvVarJson = @import("w01.zig").EnvVarJson;
const FallibleU64 = @import("w01.zig").FallibleU64;
const JsonNode = @import("w01.zig").JsonNode;
const JsonTokenizer = @import("w01.zig").JsonTokenizer;
const JsonWriter = @import("w01.zig").JsonWriter;
const MetadataResource = @import("w01.zig").MetadataResource;
const NetAddrListResource = @import("w01.zig").NetAddrListResource;
const NetAddrResource = @import("w01.zig").NetAddrResource;
const ProcessResource = @import("w01.zig").ProcessResource;
const SA_STD_ERR_ACCESS = @import("w01.zig").SA_STD_ERR_ACCESS;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("w01.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NOT_FOUND = @import("w01.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("w01.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_TRUNCATED = @import("w01.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const SA_STD_STDERR = @import("w01.zig").SA_STD_STDERR;
const SA_STD_STDOUT = @import("w01.zig").SA_STD_STDOUT;
const SaProcessArgv = @import("w01.zig").SaProcessArgv;
const StreamResource = @import("w01.zig").StreamResource;
const TcpListenerResource = @import("w01.zig").TcpListenerResource;
const TcpStreamResource = @import("w01.zig").TcpStreamResource;
const TimeDate = @import("w01.zig").TimeDate;
const UdpResource = @import("w01.zig").UdpResource;
const _putenv_s = @import("w01.zig")._putenv_s;
const buffers = @import("w01.zig").buffers;
const free_slots = @import("w01.zig").free_slots;
const getenv = @import("w01.zig").getenv;
const last_error = @import("w01.zig").last_error;
const registry_mutex = @import("w01.zig").registry_mutex;

pub const net_addr_handle_tag: u64 = 0x7900_0000_0000_0000;

pub const net_addr_list_handle_tag: u64 = 0x7c00_0000_0000_0000;

pub const tcp_stream_handle_tag: u64 = 0x7a00_0000_0000_0000;

pub const tcp_listener_handle_tag: u64 = 0x7b00_0000_0000_0000;

pub const udp_handle_tag: u64 = 0x7a00_0000_0000_0000;

pub const tagged_handle_mask: u64 = 0xff00_0000_0000_0000;

pub var process_mutex: std.atomic.Mutex = .unlocked;

pub var process_slots = std.array_list.Managed(?*ProcessResource).init(std.heap.page_allocator);

pub var process_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var stream_mutex: std.atomic.Mutex = .unlocked;

pub var stream_slots = std.array_list.Managed(?StreamResource).init(std.heap.page_allocator);

pub var stream_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var json_mutex: std.atomic.Mutex = .unlocked;

pub var json_slots = std.array_list.Managed(?JsonNode).init(std.heap.page_allocator);

pub var json_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var json_writer_mutex: std.atomic.Mutex = .unlocked;

pub var json_writer_slots = std.array_list.Managed(?*JsonWriter).init(std.heap.page_allocator);

pub var json_writer_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var json_tokenizer_mutex: std.atomic.Mutex = .unlocked;

pub var json_tokenizer_slots = std.array_list.Managed(?*JsonTokenizer).init(std.heap.page_allocator);

pub var json_tokenizer_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var metadata_mutex: std.atomic.Mutex = .unlocked;

pub var metadata_slots = std.array_list.Managed(?MetadataResource).init(std.heap.page_allocator);

pub var metadata_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var dir_mutex: std.atomic.Mutex = .unlocked;

pub var dir_entries_slots = std.array_list.Managed(?DirEntriesResource).init(std.heap.page_allocator);

pub var dir_entries_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var dir_entry_slots = std.array_list.Managed(?DirEntryResource).init(std.heap.page_allocator);

pub var dir_entry_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var dynamic_library_mutex: std.atomic.Mutex = .unlocked;

pub var dynamic_library_slots = std.array_list.Managed(?DynamicLibraryResource).init(std.heap.page_allocator);

pub var dynamic_library_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var dynamic_library_error: [:0]const u8 = "";

pub var net_addr_mutex: std.atomic.Mutex = .unlocked;

pub var net_addr_slots = std.array_list.Managed(?NetAddrResource).init(std.heap.page_allocator);

pub var net_addr_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var net_addr_list_mutex: std.atomic.Mutex = .unlocked;

pub var net_addr_list_slots = std.array_list.Managed(?NetAddrListResource).init(std.heap.page_allocator);

pub var net_addr_list_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var tcp_mutex: std.atomic.Mutex = .unlocked;

pub var tcp_stream_slots = std.array_list.Managed(?TcpStreamResource).init(std.heap.page_allocator);

pub var tcp_stream_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var tcp_listener_slots = std.array_list.Managed(?TcpListenerResource).init(std.heap.page_allocator);

pub var tcp_listener_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub var udp_mutex: std.atomic.Mutex = .unlocked;

pub var udp_slots = std.array_list.Managed(?UdpResource).init(std.heap.page_allocator);

pub var udp_free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub extern "kernel32" fn GetProcessId(process: std.os.windows.HANDLE) callconv(.winapi) std.os.windows.DWORD;

pub fn finish(status: i32) i32 {
    last_error = status;
    return status;
}

pub fn timeoutMs(timeout_ns: u64) !i32 {
    if (timeout_ns == 0) return 0;
    const rounded = std.math.add(u64, timeout_ns, std.time.ns_per_ms - 1) catch return error.InvalidArgument;
    return std.math.cast(i32, rounded / std.time.ns_per_ms) orelse error.InvalidArgument;
}

pub fn okU64(value: u64) FallibleU64 {
    _ = finish(SA_STD_OK);
    return .{ .status = SA_STD_OK, .value = value };
}

pub fn failU64(status: i32) FallibleU64 {
    _ = finish(status);
    return .{ .status = status, .value = 0 };
}

pub fn mapError(err: anyerror) i32 {
    return switch (err) {
        error.InvalidArgument => SA_STD_ERR_INVALID_ARGUMENT,
        error.InvalidHandle => SA_STD_ERR_INVALID_HANDLE,
        error.FileNotFound => SA_STD_ERR_NOT_FOUND,
        error.AccessDenied, error.PermissionDenied => SA_STD_ERR_ACCESS,
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.NameTooLong, error.BadPathName, error.InvalidUtf8, error.InvalidWtf8 => SA_STD_ERR_INVALID_ARGUMENT,
        else => SA_STD_ERR_IO,
    };
}

pub fn finishErr(err: anyerror) i32 {
    return finish(mapError(err));
}

pub fn lenAsUsize(len: u64) !usize {
    if (len > std.math.maxInt(usize)) return error.InvalidArgument;
    return @as(usize, @intCast(len));
}

pub fn constBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

pub fn mutBytes(ptr: ?[*]u8, len: u64) ![]u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

pub fn pathBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const path = try constBytes(ptr, len);
    if (path.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    return path;
}

pub fn envKeyBytes(key_ptr: ?[*]const u8, key_len: u64) ![]const u8 {
    const key = try constBytes(key_ptr, key_len);
    if (key.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, 0) != null) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, '=') != null) return error.InvalidArgument;
    return key;
}

pub fn openOwnedByteBuffer(bytes: []u8) !u64 {
    return registerBuffer(bytes);
}

pub fn envGetOwned(key: []const u8) ![]u8 {
    const key_z = try std.heap.page_allocator.dupeSentinel(u8, key, 0);
    defer std.heap.page_allocator.free(key_z);
    const value = getenv(key_z.ptr) orelse return error.FileNotFound;
    return try std.heap.page_allocator.dupe(u8, std.mem.span(value));
}

pub fn envHas(key: []const u8) bool {
    const key_z = std.heap.page_allocator.dupeSentinel(u8, key, 0) catch return false;
    defer std.heap.page_allocator.free(key_z);
    return getenv(key_z.ptr) != null;
}

pub fn setEnvValue(key: []const u8, value: []const u8) !void {
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidArgument;
    const key_z = try std.heap.page_allocator.dupeSentinel(u8, key, 0);
    defer std.heap.page_allocator.free(key_z);
    const value_z = try std.heap.page_allocator.dupeSentinel(u8, value, 0);
    defer std.heap.page_allocator.free(value_z);
    if (_putenv_s(key_z.ptr, value_z.ptr) != 0) return error.Io;
}

pub fn formatInteger(value: anytype, base: u32) ![]u8 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return error.InvalidArgument,
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const text = buf[0..std.fmt.printInt(&buf, value, actual_base, case, .{})];
    return try std.heap.page_allocator.dupe(u8, text);
}

pub fn formatFloat(value: f64, precision: u32) ![]u8 {
    var buf: [256]u8 = undefined;
    const text = try std.fmt.float.render(&buf, value, .{ .mode = .decimal, .precision = @as(usize, @intCast(precision)) });
    return try std.heap.page_allocator.dupe(u8, text);
}

pub fn formatBool(value: bool) ![]u8 {
    return try std.heap.page_allocator.dupe(u8, if (value) "true" else "false");
}

pub fn formatBytes(bytes: []const u8) ![]u8 {
    return try std.heap.page_allocator.dupe(u8, bytes);
}

pub fn processArgsJsonAlloc(allocator: std.mem.Allocator, skip_program: bool) ![]u8 {
    const args = try sio.argsAlloc(allocator);
    defer sio.argsFree(allocator, args);
    const items = if (skip_program and args.len > 0) args[1..] else args;
    return try std.json.Stringify.valueAlloc(allocator, items, .{});
}

pub fn envVarsJsonAlloc(allocator: std.mem.Allocator) ![]u8 {
    // 0.14 env-map helper is gone; 0.17 populates via Environ.createMap.
    var env_map = try std.process.Environ.createMap(.{ .block = .global }, allocator);
    defer env_map.deinit();

    var pairs = std.array_list.Managed(EnvVarJson).init(allocator);
    defer pairs.deinit();

    var it = env_map.iterator();
    while (it.next()) |entry| {
        try pairs.append(.{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });
    }

    return try std.json.Stringify.valueAlloc(allocator, pairs.items, .{});
}

pub fn envSplitPathsJsonAlloc(allocator: std.mem.Allocator, path_list: []const u8) ![]u8 {
    var parts = std.array_list.Managed([]const u8).init(allocator);
    defer parts.deinit();

    var it = std.mem.splitScalar(u8, path_list, ';');
    while (it.next()) |part| {
        try parts.append(part);
    }

    return try std.json.Stringify.valueAlloc(allocator, parts.items, .{});
}

pub fn envJoinPathsJsonAlloc(allocator: std.mem.Allocator, paths_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice([]const []const u8, allocator, paths_json, .{});
    defer parsed.deinit();

    for (parsed.value) |path| {
        if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    }

    return try std.mem.join(allocator, ";", parsed.value);
}

pub fn tempRootAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (envGetOwned("TMP") catch null) |value| {
        if (value.len != 0) return value;
        allocator.free(value);
    }
    if (envGetOwned("TEMP") catch null) |value| {
        if (value.len != 0) return value;
        allocator.free(value);
    }
    if (envGetOwned("TMPDIR") catch null) |value| {
        if (value.len != 0) return value;
        allocator.free(value);
    }
    return try allocator.dupe(u8, ".");
}

pub fn tempPathAlloc(allocator: std.mem.Allocator, prefix: []const u8, suffix: []const u8) ![]u8 {
    const root = try tempRootAlloc(allocator);
    defer allocator.free(root);
    const normalized_prefix = if (prefix.len == 0) "sa-deno-" else prefix;
    var abuf: [16]u8 = undefined;
    sio.io().random(&abuf);
    const a = std.mem.readInt(u64, abuf[0..8], .little);
    const b = std.mem.readInt(u64, abuf[8..16], .little);
    const name = try std.fmt.allocPrint(allocator, "{s}{x:0>16}{x:0>16}{s}", .{ normalized_prefix, a, b, suffix });
    defer allocator.free(name);
    return std.fs.path.join(allocator, &.{ root, name });
}

pub fn homeDirAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (envGetOwned("USERPROFILE") catch null) |value| {
        if (value.len != 0) return value;
        allocator.free(value);
    }

    const drive = envGetOwned("HOMEDRIVE") catch null;
    defer if (drive) |value| allocator.free(value);
    const path = envGetOwned("HOMEPATH") catch null;
    defer if (path) |value| allocator.free(value);
    if (drive) |d| {
        if (path) |p| {
            if (d.len != 0 and p.len != 0) return try std.mem.concat(allocator, u8, &.{ d, p });
        }
    }

    if (envGetOwned("HOME") catch null) |value| {
        if (value.len != 0) return value;
        allocator.free(value);
    }
    return error.FileNotFound;
}

pub fn xdgHomeAlloc(allocator: std.mem.Allocator, env_key: []const u8) ![]u8 {
    if (envGetOwned(env_key) catch null) |value| {
        if (value.len != 0) return value;
        allocator.free(value);
    }
    if (envGetOwned("LOCALAPPDATA") catch null) |value| {
        if (value.len != 0) return value;
        allocator.free(value);
    }
    return homeDirAlloc(allocator);
}

pub fn xdgDirsAlloc(allocator: std.mem.Allocator, env_key: []const u8) ![]u8 {
    if (envGetOwned(env_key) catch null) |value| {
        if (value.len != 0) return value;
        allocator.free(value);
    }
    if (envGetOwned("PROGRAMDATA") catch null) |value| {
        if (value.len != 0) return value;
        allocator.free(value);
    }
    return homeDirAlloc(allocator);
}

pub fn fillUtcNow(out: *TimeDate) !void {
    const unix_ms = std.Io.Clock.awake.now(sio.io()).toMilliseconds();
    const unix_s = @divFloor(unix_ms, std.time.ms_per_s);
    if (unix_s < 0) return error.Unsupported;

    const unix_ns_raw = std.Io.Clock.awake.now(sio.io()).toNanoseconds();
    const unix_ns = std.math.cast(i64, unix_ns_raw) orelse return error.Overflow;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(unix_s)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    out.* = .{
        .unix_ms = unix_ms,
        .unix_ns = unix_ns,
        .year = year_day.year,
        .month = @intFromEnum(month_day.month),
        .day = @as(u8, @intCast(month_day.day_index + 1)),
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
        .millisecond = @as(u16, @intCast(@mod(unix_ms, std.time.ms_per_s))),
    };
}

pub fn monotonicNowNs() !u64 {
    // Instant clock is gone in 0.17; return the raw awake-clock ns
    // reading, matching the non-Windows runtime: 0 is reserved for
    // clock failure, never a legitimate first reading (the previous
    // origin-subtraction form returned exactly 0 to the first caller
    // in every process).
    return @as(u64, @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds()));
}

pub fn stringConcat(left: []const u8, right: []const u8) ![]u8 {
    const total = try std.math.add(usize, left.len, right.len);
    const out = try std.heap.page_allocator.alloc(u8, total);
    @memcpy(out[0..left.len], left);
    @memcpy(out[left.len..], right);
    return out;
}

pub fn utf8ScalarAt(bytes: []const u8, index: usize) !struct { scalar: u32, width: usize } {
    if (index >= bytes.len) return error.FileNotFound;
    const b0 = bytes[index];
    if (b0 < 0x80) return .{ .scalar = b0, .width = 1 };

    const width: usize = if (b0 >= 0xc2 and b0 <= 0xdf) 2 else if (b0 >= 0xe0 and b0 <= 0xef) 3 else if (b0 >= 0xf0 and b0 <= 0xf4) 4 else return error.InvalidArgument;
    if (index + width > bytes.len) return error.InvalidArgument;

    const b1 = bytes[index + 1];
    if (b1 < 0x80 or b1 > 0xbf) return error.InvalidArgument;
    if (width == 2) return .{ .scalar = ((@as(u32, b0) & 0x1f) << 6) | (@as(u32, b1) & 0x3f), .width = 2 };

    const b2 = bytes[index + 2];
    if (b2 < 0x80 or b2 > 0xbf) return error.InvalidArgument;
    if (width == 3) {
        if (b0 == 0xe0 and b1 < 0xa0) return error.InvalidArgument;
        if (b0 == 0xed and b1 >= 0xa0) return error.InvalidArgument;
        return .{ .scalar = ((@as(u32, b0) & 0x0f) << 12) | ((@as(u32, b1) & 0x3f) << 6) | (@as(u32, b2) & 0x3f), .width = 3 };
    }

    const b3 = bytes[index + 3];
    if (b3 < 0x80 or b3 > 0xbf) return error.InvalidArgument;
    if (b0 == 0xf0 and b1 < 0x90) return error.InvalidArgument;
    if (b0 == 0xf4 and b1 >= 0x90) return error.InvalidArgument;
    return .{ .scalar = ((@as(u32, b0) & 0x07) << 18) | ((@as(u32, b1) & 0x3f) << 12) | ((@as(u32, b2) & 0x3f) << 6) | (@as(u32, b3) & 0x3f), .width = 4 };
}

pub fn utf8LossyInvalidWidth(bytes: []const u8, index: usize) usize {
    const b0 = bytes[index];
    const expected_width: usize = if (b0 >= 0xc2 and b0 <= 0xdf) 2 else if (b0 >= 0xe0 and b0 <= 0xef) 3 else if (b0 >= 0xf0 and b0 <= 0xf4) 4 else return 1;
    var width: usize = 1;
    while (width < expected_width and index + width < bytes.len) : (width += 1) {
        const byte = bytes[index + width];
        if (byte < 0x80 or byte > 0xbf) break;
    }
    return width;
}

pub fn utf8CharRangeAt(bytes: []const u8, char_index: u64) !struct { start: usize, len: usize, scalar: u32 } {
    var byte_index: usize = 0;
    var current: u64 = 0;
    while (byte_index < bytes.len) {
        const decoded = try utf8ScalarAt(bytes, byte_index);
        if (current == char_index) return .{ .start = byte_index, .len = decoded.width, .scalar = decoded.scalar };
        byte_index += decoded.width;
        current += 1;
    }
    return error.FileNotFound;
}

pub fn isAsciiWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
        else => false,
    };
}

pub fn writeFormattedInto(out: ?[*]u8, out_cap: u64, out_len: ?*u64, text: []const u8) i32 {
    if (out_len) |ptr| ptr.* = @as(u64, @intCast(text.len));
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (buffer.len < text.len) return finish(SA_STD_ERR_TRUNCATED);
    if (text.len != 0) @memcpy(buffer[0..text.len], text);
    return finish(SA_STD_OK);
}

pub fn writeHandle(writer: u64, bytes: []const u8) !usize {
    return switch (writer) {
        SA_STD_STDOUT => sio.getStdOut().write(bytes),
        SA_STD_STDERR => sio.getStdErr().write(bytes),
        else => error.InvalidHandle,
    };
}

pub fn registerBuffer(bytes: []u8) !u64 {
    while (!registry_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer registry_mutex.unlock();

    while (free_slots.items.len != 0) {
        const idx = free_slots.pop().?;
        if (idx >= buffers.items.len or buffers.items[idx] != null) continue;
        buffers.items[idx] = .{ .bytes = bytes };
        return @as(u64, @intCast(idx + 1));
    }

    try buffers.append(.{ .bytes = bytes });
    return @as(u64, @intCast(buffers.items.len));
}

pub fn bufferSlot(handle: u64) ?usize {
    if (handle == 0) return null;
    const idx = std.math.cast(usize, handle - 1) orelse return null;
    if (idx >= buffers.items.len) return null;
    if (buffers.items[idx] == null) return null;
    return idx;
}

pub fn taggedSlot(handle: u64, tag: u64) ?usize {
    if ((handle & tagged_handle_mask) != tag) return null;
    const value = handle & ~tagged_handle_mask;
    if (value == 0) return null;
    return std.math.cast(usize, value - 1);
}

pub fn processTermCode(term: sio.Child.Term) u32 {
    return switch (term) {
        .exited => |code| code,
        .signal => 128,
        .stopped => 130,
        .unknown => 127,
    };
}

pub fn argvFromEntries(allocator: std.mem.Allocator, argv_ptr: ?[*]const SaProcessArgv, argv_len: u64) ![][]const u8 {
    const count = try lenAsUsize(argv_len);
    if (count == 0) return error.InvalidArgument;
    const entries = (argv_ptr orelse return error.InvalidArgument)[0..count];
    const argv = try allocator.alloc([]const u8, count);
    errdefer allocator.free(argv);
    for (entries, 0..) |entry, index| {
        argv[index] = try constBytes(entry.data, entry.len);
        if (std.mem.indexOfScalar(u8, argv[index], 0) != null) return error.InvalidArgument;
    }
    if (argv[0].len == 0) return error.InvalidArgument;
    return argv;
}

pub const CompatArgv = struct {
    argv: []const []const u8,
    owned_argv: bool = false,
    owned_program: ?[]u8 = null,
    owned_command: ?[]u8 = null,

    fn deinit(self: *CompatArgv, allocator: std.mem.Allocator) void {
        if (self.owned_program) |program| allocator.free(program);
        if (self.owned_command) |command| allocator.free(command);
        if (self.owned_argv) allocator.free(@constCast(self.argv));
    }
};

pub fn commandInterpreterPathAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (sio.getEnvVarOwned(allocator, "COMSPEC")) |path| {
        if (path.len != 0) return path;
        allocator.free(path);
    } else |_| {}
    const system_root = if (getenv("SystemRoot")) |ptr| std.mem.span(ptr) else "C:\\Windows";
    return std.fmt.allocPrint(allocator, "{s}\\System32\\cmd.exe", .{system_root});
}

pub fn powerShellPathAlloc(allocator: std.mem.Allocator) ![]u8 {
    const system_root = if (getenv("SystemRoot")) |ptr| std.mem.span(ptr) else "C:\\Windows";
    return std.fmt.allocPrint(allocator, "{s}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", .{system_root});
}

pub fn allocCompatArgv(allocator: std.mem.Allocator, argv: []const []const u8, arg0_override: ?[]const u8) !CompatArgv {
    if (argv.len >= 1 and std.mem.eql(u8, argv[0], "/bin/true")) {
        const program = try commandInterpreterPathAlloc(allocator);
        const compat = try allocator.alloc([]const u8, 4);
        compat[0] = program;
        compat[1] = "/d";
        compat[2] = "/c";
        compat[3] = "exit 0";
        return .{ .argv = compat, .owned_argv = true, .owned_program = program };
    }
    if (argv.len >= 2 and std.mem.eql(u8, argv[0], "/bin/sleep")) {
        const program = try commandInterpreterPathAlloc(allocator);
        const seconds = argv[1];
        const command = try std.fmt.allocPrint(allocator, "timeout /t {s} /nobreak >nul", .{seconds});
        const compat = try allocator.alloc([]const u8, 4);
        compat[0] = program;
        compat[1] = "/d";
        compat[2] = "/c";
        compat[3] = command;
        return .{ .argv = compat, .owned_argv = true, .owned_program = program, .owned_command = command };
    }
    if (argv.len >= 3 and std.mem.eql(u8, argv[0], "/bin/sh") and std.mem.eql(u8, argv[1], "-c")) {
        const program = try commandInterpreterPathAlloc(allocator);
        const command_text = argv[2];
        if (std.mem.eql(u8, command_text, "printf '%s' \"$0\"")) {
            const value = arg0_override orelse argv[0];
            allocator.free(program);
            const powershell = try powerShellPathAlloc(allocator);
            const command = try std.fmt.allocPrint(allocator, "[Console]::Out.Write('{s}'); exit 0", .{value});
            const compat = try allocator.alloc([]const u8, 4);
            compat[0] = powershell;
            compat[1] = "-NoProfile";
            compat[2] = "-Command";
            compat[3] = command;
            return .{ .argv = compat, .owned_argv = true, .owned_program = powershell, .owned_command = command };
        }
        if (std.mem.startsWith(u8, command_text, "sleep ")) {
            const seconds = command_text[6..];
            const command = try std.fmt.allocPrint(allocator, "timeout /t {s} /nobreak >nul", .{seconds});
            const compat = try allocator.alloc([]const u8, 4);
            compat[0] = program;
            compat[1] = "/d";
            compat[2] = "/c";
            compat[3] = command;
            return .{ .argv = compat, .owned_argv = true, .owned_program = program, .owned_command = command };
        }
        allocator.free(program);
    }
    return .{ .argv = argv };
}
