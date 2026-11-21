const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

const FsPermission = @import("plugin_types.zig").FsPermission;
const FsPermissionOp = @import("plugin_types.zig").FsPermissionOp;
const HttpMethodMask = @import("plugin_types.zig").HttpMethodMask;
const InstallOptions = @import("install.zig").InstallOptions;
const NativeLinkEntry = @import("install.zig").NativeLinkEntry;
const NetPermission = @import("plugin_types.zig").NetPermission;
const PluginDependency = @import("install.zig").PluginDependency;
const ProcessExecPermission = @import("plugin_types.zig").ProcessExecPermission;
const SapManifest = @import("install.zig").SapManifest;
const abi_version = @import("broker.zig").abi_version;
const artifact_import_rules = @import("manifest.zig").artifact_import_rules;
const childExitedZero = @import("remote.zig").childExitedZero;
const externSymbolExists = @import("manifest.zig").externSymbolExists;
const jsonString = @import("manifest.zig").jsonString;
const parseBrokerHttpMethod = @import("permission.zig").parseBrokerHttpMethod;
const pluginDevMode = @import("util.zig").pluginDevMode;

pub fn verifyArtifactStaticPolicy(
    allocator: std.mem.Allocator,
    manifest: SapManifest,
    artifact_abs: []const u8,
    stdout: anytype,
    options: InstallOptions,
) !u8 {
    var imports = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (imports.items) |symbol| allocator.free(symbol);
        imports.deinit();
    }
    try collectArtifactUndefinedImports(allocator, artifact_abs, &imports);
    for (artifact_import_rules) |rule| {
        if (!externSymbolExists(imports.items, rule.symbol)) continue;
        switch (rule.capability) {
            .fs => if (!manifest.has_fs_permission) {
                try stdout.print("plugin artifact references file-system symbol without declared fs permission: {s}\n", .{rule.symbol});
                return 1;
            },
            .net => if (!manifest.has_net_permission) {
                try stdout.print("plugin artifact references network symbol without declared net permission: {s}\n", .{rule.symbol});
                return 1;
            },
            .env => if (!manifest.has_env_permission) {
                try stdout.print("plugin artifact references environment symbol without declared env permission: {s}\n", .{rule.symbol});
                return 1;
            },
            .process => if (!manifest.has_process_permission and !options.dev and !pluginDevMode(allocator)) {
                try stdout.print("plugin artifact references process symbol without declared process permission: {s}\n", .{rule.symbol});
                return 1;
            },
            .dynamic_loader => if (!options.dev and !pluginDevMode(allocator)) {
                try stdout.print("plugin artifact references dynamic loader symbol forbidden for formal install: {s}\n", .{rule.symbol});
                return 1;
            },
        }
    }
    return 0;
}
fn collectArtifactUndefinedImports(allocator: std.mem.Allocator, artifact_abs: []const u8, out: *std.array_list.Managed([]u8)) !void {
    if (@import("builtin").os.tag == .windows) {
        const tools = [_][]const u8{"dumpbin"};
        for (tools) |tool| {
            const result = sio.Child.run(.{
                .allocator = allocator,
                .argv = &.{ tool, "/nologo", "/imports", artifact_abs },
            }) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);
            if (!childExitedZero(result.term)) continue;
            try parseDumpbinImportList(allocator, result.stdout, out);
            return;
        }
        return error.PluginArtifactScanUnavailable;
    }

    const tools = [_][]const u8{ "nm", "llvm-nm" };
    for (tools) |tool| {
        const result = sio.Child.run(.{
            .allocator = allocator,
            .argv = &.{ tool, "-D", "--undefined-only", artifact_abs },
        }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        if (!childExitedZero(result.term)) continue;
        try parseUndefinedImportList(allocator, result.stdout, out);
        return;
    }
    return error.PluginArtifactScanUnavailable;
}
fn parseDumpbinImportList(allocator: std.mem.Allocator, text: []const u8, out: *std.array_list.Managed([]u8)) !void {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.endsWith(u8, line, ".dll") or std.mem.endsWith(u8, line, ".DLL")) continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const first = fields.next() orelse continue;
        if (!isHexToken(first)) continue;
        const symbol = fields.next() orelse continue;
        if (std.mem.eql(u8, symbol, "Ordinal")) continue;
        if (symbol.len == 0 or externSymbolExists(out.items, symbol)) continue;
        try out.append(try allocator.dupe(u8, symbol));
    }
}
fn isHexToken(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| switch (c) {
        '0'...'9', 'a'...'f', 'A'...'F' => {},
        else => return false,
    };
    return true;
}
fn parseUndefinedImportList(allocator: std.mem.Allocator, text: []const u8, out: *std.array_list.Managed([]u8)) !void {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        const last_delim = std.mem.lastIndexOfAny(u8, line, " \t") orelse continue;
        var symbol = std.mem.trim(u8, line[last_delim + 1 ..], " \t");
        if (std.mem.indexOfScalar(u8, symbol, '@')) |version_idx| symbol = symbol[0..version_idx];
        if (symbol.len == 0 or externSymbolExists(out.items, symbol)) continue;
        try out.append(try allocator.dupe(u8, symbol));
    }
}
pub fn collectStringArray(allocator: std.mem.Allocator, maybe_value: ?std.json.Value) ![][]u8 {
    var items = std.array_list.Managed([]u8).init(allocator);
    errdefer {
        for (items.items) |item| allocator.free(item);
        items.deinit();
    }
    const value = maybe_value orelse return try items.toOwnedSlice();
    const arr = switch (value) {
        .array => |a| a,
        else => return error.InvalidSapManifest,
    };
    for (arr.items) |item| try items.append(try allocator.dupe(u8, try jsonString(item)));
    return try items.toOwnedSlice();
}
pub fn collectPluginDependencies(allocator: std.mem.Allocator, maybe_value: ?std.json.Value) ![]PluginDependency {
    var deps = std.array_list.Managed(PluginDependency).init(allocator);
    errdefer {
        for (deps.items) |*dep| dep.deinit(allocator);
        deps.deinit();
    }
    const value = maybe_value orelse return try deps.toOwnedSlice();
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidSapManifest,
    };
    var it = obj.iterator();
    while (it.next()) |entry| {
        const dep_obj = switch (entry.value_ptr.*) {
            .object => |o| o,
            else => return error.InvalidSapManifest,
        };
        const version = if (dep_obj.get("version")) |version_value| try jsonString(version_value) else "*";
        const abi = if (dep_obj.get("abi")) |abi_value| switch (abi_value) {
            .integer => |n| if (n >= 0 and n <= std.math.maxInt(u32)) @as(u32, @intCast(n)) else return error.InvalidSapManifest,
            else => return error.InvalidSapManifest,
        } else abi_version;
        const optional = if (dep_obj.get("optional")) |optional_value| switch (optional_value) {
            .bool => |b| b,
            else => return error.InvalidSapManifest,
        } else false;
        const dep_symbols = try collectStringArray(allocator, dep_obj.get("symbols"));
        errdefer {
            for (dep_symbols) |symbol| allocator.free(symbol);
            allocator.free(dep_symbols);
        }
        const dep_path = if (dep_obj.get("path")) |path_value| try allocator.dupe(u8, try jsonString(path_value)) else null;
        errdefer if (dep_path) |path| allocator.free(path);
        const dep_url = if (dep_obj.get("url")) |url_value| blk: {
            const url = try jsonString(url_value);
            if (!allowedExternalUrl(url)) return error.InvalidSapManifest;
            break :blk try allocator.dupe(u8, url);
        } else null;
        errdefer if (dep_url) |url| allocator.free(url);
        try rejectUnknownKeys(dep_obj, &.{ "version", "abi", "optional", "symbols", "path", "url" });
        try deps.append(.{
            .name = try allocator.dupe(u8, entry.key_ptr.*),
            .version = try allocator.dupe(u8, version),
            .abi = abi,
            .optional = optional,
            .symbols = dep_symbols,
            .path = dep_path,
            .url = dep_url,
        });
    }
    return try deps.toOwnedSlice();
}
pub fn collectManifestExternalUrls(allocator: std.mem.Allocator, object: std.json.ObjectMap, urls: *std.array_list.Managed([]u8)) !void {
    if (object.get("source")) |source_value| {
        const source_obj = switch (source_value) {
            .object => |o| o,
            else => return error.InvalidSapManifest,
        };
        if (source_obj.get("url")) |url_value| {
            const url = try jsonString(url_value);
            if (!allowedExternalUrl(url)) return error.InvalidSapManifest;
            try urls.append(try allocator.dupe(u8, url));
        }
    }
    if (object.get("dependencies")) |deps_value| {
        const deps_obj = switch (deps_value) {
            .object => |o| o,
            else => return error.InvalidSapManifest,
        };
        var it = deps_obj.iterator();
        while (it.next()) |entry| {
            const dep_obj = switch (entry.value_ptr.*) {
                .object => |o| o,
                else => return error.InvalidSapManifest,
            };
            if (dep_obj.get("url")) |url_value| {
                const url = try jsonString(url_value);
                if (!allowedExternalUrl(url)) return error.InvalidSapManifest;
                try urls.append(try allocator.dupe(u8, url));
            }
        }
    }
}
pub const PermissionInfo = struct {
    requires_sandbox: bool,
    digest: [32]u8,
    urls: std.array_list.Managed([]u8),
    env_permissions: std.array_list.Managed([]u8),
    fs_permissions: std.array_list.Managed(FsPermission),
    net_permissions: std.array_list.Managed(NetPermission),
    process_spawn: bool,
    process_exec_permissions: std.array_list.Managed(ProcessExecPermission),
    native_link: std.array_list.Managed(NativeLinkEntry),
    has_fs_permission: bool,
    has_net_permission: bool,
    has_env_permission: bool,
    has_process_permission: bool,
    has_native_link_permission: bool,

    pub fn deinit(self: *PermissionInfo, allocator: std.mem.Allocator) void {
        for (self.urls.items) |url| allocator.free(url);
        self.urls.deinit();
        for (self.env_permissions.items) |entry| allocator.free(entry);
        self.env_permissions.deinit();
        for (self.fs_permissions.items) |*entry| entry.deinit(allocator);
        self.fs_permissions.deinit();
        for (self.net_permissions.items) |*entry| entry.deinit(allocator);
        self.net_permissions.deinit();
        for (self.process_exec_permissions.items) |*entry| entry.deinit(allocator);
        self.process_exec_permissions.deinit();
        for (self.native_link.items) |*entry| entry.deinit(allocator);
        self.native_link.deinit();
        self.* = undefined;
    }
};
pub fn validatePermissions(allocator: std.mem.Allocator, value: std.json.Value) !PermissionInfo {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.PluginPermissionsMissing,
    };
    try validatePermissionKeys(obj);
    const permissions_json = try std.json.Stringify.valueAlloc(allocator, value, .{});
    defer allocator.free(permissions_json);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(permissions_json);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    var requires_sandbox = false;
    var has_fs_permission = false;
    var has_net_permission = false;
    var has_env_permission = false;
    var has_process_permission = false;
    var has_native_link_permission = false;
    var urls = std.array_list.Managed([]u8).init(allocator);
    var env_permissions = std.array_list.Managed([]u8).init(allocator);
    var fs_permissions = std.array_list.Managed(FsPermission).init(allocator);
    var net_permissions = std.array_list.Managed(NetPermission).init(allocator);
    var process_spawn = false;
    var process_exec_permissions = std.array_list.Managed(ProcessExecPermission).init(allocator);
    var native_link = std.array_list.Managed(NativeLinkEntry).init(allocator);
    errdefer {
        for (urls.items) |url| allocator.free(url);
        urls.deinit();
        for (env_permissions.items) |entry| allocator.free(entry);
        env_permissions.deinit();
        for (fs_permissions.items) |*entry| entry.deinit(allocator);
        fs_permissions.deinit();
        for (net_permissions.items) |*entry| entry.deinit(allocator);
        net_permissions.deinit();
        for (process_exec_permissions.items) |*entry| entry.deinit(allocator);
        process_exec_permissions.deinit();
        for (native_link.items) |*entry| entry.deinit(allocator);
        native_link.deinit();
    }

    if (obj.get("fs")) |fs_value| switch (fs_value) {
        .array => |arr| {
            has_fs_permission = arr.items.len != 0;
            if (arr.items.len != 0) requires_sandbox = true;
            for (arr.items) |item| try fs_permissions.append(try parseFsPermission(allocator, item));
        },
        else => return error.InvalidPluginPermission,
    } else return error.InvalidPluginPermission;
    if (obj.get("net")) |net_value| switch (net_value) {
        .array => |arr| {
            has_net_permission = arr.items.len != 0;
            if (arr.items.len != 0) requires_sandbox = true;
            for (arr.items) |item| {
                var permission = try parseNetPermission(allocator, item);
                errdefer permission.deinit(allocator);
                try urls.append(try allocator.dupe(u8, permission.url));
                try net_permissions.append(permission);
            }
        },
        else => return error.InvalidPluginPermission,
    } else return error.InvalidPluginPermission;
    if (obj.get("env")) |env_value| switch (env_value) {
        .array => |arr| {
            has_env_permission = arr.items.len != 0;
            if (arr.items.len != 0) requires_sandbox = true;
            for (arr.items) |item| {
                const name = try jsonString(item);
                if (!validEnvPermission(name)) return error.InvalidPluginPermission;
                try env_permissions.append(try allocator.dupe(u8, name));
            }
        },
        else => return error.InvalidPluginPermission,
    } else return error.InvalidPluginPermission;
    if (obj.get("process")) |process_value| {
        const process_obj = switch (process_value) {
            .object => |o| o,
            else => return error.InvalidPluginPermission,
        };
        try rejectUnknownKeys(process_obj, &.{ "spawn", "exec" });
        if (process_obj.get("spawn")) |spawn_value| switch (spawn_value) {
            .bool => |spawn_value_bool| {
                if (spawn_value_bool) requires_sandbox = true;
                if (spawn_value_bool) has_process_permission = true;
                process_spawn = spawn_value_bool;
            },
            else => return error.InvalidPluginPermission,
        } else return error.InvalidPluginPermission;
        if (process_obj.get("exec")) |exec_value| switch (exec_value) {
            .array => |arr| {
                if (arr.items.len != 0) has_process_permission = true;
                if (arr.items.len != 0) requires_sandbox = true;
                if (arr.items.len != 0 and !process_spawn) return error.InvalidPluginPermission;
                if (process_spawn and arr.items.len == 0) return error.InvalidPluginPermission;
                for (arr.items) |item| try process_exec_permissions.append(try parseProcessExecPermission(allocator, item));
            },
            else => return error.InvalidPluginPermission,
        } else return error.InvalidPluginPermission;
    } else return error.InvalidPluginPermission;
    // native_link is the one optional permissions key: existing
    // manifests do not declare it, and absence means "no native
    // libraries" (the permission digest is unchanged for them).
    if (obj.get("native_link")) |native_link_value| switch (native_link_value) {
        .array => |arr| {
            has_native_link_permission = arr.items.len != 0;
            if (arr.items.len != 0) requires_sandbox = true;
            for (arr.items) |item| try native_link.append(try parseNativeLinkEntry(allocator, item));
        },
        else => return error.InvalidPluginPermission,
    };
    return .{
        .requires_sandbox = requires_sandbox,
        .digest = digest,
        .urls = urls,
        .env_permissions = env_permissions,
        .fs_permissions = fs_permissions,
        .net_permissions = net_permissions,
        .process_spawn = process_spawn,
        .process_exec_permissions = process_exec_permissions,
        .native_link = native_link,
        .has_fs_permission = has_fs_permission,
        .has_net_permission = has_net_permission,
        .has_env_permission = has_env_permission,
        .has_process_permission = has_process_permission,
        .has_native_link_permission = has_native_link_permission,
    };
}
fn validatePermissionKeys(obj: std.json.ObjectMap) !void {
    try rejectUnknownKeys(obj, &.{ "fs", "net", "env", "process", "native_link" });
}
/// Relative native_link paths/dirs follow the project-relative rule
/// (no absolute form, no empty/dot/dotdot components); absolute forms
/// are accepted as declared, confirmation-covered content.
fn validNativeLinkPath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (std.fs.path.isAbsolute(path)) return true;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}
fn parseNativeLinkEntry(allocator: std.mem.Allocator, value: std.json.Value) !NativeLinkEntry {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidPluginPermission,
    };
    try rejectUnknownKeys(obj, &.{ "lib", "path", "dirs" });
    const lib_value = obj.get("lib");
    const path_value = obj.get("path");
    if ((lib_value == null) == (path_value == null)) return error.InvalidPluginPermission;

    var dirs = std.array_list.Managed([]u8).init(allocator);
    errdefer {
        for (dirs.items) |dir| allocator.free(dir);
        dirs.deinit();
    }
    if (obj.get("dirs")) |dirs_value| {
        // Search directories qualify a `lib` name lookup; a direct
        // `path` entry already names its file, so dirs with path is
        // an ambiguous declaration and is rejected loudly.
        if (path_value != null) return error.InvalidPluginPermission;
        const arr = switch (dirs_value) {
            .array => |a| a,
            else => return error.InvalidPluginPermission,
        };
        for (arr.items) |item| {
            const dir = try jsonString(item);
            if (!validNativeLinkPath(dir)) return error.InvalidPluginPermission;
            try dirs.append(try allocator.dupe(u8, dir));
        }
    }

    if (lib_value) |lib_item| {
        const name = try jsonString(lib_item);
        // A lib entry is handed to the linker as -l<name>: reject
        // anything that could break out of that shape (path
        // separators, a leading '-' that would read as a flag).
        if (name.len == 0) return error.InvalidPluginPermission;
        if (name[0] == '-') return error.InvalidPluginPermission;
        if (std.mem.indexOfAny(u8, name, "/\\") != null) return error.InvalidPluginPermission;
        return .{
            .kind = .lib,
            .name = try allocator.dupe(u8, name),
            .dirs = try dirs.toOwnedSlice(),
        };
    }
    const path = try jsonString(path_value.?);
    if (!validNativeLinkPath(path)) return error.InvalidPluginPermission;
    return .{
        .kind = .path,
        .name = try allocator.dupe(u8, path),
        .dirs = try dirs.toOwnedSlice(),
    };
}
fn rejectUnknownKeys(obj: std.json.ObjectMap, allowed: []const []const u8) !void {
    var it = obj.iterator();
    while (it.next()) |entry| {
        var ok = false;
        for (allowed) |key| {
            if (std.mem.eql(u8, entry.key_ptr.*, key)) {
                ok = true;
                break;
            }
        }
        if (!ok) return error.InvalidPluginPermission;
    }
}
fn parseFsPermission(allocator: std.mem.Allocator, value: std.json.Value) !FsPermission {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidPluginPermission,
    };
    try rejectUnknownKeys(obj, &.{ "op", "path" });
    const op = try jsonString(obj.get("op") orelse return error.InvalidPluginPermission);
    const path = try jsonString(obj.get("path") orelse return error.InvalidPluginPermission);
    if (!validPermissionPath(path)) return error.InvalidPluginPermission;
    return .{
        .op = parseFsPermissionOp(op) orelse return error.InvalidPluginPermission,
        .path = try allocator.dupe(u8, path),
    };
}
fn parseNetPermission(allocator: std.mem.Allocator, value: std.json.Value) !NetPermission {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidPluginPermission,
    };
    try rejectUnknownKeys(obj, &.{ "url", "methods" });
    const url = try jsonString(obj.get("url") orelse return error.InvalidPluginPermission);
    if (!allowedPermissionUrl(url)) return error.InvalidPluginPermission;
    return .{
        .url = try allocator.dupe(u8, url),
        .methods = if (obj.get("methods")) |methods_value|
            try parseHttpMethods(methods_value)
        else
            HttpMethodMask.default(),
    };
}
fn parseFsPermissionOp(text: []const u8) ?FsPermissionOp {
    if (std.mem.eql(u8, text, "read")) return .read;
    if (std.mem.eql(u8, text, "write")) return .write;
    if (std.mem.eql(u8, text, "create")) return .create;
    if (std.mem.eql(u8, text, "delete")) return .delete;
    if (std.mem.eql(u8, text, "metadata")) return .metadata;
    return null;
}
fn validPermissionPath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/**") or std.mem.eql(u8, path, "~/**")) return false;
    if (std.mem.indexOf(u8, path, "..") != null) return false;
    if (std.mem.indexOf(u8, path, "**") != null and !std.mem.endsWith(u8, path, "/**")) return false;
    return std.mem.startsWith(u8, path, "$PROJECT/") or
        std.mem.startsWith(u8, path, "$HOME/") or
        std.mem.startsWith(u8, path, "$SA_CACHE/") or
        std.mem.startsWith(u8, path, "$SA_PLUGINS_HOME/") or
        (std.fs.path.isAbsolute(path) and !std.mem.startsWith(u8, path, "/dev/") and !std.mem.startsWith(u8, path, "/proc/"));
}
fn parseHttpMethods(value: std.json.Value) !HttpMethodMask {
    const arr = switch (value) {
        .array => |a| a,
        else => return error.InvalidPluginPermission,
    };
    var mask = HttpMethodMask{};
    for (arr.items) |item| {
        const method = try jsonString(item);
        mask.insert(parseBrokerHttpMethod(method) orelse return error.InvalidPluginPermission);
    }
    if (mask.bits == 0) return error.InvalidPluginPermission;
    return mask;
}
fn validEnvPermission(name: []const u8) bool {
    if (name.len == 0 or std.mem.eql(u8, name, "*")) return false;
    const body = if (std.mem.endsWith(u8, name, "*")) name[0 .. name.len - 1] else name;
    if (body.len == 0) return false;
    for (body) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    }
    return true;
}
fn parseProcessExecPermission(allocator: std.mem.Allocator, value: std.json.Value) !ProcessExecPermission {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidPluginPermission,
    };
    try rejectUnknownKeys(obj, &.{ "path", "args" });
    const path = try jsonString(obj.get("path") orelse return error.InvalidPluginPermission);
    if (!std.fs.path.isAbsolute(path)) return error.InvalidPluginPermission;
    var args = std.array_list.Managed([]u8).init(allocator);
    errdefer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit();
    }
    if (obj.get("args")) |args_value| {
        const arr = switch (args_value) {
            .array => |a| a,
            else => return error.InvalidPluginPermission,
        };
        for (arr.items) |item| {
            const arg = try jsonString(item);
            if (arg.len == 0) return error.InvalidPluginPermission;
            try args.append(try allocator.dupe(u8, arg));
        }
    }
    return .{
        .path = try allocator.dupe(u8, path),
        .args = try args.toOwnedSlice(),
    };
}
const PermissionUrlParts = struct {
    scheme: []const u8,
    host: []const u8,
};
pub fn allowedPermissionUrl(url: []const u8) bool {
    const parts = parsePermissionUrlParts(url) orelse return false;
    if (std.ascii.eqlIgnoreCase(parts.scheme, "http")) return isLoopbackPermissionHost(parts.host);
    if (!std.ascii.eqlIgnoreCase(parts.scheme, "https")) return false;
    if (isWildcardPermissionHost(parts.host)) return true;
    if (isIpLiteralHost(parts.host) and !isLoopbackPermissionHost(parts.host)) return false;
    return true;
}
pub fn allowedExternalUrl(url: []const u8) bool {
    if (std.mem.startsWith(u8, url, "github:")) return true;
    return allowedPermissionUrl(url);
}
fn parsePermissionUrlParts(url: []const u8) ?PermissionUrlParts {
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return null;
    const scheme = url[0..scheme_end];
    if (scheme.len == 0) return null;
    const rest = url[scheme_end + 3 ..];
    if (rest.len == 0) return null;

    if (rest[0] == '[') {
        const close_rel = std.mem.indexOfScalar(u8, rest, ']') orelse return null;
        if (close_rel <= 1) return null;
        const suffix = rest[close_rel + 1 ..];
        if (!validUrlHostSuffix(suffix)) return null;
        return .{ .scheme = scheme, .host = rest[1..close_rel] };
    }

    var host_end: usize = 0;
    while (host_end < rest.len and rest[host_end] != ':' and rest[host_end] != '/' and rest[host_end] != '?' and rest[host_end] != '#') : (host_end += 1) {}
    const host = rest[0..host_end];
    if (host.len == 0 or std.mem.indexOfScalar(u8, host, '@') != null) return null;
    return .{ .scheme = scheme, .host = host };
}
fn validUrlHostSuffix(suffix: []const u8) bool {
    return suffix.len == 0 or suffix[0] == ':' or suffix[0] == '/' or suffix[0] == '?' or suffix[0] == '#';
}
fn isWildcardPermissionHost(host: []const u8) bool {
    return std.mem.indexOfScalar(u8, host, '*') != null;
}
fn isLoopbackPermissionHost(host: []const u8) bool {
    return std.ascii.eqlIgnoreCase(host, "localhost") or
        std.mem.eql(u8, host, "127.0.0.1") or
        std.mem.eql(u8, host, "::1");
}
fn isIpLiteralHost(host: []const u8) bool {
    _ = std.Io.net.IpAddress.parseIp4(host, 0) catch {
        _ = std.Io.net.IpAddress.parseIp6(host, 0) catch return false;
        return true;
    };
    return true;
}
pub fn warnBroadNetPermissions(stdout: anytype, manifest: SapManifest) !void {
    for (manifest.net_permissions) |permission| {
        const parts = parsePermissionUrlParts(permission.url) orelse continue;
        if (isWildcardPermissionHost(parts.host)) {
            try stdout.print("warning: plugin {s} declares broad network permission: {s}\n", .{ manifest.name, permission.url });
        }
    }
}
