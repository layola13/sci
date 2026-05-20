const std = @import("std");

const test_executor = @import("test_executor.zig");
const test_formatter = @import("test_formatter.zig");
const test_meta = @import("test_meta.zig");
const test_result = @import("test_result.zig");

const SharedState = struct {
    executor: test_executor.TestExecutor,
    tests: []const test_meta.TestDescAndFn,
    next_index: std.atomic.Value(usize),
    results: []?test_result.TestOutcome,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
    results_mutex: std.Thread.Mutex = .{},
    output_mutex: std.Thread.Mutex = .{},
    summary: test_formatter.RunSummary = .{},
};

fn freeOutcome(allocator: std.mem.Allocator, outcome: test_result.TestOutcome) void {
    switch (outcome) {
        .failed => |failure| if (failure.stderr.len != 0) allocator.free(failure.stderr),
        else => {},
    }
}

fn workerMain(shared: *SharedState) void {
    while (true) {
        const index = shared.next_index.fetchAdd(1, .monotonic);
        if (index >= shared.tests.len) return;
        const test_case = shared.tests[index];
        const outcome = shared.executor.run(test_case);

        shared.results_mutex.lock();
        shared.results[index] = outcome;
        shared.summary.record(outcome);
        shared.results_mutex.unlock();

        shared.output_mutex.lock();
        defer shared.output_mutex.unlock();
        _ = test_formatter.writeOutcome(shared.stdout, shared.stderr, test_case, outcome) catch {};
    }
}

pub fn run(
    allocator: std.mem.Allocator,
    exe_path: []const u8,
    cwd_dir: std.fs.Dir,
    test_list: *test_meta.TestList,
    selection: test_meta.TestSelection,
    jobs: ?usize,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
) !u8 {
    defer test_list.deinit(allocator);

    const run_count = selection.countSelected(test_list.tests);
    const summary_count = selection.countTowardSummary(test_list.tests);

    if (run_count == 0) {
        var summary: test_formatter.RunSummary = .{};
        for (test_list.tests) |test_case| {
            if (selection.shouldRun(test_case)) continue;
            if (test_case.desc.ignored) {
                summary.ignored += 1;
            } else {
                summary.skipped += 1;
            }
        }
        try test_formatter.writeSummary(stdout, summary);
        return 0;
    }

    const effective_jobs = jobs orelse std.Thread.getCpuCount() catch 1;
    const worker_count = @max(@as(usize, 1), @min(effective_jobs, run_count));

    const results = try allocator.alloc(?test_result.TestOutcome, test_list.tests.len);
    defer allocator.free(results);
    for (results) |*slot| slot.* = null;

    var shared = SharedState{
        .executor = .{
            .allocator = allocator,
            .exe_path = exe_path,
            .cwd_dir = cwd_dir,
            .selection = selection,
        },
        .tests = test_list.tests,
        .next_index = std.atomic.Value(usize).init(0),
        .results = results,
        .stdout = stdout,
        .stderr = stderr,
    };

    if (worker_count > 1) {
        const spawned_count = worker_count - 1;
        var threads = try allocator.alloc(std.Thread, spawned_count);
        defer allocator.free(threads);
        var started_threads: usize = 0;
        errdefer {
            while (started_threads > 0) {
                started_threads -= 1;
                threads[started_threads].join();
            }
        }

        while (started_threads < spawned_count) : (started_threads += 1) {
            threads[started_threads] = try std.Thread.spawn(.{}, workerMain, .{&shared});
        }

        workerMain(&shared);

        while (started_threads > 0) {
            started_threads -= 1;
            threads[started_threads].join();
        }
    } else {
        workerMain(&shared);
    }

    _ = summary_count;
    try test_formatter.writeSummary(stdout, shared.summary);
    for (results) |maybe_outcome| {
        if (maybe_outcome) |outcome| freeOutcome(allocator, outcome);
    }
    return if (shared.summary.failed == 0) 0 else 1;
}
