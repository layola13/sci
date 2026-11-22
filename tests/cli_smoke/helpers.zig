const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

pub fn parseJsonValue(allocator: std.mem.Allocator, text: []const u8) !std.json.Parsed(std.json.Value) {
    return try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
}

pub fn jsonObjectGet(parsed: *const std.json.Parsed(std.json.Value), key: []const u8) !std.json.Value {
    const root = switch (parsed.value) {
        .object => |object| object,
        else => return error.TestUnexpectedResult,
    };
    return root.get(key) orelse return error.TestUnexpectedResult;
}

pub fn jsonObjectGetValue(value: std.json.Value, key: []const u8) !std.json.Value {
    const object = switch (value) {
        .object => |object| object,
        else => return error.TestUnexpectedResult,
    };
    return object.get(key) orelse return error.TestUnexpectedResult;
}

pub fn jsonBoolValue(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |v| v,
        else => error.TestUnexpectedResult,
    };
}

pub fn jsonArrayCount(value: std.json.Value) !usize {
    return switch (value) {
        .array => |array| array.items.len,
        else => error.TestUnexpectedResult,
    };
}

pub fn jsonStringValue(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        else => error.TestUnexpectedResult,
    };
}

pub fn writeSource(dir: std.Io.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(std.testing.io, path, .{ .truncate = true });
    defer file.close(std.testing.io);
    var wbuf: [8192]u8 = undefined;
    var w = file.writer(std.testing.io, &wbuf);
    try w.interface.writeAll(source);
    try w.interface.flush();
}

pub fn writeBytes(dir: std.Io.Dir, path: []const u8, bytes: []const u8) !void {
    var file = try dir.createFile(std.testing.io, path, .{ .truncate = true });
    defer file.close(std.testing.io);
    var wbuf: [8192]u8 = undefined;
    var w = file.writer(std.testing.io, &wbuf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}

pub fn containsPortablePath(allocator: std.mem.Allocator, text: []const u8, slash_path: []const u8) !bool {
    const normalized_text = try allocator.dupe(u8, text);
    defer allocator.free(normalized_text);
    for (normalized_text) |*byte| {
        if (byte.* == '\\') byte.* = '/';
    }
    const normalized_path = try allocator.dupe(u8, slash_path);
    defer allocator.free(normalized_path);
    return std.mem.containsAtLeast(u8, normalized_text, 1, normalized_path);
}

pub fn bytesHashHex(bytes: []const u8) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(bytes);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn writeCacheManifest(dir: std.Io.Dir, cache_dir: []const u8, kind: []const u8, key: []const u8, artifact: []const u8, output: []const u8) !void {
    const artifact_hash = bytesHashHex(artifact);
    const output_hash = bytesHashHex(output);
    const manifest = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"version\":1,\"kind\":\"{s}\",\"key\":\"{s}\",\"artifact\":{{\"size\":{d},\"sha256\":\"{s}\"}},\"output\":{{\"size\":{d},\"sha256\":\"{s}\"}}}}\n",
        .{ kind, key, artifact.len, artifact_hash[0..], output.len, output_hash[0..] },
    );
    defer std.testing.allocator.free(manifest);
    const manifest_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/manifest.json", .{cache_dir});
    defer std.testing.allocator.free(manifest_path);
    try writeBytes(dir, manifest_path, manifest);
}

pub fn freeStringMtimeMap(allocator: std.mem.Allocator, map: *std.StringHashMap(i128)) void {
    var iter = map.iterator();
    while (iter.next()) |entry| allocator.free(entry.key_ptr.*);
    map.deinit();
}

pub fn cachedFunctionObjectMtimes(allocator: std.mem.Allocator, dir: std.Io.Dir) !std.StringHashMap(i128) {
    var result = std.StringHashMap(i128).init(allocator);
    errdefer freeStringMtimeMap(allocator, &result);

    var cache_root = try dir.openDir(std.testing.io, ".sa_cache/build-obj-incremental", .{ .iterate = true });
    defer cache_root.close(std.testing.io);
    var cache_iter = cache_root.iterate();
    while (try cache_iter.next(std.testing.io)) |cache_entry| {
        if (cache_entry.kind != .directory) continue;
        var functions_dir = cache_root.openDir(std.testing.io, cache_entry.name, .{ .iterate = true }) catch continue;
        defer functions_dir.close(std.testing.io);
        var object_dir = functions_dir.openDir(std.testing.io, "functions", .{ .iterate = true }) catch continue;
        defer object_dir.close(std.testing.io);

        var object_iter = object_dir.iterate();
        while (try object_iter.next(std.testing.io)) |object_entry| {
            if (object_entry.kind != .file or !std.mem.endsWith(u8, object_entry.name, ".o")) continue;
            const key = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cache_entry.name, object_entry.name });
            errdefer allocator.free(key);
            const stat = try object_dir.statFile(std.testing.io, object_entry.name, .{});
            try result.put(key, @as(i128, stat.mtime.toNanoseconds()));
        }
    }
    return result;
}

