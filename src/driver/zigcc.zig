const std = @import("std");

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
    try argv.items.append("-Wl,-rpath,$ORIGIN");
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
