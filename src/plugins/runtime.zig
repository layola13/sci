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

    pub fn initWithAuthorization(allocator: std.mem.Allocator, authorization: RuntimeAuthorizationInput) !Runtime {
        var runtime = Runtime.init(allocator);
        errdefer runtime.deinit();
        runtime.host_authorization = try RuntimeHostAuthorization.init(allocator, authorization);
        return runtime;
    }

    pub fn initFromEnv(allocator: std.mem.Allocator) !Runtime {
        var runtime = try Runtime.initWithAuthorization(allocator, .{
            .dev_mode = pluginDevMode(allocator),
        });
        errdefer runtime.deinit();
        runtime.loadWorkspacePlugins();
        try runtime.loadFromEnv();
        return runtime;
    }

    pub fn initFromEnvWithAuthorization(allocator: std.mem.Allocator, authorization: RuntimeAuthorizationInput) !Runtime {
        var runtime = try Runtime.initWithAuthorization(allocator, authorization);
        errdefer runtime.deinit();
        runtime.loadWorkspacePlugins();
        try runtime.loadFromEnv();
        return runtime;
    }

    pub fn initFromPathList(allocator: std.mem.Allocator, path_list: []const u8) !Runtime {
        var runtime = try Runtime.initWithAuthorization(allocator, .{
            .dev_mode = pluginDevMode(allocator),
        });
        errdefer runtime.deinit();
        try runtime.loadPathList(path_list);
        return runtime;
    }

    pub fn initFromPathListWithAuthorization(allocator: std.mem.Allocator, path_list: []const u8, authorization: RuntimeAuthorizationInput) !Runtime {
        var runtime = try Runtime.initWithAuthorization(allocator, authorization);
        errdefer runtime.deinit();
        try runtime.loadPathList(path_list);
        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
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

    fn stageWorkspacePlugin(self: *Runtime, project_root: []const u8, identity: []const u8) !void {
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

    pub fn loadFromEnv(self: *Runtime) !void {
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

    pub fn loadPathList(self: *Runtime, path_list: []const u8) !void {
        const separator: u8 = if (@import("builtin").os.tag == .windows) ';' else ':';
        var it = std.mem.splitScalar(u8, path_list, separator);
        while (it.next()) |raw_entry| {
            const entry = std.mem.trim(u8, raw_entry, " \t\r\n");
            if (entry.len == 0) continue;
            try self.loadPath(entry);
        }
    }

    pub fn loadPath(self: *Runtime, path: []const u8) !void {
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

    pub fn appendSkills(self: *const Runtime, list: anytype) !void {
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

    fn shouldAdvertiseSkills(self: *const Runtime, loaded: LoadedPlugin) !bool {
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

    fn loadedPluginByName(self: *const Runtime, name: []const u8) ?*LoadedPlugin {
        const mutable_items: []LoadedPlugin = @constCast(self.plugins.items);
        for (mutable_items) |*loaded| {
            if (std.mem.eql(u8, std.mem.span(loaded.descriptor.name), name)) return loaded;
        }
        return null;
    }

    pub fn appendLibrariesExportingAny(
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

    fn appendDeclaredNativeLinks(
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
    fn nativeLinkDeclarationInEffect(self: *Runtime, plugin_dir: []const u8, manifest: SapManifest) !bool {
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

    /// Invokes one loaded plugin's command handler. Returns the exit
    /// code when the plugin handled the command (failures are
    /// reported here and also yield a code), or null when the plugin
    /// takes no commands or answered unknown_command.
    fn invokePluginCommand(
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

    pub fn dispatchCommand(
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

    fn dispatchRecordedManifestHelpIfRequested(
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

    fn dispatchManifestHelpIfRequested(
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

    fn pluginCommandMatches(self: *Runtime, loaded: *LoadedPlugin, command: []const u8) !bool {
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

    fn writePluginManifestHelp(self: *Runtime, loaded: *LoadedPlugin, stdout: anytype) !void {
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

    fn writeManifestHelpPath(
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

    fn writeManifestHelpSource(
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

    fn pluginSapPath(self: *Runtime, loaded: *const LoadedPlugin) !?[]u8 {
        const plugin_dir = std.fs.path.dirname(loaded.path) orelse return null;
        return try std.fs.path.join(self.allocator, &.{ plugin_dir, "sap.json" });
    }

    fn loadInstalledRoot(self: *Runtime, root_path: []const u8) !void {
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

    fn loadDirectory(self: *Runtime, dir_path: []const u8) !void {
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

    fn loadLibrary(self: *Runtime, path: []const u8) !void {
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

    /// Resolve a file extension (including the dot, e.g. ".sla") to the
    /// language frontend plugin that owns it, or null when no loaded
    /// language plugin claims it.
    pub fn languageFrontendForExtension(self: *const Runtime, ext: []const u8) ?[]const u8 {
        for (self.language_frontends.items) |*frontend| {
            for (frontend.extensions) |owned| {
                if (std.mem.eql(u8, owned, ext)) return frontend.plugin_name;
            }
        }
        return null;
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
    pub fn languageFrontendInfos(self: *const Runtime, allocator: std.mem.Allocator) ![]LanguageFrontendInfo {
        var infos = std.array_list.Managed(LanguageFrontendInfo).init(allocator);
        errdefer infos.deinit();
        for (self.language_frontends.items) |*frontend| {
            try infos.append(.{ .name = frontend.plugin_name, .extensions = frontend.extensions });
        }
        return infos.toOwnedSlice();
    }

    fn languageFrontendNamed(self: *const Runtime, name: []const u8) ?*const LanguageFrontend {
        for (self.language_frontends.items) |*frontend| {
            if (std.mem.eql(u8, frontend.plugin_name, name)) return frontend;
        }
        return null;
    }

    /// The plugin that claimed a top-level command through its
    /// manifest "commands" declaration, or null when the command is
    /// undeclared and dispatch falls back to the legacy scan.
    pub fn commandClaimant(self: *const Runtime, command: []const u8) ?[]const u8 {
        for (self.command_claims.items) |*claim| {
            if (std.mem.eql(u8, claim.command, command)) return claim.plugin_name;
        }
        return null;
    }

    /// Registers a plugin's declared commands in the host command
    /// index. The first claimant keeps a command; a later claim by a
    /// different plugin is skipped and reported as a load diagnostic
    /// naming both plugins, never silently shadowed.
    pub fn registerCommandClaims(self: *Runtime, plugin_name: []const u8, commands: []const []const u8) !void {
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

    pub fn registerLanguageFrontend(self: *Runtime, plugin_name: []const u8, extensions: []const []const u8) !void {
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

    fn noteCommandClaims(self: *Runtime, lib_path: []const u8) !void {
        const dir_path = std.fs.path.dirname(lib_path) orelse return;
        var manifest = parseSapManifest(self.allocator, dir_path) catch return;
        defer manifest.deinit(self.allocator);
        if (manifest.commands.len == 0) return;
        try self.registerCommandClaims(manifest.name, manifest.commands);
    }

    fn noteLanguageFrontend(self: *Runtime, lib_path: []const u8) !void {
        const dir_path = std.fs.path.dirname(lib_path) orelse return;
        var manifest = parseSapManifest(self.allocator, dir_path) catch return;
        defer manifest.deinit(self.allocator);
        if (manifest.kind != .language) return;
        if (manifest.language_extensions.len == 0) return;
        try self.registerLanguageFrontend(manifest.name, manifest.language_extensions);
    }

    fn runtimePolicyDenialForLibrary(self: *Runtime, lib_path: []const u8) !?[]u8 {
        const dir = std.fs.path.dirname(lib_path) orelse return null;
        return try self.runtimePolicyDenialForDirectory(dir);
    }

    fn runtimeArtifactHashMismatch(self: *Runtime, lib_path: []const u8) !?[]u8 {
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

    fn runtimePolicyDenialForDirectory(self: *Runtime, dir_path: []const u8) !?[]u8 {
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

    fn addDiagnostic(self: *Runtime, path: []const u8, reason: []const u8) !void {
        try self.diagnostics.append(.{
            .path = try self.allocator.dupe(u8, path),
            .reason = try self.allocator.dupe(u8, reason),
        });
    }

    fn noteManifestHelpForLibrary(self: *Runtime, lib_path: []const u8) !void {
        const dir_path = std.fs.path.dirname(lib_path) orelse return;
        try self.noteManifestHelpForDirectory(dir_path);
    }

    fn noteManifestHelpForDirectory(self: *Runtime, dir_path: []const u8) !void {
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
};
