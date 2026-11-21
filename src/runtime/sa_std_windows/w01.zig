const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const processTermCode = @import("w02.zig").processTermCode;

// TLS client: reuse the shared pure-Zig implementation
// (src/runtime/sa_tls_client.zig, std.crypto.tls.Client + std.Io.net.Stream, no
// OpenSSL). std.crypto.Certificate.Bundle.rescan covers Windows (CryptAPI
// system store), so the real backend works here -- unlike HTTP/2 below, there
// is no external native library to link. Same comptime strong-reference
// trick as sa_std.zig so every `pub export fn` is kept in the archive.
comptime {
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_supported;
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_config_new;
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_config_free;
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_config_set_server_name;
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_config_add_ca_file;
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_config_add_ca_memory;
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_config_set_insecure_no_verification;
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_config_set_verify_self_signed;
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_connect_config;
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_start_tls;
    _ = &@import("../sa_tls_client.zig").sa_std_tls_client_peer_cert_json;
    _ = &@import("../sa_ws_client.zig").sa_std_ws_client_supported;
    _ = &@import("../sa_thread_local.zig").sa_thread_local_supported;
}

pub extern fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8;

pub extern fn _putenv_s(name: [*:0]const u8, value: [*:0]const u8) callconv(.c) c_int;

pub extern "kernel32" fn CreateHardLinkW(new_file_name: [*:0]const u16, existing_file_name: [*:0]const u16, security_attributes: ?*anyopaque) callconv(.winapi) std.os.windows.BOOL;

pub extern "kernel32" fn CreateToolhelp32Snapshot(flags: std.os.windows.DWORD, process_id: std.os.windows.DWORD) callconv(.winapi) std.os.windows.HANDLE;

pub extern "kernel32" fn Process32FirstW(snapshot: std.os.windows.HANDLE, entry: *ProcessEntry32W) callconv(.winapi) std.os.windows.BOOL;

pub extern "kernel32" fn Process32NextW(snapshot: std.os.windows.HANDLE, entry: *ProcessEntry32W) callconv(.winapi) std.os.windows.BOOL;

pub extern "kernel32" fn CloseHandle(handle: std.os.windows.HANDLE) callconv(.winapi) std.os.windows.BOOL;

pub extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*anyopaque;

pub extern "c" fn fputs(s: [*:0]const u8, stream: ?*anyopaque) callconv(.c) c_int;

pub extern "c" fn fclose(stream: ?*anyopaque) callconv(.c) c_int;

pub extern "kernel32" fn LoadLibraryW(path: [*:0]const u16) callconv(.winapi) ?std.os.windows.HMODULE;

pub extern "kernel32" fn GetProcAddress(module: std.os.windows.HMODULE, name: [*:0]const u8) callconv(.winapi) ?std.os.windows.FARPROC;

pub extern "kernel32" fn FreeLibrary(module: std.os.windows.HMODULE) callconv(.winapi) std.os.windows.BOOL;

pub extern "kernel32" fn GetLastError() callconv(.winapi) std.os.windows.Win32Error;

pub extern "ntdll" fn NtQueryInformationProcess(h: std.os.windows.HANDLE, c: i32, p: ?*anyopaque, u: std.os.windows.ULONG, r: ?*std.os.windows.ULONG) callconv(.winapi) i32;

pub extern "kernel32" fn WaitForSingleObject(h: std.os.windows.HANDLE, ms: std.os.windows.DWORD) callconv(.winapi) std.os.windows.DWORD;

pub extern "kernel32" fn CreateThread(lp_thread_attributes: ?*anyopaque, dw_stack_size: std.os.windows.DWORD, lp_start_address: ?*anyopaque, lp_parameter: ?*anyopaque, dw_creation_flags: std.os.windows.DWORD, lp_thread_id: ?*std.os.windows.DWORD) callconv(.winapi) ?std.os.windows.HANDLE;

pub extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) std.os.windows.DWORD;

pub extern "kernel32" fn SwitchToThread() callconv(.winapi) std.os.windows.BOOL;

pub extern "ws2_32" fn gethostname(name: [*]u8, len: i32) callconv(.winapi) i32;

pub extern "ws2_32" fn WSAStartup(wVersionRequested: u16, lpWSAData: *WSAData) callconv(.winapi) i32;

pub extern "ws2_32" fn WSAGetLastError() callconv(.winapi) i32;

pub extern "kernel32" fn SetFileTime(handle: std.os.windows.HANDLE, creation: ?*const FILETIME, accessed: ?*const FILETIME, written: ?*const FILETIME) callconv(.winapi) std.os.windows.BOOL;

pub extern "kernel32" fn SetFilePointerEx(handle: std.os.windows.HANDLE, distance: i64, new_pos: ?*i64, method: u32) callconv(.winapi) std.os.windows.BOOL;

pub const WSAData = extern struct { buf: [512]u8 };

pub const FILETIME = extern struct { low: u32, high: u32 };

