const std = @import("std");

const tasks_path = ".kiro/specs/sa-asm-language/tasks.md";
const referee_path = "src/referee/";

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

    const tokei_argv = [_][]const u8{ "tokei", referee_path };
    const tokei_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = tokei_argv[0..],
    }) catch |err| {
        reportTokeiSpawnError(stderr, err) catch {};
        exit_code = 1;
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

    const totals = parseTokeiTotals(tokei_result.stdout) catch |err| {
        reportTokeiParseError(stderr, err, tokei_result.stdout) catch {};
        exit_code = 1;
        return;
    };

    stdout.print("[referee-loc] task ceiling from {s}: {d} code lines\n", .{ tasks_path, ceiling }) catch {};
    stdout.print(
        "[referee-loc] `tokei {s}` -> files={d}, code={d}, comments={d}, blanks={d}, total={d}\n",
        .{ referee_path, totals.files, totals.code, totals.comments, totals.blanks, totals.lines },
    ) catch {};

    if (totals.code <= ceiling) {
        stdout.print("[referee-loc] PASS: {d} <= {d}\n", .{ totals.code, ceiling }) catch {};
        return;
    }

    stdout.print("[referee-loc] FAIL: {d} > {d} (over by {d})\n", .{ totals.code, ceiling, totals.code - ceiling }) catch {};
    exit_code = 1;
}

fn readTaskCeiling(allocator: std.mem.Allocator) !usize {
    const contents = try std.fs.cwd().readFileAlloc(allocator, tasks_path, 1 << 20);
    defer allocator.free(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, "6.27 Referee LOC lint") == null) continue;
        if (std.mem.indexOf(u8, line, "tokei src/referee/") == null) continue;

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

fn parseTokeiTotals(output: []const u8) !TokeiTotals {
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
        else => try writer.print("[referee-loc] error: failed to launch `tokei {s}`: {s}\n", .{ referee_path, @errorName(err) }),
    }
}

fn reportTokeiExitError(writer: anytype, code: u8, stdout: []const u8, stderr: []const u8) !void {
    try writer.print("[referee-loc] error: `tokei {s}` exited with status {d}\n", .{ referee_path, code });
    try printCapturedOutput(writer, stdout, stderr);
}

fn reportTokeiTermError(writer: anytype, term: std.process.Child.Term, stdout: []const u8, stderr: []const u8) !void {
    switch (term) {
        .Signal => |sig| try writer.print("[referee-loc] error: `tokei {s}` was terminated by signal {d}\n", .{ referee_path, sig }),
        .Stopped => |sig| try writer.print("[referee-loc] error: `tokei {s}` was stopped by signal {d}\n", .{ referee_path, sig }),
        .Unknown => |code| try writer.print("[referee-loc] error: `tokei {s}` ended unexpectedly with code {d}\n", .{ referee_path, code }),
        .Exited => |code| try writer.print("[referee-loc] error: `tokei {s}` exited with status {d}\n", .{ referee_path, code }),
    }
    try printCapturedOutput(writer, stdout, stderr);
}

fn reportTokeiParseError(writer: anytype, err: anyerror, output: []const u8) !void {
    switch (err) {
        AppError.TokeiOutputMissing => try writer.print("[referee-loc] error: could not find a `Total` row in `tokei` output\n", .{}),
        AppError.TokeiOutputParseFailed => try writer.print("[referee-loc] error: could not parse the `Total` row in `tokei` output\n", .{}),
        else => try writer.print("[referee-loc] error: unexpected failure while parsing `tokei` output: {s}\n", .{ @errorName(err) }),
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
