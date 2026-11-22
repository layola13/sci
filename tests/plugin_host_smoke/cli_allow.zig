const std = @import("std");
const builtin = @import("builtin");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const startTimedTest = helpers.startTimedTest;
const endTimedTest = helpers.endTimedTest;
const servoWriteAll = helpers.servoWriteAll;
const writeSource = helpers.writeSource;
const targetArtifactKey = helpers.targetArtifactKey;
const dynLibInstallPath = helpers.dynLibInstallPath;
const jsonStringLiteralAlloc = helpers.jsonStringLiteralAlloc;
const expectInstallCode = helpers.expectInstallCode;
const setEnvVarZ = helpers.setEnvVarZ;
const unsetEnvVarZ = helpers.unsetEnvVarZ;
const saveEnvVarZ = helpers.saveEnvVarZ;
const runBrokerCliCase = helpers.runBrokerCliCase;

test "cli allow flags constrain broker env and fs access" {
    const test_start = startTimedTest("cli allow flags constrain broker env and fs access");
    defer endTimedTest("cli allow flags constrain broker env and fs access", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "broker_cli/src");
    try tmp.dir.createDirPath(std.testing.io, "data");
    try tmp.dir.createDirPath(std.testing.io, "secret");
    try tmp.dir.createDirPath(std.testing.io, "tools");
    try writeSource(tmp.dir, "data/allowed.txt", "payload");
    try writeSource(tmp.dir, "secret/blocked.txt", "blocked");
    const runner_rel = if (builtin.os.tag == .windows) "tools/runner.cmd" else "tools/runner.sh";
    var runner_file = try tmp.dir.createFile(std.testing.io, runner_rel, .{ .truncate = true });
    {
        var wbuf: [8192]u8 = undefined;
        var wfb = runner_file.writer(std.testing.io, &wbuf);
        if (builtin.os.tag == .windows) {
            try wfb.interface.writeAll(
                \\@echo off
                \\<nul set /p runner_output=%1
                \\exit /b 0
                \\
            );
        } else {
            try wfb.interface.writeAll(
                \\#!/bin/sh
                \\printf "%s" "$1"
                \\
            );
        }
        try wfb.interface.flush();
    }
    if (builtin.os.tag != .windows) try runner_file.setPermissions(std.testing.io, @enumFromInt(0o755));
    runner_file.close(std.testing.io);
    const runner_abs = try sio.cwd().realpathAlloc(std.testing.allocator, runner_rel);
    defer std.testing.allocator.free(runner_abs);
    const runner_exec_abs = if (builtin.os.tag == .windows)
        try sio.cwd().realpathAlloc(std.testing.allocator, "C:\\Windows\\System32\\cmd.exe")
    else
        try std.testing.allocator.dupe(u8, runner_abs);
    defer std.testing.allocator.free(runner_exec_abs);

    try writeSource(tmp.dir, "broker_cli/build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const root_module = b.createModule(.{
        \\        .root_source_file = b.path("src/plugin.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    const lib = b.addLibrary(.{
        \\        .name = "broker_cli",
        \\        .root_module = root_module,
        \\        .linkage = .dynamic,
        \\    });
        \\    b.installArtifact(lib);
        \\}
        \\
    );
    try writeSource(tmp.dir, "broker_cli/src/plugin.zig",
        \\const std = @import("std");
        \\
        \\const SkillSection = struct {
        \\    name: []const u8,
        \\    summary: []const u8,
        \\    items: []const []const u8,
        \\};
        \\
        \\const BrokerCallFn = *const fn (ctx: ?*anyopaque, op: u32, req: ?*const anyopaque, resp: ?*anyopaque) callconv(.c) u32;
        \\
        \\const Context = struct {
        \\    allocator: std.mem.Allocator,
        \\    host_version: ?[]const u8 = null,
        \\    log: ?*const fn (ctx: *const anyopaque, level: u8, message_ptr: [*]const u8, message_len: usize) callconv(.c) void = null,
        \\    log_ctx: ?*anyopaque = null,
        \\    json_mode: bool = false,
        \\    broker_abi_version: u32 = 0,
        \\    broker_call: ?BrokerCallFn = null,
        \\    broker_ctx: ?*anyopaque = null,
        \\};
        \\
        \\const HostStream = extern struct {
        \\    ctx: ?*anyopaque,
        \\    write_all: ?*const fn (ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32,
        \\};
        \\
        \\const BrokerEnvGetRequest = extern struct {
        \\    name_ptr: [*]const u8,
        \\    name_len: usize,
        \\    value_ptr: ?[*]u8,
        \\    value_cap: usize,
        \\};
        \\
        \\const BrokerEnvGetResponse = extern struct {
        \\    value_len: usize,
        \\};
        \\
        \\const BrokerFsReadRequest = extern struct {
        \\    path_ptr: [*]const u8,
        \\    path_len: usize,
        \\    value_ptr: ?[*]u8,
        \\    value_cap: usize,
        \\};
        \\
        \\const BrokerFsReadResponse = extern struct {
        \\    value_len: usize,
        \\};
        \\
        \\const BrokerHttpRequest = extern struct {
        \\    method_ptr: [*]const u8,
        \\    method_len: usize,
        \\    url_ptr: [*]const u8,
        \\    url_len: usize,
        \\    body_ptr: ?[*]const u8,
        \\    body_len: usize,
        \\    value_ptr: ?[*]u8,
        \\    value_cap: usize,
        \\};
        \\
        \\const BrokerHttpResponse = extern struct {
        \\    status_code: u16,
        \\    value_len: usize,
        \\};
        \\
        \\const BrokerString = extern struct {
        \\    ptr: [*]const u8,
        \\    len: usize,
        \\};
        \\
        \\const BrokerProcessSpawnRequest = extern struct {
        \\    path_ptr: [*]const u8,
        \\    path_len: usize,
        \\    argv_ptr: ?[*]const BrokerString,
        \\    argv_len: usize,
        \\    stdout_ptr: ?[*]u8,
        \\    stdout_cap: usize,
        \\    stderr_ptr: ?[*]u8,
        \\    stderr_cap: usize,
        \\};
        \\
        \\const BrokerProcessSpawnResponse = extern struct {
        \\    exit_code: u32,
        \\    stdout_len: usize,
        \\    stderr_len: usize,
        \\};
        \\
        \\const PluginDescriptor = extern struct {
        \\    abi_version: u32,
        \\    descriptor_size: u32,
        \\    name: [*:0]const u8,
        \\    init: ?*const fn (ctx: *const Context) callconv(.c) u32,
        \\    prebuild: ?*const fn (ctx: *const Context, compile_options: ?*anyopaque) callconv(.c) u32,
        \\    postbuild: ?*const fn (ctx: *const Context) callconv(.c) u32,
        \\    handle_command: ?*const fn (ctx: *const Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: HostStream, stderr: HostStream, out_code: *u8) callconv(.c) u32,
        \\    skills_ptr: [*]const SkillSection,
        \\    skills_len: usize,
        \\};
        \\
        \\const skills = [_]SkillSection{};
        \\
        \\fn writeAll(stream: HostStream, bytes: []const u8) u32 {
        \\    const write_fn = stream.write_all orelse return 2;
        \\    return write_fn(stream.ctx, bytes.ptr, bytes.len);
        \\}
        \\
        \\fn writeStatus(stream: HostStream, out_code: *u8, status: u32) u32 {
        \\    return switch (status) {
        \\        1 => blk: {
        \\            out_code.* = 41;
        \\            break :blk writeAll(stream, "DENIED\n");
        \\        },
        \\        4 => blk: {
        \\            out_code.* = 42;
        \\            break :blk writeAll(stream, "NOT_FOUND\n");
        \\        },
        \\        5 => blk: {
        \\            out_code.* = 43;
        \\            break :blk writeAll(stream, "BUFFER\n");
        \\        },
        \\        else => 2,
        \\    };
        \\}
        \\
        \\fn brokerEnvGet(ctx: *const Context, name: []const u8, buffer: []u8, out_len: *usize) u32 {
        \\    const broker_call = ctx.broker_call orelse return 2;
        \\    var response = BrokerEnvGetResponse{ .value_len = 0 };
        \\    const request = BrokerEnvGetRequest{
        \\        .name_ptr = name.ptr,
        \\        .name_len = name.len,
        \\        .value_ptr = if (buffer.len == 0) null else buffer.ptr,
        \\        .value_cap = buffer.len,
        \\    };
        \\    const status = broker_call(ctx.broker_ctx, 1, &request, &response);
        \\    out_len.* = response.value_len;
        \\    return status;
        \\}
        \\
        \\fn brokerFsRead(ctx: *const Context, path: []const u8, buffer: []u8, out_len: *usize) u32 {
        \\    const broker_call = ctx.broker_call orelse return 2;
        \\    var response = BrokerFsReadResponse{ .value_len = 0 };
        \\    const request = BrokerFsReadRequest{
        \\        .path_ptr = path.ptr,
        \\        .path_len = path.len,
        \\        .value_ptr = if (buffer.len == 0) null else buffer.ptr,
        \\        .value_cap = buffer.len,
        \\    };
        \\    const status = broker_call(ctx.broker_ctx, 2, &request, &response);
        \\    out_len.* = response.value_len;
        \\    return status;
        \\}
        \\
        \\fn brokerHttpRequest(ctx: *const Context, method: []const u8, url: []const u8, buffer: []u8, out_len: *usize) u32 {
        \\    const broker_call = ctx.broker_call orelse return 2;
        \\    var response = BrokerHttpResponse{
        \\        .status_code = 0,
        \\        .value_len = 0,
        \\    };
        \\    const request = BrokerHttpRequest{
        \\        .method_ptr = method.ptr,
        \\        .method_len = method.len,
        \\        .url_ptr = url.ptr,
        \\        .url_len = url.len,
        \\        .body_ptr = null,
        \\        .body_len = 0,
        \\        .value_ptr = if (buffer.len == 0) null else buffer.ptr,
        \\        .value_cap = buffer.len,
        \\    };
        \\    const status = broker_call(ctx.broker_ctx, 3, &request, &response);
        \\    out_len.* = response.value_len;
        \\    _ = response.status_code;
        \\    return status;
        \\}
        \\
        \\fn brokerProcessSpawn(ctx: *const Context, path: []const u8, args: []const BrokerString, stdout_buffer: []u8, stderr_buffer: []u8, exit_code: *u32, stdout_len: *usize, stderr_len: *usize) u32 {
        \\    const broker_call = ctx.broker_call orelse return 2;
        \\    var response = BrokerProcessSpawnResponse{
        \\        .exit_code = 0,
        \\        .stdout_len = 0,
        \\        .stderr_len = 0,
        \\    };
        \\    const request = BrokerProcessSpawnRequest{
        \\        .path_ptr = path.ptr,
        \\        .path_len = path.len,
        \\        .argv_ptr = if (args.len == 0) null else args.ptr,
        \\        .argv_len = args.len,
        \\        .stdout_ptr = if (stdout_buffer.len == 0) null else stdout_buffer.ptr,
        \\        .stdout_cap = stdout_buffer.len,
        \\        .stderr_ptr = if (stderr_buffer.len == 0) null else stderr_buffer.ptr,
        \\        .stderr_cap = stderr_buffer.len,
        \\    };
        \\    const status = broker_call(ctx.broker_ctx, 4, &request, &response);
        \\    exit_code.* = response.exit_code;
        \\    stdout_len.* = response.stdout_len;
        \\    stderr_len.* = response.stderr_len;
        \\    return status;
        \\}
        \\
        \\fn handle(ctx: *const Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: HostStream, stderr: HostStream, out_code: *u8) callconv(.c) u32 {
        \\    _ = stderr;
        \\    if (argv_len < 2) return 1;
        \\
        \\    const command = std.mem.span(argv[1]);
        \\    var buffer: [512]u8 = undefined;
        \\    var out_len: usize = 0;
        \\
        \\    if (std.mem.eql(u8, command, "broker-env-cli")) {
        \\        if (argv_len < 3) return 1;
        \\        const subject = std.mem.span(argv[2]);
        \\        const status = brokerEnvGet(ctx, subject, buffer[0..], &out_len);
        \\        if (status == 0) {
        \\            out_code.* = 0;
        \\            if (writeAll(stdout, buffer[0..out_len]) != 0) return 2;
        \\            if (writeAll(stdout, "\n") != 0) return 2;
        \\            return 0;
        \\        }
        \\        if (writeStatus(stdout, out_code, status) != 0) return 2;
        \\        return 0;
        \\    }
        \\
        \\    if (std.mem.eql(u8, command, "broker-fs-cli")) {
        \\        if (argv_len < 3) return 1;
        \\        const subject = std.mem.span(argv[2]);
        \\        const status = brokerFsRead(ctx, subject, buffer[0..], &out_len);
        \\        if (status == 0) {
        \\            out_code.* = 0;
        \\            if (writeAll(stdout, buffer[0..out_len]) != 0) return 2;
        \\            if (writeAll(stdout, "\n") != 0) return 2;
        \\            return 0;
        \\        }
        \\        if (writeStatus(stdout, out_code, status) != 0) return 2;
        \\        return 0;
        \\    }
        \\
        \\    if (std.mem.eql(u8, command, "broker-net-cli")) {
        \\        if (argv_len < 4) return 1;
        \\        const method = std.mem.span(argv[2]);
        \\        const url = std.mem.span(argv[3]);
        \\        const status = brokerHttpRequest(ctx, method, url, buffer[0..], &out_len);
        \\        if (status == 0) {
        \\            out_code.* = 0;
        \\            if (writeAll(stdout, buffer[0..out_len]) != 0) return 2;
        \\            if (writeAll(stdout, "\n") != 0) return 2;
        \\            return 0;
        \\        }
        \\        if (writeStatus(stdout, out_code, status) != 0) return 2;
        \\        return 0;
        \\    }
        \\
        \\    if (std.mem.eql(u8, command, "broker-run-cli")) {
        \\        if (argv_len < 3) return 1;
        \\        const path = std.mem.span(argv[2]);
        \\        var arg_records: [8]BrokerString = undefined;
        \\        var child_arg_count: usize = 0;
        \\        var idx: usize = 3;
        \\        while (idx < argv_len) : (idx += 1) {
        \\            const arg = std.mem.span(argv[idx]);
        \\            if (std.mem.startsWith(u8, arg, "--allow-run") or
        \\                std.mem.startsWith(u8, arg, "--permission-set") or
        \\                std.mem.startsWith(u8, arg, "-P"))
        \\            {
        \\                continue;
        \\            }
        \\            if (child_arg_count >= arg_records.len) return 1;
        \\            arg_records[child_arg_count] = .{
        \\                .ptr = arg.ptr,
        \\                .len = arg.len,
        \\            };
        \\            child_arg_count += 1;
        \\        }
        \\
        \\        var stdout_capture: [512]u8 = undefined;
        \\        var stderr_capture: [512]u8 = undefined;
        \\        var exit_code: u32 = 0;
        \\        var stdout_len: usize = 0;
        \\        var stderr_len: usize = 0;
        \\        const status = brokerProcessSpawn(
        \\            ctx,
        \\            path,
        \\            arg_records[0..child_arg_count],
        \\            stdout_capture[0..],
        \\            stderr_capture[0..],
        \\            &exit_code,
        \\            &stdout_len,
        \\            &stderr_len,
        \\        );
        \\        if (status == 0) {
        \\            out_code.* = @as(u8, @truncate(exit_code));
        \\            if (stdout_len != 0 and writeAll(stdout, stdout_capture[0..stdout_len]) != 0) return 2;
        \\            if (stderr_len != 0 and writeAll(stdout, stderr_capture[0..stderr_len]) != 0) return 2;
        \\            if (writeAll(stdout, "\n") != 0) return 2;
        \\            return 0;
        \\        }
        \\        if (writeStatus(stdout, out_code, status) != 0) return 2;
        \\        return 0;
        \\    }
        \\
        \\    return 1;
        \\}
        \\
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = .{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "broker-cli",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = handle,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\
    );
    const broker_cli_artifact = try dynLibInstallPath(std.testing.allocator, "broker_cli");
    defer std.testing.allocator.free(broker_cli_artifact);
    const runner_json = try jsonStringLiteralAlloc(std.testing.allocator, runner_exec_abs);
    defer std.testing.allocator.free(runner_json);
    const runner_permission_args = if (builtin.os.tag == .windows)
        "\"*\", \"*\", \"run-ok\""
    else
        "\"run-ok\"";
    const plugin_manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "broker-cli",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "skills": [],
        \\  "permissions": {{
        \\    "fs": [
        \\      {{ "op": "read", "path": "$PROJECT/data/**" }},
        \\      {{ "op": "read", "path": "$PROJECT/secret/**" }}
        \\    ],
        \\    "net": [
        \\      {{ "url": "http://127.0.0.1:18094/allowed", "methods": ["GET"] }}
        \\    ],
        \\    "env": ["SA_BROKER_*", "HOME"],
        \\    "process": {{
        \\      "spawn": true,
        \\      "exec": [
        \\        {{ "path": {s}, "args": [{s}] }}
        \\      ]
        \\    }}
        \\  }},
        \\  "dependencies": {{}}
        \\}}
        \\
    , .{ targetArtifactKey(), broker_cli_artifact, runner_json, runner_permission_args });
    defer std.testing.allocator.free(plugin_manifest);
    try writeSource(tmp.dir, "broker_cli/sap.json", plugin_manifest);

    const home_name: [:0]const u8 = "SA_PLUGINS_HOME";
    const saved_home = try saveEnvVarZ(std.testing.allocator, home_name);
    defer {
        if (saved_home) |value| {
            setEnvVarZ(home_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(home_name);
        }
    }
    try setEnvVarZ(home_name, "state");

    const dev_name: [:0]const u8 = "SA_PLUGIN_DEV";
    const saved_dev = try saveEnvVarZ(std.testing.allocator, dev_name);
    defer {
        if (saved_dev) |value| {
            setEnvVarZ(dev_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(dev_name);
        }
    }
    try setEnvVarZ(dev_name, "1");

    const broker_env_name: [:0]const u8 = "SA_BROKER_ALLOWED";
    const saved_broker_env = try saveEnvVarZ(std.testing.allocator, broker_env_name);
    defer {
        if (saved_broker_env) |value| {
            setEnvVarZ(broker_env_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(broker_env_name);
        }
    }
    try setEnvVarZ(broker_env_name, "cli-secret");

    var install_output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer install_output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "broker_cli", sio.managedWriter(&install_output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, install_code, install_output.items);

    const sa_mod_source = try std.fmt.allocPrint(std.testing.allocator,
        \\permission_set dev {{
        \\  env [SA_BROKER_*]
        \\  read [$PROJECT/data/**]
        \\  write []
        \\  net [http://127.0.0.1:18094/allowed]
        \\  run [{s}]
        \\}}
        \\
    , .{runner_exec_abs});
    defer std.testing.allocator.free(sa_mod_source);
    try writeSource(tmp.dir, "sa.mod", sa_mod_source);

    const net_address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 18094);
    const net_server = try std.testing.allocator.create(std.Io.net.Server);
    net_server.* = try net_address.listen(sio.io(), .{ .reuse_address = true });
    defer std.testing.allocator.destroy(net_server);

    const net_ready = try std.testing.allocator.create(std.atomic.Value(bool));
    net_ready.* = std.atomic.Value(bool).init(false);
    defer std.testing.allocator.destroy(net_ready);

    const net_thread = try std.Thread.spawn(.{}, struct {
        fn run(listen_server: *std.Io.net.Server, ready: *std.atomic.Value(bool)) void {
            defer listen_server.deinit(sio.io());
            ready.store(true, .release);

            var served: usize = 0;
            while (served < 2) : (served += 1) {
                var stream = listen_server.accept(sio.io()) catch return;
                defer stream.close(sio.io());

                var request_buf: [1024]u8 = undefined;
                const n = std.posix.read(stream.socket.handle, &request_buf) catch return;
                const request = request_buf[0..n];
                const ok = std.mem.containsAtLeast(u8, request, 1, "GET /allowed HTTP/1.1\r\n");
                const status = if (ok) "200 OK" else "404 Not Found";
                const body = if (ok) "net-ok" else "missing";

                var header_buf: [256]u8 = undefined;
                const header = std.fmt.bufPrint(
                    &header_buf,
                    "HTTP/1.1 {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
                    .{ status, body.len },
                ) catch return;
                servoWriteAll(stream, header) catch return;
                servoWriteAll(stream, body) catch return;
            }
        }
    }.run, .{ net_server, net_ready });
    defer {
        var wake_attempts: usize = 0;
        while (wake_attempts < 2) : (wake_attempts += 1) {
            var conn = net_address.connect(sio.io(), .{ .mode = .stream }) catch continue;
            defer conn.close(sio.io());
            servoWriteAll(conn, "GET /shutdown HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n") catch {};
        }
        net_thread.join();
    }
    while (!net_ready.load(.acquire)) std.Io.sleep(sio.io(), .fromMilliseconds(1), .awake) catch {};

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        &.{ "sa", "broker-env-cli", "SA_BROKER_ALLOWED", "--allow-env=SA_BROKER_*" },
        0,
        "cli-secret\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        &.{ "sa", "broker-env-cli", "HOME", "--allow-env=SA_BROKER_*" },
        41,
        "DENIED\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        &.{ "sa", "broker-env-cli", "SA_BROKER_ALLOWED", "-P=dev" },
        0,
        "cli-secret\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        &.{ "sa", "broker-fs-cli", "data/allowed.txt", "--allow-read=$PROJECT/data/**" },
        0,
        "payload\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        &.{ "sa", "broker-fs-cli", "secret/blocked.txt", "--allow-read=$PROJECT/data/**" },
        41,
        "DENIED\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        &.{ "sa", "broker-fs-cli", "data/allowed.txt", "-P=dev" },
        0,
        "payload\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        &.{ "sa", "broker-net-cli", "GET", "http://127.0.0.1:18094/allowed", "--allow-net=http://127.0.0.1:18094/allowed" },
        0,
        "net-ok\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        &.{ "sa", "broker-net-cli", "GET", "http://127.0.0.1:18094/blocked", "--allow-net=http://127.0.0.1:18094/allowed" },
        41,
        "DENIED\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        &.{ "sa", "broker-net-cli", "POST", "http://127.0.0.1:18094/allowed", "--allow-net=http://127.0.0.1:18094/allowed" },
        41,
        "DENIED\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        &.{ "sa", "broker-net-cli", "GET", "http://127.0.0.1:18094/allowed", "-P=dev" },
        0,
        "net-ok\n",
    );

    const allow_run_flag = try std.fmt.allocPrint(std.testing.allocator, "--allow-run={s}", .{runner_exec_abs});
    defer std.testing.allocator.free(allow_run_flag);
    const run_ok_args: []const []const u8 = if (builtin.os.tag == .windows)
        &.{ "sa", "broker-run-cli", runner_exec_abs, "/c", runner_abs, "run-ok", allow_run_flag }
    else
        &.{ "sa", "broker-run-cli", runner_exec_abs, "run-ok", allow_run_flag };
    const run_wrong_args: []const []const u8 = if (builtin.os.tag == .windows)
        &.{ "sa", "broker-run-cli", runner_exec_abs, "/c", runner_abs, "wrong", allow_run_flag }
    else
        &.{ "sa", "broker-run-cli", runner_exec_abs, "wrong", allow_run_flag };
    const run_denied_host_args: []const []const u8 = if (builtin.os.tag == .windows)
        &.{ "sa", "broker-run-cli", runner_exec_abs, "/c", runner_abs, "run-ok", "--allow-run=C:/Windows/System32/not-cmd.exe" }
    else
        &.{ "sa", "broker-run-cli", runner_exec_abs, "run-ok", "--allow-run=/bin/sh" };
    const run_permission_set_args: []const []const u8 = if (builtin.os.tag == .windows)
        &.{ "sa", "broker-run-cli", runner_exec_abs, "/c", runner_abs, "run-ok", "-P=dev" }
    else
        &.{ "sa", "broker-run-cli", runner_exec_abs, "run-ok", "-P=dev" };

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const run_ok = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_ok_args,
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (run_ok != 0) std.debug.print("run_ok stdout={s} stderr={s}\n", .{ stdout_buffer.items, stderr_buffer.items });
    try std.testing.expectEqual(@as(u8, 0), run_ok);
    try std.testing.expectEqualStrings("run-ok\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        run_wrong_args,
        41,
        "DENIED\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        run_denied_host_args,
        41,
        "DENIED\n",
    );

    try runBrokerCliCase(
        &stdout_buffer,
        &stderr_buffer,
        run_permission_set_args,
        0,
        "run-ok\n",
    );
}
