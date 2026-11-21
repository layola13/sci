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

pub fn initImpl(allocator: std.mem.Allocator) Runtime {
    return .{
        .allocator = allocator,
        .plugins = std.array_list.Managed(LoadedPlugin).init(allocator),
        .manifest_help = std.array_list.Managed(ManifestHelpEntry).init(allocator),
        .language_frontends = std.array_list.Managed(LanguageFrontend).init(allocator),
        .diagnostics = std.array_list.Managed(LoadDiagnostic).init(allocator),
        .host_authorization = .{},
        .workspace_plugin_dirs = std.array_list.Managed([]u8).init(allocator),
        .command_claims = std.array_list.Managed(CommandClaim).init(allocator),
    };
}

pub fn initWithAuthorizationImpl(
    allocator: std.mem.Allocator,
    authorization: RuntimeAuthorizationInput,
) !Runtime {
    var runtime = Runtime.init(allocator);
    errdefer runtime.deinit();
    runtime.host_authorization = try RuntimeHostAuthorization.init(allocator, authorization);
    return runtime;
}

pub fn initFromEnvImpl(allocator: std.mem.Allocator) !Runtime {
    var runtime = try Runtime.initWithAuthorization(allocator, .{
        .dev_mode = pluginDevMode(allocator),
    });
    errdefer runtime.deinit();
    runtime.loadWorkspacePlugins();
    try runtime.loadFromEnv();
    return runtime;
}

pub fn initFromEnvWithAuthorizationImpl(
    allocator: std.mem.Allocator,
    authorization: RuntimeAuthorizationInput,
) !Runtime {
    var runtime = try Runtime.initWithAuthorization(allocator, authorization);
    errdefer runtime.deinit();
    runtime.loadWorkspacePlugins();
    try runtime.loadFromEnv();
    return runtime;
}

pub fn initFromPathListImpl(allocator: std.mem.Allocator, path_list: []const u8) !Runtime {
    var runtime = try Runtime.initWithAuthorization(allocator, .{
        .dev_mode = pluginDevMode(allocator),
    });
    errdefer runtime.deinit();
    try runtime.loadPathList(path_list);
    return runtime;
}

pub fn initFromPathListWithAuthorizationImpl(
    allocator: std.mem.Allocator,
    path_list: []const u8,
    authorization: RuntimeAuthorizationInput,
) !Runtime {
    var runtime = try Runtime.initWithAuthorization(allocator, authorization);
    errdefer runtime.deinit();
    try runtime.loadPathList(path_list);
    return runtime;
}

pub fn deinitImpl(self: *Runtime) void {
    for (self.plugins.items) |*plugin| plugin.deinit(self.allocator);
    self.plugins.deinit();
    for (self.manifest_help.items) |*entry| entry.deinit(self.allocator);
    self.manifest_help.deinit();
    for (self.language_frontends.items) |*frontend| frontend.deinit(self.allocator);
    self.language_frontends.deinit();
    for (self.diagnostics.items) |*diagnostic| diagnostic.deinit(self.allocator);
    self.diagnostics.deinit();
    for (self.workspace_plugin_dirs.items) |dir| self.allocator.free(dir);
    self.workspace_plugin_dirs.deinit();
    for (self.command_claims.items) |*claim| claim.deinit(self.allocator);
    self.command_claims.deinit();
    self.host_authorization.deinit(self.allocator);
    self.* = undefined;
}
