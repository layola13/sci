const std = @import("std");

pub const abi_version: u32 = 1;
pub const host_version: []const u8 = "sci-0.1";
pub const descriptor_symbol_name: [:0]const u8 = "saasm_plugin_descriptor_v1";
pub const descriptor_fn_symbol_name: [:0]const u8 = "saasm_plugin_descriptor_v1_fn";

pub const SkillSection = struct {
    name: []const u8,
    summary: []const u8,
    items: []const []const u8,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    host_version: ?[]const u8 = host_version,
    log: ?*const fn (ctx: *const anyopaque, level: LogLevel, message_ptr: [*]const u8, message_len: usize) callconv(.c) void = null,
    log_ctx: ?*anyopaque = null,
    json_mode: bool = false,
};

pub const LogLevel = enum(u8) {
    debug,
    info,
    warn,
    err,
};

pub const AbiStatus = enum(u32) {
    ok = 0,
    unknown_command = 1,
    failed = 2,
    version_mismatch = 3,
    invalid_descriptor = 4,
};

pub const StreamWriteAllFn = *const fn (ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32;

pub const HostStream = extern struct {
    ctx: ?*anyopaque,
    write_all: ?StreamWriteAllFn,
};

pub const PluginDescriptor = extern struct {
    abi_version: u32,
    descriptor_size: u32,
    name: [*:0]const u8,
    init: ?*const fn (ctx: *const Context) callconv(.c) u32,
    prebuild: ?*const fn (ctx: *const Context, compile_options: ?*anyopaque) callconv(.c) u32,
    postbuild: ?*const fn (ctx: *const Context) callconv(.c) u32,
    handle_command: ?*const fn (ctx: *const Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: HostStream, stderr: HostStream, out_code: *u8) callconv(.c) u32,
    skills_ptr: [*]const SkillSection,
    skills_len: usize,
};

pub const DescriptorFn = *const fn (out: *PluginDescriptor) callconv(.c) void;

pub const LoadDiagnostic = struct {
    path: []const u8,
    reason: []const u8,

    pub fn deinit(self: *LoadDiagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.reason);
        self.* = undefined;
    }
};

