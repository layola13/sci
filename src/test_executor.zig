const std = @import("std");
const builtin = @import("builtin");

const test_meta = @import("test_meta.zig");
const test_result = @import("test_result.zig");

pub const TestExecutor = struct {
    allocator: std.mem.Allocator,
    exe_path: []const u8,
    cwd_dir: std.fs.Dir,
    selection: test_meta.TestSelection,
    trace_panic: bool = false,
    fn addPluginDirectoriesToPath(allocator: std.mem.Allocator, env_map: *std.process.EnvMap) !void {
        const plugin_paths = std.process.getEnvVarOwned(allocator, "SA_PLUGINS_PATH") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => return,
            else => return err,
        };
        defer allocator.free(plugin_paths);

        const separator: u8 = if (builtin.os.tag == .windows) ';' else ':';
        const path_separator: []const u8 = if (builtin.os.tag == .windows) ";" else ":";
        var directories = std.ArrayList([]const u8).init(allocator);
        defer {
            for (directories.items) |directory| allocator.free(directory);
            directories.deinit();
        }

        var iterator = std.mem.splitScalar(u8, plugin_paths, separator);
        while (iterator.next()) |plugin_path| {
            if (plugin_path.len == 0) continue;
            const directory = std.fs.path.dirname(plugin_path) orelse continue;
            try directories.append(try allocator.dupe(u8, directory));
        }
        if (directories.items.len == 0) return;

        const existing_path = env_map.get("PATH") orelse "";
        var path = std.ArrayList(u8).init(allocator);
        defer path.deinit();
        for (directories.items, 0..) |directory, index| {
            if (index != 0) try path.appendSlice(path_separator);
            try path.appendSlice(directory);
        }
        if (existing_path.len != 0) {
            try path.appendSlice(path_separator);
            try path.appendSlice(existing_path);
        }
        try env_map.put("PATH", path.items);
    }
    fn launchFailure(test_case: test_meta.TestDescAndFn, err_name: []const u8) test_result.TestOutcome {
        return .{
            .failed = .{
                .display_name = test_case.displayName(),
                .reason = .{ .launch_failed = err_name },
                .stderr = "",
            },
        };
    }

    pub fn run(self: *const TestExecutor, test_case: test_meta.TestDescAndFn) test_result.TestOutcome {
        if (!self.selection.shouldRun(test_case)) {
            return if (test_case.desc.ignored) .ignored else .skipped;
        }

        var env_map = std.process.getEnvMap(self.allocator) catch |err| {
            return launchFailure(test_case, @errorName(err));
        };
        defer env_map.deinit();

        env_map.put("SA_TEST_NAME", test_case.selectorName()) catch |err| {
            return launchFailure(test_case, @errorName(err));
        };
        if (self.trace_panic) {
            env_map.put("SA_TEST_TRACE_PANIC", "1") catch |err| {
                return launchFailure(test_case, @errorName(err));
            };
        }
        addPluginDirectoriesToPath(self.allocator, &env_map) catch |err| {
            return launchFailure(test_case, @errorName(err));
        };

        const run_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{self.exe_path},
            .cwd_dir = self.cwd_dir,
            .env_map = &env_map,
        }) catch |err| {
            return launchFailure(test_case, @errorName(err));
        };
        self.allocator.free(run_result.stdout);
        defer self.allocator.free(run_result.stderr);

        var outcome = test_result.toOutcome(
            test_case.displayName(),
            run_result.term,
            run_result.stderr,
            test_case.desc.should_panic,
        );
        if (outcome == .failed) {
            outcome.failed.stderr = self.allocator.dupe(u8, run_result.stderr) catch |err| {
                return launchFailure(test_case, @errorName(err));
            };
            outcome.failed.assertion = test_result.parseAssertionFailure(outcome.failed.stderr);
            outcome.failed.panic = test_result.parsePanicInfo(outcome.failed.stderr);
            outcome.failed.selector_name = test_case.selectorName();
            outcome.failed.trace_panic = self.trace_panic;
            if (test_case.desc.source_file) |file| {
                outcome.failed.location = .{
                    .file = file,
                    .line = test_case.desc.line,
                    .col = test_case.desc.col,
                };
            }
        }
        return outcome;
    }
};

test "executor skips tests that do not match selection" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const executor = TestExecutor{
        .allocator = std.testing.allocator,
        .exe_path = "unused",
        .cwd_dir = tmp.dir,
        .selection = .{
            .include_filters = &.{"match"},
            .exact = true,
        },
    };

    const skipped = executor.run(.{
        .desc = .{
            .id = 1,
            .name = "other",
            .ignored = false,
            .should_panic = false,
        },
        .testfn = .{ .selector_name = "_saasm_test_1" },
    });
    try std.testing.expect(skipped == .skipped);

    const ignored_executor = TestExecutor{
        .allocator = std.testing.allocator,
        .exe_path = "unused",
        .cwd_dir = tmp.dir,
        .selection = .{},
    };
    const ignored = ignored_executor.run(.{
        .desc = .{
            .id = 2,
            .name = "ignored",
            .ignored = true,
            .should_panic = false,
        },
        .testfn = .{ .selector_name = "_saasm_test_2" },
    });
    try std.testing.expect(ignored == .ignored);
}
