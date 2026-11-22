const std = @import("std");
const builtin = @import("builtin");
const saasm = @import("saasm");
const sio = @import("sio");
const elapsedMs = @import("util.zig").elapsedMs;
const endSaFileLog = @import("util.zig").endSaFileLog;
const errorSaFileLog = @import("util.zig").errorSaFileLog;
const expectContains = @import("util.zig").expectContains;
const expectNotContains = @import("util.zig").expectNotContains;
const restoreEnvVarZ = @import("util.zig").restoreEnvVarZ;
const saBinaryPath = @import("util.zig").saBinaryPath;
const saTestJobsArgForPath = @import("util.zig").saTestJobsArgForPath;
const saUnitFileJobs = @import("util.zig").saUnitFileJobs;
const saveEnvVarZ = @import("util.zig").saveEnvVarZ;
const setEnvVarZ = @import("util.zig").setEnvVarZ;
const startSaFileLog = @import("util.zig").startSaFileLog;
const writeSource = @import("util.zig").writeSource;

pub const SaTestExpectations = struct {
    expected_passes: []const []const u8,
    expected_absent_passes: []const []const u8 = &.{},
    expected_summary: []const u8,
    owned: bool = false,

    pub fn deinit(self: SaTestExpectations, allocator: std.mem.Allocator) void {
        if (!self.owned) return;
        freeStringList(allocator, self.expected_passes);
        freeStringList(allocator, self.expected_absent_passes);
        allocator.free(self.expected_passes);
        allocator.free(self.expected_absent_passes);
        allocator.free(self.expected_summary);
    }
};

pub const SaTestTask = struct {
    path: []const u8,
    expectations: SaTestExpectations,
    jobs_arg: []const u8,
};

pub var queued_sa_tests: std.ArrayListUnmanaged(SaTestTask) = .empty;

pub fn shouldQueueSaTestFile(allocator: std.mem.Allocator) bool {
    if (saUnitFileJobs() <= 1) return false;
    const sa_bin = saBinaryPath(allocator) orelse return false;
    allocator.free(sa_bin);
    return true;
}

pub fn freeStringList(allocator: std.mem.Allocator, items: []const []const u8) void {
    for (items) |item| allocator.free(item);
}

pub fn isSaTestSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r';
}

pub fn trimSaTestSpace(text: []const u8) []const u8 {
    return std.mem.trimStart(u8, text, " \t\r");
}

pub fn consumeSaTestKeyword(rest: *[]const u8, keyword: []const u8) bool {
    const text = rest.*;
    if (!std.mem.startsWith(u8, text, keyword)) return false;
    if (text.len > keyword.len and !isSaTestSpace(text[keyword.len])) return false;
    rest.* = trimSaTestSpace(text[keyword.len..]);
    return true;
}

pub const ParsedSaTestDecl = struct {
    name: []const u8,
    ignored: bool,
};

pub fn parseSaTestDecl(line: []const u8) ?ParsedSaTestDecl {
    var rest = trimSaTestSpace(line);
    if (!std.mem.startsWith(u8, rest, "@test")) return null;
    if (rest.len > "@test".len and !isSaTestSpace(rest["@test".len])) return null;
    rest = trimSaTestSpace(rest["@test".len..]);

    var ignored = false;
    while (true) {
        if (consumeSaTestKeyword(&rest, "ignored")) {
            ignored = true;
            continue;
        }
        if (consumeSaTestKeyword(&rest, "should_panic")) continue;
        break;
    }

    if (rest.len == 0 or rest[0] != '"') return null;
    var i: usize = 1;
    var escaped = false;
    while (i < rest.len) : (i += 1) {
        const c = rest[i];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (c == '\\') {
            escaped = true;
            continue;
        }
        if (c == '"') return .{ .name = rest[1..i], .ignored = ignored };
    }
    return null;
}

pub fn appendPassMarker(allocator: std.mem.Allocator, list: *std.array_list.Managed([]const u8), name: []const u8) !void {
    const marker = try std.fmt.allocPrint(allocator, "[PASS] {s}", .{name});
    errdefer allocator.free(marker);
    try list.append(marker);
}

