const std = @import("std");
const saasm = @import("saasm");

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

test "ffi handle demo exposes an exported C ABI symbol" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const sa_source = try original_cwd.realpathAlloc(std.testing.allocator, "tests/integration/ffi_handle/handle.saasm");
    defer std.testing.allocator.free(sa_source);
    const c_source = try original_cwd.realpathAlloc(std.testing.allocator, "tests/integration/ffi_handle/handle_host.c");
    defer std.testing.allocator.free(c_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_obj_argv = [_][]const u8{ "saasm", "build-obj", sa_source, "-o", "handle.o" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]));

    const ll_file = try std.fs.cwd().openFile("handle.o.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define i32 @ffi_handle_roundtrip()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "declare i32 @handle_new()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "declare i32 @handle_get(i32)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "declare void @handle_drop(i32)"));

    const nm_output = try runCommand(std.testing.allocator, &[_][]const u8{ "nm", "-g", "--defined-only", "handle.o" });
    defer std.testing.allocator.free(nm_output);
    try std.testing.expect(std.mem.containsAtLeast(u8, nm_output, 1, " ffi_handle_roundtrip"));

    const cc_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        c_source,
        "handle.o",
        "-o",
        "handle_demo",
    };
    const cc_result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = cc_argv[0..],
    });
    defer std.testing.allocator.free(cc_result.stdout);
    defer std.testing.allocator.free(cc_result.stderr);
    switch (cc_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }

    const output = try runCommand(std.testing.allocator, &[_][]const u8{ "./handle_demo" });
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("42\n", output);
}
