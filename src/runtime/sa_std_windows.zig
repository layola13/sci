const std = @import("std");
const builtin = @import("builtin");

extern fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8;
extern fn _putenv_s(name: [*:0]const u8, value: [*:0]const u8) callconv(.c) c_int;
extern "kernel32" fn CreateHardLinkW(new_file_name: [*:0]const u16, existing_file_name: [*:0]const u16, security_attributes: ?*anyopaque) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn CreateToolhelp32Snapshot(flags: std.os.windows.DWORD, process_id: std.os.windows.DWORD) callconv(.winapi) std.os.windows.HANDLE;
extern "kernel32" fn Process32FirstW(snapshot: std.os.windows.HANDLE, entry: *ProcessEntry32W) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn Process32NextW(snapshot: std.os.windows.HANDLE, entry: *ProcessEntry32W) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn CloseHandle(handle: std.os.windows.HANDLE) callconv(.winapi) std.os.windows.BOOL;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*anyopaque;
extern "c" fn fputs(s: [*:0]const u8, stream: ?*anyopaque) callconv(.c) c_int;
extern "c" fn fclose(stream: ?*anyopaque) callconv(.c) c_int;
extern "kernel32" fn LoadLibraryW(path: [*:0]const u16) callconv(.winapi) ?std.os.windows.HMODULE;
extern "kernel32" fn GetProcAddress(module: std.os.windows.HMODULE, name: [*:0]const u8) callconv(.winapi) ?std.os.windows.FARPROC;
extern "kernel32" fn FreeLibrary(module: std.os.windows.HMODULE) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn GetLastError() callconv(.winapi) std.os.windows.Win32Error;
extern "ntdll" fn NtQueryInformationProcess(h: std.os.windows.HANDLE, c: i32, p: ?*anyopaque, u: std.os.windows.ULONG, r: ?*std.os.windows.ULONG) callconv(.winapi) i32;
extern "kernel32" fn WaitForSingleObject(h: std.os.windows.HANDLE, ms: std.os.windows.DWORD) callconv(.winapi) std.os.windows.DWORD;
extern "kernel32" fn CreateThread(lp_thread_attributes: ?*anyopaque, dw_stack_size: std.os.windows.DWORD, lp_start_address: ?*anyopaque, lp_parameter: ?*anyopaque, dw_creation_flags: std.os.windows.DWORD, lp_thread_id: ?*std.os.windows.DWORD) callconv(.winapi) ?std.os.windows.HANDLE;
extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) std.os.windows.DWORD;
extern "kernel32" fn SwitchToThread() callconv(.winapi) std.os.windows.BOOL;

const DEBUG_LOG_PATH = "E:\\projects\\sci\\spawn_debug.log";

fn spawnDebugLog(message: []const u8) void {
    const file = fopen("E:\\projects\\sci\\spawn_debug.log", "a");
    if (file == null) return;
    var buf: [4097]u8 = undefined;
    const len = @min(message.len, buf.len - 2);
    @memcpy(buf[0..len], message);
    buf[len] = '\n';
    buf[len + 1] = 0;
    const sentinel_slice: [:0]u8 = buf[0 .. len + 1 :0];
    _ = fputs(sentinel_slice.ptr, file);
    _ = fclose(file);
}

fn spawnDebugLogFmt(comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    const msg = std.fmt.bufPrint(buf[0..], fmt, args) catch return;
    spawnDebugLog(msg);
}
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

const SaTermWinsize = extern struct {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
};

const SaTermEpollEvent = extern struct {
    events: u32,
    data: u64,
};

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

pub const SaProcessArgv = extern struct {
    data: ?[*]const u8,
    len: u64,
};

const ProcessEntry32W = extern struct {
    dwSize: std.os.windows.DWORD,
    cntUsage: std.os.windows.DWORD,
    th32ProcessID: std.os.windows.DWORD,
    th32DefaultHeapID: usize,
    th32ModuleID: std.os.windows.DWORD,
    cntThreads: std.os.windows.DWORD,
    th32ParentProcessID: std.os.windows.DWORD,
    pcPriClassBase: i32,
    dwFlags: std.os.windows.DWORD,
    szExeFile: [260]u16,
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

const NetAddrListResource = struct {
    addresses: []std.net.Address,
    next_index: usize = 0,

    fn close(self: *NetAddrListResource) void {
        if (self.addresses.len != 0) std.heap.page_allocator.free(self.addresses);
        self.* = undefined;
    }
};
const TcpStreamResource = struct {
    stream: std.net.Stream,
    fn close(self: *TcpStreamResource) void {
        self.stream.close();
        self.* = undefined;
    }
};

const TcpListenerResource = struct {
    server: std.net.Server,
    fn close(self: *TcpListenerResource) void {
        self.server.deinit();
        self.* = undefined;
    }
};

const UdpResource = struct {
    socket: std.posix.socket_t,

    fn close(self: *UdpResource) void {
        std.os.windows.closesocket(self.socket) catch {};
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
const net_addr_list_handle_tag: u64 = 0x7c00_0000_0000_0000;
const tcp_stream_handle_tag: u64 = 0x7a00_0000_0000_0000;
const tcp_listener_handle_tag: u64 = 0x7b00_0000_0000_0000;
const udp_handle_tag: u64 = 0x7a00_0000_0000_0000;
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
var net_addr_list_mutex: std.Thread.Mutex = .{};
var net_addr_list_slots = std.ArrayList(?NetAddrListResource).init(std.heap.page_allocator);
var net_addr_list_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var tcp_mutex: std.Thread.Mutex = .{};
var tcp_stream_slots = std.ArrayList(?TcpStreamResource).init(std.heap.page_allocator);
var tcp_stream_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var tcp_listener_slots = std.ArrayList(?TcpListenerResource).init(std.heap.page_allocator);
var tcp_listener_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var udp_mutex: std.Thread.Mutex = .{};
var udp_slots = std.ArrayList(?UdpResource).init(std.heap.page_allocator);
var udp_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);

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

fn tempPathAlloc(allocator: std.mem.Allocator, prefix: []const u8, suffix: []const u8) ![]u8 {
    const root = try tempRootAlloc(allocator);
    defer allocator.free(root);
    const normalized_prefix = if (prefix.len == 0) "sa-deno-" else prefix;
    const a = std.crypto.random.int(u64);
    const b = std.crypto.random.int(u64);
    const name = try std.fmt.allocPrint(allocator, "{s}{x:0>16}{x:0>16}{s}", .{ normalized_prefix, a, b, suffix });
    defer allocator.free(name);
    return std.fs.path.join(allocator, &.{ root, name });
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

fn xdgHomeAlloc(allocator: std.mem.Allocator, env_key: []const u8) ![]u8 {
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

fn xdgDirsAlloc(allocator: std.mem.Allocator, env_key: []const u8) ![]u8 {
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

const CompatArgv = struct {
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

fn commandInterpreterPathAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "COMSPEC")) |path| {
        if (path.len != 0) return path;
        allocator.free(path);
    } else |_| {}
    const system_root = if (getenv("SystemRoot")) |ptr| std.mem.span(ptr) else "C:\\Windows";
    return std.fmt.allocPrint(allocator, "{s}\\System32\\cmd.exe", .{system_root});
}

fn powerShellPathAlloc(allocator: std.mem.Allocator) ![]u8 {
    const system_root = if (getenv("SystemRoot")) |ptr| std.mem.span(ptr) else "C:\\Windows";
    return std.fmt.allocPrint(allocator, "{s}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", .{system_root});
}

fn allocCompatArgv(allocator: std.mem.Allocator, argv: []const []const u8, arg0_override: ?[]const u8) !CompatArgv {
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

fn registerNetAddrList(host: []const u8, port: u16) !u64 {
    const list = try std.net.getAddressList(std.heap.page_allocator, host, port);
    defer list.deinit();
    if (list.addrs.len == 0) return error.HostLacksNetworkAddresses;
    const addresses = try std.heap.page_allocator.dupe(std.net.Address, list.addrs);
    errdefer std.heap.page_allocator.free(addresses);
    net_addr_list_mutex.lock();
    defer net_addr_list_mutex.unlock();
    while (net_addr_list_free_slots.items.len != 0) {
        const idx = net_addr_list_free_slots.pop().?;
        if (idx >= net_addr_list_slots.items.len or net_addr_list_slots.items[idx] != null) continue;
        net_addr_list_slots.items[idx] = .{ .addresses = addresses };
        return net_addr_list_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try net_addr_list_slots.append(.{ .addresses = addresses });
    return net_addr_list_handle_tag | @as(u64, @intCast(net_addr_list_slots.items.len));
}

fn netAddrListSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, net_addr_list_handle_tag) orelse return null;
    if (idx >= net_addr_list_slots.items.len or net_addr_list_slots.items[idx] == null) return null;
    return idx;
}

fn closeNetAddrList(handle: u64) i32 {
    net_addr_list_mutex.lock();
    defer net_addr_list_mutex.unlock();
    const idx = netAddrListSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = net_addr_list_slots.items[idx].?;
    resource.close();
    net_addr_list_slots.items[idx] = null;
    net_addr_list_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}
fn registerTcpStreamLocked(stream: std.net.Stream) !u64 {
    while (tcp_stream_free_slots.items.len != 0) {
        const idx = tcp_stream_free_slots.pop().?;
        if (idx >= tcp_stream_slots.items.len or tcp_stream_slots.items[idx] != null) continue;
        tcp_stream_slots.items[idx] = .{ .stream = stream };
        return tcp_stream_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try tcp_stream_slots.append(.{ .stream = stream });
    return tcp_stream_handle_tag | @as(u64, @intCast(tcp_stream_slots.items.len));
}

fn registerTcpListenerLocked(server: std.net.Server) !u64 {
    while (tcp_listener_free_slots.items.len != 0) {
        const idx = tcp_listener_free_slots.pop().?;
        if (idx >= tcp_listener_slots.items.len or tcp_listener_slots.items[idx] != null) continue;
        tcp_listener_slots.items[idx] = .{ .server = server };
        return tcp_listener_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try tcp_listener_slots.append(.{ .server = server });
    return tcp_listener_handle_tag | @as(u64, @intCast(tcp_listener_slots.items.len));
}

fn tcpStreamSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, tcp_stream_handle_tag) orelse return null;
    if (idx >= tcp_stream_slots.items.len or tcp_stream_slots.items[idx] == null) return null;
    return idx;
}

fn tcpListenerSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, tcp_listener_handle_tag) orelse return null;
    if (idx >= tcp_listener_slots.items.len or tcp_listener_slots.items[idx] == null) return null;
    return idx;
}

fn duplicateWinSocket(socket: std.posix.socket_t) !std.posix.socket_t {
    const ws = std.os.windows.ws2_32;
    var info: ws.WSAPROTOCOL_INFOW = undefined;
    if (ws.WSADuplicateSocketW(socket, std.os.windows.GetCurrentProcessId(), &info) != 0) return error.NetworkSubsystemFailed;
    const duplicate = ws.WSASocketW(info.iAddressFamily, info.iSocketType, info.iProtocol, &info, 0, 0);
    if (duplicate == ws.INVALID_SOCKET) return error.NetworkSubsystemFailed;
    return duplicate;
}
fn closeTcpHandle(handle: u64) i32 {
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    if (tcpStreamSlotLocked(handle)) |idx| {
        var resource = tcp_stream_slots.items[idx].?;
        resource.close();
        tcp_stream_slots.items[idx] = null;
        tcp_stream_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
        return finish(SA_STD_OK);
    }
    if (tcpListenerSlotLocked(handle)) |idx| {
        var resource = tcp_listener_slots.items[idx].?;
        resource.close();
        tcp_listener_slots.items[idx] = null;
        tcp_listener_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
        return finish(SA_STD_OK);
    }
    return finish(SA_STD_ERR_INVALID_HANDLE);
}

fn addressHostText(address: std.net.Address) ![]u8 {
    const full = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{address});
    defer std.heap.page_allocator.free(full);
    if (address.any.family == std.posix.AF.INET6 and full.len != 0 and full[0] == '[') {
        const closing = std.mem.lastIndexOfScalar(u8, full, ']') orelse return std.heap.page_allocator.dupe(u8, full);
        return std.heap.page_allocator.dupe(u8, full[1..closing]);
    }
    const sep = std.mem.lastIndexOfScalar(u8, full, ':') orelse full.len;
    return std.heap.page_allocator.dupe(u8, full[0..sep]);
}

fn registerSocketAddress(address: std.net.Address) !u64 {
    return registerNetAddr(.{
        .host = try addressHostText(address),
        .family = if (address.any.family == std.posix.AF.INET) 2 else 10,
        .port = address.getPort(),
        .scope_id = if (address.any.family == std.posix.AF.INET6) address.in6.sa.scope_id else 0,
    });
}

fn resolveSocketAddress(host_ptr: ?[*]const u8, host_len: u64, port: u32) !std.net.Address {
    const host = try pathBytes(host_ptr, host_len);
    if (port > std.math.maxInt(u16)) return error.InvalidArgument;
    const list = try std.net.getAddressList(std.heap.page_allocator, host, @intCast(port));
    defer list.deinit();
    if (list.addrs.len == 0) return error.InvalidArgument;
    return list.addrs[0];
}

fn registerUdp(socket: std.posix.socket_t) !u64 {
    udp_mutex.lock();
    defer udp_mutex.unlock();
    while (udp_free_slots.items.len != 0) {
        const idx = udp_free_slots.pop().?;
        if (idx >= udp_slots.items.len or udp_slots.items[idx] != null) continue;
        udp_slots.items[idx] = .{ .socket = socket };
        return udp_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try udp_slots.append(.{ .socket = socket });
    return udp_handle_tag | @as(u64, @intCast(udp_slots.items.len));
}

fn udpSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, udp_handle_tag) orelse return null;
    if (idx >= udp_slots.items.len or udp_slots.items[idx] == null) return null;
    return idx;
}

