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
const runtime_dispatch = @import("runtime_dispatch.zig");
const runtime_frontends = @import("runtime_frontends.zig");
const runtime_init = @import("runtime_init.zig");
const runtime_links = @import("runtime_links.zig");
const runtime_load = @import("runtime_load.zig");

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    plugins: std.array_list.Managed(LoadedPlugin),
    manifest_help: std.array_list.Managed(ManifestHelpEntry),
    language_frontends: std.array_list.Managed(LanguageFrontend),
    diagnostics: std.array_list.Managed(LoadDiagnostic),
    host_authorization: RuntimeHostAuthorization,
    /// Staged "current" directories of workspace-declared plugins
    /// (sa.mod require_plugin with a local directory), staged by this
    /// process from this project's declaration. Membership is the
    /// runtime-policy provenance for those directories: a directory on
    /// disk cannot enter this set without going through the current
    /// project's declaration + staging in this run.
    workspace_plugin_dirs: std.array_list.Managed([]u8),
    command_claims: std.array_list.Managed(CommandClaim),
    /// Set when the host itself constructed the dispatch argv
    /// (language extension routing builds `sa <frontend> build ...`
    /// internally); suppresses the legacy two-layer invocation
    /// deprecation notice for that dispatch. A user-typed
    /// `sa <frontend> <verb>` keeps the notice.
    suppress_legacy_frontend_notice: bool = false,

    pub fn init(allocator: std.mem.Allocator) Runtime {
        return runtime_init.initImpl(allocator);
    }

    pub fn initWithAuthorization(
        allocator: std.mem.Allocator,
        authorization: RuntimeAuthorizationInput,
    ) !Runtime {
        return runtime_init.initWithAuthorizationImpl(allocator, authorization);
    }

    pub fn initFromEnv(allocator: std.mem.Allocator) !Runtime {
        return runtime_init.initFromEnvImpl(allocator);
    }

    pub fn initFromEnvWithAuthorization(
        allocator: std.mem.Allocator,
        authorization: RuntimeAuthorizationInput,
    ) !Runtime {
        return runtime_init.initFromEnvWithAuthorizationImpl(allocator, authorization);
    }

    pub fn initFromPathList(allocator: std.mem.Allocator, path_list: []const u8) !Runtime {
        return runtime_init.initFromPathListImpl(allocator, path_list);
    }

    pub fn initFromPathListWithAuthorization(
        allocator: std.mem.Allocator,
        path_list: []const u8,
        authorization: RuntimeAuthorizationInput,
    ) !Runtime {
        return runtime_init.initFromPathListWithAuthorizationImpl(allocator, path_list, authorization);
    }

    pub fn deinit(self: *Runtime) void {
        runtime_init.deinitImpl(self);
    }

    /// Loads plugins declared by the current project's sa.mod
    /// (require_plugin with a local directory identity). Each declared
    /// source directory is staged into
    /// <project>/.sa-cache/workspace-plugins/ with the regular install
    /// machinery (the in-repo declaration substitutes for the
    /// interactive install confirmation), reusing the staged build
    /// while the source stamp is unchanged. Failures land in
    /// diagnostics, never fatal: a broken workspace plugin must not
    /// take down unrelated commands.
    pub fn loadWorkspacePlugins(self: *Runtime) void {
        runtime_load.loadWorkspacePluginsImpl(self);
    }

    pub fn stageWorkspacePlugin(self: *Runtime, project_root: []const u8, identity: []const u8) !void {
        return runtime_load.stageWorkspacePluginImpl(self, project_root, identity);
    }

    pub fn loadFromEnv(self: *Runtime) !void {
        return runtime_load.loadFromEnvImpl(self);
    }

    pub fn loadPathList(self: *Runtime, path_list: []const u8) !void {
        return runtime_load.loadPathListImpl(self, path_list);
    }

    pub fn loadPath(self: *Runtime, path: []const u8) !void {
        return runtime_load.loadPathImpl(self, path);
    }

    pub fn appendSkills(self: *const Runtime, list: anytype) !void {
        return runtime_links.appendSkillsImpl(self, list);
    }

    pub fn shouldAdvertiseSkills(self: *const Runtime, loaded: LoadedPlugin) !bool {
        return runtime_links.shouldAdvertiseSkillsImpl(self, loaded);
    }

    pub fn loadedPluginByName(self: *const Runtime, name: []const u8) ?*LoadedPlugin {
        return runtime_links.loadedPluginByNameImpl(self, name);
    }

    pub fn appendLibrariesExportingAny(
        self: *Runtime,
        list: *std.array_list.Managed([]const u8),
        symbol_names: []const []const u8,
    ) !void {
        return runtime_links.appendLibrariesExportingAnyImpl(self, list, symbol_names);
    }

    /// ZOZI-4 (manifest_native_link): symbol-probing link collection
    /// with native_link resolution. Plugin libraries and their rpaths
    /// are appended exactly as in appendLibrariesExportingAny; for
    /// every matched plugin that declares permissions.native_link
    /// entries, the declared real libraries are additionally appended
    /// as direct link inputs — but only when the declaration is in
    /// effect for this invocation (see nativeLinkDeclarationInEffect).
    /// An unconfirmed declaration or a declared library that cannot
    /// be found returns an allocated denial string naming the plugin
    /// and the remedies; nothing is ever skipped silently.
    pub fn appendNativeLinkInputsForExterns(
        self: *Runtime,
        link_inputs: *std.array_list.Managed([]const u8),
        owned_link_inputs: *std.array_list.Managed([]const u8),
        symbol_names: []const []const u8,
    ) !?[]u8 {
        return runtime_links.appendNativeLinkInputsForExternsImpl(self, link_inputs, owned_link_inputs, symbol_names);
    }

    pub fn appendDeclaredNativeLinks(
        self: *Runtime,
        link_inputs: *std.array_list.Managed([]const u8),
        owned_link_inputs: *std.array_list.Managed([]const u8),
        loaded: *LoadedPlugin,
    ) !?[]u8 {
        return runtime_links.appendDeclaredNativeLinksImpl(self, link_inputs, owned_link_inputs, loaded);
    }

    /// Whether a plugin's native_link declaration may take effect for
    /// this invocation. The link-path runtime is constructed with
    /// dev_mode=true so plugin library collection stays ungated (see
    /// appendNativePluginLinkInputs in cli.zig), so this gate reads
    /// the invocation's real confirmation state instead of
    /// host_authorization.dev_mode: a dev invocation (SA_PLUGIN_DEV),
    /// a workspace-declared plugin directory, or an install
    /// confirmation whose permissions digest covers the current
    /// manifest (permissions.lock with confirmed=true, not a dev
    /// install).
    pub fn nativeLinkDeclarationInEffect(
        self: *Runtime,
        plugin_dir: []const u8,
        manifest: SapManifest,
    ) !bool {
        return runtime_links.nativeLinkDeclarationInEffectImpl(self, plugin_dir, manifest);
    }

    /// Invokes one loaded plugin's command handler. Returns the exit
    /// code when the plugin handled the command (failures are
    /// reported here and also yield a code), or null when the plugin
    /// takes no commands or answered unknown_command.
    pub fn invokePluginCommand(
        self: *Runtime,
        loaded: *LoadedPlugin,
        c_argv: []const [*:0]const u8,
        json_mode: bool,
        stdout_stream: HostStream,
        stderr_stream: HostStream,
        stderr: anytype,
    ) !?u8 {
        return runtime_dispatch.invokePluginCommandImpl(self, loaded, c_argv, json_mode, stdout_stream, stderr_stream, stderr);
    }

    pub fn dispatchCommand(
        self: *Runtime,
        argv: []const []const u8,
        stdout: anytype,
        stderr: anytype,
        json_mode: bool,
    ) !?u8 {
        return runtime_dispatch.dispatchCommandImpl(self, argv, stdout, stderr, json_mode);
    }

    pub fn dispatchRecordedManifestHelpIfRequested(
        self: *Runtime,
        argv: []const []const u8,
        stdout: anytype,
    ) !?u8 {
        return runtime_dispatch.dispatchRecordedManifestHelpIfRequestedImpl(self, argv, stdout);
    }

    pub fn dispatchManifestHelpIfRequested(
        self: *Runtime,
        argv: []const []const u8,
        loaded: *LoadedPlugin,
        stdout: anytype,
    ) !?u8 {
        return runtime_dispatch.dispatchManifestHelpIfRequestedImpl(self, argv, loaded, stdout);
    }

    pub fn pluginCommandMatches(self: *Runtime, loaded: *LoadedPlugin, command: []const u8) !bool {
        return runtime_dispatch.pluginCommandMatchesImpl(self, loaded, command);
    }

    pub fn writePluginManifestHelp(self: *Runtime, loaded: *LoadedPlugin, stdout: anytype) !void {
        return runtime_dispatch.writePluginManifestHelpImpl(self, loaded, stdout);
    }

    pub fn writeManifestHelpPath(
        self: *Runtime,
        sap_path: []const u8,
        stdout: anytype,
        fallback_name: []const u8,
        loaded: ?*const LoadedPlugin,
    ) !void {
        return runtime_dispatch.writeManifestHelpPathImpl(self, sap_path, stdout, fallback_name, loaded);
    }

    pub fn writeManifestHelpSource(
        self: *Runtime,
        source: []const u8,
        stdout: anytype,
        loaded: ?*const LoadedPlugin,
        fallback_name: ?[]const u8,
    ) !void {
        return runtime_dispatch.writeManifestHelpSourceImpl(self, source, stdout, loaded, fallback_name);
    }

    pub fn pluginSapPath(self: *Runtime, loaded: *const LoadedPlugin) !?[]u8 {
        return runtime_dispatch.pluginSapPathImpl(self, loaded);
    }

    pub fn loadInstalledRoot(self: *Runtime, root_path: []const u8) !void {
        return runtime_load.loadInstalledRootImpl(self, root_path);
    }

    pub fn loadDirectory(self: *Runtime, dir_path: []const u8) !void {
        return runtime_load.loadDirectoryImpl(self, dir_path);
    }

    pub fn loadLibrary(self: *Runtime, path: []const u8) !void {
        return runtime_load.loadLibraryImpl(self, path);
    }

    /// Resolve a file extension (including the dot, e.g. ".sla") to the
    /// language frontend plugin that owns it, or null when no loaded
    /// language plugin claims it.
    pub fn languageFrontendForExtension(self: *const Runtime, ext: []const u8) ?[]const u8 {
        return runtime_frontends.languageFrontendForExtensionImpl(self, ext);
    }

    /// Borrowed view of one registered language frontend: its plugin
    /// name and the file extensions it owns. Slices borrow from the
    /// runtime and stay valid while it is alive.
    pub const LanguageFrontendInfo = struct {
        name: []const u8,
        extensions: []const []const u8,
    };

    /// Snapshot of every registered language frontend, in load order.
    /// The caller owns the returned slice (but not the borrowed fields).
    pub fn languageFrontendInfos(
        self: *const Runtime,
        allocator: std.mem.Allocator,
    ) ![]LanguageFrontendInfo {
        return runtime_frontends.languageFrontendInfosImpl(self, allocator);
    }

    pub fn languageFrontendNamed(self: *const Runtime, name: []const u8) ?*const LanguageFrontend {
        return runtime_frontends.languageFrontendNamedImpl(self, name);
    }

    /// The plugin that claimed a top-level command through its
    /// manifest "commands" declaration, or null when the command is
    /// undeclared and dispatch falls back to the legacy scan.
    pub fn commandClaimant(self: *const Runtime, command: []const u8) ?[]const u8 {
        return runtime_frontends.commandClaimantImpl(self, command);
    }

    /// Registers a plugin's declared commands in the host command
    /// index. The first claimant keeps a command; a later claim by a
    /// different plugin is skipped and reported as a load diagnostic
    /// naming both plugins, never silently shadowed.
    pub fn registerCommandClaims(
        self: *Runtime,
        plugin_name: []const u8,
        commands: []const []const u8,
    ) !void {
        return runtime_frontends.registerCommandClaimsImpl(self, plugin_name, commands);
    }

    pub fn registerLanguageFrontend(
        self: *Runtime,
        plugin_name: []const u8,
        extensions: []const []const u8,
    ) !void {
        return runtime_frontends.registerLanguageFrontendImpl(self, plugin_name, extensions);
    }

    pub fn noteCommandClaims(self: *Runtime, lib_path: []const u8) !void {
        return runtime_frontends.noteCommandClaimsImpl(self, lib_path);
    }

    pub fn noteLanguageFrontend(self: *Runtime, lib_path: []const u8) !void {
        return runtime_frontends.noteLanguageFrontendImpl(self, lib_path);
    }

    pub fn runtimePolicyDenialForLibrary(self: *Runtime, lib_path: []const u8) !?[]u8 {
        return runtime_frontends.runtimePolicyDenialForLibraryImpl(self, lib_path);
    }

    pub fn runtimeArtifactHashMismatch(self: *Runtime, lib_path: []const u8) !?[]u8 {
        return runtime_frontends.runtimeArtifactHashMismatchImpl(self, lib_path);
    }

    pub fn runtimePolicyDenialForDirectory(self: *Runtime, dir_path: []const u8) !?[]u8 {
        return runtime_frontends.runtimePolicyDenialForDirectoryImpl(self, dir_path);
    }

    pub fn addDiagnostic(self: *Runtime, path: []const u8, reason: []const u8) !void {
        return runtime_frontends.addDiagnosticImpl(self, path, reason);
    }

    pub fn noteManifestHelpForLibrary(self: *Runtime, lib_path: []const u8) !void {
        return runtime_frontends.noteManifestHelpForLibraryImpl(self, lib_path);
    }

    pub fn noteManifestHelpForDirectory(self: *Runtime, dir_path: []const u8) !void {
        return runtime_frontends.noteManifestHelpForDirectoryImpl(self, dir_path);
    }
};