const LoadedPlugin = struct {
    path: []const u8,
    lib: std.DynLib,
    descriptor: PluginDescriptor,

    fn exportsAny(self: *LoadedPlugin, allocator: std.mem.Allocator, symbol_names: []const []const u8) !bool {
        for (symbol_names) |symbol| {
            const symbol_z = try allocator.dupeZ(u8, symbol);
            defer allocator.free(symbol_z);
            if (self.lib.lookup(*anyopaque, symbol_z)) |_| return true;
        }
        return false;
    }

    fn deinit(self: *LoadedPlugin, allocator: std.mem.Allocator) void {
        self.lib.close();
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    plugins: std.ArrayList(LoadedPlugin),
    diagnostics: std.ArrayList(LoadDiagnostic),

    pub fn init(allocator: std.mem.Allocator) Runtime {
        return .{
            .allocator = allocator,
            .plugins = std.ArrayList(LoadedPlugin).init(allocator),
            .diagnostics = std.ArrayList(LoadDiagnostic).init(allocator),
        };
    }

    pub fn initFromEnv(allocator: std.mem.Allocator) !Runtime {
        var runtime = Runtime.init(allocator);
        errdefer runtime.deinit();
        try runtime.loadFromEnv();
        return runtime;
    }

    pub fn initFromPathList(allocator: std.mem.Allocator, path_list: []const u8) !Runtime {
        var runtime = Runtime.init(allocator);
        errdefer runtime.deinit();
        try runtime.loadPathList(path_list);
        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
        for (self.plugins.items) |*plugin| plugin.deinit(self.allocator);
        self.plugins.deinit();
        for (self.diagnostics.items) |*diagnostic| diagnostic.deinit(self.allocator);
        self.diagnostics.deinit();
        self.* = undefined;
    }

    pub fn loadFromEnv(self: *Runtime) !void {
        if (std.process.getEnvVarOwned(self.allocator, "SA_PLUGINS_PATH")) |path_list| {
            defer self.allocator.free(path_list);
            try self.loadPathList(path_list);
            return;
        } else |err| switch (err) {
            error.EnvironmentVariableNotFound => {},
            else => return err,
        }

        const home = std.process.getEnvVarOwned(self.allocator, "SA_PLUGINS_HOME") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => try defaultPluginsHome(self.allocator),
            else => return err,
        };
        defer self.allocator.free(home);

        const installed = try std.fs.path.join(self.allocator, &.{ home, "installed" });
        defer self.allocator.free(installed);
        try self.loadInstalledRoot(installed);
    }

    pub fn loadPathList(self: *Runtime, path_list: []const u8) !void {
        var it = std.mem.splitScalar(u8, path_list, ':');
        while (it.next()) |raw_entry| {
            const entry = std.mem.trim(u8, raw_entry, " \t\r\n");
            if (entry.len == 0) continue;
            try self.loadPath(entry);
        }
    }

    pub fn loadPath(self: *Runtime, path: []const u8) !void {
        var resolved_path: ?[]u8 = null;
        const load_path = if (std.fs.path.isAbsolute(path)) path else blk: {
            const absolute = std.fs.cwd().realpathAlloc(self.allocator, path) catch |err| {
                try self.addDiagnostic(path, @errorName(err));
                return;
            };
            resolved_path = absolute;
            break :blk absolute;
        };
        defer if (resolved_path) |absolute| self.allocator.free(absolute);

        if (std.mem.endsWith(u8, load_path, ".so")) {
            try self.loadLibrary(load_path);
            return;
        }
        try self.loadDirectory(load_path);
    }

    pub fn appendSkills(self: *const Runtime, list: anytype) !void {
        for (self.plugins.items) |loaded| {
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

    pub fn appendLibrariesExportingAny(
        self: *Runtime,
        list: *std.ArrayList([]const u8),
        symbol_names: []const []const u8,
    ) !void {
        if (symbol_names.len == 0) return;
        for (self.plugins.items) |*loaded| {
            if (try loaded.exportsAny(self.allocator, symbol_names)) {
                try list.append(loaded.path);
            }
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

        const c_argv = try dupeZArgs(self.allocator, argv);
        defer freeZArgs(self.allocator, c_argv);

        var ctx = Context{
            .allocator = self.allocator,
            .json_mode = json_mode,
        };

        var stdout_value = stdout;
        var stderr_value = stderr;
        var stdout_ctx = StreamCtx(@TypeOf(stdout_value)){ .writer = &stdout_value };
        var stderr_ctx = StreamCtx(@TypeOf(stderr_value)){ .writer = &stderr_value };
        const stdout_stream = HostStream{ .ctx = &stdout_ctx, .write_all = streamWriteAll(@TypeOf(stdout_value)) };
        const stderr_stream = HostStream{ .ctx = &stderr_ctx, .write_all = streamWriteAll(@TypeOf(stderr_value)) };

        for (self.plugins.items) |loaded| {
            const handle = loaded.descriptor.handle_command orelse continue;
            var out_code: u8 = 0;
            const status_value = handle(&ctx, c_argv.ptr, c_argv.len, stdout_stream, stderr_stream, &out_code);
            const status = abiStatusFromInt(status_value);
            switch (status) {
                .ok => return out_code,
                .unknown_command => continue,
                .failed, .version_mismatch, .invalid_descriptor => {
                    try stderr.print("error[SA-PLUGIN]: plugin {s} failed with {s}\n", .{
                        std.mem.span(loaded.descriptor.name),
                        @tagName(status),
                    });
                    return 1;
                },
            }
        }
        return null;
    }

    fn loadInstalledRoot(self: *Runtime, root_path: []const u8) !void {
        var root = std.fs.openDirAbsolute(root_path, .{ .iterate = true }) catch |err| switch (err) {
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
        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch |err| switch (err) {
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
            if (!std.mem.endsWith(u8, entry.name, ".so")) continue;
            const lib_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
            defer self.allocator.free(lib_path);
            try self.loadLibrary(lib_path);
        }
    }

    fn loadLibrary(self: *Runtime, path: []const u8) !void {
        var lib = std.DynLib.open(path) catch |err| {
            try self.addDiagnostic(path, @errorName(err));
            return;
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

        if (descriptor.init) |init_fn| {
            var ctx = Context{ .allocator = self.allocator };
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
        });
        keep_lib = true;
    }

    fn addDiagnostic(self: *Runtime, path: []const u8, reason: []const u8) !void {
        try self.diagnostics.append(.{
            .path = try self.allocator.dupe(u8, path),
            .reason = try self.allocator.dupe(u8, reason),
        });
    }
};

pub const InstallOptions = struct {
    overwrite: bool = true,
    dev: bool = false,
    review: bool = false,
};

const SapManifest = struct {
    root_dir: []u8,
    sap_path: []u8,
    name: []u8,
    version: []u8,
    abi_plugin: u32,
    artifact_rel: []u8,
    interface_files: []InterfaceFile,
    dependencies: []PluginDependency,
    permission_digest: [32]u8,
    external_urls: [][]u8,
    requires_sandbox: bool,

    fn deinit(self: *SapManifest, allocator: std.mem.Allocator) void {
        allocator.free(self.root_dir);
        allocator.free(self.sap_path);
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.artifact_rel);
        for (self.interface_files) |*iface| iface.deinit(allocator);
        allocator.free(self.interface_files);
        for (self.dependencies) |*dep| dep.deinit(allocator);
        allocator.free(self.dependencies);
        for (self.external_urls) |url| allocator.free(url);
        allocator.free(self.external_urls);
        self.* = undefined;
    }
};

const InterfaceKind = enum {
    sa,
    sai,
    sal,
};

const InterfaceFile = struct {
    kind: InterfaceKind,
    path: []u8,
    sha256: ?[32]u8,

    fn deinit(self: *InterfaceFile, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        self.* = undefined;
    }
};

const PluginDependency = struct {
    name: []u8,
    version: []u8,
    abi: u32,
    optional: bool,
    path: ?[]u8,
    url: ?[]u8,

    fn deinit(self: *PluginDependency, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        if (self.path) |path| allocator.free(path);
        if (self.url) |url| allocator.free(url);
        self.* = undefined;
    }
};

pub fn installFromPath(allocator: std.mem.Allocator, path: []const u8, stdout: anytype, options: InstallOptions) !u8 {
    return try installFromPathInternal(allocator, path, stdout, options, 0, &.{});
}

fn installFromPathInternal(allocator: std.mem.Allocator, path: []const u8, stdout: anytype, options: InstallOptions, depth: u8, ancestors: []const []const u8) anyerror!u8 {
    if (depth > 32) return error.PluginDependencyCycle;
    if (std.mem.endsWith(u8, path, ".so") or std.mem.endsWith(u8, path, ".dll") or std.mem.endsWith(u8, path, ".dylib")) {
        try stdout.writeAll("refusing to install a raw dynamic library; install a plugin project directory or sap.json instead\n");
        return 1;
    }
    if (std.mem.startsWith(u8, path, "github:") or std.mem.indexOf(u8, path, "://") != null) {
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
    const next_ancestors = try allocator.alloc([]const u8, ancestors.len + 1);
    defer allocator.free(next_ancestors);
    @memcpy(next_ancestors[0..ancestors.len], ancestors);
    next_ancestors[ancestors.len] = manifest.sap_path;

    if (options.review) {
        const review_text = try renderPermissionsLock(allocator, manifest, false);
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
    if (manifest.requires_sandbox and !locked_permissions_confirmed and !options.dev and !pluginDevMode(allocator)) {
        const confirmed = try confirmPrivilegedPluginInstall(stdout, manifest);
        if (!confirmed) return 1;
        manual_permissions_confirmed = true;
    }
    const permissions_confirmed = !manifest.requires_sandbox or locked_permissions_confirmed or manual_permissions_confirmed;

    if (try buildPluginProject(allocator, manifest.root_dir, stdout) != 0) return 1;

    const artifact_abs = try std.fs.path.join(allocator, &.{ manifest.root_dir, manifest.artifact_rel });
    defer allocator.free(artifact_abs);
    if (!fileExistsAbsolute(artifact_abs)) {
        try stdout.print("plugin build did not produce declared artifact: {s}\n", .{artifact_abs});
        return 1;
    }

    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const installed_dir = try std.fs.path.join(allocator, &.{ home, "installed", manifest.name, "current" });
    defer allocator.free(installed_dir);
    const version_dir = try std.fs.path.join(allocator, &.{ home, "installed", manifest.name, manifest.version });
    defer allocator.free(version_dir);

    if (options.overwrite and dirExistsAbsolute(installed_dir)) try std.fs.cwd().deleteTree(installed_dir);
    if (options.overwrite and dirExistsAbsolute(version_dir)) try std.fs.cwd().deleteTree(version_dir);
    try std.fs.cwd().makePath(installed_dir);
    try std.fs.cwd().makePath(version_dir);

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

    if (try verifyInterfaceFiles(allocator, manifest) != 0) return 1;
    if (try verifySymbolSmoke(allocator, manifest, artifact_abs, stdout) != 0) return 1;

    if (manifest.interface_files.len > 0) {
        const sa_dir = try std.fs.path.join(allocator, &.{ installed_dir, "sa" });
        defer allocator.free(sa_dir);
        try std.fs.cwd().makePath(sa_dir);
        const version_sa_dir = try std.fs.path.join(allocator, &.{ version_dir, "sa" });
        defer allocator.free(version_sa_dir);
        try std.fs.cwd().makePath(version_sa_dir);
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

    var artifact_file = try std.fs.openFileAbsolute(artifact_abs, .{});
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

    const permissions_lock_text = try renderPermissionsLock(allocator, manifest, permissions_confirmed);
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

fn installPluginDependencies(allocator: std.mem.Allocator, manifest: SapManifest, stdout: anytype, options: InstallOptions, depth: u8, ancestors: []const []const u8) anyerror!u8 {
    for (manifest.dependencies) |dep| {
        const dep_path = dep.path orelse {
            if (dep.optional) continue;
            if (dep.url) |url| {
                const remote_spec = try remoteSpecForDependency(allocator, url, dep.version);
                defer allocator.free(remote_spec);
                const fetched_root = try fetchRemotePluginSource(allocator, remote_spec, stdout, options);
                defer allocator.free(fetched_root);
                var dep_manifest = try parseSapManifest(allocator, fetched_root);
                defer dep_manifest.deinit(allocator);
                if (!std.mem.eql(u8, dep_manifest.name, dep.name)) {
                    try stdout.print("plugin dependency name mismatch: expected {s}, found {s}\n", .{ dep.name, dep_manifest.name });
                    return 1;
                }
                if (dep_manifest.abi_plugin != dep.abi) {
                    try stdout.print("plugin dependency {s} ABI mismatch: expected {d}, found {d}\n", .{ dep.name, dep.abi, dep_manifest.abi_plugin });
                    return 1;
                }
                const code = try installFromPathInternal(allocator, fetched_root, stdout, options, depth + 1, ancestors);
                if (code != 0) return code;
                continue;
            } else {
                try stdout.print("required plugin dependency {s} has no local path; remote dependency resolver is not implemented yet\n", .{dep.name});
            }
            return 1;
        };
        const resolved_path = if (std.fs.path.isAbsolute(dep_path))
            try allocator.dupe(u8, dep_path)
        else
            try std.fs.path.join(allocator, &.{ manifest.root_dir, dep_path });
        defer allocator.free(resolved_path);

        var dep_manifest = try parseSapManifest(allocator, resolved_path);
        defer dep_manifest.deinit(allocator);
        if (!std.mem.eql(u8, dep_manifest.name, dep.name)) {
            try stdout.print("plugin dependency name mismatch: expected {s}, found {s}\n", .{ dep.name, dep_manifest.name });
            return 1;
        }
        if (dep_manifest.abi_plugin != dep.abi) {
            try stdout.print("plugin dependency {s} ABI mismatch: expected {d}, found {d}\n", .{ dep.name, dep.abi, dep_manifest.abi_plugin });
            return 1;
        }

        const code = try installFromPathInternal(allocator, resolved_path, stdout, options, depth + 1, ancestors);
        if (code != 0) return code;
    }
    return 0;
}

pub fn listInstalled(allocator: std.mem.Allocator, stdout: anytype) !u8 {
    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const root_path = try std.fs.path.join(allocator, &.{ home, "installed" });
    defer allocator.free(root_path);
    var root = std.fs.openDirAbsolute(root_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => {
            try stdout.writeAll("plugin\tinstalled_path\n");
            return 0;
        },
        else => return err,
    };
    defer root.close();

    try stdout.writeAll("plugin\tinstalled_path\n");
    var it = root.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        const current = try std.fs.path.join(allocator, &.{ root_path, entry.name, "current" });
        defer allocator.free(current);
        if (dirExistsAbsolute(current)) {
            try stdout.print("{s}\t{s}\n", .{ entry.name, current });
        }
    }
    return 0;
}

fn renderPermissionsLock(allocator: std.mem.Allocator, manifest: SapManifest, confirmed: bool) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const digest_hex = std.fmt.bytesToHex(manifest.permission_digest, .lower);
    const graph_digest = dependencyGraphDigest(manifest);
    const graph_digest_hex = std.fmt.bytesToHex(graph_digest, .lower);
    try out.writer().print(
        \\schema=sa.permissions/1
        \\plugin={s}
        \\version={s}
        \\permissions_sha256={s}
        \\dependency_graph_sha256={s}
        \\requires_confirmation={s}
        \\confirmed={s}
        \\
    , .{
        manifest.name,
        manifest.version,
        digest_hex,
        graph_digest_hex,
        if (manifest.requires_sandbox) "true" else "false",
        if (confirmed) "true" else "false",
    });
    if (manifest.external_urls.len != 0) {
        try out.writer().writeAll("external_urls\n");
        for (manifest.external_urls) |url| try out.writer().print("- {s}\n", .{url});
    }
    if (manifest.dependencies.len != 0) {
        try out.writer().writeAll("plugin_dependencies\n");
        for (manifest.dependencies) |dep| {
            try out.writer().print("- {s} version={s} abi={d} optional={s}", .{
                dep.name,
                dep.version,
                dep.abi,
                if (dep.optional) "true" else "false",
            });
            if (dep.path) |path| try out.writer().print(" path={s}", .{path});
            if (dep.url) |url| try out.writer().print(" url={s}", .{url});
            try out.writer().writeByte('\n');
        }
    }
    return try out.toOwnedSlice();
}

fn dependencyGraphDigest(manifest: SapManifest) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (manifest.dependencies) |dep| {
        hasher.update(dep.name);
        hasher.update("\x00");
        hasher.update(dep.version);
        hasher.update("\x00");
        var abi_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &abi_buf, dep.abi, .little);
        hasher.update(&abi_buf);
        hasher.update(if (dep.optional) "optional" else "required");
        hasher.update("\x00");
        if (dep.path) |path| hasher.update(path);
        hasher.update("\x00");
        if (dep.url) |url| hasher.update(url);
        hasher.update("\x00");
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn permissionsLockMatches(allocator: std.mem.Allocator, manifest: SapManifest) !bool {
    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const lock_path = try std.fs.path.join(allocator, &.{ home, "installed", manifest.name, "current", "permissions.lock" });
    defer allocator.free(lock_path);
    const lock_text = readFileAbsoluteAlloc(allocator, lock_path, 1 << 20) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer allocator.free(lock_text);

    const permission_digest_hex = std.fmt.bytesToHex(manifest.permission_digest, .lower);
    const graph_digest = dependencyGraphDigest(manifest);
    const graph_digest_hex = std.fmt.bytesToHex(graph_digest, .lower);
    return lockHasLine(lock_text, "confirmed=true") and
        lockHasKeyValue(lock_text, "permissions_sha256", permission_digest_hex[0..]) and
        lockHasKeyValue(lock_text, "dependency_graph_sha256", graph_digest_hex[0..]);
}

fn lockHasKeyValue(text: []const u8, key: []const u8, value: []const u8) bool {
    var line_buf: [256]u8 = undefined;
    const expected = std.fmt.bufPrint(&line_buf, "{s}={s}", .{ key, value }) catch return false;
    return lockHasLine(text, expected);
}

fn lockHasLine(text: []const u8, expected: []const u8) bool {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (std.mem.eql(u8, std.mem.trim(u8, line, " \t\r"), expected)) return true;
    }
    return false;
}

const RemotePluginSpec = struct {
    url: []u8,
    ref: ?[]u8,

    fn deinit(self: *RemotePluginSpec, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.ref) |ref| allocator.free(ref);
        self.* = undefined;
    }
};

fn fetchRemotePluginSource(allocator: std.mem.Allocator, spec_text: []const u8, stdout: anytype, options: InstallOptions) ![]u8 {
    var spec = try parseRemotePluginSpec(allocator, spec_text);
    defer spec.deinit(allocator);

    if (spec.ref == null and !options.dev and !pluginDevMode(allocator)) {
        try stdout.print("refusing remote plugin install without fixed #ref: {s}\n", .{spec.url});
        return error.RemotePluginRefRequired;
    }
    if (!options.dev and !pluginDevMode(allocator)) {
        const confirmed = try confirmExternalUrl(stdout, spec.url);
        if (!confirmed) return error.RemotePluginUrlNotConfirmed;
    }

    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const cache_root = try std.fs.path.join(allocator, &.{ home, "cache", "git" });
    defer allocator.free(cache_root);
    try std.fs.cwd().makePath(cache_root);

    const cache_key = remoteCacheKey(spec_text);
    const cache_key_hex = std.fmt.bytesToHex(cache_key, .lower);
    const checkout_dir = try std.fs.path.join(allocator, &.{ cache_root, cache_key_hex[0..] });
    errdefer allocator.free(checkout_dir);
    if (dirExistsAbsolute(checkout_dir)) try std.fs.cwd().deleteTree(checkout_dir);

    const clone_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "clone", "--quiet", spec.url, checkout_dir },
    });
    defer allocator.free(clone_result.stdout);
    defer allocator.free(clone_result.stderr);
    if (!childExitedZero(clone_result.term)) {
        try stdout.print("git clone failed for plugin source {s}\n{s}", .{ spec.url, clone_result.stderr });
        return error.RemotePluginFetchFailed;
    }

    if (spec.ref) |ref| {
        const checkout_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "-C", checkout_dir, "checkout", "--quiet", ref },
        });
        defer allocator.free(checkout_result.stdout);
        defer allocator.free(checkout_result.stderr);
        if (!childExitedZero(checkout_result.term)) {
            try stdout.print("git checkout failed for plugin source {s} ref {s}\n{s}", .{ spec.url, ref, checkout_result.stderr });
            return error.RemotePluginFetchFailed;
        }
    }

    return checkout_dir;
}

