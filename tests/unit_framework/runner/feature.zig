const std = @import("std");
const builtin = @import("builtin");
const saasm = @import("saasm");
const sio = @import("sio");
const buildSaTestExpectations = @import("queue.zig").buildSaTestExpectations;
const endSaFileLog = @import("util.zig").endSaFileLog;
const errorSaFileLog = @import("util.zig").errorSaFileLog;
const expectContains = @import("util.zig").expectContains;
const expectNotContains = @import("util.zig").expectNotContains;
const saTestJobsArg = @import("util.zig").saTestJobsArg;
const startSaFileLog = @import("util.zig").startSaFileLog;
const writeSource = @import("util.zig").writeSource;

test "native unit framework suite covers the demo-derived feature matrix" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const suite_path = try sio.cwd().realpathAlloc(std.testing.allocator, "tests/unit_framework/feature_suite.sa");
    defer std.testing.allocator.free(suite_path);
    const jobs_arg = try saTestJobsArg(std.testing.allocator);
    defer std.testing.allocator.free(jobs_arg);
    const start_ns = startSaFileLog("tests/unit_framework/feature_suite.sa", "all-modes", jobs_arg, 0, 0);
    // NOTE(Zig 0.17): `errdefer |err|` payload capture was removed after 0.14;
    // inner function + explicit catch preserves the structured error log marker.
    featureSuiteAllModesInner(suite_path, jobs_arg, start_ns) catch |err| {
        errorSaFileLog("tests/unit_framework/feature_suite.sa", "all-modes", 0, 0, err);
        return err;
    };
}

pub fn featureSuiteAllModesInner(suite_path: []const u8, jobs_arg: []const u8, start_ns: i128) !void {
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();
    var total_stdout_bytes: usize = 0;
    var total_stderr_bytes: usize = 0;

    const default_argv = [_][]const u8{ "sa", "test", suite_path, "--jobs", jobs_arg };
    const default_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        default_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (default_code != 0) {
        std.debug.print("stdout: {s}\n", .{stdout_buffer.items});
        std.debug.print("stderr: {s}\n", .{stderr_buffer.items});
    }
    try std.testing.expectEqual(@as(u8, 0), default_code);
    const default_expectations = try buildSaTestExpectations(std.testing.allocator, "tests/unit_framework/feature_suite.sa");
    defer default_expectations.deinit(std.testing.allocator);
    for (default_expectations.expected_passes) |expected_pass| {
        try expectContains(stdout_buffer.items, expected_pass);
    }
    for (default_expectations.expected_absent_passes) |absent_pass| {
        try expectNotContains(stdout_buffer.items, absent_pass);
    }
    try expectContains(stdout_buffer.items, default_expectations.expected_summary);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    total_stdout_bytes += stdout_buffer.items.len;
    total_stderr_bytes += stderr_buffer.items.len;

    var ignored_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer ignored_tmp.cleanup();
    try writeSource(ignored_tmp.dir, "ignored_modes.sa",
        \\@test "small normal case"():
        \\L_ENTRY:
        \\    return
        \\
        \\@test ignored "small ignored case"():
        \\L_ENTRY:
        \\    return
        \\
    );
    const ignored_path = try ignored_tmp.dir.realPathFileAlloc(std.testing.io, "ignored_modes.sa", std.testing.allocator);
    defer std.testing.allocator.free(ignored_path);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const ignored_argv = [_][]const u8{ "sa", "test", ignored_path, "--jobs", jobs_arg, "--ignored" };
    const ignored_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        ignored_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), ignored_code);
    try expectContains(stdout_buffer.items, "[PASS] small ignored case");
    try expectNotContains(stdout_buffer.items, "[PASS] small normal case");
    try expectContains(stdout_buffer.items, "test result: ok. 1 passed; 0 failed; 1 skipped");
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    total_stdout_bytes += stdout_buffer.items.len;
    total_stderr_bytes += stderr_buffer.items.len;

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const include_ignored_argv = [_][]const u8{ "sa", "test", ignored_path, "--jobs", jobs_arg, "--include-ignored" };
    const include_ignored_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        include_ignored_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), include_ignored_code);
    try expectContains(stdout_buffer.items, "[PASS] small normal case");
    try expectContains(stdout_buffer.items, "[PASS] small ignored case");
    try expectContains(stdout_buffer.items, "test result: ok. 2 passed; 0 failed; 0 skipped");
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    total_stdout_bytes += stdout_buffer.items.len;
    total_stderr_bytes += stderr_buffer.items.len;
    endSaFileLog("tests/unit_framework/feature_suite.sa", "all-modes", jobs_arg, 0, 0, start_ns, total_stdout_bytes, total_stderr_bytes);
}