pub fn buildSaTestExpectations(allocator: std.mem.Allocator, path: []const u8) !SaTestExpectations {
    const source = try sio.cwd().readFileAlloc(allocator, path, 64 * 1024 * 1024);
    defer allocator.free(source);

    var expected_passes = std.array_list.Managed([]const u8).init(allocator);
    defer expected_passes.deinit();
    errdefer freeStringList(allocator, expected_passes.items);

    var expected_absent_passes = std.array_list.Managed([]const u8).init(allocator);
    defer expected_absent_passes.deinit();
    errdefer freeStringList(allocator, expected_absent_passes.items);

    var passed_count: usize = 0;
    var ignored_count: usize = 0;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const parsed = parseSaTestDecl(line) orelse continue;
        if (parsed.ignored) {
            ignored_count += 1;
            try appendPassMarker(allocator, &expected_absent_passes, parsed.name);
        } else {
            passed_count += 1;
            try appendPassMarker(allocator, &expected_passes, parsed.name);
        }
    }

    const summary = if (ignored_count == 0)
        try std.fmt.allocPrint(allocator, "test result: ok. {} passed; 0 failed; 0 skipped", .{passed_count})
    else
        try std.fmt.allocPrint(allocator, "test result: ok. {} passed; 0 failed; 0 skipped; {} ignored", .{ passed_count, ignored_count });
    errdefer allocator.free(summary);

    return .{
        .expected_passes = try expected_passes.toOwnedSlice(),
        .expected_absent_passes = try expected_absent_passes.toOwnedSlice(),
        .expected_summary = summary,
        .owned = true,
    };
}

pub fn enqueueSaTestFile(path: []const u8, expectations: SaTestExpectations) !void {
    const jobs_arg = try saTestJobsArgForPath(std.testing.allocator, path);
    errdefer std.testing.allocator.free(jobs_arg);
    errdefer expectations.deinit(std.testing.allocator);
    try queued_sa_tests.append(std.testing.allocator, .{
        .path = path,
        .expectations = expectations,
        .jobs_arg = jobs_arg,
    });
}

pub fn runSaTestFile(path: []const u8, expected_passes: []const []const u8, expected_summary: []const u8) !void {
    return runSaTestFileWithExpectations(path, .{ .expected_passes = expected_passes, .expected_summary = expected_summary });
}

pub fn runSaTestFileAuto(path: []const u8) !void {
    const expectations = try buildSaTestExpectations(std.testing.allocator, path);
    return runSaTestFileWithExpectations(path, expectations);
}

pub fn runSaTestFileWithExpectations(path: []const u8, expectations: SaTestExpectations) !void {
    if (shouldQueueSaTestFile(std.testing.allocator)) {
        return enqueueSaTestFile(path, expectations);
    }
    defer expectations.deinit(std.testing.allocator);
    return runSaTestFileInProcess(path, expectations);
}

pub fn runSaTestFileInProcess(path: []const u8, expectations: SaTestExpectations) !void {
    const suite_path = try sio.cwd().realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(suite_path);
    const jobs_arg = try saTestJobsArgForPath(std.testing.allocator, path);
    defer std.testing.allocator.free(jobs_arg);
    const start_ns = startSaFileLog(path, "in-process", jobs_arg, 0, 0);
    // NOTE(Zig 0.17): `errdefer |err|` payload capture was removed after 0.14,
    // so the fallible tail runs in an inner function with an explicit catch
    // that preserves the structured `status=error err=<name>` log marker.
    runSaTestFileInProcessInner(path, expectations, suite_path, jobs_arg, start_ns) catch |err| {
        errorSaFileLog(path, "in-process", 0, 0, err);
        return err;
    };
}

pub fn runSaTestFileInProcessInner(path: []const u8, expectations: SaTestExpectations, suite_path: []const u8, jobs_arg: []const u8, start_ns: i128) !void {
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const argv = [_][]const u8{ "sa", "test", suite_path, "--jobs", jobs_arg, "--trace-panic" };
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (code != 0) {
        std.debug.print("stdout: {s}\n", .{stdout_buffer.items});
        std.debug.print("stderr: {s}\n", .{stderr_buffer.items});
    }
    try std.testing.expectEqual(@as(u8, 0), code);
    for (expectations.expected_passes) |expected_pass| {
        try expectContains(stdout_buffer.items, expected_pass);
    }
    for (expectations.expected_absent_passes) |absent_pass| {
        try expectNotContains(stdout_buffer.items, absent_pass);
    }
    try expectContains(stdout_buffer.items, expectations.expected_summary);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    endSaFileLog(path, "in-process", jobs_arg, 0, 0, start_ns, stdout_buffer.items.len, stderr_buffer.items.len);
}

