const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

pub const Optimization = enum {
    none,
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
    items: std.array_list.Managed([]const u8),

    pub fn slice(self: *const Argv) []const []const u8 {
        return self.items.items;
    }

    pub fn deinit(self: *Argv) void {
        self.items.deinit();
        self.* = undefined;
    }
};

var zig_exe_cache: ?[]const u8 = null;
var zig_exe_mu: std.atomic.Mutex = .unlocked;

/// Absolute path of the `zig` driver, resolved once against the live PATH.
/// See `sio.resolveHostExe`: Zig 0.17 child spawning ignores the live PATH,
/// so a bare "zig" only resolves inside /usr/local/bin:/bin:/usr/bin.
fn zigExe() []const u8 {
    while (!zig_exe_mu.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer zig_exe_mu.unlock();
    if (zig_exe_cache) |p| return p;
    if (sio.resolveHostExe(std.heap.page_allocator, "zig") catch null) |p| {
        zig_exe_cache = p;
        return p;
    }
    return "zig";
}

pub fn argvForExe(
    allocator: std.mem.Allocator,
    artifact_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    sa_std_archive_path: []const u8,
    extra_inputs: []const []const u8,
    debug: bool,
    target_triple: ?[]const u8,
) !Argv {
    var argv = Argv{ .items = std.array_list.Managed([]const u8).init(allocator) };
    errdefer argv.deinit();
    try argv.items.append(zigExe());
    try argv.items.append("cc");
    // NOTE(Zig 0.17): the driver's default UBSan set is much larger than
    // 0.14's; instrumented objects need a ubsan runtime that native glibc
    // links do not provide (undefined __ubsan_handle_*). Disable sanitizers
    // to restore 0.14 link behavior (and remove checking overhead).
    try argv.items.append("-fno-sanitize=all");
    if (target_triple) |triple| {
        try argv.items.append("-target");
        try argv.items.append(triple);
        if (std.mem.indexOf(u8, triple, "windows") != null) {
            // sa_std_windows.zig needs Winsock plus the usual base system libs
            for ([_][]const u8{ "ws2_32", "kernel32", "ntdll", "advapi32", "user32", "bcrypt", "iphlpapi" }) |lib| {
                try argv.items.append("-l");
                try argv.items.append(lib);
            }
        }
    }
    if (debug) {
        try argv.items.append("-g");
    }
    try argv.items.append(if (debug) "-O0" else switch (optimization) {
        .none => "-O0",
        .release_small => "-O1",
        .release_fast => "-O3",
    });
    if (!debug) {
        try argv.items.append("-Wl,--strip-debug");
    }
    try argv.items.append(artifact_path);
    try argv.items.append(sa_std_archive_path);
    if (builtin.os.tag == .windows) {
        // The Windows bootstrap runtime's Winsock-backed UDP/TCP slices use these system libraries.
        try argv.items.append("-lws2_32");
        try argv.items.append("-liphlpapi");
    }
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
    target_triple: ?[]const u8,
) !Argv {
    var argv = Argv{ .items = std.array_list.Managed([]const u8).init(allocator) };
    errdefer argv.deinit();
    try argv.items.append(zigExe());
    try argv.items.append("cc");
    // NOTE(Zig 0.17): see argvForExe — disable the driver's default UBSan set.
    try argv.items.append("-fno-sanitize=all");
    if (target_triple) |triple| {
        try argv.items.append("-target");
        try argv.items.append(triple);
        if (std.mem.indexOf(u8, triple, "windows") != null) {
            // sa_std_windows.zig needs Winsock plus the usual base system libs
            for ([_][]const u8{ "ws2_32", "kernel32", "ntdll", "advapi32", "user32", "bcrypt", "iphlpapi" }) |lib| {
                try argv.items.append("-l");
                try argv.items.append(lib);
            }
        }
    }
    if (debug) {
        try argv.items.append("-g");
    }
    try argv.items.append(if (debug) "-O0" else switch (optimization) {
        .none => "-O0",
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
    var argv = Argv{ .items = std.array_list.Managed([]const u8).init(allocator) };
    errdefer argv.deinit();
    try argv.items.append(zigExe());
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
    sa_std_archive_path: ?[]const u8,
) !Argv {
    var argv = Argv{ .items = std.array_list.Managed([]const u8).init(allocator) };
    errdefer argv.deinit();
    try argv.items.append(zigExe());
    try argv.items.append("cc");
    // NOTE(Zig 0.17): see argvForExe — disable the driver's default UBSan set.
    try argv.items.append("-fno-sanitize=all");
    if (debug) {
        try argv.items.append("-g");
    }
    try argv.items.append("-target");
    try argv.items.append(target.triple);

    if (target.no_entry) {
        try argv.items.append("-Wl,--no-entry");
    }

    try argv.items.append(if (debug) "-O0" else switch (optimization) {
        .none => "-O0",
        .release_small => "-O1",
        .release_fast => "-O3",
    });
    // SIMD128 ships in every supported engine (wasmtime, node16+, bun,
    // evergreen browsers) and is required for any v128 codegen: without it
    // explicit vector kernels scalarize. Placed after -O so the existing
    // positional argv tests are unaffected.
    try argv.items.append("-mcpu=generic+simd128");
    try argv.items.append(artifact_path);
    if (sa_std_archive_path) |archive| {
        try argv.items.append(archive);
    }
    try argv.items.append("-o");
    try argv.items.append(out_path);
    return argv;
}

fn runProcess(allocator: std.mem.Allocator, argv: []const []const u8) !sio.Child.RunResult {
    return try sio.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn runProcessFast(allocator: std.mem.Allocator, argv: []const []const u8) !sio.Child.Term {
    var child = sio.Child.init(argv, allocator);
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

fn printCompilerFailure(writer: anytype, argv: []const []const u8, action: []const u8, input_path: []const u8, out_path: []const u8, result: sio.Child.RunResult) !void {
    switch (result.term) {
        .exited => |code| try writer.print("error[ExternalCompiler]: zig cc exited with code {d} while {s} {s} -> {s}\n", .{ code, action, input_path, out_path }),
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
    target_triple: ?[]const u8,
) !void {
    var argv = try argvForExe(allocator, artifact_path, out_path, optimization, sa_std_archive_path, extra_inputs, debug, target_triple);
    defer argv.deinit();
    const argv_slice = argv.slice();
    const term = runProcessFast(allocator, argv_slice) catch |err| {
        try printCompilerLaunchFailure(stderr, argv_slice, "linking", artifact_path, out_path, err);
        return CompileError.ChildProcessFailed;
    };

    const failed = switch (term) {
        .exited => |code| code != 0,
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
    target_triple: ?[]const u8,
) !void {
    var argv = try argvForObj(allocator, artifact_path, out_path, optimization, debug, target_triple);
    defer argv.deinit();
    const argv_slice = argv.slice();
    const term = runProcessFast(allocator, argv_slice) catch |err| {
        try printCompilerLaunchFailure(stderr, argv_slice, "compiling object", artifact_path, out_path, err);
        return CompileError.ChildProcessFailed;
    };

    const failed = switch (term) {
        .exited => |code| code != 0,
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
        .exited => |code| code != 0,
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
}

/// Export-surface control for a shared library link. Exactly one of the
/// three mechanisms is used per target family: ELF version script, Mach-O
/// exported symbols list, or a PE module-definition (.def) file. The -Wl
/// argument strings are pre-formatted and owned by the caller (the driver
/// only borrows the slices, like every other argv builder in this file);
/// the import library argument only applies to PE targets.
pub const SharedExportControl = struct {
    soname_arg: ?[]const u8 = null,
    version_script_arg: ?[]const u8 = null,
    exported_symbols_list_arg: ?[]const u8 = null,
    def_file_path: ?[]const u8 = null,
    implib_arg: ?[]const u8 = null,
};

pub fn argvForShared(
    allocator: std.mem.Allocator,
    object_path: []const u8,
    api_source_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    sa_std_archive_path: []const u8,
    debug: bool,
    target_triple: ?[]const u8,
    export_control: SharedExportControl,
) !Argv {
    var argv = Argv{ .items = std.array_list.Managed([]const u8).init(allocator) };
    errdefer argv.deinit();
    try argv.items.append(zigExe());
    try argv.items.append("cc");
    // NOTE(Zig 0.17): see argvForExe — disable the driver's default UBSan set.
    try argv.items.append("-fno-sanitize=all");
    if (target_triple) |triple| {
        try argv.items.append("-target");
        try argv.items.append(triple);
        if (std.mem.indexOf(u8, triple, "windows") != null) {
            // sa_std_windows.zig needs Winsock plus the usual base system libs
            for ([_][]const u8{ "ws2_32", "kernel32", "ntdll", "advapi32", "user32", "bcrypt", "iphlpapi" }) |lib| {
                try argv.items.append("-l");
                try argv.items.append(lib);
            }
        }
    }
    if (debug) {
        try argv.items.append("-g");
    }
    try argv.items.append(if (debug) "-O0" else switch (optimization) {
        .none => "-O0",
        .release_small => "-O1",
        .release_fast => "-O3",
    });
    if (!debug) {
        try argv.items.append("-Wl,--strip-debug");
    }
    try argv.items.append("-shared");
    try argv.items.append("-fPIC");
    try argv.items.append(object_path);
    try argv.items.append(api_source_path);
    try argv.items.append(sa_std_archive_path);
    if (builtin.os.tag == .windows) {
        try argv.items.append("-lws2_32");
        try argv.items.append("-liphlpapi");
    }
    if (export_control.soname_arg) |arg| {
        try argv.items.append(arg);
    }
    if (export_control.version_script_arg) |arg| {
        try argv.items.append(arg);
    }
    if (export_control.exported_symbols_list_arg) |arg| {
        try argv.items.append(arg);
    }
    if (export_control.def_file_path) |def_path| {
        try argv.items.append(def_path);
    }
    if (export_control.implib_arg) |arg| {
        try argv.items.append(arg);
    }
    try argv.items.append("-o");
    try argv.items.append(out_path);
    return argv;
}

pub fn argvForArchive(
    allocator: std.mem.Allocator,
    out_path: []const u8,
    input_objects: []const []const u8,
) !Argv {
    var argv = Argv{ .items = std.array_list.Managed([]const u8).init(allocator) };
    errdefer argv.deinit();
    try argv.items.append(zigExe());
    try argv.items.append("ar");
    try argv.items.append("rcs");
    try argv.items.append(out_path);
    for (input_objects) |input| {
        try argv.items.append(input);
    }
    return argv;
}

pub fn compileShared(
    allocator: std.mem.Allocator,
    object_path: []const u8,
    api_source_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    sa_std_archive_path: []const u8,
    debug: bool,
    stderr: anytype,
    target_triple: ?[]const u8,
    export_control: SharedExportControl,
) !void {
    var argv = try argvForShared(allocator, object_path, api_source_path, out_path, optimization, sa_std_archive_path, debug, target_triple, export_control);
    defer argv.deinit();
    const argv_slice = argv.slice();
    const term = runProcessFast(allocator, argv_slice) catch |err| {
        try printCompilerLaunchFailure(stderr, argv_slice, "linking shared library", object_path, out_path, err);
        return CompileError.ChildProcessFailed;
    };

    const failed = switch (term) {
        .exited => |code| code != 0,
        else => true,
    };
    if (failed) {
        const result = runProcess(allocator, argv_slice) catch |err| {
            try printCompilerLaunchFailure(stderr, argv_slice, "linking shared library", object_path, out_path, err);
            return CompileError.ChildProcessFailed;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try printCompilerFailure(stderr, argv_slice, "linking shared library", object_path, out_path, result);
        return CompileError.ChildProcessFailed;
    }
}

pub fn compileArchive(
    allocator: std.mem.Allocator,
    out_path: []const u8,
    input_objects: []const []const u8,
    stderr: anytype,
) !void {
    var argv = try argvForArchive(allocator, out_path, input_objects);
    defer argv.deinit();
    const argv_slice = argv.slice();
    const term = runProcessFast(allocator, argv_slice) catch |err| {
        try printCompilerLaunchFailure(stderr, argv_slice, "archiving static library", input_objects[0], out_path, err);
        return CompileError.ChildProcessFailed;
    };

    const failed = switch (term) {
        .exited => |code| code != 0,
        else => true,
    };
    if (failed) {
        const result = runProcess(allocator, argv_slice) catch |err| {
            try printCompilerLaunchFailure(stderr, argv_slice, "archiving static library", input_objects[0], out_path, err);
            return CompileError.ChildProcessFailed;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try printCompilerFailure(stderr, argv_slice, "archiving static library", input_objects[0], out_path, result);
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
    sa_std_archive_path: ?[]const u8,
    stderr: anytype,
) !void {
    var argv = try argvForWasm(allocator, artifact_path, out_path, target, optimization, debug, sa_std_archive_path);
    defer argv.deinit();
    const argv_slice = argv.slice();
    const term = runProcessFast(allocator, argv_slice) catch |err| {
        try printCompilerLaunchFailure(stderr, argv_slice, "linking wasm", artifact_path, out_path, err);
        return CompileError.ChildProcessFailed;
    };

    const failed = switch (term) {
        .exited => |code| code != 0,
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
    var exe_small = try argvForExe(std.testing.allocator, "input.bc", "out.exe", .release_small, "/repo/artifacts/sa_std/libsa_std.a", &.{}, false, null);
    defer exe_small.deinit();
    try std.testing.expectEqualStrings("-O1", exe_small.slice()[3]);
    try std.testing.expectEqualStrings("-Wl,--strip-debug", exe_small.slice()[4]);
    try std.testing.expectEqualStrings("/repo/artifacts/sa_std/libsa_std.a", exe_small.slice()[6]);
    var exe_fast = try argvForExe(std.testing.allocator, "input.bc", "out.exe", .release_fast, "/repo/artifacts/sa_std/libsa_std.a", &.{}, false, null);
    defer exe_fast.deinit();
    try std.testing.expectEqualStrings("-O3", exe_fast.slice()[3]);
    try std.testing.expectEqualStrings("-Wl,--strip-debug", exe_fast.slice()[4]);

    var exe_debug = try argvForExe(std.testing.allocator, "input.bc", "out.exe", .release_fast, "/repo/artifacts/sa_std/libsa_std.a", &.{}, true, null);
    defer exe_debug.deinit();
    try std.testing.expectEqualStrings("-g", exe_debug.slice()[3]);
    try std.testing.expectEqualStrings("-O0", exe_debug.slice()[4]);
    for (exe_debug.slice()) |arg| {
        try std.testing.expect(!std.mem.eql(u8, arg, "-Wl,--strip-debug"));
    }

    var wasm_small = try argvForWasm(std.testing.allocator, "input.bc", "out.wasm", .{ .triple = "wasm32-wasi" }, .release_small, false, null);
    defer wasm_small.deinit();
    try std.testing.expectEqualStrings("-O1", wasm_small.slice()[5]);
    var wasm_fast = try argvForWasm(std.testing.allocator, "input.bc", "out.wasm", .{ .triple = "wasm32-wasi", .no_entry = true }, .release_fast, false, null);
    defer wasm_fast.deinit();
    try std.testing.expectEqualStrings("-O3", wasm_fast.slice()[6]);
    var wasm_std = try argvForWasm(std.testing.allocator, "input.bc", "out.wasm", .{ .triple = "wasm32-wasi" }, .release_fast, false, "/repo/libsa_std.a");
    defer wasm_std.deinit();
    try std.testing.expectEqualStrings("/repo/libsa_std.a", wasm_std.slice()[wasm_std.slice().len - 3]);
}

test "argv helpers for library targets carry the export control" {
    const alloc = std.testing.allocator;
    var shared = try argvForShared(alloc, "prog.o", "api.c", "out/libdemo.so", .release_fast, "/repo/libsa_std.a", false, null, .{
        .soname_arg = "-Wl,-soname,libdemo.so",
        .version_script_arg = "-Wl,--version-script,exports.map",
    });
    defer shared.deinit();
    var saw_shared = false;
    var saw_pic = false;
    var saw_script = false;
    for (shared.slice()) |arg| {
        if (std.mem.eql(u8, arg, "-shared")) saw_shared = true;
        if (std.mem.eql(u8, arg, "-fPIC")) saw_pic = true;
        if (std.mem.eql(u8, arg, "-Wl,--version-script,exports.map")) saw_script = true;
    }
    try std.testing.expect(saw_shared);
    try std.testing.expect(saw_pic);
    try std.testing.expect(saw_script);
    try std.testing.expectEqualStrings("out/libdemo.so", shared.slice()[shared.slice().len - 1]);

    var shared_pe = try argvForShared(alloc, "prog.o", "api.c", "demo.dll", .none, "/repo/sa_std.lib", false, "x86_64-windows-gnu", .{
        .def_file_path = "demo.def",
        .implib_arg = "-Wl,--out-implib,demo.lib",
    });
    defer shared_pe.deinit();
    var saw_def = false;
    var saw_implib = false;
    for (shared_pe.slice()) |arg| {
        if (std.mem.eql(u8, arg, "demo.def")) saw_def = true;
        if (std.mem.eql(u8, arg, "-Wl,--out-implib,demo.lib")) saw_implib = true;
    }
    try std.testing.expect(saw_def);
    try std.testing.expect(saw_implib);

    var archive = try argvForArchive(alloc, "libdemo.a", &.{ "combined.o", "extra.o" });
    defer archive.deinit();
    try std.testing.expectEqualStrings("ar", archive.slice()[1]);
    try std.testing.expectEqualStrings("rcs", archive.slice()[2]);
    try std.testing.expectEqualStrings("libdemo.a", archive.slice()[3]);
    try std.testing.expectEqualStrings("extra.o", archive.slice()[archive.slice().len - 1]);
}
