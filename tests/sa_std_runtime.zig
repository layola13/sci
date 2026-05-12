const std = @import("std");

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn expectSuccess(result: std.process.Child.RunResult) !void {
    if (result.stderr.len != 0) {
        std.debug.print("{s}", .{result.stderr});
    }
    switch (result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "sa_std static library exposes a usable C ABI" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t *path = (const uint8_t *)"abi.txt";
        \\    const uint8_t *data = (const uint8_t *)"hello";
        \\    uint64_t handle = 0;
        \\    uint64_t count = 0;
        \\    uint8_t buffer[16] = {0};
        \\
        \\    if (sa_std_version() != SA_STD_ABI_VERSION) return 2;
        \\    if (sa_std_fs_open_write(path, 7, 1, &handle) != SA_STD_OK) return 3;
        \\    if (sa_std_write(handle, data, 5, &count) != SA_STD_OK || count != 5) return 4;
        \\    if (sa_std_close(handle) != SA_STD_OK) return 5;
        \\
        \\    count = 0;
        \\    if (sa_std_fs_len(path, 7, &count) != SA_STD_OK || count != 5) return 6;
        \\    if (sa_std_fs_open_read(path, 7, &handle) != SA_STD_OK) return 7;
        \\    if (sa_std_read(handle, buffer, sizeof(buffer), &count) != SA_STD_OK || count != 5) return 8;
        \\    if (memcmp(buffer, data, 5) != 0) return 9;
        \\    if (sa_std_close(handle) != SA_STD_OK) return 10;
        \\
        \\    count = 0;
        \\    if (sa_std_error_name(SA_STD_ERR_NOT_FOUND, buffer, sizeof(buffer), &count) != SA_STD_OK) return 11;
        \\    if (count != 9 || memcmp(buffer, "not_found", 9) != 0) return 12;
        \\    if (sa_std_fs_remove(path, 7) != SA_STD_OK) return 13;
        \\
        \\    puts("sa_std abi ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "main.c", c_source);

    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        "-O",
        "Debug",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try expectSuccess(build_lib_result);

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-o",
        "sa_std_c_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_c_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expectEqualStrings("sa_std abi ok\n", run_result.stdout);
}