pub const SaTestWorkerContext = struct {
    sa_bin: []const u8,
    tasks: []const SaTestTask,
    next_index: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    failed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    // NOTE(Zig 0.17): `std.atomic.Mutex` is now an enum lock (`.unlocked`)
    // with tryLock/unlock only; spin instead of the removed blocking lock().
    output_mutex: std.atomic.Mutex = .unlocked,
};

pub fn externalSaTestCode(term: sio.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        else => 255,
    };
}

pub fn runSaTestFileExternal(sa_bin: []const u8, task: SaTestTask, index: usize, total: usize) !void {
    const suite_path = try sio.cwd().realpathAlloc(std.heap.page_allocator, task.path);
    defer std.heap.page_allocator.free(suite_path);
    const start_ns = startSaFileLog(task.path, "process", task.jobs_arg, index, total);
    // NOTE(Zig 0.17): `errdefer |err|` payload capture was removed after 0.14;
    // inner function + explicit catch preserves the structured error log marker.
    runSaTestFileExternalInner(sa_bin, task, index, total, suite_path, start_ns) catch |err| {
        errorSaFileLog(task.path, "process", index, total, err);
        return err;
    };
}

pub fn runSaTestFileExternalInner(sa_bin: []const u8, task: SaTestTask, index: usize, total: usize, suite_path: []const u8, start_ns: i128) !void {
    const argv = [_][]const u8{ sa_bin, "test", suite_path, "--jobs", task.jobs_arg, "--trace-panic" };

    const result = try sio.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = argv[0..],
        .max_output_bytes = 2 * 1024 * 1024,
    });
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    if (externalSaTestCode(result.term) != 0) {
        std.debug.print("stdout: {s}\n", .{result.stdout});
        std.debug.print("stderr: {s}\n", .{result.stderr});
        return error.SaTestFailed;
    }
    for (task.expectations.expected_passes) |expected_pass| {
        if (std.mem.indexOf(u8, result.stdout, expected_pass) == null) {
            std.debug.print("stdout missing expected marker for {s}: {s}\nstdout: {s}\n", .{ task.path, expected_pass, result.stdout });
            return error.SaTestMissingExpectedPass;
        }
    }
    for (task.expectations.expected_absent_passes) |absent_pass| {
        if (std.mem.indexOf(u8, result.stdout, absent_pass) != null) {
            std.debug.print("stdout contains unexpected marker for {s}: {s}\nstdout: {s}\n", .{ task.path, absent_pass, result.stdout });
            return error.SaTestUnexpectedPass;
        }
    }
    if (std.mem.indexOf(u8, result.stdout, task.expectations.expected_summary) == null) {
        std.debug.print("stdout missing expected summary for {s}: {s}\nstdout: {s}\n", .{ task.path, task.expectations.expected_summary, result.stdout });
        return error.SaTestMissingSummary;
    }
    if (result.stderr.len != 0) {
        std.debug.print("unexpected stderr for {s}: {s}\n", .{ task.path, result.stderr });
        return error.SaTestUnexpectedStderr;
    }
    endSaFileLog(task.path, "process", task.jobs_arg, index, total, start_ns, result.stdout.len, result.stderr.len);
}

pub fn saTestWorkerMain(context: *SaTestWorkerContext) void {
    while (true) {
        const index = context.next_index.fetchAdd(1, .monotonic);
        if (index >= context.tasks.len) return;
        runSaTestFileExternal(context.sa_bin, context.tasks[index], index + 1, context.tasks.len) catch |err| {
            context.failed.store(true, .release);
            while (!context.output_mutex.tryLock()) std.atomic.spinLoopHint();
            defer context.output_mutex.unlock();
            std.debug.print("[unit-framework] worker observed error file={s} err={s}\n", .{ context.tasks[index].path, @errorName(err) });
        };
    }
}

