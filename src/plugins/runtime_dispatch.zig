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

pub fn invokePluginCommandImpl(
    self: *Runtime,
    loaded: *LoadedPlugin,
    c_argv: []const [*:0]const u8,
    json_mode: bool,
    stdout_stream: HostStream,
    stderr_stream: HostStream,
    stderr: anytype,
) !?u8 {
    const handle = loaded.descriptor.handle_command orelse return null;
    var broker = RuntimeBroker{
        .allocator = self.allocator,
        .policy = &loaded.permission_policy,
        .authorization = &self.host_authorization,
    };
    var ctx = Context{
        .allocator = self.allocator,
        .json_mode = json_mode,
        .broker_abi_version = broker_abi_version,
        .broker_call = runtimeBrokerCall,
        .broker_ctx = &broker,
    };
    var out_code: u8 = 0;
    const status_value = handle(&ctx, c_argv.ptr, c_argv.len, stdout_stream, stderr_stream, &out_code);
    const status = abiStatusFromInt(status_value);
    switch (status) {
        .ok => return out_code,
        .unknown_command => return null,
        .failed, .version_mismatch, .invalid_descriptor => {
            try stderr.print("error[SA-PLUGIN]: plugin {s} failed with {s}\n", .{
                std.mem.span(loaded.descriptor.name),
                @tagName(status),
            });
            return 1;
        },
    }
}

pub fn dispatchCommandImpl(
    self: *Runtime,
    argv: []const []const u8,
    stdout: anytype,
    stderr: anytype,
    json_mode: bool,
) !?u8 {
    if (argv.len < 2) return null;

    if (try self.dispatchRecordedManifestHelpIfRequested(argv, stdout)) |code| return code;

    for (self.plugins.items) |*loaded| {
        if (try self.dispatchManifestHelpIfRequested(argv, loaded, stdout)) |code| return code;
    }

    var plugin_argv = std.array_list.Managed([]const u8).init(self.allocator);
    defer plugin_argv.deinit();
    try plugin_argv.appendSlice(argv);
    if (json_mode) try plugin_argv.append("--json");

    const c_argv = try dupeZArgs(self.allocator, plugin_argv.items);
    defer freeZArgs(self.allocator, c_argv);

    var stdout_value = stdout;
    var stderr_value = stderr;
    var stdout_ctx = StreamCtx(@TypeOf(stdout_value)){ .writer = &stdout_value };
    var stderr_ctx = StreamCtx(@TypeOf(stderr_value)){ .writer = &stderr_value };
    const stdout_stream = HostStream{ .ctx = &stdout_ctx, .write_all = streamWriteAll(@TypeOf(stdout_value)) };
    const stderr_stream = HostStream{ .ctx = &stderr_ctx, .write_all = streamWriteAll(@TypeOf(stderr_value)) };

    // Legacy two-layer language invocation: `sa <frontend>
    // <verb> ...` still dispatches, but language frontends are
    // routed by file extension, so the direct host verb is the
    // preferred form. Host-constructed dispatches (extension
    // routing) set suppress_legacy_frontend_notice and stay quiet.
    if (!self.suppress_legacy_frontend_notice and argv.len >= 3) {
        if (self.languageFrontendNamed(argv[1])) |frontend| {
            const ext = if (frontend.extensions.len != 0) frontend.extensions[0] else "";
            try stderr.print("note[SA-PLUGIN]: 'sa {s} {s}' is deprecated: language frontends are dispatched by file extension, so run the host verb directly (e.g. 'sa {s} <file{s}>'). The 'sa {s}' form keeps working during the transition.\n", .{ argv[1], argv[2], argv[2], ext, argv[1] });
        }
    }

    // A command declared in a manifest ("commands") dispatches
    // straight to its claimant and the claim is authoritative:
    // the claimant's answer stands even when it is
    // unknown_command. Undeclared commands keep the legacy
    // offer-to-all scan in load order.
    if (self.commandClaimant(argv[1])) |claimant| {
        for (self.plugins.items) |*loaded| {
            if (!std.mem.eql(u8, std.mem.span(loaded.descriptor.name), claimant)) continue;
            return try self.invokePluginCommand(loaded, c_argv, json_mode, stdout_stream, stderr_stream, stderr);
        }
    }

    for (self.plugins.items) |*loaded| {
        if (try self.invokePluginCommand(loaded, c_argv, json_mode, stdout_stream, stderr_stream, stderr)) |code| return code;
    }
    return null;
}

