const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

pub const abi_version: u32 = 1;
pub const host_version: []const u8 = "sci-0.2";
pub const descriptor_symbol_name: [:0]const u8 = "saasm_plugin_descriptor_v1";
pub const descriptor_fn_symbol_name: [:0]const u8 = "saasm_plugin_descriptor_v1_fn";
pub const broker_abi_version: u32 = 1;
pub fn targetDynamicLibrarySuffix() []const u8 {
    return switch (@import("builtin").os.tag) {
        .windows => ".dll",
        .macos => ".dylib",
        else => ".so",
    };
}
pub fn isDynamicLibraryPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".so") or
        std.mem.endsWith(u8, path, ".dll") or
        std.mem.endsWith(u8, path, ".dylib");
}
pub fn targetArtifactKey() []const u8 {
    const builtin = @import("builtin");
    return switch (builtin.cpu.arch) {
        .x86_64 => switch (builtin.os.tag) {
            .windows => "windows-x86_64",
            .linux => "linux-x86_64",
            .macos => "macos-x86_64",
            else => "linux-x86_64",
        },
        .aarch64 => switch (builtin.os.tag) {
            .windows => "windows-aarch64",
            .linux => "linux-aarch64",
            .macos => "macos-aarch64",
            else => "linux-aarch64",
        },
        else => switch (builtin.os.tag) {
            .windows => "windows-x86_64",
            .linux => "linux-x86_64",
            .macos => "macos-x86_64",
            else => "linux-x86_64",
        },
    };
}
test "plugin target helpers select host dynamic library and artifact key" {
    const builtin = @import("builtin");
    switch (builtin.os.tag) {
        .windows => {
            try std.testing.expectEqualStrings(".dll", targetDynamicLibrarySuffix());
            try std.testing.expect(std.mem.startsWith(u8, targetArtifactKey(), "windows-"));
            try std.testing.expect(isDynamicLibraryPath("plugin.dll"));
        },
        .macos => {
            try std.testing.expectEqualStrings(".dylib", targetDynamicLibrarySuffix());
            try std.testing.expect(std.mem.startsWith(u8, targetArtifactKey(), "macos-"));
            try std.testing.expect(isDynamicLibraryPath("plugin.dylib"));
        },
        else => {
            try std.testing.expectEqualStrings(".so", targetDynamicLibrarySuffix());
            try std.testing.expect(std.mem.startsWith(u8, targetArtifactKey(), "linux-"));
            try std.testing.expect(isDynamicLibraryPath("plugin.so"));
        },
    }
}
pub const SkillSection = struct {
    name: []const u8,
    summary: []const u8,
    items: []const []const u8,
};
pub const Context = struct {
    allocator: std.mem.Allocator,
    host_version: ?[]const u8 = host_version,
    log: ?*const fn (ctx: *const anyopaque, level: LogLevel, message_ptr: [*]const u8, message_len: usize) callconv(.c) void = null,
    log_ctx: ?*anyopaque = null,
    json_mode: bool = false,
    broker_abi_version: u32 = 0,
    broker_call: ?BrokerCallFn = null,
    broker_ctx: ?*anyopaque = null,
};
pub const LogLevel = enum(u8) {
    debug,
    info,
    warn,
    err,
};
pub const AbiStatus = enum(u32) {
    ok = 0,
    unknown_command = 1,
    failed = 2,
    version_mismatch = 3,
    invalid_descriptor = 4,
};
pub const BrokerCallFn = *const fn (ctx: ?*anyopaque, op: u32, req: ?*const anyopaque, resp: ?*anyopaque) callconv(.c) u32;
pub const BrokerOp = enum(u32) {
    env_get = 1,
    fs_read = 2,
    http_request = 3,
    process_spawn = 4,
    cache_lookup = 5,
    cache_store = 6,
};
pub const BrokerStatus = enum(u32) {
    ok = 0,
    denied = 1,
    unsupported = 2,
    invalid_request = 3,
    not_found = 4,
    insufficient_buffer = 5,
    failed = 6,
};
pub const BrokerEnvGetRequest = extern struct {
    name_ptr: [*]const u8,
    name_len: usize,
    value_ptr: ?[*]u8,
    value_cap: usize,
};
pub const BrokerEnvGetResponse = extern struct {
    value_len: usize,
};
pub const BrokerFsReadRequest = extern struct {
    path_ptr: [*]const u8,
    path_len: usize,
    value_ptr: ?[*]u8,
    value_cap: usize,
};
pub const BrokerFsReadResponse = extern struct {
    value_len: usize,
};
pub const BrokerHttpRequest = extern struct {
    method_ptr: [*]const u8,
    method_len: usize,
    url_ptr: [*]const u8,
    url_len: usize,
    body_ptr: ?[*]const u8,
    body_len: usize,
    value_ptr: ?[*]u8,
    value_cap: usize,
};
pub const BrokerHttpResponse = extern struct {
    status_code: u16,
    value_len: usize,
};
pub const BrokerHttpResult = struct {
    status_code: u16,
    body: []const u8,
};
pub const BrokerString = extern struct {
    ptr: [*]const u8,
    len: usize,
};
pub const BrokerProcessSpawnRequest = extern struct {
    path_ptr: [*]const u8,
    path_len: usize,
    argv_ptr: ?[*]const BrokerString,
    argv_len: usize,
    stdout_ptr: ?[*]u8,
    stdout_cap: usize,
    stderr_ptr: ?[*]u8,
    stderr_cap: usize,
};
pub const BrokerProcessSpawnResponse = extern struct {
    exit_code: u32,
    stdout_len: usize,
    stderr_len: usize,
};
pub const BrokerProcessSpawnResult = struct {
    exit_code: u32,
    stdout: []const u8,
    stderr: []const u8,
};
pub const BrokerCacheLookupRequest = extern struct {
    ns_ptr: [*]const u8,
    ns_len: usize,
    key_ptr: [*]const u8,
    key_len: usize,
    closure_ptr: [*]const u8,
    closure_len: usize,
    value_ptr: ?[*]u8,
    value_cap: usize,
};
pub const BrokerCacheLookupResponse = extern struct {
    hit: u32,
    value_len: usize,
};
pub const BrokerCacheStoreRequest = extern struct {
    ns_ptr: [*]const u8,
    ns_len: usize,
    key_ptr: [*]const u8,
    key_len: usize,
    closure_ptr: [*]const u8,
    closure_len: usize,
    value_ptr: [*]const u8,
    value_len: usize,
};
pub const BrokerCacheStoreResponse = extern struct {
    stored: u32,
};
pub const BrokerError = error{
    Unsupported,
    Denied,
    InvalidRequest,
    NotFound,
    InsufficientBuffer,
    Failed,
};
pub const RuntimeAuthorizationInput = struct {
    dev_mode: bool = false,
    project_root: ?[]const u8 = null,
    allow_env_declared: bool = false,
    allow_env: []const []const u8 = &.{},
    allow_read_declared: bool = false,
    allow_read: []const []const u8 = &.{},
    allow_write_declared: bool = false,
    allow_write: []const []const u8 = &.{},
    allow_net_declared: bool = false,
    allow_net: []const []const u8 = &.{},
    allow_run_declared: bool = false,
    allow_run: []const []const u8 = &.{},
};
pub fn brokerAvailable(ctx: *const Context) bool {
    const version = ctx.host_version orelse return false;
    if (!hostVersionSupportsBroker(version)) return false;
    return ctx.broker_call != null and ctx.broker_abi_version >= broker_abi_version;
}
pub fn brokerEnvGet(ctx: *const Context, name: []const u8, buffer: []u8) BrokerError![]const u8 {
    if (!brokerAvailable(ctx)) return error.Unsupported;
    const broker_call = ctx.broker_call orelse return error.Unsupported;
    var response = BrokerEnvGetResponse{ .value_len = 0 };
    const request = BrokerEnvGetRequest{
        .name_ptr = name.ptr,
        .name_len = name.len,
        .value_ptr = if (buffer.len == 0) null else buffer.ptr,
        .value_cap = buffer.len,
    };
    const status = brokerStatusFromInt(broker_call(ctx.broker_ctx, @intFromEnum(BrokerOp.env_get), &request, &response));
    return switch (status) {
        .ok => buffer[0..response.value_len],
        .denied => error.Denied,
        .unsupported => error.Unsupported,
        .invalid_request => error.InvalidRequest,
        .not_found => error.NotFound,
        .insufficient_buffer => error.InsufficientBuffer,
        .failed => error.Failed,
    };
}
pub fn brokerFsRead(ctx: *const Context, path: []const u8, buffer: []u8) BrokerError![]const u8 {
    if (!brokerAvailable(ctx)) return error.Unsupported;
    const broker_call = ctx.broker_call orelse return error.Unsupported;
    var response = BrokerFsReadResponse{ .value_len = 0 };
    const request = BrokerFsReadRequest{
        .path_ptr = path.ptr,
        .path_len = path.len,
        .value_ptr = if (buffer.len == 0) null else buffer.ptr,
        .value_cap = buffer.len,
    };
    const status = brokerStatusFromInt(broker_call(ctx.broker_ctx, @intFromEnum(BrokerOp.fs_read), &request, &response));
    return switch (status) {
        .ok => buffer[0..response.value_len],
        .denied => error.Denied,
        .unsupported => error.Unsupported,
        .invalid_request => error.InvalidRequest,
        .not_found => error.NotFound,
        .insufficient_buffer => error.InsufficientBuffer,
        .failed => error.Failed,
    };
}
pub fn brokerHttpRequest(
    ctx: *const Context,
    method: []const u8,
    url: []const u8,
    body: []const u8,
    buffer: []u8,
) BrokerError!BrokerHttpResult {
    if (!brokerAvailable(ctx)) return error.Unsupported;
    const broker_call = ctx.broker_call orelse return error.Unsupported;
    var response = BrokerHttpResponse{
        .status_code = 0,
        .value_len = 0,
    };
    const request = BrokerHttpRequest{
        .method_ptr = method.ptr,
        .method_len = method.len,
        .url_ptr = url.ptr,
        .url_len = url.len,
        .body_ptr = if (body.len == 0) null else body.ptr,
        .body_len = body.len,
        .value_ptr = if (buffer.len == 0) null else buffer.ptr,
        .value_cap = buffer.len,
    };
    const status = brokerStatusFromInt(broker_call(ctx.broker_ctx, @intFromEnum(BrokerOp.http_request), &request, &response));
    return switch (status) {
        .ok => .{
            .status_code = response.status_code,
            .body = buffer[0..response.value_len],
        },
        .denied => error.Denied,
        .unsupported => error.Unsupported,
        .invalid_request => error.InvalidRequest,
        .not_found => error.NotFound,
        .insufficient_buffer => error.InsufficientBuffer,
        .failed => error.Failed,
    };
}
pub fn brokerCacheStore(ctx: *const Context, ns: []const u8, key_material: []const u8, closure_blob: []const u8, bytes: []const u8) BrokerError!void {
    if (!brokerAvailable(ctx)) return error.Unsupported;
    const broker_call = ctx.broker_call orelse return error.Unsupported;
    var response = BrokerCacheStoreResponse{ .stored = 0 };
    const request = BrokerCacheStoreRequest{
        .ns_ptr = ns.ptr,
        .ns_len = ns.len,
        .key_ptr = key_material.ptr,
        .key_len = key_material.len,
        .closure_ptr = closure_blob.ptr,
        .closure_len = closure_blob.len,
        .value_ptr = bytes.ptr,
        .value_len = bytes.len,
    };
    const status = brokerStatusFromInt(broker_call(ctx.broker_ctx, @intFromEnum(BrokerOp.cache_store), &request, &response));
    return switch (status) {
        .ok => {},
        .denied => error.Denied,
        .unsupported => error.Unsupported,
        .invalid_request => error.InvalidRequest,
        .not_found => error.NotFound,
        .insufficient_buffer => error.InsufficientBuffer,
        .failed => error.Failed,
    };
}
/// Two-pass lookup: returns the stored artifact bytes when the host
/// reports a hit, null on a miss. The caller owns the returned bytes.
pub fn brokerCacheLookupAlloc(ctx: *const Context, allocator: std.mem.Allocator, ns: []const u8, key_material: []const u8, closure_blob: []const u8) BrokerError!?[]u8 {
    if (!brokerAvailable(ctx)) return error.Unsupported;
    const broker_call = ctx.broker_call orelse return error.Unsupported;
    var response = BrokerCacheLookupResponse{ .hit = 0, .value_len = 0 };
    var request = BrokerCacheLookupRequest{
        .ns_ptr = ns.ptr,
        .ns_len = ns.len,
        .key_ptr = key_material.ptr,
        .key_len = key_material.len,
        .closure_ptr = closure_blob.ptr,
        .closure_len = closure_blob.len,
        .value_ptr = null,
        .value_cap = 0,
    };
    var status = brokerStatusFromInt(broker_call(ctx.broker_ctx, @intFromEnum(BrokerOp.cache_lookup), &request, &response));
    if (status == .ok) {
        if (response.hit == 0) return null;
    } else if (status != .insufficient_buffer) {
        return switch (status) {
            .denied => error.Denied,
            .unsupported => error.Unsupported,
            .invalid_request => error.InvalidRequest,
            .not_found => error.NotFound,
            .failed => error.Failed,
            else => error.Failed,
        };
    }
    const buffer = allocator.alloc(u8, response.value_len) catch return error.Failed;
    errdefer allocator.free(buffer);
    request.value_ptr = if (buffer.len == 0) null else buffer.ptr;
    request.value_cap = buffer.len;
    var response2 = BrokerCacheLookupResponse{ .hit = 0, .value_len = 0 };
    status = brokerStatusFromInt(broker_call(ctx.broker_ctx, @intFromEnum(BrokerOp.cache_lookup), &request, &response2));
    switch (status) {
        .ok => {
            if (response2.hit == 0) {
                allocator.free(buffer);
                return null;
            }
            return buffer[0..response2.value_len];
        },
        .denied => return error.Denied,
        .unsupported => return error.Unsupported,
        .invalid_request => return error.InvalidRequest,
        .not_found => return error.NotFound,
        .insufficient_buffer => return error.InsufficientBuffer,
        .failed => return error.Failed,
    }
}
pub fn brokerProcessSpawn(
    ctx: *const Context,
    path: []const u8,
    argv: []const BrokerString,
    stdout_buffer: []u8,
    stderr_buffer: []u8,
) BrokerError!BrokerProcessSpawnResult {
    if (!brokerAvailable(ctx)) return error.Unsupported;
    const broker_call = ctx.broker_call orelse return error.Unsupported;
    var response = BrokerProcessSpawnResponse{
        .exit_code = 0,
        .stdout_len = 0,
        .stderr_len = 0,
    };
    const request = BrokerProcessSpawnRequest{
        .path_ptr = path.ptr,
        .path_len = path.len,
        .argv_ptr = if (argv.len == 0) null else argv.ptr,
        .argv_len = argv.len,
        .stdout_ptr = if (stdout_buffer.len == 0) null else stdout_buffer.ptr,
        .stdout_cap = stdout_buffer.len,
        .stderr_ptr = if (stderr_buffer.len == 0) null else stderr_buffer.ptr,
        .stderr_cap = stderr_buffer.len,
    };
    const status = brokerStatusFromInt(broker_call(ctx.broker_ctx, @intFromEnum(BrokerOp.process_spawn), &request, &response));
    return switch (status) {
        .ok => .{
            .exit_code = response.exit_code,
            .stdout = stdout_buffer[0..response.stdout_len],
            .stderr = stderr_buffer[0..response.stderr_len],
        },
        .denied => error.Denied,
        .unsupported => error.Unsupported,
        .invalid_request => error.InvalidRequest,
        .not_found => error.NotFound,
        .insufficient_buffer => error.InsufficientBuffer,
        .failed => error.Failed,
    };
}
fn hostVersionSupportsBroker(version: []const u8) bool {
    const prefix = "sci-";
    if (!std.mem.startsWith(u8, version, prefix)) return false;
    var it = std.mem.splitScalar(u8, version[prefix.len..], '.');
    const major_text = it.next() orelse return false;
    const minor_text = it.next() orelse return false;
    const major = std.fmt.parseUnsigned(u32, major_text, 10) catch return false;
    const minor = std.fmt.parseUnsigned(u32, minor_text, 10) catch return false;
    return major > 0 or minor >= 2;
}
fn brokerStatusFromInt(value: u32) BrokerStatus {
    return switch (value) {
        @intFromEnum(BrokerStatus.ok) => .ok,
        @intFromEnum(BrokerStatus.denied) => .denied,
        @intFromEnum(BrokerStatus.unsupported) => .unsupported,
        @intFromEnum(BrokerStatus.invalid_request) => .invalid_request,
        @intFromEnum(BrokerStatus.not_found) => .not_found,
        @intFromEnum(BrokerStatus.insufficient_buffer) => .insufficient_buffer,
        @intFromEnum(BrokerStatus.failed) => .failed,
        else => .failed,
    };
}
