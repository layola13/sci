const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const writeSource = helpers.writeSource;
const runCommand = helpers.runCommand;
const runCommandAnyExit = helpers.runCommandAnyExit;
const assertBuildExeLinkFailure = helpers.assertBuildExeLinkFailure;

test "atomic instructions work end to end and emit real LLVM" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\atomic_store node+0, 5 seq_cst
        \\fence release
        \\x = atomic_load node+0 seq_cst
        \\old = atomic_rmw_add node+0, 3 seq_cst
        \\cmp_old, ok = cmpxchg node+0, 8, 11 acq_rel acquire
        \\y = atomic_load node+0 seq_cst
        \\^x
        \\^old
        \\^cmp_old
        \\^ok
        \\!node
        \\return y
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "atomic.sa", source);

    const run_argv = [_][]const u8{ "sa", "run", "atomic.sa" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 11), run_code);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "atomic.sa", "-o", "atomic.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const artifact_file = try tmp.dir.openFile(std.testing.io, "atomic.out.sa.bc", .{});
    defer artifact_file.close(std.testing.io);
    const artifact_bytes = try sio.readToEndAlloc(artifact_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./atomic.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 11), code),
        else => return error.TestUnexpectedResult,
    }

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", "atomic.sa", "-o", "atomic.wasm", "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm_file = try tmp.dir.openFile(std.testing.io, "atomic.wasm", .{});
    defer wasm_file.close(std.testing.io);
    const wasm_bytes = try sio.readToEndAlloc(wasm_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);

    const build_obj_argv = [_][]const u8{ "sa", "build-obj", "atomic.sa", "-o", "atomic.o" };
    const obj_code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), obj_code);

    const obj_file = try tmp.dir.openFile(std.testing.io, "atomic.o", .{});
    defer obj_file.close(std.testing.io);
    const obj_bytes = try sio.readToEndAlloc(obj_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(obj_bytes);
    try std.testing.expect(obj_bytes.len > 0);
}

test "ptr arithmetic lowers to gep and runs through the interpreter" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\one_buf = alloc 8
        \\store one_buf+0, 1 as i64
        \\one = load one_buf+0 as i64
        \\p = ptr_add node, one
        \\store p+0, 65 as i32
        \\value = load p+0 as i32
        \\!p
        \\!one
        \\!one_buf
        \\!node
        \\return value
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "ptr_add.sa", source);

    const run_argv = [_][]const u8{ "sa", "run", "ptr_add.sa" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 65), run_code);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "ptr_add.sa", "-o", "ptr_add.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const artifact_file = try tmp.dir.openFile(std.testing.io, "ptr_add.out.sa.bc", .{});
    defer artifact_file.close(std.testing.io);
    const artifact_bytes = try sio.readToEndAlloc(artifact_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./ptr_add.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 65), code),
        else => return error.TestUnexpectedResult,
    }
}

test "invalid cmpxchg ordering is rejected by the flattener" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\old, ok = cmpxchg node+0, 0, 1 acquire seq_cst
        \\return 0
    ;

    try std.testing.expectError(error.InvalidAtomicOrdering, saasm.flattener.flatten(std.testing.allocator, source));
}

test "atomic ordering mismatch is rejected by the verifier" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\old = atomic_rmw_add node+0, 1 acquire
        \\old2 = atomic_rmw_sub node+0, 1 release
        \\return 0
    ;

    var flat = try saasm.flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try saasm.referee.verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => return error.TestUnexpectedResult,
        .trap => |report| {
            try std.testing.expectEqual(saasm.common.trap.Trap.atomic_ordering_mismatch, report.trap);
            try std.testing.expect(std.mem.containsAtLeast(u8, report.message, 1, "same-address RMW ordering combination"));
        },
    }
}

test "panic lowers to native executable failure code" {
    const source =
        \\@helper() -> i32:
        \\panic(13)
        \\@main() -> i32:
        \\buf = alloc 3
        \\store buf+0, 104 as i8
        \\store buf+1, 105 as i8
        \\store buf+2, 0 as i8
        \\panic_msg(77, *buf, 2)
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "panic_native.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "panic_native.sa", "-o", "panic_native.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const artifact_file = try tmp.dir.openFile(std.testing.io, "panic_native.out.sa.bc", .{});
    defer artifact_file.close(std.testing.io);
    const artifact_bytes = try sio.readToEndAlloc(artifact_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./panic_native.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 205), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(std.mem.containsAtLeast(u8, exe_result.stderr, 1, "PANIC[77]: hi"));

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", "panic_native.sa", "-o", "panic_native.wasm", "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm = try tmp.dir.openFile(std.testing.io, "panic_native.wasm", .{});
    defer wasm.close(std.testing.io);
    const wasm_bytes = try sio.readToEndAlloc(wasm, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);
}