pub fn runQueuedSaTestFiles() !void {
    const tasks = queued_sa_tests.items;
    if (tasks.len == 0) return;
    defer {
        clearQueuedSaTestFiles();
    }

    const sa_bin = saBinaryPath(std.testing.allocator) orelse {
        for (tasks) |task| try runSaTestFileInProcess(task.path, task.expectations);
        return;
    };
    defer std.testing.allocator.free(sa_bin);

    const worker_count = @min(saUnitFileJobs(), tasks.len);
    if (worker_count <= 1) {
        for (tasks, 0..) |task, index| try runSaTestFileExternal(sa_bin, task, index + 1, tasks.len);
        return;
    }

    const start_ns = sio.nanoTimestamp();
    defer std.debug.print("[unit-framework] macro surface files elapsed={}ms file_jobs={} files={} mode=process\n", .{ elapsedMs(start_ns), worker_count, tasks.len });

    var context = SaTestWorkerContext{ .sa_bin = sa_bin, .tasks = tasks };
    var threads = try std.testing.allocator.alloc(std.Thread, worker_count);
    defer std.testing.allocator.free(threads);

    var started: usize = 0;
    var joined: usize = 0;
    errdefer {
        for (threads[joined..started]) |thread| thread.join();
    }
    while (started < worker_count) : (started += 1) {
        threads[started] = try std.Thread.spawn(.{}, saTestWorkerMain, .{&context});
    }
    while (joined < started) : (joined += 1) {
        threads[joined].join();
    }

    try std.testing.expect(!context.failed.load(.acquire));
}

pub fn clearQueuedSaTestFiles() void {
    for (queued_sa_tests.items) |task| {
        task.expectations.deinit(std.testing.allocator);
        std.testing.allocator.free(task.jobs_arg);
    }
    queued_sa_tests.deinit(std.testing.allocator);
    queued_sa_tests = .empty;
}

test "queued sa test worker failure returns test error without crashing" {
    defer clearQueuedSaTestFiles();

    const sa_bin_name: [:0]const u8 = "SA_BIN";
    const file_jobs_name: [:0]const u8 = "SA_UNIT_FILE_JOBS";
    const file_jobs_value: [:0]const u8 = "2";

    const saved_sa_bin = try saveEnvVarZ(std.testing.allocator, "SA_BIN");
    defer if (saved_sa_bin) |value| std.testing.allocator.free(value);
    const sa_bin_value: [:0]const u8 = if (saved_sa_bin) |value| value else if (builtin.os.tag == .windows) "sa.exe" else "sa";
    const saved_file_jobs = try saveEnvVarZ(std.testing.allocator, "SA_UNIT_FILE_JOBS");
    defer if (saved_file_jobs) |value| std.testing.allocator.free(value);

    try setEnvVarZ(sa_bin_name, sa_bin_value);
    defer restoreEnvVarZ(sa_bin_name, saved_sa_bin) catch unreachable;
    try setEnvVarZ(file_jobs_name, file_jobs_value);
    defer restoreEnvVarZ(file_jobs_name, saved_file_jobs) catch unreachable;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try writeSource(tmp.dir, "queued_pass.sa",
        \\@test "queued pass"():
        \\L_ENTRY:
        \\    return
        \\
    );
    try writeSource(tmp.dir, "queued_fail.sa",
        \\@test "queued fail"():
        \\L_ENTRY:
        \\    panic(991)
        \\
    );

    const pass_path = try tmp.dir.realPathFileAlloc(std.testing.io, "queued_pass.sa", std.testing.allocator);
    defer std.testing.allocator.free(pass_path);
    const fail_path = try tmp.dir.realPathFileAlloc(std.testing.io, "queued_fail.sa", std.testing.allocator);
    defer std.testing.allocator.free(fail_path);

    try enqueueSaTestFile(pass_path, .{
        .expected_passes = &.{"[PASS] queued pass"},
        .expected_summary = "test result: ok. 1 passed; 0 failed; 0 skipped",
    });
    try enqueueSaTestFile(fail_path, .{
        .expected_passes = &.{"[PASS] queued fail"},
        .expected_summary = "test result: ok. 1 passed; 0 failed; 0 skipped",
    });

    try std.testing.expectError(error.TestUnexpectedResult, runQueuedSaTestFiles());
    try std.testing.expectEqual(@as(usize, 0), queued_sa_tests.items.len);
}
