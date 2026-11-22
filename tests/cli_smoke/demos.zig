const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const writeSource = helpers.writeSource;
const runCommand = helpers.runCommand;
const runCommandAnyExit = helpers.runCommandAnyExit;
const runWasmWithNode = helpers.runWasmWithNode;
const assertRunStdout = helpers.assertRunStdout;
const assertBuildExeStdout = helpers.assertBuildExeStdout;

test "hello world demo prints through sa run" {
    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "demos/rosetta/01_hello_world/main.sa" };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), run_code);
    try std.testing.expectEqualStrings("hello, saasm\n", stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

test "sa run reports unsupported extern symbol names" {
    const source =
        \\@extern sa_missing_plugin() -> i32
        \\
        \\@main() -> i32:
        \\value = call @sa_missing_plugin()
        \\return value
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "extern_run.sa", source);

    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "extern_run.sa" };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 1), run_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, "sa run unsupported extern: sa_missing_plugin"));
    try std.testing.expect(std.mem.indexOf(u8, stderr_buf.items, "UnsupportedExtern") == null);
}

test "hello world demo prints through build-wasm and node wasi" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const node_probe = sio.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/01_hello_world/main.sa");
    defer std.testing.allocator.free(source_path);

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", source_path, "-o", "hello.wasm", "--target", "wasm32" };
    const build_wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "hello.out" };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const native_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./hello.out"});
    defer std.testing.allocator.free(native_result.stdout);
    defer std.testing.allocator.free(native_result.stderr);
    switch (native_result.term) {
        .exited => |code| {
            if (code != 0 or !std.mem.eql(u8, native_result.stdout, "hello, saasm\n") or native_result.stderr.len != 0) {
                std.debug.print("native hello demo failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ native_result.stdout, native_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("hello, saasm\n", native_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), native_result.stderr.len);

    const node_result = try runWasmWithNode(std.testing.allocator, "hello.wasm", &.{ "sa", "hello.wasm" });
    defer std.testing.allocator.free(node_result.stdout);
    defer std.testing.allocator.free(node_result.stderr);
    switch (node_result.term) {
        .exited => |code| {
            if (code != 0 or !std.mem.containsAtLeast(u8, node_result.stdout, 1, "hello, saasm\n")) {
                std.debug.print("wasm hello demo failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ node_result.stdout, node_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("hello, saasm\n", node_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), node_result.stderr.len);
}

test "wasm32 ptr slot convention: MAP_FAILED sentinel checks fire (DEF-WASM32-PTR-REPR)" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const node_probe = sio.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    // chk: wasi-libc rejects flags 16418, mmap returns -1, and the
    // `-1 as ptr` sentinel check must fire (exit 7). On the defective
    // emitter the literal materializes as i64 -1 while the return is
    // zero-extended (4294967295), the check misses, and the program
    // traps in munmap on the wild pointer (node reports exit 1).
    // ret: the failing return's low byte stays visible (exit 255).
    // f34: flags 34 succeeds end to end (exit 42).
    const cases = [_]struct { src: []const u8, out: []const u8, want: u8 }{
        .{ .src = "tests/wasm32_ptr_repr_chk.sa", .out = "chk.wasm", .want = 7 },
        .{ .src = "tests/wasm32_ptr_repr_ret.sa", .out = "ret.wasm", .want = 255 },
        .{ .src = "tests/wasm32_ptr_repr_f34.sa", .out = "f34.wasm", .want = 42 },
    };
    for (cases) |case| {
        const source_path = try original_cwd.realpathAlloc(std.testing.allocator, case.src);
        defer std.testing.allocator.free(source_path);
        const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", source_path, "-o", case.out, "--target", "wasm32" };
        const build_wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
        try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

        const node_result = try runWasmWithNode(std.testing.allocator, case.out, &.{ "sa", case.out });
        defer std.testing.allocator.free(node_result.stdout);
        defer std.testing.allocator.free(node_result.stderr);
        switch (node_result.term) {
            .exited => |code| try std.testing.expectEqual(case.want, code),
            else => return error.TestUnexpectedResult,
        }
    }
}

test "wasm32 std size_t conversion sites run end to end (DEF-WASM32-STD-WASM-USEAFTERMOVE)" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const node_probe = sio.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    // The client links sa_growvec_* / sa_mem_copy_nonoverlapping out of
    // the wasm32-wasi sa_std archive. On the unfixed tree that archive
    // cannot be built at all (the std unit dies with UseAfterMove), so
    // its absence here means "not built in this tree state": skip.
    // Build it with: zig build -Dtarget=wasm32-wasi
    //   -Dcpu=baseline+atomics+bulk_memory sa-std-static
    original_cwd.access("artifacts/sa_std/wasm32-wasi/libsa_std.a", .{}) catch
        return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    // growvec_new (site 2) -> std mem copy inside the buffer (site 1)
    // -> growvec_free (site 3); exit 42 only if every check passes.
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/wasm32_std_uam_client.sa");
    defer std.testing.allocator.free(source_path);
    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", source_path, "-o", "uam.wasm", "--target", "wasm32" };
    const build_wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

    const node_result = try runWasmWithNode(std.testing.allocator, "uam.wasm", &.{ "sa", "uam.wasm" });
    defer std.testing.allocator.free(node_result.stdout);
    defer std.testing.allocator.free(node_result.stderr);
    switch (node_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 42), code),
        else => return error.TestUnexpectedResult,
    }
}

test "windows llvm builds and runs hello world executable" {
    if (builtin.os.tag != .windows or !saasm.build_options.llvm_enabled) return error.SkipZigTest;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/01_hello_world/main.sa");
    defer std.testing.allocator.free(source_path);
    const build_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "hello.exe", "--no-incremental" };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, &build_argv));

    const file = try tmp.dir.openFile(std.testing.io, "hello.exe", .{});
    defer file.close(std.testing.io);
    var magic: [2]u8 = undefined;
    try file.reader().readNoEof(&magic);
    try std.testing.expectEqualStrings("MZ", &magic);

    const result = try runCommandAnyExit(std.testing.allocator, &.{".\\hello.exe"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("hello, saasm\n", result.stdout);
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
}

test "hello world upstream line can break in gdb" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const gdb_probe = sio.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "gdb", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(gdb_probe.stdout);
    defer std.testing.allocator.free(gdb_probe.stderr);
    switch (gdb_probe.term) {
        .exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source =
        \\#loc "hello.rs":10:4
        \\@main() -> i32:
        \\node = alloc 8
        \\!node
        \\return 7
    ;
    const upstream_source =
        \\// 1
        \\// 2
        \\// 3
        \\// 4
        \\// 5
        \\// 6
        \\// 7
        \\// 8
        \\// 9
        \\// 10
    ;
    try writeSource(tmp.dir, "hello.sa", source);
    try writeSource(tmp.dir, "hello.rs", upstream_source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "hello.sa", "-o", "hello.out", "-g" };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const gdb_dir = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(gdb_dir);
    const directory_cmd = try std.fmt.allocPrint(std.testing.allocator, "directory {s}", .{gdb_dir});
    defer std.testing.allocator.free(directory_cmd);

    const gdb_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{
        "gdb",
        "-q",
        "--nh",
        "--nx",
        "--batch",
        "-ex",
        "file ./hello.out",
        "-ex",
        directory_cmd,
        "-ex",
        "set pagination off",
        "-ex",
        "break hello.rs:10",
        "-ex",
        "run",
        "-ex",
        "frame",
    });
    defer std.testing.allocator.free(gdb_result.stdout);
    defer std.testing.allocator.free(gdb_result.stderr);
    switch (gdb_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("gdb returned nonzero exit code {d}\nstdout:\n{s}\nstderr:\n{s}\n", .{ code, gdb_result.stdout, gdb_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    const hit_in_stdout = std.mem.containsAtLeast(u8, gdb_result.stdout, 1, "Breakpoint 1,") and std.mem.containsAtLeast(u8, gdb_result.stdout, 1, "at hello.rs:10");
    const hit_in_stderr = std.mem.containsAtLeast(u8, gdb_result.stderr, 1, "Breakpoint 1,") and std.mem.containsAtLeast(u8, gdb_result.stderr, 1, "at hello.rs:10");
    if (!hit_in_stdout and !hit_in_stderr) {
        std.debug.print("gdb breakpoint was not hit:\nstdout:\n{s}\nstderr:\n{s}\n", .{ gdb_result.stdout, gdb_result.stderr });
    }
    try std.testing.expect(hit_in_stdout or hit_in_stderr);
}

test "hello compute demo prints through build-exe and build-wasm" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const node_probe = sio.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/98_build_pipeline/main.sa");
    defer std.testing.allocator.free(source_path);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "hello_compute.out" };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const native_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./hello_compute.out"});
    defer std.testing.allocator.free(native_result.stdout);
    defer std.testing.allocator.free(native_result.stderr);
    switch (native_result.term) {
        .exited => |code| {
            if (code != 0 or !std.mem.eql(u8, native_result.stdout, "6\n") or native_result.stderr.len != 0) {
                std.debug.print("native hello-compute failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ native_result.stdout, native_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("6\n", native_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), native_result.stderr.len);

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", source_path, "-o", "hello_compute.wasm", "--target", "wasm32" };
    const build_wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

    const node_result = try runWasmWithNode(std.testing.allocator, "hello_compute.wasm", &.{ "sa", "hello_compute.wasm" });
    defer std.testing.allocator.free(node_result.stdout);
    defer std.testing.allocator.free(node_result.stderr);
    switch (node_result.term) {
        .exited => |code| {
            if (code != 0 or !std.mem.eql(u8, node_result.stdout, "6\n") or node_result.stderr.len != 0) {
                std.debug.print("wasm hello-compute failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ node_result.stdout, node_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("6\n", node_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), node_result.stderr.len);
}

test "trait vtable demo runs through sa run" {
    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "demos/rosetta/07_trait_vtable/main.sa" };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), run_code);
    try std.testing.expectEqualStrings("77\n", stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

test "callback registration demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/rosetta/253_contract_callback_registration/main.sa", "253\n");
}

test "indirect calls shadowed by an early import resolve to valued callees" {
    try assertBuildExeStdout("demos/rosetta/334_indirect_import_shadow/main.sa", "334\n");
}

test "pkg lib dynamic demo compiles via object archive and prints through native link" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const main_source = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/220_pkg_lib_dynamic/main.sa");
    defer std.testing.allocator.free(main_source);
    const lib_source = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/220_pkg_lib_dynamic/lib/index.sa");
    defer std.testing.allocator.free(lib_source);
    const sa_std_archive_path = try original_cwd.realpathAlloc(std.testing.allocator, "artifacts/sa_std/libsa_std.a");
    defer std.testing.allocator.free(sa_std_archive_path);

    const main_obj = "220_pkg_lib_dynamic_main.o";
    const lib_obj = "220_pkg_lib_dynamic_lib.o";
    const lib_archive = "220_pkg_lib_dynamic_lib.a";
    const out_path = "220_pkg_lib_dynamic.out";

    const build_main_argv = [_][]const u8{ "sa", "build-obj", main_source, "-o", main_obj };
    const build_main_code = try saasm.cli.execute(std.testing.allocator, build_main_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_main_code);

    const build_lib_argv = [_][]const u8{ "sa", "build-obj", lib_source, "-o", lib_obj };
    const build_lib_code = try saasm.cli.execute(std.testing.allocator, build_lib_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_lib_code);

    _ = try runCommand(std.testing.allocator, &[_][]const u8{ "ar", "rcs", lib_archive, lib_obj });

    const link_argv = [_][]const u8{ "zig", "cc", main_obj, lib_archive, sa_std_archive_path, "-o", out_path };
    const link_stdout = try runCommand(std.testing.allocator, link_argv[0..]);
    defer std.testing.allocator.free(link_stdout);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./220_pkg_lib_dynamic.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("220\n", exe_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stderr.len);
}

test "comparison alias demos run through sa run" {
    try assertRunStdout("demos/rosetta/03_if_else/main.sa", "20\n");
    try assertRunStdout("demos/rosetta/04_loop/main.sa", "[0,0,0,0]\n");
    try assertRunStdout("demos/rosetta/21_while_loop/main.sa", "15\n");
    try assertRunStdout("demos/rosetta/24_factorial/main.sa", "120\n");
    try assertRunStdout("demos/rosetta/25_fibonacci/main.sa", "21\n");
}

test "ownership and borrow demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/02_mutability/main.sa", "20\n");
    try assertBuildExeStdout("demos/rosetta/20_boxed_value/main.sa", "9\n");
    try assertBuildExeStdout("demos/rosetta/26_reference_return/main.sa", "9\n");
    try assertBuildExeStdout("demos/rosetta/27_move_semantics/main.sa", "11\n");
    try assertBuildExeStdout("demos/rosetta/28_borrow_chains/main.sa", "12\n");
    try assertBuildExeStdout("demos/rosetta/51_refcount/main.sa", "10\n");
    try assertBuildExeStdout("demos/rosetta/58_borrow_update/main.sa", "10\n");
    try assertBuildExeStdout("demos/rosetta/61_thread_pool/main.sa", "5\n");
    try assertBuildExeStdout("demos/rosetta/67_resource_pool/main.sa", "20\n");
    try assertBuildExeStdout("demos/rosetta/52_queue_rotate/main.sa", "2,3,1\n");
    try assertBuildExeStdout("demos/rosetta/962_mut_borrow_code/main.sa", "962\n");
}

test "core control-flow and data demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/03_if_else/main.sa", "20\n");
    try assertBuildExeStdout("demos/rosetta/05_struct/main.sa", "(10,20)\n");
    try assertBuildExeStdout("demos/rosetta/06_enum_and_match/main.sa", "30\n");
    try assertBuildExeStdout("demos/rosetta/11_tuples/main.sa", "(3, 4)\n");
    try assertBuildExeStdout("demos/rosetta/13_array_sum/main.sa", "10\n");
    try assertBuildExeStdout("demos/rosetta/15_string_bytes/main.sa", "4\n");
    try assertBuildExeStdout("demos/rosetta/18_option_map/main.sa", "8\n");
    try assertBuildExeStdout("demos/rosetta/16_methods/main.sa", "25\n");
    try assertBuildExeStdout("demos/rosetta/24_factorial/main.sa", "120\n");
    try assertBuildExeStdout("demos/rosetta/25_fibonacci/main.sa", "21\n");
    try assertBuildExeStdout("demos/rosetta/29_const_data/main.sa", "6\n");
    try assertBuildExeStdout("demos/rosetta/31_trait_static_dispatch/main.sa", "16\n");
}

test "additional rosetta demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/12_destructuring/main.sa", "7\n");
    try assertBuildExeStdout("demos/rosetta/34_iterator_filter/main.sa", "6\n");
    try assertBuildExeStdout("demos/rosetta/35_iterator_fold/main.sa", "7\n");
    try assertBuildExeStdout("demos/rosetta/36_tuple_struct/main.sa", "14\n");
    try assertBuildExeStdout("demos/rosetta/40_impl_block_state/main.sa", "15\n");
    try assertBuildExeStdout("demos/rosetta/41_module_imports/main.sa", "42\n");
    try assertBuildExeStdout("demos/rosetta/42_export_visibility/main.sa", "12\n");
    try assertBuildExeStdout("demos/rosetta/45_config_merge/main.sa", "4 3\n");
    try assertBuildExeStdout("demos/rosetta/46_option_default/main.sa", "9\n");
    try assertBuildExeStdout("demos/rosetta/48_generic_pair/main.sa", "11,31\n");
    try assertBuildExeStdout("demos/rosetta/63_router_table/main.sa", "2\n");
}

