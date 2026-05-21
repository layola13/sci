const std = @import("std");
const plugin = @import("plugin");

const default_plugin_dir = "zig-out/lib";

const LoadedPlugin = struct {
    lib: std.DynLib,
    descriptor: plugin.PluginDescriptor,

    fn deinit(self: *LoadedPlugin) void {
        self.lib.close();
        self.* = undefined;
    }
};

pub const PluginCatalog = struct {
    allocator: std.mem.Allocator,
    plugins: []LoadedPlugin,

    pub fn deinit(self: *PluginCatalog) void {
        for (self.plugins) |*item| item.deinit();
        self.allocator.free(self.plugins);
        self.* = undefined;
    }
};

var cached_skill_catalog: ?PluginCatalog = null;
var cached_skill_catalog_mutex: std.Thread.Mutex = .{};

fn pluginDirPath(allocator: std.mem.Allocator) ![]u8 {
    return std.process.getEnvVarOwned(allocator, "SAASM_PLUGIN_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try allocator.dupe(u8, default_plugin_dir),
        else => return err,
    };
}

fn collectPluginPaths(allocator: std.mem.Allocator, dir: std.fs.Dir) ![]const []u8 {
    var paths = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (paths.items) |item| allocator.free(item);
        paths.deinit();
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".so")) continue;
        if (!std.mem.startsWith(u8, entry.name, "libsaasm-")) continue;
        try paths.append(try allocator.dupe(u8, entry.name));
    }

    std.mem.sort([]u8, paths.items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    return try paths.toOwnedSlice();
}

fn loadDescriptor(lib: *std.DynLib) !plugin.PluginDescriptor {
    const descriptor_slot = lib.lookup(*const *const plugin.PluginDescriptor, plugin.descriptor_symbol_name) orelse return error.SymbolNotFound;
    return descriptor_slot.*.*;
}

fn validateDescriptor(descriptor: plugin.PluginDescriptor) !void {
    const expected_size: u32 = @intCast(@sizeOf(plugin.PluginDescriptor));
    if (descriptor.abi_version != plugin.abi_version) return error.VersionMismatch;
    if (descriptor.descriptor_size != expected_size) return error.InvalidDescriptor;
    if (descriptor.name[0] == 0) return error.InvalidDescriptor;
}

fn readDescriptorFromSlot(slot: *const anyopaque) plugin.PluginDescriptor {
    const ptr_slot = @as(*const *const plugin.PluginDescriptor, @ptrCast(@alignCast(slot)));
    return ptr_slot.*.*;
}

fn readDescriptorDirect(slot: *const anyopaque) plugin.PluginDescriptor {
    const descriptor_ptr = @as(*const plugin.PluginDescriptor, @ptrCast(@alignCast(slot)));
    return descriptor_ptr.*;
}

fn loadDescriptorValue(lib: *std.DynLib) !plugin.PluginDescriptor {
    const descriptor_slot = lib.lookup(*const *const plugin.PluginDescriptor, plugin.descriptor_symbol_name) orelse return error.SymbolNotFound;
    const descriptor_value = descriptor_slot.*.*;
    if (validateDescriptor(descriptor_value)) |_| return descriptor_value else |_| {}

    const direct_slot = lib.lookup(*const plugin.PluginDescriptor, plugin.descriptor_symbol_name) orelse return error.SymbolNotFound;
    const direct_value = direct_slot.*;
    try validateDescriptor(direct_value);
    return direct_value;
}

fn loadPluginFromPath(path: []const u8) !LoadedPlugin {
    var lib = try std.DynLib.open(path);
    errdefer lib.close();

    const descriptor = try loadDescriptorValue(&lib);
    try validateDescriptor(descriptor);

    return .{
        .lib = lib,
        .descriptor = descriptor,
    };
}

fn describePluginLoadError(err: anyerror) []const u8 {
    return switch (err) {
        error.SymbolNotFound => "missing descriptor symbol",
        error.VersionMismatch => "abi version mismatch",
        error.InvalidDescriptor => "invalid descriptor",
        error.NotElfFile => "not an elf shared library",
        error.BadPathName => "bad plugin path name",
        else => "plugin load failed",
    };
}

