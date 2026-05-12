const std = @import("std");
const builtin = @import("builtin");

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

const FIRST_DYNAMIC_HANDLE: u64 = 4;

const Resource = union(enum) {
    file: std.fs.File,
    tcp_stream: std.net.Stream,
    tcp_listener: std.net.Server,

    fn close(self: *Resource) void {
        switch (self.*) {
            .file => |file| file.close(),
            .tcp_stream => |stream| stream.close(),
            .tcp_listener => |*server| server.deinit(),
        }
        self.* = undefined;
    }
};

var registry_mutex: std.Thread.Mutex = .{};
var registry_slots = std.ArrayList(?Resource).init(std.heap.page_allocator);
threadlocal var last_error: i32 = SA_STD_OK;
var empty_mut_bytes: [0]u8 = .{};

fn finish(status: i32) i32 {
    last_error = status;
    return status;
}

fn mapError(err: anyerror) i32 {
    return switch (err) {
        error.InvalidArgument => SA_STD_ERR_INVALID_ARGUMENT,
        error.InvalidHandle => SA_STD_ERR_INVALID_HANDLE,
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.FileNotFound => SA_STD_ERR_NOT_FOUND,
        error.AccessDenied, error.PermissionDenied => SA_STD_ERR_ACCESS,
        error.Unsupported, error.SystemResources, error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded => SA_STD_ERR_UNSUPPORTED,
        error.NameTooLong,
        error.BadPathName,
        error.InvalidUtf8,
        error.InvalidWtf8,
        error.NotDir,
        error.IsDir,
        error.InvalidIPAddressFormat,
        error.InvalidCharacter,
        error.InvalidEnd,
        error.Incomplete,
        error.NonCanonical,
        error.InvalidIpv4Mapping,
        error.Overflow,
        => SA_STD_ERR_INVALID_ARGUMENT,
        error.UnknownHostName,
        error.TemporaryNameServerFailure,
        error.NameServerFailure,
        error.NetworkUnreachable,
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.AddressInUse,
        error.AddressNotAvailable,
        error.HostLacksNetworkAddresses,
        error.ServiceUnavailable,
        => SA_STD_ERR_NET,
        else => SA_STD_ERR_IO,
    };
}

fn finishErr(err: anyerror) i32 {
    return finish(mapError(err));
}

fn lenAsUsize(len: u64) !usize {
    if (len > @as(u64, @intCast(std.math.maxInt(usize)))) return error.InvalidArgument;
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
    if (n == 0) return empty_mut_bytes[0..];
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

fn pathBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const path = try constBytes(ptr, len);
    if (path.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    return path;
}

fn portFromU32(port: u32) !u16 {
    if (port > std.math.maxInt(u16)) return error.InvalidArgument;
    return @as(u16, @intCast(port));
}

fn dynamicIndex(handle: u64) ?usize {
    if (handle < FIRST_DYNAMIC_HANDLE) return null;
    const raw = handle - FIRST_DYNAMIC_HANDLE;
    if (raw > @as(u64, @intCast(std.math.maxInt(usize)))) return null;
    return @as(usize, @intCast(raw));
}

fn getResourceLocked(handle: u64) ?*Resource {
    const idx = dynamicIndex(handle) orelse return null;
    if (idx >= registry_slots.items.len) return null;
    if (registry_slots.items[idx]) |*resource| return resource;
    return null;
}

fn registerResourceLocked(resource: Resource) !u64 {
    for (registry_slots.items, 0..) |slot, idx| {
        if (slot == null) {
            registry_slots.items[idx] = resource;
            return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(idx));
        }
    }
    const idx = registry_slots.items.len;
    try registry_slots.append(resource);
    return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(idx));
}

fn registerResource(resource: Resource) !u64 {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    return try registerResourceLocked(resource);
}