fn parseRemotePluginSpec(allocator: std.mem.Allocator, spec_text: []const u8) !RemotePluginSpec {
    const split = splitRemoteRef(spec_text);
    const url_text = split.url;
    const ref_text = split.ref;
    const url = if (std.mem.startsWith(u8, url_text, "github:")) blk: {
        const repo = url_text["github:".len..];
        if (repo.len == 0 or std.mem.indexOf(u8, repo, "..") != null) return error.InvalidRemotePluginSource;
        break :blk try std.fmt.allocPrint(allocator, "https://github.com/{s}.git", .{repo});
    } else blk: {
        if (!allowedExternalUrl(url_text)) return error.InvalidRemotePluginSource;
        break :blk try allocator.dupe(u8, url_text);
    };
    errdefer allocator.free(url);
    const ref = if (ref_text) |text| try allocator.dupe(u8, text) else null;
    return .{ .url = url, .ref = ref };
}

fn splitRemoteRef(text: []const u8) struct { url: []const u8, ref: ?[]const u8 } {
    if (std.mem.lastIndexOfScalar(u8, text, '#')) |idx| {
        const ref = text[idx + 1 ..];
        return .{ .url = text[0..idx], .ref = if (ref.len == 0) null else ref };
    }
    return .{ .url = text, .ref = null };
}

