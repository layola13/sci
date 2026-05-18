const std = @import("std");

const test_meta = @import("test_meta.zig");
const test_result = @import("test_result.zig");

pub const RunSummary = struct {
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    ignored: usize = 0,

    pub fn record(self: *RunSummary, outcome: test_result.TestOutcome) void {
        switch (outcome) {
            .passed => self.passed += 1,
            .failed => self.failed += 1,
            .skipped => self.skipped += 1,
            .ignored => self.ignored += 1,
        }
    }

    pub fn executedCount(self: RunSummary) usize {
        return self.passed + self.failed + self.ignored;
    }
};

pub fn writeOutcome(
    stdout: anytype,
    stderr: anytype,
    test_case: test_meta.TestDescAndFn,
    outcome: test_result.TestOutcome,
) !void {
    switch (outcome) {
        .passed => try stdout.print("[PASS] {s}\n", .{test_case.displayName()}),
        .failed => |failure| {
            try stdout.print("[FAIL] {s}\n", .{failure.display_name});
            try test_result.writeFailure(stderr, failure);
        },
        .skipped, .ignored => {},
    }
}

pub fn writeSummary(stdout: anytype, summary: RunSummary) !void {
    try stdout.print("----\n", .{});
    try stdout.print("test result: ", .{});
    if (summary.failed == 0) {
        try stdout.print("ok. ", .{});
    } else {
        try stdout.print("FAILED. ", .{});
    }
    if (summary.ignored == 0) {
        try stdout.print(
            "{d} passed; {d} failed; {d} skipped\n",
            .{ summary.passed, summary.failed, summary.skipped },
        );
    } else {
        try stdout.print(
            "{d} passed; {d} failed; {d} skipped; {d} ignored\n",
            .{ summary.passed, summary.failed, summary.skipped, summary.ignored },
        );
    }
}

test "formatter writes stable summary text" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeSummary(out.writer(), .{
        .passed = 2,
        .failed = 0,
        .skipped = 1,
        .ignored = 0,
    });

    try std.testing.expectEqualStrings("----\ntest result: ok. 2 passed; 0 failed; 1 skipped\n", out.items);
}

test "formatter writes failure output through test_result" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();
    var stderr = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr.deinit();

    try writeOutcome(stdout.writer(), stderr.writer(), .{
        .desc = .{
            .id = 1,
            .name = "panic path",
            .ignored = false,
            .should_panic = false,
        },
        .testfn = .{ .selector_name = "_saasm_test_1" },
    }, .{
        .failed = .{
            .display_name = "panic path",
            .reason = .{ .launch_failed = "ChildProcessFailed" },
            .stderr = "panic text",
        },
    });

    try std.testing.expect(std.mem.containsAtLeast(u8, stdout.items, 1, "[FAIL] panic path"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr.items, 1, "failed to launch test panic path: ChildProcessFailed"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr.items, 1, "panic text"));
}
