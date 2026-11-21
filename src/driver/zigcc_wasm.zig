const std = @import("std");
const Argv = @import("zigcc.zig").Argv;
const CompileError = @import("zigcc.zig").CompileError;
const Optimization = @import("zigcc.zig").Optimization;
const Target = @import("zigcc.zig").Target;
const argvForExe = @import("zigcc.zig").argvForExe;
const printCompilerFailure = @import("zigcc.zig").printCompilerFailure;
const printCompilerLaunchFailure = @import("zigcc.zig").printCompilerLaunchFailure;
const runProcess = @import("zigcc.zig").runProcess;
const runProcessFast = @import("zigcc.zig").runProcessFast;
const zigExe = @import("zigcc.zig").zigExe;

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
    if (!debug) {
        // Mirror argvForExe: the emitted bitcode carries DWARF (cc1 runs
        // with -debug-info-kind=constructor) and wasm-ld copies those
        // sections into the output -- on hello they are ~1.2 MB of the
        // 1.45 MB module. The sa_std archive is already stripped at build
        // time (04fd392d); this flag covers the program-object half.
        // Placed after -O/-mcpu so the positional argv tests are unaffected.
        try argv.items.append("-Wl,--strip-debug");
    }
    try argv.items.append(artifact_path);
    if (sa_std_archive_path) |archive| {
        try argv.items.append(archive);
    }
    try argv.items.append("-o");
    try argv.items.append(out_path);
    return argv;
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
