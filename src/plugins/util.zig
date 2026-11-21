const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

const AbiStatus = @import("broker.zig").AbiStatus;
const AssetFile = @import("install.zig").AssetFile;
const DescriptorFn = @import("plugin_types.zig").DescriptorFn;
const FsPermission = @import("plugin_types.zig").FsPermission;
const InterfaceFile = @import("install.zig").InterfaceFile;
const NativeLinkEntry = @import("install.zig").NativeLinkEntry;
const NativeLinkKind = @import("install.zig").NativeLinkKind;
const NetPermission = @import("plugin_types.zig").NetPermission;
const PermissionInfo = @import("permissions.zig").PermissionInfo;
const PluginDependency = @import("install.zig").PluginDependency;
const PluginDescriptor = @import("plugin_types.zig").PluginDescriptor;
const ProcessExecPermission = @import("plugin_types.zig").ProcessExecPermission;
const SapManifest = @import("install.zig").SapManifest;
const StdinLineReader = @import("fetch.zig").StdinLineReader;
const StreamWriteAllFn = @import("plugin_types.zig").StreamWriteAllFn;
const abi_version = @import("broker.zig").abi_version;
const allowedPermissionUrl = @import("permissions.zig").allowedPermissionUrl;
const descriptor_fn_symbol_name = @import("broker.zig").descriptor_fn_symbol_name;
const descriptor_symbol_name = @import("broker.zig").descriptor_symbol_name;
const renderPermissionsLock = @import("remote.zig").renderPermissionsLock;
const stdinIsTty = @import("fetch.zig").stdinIsTty;
const validatePermissions = @import("permissions.zig").validatePermissions;

