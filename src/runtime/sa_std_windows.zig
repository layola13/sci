const std = @import("std");

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
pub const SA_STD_STDIN: u64 = 1;
pub const SA_STD_STDOUT: u64 = 2;
pub const SA_STD_STDERR: u64 = 3;

pub const SaJsonToken = extern struct { kind: u32, text_ptr: ?[*]const u8, text_len: u64 };
pub const SaProcessArgv = extern struct { data: [*]const u8, len: u64 };
pub const SaTermWinsize = extern struct { row: u16, col: u16, xpixel: u16, ypixel: u16 };
pub const SaTermEpollEvent = extern struct { events: u32, data: u64 };
pub const TimeDate = extern struct { unix_ms: i64, unix_ns: i64, year: u16, month: u8, day: u8, hour: u8, minute: u8, second: u8, millisecond: u16 };
const BufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
};
pub fn Fallible(comptime T: type) type {
    return extern struct { status: i32, value: T };
}

const FIRST_DYNAMIC_HANDLE: u64 = 4;

const MetadataHandle = struct {
    stat: std.fs.File.Stat,
};

const NetAddrHandle = struct {
    address: std.net.Address,
    host: []u8,

    fn deinit(self: *NetAddrHandle) void {
        std.heap.page_allocator.free(self.host);
        self.* = undefined;
    }
};

const ProcessHandle = struct {
    child: ?std.process.Child = null,
    args: [][]u8 = &.{},
    argv: [][]const u8 = &.{},
    pid: u32 = 0,
    exited: bool = false,
    code: u32 = 0,
    stdout_bytes: []u8 = &.{},
    stderr_bytes: []u8 = &.{},
    stdout_pos: usize = 0,
    stderr_pos: usize = 0,

    fn deinit(self: *ProcessHandle) void {
        if (self.child) |*child| {
            if (!self.exited) _ = child.kill() catch child.wait() catch .{ .Unknown = 0 };
        }
        for (self.args) |arg| std.heap.page_allocator.free(arg);
        if (self.args.len != 0) std.heap.page_allocator.free(self.args);
        if (self.argv.len != 0) std.heap.page_allocator.free(self.argv);
        if (self.stdout_bytes.len != 0) std.heap.page_allocator.free(self.stdout_bytes);
        if (self.stderr_bytes.len != 0) std.heap.page_allocator.free(self.stderr_bytes);
        self.* = undefined;
    }
};

const Resource = union(enum) {
    file: std.fs.File,
    buffer: []u8,
    metadata: MetadataHandle,
    net_addr: NetAddrHandle,
    dynamic_lib: std.DynLib,
    tcp_stream: std.net.Stream,
    tcp_listener: std.net.Server,
    udp_socket: std.posix.socket_t,
    process: ProcessHandle,

    fn close(self: *Resource) void {
        switch (self.*) {
            .file => |file| file.close(),
            .buffer => |bytes| if (bytes.len != 0) std.heap.page_allocator.free(bytes),
            .metadata => {},
            .net_addr => |*addr| addr.deinit(),
            .dynamic_lib => |*lib| lib.close(),
            .tcp_stream => |stream| stream.close(),
            .tcp_listener => |*server| server.deinit(),
            .udp_socket => |socket| (std.net.Stream{ .handle = socket }).close(),
            .process => |*process| process.deinit(),
        }
        self.* = undefined;
    }
};

var registry_mutex: std.Thread.Mutex = .{};
var registry_slots = std.ArrayList(?Resource).init(std.heap.page_allocator);
threadlocal var last_error: i32 = SA_STD_OK;

fn finish(status: i32) i32 {
    last_error = status;
    return status;
}

fn mapError(err: anyerror) i32 {
    return switch (err) {
        error.InvalidArgument, error.BadPathName, error.NameTooLong => SA_STD_ERR_INVALID_ARGUMENT,
        error.InvalidHandle, error.NotOpenForReading, error.NotOpenForWriting => SA_STD_ERR_INVALID_HANDLE,
        error.FileNotFound, error.ProcessNotFound => SA_STD_ERR_NOT_FOUND,
        error.AccessDenied, error.PermissionDenied => SA_STD_ERR_ACCESS,
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.ConnectionRefused, error.ConnectionResetByPeer, error.ConnectionTimedOut, error.NetworkUnreachable, error.AddressNotAvailable, error.AddressInUse => SA_STD_ERR_NET,
        error.Unsupported, error.OperationNotSupported, error.AddressFamilyNotSupported => SA_STD_ERR_UNSUPPORTED,
        else => SA_STD_ERR_IO,
    };
}

