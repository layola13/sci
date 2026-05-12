const std = @import("std");
const saasm = @import("saasm");

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 1 << 20);
}

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn runCommandAnyExit(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

test "sa_std core primitives are concrete and verifiable" {
    const slice_layout = try readFileAlloc(std.testing.allocator, "sa_std/core/slice.saasm-layout");
    defer std.testing.allocator.free(slice_layout);
    try std.testing.expectEqualStrings(
        "#def Slice_SIZE = 16\n#def Slice_ptr  = +0\n#def Slice_len  = +8\n",
        slice_layout,
    );

    const slice_src = try readFileAlloc(std.testing.allocator, "sa_std/core/slice.saasm");
    defer std.testing.allocator.free(slice_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_LEN"));

    var slice_flat = try saasm.flattener.flatten(std.testing.allocator, slice_src);
    defer slice_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.function_sigs.len);

    const mem_src = try readFileAlloc(std.testing.allocator, "sa_std/core/mem.saasm");
    defer std.testing.allocator.free(mem_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_copy"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_set"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "ptr_add"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "br done -> L_END, L_BODY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "stack_alloc 8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "remaining = add count, zero"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "next_remaining = sub remaining, one"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, mem_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, mem_src, 1, "i = 0"));

    var mem_flat = try saasm.flattener.flatten(std.testing.allocator, mem_src);
    defer mem_flat.deinit(std.testing.allocator);
    const verified = try saasm.referee.verify(std.testing.allocator, mem_flat.instructions);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 2), owned.function_sigs.len);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("std smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "std smoke fixture runs through the current compiler surface" {
    const fixture = try readFileAlloc(std.testing.allocator, "tests/std_smoke.saasm");
    defer std.testing.allocator.free(fixture);
    try std.testing.expect(std.mem.containsAtLeast(u8, fixture, 1, "ptr_add"));

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "std_smoke.saasm", fixture);

    const run_argv = [_][]const u8{ "saasm", "run", "std_smoke.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 209), run_code);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "std_smoke.saasm", "-o", "std_smoke.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("std_smoke.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "call ptr @malloc"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "call void @free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "load i8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "store i8"));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{ "./std_smoke.out" });
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 209), code),
        else => return error.TestUnexpectedResult,
    }
}