pub fn loadCatalogFromDir(allocator: std.mem.Allocator, dir_path: []const u8) !PluginCatalog {
    const abs_dir_path = try std.fs.cwd().realpathAlloc(allocator, dir_path);
    defer allocator.free(abs_dir_path);

    var dir = std.fs.cwd().openDir(abs_dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return .{ .allocator = allocator, .plugins = try allocator.alloc(LoadedPlugin, 0) },
        else => return err,
    };
    defer dir.close();

    const names = try collectPluginPaths(allocator, dir);
    defer {
        for (names) |name| allocator.free(name);
        allocator.free(names);
    }

    var loaded = std.ArrayList(LoadedPlugin).init(allocator);
    errdefer {
        for (loaded.items) |*item| item.deinit();
        loaded.deinit();
    }

    for (names) |name| {
        const lib_path = try std.fs.path.join(allocator, &.{ abs_dir_path, name });
        defer allocator.free(lib_path);

        const item = loadPluginFromPath(lib_path) catch |err| switch (err) {
            error.SymbolNotFound, error.VersionMismatch, error.InvalidDescriptor, error.NotElfFile, error.BadPathName => {
                std.debug.print("skip plugin {s}: {s} ({})\n", .{ lib_path, describePluginLoadError(err), err });
                continue;
            },
            else => return err,
        };
        try loaded.append(item);
    }

    return .{
        .allocator = allocator,
        .plugins = try loaded.toOwnedSlice(),
    };
}

pub fn loadCatalog(allocator: std.mem.Allocator) !PluginCatalog {
    const dir_path = try pluginDirPath(allocator);
    defer allocator.free(dir_path);
    return try loadCatalogFromDir(allocator, dir_path);
}

fn asArgs(argv: []const []const u8, allocator: std.mem.Allocator) ![]const [*:0]const u8 {
    var out = try allocator.alloc([*:0]const u8, argv.len);
    errdefer allocator.free(out);
    for (argv, 0..) |arg, idx| {
        out[idx] = try allocator.dupeZ(u8, arg);
    }
    return out;
}

fn freeArgs(allocator: std.mem.Allocator, argv: []const [*:0]const u8) void {
    for (argv) |arg| allocator.free(std.mem.sliceTo(arg, 0));
    allocator.free(argv);
}

const StreamCtx = struct {
    writer: std.io.AnyWriter,
};

