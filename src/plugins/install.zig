const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

const FsPermission = @import("plugin_types.zig").FsPermission;
const NetPermission = @import("plugin_types.zig").NetPermission;
const ProcessExecPermission = @import("plugin_types.zig").ProcessExecPermission;
const buildPluginProject = @import("util.zig").buildPluginProject;
const confirmPrivilegedPluginInstall = @import("util.zig").confirmPrivilegedPluginInstall;
const copyAssetFiles = @import("manifest.zig").copyAssetFiles;
const copyFileAbsolute = @import("util.zig").copyFileAbsolute;
const dependencyGraphDigest = @import("remote.zig").dependencyGraphDigest;
const dirExistsAbsolute = @import("util.zig").dirExistsAbsolute;
const fetchRemotePluginSource = @import("remote.zig").fetchRemotePluginSource;
const fileExistsAbsolute = @import("util.zig").fileExistsAbsolute;
const fileExistsInProject = @import("util.zig").fileExistsInProject;
const installPluginDependencies = @import("remote.zig").installPluginDependencies;
const isDynamicLibraryPath = @import("broker.zig").isDynamicLibraryPath;
const parseSapManifest = @import("fetch.zig").parseSapManifest;
const permissionsLockMatches = @import("remote.zig").permissionsLockMatches;
const pluginDevMode = @import("util.zig").pluginDevMode;
const pluginsHome = @import("fetch.zig").pluginsHome;
const renderPermissionsLock = @import("remote.zig").renderPermissionsLock;
const verifyArtifactStaticPolicy = @import("permissions.zig").verifyArtifactStaticPolicy;
const verifyAssetFiles = @import("manifest.zig").verifyAssetFiles;
const verifyInstalledExternSymbolConflicts = @import("manifest.zig").verifyInstalledExternSymbolConflicts;
const verifyInterfaceFiles = @import("manifest.zig").verifyInterfaceFiles;
const verifySymbolSmoke = @import("manifest.zig").verifySymbolSmoke;
const warnBroadNetPermissions = @import("permissions.zig").warnBroadNetPermissions;
const writeFileAbsolute = @import("util.zig").writeFileAbsolute;

