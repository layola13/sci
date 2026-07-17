const std = @import("std");
const builtin = @import("builtin");

pub const Optimization = enum {
    release_small,
    release_fast,
};

pub const Target = struct {
    triple: []const u8,
    no_entry: bool = false,
};

pub const CompileError = error{
    ChildProcessFailed,
    InvalidTarget,
    MissingTarget,
};

// Test-only external tool failure injection for zig cc / objcopy process
// launch paths. `fail_after` matching operations succeed first, then the next
// matching operation returns TestInjectedExternalToolFailure and clears the hook.
var external_tool_test_fail_op: ?[]const u8 = null;
var external_tool_test_fail_after: usize = 0;
var external_tool_test_fail_seen: usize = 0;

fn externalToolTestMaybeFail(op: []const u8) !void {
    if (!builtin.is_test) return;
    const want = external_tool_test_fail_op orelse return;
    if (!std.mem.eql(u8, want, op)) return;
    if (external_tool_test_fail_seen < external_tool_test_fail_after) {
        external_tool_test_fail_seen += 1;
        return;
    }
    external_tool_test_fail_op = null;
    external_tool_test_fail_after = 0;
    external_tool_test_fail_seen = 0;
    return error.TestInjectedExternalToolFailure;
}

fn externalToolTestArm(op: []const u8, fail_after: usize) void {
    external_tool_test_fail_op = op;
    external_tool_test_fail_after = fail_after;
    external_tool_test_fail_seen = 0;
}

fn externalToolTestDisarm() void {
    external_tool_test_fail_op = null;
    external_tool_test_fail_after = 0;
    external_tool_test_fail_seen = 0;
}

pub const Argv = struct {
    items: std.ArrayList([]const u8),

    pub fn slice(self: *const Argv) []const []const u8 {
        return self.items.items;
    }

    pub fn deinit(self: *Argv) void {
        self.items.deinit();
        self.* = undefined;
    }
};

pub const ToolchainCacheIdentityOptions = struct {
    path_env: ?[]const u8 = null,
    include_objcopy: bool = false,
};

fn supportedWindowsProgramExtension(ext: []const u8) bool {
    inline for (@typeInfo(std.process.Child.WindowsExtension).@"enum".fields) |field| {
        if (std.ascii.eqlIgnoreCase(ext, "." ++ field.name)) return true;
    }
    return false;
}

fn tryResolveProgramPath(allocator: std.mem.Allocator, full_path: []const u8, pathext: ?[]const u8) !?[]u8 {
    if (std.fs.cwd().realpathAlloc(allocator, full_path)) |resolved| {
        return resolved;
    } else |err| switch (err) {
        error.OutOfMemory => return err,
        else => {},
    }

    if (builtin.os.tag == .windows) {
        if (pathext) |extensions| {
            var it = std.mem.tokenizeScalar(u8, extensions, std.fs.path.delimiter);
            while (it.next()) |ext| {
                if (!supportedWindowsProgramExtension(ext)) continue;
                const extended_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ full_path, ext });
                defer allocator.free(extended_path);
                if (std.fs.cwd().realpathAlloc(allocator, extended_path)) |resolved| {
                    return resolved;
                } else |err| switch (err) {
                    error.OutOfMemory => return err,
                    else => continue,
                }
            }
        }
    }

    return null;
}

fn pathEnvOrNull(allocator: std.mem.Allocator, explicit_path_env: ?[]const u8) !?[]const u8 {
    if (explicit_path_env) |path_env| return path_env;
    return std.process.getEnvVarOwned(allocator, "PATH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => |e| return e,
    };
}

fn pathextEnvOrNull(allocator: std.mem.Allocator) !?[]u8 {
    if (builtin.os.tag != .windows) return null;
    return std.process.getEnvVarOwned(allocator, "PATHEXT") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => |e| return e,
    };
}