fn remoteSpecForDependency(allocator: std.mem.Allocator, url: []const u8, version: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, url, '#') != null or std.mem.eql(u8, version, "*")) return try allocator.dupe(u8, url);
    return try std.fmt.allocPrint(allocator, "{s}#{s}", .{ url, version });
}

fn remoteCacheKey(text: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(text);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn childExitedZero(term: std.process.Child.Term) bool {
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn confirmExternalUrl(stdout: anytype, url: []const u8) !bool {
    if (!std.posix.isatty(std.io.getStdIn().handle)) {
        try stdout.print("refusing remote plugin URL {s}: manual TTY confirmation is required\n", .{url});
        return false;
    }
    try stdout.print(
        \\SA PLUGIN REMOTE SOURCE REVIEW REQUIRED
        \\url: {s}
        \\Type the exact URL to fetch this plugin source: 
    , .{url});
    var buffer: [1024]u8 = undefined;
    const line = (try std.io.getStdIn().reader().readUntilDelimiterOrEof(&buffer, '\n')) orelse "";
    const answer = std.mem.trim(u8, line, " \t\r\n");
    if (!std.mem.eql(u8, answer, url)) {
        try stdout.writeAll("remote plugin install cancelled\n");
        return false;
    }
    return true;
}

pub fn defaultPluginsHome(allocator: std.mem.Allocator) ![]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return try allocator.dupe(u8, "."),
        else => return err,
    };
    defer allocator.free(home);
    return try std.fs.path.join(allocator, &.{ home, ".local", "share", "sa_plugins" });
}