fn takeResourceLocked(handle: u64) ?Resource {
    const idx = dynamicIndex(handle) orelse return null;
    if (idx >= registry_slots.items.len) return null;
    const resource = registry_slots.items[idx] orelse return null;
    registry_slots.items[idx] = null;
    return resource;
}

fn writeHandleLocked(handle: u64, data: []const u8) !usize {
    return switch (handle) {
        SA_STD_STDOUT => try std.io.getStdOut().write(data),
        SA_STD_STDERR => try std.io.getStdErr().write(data),
        SA_STD_STDIN => error.InvalidHandle,
        else => {
            const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
            return switch (resource.*) {
                .file => |file| try file.write(data),
                .tcp_stream => |stream| try stream.write(data),
                .tcp_listener => error.InvalidHandle,
            };
        },
    };
}

fn readHandleLocked(handle: u64, buffer: []u8) !usize {
    return switch (handle) {
        SA_STD_STDIN => try std.io.getStdIn().read(buffer),
        SA_STD_STDOUT, SA_STD_STDERR => error.InvalidHandle,
        else => {
            const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
            return switch (resource.*) {
                .file => |file| try file.read(buffer),
                .tcp_stream => |stream| try stream.read(buffer),
                .tcp_listener => error.InvalidHandle,
            };
        },
    };
}

fn writeAllStdout(data: []const u8) !void {
    try std.io.getStdOut().writeAll(data);
}