test "plugin network permission URLs reject remote http and bare remote IPs" {
    try std.testing.expect(allowedPermissionUrl("http://127.0.0.1:18094/allowed"));
    try std.testing.expect(allowedPermissionUrl("http://localhost/allowed"));
    try std.testing.expect(allowedPermissionUrl("http://[::1]/allowed"));
    try std.testing.expect(allowedPermissionUrl("https://example.com/api"));
    try std.testing.expect(allowedPermissionUrl("https://*/api"));

    try std.testing.expect(!allowedPermissionUrl("http://example.com/api"));
    try std.testing.expect(!allowedPermissionUrl("example.com/api"));
    try std.testing.expect(!allowedPermissionUrl("https://192.168.1.10/api"));
    try std.testing.expect(!allowedPermissionUrl("https://[2001:db8::1]/api"));
    try std.testing.expect(!allowedPermissionUrl("http://localhost.evil.example/api"));
}
fn validatePermissionsForTest(allocator: std.mem.Allocator, permissions_json: []const u8) !PermissionInfo {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, permissions_json, .{});
    defer parsed.deinit();
    return try validatePermissions(allocator, parsed.value);
}
test "native_link permissions parse into entries and require confirmation" {
    const allocator = std.testing.allocator;
    var info = try validatePermissionsForTest(allocator,
        \\{"fs":[],"net":[],"env":[],"process":{"spawn":false,"exec":[]},"native_link":[{"lib":"nlmath","dirs":["/opt/nl/lib","libs"]},{"path":"libs/libextra.so"}]}
    );
    defer info.deinit(allocator);
    try std.testing.expect(info.has_native_link_permission);
    try std.testing.expect(info.requires_sandbox);
    try std.testing.expectEqual(@as(usize, 2), info.native_link.items.len);
    try std.testing.expectEqual(NativeLinkKind.lib, info.native_link.items[0].kind);
    try std.testing.expectEqualStrings("nlmath", info.native_link.items[0].name);
    try std.testing.expectEqual(@as(usize, 2), info.native_link.items[0].dirs.len);
    try std.testing.expectEqual(NativeLinkKind.path, info.native_link.items[1].kind);
    try std.testing.expectEqualStrings("libs/libextra.so", info.native_link.items[1].name);
    try std.testing.expectEqual(@as(usize, 0), info.native_link.items[1].dirs.len);
}
test "native_link is optional and empty declarations change nothing" {
    const allocator = std.testing.allocator;
    var absent = try validatePermissionsForTest(allocator,
        \\{"fs":[],"net":[],"env":[],"process":{"spawn":false,"exec":[]}}
    );
    defer absent.deinit(allocator);
    try std.testing.expect(!absent.has_native_link_permission);
    try std.testing.expect(!absent.requires_sandbox);
    try std.testing.expectEqual(@as(usize, 0), absent.native_link.items.len);

    var empty = try validatePermissionsForTest(allocator,
        \\{"fs":[],"net":[],"env":[],"process":{"spawn":false,"exec":[]},"native_link":[]}
    );
    defer empty.deinit(allocator);
    try std.testing.expect(!empty.has_native_link_permission);
    try std.testing.expect(!empty.requires_sandbox);
    try std.testing.expectEqual(@as(usize, 0), empty.native_link.items.len);
}
test "native_link entries join the permission digest" {
    const allocator = std.testing.allocator;
    // The digest covers the whole permissions object, so a declared
    // entry is confirmation-covered: changing the declared library
    // changes the digest and invalidates earlier confirmations.
    var declared_a = try validatePermissionsForTest(allocator,
        \\{"fs":[],"net":[],"env":[],"process":{"spawn":false,"exec":[]},"native_link":[{"lib":"nlmath"}]}
    );
    defer declared_a.deinit(allocator);
    var declared_b = try validatePermissionsForTest(allocator,
        \\{"fs":[],"net":[],"env":[],"process":{"spawn":false,"exec":[]},"native_link":[{"lib":"otherlib"}]}
    );
    defer declared_b.deinit(allocator);
    try std.testing.expect(!std.mem.eql(u8, declared_a.digest[0..], declared_b.digest[0..]));
    var declared_a_again = try validatePermissionsForTest(allocator,
        \\{"fs":[],"net":[],"env":[],"process":{"spawn":false,"exec":[]},"native_link":[{"lib":"nlmath"}]}
    );
    defer declared_a_again.deinit(allocator);
    try std.testing.expectEqual(declared_a.digest, declared_a_again.digest);
}
test "native_link rejects malformed entries" {
    const allocator = std.testing.allocator;
    const base_prefix = "{\"fs\":[],\"net\":[],\"env\":[],\"process\":{\"spawn\":false,\"exec\":[]},\"native_link\":";
    const bad_declarations = [_][]const u8{
        "[{\"lib\":\"x\",\"path\":\"y.so\"}]",
        "[{\"dirs\":[]}]",
        "[{\"lib\":\"a/b\"}]",
        "[{\"lib\":\"-lm\"}]",
        "[{\"lib\":\"\"}]",
        "[{\"path\":\"../libx.so\"}]",
        "[{\"path\":\"libx.so\",\"dirs\":[\"/tmp\"]}]",
        "[{\"lib\":\"x\",\"bogus\":1}]",
        "[{\"lib\":\"x\",\"dirs\":[\"a/../b\"]}]",
        "{}",
    };
    for (bad_declarations) |decl| {
        const text = try std.fmt.allocPrint(allocator, "{s}{s}}}", .{ base_prefix, decl });
        defer allocator.free(text);
        try std.testing.expectError(error.InvalidPluginPermission, validatePermissionsForTest(allocator, text));
    }
}
test "permissions lock rendering lists native_link entries" {
    const allocator = std.testing.allocator;
    const lib_dirs = try allocator.alloc([]u8, 1);
    lib_dirs[0] = try allocator.dupe(u8, "/opt/nl/lib");
    const native_link = try allocator.alloc(NativeLinkEntry, 2);
    native_link[0] = .{ .kind = .lib, .name = try allocator.dupe(u8, "nlmath"), .dirs = lib_dirs };
    native_link[1] = .{ .kind = .path, .name = try allocator.dupe(u8, "libs/libextra.so"), .dirs = try allocator.alloc([]u8, 0) };
    var manifest = SapManifest{
        .root_dir = try allocator.dupe(u8, "/tmp/zozi4-test"),
        .sap_path = try allocator.dupe(u8, "/tmp/zozi4-test/sap.json"),
        .name = try allocator.dupe(u8, "zozi4_nl"),
        .version = try allocator.dupe(u8, "0.1.0"),
        .abi_plugin = 1,
        .artifact_rel = try allocator.dupe(u8, "zig-out/lib/libzozi4_nl.so"),
        .artifact_sha256 = null,
        .interface_files = try allocator.alloc(InterfaceFile, 0),
        .asset_files = try allocator.alloc(AssetFile, 0),
        .dependencies = try allocator.alloc(PluginDependency, 0),
        .env_permissions = try allocator.alloc([]u8, 0),
        .fs_permissions = try allocator.alloc(FsPermission, 0),
        .net_permissions = try allocator.alloc(NetPermission, 0),
        .process_spawn = false,
        .process_exec_permissions = try allocator.alloc(ProcessExecPermission, 0),
        .native_link = native_link,
        .permission_digest = std.mem.zeroes([32]u8),
        .external_urls = try allocator.alloc([]u8, 0),
        .requires_sandbox = true,
        .has_fs_permission = false,
        .has_net_permission = false,
        .has_env_permission = false,
        .has_process_permission = false,
        .has_native_link_permission = true,
        .kind = .command,
        .language_extensions = try allocator.alloc([]u8, 0),
        .commands = try allocator.alloc([]u8, 0),
    };
    defer manifest.deinit(allocator);
    const text = try renderPermissionsLock(allocator, manifest, true, false, false);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "native_link\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "- lib=nlmath dirs=/opt/nl/lib") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "- path=libs/libextra.so") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "requires_confirmation=true") != null);
}
pub fn pluginDevMode(allocator: std.mem.Allocator) bool {
    const value = sio.getEnvVarOwned(allocator, "SA_PLUGIN_DEV") catch return false;
    defer allocator.free(value);
    return std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
}
pub fn confirmPrivilegedPluginInstall(stdout: anytype, manifest: SapManifest) !bool {
    if (!stdinIsTty()) {
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
    if (manifest.native_link.len != 0) {
        try stdout.writeAll("native libraries linked into consumer programs:\n");
        for (manifest.native_link) |entry| {
            switch (entry.kind) {
                .lib => {
                    try stdout.print("- lib={s}", .{entry.name});
                    if (entry.dirs.len != 0) {
                        try stdout.writeAll(" dirs=");
                        for (entry.dirs, 0..) |dir, idx| {
                            if (idx != 0) try stdout.writeByte(',');
                            try stdout.writeAll(dir);
                        }
                    }
                    try stdout.writeAll("\n");
                },
                .path => try stdout.print("- path={s}\n", .{entry.name}),
            }
        }
    }
    try stdout.print("Type the exact plugin name to continue: ", .{});
    var buffer: [256]u8 = undefined;
    var stdin_buf: [8192]u8 = undefined;
    var stdin_stream = sio.getStdIn().reader(&stdin_buf);
    var stdin_reader = StdinLineReader{ .inner = &stdin_stream.interface };
    const line = (try stdin_reader.readUntilDelimiterOrEof(&buffer, '\n')) orelse "";
    const answer = std.mem.trim(u8, line, " \t\r\n");
    if (!std.mem.eql(u8, answer, manifest.name)) {
        try stdout.writeAll("plugin install cancelled\n");
        return false;
    }
    return true;
}
pub fn fileExistsAbsolute(path: []const u8) bool {
    var file = sio.openFileAbsolute(path, .{}) catch return false;
    file.close();
    return true;
}
pub fn sha256File(allocator: std.mem.Allocator, path: []const u8) ![32]u8 {
    _ = allocator;
    var file = try sio.openFileAbsolute(path, .{});
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
pub fn fileExistsInProject(allocator: std.mem.Allocator, root_dir: []const u8, rel: []const u8) bool {
    const path = std.fs.path.join(allocator, &.{ root_dir, rel }) catch return false;
    defer allocator.free(path);
    return fileExistsAbsolute(path);
}
pub fn buildPluginProject(allocator: std.mem.Allocator, root_dir: []const u8, stdout: anytype, optimize: []const u8) !u8 {
    const optimize_arg = try std.fmt.allocPrint(allocator, "-Doptimize={s}", .{optimize});
    defer allocator.free(optimize_arg);
    const resolved_zig = try sio.resolveHostExe(allocator, "zig");
    defer if (resolved_zig) |p| allocator.free(p);
    const zig_exe = resolved_zig orelse "zig";
    const result = sio.Child.run(.{
        .allocator = allocator,
        .argv = &.{ zig_exe, "build", optimize_arg, "--summary", "all" },
        .cwd = root_dir,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            try stdout.writeAll("error: cannot build plugin project: 'zig' not found in PATH (sa plugin install builds the plugin with zig; install zig 0.14.1+ or add it to PATH)\n");
            return 1;
        },
        else => return err,
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
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
pub fn dirExistsAbsolute(path: []const u8) bool {
    var dir = sio.openDirAbsolute(path, .{}) catch return false;
    dir.close();
    return true;
}
// NOTE(Zig 0.17): @cImport was moved to an external package; declare the
// single libc symbol this test needs directly.
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
test "plugin build reports clear error when zig is missing from PATH" {
    const allocator = std.testing.allocator;
    const old_path = sio.getEnvVarOwned(allocator, "PATH") catch null;
    defer if (old_path) |p| allocator.free(p);
    // Point PATH at a nonexistent dir so `zig` cannot be resolved; buildPluginProject
    // must return 1 with a clear message instead of propagating error.FileNotFound.
    if (setenv("PATH", "/tmp/sa-test-no-such-path-dir", 1) != 0) return error.SetEnvFailed;
    defer blk: {
        if (old_path) |p| {
            const z = allocator.dupeSentinel(u8, p, 0) catch break :blk;
            defer allocator.free(z);
            _ = setenv("PATH", z.ptr, 1);
        }
    }
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const rc = try buildPluginProject(allocator, "/tmp", &aw.writer, "ReleaseFast");
    try std.testing.expectEqual(@as(u8, 1), rc);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "PATH") != null);
}
pub fn readFileAbsoluteAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    var file = try sio.openFileAbsolute(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, max_bytes);
}
pub fn copyFileAbsolute(src: []const u8, dst: []const u8) !void {
    try ensureParentDir(dst);
    try sio.copyFileAbsolute(src, dst);
}
pub fn writeFileAbsolute(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try sio.createFileAbsolute(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}
fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| try sio.cwd().makePath(dir);
}
pub fn loadDescriptor(lib: *dynlib.DynLib) ?PluginDescriptor {
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
pub fn validateDescriptor(descriptor: PluginDescriptor) ?[]const u8 {
    if (descriptor.abi_version != abi_version) return "abi version mismatch";
    if (descriptor.descriptor_size != @as(u32, @intCast(@sizeOf(PluginDescriptor)))) return "descriptor size mismatch";
    if (std.mem.span(descriptor.name).len == 0) return "empty plugin name";
    return null;
}
pub fn abiStatusFromInt(value: u32) AbiStatus {
    return switch (value) {
        @intFromEnum(AbiStatus.ok) => .ok,
        @intFromEnum(AbiStatus.unknown_command) => .unknown_command,
        @intFromEnum(AbiStatus.failed) => .failed,
        @intFromEnum(AbiStatus.version_mismatch) => .version_mismatch,
        @intFromEnum(AbiStatus.invalid_descriptor) => .invalid_descriptor,
        else => .failed,
    };
}
pub fn dupeZArgs(allocator: std.mem.Allocator, argv: []const []const u8) ![][*:0]const u8 {
    var out = try allocator.alloc([*:0]const u8, argv.len);
    errdefer allocator.free(out);
    var copied: usize = 0;
    errdefer {
        for (out[0..copied]) |arg| allocator.free(std.mem.sliceTo(arg, 0));
    }
    for (argv, 0..) |arg, idx| {
        out[idx] = try allocator.dupeSentinel(u8, arg, 0);
        copied += 1;
    }
    return out;
}
pub fn freeZArgs(allocator: std.mem.Allocator, argv: [][*:0]const u8) void {
    for (argv) |arg| allocator.free(std.mem.sliceTo(arg, 0));
    allocator.free(argv);
}
pub fn StreamCtx(comptime Writer: type) type {
    return struct {
        writer: *Writer,
    };
}
pub fn streamWriteAll(comptime Writer: type) StreamWriteAllFn {
    return struct {
        fn write(ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32 {
            const stream_ctx = @as(*StreamCtx(Writer), @ptrCast(@alignCast(ctx orelse return @intFromEnum(AbiStatus.failed))));
            stream_ctx.writer.*.writeAll(bytes[0..len]) catch return @intFromEnum(AbiStatus.failed);
            return @intFromEnum(AbiStatus.ok);
        }
    }.write;
}