pub fn cachedFunctionManifestCount(dir: std.Io.Dir) !usize {
    var count: usize = 0;
    var cache_root = try dir.openDir(std.testing.io, ".sa_cache/build-obj-incremental", .{ .iterate = true });
    defer cache_root.close(std.testing.io);
    var cache_iter = cache_root.iterate();
    while (try cache_iter.next(std.testing.io)) |cache_entry| {
        if (cache_entry.kind != .directory) continue;
        var entry_dir = cache_root.openDir(std.testing.io, cache_entry.name, .{ .iterate = true }) catch continue;
        defer entry_dir.close(std.testing.io);
        const manifest = entry_dir.openFile(std.testing.io, "manifest.json", .{}) catch continue;
        manifest.close(std.testing.io);
        count += 1;
    }
    return count;
}

pub fn singleCacheEntryName(allocator: std.mem.Allocator, dir: std.Io.Dir, rel_path: []const u8) ![]u8 {
    var cache_root = try dir.openDir(std.testing.io, rel_path, .{ .iterate = true });
    defer cache_root.close(std.testing.io);
    var cache_iter = cache_root.iterate();
    var found: ?[]u8 = null;
    errdefer if (found) |name| allocator.free(name);
    while (try cache_iter.next(std.testing.io)) |entry| {
        if (entry.kind != .directory) continue;
        if (found != null) return error.TestUnexpectedResult;
        found = try allocator.dupe(u8, entry.name);
    }
    return found orelse error.FileNotFound;
}

pub fn cacheEntryCount(dir: std.Io.Dir, rel_path: []const u8) !usize {
    var cache_root = try dir.openDir(std.testing.io, rel_path, .{ .iterate = true });
    defer cache_root.close(std.testing.io);
    var cache_iter = cache_root.iterate();
    var count: usize = 0;
    while (try cache_iter.next(std.testing.io)) |entry| {
        if (entry.kind == .directory) count += 1;
    }
    return count;
}

pub fn writeManifestForPackage(
    dir: std.Io.Dir,
    project_root: []const u8,
    package_url: []const u8,
    package_root: []const u8,
    grants_clause: []const u8,
) !void {
    var report = try saasm.pkg.audit.auditPackage(std.testing.allocator, package_url, "HEAD", package_root, &.{});
    defer report.deinit(std.testing.allocator);
    const hash_hex = std.fmt.bytesToHex(report.source_sha256, .lower);
    const manifest_source = try std.fmt.allocPrint(
        std.testing.allocator,
        "require {s} @HEAD sha256:{s}{s}\n",
        .{ package_url, hash_hex[0..], grants_clause },
    );
    defer std.testing.allocator.free(manifest_source);
    const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ project_root, "sa.mod" });
    defer std.testing.allocator.free(manifest_path);
    try writeSource(dir, manifest_path, manifest_source);
}

pub fn writeProjectSum(dir: std.Io.Dir, project_root: []const u8) !void {
    const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ project_root, "sa.mod" });
    defer std.testing.allocator.free(manifest_path);
    const manifest_source = try dir.readFileAlloc(std.testing.io, manifest_path, std.testing.allocator, .limited(16 * 1024 * 1024));
    defer std.testing.allocator.free(manifest_source);
    var project_manifest = try saasm.pkg.manifest.parseManifestWithFile(std.testing.allocator, manifest_source, manifest_path);
    defer project_manifest.deinit(std.testing.allocator);
    const root_abs = try dir.realPathFileAlloc(std.testing.io, project_root, std.testing.allocator);
    defer std.testing.allocator.free(root_abs);
    var update = try saasm.pkg.sum.updateProjectSum(std.testing.allocator, root_abs, project_manifest);
    defer update.deinit(std.testing.allocator);
}

