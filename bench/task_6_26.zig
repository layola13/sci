const std = @import("std");
const saasm = @import("src/lib.zig");

const default_line_goal: usize = 1_000_000;
const fixed_lines: usize = 17;

const BenchError = error{
    InvalidArguments,
    VerificationTrap,
};

const Program = struct {
    source: []u8,

    fn deinit(self: *Program, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        self.* = undefined;
    }
};

fn appendLine(list: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    try list.writer().print(fmt, args);
    try list.append('\n');
}

fn parseLineGoal(args: []const []const u8) !usize {
    if (args.len <= 1) return default_line_goal;

    const arg = args[1];
    if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
        return BenchError.InvalidArguments;
    }

    if (std.mem.eql(u8, arg, "--lines")) {
        if (args.len < 3) return BenchError.InvalidArguments;
        return try std.fmt.parseInt(usize, args[2], 10);
    }

    if (std.mem.startsWith(u8, arg, "--lines=")) {
        return try std.fmt.parseInt(usize, arg["--lines=".len..], 10);
    }

    return std.fmt.parseInt(usize, arg, 10) catch default_line_goal;
}

fn buildProgram(allocator: std.mem.Allocator, line_goal: usize) !Program {
    var source = try std.ArrayList(u8).initCapacity(allocator, line_goal * 32);
    errdefer source.deinit();

    const repeat_count = if (line_goal > fixed_lines) line_goal - fixed_lines else 1;

    try appendLine(&source, "#loc \"bench.rs\":1:1", .{});
    try appendLine(&source, "@helper() -> i32!:", .{});
    try appendLine(&source, "return 7", .{});
    try appendLine(&source, "@ffi_wrapper airlock(x: ptr) -> ptr:", .{});
    try appendLine(&source, "y = *x", .{});
    try appendLine(&source, "z = assume_safe y", .{});
    try appendLine(&source, "w = assume_borrow y", .{});
    try appendLine(&source, "!w", .{});
    try appendLine(&source, "!x", .{});
    try appendLine(&source, "return z", .{});
    try appendLine(&source, "@spin() -> i32:", .{});
    try appendLine(&source, "L_LOOP:", .{});

    for (0..repeat_count) |_| {
        try appendLine(&source, "fence", .{});
    }

    try appendLine(&source, "jmp L_LOOP", .{});
    try appendLine(&source, "@main() -> i32!:", .{});
    try appendLine(&source, "x = call @helper()", .{});
    try appendLine(&source, "y = ? x", .{});
    try appendLine(&source, "return y", .{});

    return .{ .source = try source.toOwnedSlice() };
}

fn runOnce(allocator: std.mem.Allocator, source: []const u8) !struct {
    source_lines: usize,
    flattened_lines: usize,
    flatten_ns: u64,
    verify_ns: u64,
} {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const bench_allocator = arena.allocator();

    var timer = try std.time.Timer.start();

    var flat = try saasm.flattener.flatten(bench_allocator, source);
    const flatten_ns = timer.lap();
    defer flat.deinit(bench_allocator);

    const flattened_lines = flat.instructions.len;
    const verified = try saasm.referee.verify(bench_allocator, flat.instructions, flat.const_decls);
    const verify_ns = timer.lap();

    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(bench_allocator);
        },
        .trap => |report| {
            const stderr = std.io.getStdErr().writer();
            try stderr.print(
                "benchmark program failed verification: {s} at line {d} source_line {d} register {s} function {s} ({s})\n",
                .{
                    @tagName(report.trap),
                    report.line,
                    report.source_line,
                    report.register orelse "-",
                    report.function orelse "-",
                    report.message,
                },
            );
            return BenchError.VerificationTrap;
        },
    }

    return .{
        .source_lines = std.mem.count(u8, source, "\n"),
        .flattened_lines = flattened_lines,
        .flatten_ns = flatten_ns,
        .verify_ns = verify_ns,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    const line_goal = parseLineGoal(argv) catch {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("usage: zig run bench/task_6_26.zig [--lines N | N]\n");
        return BenchError.InvalidArguments;
    };

    var program = try buildProgram(allocator, line_goal);
    defer program.deinit(allocator);

    const result = try runOnce(allocator, program.source);
    const total_ns = result.flatten_ns + result.verify_ns;
    const seconds = @as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0;
    const lines_per_sec = if (total_ns == 0) 0.0 else @as(f64, @floatFromInt(result.source_lines)) / seconds;

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "task 6.26\nrequested lines: {d}\nprogram lines: {d}\nflattened lines: {d}\nflatten: {d:.3} ms\nverify: {d:.3} ms\ntotal: {d:.3} ms\nlines/sec: {d:.2}\n",
        .{
            line_goal,
            result.source_lines,
            result.flattened_lines,
            @as(f64, @floatFromInt(result.flatten_ns)) / 1_000_000.0,
            @as(f64, @floatFromInt(result.verify_ns)) / 1_000_000.0,
            @as(f64, @floatFromInt(total_ns)) / 1_000_000.0,
            lines_per_sec,
        },
    );
}
