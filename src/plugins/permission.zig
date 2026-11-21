const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

const RuntimePermissionPolicy = @import("plugin_types.zig").RuntimePermissionPolicy;
const fileExistsAbsolute = @import("util.zig").fileExistsAbsolute;
const parseSapManifest = @import("fetch.zig").parseSapManifest;
const pluginsHome = @import("fetch.zig").pluginsHome;

pub fn loadRuntimePermissionPolicy(allocator: std.mem.Allocator, lib_path: []const u8) !RuntimePermissionPolicy {
    const dir_path = std.fs.path.dirname(lib_path) orelse return .{};
    const sap_path = try std.fs.path.join(allocator, &.{ dir_path, "sap.json" });
    defer allocator.free(sap_path);
    if (!fileExistsAbsolute(sap_path)) return .{};

    var manifest = parseSapManifest(allocator, sap_path) catch return .{};
    defer manifest.deinit(allocator);
    return try RuntimePermissionPolicy.initFromManifest(allocator, manifest);
}
pub fn appendOwnedStrings(allocator: std.mem.Allocator, list: *std.ArrayList([]u8), entries: []const []const u8) !void {
    for (entries) |entry| {
        try list.append(allocator, try allocator.dupe(u8, entry));
    }
}
pub fn freeOwnedStringList(allocator: std.mem.Allocator, list: *std.ArrayList([]u8)) void {
    for (list.items) |entry| allocator.free(entry);
    list.deinit(allocator);
}
pub fn matchesAnyEnvPattern(patterns: []const []u8, name: []const u8) bool {
    for (patterns) |entry| {
        if (std.mem.endsWith(u8, entry, "*")) {
            if (std.mem.startsWith(u8, name, entry[0 .. entry.len - 1])) return true;
            continue;
        }
        if (std.mem.eql(u8, name, entry)) return true;
    }
    return false;
}
pub fn resolveBrokerRequestPath(allocator: std.mem.Allocator, requested_path: []const u8, project_root: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(requested_path)) return try sio.cwd().realpathAlloc(allocator, requested_path);
    const joined = try std.fs.path.join(allocator, &.{ project_root, requested_path });
    defer allocator.free(joined);
    return try sio.cwd().realpathAlloc(allocator, joined);
}
pub fn parseBrokerHttpMethod(text: []const u8) ?std.http.Method {
    const method: std.http.Method = std.meta.stringToEnum(std.http.Method, text) orelse return null;
    return switch (method) {
        .GET, .POST, .PUT, .PATCH, .DELETE, .HEAD, .OPTIONS => method,
        else => null,
    };
}
pub fn httpMethodBit(method: std.http.Method) ?u16 {
    return switch (method) {
        .GET => 1 << 0,
        .POST => 1 << 1,
        .PUT => 1 << 2,
        .PATCH => 1 << 3,
        .DELETE => 1 << 4,
        .HEAD => 1 << 5,
        .OPTIONS => 1 << 6,
        else => null,
    };
}
pub fn matchesUrlPermissionPattern(allocator: std.mem.Allocator, pattern_url: []const u8, requested_url: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const pattern_uri = std.Uri.parse(pattern_url) catch return false;
    const requested_uri = std.Uri.parse(requested_url) catch return false;

    if (!std.ascii.eqlIgnoreCase(pattern_uri.scheme, requested_uri.scheme)) return false;

    const pattern_host_component = pattern_uri.host orelse return false;
    const requested_host_component = requested_uri.host orelse return false;
    const pattern_host = try pattern_host_component.toRawMaybeAlloc(arena_alloc);
    const requested_host = try requested_host_component.toRawMaybeAlloc(arena_alloc);
    if (!std.ascii.eqlIgnoreCase(pattern_host, requested_host)) return false;

    if (effectiveUriPort(pattern_uri) != effectiveUriPort(requested_uri)) return false;

    const pattern_path = normalizedUriPath(pattern_uri, arena_alloc) catch return false;
    const requested_path = normalizedUriPath(requested_uri, arena_alloc) catch return false;
    return uriPathAllows(pattern_path, requested_path);
}
fn effectiveUriPort(uri: std.Uri) ?u16 {
    if (uri.port) |port| return port;
    if (std.ascii.eqlIgnoreCase(uri.scheme, "https")) return 443;
    if (std.ascii.eqlIgnoreCase(uri.scheme, "http")) return 80;
    return null;
}
fn normalizedUriPath(uri: std.Uri, allocator: std.mem.Allocator) ![]const u8 {
    const raw_path = try uri.path.toRawMaybeAlloc(allocator);
    if (raw_path.len == 0) return "/";
    return trimTrailingSlashExceptRoot(raw_path);
}
fn trimTrailingSlashExceptRoot(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') : (end -= 1) {}
    return path[0..end];
}
fn uriPathAllows(pattern_path: []const u8, requested_path: []const u8) bool {
    if (std.mem.eql(u8, pattern_path, "/")) return true;
    if (std.mem.eql(u8, pattern_path, requested_path)) return true;
    if (!std.mem.startsWith(u8, requested_path, pattern_path)) return false;
    return requested_path.len > pattern_path.len and requested_path[pattern_path.len] == '/';
}
pub fn resolveExecutablePath(allocator: std.mem.Allocator, requested_path: []const u8) ![]u8 {
    if (!std.fs.path.isAbsolute(requested_path)) return error.InvalidPath;
    return try sio.cwd().realpathAlloc(allocator, requested_path);
}
pub fn matchesExecutablePermissionPath(allocator: std.mem.Allocator, declared_path: []const u8, abs_path: []const u8) !bool {
    if (!std.fs.path.isAbsolute(declared_path)) return false;
    const resolved_declared = sio.cwd().realpathAlloc(allocator, declared_path) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer allocator.free(resolved_declared);
    return std.mem.eql(u8, resolved_declared, abs_path);
}
pub fn processArgsMatch(patterns: []const []u8, argv: []const []const u8) bool {
    if (patterns.len != argv.len) return false;
    for (patterns, argv) |pattern, arg| {
        if (std.mem.eql(u8, pattern, "*")) continue;
        if (!std.mem.eql(u8, pattern, arg)) return false;
    }
    return true;
}
pub fn matchesPathPermissionPattern(allocator: std.mem.Allocator, pattern: []const u8, project_root: []const u8, abs_path: []const u8) !bool {
    const resolved = try resolvePermissionPathPattern(allocator, pattern, project_root);
    defer allocator.free(resolved);

    const normalized_resolved = try normalizePermissionPathForMatch(allocator, resolved);
    defer allocator.free(normalized_resolved);
    const normalized_abs_path = try normalizePermissionPathForMatch(allocator, abs_path);
    defer allocator.free(normalized_abs_path);

    const recursive = std.mem.endsWith(u8, normalized_resolved, "/**");
    const base = if (recursive) normalized_resolved[0 .. normalized_resolved.len - 3] else normalized_resolved;
    if (recursive) {
        if (std.mem.eql(u8, normalized_abs_path, base)) return true;
        if (base.len == 0) return false;
        if (!std.mem.startsWith(u8, normalized_abs_path, base)) return false;
        return normalized_abs_path.len > base.len and normalized_abs_path[base.len] == '/';
    }
    return std.mem.eql(u8, normalized_abs_path, base);
}
fn normalizePermissionPathForMatch(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const normalized = try allocator.dupe(u8, path);
    for (normalized) |*c| {
        if (c.* == '\\') c.* = '/';
        if (@import("builtin").os.tag == .windows) c.* = std.ascii.toLower(c.*);
    }
    return normalized;
}
fn permissionHome(allocator: std.mem.Allocator) ![]u8 {
    return sio.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => if (@import("builtin").os.tag == .windows)
            sio.getEnvVarOwned(allocator, "USERPROFILE")
        else
            error.EnvironmentVariableNotFound,
        else => err,
    };
}
fn resolvePermissionPathPattern(allocator: std.mem.Allocator, pattern: []const u8, project_root: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, pattern, "$PROJECT/") or std.mem.eql(u8, pattern, "$PROJECT")) {
        return try resolvePatternFromRoot(allocator, project_root, pattern["$PROJECT".len..]);
    }
    if (std.mem.startsWith(u8, pattern, "$HOME/") or std.mem.eql(u8, pattern, "$HOME")) {
        const home = permissionHome(allocator) catch return error.InvalidPath;
        defer allocator.free(home);
        return try resolvePatternFromRoot(allocator, home, pattern["$HOME".len..]);
    }
    if (std.mem.startsWith(u8, pattern, "$SA_PLUGINS_HOME/") or std.mem.eql(u8, pattern, "$SA_PLUGINS_HOME")) {
        const home = try pluginsHome(allocator);
        defer allocator.free(home);
        return try resolvePatternFromRoot(allocator, home, pattern["$SA_PLUGINS_HOME".len..]);
    }
    if (std.mem.startsWith(u8, pattern, "$SA_CACHE/") or std.mem.eql(u8, pattern, "$SA_CACHE")) {
        const cache_root = try std.fs.path.join(allocator, &.{ project_root, ".sa_cache" });
        defer allocator.free(cache_root);
        return try resolvePatternFromRoot(allocator, cache_root, pattern["$SA_CACHE".len..]);
    }
    if (std.fs.path.isAbsolute(pattern)) return try allocator.dupe(u8, pattern);
    return error.InvalidPath;
}
fn resolvePatternFromRoot(allocator: std.mem.Allocator, root: []const u8, suffix: []const u8) ![]u8 {
    const recursive = std.mem.endsWith(u8, suffix, "/**");
    const suffix_body = if (recursive) suffix[0 .. suffix.len - 3] else suffix;
    const trimmed = std.mem.trimStart(u8, suffix_body, "/");
    const base = if (trimmed.len == 0)
        try allocator.dupe(u8, root)
    else
        try std.fs.path.join(allocator, &.{ root, trimmed });
    if (!recursive) return base;
    defer allocator.free(base);
    return try std.fmt.allocPrint(allocator, "{s}/**", .{base});
}
test "Windows permission path matching ignores separator and ASCII case" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };
    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const requested_path = try std.fs.path.join(std.testing.allocator, &.{ project_root, "DATA", "ITEM.TXT" });
    defer std.testing.allocator.free(requested_path);
    for (requested_path) |*c| {
        if (c.* == '\\') c.* = '/';
        c.* = std.ascii.toUpper(c.*);
    }

    try std.testing.expect(try matchesPathPermissionPattern(
        std.testing.allocator,
        "$PROJECT/data/**",
        project_root,
        requested_path,
    ));
}
test "permission path roots expand for host matching" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };
    const project_root = try tdir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);

    const project_path = try std.fs.path.join(std.testing.allocator, &.{ project_root, "data", "item.txt" });
    defer std.testing.allocator.free(project_path);
    try std.testing.expect(try matchesPathPermissionPattern(std.testing.allocator, "$PROJECT/data/**", project_root, project_path));

    const cache_path = try std.fs.path.join(std.testing.allocator, &.{ project_root, ".sa_cache", "item.txt" });
    defer std.testing.allocator.free(cache_path);
    try std.testing.expect(try matchesPathPermissionPattern(std.testing.allocator, "$SA_CACHE/**", project_root, cache_path));

    const home = try permissionHome(std.testing.allocator);
    defer std.testing.allocator.free(home);
    const home_path = try std.fs.path.join(std.testing.allocator, &.{ home, "sa-permission-item.txt" });
    defer std.testing.allocator.free(home_path);
    try std.testing.expect(try matchesPathPermissionPattern(std.testing.allocator, "$HOME/**", project_root, home_path));

    const plugins_home = try pluginsHome(std.testing.allocator);
    defer std.testing.allocator.free(plugins_home);
    const plugin_path = try std.fs.path.join(std.testing.allocator, &.{ plugins_home, "installed", "item" });
    defer std.testing.allocator.free(plugin_path);
    try std.testing.expect(try matchesPathPermissionPattern(std.testing.allocator, "$SA_PLUGINS_HOME/**", project_root, plugin_path));
}