fn pluginsHome(allocator: std.mem.Allocator) ![]u8 {
    const configured = std.process.getEnvVarOwned(allocator, "SA_PLUGINS_HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return try defaultPluginsHome(allocator),
        else => return err,
    };
    defer allocator.free(configured);
    if (std.fs.path.isAbsolute(configured)) return try allocator.dupe(u8, configured);
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    return try std.fs.path.join(allocator, &.{ cwd, configured });
}

fn parseSapManifest(allocator: std.mem.Allocator, input_path: []const u8) !SapManifest {
    const sap_path = if (std.mem.endsWith(u8, input_path, "sap.json"))
        try absolutePath(allocator, input_path)
    else blk: {
        const root = try absolutePath(allocator, input_path);
        defer allocator.free(root);
        break :blk try std.fs.path.join(allocator, &.{ root, "sap.json" });
    };
    errdefer allocator.free(sap_path);

    const root_dir = try allocator.dupe(u8, std.fs.path.dirname(sap_path) orelse ".");
    errdefer allocator.free(root_dir);

    const source = try readFileAbsoluteAlloc(allocator, sap_path, 1 << 20);
    defer allocator.free(source);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, source, .{});
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |obj| obj,
        else => return error.InvalidSapManifest,
    };

    const schema = try jsonString(object.get("schema") orelse return error.InvalidSapManifest);
    if (!std.mem.eql(u8, schema, "sa.plugin/1")) return error.UnsupportedSapSchema;
    _ = object.get("permissions") orelse return error.PluginPermissionsMissing;
    var permission_info = try validatePermissions(allocator, object.get("permissions").?);
    defer permission_info.deinit(allocator);
    try collectManifestExternalUrls(allocator, object, &permission_info.urls);

    const name = try allocator.dupe(u8, try jsonString(object.get("name") orelse return error.InvalidSapManifest));
    errdefer allocator.free(name);
    const version = try allocator.dupe(u8, try jsonString(object.get("version") orelse return error.InvalidSapManifest));
    errdefer allocator.free(version);
    const abi_plugin = try parseAbiPlugin(object.get("abi"));
    const artifact_rel = try allocator.dupe(u8, try selectArtifactPath(object.get("artifacts") orelse return error.InvalidSapManifest));
    errdefer allocator.free(artifact_rel);
    try validateProjectRelativePath(artifact_rel);
    const interface_files = try collectInterfaceFiles(allocator, object.get("interfaces"));
    errdefer {
        for (interface_files) |*iface| iface.deinit(allocator);
        allocator.free(interface_files);
    }
    const dependencies = try collectPluginDependencies(allocator, object.get("dependencies"));
    errdefer {
        for (dependencies) |*dep| dep.deinit(allocator);
        allocator.free(dependencies);
    }

    return .{
        .root_dir = root_dir,
        .sap_path = sap_path,
        .name = name,
        .version = version,
        .abi_plugin = abi_plugin,
        .artifact_rel = artifact_rel,
        .interface_files = interface_files,
        .dependencies = dependencies,
        .permission_digest = permission_info.digest,
        .external_urls = try permission_info.urls.toOwnedSlice(),
        .requires_sandbox = permission_info.requires_sandbox,
    };
}

