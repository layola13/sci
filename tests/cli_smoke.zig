const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) return error.TestUnexpectedResult;
        },
        else => return error.TestUnexpectedResult,
    }

    return result.stdout;
}

fn runCommandAnyExit(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn runWasmWithNode(allocator: std.mem.Allocator, wasm_path: []const u8, args: []const []const u8) !std.process.Child.RunResult {
    const args_json = try std.json.stringifyAlloc(allocator, args, .{});
    defer allocator.free(args_json);
    const wasm_json = try std.json.stringifyAlloc(allocator, wasm_path, .{});
    defer allocator.free(wasm_json);

    const script = try std.fmt.allocPrint(allocator,
        \\const fs = require('node:fs');
        \\const {{ WASI }} = require('node:wasi');
        \\const wasi = new WASI({{
        \\  version: 'preview1',
        \\  args: {s},
        \\  env: {{}},
        \\  preopens: {{ '/': '.' }},
        \\}});
        \\const wasm = fs.readFileSync({s});
        \\WebAssembly.instantiate(wasm, wasi.getImportObject()).then(({{ instance }}) => {{
        \\  process.exitCode = wasi.start(instance);
        \\}}).catch((err) => {{
        \\  console.error(err);
        \\  process.exit(1);
        \\}});
    , .{ args_json, wasm_json });
    defer allocator.free(script);

    const script_path = try std.fs.path.join(allocator, &.{ std.fs.path.dirname(wasm_path) orelse ".", "run_wasm.js" });
    defer allocator.free(script_path);
    try writeSource(std.fs.cwd(), script_path, script);
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", "--no-warnings", script_path },
    });
}

