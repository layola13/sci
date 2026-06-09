const std = @import("std");

const tasks_path = "tasks.md";
const referee_scope = "src/referee/ + src/verifier.zig";
const referee_paths = [_][]const u8{ "src/referee/", "src/verifier.zig" };

const AppError = error{
    TaskLineNotFound,
    CeilingParseFailed,
    TokeiOutputMissing,
    TokeiOutputParseFailed,
};

const TokeiTotals = struct {
    files: usize,
    lines: usize,
    code: usize,
    comments: usize,
    blanks: usize,
};

pub fn main() void {
    var exit_code: u8 = 0;
    defer std.process.exit(exit_code);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const ceiling = readTaskCeiling(allocator) catch |err| {
        reportTaskError(stderr, err) catch {};
        exit_code = 1;
        return;
    };

    const tokei_argv = [_][]const u8{ "tokei", referee_paths[0], referee_paths[1] };
    const tokei_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = tokei_argv[0..],
    }) catch |err| {
        switch (err) {
            error.FileNotFound, error.InvalidExe => {
                const totals = countRefereeLocFallback(allocator) catch |fallback_err| {
                    reportFallbackError(stderr, fallback_err) catch {};
                    exit_code = 1;
                    return;
                };
                printAndCheckTotals(stdout, ceiling, totals, "builtin fallback") catch {};
                if (totals.code > ceiling) exit_code = 1;
            },
            else => {
                reportTokeiSpawnError(stderr, err) catch {};
                exit_code = 1;
            },
        }
        return;
    };
    defer allocator.free(tokei_result.stdout);
    defer allocator.free(tokei_result.stderr);

    switch (tokei_result.term) {
        .Exited => |code| {
            if (code != 0) {
                reportTokeiExitError(stderr, code, tokei_result.stdout, tokei_result.stderr) catch {};
                exit_code = 1;
                return;
            }
        },
        else => {
            reportTokeiTermError(stderr, tokei_result.term, tokei_result.stdout, tokei_result.stderr) catch {};
            exit_code = 1;
            return;
        },
    }

    const totals = parseTokeiTotals(allocator, tokei_result.stdout) catch |err| {
        reportTokeiParseError(stderr, err, tokei_result.stdout) catch {};
        exit_code = 1;
        return;
    };

    printAndCheckTotals(stdout, ceiling, totals, "tokei") catch {};
    if (totals.code > ceiling) exit_code = 1;
}

fn printAndCheckTotals(writer: anytype, ceiling: usize, totals: TokeiTotals, source: []const u8) !void {
    try writer.print("[referee-loc] task ceiling from {s}: {d} code lines\n", .{ tasks_path, ceiling });
    try writer.print(
        "[referee-loc] {s} `{s}` -> files={d}, code={d}, comments={d}, blanks={d}, total={d}\n",
        .{ source, referee_scope, totals.files, totals.code, totals.comments, totals.blanks, totals.lines },
    );

    if (totals.code <= ceiling) {
        try writer.print("[referee-loc] PASS: {d} <= {d}\n", .{ totals.code, ceiling });
        return;
    }

    try writer.print("[referee-loc] FAIL: {d} > {d} (over by {d})\n", .{ totals.code, ceiling, totals.code - ceiling });
}

fn countRefereeLocFallback(allocator: std.mem.Allocator) !TokeiTotals {
    var totals = TokeiTotals{ .files = 0, .lines = 0, .code = 0, .comments = 0, .blanks = 0 };
    for (referee_paths) |path| {
        try countPathLocFallback(allocator, path, &totals);
    }
    return totals;
}

fn countPathLocFallback(allocator: std.mem.Allocator, path: []const u8, totals: *TokeiTotals) !void {
    if (std.mem.endsWith(u8, path, ".zig")) {
        const contents = try std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024);
        defer allocator.free(contents);
        totals.files += 1;
        countSourceLines(contents, totals);
        return;
    }

    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        const contents = try dir.readFileAlloc(allocator, entry.path, 16 * 1024 * 1024);
        defer allocator.free(contents);
        totals.files += 1;
        countSourceLines(contents, totals);
    }
}

fn countSourceLines(contents: []const u8, totals: *TokeiTotals) void {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        totals.lines += 1;
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) {
            totals.blanks += 1;
        } else if (std.mem.startsWith(u8, line, "//")) {
            totals.comments += 1;
        } else {
            totals.code += 1;
        }
    }
}

fn readTaskCeiling(allocator: std.mem.Allocator) !usize {
    const contents = try std.fs.cwd().readFileAlloc(allocator, tasks_path, 1 << 20);
    defer allocator.free(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, "6.27 Referee LOC lint") == null) continue;

        const marker = std.mem.indexOf(u8, line, "≤") orelse return error.CeilingParseFailed;
        const after_marker = std.mem.trimLeft(u8, line[marker + "≤".len ..], " \t");
        const ceiling = try parseUnsignedPrefix(after_marker);
        return ceiling;
    }

    return error.TaskLineNotFound;
}

fn parseUnsignedPrefix(slice: []const u8) !usize {
    var end: usize = 0;
    while (end < slice.len and std.ascii.isDigit(slice[end])) : (end += 1) {}
    if (end == 0) return error.CeilingParseFailed;
    return std.fmt.parseInt(usize, slice[0..end], 10) catch error.CeilingParseFailed;
}

