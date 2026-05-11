const std = @import("std");
const saasm = @import("saasm");

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

test "cli run/build-exe/build-wasm produce real artifacts" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\!node
        \\return 7
    ;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();

    try writeSource(tmp.dir, "sample.saasm", source);

    const run_argv = [_][]const u8{ "saasm", "run", "sample.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 7), run_code);

    const exe_path = "sample.out";
    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "sample.saasm", "-o", exe_path };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe = try tmp.dir.openFile(exe_path, .{});
    defer exe.close();
    const exe_bytes = try exe.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(exe_bytes);
    try std.testing.expect(exe_bytes.len > 0);

    const obj_path = "sample.o";
    const build_obj_argv = [_][]const u8{ "saasm", "build-obj", "sample.saasm", "-o", obj_path };
    const obj_code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), obj_code);

    const obj = try tmp.dir.openFile(obj_path, .{});
    defer obj.close();
    const obj_bytes = try obj.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(obj_bytes);
    try std.testing.expect(obj_bytes.len > 0);

    const wasm_path = "sample.wasm";
    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", "sample.saasm", "-o", wasm_path, "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm = try tmp.dir.openFile(wasm_path, .{});
    defer wasm.close();
    const wasm_bytes = try wasm.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);
}
