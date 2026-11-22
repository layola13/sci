const std = @import("std");
const builtin = @import("builtin");

const saasm = @import("saasm");
const sio = @import("sio");

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
extern "c" fn _putenv_s(name: [*:0]const u8, value: [*:0]const u8) c_int;

pub fn elapsedMs(start_ns: i128) i128 {
    return @divTrunc(sio.nanoTimestamp() - start_ns, std.time.ns_per_ms);
}

pub fn startTimedTest(name: []const u8) i128 {
    std.debug.print("[plugin-host-smoke] START test=\"{s}\"\n", .{name});
    return sio.nanoTimestamp();
}

pub fn endTimedTest(name: []const u8, start_ns: i128) void {
    std.debug.print("[plugin-host-smoke] END   test=\"{s}\" elapsed={}ms\n", .{ name, elapsedMs(start_ns) });
}

pub fn servoWriteAll(stream: std.Io.net.Stream, bytes: []const u8) !void {
    var wbuf: [8192]u8 = undefined;
    var w = stream.writer(sio.io(), &wbuf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}

pub fn writeSource(dir: std.Io.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(std.testing.io, path, .{ .truncate = true });
    defer file.close(std.testing.io);
    var wbuf: [8192]u8 = undefined;
    var w = file.writer(std.testing.io, &wbuf);
    try w.interface.writeAll(source);
    try w.interface.flush();
}

pub fn targetArtifactKey() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64 => switch (builtin.os.tag) {
            .windows => "windows-x86_64",
            .linux => "linux-x86_64",
            .macos => "macos-x86_64",
            else => "linux-x86_64",
        },
        .aarch64 => switch (builtin.os.tag) {
            .windows => "windows-aarch64",
            .linux => "linux-aarch64",
            .macos => "macos-aarch64",
            else => "linux-aarch64",
        },
        else => switch (builtin.os.tag) {
            .windows => "windows-x86_64",
            .linux => "linux-x86_64",
            .macos => "macos-x86_64",
            else => "linux-x86_64",
        },
    };
}

pub fn dynLibFileNameAlloc(allocator: std.mem.Allocator, library_name: []const u8) ![]u8 {
    return switch (builtin.os.tag) {
        .windows => try std.fmt.allocPrint(allocator, "{s}.dll", .{library_name}),
        .macos => try std.fmt.allocPrint(allocator, "lib{s}.dylib", .{library_name}),
        else => try std.fmt.allocPrint(allocator, "lib{s}.so", .{library_name}),
    };
}

pub fn dynLibInstallPath(allocator: std.mem.Allocator, library_name: []const u8) ![]u8 {
    return switch (builtin.os.tag) {
        .windows => try std.fmt.allocPrint(allocator, "zig-out/bin/{s}.dll", .{library_name}),
        .macos => try std.fmt.allocPrint(allocator, "zig-out/lib/lib{s}.dylib", .{library_name}),
        else => try std.fmt.allocPrint(allocator, "zig-out/lib/lib{s}.so", .{library_name}),
    };
}

pub fn jsonStringLiteralAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try out.append('"');
    for (text) |c| switch (c) {
        '"' => try out.appendSlice("\\\""),
        '\\' => try out.appendSlice("\\\\"),
        '\n' => try out.appendSlice("\\n"),
        '\r' => try out.appendSlice("\\r"),
        '\t' => try out.appendSlice("\\t"),
        else => try out.append(c),
    };
    try out.append('"');
    return try out.toOwnedSlice();
}

pub fn badDynamicLibraryName() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "bad.dll",
        .macos => "bad.dylib",
        else => "bad.so",
    };
}

pub fn netProbePrelude() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "extern \"c\" fn WSAStartup(version: u16, data: ?*anyopaque) i32;\n",
        else => "extern \"c\" fn connect(fd: i32, address: ?*const anyopaque, address_len: i32) i32;\n",
    };
}

pub fn netProbeBody() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "_ = WSAStartup(0x202, null);\n    return 0;",
        else => "_ = connect(-1, null, 0);\n    return 0;",
    };
}

pub fn netProbeSymbol() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "WSAStartup",
        else => "connect",
    };
}

