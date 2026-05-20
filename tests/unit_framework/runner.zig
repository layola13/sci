const std = @import("std");

const saasm = @import("saasm");

fn expectContains(text: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, text, needle) != null);
}

fn expectNotContains(text: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, text, needle) == null);
}

test "native unit framework suite covers the demo-derived feature matrix" {
    const suite_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "tests/unit_framework/feature_suite.saasm");
    defer std.testing.allocator.free(suite_path);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const default_argv = [_][]const u8{ "saasm", "test", suite_path, "--jobs", "1" };
    const default_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        default_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), default_code);
    try expectContains(stdout_buffer.items, "[PASS] 03_if_else branch path");
    try expectContains(stdout_buffer.items, "[PASS] 05_struct field layout");
    try expectContains(stdout_buffer.items, "[PASS] 06_enum_and_match tag dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 28_borrow_chains repeated load");
    try expectContains(stdout_buffer.items, "[PASS] 41_module_imports helper import");
    try expectContains(stdout_buffer.items, "[PASS] sa_std json dom roundtrip");
    try expectContains(stdout_buffer.items, "[PASS] sa_std json stream tokens");
    try expectContains(stdout_buffer.items, "[PASS] sa_std regex groups");
    try expectContains(stdout_buffer.items, "[PASS] 178 panic hook path");
    try expectNotContains(stdout_buffer.items, "[PASS] framework ignored case");
    try expectContains(stdout_buffer.items, "test result: ok. 15 passed; 0 failed; 0 skipped; 1 ignored");
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const ignored_argv = [_][]const u8{ "saasm", "test", suite_path, "--jobs", "1", "--ignored" };
    const ignored_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        ignored_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), ignored_code);
    try expectContains(stdout_buffer.items, "[PASS] framework ignored case");
    try expectNotContains(stdout_buffer.items, "[PASS] 03_if_else branch path");
    try expectContains(stdout_buffer.items, "test result: ok. 1 passed; 0 failed; 15 skipped");
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const include_ignored_argv = [_][]const u8{ "saasm", "test", suite_path, "--jobs", "1", "--include-ignored" };
    const include_ignored_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        include_ignored_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), include_ignored_code);
    try expectContains(stdout_buffer.items, "[PASS] 03_if_else branch path");
    try expectContains(stdout_buffer.items, "[PASS] 05_struct field layout");
    try expectContains(stdout_buffer.items, "[PASS] 06_enum_and_match tag dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 28_borrow_chains repeated load");
    try expectContains(stdout_buffer.items, "[PASS] 41_module_imports helper import");
    try expectContains(stdout_buffer.items, "[PASS] sa_std json dom roundtrip");
    try expectContains(stdout_buffer.items, "[PASS] sa_std json stream tokens");
    try expectContains(stdout_buffer.items, "[PASS] sa_std regex groups");
    try expectContains(stdout_buffer.items, "[PASS] 178 panic hook path");
    try expectContains(stdout_buffer.items, "[PASS] framework ignored case");
    try expectContains(stdout_buffer.items, "test result: ok. 16 passed; 0 failed; 0 skipped");
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}