test "fallible rosetta demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/19_result_question/main.sa", "21\n");
    try assertBuildExeStdout("demos/rosetta/50_error_chain/main.sa", "12\n");
    try assertBuildExeStdout("demos/rosetta/176_result_flattening/main.sa", "2\n");
}

test "slice and cache rosetta demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/44_slice_iteration/main.sa", "10\n");
    try assertBuildExeStdout("demos/rosetta/54_mem_fill/main.sa", "7,7,7,7\n");
    try assertBuildExeStdout("demos/rosetta/86_cache_eviction/main.sa", "20\n");
}

test "baseline rosetta demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/01_hello_world/main.sa", "hello, saasm\n");
    try assertBuildExeStdout("demos/rosetta/04_loop/main.sa", "[0,0,0,0]\n");
    try assertBuildExeStdout("demos/rosetta/07_trait_vtable/main.sa", "77\n");
    try assertBuildExeStdout("demos/rosetta/21_while_loop/main.sa", "15\n");
}

test "break and nested loop rosetta demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/22_break_continue/main.sa", "9\n");
    try assertBuildExeStdout("demos/rosetta/23_nested_loops/main.sa", "18\n");
}

test "more baseline rosetta demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/29_const_data/main.sa", "6\n");
    try assertBuildExeStdout("demos/rosetta/31_trait_static_dispatch/main.sa", "16\n");
    try assertBuildExeStdout("demos/rosetta/37_newtype/main.sa", "42\n");
    try assertBuildExeStdout("demos/rosetta/38_generic_struct_i32/main.sa", "31\n");
    try assertBuildExeStdout("demos/rosetta/39_generic_enum_i32/main.sa", "7\n");
    try assertBuildExeStdout("demos/rosetta/40_impl_block_state/main.sa", "15\n");
}

