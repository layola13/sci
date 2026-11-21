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

pub fn loadWorkspacePluginsImpl(self: *Runtime) void {
    const allocator = self.allocator;
    const declared_root = self.host_authorization.project_root orelse return;
    const root_abs = sio.cwd().realpathAlloc(allocator, declared_root) catch null;
    defer if (root_abs) |root| allocator.free(root);
    const project_root = root_abs orelse declared_root;
    const mod_path = std.fs.path.join(allocator, &.{ project_root, "sa.mod" }) catch return;
    defer allocator.free(mod_path);
    const source = sio.cwd().readFileAlloc(allocator, mod_path, pkg_manifest.max_manifest_bytes) catch return;
    defer allocator.free(source);
    var project = pkg_manifest.parseManifestWithFile(allocator, source, "sa.mod") catch |err| {
        self.addDiagnostic(mod_path, @errorName(err)) catch {};
        return;
    };
    defer project.deinit(allocator);
    for (project.plugin_requires) |entry| {
        self.stageWorkspacePlugin(project_root, entry.identity) catch |err| {
            self.addDiagnostic(entry.identity, @errorName(err)) catch {};
        };
    }
}

pub fn stageWorkspacePluginImpl(
    self: *Runtime,
    project_root: []const u8,
    identity: []const u8,
) !void {
    const allocator = self.allocator;
    const candidate = if (std.fs.path.isAbsolute(identity))
        try allocator.dupe(u8, identity)
    else
        try std.fs.path.join(allocator, &.{ project_root, identity });
    defer allocator.free(candidate);
    const sap_path = try std.fs.path.join(allocator, &.{ candidate, "sap.json" });
    defer allocator.free(sap_path);
    if (!fileExistsAbsolute(sap_path)) return; // name-based require: existing semantics
    var source_manifest = parseSapManifest(allocator, sap_path) catch |err| {
        try self.addDiagnostic(candidate, @errorName(err));
        return;
    };
    defer source_manifest.deinit(allocator);
    const name = source_manifest.name;

    const staging_root = try std.fs.path.join(allocator, &.{ project_root, ".sa-cache", "workspace-plugins" });
    defer allocator.free(staging_root);
    const staged_current = try std.fs.path.join(allocator, &.{ staging_root, "installed", name, "current" });
    defer allocator.free(staged_current);
    const stamp_name = try std.fmt.allocPrint(allocator, "{s}.stamp", .{name});
    defer allocator.free(stamp_name);
    const stamp_path = try std.fs.path.join(allocator, &.{ staging_root, stamp_name });
    defer allocator.free(stamp_path);

    const stamp = workspaceSourceStamp(allocator, candidate) catch 0;
    const stamp_text = try std.fmt.allocPrint(allocator, "{x:0>16}", .{stamp});
    defer allocator.free(stamp_text);
    var fresh = false;
    if (stamp != 0 and dirExistsAbsolute(staged_current)) {
        if (sio.cwd().readFileAlloc(allocator, stamp_path, 64)) |old| {
            defer allocator.free(old);
            fresh = std.mem.eql(u8, old, stamp_text);
        } else |_| {}
    }
    if (!fresh) {
        var captured = std.array_list.Managed(u8).init(allocator);
        defer captured.deinit();
        const code = installFromPath(allocator, candidate, sio.managedWriter(&captured), .{ .home_path = staging_root, .workspace_declared = true }) catch |err| {
            try self.addDiagnostic(candidate, @errorName(err));
            return;
        };
        if (code != 0) {
            const items = captured.items;
            const tail = items[if (items.len > 512) items.len - 512 else 0..];
            const message = try std.fmt.allocPrint(allocator, "workspace plugin staging failed: {s}", .{tail});
            defer allocator.free(message);
            try self.addDiagnostic(candidate, message);
            return;
        }
        std.debug.print("[sa] workspace plugin {s} staged from {s} (source changed or first use)\n", .{ name, candidate });
        sio.cwd().makePath(staging_root) catch {};
        sio.cwd().writeFile(.{ .sub_path = stamp_path, .data = stamp_text }) catch {};
    }

    try self.workspace_plugin_dirs.append(try allocator.dupe(u8, staged_current));
    try self.loadDirectory(staged_current);
}

pub fn loadFromEnvImpl(self: *Runtime) !void {
    if (sio.getEnvVarOwned(self.allocator, "SA_PLUGINS_PATH")) |path_list| {
        defer self.allocator.free(path_list);
        try self.loadPathList(path_list);
        return;
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }

    const home = try pluginsHome(self.allocator);
    defer self.allocator.free(home);

    const installed = try std.fs.path.join(self.allocator, &.{ home, "installed" });
    defer self.allocator.free(installed);
    try self.loadInstalledRoot(installed);
}

pub fn loadPathListImpl(self: *Runtime, path_list: []const u8) !void {
    const separator: u8 = if (@import("builtin").os.tag == .windows) ';' else ':';
    var it = std.mem.splitScalar(u8, path_list, separator);
    while (it.next()) |raw_entry| {
        const entry = std.mem.trim(u8, raw_entry, " \t\r\n");
        if (entry.len == 0) continue;
        try self.loadPath(entry);
    }
}