fn absolutePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return try allocator.dupe(u8, path);
    return try std.fs.cwd().realpathAlloc(allocator, path);
}

fn jsonString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |s| s,
        else => error.InvalidSapManifest,
    };
}

fn parseAbiPlugin(maybe_value: ?std.json.Value) !u32 {
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

fn selectArtifactPath(value: std.json.Value) ![]const u8 {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidSapManifest,
    };
    if (obj.get("linux-x86_64")) |target_value| {
        return try artifactPathFromValue(target_value);
    }
    var it = obj.iterator();
    if (it.next()) |entry| return try artifactPathFromValue(entry.value_ptr.*);
    return error.InvalidSapManifest;
}

fn artifactPathFromValue(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |s| s,
        .object => |o| try jsonString(o.get("path") orelse return error.InvalidSapManifest),
        else => error.InvalidSapManifest,
    };
}

fn collectInterfaceFiles(allocator: std.mem.Allocator, maybe_value: ?std.json.Value) ![]InterfaceFile {
    var files = std.ArrayList(InterfaceFile).init(allocator);
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

fn validateProjectRelativePath(path: []const u8) !void {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) return error.InvalidSapManifest;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidSapManifest;
    }
}

fn verifyInterfaceFiles(allocator: std.mem.Allocator, manifest: SapManifest) !u8 {
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

fn verifySymbolSmoke(allocator: std.mem.Allocator, manifest: SapManifest, artifact_abs: []const u8, stdout: anytype) !u8 {
    var externs = std.ArrayList([]u8).init(allocator);
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

    var lib = std.DynLib.open(artifact_abs) catch |err| {
        try stdout.print("plugin artifact could not be opened for symbol smoke: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer lib.close();
    for (externs.items) |symbol| {
        const symbol_z = try allocator.dupeZ(u8, symbol);
        defer allocator.free(symbol_z);
        if (lib.lookup(*anyopaque, symbol_z) == null) {
            try stdout.print("plugin artifact missing @extern symbol from .sai: {s}\n", .{symbol});
            return 1;
        }
    }
    return 0;
}

fn collectExternSymbolsFromSai(allocator: std.mem.Allocator, path: []const u8, out: *std.ArrayList([]u8)) !void {
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

fn externSymbolExists(items: []const []u8, symbol: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, symbol)) return true;
    }
    return false;
}

fn collectPluginDependencies(allocator: std.mem.Allocator, maybe_value: ?std.json.Value) ![]PluginDependency {
    var deps = std.ArrayList(PluginDependency).init(allocator);
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
            .path = dep_path,
            .url = dep_url,
        });
    }
    return try deps.toOwnedSlice();
}