fn resolveProgram(allocator: std.mem.Allocator, name: []const u8, explicit_path_env: ?[]const u8) !?[]u8 {
    var env_owned = false;
    const path_env = try pathEnvOrNull(allocator, explicit_path_env);
    defer if (env_owned) allocator.free(path_env.?);
    env_owned = explicit_path_env == null and path_env != null;

    const pathext = try pathextEnvOrNull(allocator);
    defer if (pathext) |value| allocator.free(value);

    if (std.fs.path.isAbsolute(name) or std.mem.indexOfAny(u8, name, "/\\") != null) {
        return try tryResolveProgramPath(allocator, name, pathext);
    }

    if (path_env) |search_path| {
        var it = std.mem.tokenizeScalar(u8, search_path, std.fs.path.delimiter);
        while (it.next()) |dir| {
            const candidate = try std.fs.path.join(allocator, &.{ dir, name });
            defer allocator.free(candidate);
            if (try tryResolveProgramPath(allocator, candidate, pathext)) |resolved| return resolved;
        }
    }

    return null;
}

fn hashFileHex(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [8192]u8 = undefined;
    while (true) {
        const read_count = try file.read(&buffer);
        if (read_count == 0) break;
        hasher.update(buffer[0..read_count]);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return try allocator.dupe(u8, hex[0..]);
}

fn firstOutputLine(bytes: []const u8) []const u8 {
    const end = std.mem.indexOfAny(u8, bytes, "\r\n") orelse bytes.len;
    return std.mem.trimRight(u8, bytes[0..end], " \t");
}

fn appendVersionIdentity(writer: anytype, allocator: std.mem.Allocator, path: []const u8) !void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ path, "--version" },
    }) catch |err| {
        try writer.print("version_error={s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const version_output = if (result.stdout.len != 0) result.stdout else result.stderr;
    const version_line = firstOutputLine(version_output);
    switch (result.term) {
        .Exited => |code| {
            try writer.print("version_exit={d};version={s}", .{ code, if (version_line.len == 0) "empty" else version_line });
        },
        else => {
            try writer.print("version_error=terminated;version={s}", .{if (version_line.len == 0) "empty" else version_line});
        },
    }
}

fn appendProgramIdentity(writer: anytype, allocator: std.mem.Allocator, label: []const u8, executable: []const u8, path_env: ?[]const u8) !bool {
    try writer.print("{s}=", .{label});
    const resolved = (try resolveProgram(allocator, executable, path_env)) orelse {
        try writer.writeAll("objcopy=missing");
        return false;
    };
    defer allocator.free(resolved);

    const stat = std.fs.cwd().statFile(resolved) catch |err| {
        try writer.print("stat_error={s};path={s}", .{ @errorName(err), resolved });
        return true;
    };
    if (stat.kind != .file) {
        try writer.print("not_file;path={s}", .{resolved});
        return true;
    }
    const digest_hex = hashFileHex(allocator, resolved) catch |err| {
        try writer.print("hash_error={s};path={s};size={d}", .{ @errorName(err), resolved, stat.size });
        return true;
    };
    defer allocator.free(digest_hex);

    try writer.print("path={s};size={d};sha256={s};", .{ resolved, stat.size, digest_hex });
    try appendVersionIdentity(writer, allocator, resolved);
    return true;
}

pub fn toolchainCacheIdentity(allocator: std.mem.Allocator, options: ToolchainCacheIdentityOptions) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    try writer.writeAll("zigcc-toolchain-cache/v1;");
    _ = try appendProgramIdentity(writer, allocator, "zig_cc_driver", "zig", options.path_env);
    try writer.writeByte(';');
    if (options.include_objcopy and builtin.os.tag == .linux) {
        const candidates = [_][]const u8{
            "llvm-objcopy",
            "llvm-objcopy-20",
            "llvm-objcopy-19",
            "llvm-objcopy-18",
            "llvm-objcopy-17",
            "llvm-objcopy-16",
            "llvm-objcopy-15",
            "llvm-objcopy-14",
            "objcopy",
        };
        for (candidates) |candidate| {
            const before_len = out.items.len;
            try writer.print("objcopy_candidate={s};", .{candidate});
            if (try appendProgramIdentity(writer, allocator, "objcopy_tool", candidate, options.path_env)) {
                return try out.toOwnedSlice();
            }
            out.shrinkRetainingCapacity(before_len);
        }
        try writer.writeAll("missing");
    } else {
        try writer.writeAll("objcopy=not-applicable");
    }
    return try out.toOwnedSlice();
}

