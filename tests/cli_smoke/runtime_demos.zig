const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const writeSource = helpers.writeSource;
const expectNoTextLlvmArtifacts = helpers.expectNoTextLlvmArtifacts;
const runCommandAnyExit = helpers.runCommandAnyExit;
const runCommandAnyExitWithEnvMap = helpers.runCommandAnyExitWithEnvMap;
const runWasmWithNode = helpers.runWasmWithNode;
const assertRunStdout = helpers.assertRunStdout;
const assertRunStdoutWithArg = helpers.assertRunStdoutWithArg;

test "struct demo runs through sa run" {
    try assertRunStdout("demos/rosetta/05_struct/main.sa", "(10,20)\n");
}

test "sys runtime demo prints and round-trips file contents" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/sys_runtime_probe.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try assertRunStdoutWithArg(source_path, "marker", "ok\n");

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "sys_runtime_probe.out" };
    const build_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{ "./sys_runtime_probe.out", "marker" });
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| {
            if (code != 0 or !std.mem.eql(u8, exe_result.stdout, "ok\n") or exe_result.stderr.len != 0) {
                std.debug.print("native demo failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("ok\n", exe_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stderr.len);

    const file = try tmp.dir.openFile(std.testing.io, "sys_io.txt", .{});
    defer file.close(std.testing.io);
    const contents = try sio.readToEndAlloc(file, std.testing.allocator, 1024);
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("saasm", contents);

    try tmp.dir.deleteFile(std.testing.io, "sys_io.txt");

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", source_path, "-o", "sys_runtime_probe.wasm", "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm_artifact = try tmp.dir.openFile(std.testing.io, "sys_runtime_probe.wasm.sa.bc", .{});
    defer wasm_artifact.close(std.testing.io);
    const wasm_artifact_bytes = try sio.readToEndAlloc(wasm_artifact, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_artifact_bytes);
    try std.testing.expect(wasm_artifact_bytes.len > 0);
    try expectNoTextLlvmArtifacts(tmp.dir, "sys_runtime_probe.wasm");

    const wasm_file = try tmp.dir.openFile(std.testing.io, "sys_runtime_probe.wasm", .{});
    defer wasm_file.close(std.testing.io);
    const wasm_bytes = try sio.readToEndAlloc(wasm_file, std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);

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

    const wasm_result = try runWasmWithNode(std.testing.allocator, "sys_runtime_probe.wasm", &.{ "sa", "sys_runtime_probe.wasm", "marker" });
    defer std.testing.allocator.free(wasm_result.stdout);
    defer std.testing.allocator.free(wasm_result.stderr);
    switch (wasm_result.term) {
        .exited => |code| {
            if (code != 0 or !std.mem.eql(u8, wasm_result.stdout, "ok\n") or wasm_result.stderr.len != 0) {
                std.debug.print("wasm sys runtime demo failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ wasm_result.stdout, wasm_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("ok\n", wasm_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), wasm_result.stderr.len);

    const wasm_written_file = try tmp.dir.openFile(std.testing.io, "sys_io.txt", .{});
    defer wasm_written_file.close(std.testing.io);
    const wasm_written = try sio.readToEndAlloc(wasm_written_file, std.testing.allocator, 1024);
    defer std.testing.allocator.free(wasm_written);
    try std.testing.expectEqualStrings("saasm", wasm_written);
}

test "ffi airlock demo preserves pointer values through assume_* in sa run" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/support/airlock_probe.sa");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try assertRunStdout(source_path, "ok\n");

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "airlock_probe.out" };
    const build_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./airlock_probe.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| {
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

test "http client saasm demo builds through native exe" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/301_http_client_saasm/main.sa");
    defer std.testing.allocator.free(source_path);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 18090);
    const server = try std.testing.allocator.create(std.Io.net.Server);
    server.* = try address.listen(sio.io(), .{ .reuse_address = true });
    defer std.testing.allocator.destroy(server);

    const body_seen = try std.testing.allocator.create(bool);
    body_seen.* = false;
    defer std.testing.allocator.destroy(body_seen);
    const server_ready = try std.testing.allocator.create(std.atomic.Value(bool));
    server_ready.* = std.atomic.Value(bool).init(false);
    defer std.testing.allocator.destroy(server_ready);

    const server_thread = try std.Thread.spawn(.{}, struct {
        fn run(listen_server: *std.Io.net.Server, seen: *bool, ready: *std.atomic.Value(bool)) void {
            defer listen_server.deinit(sio.io());
            ready.store(true, .release);
            var stream = listen_server.accept(sio.io()) catch return;
            defer stream.close(sio.io());

            var rbuf: [4096]u8 = undefined;
            var wbuf: [4096]u8 = undefined;
            var sreader = stream.reader(sio.io(), &rbuf);
            var swriter = stream.writer(sio.io(), &wbuf);
            var http_server = std.http.Server.init(&sreader.interface, &swriter.interface);
            var request = http_server.receiveHead() catch return;
            var body_tmp: [4096]u8 = undefined;
            var body_reader = request.readerExpectNone(&body_tmp);
            const content = body_reader.interface.allocRemaining(std.testing.allocator, .limited(1024 * 1024)) catch return;
            defer std.testing.allocator.free(content);
            seen.* = std.mem.eql(u8, content, "hello from saasm");
            request.respond(content, .{ .status = .ok }) catch return;
        }
    }.run, .{ server, body_seen, server_ready });
    while (!server_ready.load(.acquire)) std.Io.sleep(sio.io(), .fromMilliseconds(1), .awake) catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "http_client_saasm.out" };
    const build_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_code);

    const exe_result = try runCommandAnyExitWithEnvMap(std.testing.allocator, &[_][]const u8{"./http_client_saasm.out"}, null);
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("http client demo failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("ok\n", exe_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stderr.len);

    server_thread.join();
    try std.testing.expect(body_seen.*);
}

test "http server saasm demo builds through native exe" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/302_http_server_saasm/main.sa");
    defer std.testing.allocator.free(source_path);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", "http_server_saasm.out" };
    const build_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_code);

    const response_seen = try std.testing.allocator.create(bool);
    response_seen.* = false;
    defer std.testing.allocator.destroy(response_seen);

    const server_thread = try std.Thread.spawn(.{}, struct {
        fn run(seen: *bool) void {
            var attempt: usize = 0;
            while (attempt < 50) : (attempt += 1) {
                const dial_addr = std.Io.net.IpAddress.parseIp4("127.0.0.1", 18091) catch return;
                var conn = dial_addr.connect(sio.io(), .{ .mode = .stream }) catch |err| switch (err) {
                    error.ConnectionRefused => {
                        std.Io.sleep(sio.io(), .fromMilliseconds(20), .awake) catch {};
                        continue;
                    },
                    else => return,
                };
                defer conn.close(sio.io());

                var wbuf: [4096]u8 = undefined;
                var w = conn.writer(sio.io(), &wbuf);
                w.interface.writeAll(
                    "GET /stream HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n",
                ) catch return;
                w.interface.flush() catch return;

                var buf: [256]u8 = undefined;
                var response = std.array_list.Managed(u8).init(std.testing.allocator);
                defer response.deinit();
                while (true) {
                    const n = std.posix.read(conn.socket.handle, &buf) catch return;
                    if (n == 0) break;
                    response.appendSlice(buf[0..n]) catch return;
                }
                seen.* = std.mem.containsAtLeast(u8, response.items, 1, "data: first") and
                    std.mem.containsAtLeast(u8, response.items, 1, "data: second");
                return;
            }
        }
    }.run, .{response_seen});
    const exe_result = try runCommandAnyExitWithEnvMap(std.testing.allocator, &[_][]const u8{"./http_server_saasm.out"}, null);
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("http server demo failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("ok\n", exe_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stderr.len);

    server_thread.join();
    try std.testing.expect(response_seen.*);
}

test "panic builtins terminate through the interpreter" {
    const plain_source =
        \\@main() -> i32:
        \\panic(17)
    ;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "panic.sa", plain_source);

    const plain_argv = [_][]const u8{ "sa", "run", "panic.sa" };
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

    try writeSource(tmp.dir, "panic_msg.sa", msg_source);

    const msg_argv = [_][]const u8{ "sa", "run", "panic_msg.sa" };
    const msg_code = try saasm.cli.execute(std.testing.allocator, msg_argv[0..]);
    try std.testing.expectEqual(@as(u8, 151), msg_code);

    const result_layout_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/core/result.sal");
    defer std.testing.allocator.free(result_layout_path);
    const option_layout_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/core/option.sal");
    defer std.testing.allocator.free(option_layout_path);
    const result_src_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/core/result.sa");
    defer std.testing.allocator.free(result_src_path);
    const option_src_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/core/option.sa");
    defer std.testing.allocator.free(option_src_path);
    const panic_src_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/core/panic.sa");
    defer std.testing.allocator.free(panic_src_path);

    const result_unwrap_source = try std.fmt.allocPrint(std.testing.allocator,
        \\@import "{s}"
        \\@import "{s}"
        \\@import "{s}"
        \\
        \\@main() -> i32:
        \\res = alloc Result_SIZE
        \\EXPAND RESULT_SET_ERR res, 7
        \\EXPAND RESULT_UNWRAP value, res
        \\!res
        \\return value
    , .{ result_layout_path, result_src_path, panic_src_path });
    defer std.testing.allocator.free(result_unwrap_source);

    try writeSource(tmp.dir, "result_unwrap.sa", result_unwrap_source);

    const result_unwrap_argv = [_][]const u8{ "sa", "run", "result_unwrap.sa" };
    const result_unwrap_code = try saasm.cli.execute(std.testing.allocator, result_unwrap_argv[0..]);
    try std.testing.expectEqual(@as(u8, 145), result_unwrap_code);

    const option_unwrap_source = try std.fmt.allocPrint(std.testing.allocator,
        \\@import "{s}"
        \\@import "{s}"
        \\@import "{s}"
        \\
        \\@main() -> i32:
        \\opt = alloc Option_SIZE
        \\EXPAND OPTION_SET_NONE opt
        \\EXPAND OPTION_UNWRAP value, opt
        \\!opt
        \\return value
    , .{ option_layout_path, option_src_path, panic_src_path });
    defer std.testing.allocator.free(option_unwrap_source);

    try writeSource(tmp.dir, "option_unwrap.sa", option_unwrap_source);

    const option_unwrap_argv = [_][]const u8{ "sa", "run", "option_unwrap.sa" };
    const option_unwrap_code = try saasm.cli.execute(std.testing.allocator, option_unwrap_argv[0..]);
    try std.testing.expectEqual(@as(u8, 145), option_unwrap_code);

    const result_unwrap_err_source = try std.fmt.allocPrint(std.testing.allocator,
        \\@import "{s}"
        \\@import "{s}"
        \\@import "{s}"
        \\
        \\@main() -> i32:
        \\res = alloc Result_SIZE
        \\EXPAND RESULT_SET_OK res, 7
        \\EXPAND RESULT_UNWRAP_ERR value, res
        \\!res
        \\return value
    , .{ result_layout_path, result_src_path, panic_src_path });
    defer std.testing.allocator.free(result_unwrap_err_source);

    try writeSource(tmp.dir, "result_unwrap_err.sa", result_unwrap_err_source);

    const result_unwrap_err_argv = [_][]const u8{ "sa", "run", "result_unwrap_err.sa" };
    const result_unwrap_err_code = try saasm.cli.execute(std.testing.allocator, result_unwrap_err_argv[0..]);
    try std.testing.expectEqual(@as(u8, 145), result_unwrap_err_code);
}
