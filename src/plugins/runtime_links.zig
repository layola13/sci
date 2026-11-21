const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

const CommandClaim = @import("plugin_types.zig").CommandClaim;
const Context = @import("broker.zig").Context;
const HostStream = @import("plugin_types.zig").HostStream;
const LanguageFrontend = @import("plugin_types.zig").LanguageFrontend;
const LoadDiagnostic = @import("plugin_types.zig").LoadDiagnostic;
const LoadedPlugin = @import("plugin_types.zig").LoadedPlugin;
const ManifestHelpEntry = @import("plugin_types.zig").ManifestHelpEntry;
const RuntimeAuthorizationInput = @import("broker.zig").RuntimeAuthorizationInput;
const RuntimeBroker = @import("plugin_types.zig").RuntimeBroker;
const RuntimeHostAuthorization = @import("plugin_types.zig").RuntimeHostAuthorization;
const SapManifest = @import("install.zig").SapManifest;
const StreamCtx = @import("util.zig").StreamCtx;
const abiStatusFromInt = @import("util.zig").abiStatusFromInt;
const appendLinkInput = @import("install.zig").appendLinkInput;
const appendLinkInputFmt = @import("install.zig").appendLinkInputFmt;
const broker_abi_version = @import("broker.zig").broker_abi_version;
const dirExistsAbsolute = @import("util.zig").dirExistsAbsolute;
const dupeZArgs = @import("util.zig").dupeZArgs;
const fileExistsAbsolute = @import("util.zig").fileExistsAbsolute;
const freeZArgs = @import("util.zig").freeZArgs;
const installFromPath = @import("install.zig").installFromPath;
const invalidDynamicLibraryHeader = @import("install.zig").invalidDynamicLibraryHeader;
const isDynamicLibraryPath = @import("broker.zig").isDynamicLibraryPath;
const jsonString = @import("manifest.zig").jsonString;
const loadDescriptor = @import("util.zig").loadDescriptor;
const loadRuntimePermissionPolicy = @import("permission.zig").loadRuntimePermissionPolicy;
const lockHasKeyValue = @import("remote.zig").lockHasKeyValue;
const lockHasLine = @import("remote.zig").lockHasLine;
const parseSapManifest = @import("fetch.zig").parseSapManifest;
const pluginDevMode = @import("util.zig").pluginDevMode;
const pluginHelpTokenPresent = @import("manifest.zig").pluginHelpTokenPresent;
const pluginsHome = @import("fetch.zig").pluginsHome;
const readFileAbsoluteAlloc = @import("util.zig").readFileAbsoluteAlloc;
const resolvePluginRootPath = @import("install.zig").resolvePluginRootPath;
const runtimeBrokerCall = @import("broker_runtime.zig").runtimeBrokerCall;
const sha256File = @import("util.zig").sha256File;
const streamWriteAll = @import("util.zig").streamWriteAll;
const targetDynamicLibrarySuffix = @import("broker.zig").targetDynamicLibrarySuffix;
const validateDescriptor = @import("util.zig").validateDescriptor;
const workspaceSourceStamp = @import("broker_runtime.zig").workspaceSourceStamp;
const writeManifestHelpFallback = @import("manifest.zig").writeManifestHelpFallback;
const writeManifestHelpValue = @import("manifest.zig").writeManifestHelpValue;
const writePluginHelpFallback = @import("manifest.zig").writePluginHelpFallback;

const Runtime = @import("runtime.zig").Runtime;

pub fn appendSkillsImpl(self: *const Runtime, list: anytype) !void {
    for (self.plugins.items) |loaded| {
        if (!try self.shouldAdvertiseSkills(loaded)) continue;
        const skills = loaded.descriptor.skills_ptr[0..loaded.descriptor.skills_len];
        for (skills) |section| {
            try list.append(.{
                .name = section.name,
                .summary = section.summary,
                .items = section.items,
            });
        }
    }
}

