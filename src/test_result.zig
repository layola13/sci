const std = @import("std");

pub const Termination = union(enum) {
    exited: u32,
    signal: u32,
    stopped: u32,
    unknown: u32,
};

pub const FailureReason = union(enum) {
    exited: u32,
    signal: u32,
    stopped: u32,
    unknown: u32,
    did_not_panic,
    launch_failed: []const u8,
};

pub const AssertionFailure = struct {
    expected: []const u8,
    actual: []const u8,
};

pub const TestFailure = struct {
    display_name: []const u8,
    reason: FailureReason,
    stderr: []const u8,
    assertion: ?AssertionFailure = null,
};

pub const TestOutcome = union(enum) {
    passed,
    failed: TestFailure,
    skipped,
    ignored,
};

pub fn terminationFrom(term: std.process.Child.Term) Termination {
    return switch (term) {
        .Exited => |code| .{ .exited = code },
        .Signal => |sig_num| .{ .signal = sig_num },
        .Stopped => |sig_num| .{ .stopped = sig_num },
        .Unknown => |status| .{ .unknown = status },
    };
}

fn stderrHasPanic(stderr: []const u8) bool {
    return std.mem.indexOf(u8, stderr, "PANIC:") != null or std.mem.indexOf(u8, stderr, "PANIC[") != null;
}

fn isAssertionValueSeparator(byte: u8) bool {
    return switch (byte) {
        ':', '=', ' ', '\t' => true,
        else => false,
    };
}

fn isAssertionValueTerminator(byte: u8) bool {
    return switch (byte) {
        ',', ';', '\n', '\r', ' ', '\t' => true,
        else => false,
    };
}

fn isAssertionLabelByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn valueAfterLabel(text: []const u8, comptime labels: []const []const u8) ?[]const u8 {
    for (labels) |label| {
        var search_start: usize = 0;
        while (std.mem.indexOfPos(u8, text, search_start, label)) |label_index| {
            search_start = label_index + label.len;
            if (label_index != 0 and isAssertionLabelByte(text[label_index - 1])) continue;
            if (search_start < text.len and !isAssertionValueSeparator(text[search_start])) continue;

            var start = label_index + label.len;
            while (start < text.len and isAssertionValueSeparator(text[start])) : (start += 1) {}
            if (start >= text.len) continue;

            var end = start;
            while (end < text.len and !isAssertionValueTerminator(text[end])) : (end += 1) {}
            const value = std.mem.trim(u8, text[start..end], " \t\r\n,;.");
            if (value.len != 0) return value;
        }
    }
    return null;
}

pub fn parseAssertionFailure(stderr: []const u8) ?AssertionFailure {
    const expected = valueAfterLabel(stderr, &.{ "expected", "Expected" }) orelse return null;
    const actual = valueAfterLabel(stderr, &.{ "actual", "Actual", "got", "Got" }) orelse return null;
    return .{
        .expected = expected,
        .actual = actual,
    };
}

pub fn toOutcome(display_name: []const u8, term: std.process.Child.Term, stderr: []const u8, should_panic: bool) TestOutcome {
    const termination = terminationFrom(term);
    if (should_panic) {
        if (stderrHasPanic(stderr)) return .passed;
        return .{
            .failed = .{
                .display_name = display_name,
                .reason = .did_not_panic,
                .stderr = stderr,
                .assertion = parseAssertionFailure(stderr),
            },
        };
    }
    return switch (termination) {
        .exited => |code| if (code == 0) .passed else .{
            .failed = .{
                .display_name = display_name,
                .reason = .{ .exited = code },
                .stderr = stderr,
                .assertion = parseAssertionFailure(stderr),
            },
        },
        else => .{
            .failed = .{
                .display_name = display_name,
                .reason = switch (termination) {
                    .signal => |sig_num| .{ .signal = sig_num },
                    .stopped => |sig_num| .{ .stopped = sig_num },
                    .unknown => |status| .{ .unknown = status },
                    else => unreachable,
                },
                .stderr = stderr,
                .assertion = parseAssertionFailure(stderr),
            },
        },
    };
}

