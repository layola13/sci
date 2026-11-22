const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const endSaFileLog = @import("util.zig").endSaFileLog;
const errorSaFileLog = @import("util.zig").errorSaFileLog;
const expectContains = @import("util.zig").expectContains;
const saTestJobsArg = @import("util.zig").saTestJobsArg;
const startSaFileLog = @import("util.zig").startSaFileLog;
const writeSource = @import("util.zig").writeSource;

test "native unit assertions surface file line expected and got details" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const core_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/core/sa_core.sa");
    defer std.testing.allocator.free(core_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\@import "{s}"
        \\
        \\@const ASSERT_FAIL_MSG = utf8:"tests/assert_diag.sa:7: expected 7, got 3"
        \\#def ASSERT_FAIL_MSG_LEN = 43
        \\
        \\@test "assert eq diagnostic"():
        \\L_ENTRY:
        \\    value = add 1, 2
        \\    EXPAND ASSERT_EQ_MSG assert_cond, value, 7, ASSERT_FAIL_MSG, ASSERT_FAIL_MSG_LEN
        \\    !value
        \\    !assert_cond
        \\    return
        \\
    , .{core_path});
    defer std.testing.allocator.free(source);
    try writeSource(tmp.dir, "assert_diag.sa", source);

    const jobs_arg = try saTestJobsArg(std.testing.allocator);
    defer std.testing.allocator.free(jobs_arg);
    const start_ns = startSaFileLog("assert_diag.sa", "negative-diagnostic", jobs_arg, 0, 0);
    // NOTE(Zig 0.17): `errdefer |err|` payload capture was removed after 0.14;
    // inner function + explicit catch preserves the structured error log marker.
    assertDiagNegativeInner(jobs_arg, start_ns) catch |err| {
        errorSaFileLog("assert_diag.sa", "negative-diagnostic", 0, 0, err);
        return err;
    };
}

pub fn assertDiagNegativeInner(jobs_arg: []const u8, start_ns: i128) !void {
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const argv = [_][]const u8{ "sa", "test", "assert_diag.sa", "--jobs", jobs_arg };
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );

    try std.testing.expectEqual(@as(u8, 1), code);
    try expectContains(stdout_buffer.items, "[FAIL] assert eq diagnostic");
    try expectContains(stdout_buffer.items, "test result: FAILED. 0 passed; 1 failed; 0 skipped");
    try expectContains(stderr_buffer.items, "tests/assert_diag.sa:");
    try expectContains(stderr_buffer.items, "expected 7");
    try expectContains(stderr_buffer.items, "got 3");
    endSaFileLog("assert_diag.sa", "negative-diagnostic", jobs_arg, 0, 0, start_ns, stdout_buffer.items.len, stderr_buffer.items.len);
}