fn stripAnsiEscapes(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1b) {
            i += 1;
            if (i < input.len and input[i] == '[') {
                i += 1;
                while (i < input.len and !std.ascii.isAlphabetic(input[i])) : (i += 1) {}
                i += 1;
            }
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }
    return try result.toOwnedSlice();
}

fn parseTokeiTotals(allocator: std.mem.Allocator, raw_output: []const u8) !TokeiTotals {
    const output = try stripAnsiEscapes(allocator, raw_output);
    defer allocator.free(output);

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '=') continue;

        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        const label = tokens.next() orelse continue;
        if (!std.mem.eql(u8, label, "Total")) continue;

        const files = try parseUsizeToken(tokens.next());
        const lines_count = try parseUsizeToken(tokens.next());
        const code = try parseUsizeToken(tokens.next());
        const comments = try parseUsizeToken(tokens.next());
        const blanks = try parseUsizeToken(tokens.next());

        return .{
            .files = files,
            .lines = lines_count,
            .code = code,
            .comments = comments,
            .blanks = blanks,
        };
    }

    return AppError.TokeiOutputMissing;
}

fn parseUsizeToken(token: ?[]const u8) !usize {
    const value = token orelse return AppError.TokeiOutputParseFailed;
    return std.fmt.parseInt(usize, value, 10) catch AppError.TokeiOutputParseFailed;
}

fn reportTaskError(writer: anytype, err: anyerror) !void {
    switch (err) {
        error.FileNotFound => try writer.print("[referee-loc] error: could not read `{s}`; run this from the repository root\n", .{tasks_path}),
        error.AccessDenied => try writer.print("[referee-loc] error: permission denied reading `{s}`\n", .{tasks_path}),
        error.TaskLineNotFound => try writer.print("[referee-loc] error: could not find task 6.27 in `{s}`\n", .{tasks_path}),
        error.CeilingParseFailed => try writer.print("[referee-loc] error: could not parse the LOC ceiling from task 6.27 in `{s}`\n", .{tasks_path}),
        else => try writer.print("[referee-loc] error: unexpected failure while reading `{s}`: {s}\n", .{ tasks_path, @errorName(err) }),
    }
}

fn reportTokeiSpawnError(writer: anytype, err: anyerror) !void {
    switch (err) {
        error.FileNotFound, error.InvalidExe => try writer.print("[referee-loc] error: `tokei` was not found in PATH; install `tokei` and retry\n", .{}),
        error.AccessDenied => try writer.print("[referee-loc] error: `tokei` is not executable or cannot be accessed\n", .{}),
        else => try writer.print("[referee-loc] error: failed to launch `tokei {s}`: {s}\n", .{ referee_scope, @errorName(err) }),
    }
}

fn reportFallbackError(writer: anytype, err: anyerror) !void {
    switch (err) {
        error.FileNotFound => try writer.print("[referee-loc] error: could not read `{s}` with builtin fallback\n", .{referee_scope}),
        error.AccessDenied => try writer.print("[referee-loc] error: permission denied reading `{s}` with builtin fallback\n", .{referee_scope}),
        else => try writer.print("[referee-loc] error: builtin fallback failed for `{s}`: {s}\n", .{ referee_scope, @errorName(err) }),
    }
}

fn reportTokeiExitError(writer: anytype, code: u8, stdout: []const u8, stderr: []const u8) !void {
    try writer.print("[referee-loc] error: `tokei {s}` exited with status {d}\n", .{ referee_scope, code });
    try printCapturedOutput(writer, stdout, stderr);
}

fn reportTokeiTermError(writer: anytype, term: std.process.Child.Term, stdout: []const u8, stderr: []const u8) !void {
    switch (term) {
        .Signal => |sig| try writer.print("[referee-loc] error: `tokei {s}` was terminated by signal {d}\n", .{ referee_scope, sig }),
        .Stopped => |sig| try writer.print("[referee-loc] error: `tokei {s}` was stopped by signal {d}\n", .{ referee_scope, sig }),
        .Unknown => |code| try writer.print("[referee-loc] error: `tokei {s}` ended unexpectedly with code {d}\n", .{ referee_scope, code }),
        .Exited => |code| try writer.print("[referee-loc] error: `tokei {s}` exited with status {d}\n", .{ referee_scope, code }),
    }
    try printCapturedOutput(writer, stdout, stderr);
}

fn reportTokeiParseError(writer: anytype, err: anyerror, output: []const u8) !void {
    switch (err) {
        AppError.TokeiOutputMissing => try writer.print("[referee-loc] error: could not find a `Total` row in `tokei` output\n", .{}),
        AppError.TokeiOutputParseFailed => try writer.print("[referee-loc] error: could not parse the `Total` row in `tokei` output\n", .{}),
        else => try writer.print("[referee-loc] error: unexpected failure while parsing `tokei` output: {s}\n", .{@errorName(err)}),
    }
    try writer.print("[referee-loc] raw `tokei` output:\n{s}\n", .{output});
}

fn printCapturedOutput(writer: anytype, stdout: []const u8, stderr: []const u8) !void {
    if (stdout.len != 0) {
        try writer.print("[referee-loc] captured stdout:\n{s}\n", .{stdout});
    }
    if (stderr.len != 0) {
        try writer.print("[referee-loc] captured stderr:\n{s}\n", .{stderr});
    }
}
