const std = @import("std");
const builtin = @import("builtin");

extern fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8;
extern fn _putenv_s(name: [*:0]const u8, value: [*:0]const u8) callconv(.c) c_int;
extern "kernel32" fn CreateHardLinkW(new_file_name: [*:0]const u16, existing_file_name: [*:0]const u16, security_attributes: ?*anyopaque) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn LoadLibraryW(path: [*:0]const u16) callconv(.winapi) ?std.os.windows.HMODULE;
extern "kernel32" fn GetProcAddress(module: std.os.windows.HMODULE, name: [*:0]const u8) callconv(.winapi) ?std.os.windows.FARPROC;
extern "kernel32" fn FreeLibrary(module: std.os.windows.HMODULE) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn GetLastError() callconv(.winapi) std.os.windows.Win32Error;

pub const SA_STD_ABI_VERSION: u32 = 1;

pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = 1;
pub const SA_STD_ERR_INVALID_HANDLE: i32 = 2;
pub const SA_STD_ERR_NOT_FOUND: i32 = 3;
pub const SA_STD_ERR_ACCESS: i32 = 4;
pub const SA_STD_ERR_NO_MEMORY: i32 = 5;
pub const SA_STD_ERR_IO: i32 = 6;
pub const SA_STD_ERR_NET: i32 = 7;
pub const SA_STD_ERR_UNSUPPORTED: i32 = 8;
pub const SA_STD_ERR_TRUNCATED: i32 = 9;
pub const SA_STD_ERR_UNKNOWN: i32 = 127;

pub const SA_JSON_KIND_INVALID: u32 = std.math.maxInt(u32);
pub const SA_JSON_KIND_NULL: u32 = 0;
pub const SA_JSON_KIND_BOOL: u32 = 1;
pub const SA_JSON_KIND_INTEGER: u32 = 2;
pub const SA_JSON_KIND_FLOAT: u32 = 3;
pub const SA_JSON_KIND_NUMBER_STRING: u32 = 4;
pub const SA_JSON_KIND_STRING: u32 = 5;
pub const SA_JSON_KIND_ARRAY: u32 = 6;
pub const SA_JSON_KIND_OBJECT: u32 = 7;
pub const SA_JSON_WHITESPACE_MINIFIED: u32 = 0;
pub const SA_JSON_WHITESPACE_INDENT_1: u32 = 1;
pub const SA_JSON_WHITESPACE_INDENT_2: u32 = 2;
pub const SA_JSON_WHITESPACE_INDENT_3: u32 = 3;
pub const SA_JSON_WHITESPACE_INDENT_4: u32 = 4;
pub const SA_JSON_WHITESPACE_INDENT_8: u32 = 5;
pub const SA_JSON_WHITESPACE_INDENT_TAB: u32 = 6;
pub const SA_JSON_TOKEN_INVALID: u32 = std.math.maxInt(u32);
pub const SA_JSON_TOKEN_OBJECT_BEGIN: u32 = 0;
pub const SA_JSON_TOKEN_OBJECT_END: u32 = 1;
pub const SA_JSON_TOKEN_ARRAY_BEGIN: u32 = 2;
pub const SA_JSON_TOKEN_ARRAY_END: u32 = 3;
pub const SA_JSON_TOKEN_TRUE: u32 = 4;
pub const SA_JSON_TOKEN_FALSE: u32 = 5;
pub const SA_JSON_TOKEN_NULL: u32 = 6;
pub const SA_JSON_TOKEN_NUMBER: u32 = 7;
pub const SA_JSON_TOKEN_PARTIAL_NUMBER: u32 = 8;
pub const SA_JSON_TOKEN_STRING: u32 = 9;
pub const SA_JSON_TOKEN_PARTIAL_STRING: u32 = 10;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1: u32 = 11;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2: u32 = 12;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3: u32 = 13;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4: u32 = 14;
pub const SA_JSON_TOKEN_END_OF_DOCUMENT: u32 = 15;
pub const SA_JSON_TOKEN_ALLOCATED_NUMBER: u32 = 16;
pub const SA_JSON_TOKEN_ALLOCATED_STRING: u32 = 17;

pub const SA_STD_STDIN: u64 = 1;
pub const SA_STD_STDOUT: u64 = 2;
pub const SA_STD_STDERR: u64 = 3;

const FallibleU64 = extern struct {
    status: i32,
    value: u64,
};

const FallibleI32 = extern struct { status: i32, value: i32 };

const TimeDate = extern struct {
    unix_ms: i64,
    unix_ns: i64,
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
};

const SaProcessArgv = extern struct {
    data: ?[*]const u8,
    len: u64,
};

const SaJsonToken = extern struct {
    kind: u32,
    text_ptr: ?[*]const u8,
    text_len: u64,
};

const ProcessMode = enum {
    inherit,
    capture,
    stream,
};

const ProcessResource = struct {
    child: std.process.Child,
    pid: u32,
    mode: ProcessMode,
    stdout_buf: []u8 = &.{},
    stderr_buf: []u8 = &.{},
    stdout_pos: usize = 0,
    stderr_pos: usize = 0,
    exited: bool = false,
    code: u32 = 0,

    fn finishWait(self: *ProcessResource) !void {
        if (self.exited) return;
        if (self.mode == .capture) {
            var stdout: std.ArrayListUnmanaged(u8) = .empty;
            errdefer stdout.deinit(std.heap.page_allocator);
            var stderr: std.ArrayListUnmanaged(u8) = .empty;
            errdefer stderr.deinit(std.heap.page_allocator);
            try self.child.collectOutput(std.heap.page_allocator, &stdout, &stderr, 64 * 1024 * 1024);
            self.stdout_buf = try stdout.toOwnedSlice(std.heap.page_allocator);
            errdefer std.heap.page_allocator.free(self.stdout_buf);
            self.stderr_buf = try stderr.toOwnedSlice(std.heap.page_allocator);
        }
        self.code = processTermCode(try self.child.wait());
        self.exited = true;
    }

    fn close(self: *ProcessResource) void {
        if (!self.exited) {
            const term = self.child.kill() catch self.child.wait() catch null;
            if (term) |value| self.code = processTermCode(value);
            self.exited = true;
        }
        if (self.stdout_buf.len != 0) std.heap.page_allocator.free(self.stdout_buf);
        if (self.stderr_buf.len != 0) std.heap.page_allocator.free(self.stderr_buf);
        self.* = undefined;
    }
};

const StreamKind = enum { pipe, file };

const StreamResource = struct {
    file: std.fs.File,
    kind: StreamKind,

    fn close(self: *StreamResource) void {
        self.file.close();
        self.* = undefined;
    }
};

const DynamicLibraryResource = struct {
    module: std.os.windows.HMODULE,

    fn close(self: *DynamicLibraryResource) void {
        _ = FreeLibrary(self.module);
        self.* = undefined;
    }
};

const NetAddrResource = struct {
    host: []u8,
    family: u32,
    port: u16,
    scope_id: u64,

    fn close(self: *NetAddrResource) void {
        if (self.host.len != 0) std.heap.page_allocator.free(self.host);
        self.* = undefined;
    }
};

const SaIoBuffer = extern struct {
    ptr: ?[*]u8,
    len: u64,
    cap: u64,
};

const JsonDocument = struct {
    parsed: std.json.Parsed(std.json.Value),
    ref_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(1),

    fn retain(self: *JsonDocument) void {
        _ = self.ref_count.fetchAdd(1, .monotonic);
    }

    fn release(self: *JsonDocument) void {
        if (self.ref_count.fetchSub(1, .release) != 1) return;
        _ = self.ref_count.load(.acquire);
        self.parsed.deinit();
        std.heap.page_allocator.destroy(self);
    }
};

const JsonNode = struct {
    document: *JsonDocument,
    value: std.json.Value,

    fn release(self: JsonNode) void {
        self.document.release();
    }
};

const JsonWriter = struct {
    buffer: std.ArrayList(u8),
    stream: std.json.WriteStream(std.ArrayList(u8).Writer, .checked_to_arbitrary_depth),
    started: bool = false,
    complete: bool = false,
    depth: u32 = 0,
    finished: bool = false,

    fn create(options: std.json.StringifyOptions) !*JsonWriter {
        const writer = try std.heap.page_allocator.create(JsonWriter);
        writer.* = .{
            .buffer = std.ArrayList(u8).init(std.heap.page_allocator),
            .stream = undefined,
        };
        writer.stream = std.json.writeStreamArbitraryDepth(std.heap.page_allocator, writer.buffer.writer(), options);
        return writer;
    }

    fn destroy(self: *JsonWriter) void {
        self.stream.deinit();
        self.buffer.deinit();
        std.heap.page_allocator.destroy(self);
    }
};

const JsonTokenizer = struct {
    scanner: std.json.Scanner,
    input: []u8 = &.{},
    pending_text: std.ArrayList(u8),
    current_text: ?[]const u8 = null,
    is_stream: bool,

    fn createStreaming() !*JsonTokenizer {
        const tokenizer = try std.heap.page_allocator.create(JsonTokenizer);
        tokenizer.* = .{
            .scanner = std.json.Scanner.initStreaming(std.heap.page_allocator),
            .pending_text = std.ArrayList(u8).init(std.heap.page_allocator),
            .is_stream = false,
        };
        return tokenizer;
    }

    fn createComplete(input: []const u8) !*JsonTokenizer {
        const owned = try std.heap.page_allocator.dupe(u8, input);
        errdefer std.heap.page_allocator.free(owned);
        const tokenizer = try std.heap.page_allocator.create(JsonTokenizer);
        tokenizer.* = .{
            .scanner = std.json.Scanner.initCompleteInput(std.heap.page_allocator, owned),
            .input = owned,
            .pending_text = std.ArrayList(u8).init(std.heap.page_allocator),
            .is_stream = true,
        };
        return tokenizer;
    }

    fn destroy(self: *JsonTokenizer) void {
        self.pending_text.deinit();
        self.scanner.deinit();
        if (self.input.len != 0) std.heap.page_allocator.free(self.input);
        std.heap.page_allocator.destroy(self);
    }
};

const EnvVarJson = struct {
    key: []const u8,
    value: []const u8,
};

const BufferResource = struct {
    bytes: []u8,

    fn close(self: *BufferResource) void {
        std.heap.page_allocator.free(self.bytes);
        self.* = .{ .bytes = &.{} };
    }
};

const MetadataResource = struct { stat: std.fs.File.Stat };

const DirEntrySnapshot = struct { name: []u8, kind: u32 };
const DirEntriesResource = struct {
    entries: []DirEntrySnapshot,
    fn close(self: *DirEntriesResource) void {
        for (self.entries) |entry| std.heap.page_allocator.free(entry.name);
        std.heap.page_allocator.free(self.entries);
        self.* = undefined;
    }
};
const DirEntryResource = struct {
    name: []u8,
    kind: u32,
    fn close(self: *DirEntryResource) void {
        std.heap.page_allocator.free(self.name);
        self.* = undefined;
    }
};

var last_error: i32 = SA_STD_OK;
var registry_mutex: std.Thread.Mutex = .{};
var buffers = std.ArrayList(?BufferResource).init(std.heap.page_allocator);
var free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var time_mutex: std.Thread.Mutex = .{};
var monotonic_origin: ?std.time.Instant = null;
const process_handle_tag: u64 = 0x7000_0000_0000_0000;
const stream_handle_tag: u64 = 0x7100_0000_0000_0000;
const json_handle_tag: u64 = 0x7200_0000_0000_0000;
const json_writer_handle_tag: u64 = 0x7300_0000_0000_0000;
const json_tokenizer_handle_tag: u64 = 0x7400_0000_0000_0000;
const metadata_handle_tag: u64 = 0x7500_0000_0000_0000;
const dir_entries_handle_tag: u64 = 0x7600_0000_0000_0000;
const dir_entry_handle_tag: u64 = 0x7700_0000_0000_0000;
const dynamic_library_handle_tag: u64 = 0x7800_0000_0000_0000;
const net_addr_handle_tag: u64 = 0x7900_0000_0000_0000;
const tagged_handle_mask: u64 = 0xff00_0000_0000_0000;
var process_mutex: std.Thread.Mutex = .{};
var process_slots = std.ArrayList(?*ProcessResource).init(std.heap.page_allocator);
var process_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var stream_mutex: std.Thread.Mutex = .{};
var stream_slots = std.ArrayList(?StreamResource).init(std.heap.page_allocator);
var stream_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var json_mutex: std.Thread.Mutex = .{};
var json_slots = std.ArrayList(?JsonNode).init(std.heap.page_allocator);
var json_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var json_writer_mutex: std.Thread.Mutex = .{};
var json_writer_slots = std.ArrayList(?*JsonWriter).init(std.heap.page_allocator);
var json_writer_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var json_tokenizer_mutex: std.Thread.Mutex = .{};
var json_tokenizer_slots = std.ArrayList(?*JsonTokenizer).init(std.heap.page_allocator);
var json_tokenizer_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var metadata_mutex: std.Thread.Mutex = .{};
var metadata_slots = std.ArrayList(?MetadataResource).init(std.heap.page_allocator);
var metadata_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var dir_mutex: std.Thread.Mutex = .{};
var dir_entries_slots = std.ArrayList(?DirEntriesResource).init(std.heap.page_allocator);
var dir_entries_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var dir_entry_slots = std.ArrayList(?DirEntryResource).init(std.heap.page_allocator);
var dir_entry_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var dynamic_library_mutex: std.Thread.Mutex = .{};
var dynamic_library_slots = std.ArrayList(?DynamicLibraryResource).init(std.heap.page_allocator);
var dynamic_library_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var dynamic_library_error: [:0]const u8 = "";
var net_addr_mutex: std.Thread.Mutex = .{};
var net_addr_slots = std.ArrayList(?NetAddrResource).init(std.heap.page_allocator);
var net_addr_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);

extern "kernel32" fn GetProcessId(process: std.os.windows.HANDLE) callconv(.winapi) std.os.windows.DWORD;

fn finish(status: i32) i32 {
    last_error = status;
    return status;
}

fn okU64(value: u64) FallibleU64 {
    _ = finish(SA_STD_OK);
    return .{ .status = SA_STD_OK, .value = value };
}

fn failU64(status: i32) FallibleU64 {
    _ = finish(status);
    return .{ .status = status, .value = 0 };
}