pub fn shouldAdvertiseSkillsImpl(self: *const Runtime, loaded: LoadedPlugin) !bool {
    const plugin_dir = std.fs.path.dirname(loaded.path) orelse return true;
    const sap_path = try std.fs.path.join(self.allocator, &.{ plugin_dir, "sap.json" });
    defer self.allocator.free(sap_path);
    if (!fileExistsAbsolute(sap_path)) return true;

    var manifest = parseSapManifest(self.allocator, sap_path) catch return true;
    defer manifest.deinit(self.allocator);
    for (manifest.dependencies) |dep| {
        const dependency = self.loadedPluginByName(dep.name) orelse {
            if (dep.optional) return false;
            return false;
        };
        if (dep.symbols.len != 0 and !(try dependency.exportsAll(self.allocator, dep.symbols))) {
            if (dep.optional) return false;
            return false;
        }
    }
    return true;
}

pub fn loadedPluginByNameImpl(self: *const Runtime, name: []const u8) ?*LoadedPlugin {
    const mutable_items: []LoadedPlugin = @constCast(self.plugins.items);
    for (mutable_items) |*loaded| {
        if (std.mem.eql(u8, std.mem.span(loaded.descriptor.name), name)) return loaded;
    }
    return null;
}

pub fn appendLibrariesExportingAnyImpl(
    self: *Runtime,
    list: *std.array_list.Managed([]const u8),
    symbol_names: []const []const u8,
) !void {
    if (symbol_names.len == 0) return;
    for (self.plugins.items) |*loaded| {
        if (try loaded.exportsAny(self.allocator, symbol_names)) {
            try list.append(loaded.path);
        }
    }
}

pub fn appendNativeLinkInputsForExternsImpl(
    self: *Runtime,
    link_inputs: *std.array_list.Managed([]const u8),
    owned_link_inputs: *std.array_list.Managed([]const u8),
    symbol_names: []const []const u8,
) !?[]u8 {
    if (symbol_names.len == 0) return null;
    for (self.plugins.items) |*loaded| {
        if (!try loaded.exportsAny(self.allocator, symbol_names)) continue;
        try appendLinkInput(self.allocator, link_inputs, owned_link_inputs, loaded.path);
        if (std.fs.path.dirname(loaded.path)) |dir| {
            try appendLinkInputFmt(self.allocator, link_inputs, owned_link_inputs, "-Wl,-rpath,{s}", .{dir});
        }
        if (try self.appendDeclaredNativeLinks(link_inputs, owned_link_inputs, loaded)) |denial| return denial;
    }
    return null;
}

