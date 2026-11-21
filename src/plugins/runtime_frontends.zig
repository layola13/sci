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

pub fn languageFrontendForExtensionImpl(self: *const Runtime, ext: []const u8) ?[]const u8 {
    for (self.language_frontends.items) |*frontend| {
        for (frontend.extensions) |owned| {
            if (std.mem.eql(u8, owned, ext)) return frontend.plugin_name;
        }
    }
    return null;
}

pub fn languageFrontendInfosImpl(
    self: *const Runtime,
    allocator: std.mem.Allocator,
) ![]Runtime.LanguageFrontendInfo {
    var infos = std.array_list.Managed(Runtime.LanguageFrontendInfo).init(allocator);
    errdefer infos.deinit();
    for (self.language_frontends.items) |*frontend| {
        try infos.append(.{ .name = frontend.plugin_name, .extensions = frontend.extensions });
    }
    return infos.toOwnedSlice();
}

pub fn languageFrontendNamedImpl(
    self: *const Runtime,
    name: []const u8,
) ?*const LanguageFrontend {
    for (self.language_frontends.items) |*frontend| {
        if (std.mem.eql(u8, frontend.plugin_name, name)) return frontend;
    }
    return null;
}

pub fn commandClaimantImpl(self: *const Runtime, command: []const u8) ?[]const u8 {
    for (self.command_claims.items) |*claim| {
        if (std.mem.eql(u8, claim.command, command)) return claim.plugin_name;
    }
    return null;
}

pub fn registerCommandClaimsImpl(
    self: *Runtime,
    plugin_name: []const u8,
    commands: []const []const u8,
) !void {
    var owned = std.array_list.Managed(CommandClaim).init(self.allocator);
    defer owned.deinit();
    errdefer {
        for (owned.items) |*claim| claim.deinit(self.allocator);
    }
    for (commands) |command| {
        if (command.len == 0) continue;
        if (self.commandClaimant(command)) |existing| {
            if (!std.mem.eql(u8, existing, plugin_name)) {
                const reason = try std.fmt.allocPrint(
                    self.allocator,
                    "command {s} is claimed by both {s} and {s}; keeping {s}",
                    .{ command, existing, plugin_name, existing },
                );
                defer self.allocator.free(reason);
                try self.addDiagnostic(plugin_name, reason);
            }
            continue;
        }
        var already = false;
        for (owned.items) |*claim| {
            if (std.mem.eql(u8, claim.command, command)) {
                already = true;
                break;
            }
        }
        if (already) continue;
        try owned.append(.{
            .command = try self.allocator.dupe(u8, command),
            .plugin_name = try self.allocator.dupe(u8, plugin_name),
        });
    }
    if (owned.items.len == 0) return;
    const claims = try owned.toOwnedSlice();
    defer self.allocator.free(claims);
    try self.command_claims.appendSlice(claims);
}

pub fn registerLanguageFrontendImpl(
    self: *Runtime,
    plugin_name: []const u8,
    extensions: []const []const u8,
) !void {
    var owned = std.array_list.Managed([]u8).init(self.allocator);
    defer owned.deinit();
    errdefer {
        for (owned.items) |ext| self.allocator.free(ext);
    }
    for (extensions) |ext| {
        if (self.languageFrontendForExtension(ext)) |existing| {
            if (!std.mem.eql(u8, existing, plugin_name)) {
                const reason = try std.fmt.allocPrint(
                    self.allocator,
                    "language extension {s} is claimed by both {s} and {s}; keeping {s}",
                    .{ ext, existing, plugin_name, existing },
                );
                defer self.allocator.free(reason);
                try self.addDiagnostic(plugin_name, reason);
                continue;
            }
            continue;
        }
        try owned.append(try self.allocator.dupe(u8, ext));
    }
    if (owned.items.len == 0) return;
    const name_copy = try self.allocator.dupe(u8, plugin_name);
    errdefer self.allocator.free(name_copy);
    const exts = try owned.toOwnedSlice();
    try self.language_frontends.append(.{
        .plugin_name = name_copy,
        .extensions = exts,
    });
}

