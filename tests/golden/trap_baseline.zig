const std = @import("std");
const saasm = @import("saasm");

fn assertBuildExeTrap(path: []const u8, out_name: []const u8, expected_trap: []const u8, expected_trap_code: u32, expected_message: []const u8) !void {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", out_name };
    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(out_name, .{}));
    const bc_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.sa.bc", .{out_name});
    defer std.testing.allocator.free(bc_name);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(bc_name, .{}));

    var trap_buf: [64]u8 = undefined;
    const trap_text = try std.fmt.bufPrint(&trap_buf, "\"trap\":\"{s}\"", .{expected_trap});
    var code_buf: [32]u8 = undefined;
    const code_text = try std.fmt.bufPrint(&code_buf, "\"trap_code\":{d}", .{expected_trap_code});
    var summary_buf: [256]u8 = undefined;
    const summary_text = try std.fmt.bufPrint(&summary_buf, "error[{s}]: {s}\n", .{ expected_trap, expected_message });
    try std.testing.expect(std.mem.startsWith(u8, stderr_buffer.items, summary_text));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, trap_text));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, code_text));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, expected_message));
}

const TrapCase = struct {
    path: []const u8,
    out_name: []const u8,
    trap: []const u8,
    code: u32,
    message: []const u8,
};

test "golden trap baseline regression stays stable" {
    const cases = [_]TrapCase{
        .{ .path = "demos/support/unknown_register.sa", .out_name = "unknown_register.out", .trap = "UnknownRegister", .code = 1007, .message = "register is not declared in the current scope" },
        .{ .path = "demos/support/use_after_move.sa", .out_name = "use_after_move.out", .trap = "UseAfterMove", .code = 1009, .message = "moved value is no longer usable" },
        .{ .path = "demos/support/borrow_conflict.sa", .out_name = "borrow_conflict.out", .trap = "BorrowConflict", .code = 1008, .message = "borrow rules reject this access" },
        .{ .path = "demos/support/memory_leak.sa", .out_name = "memory_leak.out", .trap = "MemoryLeak", .code = 1012, .message = "live registers remain at function exit" },
        .{ .path = "demos/support/phi_conflict.sa", .out_name = "phi_conflict.out", .trap = "PhiStateConflict", .code = 1015, .message = "incoming control-flow states do not agree" },
        .{ .path = "demos/support/macro_recursion.sa", .out_name = "macro_recursion.out", .trap = "MacroRecursionLimit", .code = 1005, .message = "macro recursion limit exceeded" },
        .{ .path = "demos/support/forbidden_syntax.sa", .out_name = "forbidden_syntax.out", .trap = "ForbiddenSyntax", .code = 1001, .message = "forbidden syntax detected during flattening" },
        .{ .path = "demos/support/illegal_unsafe_context.sa", .out_name = "illegal_unsafe_context.out", .trap = "IllegalUnsafeContext", .code = 1019, .message = "raw pointer and assume_* instructions are only legal inside @ffi_wrapper" },
        .{ .path = "demos/support/early_return_leak.sa", .out_name = "early_return_leak.out", .trap = "EarlyReturnLeak", .code = 1026, .message = "early return would leak live registers" },
        .{ .path = "demos/support/atomic_ordering_mismatch.sa", .out_name = "atomic_ordering_mismatch.out", .trap = "AtomicOrderingMismatch", .code = 1029, .message = "same-address RMW ordering combination is not allowed" },
        .{ .path = "demos/support/invalid_atomic_ordering.sa", .out_name = "invalid_atomic_ordering.out", .trap = "InvalidAtomicOrdering", .code = 1028, .message = "invalid atomic ordering" },
        .{ .path = "demos/support/capability_mismatch.sa", .out_name = "capability_mismatch.out", .trap = "CapabilityMismatch", .code = 1013, .message = "call-site capability prefix does not match the callee contract" },
    };

    inline for (cases) |case| {
        try assertBuildExeTrap(case.path, case.out_name, case.trap, case.code, case.message);
    }
}