test "more rosetta demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/08_closures/main.sa", "15\n");
    try assertBuildExeStdout("demos/rosetta/10_generics_monomorph/main.sa", "42\n");
    try assertBuildExeStdout("demos/rosetta/17_associated_fn/main.sa", "42\n");
    try assertBuildExeStdout("demos/rosetta/30_manual_guard_branch/main.sa", "5\n");
    try assertBuildExeStdout("demos/rosetta/33_iterator_map/main.sa", "12\n");
    try assertBuildExeStdout("demos/rosetta/37_newtype/main.sa", "42\n");
    try assertBuildExeStdout("demos/rosetta/38_generic_struct_i32/main.sa", "31\n");
    try assertBuildExeStdout("demos/rosetta/39_generic_enum_i32/main.sa", "7\n");
    try assertBuildExeStdout("demos/rosetta/59_method_counter/main.sa", "4\n");
    try assertBuildExeStdout("demos/rosetta/60_enum_branch/main.sa", "2\n");
}

test "even more rosetta demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/64_file_manifest/main.sa", "3\n");
    try assertBuildExeStdout("demos/rosetta/68_parser_tokens/main.sa", "4\n");
    try assertBuildExeStdout("demos/rosetta/69_serializer/main.sa", "{\"id\":7}\n");
    try assertBuildExeStdout("demos/rosetta/70_integration_service/main.sa", "6\n");
    try assertBuildExeStdout("demos/rosetta/71_pipeline_stage/main.sa", "6\n");
    try assertBuildExeStdout("demos/rosetta/72_graph_walk/main.sa", "3\n");
    try assertBuildExeStdout("demos/rosetta/73_scene_nodes/main.sa", "15\n");
    try assertBuildExeStdout("demos/rosetta/74_component_store/main.sa", "2\n");
    try assertBuildExeStdout("demos/rosetta/77_http_route/main.sa", "/health\n");
    try assertBuildExeStdout("demos/rosetta/78_cli_args/main.sa", "2\n");
}