pub fn expectNoTextLlvmArtifacts(dir: std.Io.Dir, out_name: []const u8) !void {
    const ll_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.ll", .{out_name});
    defer std.testing.allocator.free(ll_name);
    const sa_ll_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.sa.ll", .{out_name});
    defer std.testing.allocator.free(sa_ll_name);

    try std.testing.expectError(error.FileNotFound, dir.openFile(std.testing.io, ll_name, .{}));
    try std.testing.expectError(error.FileNotFound, dir.openFile(std.testing.io, sa_ll_name, .{}));
}

pub fn extractLineValue(output: []const u8, prefix: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, output, prefix) orelse return error.NotFound;
    const value_start = start + prefix.len;
    const value_end = std.mem.indexOfScalarPos(u8, output, value_start, '\n') orelse output.len;
    return std.mem.trim(u8, output[value_start..value_end], " \t\r");
}

pub fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    const result = try sio.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code != 0) return error.TestUnexpectedResult;
        },
        else => return error.TestUnexpectedResult,
    }

    return result.stdout;
}

pub fn runCommandAnyExit(allocator: std.mem.Allocator, argv: []const []const u8) !sio.Child.RunResult {
    return try sio.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

pub fn runCommandAnyExitWithEnvMap(allocator: std.mem.Allocator, argv: []const []const u8, env_map: *const sio.EnvMap) !sio.Child.RunResult {
    return try sio.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .env_map = env_map,
    });
}
pub fn llvmDisAvailable() bool {
    // bc2sa invokes llvm-dis to disassemble bitcode; skip the test when the tool is absent.
    const probes = [_][]const u8{ "llvm-dis-14", "llvm-dis" };
    for (probes) |probe| {
        const result = sio.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{ probe, "--version" },
        }) catch continue;
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
        switch (result.term) {
            .exited => |code| if (code == 0) return true,
            else => {},
        }
    }
    return false;
}

pub fn clangAvailable() bool {
    const probes = [_][]const u8{ "clang", "clang.exe" };
    for (probes) |probe| {
        const result = sio.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{ probe, "--version" },
        }) catch continue;
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
        switch (result.term) {
            .exited => |code| if (code == 0) return true,
            else => {},
        }
    }
    return false;
}

pub fn runWasmWithNode(allocator: std.mem.Allocator, wasm_path: []const u8, args: []const []const u8) !sio.Child.RunResult {
    const args_json = try std.json.Stringify.valueAlloc(allocator, args, .{});
    defer allocator.free(args_json);
    const wasm_json = try std.json.Stringify.valueAlloc(allocator, wasm_path, .{});
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
    try writeSource(std.Io.Dir.cwd(), script_path, script);
    return try sio.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", "--no-warnings", script_path },
    });
}

pub fn assertRunStdout(path: []const u8, expected_stdout: []const u8) !void {
    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", path };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    if (run_code != 0 or stderr_buf.items.len != 0 or !std.mem.eql(u8, stdout_buf.items, expected_stdout)) {
        std.debug.print("demo run failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, stdout_buf.items, stderr_buf.items });
    }
    try std.testing.expectEqual(@as(u8, 0), run_code);
    try std.testing.expectEqualStrings(expected_stdout, stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

pub fn assertBuildExeStdout(path: []const u8, expected_stdout: []const u8) !void {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const print_iface = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/io/print.sai");
    defer std.testing.allocator.free(print_iface);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    try tmp.dir.createDirPath(std.testing.io, "bin");

    const demo_dir = std.fs.path.basename(std.fs.path.dirname(path).?);
    const out_path = try std.fmt.allocPrint(std.testing.allocator, "bin/{s}.out", .{demo_dir});
    defer std.testing.allocator.free(out_path);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", out_path, "--no-incremental" };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    if (build_exe_code != 0) {
        std.debug.print("build-exe failed: {s}\n", .{path});
    }
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const exe_path = try std.fmt.allocPrint(std.testing.allocator, "./{s}", .{out_path});
    defer std.testing.allocator.free(exe_path);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{exe_path});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| {
            if (code != 0 or !std.mem.eql(u8, exe_result.stdout, expected_stdout) or exe_result.stderr.len != 0) {
                std.debug.print("native demo failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => |term| {
            std.debug.print("native demo terminated unexpectedly: {s}\nterm: {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, term, exe_result.stdout, exe_result.stderr });
            return error.TestUnexpectedResult;
        },
    }
    try std.testing.expectEqualStrings(expected_stdout, exe_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stderr.len);
}

pub fn assertBuildExeStdoutPureBc(path: []const u8, expected_stdout: []const u8) !void {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const print_iface = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/io/print.sai");
    defer std.testing.allocator.free(print_iface);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    try tmp.dir.createDirPath(std.testing.io, "bin");

    const demo_dir = std.fs.path.basename(std.fs.path.dirname(path).?);
    const out_path = try std.fmt.allocPrint(std.testing.allocator, "bin/{s}.out", .{demo_dir});
    defer std.testing.allocator.free(out_path);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", out_path };
    const build_exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    if (build_exe_code != 0) {
        std.debug.print("build-exe failed: {s}\n", .{path});
    }
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const exe_path = try std.fmt.allocPrint(std.testing.allocator, "./{s}", .{out_path});
    defer std.testing.allocator.free(exe_path);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{exe_path});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .exited => |code| {
            if (code != 0 or !std.mem.eql(u8, exe_result.stdout, expected_stdout) or exe_result.stderr.len != 0) {
                std.debug.print("native demo failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings(expected_stdout, exe_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stderr.len);
}

pub fn assertBuildExeTrap(path: []const u8, out_name: []const u8, expected_trap: []const u8, expected_trap_code: u32, expected_message: []const u8) !void {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", out_name };
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
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, out_name, .{}));
    const bc_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.sa.bc", .{out_name});
    defer std.testing.allocator.free(bc_name);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, bc_name, .{}));
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);

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