fn assertRunStdout(path: []const u8, expected_stdout: []const u8) !void {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "saasm", "run", path };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    if (run_code != 0 or stderr_buf.items.len != 0 or !std.mem.eql(u8, stdout_buf.items, expected_stdout)) {
        std.debug.print("demo run failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, stdout_buf.items, stderr_buf.items });
    }
    try std.testing.expectEqual(@as(u8, 0), run_code);
    try std.testing.expectEqualStrings(expected_stdout, stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

fn assertRunStdoutWithArg(path: []const u8, arg: []const u8, expected_stdout: []const u8) !void {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "saasm", "run", path, arg };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    if (run_code != 0 or stderr_buf.items.len != 0 or !std.mem.eql(u8, stdout_buf.items, expected_stdout)) {
        std.debug.print("demo run failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, stdout_buf.items, stderr_buf.items });
    }
    try std.testing.expectEqual(@as(u8, 0), run_code);
    try std.testing.expectEqualStrings(expected_stdout, stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

fn containsImportName(import_names: []const []const u8, expected: []const u8) bool {
    for (import_names) |name| {
        if (std.mem.eql(u8, name, expected)) return true;
    }
    return false;
}

fn skipLimits(reader: anytype) !void {
    const flags = try std.leb.readUleb128(u32, reader);
    _ = try std.leb.readUleb128(u32, reader);
    if ((flags & 1) != 0) {
        _ = try std.leb.readUleb128(u32, reader);
    }
}

fn wasmImportNames(bytes: []const u8, allocator: std.mem.Allocator) ![]const []const u8 {
    if (bytes.len < 8) return error.InvalidWasm;
    if (!std.mem.eql(u8, bytes[0..4], &std.wasm.magic)) return error.InvalidWasm;
    if (!std.mem.eql(u8, bytes[4..8], &std.wasm.version)) return error.InvalidWasm;

    var names = std.ArrayList([]const u8).init(allocator);
    errdefer names.deinit();

    var fbs = std.io.fixedBufferStream(bytes[8..]);
    const reader = fbs.reader();
    while (fbs.pos < bytes.len - 8) {
        const section_id = reader.readByte() catch break;
        const section = std.meta.intToEnum(std.wasm.Section, section_id) catch return error.InvalidWasm;
        const section_len = try std.leb.readUleb128(u32, reader);
        const section_end = fbs.pos + @as(usize, @intCast(section_len));
        if (section_end > fbs.buffer.len) return error.InvalidWasm;
        const section_bytes = fbs.buffer[fbs.pos..section_end];
        if (section == .import) {
            var import_fbs = std.io.fixedBufferStream(section_bytes);
            const import_reader = import_fbs.reader();
            const import_count = try std.leb.readUleb128(u32, import_reader);
            var i: u32 = 0;
            while (i < import_count) : (i += 1) {
                const module_len = try std.leb.readUleb128(u32, import_reader);
                const module_end = import_fbs.pos + @as(usize, @intCast(module_len));
                if (module_end > section_bytes.len) return error.InvalidWasm;
                const module_name = section_bytes[import_fbs.pos..module_end];
                import_fbs.pos = module_end;
                const name_len = try std.leb.readUleb128(u32, import_reader);
                const name_end = import_fbs.pos + @as(usize, @intCast(name_len));
                if (name_end > section_bytes.len) return error.InvalidWasm;
                const import_name = section_bytes[import_fbs.pos..name_end];
                import_fbs.pos = name_end;
                _ = module_name;

                const kind_byte = try import_reader.readByte();
                const kind = std.meta.intToEnum(std.wasm.ExternalKind, kind_byte) catch return error.InvalidWasm;
                switch (kind) {
                    .function => {
                        _ = try std.leb.readUleb128(u32, import_reader);
                    },
                    .table => {
                        _ = try import_reader.readByte();
                        try skipLimits(import_reader);
                    },
                    .memory => {
                        try skipLimits(import_reader);
                    },
                    .global => {
                        _ = try import_reader.readByte();
                        _ = try std.leb.readUleb128(u1, import_reader);
                    },
                }
                try names.append(import_name);
            }
        }
        fbs.pos += section_len;
    }
    return try names.toOwnedSlice();
}

test "cli run/build-exe/build-wasm produce real artifacts" {
    const source =
        \\#loc "hello.rs":10:4
        \\@main() -> i32:
        \\node = alloc 8
        \\!node
        \\return 7
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "sample.saasm", source);

    const run_argv = [_][]const u8{ "saasm", "run", "sample.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 7), run_code);

    const exe_path = "sample.out";
    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "sample.saasm", "-o", exe_path, "-g" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe = try tmp.dir.openFile(exe_path, .{});
    defer exe.close();
    const exe_bytes = try exe.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(exe_bytes);
    try std.testing.expect(exe_bytes.len > 0);

    const ll_path = "sample.out.saasm.ll";
    const ll = try tmp.dir.openFile(ll_path, .{});
    defer ll.close();
    const ll_bytes = try ll.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "!llvm.dbg.cu"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "!DILocation(line: 10, column: 4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "!DISubprogram(name: \"main\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "store i32 %argc, ptr @saasm_argc, align 4, !dbg"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "ret i32 %res, !dbg"));

    const obj_path = "sample.o";
    const build_obj_argv = [_][]const u8{ "saasm", "build-obj", "sample.saasm", "-o", obj_path };
    const obj_code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), obj_code);

    const obj = try tmp.dir.openFile(obj_path, .{});
    defer obj.close();
    const obj_bytes = try obj.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(obj_bytes);
    try std.testing.expect(obj_bytes.len > 0);

    const wasm_path = "sample.wasm";
    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", "sample.saasm", "-o", wasm_path, "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm = try tmp.dir.openFile(wasm_path, .{});
    defer wasm.close();
    const wasm_bytes = try wasm.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);
}

test "hello world demo prints through saasm run" {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "saasm", "run", "demos/rosetta/01_hello_world/main.saasm" };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), run_code);
    try std.testing.expectEqualStrings("hello, saasm\n", stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

test "hello world demo prints through build-wasm and node wasi" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const node_probe = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/01_hello_world/main.saasm");
    defer std.testing.allocator.free(source_path);

    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", source_path, "-o", "hello.wasm", "--target", "wasm32" };
    const build_wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "hello.out" };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const native_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{ "./hello.out" });
    defer std.testing.allocator.free(native_result.stdout);
    defer std.testing.allocator.free(native_result.stderr);
    switch (native_result.term) {
        .Exited => |code| {
            if (code != 0 or !std.mem.eql(u8, native_result.stdout, "hello, saasm\n") or native_result.stderr.len != 0) {
                std.debug.print("native hello demo failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ native_result.stdout, native_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("hello, saasm\n", native_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), native_result.stderr.len);

    const node_result = try runWasmWithNode(std.testing.allocator, "hello.wasm", &.{ "saasm", "hello.wasm" });
    defer std.testing.allocator.free(node_result.stdout);
    defer std.testing.allocator.free(node_result.stderr);
    switch (node_result.term) {
        .Exited => |code| {
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

test "hello world upstream line can break in gdb" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const gdb_probe = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "gdb", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(gdb_probe.stdout);
    defer std.testing.allocator.free(gdb_probe.stderr);
    switch (gdb_probe.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
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
    try writeSource(tmp.dir, "hello.saasm", source);
    try writeSource(tmp.dir, "hello.rs", upstream_source);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "hello.saasm", "-o", "hello.out", "-g" };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const gdb_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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
        .Exited => |code| {
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
    const node_probe = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/98_build_pipeline/main.saasm");
    defer std.testing.allocator.free(source_path);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "hello_compute.out" };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const native_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{ "./hello_compute.out" });
    defer std.testing.allocator.free(native_result.stdout);
    defer std.testing.allocator.free(native_result.stderr);
    switch (native_result.term) {
        .Exited => |code| {
            if (code != 0 or !std.mem.eql(u8, native_result.stdout, "6\n") or native_result.stderr.len != 0) {
                std.debug.print("native hello-compute failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ native_result.stdout, native_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("6\n", native_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), native_result.stderr.len);

    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", source_path, "-o", "hello_compute.wasm", "--target", "wasm32" };
    const build_wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

    const node_result = try runWasmWithNode(std.testing.allocator, "hello_compute.wasm", &.{ "saasm", "hello_compute.wasm" });
    defer std.testing.allocator.free(node_result.stdout);
    defer std.testing.allocator.free(node_result.stderr);
    switch (node_result.term) {
        .Exited => |code| {
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

test "trait vtable demo runs through saasm run" {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "saasm", "run", "demos/rosetta/07_trait_vtable/main.saasm" };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], stdout_buf.writer(), stderr_buf.writer());
    try std.testing.expectEqual(@as(u8, 0), run_code);
    try std.testing.expectEqualStrings("77\n", stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

test "comparison alias demos run through saasm run" {
    try assertRunStdout("demos/rosetta/03_if_else/main.saasm", "20\n");
    try assertRunStdout("demos/rosetta/04_loop/main.saasm", "[0,0,0,0]\n");
    try assertRunStdout("demos/rosetta/21_while_loop/main.saasm", "15\n");
    try assertRunStdout("demos/rosetta/22_break_continue/main.saasm", "9\n");
    try assertRunStdout("demos/rosetta/23_nested_loops/main.saasm", "18\n");
    try assertRunStdout("demos/rosetta/24_factorial/main.saasm", "120\n");
    try assertRunStdout("demos/rosetta/25_fibonacci/main.saasm", "21\n");
}

test "struct demo runs through saasm run" {
    try assertRunStdout("demos/rosetta/05_struct/main.saasm", "(10,20)\n");
}

test "sys runtime demo prints and round-trips file contents" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/sys_runtime_probe.saasm");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try assertRunStdoutWithArg(source_path, "marker", "ok\n");

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "sys_runtime_probe.out" };
    const build_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{ "./sys_runtime_probe.out", "marker" });
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| {
            if (code != 0 or !std.mem.eql(u8, exe_result.stdout, "ok\n") or exe_result.stderr.len != 0) {
                std.debug.print("native demo failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("ok\n", exe_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stderr.len);

    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", source_path, "-o", "sys_runtime_probe.wasm", "--target", "wasm32" };
    const build_wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

    const wasm_file = try tmp.dir.openFile("sys_runtime_probe.wasm", .{});
    defer wasm_file.close();
    const wasm_bytes = try wasm_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);
    const import_names = try wasmImportNames(wasm_bytes, std.testing.allocator);
    defer std.testing.allocator.free(import_names);
    try std.testing.expect(containsImportName(import_names, "fd_write"));
    try std.testing.expect(containsImportName(import_names, "proc_exit"));
    try std.testing.expect(containsImportName(import_names, "args_get"));
    try std.testing.expect(containsImportName(import_names, "args_sizes_get"));

    const file = try tmp.dir.openFile("sys_io.txt", .{}); 
    defer file.close();
    const contents = try file.readToEndAlloc(std.testing.allocator, 1024);
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("saasm", contents);
}

test "ffi airlock demo preserves pointer values through assume_* in saasm run" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/airlock_probe.saasm");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try assertRunStdout(source_path, "ok\n");

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "airlock_probe.out" };
    const build_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{ "./airlock_probe.out" });
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| {
            if (code != 0 or !std.mem.eql(u8, exe_result.stdout, "ok\n") or exe_result.stderr.len != 0) {
                std.debug.print("airlock demo failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("ok\n", exe_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stderr.len);
}

test "panic builtins terminate through the interpreter" {
    const plain_source =
        \\@main() -> i32:
        \\panic(17)
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "panic.saasm", plain_source);

    const plain_argv = [_][]const u8{ "saasm", "run", "panic.saasm" };
    const plain_code = try saasm.cli.execute(std.testing.allocator, plain_argv[0..]);
    try std.testing.expectEqual(@as(u8, 145), plain_code);

    const msg_source =
        \\@main() -> i32:
        \\buf = alloc 3
        \\store buf+0, 104 as i8
        \\store buf+1, 105 as i8
        \\store buf+2, 0 as i8
        \\panic_msg(23, *buf, 2)
    ;

    try writeSource(tmp.dir, "panic_msg.saasm", msg_source);

    const msg_argv = [_][]const u8{ "saasm", "run", "panic_msg.saasm" };
    const msg_code = try saasm.cli.execute(std.testing.allocator, msg_argv[0..]);
    try std.testing.expectEqual(@as(u8, 151), msg_code);
}

test "fallible ABI and ? propagation work end to end" {
    const source =
        \\@helper() -> i32!:
        \\return 7
        \\@main() -> i32!:
        \\tmp = call @helper()
        \\value = ? tmp
        \\return value
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "fallible.saasm", source);

    const run_argv = [_][]const u8{ "saasm", "run", "fallible.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), run_code);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "fallible.saasm", "-o", "fallible.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("fallible.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define {i32, i32} @helper()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "call {i32, i32} @helper()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "extractvalue {i32, i32}"));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./fallible.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "const pointer stores survive load and print end to end" {
    const source =
        \\@import "../../../sa_std/io/print.saasm-iface"
        \\@const RESULT_OK = utf8:"OK\n"
        \\#def Box_SIZE = 8
        \\#def Box_ptr = +0
        \\@main() -> i32:
        \\box = alloc Box_SIZE
        \\store box+Box_ptr, &RESULT_OK as ptr
        \\loaded = load box+Box_ptr as ptr
        \\call @sa_print_bytes(&loaded, 3)
        \\!loaded
        \\!box
        \\return 0
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "const_ptr_store.saasm", source);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "const_ptr_store.saasm", "-o", "const_ptr_store.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./const_ptr_store.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("OK\n", exe_result.stdout);
}

test "vtable loads preserve indirect call provenance end to end" {
    const source =
        \\@import "../../../sa_std/io/print.saasm-iface"
        \\@const RESULT_OK = utf8:"OK\n"
        \\@const VTABLE = vtable { run = @slot_run }
        \\#def Obj_SIZE = 16
        \\#def Obj_DATA = +0
        \\#def Obj_VTABLE = +8
        \\#def VTable_run = +0
        \\@slot_run(&self: ptr) -> i32:
        \\L_ENTRY:
        \\    value = load self+Obj_DATA as i32
        \\    return value
        \\@invoke(&obj: ptr) -> i32:
        \\L_ENTRY:
        \\    vt = load obj+Obj_VTABLE as ptr
        \\    fn = load vt+VTable_run as ptr
        \\    value = call_indirect fn(&obj)
        \\    !fn
        \\    !vt
        \\    return value
        \\@main() -> i32:
        \\L_ENTRY:
        \\    obj = alloc Obj_SIZE
        \\    store obj+Obj_DATA, 77 as i32
        \\    store obj+Obj_VTABLE, &VTABLE as ptr
        \\    result = call @invoke(&obj)
        \\    ok = eq result, 77
        \\    !result
        \\    !obj
        \\    br ok -> L_OK, L_ERR
        \\L_OK:
        \\    !ok
        \\    call @sa_print_bytes(&RESULT_OK, 3)
        \\    return 0
        \\L_ERR:
        \\    !ok
        \\    return 1
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "vtable_indirect.saasm", source);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "vtable_indirect.saasm", "-o", "vtable_indirect.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./vtable_indirect.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("OK\n", exe_result.stdout);
}

test "import expansion keeps source paths alive end to end" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/40_impl_block_state/main.saasm");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "impl_block_state.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./impl_block_state.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("15\n", exe_result.stdout);
}

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

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "atomic.saasm", source);

    const run_argv = [_][]const u8{ "saasm", "run", "atomic.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 11), run_code);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "atomic.saasm", "-o", "atomic.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("atomic.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "load atomic i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "store atomic i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "atomicrmw add"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "cmpxchg ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "fence release"));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./atomic.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 11), code),
        else => return error.TestUnexpectedResult,
    }

    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", "atomic.saasm", "-o", "atomic.wasm", "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm_file = try tmp.dir.openFile("atomic.wasm", .{});
    defer wasm_file.close();
    const wasm_bytes = try wasm_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);

    const build_obj_argv = [_][]const u8{ "saasm", "build-obj", "atomic.saasm", "-o", "atomic.o" };
    const obj_code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), obj_code);

    const obj_file = try tmp.dir.openFile("atomic.o", .{});
    defer obj_file.close();
    const obj_bytes = try obj_file.readToEndAlloc(std.testing.allocator, 1 << 20);
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

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "ptr_add.saasm", source);

    const run_argv = [_][]const u8{ "saasm", "run", "ptr_add.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 65), run_code);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "ptr_add.saasm", "-o", "ptr_add.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("ptr_add.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define i32 @saasm_main()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "getelementptr i8, ptr"));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./ptr_add.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 65), code),
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

test "panic lowers to a real runtime call in emitted LLVM and native executables exit with that code" {
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

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "panic_native.saasm", source);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "panic_native.saasm", "-o", "panic_native.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("panic_native.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define void @__sa_panic(i32 %code, ptr %msg, i64 %len)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "@__sa_panic("));
    try std.testing.expect(!std.mem.containsAtLeast(u8, ll_bytes, 1, "unreachable ; panic("));
    try std.testing.expect(!std.mem.containsAtLeast(u8, ll_bytes, 1, "unreachable ; panic_msg("));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./panic_native.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 205), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(std.mem.containsAtLeast(u8, exe_result.stderr, 1, "PANIC[77]: hi"));

    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", "panic_native.saasm", "-o", "panic_native.wasm", "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm = try tmp.dir.openFile("panic_native.wasm", .{});
    defer wasm.close();
    const wasm_bytes = try wasm.readToEndAlloc(std.testing.allocator, 1 << 20);
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

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "contracts.saasm", source);

    const build_obj_argv = [_][]const u8{ "saasm", "build-obj", "contracts.saasm", "-o", "contracts.o" };
    const code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), code);

    const ll_file = try tmp.dir.openFile("contracts.o.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);

    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "declare i32 @ext_add(i32, i32)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define ptr @wrap(ptr %raw)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define i32 @exported()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "L_ENTRY:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define i32 @main(i32 %argc, ptr %argv)"));

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

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "unsupported_sys.saasm", source);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "unsupported_sys.saasm", "-o", "unsupported_sys.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("unsupported_sys.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("unsupported_sys.out.saasm.ll", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"UnsupportedSysIntrinsic\""));
}