pub fn writeInstallablePluginProject(
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    root: []const u8,
    library_name: []const u8,
    plugin_name: []const u8,
    export_symbol: []const u8,
    permissions_json: []const u8,
    source_prelude: []const u8,
    export_body: []const u8,
    link_libc: bool,
    link_winsock: bool,
) !void {
    const src_dir = try std.fmt.allocPrint(allocator, "{s}/src", .{root});
    defer allocator.free(src_dir);
    try dir.createDirPath(std.testing.io, src_dir);

    const build_path = try std.fmt.allocPrint(allocator, "{s}/build.zig", .{root});
    defer allocator.free(build_path);
    const winsock_link_line = if (link_winsock)
        "    if (target.result.os.tag == .windows) lib.root_module.linkSystemLibrary(\"ws2_32\", .{});\n"
    else
        "";
    const build_source = if (link_libc)
        try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {{
            \\    const target = b.standardTargetOptions(.{{}});
            \\    const optimize = b.standardOptimizeOption(.{{}});
            \\    const root_module = b.createModule(.{{
            \\        .root_source_file = b.path("src/plugin.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\        .link_libc = true,
            \\    }});
            \\    const lib = b.addLibrary(.{{
            \\        .name = "{s}",
            \\        .root_module = root_module,
            \\        .linkage = .dynamic,
            \\    }});
            \\{s}
            \\    b.installArtifact(lib);
            \\}}
            \\
        , .{ library_name, winsock_link_line })
    else
        try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {{
            \\    const target = b.standardTargetOptions(.{{}});
            \\    const optimize = b.standardOptimizeOption(.{{}});
            \\    const root_module = b.createModule(.{{
            \\        .root_source_file = b.path("src/plugin.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\    const lib = b.addLibrary(.{{
            \\        .name = "{s}",
            \\        .root_module = root_module,
            \\        .linkage = .dynamic,
            \\    }});
            \\{s}
            \\    b.installArtifact(lib);
            \\}}
            \\
        , .{ library_name, winsock_link_line });
    defer allocator.free(build_source);
    try writeSource(dir, build_path, build_source);

    const plugin_path = try std.fmt.allocPrint(allocator, "{s}/src/plugin.zig", .{root});
    defer allocator.free(plugin_path);
    const plugin_source = try std.fmt.allocPrint(allocator,
        \\const SkillSection = extern struct {{
        \\    name: [*:0]const u8,
        \\    summary: [*:0]const u8,
        \\    items: [*]const [*:0]const u8,
        \\    items_len: usize,
        \\}};
        \\const PluginDescriptor = extern struct {{
        \\    abi_version: u32,
        \\    descriptor_size: u32,
        \\    name: [*:0]const u8,
        \\    init: ?*const fn (?*anyopaque) callconv(.c) u32,
        \\    prebuild: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) u32,
        \\    postbuild: ?*const fn (?*anyopaque) callconv(.c) u32,
        \\    handle_command: ?*const anyopaque,
        \\    skills_ptr: [*]const SkillSection,
        \\    skills_len: usize,
        \\}};
        \\const skills = [_]SkillSection{{}};
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = .{{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "{s}",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = null,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\}};
        \\{s}
        \\pub export fn {s}() u32 {{
        \\    {s}
        \\}}
        \\
    , .{ plugin_name, source_prelude, export_symbol, export_body });
    defer allocator.free(plugin_source);
    try writeSource(dir, plugin_path, plugin_source);

    const interface_name = try std.fmt.allocPrint(allocator, "{s}.sai", .{plugin_name});
    defer allocator.free(interface_name);
    const interface_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, interface_name });
    defer allocator.free(interface_path);
    const interface_source = try std.fmt.allocPrint(allocator,
        \\@extern {s}() -> u32
        \\
    , .{export_symbol});
    defer allocator.free(interface_source);
    try writeSource(dir, interface_path, interface_source);

    const artifact_path = try dynLibInstallPath(allocator, library_name);
    defer allocator.free(artifact_path);

    const manifest_path = try std.fmt.allocPrint(allocator, "{s}/sap.json", .{root});
    defer allocator.free(manifest_path);
    const manifest_source = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "{s}",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "interfaces": {{
        \\    "sai": {{ "path": "{s}" }}
        \\  }},
        \\  "skills": [],
        \\  "permissions": {s},
        \\  "dependencies": {{}}
        \\}}
        \\
    , .{ plugin_name, targetArtifactKey(), artifact_path, interface_name, permissions_json });
    defer allocator.free(manifest_source);
    try writeSource(dir, manifest_path, manifest_source);
}

pub fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !sio.Child.RunResult {
    return try sio.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

pub fn sha256HexFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try sio.cwd().openFile(path, .{});
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
    const hex = std.fmt.bytesToHex(digest, .lower);
    return try allocator.dupe(u8, hex[0..]);
}

pub fn expectSuccess(result: sio.Child.RunResult) !void {
    if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
    switch (result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

pub fn expectInstallCode(expected: u8, actual: u8, output: []const u8) !void {
    if (actual != expected) std.debug.print("plugin install output:\n{s}\n", .{output});
    try std.testing.expectEqual(expected, actual);
}

pub fn setEnvVarZ(name: [:0]const u8, value: [:0]const u8) !void {
    if (builtin.os.tag == .windows) {
        if (_putenv_s(name.ptr, value.ptr) != 0) return error.SetEnvFailed;
    } else {
        if (setenv(name.ptr, value.ptr, 1) != 0) return error.SetEnvFailed;
    }
}

pub fn unsetEnvVarZ(name: [:0]const u8) void {
    if (builtin.os.tag == .windows) {
        _ = _putenv_s(name.ptr, "");
    } else {
        _ = unsetenv(name.ptr);
    }
}

pub fn saveEnvVarZ(allocator: std.mem.Allocator, name: []const u8) !?[:0]u8 {
    const value = sio.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(value);
    return try allocator.dupeSentinel(u8, value, 0);
}

pub fn runBrokerCliCase(
    stdout_buffer: *std.array_list.Managed(u8),
    stderr_buffer: *std.array_list.Managed(u8),
    argv: []const []const u8,
    expected_code: u8,
    expected_stdout: []const u8,
) !void {
    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        argv,
        sio.managedWriter(stdout_buffer),
        sio.managedWriter(stderr_buffer),
    );
    try std.testing.expectEqual(expected_code, code);
    try std.testing.expectEqualStrings(expected_stdout, stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}