pub fn hostRpathArgument(os_tag: std.Target.Os.Tag) ?[]const u8 {
    return switch (os_tag) {
        .linux => "-Wl,-rpath,$ORIGIN",
        .macos => "-Wl,-rpath,@loader_path",
        else => null,
    };
}

/// Stable native link-flag identity for project artifact keys.
/// Captures host rpath, platform system libraries, and the current
/// export-dynamic policy used by `argvForExe` / native plugin linking.
pub fn hostLinkPolicyIdentity(allocator: std.mem.Allocator, os_tag: std.Target.Os.Tag) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    try writer.writeAll("host-link-policy-v1;");
    if (hostRpathArgument(os_tag)) |rpath| {
        try writer.print("rpath={s};", .{rpath});
    } else {
        try writer.writeAll("rpath=none;");
    }
    switch (os_tag) {
        .windows => try writer.writeAll("system_libs=ws2_32,mswsock,iphlpapi;"),
        else => try writer.writeAll("system_libs=none;"),
    }
    // Native executables currently rely on default dynamic-symbol export
    // behavior (no explicit -rdynamic / --export-dynamic). Keep the policy
    // explicit so future export-flag changes invalidate artifact keys.
    try writer.writeAll("export_dynamic=default-none;");
    try writer.writeAll("plugin_rpath=Wl,-rpath,<libdir>;");
    return try out.toOwnedSlice();
}

pub fn argvForExe(
    allocator: std.mem.Allocator,
    artifact_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    sa_std_archive_path: []const u8,
    extra_inputs: []const []const u8,
    debug: bool,
) !Argv {
    var argv = Argv{ .items = std.ArrayList([]const u8).init(allocator) };
    errdefer argv.deinit();
    try argv.items.append("zig");
    try argv.items.append("cc");
    if (debug) {
        try argv.items.append("-g");
    }
    try argv.items.append(if (debug) "-O0" else switch (optimization) {
        .release_small => "-O1",
        .release_fast => "-O3",
    });
    try argv.items.append(artifact_path);
    try argv.items.append(sa_std_archive_path);
    for (extra_inputs) |input| {
        try argv.items.append(input);
    }
    if (builtin.os.tag == .windows) {
        try argv.items.append("-lws2_32");
        try argv.items.append("-lmswsock");
        try argv.items.append("-liphlpapi");
    }
    if (hostRpathArgument(builtin.os.tag)) |argument| try argv.items.append(argument);
    try argv.items.append("-o");
    try argv.items.append(out_path);
    return argv;
}

pub fn argvForObj(
    allocator: std.mem.Allocator,
    artifact_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    debug: bool,
) !Argv {
    var argv = Argv{ .items = std.ArrayList([]const u8).init(allocator) };
    errdefer argv.deinit();
    try argv.items.append("zig");
    try argv.items.append("cc");
    if (debug) {
        try argv.items.append("-g");
    }
    try argv.items.append(if (debug) "-O0" else switch (optimization) {
        .release_small => "-O1",
        .release_fast => "-O3",
    });
    try argv.items.append("-c");
    try argv.items.append(artifact_path);
    try argv.items.append("-o");
    try argv.items.append(out_path);
    return argv;
}

pub fn argvForRelocatableObj(
    allocator: std.mem.Allocator,
    out_path: []const u8,
    input_objects: []const []const u8,
) !Argv {
    var argv = Argv{ .items = std.ArrayList([]const u8).init(allocator) };
    errdefer argv.deinit();
    try argv.items.append("zig");
    try argv.items.append("cc");
    try argv.items.append("-r");
    for (input_objects) |input| {
        try argv.items.append(input);
    }
    try argv.items.append("-o");
    try argv.items.append(out_path);
    return argv;
}

pub fn argvForWasm(
    allocator: std.mem.Allocator,
    artifact_path: []const u8,
    out_path: []const u8,
    target: Target,
    optimization: Optimization,
    debug: bool,
) !Argv {
    var argv = Argv{ .items = std.ArrayList([]const u8).init(allocator) };
    errdefer argv.deinit();
    try argv.items.append("zig");
    try argv.items.append("cc");
    if (debug) {
        try argv.items.append("-g");
    }
    try argv.items.append("-target");
    try argv.items.append(target.triple);

    if (target.no_entry) {
        try argv.items.append("-Wl,--no-entry");
    }

    try argv.items.append(if (debug) "-O0" else switch (optimization) {
        .release_small => "-O1",
        .release_fast => "-O3",
    });
    try argv.items.append(artifact_path);
    try argv.items.append("-o");
    try argv.items.append(out_path);
    return argv;
}