pub fn loadPathImpl(self: *Runtime, path: []const u8) !void {
    var resolved_path: ?[]u8 = null;
    const load_path = if (std.fs.path.isAbsolute(path)) path else blk: {
        const absolute = sio.cwd().realpathAlloc(self.allocator, path) catch |err| {
            try self.addDiagnostic(path, @errorName(err));
            return;
        };
        resolved_path = absolute;
        break :blk absolute;
    };
    defer if (resolved_path) |absolute| self.allocator.free(absolute);

    if (isDynamicLibraryPath(load_path)) {
        try self.noteManifestHelpForLibrary(load_path);
        if (try self.runtimePolicyDenialForLibrary(load_path)) |reason| {
            defer self.allocator.free(reason);
            try self.addDiagnostic(load_path, reason);
            return;
        }
        try self.loadLibrary(load_path);
        return;
    }
    try self.loadDirectory(load_path);
}

pub fn loadInstalledRootImpl(self: *Runtime, root_path: []const u8) !void {
    var root = sio.openDirAbsolute(root_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return,
        else => return err,
    };
    defer root.close();

    var it = root.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        const current = try std.fs.path.join(self.allocator, &.{ root_path, entry.name, "current" });
        defer self.allocator.free(current);
        try self.loadDirectory(current);
    }
}

pub fn loadDirectoryImpl(self: *Runtime, dir_path: []const u8) !void {
    try self.noteManifestHelpForDirectory(dir_path);

    if (try self.runtimePolicyDenialForDirectory(dir_path)) |reason| {
        defer self.allocator.free(reason);
        try self.addDiagnostic(dir_path, reason);
        return;
    }

    var dir = sio.openDirAbsolute(dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => {
            try self.addDiagnostic(dir_path, @errorName(err));
            return;
        },
        else => return err,
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (!std.mem.endsWith(u8, entry.name, targetDynamicLibrarySuffix())) continue;
        const lib_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
        defer self.allocator.free(lib_path);
        try self.loadLibrary(lib_path);
    }
}

pub fn loadLibraryImpl(self: *Runtime, path: []const u8) !void {
    if (try invalidDynamicLibraryHeader(self.allocator, path)) |reason| {
        try self.addDiagnostic(path, reason);
        return;
    }

    if (try self.runtimeArtifactHashMismatch(path)) |reason| {
        defer self.allocator.free(reason);
        try self.addDiagnostic(path, reason);
        return;
    }

    var lib = blk: {
        if (@import("builtin").os.tag == .windows) {
            // Plugin DLLs live outside the executable directory, so their
            // own dependencies (LLVM-C.dll, sibling plugin DLLs) must be
            // resolved relative to the DLL's install directory.
            const path_raw = std.fmt.allocPrint(self.allocator, "{s}", .{path}) catch |err| {
                try self.addDiagnostic(path, @errorName(err));
                return;
            };
            defer self.allocator.free(path_raw);
            const path_z = std.unicode.utf8ToUtf16LeAllocZ(self.allocator, path_raw) catch |err| {
                try self.addDiagnostic(path, @errorName(err));
                return;
            };
            defer self.allocator.free(path_z);
            break :blk dynlib.DynLib.openWide(path_z) catch |err| {
                try self.addDiagnostic(path, @errorName(err));
                return;
            };
        }
        break :blk dynlib.DynLib.open(path) catch |err| {
            try self.addDiagnostic(path, @errorName(err));
            return;
        };
    };
    var keep_lib = false;
    defer if (!keep_lib) lib.close();

    const descriptor = loadDescriptor(&lib) orelse {
        try self.addDiagnostic(path, "missing descriptor");
        return;
    };

    if (validateDescriptor(descriptor)) |reason| {
        try self.addDiagnostic(path, reason);
        return;
    }

    {
        const new_name = std.mem.span(descriptor.name);
        for (self.plugins.items) |*existing| {
            if (std.mem.eql(u8, std.mem.span(existing.descriptor.name), new_name)) {
                try self.addDiagnostic(path, "plugin shadowed by an earlier-loaded plugin of the same name (a workspace declaration takes precedence)");
                return;
            }
        }
    }

    var permission_policy = try loadRuntimePermissionPolicy(self.allocator, path);
    errdefer permission_policy.deinit(self.allocator);

    if (descriptor.init) |init_fn| {
        var broker = RuntimeBroker{
            .allocator = self.allocator,
            .policy = &permission_policy,
            .authorization = &self.host_authorization,
        };
        var ctx = Context{
            .allocator = self.allocator,
            .broker_abi_version = broker_abi_version,
            .broker_call = runtimeBrokerCall,
            .broker_ctx = &broker,
        };
        const status = abiStatusFromInt(init_fn(&ctx));
        if (status != .ok) {
            try self.addDiagnostic(path, @tagName(status));
            return;
        }
    }

    const owned_path = try self.allocator.dupe(u8, path);
    errdefer self.allocator.free(owned_path);
    try self.plugins.append(.{
        .path = owned_path,
        .lib = lib,
        .descriptor = descriptor,
        .permission_policy = permission_policy,
    });
    keep_lib = true;
    try self.noteLanguageFrontend(owned_path);
    try self.noteCommandClaims(owned_path);
}