fn streamWriteAll(ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32 {
    const self = @as(*StreamCtx, @ptrCast(@alignCast(ctx.?)));
    self.writer.writeAll(bytes[0..len]) catch return @intFromEnum(plugin.AbiStatus.failed);
    return @intFromEnum(plugin.AbiStatus.ok);
}

fn makeHostStream(ctx: *StreamCtx) plugin.HostStream {
    return .{ .ctx = ctx, .write_all = streamWriteAll };
}

fn callHandleCommand(
    descriptor: plugin.PluginDescriptor,
    ctx: *const plugin.Context,
    argv: []const []const u8,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
    allocator: std.mem.Allocator,
) !?u8 {
    const handler = descriptor.handle_command orelse return null;
    const c_argv = try asArgs(argv, allocator);
    defer freeArgs(allocator, c_argv);

    var code: u8 = 0;
    var stdout_ctx = StreamCtx{ .writer = stdout };
    var stderr_ctx = StreamCtx{ .writer = stderr };
    const status = handler(ctx, c_argv.ptr, c_argv.len, makeHostStream(&stdout_ctx), makeHostStream(&stderr_ctx), &code);
    switch (@as(plugin.AbiStatus, @enumFromInt(status))) {
        .ok => return code,
        .unknown_command => return null,
        else => return error.PluginFailed,
    }
}

fn runHookFromCatalog(
    catalog: *const PluginCatalog,
    hook: enum { init, prebuild, postbuild },
    ctx: *const plugin.Context,
    compile_options: ?*anyopaque,
) !void {
    for (catalog.plugins) |item| {
        switch (hook) {
            .init => if (item.descriptor.init) |fn_ptr| {
                if (fn_ptr(ctx) != @intFromEnum(plugin.AbiStatus.ok)) return error.PluginFailed;
            },
            .prebuild => if (item.descriptor.prebuild) |fn_ptr| {
                if (fn_ptr(ctx, compile_options) != @intFromEnum(plugin.AbiStatus.ok)) return error.PluginFailed;
            },
            .postbuild => if (item.descriptor.postbuild) |fn_ptr| {
                if (fn_ptr(ctx) != @intFromEnum(plugin.AbiStatus.ok)) return error.PluginFailed;
            },
        }
    }
}

fn collectSkillsFromCatalog(allocator: std.mem.Allocator, catalog: *const PluginCatalog) ![]plugin.SkillSection {
    var sections = std.ArrayList(plugin.SkillSection).init(allocator);
    errdefer sections.deinit();

    for (catalog.plugins) |item| {
        const skills = item.descriptor.skills_ptr[0..item.descriptor.skills_len];
        try sections.appendSlice(skills);
    }

    return try sections.toOwnedSlice();
}

fn skillCatalog() !*PluginCatalog {
    cached_skill_catalog_mutex.lock();
    defer cached_skill_catalog_mutex.unlock();
    if (cached_skill_catalog == null) {
        cached_skill_catalog = try loadCatalog(std.heap.page_allocator);
    }
    return &cached_skill_catalog.?;
}

pub fn handleCommandFrom(_: []const plugin.Plugin, ctx: *const plugin.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) !?u8 {
    const catalog = try loadCatalog(ctx.allocator);
    defer catalog.deinit();

    for (catalog.plugins) |item| {
        if (try callHandleCommand(item.descriptor, ctx, argv, stdout, stderr, ctx.allocator)) |code| return code;
    }
    return null;
}

pub fn handleCommand(ctx: *const plugin.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) !?u8 {
    return try handleCommandFrom(&.{}, ctx, argv, stdout, stderr);
}

pub fn runInitHooksFrom(_: []const plugin.Plugin, ctx: *const plugin.Context) !void {
    const catalog = try loadCatalog(ctx.allocator);
    defer catalog.deinit();
    try runHookFromCatalog(&catalog, .init, ctx, null);
}

pub fn runInitHooks(ctx: *const plugin.Context) !void {
    try runInitHooksFrom(&.{}, ctx);
}

pub fn runPrebuildHooksFrom(_: []const plugin.Plugin, ctx: *const plugin.Context, compile_options: *anyopaque) !void {
    const catalog = try loadCatalog(ctx.allocator);
    defer catalog.deinit();
    try runHookFromCatalog(&catalog, .prebuild, ctx, compile_options);
}

pub fn runPrebuildHooks(ctx: *const plugin.Context, compile_options: *anyopaque) !void {
    try runPrebuildHooksFrom(&.{}, ctx, compile_options);
}

pub fn runPostbuildHooksFrom(_: []const plugin.Plugin, ctx: *const plugin.Context) !void {
    const catalog = try loadCatalog(ctx.allocator);
    defer catalog.deinit();
    try runHookFromCatalog(&catalog, .postbuild, ctx, null);
}

pub fn runPostbuildHooks(ctx: *const plugin.Context) !void {
    try runPostbuildHooksFrom(&.{}, ctx);
}

pub fn collectSkillsFrom(allocator: std.mem.Allocator, _: []const u8) ![]plugin.SkillSection {
    const catalog = try skillCatalog();
    return try collectSkillsFromCatalog(allocator, catalog);
}

pub fn collectSkills(allocator: std.mem.Allocator) ![]plugin.SkillSection {
    return try collectSkillsFrom(allocator, &.{});
}

fn writeSource(path: []const u8, source: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| try std.fs.cwd().makePath(dir);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn writeFixturePluginApi(path: []const u8) !void {
    const target = "/home/vscode/projects/sci/src/plugin_api.zig";
    std.fs.cwd().deleteFile(path) catch {};
    try std.fs.cwd().symLink(target, path, .{});
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn expectSuccess(result: std.process.Child.RunResult) !void {
    if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
    switch (result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

fn fixtureSource(allocator: std.mem.Allocator, status_code: u8, message: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    try out.appendSlice(
        \\const std = @import("std");
        \\const plugin_api = @import("plugin_api.zig");
        \\
        \\const skills = [_]plugin_api.SkillSection{
        \\    .{
        \\        .name = "fixture",
        \\        .summary = "hot-load regression fixture",
        \\        .items = &.{ "fixture command", "reload fixture" },
        \\    },
        \\};
        \\
        \\fn writeAll(stream: plugin_api.HostStream, bytes: []const u8) u32 {
        \\    const writer = stream.write_all orelse return @intFromEnum(plugin_api.AbiStatus.failed);
        \\    return writer(stream.ctx, bytes.ptr, bytes.len);
        \\}
        \\
        \\fn runCommand(ctx: *const plugin_api.Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: plugin_api.HostStream, stderr: plugin_api.HostStream, out_code: *u8) callconv(.c) u32 {
        \\    _ = ctx;
        \\    _ = stderr;
        \\    if (argv_len < 2) return @intFromEnum(plugin_api.AbiStatus.unknown_command);
        \\    if (!std.mem.eql(u8, std.mem.span(argv[1]), "fixture")) return @intFromEnum(plugin_api.AbiStatus.unknown_command);
        \\    out_code.* = 
    );
    try out.writer().print("{d}", .{status_code});
    try out.appendSlice(
        \\;
        \\    if (writeAll(stdout, 
    );
    try out.writer().writeByte('"');
    try out.writer().print("{}", .{std.zig.fmtEscapes(message)});
    try out.writer().writeByte('"');
    try out.appendSlice(
        \\) != @intFromEnum(plugin_api.AbiStatus.ok)) return @intFromEnum(plugin_api.AbiStatus.failed);
        \\    return @intFromEnum(plugin_api.AbiStatus.ok);
        \\}
        \\
        \\const descriptor = plugin_api.PluginDescriptor{
        \\    .abi_version = 
    );
    try out.writer().print("{d}", .{plugin.abi_version});
    try out.appendSlice(
        \\,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
        \\    .name = "fixture",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = runCommand,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\
        \\pub export const saasm_plugin_descriptor_v1: *const plugin_api.PluginDescriptor = &descriptor;
        \\
    );
    return try out.toOwnedSlice();
}

fn expectFixtureDescriptor(descriptor: plugin.PluginDescriptor) !void {
    try std.testing.expectEqual(plugin.abi_version, descriptor.abi_version);
    try std.testing.expectEqual(@as(u32, @intCast(@sizeOf(plugin.PluginDescriptor))), descriptor.descriptor_size);
    try std.testing.expect(descriptor.skills_len > 0);
}

fn expectLoadedDescriptor(descriptor: plugin.PluginDescriptor, expected_name: []const u8) !void {
    try std.testing.expectEqual(plugin.abi_version, descriptor.abi_version);
    try std.testing.expectEqual(@as(u32, @intCast(@sizeOf(plugin.PluginDescriptor))), descriptor.descriptor_size);
    try std.testing.expectEqualStrings(expected_name, std.mem.span(descriptor.name));
    try std.testing.expect(descriptor.skills_len > 0);
}

fn descriptorNameSet(allocator: std.mem.Allocator, catalog: *const PluginCatalog) ![]const []u8 {
    var names = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (names.items) |item| allocator.free(item);
        names.deinit();
    }
    for (catalog.plugins) |item| {
        try names.append(try allocator.dupe(u8, std.mem.span(item.descriptor.name)));
    }
    std.mem.sort([]u8, names.items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);
    return try names.toOwnedSlice();
}

fn probeFixtureDescriptor(path: []const u8) !plugin.PluginDescriptor {
    var lib = try std.DynLib.open(path);
    defer lib.close();

    return try loadDescriptorValue(&lib);
}
