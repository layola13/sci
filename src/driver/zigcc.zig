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
    items: [10][]const u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const Argv) []const []const u8 {
        return self.items[0..self.len];
    }
};

pub fn argvForExe(
    ll_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
) Argv {
    var argv: Argv = .{};
    argv.items[0] = "zig";
    argv.items[1] = "cc";
    argv.items[2] = switch (optimization) {
        .release_small => "-O1",
        .release_fast => "-O3",
    };
    argv.items[3] = ll_path;
    argv.items[4] = "-o";
    argv.items[5] = out_path;
    argv.len = 6;
    return argv;
}

pub fn argvForObj(
    ll_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
) Argv {
    var argv: Argv = .{};
    argv.items[0] = "zig";
    argv.items[1] = "cc";
    argv.items[2] = switch (optimization) {
        .release_small => "-O1",
        .release_fast => "-O3",
    };
    argv.items[3] = "-c";
    argv.items[4] = ll_path;
    argv.items[5] = "-o";
    argv.items[6] = out_path;
    argv.len = 7;
    return argv;
}

pub fn argvForWasm(
    ll_path: []const u8,
    out_path: []const u8,
    target: Target,
    optimization: Optimization,
) Argv {
    var argv: Argv = .{};
    argv.items[0] = "zig";
    argv.items[1] = "cc";
    argv.items[2] = "-target";
    argv.items[3] = target.triple;

    var index: usize = 4;
    if (target.no_entry) {
        argv.items[index] = "-Wl,--no-entry";
        index += 1;
    }

    argv.items[index] = switch (optimization) {
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
) !void {
    const argv = argvForExe(ll_path, out_path, optimization);
    try runProcess(allocator, argv.slice());
}

pub fn compileObj(
    allocator: std.mem.Allocator,
    ll_path: []const u8,
    out_path: []const u8,
    optimization: Optimization,
) !void {
    const argv = argvForObj(ll_path, out_path, optimization);
    try runProcess(allocator, argv.slice());
}

pub fn compileWasm(
    allocator: std.mem.Allocator,
    ll_path: []const u8,
    out_path: []const u8,
    target: Target,
    optimization: Optimization,
) !void {
    const argv = argvForWasm(ll_path, out_path, target, optimization);
    try runProcess(allocator, argv.slice());
}

test "argv helpers choose the requested optimization" {
    const exe_small = argvForExe("input.ll", "out.exe", .release_small);
    try std.testing.expectEqualStrings("-O1", exe_small.slice()[2]);
    const exe_fast = argvForExe("input.ll", "out.exe", .release_fast);
    try std.testing.expectEqualStrings("-O3", exe_fast.slice()[2]);

    const wasm_small = argvForWasm("input.ll", "out.wasm", .{ .triple = "wasm32-wasi" }, .release_small);
    try std.testing.expectEqualStrings("-O1", wasm_small.slice()[4]);
    const wasm_fast = argvForWasm("input.ll", "out.wasm", .{ .triple = "wasm32-wasi", .no_entry = true }, .release_fast);
    try std.testing.expectEqualStrings("-O3", wasm_fast.slice()[5]);
}
