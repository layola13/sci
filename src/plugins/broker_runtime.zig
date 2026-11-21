const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

const BrokerCacheLookupRequest = @import("broker.zig").BrokerCacheLookupRequest;
const BrokerCacheLookupResponse = @import("broker.zig").BrokerCacheLookupResponse;
const BrokerCacheStoreRequest = @import("broker.zig").BrokerCacheStoreRequest;
const BrokerCacheStoreResponse = @import("broker.zig").BrokerCacheStoreResponse;
const BrokerEnvGetRequest = @import("broker.zig").BrokerEnvGetRequest;
const BrokerEnvGetResponse = @import("broker.zig").BrokerEnvGetResponse;
const BrokerFsReadRequest = @import("broker.zig").BrokerFsReadRequest;
const BrokerFsReadResponse = @import("broker.zig").BrokerFsReadResponse;
const BrokerHttpRequest = @import("broker.zig").BrokerHttpRequest;
const BrokerHttpResponse = @import("broker.zig").BrokerHttpResponse;
const BrokerOp = @import("broker.zig").BrokerOp;
const BrokerProcessSpawnRequest = @import("broker.zig").BrokerProcessSpawnRequest;
const BrokerProcessSpawnResponse = @import("broker.zig").BrokerProcessSpawnResponse;
const BrokerStatus = @import("broker.zig").BrokerStatus;
const FrontendCacheDep = @import("plugin_types.zig").FrontendCacheDep;
const FrontendCacheManifest = @import("plugin_types.zig").FrontendCacheManifest;
const RuntimeBroker = @import("plugin_types.zig").RuntimeBroker;
const allowedPermissionUrl = @import("permissions.zig").allowedPermissionUrl;
const fileExistsAbsolute = @import("util.zig").fileExistsAbsolute;
const frontend_cache_manifest_version = @import("plugin_types.zig").frontend_cache_manifest_version;
const max_frontend_cache_artifact_bytes = @import("plugin_types.zig").max_frontend_cache_artifact_bytes;
const max_frontend_cache_dep_bytes = @import("plugin_types.zig").max_frontend_cache_dep_bytes;
const max_frontend_cache_manifest_bytes = @import("plugin_types.zig").max_frontend_cache_manifest_bytes;
const max_net_probe_bytes = @import("plugin_types.zig").max_net_probe_bytes;
const max_process_probe_bytes = @import("plugin_types.zig").max_process_probe_bytes;
const parseBrokerHttpMethod = @import("permission.zig").parseBrokerHttpMethod;
const resolveBrokerRequestPath = @import("permission.zig").resolveBrokerRequestPath;
const resolveExecutablePath = @import("permission.zig").resolveExecutablePath;

