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

fn defaultPluginsHome(allocator: std.mem.Allocator) ![]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return try allocator.dupe(u8, "."),
        else => return err,
    };
    defer allocator.free(home);
    return try std.fs.path.join(allocator, &.{ home, ".local", "share", "sa_plugins" });
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
