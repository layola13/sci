const std = @import("std");

const test_meta = @import("test_meta.zig");
const test_result = @import("test_result.zig");

pub const TestExecutor = struct {
    allocator: std.mem.Allocator,
    exe_path: []const u8,
    cwd_dir: std.fs.Dir,
    selection: test_meta.TestSelection,

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

        const run_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ self.exe_path },
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
            .include_filters = &.{ "match" },
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