fn finishErr(err: anyerror) i32 {
    return finish(mapError(err));
}

fn dynamicIndex(handle: u64) ?usize {
    if (handle < FIRST_DYNAMIC_HANDLE) return null;
    return std.math.cast(usize, handle - FIRST_DYNAMIC_HANDLE);
}

fn registerResourceLocked(resource: Resource) !u64 {
    for (registry_slots.items, 0..) |slot, index| {
        if (slot == null) {
            registry_slots.items[index] = resource;
            return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(index));
        }
    }
    const index = registry_slots.items.len;
    try registry_slots.append(resource);
    return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(index));
}

fn registerResource(resource: Resource) !u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    return registerResourceLocked(resource);
}

fn getResourceLocked(handle: u64) ?*Resource {
    const index = dynamicIndex(handle) orelse return null;
    if (index >= registry_slots.items.len) return null;
    return if (registry_slots.items[index]) |*resource| resource else null;
}

fn takeResourceLocked(handle: u64) ?Resource {
    const index = dynamicIndex(handle) orelse return null;
    if (index >= registry_slots.items.len) return null;
    const resource = registry_slots.items[index] orelse return null;
    registry_slots.items[index] = null;
    return resource;
}

fn lenAsUsize(len: u64) !usize {
    return std.math.cast(usize, len) orelse error.InvalidArgument;
}

fn constBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const size = try lenAsUsize(len);
    if (size == 0) return &.{};
    return (ptr orelse return error.InvalidArgument)[0..size];
}

fn mutBytes(ptr: ?[*]u8, len: u64) ![]u8 {
    const size = try lenAsUsize(len);
    if (size == 0) return &.{};
    return (ptr orelse return error.InvalidArgument)[0..size];
}

fn pathBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const path = try constBytes(ptr, len);
    if (path.len == 0 or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    return path;
}

fn registerOwnedBytes(bytes: []u8) !u64 {
    errdefer if (bytes.len != 0) std.heap.page_allocator.free(bytes);
    return registerResource(.{ .buffer = bytes });
}

fn duplicateAndRegister(bytes: []const u8) !u64 {
    return registerOwnedBytes(try std.heap.page_allocator.dupe(u8, bytes));
}

fn unsupportedStatus() i32 {
    return finish(SA_STD_ERR_UNSUPPORTED);
}

fn unsupported() i32 {
    return unsupportedStatus();
}
fn unsupportedU64() u64 {
    _ = unsupportedStatus();
    return 0;
}
fn unsupportedU32() u32 {
    _ = unsupportedStatus();
    return 0;
}
fn unsupportedU8() u8 {
    _ = unsupportedStatus();
    return 0;
}
fn unsupportedI64() i64 {
    _ = unsupportedStatus();
    return 0;
}
fn unsupportedF64() f64 {
    _ = unsupportedStatus();
    return 0;
}
fn unsupportedFallible(comptime T: type) Fallible(T) {
    _ = unsupportedStatus();
    return .{ .status = SA_STD_ERR_UNSUPPORTED, .value = 0 };
}

pub export fn sa_http_client_resp_body_slice(_: ?*anyopaque, _: ?*?[*]const u8, _: ?*u64) u32 {
    return unsupportedU32();
}

pub export fn sa_std_version() u32 {
    return SA_STD_ABI_VERSION;
}

pub export fn sa_std_last_error() i32 {
    return last_error;
}

