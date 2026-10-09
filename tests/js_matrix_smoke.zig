const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");

// JS backend equivalence matrix: `sa build-js` output executed with node
// must match the expected stdout of each demo (verified against native
// build-exe during development). Pure Zig backend: no LLVM required.

fn runJsWithNode(allocator: std.mem.Allocator, js_path: []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", js_path },
    });
}

fn elapsedMs(start_ns: i128) i128 {
    return @divTrunc(std.time.nanoTimestamp() - start_ns, std.time.ns_per_ms);
}

fn assertJsMatrixStdout(path: []const u8, expected_stdout: []const u8) !void {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const node_probe = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const repo_root = try original_cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    const demo_start = std.time.nanoTimestamp();
    std.debug.print("[js-matrix] START demo={s}\n", .{path});
    var demo_ended = false;
    errdefer {
        if (!demo_ended) std.debug.print("[js-matrix] FAIL demo={s}\n", .{path});
    }

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const base = std.fs.path.basename(path);
    const stem = std.fs.path.stem(base);
    const parent = std.fs.path.dirname(path) orelse ".";
    const tag = std.fs.path.basename(parent);
    const js_name = try std.fmt.allocPrint(std.testing.allocator, "{s}_{s}.mjs", .{ tag, stem });
    defer std.testing.allocator.free(js_name);

    const build_js_argv = [_][]const u8{ "sa", "build-js", source_path, "-o", js_name, "--project-root", repo_root };
    const build_js_code = saasm.cli.execute(std.testing.allocator, build_js_argv[0..]) catch |err| {
        std.debug.print("build-js errored: {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
    if (build_js_code != 0) std.debug.print("build-js failed: {s}\n", .{path});
    try std.testing.expectEqual(@as(u8, 0), build_js_code);

    const js_file = try tmp.dir.openFile(js_name, .{});
    defer js_file.close();
    const js_bytes = try js_file.readToEndAlloc(std.testing.allocator, 1 << 24);
    defer std.testing.allocator.free(js_bytes);
    try std.testing.expect(js_bytes.len > 64);

    const js_result = try runJsWithNode(std.testing.allocator, js_name);
    defer std.testing.allocator.free(js_result.stdout);
    defer std.testing.allocator.free(js_result.stderr);
    switch (js_result.term) {
        .Exited => |code| {
            if (code != 0 or !std.mem.eql(u8, js_result.stdout, expected_stdout) or js_result.stderr.len != 0) {
                std.debug.print("js demo failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, js_result.stdout, js_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings(expected_stdout, js_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), js_result.stderr.len);

    std.debug.print("[js-matrix] END   demo={s} elapsed={}ms\n", .{ path, elapsedMs(demo_start) });
    demo_ended = true;
}

test "js backend rosetta demos match expected output under node" {
    try assertJsMatrixStdout("demos/rosetta/01_hello_world/main.sa", "hello, saasm\n");
    try assertJsMatrixStdout("demos/rosetta/03_if_else/main.sa", "20\n");
    try assertJsMatrixStdout("demos/rosetta/04_loop/main.sa", "[0,0,0,0]\n");
    try assertJsMatrixStdout("demos/rosetta/05_struct/main.sa", "(10,20)\n");
    try assertJsMatrixStdout("demos/rosetta/13_array_sum/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/112_raw_pointer_arithmetic/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/22_break_continue/main.sa", "9\n");
}