pub fn noteCommandClaimsImpl(self: *Runtime, lib_path: []const u8) !void {
    const dir_path = std.fs.path.dirname(lib_path) orelse return;
    var manifest = parseSapManifest(self.allocator, dir_path) catch return;
    defer manifest.deinit(self.allocator);
    if (manifest.commands.len == 0) return;
    try self.registerCommandClaims(manifest.name, manifest.commands);
}

pub fn noteLanguageFrontendImpl(self: *Runtime, lib_path: []const u8) !void {
    const dir_path = std.fs.path.dirname(lib_path) orelse return;
    var manifest = parseSapManifest(self.allocator, dir_path) catch return;
    defer manifest.deinit(self.allocator);
    if (manifest.kind != .language) return;
    if (manifest.language_extensions.len == 0) return;
    try self.registerLanguageFrontend(manifest.name, manifest.language_extensions);
}

pub fn runtimePolicyDenialForLibraryImpl(self: *Runtime, lib_path: []const u8) !?[]u8 {
    const dir = std.fs.path.dirname(lib_path) orelse return null;
    return try self.runtimePolicyDenialForDirectory(dir);
}

pub fn runtimeArtifactHashMismatchImpl(self: *Runtime, lib_path: []const u8) !?[]u8 {
    const dir_path = std.fs.path.dirname(lib_path) orelse return null;
    const sap_path = try std.fs.path.join(self.allocator, &.{ dir_path, "sap.json" });
    defer self.allocator.free(sap_path);
    if (!fileExistsAbsolute(sap_path)) return null;

    var manifest = parseSapManifest(self.allocator, sap_path) catch |err| {
        return try std.fmt.allocPrint(self.allocator, "plugin manifest could not be parsed before load: {s}", .{@errorName(err)});
    };
    defer manifest.deinit(self.allocator);

    const expected = manifest.artifact_sha256 orelse return null;
    if (!std.mem.eql(u8, std.fs.path.basename(lib_path), std.fs.path.basename(manifest.artifact_rel))) return null;

    const actual = sha256File(self.allocator, lib_path) catch |err| {
        return try std.fmt.allocPrint(self.allocator, "plugin artifact sha256 could not be computed before load: {s}", .{@errorName(err)});
    };
    if (std.mem.eql(u8, actual[0..], expected[0..])) return null;

    const actual_hex = std.fmt.bytesToHex(actual, .lower);
    const expected_hex = std.fmt.bytesToHex(expected, .lower);
    return try std.fmt.allocPrint(
        self.allocator,
        "plugin artifact sha256 mismatch before load: expected {s}, actual {s}",
        .{ expected_hex, actual_hex },
    );
}