test "final rosetta batch compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/79_metrics/main.sa", "4\n");
    try assertBuildExeStdout("demos/rosetta/80_workflow/main.sa", "10\n");
    try assertBuildExeStdout("demos/rosetta/81_kv_store/main.sa", "5\n");
    try assertBuildExeStdout("demos/rosetta/82_sql_scan/main.sa", "2\n");
    try assertBuildExeStdout("demos/rosetta/83_blob_chunk/main.sa", "4\n");
    try assertBuildExeStdout("demos/rosetta/84_sync_gate/main.sa", "1\n");
    try assertBuildExeStdout("demos/rosetta/85_scheduler_tree/main.sa", "6\n");
    try assertBuildExeStdout("demos/rosetta/89_job_queue/main.sa", "12\n");
    try assertBuildExeStdout("demos/rosetta/90_app_shell/main.sa", "app --mode demo\n");
    try assertBuildExeStdout("demos/rosetta/91_db_session/main.sa", "2\n");
    try assertBuildExeStdout("demos/rosetta/87_protocol_frame/main.sa", "3\n");
    try assertBuildExeStdout("demos/rosetta/88_text_index/main.sa", "3\n");
    try assertBuildExeStdout("demos/rosetta/92_query_plan/main.sa", "10\n");
    try assertBuildExeStdout("demos/rosetta/93_log_aggregator/main.sa", "10\n");
    try assertBuildExeStdout("demos/rosetta/94_graphql_router/main.sa", "query user\n");
    try assertBuildExeStdout("demos/rosetta/95_repl_shell/main.sa", "sa> \n");
    try assertBuildExeStdout("demos/rosetta/96_task_orchestrator/main.sa", "4\n");
    try assertBuildExeStdout("demos/rosetta/97_sync_service/main.sa", "1\n");
    try assertBuildExeStdout("demos/rosetta/98_build_pipeline/main.sa", "6\n");
    try assertBuildExeStdout("demos/rosetta/99_release_bundle/main.sa", "3\n");
    try assertBuildExeStdout("demos/rosetta/100_full_app/main.sa", "12\n");
    try assertBuildExeStdout("demos/rosetta/178_panic_hook_override/main.sa", "1\n");
}