test "raw pointer escape is rejected outside ffi wrapper" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\raw = *node
        \\return 0
    ;

    var flat = try saasm.flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try saasm.referee.verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => return error.TestUnexpectedResult,
        .trap => |report| {
            try std.testing.expectEqual(saasm.common.trap.Trap.illegal_unsafe_context, report.trap);
            try std.testing.expectEqual(@as(?bool, false), report.is_ffi_wrapper);
        },
    }
}

test "extern export ffi wrapper map to real declarations and symbols" {
    const source =
        \\@extern ext_add(lhs: i32, rhs: i32) -> i32
        \\@ffi_wrapper wrap(*raw: ptr) -> ptr:
        \\safe = assume_safe raw
        \\return safe
        \\@export exported() -> i32:
        \\jmp L_ENTRY
        \\L_ENTRY:
        \\value = call @ext_add(1, 2)
        \\return value
        \\@main() -> i32:
        \\return 7
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "contracts.sa", source);

    const build_obj_argv = [_][]const u8{ "sa", "build-obj", "contracts.sa", "-o", "contracts.o" };
    const code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), code);

    const artifact_file = try tmp.dir.openFile(std.testing.io, "contracts.o.sa.bc", .{});
    defer artifact_file.close(std.testing.io);
    const artifact_bytes = try sio.readToEndAlloc(artifact_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(artifact_bytes);
    try std.testing.expect(artifact_bytes.len > 0);

    const nm_output = try runCommand(std.testing.allocator, &[_][]const u8{ "nm", "-g", "--defined-only", "contracts.o" });
    defer std.testing.allocator.free(nm_output);

    try std.testing.expect(std.mem.containsAtLeast(u8, nm_output, 1, " exported"));
    try std.testing.expect(std.mem.containsAtLeast(u8, nm_output, 1, " wrap"));
    try std.testing.expect(std.mem.containsAtLeast(u8, nm_output, 1, " saasm_main"));
    try std.testing.expect(std.mem.containsAtLeast(u8, nm_output, 1, " main"));
}

test "unknown sys intrinsic is rejected before emission" {
    const source =
        \\@main() -> i32:
        \\value = call @sys_not_supported()
        \\return value
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "unsupported_sys.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "unsupported_sys.sa", "-o", "unsupported_sys.out" };
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "unsupported_sys.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "unsupported_sys.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"UnsupportedSysIntrinsic\""));
}

test "external compiler failures report linker context instead of child process noise" {
    const source =
        \\@extern missing_symbol() -> i32
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\value = call @missing_symbol()
        \\return value
    ;

    try assertBuildExeLinkFailure("link_fail.sa", source, "link_fail.out", "ld.lld: error: undefined symbol: missing_symbol");
}

test "unknown register demo is rejected with structured trap output" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/unknown_register.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "unknown_register.out" };
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "unknown_register.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "unknown_register.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"UnknownRegister\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1007"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"register\":\"ghost\""));
}

test "memory leak demo is rejected with structured trap output" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/memory_leak.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "memory_leak.out" };
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "memory_leak.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "memory_leak.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"MemoryLeak\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1012"));
}

test "fallthrough demo is rejected without a terminator" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/fallthrough.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "fallthrough.out" };
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "fallthrough.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "fallthrough.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"FallthroughForbidden\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1014"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "function body ended without a terminator"));
}

test "duplicate label demo is rejected with structured trap output" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/duplicate_label.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "duplicate_label.out" };
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "duplicate_label.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "duplicate_label.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"DuplicateLabel\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1003"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "label is already defined"));
}

test "phi conflict demo is rejected on mismatched join states" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/phi_conflict.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "phi_conflict.out" };
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "phi_conflict.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "phi_conflict.out.sa.bc", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"PhiStateConflict\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1015"));
}

test "phi join AND demo runs through the join point" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/phi_join_and.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "phi_join_and.out" };
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const run_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./phi_join_and.out"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .exited => |exit_code| try std.testing.expectEqual(@as(u8, 0), exit_code),
        else => return error.TestUnexpectedResult,
    }
}
