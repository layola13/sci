const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const writeSource = helpers.writeSource;

test "sa test covers include macro expansion fixture" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/include_macro_expand_unit.sa");
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const test_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "1" };
    const test_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        test_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (test_code != 0 or stderr_buffer.items.len != 0) {
        std.debug.print("sa test failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ stdout_buffer.items, stderr_buffer.items });
    }
    try std.testing.expectEqual(@as(u8, 0), test_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] include macro expands source into current file"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "sa test covers module_path macro expansion fixture" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/module_path_macro_unit.sa");
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const test_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "1" };
    const test_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        test_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (test_code != 0 or stderr_buffer.items.len != 0) {
        std.debug.print("sa test failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ stdout_buffer.items, stderr_buffer.items });
    }
    try std.testing.expectEqual(@as(u8, 0), test_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] module_path macro reports the current source path suffix"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "sa test runs isolated native tests with filterable names" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/unit_test_basic.sa");
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const test_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "1" };
    const test_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        test_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (test_code != 0 or stderr_buffer.items.len != 0) {
        std.debug.print("sa test failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ stdout_buffer.items, stderr_buffer.items });
    }
    try std.testing.expectEqual(@as(u8, 0), test_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] simple pass"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] another test"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 2 passed; 0 failed; 0 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const list_argv = [_][]const u8{ "sa", "test", source_path, "--list", "--filter", "simple" };
    const list_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        list_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), list_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "tests:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "- simple pass"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test count: 1"));
    try std.testing.expect(std.mem.indexOf(u8, stdout_buffer.items, "[PASS]") == null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buffer.items, "another test") == null);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const list_only_source =
        \\@extern missing_runtime_probe() -> void
        \\
        \\@test "list avoids backend link"():
        \\L_ENTRY:
        \\    call @missing_runtime_probe()
        \\    return
    ;
    try writeSource(tmp.dir, "list_only.sa", list_only_source);
    const list_only_argv = [_][]const u8{ "sa", "test", "list_only.sa", "--list" };
    const list_only_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        list_only_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), list_only_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "list avoids backend link"));
    try std.testing.expect(std.mem.indexOf(u8, stdout_buffer.items, "[PASS]") == null);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const filter_argv = [_][]const u8{ "sa", "test", source_path, "--filter", "another" };
    const filter_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        filter_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), filter_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] another test"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 1 skipped"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const exact_argv = [_][]const u8{ "sa", "test", source_path, "--exact", "--filter", "simple pass" };
    const exact_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        exact_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), exact_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] simple pass"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 1 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const should_panic_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/unit_test_should_panic.sa");
    defer std.testing.allocator.free(should_panic_path);

    const should_panic_argv = [_][]const u8{ "sa", "test", should_panic_path };
    const should_panic_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        should_panic_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), should_panic_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] panic path"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const assert_source =
        \\@extern sa_assert_eq_i64(actual: i64, expected: i64, code: i32) -> void
        \\@extern sa_assert_eq_i64_at(actual: i64, expected: i64, code: i32, &file: ptr, file_len: u64, line: u32, col: u32) -> void
        \\@extern sa_test_debug_i64(&name: ptr, name_len: u64, value: i64) -> void
        \\@const ACTUAL_NAME = utf8:"actual"
        \\@const ASSERT_FILE = utf8:"assert_values.sa"
        \\
        \\@test "assert equal reports values"():
        \\L_FAIL:
        \\    actual = add 40, 1
        \\    call @sa_test_debug_i64(*ACTUAL_NAME, 6, actual)
        \\    call @sa_assert_eq_i64_at(actual, 42, 103, *ASSERT_FILE, 16, 9, 5)
        \\    !actual
        \\    return
        \\
    ;
    try writeSource(tmp.dir, "assert_values.sa", assert_source);

    const compile_only_argv = [_][]const u8{ "sa", "test", "assert_values.sa", "--compile-only" };
    const compile_only_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        compile_only_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), compile_only_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "compiled 1 selected tests (1 discovered)"));
    try std.testing.expect(std.mem.indexOf(u8, stdout_buffer.items, "[FAIL]") == null);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const assert_argv = [_][]const u8{ "sa", "test", "assert_values.sa", "--jobs", "1", "--trace-panic" };
    const assert_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        assert_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), assert_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[FAIL] assert equal reports values"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: FAILED. 0 passed; 1 failed; 0 skipped"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "test location: assert_values.sa:6:1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "code path: assert_values.sa::_saasm_test_"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "panic: code=103"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "panic location: assert_values.sa:9:5"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "trace-panic: enabled"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "recent scalars:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "actual=41"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "assertion failed:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "expected: 42"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "actual: 41"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "PANIC[103]: assert_values.sa:9:5: expected=42 actual=41"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const skip_argv = [_][]const u8{ "sa", "test", source_path, "--skip", "another" };
    const skip_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        skip_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), skip_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] simple pass"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 1 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const ignored_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/unit_test_ignored.sa");
    defer std.testing.allocator.free(ignored_path);

    const ignored_default_argv = [_][]const u8{ "sa", "test", ignored_path };
    const ignored_default_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        ignored_default_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), ignored_default_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] active case"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped; 1 ignored"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const ignored_only_argv = [_][]const u8{ "sa", "test", ignored_path, "--ignored" };
    const ignored_only_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        ignored_only_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), ignored_only_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] ignored case"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 1 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const include_ignored_argv = [_][]const u8{ "sa", "test", ignored_path, "--include-ignored" };
    const include_ignored_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        include_ignored_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), include_ignored_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] active case"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] ignored case"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 2 passed; 0 failed; 0 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const source_text = try sio.cwd().readFileAlloc(std.testing.allocator, source_path, 1024 * 1024);
    defer std.testing.allocator.free(source_text);
    var flat = try saasm.flattener.flatten(std.testing.allocator, source_text);
    defer flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), flat.test_sigs.len);
    try std.testing.expect(std.mem.eql(u8, flat.test_sigs[0].llvm_name.?, "_saasm_test_0"));
    try std.testing.expect(std.mem.eql(u8, flat.test_sigs[1].llvm_name.?, "_saasm_test_1"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const signal_source =
        \\// Native test fixture that terminates via a real POSIX signal.
        \\
        \\@extern raise(sig: i32) -> i32
        \\
        \\@test "signal abort"():
        \\L_SIGNAL:
        \\    call @raise(6)
        \\    panic(99)
        \\
    ;
    try writeSource(tmp.dir, "signal.sa", signal_source);
    const signal_path = "signal.sa";

    const signal_argv = [_][]const u8{ "sa", "test", signal_path };
    const signal_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        signal_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), signal_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "terminated by signal"));
}