fn runProcess(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    try externalToolTestMaybeFail("run");
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn runProcessFast(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.Term {
    try externalToolTestMaybeFail("spawn");
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    try child.waitForSpawn();
    return try child.wait();
}

fn localizeElfHiddenSymbols(allocator: std.mem.Allocator, object_path: []const u8, stderr: anytype) !void {
    if (builtin.os.tag != .linux) return;

    var random: [8]u8 = undefined;
    std.crypto.random.bytes(&random);
    const suffix = std.fmt.bytesToHex(random, .lower);
    const staging_path = try std.fmt.allocPrint(allocator, "{s}.localized.{s}", .{ object_path, suffix[0..] });
    defer allocator.free(staging_path);
    defer std.fs.cwd().deleteFile(staging_path) catch {};

    const candidates = [_][]const u8{
        "llvm-objcopy",
        "llvm-objcopy-20",
        "llvm-objcopy-19",
        "llvm-objcopy-18",
        "llvm-objcopy-17",
        "llvm-objcopy-16",
        "llvm-objcopy-15",
        "llvm-objcopy-14",
        "objcopy",
    };
    var found_tool = false;
    for (candidates) |candidate| {
        std.fs.cwd().deleteFile(staging_path) catch {};
        const result = runProcess(allocator, &.{ candidate, "--localize-hidden", object_path, staging_path }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        found_tool = true;
        const succeeded = switch (result.term) {
            .Exited => |code| code == 0,
            else => false,
        };
        if (!succeeded) continue;

        var localized = try std.fs.cwd().openFile(staging_path, .{});
        defer localized.close();
        const stat = try localized.stat();
        if (stat.kind != .file or stat.size == 0) continue;
        try localized.sync();
        try std.fs.cwd().rename(staging_path, object_path);
        return;
    }

    try stderr.print(
        "error[ExternalCompiler]: {s} while localizing hidden symbols in {s}\n",
        .{ if (found_tool) "all objcopy candidates failed" else "no objcopy candidate was found", object_path },
    );
    return CompileError.ChildProcessFailed;
}

fn printCommandLine(writer: anytype, argv: []const []const u8) !void {
    try writer.writeAll("  command:");
    for (argv) |arg| {
        try writer.print(" {s}", .{arg});
    }
    try writer.writeByte('\n');
}

fn printOutputSection(writer: anytype, label: []const u8, bytes: []const u8) !void {
    if (bytes.len == 0) return;
    try writer.print("  {s}:\n", .{label});
    try writer.writeAll(bytes);
    if (bytes[bytes.len - 1] != '\n') try writer.writeByte('\n');
}

fn printCompilerLaunchFailure(writer: anytype, argv: []const []const u8, action: []const u8, input_path: []const u8, out_path: []const u8, err: anyerror) !void {
    try writer.print("error[ExternalCompiler]: failed to launch zig cc while {s} {s} -> {s}: {s}\n", .{ action, input_path, out_path, @errorName(err) });
    try printCommandLine(writer, argv);
}

fn printCompilerFailure(writer: anytype, argv: []const []const u8, action: []const u8, input_path: []const u8, out_path: []const u8, result: std.process.Child.RunResult) !void {
    switch (result.term) {
        .Exited => |code| try writer.print("error[ExternalCompiler]: zig cc exited with code {d} while {s} {s} -> {s}\n", .{ code, action, input_path, out_path }),
        else => try writer.print("error[ExternalCompiler]: zig cc terminated unexpectedly while {s} {s} -> {s}\n", .{ action, input_path, out_path }),
    }
    try printCommandLine(writer, argv);
    try printOutputSection(writer, "stdout", result.stdout);
    try printOutputSection(writer, "stderr", result.stderr);
}

pub fn compileExe(
    allocator: std.mem.Allocator,
    artifact_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    sa_std_archive_path: []const u8,
    extra_inputs: []const []const u8,
    debug: bool,
    stderr: anytype,
) !void {
    var argv = try argvForExe(allocator, artifact_path, out_path, optimization, sa_std_archive_path, extra_inputs, debug);
    defer argv.deinit();
    const argv_slice = argv.slice();
    const term = runProcessFast(allocator, argv_slice) catch |err| {
        try printCompilerLaunchFailure(stderr, argv_slice, "linking", artifact_path, out_path, err);
        return CompileError.ChildProcessFailed;
    };

    const failed = switch (term) {
        .Exited => |code| code != 0,
        else => true,
    };
    if (failed) {
        const result = runProcess(allocator, argv_slice) catch |err| {
            try printCompilerLaunchFailure(stderr, argv_slice, "linking", artifact_path, out_path, err);
            return CompileError.ChildProcessFailed;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try printCompilerFailure(stderr, argv_slice, "linking", artifact_path, out_path, result);
        return CompileError.ChildProcessFailed;
    }
}

pub fn compileObj(
    allocator: std.mem.Allocator,
    artifact_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    debug: bool,
    stderr: anytype,
) !void {
    var argv = try argvForObj(allocator, artifact_path, out_path, optimization, debug);
    defer argv.deinit();
    const argv_slice = argv.slice();
    const term = runProcessFast(allocator, argv_slice) catch |err| {
        try printCompilerLaunchFailure(stderr, argv_slice, "compiling object", artifact_path, out_path, err);
        return CompileError.ChildProcessFailed;
    };

    const failed = switch (term) {
        .Exited => |code| code != 0,
        else => true,
    };
    if (failed) {
        const result = runProcess(allocator, argv_slice) catch |err| {
            try printCompilerLaunchFailure(stderr, argv_slice, "compiling object", artifact_path, out_path, err);
            return CompileError.ChildProcessFailed;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try printCompilerFailure(stderr, argv_slice, "compiling object", artifact_path, out_path, result);
        return CompileError.ChildProcessFailed;
    }
}

pub fn compileRelocatableObj(
    allocator: std.mem.Allocator,
    input_objects: []const []const u8,
    out_path: []const u8,
    stderr: anytype,
) !void {
    var argv = try argvForRelocatableObj(allocator, out_path, input_objects);
    defer argv.deinit();
    const argv_slice = argv.slice();
    const term = runProcessFast(allocator, argv_slice) catch |err| {
        try printCompilerLaunchFailure(stderr, argv_slice, "linking relocatable object", input_objects[0], out_path, err);
        return CompileError.ChildProcessFailed;
    };

    const failed = switch (term) {
        .Exited => |code| code != 0,
        else => true,
    };
    if (failed) {
        const result = runProcess(allocator, argv_slice) catch |err| {
            try printCompilerLaunchFailure(stderr, argv_slice, "linking relocatable object", input_objects[0], out_path, err);
            return CompileError.ChildProcessFailed;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try printCompilerFailure(stderr, argv_slice, "linking relocatable object", input_objects[0], out_path, result);
        return CompileError.ChildProcessFailed;
    }
    try localizeElfHiddenSymbols(allocator, out_path, stderr);
}

pub fn compileWasm(
    allocator: std.mem.Allocator,
    artifact_path: []const u8,
    out_path: []const u8,
    target: Target,
    optimization: Optimization,
    debug: bool,
    stderr: anytype,
) !void {
    var argv = try argvForWasm(allocator, artifact_path, out_path, target, optimization, debug);
    defer argv.deinit();
    const argv_slice = argv.slice();
    const term = runProcessFast(allocator, argv_slice) catch |err| {
        try printCompilerLaunchFailure(stderr, argv_slice, "linking wasm", artifact_path, out_path, err);
        return CompileError.ChildProcessFailed;
    };

    const failed = switch (term) {
        .Exited => |code| code != 0,
        else => true,
    };
    if (failed) {
        const result = runProcess(allocator, argv_slice) catch |err| {
            try printCompilerLaunchFailure(stderr, argv_slice, "linking wasm", artifact_path, out_path, err);
            return CompileError.ChildProcessFailed;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try printCompilerFailure(stderr, argv_slice, "linking wasm", artifact_path, out_path, result);
        return CompileError.ChildProcessFailed;
    }
}

test "argv helpers choose the requested optimization" {
    var exe_small = try argvForExe(std.testing.allocator, "input.bc", "out.exe", .release_small, "/repo/artifacts/sa_std/libsa_std.a", &.{}, false);
    defer exe_small.deinit();
    try std.testing.expectEqualStrings("-O1", exe_small.slice()[2]);
    try std.testing.expectEqualStrings("/repo/artifacts/sa_std/libsa_std.a", exe_small.slice()[4]);
    var exe_fast = try argvForExe(std.testing.allocator, "input.bc", "out.exe", .release_fast, "/repo/artifacts/sa_std/libsa_std.a", &.{}, false);
    defer exe_fast.deinit();
    try std.testing.expectEqualStrings("-O3", exe_fast.slice()[2]);

    var wasm_small = try argvForWasm(std.testing.allocator, "input.bc", "out.wasm", .{ .triple = "wasm32-wasi" }, .release_small, false);
    defer wasm_small.deinit();
    try std.testing.expectEqualStrings("-O1", wasm_small.slice()[4]);
    var wasm_fast = try argvForWasm(std.testing.allocator, "input.bc", "out.wasm", .{ .triple = "wasm32-wasi", .no_entry = true }, .release_fast, false);
    defer wasm_fast.deinit();
    try std.testing.expectEqualStrings("-O3", wasm_fast.slice()[5]);
}

test "native executable rpath follows host loader semantics" {
    try std.testing.expectEqualStrings("-Wl,-rpath,$ORIGIN", hostRpathArgument(.linux).?);
    try std.testing.expectEqualStrings("-Wl,-rpath,@loader_path", hostRpathArgument(.macos).?);
    try std.testing.expectEqual(@as(?[]const u8, null), hostRpathArgument(.windows));

    const linux_policy = try hostLinkPolicyIdentity(std.testing.allocator, .linux);
    defer std.testing.allocator.free(linux_policy);
    try std.testing.expect(std.mem.indexOf(u8, linux_policy, "host-link-policy-v1;") != null);
    try std.testing.expect(std.mem.indexOf(u8, linux_policy, "rpath=-Wl,-rpath,$ORIGIN;") != null);
    try std.testing.expect(std.mem.indexOf(u8, linux_policy, "system_libs=none;") != null);
    try std.testing.expect(std.mem.indexOf(u8, linux_policy, "export_dynamic=default-none;") != null);

    const windows_policy = try hostLinkPolicyIdentity(std.testing.allocator, .windows);
    defer std.testing.allocator.free(windows_policy);
    try std.testing.expect(std.mem.indexOf(u8, windows_policy, "rpath=none;") != null);
    try std.testing.expect(std.mem.indexOf(u8, windows_policy, "system_libs=ws2_32,mswsock,iphlpapi;") != null);
}

test "argv helpers preserve input and link flag order" {
    var exe = try argvForExe(
        std.testing.allocator,
        "input.bc",
        "out.exe",
        .release_small,
        "/repo/artifacts/sa_std/libsa_std.a",
        &.{ "first.o", "second.o" },
        false,
    );
    defer exe.deinit();
    const exe_args = exe.slice();
    try std.testing.expectEqualStrings("first.o", exe_args[5]);
    try std.testing.expectEqualStrings("second.o", exe_args[6]);
    if (hostRpathArgument(builtin.os.tag)) |rpath| {
        try std.testing.expectEqualStrings(rpath, exe_args[7]);
        try std.testing.expectEqualStrings("-o", exe_args[8]);
    } else {
        try std.testing.expectEqualStrings("-o", exe_args[7]);
    }

    var wasm = try argvForWasm(
        std.testing.allocator,
        "input.bc",
        "out.wasm",
        .{ .triple = "wasm32-wasi", .no_entry = true },
        .release_fast,
        false,
    );
    defer wasm.deinit();
    const wasm_args = wasm.slice();
    try std.testing.expectEqualStrings("-target", wasm_args[2]);
    try std.testing.expectEqualStrings("wasm32-wasi", wasm_args[3]);
    try std.testing.expectEqualStrings("-Wl,--no-entry", wasm_args[4]);
    try std.testing.expectEqualStrings("-O3", wasm_args[5]);
    try std.testing.expectEqualStrings("input.bc", wasm_args[6]);
    try std.testing.expectEqualStrings("-o", wasm_args[7]);
}

test "external tool injection fails compile paths before output publication" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(. .sub_path = "input.bc", .data = "not-real-bitcode" });
    const input_path = try tmp.dir.realpathAlloc(std.testing.allocator, "input.bc");
    defer std.testing.allocator.free(input_path);
    const exe_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    const exe_out = try std.fs.path.join(std.testing.allocator, &.{ exe_path, "out.exe" });
    defer std.testing.allocator.free(exe_path);
    defer std.testing.allocator.free(exe_out);

    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    externalToolTestArm("spawn", 0);
    defer externalToolTestDisarm();
    try std.testing.expectError(
        CompileError.ChildProcessFailed,
        compileExe(std.testing.allocator, input_path, exe_out, .release_small, input_path, &.{}, false, stderr_buffer.writer()),
    );
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(exe_out, .{}));
    try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "TestInjectedExternalToolFailure") != null);

    stderr_buffer.clearRetainingCapacity();
    externalToolTestArm("run", 0);
    try std.testing.expectError(
        CompileError.ChildProcessFailed,
        compileObj(std.testing.allocator, input_path, exe_out, .release_small, false, stderr_buffer.writer()),
    );
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(exe_out, .{}));
    try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "TestInjectedExternalToolFailure") != null);
}

