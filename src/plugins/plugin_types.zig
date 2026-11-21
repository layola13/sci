const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

const Context = @import("broker.zig").Context;
const RuntimeAuthorizationInput = @import("broker.zig").RuntimeAuthorizationInput;
const SapManifest = @import("install.zig").SapManifest;
const SkillSection = @import("broker.zig").SkillSection;
const abi_version = @import("broker.zig").abi_version;
const appendOwnedStrings = @import("permission.zig").appendOwnedStrings;
const freeOwnedStringList = @import("permission.zig").freeOwnedStringList;
const httpMethodBit = @import("permission.zig").httpMethodBit;
const matchesAnyEnvPattern = @import("permission.zig").matchesAnyEnvPattern;
const matchesExecutablePermissionPath = @import("permission.zig").matchesExecutablePermissionPath;
const matchesPathPermissionPattern = @import("permission.zig").matchesPathPermissionPattern;
const matchesUrlPermissionPattern = @import("permission.zig").matchesUrlPermissionPattern;
const processArgsMatch = @import("permission.zig").processArgsMatch;

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
pub const LoadedPlugin = struct {
    path: []const u8,
    lib: dynlib.DynLib,
    descriptor: PluginDescriptor,
    permission_policy: RuntimePermissionPolicy = .{},

    pub fn exportsAny(self: *LoadedPlugin, allocator: std.mem.Allocator, symbol_names: []const []const u8) !bool {
        for (symbol_names) |symbol| {
            const symbol_z = try allocator.dupeSentinel(u8, symbol, 0);
            defer allocator.free(symbol_z);
            if (self.lib.lookup(*anyopaque, symbol_z)) |_| return true;
        }
        return false;
    }

    pub fn exportsAll(self: *LoadedPlugin, allocator: std.mem.Allocator, symbol_names: []const []u8) !bool {
        for (symbol_names) |symbol| {
            const symbol_z = try allocator.dupeSentinel(u8, symbol, 0);
            defer allocator.free(symbol_z);
            if (self.lib.lookup(*anyopaque, symbol_z) == null) return false;
        }
        return true;
    }

    pub fn deinit(self: *LoadedPlugin, allocator: std.mem.Allocator) void {
        self.lib.close();
        allocator.free(self.path);
        self.permission_policy.deinit(allocator);
        self.* = undefined;
    }
};
pub const ManifestHelpEntry = struct {
    name: []u8,
    sap_path: []u8,

    pub fn deinit(self: *ManifestHelpEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.sap_path);
        self.* = undefined;
    }
};
/// A loaded plugin whose manifest declares kind=language, together with
/// the file extensions it owns (sala 05_plugins/20_system_redesign). The
/// host resolves source files to frontends through this registry instead
/// of a plugin command namespace.
/// One entry of the host command index: a top-level command name a
/// plugin declared in its manifest ("commands") and the plugin that
/// claimed it first. Declared commands dispatch straight to their
/// claimant instead of the legacy offer-to-all scan.
pub const CommandClaim = struct {
    command: []u8,
    plugin_name: []u8,

    pub fn deinit(self: *CommandClaim, allocator: std.mem.Allocator) void {
        allocator.free(self.command);
        allocator.free(self.plugin_name);
        self.* = undefined;
    }
};
pub const LanguageFrontend = struct {
    plugin_name: []u8,
    extensions: [][]u8,

    pub fn deinit(self: *LanguageFrontend, allocator: std.mem.Allocator) void {
        allocator.free(self.plugin_name);
        for (self.extensions) |ext| allocator.free(ext);
        allocator.free(self.extensions);
        self.* = undefined;
    }
};
pub const FsPermissionOp = enum {
    read,
    write,
    create,
    delete,
    metadata,
};
pub const FsPermission = struct {
    op: FsPermissionOp,
    path: []u8,

    pub fn deinit(self: *FsPermission, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        self.* = undefined;
    }
};
pub const HttpMethodMask = struct {
    bits: u16 = 0,

    pub fn default() HttpMethodMask {
        var mask = HttpMethodMask{};
        mask.insert(.GET);
        return mask;
    }

    pub fn insert(self: *HttpMethodMask, method: std.http.Method) void {
        self.bits |= httpMethodBit(method) orelse 0;
    }

    pub fn contains(self: HttpMethodMask, method: std.http.Method) bool {
        const bit = httpMethodBit(method) orelse return false;
        return (self.bits & bit) != 0;
    }
};
pub const NetPermission = struct {
    url: []u8,
    methods: HttpMethodMask,

    pub fn deinit(self: *NetPermission, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        self.* = undefined;
    }
};
pub const ProcessExecPermission = struct {
    path: []u8,
    args: [][]u8,

    pub fn deinit(self: *ProcessExecPermission, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        for (self.args) |arg| allocator.free(arg);
        allocator.free(self.args);
        self.* = undefined;
    }
};
pub const RuntimePermissionPolicy = struct {
    has_manifest: bool = false,
    requires_sandbox: bool = false,
    env_permissions: std.ArrayList([]u8) = .empty,
    fs_permissions: std.ArrayList(FsPermission) = .empty,
    net_permissions: std.ArrayList(NetPermission) = .empty,
    process_spawn: bool = false,
    process_exec_permissions: std.ArrayList(ProcessExecPermission) = .empty,

    pub fn initFromManifest(allocator: std.mem.Allocator, manifest: SapManifest) !RuntimePermissionPolicy {
        var policy = RuntimePermissionPolicy{
            .has_manifest = true,
            .requires_sandbox = manifest.requires_sandbox,
        };
        errdefer policy.deinit(allocator);
        for (manifest.env_permissions) |entry| {
            try policy.env_permissions.append(allocator, try allocator.dupe(u8, entry));
        }
        for (manifest.fs_permissions) |entry| {
            try policy.fs_permissions.append(allocator, .{
                .op = entry.op,
                .path = try allocator.dupe(u8, entry.path),
            });
        }
        for (manifest.net_permissions) |entry| {
            try policy.net_permissions.append(allocator, .{
                .url = try allocator.dupe(u8, entry.url),
                .methods = entry.methods,
            });
        }
        policy.process_spawn = manifest.process_spawn;
        for (manifest.process_exec_permissions) |entry| {
            var owned_args = std.array_list.Managed([]u8).init(allocator);
            errdefer {
                for (owned_args.items) |arg| allocator.free(arg);
                owned_args.deinit();
            }
            for (entry.args) |arg| try owned_args.append(try allocator.dupe(u8, arg));
            try policy.process_exec_permissions.append(allocator, .{
                .path = try allocator.dupe(u8, entry.path),
                .args = try owned_args.toOwnedSlice(),
            });
        }
        return policy;
    }

    pub fn deinit(self: *RuntimePermissionPolicy, allocator: std.mem.Allocator) void {
        for (self.env_permissions.items) |entry| allocator.free(entry);
        self.env_permissions.deinit(allocator);
        for (self.fs_permissions.items) |*entry| entry.deinit(allocator);
        self.fs_permissions.deinit(allocator);
        for (self.net_permissions.items) |*entry| entry.deinit(allocator);
        self.net_permissions.deinit(allocator);
        for (self.process_exec_permissions.items) |*entry| entry.deinit(allocator);
        self.process_exec_permissions.deinit(allocator);
        self.* = undefined;
    }

    pub fn allowsEnv(self: *const RuntimePermissionPolicy, name: []const u8) bool {
        return matchesAnyEnvPattern(self.env_permissions.items, name);
    }

    pub fn allowsFs(self: *const RuntimePermissionPolicy, allocator: std.mem.Allocator, project_root: []const u8, op: FsPermissionOp, abs_path: []const u8) !bool {
        for (self.fs_permissions.items) |entry| {
            if (entry.op != op) continue;
            if (try matchesPathPermissionPattern(allocator, entry.path, project_root, abs_path)) return true;
        }
        return false;
    }

    pub fn allowsNet(self: *const RuntimePermissionPolicy, allocator: std.mem.Allocator, method: std.http.Method, url: []const u8) !bool {
        for (self.net_permissions.items) |entry| {
            if (!entry.methods.contains(method)) continue;
            if (try matchesUrlPermissionPattern(allocator, entry.url, url)) return true;
        }
        return false;
    }

    pub fn allowsProcessSpawn(self: *const RuntimePermissionPolicy, allocator: std.mem.Allocator, abs_path: []const u8, argv: []const []const u8) !bool {
        if (!self.process_spawn) return false;
        for (self.process_exec_permissions.items) |entry| {
            if (try matchesExecutablePermissionPath(allocator, entry.path, abs_path) and processArgsMatch(entry.args, argv)) return true;
        }
        return false;
    }
};
pub const RuntimeHostAuthorization = struct {
    dev_mode: bool = false,
    project_root: ?[]u8 = null,
    allow_env_declared: bool = false,
    allow_read_declared: bool = false,
    allow_write_declared: bool = false,
    allow_net_declared: bool = false,
    allow_run_declared: bool = false,
    allow_env: std.ArrayList([]u8) = .empty,
    allow_read: std.ArrayList([]u8) = .empty,
    allow_write: std.ArrayList([]u8) = .empty,
    allow_net: std.ArrayList([]u8) = .empty,
    allow_run: std.ArrayList([]u8) = .empty,

    pub fn init(allocator: std.mem.Allocator, input: RuntimeAuthorizationInput) !RuntimeHostAuthorization {
        var auth = RuntimeHostAuthorization{
            .dev_mode = input.dev_mode,
            .allow_env_declared = input.allow_env_declared,
            .allow_read_declared = input.allow_read_declared,
            .allow_write_declared = input.allow_write_declared,
            .allow_net_declared = input.allow_net_declared,
            .allow_run_declared = input.allow_run_declared,
        };
        errdefer auth.deinit(allocator);
        auth.project_root = if (input.project_root) |root|
            try allocator.dupe(u8, root)
        else
            try sio.cwd().realpathAlloc(allocator, ".");
        try appendOwnedStrings(allocator, &auth.allow_env, input.allow_env);
        try appendOwnedStrings(allocator, &auth.allow_read, input.allow_read);
        try appendOwnedStrings(allocator, &auth.allow_write, input.allow_write);
        try appendOwnedStrings(allocator, &auth.allow_net, input.allow_net);
        try appendOwnedStrings(allocator, &auth.allow_run, input.allow_run);
        return auth;
    }

    pub fn deinit(self: *RuntimeHostAuthorization, allocator: std.mem.Allocator) void {
        if (self.project_root) |root| allocator.free(root);
        freeOwnedStringList(allocator, &self.allow_env);
        freeOwnedStringList(allocator, &self.allow_read);
        freeOwnedStringList(allocator, &self.allow_write);
        freeOwnedStringList(allocator, &self.allow_net);
        freeOwnedStringList(allocator, &self.allow_run);
        self.* = undefined;
    }

    pub fn effectiveProjectRoot(self: *const RuntimeHostAuthorization) []const u8 {
        return self.project_root orelse ".";
    }

    pub fn allowsEnv(self: *const RuntimeHostAuthorization, name: []const u8) bool {
        if (self.dev_mode) return true;
        if (self.allow_env_declared) return true;
        return matchesAnyEnvPattern(self.allow_env.items, name);
    }

    pub fn allowsRead(self: *const RuntimeHostAuthorization, allocator: std.mem.Allocator, abs_path: []const u8) !bool {
        if (self.dev_mode) return true;
        if (self.allow_read_declared) return true;
        const project_root = self.effectiveProjectRoot();
        for (self.allow_read.items) |entry| {
            if (try matchesPathPermissionPattern(allocator, entry, project_root, abs_path)) return true;
        }
        return false;
    }

    pub fn allowsNet(self: *const RuntimeHostAuthorization, allocator: std.mem.Allocator, url: []const u8) !bool {
        if (self.dev_mode) return true;
        if (self.allow_net_declared) return true;
        for (self.allow_net.items) |entry| {
            if (try matchesUrlPermissionPattern(allocator, entry, url)) return true;
        }
        return false;
    }

    pub fn allowsRun(self: *const RuntimeHostAuthorization, allocator: std.mem.Allocator, abs_path: []const u8) !bool {
        if (self.dev_mode) return true;
        if (self.allow_run_declared) return true;
        for (self.allow_run.items) |entry| {
            if (try matchesExecutablePermissionPath(allocator, entry, abs_path)) return true;
        }
        return false;
    }
};
pub const RuntimeBroker = struct {
    allocator: std.mem.Allocator,
    policy: *const RuntimePermissionPolicy,
    authorization: *const RuntimeHostAuthorization,
};
pub const max_net_probe_bytes: usize = 4 * 1024 * 1024;
pub const max_process_probe_bytes: usize = 4 * 1024 * 1024;
// ---------------------------------------------------------------------
// Frontend compile cache (host cache service). A language frontend's
// compile artifacts are stored under the host cache root, keyed by
// frontend-supplied opaque key material, and served back only while
// every file in the recorded dependency closure still hashes to its
// recorded value (Wyhash of contents + length) — the same freshness rule
// the SLA plugin's local gate implements for standalone use. These ops
// are host-internal storage for a plugin's own compile artifacts: they
// do not consult the plugin permission policy (namespaces separate
// frontends, and the artifacts are compiled text, not secrets).
// Namespace validation and hashed key directory names keep every path
// traversal-free.

pub const max_frontend_cache_manifest_bytes: usize = 64 * 1024 * 1024;
pub const max_frontend_cache_dep_bytes: usize = 256 * 1024 * 1024;
pub const max_frontend_cache_artifact_bytes: usize = 1024 * 1024 * 1024;
pub const frontend_cache_manifest_version: u32 = 1;
pub const FrontendCacheDep = struct {
    path: []const u8,
    len: u64,
    hash: u64,
};
pub const FrontendCacheManifest = struct {
    version: u32,
    deps: []const FrontendCacheDep,
};