pub fn dispatchRecordedManifestHelpIfRequestedImpl(
    self: *Runtime,
    argv: []const []const u8,
    stdout: anytype,
) !?u8 {
    if (argv.len < 3) return null;
    if (!pluginHelpTokenPresent(argv[2..])) return null;
    for (self.manifest_help.items) |entry| {
        if (!std.mem.eql(u8, entry.name, argv[1])) continue;
        try self.writeManifestHelpPath(entry.sap_path, stdout, entry.name, null);
        return 0;
    }
    return null;
}

pub fn dispatchManifestHelpIfRequestedImpl(
    self: *Runtime,
    argv: []const []const u8,
    loaded: *LoadedPlugin,
    stdout: anytype,
) !?u8 {
    if (argv.len < 3) return null;
    if (!pluginHelpTokenPresent(argv[2..])) return null;
    if (!try self.pluginCommandMatches(loaded, argv[1])) return null;
    try self.writePluginManifestHelp(loaded, stdout);
    return 0;
}

pub fn pluginCommandMatchesImpl(
    self: *Runtime,
    loaded: *LoadedPlugin,
    command: []const u8,
) !bool {
    if (std.mem.eql(u8, std.mem.span(loaded.descriptor.name), command)) return true;
    const sap_path = try self.pluginSapPath(loaded) orelse return false;
    defer self.allocator.free(sap_path);
    if (!fileExistsAbsolute(sap_path)) return false;

    const source = readFileAbsoluteAlloc(self.allocator, sap_path, 1 << 20) catch return false;
    defer self.allocator.free(source);
    var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, source, .{}) catch return false;
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |obj| obj,
        else => return false,
    };
    const manifest_name = jsonString(object.get("name") orelse return false) catch return false;
    return std.mem.eql(u8, manifest_name, command);
}

pub fn writePluginManifestHelpImpl(
    self: *Runtime,
    loaded: *LoadedPlugin,
    stdout: anytype,
) !void {
    const sap_path = try self.pluginSapPath(loaded) orelse {
        try writePluginHelpFallback(loaded, stdout, null, null);
        return;
    };
    defer self.allocator.free(sap_path);
    if (!fileExistsAbsolute(sap_path)) {
        try writePluginHelpFallback(loaded, stdout, null, null);
        return;
    }

    const source = readFileAbsoluteAlloc(self.allocator, sap_path, 1 << 20) catch {
        try writePluginHelpFallback(loaded, stdout, null, null);
        return;
    };
    defer self.allocator.free(source);
    try self.writeManifestHelpSource(source, stdout, loaded, null);
}

pub fn writeManifestHelpPathImpl(
    self: *Runtime,
    sap_path: []const u8,
    stdout: anytype,
    fallback_name: []const u8,
    loaded: ?*const LoadedPlugin,
) !void {
    const source = readFileAbsoluteAlloc(self.allocator, sap_path, 1 << 20) catch {
        if (loaded) |plugin| try writePluginHelpFallback(plugin, stdout, fallback_name, null) else try writeManifestHelpFallback(stdout, fallback_name, null);
        return;
    };
    defer self.allocator.free(source);
    try self.writeManifestHelpSource(source, stdout, loaded, fallback_name);
}

pub fn writeManifestHelpSourceImpl(
    self: *Runtime,
    source: []const u8,
    stdout: anytype,
    loaded: ?*const LoadedPlugin,
    fallback_name: ?[]const u8,
) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, source, .{}) catch {
        if (loaded) |plugin| try writePluginHelpFallback(plugin, stdout, fallback_name, null) else try writeManifestHelpFallback(stdout, fallback_name orelse "plugin", null);
        return;
    };
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |obj| obj,
        else => {
            if (loaded) |plugin| try writePluginHelpFallback(plugin, stdout, fallback_name, null) else try writeManifestHelpFallback(stdout, fallback_name orelse "plugin", null);
            return;
        },
    };

    const manifest_name = if (object.get("name")) |value| jsonString(value) catch null else fallback_name;
    const manifest_version = if (object.get("version")) |value| jsonString(value) catch null else null;

    if (object.get("help")) |help_value| {
        if (try writeManifestHelpValue(stdout, help_value)) return;
    }
    if (loaded) |plugin| {
        try writePluginHelpFallback(plugin, stdout, manifest_name, manifest_version);
    } else {
        try writeManifestHelpFallback(stdout, manifest_name orelse fallback_name orelse "plugin", manifest_version);
    }
}

pub fn pluginSapPathImpl(self: *Runtime, loaded: *const LoadedPlugin) !?[]u8 {
    const plugin_dir = std.fs.path.dirname(loaded.path) orelse return null;
    return try std.fs.path.join(self.allocator, &.{ plugin_dir, "sap.json" });
}