pub fn nanoSecondsToFileTime(ns: i128) FILETIME {
    const ticks: i128 = @divFloor(ns, 100) + 116444736000000000;
    const clamped: u64 = @intCast(@max(ticks, 0));
    return .{ .low = @truncate(clamped), .high = @truncate(clamped >> 32) };
}

pub fn wsaStartup() !void {
    var data: WSAData = undefined;
    if (WSAStartup(0x0202, &data) != 0) return error.NetworkSubsystemFailed;
}

pub fn wsaError() anyerror {
    return switch (WSAGetLastError()) {
        10004 => error.Interrupted,
        10009 => error.InvalidHandle,
        10013 => error.PermissionDenied,
        10014 => error.InvalidArgument,
        10022 => error.InvalidArgument,
        10024 => error.ProcessFdQuotaExceeded,
        10035 => error.WouldBlock,
        10036 => error.OperationInProgress,
        10038 => error.NotSocket,
        10040 => error.MessageTooBig,
        10047 => error.AddressFamilyUnsupported,
        10048 => error.AddressInUse,
        10049 => error.AddressNotAvailable,
        10050 => error.NetworkSubsystemFailed,
        10051 => error.NetworkUnreachable,
        10052 => error.ConnectionResetByPeer,
        10053 => error.ConnectionAborted,
        10054 => error.ConnectionResetByPeer,
        10057 => error.NotConnected,
        10058 => error.NotConnected,
        10060 => error.ConnectionTimedOut,
        10061 => error.ConnectionRefused,
        10065 => error.NetworkUnreachable,
        else => error.Unexpected,
    };
}

pub const DEBUG_LOG_PATH = "E:\\projects\\sci\\spawn_debug.log";