fn writeFakeTool(dir: std.fs.Dir, path: []const u8, version: []const u8) !void {
    const source = try std.fmt.allocPrint(std.testing.allocator, "#!/bin/sh\necho {s}\n", .{version});
    defer std.testing.allocator.free(source);
    try dir.writeFile(.{ .sub_path = path, .data = source });
    if (builtin.os.tag != .windows) {
        var file = try dir.openFile(path, .{ .mode = .read_write });
        defer file.close();
        try file.chmod(0o755);
    }
}

test "toolchain cache identity tracks resolved zig executable contents" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("bin");
    try writeFakeTool(tmp.dir, "bin/zig", "zig-tool-v1");
    const bin_path = try tmp.dir.realpathAlloc(std.testing.allocator, "bin");
    defer std.testing.allocator.free(bin_path);

    const first = try toolchainCacheIdentity(std.testing.allocator, .{ .path_env = bin_path });
    defer std.testing.allocator.free(first);
    try std.testing.expect(std.mem.indexOf(u8, first, "zig-tool-v1") != null);

    try writeFakeTool(tmp.dir, "bin/zig", "zig-tool-v2");
    const second = try toolchainCacheIdentity(std.testing.allocator, .{ .path_env = bin_path });
    defer std.testing.allocator.free(second);
    try std.testing.expect(std.mem.indexOf(u8, second, "zig-tool-v2") != null);
    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "toolchain cache identity tracks selected Linux objcopy executable contents" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("bin");
    try writeFakeTool(tmp.dir, "bin/zig", "zig-tool-v1");
    try writeFakeTool(tmp.dir, "bin/llvm-objcopy", "objcopy-tool-v1");
    const bin_path = try tmp.dir.realpathAlloc(std.testing.allocator, "bin");
    defer std.testing.allocator.free(bin_path);

    const first = try toolchainCacheIdentity(std.testing.allocator, .{ .path_env = bin_path, .include_objcopy = true });
    defer std.testing.allocator.free(first);
    try std.testing.expect(std.mem.indexOf(u8, first, "objcopy_candidate=llvm-objcopy") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "objcopy-tool-v1") != null);

    try writeFakeTool(tmp.dir, "bin/llvm-objcopy", "objcopy-tool-v2");
    const second = try toolchainCacheIdentity(std.testing.allocator, .{ .path_env = bin_path, .include_objcopy = true });
    defer std.testing.allocator.free(second);
    try std.testing.expect(std.mem.indexOf(u8, second, "objcopy-tool-v2") != null);
    try std.testing.expect(!std.mem.eql(u8, first, second));
}