pub fn appendDeclaredNativeLinksImpl(
    self: *Runtime,
    link_inputs: *std.array_list.Managed([]const u8),
    owned_link_inputs: *std.array_list.Managed([]const u8),
    loaded: *LoadedPlugin,
) !?[]u8 {
    const allocator = self.allocator;
    const plugin_dir = std.fs.path.dirname(loaded.path) orelse return null;
    const sap_path = try std.fs.path.join(allocator, &.{ plugin_dir, "sap.json" });
    defer allocator.free(sap_path);
    if (!fileExistsAbsolute(sap_path)) return null;
    var manifest = parseSapManifest(allocator, sap_path) catch |err| {
        return try std.fmt.allocPrint(allocator, "plugin manifest at {s} could not be parsed while collecting native link inputs: {s} [SA-PLUGIN-NATIVE-LINK-MANIFEST-UNREADABLE]\n  remedy: reinstall the plugin from its source directory so its manifest and confirmation are regenerated; never hand-edit the installed sap.json", .{ sap_path, @errorName(err) });
    };
    defer manifest.deinit(allocator);
    if (manifest.native_link.len == 0) return null;

    if (!try self.nativeLinkDeclarationInEffect(plugin_dir, manifest)) {
        var summary = std.array_list.Managed(u8).init(allocator);
        defer summary.deinit();
        for (manifest.native_link, 0..) |entry, idx| {
            if (idx != 0) try summary.appendSlice(", ");
            try summary.appendSlice(entry.name);
        }
        return try std.fmt.allocPrint(allocator, "plugin {s} declares native_link libraries ({s}) that are not covered by its install confirmation [SA-PLUGIN-NATIVE-LINK-UNCONFIRMED]\n  dev remedy (trusted development only): run the build with SA_PLUGIN_DEV=1, or install the plugin in dev mode (SA_PLUGIN_DEV=1 sa plugin install --dev <plugin-source-dir>)\n  formal remedy: run `sa plugin confirm {s}` to review and confirm the declared native libraries (writes permissions.lock; --yes is the explicit non-interactive form), then rebuild; never hand-write permissions.lock", .{ manifest.name, summary.items, manifest.name });
    }

    for (manifest.native_link) |entry| {
        switch (entry.kind) {
            .lib => {
                var resolved_dirs = std.array_list.Managed([]u8).init(allocator);
                defer {
                    for (resolved_dirs.items) |dir| allocator.free(dir);
                    resolved_dirs.deinit();
                }
                var found = entry.dirs.len == 0;
                for (entry.dirs) |dir| {
                    const resolved_dir = try resolvePluginRootPath(allocator, manifest.root_dir, dir);
                    errdefer allocator.free(resolved_dir);
                    try resolved_dirs.append(resolved_dir);
                    if (!found) {
                        const candidate = try std.fmt.allocPrint(allocator, "{s}/lib{s}.so", .{ resolved_dir, entry.name });
                        defer allocator.free(candidate);
                        if (fileExistsAbsolute(candidate)) found = true;
                    }
                }
                if (!found) {
                    var dirs_csv = std.array_list.Managed(u8).init(allocator);
                    defer dirs_csv.deinit();
                    for (entry.dirs, 0..) |dir, idx| {
                        if (idx != 0) try dirs_csv.appendSlice(", ");
                        try dirs_csv.appendSlice(dir);
                    }
                    return try std.fmt.allocPrint(allocator, "plugin {s} declares native_link lib '{s}' but lib{s}.so was not found in any declared search directory ({s}) [SA-PLUGIN-NATIVE-LINK-LIBRARY-MISSING]\n  remedy: provide the library at one of the declared directories, or fix the declaration in the plugin's sap.json (permissions.native_link) and reinstall + re-confirm the plugin", .{ manifest.name, entry.name, entry.name, dirs_csv.items });
                }
                for (resolved_dirs.items) |resolved_dir| {
                    try appendLinkInputFmt(allocator, link_inputs, owned_link_inputs, "-L{s}", .{resolved_dir});
                    try appendLinkInputFmt(allocator, link_inputs, owned_link_inputs, "-Wl,-rpath,{s}", .{resolved_dir});
                }
                try appendLinkInputFmt(allocator, link_inputs, owned_link_inputs, "-l{s}", .{entry.name});
            },
            .path => {
                const resolved = try resolvePluginRootPath(allocator, manifest.root_dir, entry.name);
                defer allocator.free(resolved);
                if (!fileExistsAbsolute(resolved)) {
                    return try std.fmt.allocPrint(allocator, "plugin {s} declares native_link path '{s}' (resolved to {s}) but the file does not exist [SA-PLUGIN-NATIVE-LINK-LIBRARY-MISSING]\n  remedy: provide the library at the declared path, or fix the declaration in the plugin's sap.json (permissions.native_link) and reinstall + re-confirm the plugin", .{ manifest.name, entry.name, resolved });
                }
                try appendLinkInput(allocator, link_inputs, owned_link_inputs, resolved);
                if (std.fs.path.dirname(resolved)) |dir| {
                    try appendLinkInputFmt(allocator, link_inputs, owned_link_inputs, "-Wl,-rpath,{s}", .{dir});
                }
            },
        }
    }
    return null;
}

pub fn nativeLinkDeclarationInEffectImpl(
    self: *Runtime,
    plugin_dir: []const u8,
    manifest: SapManifest,
) !bool {
    if (pluginDevMode(self.allocator)) return true;
    for (self.workspace_plugin_dirs.items) |staged| {
        if (std.mem.eql(u8, staged, plugin_dir)) return true;
    }
    const lock_path = try std.fs.path.join(self.allocator, &.{ plugin_dir, "permissions.lock" });
    defer self.allocator.free(lock_path);
    const lock_text = readFileAbsoluteAlloc(self.allocator, lock_path, 1 << 20) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer self.allocator.free(lock_text);
    if (!lockHasLine(lock_text, "confirmed=true")) return false;
    if (lockHasKeyValue(lock_text, "dev_install", "true")) return false;
    const digest_hex = std.fmt.bytesToHex(manifest.permission_digest, .lower);
    return lockHasKeyValue(lock_text, "permissions_sha256", digest_hex[0..]);
}