test "unknown register demo is rejected with structured trap output" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/unknown_register.saasm");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "unknown_register.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("unknown_register.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("unknown_register.out.saasm.ll", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"UnknownRegister\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1007"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"register\":\"ghost\""));
}

test "memory leak demo is rejected with structured trap output" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/memory_leak.saasm");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "memory_leak.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("memory_leak.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("memory_leak.out.saasm.ll", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"MemoryLeak\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1012"));
}

test "fallthrough demo is rejected without a terminator" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/fallthrough.saasm");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "fallthrough.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("fallthrough.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("fallthrough.out.saasm.ll", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"FallthroughForbidden\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1014"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "function body ended without a terminator"));
}

test "duplicate label demo is rejected with structured trap output" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/duplicate_label.saasm");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "duplicate_label.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("duplicate_label.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("duplicate_label.out.saasm.ll", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"DuplicateLabel\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1003"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "label is already defined"));
}

test "phi conflict demo is rejected on mismatched join states" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/phi_conflict.saasm");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "phi_conflict.out" };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("phi_conflict.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("phi_conflict.out.saasm.ll", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"PhiStateConflict\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap_code\":1015"));
}

test "phi join AND demo runs through the join point" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/phi_join_and.saasm");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "phi_join_and.out" };
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
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const run_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./phi_join_and.out"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .Exited => |exit_code| try std.testing.expectEqual(@as(u8, 0), exit_code),
        else => return error.TestUnexpectedResult,
    }
}