fn statusName(code: i32) []const u8 {
    return switch (code) {
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
        SA_STD_ERR_UNKNOWN => "unknown",
        else => "unknown",
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

pub export fn sa_std_print(data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    writeAllStdout(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_println(data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    writeAllStdout(bytes) catch |err| return finishErr(err);
    writeAllStdout("\n") catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    if (out_written) |written_ptr| written_ptr.* = 0;
    const bytes = constBytes(data, len) catch |err| return finishErr(err);

    registry_mutex.lock();
    defer registry_mutex.unlock();

    const written = writeHandleLocked(handle, bytes) catch |err| return finishErr(err);
    if (out_written) |written_ptr| written_ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}

pub export fn sa_std_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |read_ptr| read_ptr.* = 0;
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);

    registry_mutex.lock();
    defer registry_mutex.unlock();

    const read = readHandleLocked(handle, buffer) catch |err| return finishErr(err);
    if (out_read) |read_ptr| read_ptr.* = @as(u64, @intCast(read));
    return finish(SA_STD_OK);
}

pub export fn sa_std_close(handle: u64) i32 {
    if (handle == SA_STD_STDIN or handle == SA_STD_STDOUT or handle == SA_STD_STDERR) {
        return finish(SA_STD_ERR_INVALID_HANDLE);
    }

    registry_mutex.lock();
    var resource = takeResourceLocked(handle) orelse {
        registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    registry_mutex.unlock();

    resource.close();
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_open_read(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);

    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return finishErr(err);
    errdefer file.close();
    const handle = registerResource(.{ .file = file }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_open_write(path_ptr: ?[*]const u8, path_len: u64, truncate: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);

    const file = std.fs.cwd().createFile(path, .{
        .read = true,
        .truncate = truncate != 0,
    }) catch |err| return finishErr(err);
    errdefer file.close();
    const handle = registerResource(.{ .file = file }) catch |err| return finishErr(err);
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

pub export fn sa_std_fs_len(path_ptr: ?[*]const u8, path_len: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const stat = std.fs.cwd().statFile(path) catch |err| return finishErr(err);
    len_ptr.* = stat.size;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);

    const stream = std.net.tcpConnectToHost(std.heap.page_allocator, host, port16) catch |err| return finishErr(err);
    errdefer stream.close();
    const handle = registerResource(.{ .tcp_stream = stream }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_listen(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64, out_bound_port: ?*u32) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (out_bound_port) |port_ptr| port_ptr.* = 0;
    const host = pathBytes(host_ptr, host_len) catch |err| return finishErr(err);
    const port16 = portFromU32(port) catch |err| return finishErr(err);

    const address = std.net.Address.resolveIp(host, port16) catch |err| return finishErr(err);
    var server = address.listen(.{ .reuse_address = true }) catch |err| return finishErr(err);
    errdefer server.deinit();
    const handle = registerResource(.{ .tcp_listener = server }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    if (out_bound_port) |port_ptr| port_ptr.* = server.listen_address.getPort();
    return finish(SA_STD_OK);
}

pub export fn sa_std_net_tcp_accept(listener_handle: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;

    registry_mutex.lock();
    defer registry_mutex.unlock();

    const resource = getResourceLocked(listener_handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const connection = switch (resource.*) {
        .tcp_listener => |*server| server.accept() catch |err| return finishErr(err),
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    var stream = connection.stream;
    errdefer stream.close();
    const handle = registerResourceLocked(.{ .tcp_stream = stream }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

test "error names use fixed status bytes" {
    var len: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_error_name(SA_STD_ERR_NOT_FOUND, null, 0, &len));
    try std.testing.expectEqual(@as(u64, "not_found".len), len);

    var small: [3]u8 = undefined;
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_std_error_name(SA_STD_ERR_NOT_FOUND, &small, small.len, &len));
    try std.testing.expectEqualStrings("not", small[0..]);
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_std_last_error());
}

test "file handles read write close and surface errors" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const path = "sample.txt";
    const data = "abc123";
    var handle: u64 = 0;
    var count: u64 = 0;

    try std.testing.expectEqual(SA_STD_OK, sa_std_fs_open_write(path.ptr, path.len, 1, &handle));
    try std.testing.expect(handle >= FIRST_DYNAMIC_HANDLE);
    try std.testing.expectEqual(SA_STD_OK, sa_std_write(handle, data.ptr, data.len, &count));
    try std.testing.expectEqual(@as(u64, data.len), count);
    try std.testing.expectEqual(SA_STD_OK, sa_std_close(handle));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_HANDLE, sa_std_close(handle));

    var file_len: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_fs_len(path.ptr, path.len, &file_len));
    try std.testing.expectEqual(@as(u64, data.len), file_len);

    handle = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_fs_open_read(path.ptr, path.len, &handle));
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqual(SA_STD_OK, sa_std_read(handle, &buffer, buffer.len, &count));
    try std.testing.expectEqualStrings(data, buffer[0..@as(usize, @intCast(count))]);
    try std.testing.expectEqual(SA_STD_OK, sa_std_close(handle));

    try std.testing.expectEqual(SA_STD_OK, sa_std_fs_remove(path.ptr, path.len));
    try std.testing.expectEqual(SA_STD_ERR_NOT_FOUND, sa_std_fs_exists(path.ptr, path.len));
}

test "tcp loopback handles move bytes synchronously" {
    if (builtin.os.tag == .wasi) return error.SkipZigTest;

    const host = "127.0.0.1";
    var listener: u64 = 0;
    var port: u32 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_listen(host.ptr, host.len, 0, &listener, &port));
    defer _ = sa_std_close(listener);
    try std.testing.expect(port != 0);

    var client: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_connect(host.ptr, host.len, port, &client));
    defer _ = sa_std_close(client);

    var server_conn: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_tcp_accept(listener, &server_conn));
    defer _ = sa_std_close(server_conn);

    const payload = "ping";
    var written: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_write(client, payload.ptr, payload.len, &written));
    try std.testing.expectEqual(@as(u64, payload.len), written);

    var buffer: [8]u8 = undefined;
    var total: u64 = 0;
    while (total < payload.len) {
        var got: u64 = 0;
        const start = @as(usize, @intCast(total));
        try std.testing.expectEqual(SA_STD_OK, sa_std_read(server_conn, buffer[start..].ptr, payload.len - total, &got));
        try std.testing.expect(got != 0);
        total += got;
    }
    try std.testing.expectEqualStrings(payload, buffer[0..@as(usize, @intCast(total))]);
}
