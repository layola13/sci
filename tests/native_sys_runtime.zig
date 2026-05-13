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

test "native sys runtime stub compiles to object and links through zig cc" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/native_sys.zig");
    defer std.testing.allocator.free(runtime_source);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const io_demo =
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <stdlib.h>
        \\#include <string.h>
        \\
        \\extern void sys_print(const uint8_t *data, uint64_t len);
        \\extern int32_t sys_argc(void);
        \\extern const char *sys_argv(uint64_t index);
        \\extern uint8_t *sys_read_file(const uint8_t *path, uint64_t path_len, uint64_t *out_len);
        \\extern int32_t sys_write_file(const uint8_t *path, uint64_t path_len, const uint8_t *data, uint64_t data_len);
        \\
        \\int main(int argc, char **argv) {
        \\    const uint8_t msg[] = "native sys ok\n";
        \\    const uint8_t path[] = "native_sys_io.txt";
        \\    const uint8_t payload[] = "hello";
        \\    uint64_t len = 0;
        \\    uint8_t *buf = NULL;
        \\
        \\    if (sys_argc() < 1) return 2;
        \\    if (sys_argv(0) == NULL) return 3;
        \\    if (strcmp(sys_argv(0), argv[0]) != 0) return 4;
        \\    if (argc >= 2 && strcmp(sys_argv(1), argv[1]) != 0) return 5;
        \\    sys_print(msg, sizeof(msg) - 1);
        \\    if (sys_write_file(path, sizeof(path) - 1, payload, sizeof(payload) - 1) != 5) return 6;
        \\    buf = sys_read_file(path, sizeof(path) - 1, &len);
        \\    if (buf == NULL) return 7;
        \\    if (len != 5) return 8;
        \\    if (memcmp(buf, payload, 5) != 0) return 9;
        \\    free(buf);
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "native_sys_io.c", io_demo);

    const exit_demo =
        \\#include <stdint.h>
        \\
        \\extern void sys_exit(int32_t code);
        \\
        \\int main(void) {
        \\    sys_exit(37);
        \\}
        \\
    ;
    try writeSource(tmp.dir, "native_sys_exit.c", exit_demo);

    const build_obj_argv = [_][]const u8{
        "zig",
        "build-obj",
        runtime_source,
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=native_sys.o",
    };
    const build_obj_result = try runCommand(std.testing.allocator, build_obj_argv[0..]);
    defer std.testing.allocator.free(build_obj_result.stdout);
    defer std.testing.allocator.free(build_obj_result.stderr);
    try expectSuccess(build_obj_result);

    const build_io_argv = [_][]const u8{
        "zig",
        "cc",
        "native_sys_io.c",
        "native_sys.o",
        "-o",
        "native_sys_io_demo",
    };
    const build_io_result = try runCommand(std.testing.allocator, build_io_argv[0..]);
    defer std.testing.allocator.free(build_io_result.stdout);
    defer std.testing.allocator.free(build_io_result.stderr);
    try expectSuccess(build_io_result);

    const io_result = try runCommand(std.testing.allocator, &[_][]const u8{ "./native_sys_io_demo", "marker" });
    defer std.testing.allocator.free(io_result.stdout);
    defer std.testing.allocator.free(io_result.stderr);
    try expectSuccess(io_result);
    try std.testing.expectEqualStrings("native sys ok\n", io_result.stdout);

    const build_exit_argv = [_][]const u8{
        "zig",
        "cc",
        "native_sys_exit.c",
        "native_sys.o",
        "-o",
        "native_sys_exit_demo",
    };
    const build_exit_result = try runCommand(std.testing.allocator, build_exit_argv[0..]);
    defer std.testing.allocator.free(build_exit_result.stdout);
    defer std.testing.allocator.free(build_exit_result.stderr);
    try expectSuccess(build_exit_result);

    const exit_result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "./native_sys_exit_demo" },
    });
    defer std.testing.allocator.free(exit_result.stdout);
    defer std.testing.allocator.free(exit_result.stderr);
    switch (exit_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 37), code),
        else => return error.TestUnexpectedResult,
    }
}