fn frontendCacheRoot(allocator: std.mem.Allocator) ![]u8 {
    if (sio.getEnvVarOwned(allocator, "SA_FRONTEND_CACHE_DIR")) |dir| {
        return dir;
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }
    if (sio.getEnvVarOwned(allocator, "XDG_CACHE_HOME")) |base| {
        defer allocator.free(base);
        return std.fs.path.join(allocator, &.{ base, "sa", "frontend" });
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }
    if (sio.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, ".cache", "sa", "frontend" });
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }
    return error.EnvironmentVariableNotFound;
}
fn validFrontendCacheNamespace(ns: []const u8) bool {
    if (ns.len == 0 or ns.len > 64) return false;
    if (std.mem.eql(u8, ns, ".") or std.mem.eql(u8, ns, "..")) return false;
    for (ns) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '.' or c == '-' or c == '_';
        if (!ok) return false;
    }
    return true;
}
fn frontendCacheEntryDir(allocator: std.mem.Allocator, root: []const u8, ns: []const u8, key_material: []const u8) ![]u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(key_material, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return std.fs.path.join(allocator, &.{ root, ns, &hex });
}
/// The closure blob format is owned by the broker contract: a u32
/// little-endian count, then per entry a u32 little-endian length and
/// the path bytes. Returns slices into the blob.
fn parseFrontendCacheClosure(allocator: std.mem.Allocator, blob: []const u8) ![]const []const u8 {
    if (blob.len < 4) return error.InvalidClosure;
    const count = std.mem.readInt(u32, blob[0..4], .little);
    if (count > 100000) return error.InvalidClosure;
    var paths = std.array_list.Managed([]const u8).init(allocator);
    errdefer paths.deinit();
    var offset: usize = 4;
    for (0..count) |_| {
        if (offset + 4 > blob.len) return error.InvalidClosure;
        const len = std.mem.readInt(u32, blob[offset..][0..4], .little);
        offset += 4;
        if (offset + len > blob.len) return error.InvalidClosure;
        try paths.append(blob[offset .. offset + len]);
        offset += len;
    }
    if (offset != blob.len) return error.InvalidClosure;
    return paths.toOwnedSlice();
}
fn frontendCacheFileHash(allocator: std.mem.Allocator, path: []const u8) !FrontendCacheDep {
    const bytes = try sio.cwd().readFileAlloc(allocator, path, max_frontend_cache_dep_bytes);
    defer allocator.free(bytes);
    return .{ .path = path, .len = @intCast(bytes.len), .hash = std.hash.Wyhash.hash(0, bytes) };
}
/// Removes the whole frontend cache root (used by the cache clean command).
/// Returns true when a root existed and was removed.
pub fn cleanFrontendCache(allocator: std.mem.Allocator) !bool {
    const root = frontendCacheRoot(allocator) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return false,
        else => return err,
    };
    defer allocator.free(root);
    sio.cwd().deleteTree(root) catch return false;
    return true;
}
fn runtimeBrokerCacheLookup(broker: *const RuntimeBroker, req: ?*const anyopaque, resp: ?*anyopaque) BrokerStatus {
    const request = if (req) |raw|
        @as(*const BrokerCacheLookupRequest, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    const response = if (resp) |raw|
        @as(*BrokerCacheLookupResponse, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    response.* = .{ .hit = 0, .value_len = 0 };

    if (request.ns_len == 0 or request.key_len == 0) return .invalid_request;
    if (request.value_cap != 0 and request.value_ptr == null) return .invalid_request;
    const ns = request.ns_ptr[0..request.ns_len];
    if (!validFrontendCacheNamespace(ns)) return .invalid_request;

    const allocator = broker.allocator;
    const key_material = request.key_ptr[0..request.key_len];
    const closure_owned = request.closure_len != 0;
    const closure: []const []const u8 = if (closure_owned)
        parseFrontendCacheClosure(allocator, request.closure_ptr[0..request.closure_len]) catch return .invalid_request
    else
        &.{};
    defer if (closure_owned) allocator.free(closure);

    const root = frontendCacheRoot(allocator) catch return .failed;
    defer allocator.free(root);
    const entry_dir = frontendCacheEntryDir(allocator, root, ns, key_material) catch return .failed;
    defer allocator.free(entry_dir);
    const manifest_path = std.fs.path.join(allocator, &.{ entry_dir, "manifest.json" }) catch return .failed;
    defer allocator.free(manifest_path);
    // Every doubt below is a miss, not a failure: an unreadable or stale
    // entry simply means the frontend compiles in full.
    const manifest_bytes = sio.cwd().readFileAlloc(allocator, manifest_path, max_frontend_cache_manifest_bytes) catch return .ok;
    defer allocator.free(manifest_bytes);
    const manifest = std.json.parseFromSlice(FrontendCacheManifest, allocator, manifest_bytes, .{}) catch return .ok;
    defer manifest.deinit();
    if (manifest.value.version != frontend_cache_manifest_version) return .ok;
    if (closure_owned and manifest.value.deps.len != closure.len) return .ok;
    for (manifest.value.deps, 0..) |dep, i| {
        if (closure_owned and !std.mem.eql(u8, dep.path, closure[i])) return .ok;
        const current = frontendCacheFileHash(allocator, dep.path) catch return .ok;
        if (current.len != dep.len or current.hash != dep.hash) return .ok;
    }
    const artifact_path = std.fs.path.join(allocator, &.{ entry_dir, "artifact.bin" }) catch return .failed;
    defer allocator.free(artifact_path);
    const artifact = sio.cwd().readFileAlloc(allocator, artifact_path, max_frontend_cache_artifact_bytes) catch return .ok;
    defer allocator.free(artifact);

    response.value_len = artifact.len;
    if (artifact.len > request.value_cap) return .insufficient_buffer;
    if (artifact.len != 0) {
        const out_ptr = request.value_ptr orelse return .invalid_request;
        @memcpy(out_ptr[0..artifact.len], artifact);
    }
    response.hit = 1;
    return .ok;
}
fn runtimeBrokerCacheStore(broker: *const RuntimeBroker, req: ?*const anyopaque, resp: ?*anyopaque) BrokerStatus {
    const request = if (req) |raw|
        @as(*const BrokerCacheStoreRequest, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    const response = if (resp) |raw|
        @as(*BrokerCacheStoreResponse, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    response.* = .{ .stored = 0 };

    if (request.ns_len == 0 or request.key_len == 0) return .invalid_request;
    if (request.value_len > max_frontend_cache_artifact_bytes) return .invalid_request;
    const ns = request.ns_ptr[0..request.ns_len];
    if (!validFrontendCacheNamespace(ns)) return .invalid_request;

    const allocator = broker.allocator;
    const key_material = request.key_ptr[0..request.key_len];
    const closure = parseFrontendCacheClosure(allocator, request.closure_ptr[0..request.closure_len]) catch return .invalid_request;
    defer allocator.free(closure);

    var deps = std.array_list.Managed(FrontendCacheDep).init(allocator);
    defer deps.deinit();
    for (closure) |path| {
        // Mirror the frontends' local gates: a dependency that cannot be
        // read at store time is simply left unrecorded (the gate stays
        // disarmed for it), never a hard failure.
        const dep = frontendCacheFileHash(allocator, path) catch continue;
        deps.append(dep) catch return .failed;
    }
    if (deps.items.len == 0) return .failed;

    const root = frontendCacheRoot(allocator) catch return .failed;
    defer allocator.free(root);
    const entry_dir = frontendCacheEntryDir(allocator, root, ns, key_material) catch return .failed;
    defer allocator.free(entry_dir);
    sio.cwd().makePath(entry_dir) catch return .failed;

    const artifact_path = std.fs.path.join(allocator, &.{ entry_dir, "artifact.bin" }) catch return .failed;
    defer allocator.free(artifact_path);
    sio.cwd().writeFile(.{ .sub_path = artifact_path, .data = request.value_ptr[0..request.value_len] }) catch return .failed;

    const manifest: FrontendCacheManifest = .{ .version = frontend_cache_manifest_version, .deps = deps.items };
    const manifest_json = std.json.Stringify.valueAlloc(allocator, manifest, .{}) catch return .failed;
    defer allocator.free(manifest_json);
    const manifest_path = std.fs.path.join(allocator, &.{ entry_dir, "manifest.json" }) catch return .failed;
    defer allocator.free(manifest_path);
    sio.cwd().writeFile(.{ .sub_path = manifest_path, .data = manifest_json }) catch return .failed;

    response.stored = 1;
    return .ok;
}
/// Content stamp over a workspace plugin source directory: sap.json,
/// build files, and everything under src/ (relative path + length +
/// Wyhash of contents, chained). Zero means "could not stamp" and
/// always counts as stale.
pub fn workspaceSourceStamp(allocator: std.mem.Allocator, root: []const u8) !u64 {
    var files = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (files.items) |f| allocator.free(f);
        files.deinit();
    }
    for ([_][]const u8{ "sap.json", "build.zig", "build.zig.zon" }) |rel| {
        const full = try std.fs.path.join(allocator, &.{ root, rel });
        defer allocator.free(full);
        if (fileExistsAbsolute(full)) try files.append(try allocator.dupe(u8, rel));
    }
    const src_dir = try std.fs.path.join(allocator, &.{ root, "src" });
    defer allocator.free(src_dir);
    collectWorkspaceFiles(allocator, src_dir, "src", &files) catch {};
    std.mem.sort([]u8, files.items, {}, struct {
        fn lt(_: void, a: []u8, b: []u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lt);
    var hasher = std.hash.Wyhash.init(0);
    for (files.items) |rel| {
        const full = try std.fs.path.join(allocator, &.{ root, rel });
        defer allocator.free(full);
        const bytes = sio.cwd().readFileAlloc(allocator, full, 64 * 1024 * 1024) catch return 0;
        defer allocator.free(bytes);
        hasher.update(rel);
        hasher.update(&std.mem.toBytes(@as(u64, @intCast(bytes.len))));
        hasher.update(&std.mem.toBytes(std.hash.Wyhash.hash(0, bytes)));
    }
    return hasher.final();
}
fn collectWorkspaceFiles(allocator: std.mem.Allocator, dir_path: []const u8, rel_prefix: []const u8, out: *std.array_list.Managed([]u8)) !void {
    var dir = sio.openDirAbsolute(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        const rel = try std.fs.path.join(allocator, &.{ rel_prefix, entry.name });
        errdefer allocator.free(rel);
        const full = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
        defer allocator.free(full);
        switch (entry.kind) {
            .file, .sym_link => try out.append(rel),
            .directory => {
                try collectWorkspaceFiles(allocator, full, rel, out);
                allocator.free(rel);
            },
            else => allocator.free(rel),
        }
    }
}
pub fn runtimeBrokerCall(ctx: ?*anyopaque, op_value: u32, req: ?*const anyopaque, resp: ?*anyopaque) callconv(.c) u32 {
    const broker = if (ctx) |raw|
        @as(*const RuntimeBroker, @ptrCast(@alignCast(raw)))
    else
        return @intFromEnum(BrokerStatus.invalid_request);

    const op = switch (op_value) {
        @intFromEnum(BrokerOp.env_get) => BrokerOp.env_get,
        @intFromEnum(BrokerOp.fs_read) => BrokerOp.fs_read,
        @intFromEnum(BrokerOp.http_request) => BrokerOp.http_request,
        @intFromEnum(BrokerOp.process_spawn) => BrokerOp.process_spawn,
        @intFromEnum(BrokerOp.cache_lookup) => BrokerOp.cache_lookup,
        @intFromEnum(BrokerOp.cache_store) => BrokerOp.cache_store,
        else => return @intFromEnum(BrokerStatus.unsupported),
    };

    return @intFromEnum(switch (op) {
        .env_get => runtimeBrokerEnvGet(broker, req, resp),
        .fs_read => runtimeBrokerFsRead(broker, req, resp),
        .http_request => runtimeBrokerHttpRequest(broker, req, resp),
        .process_spawn => runtimeBrokerProcessSpawn(broker, req, resp),
        .cache_lookup => runtimeBrokerCacheLookup(broker, req, resp),
        .cache_store => runtimeBrokerCacheStore(broker, req, resp),
    });
}
fn runtimeBrokerEnvGet(broker: *const RuntimeBroker, req: ?*const anyopaque, resp: ?*anyopaque) BrokerStatus {
    const request = if (req) |raw|
        @as(*const BrokerEnvGetRequest, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    const response = if (resp) |raw|
        @as(*BrokerEnvGetResponse, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    response.* = .{ .value_len = 0 };

    if (request.name_len == 0) return .invalid_request;
    if (request.value_cap != 0 and request.value_ptr == null) return .invalid_request;

    const env_name = request.name_ptr[0..request.name_len];
    if (!broker.policy.allowsEnv(env_name)) return .denied;
    if (!broker.authorization.allowsEnv(env_name)) return .denied;

    const value = sio.getEnvVarOwned(broker.allocator, env_name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return .not_found,
        else => return .failed,
    };
    defer broker.allocator.free(value);

    response.value_len = value.len;
    if (value.len > request.value_cap) return .insufficient_buffer;
    if (value.len != 0) {
        const out_ptr = request.value_ptr orelse return .invalid_request;
        @memcpy(out_ptr[0..value.len], value);
    }
    return .ok;
}
fn runtimeBrokerFsRead(broker: *const RuntimeBroker, req: ?*const anyopaque, resp: ?*anyopaque) BrokerStatus {
    const request = if (req) |raw|
        @as(*const BrokerFsReadRequest, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    const response = if (resp) |raw|
        @as(*BrokerFsReadResponse, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    response.* = .{ .value_len = 0 };

    if (request.path_len == 0) return .invalid_request;
    if (request.value_cap != 0 and request.value_ptr == null) return .invalid_request;

    const project_root = broker.authorization.effectiveProjectRoot();
    const abs_path = resolveBrokerRequestPath(broker.allocator, request.path_ptr[0..request.path_len], project_root) catch |err| switch (err) {
        error.FileNotFound => return .not_found,
        else => return .failed,
    };
    defer broker.allocator.free(abs_path);

    const manifest_allowed = broker.policy.allowsFs(broker.allocator, project_root, .read, abs_path) catch return .failed;
    if (!manifest_allowed) return .denied;
    const host_allowed = broker.authorization.allowsRead(broker.allocator, abs_path) catch return .failed;
    if (!host_allowed) return .denied;

    var file = sio.openFileAbsolute(abs_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return .not_found,
        else => return .failed,
    };
    defer file.close();

    const file_size = file.getEndPos() catch return .failed;
    response.value_len = @as(usize, @intCast(file_size));
    if (file_size > request.value_cap) return .insufficient_buffer;
    if (file_size == 0) return .ok;

    const out_ptr = request.value_ptr orelse return .invalid_request;
    const out = out_ptr[0..@as(usize, @intCast(file_size))];
    file.readAll(out) catch return .failed;
    return .ok;
}
fn runtimeBrokerHttpRequest(broker: *const RuntimeBroker, req: ?*const anyopaque, resp: ?*anyopaque) BrokerStatus {
    const request = if (req) |raw|
        @as(*const BrokerHttpRequest, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    const response = if (resp) |raw|
        @as(*BrokerHttpResponse, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    response.* = .{
        .status_code = 0,
        .value_len = 0,
    };

    if (request.method_len == 0 or request.url_len == 0) return .invalid_request;
    if (request.body_len != 0 and request.body_ptr == null) return .invalid_request;
    if (request.value_cap != 0 and request.value_ptr == null) return .invalid_request;

    const method_text = request.method_ptr[0..request.method_len];
    const method = parseBrokerHttpMethod(method_text) orelse return .invalid_request;
    if (request.body_len != 0 and !method.requestHasBody()) return .invalid_request;

    const url = request.url_ptr[0..request.url_len];
    if (!allowedPermissionUrl(url)) return .denied;

    const manifest_allowed = broker.policy.allowsNet(broker.allocator, method, url) catch return .failed;
    if (!manifest_allowed) return .denied;
    const host_allowed = broker.authorization.allowsNet(broker.allocator, url) catch return .failed;
    if (!host_allowed) return .denied;

    const uri = std.Uri.parse(url) catch return .invalid_request;
    const body = if (request.body_len == 0)
        ""
    else
        request.body_ptr.?[0..request.body_len];

    var client: std.http.Client = .{ .allocator = broker.allocator, .io = sio.io() };
    defer client.deinit();

    var http_request = client.request(method, uri, .{
        .redirect_behavior = .not_allowed,
        .keep_alive = false,
        .headers = .{
            .accept_encoding = .omit,
        },
    }) catch return .failed;
    defer http_request.deinit();

    if (method.requestHasBody()) {
        // NOTE(Zig 0.17): sendBodyComplete takes mutable []u8.
        const body_mut = broker.allocator.dupe(u8, body) catch return .failed;
        defer broker.allocator.free(body_mut);
        http_request.sendBodyComplete(body_mut) catch return .failed;
    } else {
        http_request.sendBodiless() catch return .failed;
    }
    var redirect_buf: [8 * 1024]u8 = undefined;
    var response_head = http_request.receiveHead(&redirect_buf) catch return .failed;

    response.status_code = @intFromEnum(response_head.head.status);
    if (!method.responseHasBody()) return .ok;

    if (response_head.head.content_length) |content_length| {
        response.value_len = @as(usize, @intCast(content_length));
        if (content_length > request.value_cap) return .insufficient_buffer;
        if (content_length == 0) return .ok;
        const out_ptr = request.value_ptr orelse return .invalid_request;
        const out = out_ptr[0..@as(usize, @intCast(content_length))];
        var transfer_buf: [8192]u8 = undefined;
        response_head.reader(&transfer_buf).readSliceAll(out) catch return .failed;
        return .ok;
    }

    const unknown_body_limit = if (request.value_cap < max_net_probe_bytes)
        request.value_cap + 1
    else
        max_net_probe_bytes;
    var transfer_buf: [8192]u8 = undefined;
    var body_reader = response_head.reader(&transfer_buf);
    const payload = body_reader.allocRemaining(broker.allocator, .limited(unknown_body_limit)) catch |err| {
        if (err == error.StreamTooLong) {
            response.value_len = unknown_body_limit;
            return .insufficient_buffer;
        }
        return .failed;
    };
    defer broker.allocator.free(payload);

    response.value_len = payload.len;
    if (payload.len > request.value_cap) return .insufficient_buffer;
    if (payload.len == 0) return .ok;

    const out_ptr = request.value_ptr orelse return .invalid_request;
    @memcpy(out_ptr[0..payload.len], payload);
    return .ok;
}
fn runtimeBrokerProcessSpawn(broker: *const RuntimeBroker, req: ?*const anyopaque, resp: ?*anyopaque) BrokerStatus {
    const request = if (req) |raw|
        @as(*const BrokerProcessSpawnRequest, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    const response = if (resp) |raw|
        @as(*BrokerProcessSpawnResponse, @ptrCast(@alignCast(raw)))
    else
        return .invalid_request;
    response.* = .{
        .exit_code = 0,
        .stdout_len = 0,
        .stderr_len = 0,
    };

    if (request.path_len == 0) return .invalid_request;
    if (request.argv_len != 0 and request.argv_ptr == null) return .invalid_request;
    if (request.stdout_cap != 0 and request.stdout_ptr == null) return .invalid_request;
    if (request.stderr_cap != 0 and request.stderr_ptr == null) return .invalid_request;

    const path = request.path_ptr[0..request.path_len];
    const abs_path = resolveExecutablePath(broker.allocator, path) catch |err| switch (err) {
        error.FileNotFound => return .not_found,
        error.InvalidPath => return .invalid_request,
        else => return .failed,
    };
    defer broker.allocator.free(abs_path);

    var argv_list = std.array_list.Managed([]const u8).init(broker.allocator);
    defer argv_list.deinit();
    if (request.argv_len != 0) {
        const raw_argv = request.argv_ptr.?[0..request.argv_len];
        for (raw_argv) |arg| {
            if (arg.len == 0) return .invalid_request;
            argv_list.append(arg.ptr[0..arg.len]) catch return .failed;
        }
    }

    const manifest_allowed = broker.policy.allowsProcessSpawn(broker.allocator, abs_path, argv_list.items) catch return .failed;
    if (!manifest_allowed) return .denied;
    const host_allowed = broker.authorization.allowsRun(broker.allocator, abs_path) catch return .failed;
    if (!host_allowed) return .denied;

    var command_argv = std.array_list.Managed([]const u8).init(broker.allocator);
    defer command_argv.deinit();
    command_argv.append(abs_path) catch return .failed;
    command_argv.appendSlice(argv_list.items) catch return .failed;

    const max_output_bytes = if (request.stdout_cap + request.stderr_cap + 1 > max_process_probe_bytes)
        max_process_probe_bytes
    else
        request.stdout_cap + request.stderr_cap + 1;
    const result = sio.Child.run(.{
        .allocator = broker.allocator,
        .argv = command_argv.items,
        .max_output_bytes = max_output_bytes,
    }) catch |err| switch (err) {
        error.FileNotFound => return .not_found,
        error.StreamTooLong => return .insufficient_buffer,
        else => return .failed,
    };
    defer broker.allocator.free(result.stdout);
    defer broker.allocator.free(result.stderr);

    response.stdout_len = result.stdout.len;
    response.stderr_len = result.stderr.len;
    if (result.stdout.len > request.stdout_cap or result.stderr.len > request.stderr_cap) return .insufficient_buffer;

    response.exit_code = switch (result.term) {
        .exited => |code| code,
        else => return .failed,
    };

    if (result.stdout.len != 0) {
        const stdout_ptr = request.stdout_ptr orelse return .invalid_request;
        @memcpy(stdout_ptr[0..result.stdout.len], result.stdout);
    }
    if (result.stderr.len != 0) {
        const stderr_ptr = request.stderr_ptr orelse return .invalid_request;
        @memcpy(stderr_ptr[0..result.stderr.len], result.stderr);
    }
    return .ok;
}