pub fn writeFailure(writer: anytype, failure: TestFailure) !void {
    switch (failure.reason) {
        .did_not_panic => try writer.print("error: test {s} did not panic as expected\n", .{failure.display_name}),
        .launch_failed => |err_name| try writer.print("error: failed to launch test {s}: {s}\n", .{ failure.display_name, err_name }),
        .exited => |code| try writer.print("error: test {s} exited with code {d}\n", .{ failure.display_name, code }),
        .signal => |sig_num| try writer.print("error: test {s} terminated by signal {d}\n", .{ failure.display_name, sig_num }),
        .stopped => |sig_num| try writer.print("error: test {s} stopped by signal {d}\n", .{ failure.display_name, sig_num }),
        .unknown => |status| try writer.print("error: test {s} terminated with status {d}\n", .{ failure.display_name, status }),
    }
    if (failure.assertion) |assertion| {
        try writer.print(
            "assertion failed:\n  expected: {s}\n  actual: {s}\n",
            .{ assertion.expected, assertion.actual },
        );
    }
    if (failure.stderr.len != 0) {
        try writer.writeAll(failure.stderr);
        if (failure.stderr[failure.stderr.len - 1] != '\n') try writer.writeByte('\n');
    }
}

test "termination classification preserves process details" {
    const exited = terminationFrom(.{ .Exited = 7 });
    try std.testing.expectEqual(@as(u32, 7), exited.exited);

    const signaled = terminationFrom(.{ .Signal = 6 });
    try std.testing.expectEqual(@as(u32, 6), signaled.signal);

    const stopped = terminationFrom(.{ .Stopped = 19 });
    try std.testing.expectEqual(@as(u32, 19), stopped.stopped);
}

test "failure formatting keeps the visible process reason" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeFailure(out.writer(), .{
        .display_name = "signal abort",
        .reason = .{ .signal = 6 },
        .stderr = "panic text",
    });

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "terminated by signal 6"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "panic text"));
}

test "assertion panic text extracts expected and actual values" {
    const parsed = parseAssertionFailure("PANIC[103]: tests/assert_diag.sa:7: expected 7, got 3\n") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("7", parsed.expected);
    try std.testing.expectEqualStrings("3", parsed.actual);

    const keyed = parseAssertionFailure("PANIC[103]: expected=42 actual=41\n") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("42", keyed.expected);
    try std.testing.expectEqualStrings("41", keyed.actual);
}

test "failure formatting surfaces assertion values before raw stderr" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeFailure(out.writer(), .{
        .display_name = "assert eq diagnostic",
        .reason = .{ .exited = 231 },
        .stderr = "PANIC[103]: expected=42 actual=41",
        .assertion = .{
            .expected = "42",
            .actual = "41",
        },
    });

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "assertion failed:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "expected: 42"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "actual: 41"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "PANIC[103]: expected=42 actual=41"));
}

test "should panic classification treats PANIC output as success" {
    const outcome = toOutcome("panic path", .{ .Exited = 128 }, "PANIC: code=99\n", true);
    try std.testing.expect(outcome == .passed);
}

test "should panic classification fails if panic is missing" {
    const outcome = toOutcome("panic path", .{ .Exited = 0 }, "", true);
    try std.testing.expect(outcome == .failed);
    switch (outcome) {
        .failed => |failure| {
            try std.testing.expect(failure.reason == .did_not_panic);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "launch failure formatting stays explicit" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeFailure(out.writer(), .{
        .display_name = "panic path",
        .reason = .{ .launch_failed = "ChildProcessFailed" },
        .stderr = "",
    });

    try std.testing.expect(std.mem.containsAtLeast(u8, out.items, 1, "failed to launch test panic path: ChildProcessFailed"));
}
