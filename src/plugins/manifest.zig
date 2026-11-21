const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

const AssetFile = @import("install.zig").AssetFile;
const AssetKind = @import("install.zig").AssetKind;
const InterfaceFile = @import("install.zig").InterfaceFile;
const InterfaceKind = @import("install.zig").InterfaceKind;
const LoadedPlugin = @import("plugin_types.zig").LoadedPlugin;
const SapManifest = @import("install.zig").SapManifest;
const abi_version = @import("broker.zig").abi_version;
const copyFileAbsolute = @import("util.zig").copyFileAbsolute;
const fileExistsAbsolute = @import("util.zig").fileExistsAbsolute;
const pluginsHome = @import("fetch.zig").pluginsHome;
const readFileAbsoluteAlloc = @import("util.zig").readFileAbsoluteAlloc;
const sha256File = @import("util.zig").sha256File;
const targetArtifactKey = @import("broker.zig").targetArtifactKey;

pub fn absolutePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return try allocator.dupe(u8, path);
    return try sio.cwd().realpathAlloc(allocator, path);
}
pub fn jsonString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |s| s,
        else => error.InvalidSapManifest,
    };
}
pub fn pluginHelpTokenPresent(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or
            std.mem.eql(u8, arg, "-h") or
            std.mem.eql(u8, arg, "help")) return true;
    }
    return false;
}
pub fn writeManifestHelpValue(writer: anytype, value: std.json.Value) !bool {
    switch (value) {
        .string => |text| {
            try writer.writeAll(text);
            if (text.len == 0 or text[text.len - 1] != '\n') try writer.writeByte('\n');
            return true;
        },
        .object => |object| {
            if (object.get("text")) |text_value| {
                const text = jsonString(text_value) catch return false;
                try writer.writeAll(text);
                if (text.len == 0 or text[text.len - 1] != '\n') try writer.writeByte('\n');
                return true;
            }

            var wrote_any = false;
            if (object.get("usage")) |usage_value| {
                const usage = jsonString(usage_value) catch return false;
                try writer.print("usage: {s}\n", .{usage});
                wrote_any = true;
            }
            if (object.get("summary")) |summary_value| {
                const summary = jsonString(summary_value) catch return false;
                if (wrote_any) try writer.writeByte('\n');
                try writer.print("{s}\n", .{summary});
                wrote_any = true;
            }
            if (object.get("commands")) |commands_value| {
                const commands = switch (commands_value) {
                    .array => |arr| arr,
                    else => return false,
                };
                if (wrote_any) try writer.writeByte('\n');
                try writer.writeAll("Commands:\n");
                for (commands.items) |item| {
                    const command = switch (item) {
                        .object => |command_object| command_object,
                        else => return false,
                    };
                    const label = if (command.get("usage")) |usage_value|
                        jsonString(usage_value) catch return false
                    else if (command.get("name")) |name_value|
                        jsonString(name_value) catch return false
                    else
                        return false;
                    if (command.get("description")) |description_value| {
                        const description = jsonString(description_value) catch return false;
                        try writer.print("  {s}\n      {s}\n", .{ label, description });
                    } else {
                        try writer.print("  {s}\n", .{label});
                    }
                }
                wrote_any = true;
            }
            if (object.get("options")) |options_value| {
                const options = switch (options_value) {
                    .array => |arr| arr,
                    else => return false,
                };
                if (wrote_any) try writer.writeByte('\n');
                try writer.writeAll("Options:\n");
                for (options.items) |item| {
                    const option = switch (item) {
                        .object => |option_object| option_object,
                        else => return false,
                    };
                    const flags = jsonString(option.get("flags") orelse return false) catch return false;
                    if (option.get("description")) |description_value| {
                        const description = jsonString(description_value) catch return false;
                        try writer.print("  {s}\n      {s}\n", .{ flags, description });
                    } else {
                        try writer.print("  {s}\n", .{flags});
                    }
                }
                wrote_any = true;
            }
            return wrote_any;
        },
        else => return false,
    }
}
pub fn writePluginHelpFallback(loaded: *const LoadedPlugin, writer: anytype, manifest_name: ?[]const u8, manifest_version: ?[]const u8) !void {
    const plugin_name = manifest_name orelse std.mem.span(loaded.descriptor.name);
    try writeManifestHelpFallback(writer, plugin_name, manifest_version);

    const skills = loaded.descriptor.skills_ptr[0..loaded.descriptor.skills_len];
    if (skills.len == 0) return;
    try writer.writeAll("\nSkills:\n");
    for (skills) |section| {
        try writer.print("  {s}", .{section.name});
        const summary = section.summary;
        if (summary.len != 0) try writer.print(" - {s}", .{summary});
        try writer.writeByte('\n');
    }
}
pub fn writeManifestHelpFallback(writer: anytype, plugin_name: []const u8, manifest_version: ?[]const u8) !void {
    try writer.print("usage: sa {s} [--help]\n\n", .{plugin_name});
    if (manifest_version) |version| {
        try writer.print("{s} {s}\n", .{ plugin_name, version });
    } else {
        try writer.print("{s}\n", .{plugin_name});
    }
}
pub fn parseAbiPlugin(maybe_value: ?std.json.Value) !u32 {
    const value = maybe_value orelse return abi_version;
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidSapManifest,
    };
    const plugin_value = obj.get("plugin") orelse return abi_version;
    return switch (plugin_value) {
        .integer => |n| if (n >= 0 and n <= std.math.maxInt(u32)) @as(u32, @intCast(n)) else error.InvalidSapManifest,
        else => error.InvalidSapManifest,
    };
}
const SelectedArtifact = struct {
    path: []const u8,
    sha256: ?[32]u8,
};
pub fn selectArtifact(value: std.json.Value) !SelectedArtifact {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidSapManifest,
    };
    if (obj.get(targetArtifactKey())) |target_value| {
        return try artifactFromValue(target_value);
    }
    if (obj.get("linux-x86_64")) |target_value| {
        return try artifactFromValue(target_value);
    }
    var it = obj.iterator();
    if (it.next()) |entry| return try artifactFromValue(entry.value_ptr.*);
    return error.InvalidSapManifest;
}
fn artifactFromValue(value: std.json.Value) !SelectedArtifact {
    return switch (value) {
        .string => |s| .{ .path = s, .sha256 = null },
        .object => |o| blk: {
            try rejectUnknownSapKeys(o, &.{ "path", "sha256" });
            const path = try jsonString(o.get("path") orelse return error.InvalidSapManifest);
            const hash = if (o.get("sha256")) |hash_value| try parseSha256Json(hash_value) else null;
            break :blk .{ .path = path, .sha256 = hash };
        },
        else => error.InvalidSapManifest,
    };
}
pub fn collectInterfaceFiles(allocator: std.mem.Allocator, maybe_value: ?std.json.Value) ![]InterfaceFile {
    var files = std.array_list.Managed(InterfaceFile).init(allocator);
    errdefer {
        for (files.items) |*file| file.deinit(allocator);
        files.deinit();
    }
    const value = maybe_value orelse return try files.toOwnedSlice();
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidSapManifest,
    };
    if (obj.get("sa")) |sa_value| switch (sa_value) {
        .array => |arr| for (arr.items) |item| try files.append(try interfaceFileFromValue(allocator, .sa, item)),
        else => return error.InvalidSapManifest,
    };
    if (obj.get("sai")) |sai_value| try files.append(try interfaceFileFromValue(allocator, .sai, sai_value));
    if (obj.get("sal")) |sal_value| try files.append(try interfaceFileFromValue(allocator, .sal, sal_value));
    if (obj.get("wasm_imports")) |wasm_imports_value| switch (wasm_imports_value) {
        .array => |arr| for (arr.items) |item| try files.append(try interfaceFileFromValue(allocator, .wasm_import, item)),
        else => try files.append(try interfaceFileFromValue(allocator, .wasm_import, wasm_imports_value)),
    };
    return try files.toOwnedSlice();
}
fn interfaceFileFromValue(allocator: std.mem.Allocator, kind: InterfaceKind, value: std.json.Value) !InterfaceFile {
    switch (value) {
        .string => |s| return .{ .kind = kind, .path = try allocator.dupe(u8, s), .sha256 = null },
        .object => |o| {
            try rejectUnknownSapKeys(o, &.{ "path", "sha256" });
            const path = try allocator.dupe(u8, try jsonString(o.get("path") orelse return error.InvalidSapManifest));
            errdefer allocator.free(path);
            const hash = if (o.get("sha256")) |hash_value| try parseSha256Json(hash_value) else null;
            return .{ .kind = kind, .path = path, .sha256 = hash };
        },
        else => return error.InvalidSapManifest,
    }
}
pub fn collectAssetFiles(allocator: std.mem.Allocator, maybe_value: ?std.json.Value) ![]AssetFile {
    var files = std.array_list.Managed(AssetFile).init(allocator);
    errdefer {
        for (files.items) |*file| file.deinit(allocator);
        files.deinit();
    }
    const value = maybe_value orelse return try files.toOwnedSlice();
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidSapManifest,
    };
    if (obj.get("share")) |share_value| switch (share_value) {
        .array => |arr| for (arr.items) |item| try files.append(try assetFileFromValue(allocator, .share, item)),
        else => return error.InvalidSapManifest,
    };
    return try files.toOwnedSlice();
}
fn assetFileFromValue(allocator: std.mem.Allocator, kind: AssetKind, value: std.json.Value) !AssetFile {
    switch (value) {
        .string => |s| {
            try validateProjectRelativePath(s);
            const target = std.fs.path.basename(s);
            try validateProjectRelativePath(target);
            return .{
                .kind = kind,
                .path = try allocator.dupe(u8, s),
                .target = try allocator.dupe(u8, target),
                .sha256 = null,
            };
        },
        .object => |o| {
            try rejectUnknownSapKeys(o, &.{ "path", "target", "sha256" });
            const path_text = try jsonString(o.get("path") orelse return error.InvalidSapManifest);
            try validateProjectRelativePath(path_text);
            const target_text = if (o.get("target")) |target_value| try jsonString(target_value) else std.fs.path.basename(path_text);
            try validateProjectRelativePath(target_text);
            const path = try allocator.dupe(u8, path_text);
            errdefer allocator.free(path);
            const target = try allocator.dupe(u8, target_text);
            errdefer allocator.free(target);
            const hash = if (o.get("sha256")) |hash_value| try parseSha256Json(hash_value) else null;
            return .{ .kind = kind, .path = path, .target = target, .sha256 = hash };
        },
        else => return error.InvalidSapManifest,
    }
}
fn rejectUnknownSapKeys(obj: std.json.ObjectMap, allowed: []const []const u8) !void {
    var it = obj.iterator();
    while (it.next()) |entry| {
        var ok = false;
        for (allowed) |key| {
            if (std.mem.eql(u8, entry.key_ptr.*, key)) {
                ok = true;
                break;
            }
        }
        if (!ok) return error.InvalidSapManifest;
    }
}
fn parseSha256Json(value: std.json.Value) ![32]u8 {
    const text = try jsonString(value);
    const body = if (std.mem.startsWith(u8, text, "sha256:")) text["sha256:".len..] else text;
    if (body.len != 64) return error.InvalidSapManifest;
    var bytes: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(bytes[0..], body) catch return error.InvalidSapManifest;
    return bytes;
}
pub fn validateProjectRelativePath(path: []const u8) !void {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) return error.InvalidSapManifest;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidSapManifest;
    }
}
pub fn verifyInterfaceFiles(allocator: std.mem.Allocator, manifest: SapManifest) !u8 {
    for (manifest.interface_files) |iface| {
        try validateProjectRelativePath(iface.path);
        const path = try std.fs.path.join(allocator, &.{ manifest.root_dir, iface.path });
        defer allocator.free(path);
        if (!fileExistsAbsolute(path)) return error.PluginInterfaceMissing;
        if (iface.sha256) |expected| {
            const actual = try sha256File(allocator, path);
            if (!std.mem.eql(u8, actual[0..], expected[0..])) return error.PluginInterfaceHashMismatch;
        }
    }
    return 0;
}
pub fn verifyAssetFiles(allocator: std.mem.Allocator, manifest: SapManifest) !u8 {
    for (manifest.asset_files) |asset| {
        try validateProjectRelativePath(asset.path);
        try validateProjectRelativePath(asset.target);
        const path = try std.fs.path.join(allocator, &.{ manifest.root_dir, asset.path });
        defer allocator.free(path);
        if (!fileExistsAbsolute(path)) return error.PluginInterfaceMissing;
        if (asset.sha256) |expected| {
            const actual = try sha256File(allocator, path);
            if (!std.mem.eql(u8, actual[0..], expected[0..])) return error.PluginInterfaceHashMismatch;
        }
    }
    return 0;
}
pub fn copyAssetFiles(allocator: std.mem.Allocator, manifest: SapManifest, installed_dir: []const u8, version_dir: []const u8) !void {
    for (manifest.asset_files) |asset| {
        const src = try std.fs.path.join(allocator, &.{ manifest.root_dir, asset.path });
        defer allocator.free(src);
        switch (asset.kind) {
            .share => {
                const dst = try std.fs.path.join(allocator, &.{ installed_dir, "share", asset.target });
                defer allocator.free(dst);
                try copyFileAbsolute(src, dst);
                const version_dst = try std.fs.path.join(allocator, &.{ version_dir, "share", asset.target });
                defer allocator.free(version_dst);
                try copyFileAbsolute(src, version_dst);
            },
        }
    }
}
pub fn verifySymbolSmoke(allocator: std.mem.Allocator, manifest: SapManifest, artifact_abs: []const u8, stdout: anytype) !u8 {
    var externs = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (externs.items) |name| allocator.free(name);
        externs.deinit();
    }
    for (manifest.interface_files) |iface| {
        if (iface.kind != .sai) continue;
        const path = try std.fs.path.join(allocator, &.{ manifest.root_dir, iface.path });
        defer allocator.free(path);
        try collectExternSymbolsFromSai(allocator, path, &externs);
    }
    if (externs.items.len == 0) return 0;

    var lib = dynlib.DynLib.open(artifact_abs) catch |err| {
        try stdout.print("plugin artifact could not be opened for symbol smoke: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer lib.close();
    for (externs.items) |symbol| {
        const symbol_z = try allocator.dupeSentinel(u8, symbol, 0);
        defer allocator.free(symbol_z);
        if (lib.lookup(*anyopaque, symbol_z) == null) {
            try stdout.print("plugin artifact missing @extern symbol from .sai: {s}\n", .{symbol});
            return 1;
        }
    }
    return 0;
}
fn collectExternSymbolsFromSai(allocator: std.mem.Allocator, path: []const u8, out: *std.array_list.Managed([]u8)) !void {
    const source = try readFileAbsoluteAlloc(allocator, path, 1 << 20);
    defer allocator.free(source);
    var it = std.mem.splitScalar(u8, source, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, "@extern ")) continue;
        const rest = std.mem.trim(u8, line["@extern ".len..], " \t");
        const paren = std.mem.indexOfScalar(u8, rest, '(') orelse continue;
        const symbol = std.mem.trim(u8, rest[0..paren], " \t");
        if (symbol.len == 0) continue;
        if (externSymbolExists(out.items, symbol)) return error.PluginDuplicateExternSymbol;
        try out.append(try allocator.dupe(u8, symbol));
    }
}
pub fn externSymbolExists(items: []const []u8, symbol: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, symbol)) return true;
    }
    return false;
}
const ExternProvider = struct {
    symbol: []u8,
    plugin: []u8,

    pub fn deinit(self: *ExternProvider, allocator: std.mem.Allocator) void {
        allocator.free(self.symbol);
        allocator.free(self.plugin);
        self.* = undefined;
    }
};
pub fn verifyInstalledExternSymbolConflicts(allocator: std.mem.Allocator, manifest: SapManifest, stdout: anytype) !u8 {
    var installed = std.array_list.Managed(ExternProvider).init(allocator);
    defer {
        for (installed.items) |*provider| provider.deinit(allocator);
        installed.deinit();
    }
    if (try collectInstalledExternProviders(allocator, manifest.name, stdout, &installed) != 0) return 1;

    var current = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (current.items) |symbol| allocator.free(symbol);
        current.deinit();
    }
    try collectManifestExternSymbols(allocator, manifest, &current);
    for (current.items) |symbol| {
        if (findExternProvider(installed.items, symbol)) |provider| {
            try stdout.print(
                "plugin extern symbol conflict: {s} already provided by installed plugin {s}\n",
                .{ symbol, provider.plugin },
            );
            return 1;
        }
    }
    try printExternNamespaceHint(allocator, manifest, current.items, stdout);
    return 0;
}
/// Advisory namespace check for a plugin's declared externs. Plugin
/// externs share one flat link space across all installed plugins, so
/// a plugin's own symbols should carry its namespace: the canonical
/// prefix is sa_plugin_<name>_ and the established sa_<name>_ family
/// counts as namespaced; sa_std_ symbols belong to the standard
/// library. Anything else is listed once per install so authors can
/// rename before a collision makes an install fail outright. The
/// hint never blocks the install.
fn printExternNamespaceHint(
    allocator: std.mem.Allocator,
    manifest: SapManifest,
    symbols: []const []u8,
    stdout: anytype,
) !void {
    const underscored = try allocator.dupe(u8, manifest.name);
    defer allocator.free(underscored);
    for (underscored) |*ch| {
        if (ch.* == '-') ch.* = '_';
    }
    const canonical = try std.fmt.allocPrint(allocator, "sa_plugin_{s}_", .{underscored});
    defer allocator.free(canonical);
    const legacy = try std.fmt.allocPrint(allocator, "sa_{s}_", .{underscored});
    defer allocator.free(legacy);
    var loose = std.array_list.Managed([]const u8).init(allocator);
    defer loose.deinit();
    for (symbols) |symbol| {
        if (std.mem.startsWith(u8, symbol, canonical)) continue;
        if (std.mem.startsWith(u8, symbol, legacy)) continue;
        if (std.mem.startsWith(u8, symbol, "sa_std_")) continue;
        try loose.append(symbol);
    }
    if (loose.items.len == 0) return;
    const joined = try std.mem.join(allocator, ", ", loose.items);
    defer allocator.free(joined);
    try stdout.print(
        "plugin extern namespace hint: {s} declares extern symbol(s) outside its namespace: {s}. Plugin externs share one flat link space; prefix new symbols with {s} so they cannot collide with other plugins.\n",
        .{ manifest.name, joined, canonical },
    );
}
fn collectInstalledExternProviders(
    allocator: std.mem.Allocator,
    installing_name: []const u8,
    stdout: anytype,
    out: *std.array_list.Managed(ExternProvider),
) !u8 {
    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const root_path = try std.fs.path.join(allocator, &.{ home, "installed" });
    defer allocator.free(root_path);
    var root = sio.openDirAbsolute(root_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return 0,
        else => return err,
    };
    defer root.close();

    var it = root.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        if (std.mem.eql(u8, entry.name, installing_name)) continue;
        const sa_dir = try std.fs.path.join(allocator, &.{ root_path, entry.name, "current", "sa" });
        defer allocator.free(sa_dir);
        var dir = sio.openDirAbsolute(sa_dir, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => continue,
            else => return err,
        };
        defer dir.close();

        var dir_it = dir.iterate();
        while (try dir_it.next()) |sa_entry| {
            if (sa_entry.kind != .file and sa_entry.kind != .sym_link) continue;
            if (!std.mem.endsWith(u8, sa_entry.name, ".sai")) continue;
            const sai_path = try std.fs.path.join(allocator, &.{ sa_dir, sa_entry.name });
            defer allocator.free(sai_path);
            var symbols = std.array_list.Managed([]u8).init(allocator);
            defer symbols.deinit();
            try collectExternSymbolsFromSai(allocator, sai_path, &symbols);
            for (symbols.items, 0..) |symbol, idx| {
                if (findExternProvider(out.items, symbol)) |existing| {
                    if (std.mem.eql(u8, existing.plugin, entry.name)) {
                        try stdout.print(
                            "installed plugin duplicate extern symbol: {s} is declared more than once by installed plugin {s}\n",
                            .{ symbol, entry.name },
                        );
                    } else {
                        try stdout.print(
                            "installed plugin extern symbol conflict: {s} is provided by both {s} and {s}\n",
                            .{ symbol, existing.plugin, entry.name },
                        );
                    }
                    for (symbols.items[idx..]) |owned| allocator.free(owned);
                    return 1;
                }
                try out.append(.{
                    .symbol = symbol,
                    .plugin = try allocator.dupe(u8, entry.name),
                });
            }
            symbols.items.len = 0;
        }
    }
    return 0;
}
fn collectManifestExternSymbols(allocator: std.mem.Allocator, manifest: SapManifest, out: *std.array_list.Managed([]u8)) !void {
    for (manifest.interface_files) |iface| {
        if (iface.kind != .sai) continue;
        const path = try std.fs.path.join(allocator, &.{ manifest.root_dir, iface.path });
        defer allocator.free(path);
        try collectExternSymbolsFromSai(allocator, path, out);
    }
}
fn findExternProvider(items: []const ExternProvider, symbol: []const u8) ?*const ExternProvider {
    for (items) |*item| {
        if (std.mem.eql(u8, item.symbol, symbol)) return item;
    }
    return null;
}
const ArtifactImportCapability = enum {
    fs,
    net,
    env,
    process,
    dynamic_loader,
};
const ArtifactImportRule = struct {
    symbol: []const u8,
    capability: ArtifactImportCapability,
};
pub const artifact_import_rules = [_]ArtifactImportRule{
    .{ .symbol = "connect", .capability = .net },
    .{ .symbol = "socket", .capability = .net },
    .{ .symbol = "WSAStartup", .capability = .net },
    .{ .symbol = "WSASocketA", .capability = .net },
    .{ .symbol = "WSASocketW", .capability = .net },
    .{ .symbol = "closesocket", .capability = .net },
    .{ .symbol = "getaddrinfo", .capability = .net },
    .{ .symbol = "send", .capability = .net },
    .{ .symbol = "sendto", .capability = .net },
    .{ .symbol = "recv", .capability = .net },
    .{ .symbol = "recvfrom", .capability = .net },
    .{ .symbol = "open", .capability = .fs },
    .{ .symbol = "openat", .capability = .fs },
    .{ .symbol = "fopen", .capability = .fs },
    .{ .symbol = "mkdir", .capability = .fs },
    .{ .symbol = "rename", .capability = .fs },
    .{ .symbol = "unlink", .capability = .fs },
    .{ .symbol = "readlink", .capability = .fs },
    .{ .symbol = "stat", .capability = .fs },
    .{ .symbol = "getenv", .capability = .env },
    .{ .symbol = "_getenv", .capability = .env },
    .{ .symbol = "setenv", .capability = .env },
    .{ .symbol = "unsetenv", .capability = .env },
    .{ .symbol = "putenv", .capability = .env },
    .{ .symbol = "_putenv", .capability = .env },
    .{ .symbol = "_putenv_s", .capability = .env },
    .{ .symbol = "execve", .capability = .process },
    .{ .symbol = "CreateProcessA", .capability = .process },
    .{ .symbol = "CreateProcessW", .capability = .process },
    .{ .symbol = "execvpe", .capability = .process },
    .{ .symbol = "posix_spawn", .capability = .process },
    .{ .symbol = "fork", .capability = .process },
    .{ .symbol = "vfork", .capability = .process },
    .{ .symbol = "popen", .capability = .process },
    .{ .symbol = "system", .capability = .process },
    .{ .symbol = "dlopen", .capability = .dynamic_loader },
    .{ .symbol = "dlmopen", .capability = .dynamic_loader },
    .{ .symbol = "__libc_dlopen_mode", .capability = .dynamic_loader },
    .{ .symbol = "LoadLibraryA", .capability = .dynamic_loader },
    .{ .symbol = "LoadLibraryW", .capability = .dynamic_loader },
    .{ .symbol = "LoadLibraryExA", .capability = .dynamic_loader },
    .{ .symbol = "LoadLibraryExW", .capability = .dynamic_loader },
};