pub export fn sa_std_error_name(code: i32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const name = switch (code) {
        SA_STD_OK => "ok",
        SA_STD_ERR_INVALID_ARGUMENT => "invalid_argument",
        SA_STD_ERR_INVALID_HANDLE => "invalid_handle",
        SA_STD_ERR_NOT_FOUND => "not_found",
        SA_STD_ERR_ACCESS => "access",
        SA_STD_ERR_NO_MEMORY => "no_memory",
        SA_STD_ERR_IO => "io",
        SA_STD_ERR_NET => "net",
        SA_STD_ERR_UNSUPPORTED => "unsupported",
        SA_STD_ERR_TRUNCATED => "truncated",
        else => "unknown",
    };
    if (out_len) |len| len.* = @intCast(name.len);
    if (out_cap == 0) return finish(SA_STD_OK);
    const target = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (target.len < name.len) return finish(SA_STD_ERR_TRUNCATED);
    @memcpy(target[0..name.len], name);
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

pub export fn sa_std_print(data_ptr: ?[*]const u8, len: u64) i32 {
    const data = constBytes(data_ptr, len) catch |err| return finishErr(err);
    std.io.getStdOut().writeAll(data) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_println(data_ptr: ?[*]const u8, len: u64) i32 {
    const status = sa_std_print(data_ptr, len);
    if (status != SA_STD_OK) return status;
    std.io.getStdOut().writeAll("\n") catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_deno_cwd() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_chdir(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_deno_env_set(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_deno_env_delete(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_deno_random_uuid() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_make_temp_dir(_: ?[*]const u8, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_deno_make_temp_file(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_deno_args_json() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_btoa(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_atob(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_text_encode(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_text_decode(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_chat_sse_to_responses(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_chat_json_to_responses(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_responses_sse_normalize(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_responses_json_normalize(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_responses_request_normalize(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_responses_chat_fallback_request(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: u8) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_jsonrpc_params_string_literal(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: u8) u64 {
    return unsupportedU64();
}

pub export fn sa_deno_version_json() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_version_deno() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_build_json() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_build_os() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_build_platform_family() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_date_now_iso() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_hostname() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_os_release() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_os_uptime() f64 {
    return unsupportedF64();
}

pub export fn sa_deno_loadavg(_: ?*f64) i32 {
    return unsupported();
}

pub export fn sa_deno_system_memory_info() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_network_interfaces() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_pid() u32 {
    return unsupportedU32();
}

pub export fn sa_deno_ppid() u32 {
    return unsupportedU32();
}

pub export fn sa_deno_uid() u32 {
    return unsupportedU32();
}

pub export fn sa_deno_gid() u32 {
    return unsupportedU32();
}

pub export fn sa_deno_exec_path() u64 {
    return unsupportedU64();
}

pub export fn sa_deno_memory_usage() u64 {
    return unsupportedU64();
}

pub export fn sa_json_parse(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_json_kind(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_json_object_get(_: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_array_get(_: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_object_key_at(_: u64, _: u64, _: ?*?[*]const u8, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_object_get_string(_: u64, _: ?[*]const u8, _: u64, _: ?*?[*]const u8, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_object_get_bool(_: u64, _: ?[*]const u8, _: u64, _: ?*u8) i32 {
    return unsupported();
}

pub export fn sa_json_object_get_i64(_: u64, _: ?[*]const u8, _: u64, _: ?*i64) i32 {
    return unsupported();
}

pub export fn sa_json_object_get_f64(_: u64, _: ?[*]const u8, _: u64, _: ?*f64) i32 {
    return unsupported();
}

pub export fn sa_json_as_f64(_: u64, _: ?*f64) i32 {
    return unsupported();
}

pub export fn sa_json_as_i64(_: u64, _: ?*i64) i32 {
    return unsupported();
}

pub export fn sa_json_as_bool(_: u64, _: ?*u8) i32 {
    return unsupported();
}

pub export fn sa_json_string_ptr(_: u64) ?[*]const u8 {
    return null;
}

pub export fn sa_json_string_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_json_value_count(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_json_stringify(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_scanner_new(_: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_scanner_feed(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_scanner_end_input(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_scanner_next(_: u64, _: ?*SaJsonToken) i32 {
    return unsupported();
}

pub export fn sa_json_scanner_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_stream_new(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_json_stream_next(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_json_stream_get_slice_ptr(_: u64) ?[*]const u8 {
    return null;
}

pub export fn sa_json_stream_get_slice_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_json_stream_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_json_writer_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_new(_: u32, _: u8, _: u8, _: u8, _: u8, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_begin_object(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_end_object(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_begin_array(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_end_array(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_object_field(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_string(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_bool(_: u64, _: ?[*]const u8, _: u64, _: u8) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_i64(_: u64, _: ?[*]const u8, _: u64, _: i64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_f64(_: u64, _: ?[*]const u8, _: u64, _: f64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_null(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_field_node(_: u64, _: ?[*]const u8, _: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_bool(_: u64, _: u8) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_i64(_: u64, _: i64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_f64(_: u64, _: f64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_string(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_null(_: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_write_node(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_json_writer_finish(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_regex_compile(_: ?[*]const u8, _: u64, _: i32) u64 {
    return unsupportedU64();
}

pub export fn sa_regex_match(_: u64, _: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_regex_group_ptr(_: u64, _: u32) ?[*]const u8 {
    return null;
}

pub export fn sa_regex_group_len(_: u64, _: u32) u64 {
    return unsupportedU64();
}

pub export fn sa_regex_group_count(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_regex_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_regex_match_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_json_buffer_data(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_json_buffer_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_json_buffer_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_time_instant_ns() u64 {
    return unsupportedU64();
}

pub export fn sa_time_unix_s() i64 {
    return unsupportedI64();
}

pub export fn sa_time_unix_ms() i64 {
    return unsupportedI64();
}

pub export fn sa_time_unix_ns() i64 {
    return unsupportedI64();
}

pub export fn sa_time_utc_now(_: ?*TimeDate) i32 {
    return unsupported();
}

pub export fn sa_time_sleep_ns(_: u64) i32 {
    return unsupported();
}

pub export fn sa_time_sleep_ms(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_write(handle: u64, data_ptr: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const data = constBytes(data_ptr, len) catch |err| return finishErr(err);
    if (out_written) |written| written.* = 0;
    const count = switch (handle) {
        SA_STD_STDOUT => std.io.getStdOut().write(data) catch |err| return finishErr(err),
        SA_STD_STDERR => std.io.getStdErr().write(data) catch |err| return finishErr(err),
        else => blk: {
            registry_mutex.lock();
            defer registry_mutex.unlock();
            const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
            break :blk switch (resource.*) {
                .file => |file| file.write(data) catch |err| return finishErr(err),
                .tcp_stream => |stream| stream.write(data) catch |err| return finishErr(err),
                else => return finish(SA_STD_ERR_INVALID_HANDLE),
            };
        },
    };
    if (out_written) |written| written.* = @intCast(count);
    return finish(SA_STD_OK);
}

pub export fn sa_std_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    const target = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (out_read) |read| read.* = 0;
    const count = switch (handle) {
        SA_STD_STDIN => std.io.getStdIn().read(target) catch |err| return finishErr(err),
        else => blk: {
            registry_mutex.lock();
            defer registry_mutex.unlock();
            const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
            break :blk switch (resource.*) {
                .file => |file| file.read(target) catch |err| return finishErr(err),
                .tcp_stream => |stream| stream.read(target) catch |err| return finishErr(err),
                else => return finish(SA_STD_ERR_INVALID_HANDLE),
            };
        },
    };
    if (out_read) |read| read.* = @intCast(count);
    return finish(SA_STD_OK);
}

pub export fn sa_std_close(handle: u64) i32 {
    if (handle < FIRST_DYNAMIC_HANDLE) return finish(SA_STD_ERR_INVALID_HANDLE);
    registry_mutex.lock();
    var resource = takeResourceLocked(handle) orelse {
        registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    registry_mutex.unlock();
    resource.close();
    return finish(SA_STD_OK);
}

pub export fn sa_io_read_line(_: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_dl_open(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    var lib = std.DynLib.open(path) catch |err| return finishErr(err);
    const handle = registerResource(.{ .dynamic_lib = lib }) catch |err| {
        lib.close();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_dl_sym(handle: u64, symbol_ptr: ?[*]const u8, symbol_len: u64, out_ptr: ?*?*anyopaque) i32 {
    const target = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    target.* = null;
    const symbol = constBytes(symbol_ptr, symbol_len) catch |err| return finishErr(err);
    if (symbol.len == 0 or std.mem.indexOfScalar(u8, symbol, 0) != null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const symbol_z = std.heap.page_allocator.dupeZ(u8, symbol) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(symbol_z);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .dynamic_lib => |*lib| {
            target.* = lib.lookup(*anyopaque, symbol_z) orelse return finish(SA_STD_ERR_NOT_FOUND);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_dl_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_dl_error() ?[*:0]const u8 {
    return "unsupported";
}

pub export fn sa_std_fs_open_read(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return finishErr(err);
    const handle = registerResource(.{ .file = file }) catch |err| {
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
    const handle = registerResource(.{ .file = file }) catch |err| {
        file.close();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
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
    const exists = out_exists orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    exists.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    std.fs.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return finish(SA_STD_OK),
        else => return finishErr(err),
    };
    exists.* = 1;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_len(path_ptr: ?[*]const u8, path_len: u64, out_len: ?*u64) i32 {
    const size = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    size.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const stat = std.fs.cwd().statFile(path) catch |err| return finishErr(err);
    size.* = stat.size;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run(_: ?[*]const SaProcessArgv, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_run_cwd(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn(_: ?[*]const SaProcessArgv, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_cwd(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_stream(_: ?[*]const SaProcessArgv, _: u64, _: ?*u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_stream_cwd(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: ?*u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_run_command_ext(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_command_ext(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_stream_command_ext(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: ?*u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_run_command_ext_pidfd(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_command_ext_pidfd(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_stream_command_ext_pidfd(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: u32, _: ?*u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_run_command_ext_uid_gid(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: u32, _: u32, _: u32, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_command_ext_uid_gid(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: u32, _: u32, _: u32, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_stream_command_ext_uid_gid(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: u32, _: u32, _: u32, _: u32, _: ?*u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_run_command_ext_groups(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: ?[*]const u32, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_command_ext_groups(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: ?[*]const u32, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_stream_command_ext_groups(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: ?[*]const u32, _: u64, _: u32, _: ?*u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_run_command_ext_chroot(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: ?[*]const u8, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_command_ext_chroot(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: ?[*]const u8, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_spawn_stream_command_ext_chroot(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: ?[*]const u8, _: u64, _: u32, _: ?*u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_exec_command_ext(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: u32, _: u32, _: u32, _: u32, _: ?[*]const u32, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_process_id() u32 {
    return unsupportedU32();
}

pub export fn sa_std_process_parent_id() u32 {
    return unsupportedU32();
}

pub export fn sa_std_process_user_id() u32 {
    return unsupportedU32();
}

pub export fn sa_std_process_group_id() u32 {
    return unsupportedU32();
}

pub export fn sa_std_process_abort() noreturn {
    std.process.exit(1);
}

pub export fn sa_std_process_child_id(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_process_wait(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_process_wait_raw(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_process_try_wait(_: u64, _: ?*i32, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_process_try_wait_raw(_: u64, _: ?*i32, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_process_kill(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_send_signal(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_process_send_process_group_signal(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_process_kill_process_group(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_pidfd(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_into_pidfd(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_pidfd_kill(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_pidfd_send_signal(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_pidfd_wait_raw(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_pidfd_wait(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_pidfd_try_wait_raw(_: u64, _: ?*i32, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_pidfd_try_wait(_: u64, _: ?*i32, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_process_exit_status_code(_: i32) u32 {
    return unsupportedU32();
}

pub export fn sa_std_process_exit_status_signal(_: i32) i32 {
    return unsupported();
}

pub export fn sa_std_process_exit_status_core_dumped(_: i32) u8 {
    return unsupportedU8();
}

pub export fn sa_std_process_exit_status_stopped_signal(_: i32) i32 {
    return unsupported();
}

pub export fn sa_std_process_exit_status_continued(_: i32) u8 {
    return unsupportedU8();
}

pub export fn sa_std_process_read_stdout(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_read_stderr(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_exec_capture(_: ?[*]const SaProcessArgv, _: u64, _: ?*u32, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_exec_capture_cwd(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: ?*u32, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_process_close(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_fd_as_raw(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_fd_dup(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fd_dup_raw(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fd_from_raw(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fd_into_raw(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_fd_close_raw(_: i32) i32 {
    return unsupported();
}

pub export fn sa_std_fd_is_terminal(_: u64, _: ?*u8) i32 {
    return unsupported();
}

pub export fn sa_thread_current_id() u64 {
    return unsupportedU64();
}

pub export fn sa_thread_yield_now() i32 {
    return unsupported();
}

pub export fn sa_term_raw_enter(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_term_raw_leave(_: u64) i32 {
    return unsupported();
}

pub export fn sa_term_winsize(_: u64, _: ?*SaTermWinsize) i32 {
    return unsupported();
}

pub export fn sa_term_epoll_create(_: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_term_epoll_ctl(_: u64, _: u32, _: u64, _: u32, _: u64) i32 {
    return unsupported();
}

pub export fn sa_term_epoll_wait(_: u64, _: ?[*]SaTermEpollEvent, _: u64, _: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_term_epoll_close(_: u64) i32 {
    return unsupported();
}

pub export fn sa_io_stdin() u64 {
    return unsupportedU64();
}

pub export fn sa_io_stdout() u64 {
    return unsupportedU64();
}

pub export fn sa_io_stderr() u64 {
    return unsupportedU64();
}

pub export fn sa_io_read(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_io_read_exact(_: u64, _: ?[*]u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_io_write(_: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_io_write_all(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_io_flush(_: u64) i32 {
    return unsupported();
}

pub export fn sa_io_close(_: u64) i32 {
    return unsupported();
}

pub export fn sa_io_buffer_data(_: ?*const BufferHandle) ?[*]u8 {
    return null;
}

pub export fn sa_io_buffer_len(_: ?*const BufferHandle) u64 {
    return unsupportedU64();
}

pub export fn sa_io_buffer_free(_: ?*BufferHandle) i32 {
    return unsupported();
}

pub export fn sa_fs_file_open(_: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_file_create(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_file_close(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_fs_open_options(_: ?[*]const u8, _: u64, _: u32, _: u32, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fs_file_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fs_file_read(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_file_read(_: u64, _: ?[*]u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_fs_file_read_at(_: u64, _: ?[*]u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fs_file_read_exact_at(_: u64, _: ?[*]u8, _: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_file_read_exact(_: u64, _: ?[*]u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_fs_file_write(_: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fs_file_write_at(_: u64, _: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_fs_file_write_all_at(_: u64, _: ?[*]const u8, _: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_file_write(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_file_write_all(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_file_flush(_: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_file_sync_data(_: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_file_sync(_: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_file_truncate(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_file_seek(_: u64, _: u32, _: i64) i32 {
    return unsupported();
}

pub export fn sa_std_fs_file_seek(_: u64, _: u32, _: i64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_read_file(_: ?[*]const u8, _: u64, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_fs_read_file(_: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_read_to_string(_: ?[*]const u8, _: u64, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_fs_read_to_string(_: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_write_file(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_read_buffer_data(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_fs_read_buffer_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_read_buffer_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_read_file_base64(_: ?[*]const u8, _: u64, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_fs_read_file_base64(_: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_write_file_base64(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_read_dir_json(_: ?[*]const u8, _: u64, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_fs_read_dir_json(_: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_dir_buffer_data(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_fs_dir_buffer_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_dir_buffer_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_read_dir_entries(_: ?[*]const u8, _: u64, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_fs_read_dir_entries(_: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_dir_entries_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_std_fs_dir_entries_get(_: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_dir_entries_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_dir_entry_name_ptr(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_fs_dir_entry_name_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_dir_entry_file_name_ptr(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_fs_dir_entry_file_name_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_dir_entry_kind(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_dir_entry_ino(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_dir_entry_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_metadata(_: ?[*]const u8, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_fs_metadata(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_metadata_json(_: ?[*]const u8, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_fs_metadata_json(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_metadata_is_file(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_is_directory(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_is_symlink(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_is_block_device(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_is_char_device(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_is_fifo(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_is_socket(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_fs_metadata_modified_ms(_: u64) i64 {
    return unsupportedI64();
}

pub export fn sa_fs_metadata_created_ms(_: u64) i64 {
    return unsupportedI64();
}

pub export fn sa_fs_metadata_accessed_ms(_: u64) i64 {
    return unsupportedI64();
}

pub export fn sa_fs_metadata_changed_ms(_: u64) i64 {
    return unsupportedI64();
}

pub export fn sa_fs_metadata_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_mode(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_uid(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_gid(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_ino(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_dev(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_nlink(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_rdev(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_blksize(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_blocks(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_dev(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_ino(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_mode(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_st_nlink(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_uid(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_st_gid(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_fs_metadata_st_rdev(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_size(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_atime(_: u64) i64 {
    return unsupportedI64();
}

pub export fn sa_fs_metadata_st_atime_nsec(_: u64) i64 {
    return unsupportedI64();
}

pub export fn sa_fs_metadata_st_mtime(_: u64) i64 {
    return unsupportedI64();
}

pub export fn sa_fs_metadata_st_mtime_nsec(_: u64) i64 {
    return unsupportedI64();
}

pub export fn sa_fs_metadata_st_ctime(_: u64) i64 {
    return unsupportedI64();
}

pub export fn sa_fs_metadata_st_ctime_nsec(_: u64) i64 {
    return unsupportedI64();
}

pub export fn sa_fs_metadata_st_blksize(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_st_blocks(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fs_metadata_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_std_fs_metadata_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_fs_canonicalize(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fs_remove_file(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_rename(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_make_dir(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_make_dir_mode(_: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_create_dir(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_create_dir_mode(_: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_remove_dir(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_remove_dir_all(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_remove_path(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_copy_file(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_set_permissions(_: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_set_times_ms(_: ?[*]const u8, _: u64, _: i64, _: i64) i32 {
    return unsupported();
}

pub export fn sa_fs_hard_link(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_symlink(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_chown(_: ?[*]const u8, _: u64, _: u32, _: u32, _: u32, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_lchown(_: ?[*]const u8, _: u64, _: u32, _: u32, _: u32, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_fchown(_: u64, _: u32, _: u32, _: u32, _: u32) i32 {
    return unsupported();
}

pub export fn sa_fs_chroot(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fs_mkfifo(_: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_fs_read_link(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_connect(_: ?[*]const u8, _: u64, _: u32) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_net_to_socket_addr_first(_: ?[*]const u8, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_read(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_read(_: u64, _: ?[*]u8, _: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_std_net_tcp_stream_peek(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_peek(_: u64, _: ?[*]u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_write(_: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_write(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_write_all(_: u64, _: ?[*]const u8, _: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_net_tcp_stream_flush(_: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_peer_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_peer_addr(_: u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_shutdown(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_set_read_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_set_write_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_set_nonblocking(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_set_nodelay(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_set_ttl(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_tcp_stream_close(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_net_tcp_listener_bind(_: ?[*]const u8, _: u64, _: u16) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_net_tcp_listener_accept(_: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_net_tcp_listener_local_addr(_: u64) Fallible(u64) {
    return unsupportedFallible(u64);
}

pub export fn sa_net_tcp_listener_close(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_std_net_tcp_stream_set_nonblocking(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_nodelay(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_quickack(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_quickack(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_deferaccept(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_deferaccept(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_keepalive(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_keepalive_params(_: u64, _: u32, _: u32, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_set_reuseaddr(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_set_reuseport(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_read_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_write_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_set_ttl(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_read_timeout(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_write_timeout(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_nodelay(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_ttl(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_take_error(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_set_nonblocking(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_set_ttl(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_ttl(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_take_error(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_bind(_: ?[*]const u8, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_peer_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_connect(_: u64, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_read_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_write_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_nonblocking(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_broadcast(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_ttl(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_multicast_loop_v4(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_set_multicast_ttl_v4(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_join_multicast_v4(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_leave_multicast_v4(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_join_multicast_v6(_: u64, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_net_udp_leave_multicast_v6(_: u64, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_nonblocking(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_broadcast(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_ttl(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_read_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_write_timeout(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_read_timeout(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_write_timeout(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_broadcast(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_multicast_loop_v4(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_set_multicast_ttl_v4(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_multicast_loop_v4(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_multicast_ttl_v4(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_join_multicast_v4(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_leave_multicast_v4(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_join_multicast_v6(_: u64, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_leave_multicast_v6(_: u64, _: ?[*]const u8, _: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_ttl(_: u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_take_error(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_send(_: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_recv(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_peek(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_send_to(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_recv_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_udp_peek_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_bind(_: ?[*]const u8, _: u64, _: u16) i32 {
    return unsupported();
}

pub export fn sa_net_udp_connect(_: u64, _: ?[*]const u8, _: u64, _: u16) i32 {
    return unsupported();
}

pub export fn sa_net_udp_local_addr(_: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_send(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_recv(_: u64, _: ?[*]u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_peek(_: u64, _: ?[*]u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_send_to(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: u16) i32 {
    return unsupported();
}

pub export fn sa_net_udp_recv_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_peek_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_udp_close(_: u64) i32 {
    return unsupported();
}

pub export fn sa_net_addr_host(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_net_addr_host_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_net_addr_port(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_net_addr_family(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_net_addr_scope_id(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_std_net_addr_format(_: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_addr_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_net_ipv4_parse_ascii(_: ?[*]const u8, _: u64, _: ?[*]u8) i32 {
    return unsupported();
}

pub export fn sa_net_socket_addr_v4_parse_ascii(_: ?[*]const u8, _: u64, _: ?[*]u8) i32 {
    return unsupported();
}

pub export fn sa_net_ipv6_parse_ascii(_: ?[*]const u8, _: u64, _: ?[*]u8) i32 {
    return unsupported();
}

pub export fn sa_net_socket_addr_v6_parse_ascii(_: ?[*]const u8, _: u64, _: ?[*]u8) i32 {
    return unsupported();
}

pub export fn sa_net_ipv4_format_ascii(_: ?[*]const u8, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_ipv6_format_ascii(_: ?[*]const u8, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_socket_addr_v4_format_ascii(_: ?[*]const u8, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_socket_addr_v6_format_ascii(_: ?[*]const u8, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fmt_i64(_: i64, _: u32) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_i64_into(_: i64, _: u32, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_test_debug_i64(_: ?[*]const u8, _: u64, _: i64) void {}

pub export fn sa_assert_eq_i64(_: i64, _: i64, _: i32) void {}

pub export fn sa_assert_eq_i64_at(_: i64, _: i64, _: i32, _: ?[*]const u8, _: u64, _: u32, _: u32) void {}

pub export fn sa_fmt_u64(_: u64, _: u32) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_u64_into(_: u64, _: u32, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fmt_f64(_: f64, _: u32) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_f64_into(_: f64, _: u32, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fmt_bool(_: bool) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_bool_into(_: bool, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_fmt_bytes(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_bytes_into(_: ?[*]const u8, _: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_env_get(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_env_current_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_set_current_dir(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_env_temp_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_current_exe() u64 {
    return unsupportedU64();
}

pub export fn sa_env_home_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_args_json() u64 {
    return unsupportedU64();
}

pub export fn sa_env_vars_json() u64 {
    return unsupportedU64();
}

pub export fn sa_env_split_paths_json(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_env_join_paths_json(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_data_home_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_config_home_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_state_home_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_cache_home_dir() u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_data_dirs() u64 {
    return unsupportedU64();
}

pub export fn sa_env_xdg_config_dirs() u64 {
    return unsupportedU64();
}

pub export fn sa_env_has(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_env_set_var(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_env_remove_var(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_env_buffer_data(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_env_buffer_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_env_buffer_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_string_concat(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_str_is_ascii(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_str_eq_ignore_ascii_case(_: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_str_utf8_char_count(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_str_utf8_validate(_: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_str_utf8_char_at(_: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_str_utf8_char_at_byte(_: ?[*]const u8, _: u64, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_str_utf8_lossy_next(_: ?[*]const u8, _: u64, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_str_utf8_char_range_at(_: ?[*]const u8, _: u64, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_str_trim_ascii_start_index(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_str_trim_ascii_end_len(_: ?[*]const u8, _: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_buffer_data(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_fmt_buffer_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_fmt_buffer_write_to(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_fmt_buffer_free(_: u64) i32 {
    return unsupported();
}

pub export fn sa_print_bytes(_: ?[*]const u8, _: u64) void {}

pub export fn sa_std_net_tcp_listen(_: ?[*]const u8, _: u64, _: u32, _: ?*u64, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_accept(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_listener_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_connect(_: ?[*]const u8, _: u64, _: u32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_tcp_stream_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_listen(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_addr_from_abstract_name(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_addr_from_pathname(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_listen_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_accept(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_accept_addr(_: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_pair(_: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_listener_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_listener_try_clone(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_listener_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_try_clone(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_peer_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_set_passcred(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_passcred(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_set_mark(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_stream_peer_cred(_: u64, _: ?*i32, _: ?*u32, _: ?*u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_unbound(_: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_bind(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_bind_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_pair(_: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_connect(_: u64, _: ?[*]const u8, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_connect_addr(_: u64, _: u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_try_clone(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_from_raw_fd(_: i32, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_local_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_peer_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_set_passcred(_: u64, _: i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_passcred(_: u64, _: ?*i32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_set_mark(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_shutdown(_: u64, _: u32) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_send_to(_: u64, _: ?[*]const u8, _: u64, _: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_send_to_addr(_: u64, _: ?[*]const u8, _: u64, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_recv_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_datagram_peek_from(_: u64, _: ?[*]u8, _: u64, _: ?*u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_connect(_: ?[*]const u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_unix_connect_addr(_: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_net_unix_addr_kind(_: u64) u32 {
    return unsupportedU32();
}

pub export fn sa_net_unix_addr_is_unnamed(_: u64) u8 {
    return unsupportedU8();
}

pub export fn sa_net_unix_addr_path_ptr(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_net_unix_addr_path_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_net_unix_addr_abstract_ptr(_: u64) ?[*]u8 {
    return null;
}

pub export fn sa_net_unix_addr_abstract_len(_: u64) u64 {
    return unsupportedU64();
}

pub export fn sa_net_unix_addr_free(_: u64) Fallible(i32) {
    return unsupportedFallible(i32);
}

pub export fn sa_std_net_ja3_hash(_: ?[*]const u8, _: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_sha256_hex(_: ?[*]const u8, _: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}

pub export fn sa_std_net_ja4_hash12(_: ?[*]const u8, _: u64, _: ?[*]u8, _: u64, _: ?*u64) i32 {
    return unsupported();
}