/// Appends one link argument to both the borrowed link-input list
/// and the owning list (the pattern used for plugin library inputs).
pub fn appendLinkInput(
    allocator: std.mem.Allocator,
    link_inputs: *std.array_list.Managed([]const u8),
    owned_link_inputs: *std.array_list.Managed([]const u8),
    text: []const u8,
) !void {
    const owned = try allocator.dupe(u8, text);
    link_inputs.append(owned) catch |err| {
        allocator.free(owned);
        return err;
    };
    owned_link_inputs.append(owned) catch |err| {
        allocator.free(owned);
        return err;
    };
}
pub fn appendLinkInputFmt(
    allocator: std.mem.Allocator,
    link_inputs: *std.array_list.Managed([]const u8),
    owned_link_inputs: *std.array_list.Managed([]const u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try appendLinkInput(allocator, link_inputs, owned_link_inputs, text);
}
/// Resolves a declared native_link path/dir: absolute paths are used
/// as declared; relative ones resolve against the plugin root.
pub fn resolvePluginRootPath(allocator: std.mem.Allocator, root_dir: []const u8, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return try allocator.dupe(u8, path);
    return try std.fs.path.join(allocator, &.{ root_dir, path });
}
pub fn invalidDynamicLibraryHeader(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
    _ = allocator;
    if (@import("builtin").os.tag != .windows) return null;

    var file = sio.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return "FileNotFound",
        else => return err,
    };
    defer file.close();

    var magic: [2]u8 = undefined;
    file.readAll(&magic) catch |err| switch (err) {
        error.EndOfStream => return "invalid dynamic library header",
        else => return err,
    };
    if (!std.mem.eql(u8, magic[0..], "MZ")) return "invalid dynamic library header";
    return null;
}
pub const InstallOptions = struct {
    overwrite: bool = true,
    dev: bool = false,
    review: bool = false,
    optimize: []const u8 = "ReleaseFast",
    /// Install into this plugins home instead of the resolved default
    /// (workspace plugin staging installs into the project's local
    /// staging root).
    home_path: ?[]const u8 = null,
    /// The plugin is declared by the project's sa.mod
    /// (require_plugin with a local directory): the in-repo declaration
    /// substitutes for the interactive install confirmation, and the
    /// rendered permissions.lock records workspace_declared=true.
    workspace_declared: bool = false,
};
/// Plugin kind (sala 05_plugins/20_system_redesign): `command` is the
/// classic plugin shape; `language` marks a language frontend (e.g. SLA)
/// that the host dispatches to by file extension instead of exposing a
/// command namespace. Manifests without a "kind" field default to command.
pub const SapPluginKind = enum {
    command,
    language,
};
pub const SapManifest = struct {
    root_dir: []u8,
    sap_path: []u8,
    name: []u8,
    version: []u8,
    abi_plugin: u32,
    artifact_rel: []u8,
    artifact_sha256: ?[32]u8,
    interface_files: []InterfaceFile,
    asset_files: []AssetFile,
    dependencies: []PluginDependency,
    env_permissions: [][]u8,
    fs_permissions: []FsPermission,
    net_permissions: []NetPermission,
    process_spawn: bool,
    process_exec_permissions: []ProcessExecPermission,
    native_link: []NativeLinkEntry,
    permission_digest: [32]u8,
    external_urls: [][]u8,
    requires_sandbox: bool,
    has_fs_permission: bool,
    has_net_permission: bool,
    has_env_permission: bool,
    has_process_permission: bool,
    has_native_link_permission: bool,
    kind: SapPluginKind,
    language_extensions: [][]u8,
    commands: [][]u8,

    pub fn deinit(self: *SapManifest, allocator: std.mem.Allocator) void {
        allocator.free(self.root_dir);
        allocator.free(self.sap_path);
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.artifact_rel);
        for (self.interface_files) |*iface| iface.deinit(allocator);
        allocator.free(self.interface_files);
        for (self.asset_files) |*asset| asset.deinit(allocator);
        allocator.free(self.asset_files);
        for (self.dependencies) |*dep| dep.deinit(allocator);
        allocator.free(self.dependencies);
        for (self.env_permissions) |entry| allocator.free(entry);
        allocator.free(self.env_permissions);
        for (self.fs_permissions) |*entry| entry.deinit(allocator);
        allocator.free(self.fs_permissions);
        for (self.net_permissions) |*entry| entry.deinit(allocator);
        allocator.free(self.net_permissions);
        for (self.process_exec_permissions) |*entry| entry.deinit(allocator);
        allocator.free(self.process_exec_permissions);
        for (self.native_link) |*entry| entry.deinit(allocator);
        allocator.free(self.native_link);
        for (self.external_urls) |url| allocator.free(url);
        allocator.free(self.external_urls);
        for (self.language_extensions) |ext| allocator.free(ext);
        allocator.free(self.language_extensions);
        for (self.commands) |command| allocator.free(command);
        allocator.free(self.commands);
        self.* = undefined;
    }
};
pub const InterfaceKind = enum {
    sa,
    sai,
    sal,
    wasm_import,
};
pub const InterfaceFile = struct {
    kind: InterfaceKind,
    path: []u8,
    sha256: ?[32]u8,

    pub fn deinit(self: *InterfaceFile, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        self.* = undefined;
    }
};
pub const AssetKind = enum {
    share,
};
pub const AssetFile = struct {
    kind: AssetKind,
    path: []u8,
    target: []u8,
    sha256: ?[32]u8,

    pub fn deinit(self: *AssetFile, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.target);
        self.* = undefined;
    }
};
pub const PluginDependency = struct {
    name: []u8,
    version: []u8,
    abi: u32,
    optional: bool,
    symbols: [][]u8,
    path: ?[]u8,
    url: ?[]u8,

    pub fn deinit(self: *PluginDependency, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        for (self.symbols) |symbol| allocator.free(symbol);
        allocator.free(self.symbols);
        if (self.path) |path| allocator.free(path);
        if (self.url) |url| allocator.free(url);
        self.* = undefined;
    }
};
pub const NativeLinkKind = enum {
    lib,
    path,
};
/// One declared native library input (sap.json `permissions.native_link`,
/// ZOZI-4 manifest_native_link): either a linker library name resolved
/// through `dirs`, or a direct library file path. Relative paths and
/// dirs resolve against the plugin root directory. The declaration is
/// part of the permissions object, so the permission digest covers it
/// and the install confirmation confirms exactly these entries.
pub const NativeLinkEntry = struct {
    kind: NativeLinkKind,
    name: []u8,
    dirs: [][]u8,

    pub fn deinit(self: *NativeLinkEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.dirs) |dir| allocator.free(dir);
        allocator.free(self.dirs);
        self.* = undefined;
    }
};
/// First-load confirmation (sala 05_plugins/20_system_redesign): a plugin
/// may arrive through any channel (manual copy, npm, git) without an
/// install-time confirmation. `sa plugin confirm <name>` reviews the
/// installed manifest in place and, on approval, writes the same
/// permissions.lock a formal install would have produced. The runtime
/// acceptance rule stays permissionsLockMatches: any later manifest
/// change (permission digest change) invalidates the confirmation and
/// it must be repeated. Interactive use prompts on the TTY; --yes is the
/// explicit non-interactive confirmation (the review is still printed).
pub fn confirmInstalledPlugin(allocator: std.mem.Allocator, name: []const u8, stdout: anytype, assume_yes: bool) !u8 {
    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const installed_dir = try std.fs.path.join(allocator, &.{ home, "installed", name, "current" });
    defer allocator.free(installed_dir);
    var manifest = parseSapManifest(allocator, installed_dir) catch {
        try stdout.print("plugin {s} is not installed\n", .{name});
        return 1;
    };
    defer manifest.deinit(allocator);

    if (!manifest.requires_sandbox) {
        try stdout.print("plugin {s} declares no privileged permissions; nothing to confirm\n", .{name});
        return 0;
    }
    if (try permissionsLockMatches(allocator, manifest)) {
        try stdout.print("plugin {s}: permissions already confirmed for the current manifest\n", .{name});
        return 0;
    }

    const confirmed = if (assume_yes) blk: {
        const review_text = try renderPermissionsLock(allocator, manifest, false, false, false);
        defer allocator.free(review_text);
        try stdout.print("SA PLUGIN PERMISSION REVIEW\n{s}\nconfirming plugin {s} via explicit --yes\n", .{ review_text, name });
        break :blk true;
    } else try confirmPrivilegedPluginInstall(stdout, manifest);
    if (!confirmed) {
        try stdout.print("plugin {s} was not confirmed; no permissions.lock written\n", .{name});
        return 1;
    }

    const permissions_lock_text = try renderPermissionsLock(allocator, manifest, true, false, false);
    defer allocator.free(permissions_lock_text);
    const permissions_lock_path = try std.fs.path.join(allocator, &.{ installed_dir, "permissions.lock" });
    defer allocator.free(permissions_lock_path);
    try writeFileAbsolute(permissions_lock_path, permissions_lock_text);
    const version_dir = try std.fs.path.join(allocator, &.{ home, "installed", manifest.name, manifest.version });
    defer allocator.free(version_dir);
    const version_permissions_lock_path = try std.fs.path.join(allocator, &.{ version_dir, "permissions.lock" });
    defer allocator.free(version_permissions_lock_path);
    writeFileAbsolute(version_permissions_lock_path, permissions_lock_text) catch {};
    try stdout.print("plugin {s}: permissions confirmed; permissions.lock written\n", .{name});
    return 0;
}
pub fn installFromPath(allocator: std.mem.Allocator, path: []const u8, stdout: anytype, options: InstallOptions) !u8 {
    return try installFromPathInternal(allocator, path, stdout, options, 0, &.{});
}
pub fn installFromPathInternal(allocator: std.mem.Allocator, path: []const u8, stdout: anytype, options: InstallOptions, depth: u8, ancestors: []const []const u8) anyerror!u8 {
    if (depth > 32) return error.PluginDependencyCycle;
    if (isDynamicLibraryPath(path)) {
        try stdout.writeAll("refusing to install a raw dynamic library; install a plugin project directory or sap.json instead\n");
        return 1;
    }
    if (std.mem.startsWith(u8, path, "github:") or std.mem.startsWith(u8, path, "npm:") or std.mem.indexOf(u8, path, "://") != null) {
        const fetched_root = try fetchRemotePluginSource(allocator, path, stdout, options);
        defer allocator.free(fetched_root);
        return try installFromPathInternal(allocator, fetched_root, stdout, options, depth, ancestors);
    }

    var manifest = try parseSapManifest(allocator, path);
    defer manifest.deinit(allocator);
    for (ancestors) |ancestor| {
        if (std.mem.eql(u8, ancestor, manifest.sap_path)) {
            try stdout.print("plugin dependency cycle detected at {s}\n", .{manifest.sap_path});
            return 1;
        }
    }
    try warnBroadNetPermissions(stdout, manifest);
    const next_ancestors = try allocator.alloc([]const u8, ancestors.len + 1);
    defer allocator.free(next_ancestors);
    @memcpy(next_ancestors[0..ancestors.len], ancestors);
    next_ancestors[ancestors.len] = manifest.sap_path;

    if (options.review) {
        const review_text = try renderPermissionsLock(allocator, manifest, false, false, false);
        defer allocator.free(review_text);
        try stdout.writeAll(review_text);
        return 0;
    }

    if (try installPluginDependencies(allocator, manifest, stdout, options, depth, next_ancestors) != 0) return 1;

    if (!fileExistsInProject(allocator, manifest.root_dir, "build.zig") or
        !fileExistsInProject(allocator, manifest.root_dir, "src/plugin.zig"))
    {
        try stdout.writeAll("refusing to install plugin without text source project: required build.zig and src/plugin.zig\n");
        return 1;
    }

    const locked_permissions_confirmed = try permissionsLockMatches(allocator, manifest);
    var manual_permissions_confirmed = false;
    if (manifest.requires_sandbox and !locked_permissions_confirmed and !options.dev and !options.workspace_declared and !pluginDevMode(allocator)) {
        const confirmed = try confirmPrivilegedPluginInstall(stdout, manifest);
        if (!confirmed) return 1;
        manual_permissions_confirmed = true;
    }
    const permissions_confirmed = !manifest.requires_sandbox or locked_permissions_confirmed or manual_permissions_confirmed or options.workspace_declared;

    if (try verifyInterfaceFiles(allocator, manifest) != 0) return 1;
    if (try verifyAssetFiles(allocator, manifest) != 0) return 1;
    if (try verifyInstalledExternSymbolConflicts(allocator, manifest, stdout) != 0) return 1;

    if (try buildPluginProject(allocator, manifest.root_dir, stdout, options.optimize) != 0) return 1;

    const artifact_abs = try std.fs.path.join(allocator, &.{ manifest.root_dir, manifest.artifact_rel });
    defer allocator.free(artifact_abs);
    if (!fileExistsAbsolute(artifact_abs)) {
        try stdout.print("plugin build did not produce declared artifact: {s}\n", .{artifact_abs});
        return 1;
    }

    const home = if (options.home_path) |override| try allocator.dupe(u8, override) else try pluginsHome(allocator);
    defer allocator.free(home);
    const installed_dir = try std.fs.path.join(allocator, &.{ home, "installed", manifest.name, "current" });
    defer allocator.free(installed_dir);
    const version_dir = try std.fs.path.join(allocator, &.{ home, "installed", manifest.name, manifest.version });
    defer allocator.free(version_dir);

    if (options.overwrite and dirExistsAbsolute(installed_dir)) try sio.cwd().deleteTree(installed_dir);
    if (options.overwrite and dirExistsAbsolute(version_dir)) try sio.cwd().deleteTree(version_dir);
    try sio.cwd().makePath(installed_dir);
    try sio.cwd().makePath(version_dir);

    const artifact_name = std.fs.path.basename(manifest.artifact_rel);
    const installed_artifact = try std.fs.path.join(allocator, &.{ installed_dir, artifact_name });
    defer allocator.free(installed_artifact);
    try copyFileAbsolute(artifact_abs, installed_artifact);
    const version_artifact = try std.fs.path.join(allocator, &.{ version_dir, artifact_name });
    defer allocator.free(version_artifact);
    try copyFileAbsolute(artifact_abs, version_artifact);

    const installed_sap = try std.fs.path.join(allocator, &.{ installed_dir, "sap.json" });
    defer allocator.free(installed_sap);
    try copyFileAbsolute(manifest.sap_path, installed_sap);
    const version_sap = try std.fs.path.join(allocator, &.{ version_dir, "sap.json" });
    defer allocator.free(version_sap);
    try copyFileAbsolute(manifest.sap_path, version_sap);

    if (try verifySymbolSmoke(allocator, manifest, artifact_abs, stdout) != 0) return 1;
    if (try verifyArtifactStaticPolicy(allocator, manifest, artifact_abs, stdout, options) != 0) return 1;

    if (manifest.interface_files.len > 0) {
        const sa_dir = try std.fs.path.join(allocator, &.{ installed_dir, "sa" });
        defer allocator.free(sa_dir);
        try sio.cwd().makePath(sa_dir);
        const version_sa_dir = try std.fs.path.join(allocator, &.{ version_dir, "sa" });
        defer allocator.free(version_sa_dir);
        try sio.cwd().makePath(version_sa_dir);
        for (manifest.interface_files) |iface| {
            const rel = iface.path;
            const src = try std.fs.path.join(allocator, &.{ manifest.root_dir, rel });
            defer allocator.free(src);
            if (!fileExistsAbsolute(src)) return error.PluginInterfaceMissing;
            const dst = try std.fs.path.join(allocator, &.{ sa_dir, std.fs.path.basename(rel) });
            defer allocator.free(dst);
            try copyFileAbsolute(src, dst);
            const version_dst = try std.fs.path.join(allocator, &.{ version_sa_dir, std.fs.path.basename(rel) });
            defer allocator.free(version_dst);
            try copyFileAbsolute(src, version_dst);
        }
    }
    try copyAssetFiles(allocator, manifest, installed_dir, version_dir);

    var artifact_file = try sio.openFileAbsolute(artifact_abs, .{});
    defer artifact_file.close();
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = try artifact_file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    const permission_digest_hex = std.fmt.bytesToHex(manifest.permission_digest, .lower);
    const dependency_graph_digest = dependencyGraphDigest(manifest);
    const dependency_graph_digest_hex = std.fmt.bytesToHex(dependency_graph_digest, .lower);

    const lock_path = try std.fs.path.join(allocator, &.{ installed_dir, "sap.lock" });
    defer allocator.free(lock_path);
    const lock_text = try std.fmt.allocPrint(allocator,
        \\name={s}
        \\version={s}
        \\artifact={s}
        \\sha256={s}
        \\permissions_sha256={s}
        \\dependency_graph_sha256={s}
        \\dependencies={d}
        \\
    , .{ manifest.name, manifest.version, artifact_name, digest_hex, permission_digest_hex, dependency_graph_digest_hex, manifest.dependencies.len });
    defer allocator.free(lock_text);
    try writeFileAbsolute(lock_path, lock_text);
    const version_lock_path = try std.fs.path.join(allocator, &.{ version_dir, "sap.lock" });
    defer allocator.free(version_lock_path);
    try writeFileAbsolute(version_lock_path, lock_text);

    const dev_install = options.dev or pluginDevMode(allocator);
    const permissions_lock_text = try renderPermissionsLock(allocator, manifest, permissions_confirmed, dev_install, options.workspace_declared);
    defer allocator.free(permissions_lock_text);
    const permissions_lock_path = try std.fs.path.join(allocator, &.{ installed_dir, "permissions.lock" });
    defer allocator.free(permissions_lock_path);
    try writeFileAbsolute(permissions_lock_path, permissions_lock_text);
    const version_permissions_lock_path = try std.fs.path.join(allocator, &.{ version_dir, "permissions.lock" });
    defer allocator.free(version_permissions_lock_path);
    try writeFileAbsolute(version_permissions_lock_path, permissions_lock_text);

    try stdout.print("{s}\n", .{installed_dir});
    return 0;
}