fn mapError(err: anyerror) i32 {
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

fn finishErr(err: anyerror) i32 {
    return finish(mapError(err));
}

fn lenAsUsize(len: u64) !usize {
    if (len > std.math.maxInt(usize)) return error.InvalidArgument;
    return @as(usize, @intCast(len));
}

fn constBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

fn mutBytes(ptr: ?[*]u8, len: u64) ![]u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

fn pathBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const path = try constBytes(ptr, len);
    if (path.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    return path;
}

fn envKeyBytes(key_ptr: ?[*]const u8, key_len: u64) ![]const u8 {
    const key = try constBytes(key_ptr, key_len);
    if (key.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, 0) != null) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, '=') != null) return error.InvalidArgument;
    return key;
}

fn openOwnedByteBuffer(bytes: []u8) !u64 {
    return registerBuffer(bytes);
}

fn envGetOwned(key: []const u8) ![]u8 {
    const key_z = try std.heap.page_allocator.dupeZ(u8, key);
    defer std.heap.page_allocator.free(key_z);
    const value = getenv(key_z.ptr) orelse return error.FileNotFound;
    return try std.heap.page_allocator.dupe(u8, std.mem.span(value));
}

fn envHas(key: []const u8) bool {
    const key_z = std.heap.page_allocator.dupeZ(u8, key) catch return false;
    defer std.heap.page_allocator.free(key_z);
    return getenv(key_z.ptr) != null;
}

fn setEnvValue(key: []const u8, value: []const u8) !void {
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidArgument;
    const key_z = try std.heap.page_allocator.dupeZ(u8, key);
    defer std.heap.page_allocator.free(key_z);
    const value_z = try std.heap.page_allocator.dupeZ(u8, value);
    defer std.heap.page_allocator.free(value_z);
    if (_putenv_s(key_z.ptr, value_z.ptr) != 0) return error.Io;
}

fn formatInteger(value: anytype, base: u32) ![]u8 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return error.InvalidArgument,
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrintIntToSlice(&buf, value, actual_base, case, .{});
    return try std.heap.page_allocator.dupe(u8, text);
}

fn formatFloat(value: f64, precision: u32) ![]u8 {
    var buf: [256]u8 = undefined;
    const text = try std.fmt.formatFloat(&buf, value, .{ .mode = .decimal, .precision = @as(usize, @intCast(precision)) });
    return try std.heap.page_allocator.dupe(u8, text);
}

fn formatBool(value: bool) ![]u8 {
    return try std.heap.page_allocator.dupe(u8, if (value) "true" else "false");
}

fn formatBytes(bytes: []const u8) ![]u8 {
    return try std.heap.page_allocator.dupe(u8, bytes);
}

fn processArgsJsonAlloc(allocator: std.mem.Allocator, skip_program: bool) ![]u8 {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const items = if (skip_program and args.len > 0) args[1..] else args;
    return try std.json.stringifyAlloc(allocator, items, .{});
}

fn envVarsJsonAlloc(allocator: std.mem.Allocator) ![]u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    var pairs = std.ArrayList(EnvVarJson).init(allocator);
    defer pairs.deinit();

    var it = env_map.iterator();
    while (it.next()) |entry| {
        try pairs.append(.{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });
    }

    return try std.json.stringifyAlloc(allocator, pairs.items, .{});
}

fn envSplitPathsJsonAlloc(allocator: std.mem.Allocator, path_list: []const u8) ![]u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    var it = std.mem.splitScalar(u8, path_list, ';');
    while (it.next()) |part| {
        try parts.append(part);
    }

    return try std.json.stringifyAlloc(allocator, parts.items, .{});
}

fn envJoinPathsJsonAlloc(allocator: std.mem.Allocator, paths_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice([]const []const u8, allocator, paths_json, .{});
    defer parsed.deinit();

    for (parsed.value) |path| {
        if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    }

    return try std.mem.join(allocator, ";", parsed.value);
}

fn tempRootAlloc(allocator: std.mem.Allocator) ![]u8 {
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

fn homeDirAlloc(allocator: std.mem.Allocator) ![]u8 {
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

fn fillUtcNow(out: *TimeDate) !void {
    const unix_ms = std.time.milliTimestamp();
    const unix_s = @divFloor(unix_ms, std.time.ms_per_s);
    if (unix_s < 0) return error.Unsupported;

    const unix_ns_raw = std.time.nanoTimestamp();
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

fn monotonicNowNs() !u64 {
    time_mutex.lock();
    defer time_mutex.unlock();

    const current = try std.time.Instant.now();
    if (monotonic_origin) |origin| {
        return current.since(origin);
    }
    monotonic_origin = current;
    return 0;
}

fn stringConcat(left: []const u8, right: []const u8) ![]u8 {
    const total = try std.math.add(usize, left.len, right.len);
    const out = try std.heap.page_allocator.alloc(u8, total);
    @memcpy(out[0..left.len], left);
    @memcpy(out[left.len..], right);
    return out;
}

fn utf8ScalarAt(bytes: []const u8, index: usize) !struct { scalar: u32, width: usize } {
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

fn utf8LossyInvalidWidth(bytes: []const u8, index: usize) usize {
    const b0 = bytes[index];
    const expected_width: usize = if (b0 >= 0xc2 and b0 <= 0xdf) 2 else if (b0 >= 0xe0 and b0 <= 0xef) 3 else if (b0 >= 0xf0 and b0 <= 0xf4) 4 else return 1;
    var width: usize = 1;
    while (width < expected_width and index + width < bytes.len) : (width += 1) {
        const byte = bytes[index + width];
        if (byte < 0x80 or byte > 0xbf) break;
    }
    return width;
}

fn utf8CharRangeAt(bytes: []const u8, char_index: u64) !struct { start: usize, len: usize, scalar: u32 } {
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

fn isAsciiWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
        else => false,
    };
}

fn writeFormattedInto(out: ?[*]u8, out_cap: u64, out_len: ?*u64, text: []const u8) i32 {
    if (out_len) |ptr| ptr.* = @as(u64, @intCast(text.len));
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (buffer.len < text.len) return finish(SA_STD_ERR_TRUNCATED);
    if (text.len != 0) @memcpy(buffer[0..text.len], text);
    return finish(SA_STD_OK);
}

fn writeHandle(writer: u64, bytes: []const u8) !usize {
    return switch (writer) {
        SA_STD_STDOUT => std.io.getStdOut().write(bytes),
        SA_STD_STDERR => std.io.getStdErr().write(bytes),
        else => error.InvalidHandle,
    };
}

fn registerBuffer(bytes: []u8) !u64 {
    registry_mutex.lock();
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

fn bufferSlot(handle: u64) ?usize {
    if (handle == 0) return null;
    const idx = std.math.cast(usize, handle - 1) orelse return null;
    if (idx >= buffers.items.len) return null;
    if (buffers.items[idx] == null) return null;
    return idx;
}

fn taggedSlot(handle: u64, tag: u64) ?usize {
    if ((handle & tagged_handle_mask) != tag) return null;
    const value = handle & ~tagged_handle_mask;
    if (value == 0) return null;
    return std.math.cast(usize, value - 1);
}

fn processTermCode(term: std.process.Child.Term) u32 {
    return switch (term) {
        .Exited => |code| code,
        .Signal => |_| 128,
        .Stopped => |_| 130,
        .Unknown => |_| 127,
    };
}

fn argvFromEntries(allocator: std.mem.Allocator, argv_ptr: ?[*]const SaProcessArgv, argv_len: u64) ![][]const u8 {
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

fn registerProcess(resource: *ProcessResource) !u64 {
    process_mutex.lock();
    defer process_mutex.unlock();
    while (process_free_slots.items.len != 0) {
        const idx = process_free_slots.pop().?;
        if (idx >= process_slots.items.len or process_slots.items[idx] != null) continue;
        process_slots.items[idx] = resource;
        return process_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try process_slots.append(resource);
    return process_handle_tag | @as(u64, @intCast(process_slots.items.len));
}

fn processSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, process_handle_tag) orelse return null;
    if (idx >= process_slots.items.len or process_slots.items[idx] == null) return null;
    return idx;
}

fn registerStreamKind(file: std.fs.File, kind: StreamKind) !u64 {
    stream_mutex.lock();
    defer stream_mutex.unlock();
    while (stream_free_slots.items.len != 0) {
        const idx = stream_free_slots.pop().?;
        if (idx >= stream_slots.items.len or stream_slots.items[idx] != null) continue;
        stream_slots.items[idx] = .{ .file = file, .kind = kind };
        return stream_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try stream_slots.append(.{ .file = file, .kind = kind });
    return stream_handle_tag | @as(u64, @intCast(stream_slots.items.len));
}

fn registerStream(file: std.fs.File) !u64 {
    return registerStreamKind(file, .pipe);
}

fn registerFile(file: std.fs.File) !u64 {
    return registerStreamKind(file, .file);
}

fn streamSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, stream_handle_tag) orelse return null;
    if (idx >= stream_slots.items.len or stream_slots.items[idx] == null) return null;
    return idx;
}

fn registerDynamicLibrary(module: std.os.windows.HMODULE) !u64 {
    dynamic_library_mutex.lock();
    defer dynamic_library_mutex.unlock();
    while (dynamic_library_free_slots.items.len != 0) {
        const idx = dynamic_library_free_slots.pop().?;
        if (idx >= dynamic_library_slots.items.len or dynamic_library_slots.items[idx] != null) continue;
        dynamic_library_slots.items[idx] = .{ .module = module };
        return dynamic_library_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try dynamic_library_slots.append(.{ .module = module });
    return dynamic_library_handle_tag | @as(u64, @intCast(dynamic_library_slots.items.len));
}

fn dynamicLibrarySlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, dynamic_library_handle_tag) orelse return null;
    if (idx >= dynamic_library_slots.items.len or dynamic_library_slots.items[idx] == null) return null;
    return idx;
}

fn closeDynamicLibrary(handle: u64) i32 {
    dynamic_library_mutex.lock();
    defer dynamic_library_mutex.unlock();
    const idx = dynamicLibrarySlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = dynamic_library_slots.items[idx].?;
    resource.close();
    dynamic_library_slots.items[idx] = null;
    dynamic_library_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

fn dynamicLibraryErrorStatus() i32 {
    return switch (@intFromEnum(GetLastError())) {
        2, 3, 126 => SA_STD_ERR_NOT_FOUND,
        5 => SA_STD_ERR_ACCESS,
        8 => SA_STD_ERR_NO_MEMORY,
        193 => SA_STD_ERR_INVALID_ARGUMENT,
        else => SA_STD_ERR_UNKNOWN,
    };
}

fn registerNetAddr(resource: NetAddrResource) !u64 {
    net_addr_mutex.lock();
    defer net_addr_mutex.unlock();
    while (net_addr_free_slots.items.len != 0) {
        const idx = net_addr_free_slots.pop().?;
        if (idx >= net_addr_slots.items.len or net_addr_slots.items[idx] != null) continue;
        net_addr_slots.items[idx] = resource;
        return net_addr_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try net_addr_slots.append(resource);
    return net_addr_handle_tag | @as(u64, @intCast(net_addr_slots.items.len));
}

fn netAddrSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, net_addr_handle_tag) orelse return null;
    if (idx >= net_addr_slots.items.len or net_addr_slots.items[idx] == null) return null;
    return idx;
}

fn closeNetAddr(handle: u64) i32 {
    net_addr_mutex.lock();
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = net_addr_slots.items[idx].?;
    resource.close();
    net_addr_slots.items[idx] = null;
    net_addr_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

fn parseIpv4Ascii(text: []const u8) ?[4]u8 {
    var parts: [4]u8 = undefined;
    var index: usize = 0;
    var part_index: usize = 0;

    while (part_index < 4) : (part_index += 1) {
        if (index >= text.len) return null;
        var value: u32 = 0;
        var digits: usize = 0;
        while (index < text.len and text[index] != '.') : (index += 1) {
            const byte = text[index];
            if (byte < '0' or byte > '9') return null;
            value = value * 10 + @as(u32, byte - '0');
            if (value > 255) return null;
            digits += 1;
        }
        if (digits == 0) return null;
        parts[part_index] = @as(u8, @intCast(value));
        if (part_index < 3) {
            if (index >= text.len or text[index] != '.') return null;
            index += 1;
        }
    }
    if (index != text.len) return null;
    return parts;
}

fn parsePortAscii(text: []const u8) ?u16 {
    if (text.len == 0) return null;
    var value: u32 = 0;
    for (text) |byte| {
        if (byte < '0' or byte > '9') return null;
        value = value * 10 + @as(u32, byte - '0');
        if (value > std.math.maxInt(u16)) return null;
    }
    return @as(u16, @intCast(value));
}

fn registerMetadata(stat: std.fs.File.Stat) !u64 {
    metadata_mutex.lock();
    defer metadata_mutex.unlock();
    while (metadata_free_slots.items.len != 0) {
        const idx = metadata_free_slots.pop().?;
        if (idx >= metadata_slots.items.len or metadata_slots.items[idx] != null) continue;
        metadata_slots.items[idx] = .{ .stat = stat };
        return metadata_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try metadata_slots.append(.{ .stat = stat });
    return metadata_handle_tag | @as(u64, @intCast(metadata_slots.items.len));
}

fn metadataSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, metadata_handle_tag) orelse return null;
    if (idx >= metadata_slots.items.len or metadata_slots.items[idx] == null) return null;
    return idx;
}

fn registerDirEntriesLocked(resource: DirEntriesResource) !u64 {
    while (dir_entries_free_slots.items.len != 0) {
        const idx = dir_entries_free_slots.pop().?;
        if (idx >= dir_entries_slots.items.len or dir_entries_slots.items[idx] != null) continue;
        dir_entries_slots.items[idx] = resource;
        return dir_entries_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try dir_entries_slots.append(resource);
    return dir_entries_handle_tag | @as(u64, @intCast(dir_entries_slots.items.len));
}

fn dirEntriesSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, dir_entries_handle_tag) orelse return null;
    if (idx >= dir_entries_slots.items.len or dir_entries_slots.items[idx] == null) return null;
    return idx;
}

fn registerDirEntryLocked(resource: DirEntryResource) !u64 {
    while (dir_entry_free_slots.items.len != 0) {
        const idx = dir_entry_free_slots.pop().?;
        if (idx >= dir_entry_slots.items.len or dir_entry_slots.items[idx] != null) continue;
        dir_entry_slots.items[idx] = resource;
        return dir_entry_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try dir_entry_slots.append(resource);
    return dir_entry_handle_tag | @as(u64, @intCast(dir_entry_slots.items.len));
}

fn dirEntrySlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, dir_entry_handle_tag) orelse return null;
    if (idx >= dir_entry_slots.items.len or dir_entry_slots.items[idx] == null) return null;
    return idx;
}