fn collectManifestExternalUrls(allocator: std.mem.Allocator, object: std.json.ObjectMap, urls: *std.ArrayList([]u8)) !void {
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

const PermissionInfo = struct {
    requires_sandbox: bool,
    digest: [32]u8,
    urls: std.ArrayList([]u8),

    fn deinit(self: *PermissionInfo, allocator: std.mem.Allocator) void {
        for (self.urls.items) |url| allocator.free(url);
        self.urls.deinit();
        self.* = undefined;
    }
};

fn validatePermissions(allocator: std.mem.Allocator, value: std.json.Value) !PermissionInfo {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.PluginPermissionsMissing,
    };
    try validatePermissionKeys(obj);
    const permissions_json = try std.json.stringifyAlloc(allocator, value, .{});
    defer allocator.free(permissions_json);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(permissions_json);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    var requires_sandbox = false;
    var urls = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (urls.items) |url| allocator.free(url);
        urls.deinit();
    }

    if (obj.get("fs")) |fs_value| switch (fs_value) {
        .array => |arr| {
            if (arr.items.len != 0) requires_sandbox = true;
            for (arr.items) |item| try validateFsPermission(item);
        },
        else => return error.InvalidPluginPermission,
    } else return error.InvalidPluginPermission;
    if (obj.get("net")) |net_value| switch (net_value) {
        .array => |arr| {
            if (arr.items.len != 0) requires_sandbox = true;
            for (arr.items) |item| {
                const net_obj = switch (item) {
                    .object => |o| o,
                    else => return error.InvalidPluginPermission,
                };
                const url = try jsonString(net_obj.get("url") orelse return error.InvalidPluginPermission);
                if (!allowedPermissionUrl(url)) return error.InvalidPluginPermission;
                try urls.append(try allocator.dupe(u8, url));
                if (net_obj.get("methods")) |methods_value| try validateHttpMethods(methods_value);
                try rejectUnknownKeys(net_obj, &.{ "url", "methods" });
            }
        },
        else => return error.InvalidPluginPermission,
    } else return error.InvalidPluginPermission;
    if (obj.get("env")) |env_value| switch (env_value) {
        .array => |arr| {
            if (arr.items.len != 0) requires_sandbox = true;
            for (arr.items) |item| {
                const name = try jsonString(item);
                if (!validEnvPermission(name)) return error.InvalidPluginPermission;
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
        var spawn = false;
        if (process_obj.get("spawn")) |spawn_value| switch (spawn_value) {
            .bool => |spawn_value_bool| {
                if (spawn_value_bool) requires_sandbox = true;
                spawn = spawn_value_bool;
            },
            else => return error.InvalidPluginPermission,
        } else return error.InvalidPluginPermission;
        if (process_obj.get("exec")) |exec_value| switch (exec_value) {
            .array => |arr| {
                if (arr.items.len != 0) requires_sandbox = true;
                if (arr.items.len != 0 and !spawn) return error.InvalidPluginPermission;
                for (arr.items) |item| try validateProcessExec(item);
            },
            else => return error.InvalidPluginPermission,
        } else return error.InvalidPluginPermission;
    } else return error.InvalidPluginPermission;
    return .{
        .requires_sandbox = requires_sandbox,
        .digest = digest,
        .urls = urls,
    };
}

fn validatePermissionKeys(obj: std.json.ObjectMap) !void {
    try rejectUnknownKeys(obj, &.{ "fs", "net", "env", "process" });
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

fn validateFsPermission(value: std.json.Value) !void {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidPluginPermission,
    };
    try rejectUnknownKeys(obj, &.{ "op", "path" });
    const op = try jsonString(obj.get("op") orelse return error.InvalidPluginPermission);
    if (!std.mem.eql(u8, op, "read") and !std.mem.eql(u8, op, "write") and !std.mem.eql(u8, op, "create") and !std.mem.eql(u8, op, "delete") and !std.mem.eql(u8, op, "metadata")) {
        return error.InvalidPluginPermission;
    }
    const path = try jsonString(obj.get("path") orelse return error.InvalidPluginPermission);
    if (!validPermissionPath(path)) return error.InvalidPluginPermission;
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

fn validateHttpMethods(value: std.json.Value) !void {
    const arr = switch (value) {
        .array => |a| a,
        else => return error.InvalidPluginPermission,
    };
    for (arr.items) |item| {
        const method = try jsonString(item);
        if (!std.mem.eql(u8, method, "GET") and
            !std.mem.eql(u8, method, "POST") and
            !std.mem.eql(u8, method, "PUT") and
            !std.mem.eql(u8, method, "PATCH") and
            !std.mem.eql(u8, method, "DELETE") and
            !std.mem.eql(u8, method, "HEAD") and
            !std.mem.eql(u8, method, "OPTIONS"))
        {
            return error.InvalidPluginPermission;
        }
    }
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

fn validateProcessExec(value: std.json.Value) !void {
    const obj = switch (value) {
        .object => |o| o,
        else => return error.InvalidPluginPermission,
    };
    try rejectUnknownKeys(obj, &.{ "path", "args" });
    const path = try jsonString(obj.get("path") orelse return error.InvalidPluginPermission);
    if (!std.fs.path.isAbsolute(path)) return error.InvalidPluginPermission;
    if (obj.get("args")) |args_value| {
        const arr = switch (args_value) {
            .array => |a| a,
            else => return error.InvalidPluginPermission,
        };
        for (arr.items) |item| _ = try jsonString(item);
    }
}

fn allowedPermissionUrl(url: []const u8) bool {
    if (std.mem.startsWith(u8, url, "https://")) return true;
    if (isLoopbackHttpUrl(url, "localhost")) return true;
    if (isLoopbackHttpUrl(url, "127.0.0.1")) return true;
    if (std.mem.startsWith(u8, url, "http://[::1]")) {
        const rest = url["http://[::1]".len..];
        return rest.len == 0 or rest[0] == ':' or rest[0] == '/';
    }
    return false;
}

fn allowedExternalUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "https://") or
        isLoopbackHttpUrl(url, "localhost") or
        isLoopbackHttpUrl(url, "127.0.0.1") or
        std.mem.startsWith(u8, url, "github:");
}

fn isLoopbackHttpUrl(url: []const u8, host: []const u8) bool {
    const prefix = "http://";
    if (!std.mem.startsWith(u8, url, prefix)) return false;
    const rest = url[prefix.len..];
    if (!std.mem.startsWith(u8, rest, host)) return false;
    const suffix = rest[host.len..];
    return suffix.len == 0 or suffix[0] == ':' or suffix[0] == '/';
}

fn pluginDevMode(allocator: std.mem.Allocator) bool {
    const value = std.process.getEnvVarOwned(allocator, "SA_PLUGIN_DEV") catch return false;
    defer allocator.free(value);
    return std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
}

fn confirmPrivilegedPluginInstall(stdout: anytype, manifest: SapManifest) !bool {
    if (!std.posix.isatty(std.io.getStdIn().handle)) {
        try stdout.print("refusing to install privileged plugin {s}: manual TTY confirmation is required\n", .{manifest.name});
        return false;
    }
    try stdout.print(
        \\SA PLUGIN PERMISSION REVIEW REQUIRED
        \\plugin: {s}
        \\version: {s}
        \\permissions_sha256: {s}
        \\
    , .{ manifest.name, manifest.version, std.fmt.bytesToHex(manifest.permission_digest, .lower) });
    if (manifest.external_urls.len != 0) {
        try stdout.writeAll("external URLs:\n");
        for (manifest.external_urls) |url| try stdout.print("- {s}\n", .{url});
    }
    if (manifest.dependencies.len != 0) {
        try stdout.writeAll("plugin dependencies:\n");
        for (manifest.dependencies) |dep| try stdout.print("- {s} version={s} abi={d} optional={s}\n", .{
            dep.name,
            dep.version,
            dep.abi,
            if (dep.optional) "true" else "false",
        });
    }
    try stdout.print("Type the exact plugin name to continue: ", .{});
    var buffer: [256]u8 = undefined;
    const line = (try std.io.getStdIn().reader().readUntilDelimiterOrEof(&buffer, '\n')) orelse "";
    const answer = std.mem.trim(u8, line, " \t\r\n");
    if (!std.mem.eql(u8, answer, manifest.name)) {
        try stdout.writeAll("plugin install cancelled\n");
        return false;
    }
    return true;
}

fn fileExistsAbsolute(path: []const u8) bool {
    var file = std.fs.openFileAbsolute(path, .{}) catch return false;
    file.close();
    return true;
}

fn sha256File(allocator: std.mem.Allocator, path: []const u8) ![32]u8 {
    _ = allocator;
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn fileExistsInProject(allocator: std.mem.Allocator, root_dir: []const u8, rel: []const u8) bool {
    const path = std.fs.path.join(allocator, &.{ root_dir, rel }) catch return false;
    defer allocator.free(path);
    return fileExistsAbsolute(path);
}

fn buildPluginProject(allocator: std.mem.Allocator, root_dir: []const u8, stdout: anytype) !u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "build" },
        .cwd = root_dir,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code == 0) return 0;
            try stdout.print("zig build failed for plugin project {s}\n{s}", .{ root_dir, result.stderr });
            return 1;
        },
        else => {
            try stdout.print("zig build did not exit cleanly for plugin project {s}\n{s}", .{ root_dir, result.stderr });
            return 1;
        },
    }
}