pub fn runtimePolicyDenialForDirectoryImpl(self: *Runtime, dir_path: []const u8) !?[]u8 {
    if (pluginDevMode(self.allocator) or self.host_authorization.dev_mode) return null;
    for (self.workspace_plugin_dirs.items) |staged| {
        if (std.mem.eql(u8, staged, dir_path)) return null;
    }

    const sap_path = try std.fs.path.join(self.allocator, &.{ dir_path, "sap.json" });
    defer self.allocator.free(sap_path);
    if (!fileExistsAbsolute(sap_path)) return null;

    var manifest = parseSapManifest(self.allocator, sap_path) catch |err| {
        return try std.fmt.allocPrint(self.allocator, "plugin manifest could not be parsed at runtime: {s}", .{@errorName(err)});
    };
    defer manifest.deinit(self.allocator);
    if (!manifest.requires_sandbox) return null;

    const lock_path = try std.fs.path.join(self.allocator, &.{ dir_path, "permissions.lock" });
    defer self.allocator.free(lock_path);
    const lock_text = readFileAbsoluteAlloc(self.allocator, lock_path, 1 << 20) catch |err| switch (err) {
        error.FileNotFound => {
            return try std.fmt.allocPrint(
                self.allocator,
                "privileged plugin {s} is blocked in formal runtime mode [SA-PLUGIN-PERMISSIONS-LOCK-MISSING]: permissions.lock missing and runtime sandbox is not enforced\n  dev remedy (trusted development only): SA_PLUGIN_DEV=1 sa plugin install --dev <plugin-source-dir>, then verify with `sa plugin list`\n  formal remedy: run `sa plugin confirm <plugin-name>` to review and confirm the installed plugin in place (this generates permissions.lock; --yes is the explicit non-interactive form), or reinstall formally with `sa plugin install <plugin-source-dir>` and confirm when prompted; never hand-write permissions.lock",
                .{manifest.name},
            );
        },
        else => return err,
    };
    defer self.allocator.free(lock_text);

    if (lockHasKeyValue(lock_text, "dev_install", "true")) {
        return try std.fmt.allocPrint(
            self.allocator,
            "privileged plugin {s} is blocked in formal runtime mode [SA-PLUGIN-DEV-INSTALL-IN-FORMAL-MODE]: plugin was installed in development mode (permissions.lock records dev_install=true)\n  dev remedy (trusted development only): run with SA_PLUGIN_DEV=1, or reinstall with SA_PLUGIN_DEV=1 sa plugin install --dev <plugin-source-dir>\n  formal remedy: reinstall formally with `sa plugin install <plugin-source-dir>` and confirm the declared permissions when prompted",
            .{manifest.name},
        );
    }
    if (lockHasKeyValue(lock_text, "sandbox_enforced", "true")) return null;
    return try std.fmt.allocPrint(
        self.allocator,
        "privileged plugin {s} is blocked in formal runtime mode [SA-PLUGIN-SANDBOX-NOT-ENFORCED]: runtime sandbox/broker enforcement is not active\n  dev remedy (trusted development only): run with SA_PLUGIN_DEV=1\n  formal remedy: run on a host where the plugin sandbox/broker is enforced so the install records sandbox_enforced=true in permissions.lock; on a host that cannot enforce it, this plugin cannot run in formal mode",
        .{manifest.name},
    );
}

pub fn addDiagnosticImpl(self: *Runtime, path: []const u8, reason: []const u8) !void {
    try self.diagnostics.append(.{
        .path = try self.allocator.dupe(u8, path),
        .reason = try self.allocator.dupe(u8, reason),
    });
}

pub fn noteManifestHelpForLibraryImpl(self: *Runtime, lib_path: []const u8) !void {
    const dir_path = std.fs.path.dirname(lib_path) orelse return;
    try self.noteManifestHelpForDirectory(dir_path);
}

pub fn noteManifestHelpForDirectoryImpl(self: *Runtime, dir_path: []const u8) !void {
    const sap_path = try std.fs.path.join(self.allocator, &.{ dir_path, "sap.json" });
    errdefer self.allocator.free(sap_path);
    if (!fileExistsAbsolute(sap_path)) {
        self.allocator.free(sap_path);
        return;
    }

    for (self.manifest_help.items) |entry| {
        if (std.mem.eql(u8, entry.sap_path, sap_path)) {
            self.allocator.free(sap_path);
            return;
        }
    }

    const source = readFileAbsoluteAlloc(self.allocator, sap_path, 1 << 20) catch {
        self.allocator.free(sap_path);
        return;
    };
    defer self.allocator.free(source);
    var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, source, .{}) catch {
        self.allocator.free(sap_path);
        return;
    };
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |obj| obj,
        else => {
            self.allocator.free(sap_path);
            return;
        },
    };
    const name_text = jsonString(object.get("name") orelse {
        self.allocator.free(sap_path);
        return;
    }) catch {
        self.allocator.free(sap_path);
        return;
    };
    const name = try self.allocator.dupe(u8, name_text);
    errdefer self.allocator.free(name);
    try self.manifest_help.append(.{
        .name = name,
        .sap_path = sap_path,
    });
}