test "v0.1 build-wasm rejects wasm64 target" {
    const source =
        \\@main() -> i32:
        \\return 0
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "wasm64.saasm", source);

    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", "wasm64.saasm", "-o", "wasm64.wasm", "--target", "wasm64" };
    try std.testing.expectError(error.InvalidTarget, saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]));
}

test "layout cli prints text and json outputs" {
    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const text_argv = [_][]const u8{ "saasm", "layout", "--name", "Entity", "--fields", "id:u32, pos_x:f64, pos_y:f64, hp:i32" };
    const text_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        text_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), text_code);
    try std.testing.expectEqualStrings(
        "#def Entity_SIZE  = 32\n#def Entity_id = +0\n// 4 bytes padding\n#def Entity_pos_x = +8\n#def Entity_pos_y = +16\n#def Entity_hp = +24\n// 4 bytes tail padding\n",
        stdout_buffer.items,
    );
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const json_argv = [_][]const u8{ "saasm", "layout", "--name", "Pair", "--fields", "head:ptr, count:u32", "--format", "json", "--target", "32" };
    const json_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        json_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), json_code);
    try std.testing.expectEqualStrings(
        "{\"name\":\"Pair\",\"size\":8,\"fields\":[{\"name\":\"head\",\"offset\":0,\"size\":4,\"ty\":\"ptr\"},{\"name\":\"count\",\"offset\":4,\"size\":4,\"ty\":\"u32\"}]}\n",
        stdout_buffer.items,
    );
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}