fn dirExistsAbsolute(path: []const u8) bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
    dir.close();
    return true;
}

fn readFileAbsoluteAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, max_bytes);
}

fn copyFileAbsolute(src: []const u8, dst: []const u8) !void {
    try ensureParentDir(dst);
    try std.fs.copyFileAbsolute(src, dst, .{});
}

fn writeFileAbsolute(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| try std.fs.cwd().makePath(dir);
}

fn loadDescriptor(lib: *std.DynLib) ?PluginDescriptor {
    if (lib.lookup(*const PluginDescriptor, descriptor_symbol_name)) |descriptor_ptr| {
        return descriptor_ptr.*;
    }
    if (lib.lookup(DescriptorFn, descriptor_fn_symbol_name)) |descriptor_fn| {
        var descriptor: PluginDescriptor = undefined;
        descriptor_fn(&descriptor);
        return descriptor;
    }
    return null;
}

fn validateDescriptor(descriptor: PluginDescriptor) ?[]const u8 {
    if (descriptor.abi_version != abi_version) return "abi version mismatch";
    if (descriptor.descriptor_size != @as(u32, @intCast(@sizeOf(PluginDescriptor)))) return "descriptor size mismatch";
    if (std.mem.span(descriptor.name).len == 0) return "empty plugin name";
    return null;
}

fn abiStatusFromInt(value: u32) AbiStatus {
    return switch (value) {
        @intFromEnum(AbiStatus.ok) => .ok,
        @intFromEnum(AbiStatus.unknown_command) => .unknown_command,
        @intFromEnum(AbiStatus.failed) => .failed,
        @intFromEnum(AbiStatus.version_mismatch) => .version_mismatch,
        @intFromEnum(AbiStatus.invalid_descriptor) => .invalid_descriptor,
        else => .failed,
    };
}

fn dupeZArgs(allocator: std.mem.Allocator, argv: []const []const u8) ![][*:0]const u8 {
    var out = try allocator.alloc([*:0]const u8, argv.len);
    errdefer allocator.free(out);
    var copied: usize = 0;
    errdefer {
        for (out[0..copied]) |arg| allocator.free(std.mem.sliceTo(arg, 0));
    }
    for (argv, 0..) |arg, idx| {
        out[idx] = try allocator.dupeZ(u8, arg);
        copied += 1;
    }
    return out;
}

fn freeZArgs(allocator: std.mem.Allocator, argv: [][*:0]const u8) void {
    for (argv) |arg| allocator.free(std.mem.sliceTo(arg, 0));
    allocator.free(argv);
}

fn StreamCtx(comptime Writer: type) type {
    return struct {
        writer: *Writer,
    };
}

fn streamWriteAll(comptime Writer: type) StreamWriteAllFn {
    return struct {
        fn write(ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32 {
            const stream_ctx = @as(*StreamCtx(Writer), @ptrCast(@alignCast(ctx orelse return @intFromEnum(AbiStatus.failed))));
            stream_ctx.writer.writeAll(bytes[0..len]) catch return @intFromEnum(AbiStatus.failed);
            return @intFromEnum(AbiStatus.ok);
        }
    }.write;
}