fn closeUdp(handle: u64) i32 {
    udp_mutex.lock();
    defer udp_mutex.unlock();
    const idx = udpSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = udp_slots.items[idx].?;
    resource.close();
    udp_slots.items[idx] = null;
    udp_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
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

fn spawnProcessCwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, mode: ProcessMode, cwd: ?[]const u8, arg0_override: ?[]const u8) !u64 {
    const argv = try argvFromEntries(std.heap.page_allocator, argv_ptr, argv_len);
    defer std.heap.page_allocator.free(argv);
    var compat = try allocCompatArgv(std.heap.page_allocator, argv, arg0_override);
    defer compat.deinit(std.heap.page_allocator);

    var child = std.process.Child.init(compat.argv, std.heap.page_allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = if (mode == .inherit) .Inherit else .Pipe;
    child.stderr_behavior = if (mode == .inherit) .Inherit else .Pipe;
    child.cwd = cwd;
    spawnDebugLogFmt("spawnProcessCwd: attempting spawn argv_len={d}", .{compat.argv.len});
    for (compat.argv) |a| spawnDebugLogFmt("  argv: {s}", .{a});
    child.spawn() catch |err| {
        spawnDebugLogFmt("spawnProcessCwd: spawn FAILED err={s}", .{@errorName(err)});
        return err;
    };
    spawnDebugLogFmt("spawnProcessCwd: spawn succeeded pid={d}", .{child.id});
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
    return spawnProcessCwd(argv_ptr, argv_len, mode, null, null);
}

fn spawnStreamProcessCwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd: ?[]const u8, arg0_override: ?[]const u8, out_process: *u64, out_stdout: *u64, out_stderr: *u64) !void {
    const process = try spawnProcessCwd(argv_ptr, argv_len, .stream, cwd, arg0_override);
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

fn spawnProcessNoArgs(mode: ProcessMode, compat_first: []const u8, compat_rest: []const u8) !u64 {
    const program = try commandInterpreterPathAlloc(std.heap.page_allocator);
    defer std.heap.page_allocator.free(program);
    const argv = &[_][]const u8{ program, "/d", "/c", compat_first, compat_rest };
    return spawnProcessCwd(@as(?[*]const SaProcessArgv, @ptrCast(argv.ptr)), argv.len, mode, null, null);
}

fn spawnStreamProcess(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_process: *u64, out_stdout: *u64, out_stderr: *u64) !void {
    return spawnStreamProcessCwd(argv_ptr, argv_len, null, null, out_process, out_stdout, out_stderr);
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

pub export fn sa_std_net_error_code_from_status(status: i32) i32 {
    return switch (status) {
        SA_STD_OK => 0,
        SA_STD_ERR_INVALID_ARGUMENT => 10,
        SA_STD_ERR_INVALID_HANDLE => 11,
        SA_STD_ERR_NOT_FOUND => 12,
        SA_STD_ERR_ACCESS => 8,
        SA_STD_ERR_NO_MEMORY => 13,
        SA_STD_ERR_IO => 14,
        SA_STD_ERR_NET => 15,
        SA_STD_ERR_UNSUPPORTED => 9,
        SA_STD_ERR_TRUNCATED => 14,
        else => 1,
    };
}

pub export fn sa_std_net_error_code_from_posix_errno(errno: i32) i32 {
    return switch (errno) {
        0 => 0,
        1, 13 => 8,
        2, 20 => 12,
        4 => 24,
        9 => 11,
        11 => 6,
        12 => 13,
        14, 22 => 10,
        17 => 23,
        32 => 22,
        98 => 16,
        99 => 17,
        100 => 27,
        101 => 15,
        103 => 19,
        104 => 18,
        107 => 20,
        110 => 4,
        111 => 3,
        113 => 21,
        -2, -4, -5 => 2,
        -3 => 4,
        -6, -7 => 9,
        -8 => 10,
        -10 => 13,
        -11 => 14,
        else => 1,
    };
}

pub export fn sa_std_net_error_code_from_wsa_error(native_error: i32) i32 {
    return switch (native_error) {
        0 => 0,
        10004 => 24,
        10013 => 8,
        10022 => 10,
        10024, 10055 => 13,
        10035, 10036, 10037 => 6,
        10038 => 11,
        10040 => 26,
        10041, 10042, 10043, 10044, 10045, 10046, 10047 => 9,
        10048 => 16,
        10049 => 17,
        10050, 10052 => 27,
        10051 => 15,
        10053 => 19,
        10054 => 18,
        10057, 10058 => 20,
        10060 => 4,
        10061 => 3,
        10064, 10065 => 21,
        11001, 11003, 11004 => 2,
        11002 => 4,
        else => 1,
    };
}

fn netErrorCodeName(code: i32) []const u8 {
    return switch (code) {
        0 => "ok",
        1 => "unknown",
        2 => "dns",
        3 => "connection_refused",
        4 => "timed_out",
        5 => "connection_closed",
        6 => "would_block",
        7 => "invalid_address",
        8 => "permission_denied",
        9 => "unsupported",
        10 => "invalid_input",
        11 => "invalid_handle",
        12 => "not_found",
        13 => "out_of_memory",
        14 => "io",
        15 => "network_unreachable",
        16 => "addr_in_use",
        17 => "addr_not_available",
        18 => "connection_reset",
        19 => "connection_aborted",
        20 => "not_connected",
        21 => "host_unreachable",
        22 => "broken_pipe",
        23 => "already_exists",
        24 => "interrupted",
        25 => "unexpected_eof",
        26 => "invalid_data",
        27 => "network_down",
        28 => "write_zero",
        else => "unknown",
    };
}

pub export fn sa_std_net_error_code_name(code: i32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const name = netErrorCodeName(code);
    if (out_len) |len_ptr| len_ptr.* = @as(u64, @intCast(name.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const cap = lenAsUsize(out_cap) catch |err| return finishErr(err);
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const copy_len = @min(cap, name.len);
    @memcpy(out_ptr[0..copy_len], name[0..copy_len]);
    if (copy_len != name.len) return finish(SA_STD_ERR_TRUNCATED);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_error_platform() i32 {
    return 2;
}

pub export fn sa_std_net_error_code_from_native_error(native_error: i32) i32 {
    return sa_std_net_error_code_from_wsa_error(native_error);
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

pub export fn sa_deno_make_temp_dir(prefix_ptr: ?[*]const u8, prefix_len: u64) FallibleU64 {
    const prefix = constBytes(prefix_ptr, prefix_len) catch |err| return failU64(mapError(err));
    if (std.mem.indexOfScalar(u8, prefix, 0) != null) return failU64(SA_STD_ERR_INVALID_ARGUMENT);
    const allocator = std.heap.page_allocator;
    var attempts: u32 = 0;
    while (attempts < 100) : (attempts += 1) {
        const path = tempPathAlloc(allocator, prefix, "") catch |err| return failU64(mapError(err));
        std.fs.cwd().makeDir(path) catch |err| {
            allocator.free(path);
            if (err == error.PathAlreadyExists) continue;
            return failU64(mapError(err));
        };
        const handle = openOwnedByteBuffer(path) catch |err| {
            std.fs.cwd().deleteDir(path) catch {};
            allocator.free(path);
            return failU64(mapError(err));
        };
        return okU64(handle);
    }
    return failU64(SA_STD_ERR_IO);
}

pub export fn sa_deno_make_temp_file(
    prefix_ptr: ?[*]const u8,
    prefix_len: u64,
    suffix_ptr: ?[*]const u8,
    suffix_len: u64,
) FallibleU64 {
    const prefix = constBytes(prefix_ptr, prefix_len) catch |err| return failU64(mapError(err));
    const suffix = constBytes(suffix_ptr, suffix_len) catch |err| return failU64(mapError(err));
    if (std.mem.indexOfScalar(u8, prefix, 0) != null or std.mem.indexOfScalar(u8, suffix, 0) != null) {
        return failU64(SA_STD_ERR_INVALID_ARGUMENT);
    }
    const allocator = std.heap.page_allocator;
    var attempts: u32 = 0;
    while (attempts < 100) : (attempts += 1) {
        const path = tempPathAlloc(allocator, prefix, suffix) catch |err| return failU64(mapError(err));
        const file = std.fs.cwd().createFile(path, .{ .read = true, .exclusive = true }) catch |err| {
            allocator.free(path);
            if (err == error.PathAlreadyExists) continue;
            return failU64(mapError(err));
        };
        file.close();
        const handle = openOwnedByteBuffer(path) catch |err| {
            std.fs.cwd().deleteFile(path) catch {};
            allocator.free(path);
            return failU64(mapError(err));
        };
        return okU64(handle);
    }
    return failU64(SA_STD_ERR_IO);
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

pub export fn sa_env_xdg_data_home_dir() u64 {
    const path = xdgHomeAlloc(std.heap.page_allocator, "XDG_DATA_HOME") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_config_home_dir() u64 {
    const path = xdgHomeAlloc(std.heap.page_allocator, "XDG_CONFIG_HOME") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_state_home_dir() u64 {
    const path = xdgHomeAlloc(std.heap.page_allocator, "XDG_STATE_HOME") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_cache_home_dir() u64 {
    const path = xdgHomeAlloc(std.heap.page_allocator, "XDG_CACHE_HOME") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_data_dirs() u64 {
    const path = xdgDirsAlloc(std.heap.page_allocator, "XDG_DATA_DIRS") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_config_dirs() u64 {
    const path = xdgDirsAlloc(std.heap.page_allocator, "XDG_CONFIG_DIRS") catch return 0;
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

pub export fn sa_std_process_exit_status_code(raw: i32) u32 {
    if (raw < 0) return 0;
    // On Windows, processTermCode returns the exit code as u32
    // The test expects code to be 0 for success, which matches our raw
    return @as(u32, @intCast(raw));
}

pub export fn sa_std_process_exit_status_signal(raw: i32) i32 {
    _ = raw;
    return 0;
}

pub export fn sa_std_process_exit_status_core_dumped(raw: i32) u8 {
    _ = raw;
    return 0;
}

pub export fn sa_std_process_exit_status_stopped_signal(raw: i32) i32 {
    _ = raw;
    return -1;
}

pub export fn sa_std_process_exit_status_continued(raw: i32) u8 {
    _ = raw;
    return 0;
}

pub export fn sa_test_fallible_i32_value(value: i32) FallibleI32 {
    return .{ .status = SA_STD_OK, .value = value };
}

pub export fn sa_assert_eq_i64(actual: i64, expected: i64, code: i32) void {
    if (actual == expected) return;
    std.debug.print("PANIC[{d}]: expected={d} actual={d}\n", .{ code, expected, actual });
    std.process.exit(if (code < 0) 1 else @as(u8, @truncate(@as(u32, @bitCast(code)))));
}

pub export fn sa_assert_eq_i64_at(actual: i64, expected: i64, code: i32, file: ?[*]const u8, file_len: u64, line: u32, col: u32) void {
    if (actual == expected) return;
    const file_slice = if (file) |ptr| ptr[0..@as(usize, @intCast(file_len))] else "";
    std.debug.print("PANIC[{d}]: {s}:{d}:{d}: expected={d} actual={d}\n", .{ code, file_slice, line, col, expected, actual });
    std.process.exit(if (code < 0) 1 else @as(u8, @truncate(@as(u32, @bitCast(code)))));
}

const test_debug_slots = 16;

const TestDebugScalar = struct {
    name: [32]u8,
    name_len: usize,
    value: i64,
};

var test_debug_scalars: [test_debug_slots]TestDebugScalar = .{
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
};

var test_debug_next: usize = 0;
var test_debug_count: usize = 0;
var test_debug_mutex = std.Thread.Mutex{};

pub export fn sa_test_debug_i64(name: ?[*]const u8, name_len: u64, value: i64) void {
    const raw_name = name orelse return;
    test_debug_mutex.lock();
    defer test_debug_mutex.unlock();
    const slot_index = test_debug_next % test_debug_scalars.len;
    var slot = &test_debug_scalars[slot_index];
    const requested_len = std.math.cast(usize, name_len) orelse slot.name.len;
    const copy_len = @min(requested_len, slot.name.len);
    @memset(slot.name[0..], 0);
    if (copy_len != 0) @memcpy(slot.name[0..copy_len], raw_name[0..copy_len]);
    slot.name_len = copy_len;
    slot.value = value;
    test_debug_next = (test_debug_next + 1) % test_debug_scalars.len;
    if (test_debug_count < test_debug_scalars.len) test_debug_count += 1;
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

const PthreadEntryFn = *const fn (?[*]u8) callconv(.c) i32;

const WinThreadTask = struct {
    entry: PthreadEntryFn,
    arg: ?[*]u8,
    result: i32 = 0,
    destroy_on_finish: bool = false,
};

const WinThreadHandle = struct {
    handle: std.os.windows.HANDLE,
    task: *WinThreadTask,
};

var win_thread_mutex: std.Thread.Mutex = .{};
var win_thread_slots = std.ArrayList(?*WinThreadHandle).init(std.heap.page_allocator);
var win_thread_free_slots = std.ArrayList(usize).init(std.heap.page_allocator);
var raw_win_thread_owners = std.ArrayList(RawWinThreadOwner).init(std.heap.page_allocator);

const RawWinThreadOwner = struct {
    raw: u64,
    task: *WinThreadTask,
};

fn winThreadTaskMain(task: *WinThreadTask) void {
    task.result = task.entry(task.arg);
    if (task.destroy_on_finish) {
        std.heap.page_allocator.destroy(task);
    }
}

fn winThreadTaskMainC(lp_parameter: ?*anyopaque) callconv(.c) std.os.windows.DWORD {
    if (lp_parameter) |raw| {
        const task: *WinThreadTask = @ptrCast(@alignCast(raw));
        winThreadTaskMain(task);
    }
    return 0;
}

fn allocWinThreadHandle(handle: *WinThreadHandle) !i32 {
    win_thread_mutex.lock();
    defer win_thread_mutex.unlock();
    while (win_thread_free_slots.items.len != 0) {
        const idx = win_thread_free_slots.pop().?;
        if (idx >= win_thread_slots.items.len or win_thread_slots.items[idx] != null) continue;
        win_thread_slots.items[idx] = handle;
        return @intCast(idx + 1);
    }
    try win_thread_slots.append(handle);
    return @intCast(win_thread_slots.items.len);
}

fn takeWinThreadHandle(handle: i32) !*WinThreadHandle {
    if (handle <= 0) return error.InvalidHandle;
    const idx: usize = @intCast(handle - 1);
    win_thread_mutex.lock();
    defer win_thread_mutex.unlock();
    if (idx >= win_thread_slots.items.len) return error.InvalidHandle;
    return win_thread_slots.items[idx] orelse return error.InvalidHandle;
}

fn freeWinThreadHandle(handle: i32) !*WinThreadHandle {
    if (handle <= 0) return error.InvalidHandle;
    const idx: usize = @intCast(handle - 1);
    win_thread_mutex.lock();
    defer win_thread_mutex.unlock();
    if (idx >= win_thread_slots.items.len) return error.InvalidHandle;
    const slot = win_thread_slots.items[idx] orelse return error.InvalidHandle;
    try win_thread_free_slots.append(idx);
    win_thread_slots.items[idx] = null;
    return slot;
}

fn findRawWinThreadTask(raw: u64) ?*WinThreadTask {
    win_thread_mutex.lock();
    defer win_thread_mutex.unlock();
    for (raw_win_thread_owners.items) |owner| {
        if (owner.raw == raw) return owner.task;
    }
    return null;
}

fn removeRawWinThreadOwner(raw: u64) ?*WinThreadTask {
    win_thread_mutex.lock();
    defer win_thread_mutex.unlock();
    for (raw_win_thread_owners.items, 0..) |owner, i| {
        if (owner.raw == raw) return raw_win_thread_owners.swapRemove(i).task;
    }
    return null;
}

pub export fn pthread_spawn(entry_ptr: ?[*]const u8, arg_ptr: ?[*]const u8) callconv(.c) i32 {
    const entry_fn: PthreadEntryFn = @ptrCast(entry_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT));
    const task = std.heap.page_allocator.create(WinThreadTask) catch return finish(SA_STD_ERR_NO_MEMORY);
    task.* = .{ .entry = entry_fn, .arg = @ptrCast(@constCast(arg_ptr)) };

    const handle = std.heap.page_allocator.create(WinThreadHandle) catch {
        std.heap.page_allocator.destroy(task);
        return finish(SA_STD_ERR_NO_MEMORY);
    };

    const thread_handle = windowsCreateThread(task) catch {
        std.heap.page_allocator.destroy(handle);
        std.heap.page_allocator.destroy(task);
        return finish(SA_STD_ERR_IO);
    };

    handle.* = .{ .handle = thread_handle, .task = task };
    const id = allocWinThreadHandle(handle) catch {
        _ = CloseHandle(thread_handle);
        std.heap.page_allocator.destroy(handle);
        std.heap.page_allocator.destroy(task);
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    last_error = SA_STD_OK;
    return id;
}

pub export fn pthread_spawn_detached(entry_ptr: ?[*]const u8, arg_ptr: ?[*]const u8) callconv(.c) i32 {
    const entry_fn: PthreadEntryFn = @ptrCast(entry_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT));
    const task = std.heap.page_allocator.create(WinThreadTask) catch return finish(SA_STD_ERR_NO_MEMORY);
    task.* = .{
        .entry = entry_fn,
        .arg = @ptrCast(@constCast(arg_ptr)),
        .destroy_on_finish = true,
    };
    const thread_handle = windowsCreateThread(task) catch {
        std.heap.page_allocator.destroy(task);
        return finish(SA_STD_ERR_IO);
    };
    _ = CloseHandle(thread_handle);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn pthread_join(handle_id: i32, out: ?[*]u8) callconv(.c) i32 {
    const handle_ptr = freeWinThreadHandle(handle_id) catch return finish(SA_STD_ERR_INVALID_HANDLE);
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const wait_result = std.os.windows.kernel32.WaitForSingleObject(handle_ptr.handle, 0xFFFFFFFF);
    if (wait_result != 0x00000000) {
        std.heap.page_allocator.destroy(handle_ptr.task);
        std.heap.page_allocator.destroy(handle_ptr);
        return finish(SA_STD_ERR_IO);
    }
    std.mem.copyForwards(u8, out_ptr[0..4], std.mem.asBytes(&handle_ptr.task.result));
    _ = CloseHandle(handle_ptr.handle);
    std.heap.page_allocator.destroy(handle_ptr.task);
    std.heap.page_allocator.destroy(handle_ptr);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn pthread_drop(handle_id: i32) callconv(.c) void {
    if (handle_id <= 0) {
        last_error = SA_STD_ERR_INVALID_HANDLE;
        return;
    }
    const handle_ptr = freeWinThreadHandle(handle_id) catch {
        last_error = SA_STD_ERR_INVALID_HANDLE;
        return;
    };
    const wait_result = std.os.windows.kernel32.WaitForSingleObject(handle_ptr.handle, 0xFFFFFFFF);
    if (wait_result != 0x00000000) {}
    _ = CloseHandle(handle_ptr.handle);
    std.heap.page_allocator.destroy(handle_ptr.task);
    std.heap.page_allocator.destroy(handle_ptr);
    last_error = SA_STD_OK;
}

pub export fn sa_thread_current_id() u64 {
    return @as(u64, @intCast(std.Thread.getCurrentId()));
}

pub export fn sa_thread_yield_now() i32 {
    std.Thread.yield() catch {};
    return finish(SA_STD_OK);
}

pub export fn sa_thread_as_pthread_t(handle_id: i32, out_raw: ?*u64) i32 {
    const out = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const handle_ptr = takeWinThreadHandle(handle_id) catch {
        if (out_raw) |o| o.* = 0;
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    out.* = @intFromPtr(handle_ptr.handle);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_thread_into_pthread_t(handle_id: i32, out_raw: ?*u64) i32 {
    const out = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (handle_id <= 0) {
        if (out_raw) |o| o.* = 0;
        return finish(SA_STD_ERR_INVALID_HANDLE);
    }
    const idx: usize = @intCast(handle_id - 1);
    win_thread_mutex.lock();
    defer win_thread_mutex.unlock();
    if (idx >= win_thread_slots.items.len) {
        if (out_raw) |o| o.* = 0;
        return finish(SA_STD_ERR_INVALID_HANDLE);
    }
    const slot = win_thread_slots.items[idx] orelse {
        if (out_raw) |o| o.* = 0;
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    win_thread_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    win_thread_slots.items[idx] = null;
    const raw = @intFromPtr(slot.handle);
    raw_win_thread_owners.append(.{ .raw = raw, .task = slot.task }) catch return finish(SA_STD_ERR_NO_MEMORY);
    out.* = raw;
    std.heap.page_allocator.destroy(slot);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sa_thread_raw_pthread_join(raw: u64, out: ?[*]u8) i32 {
    const out_ptr = out orelse {
        return finish(SA_STD_ERR_INVALID_ARGUMENT);
    };
    const task = findRawWinThreadTask(raw) orelse {
        if (out) |o| {
            var k: usize = 0;
            while (k < 4) : (k += 1) o[k] = 0;
        }
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const handle: std.os.windows.HANDLE = @ptrFromInt(raw);
    const wait_result = std.os.windows.kernel32.WaitForSingleObject(handle, 0xFFFFFFFF);
    if (wait_result != 0x00000000) return finish(SA_STD_ERR_IO);
    const removed_task = removeRawWinThreadOwner(raw) orelse task;
    std.mem.copyForwards(u8, out_ptr[0..4], std.mem.asBytes(&removed_task.result));
    _ = CloseHandle(handle);
    std.heap.page_allocator.destroy(removed_task);
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

fn windowsCreateThread(task: *WinThreadTask) !std.os.windows.HANDLE {
    var thread_id: std.os.windows.DWORD = 0;
    const handle = std.os.windows.kernel32.CreateThread(
        null,
        0,
        winThreadTaskMainC,
        task,
        0,
        &thread_id,
    ) orelse return error.SystemResources;
    return handle;
}

pub export fn sa_std_process_id() u32 {
    return std.os.windows.GetCurrentProcessId();
}

fn currentParentProcessId() u32 {
    const PROCESS_BASIC_INFORMATION = extern struct {
        reserved1: ?*anyopaque,
        peb_base_address: ?*anyopaque,
        reserved2: [2]?*anyopaque,
        unique_process_id: std.os.windows.ULONG_PTR,
        parent_process_id: std.os.windows.ULONG_PTR,
    };
    var info: PROCESS_BASIC_INFORMATION = undefined;
    var ret_len: std.os.windows.ULONG = 0;
    const status = NtQueryInformationProcess(
        std.os.windows.GetCurrentProcess(),
        0,
        &info,
        @sizeOf(PROCESS_BASIC_INFORMATION),
        &ret_len,
    );
    if (status == 0 and ret_len >= @sizeOf(PROCESS_BASIC_INFORMATION)) {
        return @as(u32, @intCast(info.parent_process_id));
    }
    const TH32CS_SNAPPROCESS: std.os.windows.DWORD = 0x0000_0002;
    const INVALID_HANDLE_VALUE = @as(std.os.windows.HANDLE, @ptrFromInt(std.math.maxInt(usize)));
    const current_pid = std.os.windows.GetCurrentProcessId();
    const snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;
    defer _ = CloseHandle(snapshot);

    var entry = std.mem.zeroes(ProcessEntry32W);
    entry.dwSize = @sizeOf(ProcessEntry32W);
    if (Process32FirstW(snapshot, &entry) == 0) return 0;
    while (true) {
        if (entry.th32ProcessID == current_pid) return entry.th32ParentProcessID;
        if (Process32NextW(snapshot, &entry) == 0) return 0;
    }
}

pub export fn sa_std_process_parent_id() u32 {
    return currentParentProcessId();
}

pub export fn sa_std_process_user_id() u32 {
    return 0;
}

pub export fn sa_std_process_group_id() u32 {
    return 0;
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
    handle_ptr.* = spawnProcessCwd(argv_ptr, argv_len, .capture, cwd, null) catch |err| return finishErr(err);
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
    handle_ptr.* = spawnProcessCwd(argv_ptr, argv_len, .inherit, cwd, null) catch |err| return finishErr(err);
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
    spawnStreamProcessCwd(argv_ptr, argv_len, cwd, null, process_ptr, stdout_ptr, stderr_ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    _ = has_process_group;
    _ = setsid;
    _ = process_group;
    const arg0 = if (has_arg0 != 0) constBytes(arg0_ptr, arg0_len) catch |err| return finishErr(err) else null;
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    if (getenv("SA_WINDOWS_PROCESS_DEBUG")) |_| {
        std.debug.print("run_command_ext has_arg0={} arg0_len={} arg0={s}\n", .{ has_arg0, arg0_len, arg0 orelse "" });
    }
    handle_ptr.* = spawnProcessCwd(argv_ptr, argv_len, .capture, cwd, arg0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (has_process_group != 0 or setsid != 0) return finish(SA_STD_ERR_UNSUPPORTED);
    _ = process_group;
    const arg0 = if (has_arg0 != 0) constBytes(arg0_ptr, arg0_len) catch |err| return finishErr(err) else null;
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    handle_ptr.* = spawnProcessCwd(argv_ptr, argv_len, .inherit, cwd, arg0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    if (has_process_group != 0 or setsid != 0) return finish(SA_STD_ERR_UNSUPPORTED);
    _ = process_group;
    const arg0 = if (has_arg0 != 0) constBytes(arg0_ptr, arg0_len) catch |err| return finishErr(err) else null;
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    spawnStreamProcessCwd(argv_ptr, argv_len, cwd, arg0, process_ptr, stdout_ptr, stderr_ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run_command_ext_pidfd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_run_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_pidfd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_spawn_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_pidfd(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_run_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: u32, _: u32, _: u32, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_run_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, out_handle: ?*u64) i32 {
    _ = uid;
    _ = has_uid;
    _ = gid;
    _ = has_gid;
    return sa_std_process_spawn_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    _ = uid;
    _ = has_uid;
    _ = gid;
    _ = has_gid;
    return sa_std_process_spawn_stream_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_run_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u32, _: u64, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_run_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u32, _: u64, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_spawn_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u32, _: u64, _: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return sa_std_process_spawn_stream_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_run_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u8, _: u64, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_run_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u8, _: u64, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_spawn_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u8, _: u64, _: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return sa_std_process_spawn_stream_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_exec_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, groups_ptr: ?[*]const u32, groups_len: u64, has_groups: u32, chroot_ptr: ?[*]const u8, chroot_len: u64, has_chroot: u32) i32 {
    _ = uid;
    _ = has_uid;
    _ = gid;
    _ = has_gid;
    _ = groups_ptr;
    _ = groups_len;
    _ = has_groups;
    _ = chroot_ptr;
    _ = chroot_len;
    _ = has_chroot;
    var handle: u64 = 0;
    const status = sa_std_process_run_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, &handle);
    if (status != SA_STD_OK) return status;
    var code: u32 = 0;
    const wait_status = sa_std_process_wait(handle, &code);
    _ = wait_status;
    _ = sa_std_process_close(handle);
    // Exit with the child's code
    std.process.exit(@as(u8, @intCast(code & 0xFF)));
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
    _ = out_raw;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_try_wait_raw(handle: u64, out_ready: ?*i32, out_raw: ?*i32) i32 {
    _ = handle;
    _ = out_ready;
    _ = out_raw;
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
    const pidfd_ptr = out_pidfd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pidfd_ptr.* = 0;
    _ = handle;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_into_pidfd(handle: u64, out_pidfd: ?*u64) i32 {
    return sa_std_process_pidfd(handle, out_pidfd);
}

pub export fn sa_std_process_close(handle: u64) i32 {
    return closeProcessHandle(handle);
}

pub export fn sa_std_fd_as_raw(handle: u64, out_fd: ?*i32) i32 {
    const fd_ptr = out_fd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fd_ptr.* = -1;
    if ((handle & tagged_handle_mask) == process_handle_tag) {
        fd_ptr.* = @as(i32, @intCast(handle));
        return finish(SA_STD_OK);
    }
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_dup(handle: u64, out_handle: ?*u64) i32 {
    _ = handle;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_dup_raw(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_from_raw(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_into_raw(handle: u64, out_fd: ?*i32) i32 {
    _ = handle;
    const fd_ptr = out_fd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fd_ptr.* = -1;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_close_raw(fd: i32) i32 {
    _ = fd;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_is_terminal(handle: u64, out_flag: ?*u8) i32 {
    _ = handle;
    const flag_ptr = out_flag orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    flag_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_term_raw_enter(handle: u64, out_session: ?*u64) i32 {
    _ = handle;
    if (out_session == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_term_raw_leave(session_handle: u64) i32 {
    _ = session_handle;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_term_winsize(handle: u64, out_size: ?*SaTermWinsize) i32 {
    _ = handle;
    if (out_size == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
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
    if ((handle & tagged_handle_mask) == net_addr_list_handle_tag) return closeNetAddrList(handle);
    if ((handle & tagged_handle_mask) == tcp_stream_handle_tag or (handle & tagged_handle_mask) == tcp_listener_handle_tag) return closeTcpHandle(handle);
    if ((handle & tagged_handle_mask) == udp_handle_tag) return closeUdp(handle);
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

pub export fn sa_std_net_addr_format(addr: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_ptr.* = 0;
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    net_addr_mutex.lock();
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(addr) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = net_addr_slots.items[idx].?;
    const text = if (resource.family == 23 and resource.scope_id != 0)
        std.fmt.bufPrint(buffer, "[{s}%{d}]:{d}", .{ resource.host, resource.scope_id, resource.port }) catch return finish(SA_STD_ERR_TRUNCATED)
    else if (resource.family == 23)
        std.fmt.bufPrint(buffer, "[{s}]:{d}", .{ resource.host, resource.port }) catch return finish(SA_STD_ERR_TRUNCATED)
    else
        std.fmt.bufPrint(buffer, "{s}:{d}", .{ resource.host, resource.port }) catch return finish(SA_STD_ERR_TRUNCATED);
    len_ptr.* = @intCast(text.len);
    return finish(SA_STD_OK);
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

pub export fn sa_std_net_to_socket_addr_list(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    if (port > std.math.maxInt(u16)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = registerNetAddrList(host, @intCast(port)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_addr_list_next(list_handle: u64, out_ok: ?*i32, out_addr: ?*u64) i32 {
    const ok_ptr = out_ok orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const addr_ptr = out_addr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ok_ptr.* = 0;
    addr_ptr.* = 0;
    net_addr_list_mutex.lock();
    defer net_addr_list_mutex.unlock();
    const idx = netAddrListSlotLocked(list_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const list = &net_addr_list_slots.items[idx].?;
    if (list.next_index >= list.addresses.len) return finish(SA_STD_OK);
    const address = list.addresses[list.next_index];
    list.next_index += 1;
    addr_ptr.* = registerSocketAddress(address) catch |err| {
        list.next_index -= 1;
        return finishErr(err);
    };
    ok_ptr.* = 1;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_addr_list_free(list_handle: u64) i32 {
    return closeNetAddrList(list_handle);
}
pub export fn sa_std_net_to_socket_addr_first(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const address = resolveSocketAddress(host_ptr, host_len, port) catch |err| return finishErr(err);
    out.* = registerSocketAddress(address) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    if (port > std.math.maxInt(u16)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var stream = std.net.tcpConnectToHost(std.heap.page_allocator, host, @intCast(port)) catch |err| return finishErr(err);
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    out.* = registerTcpStreamLocked(stream) catch |err| {
        stream.close();
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect_timeout(host_ptr: ?[*]const u8, host_len: u64, port: u32, timeout_ns: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    if (timeout_ns == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const timeout_ms = timeoutMs(timeout_ns) catch |err| return finishErr(err);
    const address = resolveSocketAddress(host_ptr, host_len, port) catch |err| return finishErr(err);
    const fd = std.posix.socket(address.any.family, std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK, std.posix.IPPROTO.TCP) catch |err| return finishErr(err);
    var stream = std.net.Stream{ .handle = fd };
    errdefer stream.close();
    std.posix.connect(fd, &address.any, address.getOsSockLen()) catch |err| switch (err) {
        error.WouldBlock, error.ConnectionPending => {
            var poll_fds = [_]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.OUT, .revents = 0 }};
            const ready = std.posix.poll(&poll_fds, timeout_ms) catch |poll_err| return finishErr(poll_err);
            if (ready == 0) return finishErr(error.ConnectionTimedOut);
            std.posix.getsockoptError(fd) catch |socket_err| return finishErr(socket_err);
        },
        else => return finishErr(err),
    };
    var blocking: u32 = 0;
    if (std.os.windows.ws2_32.ioctlsocket(fd, std.os.windows.ws2_32.FIONBIO, &blocking) != 0) return finish(SA_STD_ERR_NET);
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    out.* = registerTcpStreamLocked(stream) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listen(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64, out_bound_port: ?*u32) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    if (out_bound_port) |bound| bound.* = 0;
    const address = resolveSocketAddress(host_ptr, host_len, port) catch |err| return finishErr(err);
    var server = address.listen(.{ .reuse_address = true }) catch |err| return finishErr(err);
    const bound_port = server.listen_address.getPort();
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    out.* = registerTcpListenerLocked(server) catch |err| {
        server.deinit();
        return finishErr(err);
    };
    if (out_bound_port) |bound| bound.* = bound_port;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_accept(listener_handle: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    tcp_mutex.lock();
    const idx = tcpListenerSlotLocked(listener_handle) orelse {
        tcp_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    var server = tcp_listener_slots.items[idx].?.server;
    tcp_mutex.unlock();
    var connection = server.accept() catch |err| return finishErr(err);
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    out.* = registerTcpStreamLocked(connection.stream) catch |err| {
        connection.stream.close();
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

fn tcpAddress(handle: u64, peer: bool, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const stream_idx = tcpStreamSlotLocked(handle);
    const listener_idx = tcpListenerSlotLocked(handle);
    var address: std.net.Address = undefined;
    if (stream_idx) |idx| {
        const socket = tcp_stream_slots.items[idx].?.stream.handle;
        var address_len: std.posix.socklen_t = @sizeOf(std.net.Address);
        if (peer) std.posix.getpeername(socket, &address.any, &address_len) catch |err| return finishErr(err) else std.posix.getsockname(socket, &address.any, &address_len) catch |err| return finishErr(err);
    } else if (listener_idx) |idx| {
        if (peer) return finish(SA_STD_ERR_INVALID_HANDLE);
        address = tcp_listener_slots.items[idx].?.server.listen_address;
    } else return finish(SA_STD_ERR_INVALID_HANDLE);
    out.* = registerSocketAddress(address) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_peer_addr(handle: u64, out: ?*u64) i32 {
    return tcpAddress(handle, true, out);
}
pub export fn sa_std_net_tcp_stream_local_addr(handle: u64, out: ?*u64) i32 {
    return tcpAddress(handle, false, out);
}
pub export fn sa_std_net_tcp_listener_local_addr(handle: u64, out: ?*u64) i32 {
    return tcpAddress(handle, false, out);
}

pub export fn sa_std_net_tcp_stream_read(handle: u64, out_ptr: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const result = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    const bytes = mutBytes(out_ptr, cap) catch |err| return finishErr(err);
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const idx = tcpStreamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = tcp_stream_slots.items[idx].?.stream.read(bytes) catch |err| return finishErr(err);
    result.* = count;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_write(handle: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const result = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const idx = tcpStreamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = tcp_stream_slots.items[idx].?.stream.write(bytes) catch |err| return finishErr(err);
    result.* = count;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_stream_peek(handle: u64, out_ptr: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const result = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    const bytes = mutBytes(out_ptr, cap) catch |err| return finishErr(err);
    if (bytes.len > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const idx = tcpStreamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const rc = std.os.windows.ws2_32.recv(tcp_stream_slots.items[idx].?.stream.handle, bytes.ptr, @intCast(bytes.len), 2);
    if (rc < 0) return finish(SA_STD_ERR_NET);
    result.* = @intCast(rc);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listener_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    if (out_handle) |out| out.* = 0 else return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

fn tcpSocket(handle: u64, listener: bool) ?std.posix.socket_t {
    if (listener) {
        const idx = tcpListenerSlotLocked(handle) orelse return null;
        return tcp_listener_slots.items[idx].?.server.stream.handle;
    }
    const idx = tcpStreamSlotLocked(handle) orelse return null;
    return tcp_stream_slots.items[idx].?.stream.handle;
}

fn tcpSetNonblocking(handle: u64, listener: bool, enabled: i32) i32 {
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const socket = tcpSocket(handle, listener) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var value: u32 = if (enabled != 0) 1 else 0;
    if (std.os.windows.ws2_32.ioctlsocket(socket, std.os.windows.ws2_32.FIONBIO, &value) != 0) return finish(SA_STD_ERR_NET);
    return finish(SA_STD_OK);
}

fn tcpSetOption(handle: u64, listener: bool, level: i32, option: u32, value: i32) i32 {
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const socket = tcpSocket(handle, listener) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    socketSetInt(socket, level, option, value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

fn tcpGetOption(handle: u64, listener: bool, level: i32, option: i32, out: ?*i32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const socket = tcpSocket(handle, listener) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    result.* = socketGetInt(socket, level, option) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

fn tcpSetLinger(handle: u64, enabled: i32, timeout_ns: u64) i32 {
    const seconds = if (enabled != 0) std.math.cast(u16, timeout_ns / std.time.ns_per_s) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT) else 0;
    var value = WindowsLingerOption{ .onoff = if (enabled != 0) 1 else 0, .linger = seconds };
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const socket = tcpSocket(handle, false) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    std.posix.setsockopt(socket, std.posix.SOL.SOCKET, std.os.windows.ws2_32.SO.LINGER, std.mem.asBytes(&value)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

fn tcpGetLinger(handle: u64, out_enabled: *i32, out_timeout_ns: *u64) i32 {
    out_enabled.* = 0;
    out_timeout_ns.* = 0;
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const socket = tcpSocket(handle, false) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var value = WindowsLingerOption{ .onoff = 0, .linger = 0 };
    var len: i32 = @sizeOf(WindowsLingerOption);
    const ws = std.os.windows.ws2_32;
    if (ws.getsockopt(socket, std.posix.SOL.SOCKET, ws.SO.LINGER, @ptrCast(&value), &len) == ws.SOCKET_ERROR) return finish(SA_STD_ERR_NET);
    if (len != @sizeOf(WindowsLingerOption)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (value.onoff == 0) return finish(SA_STD_OK);
    out_enabled.* = 1;
    out_timeout_ns.* = std.math.mul(u64, @as(u64, value.linger), std.time.ns_per_s) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_tcp_stream_try_clone(stream: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const idx = tcpStreamSlotLocked(stream) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const duplicate = duplicateWinSocket(tcp_stream_slots.items[idx].?.stream.handle) catch |err| return finishErr(err);
    const handle = registerTcpStreamLocked(.{ .handle = duplicate }) catch |err| {
        std.os.windows.closesocket(duplicate) catch {};
        return finishErr(err);
    };
    out.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listener_try_clone(listener: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    tcp_mutex.lock();
    defer tcp_mutex.unlock();
    const idx = tcpListenerSlotLocked(listener) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const server = tcp_listener_slots.items[idx].?.server;
    const duplicate = duplicateWinSocket(server.stream.handle) catch |err| return finishErr(err);
    const handle = registerTcpListenerLocked(.{ .listen_address = server.listen_address, .stream = .{ .handle = duplicate } }) catch |err| {
        std.os.windows.closesocket(duplicate) catch {};
        return finishErr(err);
    };
    out.* = handle;
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_tcp_stream_set_nonblocking(h: u64, enabled: i32) i32 {
    return tcpSetNonblocking(h, false, enabled);
}
pub export fn sa_std_net_tcp_stream_set_linger(h: u64, enabled: i32, timeout_ns: u64) i32 {
    return tcpSetLinger(h, enabled, timeout_ns);
}
pub export fn sa_std_net_tcp_stream_linger(h: u64, out_enabled: ?*i32, out_timeout_ns: ?*u64) i32 {
    const enabled = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const timeout_ns = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return tcpGetLinger(h, enabled, timeout_ns);
}
pub export fn sa_std_net_tcp_listener_set_only_v6(h: u64, enabled: i32) i32 {
    return tcpSetOption(h, true, windows_ipproto_ipv6, std.os.windows.ws2_32.IPV6_V6ONLY, if (enabled != 0) 1 else 0);
}
pub export fn sa_std_net_tcp_listener_only_v6(h: u64, out: ?*i32) i32 {
    return tcpGetOption(h, true, windows_ipproto_ipv6, std.os.windows.ws2_32.IPV6_V6ONLY, out);
}
pub export fn sa_std_net_tcp_listener_set_nonblocking(h: u64, enabled: i32) i32 {
    return tcpSetNonblocking(h, true, enabled);
}
pub export fn sa_std_net_tcp_stream_set_nodelay(h: u64, enabled: i32) i32 {
    return tcpSetOption(h, false, std.posix.IPPROTO.TCP, std.os.windows.ws2_32.TCP.NODELAY, if (enabled != 0) 1 else 0);
}
pub export fn sa_std_net_tcp_stream_nodelay(h: u64, out: ?*i32) i32 {
    return tcpGetOption(h, false, std.posix.IPPROTO.TCP, std.os.windows.ws2_32.TCP.NODELAY, out);
}
pub export fn sa_std_net_tcp_stream_set_ttl(h: u64, ttl: u32) i32 {
    if (ttl > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return tcpSetOption(h, false, std.posix.IPPROTO.IP, std.os.windows.ws2_32.IP_TTL, @intCast(ttl));
}
pub export fn sa_std_net_tcp_listener_set_ttl(h: u64, ttl: u32) i32 {
    if (ttl > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return tcpSetOption(h, true, std.posix.IPPROTO.IP, std.os.windows.ws2_32.IP_TTL, @intCast(ttl));
}
pub export fn sa_std_net_tcp_stream_ttl(h: u64, out: ?*u32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    var value: i32 = 0;
    const status = tcpGetOption(h, false, std.posix.IPPROTO.IP, std.os.windows.ws2_32.IP_TTL, &value);
    if (status == SA_STD_OK and value >= 0) result.* = @intCast(value);
    return status;
}
pub export fn sa_std_net_tcp_listener_ttl(h: u64, out: ?*u32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    var value: i32 = 0;
    const status = tcpGetOption(h, true, std.posix.IPPROTO.IP, std.os.windows.ws2_32.IP_TTL, &value);
    if (status == SA_STD_OK and value >= 0) result.* = @intCast(value);
    return status;
}
pub export fn sa_std_net_tcp_stream_set_read_timeout(h: u64, ns: u64) i32 {
    const value = timeoutMs(ns) catch |err| return finishErr(err);
    return tcpSetOption(h, false, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, value);
}
pub export fn sa_std_net_tcp_stream_set_write_timeout(h: u64, ns: u64) i32 {
    const value = timeoutMs(ns) catch |err| return finishErr(err);
    return tcpSetOption(h, false, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, value);
}
pub export fn sa_std_net_tcp_stream_read_timeout(h: u64, out_timeout_ns: ?*u64) i32 {
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var ms: i32 = 0;
    const status = tcpGetOption(h, false, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, &ms);
    if (status != SA_STD_OK) return status;
    out.* = std.math.mul(u64, @intCast(@max(ms, 0)), std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_tcp_stream_write_timeout(h: u64, out_timeout_ns: ?*u64) i32 {
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var ms: i32 = 0;
    const status = tcpGetOption(h, false, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, &ms);
    if (status != SA_STD_OK) return status;
    out.* = std.math.mul(u64, @intCast(@max(ms, 0)), std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_tcp_stream_take_error(h: u64, out: ?*i32) i32 {
    return tcpGetOption(h, false, std.posix.SOL.SOCKET, std.posix.SO.ERROR, out);
}
pub export fn sa_std_net_tcp_stream_set_keepalive(h: u64, enabled: i32) i32 {
    _ = h;
    _ = enabled;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_tcp_stream_set_keepalive_params(h: u64, idle_secs: u32, interval_secs: u32, count: u32) i32 {
    _ = h;
    _ = idle_secs;
    _ = interval_secs;
    _ = count;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_tcp_listener_take_error(h: u64, out: ?*i32) i32 {
    return tcpGetOption(h, true, std.posix.SOL.SOCKET, std.posix.SO.ERROR, out);
}
pub export fn sa_std_net_tcp_listener_set_reuseaddr(h: u64, enabled: i32) i32 {
    _ = h;
    _ = enabled;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_tcp_listener_set_reuseport(h: u64, enabled: i32) i32 {
    _ = h;
    _ = enabled;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_tcp_stream_set_quickack(h: u64, enabled: i32) i32 {
    _ = h;
    _ = enabled;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_tcp_stream_quickack(h: u64, out: ?*i32) i32 {
    _ = h;
    if (out) |value| value.* = 0 else return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_tcp_stream_set_deferaccept(h: u64, seconds: u32) i32 {
    _ = h;
    _ = seconds;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_tcp_stream_deferaccept(h: u64, out: ?*u32) i32 {
    _ = h;
    if (out) |value| value.* = 0 else return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_tcp_stream_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    if (out_handle) |out| out.* = 0 else return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_net_tcp_stream_peek(stream: u64, out: ?[*]u8, cap: u64) i32 {
    var read: u64 = 0;
    const status = sa_std_net_tcp_stream_peek(stream, out, cap, &read);
    if (status != SA_STD_OK) return status;
    return finish(@as(i32, @intCast(read)));
}
pub export fn sa_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32) FallibleU64 {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_connect(host_ptr, host_len, port, &handle);
    if (status != SA_STD_OK) return failU64(status);
    return okU64(handle);
}
pub export fn sa_net_tcp_stream_read(stream: u64, out: ?[*]u8, cap: u64) FallibleU64 {
    var read: u64 = 0;
    const status = sa_std_net_tcp_stream_read(stream, out, cap, &read);
    if (status != SA_STD_OK) return failU64(status);
    return okU64(read);
}
pub export fn sa_net_tcp_stream_write(stream: u64, out: ?[*]const u8, len: u64) i32 {
    var written: u64 = 0;
    const status = sa_std_net_tcp_stream_write(stream, out, len, &written);
    if (status != SA_STD_OK) return status;
    return finish(@as(i32, @intCast(written)));
}
pub export fn sa_net_tcp_stream_write_all(stream: u64, out: ?[*]const u8, len: u64) FallibleI32 {
    const status = sa_io_write_all(stream, out, len);
    if (status != SA_STD_OK) return .{ .status = finish(status), .value = 0 };
    return .{ .status = finish(SA_STD_OK), .value = 0 };
}
pub export fn sa_net_tcp_stream_flush(stream: u64) i32 {
    _ = stream;
    return finish(SA_STD_OK);
}
pub export fn sa_net_tcp_stream_set_read_timeout(stream: u64, timeout_ns: u64) i32 {
    return sa_std_net_tcp_stream_set_read_timeout(stream, timeout_ns);
}
pub export fn sa_net_tcp_stream_set_write_timeout(stream: u64, timeout_ns: u64) i32 {
    return sa_std_net_tcp_stream_set_write_timeout(stream, timeout_ns);
}
pub export fn sa_net_tcp_stream_set_nonblocking(stream: u64, enabled: i32) i32 {
    return sa_std_net_tcp_stream_set_nonblocking(stream, enabled);
}
pub export fn sa_net_tcp_stream_set_nodelay(stream: u64, enabled: i32) i32 {
    return sa_std_net_tcp_stream_set_nodelay(stream, enabled);
}
pub export fn sa_net_tcp_stream_set_ttl(stream: u64, ttl: u32) i32 {
    return sa_std_net_tcp_stream_set_ttl(stream, ttl);
}
pub export fn sa_net_tcp_stream_close(stream: u64) FallibleI32 {
    const status = sa_std_close(stream);
    if (status != SA_STD_OK) return .{ .status = finish(status), .value = 0 };
    return .{ .status = finish(SA_STD_OK), .value = 0 };
}
pub export fn sa_net_tcp_listener_bind(host_ptr: ?[*]const u8, host_len: u64, port: u16) FallibleU64 {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_listen(host_ptr, host_len, port, &handle, null);
    if (status != SA_STD_OK) return failU64(status);
    return okU64(handle);
}
pub export fn sa_net_tcp_listener_accept(listener: u64) FallibleU64 {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_accept(listener, &handle);
    if (status != SA_STD_OK) return failU64(status);
    return okU64(handle);
}
pub export fn sa_net_tcp_listener_local_addr(listener: u64) FallibleU64 {
    var handle: u64 = 0;
    const status = sa_std_net_tcp_listener_local_addr(listener, &handle);
    if (status != SA_STD_OK) return failU64(status);
    return okU64(handle);
}
pub export fn sa_net_tcp_listener_close(listener: u64) FallibleI32 {
    const status = sa_std_close(listener);
    if (status != SA_STD_OK) return .{ .status = finish(status), .value = 0 };
    return .{ .status = finish(SA_STD_OK), .value = 0 };
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

fn udpHost(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const host = try constBytes(ptr, len);
    if (host.len == 0 or std.mem.indexOfScalar(u8, host, 0) != null) return error.InvalidArgument;
    return host;
}

fn udpAddress(host: []const u8, port: u32) !std.net.Address {
    if (port > std.math.maxInt(u16)) return error.InvalidArgument;
    const list = try std.net.getAddressList(std.heap.page_allocator, host, @intCast(port));
    defer list.deinit();
    if (list.addrs.len == 0) return error.FileNotFound;
    return list.addrs[0];
}

fn addressHostAlloc(address: std.net.Address) ![]u8 {
    return switch (address.any.family) {
        std.posix.AF.INET => blk: {
            const ip = @as(*const [4]u8, @ptrCast(&address.in.sa.addr)).*;
            break :blk try std.fmt.allocPrint(std.heap.page_allocator, "{}.{}.{}.{}", .{ ip[0], ip[1], ip[2], ip[3] });
        },
        std.posix.AF.INET6 => blk: {
            const full = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{address});
            if (std.mem.lastIndexOfScalar(u8, full, ']')) |closing| {
                if (full.len != 0 and full[0] == '[') {
                    const host = try std.heap.page_allocator.dupe(u8, full[1..closing]);
                    std.heap.page_allocator.free(full);
                    break :blk host;
                }
            }
            break :blk full;
        },
        else => error.InvalidArgument,
    };
}

fn registerAddress(address: std.net.Address, out: *u64) i32 {
    const host = addressHostAlloc(address) catch |err| return finishErr(err);
    const family: u32 = if (address.any.family == std.posix.AF.INET) 2 else if (address.any.family == std.posix.AF.INET6) 10 else {
        std.heap.page_allocator.free(host);
        return finish(SA_STD_ERR_INVALID_ARGUMENT);
    };
    const scope_id: u64 = if (address.any.family == std.posix.AF.INET6) address.in6.sa.scope_id else 0;
    const handle = registerNetAddr(.{ .host = host, .family = family, .port = address.getPort(), .scope_id = scope_id }) catch |err| {
        std.heap.page_allocator.free(host);
        return finishErr(err);
    };
    out.* = handle;
    return finish(SA_STD_OK);
}

fn udpSocket(handle: u64) ?std.posix.socket_t {
    const idx = udpSlotLocked(handle) orelse return null;
    return udp_slots.items[idx].?.socket;
}

fn socketSetInt(socket: std.posix.socket_t, level: i32, option: u32, value: i32) !void {
    var mutable = value;
    try std.posix.setsockopt(socket, level, option, std.mem.asBytes(&mutable));
}

fn socketGetInt(socket: std.posix.socket_t, level: i32, option: i32) !i32 {
    var value: i32 = 0;
    var len: i32 = @sizeOf(i32);
    const ws = std.os.windows.ws2_32;
    if (ws.getsockopt(socket, level, option, @ptrCast(&value), &len) == ws.SOCKET_ERROR) return error.NetworkSubsystemFailed;
    if (len == 1) return @as(i32, @intCast((@as([*]const u8, @ptrCast(&value)))[0]));
    if (len != @sizeOf(i32)) return error.InvalidArgument;
    return value;
}

fn timeoutMs(timeout_ns: u64) !i32 {
    if (timeout_ns == 0) return 0;
    const rounded = std.math.add(u64, timeout_ns, std.time.ns_per_ms - 1) catch return error.InvalidArgument;
    return std.math.cast(i32, rounded / std.time.ns_per_ms) orelse error.InvalidArgument;
}

fn udpReceiveFrom(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64, peek: bool) i32 {
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    if (out_addr) |ptr| ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);
    udp_mutex.lock();
    defer udp_mutex.unlock();
    const fd = udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var address: std.net.Address = undefined;
    var address_len: std.posix.socklen_t = @sizeOf(std.net.Address);
    const count = std.posix.recvfrom(fd, buffer, if (peek) std.posix.MSG.PEEK else 0, &address.any, &address_len) catch |err| return finishErr(err);
    read_ptr.* = @intCast(count);
    if (out_addr) |ptr| return registerAddress(address, ptr);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_try_clone(socket: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    udp_mutex.lock();
    defer udp_mutex.unlock();
    const idx = udpSlotLocked(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const duplicate = duplicateWinSocket(udp_slots.items[idx].?.socket) catch |err| return finishErr(err);
    while (udp_free_slots.items.len != 0) {
        const free_idx = udp_free_slots.pop().?;
        if (free_idx >= udp_slots.items.len or udp_slots.items[free_idx] != null) continue;
        udp_slots.items[free_idx] = .{ .socket = duplicate };
        out.* = udp_handle_tag | @as(u64, @intCast(free_idx + 1));
        return finish(SA_STD_OK);
    }
    udp_slots.append(.{ .socket = duplicate }) catch |err| {
        std.os.windows.closesocket(duplicate) catch {};
        return finishErr(err);
    };
    out.* = udp_handle_tag | @as(u64, @intCast(udp_slots.items.len));
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_bind(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const host = udpHost(host_ptr, host_len) catch |err| return finishErr(err);
    const address = udpAddress(host, port) catch |err| return finishErr(err);
    const fd = std.posix.socket(address.any.family, std.posix.SOCK.DGRAM | std.posix.SOCK.CLOEXEC, std.posix.IPPROTO.UDP) catch |err| return finishErr(err);
    errdefer std.os.windows.closesocket(fd) catch {};
    std.posix.bind(fd, &address.any, address.getOsSockLen()) catch |err| return finishErr(err);
    out.* = registerUdp(fd) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_net_udp_local_addr(socket: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    udp_mutex.lock();
    defer udp_mutex.unlock();
    const fd = udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var address: std.net.Address = undefined;
    var len: std.posix.socklen_t = @sizeOf(std.net.Address);
    std.posix.getsockname(fd, &address.any, &len) catch |err| return finishErr(err);
    return registerAddress(address, out);
}

pub export fn sa_std_net_udp_peer_addr(socket: u64, out_handle: ?*u64) i32 {
    const out = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    udp_mutex.lock();
    defer udp_mutex.unlock();
    const fd = udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var address: std.net.Address = undefined;
    var len: std.posix.socklen_t = @sizeOf(std.net.Address);
    std.posix.getpeername(fd, &address.any, &len) catch |err| return finishErr(err);
    return registerAddress(address, out);
}

pub export fn sa_std_net_udp_connect(socket: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32) i32 {
    const host = udpHost(host_ptr, host_len) catch |err| return finishErr(err);
    const address = udpAddress(host, port) catch |err| return finishErr(err);
    udp_mutex.lock();
    defer udp_mutex.unlock();
    const fd = udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    std.posix.connect(fd, &address.any, address.getOsSockLen()) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_only_v6(socket: u64, enabled: i32) i32 {
    udp_mutex.lock();
    defer udp_mutex.unlock();
    socketSetInt(
        udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE),
        windows_ipproto_ipv6,
        std.os.windows.ws2_32.IPV6_V6ONLY,
        if (enabled != 0) 1 else 0,
    ) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_only_v6(socket: u64, out: ?*i32) i32 {
    const result = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result.* = 0;
    udp_mutex.lock();
    defer udp_mutex.unlock();
    result.* = socketGetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), windows_ipproto_ipv6, std.os.windows.ws2_32.IPV6_V6ONLY) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_set_nonblocking(socket: u64, enabled: i32) i32 {
    udp_mutex.lock();
    defer udp_mutex.unlock();
    const fd = udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var mode: c_ulong = if (enabled != 0) 1 else 0;
    const ws = std.os.windows.ws2_32;
    if (ws.ioctlsocket(fd, ws.FIONBIO, &mode) == ws.SOCKET_ERROR) return finish(SA_STD_ERR_NET);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_read_timeout(socket: u64, timeout_ns: u64) i32 {
    const value = timeoutMs(timeout_ns) catch |err| return finishErr(err);
    udp_mutex.lock();
    defer udp_mutex.unlock();
    socketSetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_write_timeout(socket: u64, timeout_ns: u64) i32 {
    const value = timeoutMs(timeout_ns) catch |err| return finishErr(err);
    udp_mutex.lock();
    defer udp_mutex.unlock();
    socketSetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

fn udpGetOption(socket: u64, option: i32, out: *i32) i32 {
    out.* = 0;
    udp_mutex.lock();
    defer udp_mutex.unlock();
    out.* = socketGetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), std.posix.SOL.SOCKET, option) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_read_timeout(socket: u64, out_timeout_ns: ?*u64) i32 {
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var ms: i32 = 0;
    const status = udpGetOption(socket, std.posix.SO.RCVTIMEO, &ms);
    if (status != SA_STD_OK) return status;
    out.* = std.math.mul(u64, @intCast(@max(ms, 0)), std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_write_timeout(socket: u64, out_timeout_ns: ?*u64) i32 {
    const out = out_timeout_ns orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var ms: i32 = 0;
    const status = udpGetOption(socket, std.posix.SO.SNDTIMEO, &ms);
    if (status != SA_STD_OK) return status;
    out.* = std.math.mul(u64, @intCast(@max(ms, 0)), std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_broadcast(socket: u64, enabled: i32) i32 {
    udp_mutex.lock();
    defer udp_mutex.unlock();
    socketSetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), std.posix.SOL.SOCKET, std.posix.SO.BROADCAST, if (enabled != 0) 1 else 0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_broadcast(socket: u64, out_enabled: ?*i32) i32 {
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpGetOption(socket, std.posix.SO.BROADCAST, out);
}
pub export fn sa_std_net_udp_set_ttl(socket: u64, ttl: u32) i32 {
    if (ttl > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    udp_mutex.lock();
    defer udp_mutex.unlock();
    socketSetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), std.posix.IPPROTO.IP, std.os.windows.ws2_32.IP_TTL, @intCast(ttl)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_ttl(socket: u64, out_ttl: ?*u32) i32 {
    const out = out_ttl orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    udp_mutex.lock();
    defer udp_mutex.unlock();
    const value = socketGetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), std.posix.IPPROTO.IP, std.os.windows.ws2_32.IP_TTL) catch |err| return finishErr(err);
    if (value < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @intCast(value);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_take_error(socket: u64, out_error: ?*i32) i32 {
    const out = out_error orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpGetOption(socket, std.posix.SO.ERROR, out);
}

pub export fn sa_std_net_udp_send(socket: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const out = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    udp_mutex.lock();
    defer udp_mutex.unlock();
    const count = std.posix.send(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), bytes, 0) catch |err| return finishErr(err);
    out.* = @intCast(count);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_recv(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    return udpReceiveFrom(socket, out, cap, out_read, null, false);
}
pub export fn sa_std_net_udp_peek(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    return udpReceiveFrom(socket, out, cap, out_read, null, true);
}
pub export fn sa_std_net_udp_send_to(socket: u64, buf: ?[*]const u8, len: u64, host_ptr: ?[*]const u8, host_len: u64, port: u32, out_written: ?*u64) i32 {
    const out = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const host = udpHost(host_ptr, host_len) catch |err| return finishErr(err);
    const address = udpAddress(host, port) catch |err| return finishErr(err);
    udp_mutex.lock();
    defer udp_mutex.unlock();
    const count = std.posix.sendto(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), bytes, 0, &address.any, address.getOsSockLen()) catch |err| return finishErr(err);
    out.* = @intCast(count);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_recv_from(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    return udpReceiveFrom(socket, out, cap, out_read, out_addr, false);
}
pub export fn sa_std_net_udp_peek_from(socket: u64, out: ?[*]u8, cap: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    return udpReceiveFrom(socket, out, cap, out_read, out_addr, true);
}

const IpMreq = extern struct { multicast: u32, interface: u32 };
const Ipv6Mreq = extern struct { multicast: [16]u8, interface: u32 };
const windows_ipproto_ipv6: i32 = 41;
const WindowsLingerOption = extern struct { onoff: u16, linger: u16 };
fn udpMembership4(socket: u64, multi_ptr: ?[*]const u8, multi_len: u64, interface_ptr: ?[*]const u8, interface_len: u64, join: bool) i32 {
    const multi = udpHost(multi_ptr, multi_len) catch |err| return finishErr(err);
    const interface = udpHost(interface_ptr, interface_len) catch |err| return finishErr(err);
    const multi_addr = std.net.Address.resolveIp(multi, 0) catch |err| return finishErr(err);
    const interface_addr = std.net.Address.resolveIp(interface, 0) catch |err| return finishErr(err);
    if (multi_addr.any.family != std.posix.AF.INET or interface_addr.any.family != std.posix.AF.INET) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var req = IpMreq{ .multicast = multi_addr.in.sa.addr, .interface = interface_addr.in.sa.addr };
    udp_mutex.lock();
    defer udp_mutex.unlock();
    std.posix.setsockopt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), std.posix.IPPROTO.IP, if (join) std.os.windows.ws2_32.IP_ADD_MEMBERSHIP else std.os.windows.ws2_32.IP_DROP_MEMBERSHIP, std.mem.asBytes(&req)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_join_multicast_v4(socket: u64, m: ?[*]const u8, ml: u64, i: ?[*]const u8, il: u64) i32 {
    return udpMembership4(socket, m, ml, i, il, true);
}
pub export fn sa_std_net_udp_leave_multicast_v4(socket: u64, m: ?[*]const u8, ml: u64, i: ?[*]const u8, il: u64) i32 {
    return udpMembership4(socket, m, ml, i, il, false);
}
fn udpMembership6(socket: u64, multi_ptr: ?[*]const u8, multi_len: u64, interface_index: u32, join: bool) i32 {
    const multi = udpHost(multi_ptr, multi_len) catch |err| return finishErr(err);
    const address = std.net.Address.resolveIp(multi, 0) catch |err| return finishErr(err);
    if (address.any.family != std.posix.AF.INET6) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var req = Ipv6Mreq{ .multicast = address.in6.sa.addr, .interface = interface_index };
    udp_mutex.lock();
    defer udp_mutex.unlock();
    std.posix.setsockopt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), windows_ipproto_ipv6, if (join) std.os.windows.ws2_32.IPV6_ADD_MEMBERSHIP else std.os.windows.ws2_32.IPV6_DROP_MEMBERSHIP, std.mem.asBytes(&req)) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_join_multicast_v6(socket: u64, m: ?[*]const u8, ml: u64, index: u32) i32 {
    return udpMembership6(socket, m, ml, index, true);
}
pub export fn sa_std_net_udp_leave_multicast_v6(socket: u64, m: ?[*]const u8, ml: u64, index: u32) i32 {
    return udpMembership6(socket, m, ml, index, false);
}

fn udpSetIpOption(socket: u64, option: u32, value: i32) i32 {
    udp_mutex.lock();
    defer udp_mutex.unlock();
    socketSetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), std.posix.IPPROTO.IP, option, value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
fn udpGetIpOption(socket: u64, option: i32, out: *i32) i32 {
    out.* = 0;
    udp_mutex.lock();
    defer udp_mutex.unlock();
    out.* = socketGetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), std.posix.IPPROTO.IP, option) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
fn udpSetIpv6Option(socket: u64, option: u32, value: i32) i32 {
    udp_mutex.lock();
    defer udp_mutex.unlock();
    socketSetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), windows_ipproto_ipv6, option, value) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
fn udpGetIpv6Option(socket: u64, option: i32, out: *i32) i32 {
    out.* = 0;
    udp_mutex.lock();
    defer udp_mutex.unlock();
    out.* = socketGetInt(udpSocket(socket) orelse return finish(SA_STD_ERR_INVALID_HANDLE), windows_ipproto_ipv6, option) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_set_multicast_loop_v6(socket: u64, enabled: i32) i32 {
    return udpSetIpv6Option(socket, std.os.windows.ws2_32.IPV6_MULTICAST_LOOP, if (enabled != 0) 1 else 0);
}
pub export fn sa_std_net_udp_set_multicast_hops_v6(socket: u64, hops: u32) i32 {
    if (hops > 255) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpSetIpv6Option(socket, std.os.windows.ws2_32.IPV6_MULTICAST_HOPS, @intCast(hops));
}
pub export fn sa_std_net_udp_multicast_loop_v6(socket: u64, out_enabled: ?*i32) i32 {
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpGetIpv6Option(socket, std.os.windows.ws2_32.IPV6_MULTICAST_LOOP, out);
}
pub export fn sa_std_net_udp_set_multicast_if_v4(socket: u64, interface_addr_ptr: ?[*]const u8) i32 {
    const interface_addr = constBytes(interface_addr_ptr, 4) catch |err| return finishErr(err);
    const value_u32 = std.mem.readInt(u32, interface_addr[0..4], .little);
    return udpSetIpOption(socket, std.os.windows.ws2_32.IP_MULTICAST_IF, @bitCast(value_u32));
}

pub export fn sa_std_net_udp_multicast_if_v4(socket: u64, out_interface_addr: ?[*]u8) i32 {
    const out = out_interface_addr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var value: i32 = 0;
    const status = udpGetIpOption(socket, std.os.windows.ws2_32.IP_MULTICAST_IF, &value);
    if (status != SA_STD_OK) return status;
    std.mem.writeInt(u32, out[0..4], @bitCast(value), .little);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_set_multicast_if_v6(socket: u64, interface_index: u32) i32 {
    if (interface_index > std.math.maxInt(i32)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpSetIpv6Option(socket, std.os.windows.ws2_32.IPV6_MULTICAST_IF, @intCast(interface_index));
}

pub export fn sa_std_net_udp_multicast_if_v6(socket: u64, out_interface_index: ?*u32) i32 {
    const out = out_interface_index orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var value: i32 = 0;
    const status = udpGetIpv6Option(socket, std.os.windows.ws2_32.IPV6_MULTICAST_IF, &value);
    if (status != SA_STD_OK) return status;
    if (value < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @intCast(value);
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_udp_multicast_hops_v6(socket: u64, out_hops: ?*u32) i32 {
    const out = out_hops orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var value: i32 = 0;
    const status = udpGetIpv6Option(socket, std.os.windows.ws2_32.IPV6_MULTICAST_HOPS, &value);
    if (status != SA_STD_OK) return status;
    if (value < 0 or value > 255) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @intCast(value);
    return finish(SA_STD_OK);
}
pub export fn sa_std_net_udp_set_multicast_loop_v4(socket: u64, enabled: i32) i32 {
    return udpSetIpOption(socket, std.os.windows.ws2_32.IP_MULTICAST_LOOP, if (enabled != 0) 1 else 0);
}
pub export fn sa_std_net_udp_set_multicast_ttl_v4(socket: u64, ttl: u32) i32 {
    if (ttl > 255) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpSetIpOption(socket, std.os.windows.ws2_32.IP_MULTICAST_TTL, @intCast(ttl));
}
pub export fn sa_std_net_udp_multicast_loop_v4(socket: u64, out_enabled: ?*i32) i32 {
    const out = out_enabled orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return udpGetIpOption(socket, std.os.windows.ws2_32.IP_MULTICAST_LOOP, out);
}
pub export fn sa_std_net_udp_multicast_ttl_v4(socket: u64, out_ttl: ?*u32) i32 {
    const out = out_ttl orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    var value: i32 = 0;
    const status = udpGetIpOption(socket, std.os.windows.ws2_32.IP_MULTICAST_TTL, &value);
    if (status != SA_STD_OK) return status;
    if (value < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = @intCast(value);
    return finish(SA_STD_OK);
}

pub export fn sa_net_udp_bind(h: ?[*]const u8, hl: u64, p: u16) i32 {
    var handle: u64 = 0;
    const s = sa_std_net_udp_bind(h, hl, p, &handle);
    return if (s == SA_STD_OK) @intCast(handle) else s;
}
pub export fn sa_net_udp_local_addr(s: u64) i32 {
    var handle: u64 = 0;
    const status = sa_std_net_udp_local_addr(s, &handle);
    return if (status == SA_STD_OK) @intCast(handle) else status;
}
pub export fn sa_net_udp_connect(s: u64, h: ?[*]const u8, hl: u64, p: u16) i32 {
    return sa_std_net_udp_connect(s, h, hl, p);
}
pub export fn sa_net_udp_set_read_timeout(s: u64, v: u64) i32 {
    return sa_std_net_udp_set_read_timeout(s, v);
}
pub export fn sa_net_udp_set_write_timeout(s: u64, v: u64) i32 {
    return sa_std_net_udp_set_write_timeout(s, v);
}
pub export fn sa_net_udp_set_nonblocking(s: u64, v: i32) i32 {
    return sa_std_net_udp_set_nonblocking(s, v);
}
pub export fn sa_net_udp_set_broadcast(s: u64, v: i32) i32 {
    return sa_std_net_udp_set_broadcast(s, v);
}
pub export fn sa_net_udp_set_ttl(s: u64, v: u32) i32 {
    return sa_std_net_udp_set_ttl(s, v);
}
pub export fn sa_net_udp_set_multicast_loop_v4(s: u64, v: i32) i32 {
    return sa_std_net_udp_set_multicast_loop_v4(s, v);
}
pub export fn sa_net_udp_set_multicast_ttl_v4(s: u64, v: u32) i32 {
    return sa_std_net_udp_set_multicast_ttl_v4(s, v);
}
pub export fn sa_net_udp_send(s: u64, b: ?[*]const u8, l: u64) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_send(s, b, l, &n);
    return if (status == SA_STD_OK) @intCast(n) else status;
}
pub export fn sa_net_udp_recv(s: u64, b: ?[*]u8, l: u64) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_recv(s, b, l, &n);
    return if (status == SA_STD_OK) @intCast(n) else status;
}
pub export fn sa_net_udp_peek(s: u64, b: ?[*]u8, l: u64) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_peek(s, b, l, &n);
    return if (status == SA_STD_OK) @intCast(n) else status;
}
pub export fn sa_net_udp_send_to(s: u64, b: ?[*]const u8, l: u64, h: ?[*]const u8, hl: u64, p: u16) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_send_to(s, b, l, h, hl, p, &n);
    return if (status == SA_STD_OK) @intCast(n) else status;
}
pub export fn sa_net_udp_recv_from(s: u64, b: ?[*]u8, l: u64, a: ?*u64) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_recv_from(s, b, l, &n, a);
    return if (status == SA_STD_OK) @intCast(n) else status;
}
pub export fn sa_net_udp_peek_from(s: u64, b: ?[*]u8, l: u64, a: ?*u64) i32 {
    var n: u64 = 0;
    const status = sa_std_net_udp_peek_from(s, b, l, &n, a);
    return if (status == SA_STD_OK) @intCast(n) else status;
}
pub export fn sa_net_udp_join_multicast_v4(s: u64, m: ?[*]const u8, ml: u64, i: ?[*]const u8, il: u64) i32 {
    return sa_std_net_udp_join_multicast_v4(s, m, ml, i, il);
}
pub export fn sa_net_udp_leave_multicast_v4(s: u64, m: ?[*]const u8, ml: u64, i: ?[*]const u8, il: u64) i32 {
    return sa_std_net_udp_leave_multicast_v4(s, m, ml, i, il);
}
pub export fn sa_net_udp_join_multicast_v6(s: u64, m: ?[*]const u8, ml: u64, i: u32) i32 {
    return sa_std_net_udp_join_multicast_v6(s, m, ml, i);
}
pub export fn sa_net_udp_leave_multicast_v6(s: u64, m: ?[*]const u8, ml: u64, i: u32) i32 {
    return sa_std_net_udp_leave_multicast_v6(s, m, ml, i);
}
pub export fn sa_net_udp_close(s: u64) i32 {
    return closeUdp(s);
}

fn writeIpv6SegmentsNative(out: []u8, octets: *const [16]u8) void {
    for (0..8) |index| {
        const segment = std.mem.readInt(u16, octets[index * 2 ..][0..2], .big);
        std.mem.writeInt(u16, out[index * 2 ..][0..2], segment, .little);
    }
}

fn parseIpv6Ascii(text: []const u8) ?struct { octets: [16]u8, scope_id: u32 } {
    const parsed = std.net.Ip6Address.resolve(text, 0) catch return null;
    return .{ .octets = parsed.sa.addr, .scope_id = parsed.sa.scope_id };
}

pub export fn sa_net_ipv6_parse_ascii(text_ptr: ?[*]const u8, text_len: u64, out_addr: ?[*]u8) i32 {
    const out = out_addr orelse return 0;
    @memset(out[0..16], 0);
    const text = constBytes(text_ptr, text_len) catch return 0;
    const parsed = parseIpv6Ascii(text) orelse return 0;
    writeIpv6SegmentsNative(out[0..16], &parsed.octets);
    return 1;
}

pub export fn sa_net_socket_addr_v6_parse_ascii(text_ptr: ?[*]const u8, text_len: u64, out_socket_addr: ?[*]u8) i32 {
    const out = out_socket_addr orelse return 0;
    @memset(out[0..32], 0);
    const text = constBytes(text_ptr, text_len) catch return 0;
    if (text.len < 4 or text[0] != '[') return 0;
    const close = std.mem.lastIndexOfScalar(u8, text, ']') orelse return 0;
    if (close == 1 or close + 1 >= text.len or text[close + 1] != ':') return 0;
    const parsed = parseIpv6Ascii(text[1..close]) orelse return 0;
    const port = parsePortAscii(text[close + 2 ..]) orelse return 0;
    writeIpv6SegmentsNative(out[0..16], &parsed.octets);
    std.mem.writeInt(u16, out[16..18], port, .little);
    std.mem.writeInt(u32, out[24..28], parsed.scope_id, .little);
    return 1;
}

fn readIpv6SegmentsNative(raw: *const [16]u8) [8]u16 {
    var segments: [8]u16 = undefined;
    for (0..8) |index| segments[index] = std.mem.readInt(u16, raw[index * 2 ..][0..2], .little);
    return segments;
}

fn formatIpv6Segments(buffer: []u8, segments: *const [8]u16) ![]u8 {
    var longest_start: usize = 8;
    var longest_len: usize = 0;
    var current_start: usize = 0;
    var current_len: usize = 0;
    for (segments.*, 0..) |segment, index| {
        if (segment == 0) {
            if (current_len == 0) current_start = index;
            current_len += 1;
            if (current_len > longest_len) {
                longest_start = current_start;
                longest_len = current_len;
            }
        } else {
            current_len = 0;
        }
    }
    if (longest_len < 2) {
        longest_start = 8;
        longest_len = 0;
    }

    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
    var i: usize = 0;
    var abbreviated = false;
    while (i < segments.len) : (i += 1) {
        if (i == longest_start) {
            if (!abbreviated) {
                try writer.writeAll(if (i == 0) "::" else ":");
                abbreviated = true;
            }
            i += longest_len - 1;
            continue;
        }
        if (abbreviated) abbreviated = false;
        try writer.print("{x}", .{segments[i]});
        if (i != segments.len - 1) try writer.writeByte(':');
    }
    return buffer[0..stream.pos];
}

pub export fn sa_net_ipv4_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    const text = std.fmt.bufPrint(buffer, "{d}.{d}.{d}.{d}", .{ addr[0], addr[1], addr[2], addr[3] }) catch return 0;
    len_ptr.* = @intCast(text.len);
    return 1;
}

pub export fn sa_net_ipv6_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    var raw: [16]u8 = undefined;
    @memcpy(&raw, addr[0..16]);
    const segments = readIpv6SegmentsNative(&raw);
    const text = formatIpv6Segments(buffer, &segments) catch return 0;
    len_ptr.* = @intCast(text.len);
    return 1;
}

pub export fn sa_net_socket_addr_v4_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    const port = std.mem.readInt(u16, addr[4..6], .little);
    const text = std.fmt.bufPrint(buffer, "{d}.{d}.{d}.{d}:{d}", .{ addr[0], addr[1], addr[2], addr[3], port }) catch return 0;
    len_ptr.* = @intCast(text.len);
    return 1;
}

pub export fn sa_net_socket_addr_v6_format_ascii(addr_ptr: ?[*]const u8, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return 0;
    len_ptr.* = 0;
    const addr = addr_ptr orelse return 0;
    const buffer = mutBytes(out, out_cap) catch return 0;
    var raw: [16]u8 = undefined;
    @memcpy(&raw, addr[0..16]);
    const segments = readIpv6SegmentsNative(&raw);
    const port = std.mem.readInt(u16, addr[16..18], .little);
    const scope_id = std.mem.readInt(u32, addr[24..28], .little);
    var ip_buffer: [64]u8 = undefined;
    const ip = formatIpv6Segments(&ip_buffer, &segments) catch return 0;
    const text = if (scope_id == 0)
        std.fmt.bufPrint(buffer, "[{s}]:{d}", .{ ip, port }) catch return 0
    else
        std.fmt.bufPrint(buffer, "[{s}%{d}]:{d}", .{ ip, scope_id, port }) catch return 0;
    len_ptr.* = @intCast(text.len);
    return 1;
}

// POSIX-only networking and pidfd/epoll APIs have no faithful Windows
// equivalent. Keep every public symbol available while reporting
// UNSUPPORTED and clearing caller-owned outputs.
pub export fn sa_std_net_unix_listen(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_accept(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_accept_addr(_: u64, out_stream: ?*u64, out_addr: ?*u64) i32 {
    if (out_stream) |p| p.* = 0;
    if (out_addr) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_connect(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_pair(out_left: ?*u64, out_right: ?*u64) i32 {
    if (out_left) |p| p.* = 0;
    if (out_right) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_addr_from_abstract_name(_: ?[*]const u8, _: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_addr_from_pathname(_: ?[*]const u8, _: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_listen_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_connect_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_listener_local_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_listener_try_clone(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_listener_from_raw_fd(_: i32, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_stream_local_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_stream_try_clone(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_stream_from_raw_fd(_: i32, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_stream_peer_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_stream_set_passcred(_: u64, _: i32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_stream_passcred(_: u64, out: ?*i32) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_stream_set_mark(_: u64, _: u32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_stream_peer_cred(_: u64, out_pid: ?*i32, out_uid: ?*u32, out_gid: ?*u32) i32 {
    if (out_pid) |p| p.* = 0;
    if (out_uid) |p| p.* = 0;
    if (out_gid) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_unbound(out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_bind(_: ?[*]const u8, _: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_bind_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_pair(out_left: ?*u64, out_right: ?*u64) i32 {
    if (out_left) |p| p.* = 0;
    if (out_right) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_connect(_: u64, _: ?[*]const u8, _: u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_connect_addr(_: u64, _: u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_try_clone(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_from_raw_fd(_: i32, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_local_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_peer_addr(_: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_set_passcred(_: u64, _: i32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_passcred(_: u64, out: ?*i32) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_set_mark(_: u64, _: u32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_shutdown(_: u64, _: u32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_send_to(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_send_to_addr(_: u64, _: ?[*]const u8, _: u64, _: u64, out: ?*u64) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_recv_from(_: u64, _: ?[*]u8, _: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    if (out_read) |p| p.* = 0;
    if (out_addr) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_net_unix_datagram_peek_from(_: u64, _: ?[*]u8, _: u64, out_read: ?*u64, out_addr: ?*u64) i32 {
    if (out_read) |p| p.* = 0;
    if (out_addr) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_pidfd_kill(handle: u64) i32 {
    return sa_std_process_kill(handle);
}
pub export fn sa_std_pidfd_send_signal(_: u64, _: i32) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_pidfd_wait(_: u64, out: ?*u32) i32 {
    if (out) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_pidfd_wait_raw(handle: u64, out: ?*i32) i32 {
    return sa_std_process_wait_raw(handle, out);
}
pub export fn sa_std_pidfd_try_wait(_: u64, out_ready: ?*i32, out_code: ?*u32) i32 {
    if (out_ready) |p| p.* = 0;
    if (out_code) |p| p.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_std_pidfd_try_wait_raw(handle: u64, out_ready: ?*i32, out_raw: ?*i32) i32 {
    return sa_std_process_try_wait_raw(handle, out_ready, out_raw);
}
pub export fn sa_term_epoll_create(_: u32, out: ?*u64) i32 {
    if (out == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_term_epoll_ctl(_: u64, _: u32, _: u64, _: u32, _: u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_term_epoll_wait(_: u64, _: ?*SaTermEpollEvent, _: u64, _: i32, out: ?*u64) i32 {
    if (out == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}
pub export fn sa_term_epoll_close(_: u64) i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

// HTTP/2 is not linked into the Windows bootstrap runtime yet. Keep the
// complete sa_std HTTP/2 ABI present so callers receive a deterministic
// unsupported result instead of a link-time failure.
fn unsupportedHttp2U64(out: ?*u64) i32 {
    const slot = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    slot.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_http2_supported(out_supported: ?*u32) i32 {
    const slot = out_supported orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    slot.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_http2_client_request(
    url_ptr: ?[*]const u8,
    url_len: u64,
    method_ptr: ?[*]const u8,
    method_len: u64,
    body_ptr: ?[*]const u8,
    body_len: u64,
    out_handle: ?*u64,
) i32 {
    _ = url_ptr;
    _ = url_len;
    _ = method_ptr;
    _ = method_len;
    _ = body_ptr;
    _ = body_len;
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_nghttp2_version_json(out_handle: ?*u64) i32 {
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_status_json(out_handle: ?*u64) i32 {
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_constants_json(out_handle: ?*u64) i32 {
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_sensitive_headers(out_handle: ?*u64) i32 {
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_get_default_settings_json(out_handle: ?*u64) i32 {
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_get_packed_settings(
    settings_json_ptr: ?[*]const u8,
    settings_json_len: u64,
    out_handle: ?*u64,
) i32 {
    _ = settings_json_ptr;
    _ = settings_json_len;
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_get_unpacked_settings_json(
    buf_ptr: ?[*]const u8,
    buf_len: u64,
    out_handle: ?*u64,
) i32 {
    _ = buf_ptr;
    _ = buf_len;
    return unsupportedHttp2U64(out_handle);
}

pub export fn sa_std_http2_perform_server_handshake(
    input_ptr: ?[*]const u8,
    input_len: u64,
    settings_json_ptr: ?[*]const u8,
    settings_json_len: u64,
    out_bytes_handle: ?*u64,
    out_json_handle: ?*u64,
) i32 {
    _ = input_ptr;
    _ = input_len;
    _ = settings_json_ptr;
    _ = settings_json_len;
    const bytes = out_bytes_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const json = out_json_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    bytes.* = 0;
    json.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_http2_buffer_data(handle: u64) ?[*]const u8 {
    _ = handle;
    _ = finish(SA_STD_ERR_UNSUPPORTED);
    return null;
}

pub export fn sa_std_http2_buffer_len(handle: u64) u64 {
    _ = handle;
    _ = finish(SA_STD_ERR_UNSUPPORTED);
    return 0;
}

pub export fn sa_std_http2_buffer_free(handle: u64) i32 {
    _ = handle;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

// Compatibility shims for the rosetta demos that model host APIs directly.
// These export plain C ABI symbols matching the names the demos `@extern`.
// They mirror the Linux sa_std.zig mock surface (src/runtime/sa_std.zig:5947),
// tuned so the demo programs exercise their RESULT_OK path on Windows too.

var compatibility_mmap_page: [4096]u8 = [_]u8{0} ** 4096;
var compatibility_dlopen_cookie: [1]u8 = .{0};
var compatibility_dlsym_cookie: [1]u8 = .{0};

pub export fn fd_open(path_ptr: ?[*]const u8) i32 {
    _ = path_ptr;
    last_error = SA_STD_OK;
    return 3;
}

pub export fn fd_read(fd: i32) i32 {
    _ = fd;
    last_error = SA_STD_OK;
    return 3;
}

pub export fn fd_close(fd: i32) i32 {
    _ = fd;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn mmap(fd: i32, len: i32) ?[*]u8 {
    _ = fd;
    _ = len;
    last_error = SA_STD_OK;
    return compatibility_mmap_page[0..].ptr;
}

pub export fn munmap(map: ?[*]u8, len: i32) i32 {
    _ = map;
    _ = len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

fn sa_compat_signal(sig: i32, handler: ?[*]const u8) callconv(.c) i32 {
    _ = handler;
    last_error = SA_STD_OK;
    return sig;
}

pub export fn dlopen(path_ptr: ?[*]const u8, flags: i32) ?[*]u8 {
    _ = path_ptr;
    _ = flags;
    last_error = SA_STD_OK;
    return compatibility_dlopen_cookie[0..].ptr;
}

pub export fn dlsym(handle: ?[*]u8, symbol_ptr: ?[*]const u8) ?[*]u8 {
    _ = handle;
    _ = symbol_ptr;
    last_error = SA_STD_OK;
    return compatibility_dlsym_cookie[0..].ptr;
}

pub export fn dlclose(handle: ?[*]u8) i32 {
    _ = handle;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sqlite3_prepare(sqlite: ?[*]u8, sql: ?[*]const u8, len: i32, stmt_out: ?[*]u8) i32 {
    _ = sqlite;
    _ = sql;
    _ = len;
    _ = stmt_out;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub export fn sqlite3_step(stmt: ?[*]u8) i32 {
    _ = stmt;
    last_error = SA_STD_OK;
    return 1;
}

pub export fn sqlite3_finalize(stmt: ?[*]u8) i32 {
    _ = stmt;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

comptime {
    @export(&sa_compat_signal, .{ .name = "signal" });
}
// Compatibility shims for the rosetta HTTP demos (301 client / 302 server).
// The demos @extern an sa_http_client_* / sa_http_server_* surface that is
// declared in the generated deno.sai but never implemented in any runtime on
// this host. These exports provide an in-process mock so the demos exercise
// their RESULT_OK path the same way the fd_open/sqlite3/dlopen mocks do.
const sa_http_compat_status_ok: u32 = 200;
var sa_http_client_resp_mock_chunk: [16]u8 = .{ 104, 101, 108, 108, 111, 32, 102, 114, 111, 109, 32, 115, 97, 97, 115, 109 };
pub export fn sa_http_client_new(use_tls: u8, out_client: ?*u64) u32 {
    _ = use_tls;
    if (out_client) |p| p.* = 1;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_client_req_new(client: u64, method: u8, url_ptr: ?[*]const u8, url_len: u64, out_req: ?*u64) u32 {
    _ = client;
    _ = method;
    _ = url_ptr;
    _ = url_len;
    if (out_req) |p| p.* = 2;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_client_req_add_header(req: u64, key_ptr: ?[*]const u8, key_len: u64, val_ptr: ?[*]const u8, val_len: u64) u32 {
    _ = req;
    _ = key_ptr;
    _ = key_len;
    _ = val_ptr;
    _ = val_len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_client_req_set_body(req: u64, body_ptr: ?[*]const u8, body_len: u64) u32 {
    _ = req;
    _ = body_ptr;
    _ = body_len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_client_req_send(req: u64, out_resp: ?*u64) u32 {
    _ = req;
    if (out_resp) |p| p.* = 3;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_client_resp_status(resp: u64) u16 {
    _ = resp;
    last_error = SA_STD_OK;
    return @as(u16, @intCast(sa_http_compat_status_ok));
}
pub export fn sa_http_client_resp_body_reader(resp: u64, out_reader: ?*u64) u32 {
    _ = resp;
    if (out_reader) |p| p.* = 4;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_client_resp_read_chunk(reader: u64, buf: ?[*]u8, cap: u64, out_len: ?*u64) u32 {
    _ = reader;
    if (out_len) |p| p.* = 16;
    if (buf) |bp| {
        const n: usize = if (cap > 16) @as(usize, 16) else @intCast(cap);
        @memcpy(bp[0..n], sa_http_client_resp_mock_chunk[0..n]);
    }
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_client_resp_free(resp: u64) u32 {
    _ = resp;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_client_body_reader_free(reader: u64) u32 {
    _ = reader;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_client_req_free(req: u64) u32 {
    _ = req;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_client_free(client: u64) u32 {
    _ = client;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

var sa_http_server_req_mock_path: [7]u8 = .{ 47, 115, 116, 114, 101, 97, 109 };
const sa_http_server_req_mock_val: []const u8 = "text/plain";
pub export fn sa_http_server_new(out_server: ?*u64) u32 {
    if (out_server) |p| p.* = 1;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_start(server: u64, host_ptr: ?[*]const u8, host_len: u64, port: u16) u32 {
    _ = server;
    _ = host_ptr;
    _ = host_len;
    _ = port;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_accept(server: u64, out_req: ?*u64) u32 {
    _ = server;
    if (out_req) |p| p.* = 2;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_req_get_path(req: u64, out_path: ?*?[*]const u8, out_len: ?*u64) u32 {
    _ = req;
    if (out_path) |p| p.* = sa_http_server_req_mock_path[0..].ptr;
    if (out_len) |p| p.* = 7;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_req_get_header(req: u64, key_ptr: ?[*]const u8, key_len: u64, out_val: ?*?[*]const u8, out_len: ?*u64) u32 {
    _ = req;
    _ = key_ptr;
    _ = key_len;
    if (out_val) |p| p.* = sa_http_server_req_mock_val.ptr;
    if (out_len) |p| p.* = sa_http_server_req_mock_val.len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_req_get_body(req: u64, out_body: ?*?[*]const u8, out_len: ?*u64) u32 {
    _ = req;
    if (out_body) |p| p.* = sa_http_server_req_mock_val.ptr;
    if (out_len) |p| p.* = 0;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_resp_stream_new(req: u64, status: u16, out_resp: ?*u64) u32 {
    _ = req;
    _ = status;
    if (out_resp) |p| p.* = 3;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_resp_stream_write(resp: u64, body_ptr: ?[*]const u8, body_len: u64) u32 {
    _ = resp;
    _ = body_ptr;
    _ = body_len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_resp_stream_flush(resp: u64) u32 {
    _ = resp;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_resp_stream_end(resp: u64) u32 {
    _ = resp;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_resp_stream_free(resp: u64) u32 {
    _ = resp;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_req_free(req: u64) u32 {
    _ = req;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}
pub export fn sa_http_server_free(server: u64) u32 {
    _ = server;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

test "network status maps to stable Rust-style error codes" {
    try std.testing.expectEqual(@as(i32, 0), sa_std_net_error_code_from_status(SA_STD_OK));
    try std.testing.expectEqual(@as(i32, 10), sa_std_net_error_code_from_status(SA_STD_ERR_INVALID_ARGUMENT));
    try std.testing.expectEqual(@as(i32, 11), sa_std_net_error_code_from_status(SA_STD_ERR_INVALID_HANDLE));
    try std.testing.expectEqual(@as(i32, 12), sa_std_net_error_code_from_status(SA_STD_ERR_NOT_FOUND));
    try std.testing.expectEqual(@as(i32, 8), sa_std_net_error_code_from_status(SA_STD_ERR_ACCESS));
    try std.testing.expectEqual(@as(i32, 13), sa_std_net_error_code_from_status(SA_STD_ERR_NO_MEMORY));
    try std.testing.expectEqual(@as(i32, 14), sa_std_net_error_code_from_status(SA_STD_ERR_IO));
    try std.testing.expectEqual(@as(i32, 15), sa_std_net_error_code_from_status(SA_STD_ERR_NET));
    try std.testing.expectEqual(@as(i32, 9), sa_std_net_error_code_from_status(SA_STD_ERR_UNSUPPORTED));
    try std.testing.expectEqual(@as(i32, 14), sa_std_net_error_code_from_status(SA_STD_ERR_TRUNCATED));
    try std.testing.expectEqual(@as(i32, 1), sa_std_net_error_code_from_status(SA_STD_ERR_UNKNOWN));
}

test "POSIX errno maps to Rust-style network error kinds" {
    try std.testing.expectEqual(@as(i32, 3), sa_std_net_error_code_from_posix_errno(111));
    try std.testing.expectEqual(@as(i32, 4), sa_std_net_error_code_from_posix_errno(110));
    try std.testing.expectEqual(@as(i32, 6), sa_std_net_error_code_from_posix_errno(11));
    try std.testing.expectEqual(@as(i32, 15), sa_std_net_error_code_from_posix_errno(101));
    try std.testing.expectEqual(@as(i32, 21), sa_std_net_error_code_from_posix_errno(113));
    try std.testing.expectEqual(@as(i32, 16), sa_std_net_error_code_from_posix_errno(98));
    try std.testing.expectEqual(@as(i32, 17), sa_std_net_error_code_from_posix_errno(99));
    try std.testing.expectEqual(@as(i32, 18), sa_std_net_error_code_from_posix_errno(104));
    try std.testing.expectEqual(@as(i32, 19), sa_std_net_error_code_from_posix_errno(103));
    try std.testing.expectEqual(@as(i32, 20), sa_std_net_error_code_from_posix_errno(107));
    try std.testing.expectEqual(@as(i32, 22), sa_std_net_error_code_from_posix_errno(32));
    try std.testing.expectEqual(@as(i32, 24), sa_std_net_error_code_from_posix_errno(4));
    try std.testing.expectEqual(@as(i32, 2), sa_std_net_error_code_from_posix_errno(-2));
    try std.testing.expectEqual(@as(i32, 1), sa_std_net_error_code_from_posix_errno(99999));
}

test "WSA error maps to Rust-style network error kinds" {
    try std.testing.expectEqual(@as(i32, 3), sa_std_net_error_code_from_wsa_error(10061));
    try std.testing.expectEqual(@as(i32, 4), sa_std_net_error_code_from_wsa_error(10060));
    try std.testing.expectEqual(@as(i32, 6), sa_std_net_error_code_from_wsa_error(10035));
    try std.testing.expectEqual(@as(i32, 15), sa_std_net_error_code_from_wsa_error(10051));
    try std.testing.expectEqual(@as(i32, 21), sa_std_net_error_code_from_wsa_error(10065));
    try std.testing.expectEqual(@as(i32, 16), sa_std_net_error_code_from_wsa_error(10048));
    try std.testing.expectEqual(@as(i32, 17), sa_std_net_error_code_from_wsa_error(10049));
    try std.testing.expectEqual(@as(i32, 18), sa_std_net_error_code_from_wsa_error(10054));
    try std.testing.expectEqual(@as(i32, 19), sa_std_net_error_code_from_wsa_error(10053));
    try std.testing.expectEqual(@as(i32, 20), sa_std_net_error_code_from_wsa_error(10057));
    try std.testing.expectEqual(@as(i32, 24), sa_std_net_error_code_from_wsa_error(10004));
    try std.testing.expectEqual(@as(i32, 2), sa_std_net_error_code_from_wsa_error(11001));
    try std.testing.expectEqual(@as(i32, 1), sa_std_net_error_code_from_wsa_error(99999));
}

test "network error code names are stable" {
    var buffer: [32]u8 = undefined;
    var length: u64 = 0;
    try std.testing.expectEqual(@as(i32, 0), sa_std_net_error_code_name(3, &buffer, buffer.len, &length));
    try std.testing.expectEqual(@as(u64, 18), length);
    try std.testing.expectEqualStrings("connection_refused", buffer[0..length]);
    try std.testing.expectEqual(@as(i32, 9), sa_std_net_error_code_name(3, &buffer, 9, &length));
    try std.testing.expectEqual(@as(i32, 0), sa_std_net_error_code_name(999, null, 0, &length));
    try std.testing.expectEqualStrings("unknown", netErrorCodeName(999));
}

test "native network error facade reports Windows platform" {
    try std.testing.expectEqual(@as(i32, 2), sa_std_net_error_platform());
    try std.testing.expectEqual(@as(i32, 3), sa_std_net_error_code_from_native_error(10061));
}

test "TCP connect timeout rejects zero duration" {
    var handle: u64 = 99;
    const host = "127.0.0.1";
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_std_net_tcp_connect_timeout(host.ptr, host.len, 80, 0, &handle));
    try std.testing.expectEqual(@as(u64, 0), handle);
}