fn jsonSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, json_handle_tag) orelse return null;
    if (idx >= json_slots.items.len or json_slots.items[idx] == null) return null;
    return idx;
}

fn registerJsonNode(document: *JsonDocument, value: std.json.Value, retain: bool) !u64 {
    if (retain) document.retain();
    errdefer document.release();
    json_mutex.lock();
    defer json_mutex.unlock();
    while (json_free_slots.items.len != 0) {
        const idx = json_free_slots.pop().?;
        if (idx >= json_slots.items.len or json_slots.items[idx] != null) continue;
        json_slots.items[idx] = .{ .document = document, .value = value };
        return json_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try json_slots.append(.{ .document = document, .value = value });
    return json_handle_tag | @as(u64, @intCast(json_slots.items.len));
}

fn acquireJsonNode(handle: u64) !JsonNode {
    json_mutex.lock();
    defer json_mutex.unlock();
    const idx = jsonSlotLocked(handle) orelse return error.InvalidHandle;
    const node = json_slots.items[idx].?;
    node.document.retain();
    return node;
}

fn closeJsonHandle(handle: u64) i32 {
    json_mutex.lock();
    const idx = jsonSlotLocked(handle) orelse {
        json_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const node = json_slots.items[idx].?;
    json_slots.items[idx] = null;
    json_free_slots.append(idx) catch {
        json_mutex.unlock();
        node.release();
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    json_mutex.unlock();
    node.release();
    return finish(SA_STD_OK);
}

fn jsonWriterSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, json_writer_handle_tag) orelse return null;
    if (idx >= json_writer_slots.items.len or json_writer_slots.items[idx] == null) return null;
    return idx;
}

fn registerJsonWriter(writer: *JsonWriter) !u64 {
    json_writer_mutex.lock();
    defer json_writer_mutex.unlock();
    while (json_writer_free_slots.items.len != 0) {
        const idx = json_writer_free_slots.pop().?;
        if (idx >= json_writer_slots.items.len or json_writer_slots.items[idx] != null) continue;
        json_writer_slots.items[idx] = writer;
        return json_writer_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try json_writer_slots.append(writer);
    return json_writer_handle_tag | @as(u64, @intCast(json_writer_slots.items.len));
}

fn closeJsonWriter(handle: u64) i32 {
    json_writer_mutex.lock();
    const idx = jsonWriterSlotLocked(handle) orelse {
        json_writer_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const writer = json_writer_slots.items[idx].?;
    json_writer_slots.items[idx] = null;
    json_writer_free_slots.append(idx) catch {
        json_writer_mutex.unlock();
        writer.destroy();
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    json_writer_mutex.unlock();
    writer.destroy();
    return finish(SA_STD_OK);
}

fn writerForValue(handle: u64) !*JsonWriter {
    const idx = jsonWriterSlotLocked(handle) orelse return error.InvalidHandle;
    const writer = json_writer_slots.items[idx].?;
    if (writer.finished) return error.InvalidHandle;
    if (writer.complete and writer.depth == 0) return error.InvalidArgument;
    return writer;
}

fn markWriterValue(writer: *JsonWriter) void {
    writer.started = true;
    writer.complete = writer.depth == 0;
}

fn writerField(writer: *JsonWriter, key: []const u8) !void {
    if (writer.depth == 0) return error.InvalidArgument;
    try writer.stream.objectField(key);
}

fn tokenizerSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, json_tokenizer_handle_tag) orelse return null;
    if (idx >= json_tokenizer_slots.items.len or json_tokenizer_slots.items[idx] == null) return null;
    return idx;
}

fn registerTokenizer(tokenizer: *JsonTokenizer) !u64 {
    json_tokenizer_mutex.lock();
    defer json_tokenizer_mutex.unlock();
    while (json_tokenizer_free_slots.items.len != 0) {
        const idx = json_tokenizer_free_slots.pop().?;
        if (idx >= json_tokenizer_slots.items.len or json_tokenizer_slots.items[idx] != null) continue;
        json_tokenizer_slots.items[idx] = tokenizer;
        return json_tokenizer_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try json_tokenizer_slots.append(tokenizer);
    return json_tokenizer_handle_tag | @as(u64, @intCast(json_tokenizer_slots.items.len));
}

fn closeTokenizer(handle: u64) i32 {
    json_tokenizer_mutex.lock();
    const idx = tokenizerSlotLocked(handle) orelse {
        json_tokenizer_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const tokenizer = json_tokenizer_slots.items[idx].?;
    json_tokenizer_slots.items[idx] = null;
    json_tokenizer_free_slots.append(idx) catch {
        json_tokenizer_mutex.unlock();
        tokenizer.destroy();
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    json_tokenizer_mutex.unlock();
    tokenizer.destroy();
    return finish(SA_STD_OK);
}

fn jsonTokenKind(token: std.json.Token) u32 {
    return switch (token) {
        .object_begin => SA_JSON_TOKEN_OBJECT_BEGIN,
        .object_end => SA_JSON_TOKEN_OBJECT_END,
        .array_begin => SA_JSON_TOKEN_ARRAY_BEGIN,
        .array_end => SA_JSON_TOKEN_ARRAY_END,
        .true => SA_JSON_TOKEN_TRUE,
        .false => SA_JSON_TOKEN_FALSE,
        .null => SA_JSON_TOKEN_NULL,
        .number => SA_JSON_TOKEN_NUMBER,
        .partial_number => SA_JSON_TOKEN_PARTIAL_NUMBER,
        .allocated_number => SA_JSON_TOKEN_ALLOCATED_NUMBER,
        .string => SA_JSON_TOKEN_STRING,
        .partial_string => SA_JSON_TOKEN_PARTIAL_STRING,
        .partial_string_escaped_1 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1,
        .partial_string_escaped_2 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2,
        .partial_string_escaped_3 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3,
        .partial_string_escaped_4 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4,
        .allocated_string => SA_JSON_TOKEN_ALLOCATED_STRING,
        .end_of_document => SA_JSON_TOKEN_END_OF_DOCUMENT,
    };
}

fn setTokenizerText(tokenizer: *JsonTokenizer, token: std.json.Token) !void {
    tokenizer.pending_text.clearRetainingCapacity();
    tokenizer.current_text = null;
    switch (token) {
        .number, .partial_number, .string, .partial_string => |slice| {
            try tokenizer.pending_text.appendSlice(slice);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        .partial_string_escaped_1 => |slice| {
            try tokenizer.pending_text.appendSlice(slice[0..]);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        .partial_string_escaped_2 => |slice| {
            try tokenizer.pending_text.appendSlice(slice[0..]);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        .partial_string_escaped_3 => |slice| {
            try tokenizer.pending_text.appendSlice(slice[0..]);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        .partial_string_escaped_4 => |slice| {
            try tokenizer.pending_text.appendSlice(slice[0..]);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        .allocated_number, .allocated_string => |slice| {
            defer std.heap.page_allocator.free(slice);
            try tokenizer.pending_text.appendSlice(slice);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        else => {},
    }
}

fn jsonKind(value: std.json.Value) u32 {
    return switch (value) {
        .null => SA_JSON_KIND_NULL,
        .bool => SA_JSON_KIND_BOOL,
        .integer => SA_JSON_KIND_INTEGER,
        .float => SA_JSON_KIND_FLOAT,
        .number_string => SA_JSON_KIND_NUMBER_STRING,
        .string => SA_JSON_KIND_STRING,
        .array => SA_JSON_KIND_ARRAY,
        .object => SA_JSON_KIND_OBJECT,
    };
}

fn jsonText(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |text_value| text_value,
        .number_string => |text_value| text_value,
        else => null,
    };
}

fn jsonAsF64(value: std.json.Value) !f64 {
    return switch (value) {
        .integer => |inner| @as(f64, @floatFromInt(inner)),
        .float => |inner| if (std.math.isFinite(inner)) inner else error.InvalidArgument,
        .number_string => |text_value| blk: {
            const parsed = std.fmt.parseFloat(f64, text_value) catch return error.InvalidArgument;
            if (!std.math.isFinite(parsed)) return error.InvalidArgument;
            break :blk parsed;
        },
        else => error.InvalidArgument,
    };
}

fn jsonAsI64(value: std.json.Value) !i64 {
    return switch (value) {
        .integer => |inner| inner,
        .float => |inner| blk: {
            if (!std.math.isFinite(inner) or @round(inner) != inner) return error.InvalidArgument;
            if (inner > @as(f64, @floatFromInt(std.math.maxInt(i64))) or inner < @as(f64, @floatFromInt(std.math.minInt(i64)))) return error.InvalidArgument;
            break :blk @as(i64, @intFromFloat(inner));
        },
        .number_string => |text_value| std.fmt.parseInt(i64, text_value, 10) catch return error.InvalidArgument,
        else => error.InvalidArgument,
    };
}

fn jsonAsBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |inner| inner,
        else => error.InvalidArgument,
    };
}

fn jsonObjectValue(node: JsonNode, key: []const u8) !std.json.Value {
    return switch (node.value) {
        .object => |object| object.get(key) orelse error.FileNotFound,
        else => error.InvalidArgument,
    };
}

fn spawnProcessCwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, mode: ProcessMode, cwd: ?[]const u8) !u64 {
    const argv = try argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len);
    defer std.heap.page_allocator.free(argv);

    var child = std.process.Child.init(argv, std.heap.page_allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = if (mode == .inherit) .Inherit else .Pipe;
    child.stderr_behavior = if (mode == .inherit) .Inherit else .Pipe;
    child.cwd = cwd;
    try child.spawn();
    errdefer _ = child.kill() catch {};

    const resource = try std.heap.page_allocator.create(ProcessResource);
    errdefer std.heap.page_allocator.destroy(resource);
    resource.* = .{
        .child = child,
        .pid = GetProcessId(child.id),
        .mode = mode,
    };
    return registerProcess(resource);
}

fn spawnProcess(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, mode: ProcessMode) !u64 {
    return spawnProcessCwd(argv_ptr, argv_len, mode, null);
}

fn spawnStreamProcessCwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd: ?[]const u8, out_process: *u64, out_stdout: *u64, out_stderr: *u64) !void {
    const process = try spawnProcessCwd(argv_ptr, argv_len, .stream, cwd);
    errdefer _ = closeProcessHandle(process);

    process_mutex.lock();
    const idx = processSlotLocked(process) orelse {
        process_mutex.unlock();
        return error.InvalidHandle;
    };
    const resource = process_slots.items[idx].?;
    const stdout_file = resource.child.stdout orelse {
        process_mutex.unlock();
        return error.InvalidHandle;
    };
    const stderr_file = resource.child.stderr orelse {
        process_mutex.unlock();
        return error.InvalidHandle;
    };
    resource.child.stdout = null;
    resource.child.stderr = null;
    process_mutex.unlock();

    const stdout_handle = registerStream(stdout_file) catch |err| {
        stdout_file.close();
        stderr_file.close();
        return err;
    };
    errdefer _ = closeStreamHandle(stdout_handle);
    const stderr_handle = registerStream(stderr_file) catch |err| {
        stderr_file.close();
        return err;
    };
    out_process.* = process;
    out_stdout.* = stdout_handle;
    out_stderr.* = stderr_handle;
}

fn spawnStreamProcess(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_process: *u64, out_stdout: *u64, out_stderr: *u64) !void {
    return spawnStreamProcessCwd(argv_ptr, argv_len, null, out_process, out_stdout, out_stderr);
}

fn closeProcessHandle(handle: u64) i32 {
    process_mutex.lock();
    const idx = processSlotLocked(handle) orelse {
        process_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const resource = process_slots.items[idx].?;
    process_slots.items[idx] = null;
    process_free_slots.append(idx) catch {
        process_mutex.unlock();
        resource.close();
        std.heap.page_allocator.destroy(resource);
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    process_mutex.unlock();
    resource.close();
    std.heap.page_allocator.destroy(resource);
    return finish(SA_STD_OK);
}

fn closeStreamHandle(handle: u64) i32 {
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = stream_slots.items[idx].?;
    resource.close();
    stream_slots.items[idx] = null;
    stream_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

fn closeMetadataHandle(handle: u64) i32 {
    metadata_mutex.lock();
    defer metadata_mutex.unlock();
    const idx = metadataSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    metadata_slots.items[idx] = null;
    metadata_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

fn closeDirEntriesHandle(handle: u64) i32 {
    dir_mutex.lock();
    defer dir_mutex.unlock();
    const idx = dirEntriesSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = dir_entries_slots.items[idx].?;
    resource.close();
    dir_entries_slots.items[idx] = null;
    dir_entries_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

fn closeDirEntryHandle(handle: u64) i32 {
    dir_mutex.lock();
    defer dir_mutex.unlock();
    const idx = dirEntrySlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = dir_entry_slots.items[idx].?;
    resource.close();
    dir_entry_slots.items[idx] = null;
    dir_entry_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

fn statusName(code: i32) []const u8 {
    return switch (code) {
        SA_STD_OK => "OK",
        SA_STD_ERR_INVALID_ARGUMENT => "INVALID_ARGUMENT",
        SA_STD_ERR_INVALID_HANDLE => "INVALID_HANDLE",
        SA_STD_ERR_NOT_FOUND => "NOT_FOUND",
        SA_STD_ERR_ACCESS => "ACCESS",
        SA_STD_ERR_NO_MEMORY => "NO_MEMORY",
        SA_STD_ERR_IO => "IO",
        SA_STD_ERR_NET => "NET",
        SA_STD_ERR_UNSUPPORTED => "UNSUPPORTED",
        SA_STD_ERR_TRUNCATED => "TRUNCATED",
        else => "UNKNOWN",
    };
}

pub export fn sa_std_version() u32 {
    return SA_STD_ABI_VERSION;
}

pub export fn sa_std_last_error() i32 {
    return last_error;
}

pub export fn sa_std_error_name(code: i32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const name = statusName(code);
    if (out_len) |len_ptr| len_ptr.* = @as(u64, @intCast(name.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const cap = lenAsUsize(out_cap) catch |err| return finishErr(err);
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const copy_len = @min(cap, name.len);
    @memcpy(out_ptr[0..copy_len], name[0..copy_len]);
    if (copy_len != name.len) return finish(SA_STD_ERR_TRUNCATED);
    return finish(SA_STD_OK);
}

pub export fn sa_std_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_std_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_std_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_io_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_io_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_io_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_deno_cwd() u64 {
    const cwd = std.process.getCwdAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(cwd) catch return 0;
}

pub export fn sa_deno_chdir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.process.changeCurDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_env_set(key_ptr: ?[*]const u8, key_len: u64, value_ptr: ?[*]const u8, value_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const value = constBytes(value_ptr, value_len) catch |err| return finishErr(err);
    setEnvValue(key, value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_env_delete(key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch |err| return finishErr(err);
    setEnvValue(key, "") catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_random_uuid() u64 {
    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    var text: [36]u8 = undefined;
    _ = std.fmt.bufPrint(
        &text,
        "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
        .{
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
        },
    ) catch return 0;
    const owned = std.heap.page_allocator.dupe(u8, &text) catch return 0;
    return openOwnedByteBuffer(owned) catch {
        std.heap.page_allocator.free(owned);
        return 0;
    };
}

pub export fn sa_deno_args_json() u64 {
    const json = processArgsJsonAlloc(std.heap.page_allocator, true) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_btoa(data_ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(data_ptr, len) catch return 0;
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = std.heap.page_allocator.alloc(u8, encoded_len) catch return 0;
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return openOwnedByteBuffer(encoded) catch {
        std.heap.page_allocator.free(encoded);
        return 0;
    };
}

pub export fn sa_deno_atob(data_ptr: ?[*]const u8, len: u64) u64 {
    const encoded = constBytes(data_ptr, len) catch return 0;
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return 0;
    const decoded = std.heap.page_allocator.alloc(u8, decoded_len) catch return 0;
    std.base64.standard.Decoder.decode(decoded, encoded) catch {
        std.heap.page_allocator.free(decoded);
        return 0;
    };
    return openOwnedByteBuffer(decoded) catch {
        std.heap.page_allocator.free(decoded);
        return 0;
    };
}

pub export fn sa_deno_text_encode(data_ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(data_ptr, len) catch return 0;
    const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 0;
    return openOwnedByteBuffer(owned) catch {
        std.heap.page_allocator.free(owned);
        return 0;
    };
}

pub export fn sa_deno_text_decode(data_ptr: ?[*]const u8, len: u64) u64 {
    return sa_deno_text_encode(data_ptr, len);
}

pub export fn sa_deno_version_json() u64 {
    const json = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"deno\":\"sa-std\",\"v8\":\"\",\"typescript\":\"\",\"sci\":\"{s}\"}}",
        .{builtin.zig_version_string},
    ) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_version_deno() u64 {
    const owned = std.heap.page_allocator.dupe(u8, "sa-std") catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_build_json() u64 {
    const os = @tagName(builtin.os.tag);
    const arch = @tagName(builtin.cpu.arch);
    const abi = @tagName(builtin.abi);
    const json = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"os\":\"{s}\",\"arch\":\"{s}\",\"target\":\"{s}-{s}\"}}",
        .{ os, arch, arch, abi },
    ) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_build_os() u64 {
    const owned = std.heap.page_allocator.dupe(u8, @tagName(builtin.os.tag)) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_build_platform_family() u64 {
    const owned = std.heap.page_allocator.dupe(u8, "windows") catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_date_now_iso() u64 {
    var date: TimeDate = undefined;
    fillUtcNow(&date) catch return 0;
    const text = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z",
        .{
            date.year,
            date.month,
            date.day,
            date.hour,
            date.minute,
            date.second,
            date.millisecond,
        },
    ) catch return 0;
    return openOwnedByteBuffer(text) catch return 0;
}

pub export fn sa_env_get(key_ptr: ?[*]const u8, key_len: u64) u64 {
    const key = envKeyBytes(key_ptr, key_len) catch return 0;
    const owned = envGetOwned(key) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_env_has(key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(if (envHas(key)) SA_STD_OK else SA_STD_ERR_NOT_FOUND);
}

pub export fn sa_env_set_var(key_ptr: ?[*]const u8, key_len: u64, value_ptr: ?[*]const u8, value_len: u64) i32 {
    return sa_deno_env_set(key_ptr, key_len, value_ptr, value_len);
}

pub export fn sa_env_remove_var(key_ptr: ?[*]const u8, key_len: u64) i32 {
    return sa_deno_env_delete(key_ptr, key_len);
}

pub export fn sa_env_current_dir() u64 {
    return sa_deno_cwd();
}

pub export fn sa_env_set_current_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    return sa_deno_chdir(path_ptr, path_len);
}

pub export fn sa_env_current_exe() u64 {
    const path = std.fs.selfExePathAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_temp_dir() u64 {
    const path = tempRootAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_home_dir() u64 {
    const path = homeDirAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_args_json() u64 {
    const json = processArgsJsonAlloc(std.heap.page_allocator, false) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_env_vars_json() u64 {
    const json = envVarsJsonAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_env_split_paths_json(path_list_ptr: ?[*]const u8, path_list_len: u64) u64 {
    const path_list = constBytes(path_list_ptr, path_list_len) catch return 0;
    const json = envSplitPathsJsonAlloc(std.heap.page_allocator, path_list) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_env_join_paths_json(paths_json_ptr: ?[*]const u8, paths_json_len: u64) u64 {
    const paths_json = constBytes(paths_json_ptr, paths_json_len) catch return 0;
    const joined = envJoinPathsJsonAlloc(std.heap.page_allocator, paths_json) catch return 0;
    return openOwnedByteBuffer(joined) catch return 0;
}

pub export fn sa_env_buffer_data(buffer: u64) ?[*]u8 {
    return sa_fs_read_buffer_data(buffer);
}

pub export fn sa_env_buffer_len(buffer: u64) u64 {
    return sa_fs_read_buffer_len(buffer);
}

pub export fn sa_env_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_std_print(data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    std.io.getStdOut().writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_println(data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    std.io.getStdOut().writeAll(bytes) catch |err| return finishErr(err);
    std.io.getStdOut().writeAll("\n") catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_print_bytes(data: ?[*]const u8, len: u64) void {
    _ = sa_std_print(data, len);
}

pub export fn sa_fs_read_file(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) FallibleU64 {
    const path = pathBytes(path_ptr, path_len) catch |err| return failU64(mapError(err));
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return failU64(mapError(err));
    defer file.close();
    const cap = lenAsUsize(max_bytes) catch |err| return failU64(mapError(err));
    const bytes = file.readToEndAlloc(std.heap.page_allocator, cap) catch |err| return failU64(mapError(err));
    const handle = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return failU64(mapError(err));
    };
    return okU64(handle);
}

pub export fn sa_std_fs_read_file(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_read_file(path_ptr, path_len, max_bytes);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_read_to_string(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) FallibleU64 {
    return sa_fs_read_file(path_ptr, path_len, max_bytes);
}

pub export fn sa_std_fs_read_to_string(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    return sa_std_fs_read_file(path_ptr, path_len, max_bytes, out_handle);
}

pub export fn sa_std_fs_open_read(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return finishErr(err);
    const handle = registerFile(file) catch |err| {
        file.close();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_open_write(path_ptr: ?[*]const u8, path_len: u64, truncate: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = truncate != 0 }) catch |err| return finishErr(err);
    const handle = registerFile(file) catch |err| {
        file.close();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_open_options(path_ptr: ?[*]const u8, path_len: u64, flags: u32, create_mode: u32, custom_flags: u32, out_handle: ?*u64) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = flags;
    _ = create_mode;
    _ = custom_flags;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fs_file_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fs_remove(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteFile(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_exists(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().access(path, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_try_exists(path_ptr: ?[*]const u8, path_len: u64, out_exists: ?*u8) i32 {
    const exists_ptr = out_exists orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    exists_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return finish(SA_STD_OK),
        else => return finishErr(err),
    };
    exists_ptr.* = 1;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_len(path_ptr: ?[*]const u8, path_len: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const stat = std.fs.cwd().statFile(path) catch |err| return finishErr(err);
    len_ptr.* = stat.size;
    return finish(SA_STD_OK);
}

fn dirEntryKind(kind: std.fs.File.Kind) u32 {
    return switch (kind) {
        .file => 1,
        .directory => 2,
        .sym_link => 3,
        else => 255,
    };
}

fn readDirSnapshots(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) !DirEntriesResource {
    const path = try pathBytes(path_ptr, path_len);
    const limit = try lenAsUsize(max_entries);
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var list = std.ArrayList(DirEntrySnapshot).init(std.heap.page_allocator);
    errdefer {
        for (list.items) |entry| std.heap.page_allocator.free(entry.name);
        list.deinit();
    }
    var iterator = dir.iterate();
    while (list.items.len < limit) {
        const entry = try iterator.next() orelse break;
        const name = try std.heap.page_allocator.dupe(u8, entry.name);
        errdefer std.heap.page_allocator.free(name);
        try list.append(.{ .name = name, .kind = dirEntryKind(entry.kind) });
    }
    return .{ .entries = try list.toOwnedSlice() };
}

pub export fn sa_fs_read_dir_json(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) FallibleU64 {
    var snapshots = readDirSnapshots(path_ptr, path_len, max_entries) catch |err| return failU64(mapError(err));
    defer snapshots.close();
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    out.appendSlice("{\"entries\":[") catch |err| return failU64(mapError(err));
    for (snapshots.entries, 0..) |entry, index| {
        if (index != 0) out.append(',') catch |err| return failU64(mapError(err));
        std.json.stringify(.{
            .name = entry.name,
            .isDirectory = entry.kind == 2,
            .isFile = entry.kind == 1,
        }, .{}, out.writer()) catch |err| return failU64(mapError(err));
    }
    out.appendSlice("]}") catch |err| return failU64(mapError(err));
    const bytes = out.toOwnedSlice() catch |err| return failU64(mapError(err));
    const handle = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return failU64(mapError(err));
    };
    return okU64(handle);
}

pub export fn sa_std_fs_read_dir_json(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_read_dir_json(path_ptr, path_len, max_entries);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_dir_buffer_data(handle: u64) ?[*]u8 {
    return sa_fs_read_buffer_data(handle);
}
pub export fn sa_fs_dir_buffer_len(handle: u64) u64 {
    return sa_fs_read_buffer_len(handle);
}
pub export fn sa_fs_dir_buffer_free(handle: u64) i32 {
    return sa_fs_read_buffer_free(handle);
}

pub export fn sa_fs_read_dir_entries(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) FallibleU64 {
    var snapshots = readDirSnapshots(path_ptr, path_len, max_entries) catch |err| return failU64(mapError(err));
    dir_mutex.lock();
    const handle = registerDirEntriesLocked(snapshots) catch |err| {
        dir_mutex.unlock();
        snapshots.close();
        return failU64(mapError(err));
    };
    dir_mutex.unlock();
    return okU64(handle);
}

pub export fn sa_std_fs_read_dir_entries(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_read_dir_entries(path_ptr, path_len, max_entries);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_dir_entries_len(handle: u64) u64 {
    dir_mutex.lock();
    defer dir_mutex.unlock();
    const idx = dirEntriesSlotLocked(handle) orelse return 0;
    return @as(u64, @intCast(dir_entries_slots.items[idx].?.entries.len));
}

pub export fn sa_std_fs_dir_entries_get(handle: u64, index: u64, out_entry_handle: ?*u64) i32 {
    const handle_ptr = out_entry_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const idx = std.math.cast(usize, index) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    dir_mutex.lock();
    defer dir_mutex.unlock();
    const parent_idx = dirEntriesSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const entries = dir_entries_slots.items[parent_idx].?.entries;
    if (idx >= entries.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const name = std.heap.page_allocator.dupe(u8, entries[idx].name) catch |err| return finishErr(err);
    const child = registerDirEntryLocked(.{ .name = name, .kind = entries[idx].kind }) catch |err| {
        std.heap.page_allocator.free(name);
        return finishErr(err);
    };
    handle_ptr.* = child;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_dir_entries_free(handle: u64) i32 {
    return sa_std_close(handle);
}
pub export fn sa_fs_dir_entry_name_ptr(handle: u64) ?[*]u8 {
    dir_mutex.lock();
    defer dir_mutex.unlock();
    const idx = dirEntrySlotLocked(handle) orelse return null;
    return dir_entry_slots.items[idx].?.name.ptr;
}
pub export fn sa_fs_dir_entry_name_len(handle: u64) u64 {
    dir_mutex.lock();
    defer dir_mutex.unlock();
    const idx = dirEntrySlotLocked(handle) orelse return 0;
    return @as(u64, @intCast(dir_entry_slots.items[idx].?.name.len));
}
pub export fn sa_fs_dir_entry_file_name_ptr(handle: u64) ?[*]u8 {
    return sa_fs_dir_entry_name_ptr(handle);
}
pub export fn sa_fs_dir_entry_file_name_len(handle: u64) u64 {
    return sa_fs_dir_entry_name_len(handle);
}
pub export fn sa_fs_dir_entry_kind(handle: u64) u32 {
    dir_mutex.lock();
    defer dir_mutex.unlock();
    const idx = dirEntrySlotLocked(handle) orelse return 0;
    return dir_entry_slots.items[idx].?.kind;
}
pub export fn sa_fs_dir_entry_ino(handle: u64) u64 {
    _ = handle;
    return 0;
}
pub export fn sa_fs_dir_entry_free(handle: u64) i32 {
    return sa_std_close(handle);
}

fn metadataStat(path_ptr: ?[*]const u8, path_len: u64) !std.fs.File.Stat {
    const path = try pathBytes(path_ptr, path_len);
    return std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.IsDir => {
            var dir = try std.fs.cwd().openDir(path, .{});
            defer dir.close();
            return dir.stat();
        },
        else => return err,
    };
}

pub export fn sa_fs_metadata(path_ptr: ?[*]const u8, path_len: u64) FallibleU64 {
    const stat = metadataStat(path_ptr, path_len) catch |err| return failU64(mapError(err));
    const handle = registerMetadata(stat) catch |err| return failU64(mapError(err));
    return okU64(handle);
}

pub export fn sa_std_fs_metadata(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_metadata(path_ptr, path_len);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

fn nsToMs(ns: i128) i64 {
    return @as(i64, @intCast(@divFloor(ns, std.time.ns_per_ms)));
}

fn metadataJsonAlloc(stat: std.fs.File.Stat) ![]u8 {
    return std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"createdAtMs\":{d},\"isDirectory\":{s},\"isFile\":{s},\"isSymlink\":{s},\"modifiedAtMs\":{d},\"accessedAtMs\":{d},\"changedAtMs\":{d},\"size\":{d},\"mode\":0,\"uid\":0,\"gid\":0,\"dev\":0,\"ino\":{d},\"nlink\":0,\"rdev\":0,\"blksize\":0,\"blocks\":0}}",
        .{ nsToMs(stat.ctime), if (stat.kind == .directory) "true" else "false", if (stat.kind == .file) "true" else "false", if (stat.kind == .sym_link) "true" else "false", nsToMs(stat.mtime), nsToMs(stat.atime), nsToMs(stat.ctime), stat.size, stat.inode },
    );
}

pub export fn sa_fs_metadata_json(path_ptr: ?[*]const u8, path_len: u64) FallibleU64 {
    const stat = metadataStat(path_ptr, path_len) catch |err| return failU64(mapError(err));
    const bytes = metadataJsonAlloc(stat) catch |err| return failU64(mapError(err));
    const handle = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return failU64(mapError(err));
    };
    return okU64(handle);
}

pub export fn sa_std_fs_metadata_json(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_metadata_json(path_ptr, path_len);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

fn metadataKindIs(handle: u64, kind: std.fs.File.Kind) u8 {
    metadata_mutex.lock();
    defer metadata_mutex.unlock();
    const idx = metadataSlotLocked(handle) orelse return 0;
    return if (metadata_slots.items[idx].?.stat.kind == kind) 1 else 0;
}

fn metadataStatCopy(handle: u64) ?std.fs.File.Stat {
    metadata_mutex.lock();
    defer metadata_mutex.unlock();
    const idx = metadataSlotLocked(handle) orelse return null;
    return metadata_slots.items[idx].?.stat;
}

pub export fn sa_fs_metadata_is_file(handle: u64) u8 {
    return metadataKindIs(handle, .file);
}
pub export fn sa_fs_metadata_is_directory(handle: u64) u8 {
    return metadataKindIs(handle, .directory);
}
pub export fn sa_fs_metadata_is_symlink(handle: u64) u8 {
    return metadataKindIs(handle, .sym_link);
}
pub export fn sa_fs_metadata_is_block_device(handle: u64) u8 {
    return metadataKindIs(handle, .block_device);
}
pub export fn sa_fs_metadata_is_char_device(handle: u64) u8 {
    return metadataKindIs(handle, .character_device);
}
pub export fn sa_fs_metadata_is_fifo(handle: u64) u8 {
    return metadataKindIs(handle, .named_pipe);
}
pub export fn sa_fs_metadata_is_socket(handle: u64) u8 {
    return metadataKindIs(handle, .unix_domain_socket);
}
pub export fn sa_fs_metadata_modified_ms(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| nsToMs(stat.mtime) else 0;
}
pub export fn sa_fs_metadata_created_ms(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| nsToMs(stat.ctime) else 0;
}
pub export fn sa_fs_metadata_accessed_ms(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| nsToMs(stat.atime) else 0;
}
pub export fn sa_fs_metadata_changed_ms(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| nsToMs(stat.ctime) else 0;
}
pub export fn sa_fs_metadata_len(handle: u64) u64 {
    return if (metadataStatCopy(handle)) |stat| stat.size else 0;
}
pub export fn sa_fs_metadata_mode(handle: u64) u32 {
    _ = handle;
    return 0;
}
pub export fn sa_fs_metadata_uid(handle: u64) u32 {
    _ = handle;
    return 0;
}
pub export fn sa_fs_metadata_gid(handle: u64) u32 {
    _ = handle;
    return 0;
}
pub export fn sa_fs_metadata_ino(handle: u64) u64 {
    return if (metadataStatCopy(handle)) |stat| @as(u64, @intCast(stat.inode)) else 0;
}
pub export fn sa_fs_metadata_dev(handle: u64) u64 {
    _ = handle;
    return 0;
}
pub export fn sa_fs_metadata_nlink(handle: u64) u64 {
    _ = handle;
    return 0;
}
pub export fn sa_fs_metadata_rdev(handle: u64) u64 {
    _ = handle;
    return 0;
}
pub export fn sa_fs_metadata_blksize(handle: u64) u64 {
    _ = handle;
    return 0;
}
pub export fn sa_fs_metadata_blocks(handle: u64) u64 {
    _ = handle;
    return 0;
}
pub export fn sa_fs_metadata_st_dev(handle: u64) u64 {
    return sa_fs_metadata_dev(handle);
}
pub export fn sa_fs_metadata_st_ino(handle: u64) u64 {
    return sa_fs_metadata_ino(handle);
}
pub export fn sa_fs_metadata_st_mode(handle: u64) u32 {
    return sa_fs_metadata_mode(handle);
}
pub export fn sa_fs_metadata_st_nlink(handle: u64) u64 {
    return sa_fs_metadata_nlink(handle);
}
pub export fn sa_fs_metadata_st_uid(handle: u64) u32 {
    return sa_fs_metadata_uid(handle);
}
pub export fn sa_fs_metadata_st_gid(handle: u64) u32 {
    return sa_fs_metadata_gid(handle);
}
pub export fn sa_fs_metadata_st_rdev(handle: u64) u64 {
    return sa_fs_metadata_rdev(handle);
}
pub export fn sa_fs_metadata_st_size(handle: u64) u64 {
    return sa_fs_metadata_len(handle);
}
fn metadataSeconds(ns: i128) i64 {
    return @as(i64, @intCast(@divFloor(ns, std.time.ns_per_s)));
}
fn metadataNanoseconds(ns: i128) i64 {
    return @as(i64, @intCast(@mod(ns, std.time.ns_per_s)));
}
pub export fn sa_fs_metadata_st_atime(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataSeconds(stat.atime) else 0;
}
pub export fn sa_fs_metadata_st_atime_nsec(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataNanoseconds(stat.atime) else 0;
}
pub export fn sa_fs_metadata_st_mtime(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataSeconds(stat.mtime) else 0;
}
pub export fn sa_fs_metadata_st_mtime_nsec(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataNanoseconds(stat.mtime) else 0;
}
pub export fn sa_fs_metadata_st_ctime(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataSeconds(stat.ctime) else 0;
}
pub export fn sa_fs_metadata_st_ctime_nsec(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataNanoseconds(stat.ctime) else 0;
}
pub export fn sa_fs_metadata_st_blksize(handle: u64) u64 {
    return sa_fs_metadata_blksize(handle);
}
pub export fn sa_fs_metadata_st_blocks(handle: u64) u64 {
    return sa_fs_metadata_blocks(handle);
}
pub export fn sa_std_fs_metadata_free(handle: u64) i32 {
    return sa_std_close(handle);
}
pub export fn sa_fs_metadata_free(handle: u64) FallibleI32 {
    const status = sa_std_close(handle);
    return if (status == SA_STD_OK) .{ .status = SA_STD_OK, .value = 0 } else .{ .status = status, .value = 0 };
}

pub export fn sa_std_fs_canonicalize(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const bytes = std.fs.cwd().realpathAlloc(std.heap.page_allocator, path) catch |err| return finishErr(err);
    const handle = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_write_file(path_ptr: ?[*]const u8, path_len: u64, buf: ?[*]const u8, len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |err| return finishErr(err);
    defer file.close();
    file.writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_file(path_ptr: ?[*]const u8, path_len: u64) i32 {
    return sa_std_fs_remove(path_ptr, path_len);
}

pub export fn sa_fs_rename(from_path: ?[*]const u8, from_len: u64, to_path: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_path, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_path, to_len) catch |err| return finishErr(err);
    std.fs.cwd().rename(from, to) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_make_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().makePath(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_make_dir_mode(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = mode;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_create_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().makeDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_create_dir_mode(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = mode;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_remove_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_dir_all(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().deleteTree(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_path(path_ptr: ?[*]const u8, path_len: u64) i32 {
    return sa_fs_remove_dir_all(path_ptr, path_len);
}

pub export fn sa_fs_copy_file(from_path: ?[*]const u8, from_len: u64, to_path: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_path, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_path, to_len) catch |err| return finishErr(err);
    std.fs.cwd().copyFile(from, std.fs.cwd(), to, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_set_permissions(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = mode;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_set_times_ms(path_ptr: ?[*]const u8, path_len: u64, accessed_ms: i64, modified_ms: i64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch |err| return finishErr(err);
    defer file.close();
    const accessed_ns = std.math.mul(i128, accessed_ms, std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const modified_ns = std.math.mul(i128, modified_ms, std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const accessed = std.os.windows.nanoSecondsToFileTime(accessed_ns);
    const modified = std.os.windows.nanoSecondsToFileTime(modified_ns);
    std.os.windows.SetFileTime(file.handle, null, &accessed, &modified) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_hard_link(from_path: ?[*]const u8, from_len: u64, to_path: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_path, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_path, to_len) catch |err| return finishErr(err);
    const from_w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, from) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(from_w);
    const to_w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, to) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(to_w);
    if (CreateHardLinkW(to_w.ptr, from_w.ptr, null) == 0) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_symlink(target_path: ?[*]const u8, target_len: u64, link_path: ?[*]const u8, link_len: u64) i32 {
    const target = pathBytes(target_path, target_len) catch |err| return finishErr(err);
    const link = pathBytes(link_path, link_len) catch |err| return finishErr(err);
    std.fs.cwd().symLink(target, link, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_chown(path_ptr: ?[*]const u8, path_len: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = uid;
    _ = gid;
    _ = has_uid;
    _ = has_gid;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_lchown(path_ptr: ?[*]const u8, path_len: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = uid;
    _ = gid;
    _ = has_uid;
    _ = has_gid;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_fchown(handle: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32) i32 {
    _ = handle;
    _ = uid;
    _ = gid;
    _ = has_uid;
    _ = has_gid;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_chroot(path_ptr: ?[*]const u8, path_len: u64) i32 {
    _ = path_ptr;
    _ = path_len;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_mkfifo(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = mode;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fs_read_link(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    var stack_buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = std.fs.cwd().readLink(path, stack_buf[0..]) catch |err| return finishErr(err);
    const bytes = std.heap.page_allocator.dupe(u8, target) catch |err| return finishErr(err);
    const handle = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_read_buffer_data(handle: u64) ?[*]u8 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const idx = bufferSlot(handle) orelse return null;
    return buffers.items[idx].?.bytes.ptr;
}

pub export fn sa_fs_read_buffer_len(handle: u64) u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const idx = bufferSlot(handle) orelse return 0;
    return @as(u64, @intCast(buffers.items[idx].?.bytes.len));
}

pub export fn sa_fs_read_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_read_file_base64(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) FallibleU64 {
    const result = sa_fs_read_file(path_ptr, path_len, max_bytes);
    if (result.status != SA_STD_OK) return result;

    registry_mutex.lock();
    const idx = bufferSlot(result.value) orelse {
        registry_mutex.unlock();
        return failU64(SA_STD_ERR_INVALID_HANDLE);
    };
    const bytes = buffers.items[idx].?.bytes;
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = std.heap.page_allocator.alloc(u8, encoded_len) catch {
        registry_mutex.unlock();
        _ = sa_std_close(result.value);
        return failU64(SA_STD_ERR_NO_MEMORY);
    };
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    registry_mutex.unlock();
    _ = sa_std_close(result.value);

    const handle = openOwnedByteBuffer(encoded) catch |err| {
        std.heap.page_allocator.free(encoded);
        return failU64(mapError(err));
    };
    return okU64(handle);
}

pub export fn sa_std_fs_read_file_base64(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_read_file_base64(path_ptr, path_len, max_bytes);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_write_file_base64(path_ptr: ?[*]const u8, path_len: u64, encoded_ptr: ?[*]const u8, encoded_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const encoded = constBytes(encoded_ptr, encoded_len) catch |err| return finishErr(err);
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const decoded = std.heap.page_allocator.alloc(u8, decoded_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, encoded) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |err| return finishErr(err);
    defer file.close();
    file.writeAll(decoded) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fmt_i64(value: i64, base: u32) u64 {
    const bytes = formatInteger(value, base) catch return 0;
    return openOwnedByteBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_i64_into(value: i64, base: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrintIntToSlice(&buf, value, actual_base, case, .{});
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_u64(value: u64, base: u32) u64 {
    const bytes = formatInteger(value, base) catch return 0;
    return openOwnedByteBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_u64_into(value: u64, base: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrintIntToSlice(&buf, value, actual_base, case, .{});
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_f64(value: f64, precision: u32) u64 {
    const bytes = formatFloat(value, precision) catch return 0;
    return openOwnedByteBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_f64_into(value: f64, precision: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    var buf: [256]u8 = undefined;
    const text = std.fmt.formatFloat(&buf, value, .{ .mode = .decimal, .precision = @as(usize, @intCast(precision)) }) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_bool(value: bool) u64 {
    const bytes = formatBool(value) catch return 0;
    return openOwnedByteBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_bool_into(value: bool, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    return writeFormattedInto(out, out_cap, out_len, if (value) "true" else "false");
}

pub export fn sa_fmt_bytes(buf: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(buf, len) catch return 0;
    const owned = formatBytes(bytes) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_fmt_bytes_into(buf: ?[*]const u8, len: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    return writeFormattedInto(out, out_cap, out_len, bytes);
}

pub export fn sa_fmt_buffer_data(buffer: u64) ?[*]u8 {
    return sa_fs_read_buffer_data(buffer);
}

pub export fn sa_fmt_buffer_len(buffer: u64) u64 {
    return sa_fs_read_buffer_len(buffer);
}

pub export fn sa_fmt_buffer_write_to(buffer: u64, writer: u64) i32 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const idx = bufferSlot(buffer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const bytes = buffers.items[idx].?.bytes;
    const written = writeHandle(writer, bytes) catch |err| return finishErr(err);
    if (written != bytes.len) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_fmt_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_string_concat(left_ptr: ?[*]const u8, left_len: u64, right_ptr: ?[*]const u8, right_len: u64) u64 {
    const left = constBytes(left_ptr, left_len) catch return 0;
    const right = constBytes(right_ptr, right_len) catch return 0;
    const owned = stringConcat(left, right) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_str_is_ascii(ptr: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(ptr, len) catch return 0;
    for (bytes) |byte| {
        if (byte > 0x7f) return 0;
    }
    return 1;
}

pub export fn sa_str_eq_ignore_ascii_case(left_ptr: ?[*]const u8, left_len: u64, right_ptr: ?[*]const u8, right_len: u64) i32 {
    const left = constBytes(left_ptr, left_len) catch return 0;
    const right = constBytes(right_ptr, right_len) catch return 0;
    if (left.len != right.len) return 0;
    return if (std.ascii.eqlIgnoreCase(left, right)) 1 else 0;
}

pub export fn sa_str_utf8_char_count(ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    var byte_index: usize = 0;
    var count: u64 = 0;
    while (byte_index < bytes.len) {
        const decoded = utf8ScalarAt(bytes, byte_index) catch return 0;
        byte_index += decoded.width;
        count += 1;
    }
    return count;
}

pub export fn sa_str_utf8_validate(ptr: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(ptr, len) catch |err| return finishErr(err);
    var byte_index: usize = 0;
    while (byte_index < bytes.len) {
        const decoded = utf8ScalarAt(bytes, byte_index) catch |err| return finishErr(err);
        byte_index += decoded.width;
    }
    return finish(SA_STD_OK);
}

pub export fn sa_str_utf8_char_at(ptr: ?[*]const u8, len: u64, char_index: u64, out_codepoint: ?*u64) i32 {
    const out = out_codepoint orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const bytes = constBytes(ptr, len) catch |err| return finishErr(err);
    const range = utf8CharRangeAt(bytes, char_index) catch |err| return finishErr(err);
    out.* = range.scalar;
    return finish(SA_STD_OK);
}

pub export fn sa_str_utf8_char_at_byte(ptr: ?[*]const u8, len: u64, byte_index: u64, out_codepoint: ?*u64, out_len: ?*u64) i32 {
    const codepoint_ptr = out_codepoint orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    codepoint_ptr.* = 0;
    len_ptr.* = 0;
    const bytes = constBytes(ptr, len) catch |err| return finishErr(err);
    if (byte_index > std.math.maxInt(usize)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const decoded = utf8ScalarAt(bytes, @as(usize, @intCast(byte_index))) catch |err| return finishErr(err);
    codepoint_ptr.* = decoded.scalar;
    len_ptr.* = @as(u64, @intCast(decoded.width));
    return finish(SA_STD_OK);
}

pub export fn sa_str_utf8_lossy_next(ptr: ?[*]const u8, len: u64, byte_index: u64, out_codepoint: ?*u64, out_len: ?*u64) i32 {
    const codepoint_ptr = out_codepoint orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    codepoint_ptr.* = 0;
    len_ptr.* = 0;
    const bytes = constBytes(ptr, len) catch |err| return finishErr(err);
    if (byte_index > std.math.maxInt(usize)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const idx: usize = @intCast(byte_index);
    if (idx >= bytes.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const decoded = utf8ScalarAt(bytes, idx) catch {
        codepoint_ptr.* = 65533;
        len_ptr.* = @as(u64, @intCast(utf8LossyInvalidWidth(bytes, idx)));
        return finish(SA_STD_OK);
    };
    codepoint_ptr.* = decoded.scalar;
    len_ptr.* = @as(u64, @intCast(decoded.width));
    return finish(SA_STD_OK);
}

pub export fn sa_str_utf8_char_range_at(ptr: ?[*]const u8, len: u64, char_index: u64, out_start: ?*u64, out_len: ?*u64) i32 {
    const start_ptr = out_start orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    start_ptr.* = 0;
    len_ptr.* = 0;
    const bytes = constBytes(ptr, len) catch |err| return finishErr(err);
    const range = utf8CharRangeAt(bytes, char_index) catch |err| return finishErr(err);
    start_ptr.* = @as(u64, @intCast(range.start));
    len_ptr.* = @as(u64, @intCast(range.len));
    return finish(SA_STD_OK);
}

pub export fn sa_str_trim_ascii_start_index(ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    var index: usize = 0;
    while (index < bytes.len and isAsciiWhitespace(bytes[index])) : (index += 1) {}
    return @as(u64, @intCast(index));
}

pub export fn sa_str_trim_ascii_end_len(ptr: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(ptr, len) catch return 0;
    var end = bytes.len;
    while (end > 0 and isAsciiWhitespace(bytes[end - 1])) : (end -= 1) {}
    return @as(u64, @intCast(end));
}

pub export fn sa_time_instant_ns() u64 {
    return monotonicNowNs() catch return 0;
}

pub export fn sa_time_unix_s() i64 {
    return std.time.timestamp();
}

pub export fn sa_time_unix_ms() i64 {
    return std.time.milliTimestamp();
}

pub export fn sa_time_unix_ns() i64 {
    const ts = std.time.nanoTimestamp();
    return @as(i64, @intCast(ts));
}

pub export fn sa_time_utc_now(out_date: ?*TimeDate) i32 {
    const ptr = out_date orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fillUtcNow(ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_time_sleep_ns(ns: u64) i32 {
    std.Thread.sleep(ns);
    return finish(SA_STD_OK);
}

pub export fn sa_time_sleep_ms(ms: u64) i32 {
    const ns = std.math.mul(u64, ms, std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return sa_time_sleep_ns(ns);
}

pub export fn sa_thread_current_id() u64 {
    return @as(u64, @intCast(std.Thread.getCurrentId()));
}

pub export fn sa_thread_yield_now() i32 {
    std.Thread.yield() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_thread_as_pthread_t(handle: i32, out_raw: ?*u64) i32 {
    _ = handle;
    const raw_ptr = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    raw_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_thread_into_pthread_t(handle: i32, out_raw: ?*u64) i32 {
    return sa_thread_as_pthread_t(handle, out_raw);
}

pub export fn sa_thread_raw_pthread_join(raw: u64, out: ?*u8) i32 {
    _ = raw;
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_id() u32 {
    return std.os.windows.GetCurrentProcessId();
}

pub export fn sa_json_parse(json_bytes: ?[*]const u8, len: u64) u64 {
    const input = constBytes(json_bytes, len) catch return 0;
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{}) catch return 0;
    const document = std.heap.page_allocator.create(JsonDocument) catch {
        parsed.deinit();
        return 0;
    };
    document.* = .{ .parsed = parsed };
    return registerJsonNode(document, parsed.value, false) catch return 0;
}

pub export fn sa_json_kind(handle: u64) u32 {
    const node = acquireJsonNode(handle) catch return SA_JSON_KIND_INVALID;
    defer node.release();
    return jsonKind(node.value);
}

pub export fn sa_json_object_get(handle: u64, key_ptr: ?[*]const u8, key_len: u64, out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    const value = jsonObjectValue(node, key) catch |err| return finishErr(err);
    output.* = registerJsonNode(node.document, value, true) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_array_get(handle: u64, index: u64, out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    const value = switch (node.value) {
        .array => |array| blk: {
            const idx = std.math.cast(usize, index) orelse return finish(SA_STD_ERR_NOT_FOUND);
            if (idx >= array.items.len) return finish(SA_STD_ERR_NOT_FOUND);
            break :blk array.items[idx];
        },
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    output.* = registerJsonNode(node.document, value, true) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_key_at(handle: u64, index: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = null;
    len_slot.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    const object = switch (node.value) {
        .object => |value| value,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    const idx = std.math.cast(usize, index) orelse return finish(SA_STD_ERR_NOT_FOUND);
    if (idx >= object.count()) return finish(SA_STD_ERR_NOT_FOUND);
    var iterator = object.iterator();
    var current: usize = 0;
    while (iterator.next()) |entry| : (current += 1) {
        if (current != idx) continue;
        ptr_slot.* = entry.key_ptr.*.ptr;
        len_slot.* = @as(u64, @intCast(entry.key_ptr.*.len));
        return finish(SA_STD_OK);
    }
    return finish(SA_STD_ERR_NOT_FOUND);
}

pub export fn sa_json_object_get_string(handle: u64, key_ptr: ?[*]const u8, key_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = null;
    len_slot.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    const value = jsonObjectValue(node, key) catch |err| return finishErr(err);
    const text_value = jsonText(value) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = text_value.ptr;
    len_slot.* = @as(u64, @intCast(text_value.len));
    return finish(SA_STD_OK);
}

fn jsonObjectTyped(handle: u64, key_ptr: ?[*]const u8, key_len: u64) !JsonNode {
    const key = try constBytes(key_ptr, key_len);
    if (key.len == 0) return error.InvalidArgument;
    const node = try acquireJsonNode(handle);
    errdefer node.release();
    return .{ .document = node.document, .value = try jsonObjectValue(node, key) };
}

pub export fn sa_json_object_get_bool(handle: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*u8) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = jsonObjectTyped(handle, key_ptr, key_len) catch |err| return finishErr(err);
    defer node.release();
    output.* = if (jsonAsBool(node.value) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_i64(handle: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*i64) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = jsonObjectTyped(handle, key_ptr, key_len) catch |err| return finishErr(err);
    defer node.release();
    output.* = jsonAsI64(node.value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_f64(handle: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*f64) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = jsonObjectTyped(handle, key_ptr, key_len) catch |err| return finishErr(err);
    defer node.release();
    output.* = jsonAsF64(node.value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_f64(handle: u64, out_value: ?*f64) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    output.* = jsonAsF64(node.value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_i64(handle: u64, out_value: ?*i64) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    output.* = jsonAsI64(node.value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_bool(handle: u64, out_value: ?*u8) i32 {
    const output = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    output.* = if (jsonAsBool(node.value) catch |err| return finishErr(err)) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_string_ptr(handle: u64) ?[*]const u8 {
    const node = acquireJsonNode(handle) catch return null;
    defer node.release();
    return if (jsonText(node.value)) |value| value.ptr else null;
}

pub export fn sa_json_string_len(handle: u64) u64 {
    const node = acquireJsonNode(handle) catch return 0;
    defer node.release();
    return if (jsonText(node.value)) |value| @as(u64, @intCast(value.len)) else 0;
}

pub export fn sa_json_value_count(handle: u64, out_count: ?*u64) i32 {
    const output = out_count orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    output.* = switch (node.value) {
        .array => |array| @as(u64, @intCast(array.items.len)),
        .object => |object| @as(u64, @intCast(object.count())),
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    return finish(SA_STD_OK);
}

pub export fn sa_json_free(handle: u64) i32 {
    return closeJsonHandle(handle);
}

pub export fn sa_json_stringify(handle: u64, out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    const bytes = std.json.stringifyAlloc(std.heap.page_allocator, node.value, .{}) catch |err| return finishErr(err);
    output.* = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_json_buffer_data(handle: u64) ?[*]u8 {
    return sa_env_buffer_data(handle);
}

pub export fn sa_json_buffer_len(handle: u64) u64 {
    return sa_env_buffer_len(handle);
}

pub export fn sa_json_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_json_writer_new(whitespace: u32, emit_null_optional_fields: u8, emit_strings_as_arrays: u8, escape_unicode: u8, emit_nonportable_numbers_as_strings: u8, out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const options: std.json.StringifyOptions = .{
        .whitespace = switch (whitespace) {
            SA_JSON_WHITESPACE_MINIFIED => .minified,
            SA_JSON_WHITESPACE_INDENT_1 => .indent_1,
            SA_JSON_WHITESPACE_INDENT_2 => .indent_2,
            SA_JSON_WHITESPACE_INDENT_3 => .indent_3,
            SA_JSON_WHITESPACE_INDENT_4 => .indent_4,
            SA_JSON_WHITESPACE_INDENT_8 => .indent_8,
            SA_JSON_WHITESPACE_INDENT_TAB => .indent_tab,
            else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
        },
        .emit_null_optional_fields = emit_null_optional_fields != 0,
        .emit_strings_as_arrays = emit_strings_as_arrays != 0,
        .escape_unicode = escape_unicode != 0,
        .emit_nonportable_numbers_as_strings = emit_nonportable_numbers_as_strings != 0,
    };
    const writer = JsonWriter.create(options) catch |err| return finishErr(err);
    output.* = registerJsonWriter(writer) catch |err| {
        writer.destroy();
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_begin_object(handle: u64) i32 {
    json_writer_mutex.lock();
    defer json_writer_mutex.unlock();
    const writer = writerForValue(handle) catch |err| return finishErr(err);
    writer.stream.beginObject() catch |err| return finishErr(err);
    writer.depth += 1;
    writer.started = true;
    writer.complete = false;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_end_object(handle: u64) i32 {
    json_writer_mutex.lock();
    defer json_writer_mutex.unlock();
    const idx = jsonWriterSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer = json_writer_slots.items[idx].?;
    if (writer.finished) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer.depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer.stream.endObject() catch |err| return finishErr(err);
    writer.depth -= 1;
    writer.complete = writer.depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_begin_array(handle: u64) i32 {
    json_writer_mutex.lock();
    defer json_writer_mutex.unlock();
    const writer = writerForValue(handle) catch |err| return finishErr(err);
    writer.stream.beginArray() catch |err| return finishErr(err);
    writer.depth += 1;
    writer.started = true;
    writer.complete = false;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_end_array(handle: u64) i32 {
    json_writer_mutex.lock();
    defer json_writer_mutex.unlock();
    const idx = jsonWriterSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer = json_writer_slots.items[idx].?;
    if (writer.finished) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer.depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer.stream.endArray() catch |err| return finishErr(err);
    writer.depth -= 1;
    writer.complete = writer.depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_object_field(handle: u64, key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    json_writer_mutex.lock();
    defer json_writer_mutex.unlock();
    const writer = writerForValue(handle) catch |err| return finishErr(err);
    writerField(writer, key) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

fn writerFieldScalar(handle: u64, key: []const u8, value: anytype) i32 {
    json_writer_mutex.lock();
    defer json_writer_mutex.unlock();
    const writer = writerForValue(handle) catch |err| return finishErr(err);
    writerField(writer, key) catch |err| return finishErr(err);
    writer.stream.write(value) catch |err| return finishErr(err);
    markWriterValue(writer);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_string(handle: u64, key_ptr: ?[*]const u8, key_len: u64, data_ptr: ?[*]const u8, len: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const value = constBytes(data_ptr, len) catch |err| return finishErr(err);
    return writerFieldScalar(handle, key, value);
}

pub export fn sa_json_writer_field_bool(handle: u64, key_ptr: ?[*]const u8, key_len: u64, value: u8) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    return writerFieldScalar(handle, key, value != 0);
}

pub export fn sa_json_writer_field_i64(handle: u64, key_ptr: ?[*]const u8, key_len: u64, value: i64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    return writerFieldScalar(handle, key, value);
}

pub export fn sa_json_writer_field_f64(handle: u64, key_ptr: ?[*]const u8, key_len: u64, value: f64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    return writerFieldScalar(handle, key, value);
}

pub export fn sa_json_writer_field_null(handle: u64, key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    return writerFieldScalar(handle, key, null);
}

pub export fn sa_json_writer_field_node(handle: u64, key_ptr: ?[*]const u8, key_len: u64, node_handle: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const node = acquireJsonNode(node_handle) catch |err| return finishErr(err);
    defer node.release();
    return writerFieldScalar(handle, key, node.value);
}

fn writerScalar(handle: u64, value: anytype) i32 {
    json_writer_mutex.lock();
    defer json_writer_mutex.unlock();
    const writer = writerForValue(handle) catch |err| return finishErr(err);
    writer.stream.write(value) catch |err| return finishErr(err);
    markWriterValue(writer);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_bool(handle: u64, value: u8) i32 {
    return writerScalar(handle, value != 0);
}

pub export fn sa_json_writer_write_i64(handle: u64, value: i64) i32 {
    return writerScalar(handle, value);
}

pub export fn sa_json_writer_write_f64(handle: u64, value: f64) i32 {
    return writerScalar(handle, value);
}

pub export fn sa_json_writer_write_string(handle: u64, data_ptr: ?[*]const u8, len: u64) i32 {
    const value = constBytes(data_ptr, len) catch |err| return finishErr(err);
    return writerScalar(handle, value);
}

pub export fn sa_json_writer_write_null(handle: u64) i32 {
    return writerScalar(handle, null);
}

pub export fn sa_json_writer_write_node(handle: u64, node_handle: u64) i32 {
    const node = acquireJsonNode(node_handle) catch |err| return finishErr(err);
    defer node.release();
    return writerScalar(handle, node.value);
}

pub export fn sa_json_writer_finish(handle: u64, out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    json_writer_mutex.lock();
    const idx = jsonWriterSlotLocked(handle) orelse {
        json_writer_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const writer = json_writer_slots.items[idx].?;
    if (writer.finished) {
        json_writer_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    }
    if (!writer.started or !writer.complete or writer.depth != 0) {
        json_writer_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_ARGUMENT);
    }
    const bytes = writer.buffer.toOwnedSlice() catch |err| {
        json_writer_mutex.unlock();
        return finishErr(err);
    };
    writer.finished = true;
    json_writer_mutex.unlock();
    output.* = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_finish_buffer(handle: u64) u64 {
    var output: u64 = 0;
    if (sa_json_writer_finish(handle, &output) != SA_STD_OK) return 0;
    return output;
}

pub export fn sa_json_writer_free(handle: u64) i32 {
    return closeJsonWriter(handle);
}

pub export fn sa_json_scanner_new(out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const tokenizer = JsonTokenizer.createStreaming() catch |err| return finishErr(err);
    output.* = registerTokenizer(tokenizer) catch |err| {
        tokenizer.destroy();
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_feed(handle: u64, input_ptr: ?[*]const u8, len: u64) i32 {
    const input = constBytes(input_ptr, len) catch |err| return finishErr(err);
    json_tokenizer_mutex.lock();
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (tokenizer.is_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (tokenizer.input.len != 0) {
        if (tokenizer.scanner.cursor != tokenizer.scanner.input.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
        std.heap.page_allocator.free(tokenizer.input);
        tokenizer.input = &.{};
    }
    tokenizer.input = std.heap.page_allocator.dupe(u8, input) catch |err| return finishErr(err);
    tokenizer.scanner.feedInput(tokenizer.input);
    tokenizer.current_text = null;
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_end_input(handle: u64) i32 {
    json_tokenizer_mutex.lock();
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (tokenizer.is_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    tokenizer.scanner.endInput();
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_next(handle: u64, out_token: ?*SaJsonToken) i32 {
    const output = out_token orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = .{ .kind = SA_JSON_TOKEN_INVALID, .text_ptr = null, .text_len = 0 };
    json_tokenizer_mutex.lock();
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (tokenizer.is_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    const token = tokenizer.scanner.next() catch |err| switch (err) {
        error.BufferUnderrun => return finish(SA_STD_ERR_TRUNCATED),
        else => return finishErr(err),
    };
    setTokenizerText(tokenizer, token) catch |err| return finishErr(err);
    output.kind = jsonTokenKind(token);
    if (tokenizer.current_text) |text_value| {
        output.text_ptr = text_value.ptr;
        output.text_len = @as(u64, @intCast(text_value.len));
    }
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_free(handle: u64) i32 {
    return closeTokenizer(handle);
}

pub export fn sa_json_stream_new(json_bytes: ?[*]const u8, len: u64) u64 {
    const input = constBytes(json_bytes, len) catch return 0;
    const tokenizer = JsonTokenizer.createComplete(input) catch return 0;
    return registerTokenizer(tokenizer) catch {
        tokenizer.destroy();
        return 0;
    };
}

pub export fn sa_json_stream_next(handle: u64) u32 {
    json_tokenizer_mutex.lock();
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return SA_JSON_TOKEN_INVALID;
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (!tokenizer.is_stream) return SA_JSON_TOKEN_INVALID;
    const token = tokenizer.scanner.next() catch return SA_JSON_TOKEN_INVALID;
    setTokenizerText(tokenizer, token) catch return SA_JSON_TOKEN_INVALID;
    return jsonTokenKind(token);
}

pub export fn sa_json_stream_get_slice_ptr(handle: u64) ?[*]const u8 {
    json_tokenizer_mutex.lock();
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return null;
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (!tokenizer.is_stream) return null;
    return if (tokenizer.current_text) |text_value| text_value.ptr else null;
}

pub export fn sa_json_stream_get_slice_len(handle: u64) u64 {
    json_tokenizer_mutex.lock();
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return 0;
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (!tokenizer.is_stream) return 0;
    return if (tokenizer.current_text) |text_value| @as(u64, @intCast(text_value.len)) else 0;
}

pub export fn sa_json_stream_free(handle: u64) i32 {
    return closeTokenizer(handle);
}

pub export fn sa_std_process_run(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    handle_ptr.* = spawnProcess(argv_ptr, argv_len, .capture) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    handle_ptr.* = spawnProcessCwd(argv_ptr, argv_len, .capture, cwd) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    handle_ptr.* = spawnProcess(argv_ptr, argv_len, .inherit) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    handle_ptr.* = spawnProcessCwd(argv_ptr, argv_len, .inherit, cwd) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    spawnStreamProcess(argv_ptr, argv_len, process_ptr, stdout_ptr, stderr_ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    spawnStreamProcessCwd(argv_ptr, argv_len, cwd, process_ptr, stdout_ptr, stderr_ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

fn commandExtSupported(has_arg0: u32, has_process_group: u32, setsid: u32) bool {
    return has_arg0 == 0 and has_process_group == 0 and setsid == 0;
}

pub export fn sa_std_process_run_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_handle: ?*u64) i32 {
    _ = arg0_ptr;
    _ = arg0_len;
    _ = process_group;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (!commandExtSupported(has_arg0, has_process_group, setsid)) return finish(SA_STD_ERR_UNSUPPORTED);
    if (has_cwd != 0) return sa_std_process_run_cwd(argv_ptr, argv_len, cwd_ptr, cwd_len, handle_ptr);
    return sa_std_process_run(argv_ptr, argv_len, handle_ptr);
}

pub export fn sa_std_process_spawn_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_handle: ?*u64) i32 {
    _ = arg0_ptr;
    _ = arg0_len;
    _ = process_group;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (!commandExtSupported(has_arg0, has_process_group, setsid)) return finish(SA_STD_ERR_UNSUPPORTED);
    if (has_cwd != 0) return sa_std_process_spawn_cwd(argv_ptr, argv_len, cwd_ptr, cwd_len, handle_ptr);
    return sa_std_process_spawn(argv_ptr, argv_len, handle_ptr);
}

pub export fn sa_std_process_spawn_stream_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    _ = arg0_ptr;
    _ = arg0_len;
    _ = process_group;
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    if (!commandExtSupported(has_arg0, has_process_group, setsid)) return finish(SA_STD_ERR_UNSUPPORTED);
    if (has_cwd != 0) return sa_std_process_spawn_stream_cwd(argv_ptr, argv_len, cwd_ptr, cwd_len, process_ptr, stdout_ptr, stderr_ptr);
    return sa_std_process_spawn_stream(argv_ptr, argv_len, process_ptr, stdout_ptr, stderr_ptr);
}

pub export fn sa_std_process_child_id(handle: u64, out_pid: ?*u32) i32 {
    const pid_ptr = out_pid orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pid_ptr.* = 0;
    process_mutex.lock();
    defer process_mutex.unlock();
    const idx = processSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    pid_ptr.* = process_slots.items[idx].?.pid;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_wait(handle: u64, out_code: ?*u32) i32 {
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    process_mutex.lock();
    defer process_mutex.unlock();
    const idx = processSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = process_slots.items[idx].?;
    resource.finishWait() catch |err| return finishErr(err);
    code_ptr.* = resource.code;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_try_wait(handle: u64, out_ready: ?*i32, out_code: ?*u32) i32 {
    const ready_ptr = out_ready orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ready_ptr.* = 0;
    code_ptr.* = 0;
    process_mutex.lock();
    defer process_mutex.unlock();
    const idx = processSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = process_slots.items[idx].?;
    if (!resource.exited) {
        std.os.windows.WaitForSingleObjectEx(resource.child.id, 0, false) catch |err| switch (err) {
            error.WaitTimeOut => return finish(SA_STD_OK),
            else => return finishErr(err),
        };
        resource.finishWait() catch |err| return finishErr(err);
    }
    ready_ptr.* = 1;
    code_ptr.* = resource.code;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_kill(handle: u64) i32 {
    process_mutex.lock();
    defer process_mutex.unlock();
    const idx = processSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = process_slots.items[idx].?;
    if (!resource.exited) {
        resource.code = processTermCode(resource.child.kill() catch |err| switch (err) {
            error.AlreadyTerminated => resource.child.wait() catch |wait_err| return finishErr(wait_err),
            else => return finishErr(err),
        });
        resource.exited = true;
    }
    return finish(SA_STD_OK);
}

fn readCapturedProcess(handle: u64, use_stderr: bool, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const output = mutBytes(out, out_cap) catch |err| return finishErr(err);
    process_mutex.lock();
    defer process_mutex.unlock();
    const idx = processSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = process_slots.items[idx].?;
    if (resource.mode != .capture or !resource.exited) return finish(SA_STD_ERR_INVALID_HANDLE);
    const source = if (use_stderr) resource.stderr_buf else resource.stdout_buf;
    const pos = if (use_stderr) &resource.stderr_pos else &resource.stdout_pos;
    const copy_len = @min(output.len, source.len - @min(pos.*, source.len));
    if (copy_len != 0) @memcpy(output[0..copy_len], source[pos.* .. pos.* + copy_len]);
    pos.* += copy_len;
    if (out_read) |ptr| ptr.* = @as(u64, @intCast(copy_len));
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_read_stdout(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return readCapturedProcess(handle, false, out, out_cap, out_read);
}

pub export fn sa_std_process_read_stderr(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return readCapturedProcess(handle, true, out, out_cap, out_read);
}

pub export fn sa_std_process_exec_capture(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    var process: u64 = 0;
    var status = sa_std_process_run(argv_ptr, argv_len, &process);
    if (status != SA_STD_OK) return status;
    defer _ = closeProcessHandle(process);
    status = sa_std_process_wait(process, code_ptr);
    if (status != SA_STD_OK) return status;

    process_mutex.lock();
    const idx = processSlotLocked(process) orelse {
        process_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const resource = process_slots.items[idx].?;
    const stdout_owned = std.heap.page_allocator.dupe(u8, resource.stdout_buf) catch |err| {
        process_mutex.unlock();
        return finishErr(err);
    };
    const stderr_owned = std.heap.page_allocator.dupe(u8, resource.stderr_buf) catch |err| {
        std.heap.page_allocator.free(stdout_owned);
        process_mutex.unlock();
        return finishErr(err);
    };
    process_mutex.unlock();
    stdout_ptr.* = registerBuffer(stdout_owned) catch |err| {
        std.heap.page_allocator.free(stdout_owned);
        std.heap.page_allocator.free(stderr_owned);
        return finishErr(err);
    };
    stderr_ptr.* = registerBuffer(stderr_owned) catch |err| {
        _ = sa_std_close(stdout_ptr.*);
        stdout_ptr.* = 0;
        std.heap.page_allocator.free(stderr_owned);
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_exec_capture_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    var process: u64 = 0;
    var status = sa_std_process_run_cwd(argv_ptr, argv_len, cwd_ptr, cwd_len, &process);
    if (status != SA_STD_OK) return status;
    defer _ = closeProcessHandle(process);
    status = sa_std_process_wait(process, code_ptr);
    if (status != SA_STD_OK) return status;

    process_mutex.lock();
    const idx = processSlotLocked(process) orelse {
        process_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const resource = process_slots.items[idx].?;
    const stdout_owned = std.heap.page_allocator.dupe(u8, resource.stdout_buf) catch |err| {
        process_mutex.unlock();
        return finishErr(err);
    };
    const stderr_owned = std.heap.page_allocator.dupe(u8, resource.stderr_buf) catch |err| {
        std.heap.page_allocator.free(stdout_owned);
        process_mutex.unlock();
        return finishErr(err);
    };
    process_mutex.unlock();
    stdout_ptr.* = registerBuffer(stdout_owned) catch |err| {
        std.heap.page_allocator.free(stdout_owned);
        std.heap.page_allocator.free(stderr_owned);
        return finishErr(err);
    };
    stderr_ptr.* = registerBuffer(stderr_owned) catch |err| {
        _ = sa_std_close(stdout_ptr.*);
        stdout_ptr.* = 0;
        std.heap.page_allocator.free(stderr_owned);
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

fn readStreamHandle(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const output = mutBytes(out, out_cap) catch |err| return finishErr(err);
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = stream_slots.items[idx].?.file.read(output) catch |err| return finishErr(err);
    if (out_read) |ptr| ptr.* = @as(u64, @intCast(count));
    return finish(SA_STD_OK);
}

pub export fn sa_std_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    if (handle == SA_STD_STDIN) {
        const output = mutBytes(out, out_cap) catch |err| return finishErr(err);
        const count = std.io.getStdIn().read(output) catch |err| return finishErr(err);
        if (out_read) |ptr| ptr.* = @as(u64, @intCast(count));
        return finish(SA_STD_OK);
    }
    if ((handle & tagged_handle_mask) == stream_handle_tag) return readStreamHandle(handle, out, out_cap, out_read);
    return finish(SA_STD_ERR_INVALID_HANDLE);
}

pub export fn sa_io_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return sa_std_read(handle, out, out_cap, out_read);
}

pub export fn sa_io_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 {
    const output = mutBytes(out, len) catch |err| return finishErr(err);
    if (handle == SA_STD_STDIN) {
        const count = std.io.getStdIn().readAll(output) catch |err| return finishErr(err);
        return finish(if (count == output.len) SA_STD_OK else SA_STD_ERR_IO);
    }
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = stream_slots.items[idx].?.file.readAll(output) catch |err| return finishErr(err);
    return finish(if (count == output.len) SA_STD_OK else SA_STD_ERR_IO);
}

pub export fn sa_std_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    if (out_written) |ptr| ptr.* = 0;
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    if (handle == SA_STD_STDOUT or handle == SA_STD_STDERR) {
        const count = writeHandle(handle, bytes) catch |err| return finishErr(err);
        if (out_written) |ptr| ptr.* = @as(u64, @intCast(count));
        return finish(SA_STD_OK);
    }
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = stream_slots.items[idx].?.file.write(bytes) catch |err| return finishErr(err);
    if (out_written) |ptr| ptr.* = @as(u64, @intCast(count));
    return finish(SA_STD_OK);
}

pub export fn sa_io_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    return sa_std_write(handle, data, len, out_written);
}

pub export fn sa_io_write_all(handle: u64, data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    if (handle == SA_STD_STDOUT or handle == SA_STD_STDERR) {
        const writer = if (handle == SA_STD_STDOUT) std.io.getStdOut() else std.io.getStdErr();
        writer.writeAll(bytes) catch |err| return finishErr(err);
        return finish(SA_STD_OK);
    }
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    stream_slots.items[idx].?.file.writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_io_flush(handle: u64) i32 {
    if (handle == SA_STD_STDOUT or handle == SA_STD_STDERR) return finish(SA_STD_OK);
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = stream_slots.items[idx].?;
    if (resource.kind != .file) return finish(SA_STD_OK);
    resource.file.sync() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

fn fileSlotLocked(handle: u64) ?usize {
    const idx = streamSlotLocked(handle) orelse return null;
    if (stream_slots.items[idx].?.kind != .file) return null;
    return idx;
}

pub export fn sa_std_fs_file_read(handle: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    return sa_std_read(handle, out, cap, out_read);
}

pub export fn sa_fs_file_read(handle: u64, out: ?[*]u8, cap: u64) i32 {
    return sa_std_read(handle, out, cap, null);
}

pub export fn sa_std_fs_file_read_at(handle: u64, out: ?[*]u8, cap: u64, offset: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const output = mutBytes(out, cap) catch |err| return finishErr(err);
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = stream_slots.items[idx].?.file.pread(output, offset) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(count));
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_file_read_exact_at(handle: u64, out: ?[*]u8, len: u64, offset: u64) i32 {
    const output = mutBytes(out, len) catch |err| return finishErr(err);
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = stream_slots.items[idx].?.file.preadAll(output, offset) catch |err| return finishErr(err);
    return finish(if (count == output.len) SA_STD_OK else SA_STD_ERR_TRUNCATED);
}

pub export fn sa_fs_file_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 {
    return sa_io_read_exact(handle, out, len);
}

pub export fn sa_std_fs_file_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    return sa_std_write(handle, data, len, out_written);
}

pub export fn sa_std_fs_file_write_at(handle: u64, data: ?[*]const u8, len: u64, offset: u64, out_written: ?*u64) i32 {
    if (out_written) |ptr| ptr.* = 0;
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = stream_slots.items[idx].?.file.pwrite(bytes, offset) catch |err| return finishErr(err);
    written_ptr.* = @as(u64, @intCast(count));
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_file_write_all_at(handle: u64, data: ?[*]const u8, len: u64, offset: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    stream_slots.items[idx].?.file.pwriteAll(bytes, offset) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_file_write(handle: u64, data: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(handle, data, len);
}

pub export fn sa_fs_file_write_all(handle: u64, data: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(handle, data, len);
}

pub export fn sa_fs_file_flush(handle: u64) i32 {
    return sa_io_flush(handle);
}

pub export fn sa_fs_file_sync_data(handle: u64) i32 {
    return sa_fs_file_sync(handle);
}

pub export fn sa_fs_file_sync(handle: u64) i32 {
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    stream_slots.items[idx].?.file.sync() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_file_truncate(handle: u64, new_size: u64) i32 {
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    stream_slots.items[idx].?.file.setEndPos(new_size) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

fn seekFileLocked(file: std.fs.File, whence: u32, offset: i64) !void {
    switch (whence) {
        0 => {
            if (offset < 0) return error.InvalidArgument;
            try file.seekTo(@as(u64, @intCast(offset)));
        },
        1 => try file.seekBy(offset),
        2 => try file.seekFromEnd(offset),
        else => return error.InvalidArgument,
    }
}

pub export fn sa_fs_file_seek(handle: u64, whence: u32, offset: i64) i32 {
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    seekFileLocked(stream_slots.items[idx].?.file, whence, offset) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_file_seek(handle: u64, whence: u32, offset: i64, out_pos: ?*u64) i32 {
    const pos_ptr = out_pos orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pos_ptr.* = 0;
    stream_mutex.lock();
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const file = stream_slots.items[idx].?.file;
    seekFileLocked(file, whence, offset) catch |err| return finishErr(err);
    pos_ptr.* = file.getPos() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_file_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_std_process_wait_raw(handle: u64, out_raw: ?*i32) i32 {
    _ = handle;
    const raw_ptr = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    raw_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_try_wait_raw(handle: u64, out_ready: ?*i32, out_raw: ?*i32) i32 {
    _ = handle;
    const ready_ptr = out_ready orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const raw_ptr = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ready_ptr.* = 0;
    raw_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_send_signal(handle: u64, signal: i32) i32 {
    _ = handle;
    _ = signal;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_send_process_group_signal(handle: u64, signal: i32) i32 {
    _ = handle;
    _ = signal;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_kill_process_group(handle: u64) i32 {
    _ = handle;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_pidfd(handle: u64, out_pidfd: ?*u64) i32 {
    _ = handle;
    const pidfd_ptr = out_pidfd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pidfd_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_into_pidfd(handle: u64, out_pidfd: ?*u64) i32 {
    return sa_std_process_pidfd(handle, out_pidfd);
}

pub export fn sa_std_process_close(handle: u64) i32 {
    return closeProcessHandle(handle);
}

pub export fn sa_std_close(handle: u64) i32 {
    if ((handle & tagged_handle_mask) == process_handle_tag) return closeProcessHandle(handle);
    if ((handle & tagged_handle_mask) == stream_handle_tag) return closeStreamHandle(handle);
    if ((handle & tagged_handle_mask) == json_handle_tag) return closeJsonHandle(handle);
    if ((handle & tagged_handle_mask) == json_writer_handle_tag) return closeJsonWriter(handle);
    if ((handle & tagged_handle_mask) == json_tokenizer_handle_tag) return closeTokenizer(handle);
    if ((handle & tagged_handle_mask) == metadata_handle_tag) return closeMetadataHandle(handle);
    if ((handle & tagged_handle_mask) == dir_entries_handle_tag) return closeDirEntriesHandle(handle);
    if ((handle & tagged_handle_mask) == dir_entry_handle_tag) return closeDirEntryHandle(handle);
    if ((handle & tagged_handle_mask) == dynamic_library_handle_tag) return closeDynamicLibrary(handle);
    if ((handle & tagged_handle_mask) == net_addr_handle_tag) return closeNetAddr(handle);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const idx = bufferSlot(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = buffers.items[idx].?;
    resource.close();
    buffers.items[idx] = null;
    free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

pub export fn sa_io_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_io_read_line(handle: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const limit = lenAsUsize(max_bytes) catch |err| return finishErr(err);
    var list = std.ArrayList(u8).init(std.heap.page_allocator);
    defer list.deinit();

    var count: usize = 0;
    while (count < limit) {
        var ch: [1]u8 = undefined;
        var read: u64 = 0;
        const status = sa_std_read(handle, &ch, 1, &read);
        if (status != SA_STD_OK) return status;
        if (read == 0) break;
        if (ch[0] == '\n') break;
        if (ch[0] == '\r') continue;
        list.append(ch[0]) catch |err| return finishErr(err);
        count += 1;
    }

    const bytes = list.toOwnedSlice() catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(bytes);
    handle_ptr.* = registerBuffer(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_io_buffer_data(buffer: ?*const SaIoBuffer) ?[*]u8 {
    return if (buffer) |value| value.ptr else null;
}

pub export fn sa_io_buffer_len(buffer: ?*const SaIoBuffer) u64 {
    return if (buffer) |value| value.len else 0;
}

pub export fn sa_io_buffer_free(buffer: ?*SaIoBuffer) i32 {
    _ = buffer;
    return finish(SA_STD_OK);
}

pub export fn sa_dl_open(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const path_w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, path) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(path_w);
    const module = LoadLibraryW(path_w.ptr) orelse {
        dynamic_library_error = "LoadLibraryW failed";
        return finish(dynamicLibraryErrorStatus());
    };
    handle_ptr.* = registerDynamicLibrary(module) catch |err| {
        _ = FreeLibrary(module);
        return finishErr(err);
    };
    dynamic_library_error = "";
    return finish(SA_STD_OK);
}

pub export fn sa_dl_sym(handle: u64, symbol_ptr: ?[*]const u8, symbol_len: u64, out_ptr: ?*?*anyopaque) i32 {
    const result_ptr = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result_ptr.* = null;
    const symbol = pathBytes(symbol_ptr, symbol_len) catch |err| return finishErr(err);
    const symbol_z = std.heap.page_allocator.dupeZ(u8, symbol) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(symbol_z);
    dynamic_library_mutex.lock();
    defer dynamic_library_mutex.unlock();
    const idx = dynamicLibrarySlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const address = GetProcAddress(dynamic_library_slots.items[idx].?.module, symbol_z.ptr) orelse {
        dynamic_library_error = "GetProcAddress failed";
        return finish(SA_STD_ERR_NOT_FOUND);
    };
    result_ptr.* = @ptrCast(address);
    dynamic_library_error = "";
    return finish(SA_STD_OK);
}

pub export fn sa_dl_close(handle: u64) i32 {
    return closeDynamicLibrary(handle);
}

pub export fn sa_dl_error() ?[*:0]const u8 {
    return dynamic_library_error.ptr;
}

pub export fn sa_net_addr_host(addr: u64) ?[*]u8 {
    net_addr_mutex.lock();
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return null;
    };
    return net_addr_slots.items[idx].?.host.ptr;
}

pub export fn sa_net_addr_host_len(addr: u64) u64 {
    net_addr_mutex.lock();
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return @as(u64, @intCast(net_addr_slots.items[idx].?.host.len));
}

pub export fn sa_net_addr_port(addr: u64) u32 {
    net_addr_mutex.lock();
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return @as(u32, net_addr_slots.items[idx].?.port);
}

pub export fn sa_net_addr_family(addr: u64) u32 {
    net_addr_mutex.lock();
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return net_addr_slots.items[idx].?.family;
}

pub export fn sa_net_addr_scope_id(addr: u64) u64 {
    net_addr_mutex.lock();
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse {
        _ = finish(SA_STD_ERR_INVALID_HANDLE);
        return 0;
    };
    return net_addr_slots.items[idx].?.scope_id;
}

pub export fn sa_net_addr_free(addr: u64) FallibleI32 {
    const status = closeNetAddr(addr);
    if (status != SA_STD_OK) return .{ .status = status, .value = 0 };
    return .{ .status = SA_STD_OK, .value = 0 };
}

pub export fn sa_net_ipv4_parse_ascii(text_ptr: ?[*]const u8, text_len: u64, out_addr: ?[*]u8) i32 {
    const out = out_addr orelse return 0;
    out[0] = 0;
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;

    const text = constBytes(text_ptr, text_len) catch return 0;
    const parts = parseIpv4Ascii(text) orelse return 0;
    @memcpy(out[0..4], &parts);
    return 1;
}

pub export fn sa_net_socket_addr_v4_parse_ascii(text_ptr: ?[*]const u8, text_len: u64, out_socket_addr: ?[*]u8) i32 {
    const out = out_socket_addr orelse return 0;
    for (out[0..8]) |*byte| byte.* = 0;

    const text = constBytes(text_ptr, text_len) catch return 0;
    const colon = std.mem.lastIndexOfScalar(u8, text, ':') orelse return 0;
    const ip = parseIpv4Ascii(text[0..colon]) orelse return 0;
    const port = parsePortAscii(text[colon + 1 ..]) orelse return 0;
    @memcpy(out[0..4], &ip);
    std.mem.writeInt(u16, out[4..6], port, .little);
    return 1;
}