pub fn assertCheckTrapWithArgs(path: []const u8, extra: []const []const u8, expected_trap: []const u8, expected_trap_code: u32, expected_message: []const u8) !void {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    var argv = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer argv.deinit();
    try argv.append("sa");
    try argv.append("check");
    try argv.appendSlice(extra);
    try argv.append(source_path);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        argv.items,
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    var trap_buf: [64]u8 = undefined;
    const trap_text = try std.fmt.bufPrint(&trap_buf, "\"trap\":\"{s}\"", .{expected_trap});
    var code_buf: [32]u8 = undefined;
    const code_text = try std.fmt.bufPrint(&code_buf, "\"trap_code\":{d}", .{expected_trap_code});
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, trap_text));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, code_text));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, expected_message));
}

pub fn assertCheckOkWithArgs(path: []const u8, extra: []const []const u8) !void {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    var argv = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer argv.deinit();
    try argv.append("sa");
    try argv.append("check");
    try argv.appendSlice(extra);
    try argv.append(source_path);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        argv.items,
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buffer.items, "check ok") != null);
}

pub fn assertBuildExeLinkFailure(source_name: []const u8, source: []const u8, out_name: []const u8, expected_fragment: []const u8) !void {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, source_name, source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_name, "-o", out_name };
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
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, out_name, .{}));
    try std.testing.expect(std.mem.startsWith(u8, stderr_buffer.items, "error[ExternalCompiler]: zig cc exited with code 1 while linking "));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "  command: zig cc "));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, expected_fragment));
    try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "error: ChildProcessFailed") == null);
}

pub fn assertRunStdoutWithArg(path: []const u8, arg: []const u8, expected_stdout: []const u8) !void {
    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const run_argv = [_][]const u8{ "sa", "run", path, arg };
    const run_code = try saasm.cli.executeWithWriters(std.testing.allocator, run_argv[0..], sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    if (run_code != 0 or stderr_buf.items.len != 0 or !std.mem.eql(u8, stdout_buf.items, expected_stdout)) {
        std.debug.print("demo run failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, stdout_buf.items, stderr_buf.items });
    }
    try std.testing.expectEqual(@as(u8, 0), run_code);
    try std.testing.expectEqualStrings(expected_stdout, stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

pub fn containsImportName(import_names: []const []const u8, expected: []const u8) bool {
    for (import_names) |name| {
        if (std.mem.eql(u8, name, expected)) return true;
    }
    return false;
}

pub fn skipLimits(reader: anytype) !void {
    const flags = try std.leb.readUleb128(u32, reader);
    _ = try std.leb.readUleb128(u32, reader);
    if ((flags & 1) != 0) {
        _ = try std.leb.readUleb128(u32, reader);
    }
}

pub fn wasmImportNames(bytes: []const u8, allocator: std.mem.Allocator) ![]const []const u8 {
    if (bytes.len < 8) return error.InvalidWasm;
    if (!std.mem.eql(u8, bytes[0..4], &std.wasm.magic)) return error.InvalidWasm;
    if (!std.mem.eql(u8, bytes[4..8], &std.wasm.version)) return error.InvalidWasm;

    var names = std.array_list.Managed([]const u8).init(allocator);
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