test "sa test arc drop frees once (task 104 regression)" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/unit_test_arc_double_free.sa");
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    // --no-incremental: the project test cache keys on the .sa source hash,
    // so a stale binary built before a codegen fix would mask a regression.
    const test_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "1", "--no-incremental" };
    const test_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        test_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (test_code != 0 or stderr_buffer.items.len != 0) {
        std.debug.print("sa test failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ stdout_buffer.items, stderr_buffer.items });
    }
    try std.testing.expectEqual(@as(u8, 0), test_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] arc drop frees once"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "sa test barrier123 three workers drop Arc once (task 125 regression)" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/unit_test_arc_barrier123.sa");
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    // --no-incremental: the project test cache keys on the .sa source hash,
    // so a stale binary built before a codegen fix would mask a regression.
    const test_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "1", "--no-incremental" };
    const test_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        test_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (test_code != 0 or stderr_buffer.items.len != 0) {
        std.debug.print("sa test failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ stdout_buffer.items, stderr_buffer.items });
    }
    try std.testing.expectEqual(@as(u8, 0), test_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] barrier123 three workers drop Arc once"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 1 passed; 0 failed; 0 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "sa test schedules native tests in parallel when jobs are higher" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/unit_test_jobs_parallel.sa");
    defer std.testing.allocator.free(source_path);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const serial_start = sio.nanoTimestamp();
    const serial_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "1" };
    const serial_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        serial_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    const serial_elapsed: i128 = sio.nanoTimestamp() - serial_start;
    if (serial_code != 0 or stderr_buffer.items.len != 0) {
        std.debug.print(
            "parallel jobs serial run failed:\nstdout:\n{s}\nstderr:\n{s}\n",
            .{ stdout_buffer.items, stderr_buffer.items },
        );
    }
    try std.testing.expectEqual(@as(u8, 0), serial_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] slow one"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] slow two"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] slow three"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] slow four"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 4 passed; 0 failed; 0 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const parallel_start = sio.nanoTimestamp();
    const parallel_argv = [_][]const u8{ "sa", "test", source_path, "--jobs", "4" };
    const parallel_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        parallel_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    const parallel_elapsed: i128 = sio.nanoTimestamp() - parallel_start;
    if (parallel_code != 0 or stderr_buffer.items.len != 0) {
        std.debug.print(
            "parallel jobs parallel run failed:\nstdout:\n{s}\nstderr:\n{s}\n",
            .{ stdout_buffer.items, stderr_buffer.items },
        );
    }
    try std.testing.expectEqual(@as(u8, 0), parallel_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] slow one"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] slow two"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] slow three"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] slow four"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "test result: ok. 4 passed; 0 failed; 0 skipped"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const min_gap_ns: i128 = 400 * std.time.ns_per_ms;
    try std.testing.expect(serial_elapsed > parallel_elapsed + min_gap_ns);
}
