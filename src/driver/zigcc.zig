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
    items: [16][]const u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const Argv) []const []const u8 {
        return self.items[0..self.len];
    }
};

pub fn argvForExe(
    ll_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    sa_std_archive_path: []const u8,
    debug: bool,
) Argv {
    var argv: Argv = .{};
    argv.items[0] = "zig";
    argv.items[1] = "cc";
    var index: usize = 2;
    if (debug) {
        argv.items[index] = "-g";
        index += 1;
    }
    argv.items[index] = if (debug) "-O0" else switch (optimization) {
        .release_small => "-O1",
        .release_fast => "-O3",
    };
    index += 1;
    argv.items[index] = ll_path;
    index += 1;
    argv.items[index] = sa_std_archive_path;
    index += 1;
    argv.items[index] = "-o";
    index += 1;
    argv.items[index] = out_path;
    index += 1;
    argv.len = index;
    return argv;
}

pub fn argvForObj(
    ll_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    debug: bool,
) Argv {
    var argv: Argv = .{};
    argv.items[0] = "zig";
    argv.items[1] = "cc";
    var index: usize = 2;
    if (debug) {
        argv.items[index] = "-g";
        index += 1;
    }
    argv.items[index] = if (debug) "-O0" else switch (optimization) {
        .release_small => "-O1",
        .release_fast => "-O3",
    };
    index += 1;
    argv.items[index] = "-c";
    index += 1;
    argv.items[index] = ll_path;
    index += 1;
    argv.items[index] = "-o";
    index += 1;
    argv.items[index] = out_path;
    index += 1;
    argv.len = index;
    return argv;
}

pub fn argvForWasm(
    ll_path: []const u8,
    out_path: []const u8,
    target: Target,
    optimization: Optimization,
    debug: bool,
) Argv {
    var argv: Argv = .{};
    argv.items[0] = "zig";
    argv.items[1] = "cc";
    var index: usize = 2;
    if (debug) {
        argv.items[index] = "-g";
        index += 1;
    }
    argv.items[index] = "-target";
    index += 1;
    argv.items[index] = target.triple;
    index += 1;

    if (target.no_entry) {
        argv.items[index] = "-Wl,--no-entry";
        index += 1;
    }

    argv.items[index] = if (debug) "-O0" else switch (optimization) {
        .release_small => "-O1",
        .release_fast => "-O3",
    };
    index += 1;
    argv.items[index] = ll_path;
    index += 1;
    argv.items[index] = "-o";
    index += 1;
    argv.items[index] = out_path;
    index += 1;
    argv.len = index;
    return argv;
}

fn runProcess(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stderr.len != 0) {
        try std.io.getStdErr().writeAll(result.stderr);
    }

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) return CompileError.ChildProcessFailed;
        },
        else => return CompileError.ChildProcessFailed,
    }
}

pub fn compileExe(
    allocator: std.mem.Allocator,
    ll_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    sa_std_archive_path: []const u8,
    debug: bool,
) !void {
    const argv = argvForExe(ll_path, out_path, optimization, sa_std_archive_path, debug);
    try runProcess(allocator, argv.slice());
}

pub fn compileObj(
    allocator: std.mem.Allocator,
    ll_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
    debug: bool,
) !void {
    const argv = argvForObj(ll_path, out_path, optimization, debug);
    try runProcess(allocator, argv.slice());
}

pub fn compileWasm(
    allocator: std.mem.Allocator,
    ll_path: []const u8,
    out_path: []const u8,
    target: Target,
    optimization: Optimization,
    debug: bool,
) !void {
    const argv = argvForWasm(ll_path, out_path, target, optimization, debug);
    try runProcess(allocator, argv.slice());
}

test "argv helpers choose the requested optimization" {
    const exe_small = argvForExe("input.ll", "out.exe", .release_small, "/repo/artifacts/sa_std/libsa_std.a");
    try std.testing.expectEqualStrings("-O1", exe_small.slice()[2]);
    try std.testing.expectEqualStrings("/repo/artifacts/sa_std/libsa_std.a", exe_small.slice()[4]);
    const exe_fast = argvForExe("input.ll", "out.exe", .release_fast, "/repo/artifacts/sa_std/libsa_std.a");
    try std.testing.expectEqualStrings("-O3", exe_fast.slice()[2]);

    const wasm_small = argvForWasm("input.ll", "out.wasm", .{ .triple = "wasm32-wasi" }, .release_small);
    try std.testing.expectEqualStrings("-O1", wasm_small.slice()[4]);
    const wasm_fast = argvForWasm("input.ll", "out.wasm", .{ .triple = "wasm32-wasi", .no_entry = true }, .release_fast);
    try std.testing.expectEqualStrings("-O3", wasm_fast.slice()[5]);
}