test "service and concurrency rosetta demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/55_builder_pattern/main.sa", "POST /api\n");
    try assertBuildExeStdout("demos/rosetta/56_state_machine/main.sa", "2\n");
    try assertBuildExeStdout("demos/rosetta/57_event_loop/main.sa", "6\n");
    try assertBuildExeStdout("demos/rosetta/62_channel_pingpong/main.sa", "8\n");
    try assertBuildExeStdout("demos/rosetta/65_job_scheduler/main.sa", "10\n");
    try assertBuildExeStdout("demos/rosetta/66_actor_mailbox/main.sa", "6\n");
    try assertBuildExeStdout("demos/rosetta/75_async_bridge/main.sa", "5\n");
    try assertBuildExeStdout("demos/rosetta/76_lockfree_counter/main.sa", "3\n");
}

test "remaining rosetta demos compile and print through build-exe" {
    try assertBuildExeStdout("demos/rosetta/14_slice_window/main.sa", "5\n");
    try assertBuildExeStdout("demos/rosetta/32_trait_object_vector/main.sa", "12\n");
    try assertBuildExeStdout("demos/rosetta/09_async_await/main.sa", "2\n");
    try assertBuildExeStdout("demos/rosetta/47_tuple_swap/main.sa", "8,3\n");
    try assertBuildExeStdout("demos/rosetta/53_cache_hits/main.sa", "3\n");
    try assertBuildExeStdout("demos/rosetta/43_tagged_union/main.sa", "36\n");
    try assertBuildExeStdout("demos/rosetta/49_pipeline_map/main.sa", "12\n");
    try assertBuildExeStdout("demos/rosetta/94_graphql_router/main.sa", "query user\n");
    try assertBuildExeStdout("demos/rosetta/95_repl_shell/main.sa", "sa> \n");
    try assertBuildExeStdout("demos/rosetta/100_full_app/main.sa", "12\n");
}
