const std = @import("std");

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) return error.TestUnexpectedResult;
        },
        else => return error.TestUnexpectedResult,
    }

    return result.stdout;
}

test "libsa_scope C-ABI demo emits release text" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const lib_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/libsa_scope.zig");
    defer std.testing.allocator.free(lib_source);
    const c_source = try original_cwd.realpathAlloc(std.testing.allocator, "tests/integration/libsa_scope_demo/main.c");
    defer std.testing.allocator.free(c_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const lib_path = "libsa_scope.a";
    const exe_path = "libsa_scope_demo";

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        lib_source,
        "-O",
        "Debug",
        "-femit-bin=libsa_scope.a",
    };
    const build_lib_result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = build_lib_argv[0..],
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    switch (build_lib_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        c_source,
        lib_path,
        "-o",
        exe_path,
    };
    const build_demo_result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = build_demo_argv[0..],
    });
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    switch (build_demo_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }

    const run_output = try runCommand(std.testing.allocator, &[_][]const u8{ "./libsa_scope_demo" });
    defer std.testing.allocator.free(run_output);
    try std.testing.expectEqualStrings("!temp\n!root\n", run_output);
}