pub fn spawnDebugLog(message: []const u8) void {
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

pub fn spawnDebugLogFmt(comptime fmt: []const u8, args: anytype) void {
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

/// Mirrors C sa_net_iov in sa_std.h.
pub const sa_net_iov = extern struct {
    base: [*]u8,
    len: usize,
};

pub const SA_NET_IOV_MAX: usize = 1024;

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

pub const FallibleU64 = extern struct {
    status: i32,
    value: u64,
};

pub const FallibleI32 = extern struct { status: i32, value: i32 };

pub const SaTermWinsize = extern struct {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
};

pub const SaTermEpollEvent = extern struct {
    events: u32,
    data: u64,
};

pub const TimeDate = extern struct {
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

pub const ProcessEntry32W = extern struct {
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

pub const SaJsonToken = extern struct {
    kind: u32,
    text_ptr: ?[*]const u8,
    text_len: u64,
};

pub const ProcessMode = enum {
    inherit,
    capture,
    stream,
};

pub const ProcessResource = struct {
    child: sio.Child,
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
            // NOTE: sequential drains (stdout then stderr) instead of the old
            // concurrent piped-output collector; a child that fills both pipes while
            // we read one could block — same caveat as the sio bridge.
            if (self.child.stdout) |out| {
                const bytes = try out.readToEndAlloc(std.heap.page_allocator, 64 * 1024 * 1024);
                errdefer std.heap.page_allocator.free(bytes);
                self.stdout_buf = bytes;
            }
            if (self.child.stderr) |err_out| {
                const bytes = try err_out.readToEndAlloc(std.heap.page_allocator, 64 * 1024 * 1024);
                errdefer std.heap.page_allocator.free(bytes);
                self.stderr_buf = bytes;
            }
        }
        self.code = processTermCode(try self.child.wait());
        self.exited = true;
    }

    fn close(self: *ProcessResource) void {
        if (!self.exited) {
            self.child.kill() catch {};
            if (self.child.wait()) |term| {
                self.code = processTermCode(term);
            } else |_| {}
            self.exited = true;
        }
        if (self.stdout_buf.len != 0) std.heap.page_allocator.free(self.stdout_buf);
        if (self.stderr_buf.len != 0) std.heap.page_allocator.free(self.stderr_buf);
        self.* = undefined;
    }
};

pub const StreamKind = enum { pipe, file };

pub const StreamResource = struct {
    file: sio.File,
    kind: StreamKind,

    fn close(self: *StreamResource) void {
        self.file.close();
        self.* = undefined;
    }
};

pub const DynamicLibraryResource = struct {
    module: std.os.windows.HMODULE,

    fn close(self: *DynamicLibraryResource) void {
        _ = FreeLibrary(self.module);
        self.* = undefined;
    }
};

pub const NetAddrResource = struct {
    host: []u8,
    family: u32,
    port: u16,
    scope_id: u64,

    fn close(self: *NetAddrResource) void {
        if (self.host.len != 0) std.heap.page_allocator.free(self.host);
        self.* = undefined;
    }
};

pub const NetAddrListResource = struct {
    addresses: []std.Io.net.IpAddress,
    next_index: usize = 0,

    fn close(self: *NetAddrListResource) void {
        if (self.addresses.len != 0) std.heap.page_allocator.free(self.addresses);
        self.* = undefined;
    }
};

pub const SockOptions = struct {
    nodelay: i32 = 0,
    ttl: i32 = 64,
    only_v6: i32 = 0,
    nonblocking: i32 = 0,
    recv_timeout_ms: i32 = 0,
    send_timeout_ms: i32 = 0,
    recv_buf: i32 = 0,
    send_buf: i32 = 0,
    last_error: i32 = 0,
    linger_on: i32 = 0,
    linger_ns: u64 = 0,
};

pub const TcpStreamResource = struct {
    stream: std.Io.net.Stream,
    options: SockOptions = .{},
    fn close(self: *TcpStreamResource) void {
        self.stream.close(sio.io());
        self.* = undefined;
    }
};

pub const TcpListenerResource = struct {
    server: std.Io.net.Server,
    options: SockOptions = .{},
    fn close(self: *TcpListenerResource) void {
        self.server.deinit(sio.io());
        self.* = undefined;
    }
};

pub const UdpResource = struct {
    socket: std.Io.net.Socket,
    peer: ?std.Io.net.IpAddress = null,
    options: SockOptions = .{},
    recv_buf: u32 = 0,
    send_buf: u32 = 0,
    broadcast: i32 = 0,
    mc_if_v4: u32 = 0,
    mc_loop_v4: i32 = 1,
    mc_ttl_v4: u32 = 1,
    mc_if_v6: u32 = 0,
    mc_loop_v6: i32 = 1,
    mc_hops_v6: u32 = 1,

    fn close(self: *UdpResource) void {
        self.socket.close(sio.io());
        self.* = undefined;
    }
};

pub const SaIoBuffer = extern struct {
    ptr: ?[*]u8,
    len: u64,
    cap: u64,
};

pub const JsonDocument = struct {
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

pub const JsonNode = struct {
    document: *JsonDocument,
    value: std.json.Value,

    fn release(self: JsonNode) void {
        self.document.release();
    }
};

pub const JsonWriter = struct {
    out: std.Io.Writer.Allocating,
    stream: std.json.Stringify,
    started: bool = false,
    complete: bool = false,
    depth: u32 = 0,
    finished: bool = false,

    fn create(options: std.json.Stringify.Options) !*JsonWriter {
        const writer = try std.heap.page_allocator.create(JsonWriter);
        writer.* = .{
            .out = .init(std.heap.page_allocator),
            .stream = undefined,
        };
        writer.stream = .{ .writer = &writer.out.writer, .options = options };
        return writer;
    }

    fn destroy(self: *JsonWriter) void {
        self.out.deinit();
        std.heap.page_allocator.destroy(self);
    }
};

pub const JsonTokenizer = struct {
    scanner: std.json.Scanner,
    input: []u8 = &.{},
    pending_text: std.array_list.Managed(u8),
    current_text: ?[]const u8 = null,
    is_stream: bool,

    fn createStreaming() !*JsonTokenizer {
        const tokenizer = try std.heap.page_allocator.create(JsonTokenizer);
        tokenizer.* = .{
            .scanner = std.json.Scanner.initStreaming(std.heap.page_allocator),
            .pending_text = std.array_list.Managed(u8).init(std.heap.page_allocator),
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
            .pending_text = std.array_list.Managed(u8).init(std.heap.page_allocator),
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

pub const EnvVarJson = struct {
    key: []const u8,
    value: []const u8,
};

pub const BufferResource = struct {
    bytes: []u8,

    fn close(self: *BufferResource) void {
        std.heap.page_allocator.free(self.bytes);
        self.* = .{ .bytes = &.{} };
    }
};

pub const MetadataResource = struct { stat: sio.Stat };

pub const DirEntrySnapshot = struct { name: []u8, kind: u32 };

pub const DirEntriesResource = struct {
    entries: []DirEntrySnapshot,
    fn close(self: *DirEntriesResource) void {
        for (self.entries) |entry| std.heap.page_allocator.free(entry.name);
        std.heap.page_allocator.free(self.entries);
        self.* = undefined;
    }
};

pub const DirEntryResource = struct {
    name: []u8,
    kind: u32,
    fn close(self: *DirEntryResource) void {
        std.heap.page_allocator.free(self.name);
        self.* = undefined;
    }
};

pub var last_error: i32 = SA_STD_OK;

pub var registry_mutex: std.atomic.Mutex = .unlocked;

pub var buffers = std.array_list.Managed(?BufferResource).init(std.heap.page_allocator);

pub var free_slots = std.array_list.Managed(usize).init(std.heap.page_allocator);

pub const process_handle_tag: u64 = 0x7000_0000_0000_0000;

pub const stream_handle_tag: u64 = 0x7100_0000_0000_0000;

pub const json_handle_tag: u64 = 0x7200_0000_0000_0000;

pub const json_writer_handle_tag: u64 = 0x7300_0000_0000_0000;

pub const json_tokenizer_handle_tag: u64 = 0x7400_0000_0000_0000;

pub const metadata_handle_tag: u64 = 0x7500_0000_0000_0000;

pub const dir_entries_handle_tag: u64 = 0x7600_0000_0000_0000;

pub const dir_entry_handle_tag: u64 = 0x7700_0000_0000_0000;

pub const dynamic_library_handle_tag: u64 = 0x7800_0000_0000_0000;
