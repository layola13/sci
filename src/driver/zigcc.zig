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

fn hostRpathArgument(os_tag: std.Target.Os.Tag) ?[]const u8 {
    return switch (os_tag) {
        .linux => "-Wl,-rpath,$ORIGIN",
        .macos => "-Wl,-rpath,@loader_path",
        else => null,
    };
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
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn runProcessFast(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.Term {
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
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ candidate, "--localize-hidden", object_path, staging_path },
        }) catch |err| switch (err) {
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
}
